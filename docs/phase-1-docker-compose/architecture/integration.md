# System Integration

**Document Status:** Complete
**Last Updated:** 2025-10-22
**Parent Document:** [ARCHITECTURE.md](../ARCHITECTURE.md)

---

## Overview

This document details how all components in the observability lab integrate with each other, including service dependencies, startup ordering, data flow, and inter-component communication patterns. This architecture demonstrates production-grade integration practices for on-premises observability stacks.

## Table of Contents

1. [Service Dependency Graph](#service-dependency-graph)
2. [Startup Orchestration](#startup-orchestration)
3. [Data Flow Architecture](#data-flow-architecture)
4. [Integration Points](#integration-points)
5. [Service Communication Matrix](#service-communication-matrix)
6. [Healthcheck Dependencies](#healthcheck-dependencies)
7. [Bootstrap and Initialization](#bootstrap-and-initialization)
8. [Network Integration](#network-integration)

---

## Service Dependency Graph

The following diagram illustrates the complete dependency chain across all services:

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        Service Dependency Architecture                           │
└──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│ Layer 1: Storage Backends (No Dependencies)                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────┐             │
│  │     Tempo       │  │      Loki       │  │    Prometheus        │             │
│  │ Trace Storage   │  │  Log Storage    │  │  Metrics Storage     │             │
│  │   Port: 3200    │  │   Port: 3100    │  │    Port: 9090        │             │
│  └─────────────────┘  └─────────────────┘  └──────────────────────┘             │
│                                                                                 │
│                                                         Prometheus scrapes      │
│                                                         backend:5000/metrics    │
└─────────────────────────────────▲─────────────────────────────────▲─────────────┘
                                  |                                 | 
                                  |                                 │
                                  |OTLP/HTTP                        │             
                                  │(Backend pushes traces & logs)   │
                                  |                                 |
                                  |                                 │
                                  |                                 │
┌───────────────────────────────────────────────────────────────────┼─────────────┐
│ Layer 2: Telemetry Pipeline (depends_on: tempo, loki, prometheus) │             │
├───────────────────────────────────────────────────────────────────┼─────────────┤
│                                 |                                 │             │
│                                 │                                 │             │
│                                 |                                 |             |
|                                 |                                 |             |
│                    ┌──────────────────────────┐                   │             │
│                    │   OTel Collector         │                   │             │
│                    │   Receives: OTLP         │                   │             │
│                    │   Ports: 4317, 4318      │                   │             │
│                    └──────────────────────────┘                   │             │
│                                │                                  │             │
│                                |                                  │             │
│                                |                                  |             │ 
│                                |                                  │             │
│                                |                                  │             |
│                                |                                  │             │
└────────────────────────────────▲──────────────────────────────────┼─────────────┘
                                 │                                  │
                                 │                                  │
                                 |                                  │
┌───────────────────────────────────────────────────────────────────┼─────────────┐
│ Layer 3: Application (depends_on: otel-collector)                 │             │
├───────────────────────────────────────────────────────────────────┼─────────────┤
│                                                                   │             │
│                        ┌──────────────────────────┐               │             │
│                        │   Flask Backend          │               │             │
│                        │   Instrumented with OTel │               │             │
│                        │   Port: 5000             │───────────────┘             │
│                        └──────────────────────────┘  /metrics endpoint          │
│                                                                                 │
└─────────────────────────────────▲───────────────────────────────────────────────┘
                                  |
                                  │ 
                                  |
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Layer 4: Presentation (depends_on: backend healthy) ★ STRONGEST DEPENDENCY      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                        ┌──────────────────────────┐                             │
│                        │   Nginx Frontend         │                             │
│                        │   Proxies /api/* to      │                             │
│                        │   backend:5000           │                             │
│                        │   Port: 8080             │                             │
│                        └──────────────────────────┘                             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│ Layer 5: Visualization (depends_on: prometheus, tempo, loki)                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                        ┌──────────────────────────┐                             │
│                        │      Grafana             │                             │
│                        │   Queries datasources    │                             │
│                        │   Port: 3000             │                             │
│                        └──────────────────────────┘                             │
│                                 │                                               │
│                 ┌───────────────┼───────────────┐                               │
│                 │               │               │                               │
│                 ▼               ▼               ▼                               │
│          [Query Tempo]   [Query Loki]   [Query Prometheus]                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘


Legend:
═══════
 │/|      Vertical arrows show data flow from Backend upward to storage
 ▲         Data flows up (Backend → OTel Collector → Tempo/Loki)
           Metrics flow up (Backend → Prometheus via scrape)
 ▼         Grafana queries flow down (Grafana → datasources)
 ★         Healthcheck-based dependency (strongest)
```

### Dependency Details from docker-compose.yml

#### Backend Service
```yaml
depends_on:
  - otel-collector
```
**Behavior:** Backend starts after OTel Collector container is created (not necessarily ready).

**Rationale:** Backend needs OTel Collector endpoint available for telemetry export. If collector is unavailable, backend will start but telemetry will be lost until collector is ready.

#### OTel Collector Service
```yaml
depends_on:
  - tempo
  - loki
  - prometheus
```
**Behavior:** OTel Collector starts after Tempo, Loki, and Prometheus containers are created.

**Rationale:** Collector needs backend storage services available to export telemetry data. Order ensures data sinks exist before data producers start.

#### Frontend Service
```yaml
depends_on:
  backend:
    condition: service_healthy
```
**Behavior:** Frontend starts ONLY after backend passes healthcheck (responds successfully to `/metrics` endpoint).

**Rationale:** This is the strongest dependency in the stack. Frontend cannot function without a healthy backend API.

#### Grafana Service
```yaml
depends_on:
  - prometheus
  - tempo
  - loki
```
**Behavior:** Grafana starts after datasource services are created.

**Rationale:** Grafana needs datasources available for provisioning. Datasources are configured via provisioning files at startup.

---

## Startup Orchestration

### Docker Compose Startup Sequence

Based on `docker-compose.yml` dependencies and `start-lab.sh` orchestration:

```
Step 1: Foundation Services (Parallel Startup)
   ├─► Tempo starts
   ├─► Loki starts
   └─► Prometheus starts

Step 2: OTel Collector (Waits for Step 1 containers)
   └─► OTel Collector starts
       └─► Binds to ports: 4317 (gRPC), 4318 (HTTP), 8888, 8889, 13133
       └─► Loads config: /etc/otel-collector-config.yml
       └─► Establishes connections to backends

Step 3: Application Services (Parallel)
   ├─► Backend starts (waits for otel-collector container)
   │   └─► Initializes OpenTelemetry SDK
   │   └─► Creates SQLite database (/app/data/tasks.db)
   │   └─► Registers SQLAlchemy event listeners
   │   └─► Exposes healthcheck endpoint: /metrics
   │   └─► Healthcheck runs every 10s (5 retries, 3s timeout)
   │
   └─► Grafana starts (waits for prometheus, tempo, loki containers)
       └─► Provisions datasources from /etc/grafana/provisioning
       └─► Loads dashboards from /var/lib/grafana/dashboards

Step 4: Frontend (Waits for Backend Health)
   └─► Frontend starts ONLY when backend healthcheck passes
       └─► Nginx serves React static files
       └─► Proxies API requests to backend
```

### start-lab.sh Orchestration Strategy

The `start-lab.sh` script demonstrates the deployment pattern:

```bash
# 1. Clean up existing containers
docker compose -p ${PROJECT} down -v

# 2. Start all services with build
docker compose -p ${PROJECT} up -d --build

# 3. Wait for services to stabilize
sleep 10

# 4. Check service health
# - OTel Collector: http://localhost:13133
# - Flask Backend: http://localhost:5000/health
# - Grafana: http://localhost:3000
# - Prometheus: http://localhost:9090/-/healthy
# - Tempo: http://localhost:3200/ready
# - Loki: http://localhost:3100/ready
```

**Key Observations:**
- Script uses project name `lab` for container management
- 10-second wait allows healthchecks to complete
- Health verification uses actual service endpoints
- No explicit waiting for dependencies (Docker Compose handles it)

---

## Data Flow Architecture

### Telemetry Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Telemetry Data Pipeline                      │
└─────────────────────────────────────────────────────────────────┘

Application Layer (Flask Backend):
┌──────────────────────────────────────────────────────────┐
│ Flask Application (backend/app.py)                       │
│                                                          │
│ OpenTelemetry SDK Initialization:                        │
│  ├─► TracerProvider (Traces)                             │
│  ├─► MeterProvider (Metrics - OTel format)               │
│  └─► LoggerProvider (Logs)                               │
│                                                          │
│ Prometheus Client (Hybrid Metrics):                      │
│  └─► Prometheus metrics exposed at /metrics endpoint     │
└──────────────────────────────────────────────────────────┘
               │                    │
               │ OTLP/HTTP          │ Prometheus Scrape
               │ (Port 4318)        │ (Port 5000/metrics)
               ▼                    ▼
┌──────────────────────────────┐  ┌────────────────────┐
│  OTel Collector (Port 4318)  │  │   Prometheus       │
│                              │  │  (Direct Scrape)   │
│  Receivers:                  │  └────────────────────┘
│   └─► OTLP (HTTP/gRPC)       │
│                              │
│  Processors:                 │
│   ├─► memory_limiter         │
│   ├─► resource (enrichment)  │
│   ├─► attributes (labels)    │
│   └─► batch (aggregation)    │
│                              │
│  Exporters:                  │
│   ├─► Traces → Tempo         │
│   └─► Logs → Loki            │
└──────────────────────────────┘
        │            │
        │            └──────────────┐
        │                           │
        ▼                           ▼
┌─────────────┐           ┌─────────────┐
│   Tempo     │           │    Loki     │
│  (Traces)   │           │   (Logs)    │
│  Port 4317  │           │  Port 3100  │
└─────────────┘           └─────────────┘
        │                           │
        └───────────┬───────────────┘
                    │
                    ▼
            ┌──────────────┐
            │   Grafana    │
            │ (Datasources)│
            │  Port 3000   │
            └──────────────┘
```

### Detailed Data Flow by Signal Type

#### 1. Traces (Distributed Tracing)

**Source:** Flask Backend (OpenTelemetry SDK)

```python
# backend/app.py - Trace Initialization
tracer_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/traces"
)
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)
trace.set_tracer_provider(tracer_provider)
```

**Flow:**
1. Flask requests generate spans (via FlaskInstrumentor)
2. SQLAlchemy queries create child spans (via SQLAlchemyInstrumentor)
3. Spans batched by BatchSpanProcessor
4. Exported via OTLP HTTP to `otel-collector:4318/v1/traces`
5. OTel Collector processes traces:
   ```yaml
   pipelines:
     traces:
       receivers: [otlp]
       processors: [memory_limiter, resource, attributes, batch]
       exporters: [otlp/tempo, logging]
   ```
6. Exported to Tempo via OTLP: `tempo:4317`
7. Tempo stores traces in `/tmp/tempo` volume
8. Grafana queries Tempo via datasource configuration

**Key Configuration:**
- Environment variable: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318`
- Protocol: `http/protobuf`
- Batch size: 1024 spans (collector config)
- Timeout: 10s batch timeout

#### 2. Logs (Structured Logging)

**Source:** Flask Backend (OpenTelemetry LoggerProvider + Python logging)

```python
# backend/app.py - Log Initialization
logger_provider = LoggerProvider(resource=resource)
otlp_log_exporter = OTLPLogExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/logs",
    timeout=5
)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(otlp_log_exporter)
)
```

**Flow:**
1. Application logs generated via Python logging
2. JSON formatting applied (pythonjsonlogger)
3. OTel LoggingHandler captures logs
4. Logs enriched with trace/span IDs
5. Batched and exported via OTLP HTTP to `otel-collector:4318/v1/logs`
6. OTel Collector processes logs:
   ```yaml
   pipelines:
     logs:
       receivers: [otlp]
       processors: [memory_limiter, resource, attributes, attributes/logs, batch]
       exporters: [loki, logging]
   ```
7. Logs enriched with resource attributes:
   - `service.name`
   - `service.instance.id`
   - `deployment.environment`
   - `level` (mapped from severity_text)
8. Exported to Loki: `http://loki:3100/loki/api/v1/push`
9. Loki stores logs with labels in `/loki` volume
10. Grafana queries Loki via datasource configuration

**Key Configuration:**
- Log format: JSON (pythonjsonlogger)
- Loki labels: `service.name`, `service.instance.id`, `deployment.environment`, `level`
- Processor: `attributes/logs` adds Loki-specific label configuration

#### 3. Metrics (Hybrid Strategy)

**IMPORTANT:** The backend uses a hybrid metrics strategy:
- **Prometheus Client:** Primary metrics source for HTTP/DB metrics
- **OpenTelemetry Metrics:** Secondary (OTel SDK database metrics)

**3a. Prometheus Client Metrics (Primary)**

```python
# backend/app.py - Prometheus Metrics
prom_http_requests_total = Counter(...)
prom_http_request_duration_seconds = Histogram(...)
prom_http_errors_total = Counter(...)
prom_db_query_duration_seconds = Histogram(...)

@app.route('/metrics', methods=['GET'])
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
```

**Flow:**
1. Application records metrics using Prometheus client
2. Metrics exposed at `/metrics` endpoint (Prometheus exposition format)
3. Prometheus scrapes backend:5000/metrics every 15s (default)
4. Metrics stored in Prometheus TSDB (`/prometheus` volume)
5. Grafana queries Prometheus via datasource

**Metrics Tracked:**
- `http_requests_total` - Total HTTP requests by method/endpoint/status
- `http_request_duration_seconds` - Request latency histogram
- `http_errors_total` - Error count by endpoint
- `db_query_duration_seconds` - Database query latency by operation type

**3b. OpenTelemetry Metrics (Secondary)**

```python
# backend/app.py - OTel Metrics
meter_provider = MeterProvider(resource=resource)
meter = metrics.get_meter(__name__)
database_query_duration = meter.create_histogram(
    name="database_query_duration_seconds",
    description="Database query duration in seconds",
    unit="s"
)
```

**Flow:**
1. Application records OTel metrics via SDK
2. **NOTE:** No OTLP metrics exporter configured in current implementation
3. Metrics pipeline not active in otel-collector-config.yml

**Architecture Note:** The backend maintains dual instrumentation:
- Prometheus metrics for HTTP/database telemetry (active)
- OTel metrics SDK initialized but not exported (placeholder for future OTLP metrics)

---

## Integration Points

### 1. Backend → OTel Collector Integration

**Protocol:** OTLP over HTTP (protobuf)

**Configuration:**

```python
# backend/app.py
environment:
  - OTEL_SERVICE_NAME=flask-backend
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
  - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
  - OTEL_TRACES_EXPORTER=otlp
  - OTEL_LOGS_EXPORTER=otlp
  - OTEL_RESOURCE_ATTRIBUTES=service.name=flask-backend,service.version=1.0.0,deployment.environment=lab
```

**Endpoints:**
- Traces: `http://otel-collector:4318/v1/traces`
- Logs: `http://otel-collector:4318/v1/logs`

**Retry Behavior:**
- SDK uses BatchSpanProcessor/BatchLogRecordProcessor
- Automatic retries on connection failure
- Telemetry queued in memory until collector available

**Failure Mode:**
- Backend starts even if collector unavailable
- Telemetry lost if collector never becomes available
- No application impact (graceful degradation)

### 2. OTel Collector → Backend Services Integration

**Tempo Integration:**
```yaml
exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
```
- Protocol: OTLP over gRPC
- Port: 4317
- No TLS (internal network)

**Loki Integration:**
```yaml
exporters:
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    tls:
      insecure: true
```
- Protocol: HTTP POST
- Port: 3100
- Loki Push API

**Failure Mode:**
- Collector buffers data in memory (memory_limiter: 512 MiB)
- Retries on backend failure
- Data loss if buffer exceeds limit

### 3. Prometheus → Backend Integration

**Scrape Configuration:**
```yaml
# otel-collector/prometheus.yml (inferred from docker-compose.yml)
scrape_configs:
  - job_name: 'flask-backend'
    static_configs:
      - targets: ['backend:5000']
    metrics_path: '/metrics'
```

**Behavior:**
- Prometheus initiates scrape (pull model)
- Default scrape interval: 15s
- Backend exposes metrics in Prometheus exposition format
- Scrape target: `http://backend:5000/metrics`

**Failure Mode:**
- Scrape failures recorded as `up=0` metric
- Data gap in time series during backend downtime
- Prometheus alerts can detect scrape failures

### 4. Grafana → Datasource Integration

**Datasource Configuration:** Provisioned from `/etc/grafana/provisioning/datasources`

**Expected Datasources:**
- **Prometheus:** `http://prometheus:9090`
- **Tempo:** `http://tempo:3200`
- **Loki:** `http://loki:3100`

**Query Flow:**
1. User opens Grafana dashboard
2. Dashboard panels query respective datasources
3. Datasources fetch data over HTTP APIs
4. Grafana renders visualizations

**Correlation Features:**
- Trace ID correlation between Loki logs and Tempo traces
- Exemplars link Prometheus metrics to Tempo traces
- Unified "Explore" interface for multi-signal investigation

### 5. Frontend → Backend Integration

**Proxy Configuration:** `frontend/default.conf` (inferred from nginx:alpine usage)

**Expected Configuration:**
```nginx
location /api {
    proxy_pass http://backend:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

**Behavior:**
- Nginx serves static React files from `/usr/share/nginx/html`
- API requests proxied to backend service
- CORS handled by Flask-CORS in backend

**Failure Mode:**
- Frontend waits for backend health before starting
- 502 Bad Gateway if backend becomes unhealthy after startup
- Client-side error handling for API failures

---

## Service Communication Matrix

| Source Service | Target Service | Protocol | Port | Purpose | Initiated By |
|---------------|----------------|----------|------|---------|--------------|
| Backend | OTel Collector | OTLP/HTTP | 4318 | Send traces/logs | Backend (push) |
| OTel Collector | Tempo | OTLP/gRPC | 4317 | Export traces | Collector (push) |
| OTel Collector | Loki | HTTP | 3100 | Export logs | Collector (push) |
| Prometheus | Backend | HTTP | 5000 | Scrape metrics | Prometheus (pull) |
| Grafana | Prometheus | HTTP | 9090 | Query metrics | Grafana (pull) |
| Grafana | Tempo | HTTP | 3200 | Query traces | Grafana (pull) |
| Grafana | Loki | HTTP | 3100 | Query logs | Grafana (pull) |
| Frontend | Backend | HTTP | 5000 | API requests | Frontend (pull/push) |
| User | Frontend | HTTP | 8080 | Web UI | External |
| User | Grafana | HTTP | 3000 | Dashboards | External |

**Network:** All services communicate over `otel-network` (Docker bridge network)

**DNS Resolution:** Docker's embedded DNS resolves service names to container IPs

---

## Healthcheck Dependencies

### Backend Healthcheck Configuration

```yaml
healthcheck:
  test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/metrics', timeout=2).read()"]
  interval: 10s
  timeout: 3s
  retries: 5
  start_period: 5s
```

**Behavior:**
- Checks `/metrics` endpoint (not `/health`)
- Runs every 10 seconds
- 5-second grace period before first check
- 5 retries before marking unhealthy
- 3-second timeout per check

**Why `/metrics`?**
- Validates both application health AND Prometheus client functionality
- Single endpoint verifies core application + observability stack
- `/health` endpoint exists but not used in healthcheck

**Frontend Dependency:**
```yaml
depends_on:
  backend:
    condition: service_healthy
```
- Frontend startup blocked until backend passes healthcheck
- Ensures API availability before serving web UI
- Strongest dependency guarantee in the stack

### Other Services

**OTel Collector:**
- Health endpoint: `http://0.0.0.0:13133` (health_check extension)
- No healthcheck defined in docker-compose.yml
- start-lab.sh verifies via `curl http://localhost:13133`

**Prometheus:**
- Health endpoint: `http://0.0.0.0:9090/-/healthy`
- No healthcheck in docker-compose.yml

**Tempo:**
- Ready endpoint: `http://0.0.0.0:3200/ready`
- No healthcheck in docker-compose.yml

**Loki:**
- Ready endpoint: `http://0.0.0.0:3100/ready`
- No healthcheck in docker-compose.yml

**Grafana:**
- Health endpoint: `http://0.0.0.0:3000/api/health`
- No healthcheck in docker-compose.yml

---

## Bootstrap and Initialization

### Backend Service Initialization Sequence

```python
# From backend/app.py - Initialization Order

# 1. Logging Configuration
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(...)
logger.addHandler(logHandler)

# 2. OpenTelemetry Resource Definition
resource = Resource.create({
    "service.name": "flask-backend",
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})

# 3. Tracer Provider Initialization
tracer_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(...)
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)
trace.set_tracer_provider(tracer_provider)

# 4. Meter Provider Initialization
meter_provider = MeterProvider(resource=resource)
metrics.set_meter_provider(meter_provider)

# 5. Logger Provider Initialization
logger_provider = LoggerProvider(resource=resource)
otlp_log_exporter = OTLPLogExporter(...)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(otlp_log_exporter))

# 6. Prometheus Client Metrics
prom_http_requests_total = Counter(...)
prom_http_request_duration_seconds = Histogram(...)
# ... other Prometheus metrics

# 7. Flask Application
app = Flask(__name__)
CORS(app)

# 8. Database Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:////app/data/tasks.db'
db = SQLAlchemy(app)

# 9. Auto-Instrumentation
FlaskInstrumentor().instrument_app(app)
LoggingInstrumentor().instrument(set_logging_format=True)

# 10. Database Initialization (in app context)
with app.app_context():
    os.makedirs('/app/data', exist_ok=True)
    SQLAlchemyInstrumentor().instrument(engine=db.engine)
    db.create_all()

    # 11. SQLAlchemy Event Listeners (for Prometheus metrics)
    event.listen(db.engine, "before_cursor_execute", _before_cursor_execute)
    event.listen(db.engine, "after_cursor_execute", _after_cursor_execute)
    logger.info("Database initialized")

# 12. Request/Response Middleware
@app.before_request
def before_request(): ...

@app.after_request
def after_request(response): ...
```

**Key Observations:**
1. **OTel SDK before Flask app:** Ensures instrumentation ready before app creation
2. **Instrumentation after app creation:** FlaskInstrumentor wraps app after configuration
3. **Database directory creation:** Ensures `/app/data` exists before SQLite access
4. **Event listeners for Prometheus:** Custom hooks for db_query_duration_seconds metric
5. **Middleware hooks:** before_request/after_request handle timing and logging

### OTel Collector Initialization

From `otel-collector-config.yml`:

```yaml
service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, attributes, batch]
      exporters: [otlp/tempo, logging]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, attributes, attributes/logs, batch]
      exporters: [loki, logging]
```

**Startup Sequence:**
1. Load configuration from `/etc/otel-collector-config.yml`
2. Initialize extensions (health_check on port 13133, pprof, zpages)
3. Start receivers (OTLP on ports 4317 gRPC, 4318 HTTP)
4. Initialize processors (memory_limiter, resource enrichment, batching)
5. Connect to exporters (Tempo at tempo:4317, Loki at loki:3100)
6. Begin accepting telemetry data

**CORS Configuration:**
```yaml
receivers:
  otlp:
    protocols:
      http:
        cors:
          allowed_origins:
            - "http://localhost:8080"
            - "http://*"
```
- Allows browser-based OTLP exports (though not used in current architecture)
- Prepared for future frontend instrumentation

### Grafana Provisioning

**Datasource Provisioning:** Loaded from `/etc/grafana/provisioning/datasources`

**Dashboard Provisioning:** Loaded from `/var/lib/grafana/dashboards`

**Startup Sequence:**
1. Start Grafana service
2. Load datasource YAML configurations
3. Connect to Prometheus, Tempo, Loki
4. Load dashboard JSON files
5. Expose UI on port 3000

**Anonymous Access:**
```yaml
environment:
  - GF_AUTH_ANONYMOUS_ENABLED=true
  - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
```
- No authentication required (lab environment)
- Admin role for anonymous users

---

## Network Integration

### Docker Bridge Network

```yaml
networks:
  otel-network:
    driver: bridge
```

**All services connected to `otel-network`:**
- backend
- otel-collector
- tempo
- loki
- prometheus
- grafana
- frontend

**DNS Resolution:**
- Docker's embedded DNS server resolves service names to container IPs
- Example: `otel-collector` resolves to collector's container IP
- Service discovery automatic within the network

### Port Mapping

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Frontend | 80 | 8080 | Web UI access |
| Backend | 5000 | 5000 | API + metrics endpoint |
| Grafana | 3000 | 3000 | Dashboard access |
| Prometheus | 9090 | 9090 | Metrics query UI |
| Tempo | 3200 | 3200 | Trace query API |
| Loki | 3100 | 3100 | Log query API |
| OTel Collector | 4317 | 4317 | OTLP gRPC receiver |
| OTel Collector | 4318 | 4318 | OTLP HTTP receiver |
| OTel Collector | 13133 | 13133 | Health check endpoint |

**Security Note:** All ports exposed for lab access. Production deployment would restrict external access.

---

## Related Documentation

- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - Main architecture overview
- **[Infrastructure Foundation](infrastructure.md)** - VM and virtualization layer
- **[Application Architecture](application.md)** - Flask backend and React frontend
- **[Observability Architecture](observability.md)** - Detailed observability component documentation
- **[Network Architecture](network.md)** - Network topology and CORS configuration
- **[CI/CD Pipeline Architecture](cicd-pipeline.md)** - Jenkins deployment pipeline

---

**Document Changelog:**
- 2025-10-22: Initial creation
- Status: Complete, production-ready
