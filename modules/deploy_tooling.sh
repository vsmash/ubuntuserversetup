#!/usr/bin/env bash
# Module: deploy_tooling.sh
# Deploys custom tooling to the server:
#   - Clones/copies repo to /opt/serversetup
#   - Symlinks slack.sh -> /usr/local/bin/slack
#   - Symlinks slack_boot.sh -> /usr/local/sbin/slack_boot
#   - Symlinks deploythis.sh -> /usr/local/sbin/deploythis.sh
#   - Symlinks deploy_poll.sh -> /usr/local/sbin/deploy_poll.sh
#   - Installs systemd service for slack_boot on boot
#   - Configures passwordless sudo for ubuntu to run deploythis.sh
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
  chmod +x "${REPO_DIR}/slack.sh"
  if [ -L /usr/local/bin/slack ] && [ "$(readlink -f /usr/local/bin/slack)" = "${REPO_DIR}/slack.sh" ]; then
    echo "  /usr/local/bin/slack symlink already correct."
  else
    echo "  Symlinking slack.sh -> /usr/local/bin/slack..."
    ln -sf "${REPO_DIR}/slack.sh" /usr/local/bin/slack
  fi

  # --- slack_boot.sh -> /usr/local/sbin/slack_boot ---
  chmod +x "${REPO_DIR}/slack_boot.sh"
  if [ -L /usr/local/sbin/slack_boot ] && [ "$(readlink -f /usr/local/sbin/slack_boot)" = "${REPO_DIR}/slack_boot.sh" ]; then
    echo "  /usr/local/sbin/slack_boot symlink already correct."
  else
    echo "  Symlinking slack_boot.sh -> /usr/local/sbin/slack_boot..."
    ln -sf "${REPO_DIR}/slack_boot.sh" /usr/local/sbin/slack_boot
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

  # --- deploythis.sh -> /usr/local/sbin/deploythis.sh ---
  chmod +x "${REPO_DIR}/deployments/deploythis.sh"
  if [ -L /usr/local/sbin/deploythis.sh ] && [ "$(readlink -f /usr/local/sbin/deploythis.sh)" = "${REPO_DIR}/deployments/deploythis.sh" ]; then
    echo "  /usr/local/sbin/deploythis.sh symlink already correct."
  else
    echo "  Symlinking deploythis.sh -> /usr/local/sbin/deploythis.sh..."
    ln -sf "${REPO_DIR}/deployments/deploythis.sh" /usr/local/sbin/deploythis.sh
  fi

  # --- deploy_poll.sh -> /usr/local/sbin/deploy_poll.sh ---
  chmod +x "${REPO_DIR}/deployments/deploy_poll.sh"
  if [ -L /usr/local/sbin/deploy_poll.sh ] && [ "$(readlink -f /usr/local/sbin/deploy_poll.sh)" = "${REPO_DIR}/deployments/deploy_poll.sh" ]; then
    echo "  /usr/local/sbin/deploy_poll.sh symlink already correct."
  else
    echo "  Symlinking deploy_poll.sh -> /usr/local/sbin/deploy_poll.sh..."
    ln -sf "${REPO_DIR}/deployments/deploy_poll.sh" /usr/local/sbin/deploy_poll.sh
  fi

  # --- Ensure /etc/deployments directory exists for site configs ---
  mkdir -p /etc/deployments

  # --- Passwordless sudo for ubuntu to run deploythis.sh ---
  local sudoers_file="/etc/sudoers.d/deploy"
  local sudoers_rule="ubuntu ALL=(root) NOPASSWD: /usr/local/sbin/deploythis.sh"
  if [ -f "$sudoers_file" ] && grep -qF "$sudoers_rule" "$sudoers_file"; then
    echo "  [ok] sudoers rule for deploy already in place."
  else
    echo "  Configuring passwordless sudo for ubuntu -> deploythis.sh..."
    echo "$sudoers_rule" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    # Validate the sudoers file
    if visudo -cf "$sudoers_file" >/dev/null 2>&1; then
      echo "  sudoers rule installed and validated."
    else
      echo "  error: sudoers file failed validation, removing." >&2
      rm -f "$sudoers_file"
      return 1
    fi
  fi

  echo "==> Custom tooling deployed."
}
