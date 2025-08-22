#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# Determine if we're in the macos subdirectory or main repo
if [[ "$(basename "$SCRIPT_DIR")" == "macos" ]]; then
    # We're in the macos subdirectory
    REPO_DIR="$SCRIPT_DIR"
else
    # We might be in the main repo
    if [[ -d "$SCRIPT_DIR/macos" ]]; then
        REPO_DIR="$SCRIPT_DIR/macos"
    fi
fi

# Paths to system files and repository copies
SYSTEM_DIR="$HOME"

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
    ".zsh_aws"
    ".zsh_encryption"
)

# Test if rsync is installed if not set copy command to cp
if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
else
    COPY_CMD="cp"
fi

# Create symlinks for macOS-specific files
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Creating symlinks for macOS configuration files..."
  ln -sf "$REPO_DIR/.zsh_handle_files" ~/.zsh_handle_files
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
missing_files=()
for file in "${ZSH_FILES[@]}"; do
    if [[ -f "$SYSTEM_DIR/$file" ]]; then
        echo "✓ $file installed correctly"
    else
        echo "✗ $file not found in home directory"
        missing_files+=("$file")
    fi
done

# Create missing files if needed
if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "----------------------------"
    echo "Found missing files:"
    for missing in "${missing_files[@]}"; do
        echo "  - $missing"
    done
    
    read -p "Would you like to create the missing files? (y/n): " create_missing
    if [[ "$create_missing" == "y" ]]; then
        for missing in "${missing_files[@]}"; do
            # Create the missing file with a basic template
            if [[ "$missing" == ".zsh_git" ]]; then
                cat > "$SYSTEM_DIR/$missing" << 'EOL'
#!/bin/zsh

# Git aliases and functions
echo "Loading Git functions..."

# Enhanced Git Status with branch info
git_status() {
  git status -sb
}

# Git Diff with color
git_diff() {
  git diff --color "$@" | less -r
}

# Git log with graph
git_log() {
  git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit
}

# Git Push with tracking
git_push() {
  if [ $# -eq 0 ]; then
    git push -u origin $(git branch --show-current)
  else
    git push "$@"
  fi
}

# Aliases
alias gs="git_status"
alias gd="git_diff"
alias gl="git_log"
alias gp="git_push"
EOL
                echo "✓ Created $missing with basic Git functions"
            else
                # Generic template for other files
                cat > "$SYSTEM_DIR/$missing" << EOL
#!/bin/zsh

# ${missing#.} functions and aliases
echo "Loading ${missing#.} functions..."

# Add your functions below
EOL
                echo "✓ Created $missing with a basic template"
            fi
        done
    fi
fi

# Verify that all zsh files are sourced in .zshrc
echo "----------------------------"
echo "Verifying .zshrc sourcing:"
if [[ -f "$SYSTEM_DIR/.zshrc" ]]; then
    zshrc_content=$(cat "$SYSTEM_DIR/.zshrc")
    
    # Extract the brace expansion line
    brace_line=$(grep "for config_file in.*zsh_" "$SYSTEM_DIR/.zshrc")
    
    if [[ -n "$brace_line" ]]; then
        echo "✓ Found zsh_* files sourcing pattern in .zshrc"
        
        # Check if files are missing from the brace expansion
        missing_files=()
        for file in "${ZSH_FILES[@]}"; do
            if [[ "$file" != ".zshrc" ]]; then
                file_base="${file#.}"  # Remove the leading dot
                if ! echo "$brace_line" | grep -q "$file_base"; then
                    missing_files+=("$file")
                fi
            fi
        done
        
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            echo "⚠️ The following files may be missing from your .zshrc brace expansion:"
            for missing in "${missing_files[@]}"; do
                echo "  - $missing"
            done
            
            # Check if any files are completely missing from .zshrc
            for missing in "${missing_files[@]}"; do
                if ! grep -q "$(basename "$missing")" "$SYSTEM_DIR/.zshrc"; then
                    echo "  ❌ $missing is not sourced at all in .zshrc"
                fi
            done
            
            echo ""
            echo "Consider updating your .zshrc with this line:"
            echo 'for config_file in ~/.zsh_{aliases,aws,functions,developer,apps,network,transfer,security,utils,docker,handle_files,encryption,git}; do'
        else
            echo "✓ All zsh files are included in the brace expansion in .zshrc"
        fi
    else
        echo "⚠️ Could not find proper zsh_* files sourcing pattern in .zshrc"
        echo "Consider adding this to your .zshrc:"
        echo 'for config_file in ~/.zsh_{aliases,aws,functions,developer,apps,network,transfer,security,utils,docker,handle_files,encryption,git}; do'
        echo '  if [ -f "$config_file" ]; then'
        echo '    source "$config_file"'
        echo '  fi'
        echo 'done'
    fi
else
    echo "⚠️ Warning: .zshrc not found in home directory"
fi

# Check if LibreOffice is installed and cp python macros to /Applications/LibreOffice.app/Contents/Resources/Scripts/python
echo "----------------------------"
echo "----LibreOffice Macros------"
if [[ -d "/Applications/LibreOffice.app/Contents/Resources/Scripts/python" ]]; then
    echo "✓ LibreOffice is installed"
    echo "Copying python macros to /Applications/LibreOffice.app/Contents/Resources/Scripts/python"
    
    # Check if libreoffice directory exists in parent directory
    LIBREOFFICE_DIR="$(dirname "$REPO_DIR")/libreoffice"
    if [[ -d "$LIBREOFFICE_DIR" ]]; then
        if ls "$LIBREOFFICE_DIR"/*.py 1> /dev/null 2>&1; then
            cp "$LIBREOFFICE_DIR"/*.py "/Applications/LibreOffice.app/Contents/Resources/Scripts/python/"
            echo "✓ Copied python macros to /Applications/LibreOffice.app/Contents/Resources/Scripts/python"
        else
            echo "⚠️ No Python files found in $LIBREOFFICE_DIR"
        fi
    else
        echo "⚠️ LibreOffice macros directory not found at $LIBREOFFICE_DIR"
    fi
else
    echo "⚠️ LibreOffice is not installed"
    echo "Would you like to install it? (y/n): "
    read -p "Enter your choice (y/n): " install_choice
    if [[ "$install_choice" == "y" ]]; then
        echo "Installing LibreOffice..."
        brew install libreoffice
        echo "✓ LibreOffice installed"
    fi
fi

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
    if [[ -f "$REPO_DIR/zsh_functions.txt" ]]; then
        cat "$REPO_DIR/zsh_functions.txt"
    else
        echo "Available functions:"
        # Use a temporary file to store and sort the functions
        temp_file=$(mktemp)
        grep -h "^[a-zA-Z0-9_]*()[ ]*{" "$SYSTEM_DIR/.zsh_"* 2>/dev/null | sed 's/()[ ]*{//' | sort > "$temp_file"
        cat "$temp_file"
        rm "$temp_file"
    fi
fi
