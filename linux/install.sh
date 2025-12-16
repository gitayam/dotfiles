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

# Function to create a symlink
create_symlink() {
    local source_file="$1"
    local destination_file="$2"
    local file_name=$(basename "$destination_file")

    if [[ ! -f "$source_file" ]]; then
        echo "Warning: Source file $source_file does not exist. Skipping."
        return
    fi

    if [[ -L "$destination_file" && "$(readlink "$destination_file")" == "$source_file" ]]; then
        echo "✓ Symlink for $file_name already exists and is correct."
    else
        if [[ -e "$destination_file" ]]; then
            read -p "File $destination_file already exists. Replace with a symlink? (y/n): " choice
            if [[ "$choice" != "y" ]]; then
                echo "✓ Kept existing file $file_name."
                return
            fi
            # Create a backup
            timestamp=$(date +"%Y%m%d_%H%M%S")
            backup_file="${destination_file}.bak_${timestamp}"
            mv "$destination_file" "$backup_file"
            echo "✓ Created backup at $backup_file"
        fi
        ln -sf "$source_file" "$destination_file"
        echo "✓ Created symlink for $file_name."
    fi
}

# Sync all shared zsh files
echo "Starting sync process for ZSH configuration files..."
for file in "${ZSH_FILES[@]}"; do
    echo "----------------------------"
    echo "Processing $file"
    create_symlink "$SHARED_DIR/zsh/$file" "$SYSTEM_DIR/$file"
done

# Create symlinks for any Linux-specific files here
# Example: ln -sf "$SCRIPT_DIR/linux-specific-file" "$SYSTEM_DIR/.linux-specific-file"

# Check for LibreOffice
echo "----------------------------"
echo "----LibreOffice Macros------"
if command -v libreoffice &> /dev/null; then
    echo "✓ LibreOffice is installed"
    # The macro path for Linux can vary, this is a common one
    LIBREOFFICE_PYTHON_DIR="$HOME/.config/libreoffice/4/user/Scripts/python"
    if [ ! -d "$LIBREOFFICE_PYTHON_DIR" ]; then
        mkdir -p "$LIBREOFFICE_PYTHON_DIR"
    fi
    echo "Copying python macros..."
    cp "$SHARED_DIR/libreoffice"/*.py "$LIBREOFFICE_PYTHON_DIR/"
    echo "✓ Copied python macros."
else
    echo "⚠️ LibreOffice is not installed. Skipping macro installation."
fi

echo "----------------------------"
echo "Sync process completed."
echo "To load the updated configuration, run: source ~/.zshrc"
