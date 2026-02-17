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

# --- Source all modules ---
source "${SCRIPT_DIR}/modules/system_update.sh"
source "${SCRIPT_DIR}/modules/setup_env.sh"
source "${SCRIPT_DIR}/modules/firewall_lockdown.sh"
source "${SCRIPT_DIR}/modules/deploy_tooling.sh"
source "${SCRIPT_DIR}/modules/certbot.sh"
source "${SCRIPT_DIR}/modules/ssh_lockdown.sh"
source "${SCRIPT_DIR}/modules/manage_sites.sh"

# --- Load /etc/app.env if it exists (needed for firewall etc.) ---
load_app_env() {
  if [ -f /etc/app.env ]; then
    set -a
    source /etc/app.env
    set +a
  fi
}

# --- Run all modules in order (original behaviour) ---
run_all() {
  echo ""
  echo "========================================="
  echo "  Running FULL server setup..."
  echo "========================================="
  echo ""

  system_update

  setup_env
  load_app_env

  echo ""
  echo "  ⚠  WARNING: The next steps will lock down the firewall and SSH."
  echo "  Only proceed on a FRESH server. Press Ctrl+C to abort."
  echo ""
  read -rp "  Continue with full setup? [y/N]: " confirm_all
  if [[ "$confirm_all" != "y" && "$confirm_all" != "Y" ]]; then
    echo "  Aborted."
    return 0
  fi

  lockdown_firewall_to_sysop_ip

  tooling_install_all

  setup_certbot

  echo "Locking down SSH to key authentication only..."
  set_ssh_key_auth_only

  echo ""
  echo "========================================="
  echo "  Full server setup complete."
  echo "========================================="
}

# --- Interactive menu ---
show_menu() {
  echo ""
  echo "========================================="
  echo "  Server Setup — Module Menu"
  echo "========================================="
  echo ""
  echo "  1)  Run full setup (all modules in order)"
  echo "  2)  System update & essential packages"
  echo "  3)  Setup environment (/etc/app.env)"
  echo "  4)  Firewall lockdown (SYSOP_IP) ⚠ DANGEROUS on existing servers"
  echo "  5)  Deploy tooling (select components)"
  echo "  6)  Certbot + Cloudflare DNS"
  echo "  7)  SSH lockdown (key auth only) ⚠ DANGEROUS on existing servers"
  echo ""
  echo "  8)  Manage site deployments"
  echo ""
  echo "  0)  Exit"
  echo ""
}

run_menu() {
  while true; do
    show_menu
    read -rp "  Choose an option [0-8]: " choice
    echo ""

    case "$choice" in
      1)
        run_all
        ;;
      2)
        system_update
        ;;
      3)
        setup_env
        load_app_env
        ;;
      4)
        load_app_env
        lockdown_firewall_to_sysop_ip
        ;;
      5)
        load_app_env
        deploy_tooling
        ;;
      6)
        setup_certbot
        ;;
      7)
        echo "Locking down SSH to key authentication only..."
        set_ssh_key_auth_only
        ;;
      8)
        manage_sites
        ;;
      0)
        echo "Exiting."
        exit 0
        ;;
      *)
        echo "  Invalid option: ${choice}"
        ;;
    esac

    echo ""
    read -rp "  Press Enter to return to menu..." _
  done
}

# --- Entry point: --all flag runs everything, otherwise show menu ---
if [[ "${1:-}" == "--all" ]]; then
  run_all
else
  run_menu
fi