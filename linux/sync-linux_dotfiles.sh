#!/bin/bash

# Paths to system files and repository copies
SYSTEM_BASHRC="$HOME/.bashrc"
SYSTEM_BASH_ALIASES="$HOME/.bash_aliases"
REPO_BASHRC="./.bashrc"
REPO_BASH_ALIASES="./.bash_aliases"

# Test if rsync is installed if not set copy command to cp
if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
else
    COPY_CMD="cp"
fi

# Function to check diff and prompt user
sync_file() {
    local system_file="$1"
    local repo_file="$2"
    local file_name=$(basename "$system_file")

    # Check if there is a difference between the system file and the repo copy
    if ! diff "$system_file" "$repo_file" &> /dev/null; then
        echo "Differences found for $file_name."
        echo "Select an option:"
        echo "1. Copy system version ($system_file) to repo"
        echo "2. Copy repo version ($repo_file) to system"
        echo "3. Skip this file"

        # Read user choice
        read -p "Enter your choice (1/2/3): " choice

        case $choice in
            1)
                #use copy command
                $COPY_CMD "$system_file" "$repo_file"
                echo "Copied $system_file to $repo_file."
                ;;
            2)
                $COPY_CMD "$repo_file" "$system_file"
                echo "Copied $repo_file to $system_file."
                ;;
            3)
                echo "Skipped $file_name."
                ;;
            *)
                echo "Invalid choice. Skipping $file_name."
                ;;
        esac
    else
        echo "No differences found for $file_name. No action taken."
    fi
}

# Sync both files
sync_file "$SYSTEM_BASHRC" "$REPO_BASHRC"
sync_file "$SYSTEM_BASH_ALIASES" "$REPO_BASH_ALIASES"

echo "Sync process completed."

# Define paths for cron configs and a temporary file for comparison
CRON_CONFIG="./cron_config.txt"
TEMP_CRON="temp_crontab"

# Load current crontab into a temporary file
crontab -l > "$TEMP_CRON"

# Compare the cron configs file with the current crontab and store differences
DIFF_ADDED=$(grep -Fxv -f "$TEMP_CRON" "$CRON_CONFIG")  # Entries in cron_configs.txt but not in crontab
DIFF_REMOVED=$(grep -Fxv -f "$CRON_CONFIG" "$TEMP_CRON") # Entries in crontab but not in cron_configs.txt

# Display and prompt to add missing entries from cron_configs.txt to crontab
if [ -n "$DIFF_ADDED" ]; then
    echo "The following entries are in $CRON_CONFIG but not in the current crontab:"
    echo "$DIFF_ADDED"
    read -p "Do you want to add these entries to your crontab? (y/n): " add_response
    if [[ "$add_response" =~ ^[Yy]$ ]]; then
        echo "$DIFF_ADDED" >> "$TEMP_CRON"
    fi
else
    echo "No new entries to add from $CRON_CONFIG."
fi

# Display and prompt to remove extra entries from crontab
if [ -n "$DIFF_REMOVED" ]; then
    echo "The following entries are in the current crontab but not in $CRON_CONFIG:"
    echo "$DIFF_REMOVED"
    read -p "Do you want to remove these entries from your crontab? (y/n): " remove_response
    if [[ "$remove_response" =~ ^[Yy]$ ]]; then
        grep -Fxv -f <(echo "$DIFF_REMOVED") "$TEMP_CRON" > "${TEMP_CRON}_clean"
        mv "${TEMP_CRON}_clean" "$TEMP_CRON"
    fi
else
    echo "No extra entries to remove from the crontab."
fi

# Update crontab with any approved changes
crontab "$TEMP_CRON"

# Clean up temporary file
rm "$TEMP_CRON"

echo "Crontab synchronization complete."