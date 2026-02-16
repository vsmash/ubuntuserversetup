#!/bin/bash

# ---------------------------------------------------------------
# SESSION LOG - Standalone terminal command capture and AI summary
# goes in /opt/sessionlog/sessionlog.sh
#
# Captures typed commands (input only, not output) during interactive
# shell sessions. Periodically and on session exit, uses AI to
# summarise the work done and sends the description to devlog
# (if available) or echoes to stdout.
#
# This script is fully standalone — no external dependencies required
# beyond curl and a standard bash environment.
#
# Setup (all users, system-wide):
#   sudo cp sessionlog.sh /opt/sessionlog/sessionlog.sh
#   sudo tee /etc/profile.d/sessionlog.sh << 'EOF'
#     export SESSIONLOG_ONEMIN_API_KEY="your-1min-key"
#     export SESSIONLOG_AUTOCAPTURE=true
#     source /opt/sessionlog/sessionlog.sh
#   EOF
#
# Setup (single user):
#   Add to ~/.bashrc:
#     export SESSIONLOG_ONEMIN_API_KEY="your-1min-key"
#     export SESSIONLOG_AUTOCAPTURE=true
#     source /opt/sessionlog/sessionlog.sh
#
#   Captures automatically on login and flushes on logout.
#   Or leave AUTOCAPTURE off and call manually:
#     sessionlog_start           Start capturing commands
#     sessionlog_stop            Stop capturing, flush and summarise
#     sessionlog_status          Show what has been captured so far
#     sessionlog_flush           Manually flush: summarise + log + clear
#
# Environment variables (set BEFORE sourcing):
#   SESSIONLOG_PROVIDER       AI provider: '1min' or 'openai' (default: 1min)
#   SESSIONLOG_ONEMIN_API_KEY 1min.ai API key (primary provider)
#   SESSIONLOG_ONEMIN_MODEL   1min model (default: gpt-4o-mini)
#   SESSIONLOG_OPENAI_TOKEN   OpenAI API key (fallback provider)
#   SESSIONLOG_OPENAI_MODEL   OpenAI model (default: gpt-4o)
#   SESSIONLOG_INTERVAL       Flush interval in minutes (default: 30)
#   SESSIONLOG_AUTOCAPTURE    Set to "true" to auto-start on source (default: false)
#   SESSIONLOG_CAPTURE_OUTPUT Capture terminal output via script (default: false)
#   SESSIONLOG_OUTPUT_LINES   Max output lines sent to AI per flush (default: 50)
#
# Copyright (c) 2024 Velvary Pty Ltd — All rights reserved.
# Author: Mark Pottie <mark@velvary.com.au>
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# Standalone colours (no external dependency)
# ---------------------------------------------------------------
if [[ -t 1 ]]; then
    _SL_GREEN='\033[1;32m'
    _SL_RED='\033[1;31m'
    _SL_YELLOW='\033[1;33m'
    _SL_CYAN='\033[1;36m'
    _SL_OFF='\033[0m'
else
    _SL_GREEN=''
    _SL_RED=''
    _SL_YELLOW=''
    _SL_CYAN=''
    _SL_OFF=''
fi

# ---------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------
_SESSIONLOG_ACTIVE=false
_SESSIONLOG_FILE=""
_SESSIONLOG_LAST_HISTNUM=""
_SESSIONLOG_LAST_FLUSH=""
_SESSIONLOG_PREV_PROMPT_COMMAND=""
_SESSIONLOG_CMD_COUNT=0
_SESSIONLOG_TS_OFFSET=0
_SESSIONLOG_FLUSHING=false

# ---------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------

