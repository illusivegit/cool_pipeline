#!/usr/bin/env bash
# scripts/backup.sh — Snapshot all Docker volumes to compressed tarballs.
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
TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')
BACKUP_DIR="$PROJECT_ROOT/backups/$TIMESTAMP"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

log_section "Volume Backup — $TIMESTAMP"

# Discover named volumes for this project
VOLUMES=$(docker volume ls --filter "name=${PROJECT}_" -q 2>/dev/null || true)

if [[ -z "$VOLUMES" ]]; then
    log_warn "No volumes found for project '$PROJECT'. Nothing to back up."
    exit 0
fi

# Stop services for consistent backup
log_info "Stopping services for consistent snapshot..."
(cd "$PROJECT_ROOT" && docker compose -p "$PROJECT" stop)

# Back up each volume
manifest="$BACKUP_DIR/manifest.json"
{
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"project\": \"$PROJECT\","
    echo "  \"volumes\": {"
} > "$manifest"

first=true
for vol in $VOLUMES; do
    short_name="${vol#"${PROJECT}"_}"
    tarball="${short_name}.tar.gz"

    log_info "Backing up volume: $vol -> $tarball"
    docker run --rm \
        -v "$vol":/data:ro \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf "/backup/$tarball" -C /data .

    size=$(du -sh "$BACKUP_DIR/$tarball" | cut -f1)
    log_success "  $tarball ($size)"

    if [[ "$first" == "true" ]]; then first=false; else echo "," >> "$manifest"; fi
    echo "    \"$short_name\": \"$tarball\"" >> "$manifest"
done

echo "  }" >> "$manifest"
echo "}" >> "$manifest"

# Restart services
log_info "Restarting services..."
(cd "$PROJECT_ROOT" && docker compose -p "$PROJECT" start)

# Retention: remove backups older than RETENTION_DAYS
log_info "Enforcing ${RETENTION_DAYS}-day retention..."
find "$PROJECT_ROOT/backups" -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

log_success "Backup complete: $BACKUP_DIR"
log_info "Manifest: $manifest"
