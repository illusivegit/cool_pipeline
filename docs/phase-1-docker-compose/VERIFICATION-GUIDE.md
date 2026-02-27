# Observability Lab Verification Guide

Complete verification procedures for deployment, CI/CD integration, and production readiness.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Manual Deployment Verification](#manual-deployment-verification)
- [CI/CD Pipeline Verification](#cicd-pipeline-verification)
- [Production Readiness Validation](#production-readiness-validation)
- [Troubleshooting Common Issues](#troubleshooting-common-issues)
- [Quick Health Check Script](#quick-health-check-script)

---

## Pre-Deployment Checklist

Before deploying, ensure these configurations are correct:

### 1. Backend Configuration
- ✅ SQLAlchemy event listeners defined as **plain functions** (not decorators)
- ✅ Event listeners attached **inside** `with app.app_context():` block
- ✅ Functions defined **before** app context block
- ✅ Prometheus histogram name: `db_query_duration_seconds`

### 2. Nginx Configuration
- ✅ Docker DNS resolver: `resolver 127.0.0.11 ipv6=off valid=30s;`
- ✅ Variable-based proxy_pass: `set $backend_upstream http://backend:5000;`
- ✅ No URI suffix: `proxy_pass $backend_upstream;` (not `/api/`)

### 3. Docker Compose Configuration
- ✅ Service name: `backend` (matches Nginx target)
- ✅ Both `backend` and `frontend` on `otel-network`
- ✅ Backend healthcheck uses Python (available in python:3.12-slim)
- ✅ Frontend `depends_on` backend with `condition: service_healthy`

### 4. Prometheus Configuration
- ✅ Scrape target: `backend:5000` (matches service name)
- ✅ Job name: `flask-backend`

---

## Manual Deployment Verification

### Step 1: Clean Deployment

```bash
# On your VM (not dev host):
cd /home/deploy/lab/app

# Remove old containers and volumes
docker compose -p lab down -v

# Rebuild and start all services
docker compose -p lab up -d --build

# Wait for healthcheck to stabilize (15-20 seconds)
echo "Waiting for backend healthcheck..."
sleep 20
```

---

### Step 2: Verify Backend Container Status

```bash
docker compose -p lab ps
```

**Expected output:**
```
NAME             IMAGE                      STATUS
flask-backend    ...                        Up (healthy)
frontend         nginx:alpine              Up
grafana          grafana/grafana:10.2.3    Up
...
```

**✅ Success criteria:**
- `backend` (flask-backend container) shows **"Up (healthy)"** status
- All other services show **"Up"** status

**❌ If backend shows "starting" or "unhealthy":**
```bash
# Check healthcheck logs
docker compose -p lab logs backend | tail -50

# Common issues:
# - Python healthcheck failing: Check if /metrics endpoint is accessible
# - App crash: Look for RuntimeError or import errors
```

---

### Step 3: Verify Backend Logs

```bash
docker compose -p lab logs backend | grep -E "Database initialized|event listeners registered"
```

**Expected output:**
```
flask-backend  | {"message": "Database initialized", ...}
flask-backend  | {"message": "SQLAlchemy event listeners registered for DB query duration tracking", ...}
```

**✅ Success criteria:**
- Both log messages present
- No RuntimeError or "Working outside of application context" errors

**❌ If messages missing:**
```bash
# View full backend logs
docker compose -p lab logs backend

# Look for:
# - RuntimeError: Working outside of application context
# - Import errors
# - SQLAlchemy errors
```

---

### Step 4: Verify DNS Resolution from Frontend

```bash
docker compose -p lab exec frontend getent hosts backend
```

**Expected output:**
```
172.18.0.X  backend
```

**✅ Success criteria:**
- Returns an IP address (172.18.0.X range)
- Service name "backend" resolves

**❌ If no output:**
- Backend container is not running or not on `otel-network`
- Check `docker compose -p lab ps` to ensure backend is up
- Verify both services are on same network:
  ```bash
  docker inspect -f '{{.Name}} -> {{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' \
    $(docker compose -p lab ps -q frontend backend)
  # Both should show same network ID
  ```

---

### Step 5: Verify API Connectivity from Frontend Container

```bash
docker compose -p lab exec frontend wget -qO- http://backend:5000/api/tasks
```

**Expected output:**
```json
[]
```
or a JSON array of tasks if you've created any.

**✅ Success criteria:**
- Returns valid JSON
- No "bad address" or connection errors

**❌ If fails:**
```bash
# Test if backend is listening
docker compose -p lab exec backend netstat -tlnp | grep 5000

# Test direct connection (bypass DNS)
docker compose -p lab exec frontend sh -c \
  'wget -qO- http://$(getent hosts backend | awk "{print \$1}"):5000/api/tasks'
```

---

### Step 6: Verify API Through Nginx Proxy (from VM Host)

```bash
curl http://192.168.122.250:8080/api/tasks
```

**Expected output:**
```json
[]
```

**✅ Success criteria:**
- Returns valid JSON
- HTTP 200 status (not 502 Bad Gateway)

**❌ If 502 error:**
```bash
# Check Nginx error logs
docker compose -p lab logs frontend | grep error

# Common error: "backend could not be resolved"
# → DNS issue, go back to Step 4

# Common error: "upstream prematurely closed connection"
# → Backend is crashing on requests, check backend logs
```

---

### Step 7: Verify Prometheus Metrics Endpoint

```bash
curl -s http://192.168.122.250:5000/metrics | head -20
```

**Expected output:**
```
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
...
# HELP db_query_duration_seconds SQLite query duration in seconds
# TYPE db_query_duration_seconds histogram
db_query_duration_seconds_bucket{le="0.002",operation="SELECT"} 0.0
db_query_duration_seconds_bucket{le="0.005",operation="SELECT"} 0.0
...
```

**✅ Success criteria:**
- Returns Prometheus metrics in text format
- `db_query_duration_seconds_bucket` metrics present
- Histogram buckets visible with `operation` label

**❌ If no db_query metrics:**
- No DB queries have executed yet (normal on fresh deploy)
- Run Step 11 (DB smoke test) to generate traffic

---

### Step 8: Verify Prometheus Scrape Target Status

#### Option A: Web UI (Recommended)
1. Open browser: `http://192.168.122.250:9090/targets`
2. Find target: `flask-backend (backend:5000)`
3. Verify: **State = UP** (green background)
4. Check: Last scrape timestamp is recent (< 30 seconds ago)

#### Option B: Command Line
```bash
curl -s http://192.168.122.250:9090/api/v1/targets | \
  python3 -c "import sys, json; \
    targets = json.load(sys.stdin)['data']['activeTargets']; \
    flask = [t for t in targets if t['labels']['job'] == 'flask-backend'][0]; \
    print(f\"State: {flask['health']}\nLast Scrape: {flask['lastScrape']}\")"
```

**Expected output:**
```
State: up
Last Scrape: 2025-10-22T16:30:00.123Z
```

**✅ Success criteria:**
- `flask-backend` target shows **"up"** state
- Last scrape timestamp is recent

**❌ If target is "down":**
```bash
# Check if Prometheus can reach backend
docker compose -p lab exec prometheus wget -qO- http://backend:5000/metrics | head -5

# Verify Prometheus config has correct target
docker compose -p lab exec prometheus cat /etc/prometheus/prometheus.yml | grep -A 3 flask-backend
```

---

### Step 9: Verify Grafana Data Sources

1. Open browser: `http://192.168.122.250:3000`
2. Navigate: **Connections → Data Sources**
3. Click: **Prometheus**
4. Scroll down: Click **"Test"** button
5. Verify: **"Data source is working"** message appears (green)

Repeat for:
- **Tempo** data source
- **Loki** data source

**✅ Success criteria:**
- All three data sources show green "working" status

**❌ If any fail:**
- Check service is running: `docker compose -p lab ps`
- Verify network connectivity from Grafana container

---

### Step 10: Verify SLI/SLO Dashboard Panels

1. Open browser: `http://192.168.122.250:3000`
2. Navigate: **Dashboards → SLI/SLO Dashboard - Task Manager**
3. Wait: 30-60 seconds for panels to load

**Check these panels:**

| Panel Name | Expected State | Notes |
|------------|----------------|-------|
| **Request Rate by Endpoint** | Shows data (may be near 0) | Increments when you use the UI |
| **Error Rate by Endpoint (%)** | Shows 0% or data | Will show errors if you click "Simulate Error" |
| **P95 Response Time (SLI)** | Shows data | Latency histogram |
| **Service Availability (SLI)** | Shows 100% or availability % | Overall service health metric |
| **Response Time Percentiles** | Shows p50/p95/p99 lines | Multi-percentile view |
| **Requests by Status Code** | Shows breakdown (200, 4xx, 5xx) | HTTP status distribution |
| **Database Query P95 Latency** | May show "No data" initially | Needs DB traffic (see Step 11) |

**✅ Success criteria:**
- Request Rate panel shows lines (even if near 0)
- No "No data" errors on Request Rate/Duration panels
- Time series data visible for recent scrape intervals

**❌ If panels show "No data":**
```bash
# Generate some traffic to create metrics
curl http://192.168.122.250:8080/api/tasks
curl http://192.168.122.250:8080/api/tasks

# Wait 15-30 seconds for next Prometheus scrape
# Refresh Grafana dashboard
```

---

### Step 11: Generate DB Traffic (Warm P95 Latency Panel)

The "Database Query P95 Latency" panel requires DB query traffic to populate.

#### Option A: Web UI (Easiest)
1. Open browser: `http://192.168.122.250:8080`
2. Click: **"DB Smoke (warm P95)"** button
3. Wait: Toast notification says "DB smoke test completed"
4. Wait: 60-90 seconds for Prometheus to scrape new metrics
5. Refresh: Grafana dashboard
6. Verify: "Database Query P95 Latency" panel shows lines for SELECT/INSERT/UPDATE/DELETE

#### Option B: Command Line
```bash
# Send 300 mixed read/write operations
curl -X POST "http://192.168.122.250:8080/api/smoke/db?ops=300&type=rw"

# Wait for Prometheus scrape (15 second interval + processing)
sleep 90

# Check metrics are visible
curl -s http://192.168.122.250:5000/metrics | grep db_query_duration_seconds_bucket | grep -v "0.0$" | head -10
```

**Expected output (after 90 seconds):**
```
db_query_duration_seconds_bucket{le="0.002",operation="SELECT"} 150.0
db_query_duration_seconds_bucket{le="0.005",operation="SELECT"} 290.0
db_query_duration_seconds_bucket{le="0.002",operation="INSERT"} 50.0
...
```

**✅ Success criteria:**
- Grafana panel shows 4 lines (SELECT, INSERT, UPDATE, DELETE)
- P95 values are in milliseconds range (typically 5-50ms for SQLite)
- Lines show recent data points

---

### Step 12: Verify Tempo Traces (Optional)

1. Open browser: `http://192.168.122.250:3000`
2. Navigate: **Explore → Tempo**
3. Click: **"Search"** tab
4. Service Name: Select **"flask-backend"**
5. Click: **"Run Query"**
6. Click: Any trace ID to open trace details

**Check trace structure:**
```
GET /api/tasks
├─ GET (Flask handler)
│  └─ SELECT (SQLAlchemy query)
└─ ...
```

**✅ Success criteria:**
- Traces appear in search results
- Trace timeline shows Flask HTTP span
- Database query spans visible as children
- Span attributes include operation type (SELECT/INSERT/etc.)

---

## CI/CD Pipeline Verification

### Jenkins Pipeline Integration

This lab can be integrated into a Jenkins DevSecOps pipeline for automated testing and deployment.

**Note:** The actual Jenkinsfile in this repository uses a different deployment strategy (SSH + rsync to remote VM at `/home/deploy/lab/app`). The example below demonstrates a simpler local Docker Compose deployment. **Adapt paths and deployment method to match your infrastructure.**

For the actual production Jenkinsfile, see: [Jenkinsfile](../../Jenkinsfile)

#### Automated Health Checks

```groovy
stage('Health Checks') {
    steps {
        script {
            echo 'Waiting for services to be healthy...'
            sh '''
                # Wait for collector
                timeout 60 sh -c 'until curl -sf http://localhost:13133; do sleep 2; done'

                # Wait for backend
                timeout 60 sh -c 'until curl -sf http://localhost:5000/health; do sleep 2; done'

                # Wait for Grafana
                timeout 60 sh -c 'until curl -sf http://localhost:3000/api/health; do sleep 2; done'

                # Wait for Prometheus
                timeout 60 sh -c 'until curl -sf http://localhost:9090/-/healthy; do sleep 2; done'

                # Wait for Loki
                timeout 60 sh -c 'until curl -sf http://localhost:3100/ready; do sleep 2; done'

                # Wait for Tempo
                timeout 60 sh -c 'until curl -sf http://localhost:3200/ready; do sleep 2; done'
            '''
        }
    }
}
```

#### Generate Test Traffic

```groovy
stage('Generate Test Traffic') {
    steps {
        script {
            echo 'Generating telemetry data...'
            sh '''
                # Create test tasks
                for i in {1..10}; do
                    curl -X POST http://localhost:5000/api/tasks \
                        -H "Content-Type: application/json" \
                        -d "{\"title\":\"Jenkins Test Task $i\",\"description\":\"Created by Jenkins pipeline\"}"
                    sleep 1
                done

                # Get all tasks
                curl http://localhost:5000/api/tasks

                # Simulate slow request
                curl "http://localhost:5000/api/simulate-slow?delay=1"

                # Simulate error (expected to fail)
                curl http://localhost:5000/api/simulate-error || true
            '''

            // Wait for telemetry to propagate
            sleep(time: 10, unit: 'SECONDS')
        }
    }
}
```

#### Verify Traces in Tempo

```groovy
stage('Verify Traces in Tempo') {
    steps {
        script {
            echo 'Verifying distributed traces...'
            sh '''
                # Query Tempo for traces
                TRACES=$(curl -s "http://localhost:3200/api/search?tags=service.name=flask-backend" | jq -r '.traces | length')

                echo "Found $TRACES traces in Tempo"

                if [ "$TRACES" -lt 5 ]; then
                    echo "ERROR: Expected at least 5 traces, found $TRACES"
                    exit 1
                fi

                echo "✅ Traces verification passed"
            '''
        }
    }
}
```

#### Verify Metrics in Prometheus

```groovy
stage('Verify Metrics in Prometheus') {
    steps {
        script {
            echo 'Verifying metrics collection...'
            sh '''
                # Query Prometheus for request count
                REQUESTS=$(curl -s 'http://localhost:9090/api/v1/query?query=http_requests_total' | jq -r '.data.result | length')

                echo "Found $REQUESTS metric series"

                if [ "$REQUESTS" -lt 1 ]; then
                    echo "ERROR: No http_requests_total metrics found"
                    exit 1
                fi

                # Check for request duration metrics
                DURATION=$(curl -s 'http://localhost:9090/api/v1/query?query=http_request_duration_seconds_count' | jq -r '.data.result | length')

                if [ "$DURATION" -lt 1 ]; then
                    echo "ERROR: No request duration metrics found"
                    exit 1
                fi

                echo "✅ Metrics verification passed"
            '''
        }
    }
}
```

#### Verify Logs in Loki

```groovy
stage('Verify Logs in Loki') {
    steps {
        script {
            echo 'Verifying log aggregation...'
            sh '''
                # Query Loki for logs
                LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
                    --data-urlencode 'query={service_name="flask-backend"}' \
                    --data-urlencode "start=$(date -u -d '5 minutes ago' '+%s')000000000" \
                    --data-urlencode "end=$(date -u '+%s')000000000" \
                    --data-urlencode "limit=100" | jq -r '.data.result[0].values | length')

                echo "Found $LOGS log entries"

                if [ "$LOGS" -lt 5 ]; then
                    echo "ERROR: Expected at least 5 log entries, found $LOGS"
                    exit 1
                fi

                # Verify service_name label exists
                LABELS=$(curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data[]')

                if ! echo "$LABELS" | grep -q "service_name"; then
                    echo "ERROR: service_name label not found in Loki"
                    exit 1
                fi

                echo "✅ Logs verification passed"
            '''
        }
    }
}
```

#### SLI/SLO Validation

```groovy
stage('SLI/SLO Validation') {
    steps {
        script {
            echo 'Validating SLI/SLO metrics...'
            sh '''
                # Calculate availability SLI
                TOTAL=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(http_requests_total)' | jq -r '.data.result[0].value[1]')
                ERRORS=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(http_errors_total)' | jq -r '.data.result[0].value[1]')

                if [ "$ERRORS" == "null" ]; then ERRORS=0; fi

                AVAILABILITY=$(echo "scale=2; (($TOTAL - $ERRORS) / $TOTAL) * 100" | bc)

                echo "Availability SLI: $AVAILABILITY%"
                echo "Target: 99%"

                # Check if availability meets SLO
                if (( $(echo "$AVAILABILITY < 99" | bc -l) )); then
                    echo "⚠️  WARNING: Availability below SLO target"
                else
                    echo "✅ Availability SLI passed"
                fi

                # Calculate P95 latency
                P95=$(curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket[5m]))by(le))' | jq -r '.data.result[0].value[1]')

                echo "P95 Latency: ${P95}s"
                echo "Target: <0.5s"

                if (( $(echo "$P95 > 0.5" | bc -l) )); then
                    echo "⚠️  WARNING: P95 latency above SLO target"
                else
                    echo "✅ Latency SLI passed"
                fi
            '''
        }
    }
}
```

#### Generate Observability Report

```groovy
stage('Generate Observability Report') {
    steps {
        script {
            echo 'Generating observability report...'
            sh '''
                cat > observability-report.txt <<EOF
========================================
OpenTelemetry Observability Lab Report
========================================
Build: ${BUILD_NUMBER}
Date: $(date)

TRACES (Tempo)
--------------
$(curl -s "http://localhost:3200/api/search?tags=service.name=flask-backend" | jq -r '.traces | length') traces collected

METRICS (Prometheus)
--------------------
Total Requests: $(curl -s 'http://localhost:9090/api/v1/query?query=sum(http_requests_total)' | jq -r '.data.result[0].value[1]')
Total Errors: $(curl -s 'http://localhost:9090/api/v1/query?query=sum(http_errors_total)' | jq -r '.data.result[0].value[1] // "0"')
P95 Latency: $(curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket[5m]))by(le))' | jq -r '.data.result[0].value[1]')s

LOGS (Loki)
-----------
$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" --data-urlencode 'query={service_name="flask-backend"}' --data-urlencode "start=$(date -u -d '5 minutes ago' '+%s')000000000" --data-urlencode "end=$(date -u '+%s')000000000" | jq -r '.data.result[0].values | length') log entries

LABELS
------
$(curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data | join(", ")')

========================================
EOF
                cat observability-report.txt
            '''

            archiveArtifacts artifacts: 'observability-report.txt', fingerprint: true
        }
    }
}
```

#### Export Grafana Dashboards

```groovy
stage('Export Grafana Dashboards') {
    steps {
        script {
            echo 'Exporting Grafana dashboards as JSON...'
            sh '''
                mkdir -p grafana-exports

                # List all dashboards
                curl -s http://localhost:3000/api/search | jq -r '.[].uid' | while read uid; do
                    echo "Exporting dashboard: $uid"
                    curl -s "http://localhost:3000/api/dashboards/uid/$uid" | jq '.dashboard' > "grafana-exports/${uid}.json"
                done
            '''

            archiveArtifacts artifacts: 'grafana-exports/*.json', fingerprint: true
        }
    }
}
```

### GitLab CI Integration

```yaml
# .gitlab-ci.yml
variables:
  DOCKER_DRIVER: overlay2

stages:
  - setup
  - test
  - verify
  - cleanup

setup_observability:
  stage: setup
  script:
    - cd otel-observability-lab
    - docker compose up -d
    - sleep 30  # Wait for services

test_telemetry:
  stage: test
  script:
    - for i in {1..10}; do curl -X POST http://localhost:5000/api/tasks -H "Content-Type: application/json" -d "{\"title\":\"Test $i\"}"; done
    - sleep 10

verify_traces:
  stage: verify
  script:
    - TRACES=$(curl -s "http://localhost:3200/api/search?tags=service.name=flask-backend" | jq -r '.traces | length')
    - if [ "$TRACES" -lt 5 ]; then exit 1; fi

verify_metrics:
  stage: verify
  script:
    - curl -s 'http://localhost:9090/api/v1/query?query=http_requests_total' | jq '.data.result | length'

cleanup:
  stage: cleanup
  when: always
  script:
    - cd otel-observability-lab
    - docker compose down -v
```

---

## Production Readiness Validation

### Security Checklist

- [ ] **OTLP Endpoints**: Enable TLS
  ```yaml
  exporters:
    otlp/tempo:
      endpoint: tempo:4317
      tls:
        insecure: false
        cert_file: /certs/client.crt
        key_file: /certs/client.key
        ca_file: /certs/ca.crt
  ```

- [ ] **Grafana Authentication**: Disable anonymous auth
  ```yaml
  environment:
    - GF_AUTH_ANONYMOUS_ENABLED=false
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
  ```

- [ ] **Sensitive Data**: Sanitize from spans/logs
  ```python
  span.set_attribute("user.email", sanitize_email(user.email))
  # Instead of: span.set_attribute("user.email", user.email)
  ```

- [ ] **API Keys**: Store in secrets manager

### Scalability Checklist

- [ ] **Collector Scaling**: Run multiple collector instances behind load balancer
- [ ] **Tempo Backend**: Switch from local storage to S3/GCS
- [ ] **Prometheus**: Implement Thanos for long-term storage
- [ ] **Loki**: Enable distributed mode for high-volume logs

### Reliability Checklist

- [ ] **Sampling**: Implement tail-based sampling
  ```yaml
  processors:
    tail_sampling:
      policies:
        - name: errors-policy
          type: status_code
          status_code: {status_codes: [ERROR]}
        - name: slow-requests
          type: latency
          latency: {threshold_ms: 1000}
        - name: probabilistic
          type: probabilistic
          probabilistic: {sampling_percentage: 10}
  ```

- [ ] **Backpressure**: Configure queue sizes
  ```yaml
  exporters:
    otlp/tempo:
      sending_queue:
        enabled: true
        num_consumers: 10
        queue_size: 1000
      retry_on_failure:
        enabled: true
        initial_interval: 5s
        max_interval: 30s
  ```

- [ ] **Health Checks**: Implement liveness/readiness probes

### Cost Optimization Checklist

- [ ] **Retention Policies**: Set appropriate data retention
  ```yaml
  # prometheus.yml
  global:
    storage.tsdb.retention.time: 15d

  # loki-config.yml
  limits_config:
    retention_period: 7d

  # tempo.yml
  compactor:
    compaction:
      block_retention: 48h
  ```

- [ ] **Cardinality Management**: Limit high-cardinality labels
- [ ] **Metric Aggregation**: Pre-aggregate in application

### Monitoring the Monitors

- [ ] **Collector Metrics**: Monitor collector health
  ```promql
  # Collector CPU/memory
  process_cpu_seconds_total{service="otel-collector"}
  process_resident_memory_bytes{service="otel-collector"}

  # Export failures
  rate(otelcol_exporter_send_failed_spans[5m])
  rate(otelcol_exporter_send_failed_metric_points[5m])
  ```

- [ ] **Backend Health**: Alert on storage issues
  ```promql
  # Tempo ingestion rate
  rate(tempo_ingester_spans_received_total[5m])

  # Loki ingestion errors
  rate(loki_distributor_errors_total[5m])

  # Prometheus storage
  prometheus_tsdb_storage_blocks_bytes
  ```

---

## Troubleshooting Common Issues

For detailed troubleshooting playbooks, see:
- **[common-issues.md](troubleshooting/common-issues.md)** - Quick reference for frequent verification issues
- **[JOURNEY.md](JOURNEY.md)** - Complete development troubleshooting stories

### Quick Diagnostic Commands

```bash
# Check all containers
docker compose -p lab ps

# Check specific service logs
docker compose -p lab logs backend --tail=100

# Check backend health
curl http://192.168.122.250:5000/health

# Check Prometheus targets
curl -s http://192.168.122.250:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check Grafana
curl http://192.168.122.250:3000/api/health
```

---

## Quick Health Check Script

Save this script on your VM for quick verification:

```bash
#!/bin/bash
# health-check.sh - Quick observability lab health check

echo "=== Observability Lab Health Check ==="
echo

echo "1. Container Status:"
docker compose -p lab ps | grep -E "(backend|frontend|prometheus|grafana)"
echo

echo "2. Backend Health:"
docker compose -p lab exec backend python -c "import urllib.request; print('✓ Healthcheck OK')" 2>&1 | head -1
echo

echo "3. DNS Resolution:"
docker compose -p lab exec frontend getent hosts backend | awk '{print "✓ backend →", $1}'
echo

echo "4. API Connectivity:"
curl -s -o /dev/null -w "✓ HTTP %{http_code}\n" http://192.168.122.250:8080/api/tasks
echo

echo "5. Prometheus Target:"
curl -s http://192.168.122.250:9090/api/v1/targets 2>/dev/null | \
  python3 -c "import sys, json; \
    targets = json.load(sys.stdin)['data']['activeTargets']; \
    flask = [t for t in targets if t['labels']['job'] == 'flask-backend']; \
    print('✓ flask-backend:', flask[0]['health'] if flask else 'NOT FOUND')" 2>/dev/null || echo "✗ Prometheus API error"
echo

echo "6. Grafana:"
curl -s -o /dev/null -w "✓ HTTP %{http_code}\n" http://192.168.122.250:3000
echo

echo "=== Health Check Complete ==="
```

**Usage:**
```bash
chmod +x health-check.sh
./health-check.sh
```

**Expected output (healthy system):**
```
=== Observability Lab Health Check ===

1. Container Status:
flask-backend   ...   Up (healthy)
frontend        ...   Up
prometheus      ...   Up
grafana         ...   Up

2. Backend Health:
✓ Healthcheck OK

3. DNS Resolution:
✓ backend → 172.18.0.7

4. API Connectivity:
✓ HTTP 200

5. Prometheus Target:
✓ flask-backend: up

6. Grafana:
✓ HTTP 200

=== Health Check Complete ===
```

---

## Success Criteria Summary

All verification steps complete when:

- ✅ Backend container status: **"Up (healthy)"**
- ✅ Backend logs show: **"Database initialized"** and **"event listeners registered"**
- ✅ DNS resolution: `getent hosts backend` returns IP
- ✅ API from frontend container: Returns JSON (no errors)
- ✅ API through Nginx: Returns JSON (no 502 errors)
- ✅ Metrics endpoint: Returns Prometheus metrics with `db_query_duration_seconds`
- ✅ Prometheus target: **flask-backend** shows **"UP"** state
- ✅ Grafana data sources: All show **"Data source is working"**
- ✅ SLI/SLO panels: Show data (after generating traffic)
- ✅ DB P95 panel: Shows data (after DB smoke test)
- ✅ Tempo traces: Show DB query spans

---

## Additional Resources

- **[CONFIGURATION-REFERENCE.md](CONFIGURATION-REFERENCE.md)** - Complete YAML configuration reference
- **[IMPLEMENTATION-GUIDE.md](IMPLEMENTATION-GUIDE.md)** - Setup guide and integration patterns
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design and component relationships
- **[architecture/network.md](architecture/network.md)** - Nginx proxy and DNS resolution details
- **[troubleshooting/README.md](troubleshooting/README.md)** - Troubleshooting guide index

---

**Document Version**: 1.0
**Last Updated**: October 22, 2025
**Lab Version**: OpenTelemetry Collector 0.96.0

---

**Phase 1 Documentation Set v1.0** | Last Reviewed: October 22, 2025
