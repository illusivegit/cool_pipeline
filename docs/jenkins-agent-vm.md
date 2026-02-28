# Deploy Target VM Bootstrap — Debian 13

Provisions a fresh Debian 13 (trixie) KVM/QEMU VM as the **deployment target** for
the Opentelemetry Observability Lab CI/CD pipeline.

## Architecture

```
┌──────────────────────────┐  SSH + rsync   ┌───────────────────────────────┐
│  CI Host (your machine)  │ ─────────────► │  This VM (deploy target)      │
│                          │                │                               │
│  Jenkins controller      │  docker ctx    │  User: deploy                 │
│  (container)             │ ─────────────► │  Docker Engine + Compose      │
│                          │                │  Runs: start-lab.sh           │
│  Jenkins agent           │  curl (smoke)  │  Hosts: all app containers    │
│  (container, docker-     │ ◄───────────── │  (Flask, Grafana, Prometheus, │
│   agent1 label)          │                │   Tempo, Loki, OTel, Nginx)   │
└──────────────────────────┘                └───────────────────────────────┘
```

The Jenkins agent does **not** run on this VM. It runs as a Docker container on
the CI host, built from `jenkins/jenkins-inbound-agent-with-jq-docker-rsync`.
The agent SSHs into this VM as `deploy`, rsyncs the repository, and executes
`start-lab.sh` to bring up the application stack.

## Prerequisites

