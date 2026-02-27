# CI/CD Pipeline Architecture

## Overview

This document describes the Jenkins-based CI/CD pipeline for the OpenTelemetry Observability Lab. The pipeline automates deployment of the containerized observability stack to a remote VM using SSH-based deployment with rsync for file synchronization.

## Quick Start

For first-time setup of the Jenkins infrastructure:

### 1. Build Custom Agent Image

The custom Jenkins agent includes jq, Docker CLI, docker-compose plugin, rsync, and SSH client:

```bash
# From project root
docker build -t jenkins-inbound-agent-with-jq-docker-rsync \
  -f jenkins/jenkins-inbound-agent-with-jq-docker-rsync .
```

**See:** [jenkins/jenkins-inbound-agent-with-jq-docker-rsync](../../../jenkins/jenkins-inbound-agent-with-jq-docker-rsync)

### 2. Deploy Jenkins Controller + Agent

Run the deployment script to create the Jenkins network and start both controller and agent:

```bash
# From project root
bash jenkins/jenkins_setup
```

This script:
- Creates `jenkins-net` Docker bridge network
- Starts Jenkins controller (ports 8080, 50000)
- Starts Jenkins agent connected to controller

**See:** [jenkins/jenkins_setup](../../../jenkins/jenkins_setup)

### 3. Install Required Plugins

Access Jenkins UI at `http://localhost:8080` and install:

**Required Plugins:**
- **SSH Agent Plugin** - For `sshagent(credentials: ['vm-ssh'])` step
- **Docker Pipeline** - For Docker operations in pipeline
- **Docker Plugin** - For agent connectivity

**Pre-installed Plugins:**
- Pipeline Plugin (native)
- Timestamper Plugin (native)
- Credentials Plugin (native)

**See:** [jenkins/jenkins_plugins.md](../../../jenkins/jenkins_plugins.md) for complete list

### 4. Configure SSH Credentials

Add the VM SSH key to Jenkins credentials store:
- Navigate to: Manage Jenkins → Credentials → System → Global credentials
- Add Credentials → Kind: SSH Username with private key
- ID: `vm-ssh`
- Username: `deploy`
- Private Key: Enter directly or from file

### 5. Create Pipeline Job

- New Item → Pipeline
- Pipeline → Definition: Pipeline script from SCM
- SCM: Git → Repository URL: `<your-repo-url>`
- Script Path: `Jenkinsfile`

For complete pipeline architecture and configuration details, continue reading this document below.

---

## Jenkins Control Plane Architecture

The Jenkins deployment uses a containerized setup with inbound Docker agents:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      JENKINS CONTROL PLANE                              │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                  Docker Network: jenkins-net                      │  │
│  │  (User-defined bridge for service discovery & stable DNS)         │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Jenkins Controller (jenkins/jenkins:lts-jdk17)                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │  Persistent Storage: jenkins_home volume                   │  │   │
│  │  │  • Job definitions (XML configs)                           │  │   │
│  │  │  • Build history & artifacts                               │  │   │
│  │  │  • Installed plugins                                       │  │   │
│  │  │  • Credentials (encrypted)                                 │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                  │   │
│  │  Exposed Ports:                                                  │   │
│  │  • 8080: HTTP UI/API                                             │   │
│  │  • 50000: JNLP inbound agent connection                          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Inbound Docker Agent (custom image with jq, docker, rsync)      │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │  Runtime Configuration:                                    │  │   │
│  │  │  • Connects via JNLP to controller:50000                   │  │   │
│  │  │  • Authenticates with static agent secret                  │  │   │
│  │  │  • Executes pipeline stages in isolated workspace          │  │   │
│  │  │  • Mounted Docker socket for DinD operations               │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Pipeline Flow (Jenkinsfile)

The pipeline is defined in the root `Jenkinsfile` and executes on the `docker-agent1` label:

