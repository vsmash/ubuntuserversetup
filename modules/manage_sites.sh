#!/usr/bin/env bash
# Module: manage_sites.sh
# Interactive management of site deployment configs.
#   - List existing sites in /etc/deployments/
#   - Add a new site config
#   - Edit an existing site config
#   - Set up / remove cron-based polling for a site

set -e

DEPLOY_CONFIG_DIR="/etc/deployments"
POLL_CMD="/usr/local/sbin/deploy_poll.sh"
DEPLOY_CMD="/usr/local/sbin/deploythis.sh"
CRON_USER="${APP_USER:-ubuntu}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_list_sites() {
  local configs
  configs=("$DEPLOY_CONFIG_DIR"/*.conf) 2>/dev/null || true
  # Filter out the glob pattern itself if no matches
  if [[ ${#configs[@]} -eq 0 ]] || [[ "${configs[0]}" == "$DEPLOY_CONFIG_DIR/*.conf" ]]; then
    echo "  (no sites configured)"
    return 1
  fi
  local i=1
  for conf in "${configs[@]}"; do
    local name
    name="$(basename "$conf" .conf)"
    # Pull key values for display
    local repo branch webroot
    repo="$(grep -oP '^REPO="\K[^"]+' "$conf" 2>/dev/null || echo '?')"
    branch="$(grep -oP '^BRANCH="\K[^"]+' "$conf" 2>/dev/null || echo '?')"
    webroot="$(grep -oP '^WEBROOT="\K[^"]+' "$conf" 2>/dev/null || echo '?')"
    printf "  %d) %-20s  branch=%-10s  webroot=%s\n" "$i" "$name" "$branch" "$webroot"
    i=$((i + 1))
  done
  return 0
}

_get_site_names() {
  local configs
  configs=("$DEPLOY_CONFIG_DIR"/*.conf) 2>/dev/null || true
  if [[ ${#configs[@]} -eq 0 ]] || [[ "${configs[0]}" == "$DEPLOY_CONFIG_DIR/*.conf" ]]; then
    return 1
  fi
  SITE_NAMES=()
  for conf in "${configs[@]}"; do
    SITE_NAMES+=("$(basename "$conf" .conf)")
  done
}

_pick_site() {
  _get_site_names || { echo "  No sites configured."; return 1; }
  echo ""
  _list_sites
  echo ""
  read -rp "  Enter site number: " num
  if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#SITE_NAMES[@]} )); then
    echo "  Invalid selection."
    return 1
  fi
  PICKED_SITE="${SITE_NAMES[$((num - 1))]}"
}

# ---------------------------------------------------------------------------
# Prompt for config values (used by add & edit)
# ---------------------------------------------------------------------------

_prompt_config() {
  local current_file="${1:-}"
  local def_repo="" def_branch="main" def_webroot="" def_base_url=""
  local def_cf_zone="" def_cf_token="" def_purge="0"

  # Load existing values as defaults if editing
  if [[ -n "$current_file" ]] && [[ -f "$current_file" ]]; then
    def_repo="$(grep -oP '^REPO="\K[^"]*' "$current_file" 2>/dev/null || true)"
    def_branch="$(grep -oP '^BRANCH="\K[^"]*' "$current_file" 2>/dev/null || echo 'main')"
    def_webroot="$(grep -oP '^WEBROOT="\K[^"]*' "$current_file" 2>/dev/null || true)"
    def_base_url="$(grep -oP '^BASE_URL="\K[^"]*' "$current_file" 2>/dev/null || true)"
    def_cf_zone="$(grep -oP '^CLOUDFLARE_ZONE_ID="\K[^"]*' "$current_file" 2>/dev/null || true)"
    def_cf_token="$(grep -oP '^CLOUDFLARE_API_TOKEN="\K[^"]*' "$current_file" 2>/dev/null || true)"
    def_purge="$(grep -oP '^PURGE_ON_DEPLOY="\K[^"]*' "$current_file" 2>/dev/null || echo '0')"
  fi

  echo ""
  echo "  Enter values (leave blank to keep default shown in brackets):"
  echo "  --------------------------------------------------------------"

  read -rp "  REPO (local git clone path, no trailing slash) [${def_repo}]: " val; CFG_REPO="${val:-$def_repo}"
  CFG_REPO="${CFG_REPO%/}"
  read -rp "  BRANCH [${def_branch}]: " val; CFG_BRANCH="${val:-$def_branch}"
  read -rp "  WEBROOT (deploy target path, no trailing slash) [${def_webroot}]: " val; CFG_WEBROOT="${val:-$def_webroot}"
  CFG_WEBROOT="${CFG_WEBROOT%/}"
  read -rp "  BASE_URL [${def_base_url}]: " val; CFG_BASE_URL="${val:-$def_base_url}"
  echo ""
  echo "  Cloudflare (for cache purge on deploy — leave blank to skip):"
  read -rp "  CLOUDFLARE_ZONE_ID [${def_cf_zone}]: " val; CFG_CF_ZONE="${val:-$def_cf_zone}"
  read -rp "  CLOUDFLARE_API_TOKEN [${def_cf_token}]: " val; CFG_CF_TOKEN="${val:-$def_cf_token}"
  read -rp "  PURGE_ON_DEPLOY (0 or 1) [${def_purge}]: " val; CFG_PURGE="${val:-$def_purge}"

  # Validate required fields
  if [[ -z "$CFG_REPO" ]]; then
    echo "  error: REPO is required." >&2
    return 1
  fi
  if [[ -z "$CFG_WEBROOT" ]]; then
    echo "  error: WEBROOT is required." >&2
    return 1
  fi
}

_write_config() {
  local conf_file="$1"
  cat > "$conf_file" <<EOF
REPO="${CFG_REPO}"
BRANCH="${CFG_BRANCH}"
WEBROOT="${CFG_WEBROOT}"
# Site URL (no trailing slash)
BASE_URL="${CFG_BASE_URL}"
# Cloudflare cache purge (not letsencrypt)
# Required permissions: Zone / Cache Purge
CLOUDFLARE_ZONE_ID="${CFG_CF_ZONE}"
CLOUDFLARE_API_TOKEN="${CFG_CF_TOKEN}"
PURGE_ON_DEPLOY="${CFG_PURGE}"
EOF
  chmod 640 "$conf_file"
  chown "root:${APP_USER:-ubuntu}" "$conf_file" 2>/dev/null || true
  echo "  Config written to ${conf_file} (chmod 640, owner root:${APP_USER:-ubuntu})."
}

# ---------------------------------------------------------------------------
# Cron management
# ---------------------------------------------------------------------------

_get_cron_line() {
  local site="$1"
  echo "* * * * * ${POLL_CMD} ${site} >> /var/log/${site}_deploy.log 2>&1"
}

_cron_is_set() {
  local site="$1"
  crontab -u "$CRON_USER" -l 2>/dev/null | grep -qF "deploy_poll.sh ${site}"
}

_setup_cron() {
  local site="$1"
  local cron_line
  cron_line="$(_get_cron_line "$site")"

  if _cron_is_set "$site"; then
    echo "  [ok] Cron already set for ${site}."
    return 0
  fi

  echo "  Adding cron job for ${site} (runs every minute as ${CRON_USER})..."
  ( crontab -u "$CRON_USER" -l 2>/dev/null || true; echo "$cron_line" ) | crontab -u "$CRON_USER" -
  echo "  Cron installed: ${cron_line}"
}

_remove_cron() {
  local site="$1"

  if ! _cron_is_set "$site"; then
    echo "  No cron entry found for ${site}."
    return 0
  fi

  echo "  Removing cron job for ${site}..."
  crontab -u "$CRON_USER" -l 2>/dev/null | grep -vF "deploy_poll.sh ${site}" | crontab -u "$CRON_USER" -
  echo "  Cron removed for ${site}."
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

site_list() {
  echo ""
  echo "==> Configured sites:"
  echo ""
  _list_sites
  echo ""

  # Show cron status for each
  if _get_site_names; then
    echo "  Polling status:"
    for name in "${SITE_NAMES[@]}"; do
      if _cron_is_set "$name"; then
        echo "    ${name}: polling ACTIVE"
      else
        echo "    ${name}: polling NOT SET"
      fi
    done
  fi
}

site_add() {
  echo ""
  read -rp "  Enter a short site name (e.g. mysite, projectx): " site_name
  site_name="$(echo "$site_name" | tr -cd 'a-zA-Z0-9_-')"

  if [[ -z "$site_name" ]]; then
    echo "  error: Invalid site name."
    return 1
  fi

  local conf_file="${DEPLOY_CONFIG_DIR}/${site_name}.conf"
  if [[ -f "$conf_file" ]]; then
    echo "  ${conf_file} already exists. Use edit instead."
    return 1
  fi

  _prompt_config || return 1
  mkdir -p "$DEPLOY_CONFIG_DIR"
  _write_config "$conf_file"

  # Create state dir
  mkdir -p "/var/lib/${site_name}"
  chown "${APP_USER:-ubuntu}:${APP_USER:-ubuntu}" "/var/lib/${site_name}"
  chmod 0755 "/var/lib/${site_name}"

  # Create deploy log file
  touch "/var/log/${site_name}_deploy.log"
  chown "${APP_USER:-ubuntu}:${APP_USER:-ubuntu}" "/var/log/${site_name}_deploy.log"

  # Create logrotate config for deploy log
  cat > "/etc/logrotate.d/${site_name}_deploy" <<EOF
/var/log/${site_name}_deploy.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 ${APP_USER:-ubuntu} ${APP_USER:-ubuntu}
}
EOF

  echo ""
  read -rp "  Enable polling for ${site_name}? [Y/n]: " enable_poll
  if [[ ! "$enable_poll" =~ ^[Nn]$ ]]; then
    _setup_cron "$site_name"
  fi

  echo ""
  echo "==> Site ${site_name} added."
}

site_edit() {
  _pick_site || return 1
  local conf_file="${DEPLOY_CONFIG_DIR}/${PICKED_SITE}.conf"

  echo ""
  echo "  Editing: ${PICKED_SITE}"
  _prompt_config "$conf_file" || return 1
  _write_config "$conf_file"

  echo ""
  echo "==> Site ${PICKED_SITE} updated."
}

site_toggle_poll() {
  _pick_site || return 1

  if _cron_is_set "$PICKED_SITE"; then
    echo ""
    read -rp "  Polling is ACTIVE for ${PICKED_SITE}. Disable? [y/N]: " disable
    if [[ "$disable" =~ ^[Yy]$ ]]; then
      _remove_cron "$PICKED_SITE"
    fi
  else
    echo ""
    read -rp "  Polling is NOT SET for ${PICKED_SITE}. Enable? [Y/n]: " enable
    if [[ ! "$enable" =~ ^[Nn]$ ]]; then
      _setup_cron "$PICKED_SITE"
    fi
  fi
}

site_remove() {
  _pick_site || return 1

  echo ""
  echo "  WARNING: This will remove the config and cron for ${PICKED_SITE}."
  echo "  It will NOT remove the repo, webroot, or state files."
  read -rp "  Are you sure? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    return 0
  fi

  _remove_cron "$PICKED_SITE"
  rm -f "${DEPLOY_CONFIG_DIR}/${PICKED_SITE}.conf"
  echo "  Config removed: ${DEPLOY_CONFIG_DIR}/${PICKED_SITE}.conf"
  echo ""
  echo "==> Site ${PICKED_SITE} removed."
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

manage_sites() {
  while true; do
    echo ""
    echo "========================================="
    echo "  Manage Site Deployments"
    echo "========================================="
    echo ""
    echo "  1)  List sites"
    echo "  2)  Add a new site"
    echo "  3)  Edit a site config"
    echo "  4)  Toggle polling (enable/disable)"
    echo "  5)  Remove a site"
    echo ""
    echo "  0)  Back"
    echo ""
    read -rp "  Choose an option [0-5]: " choice
    echo ""

    case "$choice" in
      1) site_list ;;
      2) site_add ;;
      3) site_edit ;;
      4) site_toggle_poll ;;
      5) site_remove ;;
      0) return 0 ;;
      *) echo "  Invalid option: ${choice}" ;;
    esac

    echo ""
    read -rp "  Press Enter to continue..." _
  done
}
