# Observability Architecture

**Part of:** [Phase 1 System Architecture](../ARCHITECTURE.md)
**Version:** 1.1 (Updated October 22, 2025)
**Status:** Production-Ready

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Architecture Overview](#architecture-overview)
- [The Three Pillars Implementation](#the-three-pillars-implementation)
- [OpenTelemetry Collector Configuration](#opentelemetry-collector-configuration)
- [Grafana Integration](#grafana-integration)
- [Data Flow Diagrams](#data-flow-diagrams)
- [Code-to-Architecture Mapping](#code-to-architecture-mapping)
- [Network Endpoints and Ports](#network-endpoints-and-ports)
- [Verification and Testing](#verification-and-testing)
- [Design Decisions](#design-decisions)
- [Future Enhancements](#future-enhancements)
- [Summary](#summary)

---

## Executive Summary

This document details the observability architecture for the Flask-based task management application deployed on KVM/QEMU infrastructure. The system implements the **three pillars of observability**: traces, metrics, and logs using OpenTelemetry (OTel) and the Prometheus/Grafana ecosystem.

### Key Architecture Principle

**Hybrid Approach: Separation of Concerns**

- **OpenTelemetry SDK** handles distributed tracing (traces) and structured logging (logs)
- **Prometheus Client** handles application metrics directly
- **OTel Collector** routes traces and logs to backend storage
- **Prometheus** scrapes metrics directly from Flask `/metrics` endpoint

This eliminates metric duplication while preserving full distributed tracing capabilities and trace-log correlation.

### Stack Components

| Component | Version | Purpose | Protocol |
|-----------|---------|---------|----------|
| OpenTelemetry Collector | 0.96.0 | Telemetry pipeline (traces/logs) | OTLP/HTTP, OTLP/gRPC |
| Prometheus | 2.48.1 | Metrics storage and query | HTTP scrape |
| Tempo | 2.3.1 | Distributed trace storage | OTLP/gRPC |
| Loki | 2.9.3 | Log aggregation | OTLP/HTTP |
| Grafana | 10.2.3 | Unified visualization | HTTP/API |

---

## Architecture Overview

### High-Level System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER / BROWSER                              │
│                     (http://VM_IP:8080)                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    FRONTEND (NGINX:80)                              │
│  • Serves static HTML/CSS/JS                                        │
│  • Proxies /api/* → backend:5000/api/*                              │
│  • Dynamic links to observability tools                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  FLASK BACKEND (Port 5000)                          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ INSTRUMENTATION LAYER                                         │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │ ① OpenTelemetry SDK (Traces & Logs)                          [] []
│  │    • FlaskInstrumentor: HTTP request/response spans           │  │
│  │    • SQLAlchemyInstrumentor: Database query spans             │  │
│  │    • OTLP Exporter → collector:4318                           │  │
│  │                                                               │  │
│  │ ② Prometheus Client (Metrics)                                [] [] 
│  │    • http_requests_total (Counter)                            │  │
│  │    • http_request_duration_seconds (Histogram)                │  │
│  │    • http_errors_total (Counter)                              │  │
│  │    • db_query_duration_seconds (Histogram)                    │  │
│  │    • Exposed at /metrics endpoint                             │  │
│  │                                                               │  │
│  │ ③ OTel Metrics (Not exported to Prometheus)                  [] [] 
│  │    • database_query_duration_seconds (Histogram)              │  │
│  │    • Kept for potential future OTLP metrics pipeline          │  │
│  │                                                               │  │
│  │ ④ SQLite Database                                            [] []
│  │    • /app/data/tasks.db (persistent volume)                   │  │
│  └───────────────────────────────────────────────────────────────┘  │
└────────────────────────┬──────────────────┬─────────────────────────┘
                         │                  │
                         │ OTLP             │ Prometheus scrape
                         │ (traces/logs)    │ (metrics /metrics)
                         │                  │
                         ▼                  ▼
┌────────────────────────────────┐  ┌──────────────────────────────┐
│  OTEL COLLECTOR (Port 4318)    │  │  PROMETHEUS (Port 9090)      │
│  ┌──────────────────────────┐  │  │  ┌────────────────────────┐  │
│  │ Receivers:               │  │  │  │ Scrape Configs:        │  │
│  │  • otlp (gRPC: 4317)     │  │  │  │  • flask-backend:5000  │  │
│  │  • otlp (HTTP: 4318)     │  │  │  │  • otel-collector:8888 │  │
│  │                          │  │  │  │  • tempo:3200          │  │
│  │ Processors:              │  │  │  │  • loki:3100           │  │
│  │  • memory_limiter        │  │  │  │  • grafana:3000        │  │
│  │  • resource              │  │  │  │                        │  │
│  │  • attributes            │  │  │  │ Storage: TSDB          │  │
│  │  • attributes/logs       │  │  │  │ Retention: 15 days     │  │
│  │  • batch                 │  │  │  └────────────────────────┘  │
│  │                          │  │  └──────────────────────────────┘
│  │ Exporters:               │  │
│  │  • otlp/tempo (traces)   │  │
│  │  • loki (logs)           │  │
│  │  • logging (debug)       │  │
│  │                          │  │
│  │ Extensions:              │  │
│  │  • health_check:13133    │  │
│  │  • pprof:1777            │  │
│  │  • zpages:55679          │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
                │
                │
                ▼
┌──────────────────────────────────────────────────────────────┐
│                    STORAGE BACKENDS                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ TEMPO        │  │ LOKI         │  │ PROMETHEUS   │        │
│  │ (Traces)     │  │ (Logs)       │  │ (Metrics)    │        │
│  │ Port: 3200   │  │ Port: 3100   │  │ Port: 9090   │        │
│  │ Storage:     │  │ Storage:     │  │ Storage:     │        │
│  │ /tmp/tempo   │  │ /loki        │  │ /prometheus  │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└──────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     GRAFANA (Port 3000)                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Data Sources:                                             │  │
│  │  • Prometheus (uid: prometheus) - metrics queries         │  │
│  │  • Tempo (uid: tempo) - trace queries                     │  │
│  │  • Loki (uid: loki) - log queries                         │  │
│  │                                                           │  │
│  │ Pre-Configured Features:                                  │  │
│  │  • Tempo → Loki trace correlation                         │  │
│  │  • Tempo → Prometheus metrics correlation                 │  │
│  │  • Loki → Tempo trace_id linking                          │  │
│  │                                                           │  │
│  │ Dashboards:                                               │  │
│  │  • SLI/SLO Dashboard - service availability, latency      │  │
│  │  • End-to-End Tracing - distributed request flows         │  │
│  │  • Explore - ad-hoc queries across all data sources       │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## The Three Pillars Implementation

### Pillar 1: Traces (Distributed Tracing)

**Technology:** OpenTelemetry SDK + Tempo

**Implementation in backend/app.py:**

```python
# Lines 37-50: Tracer Provider Setup
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "flask-backend"),
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})

tracer_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/traces"
)
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)
```

**Auto-Instrumentation:**

```python
# Lines 106-107: Automatic instrumentation
FlaskInstrumentor().instrument_app(app)
SQLAlchemyInstrumentor().instrument(engine=db.engine)
```

**Manual Spans:**

```python
# Example from lines 227-240
@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    with tracer.start_as_current_span("get_all_tasks") as span:
        query_start = time.time()
        tasks = Task.query.all()
        query_duration_time = time.time() - query_start

        span.set_attribute("db.query.duration", query_duration_time)
        span.set_attribute("db.result.count", len(tasks))
        # ...
```

**What Gets Traced:**

- HTTP requests (method, path, status code, duration)
- Database queries (SQL statements, duration, result count)
- Custom application logic (task operations)
- Errors and exceptions (automatic recording)

---

### Pillar 2: Metrics (Time-Series Data)

**Technology:** Prometheus Client Library (Direct Scrape)

**Implementation in backend/app.py:**

```python
# Lines 74-97: Prometheus Client Metrics
prom_http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

prom_http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'status_code']
)

prom_http_errors_total = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['method', 'endpoint', 'status_code']
)

prom_db_query_duration_seconds = Histogram(
    'db_query_duration_seconds',
    'SQLite query duration in seconds',
    ['operation'],
    buckets=(0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2)
)
```

**Metric Collection:**

```python
# Lines 173-202: After-request metric recording
@app.after_request
def after_request(response):
    if hasattr(request, 'start_time'):
        duration = time.time() - request.start_time
        method = request.method
        endpoint = request.endpoint or "unknown"
        status_code = str(response.status_code)

        # Record Prometheus client metrics (exposed at /metrics)
        if hasattr(g, 'prom_start_time'):
            prom_duration = time.time() - g.prom_start_time
            prom_http_requests_total.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).inc()

            prom_http_request_duration_seconds.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).observe(prom_duration)

            if response.status_code >= 400:
                prom_http_errors_total.labels(
                    method=method,
                    endpoint=endpoint,
                    status_code=status_code
                ).inc()
```

**Metrics Endpoint:**

```python
# Lines 419-421: Prometheus scrape endpoint
@app.route('/metrics', methods=['GET'])
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
```

**What Gets Metrified:**

- HTTP request counts (by method, endpoint, status)
- HTTP request duration (histogram with percentiles)
- HTTP error counts (status >= 400)
- Database query duration (by operation type: SELECT, INSERT, UPDATE, DELETE)

---

### Pillar 3: Logs (Structured Events)

**Technology:** OpenTelemetry LoggingHandler + Python stdlib logging + Loki

**Implementation in backend/app.py:**

```python
# Lines 28-35: JSON Structured Logging Setup
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(
    '%(asctime)s %(name)s %(levelname)s %(message)s %(trace_id)s %(span_id)s'
)
logHandler.setFormatter(formatter)
logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)
```

**OTel Log Export:**

```python
# Lines 56-66: OTel Log Provider
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)

otlp_log_exporter = OTLPLogExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/logs",
    timeout=5
)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(otlp_log_exporter))

otel_log_handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().addHandler(otel_log_handler)
```

**Automatic Trace Correlation:**

```python
# Lines 162-171: Before-request logging with trace context
@app.before_request
def before_request():
    current_span = trace.get_current_span()
    logger.info(
        "Incoming request",
        extra={
            "method": request.method,
            "path": request.path,
            "trace_id": format(current_span.get_span_context().trace_id, '032x') if current_span else None,
            "span_id": format(current_span.get_span_context().span_id, '016x') if current_span else None
        }
    )
```

**What Gets Logged:**

- Incoming requests (with trace_id and span_id)
- Request completion (with duration and status)
- Database operations (query counts, smoke tests)
- Errors and warnings
- Application-specific events (task creation, updates, deletions)

---

## OpenTelemetry Collector Configuration

**File:** `otel-collector/otel-collector-config.yml`

### Receivers

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - "http://localhost:8080"
            - "http://*"
          allowed_headers:
            - "*"
```

**Purpose:** Accept traces and logs from Flask backend via OTLP protocol

---

### Processors

```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

  resource:
    attributes:
      - key: service.instance.id
        value: ${env:HOSTNAME}
        action: insert
      - key: loki.resource.labels
        value: service.name, service.instance.id, deployment.environment
        action: insert

  memory_limiter:
    check_interval: 1s
    limit_mib: 512

  attributes:
    actions:
      - key: environment
        value: "lab"
        action: insert

  attributes/logs:
    actions:
      - key: service.name
        from_context: resource
        action: insert
      - key: service.instance.id
        from_context: resource
        action: insert
      - key: level
        from_attribute: severity_text
        action: insert
      - key: loki.attribute.labels
        value: level
        action: insert
```

**Purpose:**
- **batch:** Improves efficiency by batching telemetry
- **resource:** Adds service identification metadata
- **memory_limiter:** Prevents OOM conditions
- **attributes:** Enriches spans/logs with environment context
- **attributes/logs:** Prepares logs for Loki label extraction

---

### Exporters

```yaml
exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    tls:
      insecure: true

  logging:
    loglevel: info
    sampling_initial: 5
    sampling_thereafter: 200
```

**Purpose:**
- **otlp/tempo:** Sends traces to Tempo for storage
- **loki:** Sends logs to Loki for aggregation
- **logging:** Debug output (sampled to avoid noise)

**Note:** NO Prometheus exporters. Metrics go directly from Flask to Prometheus.

---

### Extensions

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679
```

**Purpose:** Operational utilities (health checks, profiling, debug pages)

---

### Service Pipelines

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

**Key Point:** No `metrics` pipeline. Prometheus scrapes Flask directly.

---

## Grafana Integration

**File:** `grafana/provisioning/datasources/datasources.yml`

### Prometheus Datasource

```yaml
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus:9090
  uid: prometheus
  isDefault: true
  editable: true
  jsonData:
    manageAlerts: true
    prometheusType: Prometheus
    prometheusVersion: 2.48.0
    cacheLevel: 'High'
    timeInterval: 15s
```

**Purpose:** Query metrics for SLI/SLO dashboards

---

### Tempo Datasource

```yaml
- name: Tempo
  type: tempo
  access: proxy
  url: http://tempo:3200
  uid: tempo
  editable: true
  jsonData:
    httpMethod: GET
    tracesToLogs:
      datasourceUid: 'loki'
      tags: ['otelTraceID']
      mappedTags: [{ key: 'service.name', value: 'service_name' }]
      mapTagNamesEnabled: true
      spanStartTimeShift: '-1h'
      spanEndTimeShift: '1h'
      filterByTraceID: true
      filterBySpanID: false
      customQuery: true
      query: '{service_name="${__span.tags["service.name"]}"} |= "${__trace.traceId}"'
    tracesToMetrics:
      datasourceUid: 'prometheus'
      tags: [{ key: 'service.name', value: 'service' }]
      queries:
        - name: 'Request Rate'
          query: 'rate(http_requests_total{$$__tags}[5m])'
        - name: 'Error Rate'
          query: 'rate(http_errors_total{$$__tags}[5m])'
    serviceMap:
      datasourceUid: 'prometheus'
    search:
      hide: false
    nodeGraph:
      enabled: true
    lokiSearch:
      datasourceUid: 'loki'
```

**Purpose:**
- Query traces
- Enable trace → log correlation (click trace_id → jump to logs)
- Enable trace → metrics correlation (view request rate/errors for trace)

---

### Loki Datasource

```yaml
- name: Loki
  type: loki
  access: proxy
  url: http://loki:3100
  uid: loki
  editable: true
  jsonData:
    maxLines: 1000
    derivedFields:
      - datasourceUid: tempo
        matcherRegex: '"otelTraceID":"([0-9a-f]+)"'
        name: TraceID
        url: '$${__value.raw}'
      - datasourceUid: tempo
        matcherRegex: 'otelTraceID=([0-9a-f]+)'
        name: otelTraceID
        url: '$${__value.raw}'
```

**Purpose:**
- Query logs
- Enable log → trace correlation (extract trace_id from logs → link to Tempo)

---

## Data Flow Diagrams

### Complete Request Flow

```
1. User Request
   Browser → http://VM_IP:8080/api/tasks
      ↓
2. Nginx Proxy
   frontend:80/api/* → backend:5000/api/*
      ↓
3. Flask @app.before_request
   • Start timer (g.prom_start_time)
   • Log "Incoming request" (includes trace_id)
   • OTel creates root span
      ↓
4. Route Handler (e.g., GET /api/tasks)
   • OTel span: "get_all_tasks"
   • Span attributes: endpoint, method
      ↓
5. Database Query
   • SQLAlchemy auto-instrumentation creates child span
   • Span name: "SELECT /app/data/tasks.db"
   • Record duration in span attributes
   • Prometheus histogram: db_query_duration_seconds
      ↓
6. Flask @app.after_request
   • Calculate request duration
   • Increment Prometheus metrics:
     - prom_http_requests_total.labels(...).inc()
     - prom_http_request_duration_seconds.labels(...).observe(duration)
   • Log "Request completed" (includes trace_id, span_id, duration)
   • OTel closes spans
      ↓
7. Background Export (Async)
   • OTel spans → OTLP → Collector → Tempo
   • OTel logs → OTLP → Collector → Loki
   • Prometheus scrapes /metrics every 15s
      ↓
8. Grafana Queries
   • Tempo: Fetch trace by trace_id
   • Prometheus: Query http_requests_total{job="flask-backend"}
   • Loki: Query logs with {service_name="flask-backend"} |= "trace_id"
```

---

### Traces Flow

```
┌──────────────┐
│ Flask Route  │
│  Handler     │ ① Creates span with FlaskInstrumentor
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ SQLAlchemy   │
│  Query       │ ② Creates child span with SQLAlchemyInstrumentor
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│BatchSpanProcessor| ③ Batches spans (10s timeout)
└──────┬───────────┘
       │
       ▼ OTLP/HTTP
┌──────────────────┐
│ OTel Collector   │ ④ Receives spans at :4318/v1/traces
│  (receiver: otlp)│    Adds resource attributes
└──────┬───────────┘
       │
       ▼ OTLP/gRPC
┌──────────────────┐
│ Tempo            │ ⑤ Stores traces in /tmp/tempo
│  (port 3200)     │
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ Grafana          │ ⑥ Queries traces via Tempo datasource
│  (Explore/       │    Example: trace ID lookup from log
│   Dashboard)     │    TraceQL: {duration > 500ms}
└──────────────────┘
```

---

### Metrics Flow

```
┌──────────────┐
│ Flask Request│
│  Middleware  │ ① Increments prometheus_client counters/histograms
└──────┬───────┘
       │
       ▼
┌─────────────────────┐
│ /metrics Endpoint   │ ② Exposes metrics in Prometheus text format
│  (GET /metrics)     │    Example: http_requests_total{...} 42
└──────┬──────────────┘
       │
       ▼ HTTP Scrape (15s interval)
┌─────────────────────┐
│ Prometheus          │ ③ Scrapes backend:5000/metrics
│  (scrape_config:    │    job="flask-backend"
│   flask-backend)    │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Prometheus TSDB     │ ④ Stores time-series data
│  (retention: 15d)   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Grafana             │ ⑤ Queries via Prometheus datasource
│  (SLI/SLO Dashboard)│    Example: rate(http_requests_total[5m])
└─────────────────────┘
```

---

### Logs Flow

```
┌──────────────┐
│ Flask Logger │
│  (stdlib)    │ ① Emits log with trace_id in extra fields
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ LoggingHandler   │ ② OTel bridges stdlib logs to OTel LogRecordProcessor
│  (OTel SDK)      │
└──────┬───────────┘
       │
       ▼
┌────────────────────────┐
│ BatchLogRecordProcessor│ ③ Batches log records
└──────┬─────────────────┘
       │
       ▼ OTLP/HTTP
┌──────────────────┐
│ OTel Collector   │ ④ Receives logs at :4318/v1/logs
│  (receiver: otlp)│    Adds resource attributes
│                  │    Extracts Loki labels (service_name, level)
└──────┬───────────┘
       │
       ▼ HTTP Push
┌──────────────────┐
│ Loki             │ ⑤ Stores logs with labels:
│  (port 3100)     │    {service_name="flask-backend", level="INFO"}
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ Grafana          │ ⑥ Queries logs via Loki datasource
│  (Explore/Logs)  │    Can filter by trace_id for correlation
│                  │    LogQL: {service_name="flask-backend"} |= "error"
└──────────────────┘
```

---

## Code-to-Architecture Mapping

### Backend: `backend/app.py`

#### OpenTelemetry Initialization (Lines 37-50)

**Source Code:**
```python
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "flask-backend"),
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})

tracer_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/traces"
)
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)
```

**Maps to:** Traces pillar in architecture, OTLP endpoint configuration

---

#### OTel Meter Provider (Lines 52-54)

**Source Code:**
```python
meter_provider = MeterProvider(resource=resource)
metrics.set_meter_provider(meter_provider)
meter = metrics.get_meter(__name__)
```

**Maps to:** OTel metrics SDK (currently not exported to Prometheus)

---

#### OTel Metrics Histogram (Lines 68-72)

**Source Code:**
```python
database_query_duration = meter.create_histogram(
    name="database_query_duration_seconds",
    description="Database query duration in seconds",
    unit="s"
)
```

**Maps to:** OTel metrics (kept for future OTLP metrics pipeline, not currently used in dashboards)

**Note:** This is distinct from the Prometheus `db_query_duration_seconds` histogram. Both exist in code for hybrid architecture.

---

#### Prometheus Client Metrics (Lines 74-97)

**Source Code:**
```python
prom_http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

prom_http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'status_code']
)

prom_http_errors_total = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['method', 'endpoint', 'status_code']
)

prom_db_query_duration_seconds = Histogram(
    'db_query_duration_seconds',
    'SQLite query duration in seconds',
    ['operation'],
    buckets=(0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2)
)
```

**Maps to:** Metrics pillar → Prometheus scrape flow, SLI/SLO dashboard queries

---

#### Before Request Middleware (Lines 158-171)

**Source Code:**
```python
@app.before_request
def before_request():
    request.start_time = time.time()
    g.prom_start_time = time.time()
    current_span = trace.get_current_span()
    logger.info(
        "Incoming request",
        extra={
            "method": request.method,
            "path": request.path,
            "trace_id": format(current_span.get_span_context().trace_id, '032x') if current_span else None,
            "span_id": format(current_span.get_span_context().span_id, '016x') if current_span else None
        }
    )
```

**Maps to:** Request flow step 3, log-trace correlation

---

#### After Request Middleware (Lines 173-217)

**Source Code:**
```python
@app.after_request
def after_request(response):
    if hasattr(request, 'start_time'):
        duration = time.time() - request.start_time
        method = request.method
        endpoint = request.endpoint or "unknown"
        status_code = str(response.status_code)

        # Record Prometheus client metrics (exposed at /metrics)
        # This is the ONLY source of metrics for Prometheus now
        if hasattr(g, 'prom_start_time'):
            prom_duration = time.time() - g.prom_start_time
            prom_http_requests_total.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).inc()

            prom_http_request_duration_seconds.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).observe(prom_duration)

            if response.status_code >= 400:
                prom_http_errors_total.labels(
                    method=method,
                    endpoint=endpoint,
                    status_code=status_code
                ).inc()
```

**Maps to:** Request flow step 6, metrics flow step 1

---

#### /metrics Endpoint (Lines 419-421)

**Source Code:**
```python
@app.route('/metrics', methods=['GET'])
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
```

**Maps to:** Metrics flow step 2, Prometheus scrape target

---

### Docker Compose: `docker-compose.yml`

#### Backend Service (Lines 2-26)

**Source Code:**
```yaml
backend:
  build: ./backend
  container_name: flask-backend
  ports:
    - "5000:5000"
  environment:
    - OTEL_SERVICE_NAME=flask-backend
    - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
    - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
    - OTEL_TRACES_EXPORTER=otlp
    - OTEL_LOGS_EXPORTER=otlp
    - OTEL_RESOURCE_ATTRIBUTES=service.name=flask-backend,service.version=1.0.0,deployment.environment=lab
  volumes:
    - ./backend:/app
    - backend-data:/app/data
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/metrics', timeout=2).read()"]
    interval: 10s
    timeout: 3s
    retries: 5
    start_period: 5s
  depends_on:
    - otel-collector
  networks:
    - otel-network
```

**Maps to:** Flask backend configuration, OTel endpoint configuration, healthcheck via /metrics

---

#### OTel Collector Service (Lines 28-45)

**Source Code:**
```yaml
otel-collector:
  image: otel/opentelemetry-collector-contrib:0.96.0
  container_name: otel-collector
  command: ["--config=/etc/otel-collector-config.yml"]
  volumes:
    - ./otel-collector/otel-collector-config.yml:/etc/otel-collector-config.yml
  ports:
    - "4317:4317"  # OTLP gRPC
    - "4318:4318"  # OTLP HTTP
    - "8888:8888"  # Prometheus metrics (collector self-metrics)
    - "8889:8889"  # (Not used - legacy prometheus exporter port)
    - "13133:13133"  # Health check
  depends_on:
    - tempo
    - loki
    - prometheus
  networks:
    - otel-network
```

**Maps to:** OTel collector architecture, OTLP receiver endpoints

---

#### Prometheus Service (Lines 72-88)

**Source Code:**
```yaml
prometheus:
  image: prom/prometheus:v2.48.1
  container_name: prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--web.console.libraries=/etc/prometheus/console_libraries'
    - '--web.console.templates=/etc/prometheus/consoles'
    - '--web.enable-lifecycle'
    - '--web.enable-remote-write-receiver'
  volumes:
    - ./otel-collector/prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus-data:/prometheus
  ports:
    - "9090:9090"
  networks:
    - otel-network
```

**Maps to:** Prometheus configuration, metrics storage backend

---

### Prometheus Config: `otel-collector/prometheus.yml`

#### Flask Backend Scrape (Lines 19-23)

**Source Code:**
```yaml
- job_name: 'flask-backend'
  static_configs:
    - targets: ['backend:5000']
      labels:
        service: 'flask-backend'
```

**Maps to:** Metrics flow step 3 - Prometheus scrapes /metrics from Flask

---

### Grafana Datasources: `grafana/provisioning/datasources/datasources.yml`

#### Prometheus Datasource (Lines 4-16)

**Source Code:**
```yaml
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus:9090
  uid: prometheus
  isDefault: true
  editable: true
  jsonData:
    manageAlerts: true
    prometheusType: Prometheus
    prometheusVersion: 2.48.0
    cacheLevel: 'High'
    timeInterval: 15s
```

**Maps to:** Grafana → Prometheus query path for SLI dashboards

---

#### Tempo Datasource with Correlations (Lines 18-52)

**Source Code:**
```yaml
- name: Tempo
  type: tempo
  access: proxy
  url: http://tempo:3200
  uid: tempo
  editable: true
  jsonData:
    httpMethod: GET
    tracesToLogs:
      datasourceUid: 'loki'
      tags: ['otelTraceID']
      mappedTags: [{ key: 'service.name', value: 'service_name' }]
      mapTagNamesEnabled: true
      spanStartTimeShift: '-1h'
      spanEndTimeShift: '1h'
      filterByTraceID: true
      filterBySpanID: false
      customQuery: true
      query: '{service_name="${__span.tags["service.name"]}"} |= "${__trace.traceId}"'
    tracesToMetrics:
      datasourceUid: 'prometheus'
      tags: [{ key: 'service.name', value: 'service' }]
      queries:
        - name: 'Request Rate'
          query: 'rate(http_requests_total{$$__tags}[5m])'
        - name: 'Error Rate'
          query: 'rate(http_errors_total{$$__tags}[5m])'
```

**Maps to:** Trace → Log correlation, Trace → Metrics correlation

---

## Network Endpoints and Ports

### External Access (From Host Machine)

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| Frontend | 8080 | http://VM_IP:8080 | User interface |
| Grafana | 3000 | http://VM_IP:3000 | Observability dashboards |
| Prometheus | 9090 | http://VM_IP:9090 | Metrics query UI |
| Tempo | 3200 | http://VM_IP:3200 | Trace API (Grafana uses this) |
| Loki | 3100 | http://VM_IP:3100 | Log API (Grafana uses this) |
| OTel Collector | 4317 | - | OTLP gRPC (internal only) |
| OTel Collector | 4318 | - | OTLP HTTP (internal only) |
| OTel Collector | 13133 | http://VM_IP:13133/health | Health check |
| Backend | 5000 | - | Internal (proxied via Nginx) |

---

### Internal Docker Network Communication

| Source | Target | Protocol | Purpose |
|--------|--------|----------|---------|
| Frontend (Nginx) | backend:5000 | HTTP | API proxy |
| Backend | otel-collector:4318 | OTLP/HTTP | Traces & logs export |
| OTel Collector | tempo:4317 | OTLP/gRPC | Trace storage |
| OTel Collector | loki:3100 | HTTP | Log storage |
| Prometheus | backend:5000/metrics | HTTP | Metrics scrape |
| Prometheus | otel-collector:8888/metrics | HTTP | Collector self-metrics |
| Grafana | prometheus:9090 | HTTP | Metrics queries |
| Grafana | tempo:3200 | HTTP | Trace queries |
| Grafana | loki:3100 | HTTP | Log queries |

---

## Verification and Testing

### Post-Deployment Checks

#### 1. Verify Single Metric Source

```bash
# Access Prometheus UI: http://VM_IP:9090
# Run query:
count by (__name__, job) (http_requests_total)

# Expected Output:
# http_requests_total{job="flask-backend"} = 1
# (Only ONE job, not two! No "otel-collector-prometheus-exporter" job)
```

---

#### 2. Test /metrics Endpoint

```bash
curl http://VM_IP:5000/metrics | grep http_requests

# Expected Output:
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
# http_requests_total{endpoint="get_tasks",method="GET",status_code="200"} 15.0
```

---

#### 3. Verify Traces in Tempo

1. Access Grafana: http://VM_IP:3000
2. Navigate to **Explore** → Select **Tempo** datasource
3. Click **Search** tab
4. Service Name: `flask-backend`
5. Click **Run Query**

**Expected:** See traces with spans like:
- `GET /api/tasks`
- `SELECT /app/data/tasks.db`

---

#### 4. Verify Logs in Loki

1. Grafana → **Explore** → Select **Loki** datasource
2. Query: `{service_name="flask-backend"} |= "Request completed"`

**Expected:** Logs with fields:
- `trace_id`
- `span_id`
- `duration_seconds`
- `status_code`

---

#### 5. Verify Trace-Log Correlation

1. In Tempo trace view, find a trace
2. Click on a span
3. Look for **Logs for this span** button
4. Click it

**Expected:** Jumps to Loki with logs filtered by trace_id

---

#### 6. SLI Dashboard

1. Navigate to: http://VM_IP:3000
2. Go to **Dashboards** → **SLI/SLO Dashboard**

**Expected panels:**
- Service Availability (SLI): ~100% (if no errors)
- Request Rate by Endpoint: Non-zero lines
- P95 Response Time: Latency data
- Error Rate: Near 0%

---

#### 7. OTel Collector Health

```bash
curl http://VM_IP:13133/health

# Expected:
# {"status":"Server available"}
```

---

## Design Decisions

### Why Hybrid Metrics Architecture?

**Decision:** Use Prometheus Client for metrics, NOT OTel SDK metrics

**Rationale:**

1. **Eliminated Duplication:** Previously had two sources for same metrics (`job="flask-backend"` and `job="otel-collector-prometheus-exporter"`), causing double-counting in dashboards

2. **Simpler Architecture:** Direct scrape is more straightforward than OTLP → Collector → Prometheus export

3. **OTel Traces are the Real Value:** Distributed tracing and span context is where OTel shines. Metrics are simpler and don't need collector processing.

4. **No Dashboard Changes:** Prometheus queries work immediately without filtering by job label

5. **Prometheus Client is Purpose-Built:** Designed specifically for app-level SLI metrics

**Trade-off Accepted:**

We lose the ability to send application metrics through the OTel collector for enrichment. However:
- Metrics are simple counters/histograms (no complex processing needed)
- Traces provide the distributed context we need
- Prometheus client metrics are sufficient for SLI/SLO dashboards

**Evidence in Code:**

```python
# Lines 182-184 comment in backend/app.py:
# Record Prometheus client metrics (exposed at /metrics)
# This is the ONLY source of metrics for Prometheus now
```

**Hybrid Architecture Summary:**

| Pillar | Technology | Export Path |
|--------|------------|-------------|
| **Traces** | OTel SDK | OTLP → Collector → Tempo |
| **Metrics** | Prometheus Client | HTTP scrape → Prometheus |
| **Logs** | OTel SDK | OTLP → Collector → Loki |

---

### Why Keep OTel Metrics in Code?

**Decision:** Keep `meter.create_histogram("database_query_duration_seconds")` even though not exported

**Rationale:**

1. **Future-Proofing:** Easy to enable OTLP metrics pipeline in Phase 2 if needed
2. **Dual Instrumentation:** Also have `prom_db_query_duration_seconds` for Prometheus
3. **Minimal Overhead:** Histogram creation without export is negligible
4. **Demonstrating Hybrid Approach:** Shows both methods coexisting

---

### Why OTLP HTTP Instead of gRPC for Backend?

**Decision:** Backend uses `http://otel-collector:4318` (HTTP) not port 4317 (gRPC)

**Rationale:**

1. **Simpler Dependencies:** No gRPC Python libraries needed in backend
2. **Easier Debugging:** HTTP traffic can be inspected with standard tools
3. **Collector Converts:** Collector receives HTTP and exports gRPC to Tempo (optimal)

**Source:**
```python
# backend/app.py line 45
endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/traces"
```

---

## Future Enhancements

### Short-Term (Phase 2)

#### 1. Span Metrics from Tempo

**Goal:** Generate RED metrics (Request rate, Error rate, Duration) automatically from traces

**Implementation:**
```yaml
# tempo.yml
metrics_generator:
  processor:
    service_graphs:
      dimensions: [http.method, http.target]
  storage:
    path: /tmp/tempo/generator
```

**Benefit:** Automatic metrics without manual instrumentation

---

#### 2. Exemplars in Prometheus

**Goal:** Link Prometheus metrics to example traces

**Implementation:**
```python
# Add exemplar support to Prometheus histograms
prom_http_request_duration_seconds.observe(
    duration,
    exemplar={'trace_id': trace_id}
)
```

**Benefit:** Click spike in graph → jump to example trace

---

#### 3. Custom Business Metrics

**Goal:** Track domain-specific metrics

**Examples:**
```python
tasks_created_total = Counter('tasks_created_total', 'Total tasks created')
tasks_completed_total = Counter('tasks_completed_total', 'Total tasks completed')
task_completion_duration = Histogram('task_completion_duration_seconds', 'Time to complete task')
```

---

### Mid-Term (Phase 3)

#### 1. Alert Rules

**Goal:** Automated SLO violation alerts

**Implementation:**
```yaml
# prometheus_rules.yml
groups:
  - name: slo_violations
    rules:
      - alert: HighErrorRate
        expr: rate(http_errors_total[5m]) / rate(http_requests_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate exceeds 1% threshold"
```

---

#### 2. Frontend → Backend Trace Propagation

**Goal:** Full browser-to-database trace visualization

**Implementation:**
```javascript
// frontend: Inject W3C Trace Context header
fetch('/api/tasks', {
  headers: {
    'traceparent': `00-${traceId}-${spanId}-01`
  }
})
```

---

### Long-Term (Phase 4+)

#### 1. Multi-Environment Observability

**Goal:** Centralized Grafana querying dev/staging/prod

**Architecture:**
```
Grafana Central
  ├─ Prometheus (dev)
  ├─ Prometheus (staging)
  ├─ Prometheus (prod)
  ├─ Tempo (centralized)
  └─ Loki (centralized)
```

---

#### 2. Trace Sampling Strategies

**Goal:** Reduce trace storage costs in production

**Implementation:**
```yaml
# otel-collector-config.yml
processors:
  probabilistic_sampler:
    sampling_percentage: 10  # Sample 10% of traces
```

---

## Summary

This observability architecture achieves:

✅ **Single Source of Truth** - Prometheus metrics come only from prometheus_client
✅ **Full Distributed Tracing** - OTel traces flow to Tempo with automatic SQLAlchemy instrumentation
✅ **Correlated Logs** - Automatic trace_id injection enables log→trace navigation
✅ **Clean Separation** - OTel handles distributed context, Prometheus handles app metrics
✅ **No Duplication** - Eliminated double-counting and dashboard confusion
✅ **Production-Ready** - SLI/SLO dashboards work out-of-the-box
✅ **Environment-Agnostic** - Works seamlessly across localhost, VM, and cloud deployments
✅ **Comprehensive Coverage** - Traces, metrics, and logs all integrated

### Key Architectural Insights

1. **Hybrid is OK:** Mixing OTel and Prometheus Client is a valid pattern when each tool plays to its strengths

2. **Correlation is King:** The real power is trace_id linking traces/logs/metrics, not which library generated them

3. **Simplicity Wins:** Direct Prometheus scrape is simpler than OTLP → Collector → Prometheus export for metrics

4. **Infrastructure as Code:** All observability configuration is version-controlled and reproducible

---

**Document Version:** 1.1
**Last Updated:** October 22, 2025
**Source Files:**
- backend/app.py (instrumentation code)
- docker-compose.yml (service configuration)
- otel-collector/otel-collector-config.yml (collector pipelines)
- otel-collector/prometheus.yml (scrape configuration)
- grafana/provisioning/datasources/datasources.yml (Grafana datasources)

---

**Related Documentation:**

- [Infrastructure Foundation](infrastructure.md) - VM and virtualization setup
- [CI/CD Pipeline Architecture](cicd-pipeline.md) - Jenkins deployment pipeline
- [Application Architecture](application.md) - Flask backend and React frontend
- [Main Architecture Document](../ARCHITECTURE.md) - Overview and navigation
- [Design Decisions](../DESIGN-DECISIONS.md) - Rationale for technical choices
- [Observability Fundamentals](../../cross-cutting/observability-fundamentals.md) - Three pillars concepts
