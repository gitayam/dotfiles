#!/bin/bash

# Paths to system files and repository copies
SYSTEM_DIR="$HOME"
REPO_DIR="."

# Array of all zsh config files to sync
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
)

# Test if rsync is installed if not set copy command to cp
if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
else
    COPY_CMD="cp"
fi

# Get the directory where the script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create symlinks for macOS-specific files
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Creating symlinks for macOS configuration files..."
  ln -sf "$DOTFILES_DIR/macos/.zsh_handle_files" ~/.zsh_handle_files
  # Add other macOS-specific files here
fi

# More platform-specific linking as needed
echo "Dotfiles sync complete!"

# Function to check diff and prompt user
sync_file() {
    local system_file="$1"
    local repo_file="$2"
    local file_name=$(basename "$system_file")

    # Check if repo file exists
    if [[ ! -f "$repo_file" ]]; then
        echo "Warning: Repository file $repo_file does not exist. Skipping."
        return
    fi

    # Check if system file exists - if not, just copy it without prompting
    if [[ ! -f "$system_file" ]]; then
        echo "System file $file_name doesn't exist. Creating it from repository version."
        $COPY_CMD "$repo_file" "$system_file"
        echo "✓ Created $file_name in home directory"
        return
    fi

    # Check if there is a difference between the system file and the repo copy
    if ! diff "$system_file" "$repo_file" &> /dev/null; then
        echo "Differences found in $file_name."
        
        while true; do
            echo "What would you like to do?"
            echo "1. Update home directory file with repository version (recommended)"
            echo "2. Keep current home directory file unchanged"
            echo "3. Show differences between files"

            # Read user choice with default to option 1
            read -p "Enter your choice (1/2/3) [Press Enter for option 1]: " choice
            choice=${choice:-1}  # Default to 1 if empty

            case $choice in
                1)
                    # Create backup with timestamp
                    timestamp=$(date +"%Y%m%d_%H%M%S")
                    backup_file="${system_file}.bak_${timestamp}"
                    cp "$system_file" "$backup_file"
                    echo "✓ Created backup at $backup_file"
                    
                    # Copy the repo file to system
                    $COPY_CMD "$repo_file" "$system_file"
                    echo "✓ Updated $file_name in home directory"
                    break
                    ;;
                2)
                    echo "✓ Kept current $file_name unchanged"
                    break
                    ;;
                3)
                    echo "=== Differences between home directory and repository versions ==="
                    diff -u "$system_file" "$repo_file"
                    echo "=================================================================="
                    # Continue the loop to prompt again
                    ;;
                *)
                    echo "❌ Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
    else
        echo "✓ No differences found in $file_name. No action needed."
    fi
}

# Sync all files
echo "Starting sync process for ZSH configuration files..."
for file in "${ZSH_FILES[@]}"; do
    echo "----------------------------"
    echo "Processing $file"
    sync_file "$SYSTEM_DIR/$file" "$REPO_DIR/$file"
done

echo "----------------------------"
echo "Sync process completed."
echo "To load the updated configuration, run: source ~/.zshrc"

# Verify that files were copied correctly
echo "----------------------------"
echo "Verifying installed files:"
for file in "${ZSH_FILES[@]}"; do
    if [[ -f "$SYSTEM_DIR/$file" ]]; then
        echo "✓ $file installed correctly"
    else
        echo "✗ $file not found in home directory"
    fi
done

# Ask user if they want to load the new configuration
echo "----------------------------"
read -p "Do you want to source ~/.zshrc now to load the configuration? (y/n): " choice
if [[ "$choice" == "y" ]]; then
    echo "Sourcing ~/.zshrc..."
    source "$SYSTEM_DIR/.zshrc"
    echo "Configuration loaded. Try using some of your functions now."
fi

# Optionally show functions documentation
echo "----------------------------"
read -p "Do you want to see the list of available functions? (y/n): " choice
if [[ "$choice" == "y" ]]; then
    # Read the zsh_functions file if it exists, otherwise list functions from modular files
    if [[ -f "./zsh_functions.txt" ]]; then
        cat ./zsh_functions.txt
    else
        echo "Available functions:"
        grep -h "^[a-zA-Z0-9_]*()[ ]*{" "$SYSTEM_DIR/.zsh_"* | sed 's/()[ ]*{//' | sort
    fi
fi

echo "----------------------------"
echo "Processing .zsh_handle_files"
if [ -f "$HOME/.zsh_handle_files" ] && [ -f ".zsh_handle_files" ]; then
    diff -q "$HOME/.zsh_handle_files" ".zsh_handle_files" >/dev/null
    if [ $? -ne 0 ]; then
        cp ".zsh_handle_files" "$HOME/.zsh_handle_files"
        echo "✓ Updated .zsh_handle_files"
    else
        echo "✓ No differences found in .zsh_handle_files. No action needed."
    fi
else
    cp ".zsh_handle_files" "$HOME/.zsh_handle_files"
    echo "✓ Installed .zsh_handle_files"
fi

echo "✓ .zsh_handle_files installed correctly"
