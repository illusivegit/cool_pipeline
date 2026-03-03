#!/usr/bin/env bash
# lib/checks.sh — Reusable check functions for health/state scripts.
# Source guard: safe to source multiple times.
[[ -n "${_LIB_CHECKS_LOADED:-}" ]] && return
readonly _LIB_CHECKS_LOADED=1

# Counters (global to the sourcing script)
CHECKS_PASS=0
CHECKS_FAIL=0
CHECKS_WARN=0

# check_endpoint URL LABEL
#   Curl the URL, return 0 on HTTP 2xx, 1 otherwise.
check_endpoint() {
    local url="$1" label="$2"
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null) || http_code=000
    if [[ "$http_code" =~ ^2 ]]; then
        log_success "PASS  $label ($url) -> HTTP $http_code"
        CHECKS_PASS=$(( CHECKS_PASS + 1 ))
        return 0
    else
        log_error "FAIL  $label ($url) -> HTTP $http_code"
        CHECKS_FAIL=$(( CHECKS_FAIL + 1 ))
        return 0
    fi
}

# check_container_running CONTAINER_NAME
#   Return 0 if the container is running. Failures are recorded but don't abort.
check_container_running() {
    local name="$1"
    local state
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null) || state="not_found"
    if [[ "$state" == "running" ]]; then
        log_success "PASS  Container '$name' is running"
        CHECKS_PASS=$(( CHECKS_PASS + 1 ))
        return 0
    else
        log_error "FAIL  Container '$name' state=$state"
        CHECKS_FAIL=$(( CHECKS_FAIL + 1 ))
        return 0
    fi
}

# check_container_healthy CONTAINER_NAME
#   Return 0 if the container health status is "healthy".
check_container_healthy() {
    local name="$1"
    local health
    health=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null) || health="none"
    if [[ "$health" == "healthy" ]]; then
        log_success "PASS  Container '$name' is healthy"
        CHECKS_PASS=$(( CHECKS_PASS + 1 ))
        return 0
    else
        log_warn "WARN  Container '$name' health=$health"
        CHECKS_WARN=$(( CHECKS_WARN + 1 ))
        return 0
    fi
}

# check_version CONTAINER_NAME COMMAND EXPECTED_SUBSTRING
#   Run COMMAND in container, check output contains EXPECTED_SUBSTRING.
check_version() {
    local container="$1" cmd="$2" expected="$3"
    local actual
    actual=$(docker exec "$container" sh -c "$cmd" 2>/dev/null) || actual="(exec failed)"
    if echo "$actual" | grep -q "$expected"; then
        log_success "PASS  $container version matches ($expected)"
        CHECKS_PASS=$(( CHECKS_PASS + 1 ))
        return 0
    else
        log_warn "WARN  $container version mismatch: expected='$expected' actual='$actual'"
        CHECKS_WARN=$(( CHECKS_WARN + 1 ))
        return 0
    fi
}

# print_summary
#   Print pass/fail/warn totals. Return 1 if any failures.
print_summary() {
    echo ""
    log_section "Results: $CHECKS_PASS passed, $CHECKS_FAIL failed, $CHECKS_WARN warnings"
    [[ "$CHECKS_FAIL" -eq 0 ]]
}
