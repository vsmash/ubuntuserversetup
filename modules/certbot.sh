#!/usr/bin/env bash
# Module: certbot.sh
# Installs certbot via snap + Cloudflare DNS plugin
# Copies cloudflare credentials template if not already present

set -e

REPO_DIR="/opt/serversetup"
CF_CREDS="/etc/letsencrypt/cloudflare.ini"

setup_certbot() {
  echo "==> Setting up Certbot + Cloudflare DNS plugin..."

  # --- Ensure snapd is installed and ready ---
  if ! command -v snap &>/dev/null; then
    echo "  Installing snapd..."
    apt-get install -y snapd
  else
    echo "  [ok] snapd"
  fi

  # Ensure snapd core is up to date
  snap install core 2>/dev/null || true
  snap refresh core 2>/dev/null || true

  # --- Certbot via snap ---
  if snap list certbot &>/dev/null; then
    echo "  [ok] certbot (snap)"
  else
    echo "  Installing certbot via snap..."
    snap install --classic certbot
  fi

  # Ensure certbot command is available in PATH
  if [ ! -L /usr/bin/certbot ] && [ ! -f /usr/bin/certbot ]; then
    ln -sf /snap/bin/certbot /usr/bin/certbot
  fi

  # --- Cloudflare DNS plugin ---
  if snap list certbot-dns-cloudflare &>/dev/null; then
    echo "  [ok] certbot-dns-cloudflare (snap)"
  else
    echo "  Installing certbot-dns-cloudflare plugin..."
    snap set certbot trust-plugin-with-root=ok
    snap install certbot-dns-cloudflare
  fi

  # --- Cloudflare credentials file (copy, not symlink — secrets stay out of repo) ---
  if [ -f "$CF_CREDS" ]; then
    echo "  [ok] ${CF_CREDS} already exists."
  else
    echo "  Copying cloudflare.ini.example -> ${CF_CREDS}..."
    mkdir -p /etc/letsencrypt
    cp "${REPO_DIR}/cloudflare.ini.example" "$CF_CREDS"
    chmod 600 "$CF_CREDS"
    echo "  *** IMPORTANT: Edit ${CF_CREDS} with your actual Cloudflare API token ***"
  fi

  echo "==> Certbot + Cloudflare DNS plugin ready."
}
