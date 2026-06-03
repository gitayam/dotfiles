#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_DIR="$REPO_DIR/shared"
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
    ".zsh_linux_compat"
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

# Wire the shared config files into bash (default shell on most Linux hosts).
# The .zsh_* files are bash-compatible; only zsh reads ~/.zshrc, so bash needs
# its own loader block in ~/.bashrc.
echo "----------------------------"
echo "----Bash Integration--------"
BASHRC="$SYSTEM_DIR/.bashrc"
MARKER=">>> dotfiles shared shell config >>>"
if grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    echo "✓ Bash loader block already present in ~/.bashrc"
else
    cat >> "$BASHRC" <<'EOF'

# >>> dotfiles shared shell config >>>
# Managed by ~/Git/dotfiles/linux/install.sh — shared aliases/functions (also used by zsh)
for config_file in "$HOME"/.zsh_{aliases,aws,functions,developer,apps,network,transfer,security,utils,docker,handle_files,encryption,git,linux_compat}; do
  [ -f "$config_file" ] && . "$config_file"
done
unset config_file
# <<< dotfiles shared shell config <<<
EOF
    echo "✓ Added shared config loader block to ~/.bashrc"
fi

# Check for LibreOffice
echo "----------------------------"
echo "----LibreOffice Macros------"
if command -v libreoffice &> /dev/null; then
    echo "✓ LibreOffice is installed"
    # The macro path for Linux can vary, this is a common one
    LIBREOFFICE_PYTHON_DIR="$HOME/.config/libreoffice/4/user/Scripts/python"
    MACRO_SRC_DIR="$REPO_DIR/libreoffice"
    if ls "$MACRO_SRC_DIR"/*.py &> /dev/null; then
        mkdir -p "$LIBREOFFICE_PYTHON_DIR"
        echo "Copying python macros from $MACRO_SRC_DIR..."
        for macro in "$MACRO_SRC_DIR"/*.py; do
            cp "$macro" "$LIBREOFFICE_PYTHON_DIR/"
            echo "✓ Copied $(basename "$macro")"
        done
    else
        echo "⚠️ No macros found in $MACRO_SRC_DIR. Skipping."
    fi
else
    echo "⚠️ LibreOffice is not installed. Skipping macro installation."
fi

echo "----------------------------"
echo "Sync process completed."
echo "To load the updated configuration, run: source ~/.bashrc (bash) or source ~/.zshrc (zsh)"
