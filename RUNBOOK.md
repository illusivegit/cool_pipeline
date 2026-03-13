# Operations Runbook

## 1. Prerequisites

### Local Development

| Tool | Minimum Version | Check |
|---|---|---|
| Docker Engine | 24+ | `docker --version` |
| Docker Compose | v2 | `docker compose version` |
| make | any | `make --version` |
| curl | any | `curl --version` |
| jq | 1.6+ | `jq --version` |
| Git | 2.x | `git --version` |
| pipx | any (for pre-commit) | `pipx --version` |

### CI/CD (Jenkins)

| Tool | Where | Purpose |
|---|---|---|
| Jenkins Controller | Docker container | Pipeline orchestration |
| Jenkins Inbound Agent | Docker container (`jenkins-inbound-agent1`) | Build execution |
| HashiCorp Vault | VM or host | Secret management |
| Docker Hub | `bleeng089/cool_images` | Immutable artifact storage |

---

## 2. Local Setup

### First Run

```bash
git clone https://github.com/illusivegit/cool_pipeline.git
cd cool_pipeline

# Option A: With Vault
cp .vault-env.example .vault-env
# Edit .vault-env with your VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID

# Option B: Without Vault
cp .env.secrets.example .env.secrets
# Edit .env.secrets with SMTP_AUTH_USERNAME, SMTP_AUTH_PASSWORD, ALERT_EMAIL_TO

make up
```

`make up` does three things in order:
1. `fetch-secrets` -- authenticates to Vault (if configured), writes `.env.secrets`
2. `render-alertmanager` -- runs `envsubst` on `alertmanager.yml.tmpl` to produce `.alertmanager-rendered.yml` with SMTP credentials injected
3. `docker compose up -d --build` -- builds the backend image and starts all 14 services

### Verify

```bash
make health          # 29-point check: containers, endpoints, targets, rules, versions
make status          # quick curl check on core endpoints
make test-observability   # 14 MELT integration tests (takes ~35s due to propagation wait)
```

### Generate Test Data

```bash
make traffic         # 40 synthetic API requests (20 GET, 20 POST)
```

Then open Grafana at http://localhost:3000 to see data flowing through all dashboards.

### Pre-Commit Hooks

```bash
pipx install pre-commit
pre-commit install
```

12 hooks run on every commit: trailing whitespace, end-of-file, YAML/JSON validation, large file detection, merge conflict markers, private key detection, gitleaks, ShellCheck, Ruff lint+format, Hadolint.

---

## 3. Jenkins Setup

### Controller

```bash
docker network create jenkins-network

docker run -d \
  --name jenkins-controller \
  --network jenkins-network \
  -p 8080:8080 \
  -p 50000:50000 \
  --restart=on-failure \
  -v jenkins_volume:/var/jenkins_home \
  jenkins/jenkins:2.541.2-lts-jdk21
```

Initial password:
```bash
docker exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
```

Pin the image tag. `jenkins/jenkins:lts-jdk21` is a rolling tag that will drift.

### Required Plugins

| Plugin | Why |
|---|---|
| Pipeline | `pipeline {}` DSL |
| SSH Agent | `sshagent(credentials: ['vm-ssh'])` |
| Timestamper | `options { timestamps() }` |
| Credentials Binding | Expose credentials to build steps |
| Git | Pull repo into workspace |
| GitHub | Webhook triggers, commit status |

### Agent Image

```bash
docker build -t jenkins-inbound-agent1 \
  -f jenkins/jenkins-inbound-agent1 jenkins/
```

The Dockerfile is a file, not a directory. Use `-f` to specify it.

Packages installed and why:

| Package | Justification |
|---|---|
| `ca-certificates`, `curl`, `gnupg` | Docker repo setup, HTTPS, API calls |
| `jq` | JSON parsing in pipeline scripts |
| `openssh-client` | SSH to VM for remote Docker context |
| `git` | SCM operations on agent |
| `nodejs` | sonar-scanner JS analysis sensor |
| `python3`, `python3-venv` | pip-audit SCA stage (venv isolation) |
| `shellcheck` | Lint stage (shell script analysis) |
| `unzip` | sonar-scanner CLI extraction |
| `docker-ce-cli` | Remote Docker context (CLI only, no daemon) |
| `docker-compose-plugin` | `docker compose` v2 |

