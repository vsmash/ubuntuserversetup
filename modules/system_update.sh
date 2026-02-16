#!/usr/bin/env bash
# Module: system_update.sh
# Runs apt update & full upgrade, then installs essential packages (skipping any already present)

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
  if ! apt-get update -y; then
    echo "  [warning] apt-get update failed, but continuing..."
  fi
  if ! apt-get upgrade -y; then
    echo "  [warning] apt-get upgrade failed, but continuing..."
  fi
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
    local failed_packages=()
    
    # Try installing all packages together first
    if ! apt-get install -y "${to_install[@]}" 2>/dev/null; then
      echo "  [warning] Batch install failed. Trying packages individually..."
      
      # Try each package individually
      for pkg in "${to_install[@]}"; do
        echo "  Installing $pkg..."
        if apt-get install -y "$pkg" 2>/dev/null; then
          echo "    [ok] $pkg installed"
        else
          echo "    [failed] $pkg could not be installed"
          failed_packages+=("$pkg")
        fi
      done
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo ""
      echo "  *** WARNING: Some packages failed to install: ${failed_packages[*]} ***"
      echo "  This may be due to platform incompatibility (e.g., Raspberry Pi)."
      read -rp "  Continue anyway? [Y/n]: " continue_yn
      if [[ "$continue_yn" =~ ^[Nn]$ ]]; then
        echo "  Setup aborted by user."
        return 1
      fi
      echo "  Continuing with available packages..."
    else
      echo "==> Essential packages installed."
    fi
  fi

  # Warn if reboot is needed (kernel upgrade etc.)
  if [ -f /var/run/reboot-required ]; then
    echo "  *** NOTICE: A reboot is required to complete updates ***"
  fi
}
