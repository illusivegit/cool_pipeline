# Future Roadmap: Evolution of the On-Prem Domain

**Version:** 1.0
**Last Updated:** 2025-10-22
**Status:** Planning Document

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Current State: Phase 1 Complete](#current-state-phase-1-complete)
- [Phase 2: Policy as Code & Secure Delivery](#phase-2-policy-as-code-secure-delivery)
- [Phase 3: Kubernetes Refactoring & Platform Automation](#phase-3-kubernetes-refactoring-platform-automation)
- [Phase 4: Cloud-Native AWS Migration](#phase-4-cloud-native-aws-migration)
- [Technology Evaluation Criteria](#technology-evaluation-criteria)
- [Cross-Cutting Themes](#cross-cutting-themes)
- [Dependencies Between Phases](#dependencies-between-phases)
- [Timeline Estimates](#timeline-estimates)
- [Learning Objectives by Phase](#learning-objectives-by-phase)
- [Success Criteria by Phase](#success-criteria-by-phase)
- [Risk Management](#risk-management)
- [Proof of Concept Foundation](#proof-of-concept-foundation)
- [Conclusion](#conclusion)

---

## Executive Summary

This roadmap outlines the evolution of the observability lab from its current Docker Compose foundation through Kubernetes refactoring to hybrid cloud deployment. The journey represents a structured learning path that mirrors real-world infrastructure modernization patterns.

### Vision Statement

The "On-Prem Domain" project aims to build comprehensive infrastructure expertise by:

1. **Understanding fundamentals** through hands-on on-premises infrastructure
2. **Mastering orchestration** via progressive tooling adoption
3. **Migrating strategically** to cloud with full architectural awareness
4. **Operating hybrid environments** combining on-prem and cloud strengths

**Core Philosophy:** Learn what cloud abstractions hide by building without them first, then appreciate managed services by understanding what they solve.

---

## Current State: Phase 1 Complete

### Milestone 1 Achievements (October 2025)

**Infrastructure:**
- ✅ KVM/QEMU/libvirt virtualization on Debian 13
- ✅ Virtual networking with libvirt bridges
- ✅ VM lifecycle management via virsh
- ✅ Storage pools and qcow2 volumes

**Application Stack:**
- ✅ Flask backend (Python 3.12) with full instrumentation
- ✅ Nginx reverse proxy with dynamic DNS resolution
- ✅ SQLite database (migration-ready architecture)
- ✅ Browser-instrumented frontend

**Observability:**
- ✅ OpenTelemetry Collector (traces + logs)
- ✅ Prometheus (metrics via direct scrape)
- ✅ Tempo (distributed tracing, TraceQL)
- ✅ Loki (log aggregation, LogQL)
- ✅ Grafana (unified visualization)
- ✅ SLI/SLO dashboards (availability, P95 latency, error rates)
- ✅ End-to-end trace correlation (browser → backend → database)
- ✅ Log-to-trace correlation via trace_id/span_id

**CI/CD:**
- ✅ Containerized Jenkins controller
- ✅ Docker build agents
- ✅ SSH + rsync deployment strategy
- ✅ Six-stage pipeline (checkout, sync, deploy, health checks, smoke tests, cleanup)
- ✅ Key-only SSH authentication (ED25519, password auth disabled)

**Documentation:**
- ✅ 152,000+ words across comprehensive documentation
- ✅ Architecture, design decisions, implementation guide, journey narrative
- ✅ Troubleshooting playbooks
- ✅ Source code audits for accuracy

### Learning Outcomes Achieved

- Hypervisor concepts and virtual networking
- Container orchestration and service discovery
- Distributed tracing architecture
- Metrics instrumentation (counters, histograms, percentiles)
- Structured logging with trace correlation
- Jenkins pipeline design and SSH-based deployment
- Production-grade security patterns (SSH hardening, least privilege)
- Debug methodologies for distributed systems

---

## Phase 2: Policy as Code & Secure Delivery

**Objective:** Shift security left, enforce policy guardrails, and establish artifact provenance

**Target Timeline:** Q1 2026 (3-4 months)
**Status:** Planning
**Dependencies:** Phase 1 complete

### Core Initiatives

#### 1. Policy as Code (OPA/Rego)

**Goal:** Prevent misconfigurations and enforce security/compliance rules at build time

**Deliverables:**
- Deepen Rego (Open Policy Agent policy language) expertise
- Build reusable policy libraries for:
  - Container security (no privileged containers, must have resource limits)
  - Infrastructure guardrails (network policies, storage constraints)
  - Secret detection (block hardcoded credentials, API keys, tokens)
- Integrate Conftest into Jenkins pipeline
- Capture policy violations as structured pipeline output
- Create policy exemption workflow with approval gates

**Learning Objectives:**
- Understand policy-driven compliance
- Practice declarative policy authoring
- Learn policy testing and validation
- Experience policy as part of CI/CD gates

#### 2. Shift-Left Security & Testing

**Goal:** Catch vulnerabilities early in the development lifecycle

**Deliverables:**

**SAST (Static Application Security Testing):**
- Stand up SonarQube for code quality gates
- Configure quality profiles for Python and JavaScript
- Set minimum quality gates (coverage thresholds, code smells, vulnerabilities)
- Block PRs that don't meet quality standards

**Dependency Scanning:**
- Integrate Snyk for dependency vulnerability scanning
- Monitor Python (pip) and JavaScript (npm) dependencies
- Create automated PR comments for vulnerable dependencies
- Establish severity thresholds for pipeline failures

**Container Image Scanning:**
- Add Trivy for container image vulnerability scanning
- Scan base images and application layers
- Fail builds on critical/high vulnerabilities
- Generate SBOM (Software Bill of Materials)

**DAST (Dynamic Application Security Testing):**
- Automate OWASP ZAP or Burp Suite for basic DAST
- Run lightweight smoke scans post-deployment
- Focus on common web vulnerabilities (XSS, SQL injection, CSRF)
- Integrate results into Jenkins pipeline reporting

**Learning Objectives:**
- Understand the security testing pyramid (SAST, DAST, dependency scanning)
- Experience DevSecOps workflows
- Learn vulnerability triage and remediation
- Practice threat modeling

#### 3. Artifact & Credential Management

**Goal:** Immutable artifacts with provenance and secure credential distribution

**Deliverables:**

**JFrog Artifactory:**
- Stand up JFrog Artifactory instance (self-hosted or cloud)
- Configure Docker registry for immutable image storage
- Enable image signing and provenance attestation
- Implement artifact retention policies
- Create promotion workflows (dev → staging → prod)

**HashiCorp Vault Integration:**
- Reintroduce Vault (previously integrated, removed for simplification)
- Configure AppRole authentication for Jenkins
- Issue short-lived credentials for:
  - SSH deployment keys
  - Container registry tokens
  - Database passwords (future PostgreSQL migration)
- Implement automatic credential rotation
- Add Vault audit logging

**Learning Objectives:**
- Understand artifact lifecycle management
- Practice supply chain security (provenance, attestation)
- Learn dynamic secrets management
- Experience credential rotation workflows

#### 4. Operational Guardrails

**Goal:** Harden infrastructure and improve code quality gates

**Deliverables:**

**Pre-Commit Hooks:**
- Expand pre-commit hooks beyond basic linting
- Add `black` (Python formatting)
- Add `flake8` (Python linting)
- Add `prettier` (JavaScript/CSS formatting)
- Add `detect-secrets` (prevent credential leaks)
- Add `shellcheck` (shell script linting)

**Server Hardening:**
- Implement fail2ban (automated IP banning after failed SSH attempts)
- Configure UFW firewall (restrict to required ports only)
- Enable auditd for system call auditing
- Harden SSH configuration (disable root login, key-only auth already done)
- Implement kernel tuning for security (sysctl hardening)
- Reference: [How To Secure A Linux Server](https://github.com/imthenachoman/How-To-Secure-A-Linux-Server)

**Hardening Sequence:**
1. ✅ SSH keys (done in Phase 1)
2. fail2ban (ban brute-force attacks)
3. Firewall (UFW/iptables)
4. HIDS (Host Intrusion Detection System)
5. Audit logging (auditd)

**Branch Protection:**
- Add branch protection rules in Git
- Require code review approvals
- Consider Gerrit-style review workflow
- Add ChatOps notifications (Slack/Teams) for gate failures

**Learning Objectives:**
- Understand defense in depth
- Practice Linux hardening techniques
- Learn intrusion detection patterns
- Experience GitOps workflow improvements

### Success Metrics

**Policy Enforcement:**
- 100% of policy checks passing before Phase 3
- Zero privileged containers in production
- All secrets managed via Vault (no hardcoded credentials)

**Security Posture:**
- SAST scan results: Zero critical vulnerabilities
- Dependency scanning: All high/critical CVEs remediated within 7 days
- Container images: Zero critical vulnerabilities at deployment time
- Server hardening: Pass CIS benchmark Level 1

**Artifact Management:**
- All container images stored in Artifactory with provenance
- Image signing enabled for production deployments
- Vault issuing 100% of credentials (zero static secrets)

### Dependencies & Risks

**Dependencies:**
- Phase 1 infrastructure and CI/CD pipeline
- Additional compute resources for new services (SonarQube, Vault, Artifactory)
- Learning time for Rego, OPA, and security tooling

**Risks:**
- Policy authoring complexity (mitigation: start with simple policies, iterate)
- Vault integration complexity (mitigation: reuse prior implementation)
- Performance impact of security scans (mitigation: run in parallel, optimize scan scope)

---

## Phase 3: Kubernetes Refactoring & Platform Automation

**Objective:** Migrate to Kubernetes for orchestration, introduce service mesh, and automate infrastructure provisioning

**Target Timeline:** Q2-Q3 2026 (6 months)
**Status:** Planning
**Dependencies:** Phase 1 complete, Phase 2 optional but recommended

### Core Initiatives

#### 1. Kubernetes Migration

**Goal:** Replace Docker Compose with production-grade orchestration

**Deliverables:**

**Cluster Setup:**
- Provision multi-node Kubernetes cluster via kubeadm
- Configure control plane nodes (3 for HA)
- Configure worker nodes (3+ for workload distribution)
- Set up etcd backup and recovery procedures
- Automate cluster provisioning via Ansible playbooks

**Manifest Migration:**
- Convert `docker-compose.yml` to Kubernetes manifests
- Use Kompose as initial conversion tool
- Refactor to follow Kubernetes best practices:
  - Use Deployments for stateless services
  - Use StatefulSets for stateful services (PostgreSQL)
  - Define Services (ClusterIP, NodePort, LoadBalancer)
  - Create ConfigMaps for configuration
  - Create Secrets for sensitive data
  - Define PersistentVolumeClaims for storage

**Package with Helm:**
- Create Helm charts for each service
- Define reusable values files (dev, staging, prod)
- Implement templating for environment-specific configs
- Add Helm hooks for database migrations
- Create umbrella chart for full stack deployment

**Database Migration (SQLite → PostgreSQL):**
- Deploy PostgreSQL StatefulSet with PersistentVolumes
- Implement automated backups via CronJobs
- Migrate data from SQLite to PostgreSQL
- Update backend ORM configuration
- Test transaction isolation and connection pooling
- Document rollback procedures

**Learning Objectives:**
- Kubernetes architecture (control plane, worker nodes, etcd)
- Pod lifecycle and scheduling
- StatefulSets and persistent storage
- Helm chart design and templating
- Database migration strategies

#### 2. Traffic & Observability Fabric

**Goal:** Uniform telemetry, mTLS, and advanced traffic management

**Deliverables:**

**Istio Service Mesh:**
- Install Istio control plane
- Deploy Envoy sidecars to all application pods
- Configure mTLS for service-to-service communication
- Implement traffic routing rules:
  - Canary deployments (gradual traffic shifting)
  - Blue-green deployments
  - A/B testing
  - Fault injection for chaos engineering
- Set up ingress gateway for external traffic

**OpenTelemetry on Kubernetes:**
- Deploy OpenTelemetry Collector as DaemonSet
- Configure auto-instrumentation via Istio
- Standardize trace context propagation across services
- Export telemetry to existing backends (Tempo, Prometheus, Loki)

**Observability Enhancements:**
- Enable Istio telemetry (request rates, latencies, error rates)
- Add service mesh dashboards in Grafana
- Implement distributed tracing for mesh hops
- Monitor east-west traffic patterns

**Learning Objectives:**
- Service mesh architecture and sidecar pattern
- mTLS certificate management
- Advanced traffic routing strategies
- Chaos engineering practices
- Observability at scale

#### 3. GitOps & Automation

**Goal:** Declarative deployments and infrastructure as code

**Deliverables:**

**ArgoCD for GitOps:**
- Install ArgoCD on Kubernetes cluster
- Configure Git repositories as source of truth
- Implement application synchronization policies
- Set up automated deployments on Git commits
- Create rollback workflows
- Add Slack/Teams notifications for deployment events

**Ansible Automation:**
- Create Ansible playbooks for:
  - VM provisioning (libvirt module)
  - Kubernetes cluster bootstrap (kubeadm)
  - Day 2 operations (upgrades, patches, backups)
  - Configuration management
- Organize playbooks into reusable roles
- Implement Ansible Vault for secrets
- Add smoke tests per playbook execution

**Automated Testing:**
- Create smoke tests for each Helm release
- Implement integration tests for service interactions
- Add automated rollback on test failures
- Generate test reports in CI/CD pipeline

**Ingress & HTTPS:**
- Install Nginx Ingress Controller
- Configure TLS termination with Let's Encrypt
- Implement cert-manager for automated certificate renewal
- Set up DNS automation (ExternalDNS or manual)

**Learning Objectives:**
- GitOps principles and workflows
- Declarative infrastructure management
- Ansible automation patterns
- Certificate management and PKI
- Automated testing strategies

### Success Metrics

**Kubernetes Adoption:**
- 100% of Docker Compose services migrated to Kubernetes
- Multi-node cluster running in HA mode
- PostgreSQL StatefulSet with automated backups
- Zero data loss during SQLite → PostgreSQL migration

**Service Mesh:**
- mTLS enabled for all service-to-service traffic
- Canary deployment workflow operational
- Istio telemetry integrated into Grafana dashboards

**Automation:**
- Cluster provisioning fully automated via Ansible
- ArgoCD managing 100% of application deployments
- Automated smoke tests passing for all releases

**Observability:**
- Distributed tracing across all Kubernetes services
- Service mesh metrics in Grafana
- Alert rules defined for cluster health

### Migration Strategies

**Phased Migration Approach:**

**Phase 3.1: Kubernetes Foundation (Months 1-2)**
- Set up 3-node cluster (1 control plane, 2 workers)
- Migrate non-stateful services (frontend, backend without DB)
- Test networking and service discovery
- Validate observability pipelines

**Phase 3.2: Stateful Services (Month 3)**
- Deploy PostgreSQL StatefulSet
- Migrate SQLite data to PostgreSQL
- Test backup/restore procedures
- Update application configuration

**Phase 3.3: Service Mesh (Month 4)**
- Install Istio control plane
- Inject Envoy sidecars progressively
- Enable mTLS service by service
- Implement first canary deployment

**Phase 3.4: GitOps & Automation (Months 5-6)**
- Install ArgoCD and configure Git sync
- Create Ansible playbooks for cluster operations
- Implement automated testing workflows
- Document runbooks and playbooks

**Rollback Strategy:**
- Keep Docker Compose stack operational until Phase 3 validation complete
- Document manual rollback procedures
- Test rollback workflows in non-production environment
- Establish rollback SLAs (< 15 minutes to previous state)

### Dependencies & Risks

**Dependencies:**
- Additional compute resources (3+ VMs for Kubernetes cluster)
- Storage provisioning (NFS or Ceph for PersistentVolumes)
- Learning time for Kubernetes, Istio, Helm, Ansible

**Risks:**
- Migration complexity (mitigation: phased approach, extensive testing)
- Data loss during PostgreSQL migration (mitigation: backups, validation)
- Service mesh performance overhead (mitigation: monitoring, optimization)
- Learning curve steepness (mitigation: incremental adoption, documentation)

---

## Phase 4: Cloud-Native AWS Migration

**Objective:** Establish hybrid cloud footprint, migrate to AWS managed services, and optimize for cloud economics

**Target Timeline:** Q4 2026 and beyond (6+ months)
**Status:** Planning
**Dependencies:** Phase 3 complete

### Core Initiatives

#### 1. Hybrid Footprint & Connectivity

**Goal:** Secure connectivity between on-premises lab and AWS cloud

**Deliverables:**

**AWS Landing Zone:**
- Design AWS VPC architecture:
  - Segmented subnets (public, private, data)
  - Multi-AZ for high availability
  - Internet Gateway and NAT Gateways
  - Route tables and network ACLs
- Implement IAM guardrails:
  - Least privilege access policies
  - Service Control Policies (SCPs)
  - Role-based access control
  - MFA enforcement
- Enable AWS security services:
  - AWS GuardDuty (threat detection)
  - AWS Config (compliance monitoring)
  - AWS CloudTrail (audit logging)
  - AWS Security Hub (centralized findings)

**Hybrid Connectivity:**
- Establish AWS Site-to-Site VPN from on-prem lab
- Configure IPsec tunnels with redundancy
- Test latency and throughput
- Evaluate AWS Direct Connect for future (dedicated connection)
- Implement hybrid DNS resolution

**Learning Objectives:**
- AWS VPC networking architecture
- IAM policy design and SCP enforcement
- AWS security service integration
- VPN tunnel configuration and troubleshooting
- Hybrid cloud networking patterns

#### 2. Container Platforms on AWS

**Goal:** Lift Kubernetes workloads to managed AWS container services

**Deliverables:**

**Amazon EKS (Elastic Kubernetes Service):**
- Provision EKS cluster with managed control plane
- Configure managed node groups (EC2-based)
- Evaluate Fargate profiles for serverless pods
- Migrate Kubernetes manifests from on-prem cluster
- Configure cluster autoscaling
- Implement pod autoscaling (HPA, VPA)

**Storage Migration:**
- Replace on-prem PersistentVolumes with AWS-native storage:
  - Amazon EBS (Elastic Block Store) for block storage
  - Amazon EFS (Elastic File System) for shared storage
  - S3 for object storage (backups, artifacts)
- Update StorageClasses in Kubernetes
- Test backup/restore with AWS Backup

**Amazon ECS/Fargate Evaluation:**
- Identify stateless services suitable for ECS
- Deploy select services on ECS with Fargate launch type
- Compare cost and performance: EKS vs. ECS
- Document trade-offs (flexibility vs. simplicity)

**Learning Objectives:**
- EKS architecture and managed services
- AWS IAM Roles for Service Accounts (IRSA)
- EBS/EFS storage integration with Kubernetes
- ECS task definitions and service deployment
- Fargate serverless containers

#### 3. Managed Observability & Secrets

**Goal:** Replace self-hosted telemetry with AWS managed services

**Deliverables:**

**AWS Managed Prometheus (AMP):**
- Migrate Prometheus metrics to AMP
- Configure remote write from EKS
- Update Grafana datasources
- Test PromQL query compatibility

**AWS Managed Grafana (AMG):**
- Provision AMG workspace
- Migrate existing dashboards
- Configure SSO authentication (AWS IAM Identity Center)
- Set up alerts and notifications

**AWS X-Ray:**
- Integrate AWS X-Ray for distributed tracing
- Configure OpenTelemetry Collector to export to X-Ray
- Compare X-Ray with self-hosted Tempo
- Decide on unified vs. hybrid tracing strategy

**Amazon CloudWatch Logs:**
- Stream logs to CloudWatch Logs
- Create log groups and retention policies
- Configure CloudWatch Insights for log queries
- Compare with self-hosted Loki

**AWS Secrets Manager & Parameter Store:**
- Migrate secrets from HashiCorp Vault
- Use AWS Secrets Manager for database credentials
- Use Parameter Store for configuration
- Implement automatic rotation for RDS passwords
- Configure EKS integration (CSI driver for secrets)

**Learning Objectives:**
- AWS observability service integration
- Managed vs. self-hosted trade-offs
- AWS IAM authentication for Grafana
- CloudWatch Insights query language
- Secrets rotation and compliance

#### 4. Modernization Loop

**Goal:** Decompose monolith and adopt cloud-native patterns

**Deliverables:**

**Service Decomposition:**
- Analyze application for domain boundaries
- Extract services strategically:
  - Task service (core CRUD operations)
  - Auth service (authentication, authorization)
  - Notification service (email, webhooks)
- Implement API gateway (AWS API Gateway or Kong)
- Define service contracts and versioning

**Asynchronous Communication:**
- Introduce message queues and event streaming:
  - Amazon EventBridge (event bus)
  - Amazon SQS (queue for task processing)
  - Amazon SNS (pub/sub for notifications)
- Decouple synchronous flows
- Implement retry and dead-letter queue patterns

**Database Strategy:**
- Migrate PostgreSQL to Amazon RDS
- Evaluate Aurora PostgreSQL for serverless scaling
- Implement read replicas for performance
- Configure automated backups and point-in-time recovery
- Test multi-AZ failover

**Cost Optimization (FinOps):**
- Create cost dashboards comparing on-prem vs. AWS
- Track metrics:
  - Compute costs (EC2, EKS, Fargate)
  - Storage costs (EBS, EFS, S3)
  - Data transfer costs
  - Managed service costs (RDS, AMP, AMG)
- Implement cost allocation tags
- Right-size instances based on utilization
- Evaluate Reserved Instances and Savings Plans

**Learning Objectives:**
- Microservices architecture patterns
- Event-driven architecture design
- AWS messaging services (EventBridge, SQS, SNS)
- Amazon RDS and Aurora operations
- FinOps principles and cost optimization

### Success Metrics

**Migration:**
- 100% of workloads running on AWS (with on-prem lab retained for experimentation)
- Zero data loss during RDS migration
- Application SLIs maintained or improved (availability, latency, error rates)

**Cost:**
- Total cost of ownership (TCO) analysis complete
- Cloud costs optimized within 20% of initial estimates
- FinOps dashboards tracking daily spend

**Modernization:**
- At least 3 services decomposed from monolith
- Asynchronous flows implemented for 50%+ of background tasks
- API gateway operational with rate limiting and auth

**Observability:**
- AWS managed services handling 100% of telemetry
- Migration from self-hosted Prometheus/Grafana/Tempo complete
- CloudWatch Insights queries equivalent to LogQL

### Migration Strategies

**Phased Migration Approach:**

**Phase 4.1: Landing Zone (Months 1-2)**
- Set up AWS account structure (Organizations, multi-account strategy)
- Configure VPC networking and subnets
- Establish VPN connectivity to on-prem
- Deploy bastion hosts and security tooling

**Phase 4.2: Lift-and-Shift EKS (Months 3-4)**
- Provision EKS cluster
- Migrate Kubernetes manifests without changes
- Validate networking, storage, and observability
- Test application functionality in AWS

**Phase 4.3: Managed Services Adoption (Months 5-6)**
- Migrate to Amazon RDS for PostgreSQL
- Adopt AWS managed observability (AMP, AMG, X-Ray)
- Migrate secrets to AWS Secrets Manager
- Decommission self-hosted equivalents

**Phase 4.4: Modernization (Months 7+)**
- Decompose monolith into microservices
- Introduce event-driven architecture
- Implement cost optimization strategies
- Iterate based on FinOps insights

**Hybrid Transition Plan:**
- Retain on-prem lab for experimentation and new feature testing
- Use on-prem as development environment, AWS as production
- Establish CI/CD pipeline deploying to both environments
- Document lessons learned from hybrid operations

### Dependencies & Risks

**Dependencies:**
- AWS account with sufficient budget
- Learning time for AWS services (EKS, RDS, EventBridge, etc.)
- Data migration planning and validation
- Cost estimates and approval

**Risks:**
- Cost overruns (mitigation: FinOps dashboards, budget alerts)
- Vendor lock-in (mitigation: use open standards like OpenTelemetry)
- Performance degradation (mitigation: extensive testing, monitoring)
- Complexity of managed service integration (mitigation: phased approach)

---

## Technology Evaluation Criteria

### Decision Framework for Tool Selection

When evaluating new technologies for any phase, apply these criteria:

#### 1. Learning Value

**Questions to Ask:**
- Does this teach transferable skills?
- Is this technology used in production environments?
- Will this knowledge apply to both on-prem and cloud?

**Examples:**
- ✅ Kubernetes: Transferable to EKS, GKE, AKS
- ✅ Ansible: Used in enterprise on-prem and hybrid cloud
- ❌ Proprietary tool with no industry adoption

#### 2. Production Readiness

**Questions to Ask:**
- Is this suitable for production workloads?
- Does it have proven stability and community support?
- Can it scale to real-world requirements?

**Examples:**
- ✅ Prometheus: Industry-standard metrics
- ✅ Istio: Battle-tested service mesh
- ❌ Experimental tool with no production track record

#### 3. Operational Complexity

**Questions to Ask:**
- What is the operational burden (maintenance, upgrades)?
- Can it be automated via CI/CD?
- Is documentation and community support strong?

**Examples:**
- ✅ Docker Compose: Simple, well-documented (Phase 1)
- ⚠️ Kubernetes: Complex but justified for Phase 3 learning
- ❌ Tool requiring constant manual intervention

#### 4. Cost (Time and Money)

**Questions to Ask:**
- What is the time investment to learn and implement?
- What are the infrastructure costs (compute, storage, licenses)?
- Does it fit within project budget and timeline?

**Examples:**
- ✅ Open-source tools with no licensing costs
- ✅ Managed services with predictable pricing
- ❌ Enterprise licenses beyond project scope

#### 5. Migration Path

**Questions to Ask:**
- Does this support future phases?
- Can it be replaced without major refactoring?
- Is there a clear upgrade/migration strategy?

**Examples:**
- ✅ SQLite → PostgreSQL (migration path documented)
- ✅ Docker Compose → Kubernetes (Kompose available)
- ❌ Technology requiring complete rewrite to replace

### Tool Comparison Matrix

| Tool/Service | Learning Value | Production Ready | Operational Complexity | Cost | Migration Path | Phase |
|--------------|----------------|------------------|------------------------|------|----------------|-------|
| **Docker Compose** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | Free | → Kubernetes | Phase 1 |
| **Kubernetes** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | Free (self-hosted) | → EKS | Phase 3 |
| **Ansible** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Free | → Terraform (optional) | Phase 3 |
| **Istio** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | Free | → AWS App Mesh (optional) | Phase 3 |
| **OPA/Rego** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Free | N/A (portable) | Phase 2 |
| **Vault** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Free (OSS) | → AWS Secrets Manager | Phase 2 |
| **SonarQube** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Free (Community) | N/A (portable) | Phase 2 |
| **ArgoCD** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Free | N/A (portable) | Phase 3 |
| **Amazon EKS** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | $$ (managed control plane) | N/A | Phase 4 |
| **Amazon RDS** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | $$ (managed DB) | → Aurora (optional) | Phase 4 |

**Rating Scale:**
- ⭐⭐⭐⭐⭐ Excellent
- ⭐⭐⭐⭐ Very Good
- ⭐⭐⭐ Good
- ⭐⭐ Fair
- ⭐ Poor

---

## Cross-Cutting Themes

### Theme 1: Infrastructure Evolution

```
Phase 1: Single VM
  └─ Docker Compose orchestration
     └─ 7 containers, bridge networking

Phase 3: Multi-Node Cluster
  └─ Kubernetes orchestration
     └─ 3+ nodes, pod networking, StatefulSets

Phase 4: Hybrid Cloud
  └─ EKS managed orchestration
     └─ Managed node groups, Fargate, AWS networking
```

**Key Learning Progression:**
- Single-host container networking → Multi-host pod networking → Cloud-native networking
- Local storage → Persistent volumes → Cloud block/file storage
- Manual VM provisioning → Ansible automation → Cloud IaC (Terraform optional)

### Theme 2: CI/CD Evolution

```
Phase 1: Jenkins SSH Deployment
  └─ SSH + rsync to single VM
     └─ Docker Compose up
        └─ Smoke tests

Phase 2: Policy-Gated Pipeline
  └─ OPA policy checks
     └─ SAST/DAST/dependency scans
        └─ Artifactory push
           └─ Vault credential issuance

Phase 3: GitOps
  └─ Git commit
     └─ ArgoCD sync
        └─ Helm release
           └─ Automated smoke tests

Phase 4: Hybrid GitOps
  └─ Git commit
     └─ ArgoCD sync to EKS
        └─ AWS CodePipeline (optional)
           └─ Blue-green deployment
```

**Key Learning Progression:**
- Imperative deployment → Declarative deployment → GitOps
- Manual smoke tests → Automated integration tests → Chaos engineering
- Static credentials → Dynamic secrets → Cloud-managed IAM

### Theme 3: Observability Evolution

```
Phase 1: Self-Hosted Stack
  └─ OpenTelemetry Collector
     └─ Tempo, Prometheus, Loki, Grafana
        └─ Single-VM deployment

Phase 3: Kubernetes-Native
  └─ OTel Collector DaemonSet
     └─ Istio telemetry integration
        └─ Service mesh metrics
           └─ Cluster-wide tracing

Phase 4: Managed Services
  └─ AWS Managed Prometheus (AMP)
     └─ AWS Managed Grafana (AMG)
        └─ AWS X-Ray
           └─ CloudWatch Logs
```

**Key Learning Progression:**
- Single-host observability → Cluster observability → Multi-cluster hybrid
- Self-managed Prometheus → Remote write to AMP → Fully managed
- LogQL → CloudWatch Insights → Unified query language

### Theme 4: Security Evolution

```
Phase 1: Basic Hardening
  └─ SSH key-only authentication
     └─ Password auth disabled
        └─ Docker network isolation

Phase 2: Shift-Left Security
  └─ SAST/DAST gates
     └─ OPA policy enforcement
        └─ Vault credential management
           └─ Server hardening (fail2ban, UFW)

Phase 3: Zero-Trust Networking
  └─ Istio mTLS
     └─ Kubernetes RBAC
        └─ Network policies
           └─ Pod security policies

Phase 4: Cloud-Native Security
  └─ AWS IAM policies
     └─ Security Hub findings
        └─ GuardDuty threat detection
           └─ AWS Config compliance
```

**Key Learning Progression:**
- Host-based security → Container security → Pod security → Cloud IAM
- Static secrets → Dynamic secrets → Cloud-managed secrets
- Manual hardening → Automated policy → Managed security services

---

## Dependencies Between Phases

### Phase 1 → Phase 2 Dependencies

**Required from Phase 1:**
- ✅ Working CI/CD pipeline (Jenkins)
- ✅ Containerized application stack
- ✅ SSH deployment mechanism

**Optional but Recommended:**
- Observability stack operational (to monitor policy enforcement)
- Documentation complete (to establish baseline)

**Blockers if Phase 1 Incomplete:**
- No pipeline to integrate policy checks into
- No artifacts to scan or sign

### Phase 2 → Phase 3 Dependencies

**Required from Phase 2:**
- Policy enforcement operational (carry policies to Kubernetes)
- Artifact management in place (for Helm chart storage)

**Optional but Recommended:**
- Vault integration (for Kubernetes secrets management)
- SAST/DAST gates (maintain security posture in K8s)

**Can Proceed Without Phase 2:**
- Phase 3 can start without Phase 2 complete
- Security tooling can be added to Kubernetes later
- Phase 2 and Phase 3 can run in parallel

### Phase 3 → Phase 4 Dependencies

**Required from Phase 3:**
- ✅ Kubernetes manifests and Helm charts
- ✅ Ansible playbooks for automation

**Optional but Recommended:**
- Istio service mesh (easier to migrate to AWS App Mesh or stay with Istio on EKS)
- ArgoCD GitOps (can use same approach on EKS)

**Blockers if Phase 3 Incomplete:**
- No Kubernetes manifests to lift to EKS
- No automation patterns to apply in cloud

---

## Timeline Estimates

### Detailed Quarter-by-Quarter Plan

#### Q1 2026: Phase 2 (Policy as Code & Secure Delivery)

**Month 1: Policy & SAST**
- Week 1-2: OPA/Rego learning and policy library creation
- Week 3-4: SonarQube setup and Jenkins integration

**Month 2: Dependency & Container Scanning**
- Week 1-2: Snyk and Trivy integration
- Week 3-4: OWASP ZAP DAST automation

**Month 3: Artifact & Hardening**
- Week 1-2: JFrog Artifactory setup and Vault reintegration
- Week 3-4: Server hardening (fail2ban, UFW, auditd)

**Checkpoint:** All security gates operational, Phase 3 greenlit

#### Q2-Q3 2026: Phase 3 (Kubernetes Refactoring & Platform Automation)

**Month 1 (Q2 Start): Kubernetes Foundation**
- Week 1-2: Multi-node cluster provisioning
- Week 3-4: Non-stateful service migration

**Month 2: Stateful Services**
- Week 1-2: PostgreSQL StatefulSet deployment
- Week 3-4: SQLite → PostgreSQL migration

**Month 3: Service Mesh**
- Week 1-2: Istio installation and sidecar injection
- Week 3-4: mTLS enablement and canary deployments

**Month 4 (Q3 Start): GitOps Part 1**
- Week 1-2: ArgoCD installation and Git sync
- Week 3-4: Helm chart creation for all services

**Month 5: GitOps Part 2 & Ansible**
- Week 1-2: Ansible playbooks for cluster ops
- Week 3-4: Automated testing workflows

**Month 6: Stabilization**
- Week 1-4: Bug fixes, documentation, runbooks, validation

**Checkpoint:** All services on Kubernetes, Phase 4 greenlit

#### Q4 2026+: Phase 4 (Cloud-Native AWS Migration)

**Month 1-2: Landing Zone**
- AWS account setup, VPC design, VPN connectivity

**Month 3-4: Lift-and-Shift EKS**
- EKS cluster provisioning, manifest migration, validation

**Month 5-6: Managed Services**
- Amazon RDS, AMP, AMG, X-Ray adoption

**Month 7+: Modernization**
- Service decomposition, event-driven architecture, cost optimization

**Checkpoint:** Hybrid cloud operational, TCO analysis complete

### Flexibility and Iteration

**Note:** These timelines are estimates based on part-time learning (10-15 hours/week). Adjust based on:

- Available time commitment
- Learning curve for new technologies
- Complexity encountered during migration
- Real-world blockers (hardware, budget, etc.)

**Iteration Over Perfection:**
- Each phase is iterative; expect to revisit and refine
- Documentation will evolve with implementation
- Fail fast, learn, and adjust

---

## Learning Objectives by Phase

### Phase 1 (Complete)

**Infrastructure:**
- ✅ Hypervisor architecture (KVM, QEMU, libvirt)
- ✅ Virtual networking (bridges, NAT, DHCP)
- ✅ Storage management (qcow2, volumes)

**Containerization:**
- ✅ Docker networking and service discovery
- ✅ Healthchecks and dependency ordering
- ✅ Multi-stage builds

**Observability:**
- ✅ Distributed tracing (OpenTelemetry, Tempo)
- ✅ Metrics instrumentation (Prometheus)
- ✅ Structured logging (Loki)
- ✅ SLI/SLO design

**CI/CD:**
- ✅ Jenkins pipeline design
- ✅ SSH-based deployment
- ✅ Smoke testing

**Security:**
- ✅ SSH key authentication
- ✅ Password auth disablement

### Phase 2 (Planned)

**Policy & Governance:**
- Policy-driven compliance (OPA, Rego)
- Policy testing and validation
- Policy exemption workflows

**Security Testing:**
- SAST and code quality gates (SonarQube)
- Dependency vulnerability scanning (Snyk)
- Container image scanning (Trivy)
- DAST automation (OWASP ZAP)

**Secrets Management:**
- Dynamic secrets issuance (Vault)
- Credential rotation
- Audit logging

**Artifact Management:**
- Immutable artifact storage (Artifactory)
- Image signing and provenance
- Promotion workflows

**Infrastructure Hardening:**
- Linux server hardening (fail2ban, UFW, auditd)
- Intrusion detection
- Kernel tuning

### Phase 3 (Planned)

**Kubernetes:**
- Cluster architecture (control plane, etcd, workers)
- Pod lifecycle and scheduling
- StatefulSets and persistent storage
- Helm chart design

**Service Mesh:**
- Istio architecture and Envoy sidecars
- mTLS certificate management
- Traffic routing (canary, blue-green)
- Chaos engineering

**GitOps:**
- Declarative infrastructure (ArgoCD)
- Git as source of truth
- Automated synchronization

**Automation:**
- Ansible playbooks and roles
- Infrastructure as code
- Day 2 operations automation

**Database Migration:**
- SQLite → PostgreSQL migration
- Transaction management
- Backup/restore strategies

### Phase 4 (Planned)

**AWS Fundamentals:**
- VPC networking and subnets
- IAM policies and roles
- Security service integration

**Managed Kubernetes:**
- EKS architecture
- Fargate serverless containers
- AWS storage integration (EBS, EFS)

**Managed Observability:**
- AWS Managed Prometheus (AMP)
- AWS Managed Grafana (AMG)
- AWS X-Ray distributed tracing
- CloudWatch Logs

**Microservices:**
- Service decomposition patterns
- API gateway design
- Event-driven architecture (EventBridge, SQS, SNS)

**FinOps:**
- Cloud cost management
- TCO analysis
- Right-sizing and optimization

---

## Success Criteria by Phase

### Phase 2 Success Criteria

**Policy Enforcement:**
- [ ] OPA policies enforce container security (no privileged, resource limits)
- [ ] Conftest integrated into Jenkins pipeline
- [ ] Policy violations block deployments

**Security Testing:**
- [ ] SonarQube SAST gates operational
- [ ] Snyk dependency scanning integrated
- [ ] Trivy container scanning integrated
- [ ] OWASP ZAP DAST smoke tests running post-deployment
- [ ] Zero critical vulnerabilities in production images

**Artifact & Secrets:**
- [ ] JFrog Artifactory storing all container images
- [ ] Image signing and provenance enabled
- [ ] Vault issuing 100% of dynamic credentials
- [ ] Zero static secrets in code or configs

**Server Hardening:**
- [ ] fail2ban active and banning brute-force attempts
- [ ] UFW firewall restricting to required ports only
- [ ] auditd logging system calls
- [ ] CIS benchmark Level 1 compliance

### Phase 3 Success Criteria

**Kubernetes Migration:**
- [ ] Multi-node cluster operational (3+ nodes)
- [ ] All Docker Compose services migrated to Kubernetes
- [ ] PostgreSQL StatefulSet with automated backups
- [ ] SQLite → PostgreSQL migration complete with zero data loss
- [ ] Helm charts created for all services

**Service Mesh:**
- [ ] Istio installed and Envoy sidecars injected
- [ ] mTLS enabled for all service-to-service traffic
- [ ] Canary deployment workflow operational
- [ ] Service mesh telemetry in Grafana dashboards

**GitOps & Automation:**
- [ ] ArgoCD managing 100% of application deployments
- [ ] Ansible playbooks automate cluster provisioning
- [ ] Automated smoke tests passing for all releases
- [ ] Ingress controller with HTTPS termination

**Observability:**
- [ ] Distributed tracing across all Kubernetes services
- [ ] Prometheus metrics from Istio
- [ ] Alert rules for cluster health
- [ ] Runbooks documented for common issues

### Phase 4 Success Criteria

**AWS Migration:**
- [ ] AWS VPC with segmented subnets operational
- [ ] VPN connectivity to on-prem lab established
- [ ] EKS cluster running all workloads
- [ ] Amazon RDS PostgreSQL with automated backups

**Managed Services:**
- [ ] AWS Managed Prometheus (AMP) receiving metrics
- [ ] AWS Managed Grafana (AMG) dashboards migrated
- [ ] AWS X-Ray tracing operational
- [ ] CloudWatch Logs aggregating all logs
- [ ] AWS Secrets Manager handling all secrets

**Modernization:**
- [ ] At least 3 services decomposed from monolith
- [ ] EventBridge/SQS/SNS handling async flows
- [ ] API Gateway operational with rate limiting

**FinOps:**
- [ ] TCO analysis comparing on-prem vs. AWS complete
- [ ] Daily cost dashboards operational
- [ ] Cloud costs within 20% of initial estimates
- [ ] Right-sizing recommendations implemented

---

## Risk Management

### Common Risks Across All Phases

#### Risk: Scope Creep

**Description:** Adding too many features or technologies beyond planned scope
**Likelihood:** High
**Impact:** Medium (delays, incomplete features)

**Mitigation:**
- Define clear success criteria per phase
- Resist temptation to add "just one more tool"
- Timebox exploration of new technologies
- Document "future enhancements" section instead of implementing immediately

#### Risk: Learning Curve Underestimation

**Description:** New technologies taking longer to learn than expected
**Likelihood:** High
**Impact:** Medium (timeline delays)

**Mitigation:**
- Allocate buffer time (20-30%) in timeline estimates
- Start with proof-of-concept before full implementation
- Use official documentation and tutorials
- Engage with community forums and Slack channels

#### Risk: Hardware/Resource Constraints

**Description:** Insufficient compute, storage, or network for advanced phases
**Likelihood:** Medium
**Impact:** High (blockers)

**Mitigation:**
- Plan resource requirements upfront for each phase
- Evaluate cloud alternatives if on-prem resources insufficient
- Optimize existing workloads before scaling
- Consider phased hardware upgrades

#### Risk: Documentation Lag

**Description:** Implementation outpacing documentation updates
**Likelihood:** High
**Impact:** Medium (knowledge loss)

**Mitigation:**
- Document as you build (not after)
- Create templates for architecture, design decisions, and runbooks
- Use code comments and README files liberally
- Schedule dedicated documentation sprints

### Phase-Specific Risks

#### Phase 2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Vault integration complexity | Medium | Medium | Reuse prior implementation, start simple |
| Policy authoring errors | High | Low | Test policies in non-prod first |
| Security scan false positives | High | Low | Tune scan rules, establish exemption process |

#### Phase 3 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data loss during PostgreSQL migration | Low | Critical | Multiple backups, validation scripts, test in dev |
| Kubernetes complexity overwhelm | High | Medium | Incremental adoption, one concept at a time |
| Service mesh performance overhead | Medium | Medium | Monitor latency, disable if unacceptable |
| Multi-node networking issues | Medium | High | Test in isolated environment, document troubleshooting |

#### Phase 4 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| AWS cost overruns | High | High | Budget alerts, daily cost dashboards, right-sizing |
| Vendor lock-in | Medium | Medium | Use open standards (OTel, K8s), document migration paths |
| Performance degradation in cloud | Medium | Medium | Extensive load testing, monitoring, rollback plan |
| Hybrid connectivity failures | Medium | High | Redundant VPN tunnels, test failover scenarios |

---

## Proof of Concept Foundation

### Why This Matters

This roadmap builds upon a **production-grade proof of concept**, not a toy project. The foundation established in Phase 1 demonstrates:

**Production Patterns:**
- Reverse proxy architecture (Nginx)
- Full observability (three pillars: traces, metrics, logs)
- SLI/SLO tracking (availability, latency, error rates)
- Automated deployment via CI/CD
- Healthchecks and graceful degradation

**Battle-Tested:**
- Every error encountered, debugged, and documented
- Comprehensive troubleshooting guides
- Source code audits for accuracy
- Real-world debugging experience

**Learning-Oriented:**
- Documentation exceeds 152,000 words
- Design decisions captured with rationale
- Journey narrative includes failures and breakthroughs
- Transferable skills to enterprise and cloud environments

### Maintaining the Proof of Concept Nature

As the project evolves through Phases 2-4, maintain these principles:

**1. Learn First, Optimize Later**
- Prioritize understanding over perfection
- Document trade-offs and alternatives
- Accept "good enough" for learning purposes

**2. Production-Inspired, Not Production-Required**
- Use production-grade tools and patterns
- But don't over-engineer for scale you don't need
- Focus on learning the architecture, not running at Google scale

**3. Iterative and Experimental**
- Phases can overlap or run in parallel
- Feel free to skip ahead if a technology excites you
- Return to earlier phases to refine

**4. Documentation is Part of the Product**
- Every phase must include comprehensive documentation
- Capture design decisions, not just implementation
- Write for future you (you will forget)

---

## Conclusion

This roadmap outlines a multi-year journey from on-premises Docker Compose to hybrid cloud Kubernetes. Each phase builds upon the last, introducing new technologies and patterns while maintaining the core philosophy:

**Learn what cloud abstractions hide by building without them first.**

The phases are structured but flexible. Adjust timelines, skip ahead, or iterate based on your learning goals and available time. The key is to maintain momentum, document as you go, and embrace failures as learning opportunities.

**Current Status:**
- ✅ Phase 1: Complete (October 2025)
- 🚧 Phase 2: Planning (Q1 2026)
- 📋 Phase 3: Planning (Q2-Q3 2026)
- 📋 Phase 4: Planning (Q4 2026+)

**Next Steps:**
1. Review Phase 2 deliverables
2. Allocate time for OPA/Rego learning
3. Provision resources for SonarQube and Artifactory
4. Begin policy library creation

---

**Related Documentation:**
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Current system architecture
- [DESIGN-DECISIONS.md](../DESIGN-DECISIONS.md) - Design rationale for Phase 1
- [JOURNEY.md](../JOURNEY.md) - The story of building Phase 1
- [Infrastructure Foundation](infrastructure.md) - KVM/libvirt virtualization
- [Observability Architecture](observability.md) - OpenTelemetry stack

---

**Created:** October 22, 2025
**Author:** Wally
**Version:** 1.0
**Status:** Living Document (will evolve with implementation)
