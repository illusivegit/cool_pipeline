# Documentation Index

## 🚀 Current Phase: Phase 1 - Docker Compose Stack
**Status:** ✅ Complete
**Last Updated:** 2025-10-22
**Next Phase:** Phase 2 - Policy as Code & Secure Delivery 

---

## Quick Navigation

### 🎯 New to this project?
1. Start with **[Project README](../README.md)** in root directory
2. Read **[Phase 1 Architecture](phase-1-docker-compose/ARCHITECTURE.md)** for system overview
3. Follow **[Implementation Guide](phase-1-docker-compose/IMPLEMENTATION-GUIDE.md)** for concepts
4. Reference **[Configuration Guide](phase-1-docker-compose/CONFIGURATION-REFERENCE.md)** for YAML configs
5. Use **[Verification Guide](phase-1-docker-compose/VERIFICATION-GUIDE.md)** to validate deployment

### 🔧 Need to troubleshoot?
- **[Troubleshooting Playbooks](phase-1-docker-compose/troubleshooting/)** for common issues
- **[Design Decisions](phase-1-docker-compose/DESIGN-DECISIONS.md)** for architectural rationale

### 📚 Learning observability concepts?
- **[Observability Fundamentals](cross-cutting/observability-fundamentals.md)** - Three Pillars, SLI/SLO
- **[TraceQL Reference](cross-cutting/traceql-reference.md)** - Query language guide

---

## 📖 Documentation by Phase

### Phase 1: Docker Compose Foundation ✅ Complete

**Scope:** On-prem VM, Docker Compose, Jenkins CI/CD, full observability stack

| Document | Purpose | Status |
|----------|---------|--------|
| **[Architecture](phase-1-docker-compose/ARCHITECTURE.md)** | Complete system design - modularized into 8 sections | ✅ Master index + [8 modules](phase-1-docker-compose/architecture/) |
| **[Design Decisions](phase-1-docker-compose/DESIGN-DECISIONS.md)** | 16 architectural decisions with trade-offs and rationale | ✅ 2,085 lines |
| **[Implementation Guide](phase-1-docker-compose/IMPLEMENTATION-GUIDE.md)** | Architecture, integration patterns, and lessons learned | ✅ 766 lines |
| **[Configuration Reference](phase-1-docker-compose/CONFIGURATION-REFERENCE.md)** | Complete YAML configuration guide for all components | ✅ 941 lines |
| **[Verification Guide](phase-1-docker-compose/VERIFICATION-GUIDE.md)** | Deployment verification and CI/CD testing procedures | ✅ 980 lines |
| **[Journey](phase-1-docker-compose/JOURNEY.md)** | The story of building this (failures, breakthroughs, lessons) | ✅ 959 lines |
| **[Troubleshooting](phase-1-docker-compose/troubleshooting/)** | Operational playbooks for common issues | ✅ 4 guides + index |
| **[Code Snippets](phase-1-docker-compose/snippets/)** | Reusable configuration examples | ✅ 5 snippets + index |

**Modular Architecture Sections:**
1. **[Infrastructure Foundation](phase-1-docker-compose/architecture/infrastructure.md)** - KVM/QEMU/libvirt, VM configuration
2. **[CI/CD Pipeline](phase-1-docker-compose/architecture/cicd-pipeline.md)** - Jenkins 6-stage deployment
3. **[Application](phase-1-docker-compose/architecture/application.md)** - Flask backend, React frontend, SQLite
4. **[Observability](phase-1-docker-compose/architecture/observability.md)** - OTel, Prometheus, Tempo, Loki, Grafana
5. **[Network](phase-1-docker-compose/architecture/network.md)** - Docker networking, Nginx proxy, CORS
6. **[Integration](phase-1-docker-compose/architecture/integration.md)** - Service dependencies, data flows
7. **[Deployment](phase-1-docker-compose/architecture/deployment.md)** - Deployment procedures, rollback strategies
8. **[Docker Optimization](phase-1-docker-compose/architecture/docker-optimization.md)** - BuildKit, caching, multi-stage builds
9. **[Roadmap](phase-1-docker-compose/architecture/roadmap.md)** - Phase 2-4 planning

**Key Technologies:**
- Infrastructure: KVM/QEMU/libvirt on Debian 13
- CI/CD: Jenkins with Docker agents, SSH deployment
- Application: Flask (Python 3.12) backend, Nginx frontend, SQLite database
- Observability: OpenTelemetry → Tempo (traces), Hybrid metrics (Prometheus + OTel), Loki (logs)
- Visualization: Grafana dashboards (SLI/SLO, traces)
- Architecture: Defense-in-depth (Nginx proxy + CORS headers)

