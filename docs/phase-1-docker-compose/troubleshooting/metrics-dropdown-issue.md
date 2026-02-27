# Grafana Metrics Dropdown Troubleshooting Guide

## Problem Statement

**Symptom**: Grafana Explore → Prometheus → Builder mode → Metrics dropdown shows "No options found" or stays empty, even though:
- Code mode works (typing `up` returns results)
- Prometheus API endpoints return data
- All services are healthy

**Environment**:
- Grafana 10.2.3
- Prometheus v2.48.1
- Docker Compose deployment
- Both local and VM environments affected

---

## Root Cause (Actual Solution)

### The Real Issue: Time Range Mismatch

**The metrics dropdown is time-range aware**. When Grafana requests metric names from Prometheus, it includes the currently selected time range. If no data exists in that time range, the API returns an empty array, causing the dropdown to appear empty.

**What happened in our case**:
1. Grafana was showing "Last 6 hours" time range
2. The containers had just been restarted (fresh data)
3. Prometheus only had data from the last ~10 minutes
4. Grafana requested metrics for 6 hours ago → Prometheus returned empty results
5. Dropdown appeared broken, but it was just "no data for that time range"

**The Fix**: Change time range to "Last 5 minutes" or "Last 1 hour" to match available data.

---

## Troubleshooting Journey & Methodology

This documents the systematic approach we used to isolate the problem, including all diagnostic tools and techniques.

### Phase 1: Initial Hypothesis - HTTP Method Issue

**Initial theory**: The `httpMethod: POST` setting in datasources.yml was causing issues with Prometheus label API endpoints.

#### Test 1: Check Prometheus API directly from Grafana container

```bash
#!/bin/bash
# Test if Prometheus label API works with GET vs POST

# GET request (what should work)
docker exec grafana sh -c '
  apk add --no-cache curl >/dev/null 2>&1 || true
  curl -s -w "\nHTTP_CODE:%{http_code}\n" \
    "http://prometheus:9090/api/v1/label/__name__/values"
' | tail -5

# POST request (what we suspected was failing)
docker exec grafana sh -c '
  curl -s -w "\nHTTP_CODE:%{http_code}\n" \
    -X POST "http://prometheus:9090/api/v1/label/__name__/values"
' | tail -5
```

**Result**: GET returned 200, POST returned 405 (Method Not Allowed) from Prometheus.

#### Test 2: Check Grafana's proxy behavior

Created `test-grafana-proxy.sh`:

```bash
#!/bin/bash
# Test Grafana's datasource proxy (what the UI actually uses)

echo "Testing via Grafana's datasource proxy..."

# Test GET through Grafana proxy
echo "GET request:"
curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values" \
  | grep -E "HTTP_CODE|data"

# Test POST through Grafana proxy
echo ""
echo "POST request:"
curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -X POST \
  "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values" \
  | grep -E "HTTP_CODE|message"
```

**Key Discovery**: POST returned HTTP 403 with message:
```json
{"message":"non allow-listed POSTs not allowed on proxied Prometheus datasource"}
```

This revealed **Grafana's security policy** blocks POST to label endpoints, not just Prometheus.

#### Test 3: Remove httpMethod: POST from config

```bash
# Modified grafana/provisioning/datasources/datasources.yml
# Removed the line: httpMethod: POST

# Restart Grafana
docker compose -p lab restart grafana

# Verify config loaded
docker exec grafana cat /etc/grafana/provisioning/datasources/datasources.yml | \
  grep -A 10 "name: Prometheus"
```

**Result**: This fixed the API layer issue, but the dropdown still didn't populate in the browser.

---

### Phase 2: Grafana State & Cache Issues

**New hypothesis**: Grafana cached the old configuration and wasn't picking up changes.

#### Test 4: Check Grafana's internal datasource state

```bash
# Query Grafana's API to see the actual datasource config
curl -s http://localhost:3000/api/datasources/uid/prometheus | \
  jq '{name, type, uid, jsonData}'
```

**Result**: Config looked correct (no httpMethod), but logs showed POST was still being used.

#### Test 5: Check Grafana logs for actual requests

```bash
#!/bin/bash
# Monitor Grafana logs in real-time
docker logs grafana --follow 2>&1 | \
  grep --line-buffered -E "method=(GET|POST).*(label|__name__|query)"
```

