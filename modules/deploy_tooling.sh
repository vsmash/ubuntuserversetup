#!/usr/bin/env bash
# Module: deploy_tooling.sh
# Deploys custom tooling to the server:
#   - Clones/copies repo to /opt/serversetup
#   - Symlinks slack.sh -> /usr/local/bin/slack
#   - Symlinks slack_boot.sh -> /usr/local/sbin/slack_boot
#   - Installs systemd service for slack_boot on boot
# Note: /etc/app.env is handled by setup_env.sh (runs earlier)

set -e

REPO_DIR="/opt/serversetup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

deploy_tooling() {
  echo "==> Deploying custom tooling..."

  # --- Repo directory (always sync to pick up updates) ---
  if [ ! -d "$REPO_DIR" ]; then
    echo "  Copying repo to ${REPO_DIR}..."
    cp -a "$SCRIPT_DIR" "$REPO_DIR"
  else
    echo "  Updating ${REPO_DIR} from source..."
    rsync -a --exclude='.git' --exclude='.env.*' "$SCRIPT_DIR/" "$REPO_DIR/"
  fi

  # --- slack.sh -> /usr/local/bin/slack ---
  if [ -L /usr/local/bin/slack ] && [ "$(readlink -f /usr/local/bin/slack)" = "${REPO_DIR}/slack.sh" ]; then
    echo "  /usr/local/bin/slack symlink already correct."
  else
    echo "  Symlinking slack.sh -> /usr/local/bin/slack..."
    ln -sf "${REPO_DIR}/slack.sh" /usr/local/bin/slack
    chmod +x "${REPO_DIR}/slack.sh"
  fi

  # --- slack_boot.sh -> /usr/local/sbin/slack_boot ---
  if [ -L /usr/local/sbin/slack_boot ] && [ "$(readlink -f /usr/local/sbin/slack_boot)" = "${REPO_DIR}/slack_boot.sh" ]; then
    echo "  /usr/local/sbin/slack_boot symlink already correct."
  else
    echo "  Symlinking slack_boot.sh -> /usr/local/sbin/slack_boot..."
    ln -sf "${REPO_DIR}/slack_boot.sh" /usr/local/sbin/slack_boot
    chmod +x "${REPO_DIR}/slack_boot.sh"
  fi

  # --- systemd service for slack_boot ---
  local service_file="/etc/systemd/system/slack-boot.service"
  if [ -f "$service_file" ]; then
    echo "  slack-boot.service already installed."
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

  echo "==> Custom tooling deployed."
}
