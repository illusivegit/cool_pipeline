#!/usr/bin/env bash
# scripts/validate-versions.sh — Compare running container image tags against .env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"
# shellcheck source=../lib/checks.sh
source "$PROJECT_ROOT/lib/checks.sh"

log_section "Version Validation"

# Load expected versions from .env
if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
    log_error ".env file not found at $PROJECT_ROOT/.env"
    exit 1
fi
# shellcheck source=../.env
source "$PROJECT_ROOT/.env"

# Map: container_name  expected_image  version_command
declare -A EXPECTED=(
    ["otel-collector"]="${OTEL_COLLECTOR_IMAGE}"
    ["prometheus"]="${PROMETHEUS_IMAGE}"
    ["tempo"]="${TEMPO_IMAGE}"
    ["loki"]="${LOKI_IMAGE}"
    ["grafana"]="${GRAFANA_IMAGE}"
    ["alertmanager"]="${ALERTMANAGER_IMAGE}"
    ["node-exporter"]="${NODE_EXPORTER_IMAGE}"
    ["promtail"]="${PROMTAIL_IMAGE}"
    ["frontend"]="${NGINX_IMAGE}"
)

for container in "${!EXPECTED[@]}"; do
    expected_image="${EXPECTED[$container]}"

    # Get actual image from running container
    actual_image=$(docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null) || actual_image="(not running)"

    if [[ "$actual_image" == "$expected_image" ]]; then
        log_success "PASS  $container: $actual_image"
        CHECKS_PASS=$(( CHECKS_PASS + 1 ))
    elif [[ "$actual_image" == "(not running)" ]]; then
        log_error "FAIL  $container: container not running (expected $expected_image)"
        CHECKS_FAIL=$(( CHECKS_FAIL + 1 ))
    else
        log_warn "WARN  $container: running=$actual_image expected=$expected_image"
        CHECKS_WARN=$(( CHECKS_WARN + 1 ))
    fi
done

# Special case: backend is a build image, check Python version instead
check_version "flask-backend" "python --version" "3.11"

print_summary