**CI/CD Infrastructure Setup:**

For first-time Jenkins deployment, these setup resources are available in the `jenkins/` directory:

| Resource | Type | Purpose |
|----------|------|---------|
| **[Jenkins Agent Dockerfile](../jenkins/jenkins-inbound-agent-with-jq-docker-rsync)** | Dockerfile | Custom agent image with jq, Docker CLI, rsync, and SSH client |
| **[Jenkins Deployment Script](../jenkins/jenkins_setup)** | Shell Script | Docker deployment commands for controller + agent |
| **[Jenkins Plugins Reference](../jenkins/jenkins_plugins.md)** | Markdown | Required and optional plugin list with installation status |

**Usage:** Build the custom agent image, run the deployment script, then install required plugins via Jenkins UI. See [CI/CD Pipeline Architecture](phase-1-docker-compose/architecture/cicd-pipeline.md) for complete pipeline configuration.

---

### Phase 2: Policy as Code & Secure Delivery 📋 Planned

**Scope:** OPA/Rego guardrails, SonarQube/Snyk/Trivy, Vault reintroduction, JFrog Artifactory, incremental hardening

**Planned Start:** After Phase 1 stabilization
**Estimated Duration:** Iterative milestones

**Documentation Plan:**
- [x] Templates ready in `/docs/templates/`
- [ ] Architecture outline (to be created)
- [ ] Design decisions (to be documented as made)
- [ ] Implementation guide (to be written during work)
- [ ] Troubleshooting playbooks (to be added as issues found)

**Key Additions:**
- Policy as Code: Rego policies enforced via Conftest in Jenkins
- SAST/DAST: SonarQube coverage, Snyk dependency scanning, OWASP ZAP automation
- Container Scanning: Trivy for image analysis
- Artifact Management: JFrog Artifactory with provenance attestation
- Secrets Management: Vault returns for short-lived credentials
- Server Hardening: fail2ban, UFW firewall, auditd, MFA for privileged access

---

### Phase 3: Kubernetes Refactoring & Platform Automation 💭 Concept

**Scope:** Kubernetes cluster, Helm charts, PostgreSQL, Istio/Envoy, ArgoCD, Ansible automation

**Planned Start:** After Phase 2 hardening
**Estimated Duration:** Multi-phase rollout

**Key Changes:**
- Docker Compose → Kubernetes manifests backed by Helm
- SQLite → PostgreSQL StatefulSet with PersistentVolumes
- On-prem K8s cluster (kubeadm + Ansible automation)
- Istio service mesh with Envoy sidecars for mTLS and traffic shaping
- GitOps: ArgoCD managing Git-driven deployments

---

### Phase 4: Cloud-Native AWS Migration 🌥️ Future

**Scope:** AWS landing zone, ECS/EKS iteration, managed observability, hybrid connectivity

**Timing:** When AWS landing zone readiness matures

**Key Changes:**
- Establish Site-to-Site VPN or Direct Connect between lab and AWS
- Migrate Kubernetes workloads to Amazon EKS; evaluate ECS/Fargate for stateless services
- Replace self-managed observability stack with AWS managed alternatives
- Move secrets/configuration to AWS Secrets Manager and Parameter Store
- Build migration playbooks comparing cost/performance across environments
## 🔧 Cross-Cutting Documentation

**Applies to all phases**

| Document | Purpose | Size |
|----------|---------|------|
| **[Observability Fundamentals](cross-cutting/observability-fundamentals.md)** | Three Pillars (traces, metrics, logs), SLI/SLO, OpenTelemetry basics | 15,000 words |
| **[TraceQL Reference](cross-cutting/traceql-reference.md)** | Query language guide for Tempo | 4,000 words |
| **[PromQL Reference](cross-cutting/promql-reference.md)** | Query language guide for Prometheus | 8,000 words |
| **[LogQL Reference](cross-cutting/logql-reference.md)** | Query language guide for Loki | 7,000 words |

**Planned:**
- [ ] Security Baseline (SSH, fail2ban, firewall)

---

## 📖 Operational Playbooks

**Runbooks for common operations**

**Current:**
- (Playbooks will be added as operational needs arise)

**Planned:**
- [ ] Incident Response
- [ ] Rollback Procedure
- [ ] Backup & Restore
- [ ] Disaster Recovery

---

## 📐 Templates

**For creating new phase documentation**

