# Infrastructure Foundation

## Overview

This document describes the foundational infrastructure layer for the OpenTelemetry Observability Lab. The lab runs on a simulated on-premises environment using KVM/QEMU virtualization with libvirt management on a Debian 13 host. This architecture deliberately mirrors enterprise data center patterns to provide realistic operational experience before transitioning to cloud-native environments.

## Virtualization Stack

The infrastructure is built on a three-layer virtualization stack:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PHYSICAL HOST (Debian 13)                           │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   KVM Hypervisor (Kernel Module)                  │  │
│  │  • Hardware-accelerated virtualization (Intel VT-x / AMD-V)       │  │
│  │  • Type-1 hypervisor integrated into Linux kernel                 │  │
│  │  • Production-grade (powers OpenStack, oVirt, RHEV)               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                ↓                                        │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │              libvirt Management Layer (v9.0+)                     │  │
│  │  • VM lifecycle management (create, start, stop, destroy)         │  │
│  │  • Storage pool management (qcow2 images, volumes)                │  │
│  │  • Virtual network management (bridges, NAT, routing)             │  │
│  │  • API for automation (virsh CLI, Python bindings)                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                ↓                                        │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │               QEMU/KVM Virtual Machine (VM)                       │  │
│  │  • Guest OS: Debian 13                                            │  │
│  │  • IP Address: 192.168.122.250                                    │  │
│  │  • Hostname: observability-vm (or similar)                        │  │
│  │  • Purpose: Observability lab deployment target                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why KVM/QEMU/libvirt?

**Enterprise Alignment:**
- **KVM** is the hypervisor behind OpenStack, oVirt, RHEV, and Google Cloud
- Represents real-world on-premises infrastructure patterns
- Direct experience translates to VMware vSphere/ESXi concepts

**Technical Advantages:**
- Hardware-accelerated virtualization (Intel VT-x)
- Near-native performance (type-1 hypervisor)
- Scriptable via `virsh` CLI (future Ansible automation)
- Free and open source

**Learning Objectives:**
- Understand hypervisor fundamentals before abstracting to cloud VMs
- Practice infrastructure-as-code concepts (libvirt XML)
- Simulate on-premises operational challenges (SSH deployment, network isolation)

## Virtual Machine Configuration

### Resource Allocation

The observability VM is provisioned with sufficient resources to run the full Docker Compose stack:

| Resource | Allocation | Rationale |
|----------|-----------|-----------|
| **vCPUs** | 2-4 cores | Sufficient for 7 containers + host processes |
| **Memory** | 4-8 GB RAM | Prometheus, Tempo, and Loki are memory-intensive |
| **Disk** | 20-40 GB (qcow2) | Thin-provisioned, grows as needed |
| **Network** | 1 virtio NIC | Paravirtualized driver for better performance |

**Note:** Exact allocations may vary based on host capacity. Minimum 4GB RAM recommended for stable operation.

### Storage Architecture

Virtual machine disk storage uses **qcow2** (QEMU Copy-On-Write version 2) format:

```
Host Filesystem
  └─ /var/lib/libvirt/images/
      └─ observability-vm.qcow2 (thin-provisioned disk image)
          ├─ Base OS (Debian 13)
          ├─ Docker images (pulled containers)
          ├─ Docker volumes (persistent data)
          └─ Application files (/home/deploy/lab/app)
```

**qcow2 Advantages:**
- **Thin provisioning:** Only consumes space actually used
- **Snapshot support:** Can save VM state before risky operations
- **Compression:** Reduces disk space consumption
- **Copy-on-write:** Efficient incremental backups

**Docker Volume Persistence:**
The Docker Compose stack creates named volumes that persist in `/var/lib/docker/volumes/` on the VM. These survive container restarts but are VM-local (not shared across VMs).

### Operating System

**Guest OS:** Debian 13 (Trixie)

**Chosen Because:**
- Same OS as host (consistent tooling and behavior)
- Stable, well-documented, enterprise-friendly
- Excellent Docker support
- Security updates via `apt`

**Base System Setup:**
- SSH server enabled (for Jenkins deployment)
- Docker Engine installed
- Docker Compose V2 installed
- User account: `deploy` (passwordless SSH key authentication)
- Firewall: Permissive for lab environment (ports 80, 3000, 5000, 9090 exposed)

### VM XML Definition (Conceptual)

VMs in libvirt are defined by XML manifests. A simplified example:

```xml
<domain type='kvm'>
  <name>observability-vm</name>
  <memory unit='GiB'>4</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-9.0'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <source file='/var/lib/libvirt/images/observability-vm.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='bridge'>
      <source bridge='virbr0'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>
```

**Key Elements:**
- `type='kvm'`: Uses KVM hardware acceleration
- `<memory>`: RAM allocation
- `<vcpu>`: Virtual CPU count
- `<disk>`: qcow2 image location, virtio driver for performance
- `<interface>`: Network connection via libvirt bridge

