# OpenTelemetry Collector Troubleshooting Guide

## Overview

This guide covers common issues, diagnostics, and solutions for the OpenTelemetry Collector in this observability lab.

**Collector Version:** 0.96.0 (contrib distribution)
**Configuration:** `otel-collector/otel-collector-config.yml`
**Related:** [Observability Architecture](../architecture/observability.md), [Configuration Reference](../CONFIGURATION-REFERENCE.md)

---

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Memory Issues](#memory-issues)
- [Pipeline Problems](#pipeline-problems)
- [Exporter Issues](#exporter-issues)
- [Receiver Problems](#receiver-problems)
- [Performance Tuning](#performance-tuning)
- [Debug Mode](#debug-mode)
- [Health Checks](#health-checks)

---

## Quick Diagnostics

### Check Collector Status

```bash
# Check if collector is running
docker compose -p lab ps otel-collector

# Check collector logs
docker compose -p lab logs otel-collector --tail=100

# Check health endpoint
curl http://localhost:13133
```

**Expected response:**
```json
{"status":"Server available","upSince":"2025-10-22T12:00:00Z","uptime":"2h30m15s"}
```

### Check Metrics Export

```bash
# Check if collector is receiving spans
curl -s http://localhost:8888/metrics | grep otelcol_receiver

# Check if collector is exporting
curl -s http://localhost:8888/metrics | grep otelcol_exporter
```

---

## Common Issues

### Issue #1: Collector Not Receiving Data

**Symptoms:**
- Backend sends telemetry but collector shows no activity
- `otelcol_receiver_accepted_spans` = 0
- Tempo/Loki show no data

**Diagnosis:**

```bash
# Check if collector is listening on correct ports
docker compose -p lab exec otel-collector netstat -tlnp

# Should show:
# 0.0.0.0:4317 (gRPC)
# 0.0.0.0:4318 (HTTP)

# Check backend can reach collector
docker compose -p lab exec backend ping otel-collector

# Check logs for receiver errors
docker compose -p lab logs otel-collector | grep -i "receiver"
```

**Common Causes:**

1. **Wrong endpoint in backend**

   Check `backend/app.py`:
   ```python
   # Should be:
   OtlpSpanExporter(endpoint="http://otel-collector:4318/v1/traces")

   # NOT:
   OtlpSpanExporter(endpoint="http://localhost:4318/v1/traces")
   ```

2. **CORS blocking HTTP receiver**

   Check `otel-collector-config.yml`:
   ```yaml
   receivers:
     otlp:
       protocols:
         http:
           cors:
             allowed_origins:
               - "http://localhost:8080"  # Add your frontend URL
   ```

3. **Container not on same network**

   ```bash
   # Verify network
   docker inspect otel-collector | jq '.[0].NetworkSettings.Networks'
   docker inspect backend | jq '.[0].NetworkSettings.Networks'

   # Both should show "otel-network"
   ```

**Solution:**

Update backend configuration and restart:
```bash
# Fix endpoint in backend code
# Then rebuild
docker compose -p lab build backend
docker compose -p lab up -d backend
```

---

### Issue #2: Collector Crashes with OOM (Out of Memory)

**Symptoms:**
- Collector container keeps restarting
- Logs show: `signal: killed` or `OOMKilled`
- Docker inspect shows: `"OOMKilled": true`

**Diagnosis:**

```bash
# Check if container was killed
docker inspect otel-collector | jq '.[0].State.OOMKilled'

# Check collector memory usage before crash
docker stats otel-collector --no-stream

# Check memory_limiter processor settings
grep -A 5 "memory_limiter" otel-collector/otel-collector-config.yml
```

**Root Cause:**

The `memory_limiter` processor is configured but memory limit is too low for traffic volume.

**Current Config:**
```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512  # 512MB limit
```

**Solution:**

**Option 1: Increase memory limit**

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1024  # Increase to 1GB
    spike_limit_mib: 256  # Add spike limit
```

**Option 2: Add soft limit with graceful handling**

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1024
    spike_limit_mib: 256
    # Drop data instead of crashing
    check_interval: 5s
```

**Option 3: Increase Docker container memory**

```yaml
# docker-compose.yml
services:
  otel-collector:
    deploy:
      resources:
        limits:
          memory: 2G  # Increase from default
        reservations:
          memory: 512M
```

**Apply changes:**
```bash
docker compose -p lab up -d otel-collector
```

---

### Issue #3: Data Not Reaching Tempo/Loki

**Symptoms:**
- Collector receives data (`otelcol_receiver_accepted_spans` > 0)
- But Tempo shows no traces or Loki shows no logs
- `otelcol_exporter_sent_spans` = 0 or errors

**Diagnosis:**

```bash
# Check exporter metrics
curl -s http://localhost:8888/metrics | grep otelcol_exporter_sent

# Check for export errors
docker compose -p lab logs otel-collector | grep -i "exporter"

# Verify Tempo/Loki are reachable
docker compose -p lab exec otel-collector wget -qO- http://tempo:4317
docker compose -p lab exec otel-collector wget -qO- http://loki:3100/ready
```

**Common Causes:**

1. **Wrong exporter endpoint**

   ```yaml
   exporters:
     otlp/tempo:
       endpoint: tempo:4317  # ✅ Correct
       # NOT: http://tempo:4317  # ❌ Wrong - don't use http:// for gRPC
   ```

2. **TLS misconfiguration**

   ```yaml
   exporters:
     otlp/tempo:
       endpoint: tempo:4317
       tls:
         insecure: true  # ✅ Required for local deployment
   ```

3. **Exporter not in pipeline**

   ```yaml
   service:
     pipelines:
       traces:
         receivers: [otlp]
         processors: [batch]
         exporters: [otlp/tempo]  # ✅ Must include exporter
   ```

**Solution:**

Fix configuration and restart:
```bash
# Edit otel-collector/otel-collector-config.yml
# Then restart
docker compose -p lab restart otel-collector
```

---

### Issue #4: High CPU Usage

**Symptoms:**
- Collector CPU at 100%
- Slow telemetry processing
- Increased latency in applications

**Diagnosis:**

```bash
# Check CPU usage
docker stats otel-collector --no-stream

# Check batch processor settings
grep -A 5 "batch:" otel-collector/otel-collector-config.yml

# Check telemetry volume
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted
```

**Root Cause:**

Batch processor configured with too-aggressive settings causing frequent exports.

**Current Config:**
```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
```

**Solution:**

Optimize batch settings:

```yaml
processors:
  batch:
    timeout: 30s  # Increase timeout (less frequent exports)
    send_batch_size: 5000  # Increase batch size
    send_batch_max_size: 10000  # Add max size
```

**Trade-offs:**
- **Higher timeout:** Less CPU, but higher memory usage and latency
- **Larger batches:** More efficient exports, but higher memory usage

**Apply:**
```bash
docker compose -p lab restart otel-collector
```

---

## Memory Issues

### Monitoring Memory Usage

```bash
# Real-time memory monitoring
docker stats otel-collector

# Check memory_limiter metrics
curl -s http://localhost:8888/metrics | grep memory_limiter
```

**Key Metrics:**
- `otelcol_processor_refused_spans` - Spans dropped due to memory limit
- `otelcol_processor_refused_metric_points` - Metrics dropped
- `otelcol_processor_refused_log_records` - Logs dropped

### Memory Limiter Configuration

**Basic Configuration:**
```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
```

**Advanced Configuration:**
```yaml
processors:
  memory_limiter:
    check_interval: 5s  # How often to check memory
    limit_mib: 1024  # Hard limit (collector will drop data)
    spike_limit_mib: 256  # Additional buffer for spikes
    ballast_size_mib: 256  # Pre-allocate memory for stability
```

**Ballast Explanation:**

Ballast pre-allocates memory to reduce GC pressure:

```yaml
processors:
  memory_limiter:
    ballast_size_mib: 256  # Pre-allocate 256MB
    limit_mib: 1280  # Total = ballast (256) + working (1024)
```

### Memory Limit Alerts

**Check if data is being dropped:**

```bash
curl -s http://localhost:8888/metrics | grep refused

# Output:
# otelcol_processor_refused_spans{...} 150  # ❌ Data loss!
```

**Increase limit if you see drops:**
```yaml
processors:
  memory_limiter:
    limit_mib: 2048  # Double the limit
```

---

## Pipeline Problems

### Pipeline Not Configured

**Symptoms:**
- Data received but not exported
- Logs show: `no exporters configured for pipeline`

**Diagnosis:**

```bash
# Check pipeline configuration
grep -A 10 "pipelines:" otel-collector/otel-collector-config.yml
```

**Common Mistakes:**

❌ **Missing pipeline:**
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: []  # No exporters!
```

❌ **Typo in component name:**
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tembo]  # Typo: "tembo" not "tempo"
```

✅ **Correct:**
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, attributes, batch]
      exporters: [otlp/tempo, logging]
```

### Processor Order Matters

**Incorrect Order:**
```yaml
pipelines:
  traces:
    processors: [batch, memory_limiter]  # ❌ Wrong order
```

**Correct Order:**
```yaml
pipelines:
  traces:
    processors: [memory_limiter, resource, attributes, batch]
    # ✅ memory_limiter first, batch last
```

**Why order matters:**
1. `memory_limiter` - Protect collector memory (first)
2. `resource` - Add resource attributes
3. `attributes` - Add custom attributes
4. `batch` - Batch for efficient export (last)

---

## Exporter Issues

### Tempo Exporter Not Working

**Symptoms:**
- Logs show: `failed to export to tempo`
- Error: `connection refused`

**Diagnosis:**

```bash
# Check if Tempo is running
docker compose -p lab ps tempo

# Check Tempo is reachable
docker compose -p lab exec otel-collector nc -zv tempo 4317

# Check exporter configuration
grep -A 5 "otlp/tempo" otel-collector/otel-collector-config.yml
```

**Common Fixes:**

1. **Tempo not running:**
   ```bash
   docker compose -p lab up -d tempo
   ```

2. **Wrong endpoint:**
   ```yaml
   exporters:
     otlp/tempo:
       endpoint: tempo:4317  # ✅ Correct
       # NOT: localhost:4317  # ❌ Wrong
   ```

3. **Missing TLS config:**
   ```yaml
   exporters:
     otlp/tempo:
       endpoint: tempo:4317
       tls:
         insecure: true  # Required for local deployment
   ```

### Loki Exporter Not Working

**Symptoms:**
- Logs not appearing in Loki
- Error: `failed to send logs to Loki`

**Diagnosis:**

```bash
# Check Loki health
curl http://localhost:3100/ready

# Check exporter config
grep -A 5 "loki:" otel-collector/otel-collector-config.yml

# Test manual push to Loki
curl -X POST "http://localhost:3100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"service":"test"},"values":[["'$(date +%s)000000000'","test message"]]}]}'
```

**Common Fixes:**

1. **Wrong endpoint:**
   ```yaml
   exporters:
     loki:
       endpoint: http://loki:3100/loki/api/v1/push  # ✅ Include full path
       # NOT: http://loki:3100  # ❌ Missing path
   ```

2. **Missing resource-to-label mapping:**
   ```yaml
   processors:
     resource:
       attributes:
         - key: loki.resource.labels
           value: service.name, service.instance.id, deployment.environment
           action: insert
   ```

---

## Receiver Problems

### OTLP Receiver Not Listening

**Symptoms:**
- Backend can't connect to collector
- Error: `connection refused`

**Diagnosis:**

```bash
# Check if ports are exposed
docker port otel-collector

# Should show:
# 4317/tcp -> 0.0.0.0:4317
# 4318/tcp -> 0.0.0.0:4318

# Check receiver config
grep -A 10 "receivers:" otel-collector/otel-collector-config.yml
```

**Fix:**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317  # Listen on all interfaces
      http:
        endpoint: 0.0.0.0:4318
```

### CORS Issues with HTTP Receiver

**Symptoms:**
- Browser console shows CORS error
- Frontend can't send telemetry

**Fix:**

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - "http://localhost:8080"
            - "http://192.168.122.250:8080"  # Add VM IP
          allowed_headers:
            - "*"
```

---

## Performance Tuning

### Optimize for High Throughput

**For high-volume environments:**

```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 10000  # Large batches
    send_batch_max_size: 20000

  memory_limiter:
    limit_mib: 2048  # More memory
    spike_limit_mib: 512
    ballast_size_mib: 512

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16  # Accept large payloads
```

### Optimize for Low Latency

**For real-time requirements:**

```yaml
processors:
  batch:
    timeout: 1s  # Export quickly
    send_batch_size: 100  # Small batches

  memory_limiter:
    check_interval: 1s  # Frequent checks
```

---

## Debug Mode

### Enable Debug Logging

**Temporarily enable debug logging:**

```yaml
exporters:
  logging:
    loglevel: debug  # Change from "info" to "debug"
    sampling_initial: 1  # Log everything initially
    sampling_thereafter: 1  # Keep logging everything
```

**Restart collector:**
```bash
docker compose -p lab restart otel-collector
docker compose -p lab logs otel-collector --tail=100 -f
```

### Use zpages for Debugging

**Access zpages:**
```bash
# View pipelines
curl http://localhost:55679/debug/pipelinez

# View tracez (active traces)
curl http://localhost:55679/debug/tracez

# View servicez (service info)
curl http://localhost:55679/debug/servicez
```

**Or open in browser:**
- http://localhost:55679/debug/pipelinez
- http://localhost:55679/debug/tracez
- http://localhost:55679/debug/servicez

---

## Health Checks

### Collector Health Endpoint

```bash
# Basic health check
curl http://localhost:13133

# Detailed status
curl http://localhost:13133 | jq
```

### Metrics Endpoint

```bash
# View all collector internal metrics
curl http://localhost:8888/metrics

# Specific metric families
curl -s http://localhost:8888/metrics | grep otelcol_receiver
curl -s http://localhost:8888/metrics | grep otelcol_exporter
curl -s http://localhost:8888/metrics | grep otelcol_processor
```

**Key Metrics to Monitor:**

```bash
# Spans received
otelcol_receiver_accepted_spans

# Spans sent
otelcol_exporter_sent_spans

# Spans dropped
otelcol_processor_refused_spans

# Export errors
otelcol_exporter_send_failed_spans
```

### Docker Healthcheck

**Add to docker-compose.yml:**

```yaml
services:
  otel-collector:
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:13133"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
```

---

## Verification Checklist

After troubleshooting, verify:

- [ ] Collector container is running: `docker compose -p lab ps otel-collector`
- [ ] Health endpoint returns 200: `curl http://localhost:13133`
- [ ] Receiver is accepting spans: `curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted_spans`
- [ ] Exporter is sending spans: `curl -s http://localhost:8888/metrics | grep otelcol_exporter_sent_spans`
- [ ] No data is being dropped: `curl -s http://localhost:8888/metrics | grep refused` (should be 0)
- [ ] Tempo shows traces: Open Grafana → Explore → Tempo
- [ ] Loki shows logs: Open Grafana → Explore → Loki
- [ ] No errors in logs: `docker compose -p lab logs otel-collector | grep -i error`

---

## Related Documentation

- [Observability Architecture](../architecture/observability.md) - Collector role in system
- [Configuration Reference](../CONFIGURATION-REFERENCE.md) - Complete YAML config guide
- [IMPLEMENTATION-GUIDE.md](../IMPLEMENTATION-GUIDE.md) - Integration patterns
- [Common Issues](common-issues.md) - General troubleshooting

---

**Last Updated:** 2025-10-22
**Version:** 1.0
**Collector Version:** 0.96.0 (contrib)
