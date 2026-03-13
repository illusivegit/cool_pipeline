# Workflow Context — Docker CI/CD Observability Lab

> **Purpose:** Give this file to an LLM when you need to make architectural changes and run end-to-end testing. It contains everything needed to understand the environment, avoid known pitfalls, and execute a full pipeline run.
>
> **Usage:** "Read `workflow-context-*.md` in Docker-CICD/, then [describe the change]."

---

## 1. Environment Topology

```
Host (Debian 13, 192.168.122.1 from VM)
├── Jenkins controller    (container, :8080, :50000)
├── Jenkins agent1        (container, jenkins-network, image: jenkins-inbound-agent1)
├── SonarQube             (container, :9000)
├── Vault                 (container, :8200)
│
├── Docker Hub            (bleeng089/cool_images, remote registry)
│
└── VM "debian13" (KVM/libvirt, 192.168.122.230)
    ├── SSH: ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230
    ├── Docker daemon (authenticated to Docker Hub)
    ├── Repo clone: /home/jenkins/lab/app
    ├── Prod stack: docker compose -p lab (default ports)
    └── Test stack: docker compose -p lab-test (offset ports, test- prefixed containers)
```

**Network path:** Host ↔ VM via libvirt NAT bridge (`virbr0`). Host is `192.168.122.1` from VM perspective. VM is `192.168.122.230` from host.

---

## 2. Pre-flight Checklist

Run these before any pipeline execution or infrastructure change.

### 2.1 Local Docker state

```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

**Expect:** `jenkins-controller`, `jenkins-agent1`, `sonarqube`, `vault-server` — all running.

### 2.2 VM Docker state

```bash
ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230 "docker ps -a"
```

**Clean stale containers before a fresh pipeline run:**
```bash
ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230 "
  docker ps -a -q | xargs -r docker rm -f 2>/dev/null || true
  docker volume prune -f 2>/dev/null || true
"
```

### 2.3 VM Docker Hub authentication

The `jenkins` user on the VM must be logged in to Docker Hub to push/pull images.
```bash
ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230 \
  "cat ~/.docker/config.json 2>/dev/null && echo 'Auth OK' || echo 'NO AUTH'"
