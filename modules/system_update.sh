#!/usr/bin/env bash
# Module: system_update.sh
# Runs apt update & full upgrade, then installs essential packages (skipping any already present)

# Core utilities needed for basic server operation
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
  ca-certificates
  gnupg
  lsb-release
)

# Optional packages that may conflict with existing setups
# These are installed separately with user confirmation
OPTIONAL_PACKAGES=(
  fail2ban
  software-properties-common
)

system_update() {
  echo "==> System update & upgrade"
  echo "  ⚠ WARNING: Updating packages may break existing configurations on production servers."
  read -rp "  Run apt-get update? [y/N]: " do_update
  if [[ "$do_update" =~ ^[Yy]$ ]]; then
    if ! apt-get update -y; then
      echo "  [warning] apt-get update failed, but continuing..."
    fi
  else
    echo "  [skipped] apt-get update"
  fi
  
  read -rp "  Run apt-get upgrade? [y/N]: " do_upgrade
  if [[ "$do_upgrade" =~ ^[Yy]$ ]]; then
    if ! apt-get upgrade -y; then
      echo "  [warning] apt-get upgrade failed, but continuing..."
    fi
  else
    echo "  [skipped] apt-get upgrade"
  fi

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

  # Prompt for optional packages
  echo ""
  echo "==> Optional packages (may conflict with existing setups):"
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      echo "  [ok] $pkg (already installed)"
    else
      read -rp "  Install $pkg? [y/N]: " install_opt
      if [[ "$install_opt" =~ ^[Yy]$ ]]; then
        if apt-get install -y "$pkg" 2>/dev/null; then
          echo "    [ok] $pkg installed"
        else
          echo "    [failed] $pkg could not be installed"
        fi
      else
        echo "    [skipped] $pkg"
      fi
    fi
  done

  # Warn if reboot is needed (kernel upgrade etc.)
  if [ -f /var/run/reboot-required ]; then
    echo ""
    echo "  *** NOTICE: A reboot is required to complete updates ***"
  fi
}
