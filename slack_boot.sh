#!/usr/bin/env bash
set -e
set -a
source /etc/app.env
set +a

WEBHOOK_URL="${APP_SLACK_WEBHOOK:-}"
[ -z "$WEBHOOK_URL" ] && exit 0

SERVER_HOST="$(hostname -f 2>/dev/null || hostname)"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
WHEN="$(TZ=Australia/Sydney date -Is 2>/dev/null || TZ=Australia/Sydney date)"

MSG=":${LOGO}: 🔁 server boot: _${SERVER_HOST}_ ip=${SERVER_IP:-?} boot_id=${BOOT_ID:-?} at=${WHEN}"

curl -fsS -m 5 \
  -H 'Content-type: application/json' \
  --data "{\"text\":\"${MSG//\"/\\\"}\"}" \
  "$WEBHOOK_URL" >/dev/null 2>&1 || true
