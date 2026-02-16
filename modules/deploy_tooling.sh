#!/usr/bin/env bash
# Module: deploy_tooling.sh
# Modular tooling installer — each component can be installed independently.
# Note: /etc/app.env is handled by setup_env.sh (runs earlier)

set -e

REPO_DIR="/opt/serversetup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- Helper: sync repo to /opt/serversetup (base for everything) ----
_tooling_sync_repo() {
  if [ ! -d "$REPO_DIR" ]; then
    echo "  Copying repo to ${REPO_DIR}..."
    cp -a "$SCRIPT_DIR" "$REPO_DIR"
  else
    echo "  Updating ${REPO_DIR} from source..."
    rsync -a --exclude='.git' --exclude='.env.*' "$SCRIPT_DIR/" "$REPO_DIR/"
  fi
}

# ---- Helper: symlink with idempotency ----
_tooling_symlink() {
  local src="$1" dest="$2"
  chmod +x "$src"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$src" ]; then
    echo "  [ok] $dest already correct."
  else
    echo "  Symlinking $src -> $dest..."
    ln -sf "$src" "$dest"
  fi
}

# ============================================================
# Individual install functions
# ============================================================

tooling_install_slack() {
  echo "--- Installing Slack CLI ---"
  _tooling_sync_repo
  _tooling_symlink "${REPO_DIR}/slack.sh" /usr/local/bin/slack
  echo "  Done. Usage: slack 'message' or slack --webhook=monitor 'message'"
}

tooling_install_slack_boot() {
  echo "--- Installing Slack boot notification ---"
  _tooling_sync_repo
  _tooling_symlink "${REPO_DIR}/slack_boot.sh" /usr/local/sbin/slack_boot

  local service_file="/etc/systemd/system/slack-boot.service"
  if [ -f "$service_file" ]; then
    echo "  [ok] slack-boot.service already installed."
  else
    echo "  Installing slack-boot.service..."
    cat > "$service_file" <<'EOF'
[Unit]
Description=Slack boot notification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/slack_boot
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable slack-boot.service
    echo "  slack-boot.service enabled."
  fi
}

tooling_install_deploy_scripts() {
  echo "--- Installing deploy scripts ---"
  _tooling_sync_repo

  _tooling_symlink "${REPO_DIR}/deployments/deploythis.sh" /usr/local/sbin/deploythis.sh
  _tooling_symlink "${REPO_DIR}/deployments/deploy_poll.sh" /usr/local/sbin/deploy_poll.sh

  mkdir -p /etc/deployments

  # Passwordless sudo for APP_USER to run deploythis.sh
  local sudoers_file="/etc/sudoers.d/deploy"
  local sudoers_rule="${APP_USER:-ubuntu} ALL=(root) NOPASSWD: /usr/local/sbin/deploythis.sh"
  if [ -f "$sudoers_file" ] && grep -qF "$sudoers_rule" "$sudoers_file"; then
    echo "  [ok] sudoers rule for deploy already in place."
  else
    echo "  Configuring passwordless sudo for ${APP_USER:-ubuntu} -> deploythis.sh..."
    echo "$sudoers_rule" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    if visudo -cf "$sudoers_file" >/dev/null 2>&1; then
      echo "  sudoers rule installed and validated."
    else
      echo "  error: sudoers file failed validation, removing." >&2
      rm -f "$sudoers_file"
      return 1
    fi
  fi
}

tooling_install_devlog() {
  echo "--- Installing devlog ---"
  _tooling_sync_repo

  _tooling_symlink "${REPO_DIR}/devlog_server.sh" /usr/local/bin/devlog

  mkdir -p /etc/serversetup/credentials
  chmod 700 /etc/serversetup/credentials

  # PHP dependencies for Google Sheets integration
  if [ -d "${REPO_DIR}/php_functions" ]; then
    chown -R "${APP_USER:-ubuntu}:${APP_USER:-ubuntu}" "${REPO_DIR}/php_functions"
    if [ ! -d "${REPO_DIR}/php_functions/vendor" ]; then
      echo "  Installing devlog PHP dependencies..."
      sudo -u "${APP_USER:-ubuntu}" bash -c "cd '${REPO_DIR}/php_functions' && composer install --no-dev --optimize-autoloader" 2>/dev/null || {
        echo "  Warning: Composer not available, skipping PHP dependencies."
        echo "  Google Sheets logging will not work until you run: cd ${REPO_DIR}/php_functions && composer install"
      }
    else
      echo "  [ok] Devlog PHP dependencies already installed."
    fi
  fi
}

