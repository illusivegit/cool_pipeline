# Configuration Reference

Complete configuration reference for all components in the OpenTelemetry Observability Lab.

## Table of Contents

- [Docker Compose Configuration](#docker-compose-configuration)
- [OpenTelemetry Collector Configuration](#opentelemetry-collector-configuration)
- [Prometheus Configuration](#prometheus-configuration)
- [Grafana Datasource Provisioning](#grafana-datasource-provisioning)
- [Flask Backend Configuration](#flask-backend-configuration)
- [Nginx Configuration](#nginx-configuration)
- [Tempo Configuration](#tempo-configuration)
- [Loki Configuration](#loki-configuration)

---

## Docker Compose Configuration

### Architecture Overview

The `docker-compose.yml` orchestrates 7 services with careful dependency management:

```yaml
version: '3.8'

networks:
  otel-network:
    driver: bridge

volumes:
  backend-data:      # Flask SQLite database
  tempo-data:        # Tempo trace storage
  loki-data:         # Loki log storage
  prometheus-data:   # Prometheus metrics storage
  grafana-data:      # Grafana configuration persistence

services:
  # Service startup order:
  # 1. tempo, loki, prometheus (storage backends)
  # 2. otel-collector (depends on storage backends)
  # 3. grafana (depends on storage backends for provisioning)
  # 4. backend (depends on collector)
  # 5. frontend (no dependencies)
```

### Key Design Decisions

**1. Network Isolation**: All services on `otel-network` bridge network
- Internal DNS resolution (service name = hostname)
- Port exposure only where needed
- Security through network segmentation

**2. Volume Strategy**:
- Named volumes for persistence (survive container recreation)
- Bind mounts for configuration (live editing during development)
- Backend data volume for SQLite database persistence

**3. Environment Variables**:
- OTEL configuration via env vars (12-factor app principle)
- Easy override in different environments
- No hardcoded endpoints in application code

---

## OpenTelemetry Collector Configuration

**File**: `otel-collector/otel-collector-config.yml`

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

processors:
  # Order matters! Processors run in sequence.

  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    # Prevents OOM by rejecting data when near limit
    # Critical for production stability

  resource:
    attributes:
      - key: service.instance.id
        value: ${env:HOSTNAME}
        action: insert
      - key: loki.resource.labels
        value: service.name, service.instance.id, deployment.environment
        action: insert
        # Attribute hint: tells Loki exporter to promote these
        # resource attributes to Loki labels for efficient filtering

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
        # Attribute hint: promotes log-level to Loki label

  batch:
    timeout: 10s
    send_batch_size: 1024
    # Batching reduces network overhead and backend load
    # Trade-off: slight delay vs. efficiency

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    tls:
      insecure: true
    # No 'labels' config needed - using attribute hints in processors

  logging:
    loglevel: info
    sampling_initial: 5
    sampling_thereafter: 200
    # Debug exporter - samples to avoid log spam

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679

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

    # NOTE: No metrics pipeline configured
    # Metrics flow: Flask backend exposes /metrics → Prometheus scrapes directly
    # This is simpler than routing through the OTel Collector
```

### Configuration Rationale

1. **Memory Limiter First**: Protects collector from OOM crashes
2. **Resource Processor**: Enriches all telemetry with common attributes
3. **Attribute Hints**: Modern approach for configuring Loki labels (v0.96.0+)
4. **Batch Processor Last**: Batches after all transformations complete
5. **Multiple Exporters**: Parallel export to storage + debug logging

### Production Tuning

**Memory Limiter**:
```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1024          # Adjust based on available RAM
    spike_limit_mib: 256     # Headroom for spikes
```

**Batch Processor**:
```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 8192     # Increase for high throughput
    send_batch_max_size: 16384
```

**Queuing**:
```yaml
exporters:
  otlp/tempo:
    sending_queue:
      enabled: true
      num_consumers: 10       # Increase for more parallelism
      queue_size: 5000        # Buffer for bursts
```

---

## Prometheus Configuration

**File**: `otel-collector/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'otel-lab'
    environment: 'development'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'flask-backend'
    static_configs:
      - targets: ['backend:5000']
        labels:
          service: 'flask-backend'
    # Scrapes /metrics endpoint exposed by Flask app
    # Contains http_requests_total, http_request_duration_seconds, etc.

  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8888']
        labels:
          service: 'otel-collector'
    # Scrapes OTel Collector's internal metrics

  - job_name: 'tempo'
    static_configs:
      - targets: ['tempo:3200']
        labels:
          service: 'tempo'

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
        labels:
          service: 'loki'

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
        labels:
          service: 'grafana'

# NOTE: No remote_write section!
# This was a critical fix - removed self-referential remote_write
# that caused Prometheus to write to itself in an infinite loop
```

### Metrics Architecture

This lab uses **direct scraping** (not OTel Collector routing):

```
Flask Backend (/metrics) ──scrape──> Prometheus ──query──> Grafana
```

**Why Direct Scraping?**
- Simpler architecture for learning
- No need for OTel Collector metrics pipeline
- Prometheus is excellent at pull-based metrics collection
- Reduces moving parts

**What Prometheus Scrapes:**
1. **flask-backend:5000** - Application metrics (http_requests_total, db_query_duration_seconds)
2. **otel-collector:8888** - Collector internal metrics
3. **prometheus:9090** - Prometheus self-monitoring
4. **tempo, loki, grafana** - Infrastructure metrics

**Critical Fix Applied**: Removed `remote_write` section that pointed back to itself, which created an infinite loop causing memory exhaustion.

### Production Tuning

```yaml
# prometheus.yml
global:
  scrape_interval: 30s      # Reduce frequency (was 15s)
  scrape_timeout: 10s

# Command flags
command:
  - '--storage.tsdb.retention.time=15d'
  - '--storage.tsdb.retention.size=50GB'
  - '--storage.tsdb.wal-compression'  # Enable compression
```

---

## Grafana Datasource Provisioning

**File**: `grafana/provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    uid: prometheus  # ← Explicit UID for cross-datasource references
    isDefault: true
    editable: true
    jsonData:
      httpMethod: POST
      manageAlerts: true
      prometheusType: Prometheus
      prometheusVersion: 2.48.0
      cacheLevel: 'High'
      timeInterval: 15s

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    uid: tempo  # ← Explicit UID
    editable: true
    jsonData:
      httpMethod: GET

      # Trace → Log correlation
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

      # Trace → Metrics correlation
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

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    uid: loki  # ← Explicit UID
    editable: true
    jsonData:
      maxLines: 1000

      # Log → Trace correlation
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

### Correlation Configuration

This configuration creates bidirectional links between all three pillars:

**1. Tempo → Loki (tracesToLogs)**:
- When viewing a trace span, click "Logs for this span"
- Grafana extracts `service.name` from span attributes
- Constructs Loki query: `{service_name="flask-backend"} |= "trace-id-here"`
- Shows logs with matching trace ID from same service

**2. Tempo → Prometheus (tracesToMetrics)**:
- View metrics related to traced operations
- Exemplar linking (Prometheus samples with trace context)
- Jump from trace span to rate/latency metrics

**3. Loki → Tempo (derivedFields)**:
- Regex extracts trace IDs from log messages
- Creates clickable links in log viewer
- Jump from log line to full distributed trace

### Production Configuration

**Grafana Authentication**:
```yaml
environment:
  - GF_AUTH_ANONYMOUS_ENABLED=false
  - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
```

**RBAC Settings**:
```yaml
# grafana.ini
[auth]
disable_login_form = false
disable_signout_menu = false

[auth.basic]
enabled = true

[users]
allow_sign_up = false
allow_org_create = false

[auth.anonymous]
enabled = false

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASSWORD}
secret_key = ${GRAFANA_SECRET_KEY}
```

---

## Flask Backend Configuration

**File**: `backend/app.py`

### OpenTelemetry Resource Configuration

```python
# Resource: Identifies this service in the telemetry system
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "flask-backend"),
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})
```

**Resource attributes are crucial**:
- Attached to EVERY span, metric, log
- Used for filtering and grouping
- Enable multi-environment deployments
- Support service mesh integration

### Tracing Configuration

```python
# Tracer Provider
tracer_provider = TracerProvider(resource=resource)

# OTLP Span Exporter
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/traces"
)

# Batch Span Processor
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)

# Set global tracer provider
trace.set_tracer_provider(tracer_provider)

# Get tracer for manual instrumentation
tracer = trace.get_tracer(__name__)
```

**Why BatchSpanProcessor?**
- Buffers spans in memory
- Sends in batches (reduces network calls)
- Configurable: batch size, timeout
- Production-ready (handles failures gracefully)

**Alternative**: `SimpleSpanProcessor`
- Sends each span immediately
- Good for debugging
- Bad for performance

**Production Tuning**:
```python
from opentelemetry.sdk.trace.export import BatchSpanProcessor

span_processor = BatchSpanProcessor(
    otlp_trace_exporter,
    max_queue_size=2048,        # Default: 2048
    schedule_delay_millis=5000, # Default: 5000 (5s)
    max_export_batch_size=512,  # Default: 512
    export_timeout_millis=30000 # Default: 30000 (30s)
)
```

**Trade-offs**:
- **Larger batch size**: Less network overhead, more memory usage
- **Longer delay**: Less overhead, higher latency in observability
- **Smaller batch size**: Lower memory, more network calls

### Metrics Configuration

```python
# OTLP Metric Exporter
otlp_metric_exporter = OTLPMetricExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/metrics"
)

# Periodic Exporting Metric Reader
metric_reader = PeriodicExportingMetricReader(
    otlp_metric_exporter,
    export_interval_millis=5000  # Export every 5 seconds
)

# Meter Provider
meter_provider = MeterProvider(
    resource=resource,
    metric_readers=[metric_reader]
)
metrics.set_meter_provider(meter_provider)

# Get meter for creating instruments
meter = metrics.get_meter(__name__)
```

**Metric Instruments**:

**1. Counter**: Monotonically increasing value
```python
request_counter = meter.create_counter(
    name="http_requests_total",
    description="Total number of HTTP requests",
    unit="1"
)

# Usage
request_counter.add(1, {
    "method": request.method,
    "endpoint": request.endpoint,
    "status_code": str(response.status_code)
})
```

**2. Histogram**: Distribution of values
```python
request_duration = meter.create_histogram(
    name="http_request_duration_seconds",
    description="HTTP request duration in seconds",
    unit="s"
)

# Usage
request_duration.record(duration, {
    "method": request.method,
    "endpoint": request.endpoint
})
```

**Why these metric types?**
- **Counter**: For calculating rates (req/sec, errors/sec)
- **Histogram**: For percentiles (p50, p95, p99 latency)
- Both support labels/attributes for grouping

### Logs Configuration

```python
# Logger Provider
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)

# OTLP Log Exporter
otlp_log_exporter = OTLPLogExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/logs",
    timeout=5
)

# Batch Log Record Processor
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(otlp_log_exporter)
)

# Logging Handler (bridges stdlib logging to OTel)
otel_log_handler = LoggingHandler(
    level=logging.INFO,
    logger_provider=logger_provider
)
logging.getLogger().addHandler(otel_log_handler)
```

**Dual logging setup**:
```python
# Structured JSON to stdout (for kubectl logs, docker logs)
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(
    '%(asctime)s %(name)s %(levelname)s %(message)s %(trace_id)s %(span_id)s'
)
logHandler.setFormatter(formatter)
logger = logging.getLogger()
logger.addHandler(logHandler)

# OTLP to collector (for Loki, aggregation)
logger.addHandler(otel_log_handler)
```

**Benefits**:
- Stdout logs: Easy kubectl/docker debugging
- OTLP logs: Centralized aggregation, correlation, querying

### Automatic Instrumentation

```python
# Flask HTTP instrumentation
FlaskInstrumentor().instrument_app(app)

# SQLAlchemy database instrumentation
with app.app_context():
    SQLAlchemyInstrumentor().instrument(engine=db.engine)

# Logging instrumentation
LoggingInstrumentor().instrument(set_logging_format=True)
```

**What FlaskInstrumentor does**:
- Creates span for every HTTP request
- Captures HTTP method, route, status code
- Propagates trace context (W3C Trace Context headers)
- Handles exceptions

**What SQLAlchemyInstrumentor does**:
- Creates span for every database query
- Captures SQL statement (sanitized)
- Records query duration
- Links to parent HTTP span

### Manual Instrumentation

```python
@app.route('/api/tasks', methods=['POST'])
def create_task():
    with tracer.start_as_current_span("create_task") as span:
        try:
            data = request.get_json()

            # Custom span attributes
            span.set_attribute("task.title", data['title'])
            span.set_attribute("validation.failed", False)

            # Business logic
            new_task = Task(title=data['title'], ...)
            db.session.add(new_task)
            db.session.commit()

            span.set_attribute("task.id", new_task.id)

            return jsonify(new_task.to_dict()), 201

        except Exception as e:
            # Record exception in span
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))

            # Also log
            logger.error(f"Error creating task: {str(e)}", exc_info=True)

            return jsonify({"error": "Failed to create task"}), 500
```

**When to manually instrument**:
- Business-specific operations
- Domain logic spans (create_order, process_payment)
- Custom attributes (user_id, order_amount)
- Fine-grained performance tracking

### Middleware Configuration

```python
@app.before_request
def before_request():
    request.start_time = time.time()
    current_span = trace.get_current_span()
    logger.info(
        "Incoming request",
        extra={
            "method": request.method,
            "path": request.path,
            "trace_id": format(current_span.get_span_context().trace_id, '032x'),
            "span_id": format(current_span.get_span_context().span_id, '016x')
        }
    )

@app.after_request
def after_request(response):
    if hasattr(request, 'start_time'):
        duration = time.time() - request.start_time

        # Record metrics
        request_counter.add(1, {
            "method": request.method,
            "endpoint": request.endpoint or "unknown",
            "status_code": str(response.status_code)
        })

        request_duration.record(duration, {
            "method": request.method,
            "endpoint": request.endpoint or "unknown",
            "status_code": str(response.status_code)
        })

        # Track errors for SLI
        if response.status_code >= 400:
            error_counter.add(1, {
                "method": request.method,
                "endpoint": request.endpoint or "unknown",
                "status_code": str(response.status_code)
            })

        # Log response
        current_span = trace.get_current_span()
        logger.info(
            "Request completed",
            extra={
                "method": request.method,
                "path": request.path,
                "status_code": response.status_code,
                "duration_seconds": duration,
                "trace_id": format(current_span.get_span_context().trace_id, '032x'),
                "span_id": format(current_span.get_span_context().span_id, '016x')
            }
        )

    return response
```

**Why middleware?**
- Centralized request/response logging
- Consistent metric collection
- Automatic correlation (trace ID in logs)
- No code duplication across endpoints

---

## Nginx Configuration

For detailed Nginx configuration including proxy_pass options and DNS resolver settings, see [architecture/network.md](architecture/network.md).

**Key Configuration Points:**

```nginx
# DNS resolver for Docker internal DNS
resolver 127.0.0.11 ipv6=off valid=30s;

# Variable-based proxy_pass (prevents DNS caching)
set $backend_upstream http://backend:5000;
proxy_pass $backend_upstream;

# CORS headers (defense-in-depth with Flask-CORS)
add_header 'Access-Control-Allow-Origin' '*' always;
add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization' always;
```

---

## Tempo Configuration

**File**: `tempo/tempo.yml`

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
    wal:
      path: /tmp/tempo/wal
```

### Production Configuration

```yaml
# tempo.yml
storage:
  trace:
    backend: s3
    s3:
      bucket: tempo-traces
      endpoint: s3.amazonaws.com
    pool:
      max_workers: 50         # Parallel workers
      queue_depth: 10000
    wal:
      path: /tmp/tempo/wal
      encoding: snappy         # Compression
    block:
      encoding: zstd           # Better compression

compactor:
  compaction:
    block_retention: 48h
```

---

## Loki Configuration

**File**: `loki/loki-config.yml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

### Production Configuration

```yaml
# loki-config.yml
limits_config:
  ingestion_rate_mb: 10      # MB per second per tenant
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb
  retention_period: 7d

chunk_store_config:
  max_look_back_period: 7d

compactor:
  retention_enabled: true
  retention_delete_delay: 2h
```

---

## Environment Variables

### Backend Service

```yaml
environment:
  - FLASK_ENV=production
  - OTEL_SERVICE_NAME=flask-backend
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
  - OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
  - PYTHONDONTWRITEBYTECODE=1
```

### OTel Collector

```yaml
environment:
  - HOSTNAME=${HOSTNAME}
```

### Grafana

```yaml
environment:
  - GF_AUTH_ANONYMOUS_ENABLED=true
  - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
  - GF_SECURITY_ADMIN_PASSWORD=admin
```

---

**Document Version**: 1.0
**Last Updated**: October 22, 2025
**Lab Version**: OpenTelemetry Collector 0.96.0

---

**Phase 1 Documentation Set v1.0** | Last Reviewed: October 22, 2025