Located in: `docs/templates/`

| Template | Purpose | Usage |
|----------|---------|-------|
| **[ARCHITECTURE-template.md](templates/ARCHITECTURE-template.md)** | Comprehensive architecture documentation | Copy for each new phase |
| **[DESIGN-DECISIONS-template.md](templates/DESIGN-DECISIONS-template.md)** | Structured decision documentation | Use for all significant decisions |
| **[troubleshooting-template.md](templates/troubleshooting-template.md)** | Operational playbook format | One per issue/problem |

**How to use:**
```bash
# Starting Phase 2
mkdir -p docs/phase-2-security-scanning/troubleshooting
cp docs/templates/ARCHITECTURE-template.md docs/phase-2-security-scanning/ARCHITECTURE.md
# Fill in the template
```

---

## 📊 Documentation Statistics

**Total Documentation:** 150,000+ words

**By Phase:**
- **Phase 1:** 145,000+ words (complete, modularized)
  - 8 modular architecture sections (~200KB)
  - 16 design decisions documented
  - 20+ architecture diagrams
- **Cross-cutting:** 19,000 words (growing)
- **Templates:** 3,000 words (guides for future)

**File Count:**
- Documentation files: 14+ (modularized architecture)
- Templates: 3
- Troubleshooting playbooks: 4

---

## 🔗 External References

### Project Infrastructure
- [GitHub Repository](https://github.com/illusivegit/Opentelemetry_Observability_Lab)
- [Main README](../README.md)

### Technology Documentation
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Grafana Tempo](https://grafana.com/docs/tempo/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)

### Learning Resources
- [Google SRE Book](https://sre.google/books/)
- [Observability Engineering Book](https://www.oreilly.com/library/view/observability-engineering/9781492076438/)

---

## 🎯 Documentation Standards

### File Naming
- **Phase docs:** `phase-X-descriptive-name/`
- **Core files:** `ARCHITECTURE.md`, `DESIGN-DECISIONS.md`, `IMPLEMENTATION-GUIDE.md`
- **Troubleshooting:** `troubleshooting/issue-name.md`

### File Size Limits
| Type | Max Lines | Action When Exceeded |
|------|-----------|----------------------|
| ARCHITECTURE.md | 1,000 | Split by domain (✅ Done for Phase 1) |
| IMPLEMENTATION-GUIDE.md | 2,000 | Create sub-guides |
| DESIGN-DECISIONS.md | 2,500 | Archive old decisions or modularize |
| Troubleshooting | 200 | One issue per file |

### Design Decision IDs
- **Format:** `DD-{number}` (Phase 1 uses simple numbering)
- **Examples:** `DD-001`, `DD-006`, `DD-013`
- **Phase 1 Status:** DD-001 through DD-016 documented
- **Future Phases:** May adopt `DD-{phase}-{number}` format for clarity

---

## 🔄 Documentation Workflow

### Adding New Phase

1. **Create directory:**
   ```bash
   mkdir -p docs/phase-X-name/troubleshooting
   ```

2. **Copy templates:**
   ```bash
   cp docs/templates/*.md docs/phase-X-name/
   ```

3. **Fill in content:**
   - Architecture: What's new, integration with previous phase
   - Design Decisions: DD-X-001, DD-X-002, etc.
   - Implementation: Step-by-step guide

4. **Update this index:**
   - Add phase to table above
   - Update statistics
   - Link to phase docs

### Adding Troubleshooting Playbook

1. **Copy template:**
   ```bash
   cp docs/templates/troubleshooting-template.md \
      docs/phase-X-name/troubleshooting/issue-name.md
   ```

2. **Fill in:**
   - Problem symptoms
   - Root cause
   - Solution steps
   - Prevention measures

3. **Link from phase README** (when created)

---

---

## 🆘 Need Help?

### Finding Information

**"How do I deploy Phase 1?"**
→ [Phase 1 Implementation Guide](phase-1-docker-compose/IMPLEMENTATION-GUIDE.md)

**"Why was X chosen over Y?"**
→ [Phase 1 Design Decisions](phase-1-docker-compose/DESIGN-DECISIONS.md)

**"Component X is broken, how do I fix it?"**
→ [Phase 1 Troubleshooting](phase-1-docker-compose/troubleshooting/)

**"What is distributed tracing?"**
→ [Observability Fundamentals](cross-cutting/observability-fundamentals.md)

**"How do I write TraceQL queries?"**
→ [TraceQL Reference](cross-cutting/traceql-reference.md)

---
