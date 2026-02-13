#!/usr/bin/env bash

# This script is used to set up the environment for a unbuntu server
# It will install the necessary packages and configure the server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

# --- Module: System update & essential packages ---
source "${SCRIPT_DIR}/modules/system_update.sh"
system_update

# --- Module: Populate /etc/app.env interactively ---
source "${SCRIPT_DIR}/modules/setup_env.sh"
setup_env

source "/etc/app.env"
# --- Module: Firewall lockdown to SYSOP_IP ---
source "${SCRIPT_DIR}/modules/firewall_lockdown.sh"
lockdown_firewall_to_sysop_ip

# --- Module: Deploy custom tooling (slack, slack_boot, app.env, systemd) ---
source "${SCRIPT_DIR}/modules/deploy_tooling.sh"
deploy_tooling

# --- Module: Certbot + Cloudflare DNS plugin ---
source "${SCRIPT_DIR}/modules/certbot.sh"
setup_certbot

echo "Locking down SSH to key authentication only..."
# --- Module: Lock down SSH to key authentication only ---
source "${SCRIPT_DIR}/modules/ssh_lockdown.sh"
set_ssh_key_auth_only