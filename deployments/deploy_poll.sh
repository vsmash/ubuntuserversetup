#!/usr/bin/env bash
set -euo pipefail

cd /tmp

site="$1"

# check for site parameter
if [[ -z "$site" ]]; then
  echo "Usage: $0 <site>"
  exit 1
fi

# check for config in /etc/deploy/
SITE_CONFIG="/etc/deployments/${site}.conf"
if [[ ! -f "$SITE_CONFIG" ]]; then
  echo "Config not found: $SITE_CONFIG"
  exit 1
fi

source "$SITE_CONFIG"

# ---- site-specific config ----
DEPLOY_CMD="/usr/local/sbin/deploythis.sh ${site} deploy"
# --------------------------------

STATE_DIR="/var/lib/${site}"
mkdir -p "$STATE_DIR"
LAST_SEEN="$STATE_DIR/last_seen_${site}.txt"

LOCK_FILE="$STATE_DIR/${site}.lock"

# If a deploy is already running, do nothing
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# Ask the remote what HEAD is (cheap)
remote_head="$(git -C "$REPO" ls-remote --heads origin "$BRANCH" | awk '{print $1}')"

[[ -n "$remote_head" ]] || exit 0

last_seen=""
[[ -f "$LAST_SEEN" ]] && last_seen="$(cat "$LAST_SEEN" || true)"

# No change → nothing to do
[[ "$remote_head" == "$last_seen" ]] && exit 0

# Trigger deploy (wrapper already handles locking, tests, rollback)
if sudo $DEPLOY_CMD; then
  # Record new head only after successful deploy
  echo "$remote_head" > "$LAST_SEEN"
else
  # Deploy failed — don't record, so next poll retries
  exit 1
fi
