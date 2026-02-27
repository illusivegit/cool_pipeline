# Trace Search Panel - Complete Troubleshooting Guide

## Executive Summary

This document consolidates the complete troubleshooting journey and working solution for the Grafana "Trace Search" panel with Tempo 2.3.1 and Grafana 10.2.3.

**TL;DR - Working Solution:**
- Panel type: `table` (not `traces`)
- Query type: `traceql`
- Query: `{ resource.service.name = "flask-backend" }` (no pipeline operators)
- Limit: Set in target config as `"limit": 50`, not in query string

---

## The Problem

The "Trace Search" panel in the End-to-End Tracing Dashboard was not displaying traces, while "Service Dependency Map" and "Application Logs" panels worked correctly.

**Initial symptoms:**
- "Trace Search" showed "No data found in response"
- Later showed JavaScript error: `Cannot read properties of undefined (reading 'filter')`
- Service variable dropdown appeared but had no effect

---

## Root Causes Identified

### 1. Invalid Tempo Configuration (Initial Attempt)
**Problem:** Added `search_enabled: true` at root level of `tempo.yml`
**Error:** `field search_enabled not found in type app.Config`
**Cause:** This field doesn't exist in Tempo 2.3.1 - search is enabled by default

### 2. Wrong Panel Configuration
**Problem:** Used `type: "traces"` panel with incompatible configuration
**Cause:** Grafana 10.2.3 + Tempo 2.3.1 compatibility issues with traces panel type

### 3. Incorrect TraceQL Syntax
**Problems encountered:**
- Used `service.name` instead of `resource.service.name`
- Used pipeline operator `| limit 50` (not supported in Tempo 2.3.1)
- Used experimental query types (`traceqlSearch`, `nativeSearch`)

### 4. Broken Dashboard Variable
**Problem:** `$service` variable not properly configured
**Cause:** Empty query field, not connected to panel

---

## The Working Solution

### Tempo Configuration

**File:** `otel-collector/tempo.yml`

```yaml
server:
  http_listen_port: 3200

# NO search_enabled field - search is on by default in Tempo 2.3.1

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318  # Added for HTTP protocol support

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 1h

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
    wal:
      path: /tmp/tempo/wal
    pool:
      max_workers: 100
      queue_depth: 10000

query_frontend:
  search:
    duration_slo: 5s
    throughput_bytes_slo: 1.073741824e+09
  trace_by_id:
    duration_slo: 5s

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: docker-compose
  storage:
    path: /tmp/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true

overrides:
  metrics_generator_processors: [service-graphs, span-metrics]
```

### Grafana Dashboard Panel Configuration

**File:** `grafana/dashboards/end-to-end-tracing.json`

```json
{
  "type": "table",
  "title": "Trace Search",
  "datasource": {
    "type": "tempo",
    "uid": "tempo"
  },
  "gridPos": {
    "h": 12,
    "w": 24,
    "x": 0,
    "y": 0
  },
  "id": 1,
  "targets": [
    {
      "refId": "A",
      "datasource": {
        "type": "tempo",
        "uid": "tempo"
      },
      "queryType": "traceql",
      "query": "{ resource.service.name = \"flask-backend\" }",
      "limit": 50
    }
  ],
  "fieldConfig": {
    "defaults": {},
    "overrides": []
  },
  "transformations": [
    {
      "id": "organize",
      "options": {
        "excludeByName": {},
        "indexByName": {},
        "renameByName": {}
      }
    }
  ],
  "description": "Search for traces across the entire application."
}
```

**Key elements:**
- ✅ Panel type: `"table"`
- ✅ Query type: `"traceql"`
- ✅ Correct TraceQL: `{ resource.service.name = "flask-backend" }`
- ✅ Limit in config: `"limit": 50`
- ❌ No `tableType` parameter
- ❌ No pipeline operators in query
- ❌ No `search_enabled` in Tempo config

---

## What I Tried (Chronological Journey)

### Attempt 1: Add search_enabled ❌
**Action:** Added `search_enabled: true` to `tempo.yml`
**Result:** Tempo failed to start
**Error:** `field search_enabled not found in type app.Config`
**Learning:** Tempo 2.3.1 doesn't have this field; search is always enabled

### Attempt 2: Use traceqlSearch query type ❌
**Action:** Changed panel to `queryType: "traceqlSearch"`
**Result:** JavaScript error in Grafana
**Error:** `Cannot read properties of undefined (reading 'filter')`
**Learning:** Experimental query types not stable in Grafana 10.2.3

### Attempt 3: Use nativeSearch query type ❌
**Action:** Changed to `queryType: "nativeSearch"`
**Result:** Panel showed "No data found in response"
**Learning:** Not the correct query type for this Grafana version

### Attempt 4: Fix TraceQL syntax with pipeline ❌
**Action:** Used `{ service.name = "flask-backend" } | limit 50`
**Result:** Parse error at column 47
**Error:** `syntax error: unexpected IDENTIFIER`
**Learning:** Pipeline operators not supported in Tempo 2.3.1

