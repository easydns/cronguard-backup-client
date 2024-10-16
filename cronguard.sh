#!/bin/bash
#
# Copyright 2024 easyDNS Technologies Inc.  https://easydns.com
# cronguard-backup-client                 https://cronly.app
#
# Github: https://github.com/easydns/cronguard-backup-client
#
# Version: 1.0.1-beta
# Release Date: 2024-07-25
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Default configuration file location
config_file="/etc/cronguard/cronguard.conf"

# Parse command-line options for the config file location
while getopts ":c:" opt; do
  case ${opt} in
    c )
      config_file=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      ;;
  esac
done
shift $((OPTIND -1))

# Read configuration from the specified config file
if [ -f "$config_file" ]; then
    source "$config_file"
else
    echo "Configuration file not found: $config_file"
    exit 1
fi

# Check for and create the crontab database file if it doesn't exist
if [ ! -f "$CRONTAB_DB_FILE" ]; then
    touch "$CRONTAB_DB_FILE"
    echo "Created crontab database file: $CRONTAB_DB_FILE"
fi

# Check for and create the script checksum database file if it doesn't exist
if [ ! -f "$SCRIPTS_DB_FILE" ]; then
    touch "$SCRIPTS_DB_FILE"
    echo "Created script checksum database file: $SCRIPTS_DB_FILE"
fi

# Load API endpoint from api.conf file

if [ -f /etc/cronguard/api.conf ]; then
    while IFS='=' read -r key value; do
        case "$key" in
           APIKEY) APIKEY="$value" ;;
	   ALERT_ENDPOINT) ALERT_ENDPOINT="$value" ;;
        esac
    done < /etc/cronguard/api.conf
    else
       echo "api.conf not found. Please ensure it exists in /etc/cronguard."
    exit 1
fi


# Function to generate file checksum
generate_file_checksum() {
    local file=$1

    # If the file is not fully qualified, use "which" to get the full path
    if [[ "$file" != /* ]]; then
        file=$(which "$file")
    fi

    if [ -z "$file" ]; then
        echo "Command not found: $1"
        return
    fi

    local md5=$(md5sum "$file" | awk '{print $1}')
    local modified=$(stat -c %Y "$file")
    local permissions=$(stat -c %a "$file")
    echo "$md5-$modified-$permissions"
}

# Function to send alert to the API
send_alert() {
    local user=$1
    local cmd=$2

    curl -s -X POST $ALERT_ENDPOINT \
     	-H "Authorization: Bearer $APIKEY" \
     	-d "username=$user" \
     	-d "command=$cmd" \
     	-d "server_id=$LOCAL_ID"

    # Check for successful response
    if [ $? -eq 0 ]; then
        echo "Alert sent successfully for command: $cmd"
    else
        echo "Failed to send alert for command: $cmd"
    fi
}

# Function to process crontab commands
process_crontab_commands() {
    local user=$1
    local crontab_file=$2

    # Extract commands and scripts from crontab file
    commands=$(awk '!/^#/ && NF {
        print $6;
        if (index($0, ";") > 0) {
            split($0, parts, ";");
            for (i = 2; i <= length(parts); i++) {
                cmd = parts[i];
                sub(/^ */, "", cmd); # Remove leading spaces
                sub(/;.*$/, "", cmd); # Remove trailing semicolon and everything after
                sub(/ .*/, "", cmd);  # Remove everything after the command
                print cmd
            }
        }
    }' "$crontab_file" | sed 's/;$//' | sort | uniq)

    for cmd in $commands; do
        if [ -n "$cmd" ]; then
            if command -v "$cmd" > /dev/null; then
                local checksum=$(generate_file_checksum "$cmd")
                local existing_checksum=$(grep "^$cmd:" "$SCRIPTS_DB_FILE" | awk -F ':' '{print $2}')
                if [ "$checksum" != "$existing_checksum" ]; then
                    grep -v "^$cmd:" "$SCRIPTS_DB_FILE" > "$SCRIPTS_DB_FILE.tmp" && mv "$SCRIPTS_DB_FILE.tmp" "$SCRIPTS_DB_FILE"
                    echo "$cmd:$checksum" >> "$SCRIPTS_DB_FILE"
                    echo "Change detected in command: $cmd"

                    # Call the send_alert function
                    send_alert "$user" "Changed: $cmd"
                fi
            else
                echo "Command not found or not executable: $cmd"
                send_alert "$user" "Missing or not executable: $cmd"
            fi
        fi
    done
}

# Process each user's crontab in the crontabs directory
for user_crontab in "$USER_CRONTAB_DIR"/*; do
    # Skip if directory is empty
    if [ "$user_crontab" == "$USER_CRONTAB_DIR/*" ]; then continue; fi
    
    user=$(basename "$user_crontab")
    echo "Processing crontab for user: $user"
    
    # Create an md5 hash of the crontab
    if [ -f "$user_crontab" ]; then
        hash=$($HASH_UTILITY "$user_crontab" | awk '{print $1}')
        echo "$user crontab hash: $hash"
        
        # Check if the hash exists in crontab database
        if grep -q "$user:$hash" "$CRONTAB_DB_FILE"; then
            echo "No changes detected for $user."
        else
            # Update the hash in the crontab database
            grep -v "$user:" "$CRONTAB_DB_FILE" > "$CRONTAB_DB_FILE.tmp" && mv "$CRONTAB_DB_FILE.tmp" "$CRONTAB_DB_FILE"
            echo "$user:$hash" >> "$CRONTAB_DB_FILE"
            echo "Updated hash for $user."

            # Added: Invoke the command line for change detected
            echo "Change detected for $user, invoking cronguard-cli..."
            "${INSTALL_DIR}/cronguard-cli.sh" create "$user"
        fi

        # Process commands in the crontab
        process_crontab_commands "$user" "$user_crontab"
    else
        echo "Crontab file for $user not found or not accessible."
    fi
done

# If MONITOR_TOKEN is set, use the headless browser to request the MONITOR_TOKEN URL
if [ -n "$MONITOR_TOKEN" ]; then
    echo "Notifying monitor token URL..."
    $WEB_BROWSER "$MONITOR_TOKEN" >/dev/null 2>&1
fi

echo "Cronguard processing complete."
