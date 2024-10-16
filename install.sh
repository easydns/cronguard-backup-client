#!/bin/bash
#
# Copyright 2024 easyDNS Technologies Inc.  https://easydns.com
# cronguard-backup-client              https://cronly.app
#
# Github: https://github.com/easydns/cronguard-backup-client
# 
# Version: 1.0.1-beta
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

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

set -eo pipefail

echo "Starting Cronguard setup..."

# Define default installation location
default_install_location="/usr/local/sbin"

# Ask for installation location with default option
read -p "Enter the installation location [$default_install_location]: " install_location
install_location=${install_location:-$default_install_location}

# Confirm installation location and create if not exists
echo "Using installation location: $install_location"
mkdir -p "$install_location"

# Detect crond service and user crontab directory
echo "Checking if crond service is active and locating user crontab directory..."
crond_service_active=false
user_crontab_dir=""

if systemctl is-active --quiet cron.service || systemctl is-active --quiet crond.service; then
    crond_service_active=true
    echo "Crond service is running."
else
    echo "Crond service is not active. Please ensure cron is installed and running."
    exit 1
fi

# Attempt to locate user crontab directory
if [ -d "/var/spool/cron/crontabs" ]; then
    user_crontab_dir="/var/spool/cron/crontabs"
elif [ -d "/var/spool/cron" ]; then
    user_crontab_dir="/var/spool/cron"
else
    echo "Unable to locate user crontab directory. Please check your system configuration."
    exit 1
fi
echo "User crontab directory located at: $user_crontab_dir"

# Check for necessary utilities
echo "Checking for a file hash utility..."
if command -v md5sum >/dev/null 2>&1; then
    hash_utility="md5sum"
    echo "md5sum is available."
elif command -v sha256sum >/dev/null 2>&1; then
    hash_utility="sha256sum"
    echo "sha256sum is available."
else
    echo "No suitable hash utility found. Please install md5sum or sha256sum."
    exit 1
fi

echo "Checking for a headless web browser..."
if command -v wget >/dev/null 2>&1; then
    web_browser="wget"
    echo "wget is available."
elif command -v curl >/dev/null 2>&1; then
    web_browser="curl"
    echo "curl is available."
else
    echo "No suitable web browser found. Please install wget or curl."
    exit 1
fi

echo "Testing accessibility to the remote node: https://cronly.app/"
if ! $web_browser "https://cronly.app/" --spider >/dev/null 2>&1; then
    echo "Cannot reach remote node: https://cronly.app/. Check your internet connection or the node's status."
    exit 1
else
    echo "Successfully connected to remote node: https://cronly.app/"
fi

echo "Checking for jq (JSON Parser)..."
if command -v jq >/dev/null 2>&1; then
    jq_path=$(which jq)
    echo "jq is available at: $jq_path"
else
    echo "jq is not installed. Please install jq for JSON parsing capabilities."
    exit 1
fi

echo "Fetching the publicly facing IP address..."
if [ "$web_browser" = "wget" ]; then
    IP=$(wget -qO- ifconfig.me)
    echo "Public IP address fetched with wget: $IP"
elif [ "$web_browser" = "curl" ]; then
    IP=$(curl -s ifconfig.me)
    echo "Public IP address fetched with curl: $IP"
fi

# Determine Configuration File Location and Write Configuration
config_dir="/etc/cronguard"
config_file="$config_dir/cronguard.conf"
api_config_file="$config_dir/api.conf"

# Create the configuration directory if it doesn't exist
if [ ! -d "$config_dir" ]; then
    echo "Creating configuration directory: $config_dir"
    sudo mkdir -p "$config_dir"
fi