```groovy
pipeline {
  agent { label 'docker-agent1' }
  options { timestamps() }

  environment {
    VM_USER    = 'deploy'
    VM_IP      = '192.168.122.250'      // Target VM for deployment
    DOCKER_CTX = 'vm-lab'                // Remote Docker context
    PROJECT    = 'lab'                   // Docker Compose project name
    VM_DIR     = '/home/deploy/lab/app' // Deployment directory on VM
  }

  stages {
    stage('Sanity on agent') {
      // Verify SSH, Docker, Docker Compose availability on agent
    }

    stage('Ensure remote Docker context') {
      // Create SSH-based Docker context pointing to VM
      // Enables: docker --context vm-lab commands for verification
    }

    stage('Sync repo to VM') {
      // rsync entire repository to VM (bind mounts require local files)
      // Ensures docker-compose.yml and all configs are present
    }

    stage('Debug: verify compose paths') {
      // Validate file structure on VM before deployment
    }

    stage('Compose up (remote via SSH)') {
      steps {
        sshagent(credentials: ['vm-ssh']) {
          sh '''
            set -eu
            export DOCKER_BUILDKIT=1
            ssh ${VM_USER}@${VM_IP} "
              cd ${VM_DIR} && \
              PROJECT=${PROJECT} LAB_HOST=${VM_IP} ./start-lab.sh
            "
          '''
        }
      }
    }

    stage('Smoke tests') {
      // Verify service health:
      //   - Frontend: http://192.168.122.250:8080
      //   - Grafana: http://192.168.122.250:3000/login
      //   - Prometheus: http://192.168.122.250:9090/-/ready
    }
  }

  post {
    failure {
      // Log hint for troubleshooting remote container logs
    }
  }
}
```

## Pipeline Stages Details

### 1. Sanity on agent
Validates the Docker agent has required tools:
- `ssh` (for remote command execution)
- `docker` (for context creation and verification)
- `docker compose` (for deployment validation)

### 2. Ensure remote Docker context
Creates an SSH-based Docker context if it doesn't exist:
```bash
docker context create vm-lab --docker "host=ssh://deploy@192.168.122.250"
```
This allows the agent to run `docker --context vm-lab` commands for verification purposes.

### 3. Sync repo to VM
Uses `rsync` to synchronize the entire repository to the VM:
```bash
rsync -az --delete ./ deploy@192.168.122.250:/home/deploy/lab/app/
```
This is required because Docker Compose bind mounts need files to exist on the VM's filesystem.

### 4. Debug: verify compose paths
Lists files on both local workspace and remote VM to validate synchronization succeeded.

### 5. Compose up (remote via SSH)
Executes the `start-lab.sh` script on the remote VM via SSH:
- Sets `DOCKER_BUILDKIT=1` for optimized builds
- Passes `PROJECT` and `LAB_HOST` environment variables
- Script handles Docker Compose orchestration and health checks

### 6. Smoke tests
Validates deployed services are responding:
- Frontend: HTTP 200 on port 8080
- Grafana: Login page accessible on port 3000
- Prometheus: Ready endpoint on port 9090

## Key Design Decisions

### SSH-Based Deployment (Not Docker Context API)

**Why:** The target VM does not expose its Docker daemon over the network for security reasons.

**How:** Uses Jenkins `sshagent` credential binding with SSH keys, and `rsync` for file synchronization.

**Benefit:** Works with standard SSH hardening practices without requiring Docker daemon exposure (no port 2375).

### Remote File Sync (rsync)

**Why:** Docker Compose bind mounts require files to exist on the VM's filesystem.

**Example:** Configuration files like `frontend/default.conf` are mounted into the Nginx container and must be present on the VM.

**Implementation:** `rsync -az --delete` ensures complete synchronization with cleanup of removed files.

### Docker Context for Verification

**Creation:** `docker context create vm-lab --docker "host=ssh://deploy@192.168.122.250"`

