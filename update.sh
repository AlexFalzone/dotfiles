#!/usr/bin/env bash
#
# Persistent log: $BASE/update.log

set -uo pipefail

BASE="/home/alex"
LOG="$BASE/update.log"

# Services to update (paths relative to $BASE)
SERVICES=(
    "immich-app"
    "nginx"
    "navidrome"
    "opencloud/opencloud-compose"
    "mealie"
    "vaultwarden"
    #"ryot"
    # "n8n"
)

FAILED=()

SECRETS_FILE="$BASE/.secrets"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
else
    log "WARNING: $SECRETS_FILE not found - Telegram notifications disabled"
fi

notify_telegram() {
    local msg="$1"
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        return
    fi
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${msg}" >/dev/null
}

update_service() {
    local dir="$1"
    local path="$BASE/$dir"
    if [[ ! -d "$path" ]]; then
        log "ERROR: directory not found: $path"
        FAILED+=("$dir")
        return
    fi
    log "--- Updating: $dir ---"
    if (cd "$path" && docker compose pull && docker compose up -d) 2>&1 | tee -a "$LOG"; then
        log "OK: $dir updated"
    else
        log "ERROR: update failed for $dir"
        FAILED+=("$dir")
    fi
}

log "===== Starting Docker stack update ====="
for svc in "${SERVICES[@]}"; do
    update_service "$svc"
    echo
done
log "===== Update complete ====="

log "--- Pruning unused Docker images ---"
docker image prune -f 2>&1 | tee -a "$LOG"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "Services with errors: ${FAILED[*]}"
    notify_telegram "⚠ update.sh (Storage VM): errors on: ${FAILED[*]}"
    exit 1
fi

log "All services updated successfully."
notify_telegram "✅ Update (Storage VM): all stacks updated successfully"
exit 0