echo "Writing Cronguard configuration to $config_file..."
{
    echo "# Cronguard Configuration File"
    echo "CONFIG_DIR=$config_dir"
    echo "PATTERNS_FILE=$config_dir/patterns.conf"
    echo "USER_CRONTAB_DIR=$user_crontab_dir"
    echo "HASH_UTILITY=$hash_utility"
    echo "WEB_BROWSER=$web_browser"
    echo "REDACT_PWS=true"
    echo "REMOTE_NODE=https://cronly.app/"
    echo "PUBLIC_IP=$IP"
    echo "JQ_PATH=$jq_path"
    echo "INSTALL_DIR=$install_location"
    echo "CRONTAB_DB_FILE=$config_dir/crontabs.db"
    echo "SCRIPTS_DB_FILE=$config_dir/scripts.db"
} | sudo tee "$config_file" > /dev/null

# Fetch the API key and server ID
echo "Configuring API credentials..."
read -p "Do you have your API Key? (you can add it later to: $api_config_file) " api_key
default_server_id=$(hostname)
read -p "Enter your server ID [$default_server_id]: " server_id
server_id=${server_id:-$default_server_id}

# Ask for the Monitor token
echo "Do you have a Monitor token? (you can add this later to the $config_file, obtain it from 'Create Backup Monitor' in https://cronly.app/backups/)"
read -p "Enter your Monitor token: " monitor_token

# Write API configuration
{
    echo "APIKEY=$api_key"
    echo "SERVERID=$server_id"
    echo "ALERT_ENDPOINT=https://cronly.app/api/servers/alert"
} | sudo tee "$api_config_file" > /dev/null
echo "API configuration has been written to $api_config_file."

# Write Monitor token to the config file if provided
if [ -n "$monitor_token" ]; then
    echo "MONITOR_TOKEN=$monitor_token" | sudo tee -a "$config_file" > /dev/null
else
    echo "MONITOR_TOKEN=" | sudo tee -a "$config_file" > /dev/null
fi

# Copy cronguard.sh and cronguard-cli.sh to the installation location
echo "Copying cronguard.sh and cronguard-cli.sh to $install_location..."
sudo cp cronguard.sh "$install_location/"
sudo cp cronguard-cli.sh "$install_location/"
sudo chmod +x "$install_location/cronguard.sh"
sudo chmod +x "$install_location/cronguard-cli.sh"
sudo cp patterns.conf "$config_dir/"

# Ask user if they want to create the backup server in their cronly.app account
if [ -n "$api_key" ]; then
    read -p "Do you want to create the backup server in your cronly.app account? (yes/no): " create_backup_server
    if [[ "$create_backup_server" == "yes" ]]; then
        # Generate a unique LOCAL_ID
        local_id=$(openssl rand -hex 4) # Generate 8 hexadecimal digits

        # Append LOCAL_ID to the cronguard.conf file
        echo "LOCAL_ID=$local_id" | sudo tee -a "$config_file" > /dev/null

        # Run the cronguard-cli.sh script with SERVER_ID, PUBLIC_IP, and LOCAL_ID
        echo "Creating backup server with $server_id, $IP and $local_id..."
        "$install_location/cronguard-cli.sh" "create-server" "$server_id" "$IP" "$local_id"
        echo -e "\nBackup server created successfully."
    fi
fi

# Ask user if they want to install cronguard.sh in the root crontab
read -p "Do you want to install cronguard.sh in the root crontab? (yes/no): " install_crontab

if [[ "$install_crontab" == "yes" ]]; then
    read -p "How often to run cronly.sh (default is every 5 minutes, enter \"*/5\" or your own interval, for every minute type \"*\"): " cron_interval
    cron_interval=${cron_interval:-"*/5"}

    # Add the cron job to the root crontab
    (sudo crontab -l 2>/dev/null; echo -e "\n\n# Cronguard backup and monitoring by Cronly.app") | sudo crontab -
    (sudo crontab -l 2>/dev/null; echo "$cron_interval * * * * $install_location/cronguard.sh > /dev/null") | sudo crontab -
    echo "cronguard.sh has been added to the root crontab to run every $cron_interval minute(s)."
fi

echo "Cronguard setup is complete."
echo "cronguard.sh and cronguard-cli.sh have been installed to $install_location."
