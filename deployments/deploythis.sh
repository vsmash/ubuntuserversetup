#!/usr/bin/env bash
set -euo pipefail
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

# these should all now come from the config file DO NOT UNCOMMENT
#REPO="/path/to/repo"
#BRANCH="main"
#WEBROOT="/var/www/your/wwwroot"
# set this to your actual URL (no trailing slash)
#BASE_URL="https://www.your.site"
# Cloudflare API token for cach purge (not letsencrypt)
# Required permissions: Zone / Cache Purge
# Create a token at: https://dash.cloudflare.com/profile/api-tokens
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

  # Only purge if explicitly enabled in config
  if [[ "${PURGE_ON_DEPLOY:-0}" -ne 1 ]]; then
    echo "Skipping Cloudflare purge (PURGE_ON_DEPLOY not set to 1)"
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
LOCK_FILE="$LOCK_DIR/${site}_deploy_${BRANCH}.lock"

mkdir -p "$STATE_DIR"
chmod 0755 "$STATE_DIR"

# prevent overlapping deploys
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Deploy already running (lock: $LOCK_FILE)"; exit 1; }

cmd="${2:-deploy}"

apply_perms() {
  # 1) Ensure base ownership is sane without walking the whole tree
  chown -R ubuntu:www-data "$WEBROOT"
  #2) make sure wordpress files and folders have correct permissions
  find "$WEBROOT" -type d -exec chmod 755 {} \;
  find "$WEBROOT" -type f -exec chmod 644 {} \;


}

run_tests() {
  if [[ -f "$REPO/.scripts/test-production.sh" ]]; then
    sudo -u ubuntu bash -lc "
      cd '$REPO'
      source .scripts/test-production.sh '$BASE_URL'
    "
  else
    echo "No test script at ${REPO}/.scripts/test-production.sh — skipping tests."
  fi
}

deploy() {
  # update repo as ubuntu to origin/$BRANCH
  sudo -u ubuntu bash -lc "
    set -e
    cd '$REPO'
    git fetch --prune origin
    git checkout -f '$BRANCH'
    git reset --hard 'origin/$BRANCH'
  "

  new_commit="$(sudo -u ubuntu bash -lc "cd '$REPO' && git rev-parse HEAD")"

  # deploy files — run repo's deploy script if present, skip if not
  if [[ -f "$REPO/.scripts/deploy-main.sh" ]]; then
    sudo -u ubuntu bash -lc "
      cd '$REPO'
      bash .scripts/deploy-main.sh '$WEBROOT'
    "
  else
    echo "No deploy script at ${REPO}/.scripts/deploy-main.sh — skipping file sync."
  fi

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

  sudo -u ubuntu bash -lc "
    set -e
    cd '$REPO'
    git fetch --prune origin
    git checkout -f '$BRANCH'
    git reset --hard '$good_commit'
  "

  # deploy files — run repo's deploy script if present, skip if not
  if [[ -f "$REPO/.scripts/deploy-main.sh" ]]; then
    sudo -u ubuntu bash -lc "
      cd '$REPO'
      bash .scripts/deploy-main.sh '$WEBROOT'
    "
  else
    echo "No deploy script at ${REPO}/.scripts/deploy-main.sh — skipping file sync."
  fi

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