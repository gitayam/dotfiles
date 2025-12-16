#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"
SYSTEM_DIR="$HOME"

# Array of all zsh config files to sync from the shared directory
ZSH_FILES=(
    ".zshrc"
    ".zsh_aliases"
    ".zsh_developer"
    ".zsh_functions"
    ".zsh_git"
    ".zsh_apps"
    ".zsh_network"
    ".zsh_transfer"
    ".zsh_security"
    ".zsh_utils"
    ".zsh_docker"
    ".zsh_handle_files"
    ".zsh_aws"
    ".zsh_encryption"
)

# Function to sync a file
sync_file() {
    local system_file="$1"
    local repo_file="$2"
    local file_name=$(basename "$system_file")

    if [[ ! -f "$repo_file" ]]; then
        echo "Warning: Repository file $repo_file does not exist. Skipping."
        return
    fi

    if [[ ! -f "$system_file" ]]; then
        echo "System file $file_name doesn't exist. Creating it from repository version."
        cp "$repo_file" "$system_file"
        echo "✓ Created $file_name in home directory"
        return
    fi

    if ! diff "$system_file" "$repo_file" &> /dev/null; then
        echo "Differences found in $file_name."
        read -p "Update home directory file with repository version? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            timestamp=$(date +"%Y%m%d_%H%M%S")
            backup_file="${system_file}.bak_${timestamp}"
            cp "$system_file" "$backup_file"
            echo "✓ Created backup at $backup_file"
            cp "$repo_file" "$system_file"
            echo "✓ Updated $file_name in home directory"
        else
            echo "✓ Kept current $file_name unchanged"
        fi
    else
        echo "✓ No differences found in $file_name. No action needed."
    fi
}

# Sync all shared zsh files
echo "Starting sync process for ZSH configuration files..."
for file in "${ZSH_FILES[@]}"; do
    echo "----------------------------"
    echo "Processing $file"
    sync_file "$SYSTEM_DIR/$file" "$SHARED_DIR/zsh/$file"
done

# Create symlinks for any macOS-specific files here
# Example: ln -sf "$SCRIPT_DIR/macos-specific-file" "$SYSTEM_DIR/.macos-specific-file"

# Check for LibreOffice
echo "----------------------------"
echo "----LibreOffice Macros------"
if [[ -d "/Applications/LibreOffice.app" ]]; then
    echo "✓ LibreOffice is installed"
    LIBREOFFICE_PYTHON_DIR="/Applications/LibreOffice.app/Contents/Resources/Scripts/python"
    if [ -d "$LIBREOFFICE_PYTHON_DIR" ]; then
        echo "Copying python macros..."
        cp "$SCRIPT_DIR/../scripts"/*.py "$LIBREOFFICE_PYTHON_DIR/"
        echo "✓ Copied python macros."
    fi
else
    echo "⚠️ LibreOffice is not installed. Skipping macro installation."
fi

echo "----------------------------"
echo "Sync process completed."
echo "To load the updated configuration, run: source ~/.zshrc"
