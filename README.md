# Docker CI/CD Observability Lab

A 14-service Docker Compose stack that deploys a task manager application with production-grade MELT observability (Metrics, Events, Logs, Traces) and a 20-stage Jenkins CI/CD pipeline. One `make up` brings up the application, telemetry collection, storage backends, alerting, and pre-built Grafana dashboards.

## Architecture

```
                          +---------------------------------+
                          |         APPLICATION             |
                          |                                 |
                          |  +-----------+   +-----------+  |
              :8080       |  |  Nginx    |-->|  Flask    |  |
            <-------------|  |  Frontend |   |  Backend  |  |
  Browser traces -------->|  | /v1/traces|   |  :5000    |  |
  (rate-limited 10r/s)    |  +--+--+---+-+   +-----+-----+  |
                          +----+--+---+------------|--------+
                               |  |   |            |
                     logs      |  |stub|     OTLP   |  /metrics
                     (file)    |  |stat|   (traces  |  (scrape)
                               |  |   |   + logs)  |
         +---------------------+--+---+------------|----------------+
         |  TELEMETRY          |  |   |            |                |
         |  COLLECTION         v  v   v            v                |
         |             +----------+ +--------+ +--------------+    |
         |             | Promtail | | Nginx  | |     OTel     |    |
         |             |          | |Exporter| |   Collector  |<-- |
         |             |          | | :9113  | |:4317 (gRPC)  |Ngx |
         |             +----+-----+ +---+----+ +---+------+---+/v1 |
         |                  |           |          |      |        |
         +------------------|-----------+----------|------|----- --+
                            |           |          |      |
         +------------------|-----------+----------|------|---------+
         |  STORAGE         v           |          v      v         |
         |                              |                           |
         |  +---------+  +--------+  +------+  +--------------+    |
         |  |  Loki   |  | Prom   |  | Tempo|  |    Prom      |    |
         |  | :3100   |  |:9090   |  |:3200 |  |   (scrape)   |    |
         |  +---------+  +---+----+  +------+  +--------------+    |
         |                   |                                      |
         |              +----+------+    +-------------+            |
         |              |Alertmanager|    | Node Exp   |            |
         |              |  :9093    |    |  :9100     |            |
         |              +-----------+    +-------------+            |
         +---------------------------------------------------------+
                            |
         +-----------------+--+---+--------------------------------+
         |  VISUALIZATION  |  |   |                                |
         |                 v  v   v                                |
         |  +------------------------------------------+           |
         |  |              Grafana :3000                |           |
         |  |  +----------+ +---------+ +------------+ |           |
         |  |  | Overview | | Infra   | | Service    | |           |
         |  |  |Dashboard | |Dashboard| | Health     | |           |
         |  |  +----------+ +---------+ +------------+ |           |
         |  |  +------------------+                    |           |
         |  |  | End-to-End       |    cAdvisor :8081   |           |
         |  |  | Tracing          |                    |           |
         |  |  +------------------+                    |           |
         |  +------------------------------------------+           |
         +---------------------------------------------------------+
```

### Service Inventory

| Service | Image | Port | Purpose |
|---|---|---|---|
| frontend | nginx:alpine | 8080 | SPA, API proxy, OTLP trace relay |
| backend | python:3.11-slim | 5000 | REST API, /metrics, /health |
| otel-collector | otel/opentelemetry-collector-contrib:0.96.0 | 4317, 4318, 8888, 8889, 13133 | Trace + log ingestion, routing |
| prometheus | prom/prometheus:v2.48.1 | 9090 | Metrics storage, alerting rules |
| tempo | grafana/tempo:2.3.1 | 3200 | Distributed trace storage |
| loki | grafana/loki:2.9.3 | 3100 | Log aggregation |
| alertmanager | prom/alertmanager:v0.27.0 | 9093 | Alert routing, email notification |
| grafana | grafana/grafana:10.2.3 | 3000 | Dashboards, datasource correlation |
| node-exporter | prom/node-exporter:v1.7.0 | 9100 | Host metrics |
| nginx-exporter | nginx/nginx-prometheus-exporter:1.1 | 9113 | Nginx metrics |
| cadvisor | gcr.io/cadvisor/cadvisor:v0.49.1 | 8081 | Container metrics |
| promtail | grafana/promtail:2.9.3 | -- | Nginx log shipping to Loki |

All images are pinned to specific versions in `.env`.

---

## Quick Start

### Prerequisites

- Docker Engine 24+ with Compose v2
- `curl`, `jq`, `make`
- HashiCorp Vault (optional, for secret management)

### Start

```bash
git clone https://github.com/illusivegit/cool_pipeline.git
cd cool_pipeline

# If using Vault for secrets:
cp .vault-env.example .vault-env    # fill in Vault AppRole credentials
# If not using Vault:
cp .env.secrets.example .env.secrets  # fill in SMTP credentials manually

make up        # fetch secrets, render alertmanager config, start all services
make health    # run 29-point health check
make status    # quick endpoint check
```