## Virtual Networking

### Network Topology

The lab uses libvirt's **default NAT network** with a bridge interface:

```
Physical Network (192.168.1.0/24)
  │
  └─ Physical NIC (enp0s31f6 or similar)
      │
      └─ Linux Bridge: virbr0 (192.168.122.1)
          │
          ├─ libvirt dnsmasq (DHCP/DNS server)
          │   • IP range: 192.168.122.2 - 192.168.122.254
          │   • DNS resolution for VMs
          │   • DHCP reservations (MAC → IP mapping)
          │
          └─ VM NIC (virtio)
              • IP: 192.168.122.250 (static or DHCP reservation)
              • Gateway: 192.168.122.1
              • DNS: 192.168.122.1 (forwarded to host DNS)
```

### NAT vs Bridge Mode

**NAT Mode (Current Setup):**
- VMs can reach the internet (outbound traffic NATted through host)
- Host can reach VMs directly (same subnet routing)
- VMs NOT directly accessible from external LAN (requires port forwarding or proxy)
- **Use Case:** Isolated lab environment, development/testing

**Bridge Mode (Alternative):**
- VMs appear as physical devices on your LAN (e.g., 192.168.1.x addresses)
- Accessible from any device on the network
- Requires network administrator permissions (bridging physical NIC)
- **Use Case:** Production-like environments, external access requirements