### Agent Node Configuration

1. Jenkins UI: Manage Jenkins > Nodes > New Node
   - Name: `agent1`
   - Labels: `agent1` (must match `agent { label 'agent1' }` in Jenkinsfile)
   - Remote root directory: `/home/jenkins/agent`
   - Launch method: Launch agent by connecting it to the controller
2. Copy the secret from the node page
3. Start the agent:

```bash
docker run -d \
  --name jenkins-agent1 \
  --init \
  --restart=on-failure \
  --network jenkins-network \
  jenkins-inbound-agent1 \
  -url http://jenkins-controller:8080 \
  -secret <SECRET_FROM_NODE_PAGE> \
  -name agent1
```

Put the command on one line or be paranoid about trailing spaces after `\`. Bash interprets `\ ` (backslash-space) as an escaped space, not a line continuation — everything after the break becomes a separate command.

### Key Distinctions

- **Node name** (`agent1`): must match `-name` arg in `docker run`
- **Node label** (`agent1`): must match `agent { label '...' }` in Jenkinsfile
- **Remote root directory** (`/home/jenkins/agent`): must be writable by the `jenkins` user inside the container (home: `/home/jenkins`)
- After changing node config, you must **disconnect the agent and restart the container**. Config is cached at connect time.

### Docker Hub Registry

Build artifacts are pushed to Docker Hub as `bleeng089/cool_images:<git-sha>`.

**Authentication:** The `jenkins` user on the VM must be logged in to Docker Hub. Credentials are stored in `/home/jenkins/.docker/config.json`. If missing, copy from root's config or run `docker login` as jenkins.

**Jenkinsfile:** The `REGISTRY_IMAGE` environment variable is set to `bleeng089/cool_images`. All docker tag/push/pull operations run on the VM via SSH.

**Listing tags:**
```bash
curl -sf "https://hub.docker.com/v2/repositories/bleeng089/cool_images/tags?page_size=25" | jq '.results[].name'
```

Each tag is a 7-character git SHA. Cross-reference with `git log --oneline`.

### Jenkins Job Configuration

Create a Pipeline job:
- Pipeline Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: `https://github.com/illusivegit/cool_pipeline.git`
- Branch: `*/main`
- Script Path: `Jenkinsfile`

### Credentials

| ID | Type | Purpose |
|---|---|---|
| `vm-ssh` | SSH Username with private key | SSH to VM (user: `jenkins`) |
| Vault AppRole | Stored in Jenkinsfile env block | `VAULT_ADDR`, role/secret IDs fetched at runtime |

---

## 4. Pipeline Operations

### Running a Build

**Full pipeline** (normal CI/CD):
```bash
# Via Jenkins UI: Build with Parameters > MODE = full
# Via API:
curl -X POST "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=full" \
  --user admin:<TOKEN>
```

**Rollback (fast)** -- emergency, skip all testing:
```bash
curl -X POST "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=rollback-fast&DEPLOY_TAG=<git-sha>" \
  --user admin:<TOKEN>
```

**Rollback (safe)** -- test first, then promote:
```bash
curl -X POST "http://localhost:8080/job/Pipeline-v2-Test/buildWithParameters?MODE=rollback-safe&DEPLOY_TAG=<git-sha>" \
  --user admin:<TOKEN>
```

### Finding Available Tags for Rollback

```bash
# List Docker Hub tags
curl -sf "https://hub.docker.com/v2/repositories/bleeng089/cool_images/tags?page_size=25" | jq '.results[].name'
```

Each tag is a git SHA. Cross-reference with `git log --oneline` to find the commit.

### What Each Mode Skips

| Skipped in rollback-fast | Skipped in rollback-safe |
|---|---|
| Lint, Secrets, SAST, SCA | Lint, Secrets, SAST, SCA |
| Build + Tag + Push | Build + Tag + Push |
| Image scan (Trivy) | Image scan (Trivy) |
| Test deploy, Health, DAST | -- |
| Observability tests | -- |
| Teardown | -- |

