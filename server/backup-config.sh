#!/usr/bin/env bash
#
# backup-config.sh
# Encrypted, incremental backup of configs, databases and credentials to
# Google Drive via restic + rclone.
#
# Does NOT cover heavy media (Immich photos, Navidrome music library)
# that's a separate script/target.
#
# ==============================================================================
# SETUP:
#
# 1. Install prerequisites (Debian):
#      sudo apt update && sudo apt install -y restic rclone sqlite3
#
# 2. Configure the rclone remote:
#    New remote named "drive", type "drive" (Google Drive).
#
# 3. Generate the restic repository password:
#      openssl rand -base64 32 | sudo tee /root/.restic-config-pass
#      sudo chmod 600 /root/.restic-config-pass
#
# 4. Set HOME_DIR and the per-service paths below to match your own layout.
#
# 5. Initialize the repository (first run only):
#      export RESTIC_PASSWORD_FILE=/root/.restic-config-pass
#      restic -r rclone:drive:/backup/config init
#
# 6. Test it:
#      chmod +x backup-config.sh
#      sudo ./backup-config.sh
#
# 7. Schedule with a systemd timer or cron.
# ==============================================================================

set -euo pipefail

# ============================ CONFIG =========================================

HOME_DIR="/home/alex"

export RESTIC_REPOSITORY="rclone:drive:/backup/config"
export RESTIC_PASSWORD_FILE="/root/.restic-config-pass"
export RCLONE_CONFIG="${HOME_DIR}/.config/rclone/rclone.conf"

# Private (0700) random dir: staging holds DB dumps and Vaultwarden data.
STAGING="$(mktemp -d /tmp/backup-staging.XXXXXXXX)"

# Retention policy
KEEP_DAILY=5
KEEP_WEEKLY=2
KEEP_MONTHLY=3

# --- Per-service paths ---
RYOT_COMPOSE_DIR="${HOME_DIR}/ryot"                       # currently disabled, see EXECUTION
RYOT_DB_CONTAINER="ryot-db"
RYOT_DB_USER="postgres"
RYOT_DB_NAME="postgres"

VAULTWARDEN_DATA="/opt/vaultwarden_data"

IMMICH_COMPOSE_DIR="${HOME_DIR}/immich-app"
IMMICH_DB_CONTAINER="immich_postgres"
IMMICH_DB_USER="postgres"
IMMICH_DB_NAME="immich"

OPENCLOUD_COMPOSE_DIR="${HOME_DIR}/opencloud/opencloud-compose"
OPENCLOUD_RUNTIME_CONFIG="/opt/opencloud/config"
OPENCLOUD_RADICALE_DATA="/opt/opencloud/radicale"

NAVIDROME_CONTAINER="navidrome-navidrome-1"
NAVIDROME_DATA="/opt/navidrome_data"

MEALIE_COMPOSE_DIR="${HOME_DIR}/mealie"
MEALIE_DATA="/opt/mealie_data"

NPM_DATA="${HOME_DIR}/nginx/data"
NPM_LETSENCRYPT="${HOME_DIR}/nginx/letsencrypt"

WGER_COMPOSE_DIR="${HOME_DIR}/wger"
WGER_DB_CONTAINER="wger-db-1"
WGER_DB_USER="wger"

OPENWEBUI_COMPOSE_DIR="${HOME_DIR}/openwebui"
OPENWEBUI_DATA="/opt/openwebui_data"

SECRETS_FILE="${HOME_DIR}/.secrets"
# Parsed, not sourced: this script runs as root and the file is user-owned.
secret() {
    [[ -r "$SECRETS_FILE" ]] || return 0
    sed -n "s/^$1=//p" "$SECRETS_FILE" | tail -n1 | tr -d "\"'"
}
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $SECRETS_FILE not found - Telegram notifications disabled"
fi
TG_BOT_TOKEN="$(secret TELEGRAM_BOT_TOKEN)"
TG_CHAT_ID="$(secret TELEGRAM_CHAT_ID)"

# ==============================================================================
# --------------------------- FUNCTIONS ---------------------------------------

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
    # Best-effort Telegram notification.
    local msg="$1"
    if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
        # URL passed via stdin so the token does not show up in the process list.
        printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TG_BOT_TOKEN" |
            curl -s -K - \
                -d chat_id="${TG_CHAT_ID}" \
                --data-urlencode text="${msg}" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    [[ -d "$STAGING" ]] && rm -rf "$STAGING"
}
trap cleanup EXIT

dump_ryot() {
    log "Dumping Ryot database (Postgres)..."
    if docker ps --format '{{.Names}}' | grep -q "^${RYOT_DB_CONTAINER}$"; then
        docker exec "$RYOT_DB_CONTAINER" \
            pg_dump -U "$RYOT_DB_USER" -d "$RYOT_DB_NAME" \
            > "${STAGING}/ryot-db.sql"
        log "  -> ryot-db.sql created ($(du -h "${STAGING}/ryot-db.sql" | cut -f1))"
    else
        log "  WARNING: ${RYOT_DB_CONTAINER} not running, skipping DB dump."
    fi
}

dump_immich() {
    log "Dumping Immich database (Postgres)..."
    if docker ps --format '{{.Names}}' | grep -q "^${IMMICH_DB_CONTAINER}$"; then
        mkdir -p "${STAGING}/immich"
        docker exec "$IMMICH_DB_CONTAINER" \
            pg_dump -U "$IMMICH_DB_USER" -d "$IMMICH_DB_NAME" \
            > "${STAGING}/immich/immich-db.sql"
        log "  -> immich-db.sql created ($(du -h "${STAGING}/immich/immich-db.sql" | cut -f1))"
    else
        log "  WARNING: ${IMMICH_DB_CONTAINER} not running, skipping DB dump."
    fi
}