**Discovery**: Logs showed:
```
method=POST path=/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values status=403
```

Grafana was **still using POST** even after config change!

#### Test 6: Complete state reset

```bash
# Stop everything
docker compose -p lab down

# Remove Grafana volume (contains cached state)
docker volume rm lab_grafana-data

# Start fresh
docker compose -p lab up -d

# Wait for startup
sleep 30
```

**Result**: After complete reset, API calls worked, but browser dropdown still empty!

---

### Phase 3: Browser-Side Investigation (The Breakthrough)

**New hypothesis**: If the API works but the UI doesn't, the problem is browser-side.

#### Test 7: Use Browser DevTools (Network Tab)

**Steps**:
1. Open http://localhost:3000 in browser
2. Press F12 → Network tab
3. Navigate to Explore → Prometheus → Builder
4. Click "Metrics" dropdown
5. Look for API calls

**Discovery from Network Tab**:

```
Request URL:
http://localhost:3000/api/datasources/uid/prometheus/resources/api/v1/label/__name__/values?start=1761112800&end=1761134400

Method: GET
Status: 200 OK

Response:
{"status":"success","data":[]}
```

**Critical Finding**:
- HTTP 200 (success!)
- But `"data":[]"` (empty array!)
- The API worked, but returned no results

#### Test 8: Verify those exact timestamps with Prometheus

```bash
#!/bin/bash
# Test the exact time range Grafana sent

# The timestamps from browser DevTools
START=1761112800  # Oct 22 06:00:00 UTC 2025
END=1761134400    # Oct 22 12:00:00 UTC 2025

echo "Testing with browser's time range:"
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=${START}&end=${END}" | \
  jq '{status, data_count: (.data | length)}'

echo ""
echo "Testing without time range:"
curl -s "http://localhost:9090/api/v1/label/__name__/values" | \
  jq '{status, data_count: (.data | length)}'
```

**Result**:
```json
// With time range from browser:
{"status": "success", "data_count": 0}

// Without time range:
{"status": "success", "data_count": 1047}
```

**THE SMOKING GUN**: Prometheus had 1047 metrics available, but **zero metrics existed in the time range Grafana requested**!

#### Test 9: Calculate current time and verify data availability

```bash
#!/bin/bash
# Check when containers were started vs requested time range

# Current timestamp
NOW=$(date +%s)
echo "Current time: $NOW ($(date -d @${NOW} 2>/dev/null || date -r ${NOW}))"

# Requested range from browser
START=1761112800
END=1761134400
echo "Browser requested: $START to $END"
echo "That's $(( (NOW - END) / 3600 )) hours ago!"

# Check when Prometheus started collecting data
echo ""
echo "Prometheus earliest data:"
curl -s 'http://localhost:9090/api/v1/query?query=up' | \
  jq -r '.data.result[0].value[0]' | \
  xargs -I {} date -d @{} 2>/dev/null || echo "Check manually"

# Test with current 6-hour range
SIX_HOURS_AGO=$((NOW - 21600))
echo ""
echo "Testing with current 6-hour range:"
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=${SIX_HOURS_AGO}&end=${NOW}" | \
  jq '{status, data_count: (.data | length)}'
```

**Result**: The browser was requesting data from **7 hours ago**, but Prometheus only had data from the last **10 minutes** (since restart).

---

## The Complete Diagnostic Toolkit

### Script 1: Basic Connectivity Check

**File**: `debug-metrics-dropdown.sh`

