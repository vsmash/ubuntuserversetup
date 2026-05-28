#!/usr/bin/env bash

#if SYSOP_IP has a proper ip value, lock down firewall to only allow that IP
# SYSOP_IP is expected to be set in /etc/app.env


lockdown_firewall_to_ip() {
  local allowed_ip="$1"
  if [[ -z "$allowed_ip" ]]; then
    echo "Usage: lockdown_firewall_to_ip <ip-address>"
    return 1
  fi

  # Check if UFW is already active and locked down to only this IP
  if ufw status | grep -q 'Status: active'; then
    local current_rules
    current_rules="$(ufw status numbered | grep -oP '\d+\.\d+\.\d+\.\d+' | sort -u)"
    local rule_count
    rule_count="$(echo "$current_rules" | grep -c . || true)"

    if [[ "$rule_count" -eq 1 ]] && [[ "$current_rules" == "$allowed_ip" ]]; then
      echo "UFW already locked down to ${allowed_ip}. No changes needed."
      ufw status verbose
      return 0
    fi
  fi

  echo "Resetting UFW rules..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$allowed_ip"
  ufw --force enable
  echo "UFW is now locked down to allow only: $allowed_ip"
  ufw status verbose
}


lockdown_firewall_to_sysop_ip() {
  # SYSOP_IP must be a valid IPv4 address (app.env.example ships a placeholder).
  if ! [[ "${SYSOP_IP:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "SYSOP_IP ('${SYSOP_IP:-}') is not a valid IPv4 address. Skipping firewall lockdown."
    return 0
  fi

  # Ensure ufw is installed.
  if ! command -v ufw >/dev/null; then
    echo "UFW is not installed."
    read -rp "  Install ufw now? [y/N]: " install_ufw
    if [[ "$install_ufw" =~ ^[Yy]$ ]]; then
      apt-get install -y ufw || { echo "  Failed to install ufw. Skipping firewall lockdown."; return 0; }
    else
      echo "  Skipping firewall lockdown."
      return 0
    fi
  fi

  # If ufw is inactive, enabling it locked to SYSOP_IP blocks all other incoming
  # traffic — confirm first to avoid locking out a session from another IP.
  if ! ufw status | grep -q 'Status: active'; then
    echo "  ⚠ Enabling UFW locked to ${SYSOP_IP} will block ALL other incoming traffic."
    echo "    Make sure you are connecting from ${SYSOP_IP} or you may lock yourself out."
    read -rp "  Enable and lock down now? [y/N]: " enable_ufw
    if [[ ! "$enable_ufw" =~ ^[Yy]$ ]]; then
      echo "  Skipping firewall lockdown."
      return 0
    fi
  fi

  lockdown_firewall_to_ip "$SYSOP_IP"
}