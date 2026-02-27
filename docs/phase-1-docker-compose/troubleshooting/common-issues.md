# Common Verification Issues

## Issue 1: Backend shows "unhealthy" status

**Symptoms:**
```bash
docker compose -p lab ps
# flask-backend shows "Up (unhealthy)" or "starting"
```

**Diagnosis:**
```bash
# Check healthcheck command execution
docker compose -p lab exec backend python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/metrics', timeout=2).read()"
```

**Common causes:**
1. Flask app crashed → Check `docker compose -p lab logs backend` for errors
2. `/metrics` endpoint not responding → App may still be starting
3. Python import error → Verify `urllib.request` is available (should be in stdlib)

**Fix:**
```bash
# Wait longer for start_period (5 seconds)
sleep 10
docker compose -p lab ps

# If still unhealthy, check logs
docker compose -p lab logs backend | tail -100
```

---

## Issue 2: Nginx 502 "backend could not be resolved"

**Symptoms:**
```bash
curl http://192.168.122.250:8080/api/tasks
# Returns: 502 Bad Gateway

docker compose -p lab logs frontend | grep error
# Shows: backend could not be resolved (3: Host not found)
```

**Diagnosis:**
```bash
# Test DNS from frontend container
docker compose -p lab exec frontend getent hosts backend
# If no output → DNS problem
```

**Common causes:**
1. Backend container not running → `docker compose -p lab ps`
2. Backend not on otel-network → Check network config
3. Service name mismatch → Verify `backend` in docker-compose.yml

**Fix:**
```bash
# Restart frontend to re-resolve DNS
docker compose -p lab restart frontend

# Verify backend is up and healthy
docker compose -p lab ps | grep backend

# Check network membership
docker inspect -f '{{.Name}} -> {{range .NetworkSettings.Networks}}{{.Name}}{{end}}' \
  $(docker compose -p lab ps -q frontend backend)
```

---

## Issue 3: Grafana panels show "No data"

**Symptoms:**
- Dashboard panels are blank or show "No data" message
- Time range selector shows "Last 5 minutes" or similar

**Diagnosis:**
```bash
# Check Prometheus is scraping
curl -s http://192.168.122.250:9090/api/v1/targets | grep flask-backend

# Check metrics are being exported
curl -s http://192.168.122.250:5000/metrics | grep http_requests_total
```

**Common causes:**
1. No traffic generated yet → Use the UI to create requests
2. Prometheus target down → Check Step 8
3. Time range too narrow → Expand to "Last 15 minutes" in Grafana

**Fix:**
```bash
# Generate traffic
for i in {1..10}; do
  curl http://192.168.122.250:8080/api/tasks
  sleep 1
done

# Wait for scrape
sleep 20

# Refresh Grafana dashboard
# Expand time range to "Last 15 minutes"
```

---

## Issue 4: DB P95 Latency panel shows "No data"

**Symptoms:**
- Other panels work fine
- "Database Query P95 Latency" panel remains empty

**Diagnosis:**
```bash
# Check if histogram metrics exist
curl -s http://192.168.122.250:5000/metrics | grep db_query_duration_seconds_bucket
```

**Common causes:**
1. No DB queries executed yet → Histogram has no samples
2. Event listeners not registered → Check backend logs for "event listeners registered"
3. Metric name mismatch → Verify `db_query_duration_seconds` in code and dashboard

**Fix:**
```bash
# Verify event listeners are registered
docker compose -p lab logs backend | grep "event listeners registered"

# Generate DB traffic
curl "http://192.168.122.250:8080/api/smoke/db?ops=300&type=rw"

# Wait for Prometheus scrape
sleep 90

# Check histogram has data
curl -s http://192.168.122.250:5000/metrics | grep db_query_duration_seconds_bucket | grep -v "0.0$"

# Refresh Grafana panel
```

---
