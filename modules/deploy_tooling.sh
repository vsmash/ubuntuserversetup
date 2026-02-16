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
  
  # Ensure all users can read and execute scripts
  chmod -R a+rX "$REPO_DIR"
}

# ---- Helper: symlink with idempotency ----
_tooling_symlink() {
  local src="$1" dest="$2"
  chmod a+rx "$src"
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
  chmod 755 /etc/serversetup/credentials

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

  # Install profile.d hook
  local profile_hook="/etc/profile.d/sessionlog.sh"
  if [ -f "$profile_hook" ]; then
    echo "  [ok] $profile_hook already exists."
    read -rp "  Overwrite? [y/N]: " overwrite_sl
    if [[ ! "$overwrite_sl" =~ ^[Yy]$ ]]; then
      echo "  Keeping existing $profile_hook."
      return 0
    fi
  fi

  read -rp "  1min.ai API key (required for AI summaries): " sl_key
  if [ -z "$sl_key" ]; then
    echo "  Warning: No API key provided. Session log AI summaries will not work."
    echo "  Edit $profile_hook and set SESSIONLOG_ONEMIN_API_KEY later."
  fi

  read -rp "  Autocapture on login? [Y/n]: " sl_auto_yn
  local sl_auto="true"
  [[ "$sl_auto_yn" =~ ^[Nn]$ ]] && sl_auto="false"

  read -rp "  Capture command output? [Y/n]: " sl_output_yn
  local sl_output="true"
  [[ "$sl_output_yn" =~ ^[Nn]$ ]] && sl_output="false"

  read -rp "  Flush interval in minutes [30]: " sl_interval
  sl_interval="${sl_interval:-30}"

  echo "  Writing $profile_hook..."
  cat > "$profile_hook" <<PROFEOF
# Session log — AI-powered command summaries via devlog
export SESSIONLOG_ONEMIN_API_KEY="${sl_key}"
export SESSIONLOG_AUTOCAPTURE=${sl_auto}
export SESSIONLOG_CAPTURE_OUTPUT=${sl_output}
export SESSIONLOG_INTERVAL=${sl_interval}
source /opt/sessionlog/sessionlog.sh
PROFEOF
  chmod 644 "$profile_hook"
  echo "  Session log installed. Will activate on next login."
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
