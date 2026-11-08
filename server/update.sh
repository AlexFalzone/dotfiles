#!/bin/bash
#
# Persistent log: $BASE/update.log
# Failure notifications: handled by systemd (docker-update.service OnFailure).

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
    "wger"
    "openwebui"
    #"ryot"
    # "n8n"    # not active
)

FAILED=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
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
    exit 1
fi

log "All services updated successfully."
exit 0