| Requirement | Notes |
|---|---|
| Debian 13 (trixie) | Tested on `6.12.x` kernel |
| Docker Engine | Installed via [Docker's official Debian guide](https://docs.docker.com/engine/install/debian/) |
| Docker Compose plugin | Installed alongside Docker Engine |
| Root / sudo access | Script must run as root |
| Network connectivity | For `apt-get` package installation |

## Quick Start

```bash
# From the repository root on the VM (or via SSH):
sudo bash scripts/bootstrap_debian13_jenkins_agent.sh
```

The script is **idempotent** — safe to re-run without side effects.

## What the Script Does

### 1. Installs Required Packages

Only what actually runs on the deployment VM during pipeline execution:

| Package | Why |
|---|---|
| `rsync` | Receives files from agent: `rsync -az --delete` |
| `curl` | `start-lab.sh` health checks: `curl -s http://localhost:...` |
| `ca-certificates` | TLS certificate chain (Docker Hub image pulls) |
| `unattended-upgrades` | Automatic security patch installation |

**Not installed** (these live inside the Jenkins agent container on the CI host):
`git`, `jq`, `java`, `openssh-client`, `docker-cli`, `docker-compose-plugin`

### 2. Creates `deploy` User

Matches the Jenkinsfile's `VM_USER = 'deploy'`:

- Home directory: `/home/deploy`
- App directory: `/home/deploy/lab/app` (matches `VM_DIR`)
- Password: **locked** (no interactive login)
- Sudo: **none** (zero sudo privileges)
- Shell: `/bin/bash` (required for SSH command execution)
- SSH: key-only authentication enforced via sshd drop-in

### 3. Configures Docker Access

The `deploy` user is added to the `docker` group so the pipeline can:
- Run `docker compose -p lab up -d --build` (via `start-lab.sh`)
- Respond to `docker --context vm-lab info` from the remote agent

### 4. Hardens SSH

Adds a drop-in config at `/etc/ssh/sshd_config.d/50-deploy-target-hardening.conf`:

- Disables root SSH login
- Forces key-only auth for `deploy`
- Allows agent forwarding for `deploy` (needed for Docker context SSH)
- Disables X11 forwarding for `deploy`

The `debian` user is **not affected** — password + key auth remain available.

### 5. Configures Docker Daemon

Creates `/etc/docker/daemon.json` if absent:

- Log rotation: 10 MB x 3 files (prevents disk fill)
- Live restore: containers survive daemon restarts
- Userland proxy disabled: uses kernel nftables instead
- **No TCP listener** — unix socket only

### 6. Enables Automatic Security Updates

Configures `unattended-upgrades` for daily security patching.

## Post-Bootstrap Steps

### 1. Install the Jenkins Agent's SSH Public Key

The Jenkins agent container SSHs into this VM as `deploy`. Add the key it uses
(configured as credential `vm-ssh` in Jenkins):

```bash
echo 'ssh-ed25519 AAAA... jenkins-agent' \
  | sudo tee -a /home/deploy/.ssh/authorized_keys
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
```

### 2. Verify Connectivity from the Agent

From the CI host (or from inside the agent container):

```bash
ssh -i <key> deploy@<VM_IP> 'docker info'
```

### 3. Update Jenkinsfile VM_IP if Needed

The Jenkinsfile currently references `VM_IP = '192.168.122.250'`. If this VM
has a different IP, update the Jenkinsfile accordingly.

## Security Considerations

### Docker Group = Effective Root

Adding a user to the `docker` group grants the ability to:

- Mount any host directory into a container
- Run privileged containers
- Access the Docker daemon as root

**Mitigations applied:**

1. `deploy` has no password (SSH key only)
2. `deploy` has zero sudo access
3. Docker daemon listens on unix socket only (no TCP/2375/2376)
4. VM is single-purpose (deployment target)
5. SSH hardening restricts the deploy user's session capabilities

**If stronger isolation is required**, consider:

- Rootless Docker (breaks the `docker context` SSH pattern this pipeline uses)
- Kata Containers or gVisor for workload sandboxing
- Dedicated CI container runtime (Podman with `--userns=keep-id`)

### Recommended Firewall Rules

Not enforced by the script to avoid breaking libvirt/KVM networking:

| Direction | Port | Protocol | Purpose |
|---|---|---|---|
| Inbound | 22 | TCP | SSH (Jenkins agent + admin) |
| Inbound | 3000 | TCP | Grafana (if accessed externally) |
| Inbound | 5000 | TCP | Flask backend |
| Inbound | 8080 | TCP | Frontend (Nginx) |
| Inbound | 9090 | TCP | Prometheus |
| Outbound | * | * | Unrestricted (apt, Docker Hub, etc.) |
| Inbound | * | * | Deny all other |

## Rollback

### Partial Rollback

```bash
# Remove deploy user
sudo userdel -r deploy

# Remove SSH hardening
sudo rm /etc/ssh/sshd_config.d/50-deploy-target-hardening.conf
sudo systemctl reload ssh

# Remove Docker daemon config
sudo rm /etc/docker/daemon.json
sudo systemctl restart docker

# Remove packages (if desired)
sudo apt-get purge -y rsync unattended-upgrades
```

### Full VM Rollback (virsh snapshot)

```bash
virsh -c qemu:///system shutdown debian13
# Wait for shutdown, then:
virsh -c qemu:///system snapshot-revert debian13 docker_install --running
ssh -i ~/.ssh/id_ed25519_fedora debian@192.168.122.230
```

## Jenkinsfile Pipeline Flow on This VM

| Stage | What the agent does | What happens on this VM |
|---|---|---|
| Sanity on agent | `ssh`, `docker --version` | Nothing (runs on agent) |
| Ensure remote Docker context | `docker context create vm-lab --docker "host=ssh://deploy@VM"` | SSH session opened, `docker info` runs as `deploy` |
| Sync repo to VM | `rsync -az --delete ./ deploy@VM:/home/deploy/lab/app/` | rsync daemon receives files into `/home/deploy/lab/app` |
| Debug: verify compose paths | `ssh deploy@VM "ls -la /home/deploy/lab/app"` | Lists files |
| Compose up (remote via SSH) | `ssh deploy@VM "cd /home/deploy/lab/app && ./start-lab.sh"` | `deploy` runs `docker compose -p lab up -d --build` |
| Smoke tests | `curl -sf http://VM:8080`, `:3000`, `:9090` | App containers respond |
