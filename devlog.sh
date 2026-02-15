#!/usr/bin/env bash


function devlognulloutput() {
    (
    devlogfunction "$@"
    ) &> /dev/null &
    disown
    return 0
}



function devlogfunction() {
    local silent=false
    local continuation=false

    echo -e "${BPurple}Devlog argument reminder${Color_Off}"
    echo -e "${BAqua}devlog [-s] [-c] \"message\" \"minutes\" \"project\"  \"client\" \"ticket\" \"subclient\" ${Color_Off}"
    echo -e "${BGreen}  -s = silent mode (uses defaults)  -c = continuation mode (reuse previous values)${Color_Off}"
    echo -e "${BGreen}  Use '?' for minutes to auto-calculate time since last entry${Color_Off}"

    # Use getopts for option parsing to handle -s, -c or --s, --c without shifting arguments
    while getopts ":sc-:" opt; do
        case $opt in
            s)
                silent=true
                ;;
            c)
                continuation=true
                ;;
            -)
                case $OPTARG in
                    s)
                        silent=true
                        ;;
                    c)
                        continuation=true
                        ;;
                    *)
                        echo "Invalid option: --$OPTARG" >&2
                        ;;
                esac
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                ;;
        esac
    done
    shift $((OPTIND -1))  # Shift the arguments so that positional parameters are correct

    # Reset getopts
    OPTIND=1
    
    # Use getopts again to catch any options that might have been missed
    while getopts ":sc-:" opt; do
        case $opt in
            s)
                silent=true
                ;;
            c)
                continuation=true
                ;;
            -)
                case $OPTARG in
                    s)
                        silent=true
                        ;;
                    c)
                        continuation=true
                        ;;
                    *)
                        echo "Invalid option: --$OPTARG" >&2
                        ;;
                esac
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                ;;
        esac
    done
    shift $((OPTIND -1))  # Shift the arguments so that positional parameters are correct

    # Return 0 if devlogging is false or does not exist
    if [ -z "$devlogging" ] || [ "$devlogging" = false ]; then
        return 0
    fi
    local log_date=$(date +"%a %d %b %H:%M")

    # If there are no arguments, prompt for the log message
    if [ -z "$1" ]; then
        local log_message=$(getInput "What is your log entry? ")
    else
        local log_message="${1}"
    fi

    # If message is "stop", set silent to true
    if [ "$log_message" = "stop" ]; then
        silent=true
        log_message="stop"
    fi

    # if continuation is true, set silent to true
    if [ "$continuation" = true ]; then
        silent=true
    fi

    # 2nd argument is time in minutes
    if [ -z "$2" ] && [ "$silent" = false ]; then
        read -p "Time spent in minutes? " log_minutes
    else
        local log_minutes="${2}"
    fi

    # 3rd argument is the project
    if [ -z "$3" ]; then
        # If continuation is true, keep the previous log_project value
        if [ "$continuation" = true ] && [ -n "$log_project" ]; then
            # Keep the existing log_project value
            echo -e "${BGreen}Using previous project: $log_project${Color_Off}"
        else
            # Use $project if set
            if [ -n "$project" ]; then
                echo -e "${BGreen}Using project from environment variable: $project${Color_Off}"
                log_project="${project}"
            else
                # Use $log_project if it has a value
                if [ -n "$log_project" ]; then
                    echo -e "${BGreen}Using previous project: $log_project${Color_Off}"
                    log_project="${log_project}"
                else
                    # Get the current directory name
                    current_dir=$(basename "$PWD")
                    # If silent is true, use the current directory as the default project
                    if [ "$silent" = true ]; then
                        echo -e "${BGreen}Using current directory as project: $current_dir${Color_Off}"
                        log_project="${current_dir}"
                    else
                        # Prompt the user with the current directory as the default answer
                        read -p "What is the project? [${current_dir}] " log_project
                        # Use the current directory as the default value if the user hits enter
                        log_project="${log_project:-$current_dir}"
                        # If log_project is "folder", use the current directory as the project
                        if [ "$log_project" = "folder" ]; then
                            log_project="${current_dir}"
                        fi
                    fi
                fi
            fi
        fi
    else
        echo -e "${BGreen}Using project from argument: ${3}${Color_Off}"
        log_project="${3}"
    fi

    # 4th argument is the client
    if [ -z "$4" ]; then
        # If continuation is true, keep the previous log_client value
        if [ "$continuation" = true ] && [ -n "$log_client" ]; then
            # Keep the existing log_client value
            echo -e "${BGreen}Using log_client as continuation client: $log_client${Color_Off}"
        else
            # Use $client if set
            if [ -n "$client" ]; then
                echo -e "${BGreen}Using client from environment variable: $client${Color_Off}"
                log_client="${client}"
            else
                if [ -n "$log_client" ]; then
                    echo -e "${BGreen}Using log_client because it exists as client: $log_client${Color_Off}"
                    log_client="${log_client}"
                else
                    # If silent is true, use the default client
                    if [ "$silent" = true ]; then
                        echo -e "${BGreen}Using default client: ${loggingdefaultclient} due to silent${Color_Off}"
                        log_client="${loggingdefaultclient}"
                    else
                        if is_array loggingclientlist; then
                            echo "Available clients:"
                            for i in "${!loggingclientlist[@]}"; do
                                echo "$((i + 1)). ${loggingclientlist[i]}"
                            done
                            # Read the user input again to handle number selection
                            read -p "Select a client by number or enter a custom value: " selection

                            # Check if the selection is a valid number
                            if [[ $selection =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#loggingclientlist[@]}" ]; then
                                log_client="${loggingclientlist[$((selection - 1))]}"
                            elif [ -z "$selection" ]; then
                                # Use the default client if no input is provided
                                log_client="${loggingdefaultclient}"
                            else
                                # Use the entered value as free text
                                log_client="$selection"
                            fi
                        else
                            read -p "Who is the client? [${loggingdefaultclient}] " log_client
                            log_client="${log_client:-$loggingdefaultclient}"
                        fi
                    fi
                fi
            fi
        fi
    else
        echo -e "${BGreen}Using client from argument: ${4}${Color_Off}"
        log_client="${4}"
    fi

    # Find the name of the computer
    computername=$(hostname)

    # 5th argument is the ticket
    if [ -z "$5" ]; then
        # If continuation is true, keep the previous log_ticket value
        if [ "$continuation" = true ] && [ -n "$log_ticket" ]; then
            # Keep the existing log_ticket value
            echo -e "${BGreen}Using previous ticket: $log_ticket${Color_Off}"
        else
            # check to see if we are in a git repository and look for a jira ticket number at the beginning of the branch name or after a slash, then use that ticket number
            if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                local branch=$(git branch --show-current)
                if [[ $branch =~ ^[A-Z]+-[0-9]+$ ]]; then
                    log_ticket="${branch}"
                elif [[ $branch =~ /([A-Z]+-[0-9]+) ]]; then
                    log_ticket="${BASH_REMATCH[1]}"
                fi
            fi
            # if log_ticket has value, use it
            if [[ "$silent" != true ]] && [[ -z "$log_ticket" ]]; then
                # Prompt the user for the ticket number if not set
                read -p "What is the ticket number? " log_ticket        
            else
                log_ticket="devops"
                echo -e "${BGreen}Log ticket is devops due to no log ticket:{Color_Off}"
            fi
        fi
    else
        log_ticket="${5}"
    fi

    # 6th argument is the subclient
    if [ -z "$6" ]; then
        # If continuation is true, keep the previous log_subclient value
        if [ "$continuation" = true ] && [ -n "$log_subclient" ]; then
            # Keep the existing log_subclient value
            echo -e "${BGreen}Using previous subclient: $log_subclient${Color_Off}"
        else
            log_subclient="$log_client"
            echo -e "${BGreen}Using client as subclient: $log_subclient${Color_Off}"
        fi
    else
        echo -e "${BGreen}Using subclient from argument: ${6}${Color_Off}"
        log_subclient="${6}"
    fi


    # MAKE SURE devlog is not in repo
    # If loginsamefolder is true, then log in the same folder
    if [ "$loginsamefolder" = true ]; then
        # Check if this folder is part of a git repository
        if [ -d .git ]; then
            local ignored=$(git check-ignore devlog.csv)
            # If not ignored, prompt to add to .gitignore
            if [ -z "$ignored" ]; then
                # Echo in bold red that devlog.csv is being written to a git repository folder
                echo -e "\e[1;31mdevlog.csv is being written to a git repository folder\e[0m"
                read -p "Do you want to add devlog.csv to .gitignore? [y/n] " addgitignore
                if [ "$addgitignore" = "y" ]; then
                    git rm --cached devlog.csv
                    echo "devlog.csv" >> .gitignore
                fi
            fi
        fi

        # Create devlog.csv if it doesn't exist
        if [ ! -f devlog.csv ]; then
            touch devlog.csv
            echo -e "Date\tComputer\tClient\tProject\tMinutes\tTicket\tMessage" >> devlog.csv
        fi
        echo -e "$log_date\t$computername\t$log_client\t$log_subclient\t$log_project\t$log_ticket\t$log_minutes\t$log_message" >> "devlog.csv"
        echo -e "$log_date\t$computername\t$log_client\t$log_subclient\t$log_project\t$log_ticket\t$log_minutes\t$log_message"
    fi

    # If mainlogfile is not false, then log in the main log file
    if [ "$mainlogfile" != false ]; then
        # Ensure the path exists
        if [ ! -d "$(dirname $mainlogfile)" ]; then
            # Skip logging if the path does not exist
            echo "The path $(dirname $mainlogfile) does not exist. Skipping logging."
        else
            # Create the log file if it doesn't exist
            if [ ! -f "$mainlogfile" ]; then
                touch "$mainlogfile"
            fi
            echo "Logging to $mainlogfile"
            # Attempt to log and echo if failed
            #echo -e "$log_date\t$computername\t$log_client\t$log_project\t$log_minutes\t$log_ticket\t$log_message" >> "$mainlogfile" || echo "Failed to log to $mainlogfile"
            # Log entry 
            echo "$(escape_csv "$log_date"),$(escape_csv "$computername"),$(escape_csv "$log_client"),$(escape_csv "$log_subclient"),$(escape_csv "$log_project"),$(escape_csv "$log_minutes"),$(escape_csv "$log_ticket"),$(escape_csv "$log_message")" >> "$mainlogfile" || echo "Failed to log to $mainlogfile"
        fi
    fi

    # If logingooglespreadsheet is set, then log to Google Spreadsheet
    if [ -n "$logingooglespreadsheet" ] && [ "$logingooglespreadsheet" != false ]; then
        # Skip if PHP is not installed
        if ! command -v php &> /dev/null; then
            echo "PHP is not installed. Skipping logging to Google Spreadsheet."
        else
            verifyComposer
            # Execute the PHP script to log to Google Spreadsheet
            php=$(which php)
            echo -e "${BGreen}Logging to Google Spreadsheet${Color_Off}"
            if [ "$continuation" = true ]; then
                echo -e "${BGreen}Logging as continuation to Google Spreadsheet${Color_Off}"
                $php $bbb/source/functions/php/logToGoogleSpreadSheet.php "$googleserviceaccount" "$logfilegooglespreadsheetid" "same" "same" "$computername" "same" "same" "c" "$log_message"
            else
                # debug echo the commmand being run
                echo -e "${BGreen}Running command: $php $bbb/source/functions/php/logToGoogleSpreadSheet.php \"$googleserviceaccount\" \"$logfilegooglespreadsheetid\" \"$log_client\" \"$log_subclient\" \"$computername\" \"$log_project\" \"$log_ticket\" \"$log_minutes\" \"$log_message\"${Color_Off}"
                $php $bbb/source/functions/php/logToGoogleSpreadSheet.php "$googleserviceaccount" "$logfilegooglespreadsheetid" "$log_client" "$log_subclient" "$computername" "$log_project" "$log_ticket" "$log_minutes" "$log_message"
            fi
        fi
    fi
    

# $data= [
#     'client' => $argv[3],
#     'subclient' => $argv[4],
#     'hostmachine' => $argv[5],
#     'project' => $argv[6],
#     'ticket' => $argv[7],
#     'minutes' => $argv[8],
#     'logentry' => $argv[9]
# ];

# $result=logToGoogleSheet($argv[1], $argv[2], $data); 


    # If continuation was used, inform the user
    if [ "$continuation" = true ]; then
        echo -e "${BGreen}Log entry added as continuation of previous entry${Color_Off}"
    fi
    
    return 0
}