---

## 5. Troubleshooting

### Container Won't Start

```bash
docker compose logs <service-name>     # check container logs
docker compose ps                      # check exit codes
make health                            # systematic 29-point check
```

### Port Conflicts

If you see `Bind for 0.0.0.0:XXXX failed: port is already allocated`:

1. Check what's using the port: `ss -tlnp | grep XXXX`
2. All ports are parameterized in `docker-compose.yml` via `${VAR:-default}`. Override by setting the env var:
   ```bash
   GRAFANA_PORT=3001 make up
   ```

### Observability Tests Fail

The tests use a two-phase poll (up to 90s) instead of a blind sleep:
- **Phase 2a:** Polls Prometheus for `db_query_duration_seconds_count` every 5s (up to 60s). This metric only appears after the test's API calls are scraped — avoids false-early exit from health check traffic.
- **Phase 2b:** Polls Tempo for `{name="create_task"}` span every 5s (up to 30s). Checks span-level index, not resource-level (which indexes faster but doesn't guarantee span searches work).

If tests fail intermittently:

1. **"No traces found"** -- Tempo span-level indexing is slow on cold start (~20-30s). The two-phase poll should handle this, but if it persists, retry: `make test-observability`
2. **"Tempo/Loki is reachable" fails but queries pass** -- The tests use query APIs (not `/ready`) for reachability because `/ready` returns 503 during WAL recovery even when queries work
3. **"No db_query_duration samples"** -- Prometheus scrape hasn't happened yet. Default scrape interval is 15s. The poll retries for up to 60s.

### Jenkins Build Fails

```bash
# Check console output
curl -sf --user admin:<TOKEN> "http://localhost:8080/job/Pipeline-v2-Test/lastBuild/consoleText" | tail -50

# Check if agent is connected
curl -sf --user admin:<TOKEN> "http://localhost:8080/computer/agent1/api/json" | jq '{offline, idle}'

# Check failure artifacts
curl -sf --user admin:<TOKEN> "http://localhost:8080/job/Pipeline-v2-Test/lastBuild/artifact/failure-logs.txt"
```

Common failures:

| Error | Cause | Fix |
|---|---|---|
| `Unknown client name: agent1` | Node not created in Jenkins UI | Create node in Manage Jenkins > Nodes |
| `AccessDeniedException /home/deploy` | Wrong Remote root directory | Set to `/home/jenkins/agent`, disconnect + restart |
| `bash: -url: command not found` | Trailing space after `\` in docker run | Use single-line command |
| `unzip: not found` / `node -v` not found | Missing agent image package | Rebuild `jenkins-inbound-agent1` |
| `port already allocated` | Test/prod port conflict | Check port parameterization in Jenkinsfile test deploy |

### Vault Connection

The Jenkins agent connects to Vault via `http://192.168.122.1:8200` (host bridge IP from the VM's perspective). If Vault is unreachable:

```bash
# From the VM
curl -sf http://192.168.122.1:8200/v1/sys/health | jq

# Check if Vault is listening on the bridge
curl -sf http://localhost:8200/v1/sys/health | jq

# Vault may be bound to 127.0.0.1 only — needs 0.0.0.0
```

### SonarQube SAST Stage

SonarQube scanner is downloaded and cached in `${WORKSPACE}/.sonar-scanner/`. If the SAST stage fails:

1. **Auth failure**: Vault AppRole credentials for SonarQube may have expired. Check `secret/data/lab/sonarqube` in Vault.
2. **Node.js error**: Scanner requires Node.js. Ensure `nodejs` is in the agent Dockerfile.
3. **Scanner download fails**: Network issue. The scanner ZIP is ~50MB from `binaries.sonarsource.com`.

---

## 6. Alerting

### How It Works

```
Prometheus alert rules  -->  Alertmanager  -->  SMTP relay  -->  Yahoo Mail
(otel-collector/            (email routing,     (Postfix or
 alert-rules.yml)            grouping,           direct SMTP)
                             silencing)
```

### Alert Rules (6 groups)

| Group | Alert | Condition | For |
|---|---|---|---|
| application | BackendDown | backend target absent | 1m |
| application | HighErrorRate | error rate > 5% | 2m |
| application | HighLatencyP95 | p95 > 500ms | 30s |
| infrastructure | HostHighCpuUsage | CPU > 85% | 5m |
| infrastructure | HostHighMemoryUsage | Memory > 85% | 5m |
| infrastructure | HostDiskSpaceWarning | Disk > 80% | 5m |
| observability-stack | PrometheusTargetDown | any target down | 2m |
| observability-stack | OtelCollectorDroppedSpans | dropped spans > 0 | 5m |
| slo | HighAvailabilityBurnRate | 14.4x burn rate on 99% SLO | 2m |
| storage | PrometheusTSDBHighDiskUsage | TSDB > 4GB | 5m |
| storage | HostDiskWillFillIn24h | predictive fill | 30m |
| collector-health | OtelCollectorHighMemory | > 400MB | 5m |
| collector-health | LokiIngestionErrors | ingestion errors > 0 | 5m |
| collector-health | PrometheusScrapeSlow | scrape > 10s | 5m |

### Testing Alerts

```bash
# Simulate backend error (triggers HighErrorRate if sustained)
for i in $(seq 1 50); do curl -s http://localhost:5000/api/simulate-error > /dev/null; done

# Check alert state
curl -sf http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {alertname: .labels.alertname, state}'

# Check Alertmanager
curl -sf http://localhost:9093/api/v2/alerts | jq '.[].labels.alertname'
```

### SMTP Configuration

Alertmanager sends email via SMTP. The configuration is templated:

1. `otel-collector/alertmanager.yml.tmpl` -- template with `${SMTP_*}` variables
2. `make render-alertmanager` -- runs `envsubst` to produce `.alertmanager-rendered.yml`
3. `.alertmanager-rendered.yml` contains secrets and is gitignored

If using Yahoo SMTP: the envelope sender must match the authenticated account. Alertmanager sets `smtp_from` in its config, so this works natively. The `mail` CLI command uses the local unix identity, which Yahoo rejects — use Postfix `sender_canonical_maps` with a regexp catch-all to rewrite all senders.

---

## 7. Backup and Restore

### Backup

```bash
make backup
```

Creates a timestamped snapshot in `backups/<timestamp>/`:
- Stops all services
- Tars each Docker volume (backend-data, prometheus-data, grafana-data, tempo-data, loki-data, alertmanager-data, nginx-logs)
- Writes `manifest.json` with volume-to-tarball mappings
- Restarts services
- Enforces 7-day retention (deletes snapshots older than 7 days)

### Restore

```bash
make restore                    # restore from latest backup
bash scripts/restore.sh <TIMESTAMP>  # restore from specific backup
```

Stops services, clears volumes, extracts tarballs, restarts services.

### What's Backed Up

| Volume | Contents |
|---|---|
| backend-data | SQLite database (`tasks.db`) |
| prometheus-data | TSDB (15-day retention) |
| grafana-data | Dashboard state, user prefs |
| tempo-data | Trace blocks (72h retention) |
| loki-data | Log chunks, index (168h retention) |
| alertmanager-data | Silence state, notification log |
| nginx-logs | Access/error logs (Promtail source) |

---

## 8. State Contract and Drift Detection

### Generate State

```bash
make state
```

Creates `artifacts/state/<timestamp>/` with two files:

- **`state.json`** -- machine-readable: service status, health, image, restart count, started_at
- **`state.kv`** -- flat key=value format for diffing

### Detect Drift

```bash
# Compare two state snapshots
diff artifacts/state/<old>/state.kv artifacts/state/<new>/state.kv

# Check if running images match .env declarations
make validate-versions
```

The `validate-versions` script compares each running container's image against the pinned version in `.env`. Any mismatch is flagged.

### Pipeline Integration

The Jenkins pipeline generates a state contract after every successful deployment (both test and production). The `post { success }` block prints the last 30 lines of `state.kv` to the build log.

---

## 9. Retention Policies

| System | Retention | Configured In |
|---|---|---|
| Prometheus TSDB | 15 days | `.env` (`PROMETHEUS_RETENTION`) |
| Tempo traces | 72 hours | `.env` (`TEMPO_RETENTION`) |
| Loki logs | 168 hours (7 days) | `.env` (`LOKI_RETENTION`) |
| Backups | 7 days | `scripts/backup.sh` (mtime +7) |

---

## 10. Resource Limits

Every service has CPU/memory limits and reservations defined in `docker-compose.yml`:

| Service | CPU Limit | Memory Limit | CPU Reserve | Memory Reserve |
|---|---|---|---|---|
| backend | 1.0 | 512MB | 0.25 | 128MB |
| frontend | 0.5 | 128MB | 0.05 | 32MB |
| otel-collector | 1.0 | 512MB | 0.1 | 64MB |
| prometheus | 1.0 | 512MB | 0.25 | 128MB |
| tempo | 1.0 | 512MB | 0.1 | 64MB |
| loki | 1.0 | 512MB | 0.1 | 64MB |
| grafana | 1.0 | 512MB | 0.1 | 64MB |
| alertmanager | 0.5 | 128MB | 0.05 | 32MB |
| node-exporter | 0.5 | 128MB | 0.05 | 32MB |
| nginx-exporter | 0.25 | 64MB | 0.05 | 16MB |
| promtail | 0.5 | 128MB | 0.05 | 32MB |
| cadvisor | 0.5 | 256MB | 0.1 | 64MB |

The OTel Collector also has a `memory_limiter` processor set to 512MiB, matching its container limit.

---

## 11. Security Hardening

| Measure | Where |
|---|---|
| Read-only filesystem | backend, otel-collector, nginx-exporter, promtail, node-exporter |
| `no-new-privileges` | backend, otel-collector, nginx-exporter, promtail |
| Dropped capabilities | backend (`ALL`), nginx-exporter (`ALL`), promtail (`ALL`), node-exporter (`ALL` except SYS_PTRACE) |
| Minimal capabilities | frontend (NET_BIND_SERVICE, CHOWN, SETGID, SETUID, DAC_OVERRIDE) |
| tmpfs for writable paths | backend (`/tmp`), frontend (`/tmp`, `/var/cache/nginx`, `/run`) |
| Secrets gitignored | `.env.secrets`, `.vault-env`, `.alertmanager-rendered.yml` |
| Vault AppRole auth | Scoped, auditable secret access (no long-lived tokens) |
| CORS restricted | OTel Collector HTTP receiver restricted to `ALLOWED_ORIGIN` |
| Rate limiting | Nginx rate-limits `/v1/traces` to 10 req/s burst 20 |
| Network isolation | 3 Docker networks (frontend-net, backend-net, observability) |
| Pre-commit secrets scan | gitleaks runs on every commit |
| CI secrets scan | gitleaks-action in GitHub Actions + gitleaks in Jenkins |

---

## 12. Updating Image Versions

1. Edit `.env` with the new version:
   ```
   PROMETHEUS_IMAGE=prom/prometheus:v2.50.0
   ```
2. Run `make up` (rebuilds if needed)
3. Run `make validate-versions` to confirm the running image matches
4. Run `make health` to verify the update didn't break anything
5. Commit the `.env` change

---

## 13. Common Make Targets Reference

```bash
make help                  # show all targets with descriptions
make up                    # start everything (fetch secrets, render config, compose up)
make down                  # stop (preserve volumes)
make restart               # down + up
make status                # quick endpoint checks
make health                # 29-point validation
make test-observability    # 14 MELT integration tests
make state                 # generate state contract artifacts
make validate-versions     # check running images vs .env
make traffic               # generate synthetic API load
make smoke                 # 3-endpoint quick check
make logs                  # tail all container logs
make backup                # snapshot all volumes
make restore               # restore from latest snapshot
make lint                  # ShellCheck all scripts
make clean                 # remove artifacts and caches
make nuke                  # destroy everything
```
