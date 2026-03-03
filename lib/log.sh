#!/usr/bin/env bash
# lib/log.sh — Structured logging with ANSI colours and timestamps.
# Source guard: safe to source multiple times.
[[ -n "${_LIB_LOG_LOADED:-}" ]] && return
readonly _LIB_LOG_LOADED=1

# Colours (disabled when stdout is not a terminal)
if [[ -t 1 ]]; then
    readonly _C_RESET='\033[0m'
    readonly _C_RED='\033[0;31m'
    readonly _C_GREEN='\033[0;32m'
    readonly _C_YELLOW='\033[0;33m'
    readonly _C_BLUE='\033[0;34m'
    readonly _C_CYAN='\033[0;36m'
else
    readonly _C_RESET='' _C_RED='' _C_GREEN='' _C_YELLOW='' _C_BLUE='' _C_CYAN=''
fi

_log() {
    local level="$1" colour="$2" message="$3"
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%b[%s] [%-5s] %s%b\n' "$colour" "$ts" "$level" "$message" "$_C_RESET" >&2
}

log_info()    { _log "INFO"  "$_C_BLUE"   "$*"; }
log_warn()    { _log "WARN"  "$_C_YELLOW" "$*"; }
log_error()   { _log "ERROR" "$_C_RED"    "$*"; }
log_success() { _log "OK"    "$_C_GREEN"  "$*"; }
log_debug()   { _log "DEBUG" "$_C_CYAN"   "$*"; }

# Section header for visual separation
log_section() {
    printf '%b══════════════════════════════════════════════════════════════%b\n' "$_C_BLUE" "$_C_RESET" >&2
    log_info "$*"
    printf '%b══════════════════════════════════════════════════════════════%b\n' "$_C_BLUE" "$_C_RESET" >&2
}