```

If missing — copy from root's config via QEMU guest agent (jenkins has no sudo):
```bash
# Read root's config
HANDLE=$(virsh -c qemu:///system qemu-agent-command debian13 \
  '{"execute":"guest-file-open","arguments":{"path":"/root/.docker/config.json","mode":"r"}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['return'])")
ROOT_CONFIG=$(virsh -c qemu:///system qemu-agent-command debian13 \
  "{\"execute\":\"guest-file-read\",\"arguments\":{\"handle\":${HANDLE},\"count\":4096}}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['return']['buf-b64'])")
virsh -c qemu:///system qemu-agent-command debian13 \
  "{\"execute\":\"guest-file-close\",\"arguments\":{\"handle\":${HANDLE}}}"

# Create jenkins .docker dir
virsh -c qemu:///system qemu-agent-command debian13 \
  '{"execute":"guest-exec","arguments":{"path":"/usr/bin/mkdir","arg":["-p","/home/jenkins/.docker"]}}'

# Write config
HANDLE=$(virsh -c qemu:///system qemu-agent-command debian13 \
  '{"execute":"guest-file-open","arguments":{"path":"/home/jenkins/.docker/config.json","mode":"w"}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['return'])")
virsh -c qemu:///system qemu-agent-command debian13 \
  "{\"execute\":\"guest-file-write\",\"arguments\":{\"handle\":${HANDLE},\"buf-b64\":\"${ROOT_CONFIG}\"}}"
virsh -c qemu:///system qemu-agent-command debian13 \
  "{\"execute\":\"guest-file-close\",\"arguments\":{\"handle\":${HANDLE}}}"

# Set ownership
virsh -c qemu:///system qemu-agent-command debian13 \
  '{"execute":"guest-exec","arguments":{"path":"/usr/bin/chown","arg":["-R","jenkins:jenkins","/home/jenkins/.docker"]}}'
```

### 2.4 Vault secret_id

Secret IDs can expire. Always verify or regenerate before a pipeline run.

```bash
# Check current Vault token works
export VAULT_TOKEN="<root-token>"  # Get from: vault print-token
curl -sf http://localhost:8200/v1/auth/token/lookup-self \
  -H "X-Vault-Token: $VAULT_TOKEN" | python3 -c "import sys,json; print('OK')" && echo "Token valid"

# Role ID (stable, does not change):
# 8673acd8-eb1b-9643-256e-2ff198a62fce

# Generate new secret_id:
NEW_SECRET=$(curl -sf --request POST \
  http://localhost:8200/v1/auth/approle/role/lab/secret-id \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['secret_id'])")
echo "New secret_id: $NEW_SECRET"

# Verify login:
curl -sf --request POST \
  --data "{\"role_id\":\"8673acd8-eb1b-9643-256e-2ff198a62fce\",\"secret_id\":\"$NEW_SECRET\"}" \
  http://localhost:8200/v1/auth/approle/login \
  | python3 -c "import sys,json; print('Login OK' if json.load(sys.stdin).get('auth') else 'FAILED')"
```

Then update the Jenkins credential — see section 4.2.

---

## 3. Known Gotchas

These are non-obvious behaviors that have caused pipeline failures in the past.

| Gotcha | What happens | Fix |
|---|---|---|
| **Jenkins CPS config.xml bug** | `POST /job/<name>/config.xml` returns HTTP 500 for Pipeline (CPS) flow definitions | Delete job via `doDelete`, recreate via `createItem` (see 4.3) |
| **Jenkins CSRF cookie** | Crumb without session cookie → 403 | Always use `-c $COOKIE_JAR` on crumb request, `-b $COOKIE_JAR` on all subsequent requests |
| **`docker restart` doesn't pick up new image** | Container keeps old image layers | Must `docker stop && docker rm`, then `docker run` with new image |
| **Tempo resource vs span indexing** | `{resource.service.name=...}` returns results before `{name=...}` on cold start | Poll for the exact span-level query the test uses, not resource-level |
| **Health check traffic pollutes metrics** | Pipeline readiness loop populates `http_requests_total` before test traffic | Poll for `db_query_duration_seconds_count` (only generated by test API calls) |
| **ShellCheck SC1091 in CI** | `source` paths can't be followed in agent workspace → exit code 1 | Use `-S warning` to ignore info-level findings |
| **Docker Compose port merging** | Override files ADD ports, not REPLACE | Use env var substitution in base file (`${VAR:-default}`), not overlay ports |
| **SonarQube Scanner 8.x needs Node.js** | Bundles a JS analysis sensor that fails fatally without `node` | Agent Dockerfile includes `nodejs` |

---

## 4. Common Operations

### 4.1 Trigger a Pipeline Build

```bash
COOKIE_JAR=$(mktemp)
CRUMB=$(curl -sf -u $JENKINS_USER:$JENKINS_PASS -c "$COOKIE_JAR" \
  'http://localhost:8080/crumbIssuer/api/json' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])")

# Full mode (normal CI/CD):
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=full"

# Rollback-safe (test then promote):
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=rollback-safe&DEPLOY_TAG=<sha>"

# Rollback-fast (skip testing):
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=rollback-fast&DEPLOY_TAG=<sha>"
```

### 4.2 Update Jenkins Credentials

```bash
COOKIE_JAR=$(mktemp)
CRUMB=$(curl -sf -u $JENKINS_USER:$JENKINS_PASS -c "$COOKIE_JAR" \
  'http://localhost:8080/crumbIssuer/api/json' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])")

# Delete old credential
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  "http://localhost:8080/credentials/store/system/domain/_/credential/<CRED-ID>/doDelete"

# Create new credential (Secret Text)
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  -H "Content-Type:application/xml" \
  -d '<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
        <scope>GLOBAL</scope>
        <id><CRED-ID></id>
        <description>Description</description>
        <secret><VALUE></secret>
      </org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>' \
  "http://localhost:8080/credentials/store/system/domain/_/createCredentials"

# Verify
curl -sf -u $JENKINS_USER:$JENKINS_PASS \
  "http://localhost:8080/credentials/store/system/domain/_/api/json?depth=1" \
  | python3 -c "import sys,json; [print(f'  {c[\"id\"]}') for c in json.load(sys.stdin)['credentials']]"
```

**Current credentials:** `vm-ssh` (SSH key), `vault-role-id` (secret text), `vault-secret-id` (secret text)

### 4.3 Delete and Recreate Jenkins Job

```bash
# Save current config
curl -sf -u $JENKINS_USER:$JENKINS_PASS \
  "http://localhost:8080/job/Pipeline-v2-Test/config.xml" > /tmp/config.xml

# Modify if needed (e.g., change branch or scriptPath)
# sed -i 's|old|new|' /tmp/config.xml

COOKIE_JAR=$(mktemp)
CRUMB=$(curl -sf -u $JENKINS_USER:$JENKINS_PASS -c "$COOKIE_JAR" \
  'http://localhost:8080/crumbIssuer/api/json' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])")

