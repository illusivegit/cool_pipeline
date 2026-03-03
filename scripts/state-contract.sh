#!/usr/bin/env bash
# scripts/state-contract.sh — Generate a machine-readable post-deploy state artifact.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"
# shellcheck source=../lib/checks.sh
source "$PROJECT_ROOT/lib/checks.sh"

TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')
ARTIFACT_DIR="$PROJECT_ROOT/artifacts/state/$TIMESTAMP"
mkdir -p "$ARTIFACT_DIR"

log_section "State Contract — $TIMESTAMP"

SERVICES=(
    "flask-backend"
    "frontend"
    "otel-collector"
    "prometheus"
    "tempo"
    "loki"
    "grafana"
    "alertmanager"
    "node-exporter"
    "promtail"
)

# ── Collect container state ─────────────────────────────────────────────────
json_file="$ARTIFACT_DIR/state.json"
kv_file="$ARTIFACT_DIR/state.kv"

echo "{" > "$json_file"
: > "$kv_file"

first=true
for svc in "${SERVICES[@]}"; do
    status=$(docker inspect -f '{{.State.Status}}' "$svc" 2>/dev/null) || status="not_found"
    health=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null) || health="none"
    image=$(docker inspect -f '{{.Config.Image}}' "$svc" 2>/dev/null) || image="unknown"
    restarts=$(docker inspect -f '{{.RestartCount}}' "$svc" 2>/dev/null) || restarts="-1"
    started=$(docker inspect -f '{{.State.StartedAt}}' "$svc" 2>/dev/null) || started="unknown"

    # KV format
    {
        echo "${svc}_status=$status"
        echo "${svc}_health=$health"
        echo "${svc}_image=$image"
        echo "${svc}_restarts=$restarts"
    } >> "$kv_file"

    # JSON format
    if [[ "$first" == "true" ]]; then first=false; else echo "," >> "$json_file"; fi
    cat >> "$json_file" <<ENTRY
  "$svc": {
    "status": "$status",
    "health": "$health",
    "image": "$image",
    "restarts": $restarts,
    "started_at": "$started"
  }
ENTRY
done

echo "}" >> "$json_file"

# ── Endpoint checks ─────────────────────────────────────────────────────────
log_section "Endpoint Health Checks"

HOST="${LAB_HOST:-localhost}"

check_endpoint "http://$HOST:${FRONTEND_PORT:-8080}/"              "Frontend"
check_endpoint "http://$HOST:${BACKEND_PORT:-5000}/health"         "Backend /health"
check_endpoint "http://$HOST:${GRAFANA_PORT:-3000}/api/health"     "Grafana"
check_endpoint "http://$HOST:${PROMETHEUS_PORT:-9090}/-/healthy"   "Prometheus"
check_endpoint "http://$HOST:${TEMPO_PORT:-3200}/ready"            "Tempo"
check_endpoint "http://$HOST:${LOKI_PORT:-3100}/ready"             "Loki"
check_endpoint "http://$HOST:${ALERTMANAGER_PORT:-9093}/-/healthy" "Alertmanager"
check_endpoint "http://$HOST:13133"                                "OTel Collector"
check_endpoint "http://$HOST:${NODE_EXPORTER_PORT:-9100}/metrics"  "Node Exporter"

# Record endpoint results in KV
{
    echo "endpoint_frontend=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${FRONTEND_PORT:-8080}/" 2>/dev/null || echo 000 )"
    echo "endpoint_backend=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${BACKEND_PORT:-5000}/health" 2>/dev/null || echo 000 )"
    echo "endpoint_grafana=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${GRAFANA_PORT:-3000}/api/health" 2>/dev/null || echo 000 )"
    echo "endpoint_prometheus=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${PROMETHEUS_PORT:-9090}/-/healthy" 2>/dev/null || echo 000 )"
    echo "endpoint_tempo=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${TEMPO_PORT:-3200}/ready" 2>/dev/null || echo 000 )"
    echo "endpoint_loki=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${LOKI_PORT:-3100}/ready" 2>/dev/null || echo 000 )"
    echo "endpoint_alertmanager=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${ALERTMANAGER_PORT:-9093}/-/healthy" 2>/dev/null || echo 000 )"
    echo "endpoint_otel_collector=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:13133" 2>/dev/null || echo 000 )"
    echo "endpoint_node_exporter=$( curl -s -o /dev/null -w '%{http_code}' "http://$HOST:${NODE_EXPORTER_PORT:-9100}/metrics" 2>/dev/null || echo 000 )"
    echo "timestamp=$TIMESTAMP"
} >> "$kv_file"

log_info "Artifacts written to: $ARTIFACT_DIR/"
log_info "  state.json  — machine-readable container state"
log_info "  state.kv    — flat key=value for diffing"

print_summary
