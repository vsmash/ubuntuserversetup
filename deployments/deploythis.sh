#!/usr/bin/env bash
set -euo pipefail
site="$1"

# check for site parameter
if [[ -z "$site" ]]; then
  echo "Usage: $0 <site>"
  exit 1
fi

# check for config in /etc/deploy/
SITE_CONFIG="/etc/deploy/${site}.conf"
if [[ ! -f "$SITE_CONFIG" ]]; then
  echo "Config not found: $SITE_CONFIG"
  exit 1
fi

# these should all now come from the config file DO NOT UNCOMMENT
#REPO="/path/to/repo"
#BRANCH="main"
#WEBROOT="/var/www/your/wwwroot"
# set this to your actual URL (no trailing slash)
#BASE_URL="https://www.your.site"
# Cloudflare API token for certbot DNS validation
# Create a token at: https://dash.cloudflare.com/profile/api-tokens
# Required permissions: Zone / DNS / Edit
#CLOUDFLARE_ZONE_ID=""
#CLOUDFLARE_API_TOKEN=""

source "$SITE_CONFIG"


STATE_DIR="/var/lib/${site}"
LAST_GOOD="$STATE_DIR/last_good_${BRANCH}.txt"

# slack notification helper
notify_slack() {
  local emoji="$1"
  local message="$2"
  /usr/local/bin/slack --webhook=mark "${emoji} ${message}" || true
}

# cloudflare cache purge
purge_cloudflare() {
  if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]] || [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    echo "Skipping Cloudflare purge (credentials not configured)"
    return 0
  fi

  echo "Purging Cloudflare cache..."
  local response
  response=$(curl -s -w "\n%{http_code}" -X POST \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"purge_everything":true}')
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')
  
  if [[ "$http_code" == "200" ]]; then
    echo "Cloudflare cache purged successfully"
  else
    echo "Warning: Cloudflare purge failed (HTTP $http_code): $body" >&2
    # Don't fail the deploy if cache purge fails
    return 0
  fi
}

# lock: prefer /run/lock, fall back to /var/lock
LOCK_DIR="/run/lock"
[[ -d "$LOCK_DIR" ]] || LOCK_DIR="/var/lock"
LOCK_FILE="$LOCK_DIR/spirit_deploy_${BRANCH}.lock"

mkdir -p "$STATE_DIR"
chmod 0755 "$STATE_DIR"

# prevent overlapping deploys
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Deploy already running (lock: $LOCK_FILE)"; exit 1; }

cmd="${1:-deploy}"

apply_perms() {
  # 1) Ensure base ownership is sane without walking the whole tree
  chown mark:www-data "$WEBROOT"

  # 2) Fix permissions on code-ish stuff, but skip big dirs
  find "$WEBROOT" -type d \( -path "$WEBROOT/image" -o -path "$WEBROOT/mp3" \) -prune -o -type d -exec chmod 2775 {} +
  find "$WEBROOT" -type f \( -path "$WEBROOT/image/*" -o -path "$WEBROOT/mp3/*" \) -prune -o -type f -exec chmod 0664 {} +

  # 3) Writable dirs: set just these
  install -d -m 2775 -o mark -g www-data \
    "$WEBROOT/system/cache" \
    "$WEBROOT/system/logs" \
    "$WEBROOT/image/cache" \
    "$WEBROOT/download" \
    "$WEBROOT/mp3"

  if [[ -d "$WEBROOT/image/data" ]]; then
    chown -R mark:www-data "$WEBROOT/image/data"
    chmod -R 2775 "$WEBROOT/image/data"
  fi

  chown -R mark:www-data \
    "$WEBROOT/system/cache" \
    "$WEBROOT/system/logs" \
    "$WEBROOT/image/cache" \
    "$WEBROOT/download" \
    "$WEBROOT/mp3"

  find "$WEBROOT/system/cache" "$WEBROOT/system/logs" "$WEBROOT/image/cache" "$WEBROOT/download" "$WEBROOT/mp3" -type d -exec chmod 2775 {} +
  find "$WEBROOT/system/cache" "$WEBROOT/system/logs" "$WEBROOT/image/cache" "$WEBROOT/download" "$WEBROOT/mp3" -type f -exec chmod 0664 {} +

  # optional reloads
  # systemctl reload php8.4-fpm
}

run_tests() {
  sudo -u mark bash -lc "
    cd '$REPO'
    ./scripts/test-production.sh '$BASE_URL'
  "
}

deploy() {
  # update repo as mark to origin/$BRANCH
  sudo -u mark bash -lc "
    cd '$REPO'
    git fetch --prune origin
    git checkout -f '$BRANCH'
    git reset --hard 'origin/$BRANCH'
  "

  new_commit="$(sudo -u mark bash -lc "cd '$REPO' && git rev-parse HEAD")"

  # deploy files
  sudo -u mark bash -lc "
    cd '$REPO'
    ./scripts/deploy-main.sh '$WEBROOT'
  "

  apply_perms

  # tests must pass before recording last-good
  run_tests

  echo "$new_commit" > "$LAST_GOOD"
  chmod 0644 "$LAST_GOOD"

  # read version if available
  version="unknown"
  if [[ -f "$REPO/VERSION" ]]; then
    version=$(cat "$REPO/VERSION" | tr -d '[:space:]')
  fi

  # purge cloudflare cache after successful deploy
  purge_cloudflare

  echo "OK: deployed $BRANCH @ $new_commit"
  notify_slack ":white_check_mark:" "Deployment successful: $BRANCH @ ${new_commit:0:7} (v${version})"
}

rollback() {
  [[ -f "$LAST_GOOD" ]] || { echo "No last-good file: $LAST_GOOD" >&2; exit 1; }
  good_commit="$(cat "$LAST_GOOD")"
  [[ -n "$good_commit" ]] || { echo "Last-good commit empty" >&2; exit 1; }

  sudo -u mark bash -lc "
    cd '$REPO'
    git fetch --prune origin
    git checkout -f '$BRANCH'
    git reset --hard '$good_commit'
  "

  sudo -u mark bash -lc "
    cd '$REPO'
    ./scripts/deploy-main.sh '$WEBROOT'
  "

  apply_perms
  run_tests

  # read version if available
  version="unknown"
  if [[ -f "$REPO/VERSION" ]]; then
    version=$(cat "$REPO/VERSION" | tr -d '[:space:]')
  fi

  echo "OK: rolled back $BRANCH to $good_commit"
  notify_slack ":rewind:" "Rollback successful: $BRANCH to ${good_commit:0:7} (v${version})"
}

deploy_with_auto_rollback() {
  set +e
  deploy
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "Deploy failed; attempting rollback to last-known-good..." >&2
    notify_slack ":x:" "Deployment FAILED for $BRANCH - attempting automatic rollback"
    rollback || true
    exit "$rc"
  fi
}

case "$cmd" in
  deploy) deploy_with_auto_rollback ;;
  deploy-no-rollback) deploy ;;
  rollback) rollback ;;
  *)
    echo "Usage: $0 [deploy|deploy-no-rollback|rollback]" >&2
    exit 2
    ;;
esac