function sessionlog_start() {
    if [[ "$_SESSIONLOG_ACTIVE" == "true" ]]; then
        echo -e "${_SL_YELLOW}Session log is already running.${_SL_OFF}"
        return 0
    fi

    local onemin_key="${SESSIONLOG_ONEMIN_API_KEY:-}"
    local openai_key="${SESSIONLOG_OPENAI_TOKEN:-${BUMPSCRIPT_OPENAI_TOKEN:-}}"
    if [[ -z "$onemin_key" ]] && [[ -z "$openai_key" ]]; then
        echo -e "${_SL_RED}Error: No AI API key found.${_SL_OFF}"
        echo "Set SESSIONLOG_ONEMIN_API_KEY (preferred) or SESSIONLOG_OPENAI_TOKEN"
        return 1
    fi

    # Output capture: wrap session in script(1) if requested
    if [[ "${SESSIONLOG_CAPTURE_OUTPUT:-false}" == "true" ]] && [[ -z "${_SESSIONLOG_INSIDE_SCRIPT:-}" ]]; then
        if command -v script >/dev/null 2>&1; then
            export _SESSIONLOG_INSIDE_SCRIPT=1
            export _SESSIONLOG_TYPESCRIPT="/tmp/.sessionlog_ts_${USER}_$$"
            > "$_SESSIONLOG_TYPESCRIPT"
            exec script -qf "$_SESSIONLOG_TYPESCRIPT"
        fi
    fi

    _SESSIONLOG_FILE="/tmp/.sessionlog_${USER}_$$"
    _SESSIONLOG_LAST_FLUSH=$(date +%s)
    _SESSIONLOG_LAST_HISTNUM=""
    _SESSIONLOG_CMD_COUNT=0
    _SESSIONLOG_ACTIVE=true

    # Detect shell and set up appropriate hook
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh: use precmd hook
        precmd_functions+=(_sessionlog_capture)
    else
        # bash: use PROMPT_COMMAND
        _SESSIONLOG_PREV_PROMPT_COMMAND="${PROMPT_COMMAND:-}"
        PROMPT_COMMAND="_sessionlog_capture; ${PROMPT_COMMAND:-}"
    fi

    # Set EXIT trap (preserve existing trap)
    local existing_trap
    existing_trap=$(trap -p EXIT | sed "s/trap -- '//;s/' EXIT//")
    if [[ -n "$existing_trap" ]]; then
        trap "$existing_trap; _sessionlog_on_exit" EXIT
    else
        trap '_sessionlog_on_exit' EXIT
    fi

    # echo -e "${_SL_GREEN}Session log started.${_SL_OFF} Capturing commands to ${_SESSIONLOG_FILE}"
    # echo "Commands will be summarised every ${SESSIONLOG_INTERVAL:-30} minutes and on session exit."
}

