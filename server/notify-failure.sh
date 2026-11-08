#!/usr/bin/env bash
set -euo pipefail
UNIT="${1:-unknown}"
SECRETS_FILE="/home/alex/.secrets"

# Parsed, not sourced: this script runs as root and the file is user-owned.
secret() { sed -n "s/^$1=//p" "$SECRETS_FILE" | tail -n1 | tr -d "\"'"; }
TELEGRAM_BOT_TOKEN="$(secret TELEGRAM_BOT_TOKEN)"
TELEGRAM_CHAT_ID="$(secret TELEGRAM_CHAT_ID)"

LOG="$(journalctl -u "$UNIT" -n 8 --no-pager -o cat 2>/dev/null | tail -c 1500 || true)"
MSG="⚠️ ${UNIT} fallito su $(hostname) il $(date '+%F %T')

${LOG}"

# URL passed via stdin so the token does not show up in the process list.
printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" |
  curl -fsS --max-time 20 --retry 3 --retry-delay 5 -K - \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode text="${MSG}" >/dev/null
