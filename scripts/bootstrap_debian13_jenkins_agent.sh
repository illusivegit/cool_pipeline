#!/usr/bin/env bash
#==============================================================================
# bootstrap_debian13_jenkins_agent.sh
#
# Purpose:
#   Bootstraps a fresh Debian 13 (trixie) VM as a deployment target for the
#   Opentelemetry Observability Lab CI/CD pipeline.
#
# Architecture:
#   The Jenkins agent runs as a Docker container on the CI host (built from
#   jenkins/jenkins-inbound-agent-with-jq-docker-rsync). It SSHs into THIS VM
#   as the 'jenkins' user, rsyncs the repo, and runs Makefile targets to bring
#   up the application stack via docker compose.
#
#   ┌──────────────────────┐  SSH + rsync   ┌──────────────────────────┐
#   │  CI Host             │ ────────────►  │  This VM (deploy target) │
#   │  Jenkins controller  │                │                          │
#   │  Jenkins agent       │  docker ctx    │  jenkins user            │
#   │  (Docker container)  │ ────────────►  │  docker compose up       │
#   └──────────────────────┘                └──────────────────────────┘
#
# What it installs (only what the pipeline needs on this VM):
#   - make               (Makefile targets: make up, make health, make state)
#   - rsync              (receives files from agent: rsync -az --delete)
#   - curl               (health-check scripts)
#   - ca-certificates    (TLS certificate chain verification)
#   - unattended-upgrades (automatic security patches)
#   - apt-listchanges    (companion for unattended-upgrades)
#
# What it configures:
#   - 'jenkins' user: no password, locked, SSH key-only, no sudo
#   - Docker group membership for jenkins (security note below)
#   - SSH authorized_keys scaffold for jenkins
#   - Docker daemon: unix socket only (no TCP), log rotation, live-restore
#   - SSH hardening: no root login, key-only auth for jenkins user
#   - Automatic security updates via unattended-upgrades
#
# What it does NOT install (runs on the CI host agent container, not here):
#   - Java (agent container has its own JRE)
#   - jq (agent container installs it)
#   - git (pipeline uses rsync to sync, not git clone on this VM)
#
# Assumptions:
#   - Running on Debian 13 (trixie) with systemd
#   - Docker Engine + Compose plugin already installed (Docker official repo)
#   - Script is run as root or via sudo
#   - Network connectivity available for apt
#
# How to run:
#   sudo bash scripts/bootstrap_debian13_jenkins_agent.sh
#
# Idempotency:
#   Safe to re-run. Each function checks current state before modifying.
#   No destructive operations on re-run.
#
# Rollback:
#   - Per-change: userdel -r jenkins; apt-get purge <pkg>;
#     rm /etc/ssh/sshd_config.d/50-deploy-target-hardening.conf
#   - Full rollback: virsh snapshot-revert debian13 docker_install --running
#
# Security note — Docker group:
#   Adding a user to the 'docker' group is effectively equivalent to root
#   access because containers can mount the host filesystem. Required here
#   because the jenkins user must run 'docker compose up -d --build'.
#   Mitigations applied:
#     1. Jenkins user has no password (SSH key only)
#     2. Jenkins user has NO sudo access
#     3. Docker daemon listens only on the unix socket (no TCP)
#     4. VM is single-purpose (deployment target)
#   See docs/jenkins-agent-vm.md for full discussion.
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly DEPLOY_USER="jenkins"
readonly DEPLOY_HOME="/home/${DEPLOY_USER}"
readonly APP_DIR="${DEPLOY_HOME}/lab/app"       # Matches Jenkinsfile VM_DIR
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()  { printf '[%s] \033[0;32mINFO\033[0m   %s\n'  "${SCRIPT_NAME}" "$*"; }
log_warn()  { printf '[%s] \033[1;33mWARN\033[0m   %s\n'  "${SCRIPT_NAME}" "$*"; }
log_error() { printf '[%s] \033[0;31mERROR\033[0m  %s\n'  "${SCRIPT_NAME}" "$*" >&2; }
log_step()  { printf '\n[%s] \033[0;34m══════ %s ══════\033[0m\n' "${SCRIPT_NAME}" "$*"; }