function sessionlog_stop() {
    if [[ "$_SESSIONLOG_ACTIVE" != "true" ]]; then
        echo -e "${_SL_YELLOW}Session log is not running.${_SL_OFF}"
        return 0
    fi

    _sessionlog_flush_and_log "Session ended"

    # Remove hooks based on shell type
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh: remove from precmd_functions
        precmd_functions=(${precmd_functions[@]:#_sessionlog_capture})
    else
        # bash: restore PROMPT_COMMAND
        PROMPT_COMMAND="${_SESSIONLOG_PREV_PROMPT_COMMAND:-}"
    fi

    _SESSIONLOG_ACTIVE=false
    echo -e "${_SL_GREEN}Session log stopped.${_SL_OFF}"
}

function sessionlog_status() {
    if [[ "$_SESSIONLOG_ACTIVE" != "true" ]]; then
        echo -e "${_SL_YELLOW}Session log is not running.${_SL_OFF}"
        return 0
    fi

    if [[ ! -f "$_SESSIONLOG_FILE" ]] || [[ ! -s "$_SESSIONLOG_FILE" ]]; then
        echo -e "${_SL_YELLOW}No commands captured yet.${_SL_OFF}"
        return 0
    fi

    local count
    count=$(wc -l < "$_SESSIONLOG_FILE" | tr -d ' ')
    local interval="${SESSIONLOG_INTERVAL:-30}"
    local now=$(date +%s)
    local mins_since_flush=$(( (now - _SESSIONLOG_LAST_FLUSH) / 60 ))

    echo -e "${_SL_GREEN}Session log status:${_SL_OFF}"
    echo "  Commands captured: $count"
    echo "  Minutes since last flush: $mins_since_flush / $interval"
    echo "  Session file: $_SESSIONLOG_FILE"
    echo ""
    echo -e "${_SL_CYAN}Captured commands:${_SL_OFF}"
    cat "$_SESSIONLOG_FILE"
}

function sessionlog_flush() {
    if [[ "$_SESSIONLOG_ACTIVE" != "true" ]]; then
        echo -e "${_SL_YELLOW}Session log is not running.${_SL_OFF}"
        return 0
    fi
    _sessionlog_flush_and_log "Manual flush"
}

# ---------------------------------------------------------------
# Internal functions
# ---------------------------------------------------------------

function _sessionlog_capture() {
    [[ "$_SESSIONLOG_ACTIVE" != "true" ]] && return
    [[ "$_SESSIONLOG_FLUSHING" == "true" ]] && return

    # Get the last history entry (shell-specific)
    local hist_line hist_num cmd
    
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh: use fc -l -1 or history array
        hist_line=$(fc -l -1 2>/dev/null)
        hist_num=$(echo "$hist_line" | awk '{print $1}')
        cmd=$(echo "$hist_line" | sed 's/^[ ]*[0-9]*[ ]*//')
    else
        # bash: use history 1
        hist_line=$(history 1)
        hist_num=$(echo "$hist_line" | awk '{print $1}')
        cmd=$(echo "$hist_line" | sed 's/^[ ]*[0-9]*[ ]*//')
    fi

    # Skip if same history number (duplicate prompt redraw)
    if [[ "$hist_num" == "$_SESSIONLOG_LAST_HISTNUM" ]]; then
        _sessionlog_periodic_check
        return
    fi
    _SESSIONLOG_LAST_HISTNUM="$hist_num"

    # Skip empty commands and our own internal functions
    if [[ -z "$cmd" ]] || [[ "$cmd" == _sessionlog_* ]] || [[ "$cmd" == sessionlog_* ]]; then
        return
    fi

    # Append timestamp and command to session file
    echo "$(date +%H:%M:%S) $cmd" >> "$_SESSIONLOG_FILE"
    (( _SESSIONLOG_CMD_COUNT++ ))

    _sessionlog_periodic_check
}

function _sessionlog_periodic_check() {
    local interval_seconds=$(( ${SESSIONLOG_INTERVAL:-30} * 60 ))
    local now=$(date +%s)
    local elapsed=$(( now - _SESSIONLOG_LAST_FLUSH ))

    if [[ $elapsed -ge $interval_seconds ]]; then
        _sessionlog_flush_and_log "Periodic flush (${SESSIONLOG_INTERVAL:-30}min)"
    fi
}

function _sessionlog_on_exit() {
    [[ "$_SESSIONLOG_ACTIVE" != "true" ]] && return
    _sessionlog_flush_and_log "Session exit"
    rm -f "$_SESSIONLOG_FILE" 2>/dev/null
    rm -f "${_SESSIONLOG_TYPESCRIPT:-}" 2>/dev/null
}

function _sessionlog_flush_and_log() {
    local reason="${1:-flush}"

    # Nothing to flush
    if [[ ! -f "$_SESSIONLOG_FILE" ]]; then
        _SESSIONLOG_LAST_FLUSH=$(date +%s)
        return 0
    fi
    
    if [[ ! -s "$_SESSIONLOG_FILE" ]]; then
        _SESSIONLOG_LAST_FLUSH=$(date +%s)
        return 0
    fi

    # Prevent recursive flush (only set after confirming there's data)
    if [[ "$_SESSIONLOG_FLUSHING" == "true" ]]; then
        return 0
    fi
    _SESSIONLOG_FLUSHING=true

    # Atomically move file to temp location to avoid race conditions
    local temp_file="${_SESSIONLOG_FILE}.flush.$$"
    mv "$_SESSIONLOG_FILE" "$temp_file" 2>/dev/null || return 0
    
    # Read from temp file
    local commands cmd_count
    commands=$(<"$temp_file")
    cmd_count=$(echo "$commands" | wc -l | tr -d ' ')
    > "$_SESSIONLOG_FILE"
    _SESSIONLOG_LAST_FLUSH=$(date +%s)
    _SESSIONLOG_CMD_COUNT=0

    # Snapshot terminal output if typescript capture is active
    local output_context=""
    if [[ -n "${_SESSIONLOG_TYPESCRIPT:-}" ]] && [[ -f "$_SESSIONLOG_TYPESCRIPT" ]]; then
        local max_lines="${SESSIONLOG_OUTPUT_LINES:-50}"
        local ts_size
        ts_size=$(stat -c%s "$_SESSIONLOG_TYPESCRIPT" 2>/dev/null || stat -f%z "$_SESSIONLOG_TYPESCRIPT" 2>/dev/null || echo 0)
        if [[ "$ts_size" -gt "$_SESSIONLOG_TS_OFFSET" ]]; then
            output_context=$(tail -c +"$(( _SESSIONLOG_TS_OFFSET + 1 ))" "$_SESSIONLOG_TYPESCRIPT" 2>/dev/null \
                | (col -b 2>/dev/null || cat) \
                | sed $'s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' \
                | grep -v '^$' \
                | tail -"$max_lines")
            _SESSIONLOG_TS_OFFSET=$ts_size
        fi
    fi

    # Reset flush guard before spawning background job
    _SESSIONLOG_FLUSHING=false

    # Capture env vars for background subshell
    local api_key="${SESSIONLOG_ONEMIN_API_KEY:-}"
    local openai_key="${SESSIONLOG_OPENAI_TOKEN:-}"

    # Fire and forget — AI summary + devlog in background subshell
    (
        # Strip timestamps from commands
        clean_commands=$(echo "$commands" | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\} //')
        
        # Skip trivial sessions
        meaningful=$(echo "$clean_commands" | grep -cvE '^\s*(exit|logout|$)' || true)
        if [[ "$meaningful" -lt 1 ]]; then
            exit 0
        fi
        
        # Build prompt
        prompt="Summarise these terminal commands into a brief past-tense dev log entry. One or two sentences max. Rules: No timestamps. No usernames or hostnames. No filler like 'to enhance efficiency' or 'after completing necessary tasks'. Start with the action verb. Example: 'Restarted nginx and checked error logs after deploying config changes.'

Commands:
$clean_commands"
        
        # Call 1min.ai API directly
        if [[ -n "$api_key" ]]; then
            json_payload=$(printf '{"type":"CHAT_WITH_AI","model":"gpt-4o-mini","promptObject":{"prompt":"%s","isMixed":false,"webSearch":false}}' "$(echo "$prompt" | sed 's/"/\\"/g' | tr '\n' ' ')")
            
            api_response=$(curl -s --connect-timeout 5 --max-time 10 \
                -X POST "https://api.1min.ai/api/features" \
                -H "Content-Type: application/json" \
                -H "API-KEY: $api_key" \
                -d "$json_payload" 2>/dev/null)
            
            if command -v jq >/dev/null 2>&1; then
                summary=$(echo "$api_response" | jq -r '.aiRecord.aiRecordDetail.resultObject[0] // empty' 2>/dev/null)
            else
                summary=$(echo "$api_response" | grep -o '"resultObject":\["[^"]*"' | sed 's/.*"\([^"]*\)"/\1/' | head -1)
            fi
        fi

        if [[ -n "$summary" ]]; then
            if command -v devlog >/dev/null 2>&1; then
                devlog -s "$summary" 2>/dev/null
            fi
        else
            # AI failed — send raw command summary as fallback
            fallback="Terminal session ($cmd_count commands): $(echo "$commands" | head -5 | sed 's/^[0-9:]* //' | tr '\n' '; ')"
            if command -v devlog >/dev/null 2>&1; then
                devlog -s "$fallback" 2>/dev/null
            fi
        fi
        
        # Clean up temp file
        rm -f "$temp_file" 2>/dev/null
    ) &>/dev/null & disown
    
    return 0
}

function _sessionlog_ai_summarise() {
    local commands="$1"
    local output_context="${2:-}"
    local provider="${SESSIONLOG_PROVIDER:-1min}"
    local summary=""

    local hostname_str
    hostname_str=$(hostname)

    # Strip timestamps (HH:MM:SS prefix) from command list before sending to AI
    local clean_commands
    clean_commands=$(echo "$commands" | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\} //')

    # Skip trivial sessions (e.g. just 'exit' or 'logout')
    local meaningful
    meaningful=$(echo "$clean_commands" | grep -cvE '^\s*(exit|logout|$)' || true)
    if [[ "$meaningful" -lt 1 ]]; then
        return 1
    fi

    local prompt="Summarise these terminal commands into a brief past-tense dev log entry. One or two sentences max. Rules: No timestamps. No usernames or hostnames. No filler like 'to enhance efficiency' or 'after completing necessary tasks'. Start with the action verb. Example: 'Restarted nginx and checked error logs after deploying config changes.'

Commands:
$clean_commands"

    # Append output context if available (gives AI better understanding)
    if [[ -n "$output_context" ]]; then
        prompt="$prompt

Terminal output (trimmed):
$output_context"
    fi

    # Try 1min first (if configured or default)
    if [[ "$provider" == "1min" ]] || [[ -n "${SESSIONLOG_ONEMIN_API_KEY:-}" ]]; then
        summary=$(_sessionlog_call_1min "$prompt")
    fi

    # Fallback to OpenAI if 1min failed or not configured
    if [[ -z "$summary" ]]; then
        local openai_key="${SESSIONLOG_OPENAI_TOKEN:-${BUMPSCRIPT_OPENAI_TOKEN:-}}"
        if [[ -n "$openai_key" ]]; then
            summary=$(_sessionlog_call_openai "$prompt")
        fi
    fi

    if [[ -z "$summary" ]]; then
        return 1
    fi

    # Clean up leading/trailing whitespace
    summary=$(echo "$summary" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$summary"
}

# ---------------------------------------------------------------
# 1min.ai provider
# ---------------------------------------------------------------
function _sessionlog_call_1min() {
    local prompt="$1"
    local api_key="${SESSIONLOG_ONEMIN_API_KEY:-}"
    local model="${SESSIONLOG_ONEMIN_MODEL:-gpt-4o-mini}"

    if [[ -z "$api_key" ]]; then
        return 1
    fi

    local json_payload
    if command -v jq >/dev/null 2>&1; then
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg prompt "$prompt" \
            '{
                "type": "CHAT_WITH_AI",
                "model": $model,
                "promptObject": {
                    "prompt": $prompt,
                    "isMixed": false,
                    "webSearch": false
                }
            }')
    else
        local safe_prompt
        safe_prompt=$(printf '%s' "$prompt" | sed 's/"/\\"/g' | tr '\n' ' ')
        json_payload='{"type":"CHAT_WITH_AI","model":"'"$model"'","promptObject":{"prompt":"'"$safe_prompt"'","isMixed":false,"webSearch":false}}'
    fi

    local api_response
    api_response=$(curl -s --connect-timeout 5 --max-time 10 \
        -X POST "https://api.1min.ai/api/features" \
        -H "Content-Type: application/json" \
        -H "API-KEY: $api_key" \
        -d "$json_payload" 2>/dev/null)

    if [[ -z "$api_response" ]]; then
        return 1
    fi

    if echo "$api_response" | grep -q '"error"'; then
        return 1
    fi

    # Extract result from 1min response structure
    local summary=""
    if command -v jq >/dev/null 2>&1; then
        summary=$(echo "$api_response" | jq -r '.aiRecord.aiRecordDetail.resultObject[0] // .aiRecord.aiRecordDetail.result // empty' 2>/dev/null)
    fi

    # Fallback to grep/sed if jq unavailable
    if [[ -z "$summary" ]]; then
        summary=$(echo "$api_response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p' | tail -1)
    fi

    echo "$summary"
}

# ---------------------------------------------------------------
# OpenAI provider (fallback)
# ---------------------------------------------------------------
function _sessionlog_call_openai() {
    local prompt="$1"
    local token="${SESSIONLOG_OPENAI_TOKEN:-${BUMPSCRIPT_OPENAI_TOKEN:-}}"
    local model="${SESSIONLOG_OPENAI_MODEL:-gpt-4o}"

    if [[ -z "$token" ]]; then
        return 1
    fi

    local json_payload
    if command -v jq >/dev/null 2>&1; then
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg prompt "$prompt" \
            '{
                "model": $model,
                "messages": [
                    {"role": "system", "content": "You write brief dev log entries summarising terminal work sessions. Past tense. Concise."},
                    {"role": "user", "content": $prompt}
                ],
                "max_tokens": 150,
                "temperature": 0.5
            }')
    else
        local safe_prompt
        safe_prompt=$(printf '%s' "$prompt" | sed 's/"/\\"/g' | tr '\n' ' ')
        json_payload='{"model":"'"$model"'","messages":[{"role":"system","content":"You write brief dev log entries summarising terminal work sessions. Past tense. Concise."},{"role":"user","content":"'"$safe_prompt"'"}],"max_tokens":150,"temperature":0.5}'
    fi

    local api_response
    api_response=$(curl -s --connect-timeout 5 --max-time 10 \
        -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$json_payload" 2>/dev/null)

    if [[ -z "$api_response" ]]; then
        return 1
    fi

    if echo "$api_response" | grep -q '"error"'; then
        return 1
    fi

    local summary=""
    if command -v jq >/dev/null 2>&1; then
        summary=$(echo "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    fi

    if [[ -z "$summary" ]]; then
        summary=$(echo "$api_response" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | tail -1)
    fi

    echo "$summary"
}

# ---------------------------------------------------------------
# Auto-start if SESSIONLOG_AUTOCAPTURE is true
# ---------------------------------------------------------------
if [[ "${SESSIONLOG_AUTOCAPTURE:-false}" == "true" ]] && [[ $- == *i* ]]; then
    sessionlog_start
fi
