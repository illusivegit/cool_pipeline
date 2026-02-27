# LogQL Query Reference

## Overview

**LogQL** (Log Query Language) is Grafana Loki's query language for searching, filtering, and aggregating log data.

**Version:** Loki 2.9.3+
**Related:** [Observability Fundamentals](observability-fundamentals.md), [PromQL Reference](promql-reference.md), [TraceQL Reference](traceql-reference.md)

---

## Table of Contents

- [Basic Syntax](#basic-syntax)
- [Log Stream Selectors](#log-stream-selectors)
- [Log Pipeline](#log-pipeline)
- [Parsers](#parsers)
- [Filters](#filters)
- [Label Formatters](#label-formatters)
- [Metric Queries](#metric-queries)
- [Aggregations](#aggregations)
- [Common Patterns](#common-patterns)
- [Trace Correlation](#trace-correlation)
- [Best Practices](#best-practices)
- [Performance Tips](#performance-tips)

---

## Basic Syntax

### Simple Log Stream Query

```logql
{label="value"}
```

**Examples:**
```logql
# All logs from flask-backend
{service_name="flask-backend"}

# All logs with level ERROR
{level="ERROR"}

# All logs from specific instance
{instance="192.168.122.250:5000"}
```

---

## Log Stream Selectors

### Label Matching

#### Equality Matcher
```logql
{service_name="flask-backend"}
```

#### Inequality Matcher
```logql
{level!="DEBUG"}
```

#### Regex Matcher
```logql
{service_name=~"flask-.*"}
```

#### Negative Regex Matcher
```logql
{service_name!~"test-.*"}
```

### Multiple Labels

```logql
{service_name="flask-backend", level="ERROR", environment="production"}
```

### Label Existence

```logql
# Logs that have trace_id label
{trace_id!=""}

# Logs that have any error-related label
{error!=""}
```

---

## Log Pipeline

LogQL pipelines transform log lines through a series of stages using the `|` operator.

### Pipeline Syntax

```logql
{label="value"} | stage1 | stage2 | stage3
```

### Pipeline Stages

1. **Line Filter** - Filter log lines by content
2. **Parser** - Extract labels from log lines
3. **Label Filter** - Filter by extracted labels
4. **Label Formatter** - Modify or add labels
5. **Unwrap** - Extract numeric values for metrics

---

## Filters

### Line Contains Filter

```logql
# Logs containing "database"
{service_name="flask-backend"} |= "database"

# Logs NOT containing "health"
{service_name="flask-backend"} != "health"

# Regex match
{service_name="flask-backend"} |~ "error|failed|exception"

# Negative regex match
{service_name="flask-backend"} !~ "debug|trace"
```

### Case-Insensitive Filters

```logql
# Case-insensitive contains
{service_name="flask-backend"} |~ "(?i)error"

# Case-insensitive not contains
{service_name="flask-backend"} !~ "(?i)debug"
```

### Multiple Filters

```logql
# Logs containing "POST" but not "health"
{service_name="flask-backend"} |= "POST" != "/health"

# Chain multiple conditions
{service_name="flask-backend"}
  |= "database"
  |~ "SELECT|INSERT|UPDATE"
  != "health_check"
```

---

## Parsers

### JSON Parser

For structured JSON logs:

```logql
{service_name="flask-backend"} | json
```

**Extracts all JSON fields as labels:**
```json
{"level":"ERROR","message":"Database connection failed","trace_id":"abc123"}
```

**Becomes labels:**
- `level="ERROR"`
- `message="Database connection failed"`
- `trace_id="abc123"`

### Specific Field Extraction

```logql
# Extract specific fields
{service_name="flask-backend"} | json level, trace_id, span_id

# Rename extracted fields
{service_name="flask-backend"} | json log_level="level", tid="trace_id"
```

### Nested JSON Fields

```logql
# Extract nested field
{service_name="flask-backend"} | json request_method="request.method"

# Multiple nested fields
{service_name="flask-backend"}
  | json
    request_path="request.path",
    response_status="response.status"
```

### Logfmt Parser

For key=value formatted logs:

```logql
{service_name="app"} | logfmt
```

**Example log line:**
```
level=error method=POST path=/api/tasks status=500
```

**Becomes labels:**
- `level="error"`
- `method="POST"`
- `path="/api/tasks"`
- `status="500"`

### Regex Parser

Extract fields using regular expressions:

```logql
{service_name="nginx"}
  | regexp `(?P<method>\w+) (?P<path>\/[^\s]+) .* (?P<status>\d{3})`
```

**Example log line:**
```
POST /api/tasks HTTP/1.1 200
```

**Extracts:**
- `method="POST"`
- `path="/api/tasks"`
- `status="200"`

### Pattern Parser

Template-based extraction:

```logql
{service_name="app"}
  | pattern `<level> <timestamp> <message>`
```

---

## Label Filters

### Filter by Extracted Labels

After parsing, filter by the extracted labels:

```logql
# Parse JSON, then filter by extracted level
{service_name="flask-backend"}
  | json
  | level="ERROR"

# Multiple label filters
{service_name="flask-backend"}
  | json
  | level="ERROR"
  | response_status=~"5.."

# Numeric comparisons
{service_name="flask-backend"}
  | json
  | response_status >= 500

# Duration comparisons
{service_name="flask-backend"}
  | json
  | duration > 1s
```

---

## Label Formatters

### line_format

Reformat the log line output:

```logql
{service_name="flask-backend"}
  | json
  | line_format "{{.level}} - {{.message}}"
```

### label_format

Add or modify labels:

```logql
{service_name="flask-backend"}
  | json
  | label_format level=`{{ToUpper .level}}`
```

**Available functions:**
- `ToUpper` / `ToLower` - Change case
- `Replace` - Replace text
- `Trim` - Remove whitespace
- `regexReplaceAll` - Regex replacement

**Examples:**
```logql
# Uppercase level
| label_format level=`{{ToUpper .level}}`

# Extract first part of path
| label_format endpoint=`{{regexReplaceAll "/([^/]+).*" .path "${1}"}}`

# Combine labels
| label_format full_name=`{{.first_name}} {{.last_name}}`
```

---

## Metric Queries

### Count Over Time

```logql
# Error logs per second (5-minute window)
rate({service_name="flask-backend", level="ERROR"}[5m])

# Log volume by service
sum(rate({job="flask-backend"}[5m])) by (service_name)
```

### count_over_time()

Count log lines in a range:

```logql
# Number of errors in last 5 minutes
count_over_time({service_name="flask-backend", level="ERROR"}[5m])

# Errors per endpoint
sum(count_over_time({service_name="flask-backend"} | json | level="ERROR" [5m])) by (path)
```

### rate()

Calculate per-second rate:

```logql
# Error rate per second
rate({service_name="flask-backend", level="ERROR"}[5m])

# 5xx error rate per endpoint
sum(rate({service_name="flask-backend"} | json | response_status=~"5.." [5m])) by (path)
```

### bytes_over_time() / bytes_rate()

Measure log volume in bytes:

```logql
# Bytes of logs per second
bytes_rate({service_name="flask-backend"}[5m])

# Total bytes in time range
bytes_over_time({service_name="flask-backend"}[1h])
```

---

## Aggregations

### sum

```logql
# Total error rate across all instances
sum(rate({service_name="flask-backend", level="ERROR"}[5m]))

# Error rate by level
sum(rate({service_name="flask-backend"}[5m])) by (level)
```

### avg / max / min

```logql
# Average log rate per instance
avg(rate({service_name="flask-backend"}[5m])) by (instance)

# Maximum error rate
max(rate({level="ERROR"}[5m]))

# Minimum log volume
min(bytes_rate({service_name="flask-backend"}[5m]))
```

### topk / bottomk

```logql
# Top 5 endpoints by error rate
topk(5,
  sum(rate({service_name="flask-backend", level="ERROR"}[5m])) by (path)
)

# Bottom 3 services by log volume
bottomk(3,
  sum(bytes_rate({job=~".+"}[5m])) by (service_name)
)
```

---

## Unwrap for Numeric Metrics

Extract numeric values from logs for quantile calculations:

### Duration Quantiles

```logql
# P95 request duration from logs
quantile_over_time(0.95,
  {service_name="flask-backend"}
    | json
    | unwrap duration [5m]
)

# P99 database query time
quantile_over_time(0.99,
  {service_name="flask-backend"}
    | json
    | line_format=""
    | unwrap db_duration [5m]
)
```

### Aggregated Unwrapped Metrics

```logql
# Average request duration by endpoint
avg_over_time(
  {service_name="flask-backend"}
    | json
    | unwrap duration [5m]
) by (path)

# Sum of bytes processed
sum_over_time(
  {service_name="app"}
    | json
    | unwrap bytes_processed [5m]
)
```

---

## Common Patterns

### Error Tracking

```logql
# All errors in last hour
{service_name="flask-backend", level="ERROR"}

# Errors with trace IDs
{service_name="flask-backend"}
  | json
  | level="ERROR"
  | trace_id!=""

# Errors by type
{service_name="flask-backend"}
  | json
  | level="ERROR"
  | line_format "{{.error_type}}: {{.message}}"
```

### Request Tracking

```logql
# All POST requests
{service_name="flask-backend"}
  | json
  | request_method="POST"

# Slow requests (>1 second)
{service_name="flask-backend"}
  | json
  | duration > 1s

# Failed requests (5xx)
{service_name="flask-backend"}
  | json
  | response_status=~"5.."
```

### Search by Specific Field

```logql
# Find logs for specific user
{service_name="flask-backend"}
  | json
  | user_id="12345"

# Find logs for specific trace
{service_name="flask-backend"}
  | json
  | trace_id="abc123xyz"

# Find logs mentioning specific resource
{service_name="flask-backend"}
  |= "task_id"
  | json
  | task_id="456"
```

---

## Trace Correlation

### Finding Logs for a Trace

```logql
# All logs for specific trace
{service_name="flask-backend"}
  | json
  | trace_id="a1b2c3d4e5f6"

# Logs with trace context (trace_id exists)
{service_name="flask-backend"}
  | json
  | trace_id!=""
```

### Linking Traces to Logs in Grafana

When configuring Loki datasource in Grafana:

```yaml
# grafana/provisioning/datasources/datasources.yml
datasources:
  - name: Loki
    type: loki
    uid: loki
    url: http://loki:3100
    jsonData:
      # Enable trace-to-log correlation
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: '"trace_id":\s*"(\w+)"'
          name: TraceID
          url: '$${__value.raw}'
```

This makes trace_ids clickable links that jump to Tempo traces.

---

## Best Practices

### 1. Use Stream Selectors First

❌ **Slow:**
```logql
{job="flask-backend"} |= "error"
```

✅ **Faster:**
```logql
{job="flask-backend", level="ERROR"}
```

**Why:** Stream selectors use index, line filters scan all logs.

### 2. Limit Label Cardinality

❌ **Avoid:**
```logql
{user_id="12345"}  # Unique per user
```

✅ **Prefer:**
```logql
{service_name="flask-backend", level="ERROR"}  # Limited values
```

### 3. Parse Only What You Need

❌ **Unnecessary:**
```logql
{service_name="flask-backend"} | json  # Extracts all fields
```

✅ **Efficient:**
```logql
{service_name="flask-backend"} | json level, message  # Only needed fields
```

### 4. Use Appropriate Time Ranges

```logql
# Short range for recent debugging (5m-1h)
{service_name="flask-backend", level="ERROR"}[5m]

# Longer range for trend analysis (24h-7d)
sum(count_over_time({service_name="flask-backend"}[24h]))
```

### 5. Filter Early in Pipeline

❌ **Inefficient:**
```logql
{service_name="flask-backend"}
  | json
  | level="ERROR"  # Parses all logs first
```

✅ **Efficient:**
```logql
{service_name="flask-backend"}
  |= "ERROR"  # Filter first
  | json
  | level="ERROR"
```

### 6. Index Critical Labels

Configure Loki to index labels you query frequently:

```yaml
# loki-config.yml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
```

**Index these labels:**
- `service_name`
- `level`
- `environment`
- `deployment_name`

**Don't index:**
- `trace_id` (high cardinality)
- `user_id` (high cardinality)
- `message` (full-text search via line filters)

---

## Performance Tips

### 1. Use Label Matchers for Initial Filtering

```logql
# Good - uses indexed labels
{service_name="flask-backend", level="ERROR"}

# Bad - scans all streams
{job=~".+"} |= "error"
```

### 2. Avoid Full Log Scans

```logql
# Avoid querying all logs
{}  # ❌ Very expensive

# Always specify at least one label
{service_name="flask-backend"}  # ✅ Filtered
```

### 3. Limit Query Time Ranges

```logql
# Prefer shorter ranges
{service_name="flask-backend"}[5m]

# Avoid very long ranges in dashboards
{service_name="flask-backend"}[30d]  # Expensive
```

### 4. Use Recording Rules (Upcoming Feature)

Pre-aggregate common queries (when Loki supports recording rules).

### 5. Optimize Chunk Size

Configure appropriate chunk target size in Loki:

```yaml
# loki-config.yml
limits_config:
  max_chunk_age: 2h
  chunk_target_size: 1536000  # ~1.5MB
```

---

## Troubleshooting Queries

### Check If Logs Are Arriving

```logql
# Count logs in last 5 minutes
count_over_time({service_name="flask-backend"}[5m])
```

### Find Label Values

```logql
# What services are logging?
{job="flask-backend"} | json | __error__=""

# What log levels exist?
sum(count_over_time({service_name="flask-backend"}[5m])) by (level)
```

### Debug Parsing Issues

```logql
# Check for parsing errors
{service_name="flask-backend"} | json | __error__!=""

# View raw log lines
{service_name="flask-backend"} | line_format "{{.}}"
```

### Find High-Cardinality Labels

```logql
# Count unique trace_ids
count(count_over_time({service_name="flask-backend"} | json | trace_id!="" [5m])) by (trace_id)
```

---

## Integration with This Project

### Flask Backend Logs

```logql
# All backend logs
{service_name="flask-backend"}

# Backend errors with trace context
{service_name="flask-backend"}
  | json
  | level="ERROR"
  | trace_id!=""

# Slow requests
{service_name="flask-backend"}
  | json
  | duration > 500
```

### Database Operation Logs

```logql
# All database operations
{service_name="flask-backend"}
  | json
  | db_operation!=""

# Slow database queries
{service_name="flask-backend"}
  | json
  | db_operation!=""
  | db_duration > 50
```

### HTTP Request Logs

```logql
# All HTTP requests
{service_name="flask-backend"}
  | json
  | request_method!=""

# Failed requests by endpoint
sum(count_over_time(
  {service_name="flask-backend"}
    | json
    | response_status=~"5.." [5m]
)) by (request_path)
```

### Trace-to-Log Correlation

```logql
# Find all logs for a specific trace
{service_name="flask-backend"}
  | json
  | trace_id="your-trace-id-here"

# Find traces that have errors
{service_name="flask-backend"}
  | json
  | level="ERROR"
  | trace_id!=""
```

---

## Label Design Lessons from This Project

### Good Label Design

From `IMPLEMENTATION-GUIDE.md` Lesson #6:

✅ **Good labels** (low cardinality):
- `service_name` - Limited number of services
- `level` - Limited log levels (DEBUG, INFO, WARN, ERROR)
- `deployment_environment` - Few environments (dev, staging, prod)

❌ **Bad labels** (high cardinality):
- `trace_id` - Unique per request
- `user_id` - Unique per user
- `timestamp` - Changes every log

**Solution:** Use labels for filtering, search content via line filters or parsed fields.

### Loki Label Configuration

From `CONFIGURATION-REFERENCE.md`:

```yaml
# otel-collector/otel-collector-config.yml
processors:
  resource:
    attributes:
      - key: loki.resource.labels
        value: service.name, service.instance.id, deployment.environment
        action: insert
```

This tells OTel Collector which resource attributes to promote to Loki labels.

---

## Quick Reference Card

| Operation | Syntax | Example |
|-----------|--------|---------|
| **Basic Query** | `{label="value"}` | `{service_name="flask-backend"}` |
| **Line Filter** | `{} |= "text"` | `{} |= "error"` |
| **Parse JSON** | `{} | json` | `{service_name="app"} | json` |
| **Label Filter** | `{} | json | label="value"` | `{} | json | level="ERROR"` |
| **Count** | `count_over_time({}[5m])` | `count_over_time({level="ERROR"}[5m])` |
| **Rate** | `rate({}[5m])` | `rate({service_name="app"}[5m])` |
| **Unwrap** | `{} | json | unwrap field` | `{} | json | unwrap duration` |

---

## References

- [Loki Official Documentation](https://grafana.com/docs/loki/latest/query/)
- [LogQL Cheat Sheet](https://megamorf.gitlab.io/cheat-sheets/loki/)
- [Observability Fundamentals](observability-fundamentals.md)
- [PromQL Reference](promql-reference.md)
- [TraceQL Reference](traceql-reference.md)

---

**Last Updated:** 2025-10-22
**Version:** 1.0
**Related Files:**
- [IMPLEMENTATION-GUIDE.md](../phase-1-docker-compose/IMPLEMENTATION-GUIDE.md) - Lesson #6 (Loki label design)
- [architecture/observability.md](../phase-1-docker-compose/architecture/observability.md) - Loki architecture
- [CONFIGURATION-REFERENCE.md](../phase-1-docker-compose/CONFIGURATION-REFERENCE.md) - OTel Collector log configuration
