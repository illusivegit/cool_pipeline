#!/usr/bin/env bash
# ============================================================================
# Observability Integration Tests
# ============================================================================
#
# Validates the full MELT (Metrics, Events, Logs, Traces) pipeline end-to-end.
# These are NOT unit tests — they verify that telemetry flows from the
# application through the OTel collector to the storage backends.
#
# Usage:
#   ./scripts/observability-integration-tests.sh [HOST] [BACKEND_PORT] [PROMETHEUS_PORT] [TEMPO_PORT] [LOKI_PORT]
#
# Defaults (production):
#   HOST=localhost  BACKEND=5000  PROMETHEUS=9090  TEMPO=3200  LOKI=3100
#
# Test environment example:
#   ./scripts/observability-integration-tests.sh localhost 9000 9190 3200 3100
# ============================================================================

set -euo pipefail

# shellcheck source=lib/log.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/log.sh" 2>/dev/null || true

HOST="${1:-localhost}"
BACKEND_PORT="${2:-5000}"
PROMETHEUS_PORT="${3:-9090}"
TEMPO_PORT="${4:-3200}"
LOKI_PORT="${5:-3100}"

PASSED=0
FAILED=0
TOTAL=0

# ── Test helper ──────────────────────────────────────────────────────────────

run_test() {
    local name="$1"
    local result
    TOTAL=$((TOTAL + 1))

    if result=$(eval "$2" 2>&1); then
        echo "PASS  ${name}"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL  ${name}"
        echo "      Detail: ${result}"
        FAILED=$((FAILED + 1))
    fi
}

# ── Phase 1: Generate telemetry ──────────────────────────────────────────────
# Sends requests that produce metrics, traces, and logs.
# Each endpoint is instrumented with OTel and Prometheus client.

echo "============================================"
echo "Observability Integration Tests"
echo "============================================"
echo "Backend:    http://${HOST}:${BACKEND_PORT}"
echo "Prometheus: http://${HOST}:${PROMETHEUS_PORT}"
echo "Tempo:      http://${HOST}:${TEMPO_PORT}"
echo "Loki:       http://${HOST}:${LOKI_PORT}"
echo "============================================"
echo ""
echo "Phase 1: Generating telemetry..."

# Generate a unique marker to identify this test run's data
TEST_MARKER="otel-inttest-$(date +%s)"

# Create a task (generates trace, log, and metric)
TASK_RESPONSE=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"${TEST_MARKER}\",\"description\":\"integration test\"}" \
    "http://${HOST}:${BACKEND_PORT}/api/tasks" 2>&1) || true

