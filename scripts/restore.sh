#!/usr/bin/env bash
# scripts/restore.sh — Restore Docker volumes from a backup snapshot.
# Usage: ./scripts/restore.sh [TIMESTAMP]
#   If TIMESTAMP is omitted, restores from the latest backup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/log.sh
source "$PROJECT_ROOT/lib/log.sh"

# Load .env for COMPOSE_PROJECT_NAME
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck source=../.env
    source "$PROJECT_ROOT/.env"
fi

PROJECT="${COMPOSE_PROJECT_NAME:-lab}"
BACKUP_BASE="$PROJECT_ROOT/backups"

# Determine which backup to restore
if [[ -n "${1:-}" ]]; then
    SNAP="$1"
else
    # Find latest backup directory
    SNAP=$(find "$BACKUP_BASE" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r | head -1)
fi

if [[ -z "$SNAP" ]] || [[ ! -d "$BACKUP_BASE/$SNAP" ]]; then
    log_error "No backup found. Provide a timestamp or ensure backups/ has snapshots."
    exit 1
fi

BACKUP_DIR="$BACKUP_BASE/$SNAP"
MANIFEST="$BACKUP_DIR/manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
    log_error "Manifest not found at $MANIFEST"
    exit 1
fi

log_section "Volume Restore — $SNAP"

# Stop services
log_info "Stopping services..."
(cd "$PROJECT_ROOT" && docker compose -p "$PROJECT" stop)

# Restore each volume listed in the manifest
# Parse volume names from manifest (simple grep approach, no jq dependency)
while IFS=: read -r vol_name tarball; do
    # Clean up JSON formatting
    vol_name=$(echo "$vol_name" | tr -d ' "')
    tarball=$(echo "$tarball" | tr -d ' "' | tr -d ',')

    [[ -z "$vol_name" || -z "$tarball" ]] && continue

    full_vol="${PROJECT}_${vol_name}"
    tarpath="$BACKUP_DIR/$tarball"

    if [[ ! -f "$tarpath" ]]; then
        log_warn "Tarball not found: $tarpath — skipping $vol_name"
        continue
    fi

    log_info "Restoring volume: $full_vol from $tarball"

    # Recreate volume if it doesn't exist
    docker volume create "$full_vol" >/dev/null 2>&1 || true

    # Clear volume and restore
    docker run --rm \
        -v "$full_vol":/data \
        -v "$BACKUP_DIR":/backup:ro \
        alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/$tarball -C /data"

    log_success "  Restored $vol_name"
done < <(grep -E '^\s+"[a-z]' "$MANIFEST" | grep -v '"timestamp"\|"project"\|"volumes"')

# Restart services
log_info "Restarting services..."
(cd "$PROJECT_ROOT" && docker compose -p "$PROJECT" start)

log_success "Restore complete from snapshot: $SNAP"
log_info "Run 'make health' to validate."
