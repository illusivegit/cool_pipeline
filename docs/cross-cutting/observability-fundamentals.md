# Observability Fundamentals

## The Three Pillars of Observability

This document explains the fundamental concepts of observability that apply across all phases of this project.

### Overview

Modern observability is built on three pillars: **Traces**, **Metrics**, and **Logs**. Each pillar provides a different perspective on system behavior, and together they enable comprehensive understanding of distributed systems.

---

## Pillar 1: Traces (Distributed Tracing)

### What Are Traces?

**Traces** track the journey of a single request as it flows through multiple services in a distributed system.

**Key Concepts:**
- **Trace:** The complete journey of a request from start to finish
- **Span:** A single unit of work within a trace (e.g., database query, HTTP call)
- **Parent-Child Relationship:** Spans form a tree showing call hierarchy
- **Trace Context:** Propagated metadata (trace_id, span_id) that links spans together

### Trace Structure

```
Trace (e5ce58dede162ea2d04bd82c0ef6de2)
│
├─ Span: GET /api/tasks (root)
│   ├─ Span: flask.request_handler
│   │   ├─ Span: db.query (SELECT * FROM tasks)
│   │   └─ Span: json.serialize
│   └─ Span: http.response
```

### W3C Trace Context

**Standard:** [W3C Trace Context](https://www.w3.org/TR/trace-context/)

**Headers:**
- `traceparent`: `00-{trace-id}-{parent-span-id}-{trace-flags}`
- `tracestate`: Vendor-specific context

**Example:**
```
traceparent: 00-e5ce58dede162ea2d04bd82c0ef6de2-938a0f3756ee9632-01
```

### Benefits of Tracing

✅ **Performance Analysis:** Find slow operations in request path
✅ **Dependency Mapping:** Understand service interactions
✅ **Root Cause Analysis:** Trace errors back to origin
✅ **Request Correlation:** Link all data for a single request

---

## Pillar 2: Metrics (Time-Series Data)

### What Are Metrics?

**Metrics** are numerical measurements aggregated over time windows, providing quantitative insights into system behavior.

**Characteristics:**
- **Aggregated:** Not per-request, but over time periods
- **Cheap to store:** Much smaller than traces/logs
- **Queryable:** Support mathematical operations (rate, avg, percentile)
- **Alertable:** Easy to define thresholds

### Metric Types

#### 1. Counter
**Monotonically increasing value (only goes up or resets to zero)**

Examples:
- `http_requests_total{status="200"}`
- `http_errors_total{status="500"}`

**Usage:**
```promql
# Request rate over 5 minutes
rate(http_requests_total[5m])

# Total requests in last hour
increase(http_requests_total[1h])
```

#### 2. Gauge
**Point-in-time value that can go up or down**

Examples:
- `memory_usage_bytes`
- `active_connections`
- `queue_depth`

**Usage:**
```promql
# Current memory usage
memory_usage_bytes

# Average CPU over 5 minutes
avg_over_time(cpu_usage_percent[5m])
```

#### 3. Histogram
**Bucket-based distribution of values**

Examples:
- `http_request_duration_seconds_bucket{le="0.1"}`
- `db_query_duration_seconds_bucket{le="0.05"}`

**Usage:**
```promql
# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P50 (median) latency
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
```

**Bucket Structure:**
```
le="0.01"  count=100  (requests < 10ms)
le="0.05"  count=250  (requests < 50ms)
le="0.1"   count=400  (requests < 100ms)
le="0.5"   count=480  (requests < 500ms)
le="+Inf"  count=500  (all requests)
```

#### 4. Summary
**Pre-calculated quantiles (less common with Prometheus)**

Examples:
- `rpc_duration_seconds{quantile="0.99"}`

---

## Pillar 3: Logs (Structured Events)

### What Are Logs?

**Logs** are discrete events with timestamps and contextual information about what happened.

**Characteristics:**
- **Event-based:** Each log is a single occurrence
- **High cardinality:** Can contain unique values
- **Detailed:** Rich contextual information
- **Expensive:** Large volume, storage-intensive

### Structured Logging

**Unstructured (Bad):**
```
2025-10-20 12:00:00 User login failed for john@example.com
```

**Structured (Good):**
```json
{
  "timestamp": "2025-10-20T12:00:00Z",
  "level": "ERROR",
  "message": "User login failed",
  "user_email": "john@example.com",
  "ip_address": "192.168.1.100",
  "trace_id": "e5ce58dede162ea2d04bd82c0ef6de2",
  "span_id": "938a0f3756ee9632"
}
```

### Log Levels

| Level | Usage | Example |
|-------|-------|---------|
| **DEBUG** | Detailed diagnostic info | Variable values, function entry/exit |
| **INFO** | General informational | "Service started", "Request received" |
| **WARN** | Potentially harmful situations | "Disk 80% full", "Retry attempt 3/5" |
| **ERROR** | Error events | "Database connection failed" |
| **FATAL** | Severe errors causing shutdown | "Out of memory" |

### Trace-Log Correlation

**Best Practice:** Include `trace_id` and `span_id` in log entries

```json
{
  "level": "INFO",
  "message": "Database query executed",
  "trace_id": "e5ce58dede162ea2d04bd82c0ef6de2",
  "span_id": "facf232a4b884085",
  "duration_ms": 45,
  "rows_returned": 10
}
```

**Benefit:** Click trace_id in logs → Jump to distributed trace view

---

## How the Three Pillars Work Together

### Single Request Example

**Scenario:** User loads task list

#### 1. Trace Captures Journey
```
Browser → Nginx → Flask → Database
  100ms    5ms     40ms     30ms
```

#### 2. Metrics Aggregate Over Time
```promql
http_request_duration_seconds{
  endpoint="/api/tasks",
  method="GET"
}
P95: 150ms
P99: 250ms
Average: 100ms
```

#### 3. Logs Provide Details
```json
{"timestamp": "2025-10-20T12:00:00Z", "trace_id": "abc123", "message": "Fetched 10 tasks"}
{"timestamp": "2025-10-20T12:00:00Z", "trace_id": "abc123", "message": "Database query slow", "duration_ms": 250}
```

### Query Workflow

**Problem:** "Why is the app slow?"

1. **Check Metrics:** P95 latency is 500ms (normally 100ms)
2. **Find Slow Traces:** Query for traces with `duration > 500ms`
3. **Analyze Trace:** See database query taking 400ms
4. **Check Logs:** Find `trace_id` in logs, see query details
5. **Root Cause:** Database is waiting on lock

---

## SLI/SLO Framework

### Service Level Indicator (SLI)

**Definition:** A quantitative measure of service level

**Common SLIs:**
- **Availability:** Percentage of successful requests
- **Latency:** Percentage of requests faster than threshold
- **Error Rate:** Percentage of failed requests

**Example:**
```promql
# Availability SLI
100 * (
  sum(rate(http_requests_total{status=~"2.."}[5m])) /
  sum(rate(http_requests_total[5m]))
)
# Result: 99.8% (good)
```

### Service Level Objective (SLO)

**Definition:** Target value for an SLI

**Examples:**
- Availability: **99.9%** of requests succeed
- Latency: **95%** of requests < 500ms
- Error Rate: **< 0.1%** of requests fail

### Service Level Agreement (SLA)

**Definition:** Contractual commitment with consequences

**Example:**
- **SLA:** 99.9% uptime per month
- **Penalty:** 10% refund if < 99.9%

**Relationship:**
- SLA (99.9%) > SLO (99.95%) > SLI (actual: 99.97%)
- **Error Budget:** 99.95% target - 99.97% actual = +0.02% buffer

---

## OpenTelemetry (OTel)

### What Is OpenTelemetry?

**Open-source** observability framework providing:
- Vendor-neutral APIs and SDKs
- Automatic instrumentation for popular frameworks
- Standardized data formats (OTLP)

### OTel Architecture

```
Application (instrumented)
  ↓
OTel SDK (in-process)
  ↓
OTel Collector (separate service)
  ↓
Backend (Tempo, Prometheus, Loki)
```

### OTel Components

#### 1. SDK
**Embedded in application code**

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

# Initialize tracer
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Create span
with tracer.start_as_current_span("process_request"):
    # Your code here
    pass
```

#### 2. Auto-Instrumentation
**Automatically instruments libraries**

```bash
# Python example
opentelemetry-instrument python app.py
```

**Automatically captures:**
- HTTP requests (Flask, FastAPI, etc.)
- Database queries (SQLAlchemy, psycopg2)
- gRPC calls
- Redis operations

#### 3. Collector
**Receives, processes, and exports telemetry**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  otlp/tempo:
    endpoint: tempo:4317
  prometheus:
    endpoint: 0.0.0.0:8889

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

---

## Best Practices

### Tracing Best Practices

✅ **DO:**
- Propagate trace context across all service boundaries
- Include meaningful span names (operation, not file names)
- Add semantic attributes (http.method, db.statement)
- Sample traces in production (not 100%)

❌ **DON'T:**
- Create spans for every function call (too granular)
- Include sensitive data in span attributes
- Block on span creation (async/background)

### Metrics Best Practices

✅ **DO:**
- Use histograms for latency (not averages)
- Include cardinality-bounded labels only
- Name metrics consistently (component_operation_unit)
- Set appropriate bucket boundaries

❌ **DON'T:**
- Use high-cardinality labels (user_id, trace_id)
- Create unbounded metrics (memory leak)
- Use metrics for event logging (use logs)

### Logging Best Practices

✅ **DO:**
- Use structured logging (JSON)
- Include trace_id/span_id for correlation
- Log at appropriate levels
- Sanitize sensitive data

❌ **DON'T:**
- Log at DEBUG level in production (volume)
- Include passwords/tokens in logs
- Log every request (use sampling)

---

## Tools Used in This Project

### Phase 1 Stack

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Traces** | Tempo | Storage and querying (TraceQL) |
| **Metrics** | Prometheus | Time-series database (PromQL) |
| **Logs** | Loki | Log aggregation (LogQL) |
| **Visualization** | Grafana | Unified dashboards |
| **Collection** | OTel Collector | Telemetry pipeline |

### Data Flow

```
Flask App (instrumented)
  ↓ OTLP/HTTP
OTel Collector
  ├─ Traces → Tempo (port 4317)
  ├─ Metrics → Prometheus (scrape :8889)
  └─ Logs → Loki (OTLP)
        ↓
    Grafana (queries all three)
```

---

## Query Language Quick Reference

### PromQL (Prometheus)

```promql
# Request rate
rate(http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Availability
100 * (1 - (sum(rate(http_errors_total[5m])) / sum(rate(http_requests_total[5m]))))
```

### LogQL (Loki)

```logql
# All logs from flask-backend
{service_name="flask-backend"}

# Filter by level
{service_name="flask-backend", level="ERROR"}

# Search for trace
{service_name="flask-backend"} |= "trace_id=abc123"
```

### TraceQL (Tempo)

```traceql
# All traces from flask-backend
{ resource.service.name = "flask-backend" }

# Slow requests
{ duration > 500ms }

# Errors on specific endpoint
{ span.http.target = "/api/tasks" && status = error }
```

---

## Further Reading

### Official Documentation
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana Tempo](https://grafana.com/docs/tempo/)
- [Grafana Loki](https://grafana.com/docs/loki/)

### Books
- **"Observability Engineering"** by Charity Majors, Liz Fong-Jones, George Miranda
- **"Distributed Tracing in Practice"** by Austin Parker, et al.
- **"Google SRE Book"** - SLI/SLO chapters

### Phase-Specific Docs
- [Phase 1 Architecture](../phase-1-docker-compose/ARCHITECTURE.md)
- [TraceQL Reference](traceql-reference.md)
- [PromQL Reference](promql-reference.md)

---
