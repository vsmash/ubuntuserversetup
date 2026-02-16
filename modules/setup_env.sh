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
      if [ -z "${SYSOP_IP:-}" ] || ! [[ "$SYSOP_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  error: Existing ${ENV_FILE} has missing or invalid SYSOP_IP." >&2
        echo "  Re-run and choose to overwrite, or edit ${ENV_FILE} manually." >&2
        exit 1
      fi
      echo "  SYSOP_IP validated: ${SYSOP_IP}"
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

  # --- Validate required variables ---
  if [ -z "${SYSOP_IP:-}" ]; then
    echo ""
    echo "  error: SYSOP_IP is required but was left empty." >&2
    echo "  This IP is used to lock down the firewall. Cannot continue without it." >&2
    echo "  Re-run this script and provide a valid IP for SYSOP_IP." >&2
    exit 1
  fi

  # Basic IPv4 format check
  if ! [[ "$SYSOP_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ""
    echo "  error: SYSOP_IP '${SYSOP_IP}' does not look like a valid IPv4 address." >&2
    echo "  Re-run this script and provide a valid IP for SYSOP_IP." >&2
    exit 1
  fi

  echo ""
  echo "  SYSOP_IP validated: ${SYSOP_IP}"
  echo "==> Environment setup complete."
}
