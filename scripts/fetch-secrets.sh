#!/usr/bin/env bash
# fetch-secrets.sh — Pull secrets from one or more Vault KV v2 paths
#
# Authentication: AppRole (role_id + secret_id → short-lived token)
# Transport:      curl + jq (no vault CLI dependency)
#
# Usage:
#   VAULT_ADDR=http://vault:8200 \
#   VAULT_ROLE_ID=xxx VAULT_SECRET_ID=yyy \
#     bash scripts/fetch-secrets.sh [-o output] path [path ...]
#
# Examples:
#   # Single path (default output: .env.secrets)
#   bash scripts/fetch-secrets.sh secret/data/lab/alertmanager
#
#   # Multiple paths merged into one file
#   bash scripts/fetch-secrets.sh -o .env.secrets \
#       secret/data/lab/alertmanager \
#       secret/data/lab/sonarqube \
#       secret/data/lab/registry
#
# All KV paths are fetched, merged, and written as KEY=value lines.
# Duplicate keys across paths: last path wins (intentional — allows overrides).
set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────
OUTPUT_FILE=".env.secrets"
PATHS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: fetch-secrets.sh [-o output] path [path ...]" >&2
            exit 1
            ;;
        *)
            PATHS+=("$1")
            shift
            ;;
    esac
done

if [ ${#PATHS[@]} -eq 0 ]; then
    echo "ERROR: At least one Vault KV path is required" >&2
    echo "Usage: fetch-secrets.sh [-o output] path [path ...]" >&2
    exit 1
fi

# ── Configuration ─────────────────────────────────────────────────────────
VAULT_ADDR="${VAULT_ADDR:?VAULT_ADDR is required}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:?VAULT_ROLE_ID is required}"
VAULT_SECRET_ID="${VAULT_SECRET_ID:?VAULT_SECRET_ID is required}"

# ── Preflight ─────────────────────────────────────────────────────────────
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '${cmd}' is required but not found" >&2
        exit 1
    fi
done

# ── Authenticate via AppRole ──────────────────────────────────────────────
echo "Authenticating to Vault via AppRole..."
login_response=$(curl -sf --max-time 10 \
    --request POST \
    --data "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
    "${VAULT_ADDR}/v1/auth/approle/login") || {
        echo "ERROR: AppRole login failed — is Vault reachable at ${VAULT_ADDR}?" >&2
        exit 1
    }

VAULT_TOKEN=$(echo "$login_response" | jq -re '.auth.client_token') || {
    echo "ERROR: Failed to extract token from login response" >&2
    echo "  Response: ${login_response}" >&2
    exit 1
}

token_ttl=$(echo "$login_response" | jq -r '.auth.lease_duration')
echo "  Authenticated (token TTL: ${token_ttl}s)"

# ── Fetch and merge secrets from all paths ────────────────────────────────
total_keys=0
merged_json="{}"
source_list=""

for kv_path in "${PATHS[@]}"; do
    echo "Reading secrets from ${kv_path}..."
    secret_response=$(curl -sf --max-time 10 \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        "${VAULT_ADDR}/v1/${kv_path}") || {
            echo "ERROR: Failed to read ${kv_path}" >&2
            echo "  Check that the path exists and the policy grants read access" >&2
            exit 1
        }

    key_count=$(echo "$secret_response" | jq -r '.data.data | length')
    if [ "$key_count" -eq 0 ]; then
        echo "  WARNING: No secrets found at ${kv_path} — skipping" >&2
        continue
    fi

    # Merge this path's secrets into the accumulated JSON object
    # jq '*' performs object merge — last path wins on duplicate keys
    merged_json=$(echo "$merged_json" "$secret_response" | \
        jq -s '.[0] * (.[1].data.data)')

    total_keys=$(echo "$merged_json" | jq 'length')
    source_list="${source_list}# Source: ${kv_path} (${key_count} keys)
"
    echo "  Read ${key_count} keys (${total_keys} total)"
done

if [ "$total_keys" -eq 0 ]; then
    echo "ERROR: No secrets found across any path" >&2
    exit 1
fi

# ── Write .env.secrets ────────────────────────────────────────────────────
{
    echo "# Auto-generated from Vault — do not edit manually"
    printf '%s' "$source_list"
    echo "# Fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "$merged_json" | jq -r 'to_entries | sort_by(.key)[] | "\(.key)=\(.value)"'
} > "${OUTPUT_FILE}"

chmod 0600 "${OUTPUT_FILE}"
echo "  Wrote ${total_keys} secrets to ${OUTPUT_FILE} (mode 0600)"
