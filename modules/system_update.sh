#!/usr/bin/env bash
# Module: system_update.sh
# Runs apt update & full upgrade, then installs essential packages (skipping any already present)

set -e

ESSENTIAL_PACKAGES=(
  curl
  wget
  git
  htop
  unzip
  zip
  jq
  tree
  ncdu
  tmux
  fail2ban
  software-properties-common
  ca-certificates
  gnupg
  lsb-release
)

system_update() {
  echo "==> Running system update & upgrade..."
  apt-get update -y
  apt-get upgrade -y
  echo "==> System update & upgrade complete."

  echo "==> Checking essential packages..."
  local to_install=()
  for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      echo "  [ok] $pkg"
    else
      echo "  [missing] $pkg"
      to_install+=("$pkg")
    fi
  done

  if [ ${#to_install[@]} -eq 0 ]; then
    echo "==> All essential packages already installed."
  else
    echo "==> Installing: ${to_install[*]}"
    apt-get install -y "${to_install[@]}"
    echo "==> Essential packages installed."
  fi

  # Warn if reboot is needed (kernel upgrade etc.)
  if [ -f /var/run/reboot-required ]; then
    echo "  *** NOTICE: A reboot is required to complete updates ***"
  fi
}
