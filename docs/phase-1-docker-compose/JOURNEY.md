# From Theory to Practice: Building Production Observability on Bare Metal

## The Story of Transforming Cloud-Native Concepts into an On-Premises Reality

**Author:** Wally
**Date:** October 2025
**Reading Time:** 20 minutes
**Tags:** #DevSecOps #Observability #OpenTelemetry #OnPremises #SRE #Kubernetes #Jenkins

---

## Table of Contents

- [Prologue: The Vision](#prologue-the-vision)
- [Chapter 1: The On-Premises Foundation](#chapter-1-the-on-premises-foundation)
- [Chapter 2: The CI/CD Control Plane](#chapter-2-the-cicd-control-plane)
- [Chapter 3: The Observability Application](#chapter-3-the-observability-application)
- [Chapter 4: The Nginx Saga](#chapter-4-the-nginx-saga)
- [Chapter 5: The Observability Stack](#chapter-5-the-observability-stack)
- [Chapter 6: The Wins](#chapter-6-the-wins)
- [Chapter 7: The Roadmap](#chapter-7-the-roadmap)
- [Epilogue: Why This Matters](#epilogue-why-this-matters)
- [Conclusion: The Journey Continues](#conclusion-the-journey-continues)

---

## Prologue: The Vision

*"I want to understand how the big players do it. Not just read about it—actually build it."*

That thought kept me up at night. I'd read the Google SRE book. I'd bookmarked every Honeycomb.io blog post about observability. I'd watched conference talks about how Netflix debugs microservices with distributed tracing. But reading != understanding.

I needed to **build it myself**.

Not with managed services where the hard parts are abstracted away. Not with tutorials that gloss over the failures. I needed the full experience: the errors, the breakthroughs, the "why the hell isn't this working" moments that force you to truly understand the system.

So I set out to build a **production-grade observability stack** on my own hardware. This is that story.

---

## Chapter 1: The On-Premises Foundation

### Why Not Cloud?

Everyone's first question: *"Why not just use AWS/GCP/Azure?"*

Valid question. But here's the thing: I'm building my **On-Prem Domain**—a deliberate learning path focused on understanding infrastructure from the ground up before ascending to cloud abstractions.

**The Philosophy:**
- **Own the stack** (hypervisor → OS → containers → orchestration)
- **Learn by failing** (no black-box managed services hiding complexity)
- **Zero recurring costs** (one-time hardware investment, unlimited experimentation)
- **Hybrid future** (on-prem skills + cloud skills = complete engineer)

### The Virtualization Layer

I started with the foundation: **KVM/QEMU/libvirt** on Debian 13.

```
Physical Server
  └─ KVM Hypervisor (kernel-based virtualization)
      └─ libvirt (VM lifecycle management)
          └─ virt-manager (GUI for us mere mortals)
              └─ VMs running Debian 13
```

**Why KVM?**
- It's what powers OpenStack, oVirt, and RHEV (enterprise-grade)
- Hardware-accelerated virtualization (Intel VT-x)
- Scriptable via `virsh` (future Ansible automation)
- Free and open source

**First Challenge:** Understanding libvirt XML.

VMs aren't just "click, create, done." They're defined by XML manifests:

```xml
<domain type='kvm'>
  <name>observability-vm</name>
  <memory unit='GiB'>8</memory>
  <vcpu>4</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
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

This XML taught me about:
- **Virtual CPUs and topology** (sockets, cores, threads)
- **Storage backends** (qcow2 images, LVM volumes, NFS)
- **Virtual networking** (bridge, NAT, macvtap)

It's like Kubernetes manifests, but for VMs. My first taste of infrastructure as code.

### The Network Topology

Virtual networking was a mind-bender at first.

```
Physical NIC (enp0s31f6) → 192.168.1.x (home LAN)
    ↓
libvirt bridge (virbr0) → 192.168.122.0/24 (VM network)
    ↓
VM NIC (virtio) → 192.168.122.250 (observability app VM)
```

**Concepts I Internalized:**
- **NAT mode:** VMs can reach internet, but not directly accessible from LAN
- **Bridge mode:** VMs appear as physical devices on your LAN (can SSH from laptop)
- **DNS/DHCP:** libvirt's dnsmasq provides automatic IP assignment and name resolution

This networking knowledge became critical later when I debugged Docker container DNS issues.

---

## Chapter 2: The CI/CD Control Plane

### Security First: Hardening SSH Access

Before I even touched Jenkins, I needed to secure the foundation: **SSH access to my VMs**.

**The Problem:**
Fresh Debian VM with a `deploy` user account, no password set. Jenkins needs to SSH in to deploy containers, but I don't want password-based authentication—that's asking for brute-force attacks.

**The Goal:**
Key-only SSH authentication (industry best practice).

**The Journey:**

1. **Generate ED25519 key pair on host (`Maria`):**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_jenkins -C "jenkins-deployment-key"
   ```

   Why ED25519? Smaller keys, faster, more secure than RSA-2048.

2. **The Catch-22:**
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519_jenkins.pub deploy@192.168.122.250
   ```

   **Failed:** `ssh-copy-id` needs to *log in* to copy the key, but `deploy` has no password!

3. **Temporary Password (Walking Through Security Hardening):**
   ```bash
   # SSH as existing user
   ssh wally@192.168.122.250

   # Set temporary password for deploy
   sudo passwd deploy
   # (chose something short, will remove it in 2 minutes)
   ```

4. **Copy Key:**
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519_jenkins.pub deploy@192.168.122.250
   # Asks for password once, installs key to ~/.ssh/authorized_keys
   ```

5. **Test Key-Based Login:**
   ```bash
   ssh -i ~/.ssh/id_ed25519_jenkins deploy@192.168.122.250 hostname
   # Returns: debian-VM
   # No password prompt ✅
   ```

6. **Harden SSH (Remove Password Authentication):**
   ```bash
   # Lock the password (can't be used even if someone tries)
   sudo passwd -l deploy

   # Edit SSH daemon config
   sudo vi /etc/ssh/sshd_config

   # Ensure these lines:
   PubkeyAuthentication yes
   PasswordAuthentication no

   # Restart SSH daemon
   sudo systemctl restart ssh
   ```

7. **Final Test:**
   ```bash
   ssh deploy@192.168.122.250 hostname
   # Works with key, fails with password ✅
   ```

**Why This Matters:**

I didn't just copy-paste the public key to the VM. I **walked through the entire hardening process** because:
- **Production Mindset:** This is how you secure real servers (no shortcuts)
- **Understanding Over Convenience:** Each step taught me *why* key-only auth is secure
- **Muscle Memory:** Next time I provision a server, this is automatic

**Lesson Learned:**
Security isn't a checkbox—it's a habit. Even in a lab environment, practice the same rigor you'd use in production.

**Resource for Future Hardening:**
Bookmarked for Phase 2: [How To Secure A Linux Server](https://github.com/imthenachoman/How-To-Secure-A-Linux-Server)
- Comprehensive guide covering: fail2ban, firewall rules, kernel hardening, audit logging
- Will implement incremental hardening as the project evolves
- Security isn't one-and-done; it's iterative

**What This Unlocked:**
Now Jenkins can SSH into the VM without passwords, enabling:
- Automated deployments (no manual intervention)
- Pipeline-driven infrastructure changes
- Secure remote execution (brute-force attacks eliminated)

This simple hardening exercise taught me more about SSH than years of "just using it." Understanding *why* password auth is dangerous (even in a lab) builds the discipline needed for production environments.

---

### Jenkins: The Orchestration Brain

Most people start with "hello world." I started with **containerized Jenkins** because that's how I wanted to deploy everything: automated, repeatable, version-controlled.

**The Jenkins Stack:**

```
jenkins-net (Docker bridge network)
  ├─ Jenkins Controller (jenkins/jenkins:lts-jdk17)
  │    • Port 8080: Web UI
  │    • Port 50000: JNLP agent connection
  │    • Volume: jenkins_home (persistent state)
  │
  ├─ Docker Agent (custom image: jq + docker + rsync)
  │    • Executes pipeline stages
  │    • Connects to controller via JNLP
  │
  └─ HashiCorp Vault (vault:latest - paused for this phase)
       • Port 8200: Secrets API
       • Volume: vault_server_volume
```

**Key Insight:** Jenkins agents need **tools**, not just Java. My custom agent image included:
- `docker` (for building images)
- `rsync` (for file synchronization to VMs)
- `jq` (for parsing JSON responses)
- SSH client (for remote deployment)

This taught me: **Agents are cattle, not pets.** Build them as container images, destroy and recreate at will.

### The Deployment Pipeline

Here's where theory met practice **hard**.

**The Problem:**
Jenkins running on one VM needs to deploy Docker Compose stack to *another* VM (192.168.122.250), but the Compose file has **bind mounts**:

```yaml
services:
  frontend:
    volumes:
      - ./frontend/default.conf:/etc/nginx/conf.d/default.conf
```

That `./frontend/default.conf` must exist on the **target VM's filesystem**, not Jenkins workspace.

**Failed Attempt #1: Docker Context**

```groovy
docker context create vm-lab --docker "host=ssh://deploy@192.168.122.250"
docker --context vm-lab compose up -d
```

**Result:** Container failed to start. File not found.

**Why:** Docker context tells Docker *where* to run commands, but doesn't sync files. The `./frontend/default.conf` path is relative to where `docker compose` runs—which is the remote VM. File doesn't exist there.

**The Solution: rsync + SSH**

```groovy
stage('Sync repo to VM') {
  sshagent(credentials: ['vm-ssh']) {
    sh 'rsync -az --delete ./ deploy@192.168.122.250:/home/deploy/lab/app/'
  }
}

stage('Deploy to VM') {
  sshagent(credentials: ['vm-ssh']) {
    sh '''
      ssh deploy@192.168.122.250 "
        cd /home/deploy/lab/app &&
        docker compose -p lab up -d --build
      "
    '''
  }
}
```

**Lesson Learned:**
- **Bind mounts require files on the daemon's host.**
- **rsync is your friend** for keeping remote directories in sync.
- **Docker context is great** for commands, but doesn't handle file dependencies.

This was my first "oh shit" moment where I realized cloud-native tools assume **one thing**: your files are already where they need to be. In multi-machine scenarios, you have to solve that yourself.

---

## Chapter 3: The Observability Application

### The Architecture

I built a simple **task manager app** (think Todoist, but way dumber). The app isn't the point—the **observability** is.

```
Browser (http://192.168.122.250:8080)
    ↓
Nginx (frontend container)
    ↓ Reverse proxy /api/* → backend:5000
Flask Backend (Python 3.11)
    ↓
SQLite Database (/app/data/tasks.db)
```

**Three-Tier Classic:** Frontend, backend, database. Perfect for demonstrating distributed tracing.

### Battle #1: "Working Outside of Application Context"

My first Flask crash:

```python
# app.py
app = Flask(__name__)
db = SQLAlchemy(app)

SQLAlchemyInstrumentor().instrument(engine=db.engine)  # ← BOOM
```

```
RuntimeError: Working outside of application context.
```

**WTF Does That Mean?**

After an hour of Googling and reading Flask source code:

**The Problem:**
- Python imports `app.py` top-to-bottom
- `db = SQLAlchemy(app)` creates the SQLAlchemy object
- `db.engine` doesn't exist until **inside** Flask's application context
- My code tried to access `db.engine` during module import (before context exists)

**The Fix:**

```python
# Define app and db
app = Flask(__name__)
db = SQLAlchemy(app)

# Later... wrap in context
with app.app_context():
    SQLAlchemyInstrumentor().instrument(engine=db.engine)  # Now db.engine exists
    db.create_all()  # Create tables
```

**Lesson:** Frameworks have **lifecycles**. Understanding *when* objects become available is 50% of debugging framework errors.

### Battle #2: The Disappearing Database

Next error:

```
sqlite3.OperationalError: unable to open database file
```

But I **created** the database! I could see `tasks.db` in my project directory!

**The Problem:**

```python
SQLALCHEMY_DATABASE_URI = 'sqlite:///data/tasks.db'  # 3 slashes = relative path
```

In a Docker container, "relative path" is relative to the container's working directory. Which might be `/`, `/app`, or `/usr/src/app` depending on the `WORKDIR` in the Dockerfile.

**The Fix:**

```python
import os
os.makedirs('/app/data', exist_ok=True)  # Ensure directory exists
SQLALCHEMY_DATABASE_URI = 'sqlite:////app/data/tasks.db'  # 4 slashes = absolute path
```

Four slashes! That fourth slash means "absolute path starting at root."

**Lesson:** In containers, **always use absolute paths**. Relative paths are asking for "works on my machine" syndrome.

### Battle #3: The Phantom Code Cache

I fixed the database path. I rebuilt the container:

```bash
docker compose up -d backend
```

I checked the logs:

```
RuntimeError: Working outside of application context.
```

**WAIT. I JUST FIXED THAT.**

I opened `app.py`. The fix was there. I printed the file to make sure I wasn't going insane. The code was correct.

But the container was running the **old, broken code**.

**Docker Layer Caching.**

Docker caches image layers. If the Dockerfile hasn't changed, it reuses the cached image—even if the files *inside* the Dockerfile have changed.

```bash
docker compose build --no-cache backend  # The nuclear option
docker compose up -d backend
```

**NOW** it worked.

**Lesson:** When debugging, don't assume "rebuild" means "rebuild everything." Sometimes you need `--no-cache` to force Docker to forget its cache.

---

## Chapter 4: The Nginx Saga

### The 502 Bad Gateway

The frontend container started. The backend container started. Both looked healthy:

```bash
docker compose ps
# backend: Up (healthy)
# frontend: Up
```

I opened the browser: `http://192.168.122.250:8080`

**502 Bad Gateway.**

I checked the Nginx logs:

```
[error] backend could not be resolved (3: Host not found)
```

**WHAT?!** Both containers are on the same Docker network (`otel-network`). They should resolve each other via DNS.

### The Root Cause: Race Condition

Here's what was happening:

1. `docker compose up -d` starts all containers **in parallel** (unless depends_on is set)
2. Frontend (Nginx) starts first
3. Nginx resolves `backend` via Docker DNS → **host not found** (backend not started yet)
4. Nginx caches this "not found" result
5. Backend starts 2 seconds later
6. Docker DNS now has entry: `backend → 172.18.0.7`
7. But Nginx still has cached "not found"
8. Every request: **502 Bad Gateway**

**First Fix: Startup Ordering**

```yaml
services:
  backend:
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/metrics')"]
      interval: 5s
      retries: 3

  frontend:
    depends_on:
      backend:
        condition: service_healthy  # Wait for healthcheck to pass
```

This ensured frontend wouldn't start until backend was **actually ready**, not just "started."

But there was still a problem...

### The Cached IP Problem

Even with startup ordering, if backend **restarted** after frontend was running, Nginx would still cache the old IP.

**Example:**
1. Backend starts: `backend → 172.18.0.7`
2. Nginx resolves and caches: `proxy_pass http://172.18.0.7:5000`
3. Backend crashes and restarts
4. Docker assigns new IP: `backend → 172.18.0.9`
5. Nginx still tries old IP: `172.18.0.7` → **502**

**The Fix: Dynamic DNS Resolution**

```nginx
location /api/ {
    resolver 127.0.0.11 ipv6=off valid=30s;  # Docker's DNS server
    set $backend_upstream http://backend:5000;  # Variable forces re-resolution
    proxy_pass $backend_upstream;  # Use variable, not literal URL
}
```

**Why This Works:**
- `resolver 127.0.0.11`: Tells Nginx to use Docker's embedded DNS
- `set $backend_upstream`: **Variables are re-evaluated on every request**
- `valid=30s`: Cache DNS result for 30 seconds (balance performance vs. freshness)

**Lesson:** Static configuration is fast but fragile. Dynamic configuration is slightly slower but resilient. In distributed systems, **resilience > speed**.

---

## Chapter 5: The Observability Stack

### The Three Pillars

I implemented full observability: **traces, metrics, logs**.

```
Application Code
  ├─ TRACES (OpenTelemetry)
  │    • FlaskInstrumentor: HTTP request/response spans
  │    • SQLAlchemyInstrumentor: Database query spans
  │    • Export: OTLP → Collector → Tempo
  │
  ├─ METRICS (Prometheus Client)
  │    • http_requests_total (Counter)
  │    • http_request_duration_seconds (Histogram)
  │    • db_query_duration_seconds (Histogram)
  │    • Export: /metrics endpoint → Prometheus scrape
  │
  └─ LOGS (OpenTelemetry)
       • Structured JSON logging
       • Automatic trace_id injection
       • Export: OTLP → Collector → Loki
```

### Battle #4: The Metric Duplication Mystery

After setting up Grafana dashboards, I noticed something weird:

```promql
sum(http_requests_total)
```

This showed **2x** the expected request count.

I queried Prometheus directly:

```promql
count by (__name__, job) (http_requests_total)
```

Result:

```
http_requests_total{job="flask-backend"}  = 1
http_requests_total{job="otel-collector-prometheus-exporter"} = 1
```

**I had TWO sources for the same metric!**

**Root Cause:**

I had both:
1. **Prometheus client** in Flask (`prometheus_client.Counter`)
2. **OTel SDK metrics** in Flask (`meter.create_counter`)

Both exported `http_requests_total`, but with different `job` labels:
- Prometheus client → exposed at `/metrics` → scraped by Prometheus (`job="flask-backend"`)
- OTel SDK → sent via OTLP → collector → exported to Prometheus (`job="otel-collector-prometheus-exporter"`)

**The Solution: Pick One**

I evaluated three options:

**Option A:** Remove OTel metrics, keep Prometheus client
**Option B:** Remove Prometheus client, keep OTel metrics
**Option C:** Rename metrics to avoid collision

I chose **Option A** for one critical reason:

> **Traces are the real value of OpenTelemetry.**

Metrics (counters, histograms) are simple. They don't need the distributed context that OTel provides. Prometheus client is *purpose-built* for application metrics.

But **traces**? That's where OTel shines. Following a request from browser → backend → database with parent-child span relationships? That's magical.

So I removed the OTel metric pipeline and kept:
- **OTel for traces and logs** (distributed context)
- **Prometheus client for metrics** (simple, efficient, no duplication)

**Lesson:** Not every telemetry signal needs the same pipeline. Choose tools based on **what each signal needs**, not "one tool for everything."

### Battle #5: The Disappearing Metrics Dropdown

After successfully deploying the stack, I encountered one of the most deceptive bugs I've ever debugged. Grafana's metrics dropdown in Builder mode showed **"No options found"** despite everything appearing healthy.

**The Symptom:**
- Prometheus: ✅ Healthy, reporting 1000+ metrics
- Grafana Code mode: ✅ Works (typing `up` returns results)
- Grafana Builder mode metrics dropdown: ❌ Empty

**Initial Hypothesis: `httpMethod: POST` Problem**

My `datasources.yml` had this configuration:

```yaml
datasources:
  - name: Prometheus
    jsonData:
      httpMethod: POST  # ← Suspicious!
```

I tested Prometheus's label API directly:

```bash
# GET request - should work
curl "http://prometheus:9090/api/v1/label/__name__/values"
# Response: {"status":"success","data":[...1047 metrics...]}

# POST request - what Grafana might be doing?
curl -X POST "http://prometheus:9090/api/v1/label/__name__/values"
# Response: HTTP 405 Method Not Allowed
```

**Aha!** Prometheus's label API only accepts GET requests. POST returns 405.

But wait—testing through Grafana's datasource proxy revealed something else:

```bash
curl -X POST "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values"
# Response: HTTP 403 Forbidden
# {"message":"non allow-listed POSTs not allowed on proxied Prometheus datasource"}
```

**Grafana has a security policy** that blocks POST requests to Prometheus label endpoints! This made sense—I removed `httpMethod: POST` from `datasources.yml`, restarted Grafana, and waited for metrics to appear.

**Still empty.**

**The Real Investigation: Browser DevTools**

Nothing in the logs explained it. The API endpoints worked. So I opened the browser.

**F12 → Network tab → Click metrics dropdown**

There it was—the actual request Grafana made:

```http
GET /api/datasources/uid/prometheus/resources/api/v1/label/__name__/values?start=1761112800&end=1761134400
Status: 200 OK
Response: {"status":"success","data":[]}
```

**HTTP 200!** The request succeeded. But `"data":[]`—an empty array!

I stared at this for a moment. The API worked. Prometheus had metrics. But the response was empty.

Then I looked at those timestamps:
- `start=1761112800` → **October 22, 06:00 UTC**
- `end=1761134400` → **October 22, 12:00 UTC**

I checked when I'd restarted the containers:

```bash
docker inspect prometheus | jq '.[0].State.StartedAt'
# "2025-10-22T12:45:00Z"  ← 10 minutes ago
```

**The containers had been running for 10 minutes.** But Grafana was requesting metrics from **6 hours ago**.

I looked at the Grafana UI—top-right corner showed **"Last 6 hours"** as the selected time range.

**The Real Problem: Time Range Mismatch**

Prometheus's `/api/v1/label/__name__/values` endpoint is **time-range aware**. When Grafana includes `start` and `end` parameters, Prometheus only returns metrics that have data in that time window.

My fresh deployment had:
- Prometheus running for 10 minutes
- Data from the last 10 minutes only
- Grafana requesting metrics from 6 hours ago → **no data exists**

**The Fix:**

Changed the time range dropdown from "Last 6 hours" → **"Last 5 minutes"**.

The metrics dropdown **immediately** populated with 1047 metrics.

**Lessons Learned:**

**1. HTTP 200 with Empty Data Isn't Always an Error**

```json
{"status":"success","data":[]}
```

This doesn't mean the API is broken. It means "your query succeeded, but no results match your criteria."

**2. Check What the Browser Actually Requests**

Server logs showed success. API tests showed success. But only **Browser DevTools** revealed the mismatch between what the UI showed ("Last 6 hours") and what data actually existed (10 minutes).

**3. Time-Range Awareness in APIs**

Prometheus's label API doesn't return "all known metrics." It returns "metrics with data in the specified time range." This is by design—it prevents enormous responses on large deployments.

**4. The Debugging Hierarchy**

I debugged this bottom-up:
```
Does Prometheus have data? ✅ Yes
Does the API endpoint work? ✅ Yes
Does Grafana's proxy work? ✅ Yes
Does the browser request succeed? ✅ Yes... wait
```

The answer was at the **top** (UI time range), but I started at the **bottom** (backend data).

**Better approach:** Start with what the user sees (Browser DevTools) before diving into backend debugging.

**5. Don't Assume Configuration Issues**

I spent hours chasing `httpMethod: POST` as the culprit. The actual problem? The application worked perfectly—it was returning exactly what was requested. The request parameters were just wrong for the current state of the system.

**The Meta-Lesson:**

> "The application isn't broken. The application is doing exactly what you told it to do. You're just not aware of what you told it to do."

Browser DevTools bridges that gap. It shows you **what you actually asked for** vs. **what you think you asked for**.

This battle taught me: **Always check the browser before blaming the backend.**

**For detailed troubleshooting steps and complete resolution process, see:** [Metrics Dropdown Troubleshooting Guide](troubleshooting/metrics-dropdown-issue.md)

---

## Chapter 6: The Wins

After weeks of debugging, refactoring, and documenting, I had a **production-grade observability stack**:

### What I Built

**Infrastructure:**
- KVM/libvirt virtualization on Debian 13 (simulates on-prem data center)
- Containerized Jenkins with Docker agents (CI/CD control plane)
- Secrets managed manually in this iteration (Vault integration returns later)
- SSH-based deployment pipeline (rsync + docker compose)

**Application:**
- Flask backend with SQLAlchemy ORM
- Nginx reverse proxy (dynamic DNS resolution)
- Full OpenTelemetry instrumentation
  - Automatic HTTP tracing (FlaskInstrumentor)
  - Automatic database tracing (SQLAlchemyInstrumentor)
  - Structured JSON logging with trace correlation

**Observability Stack:**
- OpenTelemetry Collector (telemetry hub)
- Grafana Tempo (distributed tracing)
- Prometheus (metrics storage and querying)
- Loki (log aggregation)
- Grafana (unified visualization)

**Pre-built Dashboards:**
- SLI/SLO Dashboard (service availability, P95 latency, error rates)
- End-to-End Tracing Dashboard (service dependency maps, trace timelines)

### What I Learned

**Technical Skills:**
- **Virtualization:** libvirt XML, virsh CLI, storage pools, virtual networks
- **CI/CD:** Jenkins pipelines, Docker agents, SSH deployment, rsync
- **Containerization:** Docker networking, healthchecks, bind mounts, multi-stage builds
- **Observability:** Distributed tracing, structured logging, SLI/SLO implementation
- **Nginx:** Reverse proxy configuration, dynamic DNS resolution, upstream variables
- **Flask:** Application context lifecycle, SQLAlchemy event listeners, middleware patterns
- **Prometheus:** PromQL queries, histogram quantiles, remote write, scrape configs
- **OpenTelemetry:** OTLP protocol, collector processors, resource attributes, trace context propagation

**Meta-Skills:**
- **Debugging Distributed Systems:** Follow data flow across network boundaries
- **Reading Error Messages:** "Working outside of application context" → understand framework lifecycles
- **Browser DevTools for UI Debugging:** Network tab reveals actual API requests/responses when UI appears broken (time ranges, parameters, empty vs. failed responses)
- **When to Restart vs. Rebuild:** Docker caching, DNS state, network cleanup (`docker compose down` vs `restart`)
- **Documentation as Learning:** Writing this journey solidified my understanding
- **Fail Fast and Iterate:** Every error taught something; perfection is the enemy of progress

---

## Chapter 7: The Roadmap

This isn't the end—it's **milestone 1** in a multi-year learning journey.

### Phase 2: Policy as Code & Secure Delivery (Planned)

**Policy as Code:**
- Deepen Rego expertise and build reusable policy libraries
- Enforce container guardrails with Conftest in Jenkins (no privileged pods, resource limits, blocked hardcoded secrets)
- Capture policy violations as structured pipeline output

**Shift-Left Security:**
- SonarQube for SAST gates
- Snyk for dependency scanning (Python + JavaScript)
- Trivy for container images
- OWASP ZAP automation for lightweight DAST

**Artifact & Secrets Management:**
- Stand up JFrog Artifactory for immutable artifacts with provenance
- Reintroduce Vault to mint short-lived credentials for the pipeline
- Expand pre-commit hooks (`black`, `flake8`, `prettier`, `detect-secrets`)

**Operational Hardening:**
- Implement fail2ban, UFW, auditd, and MFA for privileged access
- Add branch protection and chatops notifications on gate failures

### Phase 3: Kubernetes Refactoring & Platform Automation (Planned)

**Why Kubernetes Now:**
- Multi-node orchestration and horizontal scalability
- Service mesh adoption (Istio with Envoy) for uniform telemetry and mTLS
- Align with industry-standard platform operations

**Migration Path:**
1. Convert `docker-compose.yml` to Kubernetes manifests (Kompose as a starting point)
2. Package workloads into Helm charts with reusable values files
3. Replace SQLite with a PostgreSQL StatefulSet and PersistentVolumes
4. Install Nginx Ingress Controller and enable HTTPS termination
5. Automate cluster provisioning via kubeadm + Ansible playbooks

**Automation & GitOps:**
- Introduce ArgoCD for declarative deployments
- Run smoke/integration tests per Helm release
- Capture platform runbooks as Ansible roles

### Phase 4: Cloud-Native AWS Migration (Planned)

**Landing Zone & Connectivity:**
- Build an AWS VPC with segmented subnets, IAM guardrails, and GuardDuty
- Establish Site-to-Site VPN (and eventually Direct Connect) from the lab

**Container Platforms:**
- Lift Kubernetes workloads to Amazon EKS with managed node groups and Fargate
- Evaluate Amazon ECS/Fargate for select stateless services
- Swap Kubernetes storage classes for AWS-native equivalents (EBS, EFS)

**Managed Observability & Secrets:**
- Replace self-hosted Prometheus/Grafana/Tempo/Loki with AWS Managed Prometheus, Managed Grafana, X-Ray, and CloudWatch Logs
- Move secrets/configuration into AWS Secrets Manager and Parameter Store
- Stream pipeline events into AWS services for centralized auditing

**Modernization Loop:**
- Decompose the application strategically (task-service, auth-service, notification-service)
- Introduce EventBridge/SQS/SNS to decouple asynchronous flows
- Track cost and performance deltas with FinOps dashboards

---

## Epilogue: Why This Matters

### The On-Prem Domain Philosophy

Cloud is amazing. Serverless, managed databases, auto-scaling—it's all incredible.

But here's the thing: **Cloud abstractions hide complexity.** You don't learn networking if VPCs are pre-configured. You don't learn storage if RDS handles backups. You don't learn orchestration if EKS manages your control plane.

The **On-Prem Domain** is about understanding those abstractions **before** relying on them.

**The Progression:**
1. **Build on bare metal/VMs** (understand the foundations)
2. **Orchestrate with tools** (Docker, Kubernetes, Ansible)
3. **Migrate to cloud** (appreciate what managed services solve)
4. **Operate hybrid** (best of both worlds)

### Skills That Transfer

Everything I learned in this project applies directly to:

**Enterprise On-Prem:**
- VMware vSphere/ESXi (same hypervisor concepts as KVM)
- On-prem Kubernetes (OpenShift, Rancher, Tanzu)
- Data center operations (networking, storage, compute)

**Cloud:**
- AWS ECS/EKS (container orchestration)
- GCP GKE (managed Kubernetes)
- Azure AKS (same K8s primitives)

**DevSecOps:**
- CI/CD pipelines (Jenkins, GitLab CI, GitHub Actions)
- Security scanning (SAST, DAST, container scanning)
- Policy as code (OPA, Sentinel)

**Observability:**
- Datadog, New Relic, Honeycomb (same three pillars: traces, metrics, logs)
- AWS X-Ray, GCP Cloud Trace (distributed tracing)
- ELK/EFK stacks (log aggregation)

### The Meta-Lesson

**You don't learn by watching tutorials. You learn by building and breaking.**

Every 502 error was a lesson in networking. Every "database not found" taught me about filesystems and containers. Every RuntimeError forced me to understand framework lifecycles.

The observability stack I built isn't special because it's complex—it's special because **I debugged every error myself**.

That's the difference between *knowing about* distributed tracing and *understanding* how traces flow from browser → backend → database → collector → Tempo → Grafana.

---

## Conclusion: The Journey Continues

This observability lab is **milestone 1** in a multi-year journey to become a complete infrastructure engineer.

**What I've Accomplished:**
- ✅ Simulated on-prem environment (KVM/libvirt virtualization)
- ✅ Containerized CI/CD pipeline (Jenkins + Docker agents)
- ✅ Production-grade observability (traces, metrics, logs)
- ✅ Automated deployment (SSH + rsync + docker compose)
- ✅ Comprehensive documentation (architecture, design decisions, this journey)

**What's Next:**
- Phase 2: Policy as code & secure delivery (OPA, Vault, SonarQube/Snyk/Trivy, Artifactory)
- Phase 3: Kubernetes refactoring & automation (Helm, ArgoCD, Istio/Envoy, Ansible)
- Phase 4: Cloud-native AWS migration (ECS/EKS iteration, managed telemetry, EventBridge/SQS)

**Why Share This?**

If you're reading this and feeling overwhelmed by "how the big players do it," I've been there.

Start small. Build something. Break it. Fix it. Document it.

Every senior engineer was once a junior who refused to give up after the 20th error message.

Welcome to the journey.

---

**Connect With Me:**
- GitHub: [illusivegit](https://github.com/illusivegit/Opentelemetry_Observability_Lab)
- Email: (see GitHub profile)

**Want to Try This Yourself?**
- Clone the repo: `git clone https://github.com/illusivegit/Opentelemetry_Observability_Lab.git`
- Read: `ARCHITECTURE.md` (system design)
- Read: `DESIGN-DECISIONS.md` (why choices were made)
- Deploy: `docs/phase-1-docker-compose/VERIFICATION-GUIDE.md` (deployment verification and CI/CD testing)

**Feedback Welcome:**
Found errors? Have questions? Open an issue or PR. This is a learning project—collaboration makes it better.

---

**Final Thought:**

> "Theory is when you know everything but nothing works. Practice is when everything works but no one knows why. In this project, I combined theory and practice—now I know **why** everything works."
>
> — Inspired by Albert Einstein (adapted)

**Happy Building.**

*— Wally, October 2025*

---

**Phase 1 Documentation Set v1.0** | Last Reviewed: October 22, 2025
