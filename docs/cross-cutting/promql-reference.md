# PromQL Query Reference

## Overview

**PromQL** (Prometheus Query Language) is the query language for Prometheus metrics, enabling powerful time-series analysis and alerting.

**Version:** Prometheus 2.48.1+
**Related:** [Observability Fundamentals](observability-fundamentals.md), [TraceQL Reference](traceql-reference.md)

---

## Table of Contents

- [Basic Syntax](#basic-syntax)
- [Data Types](#data-types)
- [Selectors](#selectors)
- [Operators](#operators)
- [Functions](#functions)
- [Aggregations](#aggregations)
- [SLI/SLO Queries](#slislo-queries)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Performance Tips](#performance-tips)

---

## Basic Syntax

### Simple Metric Query

```promql
metric_name
```

**Examples:**
```promql
# Current value of all http_requests_total metrics
http_requests_total

# Current value of up metric
up

# Database query duration
db_query_duration_seconds
```

### Instant Vector

Returns a single value per time series at the current time:

```promql
http_requests_total{job="flask-backend"}
```

### Range Vector

Returns values over a time range:

```promql
http_requests_total{job="flask-backend"}[5m]
```

---

## Data Types

### Instant Vector
A set of time series containing a single sample per time series, all sharing the same timestamp.

```promql
up{job="flask-backend"}
```

### Range Vector
A set of time series containing a range of data points over time for each time series.

```promql
http_requests_total[5m]
```

### Scalar
A simple numeric floating-point value.

```promql
1.5
```

### String
A simple string value (currently limited use).

```promql
"hello"
```

---

## Selectors

### Label Matching

#### Equality Matcher
```promql
http_requests_total{method="POST"}
```

#### Inequality Matcher
```promql
http_requests_total{method!="GET"}
```

#### Regex Matcher
```promql
http_requests_total{path=~"/api/.*"}
```

#### Negative Regex Matcher
```promql
http_requests_total{path!~"/health|/metrics"}
```

### Multiple Labels

```promql
http_requests_total{job="flask-backend", method="POST", status="200"}
```

---

## Operators

### Arithmetic Operators

```promql
# Addition
http_requests_total + 10

# Subtraction
http_requests_total - http_errors_total

# Multiplication
http_requests_total * 2

# Division
http_errors_total / http_requests_total

# Modulo
http_requests_total % 100

# Exponentiation
http_requests_total ^ 2
```

### Comparison Operators

```promql
# Equal
http_requests_total == 100

# Not equal
http_requests_total != 0

# Greater than
http_requests_total > 1000

# Less than
http_requests_total < 100

# Greater than or equal
http_requests_total >= 500

# Less than or equal
http_requests_total <= 200
```

### Logical Operators

```promql
# AND
(up == 1) and (http_requests_total > 100)

# OR
(http_errors_total > 10) or (http_requests_total > 1000)

# UNLESS (AND NOT)
http_requests_total unless http_errors_total
```

---

## Functions

### Rate Functions

#### rate()
Calculate per-second average rate of increase over a time range.

```promql
# Requests per second over last 5 minutes
rate(http_requests_total[5m])

# Error rate per second
rate(http_errors_total[5m])

# Database queries per second
rate(db_query_duration_seconds_count[5m])
```

**Use when:** Metric is a counter and you want per-second rate.

#### irate()
Calculate instantaneous rate using the last two data points.

```promql
irate(http_requests_total[5m])
```

**Use when:** You need high-resolution, volatile graphs.

#### increase()
Calculate total increase over a time range.

```promql
# Total requests in last hour
increase(http_requests_total[1h])
```

**Use when:** You want total growth, not rate.

### Aggregation Over Time

#### avg_over_time()
Average value over time range.

```promql
avg_over_time(http_request_duration_seconds[5m])
```

#### max_over_time()
Maximum value over time range.

```promql
max_over_time(http_request_duration_seconds[5m])
```

#### min_over_time()
Minimum value over time range.

```promql
min_over_time(http_request_duration_seconds[5m])
```

#### sum_over_time()
Sum of all values over time range.

```promql
sum_over_time(http_requests_total[5m])
```

### Histogram Functions

#### histogram_quantile()
Calculate quantiles from histogram buckets.

```promql
# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P99 latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# P50 (median) latency
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
```

**Critical:** Must use with `rate()` or `increase()` on bucket metrics.

### Label Manipulation

#### label_replace()
Add or modify labels based on regex.

```promql
label_replace(http_requests_total, "env", "prod", "job", ".*")
```

#### label_join()
Join multiple labels into one.

```promql
label_join(up, "instance_job", ":", "instance", "job")
```

### Math Functions

```promql
# Absolute value
abs(http_requests_total - 100)

# Ceiling
ceil(http_request_duration_seconds)

# Floor
floor(http_request_duration_seconds)

# Round
round(http_request_duration_seconds, 0.1)

# Square root
sqrt(http_requests_total)

# Logarithm
ln(http_requests_total)
log2(http_requests_total)
log10(http_requests_total)
```

### Time Functions

```promql
# Current Unix timestamp
time()

# Day of month (1-31)
day_of_month()

# Day of week (0-6, Sunday=0)
day_of_week()

# Hour of day (0-23)
hour()
```

---

## Aggregations

### sum()
Sum values across dimensions.

```promql
# Total requests across all instances
sum(rate(http_requests_total[5m]))

# Total requests by method
sum(rate(http_requests_total[5m])) by (method)

# Total requests excluding path dimension
sum(rate(http_requests_total[5m])) without (path)
```

### avg()
Average values across dimensions.

```promql
# Average latency across all instances
avg(http_request_duration_seconds)

# Average latency by endpoint
avg(http_request_duration_seconds) by (path)
```

### max() / min()
Maximum or minimum value across dimensions.

```promql
# Maximum latency seen
max(http_request_duration_seconds)

# Minimum memory available
min(node_memory_MemAvailable_bytes) by (instance)
```

### count()
Count number of time series.

```promql
# Number of healthy instances
count(up == 1)

# Number of endpoints
count(http_requests_total) by (path)
```

### topk() / bottomk()
Top or bottom K time series by value.

```promql
# Top 5 endpoints by request rate
topk(5, rate(http_requests_total[5m]))

# Bottom 3 instances by memory
bottomk(3, node_memory_MemAvailable_bytes)
```

### quantile()
Calculate quantile across dimensions.

```promql
# 95th percentile latency across all instances
quantile(0.95, http_request_duration_seconds)
```

---

## SLI/SLO Queries

### Service Availability

#### Success Rate (Availability SLI)

```promql
# Availability percentage (5-minute window)
100 * (
  1 - (
    sum(rate(http_errors_total[5m]))
    /
    sum(rate(http_requests_total[5m]))
  )
)
```

#### Instance Availability

```promql
# Percentage of healthy instances
100 * (
  count(up == 1)
  /
  count(up)
)
```

### Latency SLIs

#### P95 Response Time

```promql
# P95 latency (5-minute window)
histogram_quantile(
  0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
)
```

#### P99 Response Time

```promql
histogram_quantile(
  0.99,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
)
```

#### Average Latency

```promql
# Average response time
sum(rate(http_request_duration_seconds_sum[5m]))
/
sum(rate(http_request_duration_seconds_count[5m]))
```

### Error Rate SLIs

#### Error Percentage

```promql
# Error rate as percentage
100 * (
  sum(rate(http_requests_total{status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
)
```

#### 4xx vs 5xx Errors

```promql
# Client errors (4xx)
sum(rate(http_requests_total{status=~"4.."}[5m])) by (status)

# Server errors (5xx)
sum(rate(http_requests_total{status=~"5.."}[5m])) by (status)
```

### Database SLIs

#### Database P95 Latency

```promql
# P95 database query latency by operation
histogram_quantile(
  0.95,
  sum(rate(db_query_duration_seconds_bucket[5m])) by (le, operation)
)
```

#### Database Query Rate

```promql
# Queries per second by operation
sum(rate(db_query_duration_seconds_count[5m])) by (operation)
```

#### Database Error Rate

```promql
# Database error percentage
100 * (
  sum(rate(db_errors_total[5m]))
  /
  sum(rate(db_queries_total[5m]))
)
```

### Throughput SLIs

#### Request Rate

```promql
# Requests per second
sum(rate(http_requests_total[5m]))

# Requests per second by endpoint
sum(rate(http_requests_total[5m])) by (path)

# Requests per second by method
sum(rate(http_requests_total[5m])) by (method)
```

### SLO Compliance

#### Error Budget Consumption

```promql
# Error budget (SLO: 99.9% availability)
# 0.1% error budget = 43.2 minutes downtime per month

# Current error rate
(
  sum(rate(http_errors_total[30d]))
  /
  sum(rate(http_requests_total[30d]))
)

# Error budget remaining
0.001 - (
  sum(rate(http_errors_total[30d]))
  /
  sum(rate(http_requests_total[30d]))
)
```

---

## Best Practices

### 1. Always Use rate() with Counters

❌ **Wrong:**
```promql
http_requests_total
```

✅ **Correct:**
```promql
rate(http_requests_total[5m])
```

**Why:** Counters reset on restart, `rate()` handles this correctly.

### 2. Use Appropriate Time Ranges

```promql
# Short range for volatile metrics (5m-15m)
rate(http_requests_total[5m])

# Longer range for stable trends (1h-24h)
rate(http_requests_total[1h])
```

**Rule of thumb:** Time range should be ≥ 4× scrape interval.

### 3. Aggregate Before Calculating Rates

❌ **Wrong:**
```promql
sum(http_requests_total)
```

✅ **Correct:**
```promql
sum(rate(http_requests_total[5m]))
```

### 4. Use `by` for Grouping, `without` for Exclusion

```promql
# Group by specific labels
sum(rate(http_requests_total[5m])) by (method, status)

# Exclude specific labels
sum(rate(http_requests_total[5m])) without (instance)
```

### 5. Avoid High-Cardinality Labels

❌ **Avoid:**
```promql
http_requests_total{user_id="12345"}  # Unique per user
```

✅ **Prefer:**
```promql
http_requests_total{user_type="premium"}  # Limited values
```

### 6. Use Recording Rules for Complex Queries

For expensive queries used in multiple dashboards, create recording rules:

```yaml
# prometheus.yml
groups:
  - name: sli_rules
    interval: 30s
    rules:
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)

      - record: job:http_latency_p95:rate5m
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, job))
```

---

## Common Patterns

### RED Method (Request, Error, Duration)

```promql
# Request Rate
sum(rate(http_requests_total[5m])) by (job)

# Error Rate
sum(rate(http_errors_total[5m])) by (job)
/
sum(rate(http_requests_total[5m])) by (job)

# Duration (P95)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, job))
```

### USE Method (Utilization, Saturation, Errors)

```promql
# Utilization (CPU)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Saturation (Load Average)
node_load1 / count(node_cpu_seconds_total{mode="idle"}) by (instance)

# Errors (Network)
rate(node_network_receive_errs_total[5m])
```

### Availability Calculation

```promql
# Uptime percentage over 30 days
avg_over_time(up[30d]) * 100
```

### Apdex Score

```promql
# Apdex score (T=100ms, 4T=400ms)
(
  sum(rate(http_request_duration_seconds_bucket{le="0.1"}[5m]))
  +
  sum(rate(http_request_duration_seconds_bucket{le="0.4"}[5m])) / 2
)
/
sum(rate(http_request_duration_seconds_count[5m]))
```

### Burn Rate (Error Budget)

```promql
# 1-hour burn rate for 99.9% SLO
(
  sum(rate(http_errors_total[1h]))
  /
  sum(rate(http_requests_total[1h]))
)
/
0.001  # SLO error budget (0.1%)
```

---

## Performance Tips

### 1. Limit Time Series with Selectors

❌ **Slow:**
```promql
sum(rate(http_requests_total[5m]))
```

✅ **Faster:**
```promql
sum(rate(http_requests_total{job="flask-backend"}[5m]))
```

### 2. Use Recording Rules for Dashboard Queries

Pre-calculate expensive queries and query the recording instead.

### 3. Avoid Large Time Ranges in Dashboards

```promql
# Use variables for time ranges
rate(http_requests_total[$__rate_interval])
```

### 4. Reduce Cardinality

Drop high-cardinality labels before ingestion:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'flask-backend'
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'http_requests_total'
        action: labeldrop
        regex: 'user_id|session_id'
```

### 5. Use Subqueries Sparingly

Subqueries are powerful but expensive:

```promql
# Calculates max request rate over last hour in 5m windows
max_over_time(
  sum(rate(http_requests_total[5m]))[1h:5m]
)
```

---

## Troubleshooting Queries

### No Data Returned

Check if metric exists:
```promql
{__name__=~"http.*"}
```

### High Cardinality

Count unique time series:
```promql
count(http_requests_total) by (__name__)
```

### Label Values

Get all label values:
```promql
count by (method) (http_requests_total)
```

---

## Integration with This Project

### Flask Backend Metrics

```promql
# Request rate
sum(rate(http_requests_total{job="flask-backend"}[5m])) by (method, path)

# Error rate
sum(rate(http_errors_total{job="flask-backend"}[5m]))

# P95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="flask-backend"}[5m])) by (le))
```

### Database Metrics

```promql
# Database query rate by operation
sum(rate(db_query_duration_seconds_count[5m])) by (operation)

# Database P95 latency
histogram_quantile(0.95, sum(rate(db_query_duration_seconds_bucket[5m])) by (le, operation))
```

### OTel Collector Metrics

```promql
# Spans received per second
rate(otelcol_receiver_accepted_spans[5m])

# Spans exported per second
rate(otelcol_exporter_sent_spans[5m])
```

---

## References

- [Prometheus Official Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Observability Fundamentals](observability-fundamentals.md)
- [TraceQL Reference](traceql-reference.md)
- [SLI/SLO Dashboard Documentation](../phase-1-docker-compose/architecture/observability.md)

---

## Quick Reference Card

| Operation | Syntax | Example |
|-----------|--------|---------|
| **Rate** | `rate(metric[5m])` | `rate(http_requests_total[5m])` |
| **Sum** | `sum(metric)` | `sum(rate(http_requests_total[5m]))` |
| **By** | `sum(...) by (label)` | `sum(...) by (method)` |
| **P95** | `histogram_quantile(0.95, ...)` | `histogram_quantile(0.95, rate(metric_bucket[5m]))` |
| **Availability** | `100 * (1 - errors/total)` | `100 * (1 - rate(http_errors_total[5m]) / rate(http_requests_total[5m]))` |

---

**Last Updated:** 2025-10-22
**Version:** 1.0
**Related Files:**
- [IMPLEMENTATION-GUIDE.md](../phase-1-docker-compose/IMPLEMENTATION-GUIDE.md) - Metrics instrumentation patterns
- [architecture/observability.md](../phase-1-docker-compose/architecture/observability.md) - Prometheus architecture
- [VERIFICATION-GUIDE.md](../phase-1-docker-compose/VERIFICATION-GUIDE.md) - Metrics verification