dump_navidrome() {
    log "Dumping Navidrome database (SQLite)..."
    if docker ps --format '{{.Names}}' | grep -q "^${NAVIDROME_CONTAINER}$"; then
        mkdir -p "${STAGING}/navidrome"
        sqlite3 "${NAVIDROME_DATA}/navidrome.db" \
            ".backup '${STAGING}/navidrome/navidrome.db'"
        log "  -> navidrome.db (consistent backup) created"
    else
        log "  WARNING: ${NAVIDROME_CONTAINER} not running, skipping DB dump."
    fi
    for item in beets.db beets-import.log artwork playlist; do
        collect "${NAVIDROME_DATA}/${item}" "navidrome"
    done
}

dump_mealie() {
    log "Dumping Mealie database (SQLite)..."
    mkdir -p "${STAGING}/mealie"
    local db_file
    db_file=$(find "${MEALIE_DATA}" -maxdepth 2 -name '*.db' -print -quit)
    if [[ -n "$db_file" ]]; then
        sqlite3 "$db_file" ".backup '${STAGING}/mealie/$(basename "$db_file")'"
        log "  -> $(basename "$db_file") (consistent backup) created"
    else
        log "  WARNING: no .db file found under ${MEALIE_DATA}, skipping DB dump."
    fi
    mkdir -p "${STAGING}/mealie/data"
    cp -a "${MEALIE_DATA}/." "${STAGING}/mealie/data/" 2>/dev/null || true
    find "${STAGING}/mealie/data" -maxdepth 2 -name '*.db*' -delete 2>/dev/null || true
}

dump_wger() {
    log "Dumping wger database (Postgres)..."
    if docker ps --format '{{.Names}}' | grep -q "^${WGER_DB_CONTAINER}$"; then
        mkdir -p "${STAGING}/wger"
        docker exec "$WGER_DB_CONTAINER" \
            pg_dumpall --clean --username "$WGER_DB_USER" \
            > "${STAGING}/wger/wger-db.sql"
        log "  -> wger-db.sql created ($(du -h "${STAGING}/wger/wger-db.sql" | cut -f1))"
    else
        log "  WARNING: ${WGER_DB_CONTAINER} not running, skipping DB dump."
    fi
}

dump_openwebui() {
    # Chat history, users and settings live in webui.db (SQLite).
    # vector_db/ and cache/ are rebuildable, so they are not backed up.
    log "Dumping Open WebUI database (SQLite)..."
    if [[ -f "${OPENWEBUI_DATA}/webui.db" ]]; then
        mkdir -p "${STAGING}/openwebui"
        sqlite3 "${OPENWEBUI_DATA}/webui.db" \
            ".backup '${STAGING}/openwebui/webui.db'"
        log "  -> webui.db (consistent backup) created"
    else
        log "  WARNING: ${OPENWEBUI_DATA}/webui.db not found, skipping DB dump."
    fi
    collect "${OPENWEBUI_DATA}/uploads" "openwebui"
}

collect() {
    local src="$1" dest="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "${STAGING}/${dest}"
        if cp -a "$src" "${STAGING}/${dest}/"; then
            log "  collected: $src"
        else
            log "  WARNING: copy failed/partial for $src (permissions?) - continuing anyway"
        fi
    else
        log "  WARNING: path not found, skipped: $src"
    fi
}

# --------------------------- EXECUTION ---------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Must run as root (needs /root/.restic-config-pass and root-owned" >&2
    echo "files like Let's Encrypt certs). Use: sudo $0" >&2
    exit 1
fi

log "=== Starting config backup to Google Drive ==="
mkdir -p "$STAGING"

# Ryot
#collect "${RYOT_COMPOSE_DIR}/docker-compose.yml" "ryot"
#collect "${RYOT_COMPOSE_DIR}/.env"               "ryot"

# Vaultwarden
collect "${VAULTWARDEN_DATA}" "vaultwarden"

# Immich
collect "${IMMICH_COMPOSE_DIR}/docker-compose.yml" "immich"
collect "${IMMICH_COMPOSE_DIR}/.env"               "immich"
dump_immich

# OpenCloud
collect "${OPENCLOUD_COMPOSE_DIR}"    "opencloud"
collect "${OPENCLOUD_RUNTIME_CONFIG}" "opencloud"
collect "${OPENCLOUD_RADICALE_DATA}"  "opencloud-radicale"

# Navidrome
dump_navidrome

# Mealie
collect "${MEALIE_COMPOSE_DIR}/docker-compose.yml" "mealie"
collect "${MEALIE_COMPOSE_DIR}/.env"               "mealie"
dump_mealie

# wger
collect "${WGER_COMPOSE_DIR}/config/prod.env"             "wger/config"
collect "${WGER_COMPOSE_DIR}/docker-compose.override.yml" "wger"
dump_wger

# Open WebUI
collect "${OPENWEBUI_COMPOSE_DIR}/docker-compose.yml" "openwebui"
dump_openwebui

# Nginx
collect "${NPM_DATA}"        "npm"
collect "${NPM_LETSENCRYPT}" "npm"

log "Sending to restic..."
restic backup "$STAGING" \
    --tag config \
    --host storage \
    --exclude-caches

log "Applying retention policy..."
restic forget \
    --tag config \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune

log "Checking repository integrity..."
restic check

log "=== Backup complete ==="
notify "✅ Config backup complete ($(date '+%Y-%m-%d %H:%M'))"