# Delete
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  "http://localhost:8080/job/Pipeline-v2-Test/doDelete"

# Recreate
curl -sf -X POST -u $JENKINS_USER:$JENKINS_PASS -b "$COOKIE_JAR" -H "Jenkins-Crumb:${CRUMB}" \
  -H "Content-Type:application/xml" --data-binary @/tmp/config.xml \
  "http://localhost:8080/createItem?name=Pipeline-v2-Test"
```

### 4.4 Rebuild Agent Image

```bash
# Rebuild
docker build -t jenkins-inbound-agent1 \
  -f jenkins/jenkins-inbound-agent1 jenkins/

# Save connection params before removing
AGENT_SECRET=$(docker inspect jenkins-agent1 --format '{{index .Config.Cmd 3}}')
AGENT_NETWORK=$(docker inspect jenkins-agent1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')

# Recreate
docker stop jenkins-agent1 && docker rm jenkins-agent1
docker run -d --name jenkins-agent1 --network "$AGENT_NETWORK" --restart unless-stopped \
  jenkins-inbound-agent1 \
  -url http://jenkins-controller:8080 -secret "$AGENT_SECRET" -name agent1

# Verify
docker exec jenkins-agent1 shellcheck --version | head -1
curl -sf -u $JENKINS_USER:$JENKINS_PASS "http://localhost:8080/computer/agent1/api/json" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'offline: {d[\"offline\"]}')"
```

### 4.5 Monitor a Running Build

```bash
BUILD=<number>

