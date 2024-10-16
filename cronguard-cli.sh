#!/bin/bash
#
# Copyright 2024 easyDNS Technologies Inc.  https://cronly.app
# cronguard-backup-client		    https://cronly.app
#
# Github: https://github.com/easydns/cronguard-backup-client
#
# Version: 1.0.0-beta
# Release Date: 2024-06-18
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

# Load settings from /etc/cronguard/api.conf
if [ -f /etc/cronguard/api.conf ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            APIKEY) APIKEY="$value" ;;
        esac
    done < /etc/cronguard/api.conf
else
    echo "api.conf not found. Please ensure it exists in /etc/cronguard."
    exit 1
fi

# Load settings from /etc/cronguard/cronguard.conf
if [ -f /etc/cronguard/cronguard.conf ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            USER_CRONTAB_DIR) USER_CRONTAB_DIR="$value" ;;
            REDACT_PWS) REDACT_PWS="$value" ;;
            PATTERNS_FILE) PATTERNS_FILE="$value" ;;
            LOCAL_ID) LOCAL_ID="$value" ;;  # Load LOCAL_ID from configuration
        esac
    done < /etc/cronguard/cronguard.conf
else
    echo "cronguard.conf not found. Please ensure it exists in /etc/cronguard."
    exit 1
fi

# Validate APIKEY, USER_CRONTAB_DIR, and LOCAL_ID
if [ -z "$APIKEY" ]; then
    echo "APIKEY is not set. Check /etc/cronguard/api.conf."
    exit 1
fi

if [ -z "$USER_CRONTAB_DIR" ]; then
    echo "USER_CRONTAB_DIR is not set in /etc/cronguard/cronguard.conf."
    exit 1
fi

if [ -z "$LOCAL_ID" ]; then
    echo "LOCAL_ID is not set in /etc/cronguard/cronguard.conf."
    exit 1
fi


# Function definitions for API actions
function list_servers {
    curl -s -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/servers"
}

function view_server {
    local server_id=$1
    curl -s -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/servers/$server_id"
}

function create_server {
    local name=$1
    local ip_address=$2
    local identifier=$3
    curl -s -X POST "https://cronly.app/api/servers" \
         -H "Authorization: Bearer $APIKEY" \
         -d "name=$name" \
         -d "ip_address=$ip_address" \
         -d "identifier=$identifier"
}

function delete_server {
    local server_id=$1
    curl -s -X DELETE -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/servers/$server_id"
}

function list_backups {
    curl -s -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/backups"
}

function view_backup {
    local server_id=$1
    local username=$2
    curl -s -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/backups/$server_id/$username"
}

function sanitize_contents {
    local file_contents="$1"
    if [[ "$REDACT_PWS" == "true" && -f "$PATTERNS_FILE" ]]; then
        while IFS= read -r pattern; do
            file_contents=$(echo "$file_contents" | sed -E "s/($pattern[ :=]+)[^ ,]+/\1REDACTED/gi")
        done < "$PATTERNS_FILE"
    fi
    echo "$file_contents"
}

function create_backup {
    local username=$1
    local file_path="$USER_CRONTAB_DIR/${username}"
    
    if [ ! -f "$file_path" ]; then
        echo "Error: File does not exist - ${file_path}"
        exit 1
    fi

    local file_contents=$(<"$file_path")
    file_contents=$(sanitize_contents "$file_contents")

    # Ensure that all variables are quoted to avoid issues with spaces or special characters
    curl -s -X POST "https://cronly.app/api/backups" \
         -H "Authorization: Bearer $APIKEY" \
         -d "username=$username" \
         -d "server_id=$LOCAL_ID" \
         -d "file_content=$file_contents"
}

function add_backup_content {
    local backup_id=$1
    local file_name=$2
    local file_path="$USER_CRONTAB_DIR/${file_name}"

    if [ ! -f "$file_path" ]; then
        echo "Error: File does not exist - ${file_path}"
        exit 1
    fi

    local file_content=$(<"$file_path")
    curl -s -X POST "https://cronly.app/api/backups/$backup_id/content" \
         -H "Authorization: Bearer $APIKEY" \
         -d "file_content=$file_content"
}

function delete_backup {
    local server_id=$1
    local username=$2
    curl -s -X DELETE -H "Authorization: Bearer $APIKEY" "https://cronly.app/api/backups/$server_id/$username"
}

# Main command switch
case "$1" in
    "list-servers")
        list_servers
        ;;
    "view-server")
        [ "$#" -eq 2 ] || { echo "Usage: $0 view-server <server_id>" >&2; exit 1; }
        view_server "$2"
        ;;
    "create-server")
        [ "$#" -eq 4 ] || { echo "Usage: $0 create-server <name> <ip_address> <identifier>" >&2; exit 1; }
        create_server "$2" "$3" "$4"
        ;;
    "delete-server")
        [ "$#" -eq 2 ] || { echo "Usage: $0 delete-server <server_id>" >&2; exit 1; }
        delete_server "$2"
        ;;
    "list")
        list_backups
        ;;
    "view")
        [ "$#" -eq 3 ] || { echo "Usage: $0 view <server_id> <username>" >&2; exit 1; }
        view_backup "$2" "$3"
        ;;
    "create")
        [ "$#" -eq 2 ] || { echo "Usage: $0 create <username>" >&2; exit 1; }
        create_backup "$2"
        ;;
    "add-content")
        [ "$#" -eq 3 ] || { echo "Usage: $0 add-content <backup_id> <file_name>" >&2; exit 1; }
        add_backup_content "$2" "$3"
        ;;
    "delete")
        [ "$#" -eq 3 ] || { echo "Usage: $0 delete <server_id> <username>" >&2; exit 1; }
        delete_backup "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {list-servers|view-server|create-server|delete-server|list|view|create|add-content|delete}"
        exit 1
        ;;
esac
