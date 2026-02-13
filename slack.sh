#!/usr/bin/env bash
####################################################################################
# Slack Bash console script for sending messages.
####################################################################################
# Installation
#    $ curl -s https://gist.githubusercontent.com/andkirby/67a774513215d7ba06384186dd441d9e/raw --output /usr/bin/slack
#    $ chmod +x /usr/bin/slack
####################################################################################
# USAGE
# Send message to slack (channel is determined by the webhook endpoint)
#   Send a message using the default webhook:
#     $ slack 'Some message here.'
#
#   Send a message using a specific webhook:
#     $ slack --webhook=mark MESSAGE
#     $ slack --webhook=monitor MESSAGE
#
# VARIABLES
#
# Please declare environment variables:
#   - APP_SLACK_WEBHOOK (default webhook)
#   - APP_SLACK_MARK_WEBHOOK (override for mark)
#   - APP_SLACK_MONITOR_WEBHOOK (override for MONITOR)
#   - APP_SLACK_USERNAME (optional)
#   - APP_SLACK_ICON_EMOJI (optional)
# You may also declare them in ~/.slackrc file.
####################################################################################

set -o pipefail
set -o errexit
set -o nounset
#set -o xtrace

set -a
source /etc/app.env
set +a

init_params() {
  # Parse webhook option if provided
  webhook_type="default"
  if [[ "${1:-}" =~ ^--webhook=(.+)$ ]]; then
    webhook_type="${BASH_REMATCH[1]}"
    shift
  fi

  # Select the appropriate webhook based on the type
  case "${webhook_type}" in
    mark)
      APP_SLACK_WEBHOOK="${APP_SLACK_MARK_WEBHOOK:-}"
      ;;
    monitor)
      APP_SLACK_WEBHOOK="${APP_SLACK_MONITOR_WEBHOOK:-}"
      ;;
    default)
      APP_SLACK_WEBHOOK="${APP_SLACK_WEBHOOK:-}"
      ;;
    *)
      echo "error: Unknown webhook type: ${webhook_type}" > /dev/stderr
      echo 'note: Valid options are: default, mark, monitor' > /dev/stderr
      exit 4
      ;;
  esac

  # you may declare ENV vars in /etc/profile.d/slack.sh
  if [ -z "${APP_SLACK_WEBHOOK:-}" ]; then
    echo 'error: Please configure Slack environment variable: ' > /dev/stderr
    if [ "${webhook_type}" == "default" ]; then
      echo '  APP_SLACK_WEBHOOK' > /dev/stderr
    else
      echo "  APP_SLACK_${webhook_type^^}_WEBHOOK" > /dev/stderr
    fi
    exit 2
  fi

  APP_SLACK_USERNAME=${APP_SLACK_USERNAME:-$(hostname | cut -d '.' -f 1)}

  APP_SLACK_ICON_EMOJI=${APP_SLACK_ICON_EMOJI:-:slack:}
  if [ -z "${1:-}" ]; then
    echo 'error: Missed required arguments.' > /dev/stderr
    echo 'note: Please follow this example:' > /dev/stderr
    echo '  $ slack.sh Some message here. ' > /dev/stderr
    exit 3
  fi

  slack_message=${@}
}


send_message() {
  echo 'Sending message...'
  local response
  local exit_code
  
  response=$(curl --silent --show-error --write-out "\n%{http_code}" --data-urlencode \
    "$(printf 'payload={"text": "%s", "username": "%s", "link_names": "true", "icon_emoji": "%s" }' \
        ":${LOGO}: (Webserver) ${slack_message}" \
        "${APP_SLACK_USERNAME}" \
        "${APP_SLACK_ICON_EMOJI}" \
    )" \
    "${APP_SLACK_WEBHOOK}" 2>&1) || exit_code=$?
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')
  
  if [ "${exit_code:-0}" -ne 0 ]; then
    echo "error: curl failed with exit code ${exit_code}" >&2
    echo "$response" >&2
    return ${exit_code}
  elif [ "$http_code" != "200" ]; then
    echo "error: Slack returned HTTP $http_code" >&2
    echo "$body" >&2
    return 1
  else
    echo "Message sent successfully (HTTP $http_code)"
  fi
}

slack() {
  # Set magic variables for current file & dir
  __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  __file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
  readonly __dir __file

  cd ${__dir}

  if [ -f $(cd; pwd)/.slackrc ]; then
    . $(cd; pwd)/.slackrc
  fi

  init_params ${@}
  send_message
}

if [ "${BASH_SOURCE[0]:-}" != "${0}" ]; then
  export -f slack
else
  slack ${@}
  exit $?
fi