```bash
#!/bin/bash
# Quick diagnostic for Grafana → Prometheus connectivity

PROJECT="${PROJECT:-lab}"

echo "=========================================="
echo "Grafana → Prometheus Connectivity Check"
echo "=========================================="
echo ""

# 1. Check containers
echo "1. Container Status:"
docker ps --filter "name=grafana" --filter "name=prometheus" \
  --format "table {{.Names}}\t{{.Status}}"
echo ""

# 2. Basic connectivity
echo "2. Basic Connectivity Test:"
docker exec grafana sh -c 'command -v curl >/dev/null || apk add --no-cache curl >/dev/null 2>&1'
docker exec grafana curl -s -o /dev/null -w "Prometheus health: HTTP %{http_code}\n" \
  "http://prometheus:9090/-/ready"
echo ""

# 3. Label API (what Builder uses)
echo "3. Metrics Label API Test:"
START=$(date -d "1 hour ago" +%s 2>/dev/null || date -v-1H +%s)
END=$(date +%s)
docker exec grafana curl -s -o /dev/null -w "Label API: HTTP %{http_code}\n" \
  "http://prometheus:9090/api/v1/label/__name__/values?start=$START&end=$END"
echo ""

# 4. Sample metric names
echo "4. Sample Metric Names:"
docker exec grafana curl -s "http://prometheus:9090/api/v1/label/__name__/values" | \
  head -c 500
echo -e "\n...\n"

# 5. Time check
echo "5. Time Synchronization:"
echo "   System:     $(date)"
echo "   Prometheus: $(docker exec prometheus date)"
echo ""

# 6. Current datasource config
echo "6. Current Datasource Config:"
docker exec grafana grep -A 8 "name: Prometheus" \
  /etc/grafana/provisioning/datasources/datasources.yml | grep -v "^--"
echo ""

echo "=========================================="
echo "If all checks pass but dropdown is empty:"
echo "- Check browser DevTools Network tab"
echo "- Verify time range in Grafana UI"
echo "- Try changing to 'Last 5 minutes'"
echo "=========================================="
```

---

### Script 2: Deep Diagnostic

**File**: `diagnose-metrics-ui.sh`

```bash
#!/bin/bash
# Comprehensive diagnostic for Grafana metrics dropdown

PROJECT="${PROJECT:-lab}"

echo "=========================================="
echo "Grafana Metrics Dropdown Deep Diagnostic"
echo "=========================================="
echo ""

# Detect container names
GRAFANA_CONTAINER=$(docker ps --filter "name=grafana" --format "{{.Names}}" | head -1)
PROMETHEUS_CONTAINER=$(docker ps --filter "name=prometheus" --format "{{.Names}}" | head -1)

if [ -z "$GRAFANA_CONTAINER" ]; then
    echo "❌ Grafana container not found"
    exit 1
fi

echo "✅ Using containers: $GRAFANA_CONTAINER, $PROMETHEUS_CONTAINER"
echo ""

# 1. Grafana version
echo "1. Grafana Version:"
docker exec $GRAFANA_CONTAINER grafana-cli --version 2>/dev/null | grep -i "grafana version"
echo ""

# 2. Test label API with and without time range
echo "2. Testing Label API (with/without time range):"
docker exec $GRAFANA_CONTAINER sh -c 'command -v curl >/dev/null || apk add curl >/dev/null 2>&1'

echo "   Without time range:"
RESPONSE=$(docker exec $GRAFANA_CONTAINER curl -s \
  "http://prometheus:9090/api/v1/label/__name__/values")
COUNT=$(echo "$RESPONSE" | grep -o '","' | wc -l)
echo "   Response: $(echo "$RESPONSE" | head -c 100)..."
echo "   Metric count: ~$COUNT"
echo ""

echo "   With 6-hour time range:"
NOW=$(date +%s)
SIX_HOURS=$((NOW - 21600))
RESPONSE=$(docker exec $GRAFANA_CONTAINER curl -s \
  "http://prometheus:9090/api/v1/label/__name__/values?start=$SIX_HOURS&end=$NOW")
COUNT=$(echo "$RESPONSE" | grep -o '"data":\[' | wc -l)
if [ "$COUNT" -gt 0 ]; then
    ITEMS=$(echo "$RESPONSE" | grep -o '","' | wc -l)
    echo "   ✅ Got $ITEMS metrics for last 6 hours"
else
    echo "   ⚠️  No metrics for last 6 hours (containers recently restarted?)"
fi
echo ""

# 3. Test Grafana proxy endpoint
echo "3. Testing Grafana Datasource Proxy:"
curl -s -w "\n   HTTP Status: %{http_code}\n" \
  "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values" | \
  head -c 200
echo -e "\n"

# 4. Check Grafana logs for errors
echo "4. Recent Grafana Errors:"
docker logs $GRAFANA_CONTAINER --tail 100 2>&1 | \
  grep -i "error\|fail\|403\|405" | tail -5
echo ""

# 5. Datasource health
echo "5. Datasource Health Check:"
curl -s "http://localhost:3000/api/datasources/uid/prometheus/health" | \
  jq -r '.status, .message' 2>/dev/null || echo "Check manually"
echo ""

# 6. Network connectivity
echo "6. Network Configuration:"
GRAFANA_NET=$(docker inspect $GRAFANA_CONTAINER | grep -A 3 '"Networks"' | grep -o '"otel-network"' || echo "none")
PROM_NET=$(docker inspect $PROMETHEUS_CONTAINER | grep -A 3 '"Networks"' | grep -o '"otel-network"' || echo "none")
if [ -n "$GRAFANA_NET" ] && [ -n "$PROM_NET" ]; then
    echo "   ✅ Both containers on otel-network"
else
    echo "   ❌ Network mismatch detected"
fi
echo ""

# 7. Container startup times
echo "7. Container Startup Times:"
echo "   Prometheus: $(docker inspect $PROMETHEUS_CONTAINER | jq -r '.[0].State.StartedAt')"
echo "   Grafana:    $(docker inspect $GRAFANA_CONTAINER | jq -r '.[0].State.StartedAt')"
echo ""

# 8. Data availability window
echo "8. Prometheus Data Window:"
OLDEST=$(docker exec $PROMETHEUS_CONTAINER sh -c \
  "date -d @\$(curl -s 'http://localhost:9090/api/v1/query?query=up' | \
  grep -o '\"value\":\[[0-9.]*' | head -1 | grep -o '[0-9]*' | head -1) 2>/dev/null || echo '?'")
echo "   Earliest data: $OLDEST"
echo "   Current time:  $(date)"
echo ""

echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo "1. Open browser DevTools (F12) → Network tab"
echo "2. Navigate to Grafana Explore → Prometheus"
echo "3. Click Metrics dropdown"
echo "4. Look for API call with 'label/__name__/values'"
echo "5. Check the 'start' and 'end' parameters"
echo "6. Compare with available data window above"
echo ""
echo "Common fix: Change time range to 'Last 5 minutes'"
echo "=========================================="
```

