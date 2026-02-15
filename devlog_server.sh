#!/usr/bin/env bash
# Simplified devlog for VPS server
# Fixed values: Client=TMPDesign, Subclient=SMWS, Project=VPS Devops

# Source environment variables
if [ -f /etc/app.env ]; then
    source /etc/app.env
fi

function devlog() {
    local silent=false
    local continuation=false

    # Parse flags
    while getopts ":sc-:" opt; do
        case $opt in
            s) silent=true ;;
            c) continuation=true ;;
            -)
                case $OPTARG in
                    s) silent=true ;;
                    c) continuation=true ;;
                    *) echo "Invalid option: --$OPTARG" >&2 ;;
                esac
                ;;
            \?) echo "Invalid option: -$OPTARG" >&2 ;;
        esac
    done
    shift $((OPTIND - 1))
    OPTIND=1

    # Return if devlogging is disabled
    if [ -z "$devlogging" ] || [ "$devlogging" = false ]; then
        return 0
    fi

    # Fixed values
    local log_client="TMPDesign"
    local log_subclient="SMWS"
    local log_project="VPS Devops"
    local computername=$(hostname)
    local log_date=$(date +"%a %d %b %H:%M")

    # 1st argument: message
    if [ -z "$1" ]; then
        if [ "$silent" = false ]; then
            echo "Log message (press Enter 3 times to finish):"
            local log_message=""
            local empty_count=0
            while true; do
                read -r line
                if [ -z "$line" ]; then
                    empty_count=$((empty_count + 1))
                    if [ $empty_count -ge 3 ]; then
                        break
                    fi
                    log_message="${log_message}"$'\n'
                else
                    empty_count=0
                    if [ -n "$log_message" ]; then
                        log_message="${log_message}"$'\n'"${line}"
                    else
                        log_message="${line}"
                    fi
                fi
            done
            # Trim trailing newlines
            log_message=$(echo "$log_message" | sed -e :a -e '/^\n*$/d;N;ba')
        else
            echo "Error: Message required" >&2
            return 1
        fi
    else
        local log_message="${1}"
    fi

    # Handle "stop" message
    if [ "$log_message" = "stop" ]; then
        silent=true
    fi

    # 2nd argument: minutes (optional)
    if [ -z "$2" ]; then
        if [ "$silent" = false ]; then
            read -p "Time spent in minutes [?]: " log_minutes
            log_minutes="${log_minutes:-?}"
        else
            log_minutes="?"
        fi
    else
        local log_minutes="${2}"
    fi

    # 3rd argument: ticket (optional)
    if [ -z "$3" ]; then
        # If continuation, keep previous ticket
        if [ "$continuation" = true ] && [ -n "$log_ticket" ]; then
            echo -e "${BGreen}Using previous ticket: $log_ticket${Color_Off}"
        else
            # Try to extract from git branch
            if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                local branch=$(git branch --show-current)
                if [[ $branch =~ ^[A-Z]+-[0-9]+$ ]]; then
                    log_ticket="${branch}"
                elif [[ $branch =~ /([A-Z]+-[0-9]+) ]]; then
                    log_ticket="${BASH_REMATCH[1]}"
                fi
            fi
            
            # Prompt if not found and not silent
            if [ -z "$log_ticket" ] && [ "$silent" = false ]; then
                read -p "Ticket number [devops]: " log_ticket
                log_ticket="${log_ticket:-devops}"
            elif [ -z "$log_ticket" ]; then
                log_ticket="devops"
            fi
        fi
    else
        log_ticket="${3}"
    fi

    # Display what we're logging
    if [ "$silent" = false ]; then
        echo ""
        echo "Logging: $log_message"
        echo "  Client: $log_client / $log_subclient"
        echo "  Project: $log_project"
        echo "  Ticket: $log_ticket"
        echo "  Minutes: $log_minutes"
        echo ""
    fi

    # Log to local CSV if enabled
    if [ "$loginsamefolder" = true ]; then
        # Check if in git repo and devlog.csv is not ignored
        if [ -d .git ]; then
            local ignored=$(git check-ignore devlog.csv 2>/dev/null)
            if [ -z "$ignored" ]; then
                echo -e "\e[1;31mWarning: devlog.csv is in a git repository\e[0m"
            fi
        fi

        # Create CSV if doesn't exist
        if [ ! -f devlog.csv ]; then
            echo -e "Date\tComputer\tClient\tSubclient\tProject\tTicket\tMinutes\tMessage" > devlog.csv
            # Make it group-writable so both root and ubuntu can append
            chmod 664 devlog.csv 2>/dev/null || true
        fi
        echo -e "$log_date\t$computername\t$log_client\t$log_subclient\t$log_project\t$log_ticket\t$log_minutes\t$log_message" >> devlog.csv
    fi

    # Log to main log file
    if [ "$mainlogfile" != false ] && [ -n "$mainlogfile" ]; then
        if [ ! -d "$(dirname "$mainlogfile")" ]; then
            echo "Warning: $(dirname "$mainlogfile") does not exist. Skipping main log."
        else
            if [ ! -f "$mainlogfile" ]; then
                touch "$mainlogfile"
                # Make it group-writable so both root and ubuntu can append
                chmod 664 "$mainlogfile" 2>/dev/null || true
                chown ubuntu:ubuntu "$mainlogfile" 2>/dev/null || true
            fi
            # CSV format with proper escaping
            echo "\"$log_date\",\"$computername\",\"$log_client\",\"$log_subclient\",\"$log_project\",\"$log_minutes\",\"$log_ticket\",\"$log_message\"" >> "$mainlogfile"
        fi
    fi

    # Log to Google Spreadsheet
    if [ -n "$logingooglespreadsheet" ] && [ "$logingooglespreadsheet" != false ]; then
        if ! command -v php &> /dev/null; then
            echo "Warning: PHP not installed. Skipping Google Spreadsheet logging."
        else
            local php=$(which php)
            local php_script="${bbb:-/opt/serversetup}/php_functions/logToGoogleSpreadSheet.php"
            # Default to /etc/serversetup/credentials if not specified
            local service_account="${googleserviceaccount:-/etc/serversetup/credentials/service-account.json}"
            
            if [ ! -f "$php_script" ]; then
                echo "Warning: PHP script not found at $php_script"
            elif [ ! -f "$service_account" ]; then
                echo "Warning: Service account file not found at $service_account"
            else
                if [ "$continuation" = true ]; then
                    $php "$php_script" \
                        "$service_account" "$logfilegooglespreadsheetid" \
                        "same" "same" "$computername" "same" "same" "c" "$log_message"
                else
                    $php "$php_script" \
                        "$service_account" "$logfilegooglespreadsheetid" \
                        "$log_client" "$log_subclient" "$computername" \
                        "$log_project" "$log_ticket" "$log_minutes" "$log_message"
                fi
            fi
        fi
    fi

    if [ "$continuation" = true ]; then
        echo -e "${BGreen}Log entry added as continuation${Color_Off}"
    fi

    return 0
}

# Background logging (default behavior)
function devlognulloutput() {
    (devlog "$@") &> /dev/null &
    disown
    return 0
}

# Call the function with script arguments
# Run interactively if stdin is a terminal and no arguments provided
# Otherwise run in background to not block
if [ -t 0 ] && [ $# -eq 0 ]; then
    # Interactive mode - run directly so prompts work
    devlog "$@"
else
    # Background mode - don't block
    devlognulloutput "$@"
fi
