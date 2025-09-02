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
