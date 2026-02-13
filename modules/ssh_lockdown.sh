#!/usr/bin/env bash

set_ssh_key_auth_only() {
  local sshd_config="/etc/ssh/sshd_config"
  local changed=0

  # Ensure PasswordAuthentication is set to no
  if grep -q '^PasswordAuthentication no$' "$sshd_config"; then
    echo "  [ok] PasswordAuthentication already set to no."
  elif grep -q '^PasswordAuthentication' "$sshd_config"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    changed=1
  else
    echo 'PasswordAuthentication no' >> "$sshd_config"
    changed=1
  fi

  # Only reload SSH if config was changed
  if [ "$changed" -eq 1 ]; then
    if systemctl list-units --type=service | grep -qE 'sshd?\.service'; then
      systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null
      systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null
    else
      systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null
    fi
    echo "SSH config updated and service reloaded."
  fi

  echo "SSH is now set to key authentication only."
}

change_ssh_port() {
  local sshd_config="/etc/ssh/sshd_config"
  local current_port
  current_port=$(grep -E '^Port ' "$sshd_config" | awk '{print $2}' | head -n1)
  echo -n "Enter new SSH port (leave blank to keep current: ${current_port:-22}): "
  read -r new_port
  if [[ -z "$new_port" ]]; then
    echo "SSH port unchanged."
    return 0
  fi
  if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
    echo "Invalid port number."
    return 1
  fi
  if ss -tuln | grep -q ":$new_port[[:space:]]"; then
    echo "Port $new_port is already in use."
    return 1
  fi
  if grep -qE '^Port ' "$sshd_config"; then
    sed -i "s/^Port .*/Port $new_port/" "$sshd_config"
  else
    echo "Port $new_port" >> "$sshd_config"
  fi
  if systemctl list-units --type=service | grep -qE 'sshd?\.service'; then
    systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null
  else
    systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null
  fi
}