# ---------------------------------------------------------------------------
# 1. Preflight checks
# ---------------------------------------------------------------------------
preflight() {
    log_step "Preflight checks"

    # Must be root
    if [[ $(id -u) -ne 0 ]]; then
        log_error "This script must be run as root (or via sudo)."
        exit 1
    fi
    log_info "Running as root: OK"

    # Must be Debian
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found — is this Debian?"
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
        log_error "Expected Debian, got ID=${ID:-unknown}."
        exit 1
    fi
    if [[ "${VERSION_ID:-}" != "13" ]]; then
        log_warn "Expected Debian 13, got VERSION_ID=${VERSION_ID:-unknown} — proceeding."
    fi
    log_info "OS: ${PRETTY_NAME}"

    # Docker Engine must be installed and running
    if ! command -v docker &>/dev/null; then
        log_error "Docker CLI not found. Install Docker Engine first."
        exit 1
    fi
    if ! systemctl is-active --quiet docker; then
        log_error "Docker daemon is not running."
        exit 1
    fi
    log_info "Docker Engine: $(docker version --format '{{.Server.Version}}')"

    # Docker Compose plugin must be available
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose plugin not found."
        exit 1
    fi
    log_info "Docker Compose: $(docker compose version --short)"
}

# ---------------------------------------------------------------------------
# 2. Install required packages
# ---------------------------------------------------------------------------
install_packages() {
    log_step "Installing required packages"

    # Only what runs ON THIS VM during deployment:
    #
    #   make             Makefile targets (make up, make health, make state, ...)
    #
    #   rsync            Receives files from the Jenkins agent container
    #                    (Jenkinsfile: rsync -az --delete ./ jenkins@VM:VM_DIR/)
    #
    #   curl             Health-check scripts (curl -s http://localhost:...)
    #
    #   ca-certificates  TLS certificate chain (Docker Hub pulls, apt https)
    #
    #   unattended-upgrades + apt-listchanges
    #                    Automatic security patching
    #
    # NOT installed (lives in the Jenkins agent container on the CI host):
    #   git, jq, java, openssh-client, docker-cli, docker-compose-plugin

    local -a required_pkgs=(
        make
        rsync
        curl
        ca-certificates
        unattended-upgrades
        apt-listchanges
    )

    log_info "Refreshing apt package cache..."
    apt-get update -qq

    local -a to_install=()
    for pkg in "${required_pkgs[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            log_info "Already installed: ${pkg}"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        log_info "Installing: ${to_install[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            --no-install-recommends "${to_install[@]}"
        log_info "Package installation complete."
    else
        log_info "All required packages already installed."
    fi
}

# ---------------------------------------------------------------------------
# 3. Create dedicated jenkins user
# ---------------------------------------------------------------------------
create_deploy_user() {
    log_step "Creating jenkins user: ${DEPLOY_USER}"

    # Jenkinsfile references:
    #   VM_USER = 'jenkins'
    #   VM_DIR  = '/home/jenkins/lab/app'

    if id "${DEPLOY_USER}" &>/dev/null; then
        log_info "User ${DEPLOY_USER} already exists."
    else
        useradd \
            --create-home \
            --home-dir "${DEPLOY_HOME}" \
            --shell /bin/bash \
            --comment "CI/CD jenkins target — least-privilege, no sudo" \
            "${DEPLOY_USER}"
        log_info "Created user: ${DEPLOY_USER}"
    fi

    # Lock password: no interactive / password-based login
    passwd --lock "${DEPLOY_USER}" >/dev/null 2>&1
    log_info "Password locked for ${DEPLOY_USER} (SSH key-only access)."

    # Prepare .ssh directory with strict permissions
    local ssh_dir="${DEPLOY_HOME}/.ssh"
    local authkeys="${ssh_dir}/authorized_keys"

    install -d -m 0700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${ssh_dir}"

    if [[ ! -f "${authkeys}" ]]; then
        touch "${authkeys}"
        log_info "Created ${authkeys}"
    fi
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "${authkeys}"
    chmod 0600 "${authkeys}"
    log_info "SSH directory permissions: .ssh=700, authorized_keys=600"

    # Create the app deployment directory tree
    # Matches Jenkinsfile: VM_DIR = '/home/jenkins/lab/app'
    install -d -m 0755 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${APP_DIR}"
    log_info "App directory: ${APP_DIR}  (Jenkinsfile VM_DIR)"
}

# ---------------------------------------------------------------------------
# 4. Configure Docker access
# ---------------------------------------------------------------------------
configure_docker() {
    log_step "Configuring Docker access for ${DEPLOY_USER}"

    # ┌─────────────────────────────────────────────────────────────────────┐
    # │  SECURITY: docker group ≈ root                                     │
    # │                                                                     │
    # │  The jenkins user must run:                                         │
    # │    docker compose -p lab down -v                                    │
    # │    docker compose -p lab up -d --build                              │
    # │    docker compose -p lab ps                                         │
    # │    docker info   (via Docker context from the agent)                │
    # │  These all require docker socket access.                            │
    # │                                                                     │
    # │  Additionally, the Jenkins agent creates a Docker context that      │
    # │  connects to this VM via SSH as the jenkins user:                   │
    # │    docker context create vm-lab --docker "host=ssh://jenkins@VM"    │
    # │  When the agent runs 'docker --context vm-lab info', the SSH        │
    # │  session lands as the jenkins user, who must access the socket.     │
    # │                                                                     │
    # │  Alternatives considered:                                           │
    # │   - Rootless Docker: breaks the remote Docker context SSH pattern   │
    # │     (socket path differs, agent can't discover it automatically)    │
    # │   - sudo wrapper: adds friction, breaks 'docker context' commands   │
    # │                                                                     │
    # │  Mitigations applied:                                               │
    # │   1. Jenkins user has no password (SSH key only)                     │
    # │   2. Jenkins user has NO sudo access whatsoever                     │
    # │   3. Docker daemon: unix socket only, no TCP exposure               │
    # │   4. This VM is single-purpose (deployment target)                  │
    # └─────────────────────────────────────────────────────────────────────┘

    if ! getent group docker &>/dev/null; then
        log_error "Docker group does not exist. Is Docker installed correctly?"
        exit 1
    fi

    if id -nG "${DEPLOY_USER}" 2>/dev/null | grep -qw docker; then
        log_info "${DEPLOY_USER} already in docker group."
    else
        usermod -aG docker "${DEPLOY_USER}"
        log_info "Added ${DEPLOY_USER} to docker group."
    fi

    # Verify Docker is NOT listening on TCP
    if ss -lntp 2>/dev/null | grep -qE ':2375|:2376'; then
        log_warn "Docker daemon appears to have a TCP listener — this is insecure!"
        log_warn "Remove any -H tcp:// flags from Docker service configuration."
    else
        log_info "Docker daemon: unix socket only (no TCP listener) — OK"
    fi

    # Create/verify daemon.json with secure, production defaults
    local daemon_json="/etc/docker/daemon.json"
    if [[ ! -f "${daemon_json}" ]]; then
        cat > "${daemon_json}" <<'DAEMON_EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
DAEMON_EOF
        log_info "Created ${daemon_json} with production defaults."
        log_info "  log rotation: 10m x 3 files"
        log_info "  live-restore: enabled (containers survive daemon restart)"
        log_info "  userland-proxy: disabled (use kernel nftables)"
        log_info "Restarting Docker daemon to apply config..."
        systemctl restart docker
        # Wait for daemon to come back
        local retries=0
        while ! docker info &>/dev/null && [[ $retries -lt 10 ]]; do
            sleep 1
            retries=$((retries + 1))
        done
        if docker info &>/dev/null; then
            log_info "Docker daemon restarted successfully."
        else
            log_error "Docker daemon failed to restart after config change."
            log_error "Check: journalctl -u docker --no-pager -n 20"
            exit 1
        fi
    else
        log_info "${daemon_json} already exists — not overwriting."
    fi
}

# ---------------------------------------------------------------------------
# 5. SSH hardening (conservative — will not lock out existing users)
# ---------------------------------------------------------------------------
harden_ssh() {
    log_step "SSH hardening (conservative)"

    local drop_in_dir="/etc/ssh/sshd_config.d"
    local drop_in="${drop_in_dir}/50-deploy-target-hardening.conf"

    # Use a drop-in file so the main sshd_config stays untouched.
    # This is easy to review and roll back (just delete the file).
    mkdir -p "${drop_in_dir}"

    if [[ -f "${drop_in}" ]]; then
        log_info "SSH hardening drop-in already exists: ${drop_in}"
        return
    fi

    cat > "${drop_in}" <<'SSHD_EOF'
# Deployment target VM — SSH hardening drop-in
# Installed by: bootstrap_debian13_jenkins_agent.sh
# Rollback:     rm /etc/ssh/sshd_config.d/50-deploy-target-hardening.conf && systemctl reload ssh

# Disable root SSH login (use 'debian' user + sudo instead)
PermitRootLogin no

# Restrict the jenkins user to key-based auth only
Match User jenkins
    PasswordAuthentication no
    AuthenticationMethods publickey
    AllowAgentForwarding yes
    X11Forwarding no
SSHD_EOF

    log_info "Created SSH hardening drop-in: ${drop_in}"

    # Validate the config before reloading — never lock anyone out
    if sshd -t 2>/dev/null; then
        systemctl reload ssh
        log_info "sshd reloaded with hardened config."
    else
        log_error "sshd config validation FAILED — removing drop-in to prevent lockout."
        rm -f "${drop_in}"
        log_error "SSH hardening aborted. Investigate manually."
        # Non-fatal: don't exit, just warn
    fi
}

# ---------------------------------------------------------------------------
# 6. Automatic security updates
# ---------------------------------------------------------------------------
configure_auto_updates() {
    log_step "Configuring automatic security updates"

    local auto_conf="/etc/apt/apt.conf.d/20auto-upgrades"
    if [[ -f "${auto_conf}" ]]; then
        log_info "Auto-upgrades config already exists: ${auto_conf}"
    else
        cat > "${auto_conf}" <<'APT_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT_EOF
        log_info "Enabled daily automatic security updates."
    fi
}

# ---------------------------------------------------------------------------
# 7. Verification
# ---------------------------------------------------------------------------
verify_setup() {
    log_step "Verification"

    log_info "Installed tool versions:"
    printf '  %-20s %s\n' "docker:"         "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'ERROR')"
    printf '  %-20s %s\n' "docker compose:" "$(docker compose version --short 2>/dev/null || echo 'ERROR')"
    printf '  %-20s %s\n' "make:"           "$(make --version 2>/dev/null | head -1 | awk '{print $NF}')"
    printf '  %-20s %s\n' "rsync:"          "$(rsync --version 2>/dev/null | head -1 | awk '/version/{print $3}')"
    printf '  %-20s %s\n' "curl:"           "$(curl --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'ERROR')"

    echo ""
    log_info "Jenkins user verification:"
    if id "${DEPLOY_USER}" &>/dev/null; then
        printf '  %-20s %s\n' "user exists:"     "yes"
        printf '  %-20s %s\n' "uid/gid:"         "$(id "${DEPLOY_USER}" 2>/dev/null)"
        printf '  %-20s %s\n' "docker group:"    "$(id -nG "${DEPLOY_USER}" | grep -qw docker && echo 'member' || echo 'NOT member')"
        printf '  %-20s %s\n' "password status:" "$(passwd -S "${DEPLOY_USER}" 2>/dev/null | awk '{print $2}')"
        printf '  %-20s %s\n' "home:"            "${DEPLOY_HOME}"
        printf '  %-20s %s\n' "app dir:"         "$(stat -c '%a %U:%G' "${APP_DIR}" 2>/dev/null || echo 'MISSING')"
        printf '  %-20s %s\n' "authorized_keys:" "$(stat -c '%a %U:%G' "${DEPLOY_HOME}/.ssh/authorized_keys" 2>/dev/null || echo 'MISSING')"
    else
        log_error "User ${DEPLOY_USER} does not exist!"
    fi

    echo ""
    log_info "Docker daemon status:"
    if docker info &>/dev/null; then
        printf '  %-20s %s\n' "status:"    "running"
        printf '  %-20s %s\n' "socket:"    "/var/run/docker.sock"
        local tcp_count
        tcp_count=$(ss -lntp 2>/dev/null | grep -cE ':2375|:2376' || true)
        printf '  %-20s %s\n' "TCP listen:" "${tcp_count:-0} (should be 0)"
    else
        log_warn "Docker daemon not responding."
    fi

    # Test docker access as jenkins user
    echo ""
    log_info "Docker access test as ${DEPLOY_USER}:"
    if su -s /bin/bash -c 'docker ps --format "table {{.Names}}"' "${DEPLOY_USER}" &>/dev/null; then
        printf '  %-20s %s\n' "docker ps:"       "OK"
    else
        log_warn "docker ps as ${DEPLOY_USER}: FAILED"
        log_warn "This is expected on first run — group membership takes effect on next login."
    fi

    if su -s /bin/bash -c 'docker compose version' "${DEPLOY_USER}" &>/dev/null; then
        printf '  %-20s %s\n' "docker compose:"  "OK"
    else
        log_warn "docker compose as ${DEPLOY_USER}: FAILED"
    fi

    echo ""
    log_info "Network listeners:"
    ss -lntp 2>/dev/null | head -20

    echo ""
    log_step "Bootstrap complete"
    echo ""
    log_info "NEXT STEPS:"
    echo ""
    echo "  1. Add the Jenkins agent's SSH public key so it can connect as '${DEPLOY_USER}':"
    echo ""
    echo "     echo 'ssh-ed25519 AAAA... jenkins-agent' \\"
    echo "       | sudo tee -a ${DEPLOY_HOME}/.ssh/authorized_keys"
    echo "     sudo chown ${DEPLOY_USER}:${DEPLOY_USER} ${DEPLOY_HOME}/.ssh/authorized_keys"
    echo ""
    echo "  2. Update the Jenkinsfile VM_IP if this VM's IP differs:"
    echo "     Current VM IP: $(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "     Jenkinsfile:   VM_IP = '192.168.122.230'"
    echo ""
    echo "  3. Verify the agent container can reach this VM:"
    echo "     ssh -i <key> ${DEPLOY_USER}@$(hostname -I 2>/dev/null | awk '{print $1}') 'docker info'"
    echo ""
    echo "  4. Recommended firewall rules (not enforced to avoid"
    echo "     breaking libvirt networking):"
    echo ""
    echo "     Allow inbound:  TCP 22    (SSH from Jenkins agent)"
    echo "     Allow inbound:  TCP 3000  (Grafana, if accessed externally)"
    echo "     Allow inbound:  TCP 5000  (Flask backend)"
    echo "     Allow inbound:  TCP 8080  (Frontend / Nginx)"
    echo "     Allow inbound:  TCP 9090  (Prometheus)"
    echo "     Deny:           everything else from untrusted networks"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "================================================================"
    echo "  Deploy Target VM Bootstrap — Debian 13 (trixie)"
    echo "  Opentelemetry Observability Lab"
    echo "  $(date -Iseconds)"
    echo "================================================================"
    echo ""

    preflight
    install_packages
    create_deploy_user
    configure_docker
    harden_ssh
    configure_auto_updates
    verify_setup
}

main "$@"