### Attempt 5: Fix resource prefix ❌
**Action:** Changed to `{ resource.service.name = "flask-backend" } | limit 50`
**Result:** Still parse error
**Error:** Same - pipeline operator issue
**Learning:** Correct prefix, but pipeline still wrong

### Attempt 6: Remove pipeline operator ⚠️
**Action:** Used `{ resource.service.name = "flask-backend" }` with `type: "traces"`
**Result:** "No data found in response" (even though Explore worked)
**Learning:** Query syntax correct, but panel type incompatible

### Attempt 7: Switch to table panel ✅
**Action:** Changed panel `type: "table"` with same TraceQL query
**Result:** SUCCESS - Traces displayed!
**Learning:** Table panel type works reliably with TraceQL in Grafana 10.2.3

---

## Debugging Methodology

### Step 1: Verify Tempo is Running and Has Data
```bash
# Check container status
docker compose -p lab ps tempo

# Test Tempo API directly
curl -s "http://localhost:3200/api/search?limit=5" | jq '.traces | length'

# Get sample trace
curl -s "http://localhost:3200/api/search?limit=1" | jq '.traces[0]'
```

**Expected:** Tempo returns trace data

### Step 2: Test in Grafana Explore
1. Navigate to: `http://localhost:3000/explore`
2. Select datasource: **Tempo**
3. Switch to **TraceQL** mode
4. Enter query: `{ resource.service.name = "flask-backend" }`
5. Click **Run query**

**Expected:** Traces display in table format

**If this works:** Problem is with dashboard panel configuration
**If this fails:** Problem is with Tempo connectivity or data

### Step 3: Compare Explore vs Dashboard
- Explore uses `table` visualization for TraceQL results
- Dashboard `traces` panel type had compatibility issues
- Solution: Match dashboard to Explore's approach

### Step 4: Use Query Inspector
1. Click panel title → **Inspect** → **Query**
2. Click **Refresh** button
3. Check tabs:
   - **Request:** Shows actual query sent to Tempo
   - **Response:** Shows data returned (or empty)
   - **Error:** Shows any errors

### Step 5: Check Browser Console
- Open browser developer tools (F12)
- Look for JavaScript errors
- Common error: `Cannot read properties of undefined`
- Cause: Missing required panel fields

---

## TraceQL Query Examples

### Basic Queries

```traceql
# All traces from flask-backend
{ resource.service.name = "flask-backend" }

# All traces with HTTP spans
{ span.http.method != "" }

# Specific endpoint
{ span.http.target = "/api/tasks" }
```

### Filtered Queries

```traceql
# Slow requests (> 100ms)
{ resource.service.name = "flask-backend" && duration > 100ms }

# POST requests only
{ span.http.method = "POST" }

# Database operations
{ span.db.system != "" }

# Errors only
{ status = error }
```

### Important Notes

- ✅ Use `resource.` prefix for resource attributes (service.name, service.version, etc.)
- ✅ Use `span.` prefix for span attributes (http.method, db.system, etc.)
- ❌ Do NOT use pipeline operators like `| limit 50` in Tempo 2.3.1
- ❌ Do NOT use bare attribute names like `service.name`

---

## Troubleshooting Common Issues

### Issue: "No data found in response"

**Possible causes:**

1. **Time range too narrow**
   - Solution: Widen to "Last 6 hours"
   - Note: Tempo retention is 1h by default

2. **No traces in time range**
   - Test: `curl "http://localhost:3200/api/search?limit=1"`
   - Solution: Generate traffic, then check again

3. **TraceQL query doesn't match**
   - Test in Explore first
   - Verify service name matches exactly

4. **Grafana not querying Tempo**
   - Check Query Inspector
   - Verify datasource UID is correct

### Issue: JavaScript errors in browser

**Error:** `Cannot read properties of undefined (reading 'filter')`

**Causes:**
- Missing required panel fields (`fieldConfig`, `transformations`)
- Experimental query types (`traceqlSearch`, `nativeSearch`)
- Wrong panel type with incompatible options

**Solution:** Use the exact working configuration above

### Issue: Tempo container not running

**Symptoms:**
- `docker compose -p lab ps tempo` shows nothing
- Validation script reports "Tempo NOT running"

**Debug steps:**
```bash
# Check for stale containers
docker ps -a --filter "name=tempo"

# Check logs from stopped container
docker logs tempo

# Remove stale container
docker rm tempo

# Restart
docker compose -p lab up -d tempo
```

### Issue: TraceQL parse errors

**Error:** `parse error at line 1, col X: syntax error`

**Common causes:**
- Using `service.name` instead of `resource.service.name`
- Using pipeline operators (`| limit`, `| select`, etc.)
- Incorrect quote escaping

**Solution:** Use simple selector syntax only

### Issue: Service Dependency Map breaks

**Cause:** Service Map uses Tempo's `metrics_generator`

**Check:**
```bash
docker compose -p lab logs tempo | grep -i metrics
```