**Use Case:** Allows `docker --context vm-lab ps` from Jenkins agent for verification and troubleshooting.

**Note:** Currently used for verification only. Actual deployment happens via SSH commands to maintain consistency with manual operations.

### Healthcheck-Based Orchestration

**Backend healthcheck:** Python-based `/metrics` endpoint validation in docker-compose.yml.

**Frontend dependency:** `depends_on: backend (service_healthy)` ensures proper startup order.

**Result:** Eliminates race conditions where Nginx starts before backend DNS resolves.

### Single Deployment Script (start-lab.sh)

**Why:** Maintains parity between local development runs and pipeline deployments.

**Overrides:** Jenkins passes `PROJECT` and `LAB_HOST` environment variables:
- `PROJECT=lab` ensures consistent container naming
- `LAB_HOST=192.168.122.250` prints correct access URLs

**Features:**
- Validates Docker and Docker Compose availability
- Exports `DOCKER_BUILDKIT=1` for optimized builds
- Runs health checks on all services after startup
- Displays service access URLs

### SSH Security Hardening

**Implementation:** ED25519 key-based authentication with password authentication disabled.

**Why ED25519:** Smaller keys (256-bit), faster cryptographic operations, modern security standard.

**Setup Process:**
1. Generate key pair: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_jenkins`
2. Temporarily set password on `deploy` user for key installation
3. Copy public key: `ssh-copy-id -i ~/.ssh/id_ed25519_jenkins.pub deploy@192.168.122.250`
4. Lock password: `sudo passwd -l deploy`
5. Disable password authentication in `/etc/ssh/sshd_config`:
   ```
   PasswordAuthentication no
   ChallengeResponseAuthentication no
   ```
6. Restart SSH daemon: `sudo systemctl restart ssh`

**Result:** Production-grade security that eliminates brute-force attack vectors.

**Learning Value:** Full walkthrough of SSH hardening process (not just copy-paste) builds security best practices knowledge.

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `VM_USER` | `deploy` | Non-root user on target VM |
| `VM_IP` | `192.168.122.250` | Target VM IP address |
| `DOCKER_CTX` | `vm-lab` | Name of Docker context for verification |
| `PROJECT` | `lab` | Docker Compose project name (container prefix) |
| `VM_DIR` | `/home/deploy/lab/app` | Deployment directory on VM |

## Security Considerations

### Current Implementation
- **Key-based SSH authentication**: No password authentication allowed
- **Non-root deployment user**: Principle of least privilege
- **SSH agent forwarding**: Credentials never stored on agent
- **Docker socket mounting**: Limited to agent container for isolation

### Future Enhancements 
- fail2ban for intrusion detection and prevention
- UFW firewall configuration with explicit allow rules
- SSH 2FA with Google Authenticator PAM module
- Key rotation policy (90-day cycle)
- SELinux/AppArmor mandatory access controls

**Reference:** [How To Secure A Linux Server](https://github.com/imthenachoman/How-To-Secure-A-Linux-Server)

## Troubleshooting

### View Remote Container Logs
```bash
docker --context vm-lab compose --project-directory /home/deploy/lab/app -p lab logs --tail=200
```

### Check Remote Container Status
```bash
docker --context vm-lab ps -a
```

### Verify SSH Connectivity
```bash
ssh deploy@192.168.122.250 'docker compose -p lab ps'
```

### Re-run Deployment Manually
```bash
ssh deploy@192.168.122.250 'cd /home/deploy/lab/app && ./start-lab.sh'
```

## Related Documentation

- **Jenkinsfile:** `/home/wally/Documents/temp2/Opentelemetry_Observability_Lab/Jenkinsfile`
- **Deployment Script:** `/home/wally/Documents/temp2/Opentelemetry_Observability_Lab/start-lab.sh`
- **Architecture Overview:** `/home/wally/Documents/temp2/Opentelemetry_Observability_Lab/docs/phase-1-docker-compose/ARCHITECTURE.md`