### Access

| Service | URL |
|---|---|
| Application | http://localhost:8080 |
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |
| Backend API | http://localhost:5000/api/tasks |
| Backend metrics | http://localhost:5000/metrics |

### Stop

```bash
make down      # stop containers, preserve data volumes
make nuke      # destroy everything including volumes and images
```

---

## Observability (MELT)

### Metrics

Flask exposes three Prometheus counters/histograms via `/metrics`:

| Metric | Type | Labels |
|---|---|---|
| `http_requests_total` | counter | method, endpoint, status_code |
| `http_request_duration_seconds` | histogram | method, endpoint, status_code |
| `db_query_duration_seconds` | histogram | operation (SELECT/INSERT/UPDATE/DELETE) |

Prometheus scrapes 10 targets at 15s intervals. 6 alert rule groups cover application health, infrastructure, SLO burn rate, storage, and collector health.

### Traces

Flask sends spans via OpenTelemetry SDK to the OTel Collector (OTLP/HTTP on :4318), which exports to Tempo. The browser frontend also sends traces via the Nginx-proxied `/v1/traces` endpoint (rate-limited to 10 req/s).

Tempo generates span metrics and service graphs, writing them back to Prometheus via remote_write.

### Logs

Two log paths:

1. **Application logs**: Flask structured JSON (python-json-logger) with `trace_id` and `span_id` injected by OTel. Sent via OTLP log exporter to Collector, then to Loki.
2. **Nginx logs**: Access and error logs written to a shared volume. Promtail parses them with regex, normalizes URL paths, and ships to Loki.

### Cross-Signal Correlation

Grafana datasource provisioning connects all three signals:

- **Trace to Logs**: Tempo links to Loki via `otelTraceID` tag
- **Trace to Metrics**: Tempo links to Prometheus request rate and error rate queries
- **Logs to Traces**: Loki derived field extracts `otelTraceID` and links to Tempo

### Dashboards

| Dashboard | What it shows |
|---|---|
| Overview | Request rate, error rate, latency percentiles, active tasks |
| Infrastructure | CPU, memory, disk, network per container (cAdvisor + Node Exporter) |
| Service Health | Per-service availability, scrape target status, alert state |
| End-to-End Tracing | Trace search, span waterfall, service graph |

---

## API

### Task CRUD

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/tasks` | List all tasks |
| GET | `/api/tasks/:id` | Get task by ID |
| POST | `/api/tasks` | Create task (`{"title": "...", "description": "..."}`) |
| PUT | `/api/tasks/:id` | Update task |
| DELETE | `/api/tasks/:id` | Delete task |

### Observability Endpoints

| Endpoint | Purpose |
|---|---|
| `/health` | Health check (JSON) |
| `/metrics` | Prometheus metrics (text) |
| `/api/simulate-error` | Generate 500 error with trace context |
| `/api/simulate-slow?delay=N` | Generate slow request (default 2s) |
| `/api/smoke/db?ops=N&type=rw` | Generate DB load (rolled back) |

---

## CI/CD Pipeline

### Quality Gates

```
  Developer                 GitHub                     Jenkins
  workstation               Actions                    (VM deploy)
      |                       |                           |
  Gate 1: pre-commit      Gate 3: PR Gate           Gate 4: CI/CD
  12 hooks, <10s           4 jobs, <30s              20 stages, ~2.5min
      |                       |                           |
  trailing-ws             gitleaks                   lint
  end-of-file             shellcheck                 gitleaks
  check-yaml              hadolint                   sonarqube (SAST)
  check-json              yamllint                   pip-audit (SCA)
  large-files             ruff                       build + tag + push
  merge-conflict          compose-validate           trivy (image scan)
  detect-private-key      pr-size                    test deploy
  gitleaks                                           health checks
  shellcheck                                         observability tests (14)
  ruff lint+format                                   OWASP ZAP (DAST)
  hadolint                                           promote to prod
                                                     state contract
```

### Pipeline Modes

The Jenkins pipeline (`Jenkinsfile`) supports three parameterized modes:

| Mode | Stages | Use case |
|---|---|---|
| `full` | 20 | Normal CI/CD: build, scan, test, promote |
| `rollback-fast` | 9 | Emergency: redeploy known-good artifact, skip all testing |
| `rollback-safe` | 13 | Cautious: test known-good artifact, then promote |

### Stage Matrix

```
Stage                       full  rollback-fast  rollback-safe
---------------------------+------+---------------+-------------
Sanity                        Y         Y              Y
Docker context                Y         Y              Y
Sync repo to VM               Y         Y              Y
Lint                          Y         -              -
Secret scan (gitleaks)        Y         -              -
SAST (SonarQube)              Y         -              -
Dependency audit (pip-audit)  Y         -              -
Fetch secrets from Vault      Y         Y              Y
Build + Tag + Push            Y         -              -
Image scan (Trivy)            Y         -              -
Resolve tag                   Y         Y              Y
Test deploy                   Y         -              Y
Health checks (test)          Y         -              Y
Observability tests (14)      Y         -              Y
DAST (OWASP ZAP)              Y         -              Y
Teardown test                 Y         -              Y
Promote                       Y         Y              Y
Health checks (prod)          Y         Y              Y
State contract                Y         Y              Y
Version validation            Y         Y              Y
```

### Immutable Artifacts

The pipeline builds once and deploys everywhere:

1. `Build + Tag + Push` creates `<registry>/lab-flask-backend:<git-sha>`
2. The same image deploys to the test environment
3. If all gates pass, the same image promotes to production
4. Rollback modes reference a previous `<git-sha>` tag from the registry

---

## Secret Management

Secrets are managed through HashiCorp Vault with AppRole authentication:

```
Vault KV v2
  secret/data/lab/alertmanager    -> SMTP credentials
  secret/data/lab/sonarqube       -> SONAR_TOKEN, SONAR_HOST_URL
  secret/data/lab/registry        -> Docker registry credentials