---

### Script 3: Grafana Proxy Test

**File**: `test-grafana-proxy.sh`

```bash
#!/bin/bash
# Test Grafana's proxy behavior for Prometheus datasource

echo "=========================================="
echo "Testing Grafana Proxy to Prometheus"
echo "=========================================="
echo ""

# 1. Test GET through proxy
echo "1. GET Request (should work):"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

echo "   Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    COUNT=$(echo "$BODY" | grep -o '","' | wc -l)
    echo "   ✅ Success - ~$COUNT metrics"
else
    echo "   ❌ Failed"
    echo "   Response: $BODY" | head -c 200
fi
echo ""

# 2. Test POST through proxy
echo "2. POST Request (should fail with 403):"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -X POST \
  "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

echo "   Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "403" ]; then
    echo "   ✅ Expected 403 - POST blocked by Grafana security"
    echo "   Message: $BODY"
else
    echo "   Response: $BODY"
fi
echo ""

# 3. Datasource configuration
echo "3. Current Datasource Config:"
curl -s "http://localhost:3000/api/datasources/uid/prometheus" | \
  jq '{name, type, uid, jsonData}' 2>/dev/null || echo "Check manually"
echo ""

# 4. Health check
echo "4. Datasource Health:"
curl -s "http://localhost:3000/api/datasources/uid/prometheus/health" | \
  jq -r '.status, .message' 2>/dev/null || echo "OK"
echo ""

echo "=========================================="
echo "Analysis:"
echo "=========================================="
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Grafana proxy is working correctly"
    echo ""
    echo "If dropdown still empty, this is a TIME RANGE issue:"
    echo "- Open browser DevTools → Network tab"
    echo "- Click metrics dropdown"
    echo "- Check 'start' and 'end' parameters"
    echo "- Change to 'Last 5 minutes' in Grafana UI"
else
    echo "❌ Grafana proxy issue detected"
    echo "- Check datasources.yml for httpMethod: POST"
    echo "- Restart Grafana after config changes"
    echo "- May need to remove Grafana volume for clean state"
fi
echo "=========================================="
```

---

### Script 4: Real-Time Log Monitor

**File**: `monitor-dropdown-requests.sh`