tooling_install_sessionlog() {
  echo "--- Installing session log ---"
  _tooling_sync_repo

  if [ ! -d "${REPO_DIR}/opt/sessionlog" ]; then
    echo "  error: opt/sessionlog not found in repo." >&2
    return 1
  fi

  mkdir -p /opt/sessionlog
  cp -f "${REPO_DIR}/opt/sessionlog/sessionlog.sh" /opt/sessionlog/sessionlog.sh
  chmod +x /opt/sessionlog/sessionlog.sh

  # Install profile.d hook if not already present
  local profile_hook="/etc/profile.d/sessionlog.sh"
  if [ -f "$profile_hook" ]; then
    echo "  [ok] $profile_hook already exists."
  else
    echo "  Creating $profile_hook (autocapture off by default)..."
    cat > "$profile_hook" <<'PROFEOF'
# Session log — set SESSIONLOG_ONEMIN_API_KEY and SESSIONLOG_AUTOCAPTURE=true to enable
# source /opt/sessionlog/sessionlog.sh
PROFEOF
    echo "  To enable, edit $profile_hook and uncomment the source line."
    echo "  Set SESSIONLOG_ONEMIN_API_KEY in /etc/app.env or the profile hook."
  fi
}

tooling_install_root_bash() {
  echo "--- Installing /root/bash scripts ---"
  _tooling_sync_repo

  if [ -d "${REPO_DIR}/root/bash" ]; then
    mkdir -p /root/bash
    rsync -a "${REPO_DIR}/root/bash/" /root/bash/
    chmod +x /root/bash/*.sh 2>/dev/null || true
    echo "  /root/bash scripts updated."
  else
    echo "  No root/bash directory found in repo."
  fi
}

# ============================================================
# Install all (for full setup)
# ============================================================
tooling_install_all() {
  echo "==> Installing all tooling..."
  _tooling_sync_repo
  tooling_install_slack
  tooling_install_slack_boot
  tooling_install_deploy_scripts
  tooling_install_devlog
  tooling_install_sessionlog
  tooling_install_root_bash
  echo "==> All tooling installed."
}

# ============================================================
# Interactive sub-menu
# ============================================================
deploy_tooling() {
  echo ""
  echo "  ─────────────────────────────────────"
  echo "  Deploy Tooling — Select Components"
  echo "  ─────────────────────────────────────"
  echo ""
  echo "  1)  Install ALL tooling"
  echo "  2)  Sync repo to /opt/serversetup"
  echo "  3)  Slack CLI (/usr/local/bin/slack)"
  echo "  4)  Slack boot notification (systemd)"
  echo "  5)  Deploy scripts (deploythis + poll + sudoers)"
  echo "  6)  Devlog (Google Sheets logging)"
  echo "  7)  Session log (AI command summaries)"
  echo "  8)  Root bash scripts (/root/bash)"
  echo ""
  echo "  0)  Back"
  echo ""

  read -rp "  Choose [0-8]: " dt_choice
  echo ""

  case "$dt_choice" in
    1) tooling_install_all ;;
    2) _tooling_sync_repo ;;
    3) tooling_install_slack ;;
    4) tooling_install_slack_boot ;;
    5) tooling_install_deploy_scripts ;;
    6) tooling_install_devlog ;;
    7) tooling_install_sessionlog ;;
    8) tooling_install_root_bash ;;
    0) return 0 ;;
    *) echo "  Invalid option: ${dt_choice}" ;;
  esac
}