```

The `scripts/fetch-secrets.sh` script authenticates via AppRole, reads KV paths, and writes `.env.secrets` (mode 0600, gitignored). The Makefile sources these before `docker compose up`.

For local development without Vault, copy `.env.secrets.example` and fill in values manually.

---

## Operational Scripts

| Script | Purpose |
|---|---|
| `make health` | 29-point health check (containers, endpoints, targets, rules, versions) |
| `make test-observability` | 14 MELT integration tests (Prometheus, Tempo, Loki, correlation) |
| `make state` | Generate state contract artifacts (`artifacts/state/`) for drift detection |
| `make validate-versions` | Compare running container images against `.env` declarations |
| `make backup` | Snapshot all Docker volumes (7-day retention) |
| `make restore` | Restore volumes from a named or latest backup snapshot |
| `make traffic` | Generate 40 synthetic API requests for dashboard testing |
| `make smoke` | Quick 3-endpoint availability check |
| `make lint` | ShellCheck all scripts in `lib/` and `scripts/` |

---

## Test/Prod Coexistence

The test environment runs alongside production on the same VM using:

- **Docker Compose project separation**: `-p lab` (prod) vs `-p lab-test` (test)
- **Container name prefixing**: `docker-compose.test.yml` overrides names with `test-` prefix
- **Port parameterization**: All 14 host-bound ports use `${VAR:-default}` syntax

| Port | Prod | Test |
|---|---|---|
| Backend | 5000 | 9000 |
| Frontend | 8080 | 9080 |
| Prometheus | 9090 | 9190 |
| Grafana | 3000 | 9300 |
| Tempo | 3200 | 3201 |
| Loki | 3100 | 3101 |
| Alertmanager | 9093 | 9193 |
| OTel gRPC | 4317 | 4327 |
| OTel metrics | 8888 | 8898 |
| OTel health | 13133 | 13134 |
| Node Exporter | 9100 | 9110 |
| Nginx Exporter | 9113 | 9114 |
| cAdvisor | 8081 | 9081 |

---

## Project Structure

```
.
|-- backend/                  # Flask app, Dockerfile, requirements.txt
|-- frontend/                 # Nginx config, SPA (HTML/JS/CSS)
|-- otel-collector/           # OTel, Prometheus, Tempo, Loki, Promtail, Alertmanager configs
|-- grafana/
|   |-- dashboards/           # 4 JSON dashboard definitions
|   +-- provisioning/         # Datasource and dashboard provider YAML
|-- jenkins/
|   +-- jenkins-inbound-agent1  # Agent Dockerfile (CLI-only Docker, Python, Node)
|-- scripts/
|   |-- health-checks.sh         # 29-point health validation
|   |-- observability-integration-tests.sh  # 14 MELT integration tests
|   |-- state-contract.sh        # Post-deploy state artifact generation
|   |-- validate-versions.sh     # Image version drift detection
|   |-- fetch-secrets.sh         # Vault AppRole secret fetching
|   |-- backup.sh                # Volume snapshot (7-day retention)
|   |-- restore.sh               # Volume restore from snapshot
|   +-- bootstrap_debian13_jenkins_agent.sh  # VM provisioning
|-- lib/
|   |-- log.sh                   # Structured logging library
|   +-- checks.sh                # Reusable health check functions
|-- .github/workflows/
|   +-- pr-gate.yml              # GitHub Actions quality gate (4 jobs)
|-- .pre-commit-config.yaml      # 12 local hooks
|-- docker-compose.yml           # 14-service stack (all ports parameterized)
|-- docker-compose.test.yml      # Test environment container name overrides
|-- Jenkinsfile                  # 20-stage pipeline (3 modes)
|-- Makefile                     # Operational targets
|-- sonar-project.properties     # SonarQube analysis config
|-- .env                         # Image versions, ports, retention policies
|-- .env.secrets.example         # SMTP credential template
+-- .vault-env.example           # Vault AppRole credential template
```

---

## License

MIT