# Poll until complete
for i in $(seq 1 40); do
    RESULT=$(curl -sf -u $JENKINS_USER:$JENKINS_PASS \
      "http://localhost:8080/job/Pipeline-v2-Test/${BUILD}/api/json" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result','IN_PROGRESS') or 'IN_PROGRESS')")
    [ "$RESULT" != "IN_PROGRESS" ] && echo "Finished: $RESULT" && break
    echo "[$((i*15))s] IN_PROGRESS"
    sleep 15
done

# Get console output
curl -sf -u $JENKINS_USER:$JENKINS_PASS "http://localhost:8080/job/Pipeline-v2-Test/${BUILD}/consoleText" | tail -50

# Get observability test results
curl -sf -u $JENKINS_USER:$JENKINS_PASS "http://localhost:8080/job/Pipeline-v2-Test/${BUILD}/consoleText" \
  | grep -E "PASS|FAIL|Results:"
```

---

## 5. Pipeline Stage Locality

Understanding which stages run where prevents debugging in the wrong place.

| Stage | Runs on | Why |
|---|---|---|
| Lint (shellcheck) | Agent (local) | Static analysis — inspects source code |
| Secret scan (gitleaks) | Agent (local) | Scans git history in workspace |
| SAST (SonarQube) | Agent (local) | Analyzes source code, reports to SonarQube on host |
| Dependency audit (pip-audit) | Agent (local) | Reads `requirements.txt` from workspace |
| DAST (OWASP ZAP) | Agent (local) | Scans test environment over network (targets VM:9080) |
| Sync repo | VM (SSH) | Updates `/home/jenkins/lab/app` via git pull |
| Fetch secrets | VM (SSH) | Vault is at `192.168.122.1:8200` from VM |
| Build + Tag + Push | VM (SSH) | Docker daemon is on VM, pushes to Docker Hub |
| Image scan (Trivy) | VM (SSH) | Scans image on VM's Docker daemon |
| Test deploy | VM (SSH) | Starts 12 containers on offset ports |
| Health checks | VM (SSH) | Curls endpoints on VM's localhost |
| Observability tests | VM (SSH) | Queries Prometheus/Tempo/Loki on VM's localhost |
| Promote | VM (SSH) | Restarts prod stack with new image |
| State contract | VM (SSH) | Runs `make state` on VM |

**Rule of thumb:** If it reads source files → agent. If it needs running containers → VM.

---

## 6. Port Map

### Production (default)

| Service | Port |
|---|---|
| Frontend | 8080 |
| Backend | 5000 |
| Prometheus | 9090 |
| Grafana | 3000 |
| Tempo | 3200 |
| Loki | 3100 |
| Alertmanager | 9093 |
| OTel gRPC | 4317 |
| OTel metrics | 8888 |
| OTel health | 13133 |
| Node Exporter | 9100 |
| Nginx Exporter | 9113 |
| cAdvisor | 8081 |

### Test (offset, set via env vars in Jenkinsfile)

| Service | Port |
|---|---|
| Frontend | 9080 |
| Backend | 9000 |
| Prometheus | 9190 |
| Grafana | 9300 |
| Tempo | 3201 |
| Loki | 3101 |
| Alertmanager | 9193 |
| OTel gRPC | 4327 |
| OTel metrics | 8898 |
| OTel health | 13134 |
| Node Exporter | 9110 |
| Nginx Exporter | 9114 |
| cAdvisor | 9081 |

All ports are parameterized in `docker-compose.yml` via `${VAR:-default}`.

---

## 7. Key File Inventory

| File | Purpose | When to read |
|---|---|---|
| `Jenkinsfile` | 20-stage pipeline, 3 modes | Changing pipeline stages or flow |
| `docker-compose.yml` | 12-service stack definition | Adding/removing services, changing ports |
| `docker-compose.test.yml` | Test container name overrides | Changing test environment isolation |
| `.env` | Image versions, ports, retention | Updating pinned versions |
| `jenkins/jenkins-inbound-agent1` | Agent Dockerfile (14 packages) | Adding tools the agent needs |
| `scripts/observability-integration-tests.sh` | 14 MELT tests with two-phase poll | Changing observability assertions |
| `scripts/health-checks.sh` | 29-point health validation | Changing health check criteria |
| `scripts/fetch-secrets.sh` | Vault AppRole → `.env.secrets` | Changing secret management |
| `otel-collector/otel-collector-config.yml` | OTel Collector pipelines | Changing telemetry routing |
| `otel-collector/prometheus.yml` | Scrape targets and alert rules | Adding scrape targets |
| `otel-collector/tempo.yml` | Trace storage and metrics generator | Changing trace retention or search |
| `grafana/provisioning/datasources/datasources.yml` | Cross-signal correlation links | Changing datasource connections |

---

## 8. End-to-End Testing Runbook

When you've made changes and need to verify everything works:

```bash
# 1. Inspect and clean
docker ps -a                                           # host containers healthy?
ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230 "docker ps -a"  # VM clean?
ssh -i ~/.ssh/id_ed25519_jenkins jenkins@192.168.122.230 "docker ps -a -q | xargs -r docker rm -f; docker volume prune -f"

# 2. Vault — regenerate secret_id if stale
# (see section 2.4)

# 3. Agent — rebuild if Dockerfile changed
# (see section 4.4)

# 4. Commit and push
git add <files> && git commit -m "message" && git push origin main

# 5. Recreate Jenkins job if scriptPath or branch changed
# (see section 4.3)

# 6. Trigger and monitor
# (see sections 4.1 and 4.5)

# 7. Verify results
curl -sf -u $JENKINS_USER:$JENKINS_PASS "http://localhost:8080/job/Pipeline-v2-Test/lastBuild/consoleText" \
  | grep -E "Results:|Finished:"
```

**Expected on success:**
```
Results: 14/14 passed, 0 failed       (observability tests)
Results: 29 passed, 0 failed          (health checks)
Results: 9 passed, 0 failed           (state contract)
Results: 10 passed, 0 failed          (version validation)
Finished: SUCCESS
```