**Verify:**
- `metrics_generator` section in `tempo.yml`
- Prometheus is scraping Tempo metrics
- `overrides.metrics_generator_processors` includes `service-graphs`

---

## Validation Checklist

After applying fixes:

- [ ] Tempo container running: `docker compose -p lab ps tempo`
- [ ] Tempo API returns traces: `curl http://localhost:3200/api/search?limit=1`
- [ ] Tempo logs show "Tempo started": `docker compose -p lab logs tempo | grep started`
- [ ] Grafana running: `docker compose -p lab ps grafana`
- [ ] Grafana Explore shows traces with TraceQL query
- [ ] Dashboard "Trace Search" panel displays traces in table format
- [ ] Service Dependency Map still works
- [ ] Application Logs still work
- [ ] No JavaScript errors in browser console (F12)
- [ ] Clicking trace IDs shows detailed trace view

---

## Key Technical Learnings

### Tempo 2.3.1 Configuration
- Search is **always enabled** by default - no configuration needed
- `query_frontend.search` section controls search behavior
- Local storage backend supports search out of the box
- `metrics_generator` is separate from search (used for Service Map)

### TraceQL in Tempo 2.3.1
- Supports basic selector syntax: `{ attribute = "value" }`
- Supports AND/OR: `{ attr1 = "val1" && attr2 = "val2" }`
- Supports duration filters: `{ duration > 100ms }`
- **Does NOT support** pipeline operators (`|`)
- **Does NOT support** advanced features from later versions

### Grafana 10.2.3 + Tempo Integration
- `table` panel type is most reliable for TraceQL results
- `traces` panel type requires specific configuration that varies by version
- Explore uses table visualization - dashboard should match
- `queryType: "traceql"` is the stable option
- Datasource UID must match in both datasource config and panel

### OTLP Protocol Support
- Tempo can receive traces via gRPC (4317) or HTTP (4318)
- Both protocols should be configured for maximum compatibility
- OTel Collector can send via either protocol
- HTTP is more firewall-friendly, gRPC is more efficient

---

## File Modifications Summary

### Files Changed

| File | Change | Purpose |
|------|--------|---------|
| `otel-collector/tempo.yml` | Added HTTP protocol endpoint | Support both gRPC and HTTP OTLP |
| `grafana/dashboards/end-to-end-tracing.json` | Changed panel type to `table` | Fix compatibility issues |
| `grafana/dashboards/end-to-end-tracing.json` | Fixed TraceQL query syntax | Correct resource attribute reference |
| `grafana/dashboards/end-to-end-tracing.json` | Removed broken service variable | Eliminate confusion |

### Files NOT Changed (Already Correct)

| File | Why It Was Fine |
|------|----------------|
| `grafana/provisioning/datasources/datasources.yml` | Datasource UID was already `tempo` |
| `docker-compose.yml` | Tempo service definition was correct |
| `otel-collector/otel-collector-config.yml` | OTLP exporter configuration was fine |

---

## Future Enhancements

### 1. Add Service Dropdown Variable

**From Prometheus span-metrics:**
```json
{
  "name": "service",
  "type": "query",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "query": "label_values(tempo_spanmetrics_calls_total, service)",
  "refresh": 2,
  "current": {"text": "flask-backend", "value": "flask-backend"}
}
```

**Custom list:**
```json
{
  "name": "service",
  "type": "custom",
  "query": "flask-backend,frontend,otel-collector",
  "current": {"text": "flask-backend", "value": "flask-backend"}
}
```

Then update query to: `{ resource.service.name = "$service" }`

### 2. Add Additional Filter Panels

Create separate panels for common queries:
- Slow requests (duration > threshold)
- Error traces (status = error)
- Specific endpoints
- Database operations

### 3. Add Trace ID Data Links

Make trace IDs clickable to jump to detailed view:
```json
"fieldConfig": {
  "defaults": {
    "links": [{
      "title": "View Trace",
      "url": "/explore?datasource=tempo&query=${__value.raw}"
    }]
  }
}
```

---

## References

- [Tempo 2.3.x Documentation](https://grafana.com/docs/tempo/v2.3/)
- [Tempo Configuration Reference](https://grafana.com/docs/tempo/v2.3/configuration/)
- [TraceQL Query Language](https://grafana.com/docs/tempo/latest/traceql/)
- [Grafana Table Panel](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/table/)
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)

---

## Conclusion

**Root cause:** Panel type incompatibility between Grafana 10.2.3 and Tempo 2.3.1

**Solution:** Use `table` panel type with correct TraceQL syntax

**Result:** Fully functional Trace Search displaying:
- Trace IDs
- Timestamps
- Service names
- Span names
- Durations

**Status:** ✅ WORKING

---

**Document Version:** 1.0
**Last Updated:** 2025-10-20
**Verified On:** Grafana 10.2.3 + Tempo 2.3.1
**Related Files:** See docs/phase-1-docker-compose/VERIFICATION-GUIDE.md for post-deployment validation and CI/CD testing