```bash
#!/bin/bash
# Monitor Grafana API requests in real-time

GRAFANA_CONTAINER=$(docker ps --filter "name=grafana" --format "{{.Names}}" | head -1)

echo "=========================================="
echo "Real-Time Grafana Request Monitor"
echo "=========================================="
echo ""
echo "Instructions:"
echo "1. Keep this terminal visible"
echo "2. In browser: Go to Grafana Explore"
echo "3. Click the Metrics dropdown"
echo "4. Watch for API calls below"
echo ""
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

# Follow logs and filter for API requests
docker logs $GRAFANA_CONTAINER --follow 2>&1 | \
  grep --line-buffered -E "method=(GET|POST).*(label|__name__|query|proxy)" | \
  while read line; do
    echo "[$(date +%H:%M:%S)] $line"

    # Highlight important patterns
    if echo "$line" | grep -q "status=403"; then
        echo "   ⚠️  403 Forbidden - Check httpMethod setting"
    elif echo "$line" | grep -q "status=405"; then
        echo "   ⚠️  405 Method Not Allowed - POST not supported"
    elif echo "$line" | grep -q "status=200.*label/__name__"; then
        echo "   ✅ Label API call succeeded"
    fi
done
```

---

## Browser DevTools Investigation Steps

### Using Network Tab (The Critical Step)

1. **Open DevTools**:
   ```
   Press F12 (or Right-click → Inspect)
   Go to Network tab
   ```

2. **Enable logging**:
   ```
   ☑ Check "Preserve log"
   ☑ Check "Disable cache" (optional)
   ```

3. **Trigger the request**:
   ```
   Navigate to: Explore → Prometheus → Builder
   Click: Metrics dropdown
   ```

4. **Analyze the request**:
   - Look for: `/api/datasources/uid/prometheus/resources/api/v1/label/__name__/values`
   - Check Method: Should be `GET`
   - Check Status: Should be `200 OK`
   - **Check Parameters**: Look for `start` and `end`
   - **Check Response**: Click on the request → Response tab

5. **Key things to verify**:
   ```
   Request URL parameters:
   - start: [unix timestamp]
   - end: [unix timestamp]

   Response body:
   {
     "status": "success",
     "data": [...]  // <-- Is this empty?
   }
   ```

### Using Console Tab

```javascript
// Clear Grafana cache
localStorage.clear();
sessionStorage.clear();
location.reload();

// Check current time in browser
console.log("Browser time:", new Date().toISOString());
console.log("Unix timestamp:", Math.floor(Date.now() / 1000));

// Manually test API
fetch('/api/datasources/uid/prometheus/resources/api/v1/label/__name__/values')
  .then(r => r.json())
  .then(d => console.log('Metric count:', d.data.length));
```

---

## The Solution: Time Range Configuration

### Why the Dropdown Appeared Empty

1. **Grafana's Metrics API is time-range aware**
   - The `/api/v1/label/__name__/values` endpoint accepts `start` and `end` parameters
   - Prometheus only returns metrics that have data points in that range
   - This is by design - helps with performance on large deployments

2. **Our specific situation**:
   - Containers were freshly restarted → only ~10 minutes of data
   - Grafana UI showed "Last 6 hours" → requested data from 6 hours ago
   - Prometheus correctly returned empty array (no data exists that far back)
   - Dropdown showed "No options found"

3. **Why it seemed like a config problem**:
   - The API technically worked (HTTP 200)
   - Other queries in Code mode worked (they used current time)
   - Only the dropdown failed (because it respected the UI time range)

### The Fix

**Immediate fix**:
```
In Grafana UI (top-right corner):
Change time range from "Last 6 hours" → "Last 5 minutes"
Click Metrics dropdown → Should populate with 1000+ metrics
```

**Permanent solution for fresh deployments**:
```bash
# Option 1: Wait for data to accumulate
# After starting containers, wait 15-30 minutes before using long time ranges

# Option 2: Use shorter default time ranges
# When exploring a fresh deployment, start with "Last 5 minutes"

# Option 3: Pre-populate with historical data (advanced)
# Use Prometheus remote write to backfill data if needed
```

### Understanding Time Range Behavior