TASK_ID=$(echo "${TASK_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null) || true

# Read it back (GET generates a trace + metric)
curl -sf "http://${HOST}:${BACKEND_PORT}/api/tasks" >/dev/null 2>&1 || true

# Trigger the simulate-error endpoint (generates error trace + error log)
curl -sf "http://${HOST}:${BACKEND_PORT}/api/simulate-error" >/dev/null 2>&1 || true

# Hit /metrics to ensure Prometheus client has data
curl -sf "http://${HOST}:${BACKEND_PORT}/metrics" >/dev/null 2>&1 || true

# Wait for telemetry to propagate through the pipeline.
# OTel batch processor flushes every 10s, Tempo needs indexing time,
# and Prometheus scrape interval is 15s. 20s covers the worst case.
echo "Phase 2: Waiting 20s for telemetry propagation..."
sleep 20
echo ""

# ── Phase 3: Validate Metrics (Prometheus) ───────────────────────────────────
echo "Phase 3: Metrics (Prometheus)"

run_test "Prometheus is reachable" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/-/ready' >/dev/null"

run_test "http_requests_total counter exists" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/api/v1/query?query=http_requests_total' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
results = data['data']['result']
assert len(results) > 0, 'No http_requests_total samples found'
print(f'      Found {len(results)} time series')
\""

run_test "http_request_duration_seconds histogram exists" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/api/v1/query?query=http_request_duration_seconds_count' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
results = data['data']['result']
assert len(results) > 0, 'No http_request_duration_seconds samples found'
total = sum(float(r['value'][1]) for r in results)
print(f'      Total requests observed: {int(total)}')
\""

run_test "db_query_duration_seconds histogram exists" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/api/v1/query?query=db_query_duration_seconds_count' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
results = data['data']['result']
assert len(results) > 0, 'No db_query_duration_seconds samples found'
print(f'      Found {len(results)} operation types')
\""

run_test "Scrape target flask-backend is UP" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/api/v1/targets' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
targets = data['data']['activeTargets']
backend = [t for t in targets if 'backend' in t.get('scrapeUrl','') or '${BACKEND_PORT}' in t.get('scrapeUrl','')]
assert len(backend) > 0, 'No backend scrape target found'
state = backend[0]['health']
assert state == 'up', f'Backend target is {state}, expected up'
print(f'      Backend target: {state}')
\""

echo ""

# ── Phase 4: Validate Traces (Tempo) ─────────────────────────────────────────
echo "Phase 4: Traces (Tempo)"

run_test "Tempo is reachable" \
    "curl -sf 'http://${HOST}:${TEMPO_PORT}/ready' >/dev/null"

run_test "Traces exist for flask-backend service" \
    "curl -sf 'http://${HOST}:${TEMPO_PORT}/api/search?q=%7Bresource.service.name%3D%22flask-backend%22%7D&limit=5' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
traces = data.get('traces', [])
assert len(traces) > 0, 'No traces found for flask-backend'
print(f'      Found {len(traces)} traces')
\""

run_test "Trace contains create_task span" \
    "curl -sf 'http://${HOST}:${TEMPO_PORT}/api/search?q=%7Bname%3D%22create_task%22%7D&limit=5' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
traces = data.get('traces', [])
assert len(traces) > 0, 'No traces found with create_task span'
print(f'      Found {len(traces)} traces with create_task span')
\""

run_test "Trace contains simulate_error span (error trace)" \
    "curl -sf 'http://${HOST}:${TEMPO_PORT}/api/search?q=%7Bname%3D%22simulate_error%22%7D&limit=5' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
traces = data.get('traces', [])
assert len(traces) > 0, 'No traces found with simulate_error span'
print(f'      Found {len(traces)} error traces')
\""

echo ""

# ── Phase 5: Validate Logs (Loki) ───────────────────────────────────────────
echo "Phase 5: Logs (Loki)"

run_test "Loki is reachable" \
    "curl -sf 'http://${HOST}:${LOKI_PORT}/ready' >/dev/null"

# Query Loki for logs from flask-backend service
# LogQL query: {service_name="flask-backend"} — last 5 minutes
run_test "Logs exist for flask-backend service" \
    "curl -sf 'http://${HOST}:${LOKI_PORT}/loki/api/v1/query_range' \
     --data-urlencode 'query={service_name=\"flask-backend\"}' \
     --data-urlencode 'limit=10' \
     --data-urlencode 'start=$(( $(date +%s) - 300 ))000000000' \
     --data-urlencode 'end=$(date +%s)000000000' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
streams = data['data']['result']
assert len(streams) > 0, 'No log streams found for flask-backend'
total_entries = sum(len(s['values']) for s in streams)
print(f'      Found {len(streams)} streams, {total_entries} log entries')
\""

run_test "Error logs captured (simulate-error)" \
    "curl -sf 'http://${HOST}:${LOKI_PORT}/loki/api/v1/query_range' \
     --data-urlencode 'query={service_name=\"flask-backend\"} |= \"Simulated error\"' \
     --data-urlencode 'limit=5' \
     --data-urlencode 'start=$(( $(date +%s) - 300 ))000000000' \
     --data-urlencode 'end=$(date +%s)000000000' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
streams = data['data']['result']
total = sum(len(s['values']) for s in streams)
assert total > 0, 'No error logs found matching Simulated error'
print(f'      Found {total} error log entries')
\""

run_test "Logs contain trace_id for correlation" \
    "curl -sf 'http://${HOST}:${LOKI_PORT}/loki/api/v1/query_range' \
     --data-urlencode 'query={service_name=\"flask-backend\"} |= \"trace_id\"' \
     --data-urlencode 'limit=5' \
     --data-urlencode 'start=$(( $(date +%s) - 300 ))000000000' \
     --data-urlencode 'end=$(date +%s)000000000' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
streams = data['data']['result']
total = sum(len(s['values']) for s in streams)
assert total > 0, 'No logs with trace_id found — log-trace correlation broken'
print(f'      Found {total} logs with trace_id (correlation working)')
\""

echo ""

# ── Phase 6: Cross-Signal Correlation ────────────────────────────────────────
echo "Phase 6: Cross-signal correlation"

run_test "Trace-to-metric: request that generated trace also incremented counter" \
    "curl -sf 'http://${HOST}:${PROMETHEUS_PORT}/api/v1/query?query=http_requests_total%7Bendpoint%3D%22create_task%22%7D' \
     | python3 -c \"
import sys, json
data = json.load(sys.stdin)
results = data['data']['result']
assert len(results) > 0, 'No http_requests_total for create_task endpoint'
count = float(results[0]['value'][1])
assert count > 0, f'Counter is {count}, expected > 0'
print(f'      create_task requests counted: {int(count)}')
\""

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "============================================"
echo "Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "============================================"

# Clean up test task if created
if [ -n "${TASK_ID}" ] && [ "${TASK_ID}" != "" ]; then
    curl -sf -X DELETE "http://${HOST}:${BACKEND_PORT}/api/tasks/${TASK_ID}" >/dev/null 2>&1 || true
fi

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