**Why NAT for This Lab:**
- Simpler setup (no physical NIC bridging required)
- Network isolation (VMs don't expose services to home/office LAN)
- Sufficient for Jenkins SSH deployment and local browser access

### IP Address Assignment

**Static IP: 192.168.122.250**

The VM is assigned a predictable IP address via one of:
1. **DHCP Reservation:** libvirt dnsmasq maps VM's MAC address to 192.168.122.250
2. **Static Configuration:** Manual IP configuration in VM's `/etc/network/interfaces`

**Why Static IP Matters:**
- Jenkins pipeline targets `deploy@192.168.122.250` for SSH/rsync
- Browser access URLs are hardcoded (e.g., `http://192.168.122.250:3000`)
- Simplifies debugging (no need to lookup dynamic IPs with `virsh domifaddr`)

### DNS Resolution

**libvirt dnsmasq** provides DNS services:
- Resolves VM hostnames (e.g., `observability-vm` → `192.168.122.250`)
- Forwards external queries to host's DNS server
- Critical for Docker container DNS (containers use host DNS by default)

**Docker DNS Note:**
Docker containers on the VM use the host's DNS resolver (`/etc/resolv.conf`), which points to libvirt's dnsmasq. This enables containers to resolve external hostnames (e.g., pulling images from Docker Hub).

## VM Lifecycle Management

### virsh CLI Commands

Common operations for managing the VM:

```bash
# Start VM
virsh start observability-vm

# Stop VM gracefully (ACPI shutdown)
virsh shutdown observability-vm

# Force stop (equivalent to pulling power plug)
virsh destroy observability-vm

# Check VM status
virsh list --all

# Get VM IP address
virsh domifaddr observability-vm

# View VM console (useful for debugging boot issues)
virsh console observability-vm

# Edit VM configuration (XML)
virsh edit observability-vm

# Create snapshot
virsh snapshot-create-as observability-vm snapshot1 "Before risky change"

# Revert to snapshot
virsh snapshot-revert observability-vm snapshot1
```

### Automation Potential (Future)

The VM lifecycle can be automated using:
- **Ansible:** Playbooks for VM provisioning, Docker installation, app deployment
- **Terraform:** Infrastructure-as-code for libvirt resources (via `dmacvicar/libvirt` provider)
- **Cloud-init:** Automated initial configuration (user accounts, SSH keys, packages)

**Phase 3 Goal:** Replace manual VM setup with Ansible playbooks that provision VMs from scratch.

## Network Access Patterns

### SSH Access (Jenkins Deployment)

The Jenkins pipeline deploys to the VM via SSH:

```
Jenkins Controller (Host or Container)
  │
  └─ SSH Connection: deploy@192.168.122.250
      │
      ├─ Authentication: SSH key-based (no password)
      │   • Private key stored in Jenkins credentials
      │   • Public key in /home/deploy/.ssh/authorized_keys
      │
      ├─ Commands Executed:
      │   • rsync (file synchronization)
      │   • docker compose up (start services)
      │   • healthcheck validation
      │
      └─ Deployment Directory: /home/deploy/lab/app
```

**Security Configuration:**
- SSH password authentication disabled
- Key-based authentication only
- Dedicated `deploy` user (non-root)
- Sudo privileges for Docker commands (if needed)

### HTTP Access (Browser)

Users access services via HTTP on the VM's IP:

| Service | URL | Purpose |
|---------|-----|---------|
| Frontend (Nginx) | http://192.168.122.250:80 | Task Manager UI |
| Grafana | http://192.168.122.250:3000 | Dashboards, traces, logs |
| Prometheus | http://192.168.122.250:9090 | Metrics explorer |
| Backend (Direct) | http://192.168.122.250:5000 | API debugging (bypasses Nginx) |

**Network Path:**
```
Browser (Host) → 192.168.122.250:80 → virbr0 → VM → Docker Bridge → Nginx Container
```

### Container-to-Container Networking

Within the VM, Docker containers communicate via Docker's bridge network:

```
Docker Bridge Network: lab_default (172.x.x.x subnet)
  │
  ├─ frontend (Nginx) → http://backend:5000
  ├─ backend (Flask) → http://otel-collector:4318
  ├─ otel-collector → http://tempo:4317, http://loki:3100
  ├─ prometheus → http://backend:5000/metrics
  └─ grafana → http://prometheus:9090, http://tempo:3200, http://loki:3100
```

**Key Point:** Containers use service names for DNS (Docker's embedded DNS resolver). IP addresses are dynamic and should not be hardcoded.

## Infrastructure Design Decisions

### Why Virtualization Instead of Bare Metal?

**Isolation:**
- Lab environment isolated from host OS
- Can snapshot/revert risky changes
- No risk of breaking host system

**Portability:**
- VM image can be copied to different hosts
- Consistent environment across team members
- Easier to replicate issues

**Learning Value:**
- Mirrors enterprise on-prem infrastructure (VMware, Hyper-V, KVM)
- Forced to deal with networking, SSH, remote deployment
- Prepares for multi-VM architectures (Phase 3+)

### Why Not Cloud VMs (AWS EC2, Azure VMs)?

**Phase 1 Goal:** Master on-premises patterns first

**Learning Objectives:**
- Understand hypervisor fundamentals
- Manually configure networking (no VPC abstraction)
- Practice SSH-based deployment (no cloud-init/user-data shortcuts)
- Cost-effective (no hourly billing)

**Phase 4 Migration:** Once on-prem patterns are mastered, the architecture will migrate to AWS/Azure to learn cloud-specific services (VPC, security groups, load balancers, managed databases).

### Why Debian 13?

**Consistency:** Same OS as host (Debian 13 on both)

**Stability:** Enterprise-grade, long-term support

**Docker Support:** Excellent upstream support, official Docker Engine packages

**Package Management:** Apt ecosystem is well-documented and reliable

**Alternative Considered:** Ubuntu Server 24.04 LTS (also valid, slightly different package versions)

## Operational Considerations

### Performance

**Current Bottlenecks:**
- **Memory:** Prometheus/Tempo can consume 1-2GB each under load
- **Disk I/O:** Log ingestion to Loki, metrics scraping to Prometheus
- **CPU:** Generally not a bottleneck for this workload

**Monitoring Host Resources:**
```bash
# Check VM resource usage from host
virsh domstats observability-vm

# Inside VM, monitor Docker resource usage
docker stats

# Check disk space (qcow2 image growth)
qemu-img info /var/lib/libvirt/images/observability-vm.qcow2
```

### Backup Strategy

**VM-Level Backups:**
```bash
# Snapshot (quick, space-efficient)
virsh snapshot-create-as observability-vm backup-$(date +%Y%m%d)

# Full clone (slower, independent copy)
virt-clone --original observability-vm --name observability-vm-backup --auto-clone
```

**Application-Level Backups:**
- Docker volumes can be backed up with `docker run --volumes-from`
- Configuration files synchronized via rsync (already in Git)
- Data loss acceptable for lab environment (no production data)

### Troubleshooting

**VM Won't Start:**
```bash
# Check libvirt logs
journalctl -u libvirtd

# Verify VM XML definition
virsh dumpxml observability-vm

# Check host virtualization support
virt-host-validate
```

**Network Issues:**
```bash
# Verify bridge is up
ip addr show virbr0

# Check dnsmasq is running
systemctl status libvirt-guests

# Test VM reachability
ping 192.168.122.250

# Verify SSH port is open
nmap -p 22 192.168.122.250
```

**Disk Space Issues:**
```bash
# Check qcow2 image size
qemu-img info /var/lib/libvirt/images/observability-vm.qcow2

# Reclaim unused space (VM must be shut down)
qemu-img convert -O qcow2 -c original.qcow2 compacted.qcow2

# Inside VM, clean Docker
docker system prune -a --volumes
```

## Integration with Other Architecture Layers

### CI/CD Integration

The VM serves as the **deployment target** for the Jenkins pipeline:

```
Jenkins Pipeline (cicd-pipeline.md)
  │
  ├─ Stage: Sync repo to VM
  │   └─ rsync → /home/deploy/lab/app
  │
  ├─ Stage: Compose up
  │   └─ SSH → docker compose up -d
  │
  └─ Stage: Smoke tests
      └─ curl http://192.168.122.250:8080
```

See: [CI/CD Pipeline Architecture](cicd-pipeline.md) for deployment details.

### Network Integration

The VM provides the **network boundary** between external access and containerized services:

```
External Browser
  ↓
192.168.122.250:80 (VM IP)
  ↓
Docker Bridge Network (internal)
  ↓
Nginx → Backend → OTel Collector → Backends
```

See: [Network Architecture](network.md) for Docker networking and Nginx proxy details.

### Application Deployment

The VM hosts the **Docker Compose stack**:

```
VM Filesystem: /home/deploy/lab/app/
  ├─ docker-compose.yml (service definitions)
  ├─ backend/ (Flask application)
  ├─ frontend/ (React + Nginx)
  ├─ otel-collector-config.yml
  └─ grafana/
      ├─ datasources.yml
      └─ dashboards/
```

See: [Application Architecture](application.md) and [Deployment](deployment.md) for service details.

## Future Evolution

### Phase 2: Infrastructure as Code

**Goal:** Automate VM provisioning with Ansible

**Planned Improvements:**
- Ansible playbook for VM creation (libvirt XML template)
- Automated Docker installation
- User account and SSH key setup
- Network configuration (static IP via netplan/ifupdown)

### Phase 3: Multi-VM Kubernetes Cluster

**Goal:** Replace single VM with 3-node Kubernetes cluster

**Architecture:**
```
KVM Host
  ├─ k8s-control-plane (192.168.122.10)
  ├─ k8s-worker-1 (192.168.122.11)
  └─ k8s-worker-2 (192.168.122.12)
```

**Migration Path:**
- Docker Compose → Kubernetes manifests
- Local volumes → Persistent Volume Claims (PVCs)
- Nginx → Ingress controller (Traefik, Nginx Ingress)
- Manual deployment → Helm charts + ArgoCD

### Phase 4: Cloud Migration

**Goal:** Migrate to AWS/Azure while maintaining infrastructure-as-code practices

**AWS Equivalent:**
- KVM VM → EC2 instance
- libvirt network → VPC + subnets
- Manual SSH → Systems Manager Session Manager
- Docker Compose → ECS or EKS

**Learning Objectives:**
- Understand cloud-native equivalents of on-prem concepts
- Practice lift-and-shift migration strategies
- Compare cost/complexity of cloud vs on-prem

## Related Documentation

- **[CI/CD Pipeline Architecture](cicd-pipeline.md)** - Jenkins deployment to this VM
- **[Network Architecture](network.md)** - Docker networking and service exposure
- **[Application Architecture](application.md)** - Services running on this VM
- **[Deployment Guide](deployment.md)** - Step-by-step deployment procedures
- **[Roadmap](roadmap.md)** - Future phases (Kubernetes, cloud migration)

## Verification Checklist

After VM provisioning, verify the infrastructure is ready:

```bash
# 1. Verify VM is running
virsh list --all | grep observability-vm

# 2. Check VM IP address
virsh domifaddr observability-vm
# Expected: 192.168.122.250

# 3. Test SSH connectivity
ssh deploy@192.168.122.250 'echo "SSH works"'

# 4. Verify Docker is installed
ssh deploy@192.168.122.250 'docker --version'

# 5. Verify Docker Compose is installed
ssh deploy@192.168.122.250 'docker compose version'

# 6. Check available disk space
ssh deploy@192.168.122.250 'df -h | grep -E "Filesystem|/dev/vda"'
# Should have >10GB free

# 7. Test internet connectivity from VM
ssh deploy@192.168.122.250 'ping -c 3 1.1.1.1'
```

**✅ Success Criteria:**
- VM is running and accessible via SSH
- Docker and Docker Compose installed
- Static IP 192.168.122.250 configured
- At least 10GB free disk space
- Internet connectivity working (for pulling images)

---

## Summary

The infrastructure foundation provides a **production-realistic on-premises environment** using KVM/QEMU/libvirt virtualization. This architecture:

- **Simulates enterprise data center patterns** (hypervisor, VMs, network isolation)
- **Enables SSH-based CI/CD deployment** (Jenkins → VM via rsync)
- **Provides network isolation** (NAT mode with predictable IP addressing)
- **Supports future expansion** (multi-VM Kubernetes cluster, Ansible automation)
- **Facilitates learning** (manual VM management before cloud abstraction)

The VM serves as the **deployment target** for the Docker Compose observability stack, bridging the gap between development (containerized services) and operations (infrastructure management).

---

**Phase 1 Documentation Set v1.0** | Last Reviewed: October 22, 2025
