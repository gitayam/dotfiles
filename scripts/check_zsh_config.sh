#!/bin/bash
# Check ZSH Configuration Script
# This script verifies that all needed zsh configuration files exist and are properly loaded

echo "=== ZSH Configuration Check ==="

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define the required files
FILES=(
    ".zshrc"
    ".zsh_aliases"
    ".zsh_functions"
    ".zsh_git"
    ".zsh_apps"
    ".zsh_network"
    ".zsh_transfer"
    ".zsh_security"
    ".zsh_utils"
    ".zsh_docker"
)

# Check if each file exists in the home directory
echo -e "\nChecking for required files in home directory..."
missing_files=0
for file in "${FILES[@]}"; do
    if [ -f "$HOME/$file" ]; then
        echo -e "${GREEN}✓ $file exists${NC}"
    else
        echo -e "${RED}✗ $file is missing${NC}"
        missing_files=$((missing_files + 1))
    fi
done

# Check if .zshrc is properly configured to load all the modular files
echo -e "\nChecking if .zshrc is configured to load all modular files..."
if [ -f "$HOME/.zshrc" ]; then
    if grep -q "for config_file in ~/.zsh_" "$HOME/.zshrc"; then
        echo -e "${GREEN}✓ .zshrc is configured to load modular files${NC}"
    else
        echo -e "${RED}✗ .zshrc does not contain the loop to load modular files${NC}"
        echo -e "${YELLOW}Recommendation: Add the following to your .zshrc:${NC}"
        echo "# Load zsh configuration files"
        echo 'for config_file in ~/.zsh_{aliases,functions,git,apps,network,transfer,security,utils,docker}; do'
        echo '  if [ -f "$config_file" ]; then'
        echo '    source "$config_file"'
        echo '  fi'
        echo 'done'
    fi
else
    echo -e "${RED}✗ .zshrc not found${NC}"
fi

# If there are missing files, offer to install them
if [ $missing_files -gt 0 ]; then
    echo -e "\n${YELLOW}$missing_files file(s) are missing from your home directory.${NC}"
    echo -n "Do you want to install the missing files from the repository? (y/n): "
    read install_files
    
    if [[ $install_files =~ ^[Yy]$ ]]; then
        repo_dir=$(dirname "$(realpath "$0")")
        
        for file in "${FILES[@]}"; do
            if [ ! -f "$HOME/$file" ] && [ -f "$repo_dir/$file" ]; then
                cp "$repo_dir/$file" "$HOME/$file"
                echo -e "${GREEN}Installed $file to your home directory${NC}"
            elif [ ! -f "$HOME/$file" ] && [ ! -f "$repo_dir/$file" ]; then
                echo -e "${RED}Cannot install $file - not found in repository${NC}"
            fi
        done
        
        # If .zshrc exists but is not configured correctly, offer to update it
        if [ -f "$HOME/.zshrc" ] && ! grep -q "for config_file in ~/.zsh_" "$HOME/.zshrc"; then
            echo -n "Do you want to update your .zshrc to load all modular files? (y/n): "
            read update_zshrc
            
            if [[ $update_zshrc =~ ^[Yy]$ ]]; then
                # Backup the original .zshrc
                cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
                echo -e "${GREEN}Backed up .zshrc to .zshrc.bak${NC}"
                
                # Replace the single source line with the loop
                sed -i 's|source ~/.zsh_aliases|# Load zsh configuration files\nfor config_file in ~/.zsh_{aliases,functions,git,apps,network,transfer,security,utils,docker}; do\n  if [ -f "$config_file" ]; then\n    source "$config_file"\n  fi\ndone|g' "$HOME/.zshrc"
                echo -e "${GREEN}Updated .zshrc to load all modular files${NC}"
            fi
        fi
    fi
fi

echo -e "\n=== Check Complete ==="
if [ $missing_files -eq 0 ]; then
    echo -e "${GREEN}All configuration files are present and correctly set up!${NC}"
    echo -e "To apply changes, run: ${YELLOW}source ~/.zshrc${NC}"
else
    echo -e "${YELLOW}Some configuration files are missing or not correctly set up.${NC}"
    echo -e "Please fix the issues or run this script again to install the missing files."
fi 