```bash
#!/bin/bash
# Demonstrate time range effect on metrics API

NOW=$(date +%s)
ONE_HOUR_AGO=$((NOW - 3600))
SIX_HOURS_AGO=$((NOW - 21600))
ONE_DAY_AGO=$((NOW - 86400))

echo "Testing different time ranges:"
echo ""

# No time range - returns all known metrics
echo "1. No time range (all metrics ever seen):"
curl -s "http://localhost:9090/api/v1/label/__name__/values" | \
  jq '.data | length'
echo ""

# Last hour - returns metrics with data in last hour
echo "2. Last 1 hour:"
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=$ONE_HOUR_AGO&end=$NOW" | \
  jq '.data | length'
echo ""

# Last 6 hours - may return fewer if containers recently restarted
echo "3. Last 6 hours:"
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=$SIX_HOURS_AGO&end=$NOW" | \
  jq '.data | length'
echo ""

# Last 24 hours - likely empty on fresh deployment
echo "4. Last 24 hours:"
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=$ONE_DAY_AGO&end=$NOW" | \
  jq '.data | length'
echo ""

echo "Note: Metric count decreases as time range extends beyond available data"
```

---

## Troubleshooting Checklist

Use this checklist to systematically diagnose metrics dropdown issues:

### Level 1: Quick Checks (2 minutes)

- [ ] **Containers running?**
  ```bash
  docker ps | grep -E "grafana|prometheus"
  ```

- [ ] **Basic connectivity?**
  ```bash
  curl -s http://localhost:3000/api/health
  curl -s http://localhost:9090/-/healthy
  ```

- [ ] **Browser time range?**
  ```
  Check top-right corner of Grafana Explore
  Try changing to "Last 5 minutes"
  ```

### Level 2: API Validation (5 minutes)

- [ ] **Prometheus has metrics?**
  ```bash
  curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq '.data | length'
  # Should return > 0
  ```

- [ ] **Grafana proxy works?**
  ```bash
  ./test-grafana-proxy.sh
  # Should show HTTP 200 for GET
  ```

- [ ] **No httpMethod: POST?**
  ```bash
  docker exec grafana grep httpMethod /etc/grafana/provisioning/datasources/datasources.yml
  # Should return nothing or "No such file"
  ```

### Level 3: Deep Investigation (15 minutes)

- [ ] **Run comprehensive diagnostic**
  ```bash
  ./diagnose-metrics-ui.sh
  ```

- [ ] **Check Grafana logs**
  ```bash
  docker logs grafana --tail 50 | grep -i "error\|403\|405"
  ```

- [ ] **Browser DevTools investigation**
  - Open Network tab
  - Click Metrics dropdown
  - Find `/label/__name__/values` request
  - Check response: `"data":[]` or `"data":[...]`?
  - Note `start` and `end` parameters

- [ ] **Verify time range alignment**
  ```bash
  # Get container start time
  docker inspect prometheus | jq '.[0].State.StartedAt'

  # Compare with time range from browser DevTools
  # If browser requests data before container start → empty results
  ```

### Level 4: Nuclear Option (if nothing else works)

- [ ] **Complete reset**
  ```bash
  # Stop everything
  docker compose -p lab down -v

  # Remove ALL volumes (WARNING: loses all data)
  docker volume rm lab_grafana-data lab_prometheus-data

  # Start fresh
  docker compose -p lab up -d

  # Wait for initialization
  sleep 60

  # Use "Last 5 minutes" time range
  ```

---

## Prevention & Best Practices

### For Development

1. **Use appropriate time ranges**:
   ```
   Fresh deployment (< 1 hour old):  Use "Last 5 minutes"
   Running for hours:                 Use "Last 1 hour"
   Running for days:                  Use "Last 6 hours" or more
   ```

2. **Add startup script delay**:
   ```bash
   # In start-lab.sh, add:
   echo "⏳ Waiting for metric collection..."
   sleep 30  # Let Prometheus scrape a few times
   ```

3. **Document expected behavior**:
   ```markdown
   # README note:
   After starting the lab, wait 1-2 minutes for metrics to accumulate.
   Use "Last 5 minutes" time range when first exploring.
   ```

### For CI/CD (Jenkins Pipeline)

Add to Jenkinsfile smoke tests:

```groovy
stage('Verify Metrics Available') {
  steps {
    script {
      // Wait for Prometheus to scrape
      sleep 60

      // Verify metrics exist
      sh '''
        METRICS=$(curl -s http://${VM_IP}:9090/api/v1/label/__name__/values | \
          jq '.data | length')

        if [ "$METRICS" -lt 10 ]; then
          echo "ERROR: Only $METRICS metrics found, expected many more"
          exit 1
        fi

        echo "✅ Found $METRICS metrics"
      '''
    }
  }
}
```

### For VM Deployments

Add to deployment documentation:

