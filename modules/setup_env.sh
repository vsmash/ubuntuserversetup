#!/usr/bin/env bash
# Module: setup_env.sh
# Interactively populates /etc/app.env by prompting for each variable
# defined in app.env.example. If user leaves input empty, the value is set to empty.
# Skips if /etc/app.env already exists (offers to overwrite).

set -e

ENV_FILE="/etc/app.env"
SCRIPT_DIR_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Use /opt/serversetup if it exists, otherwise fall back to the source repo
if [ -d "/opt/serversetup" ]; then
  REPO_DIR="/opt/serversetup"
else
  REPO_DIR="$SCRIPT_DIR_ENV"
fi
EXAMPLE_FILE="${REPO_DIR}/app.env.example"

setup_env() {
  echo "==> Setting up ${ENV_FILE}..."

  if [ -f "$ENV_FILE" ]; then
    echo "  ${ENV_FILE} already exists."
    read -rp "  Overwrite? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      echo "  Keeping existing ${ENV_FILE}."
      # Still source and validate
      set -a
      source "$ENV_FILE"
      set +a
      
      # Validate SYSOP_IP (optional)
      if [ -z "${SYSOP_IP:-}" ]; then
        echo "  ⚠ WARNING: SYSOP_IP is empty. Firewall lockdown will be skipped."
      elif ! [[ "$SYSOP_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  ⚠ WARNING: SYSOP_IP '${SYSOP_IP}' is not a valid IPv4 address."
        echo "  Firewall lockdown will be skipped."
      else
        echo "  ✓ SYSOP_IP validated: ${SYSOP_IP}"
      fi
      
      return 0
    fi
  fi

  if [ ! -f "$EXAMPLE_FILE" ]; then
    echo "  error: ${EXAMPLE_FILE} not found." >&2
    return 1
  fi

  echo ""
  echo "  Enter values for each variable (leave empty for blank):"
  echo "  -------------------------------------------------------"

  # Clear the output file
  > "$ENV_FILE"

  # Use file descriptor 3 to avoid stdin conflict with read prompts
  while IFS= read -r line <&3; do
    # Skip empty lines and comments — write them directly
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      echo "$line" >> "$ENV_FILE"
      continue
    fi

    # Parse KEY="VALUE" or KEY=VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local default_val="${BASH_REMATCH[2]}"
      
      # Strip surrounding quotes from default (handles both single and double quotes)
      if [[ "$default_val" =~ ^\"(.*)\"$ ]] || [[ "$default_val" =~ ^\'(.*)\'$ ]]; then
        default_val="${BASH_REMATCH[1]}"
      fi

      # Read from stdin (terminal), not from file descriptor 3
      read -rp "  ${key} [${default_val}]: " user_val </dev/tty

      if [ -n "$user_val" ]; then
        echo "${key}=\"${user_val}\"" >> "$ENV_FILE"
      else
        echo "${key}=\"\"" >> "$ENV_FILE"
      fi
    else
      # Unknown format, pass through
      echo "$line" >> "$ENV_FILE"
    fi
  done 3< "$EXAMPLE_FILE"
  chmod 644 "$ENV_FILE"

  echo ""
  echo "  ${ENV_FILE} written (chmod 644 — readable by all users)."

  # Source it so subsequent modules can use the values
  set -a
  source "$ENV_FILE"
  set +a

  # --- Validate SYSOP_IP (optional) ---
  if [ -z "${SYSOP_IP:-}" ]; then
    echo ""
    echo "  ⚠ WARNING: SYSOP_IP is empty. Firewall lockdown will be skipped."
  elif ! [[ "$SYSOP_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ""
    echo "  ⚠ WARNING: SYSOP_IP '${SYSOP_IP}' is not a valid IPv4 address."
    echo "  Firewall lockdown will be skipped."
  else
    echo ""
    echo "  ✓ SYSOP_IP validated: ${SYSOP_IP}"
  fi
  
  echo "==> Environment setup complete."
}

# Verify the deploy user (APP_USER, default "ubuntu") exists. The deploy tooling,
# devlog, and site management all chown/sudo/crontab against it, so it must exist
# before those run. Offer to create it — nothing else in the repo does.
ensure_app_user() {
  local user="${APP_USER:-ubuntu}"

  if id "$user" &>/dev/null; then
    echo "  ✓ Deploy user '${user}' exists."
    return 0
  fi

  echo ""
  echo "  ⚠ Deploy user '${user}' does NOT exist."
  echo "    Deploy tooling (5), devlog, and site management (8) all run as this user."
  read -rp "  Create user '${user}' now? [y/N]: " create_user
  if [[ ! "$create_user" =~ ^[Yy]$ ]]; then
    echo "  Skipped. Create it before running deploy tooling (5) or site management (8)."
    return 0
  fi

  adduser --disabled-password --gecos "" "$user"

  # sudo: admin group. www-data: deploys chown webroot to ubuntu:www-data
  # ([deployments/deploythis.sh] apply_perms), so the user should be in it.
  # www-data isn't guaranteed on a minimal install — add only if present.
  if getent group www-data >/dev/null; then
    usermod -aG sudo,www-data "$user"
    echo "  User '${user}' created, added to groups: sudo, www-data."
  else
    usermod -aG sudo "$user"
    echo "  User '${user}' created, added to group: sudo."
    echo "    (www-data group not present yet — add later: usermod -aG www-data ${user})"
  fi

  install -d -m 700 -o "$user" -g "$user" "/home/${user}/.ssh"
  echo "  ⚠ Add your SSH public key to /home/${user}/.ssh/authorized_keys before SSH lockdown (7)."
  echo "  ⚠ '${user}' has NO password set. The deploy automation still works (the targeted"
  echo "    /etc/sudoers.d/deploy NOPASSWD rule is created by tooling install), but"
  echo "    '${user}' cannot run 'sudo' interactively. To enable that, either:"
  echo "      echo '${user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-${user}-user && chmod 440 /etc/sudoers.d/90-${user}-user"
  echo "    or set a password with:  passwd ${user}"
}
