#!/bin/bash

# Paths to system files and repository copies
SYSTEM_ZSHRC="$HOME/.zshrc"
SYSTEM_ZSH_ALIASES="$HOME/.zsh_aliases"
REPO_ZSHRC="./.zshrc"
REPO_ZSH_ALIASES="./.zsh_aliases"

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
        echo "1. Copy repo version ($repo_file) to overwrite system ~/zshrc"
        echo "2. Skip this file"

        # Read user choice
        read -p "Enter your choice (1/2/3): " choice

        case $choice in
            1)
                $COPY_CMD "$repo_file" "$system_file"
                echo "Copied $repo_file to $system_file."
                ;;
            2)
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
sync_file "$SYSTEM_ZSHRC" "$REPO_ZSHRC"
sync_file "$SYSTEM_ZSH_ALIASES" "$REPO_ZSH_ALIASES"

echo "Sync process completed."
source "$SYSTEM_ZSHRC"