```markdown
## After Deployment

1. Wait 2-3 minutes for metrics collection
2. Access Grafana: http://<VM-IP>:3000
3. Navigate to Explore → Prometheus
4. **Set time range to "Last 5 minutes"**
5. Click Metrics dropdown → Should show 1000+ metrics
```

---

## Key Learnings

### What We Learned

1. **Time-range awareness**: Prometheus label APIs filter by time range, not just return all known metrics
2. **Browser DevTools are essential**: Can't fully troubleshoot Grafana issues without inspecting actual browser requests
3. **Don't assume config issues**: Sometimes the app works perfectly, but the request parameters are wrong
4. **Empty response ≠ error**: HTTP 200 with `data:[]` is valid - it means "no data for that range"

### Common Misdiagnoses

| Symptom | Suspected Cause | Actual Cause |
|---------|----------------|--------------|
| Dropdown empty | httpMethod: POST | Time range too old |
| API returns 200 | Config is right | Response is empty array |
| Works locally, not VM | Environment difference | Both had same issue, just different time ranges |
| Restart doesn't fix | Grafana bug | Fresh data = short time range needed |

### Debugging Hierarchy

```
Browser behavior (what user sees)
    ↓
Browser DevTools (what browser requests)
    ↓
Grafana proxy (how Grafana forwards requests)
    ↓
Prometheus API (what Prometheus returns)
    ↓
Prometheus data (what actually exists)
```

**Start at the bottom** (does data exist?) but **the answer was at the top** (wrong time range in UI).

---

## Quick Reference Commands

### One-Liners for Common Checks

```bash
# Check if metrics exist (any time range)
curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq '.data | length'

# Check metrics for last hour
curl -s "http://localhost:9090/api/v1/label/__name__/values?start=$(($(date +%s)-3600))&end=$(date +%s)" | jq '.data | length'

# Test Grafana proxy
curl -s "http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values" | jq '.data | length'

# Check datasource config
curl -s "http://localhost:3000/api/datasources/uid/prometheus" | jq '.jsonData.httpMethod // "default (GET)"'

# Get container start times
docker inspect grafana prometheus --format '{{.Name}}: {{.State.StartedAt}}'

# Monitor Grafana logs
docker logs grafana --follow 2>&1 | grep --line-buffered -E "label|__name__|method=POST"

# Check Prometheus targets
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | {job, health, lastScrape}'
```

---

## Conclusion

The metrics dropdown issue turned out to be a **time range mismatch**, not a configuration or API problem. The systematic troubleshooting approach revealed:

1. ✅ API worked correctly (HTTP 200)
2. ✅ Datasource config was valid
3. ✅ Network connectivity was fine
4. ❌ **Grafana requested data from before Prometheus had any** (6 hours ago on fresh deployment)

**The fix**: Change time range to match available data ("Last 5 minutes" on fresh deployments).

**The lesson**: Always check browser DevTools to see actual request/response data before assuming backend issues.

---

## Additional Resources

### Related Documentation
- [Prometheus Label API Documentation](https://prometheus.io/docs/prometheus/latest/querying/api/#querying-label-values)
- [Grafana Datasource Proxy](https://grafana.com/docs/grafana/latest/developers/http_api/data_source/)
- [Grafana Time Range](https://grafana.com/docs/grafana/latest/dashboards/use-dashboards/#set-dashboard-time-range)

### Files Created During Troubleshooting
- `debug-metrics-dropdown.sh` - Basic connectivity tests
- `diagnose-metrics-ui.sh` - Comprehensive diagnostic
- `test-grafana-proxy.sh` - Grafana proxy behavior tests
- `monitor-dropdown-requests.sh` - Real-time log monitoring
- `check-grafana-logs.sh` - Log analysis helper

### Testing on Other Environments

```bash
# To test on your VM:
scp debug-metrics-dropdown.sh deploy@192.168.122.250:/home/deploy/lab/app/
ssh deploy@192.168.122.250 "cd /home/deploy/lab/app && chmod +x debug-metrics-dropdown.sh && ./debug-metrics-dropdown.sh"

# Then in browser on VM:
# 1. Open http://192.168.122.250:3000
# 2. Go to Explore → Prometheus
# 3. Set time range to "Last 5 minutes"
# 4. Click Metrics dropdown → Should work
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-22
**Tested With**: Grafana 10.2.3, Prometheus v2.48.1, Docker Compose v2.x
