#!/usr/bin/env bash

#if SYSOP_IP has a proper ip value, lock down firewall to only allow that IP
# SYSOP_IP is expected to be set in /etc/app.env


lockdown_firewall_to_ip() {
  local allowed_ip="$1"
  if [[ -z "$allowed_ip" ]]; then
    echo "Usage: lockdown_firewall_to_ip <ip-address>"
    return 1
  fi
  echo "Resetting UFW rules..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$allowed_ip"
  ufw enable
  echo "UFW is now locked down to allow only: $allowed_ip"
  ufw status verbose
}


lockdown_firewall_to_sysop_ip() {
  if [[ -z "$SYSOP_IP" || "$SYSOP_IP" == "your.ip.address.here" ]]; then
    echo "SYSOP_IP is not set to a valid IP address. Skipping firewall lockdown."
    return 1
  fi
  # Add firewall rules to allow only SYSOP_IP
  if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    lockdown_firewall_to_ip "$SYSOP_IP"
  else
    echo "UFW is not active or not installed. Skipping firewall lockdown."
  fi
}