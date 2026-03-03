#!/usr/bin/env bash
# scripts/health-checks.sh — Comprehensive health validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"
# shellcheck source=../lib/checks.sh
source "$PROJECT_ROOT/lib/checks.sh"

# Load .env for port defaults
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck source=../.env
    source "$PROJECT_ROOT/.env"
fi

HOST="${LAB_HOST:-localhost}"

# ── Docker-level checks ────────────────────────────────────────────────────
log_section "Docker Container Status"

CONTAINERS=(
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

for c in "${CONTAINERS[@]}"; do
    check_container_running "$c"
done

# Backend has a healthcheck
check_container_healthy "flask-backend"

# ── Endpoint-level checks ──────────────────────────────────────────────────
log_section "Endpoint Health"

check_endpoint "http://$HOST:${FRONTEND_PORT:-8080}/"              "Frontend (Nginx)"
check_endpoint "http://$HOST:${BACKEND_PORT:-5000}/health"         "Backend /health"
check_endpoint "http://$HOST:${BACKEND_PORT:-5000}/metrics"        "Backend /metrics"
check_endpoint "http://$HOST:${GRAFANA_PORT:-3000}/api/health"     "Grafana"
check_endpoint "http://$HOST:${PROMETHEUS_PORT:-9090}/-/healthy"   "Prometheus /-/healthy"
check_endpoint "http://$HOST:${PROMETHEUS_PORT:-9090}/-/ready"     "Prometheus /-/ready"
check_endpoint "http://$HOST:${TEMPO_PORT:-3200}/ready"            "Tempo"
check_endpoint "http://$HOST:${LOKI_PORT:-3100}/ready"             "Loki"
check_endpoint "http://$HOST:${ALERTMANAGER_PORT:-9093}/-/healthy" "Alertmanager"
check_endpoint "http://$HOST:13133"                                "OTel Collector health"
check_endpoint "http://$HOST:${NODE_EXPORTER_PORT:-9100}/metrics"  "Node Exporter"

# ── Pipeline-level checks ──────────────────────────────────────────────────
log_section "Pipeline Validation"

# Check Prometheus has scrape targets
targets_up=$(curl -sf "http://$HOST:${PROMETHEUS_PORT:-9090}/api/v1/targets" 2>/dev/null | grep -c '"health":"up"' || echo 0)
if [[ "$targets_up" -gt 0 ]]; then
    log_success "PASS  Prometheus has $targets_up active scrape targets"
    CHECKS_PASS=$(( CHECKS_PASS + 1 ))
else
    log_error "FAIL  Prometheus has no active scrape targets"
    CHECKS_FAIL=$(( CHECKS_FAIL + 1 ))
fi

# Check Prometheus alert rules are loaded
rules_count=$(curl -sf "http://$HOST:${PROMETHEUS_PORT:-9090}/api/v1/rules" 2>/dev/null | grep -c '"type":"alerting"' || echo 0)
if [[ "$rules_count" -gt 0 ]]; then
    log_success "PASS  Prometheus has $rules_count alert rule groups loaded"
    CHECKS_PASS=$(( CHECKS_PASS + 1 ))
else
    log_warn "WARN  No alert rules detected in Prometheus"
    CHECKS_WARN=$(( CHECKS_WARN + 1 ))
fi

# Check recording rules
rec_count=$(curl -sf "http://$HOST:${PROMETHEUS_PORT:-9090}/api/v1/rules" 2>/dev/null | grep -c '"type":"recording"' || echo 0)
if [[ "$rec_count" -gt 0 ]]; then
    log_success "PASS  Prometheus has $rec_count recording rule groups loaded"
    CHECKS_PASS=$(( CHECKS_PASS + 1 ))
else
    log_warn "WARN  No recording rules detected in Prometheus"
    CHECKS_WARN=$(( CHECKS_WARN + 1 ))
fi

# Check Loki is accepting logs (query readiness)
loki_ready=$(curl -sf "http://$HOST:${LOKI_PORT:-3100}/ready" 2>/dev/null) || loki_ready=""
if [[ "$loki_ready" == "ready" ]]; then
    log_success "PASS  Loki reports ready"
    CHECKS_PASS=$(( CHECKS_PASS + 1 ))
else
    log_warn "WARN  Loki readiness: '$loki_ready'"
    CHECKS_WARN=$(( CHECKS_WARN + 1 ))
fi

# ── Version checks ──────────────────────────────────────────────────────────
log_section "Version Checks"

check_version "flask-backend" "python --version" "3.11"
check_version "prometheus"    "prometheus --version 2>&1 | head -1" "2.48"
check_version "grafana"       "grafana-server -v 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1" "10.2"

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary
