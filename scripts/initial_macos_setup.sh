#!/bin/bash
#./initial-install.sh
# MacOS Install
# Define OS and Architecture
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi

# Detect architecture
ARCH=$(uname -m)
echo "Detected OS: $OS"
echo "Detected Architecture: $ARCH"

# Global variables to store user preferences
EDITOR_CHOICES=()
AI_CHOICES=()
CLOUD_CHOICES=()
INSTALL_PROTON=""
INSTALL_MULLVAD=""

# Gather all user preferences at the beginning
gather_user_preferences() {
  echo "======================================"
  echo "Initial MacOS Setup - User Preferences"
  echo "======================================"
  echo ""
  
  # Code Editor Selection
  echo "Which code editor(s) would you like to install?"
  echo "1. Visual Studio Code"
  echo "2. Cursor (Default)"
  echo "3. Windsurf"
  echo "4. Claude Code (CLI)"
  echo "5. None"
  echo -n "Enter your choice (1-5)(Default: 2) (multiple choices separated by commas): "
  read editor_choice
  editor_choice=${editor_choice:-2}
  
  # Parse editor choices
  raw_choices=()
  local IFS=','
  for item in $editor_choice; do
    raw_choices+=("$item")
  done
  
  declare -A seen_editors
  for raw in "${raw_choices[@]}"; do
    choice=$(echo "$raw" | xargs)
    if [[ -n "$choice" && -z "${seen_editors[$choice]}" ]]; then
      EDITOR_CHOICES+=("$choice")
      seen_editors[$choice]=1
    fi
  done
  
  echo ""
  
  # AI Apps Selection
  echo "Which AI Apps would you like to install?"
  echo "1. ChatGpt"
  echo "2. Claude"
  echo "3. LLM Studio"
  echo "4. Qwen"
  echo "5. None"
  echo -n "Enter your choice (1-5)(Default: 5) (multiple choices separated by commas): "
  read ai_choice
  ai_choice=${ai_choice:-5}
  
  # Parse AI choices
  raw_choices=()
  local IFS=','
  for item in $ai_choice; do
    raw_choices+=("$item")
  done
  
  declare -A seen_ais
  for raw in "${raw_choices[@]}"; do
    choice=$(echo "$raw" | xargs)
    if [[ -n "$choice" && -z "${seen_ais[$choice]}" ]]; then
      AI_CHOICES+=("$choice")
      seen_ais[$choice]=1
    fi
  done
  
  echo ""
  
  # Cloud Drive Selection
  echo "Which cloud drive apps would you like to install?"
  echo "1. iCloud Drive (built-in)"
  echo "2. Google Drive"
  echo "3. Dropbox"
  echo "4. pCloud"
  echo "5. MEGA"
  echo "6. OneDrive"
  echo "7. Box"
  echo "8. Sync.com"
  echo "9. Syncthing"
  echo "10. None"
  echo -n "Enter your choice (1-10)(Default: 10) (multiple choices separated by commas): "
  read cloud_choice
  cloud_choice=${cloud_choice:-10}
  
  # Parse cloud choices
  raw_choices=()
  local IFS=','
  for item in $cloud_choice; do
    raw_choices+=("$item")
  done
  
  declare -A seen_clouds
  for raw in "${raw_choices[@]}"; do
    choice=$(echo "$raw" | xargs)
    if [[ -n "$choice" && -z "${seen_clouds[$choice]}" ]]; then
      CLOUD_CHOICES+=("$choice")
      seen_clouds[$choice]=1
    fi
  done
  
  echo ""
  
  # VPN Apps Selection
  echo -n "Do you want to install Proton apps (ProtonVPN, Mail, Pass, Drive)? (y/n)(Default: n): "
  read INSTALL_PROTON
  INSTALL_PROTON=${INSTALL_PROTON:-n}
  
  echo -n "Do you want to install Mullvad apps (MullvadVPN, Browser)? (y/n)(Default: n): "
  read INSTALL_MULLVAD
  INSTALL_MULLVAD=${INSTALL_MULLVAD:-n}
  
  echo ""
  echo "======================================"
  echo "Preferences saved. Starting installation..."
  echo "======================================"
  echo ""
}

# Loop through this list checking if the application is installed and if not then install it
install_terminal_apps() {
  terminal_apps=("coreutils" "diceware" "git" "gh" "tree" "python" "ansible" "docker" "kubectl" "gpg" "age" "magic-wormhole" "wireguard-tools" "ocrmypdf" "pandoc" "tesseract" "clamav" "ghostscript" "imagemagick")
  for app in "${terminal_apps[@]}"; do
    # Capitalize the first letter of the app name
    capitalized_app="$(echo "${app:0:1}" | tr '[:lower:]' '[:upper:]')${app:1}"

    # Check if the app is a GUI application
    if [[ -d "/Applications/$capitalized_app.app" ]] || [[ -d "/Applications/$app.app" ]]; then
      echo "$app is already installed."
    # Check if the app is a command-line tool
    elif command -v "$app" &> /dev/null; then
      echo "$app is already installed."
    else
      echo "$app is not installed. Installing..."
      brew install "$app" || brew install --cask "$app"
    fi
  done
}

install_simplex_chat() {
  echo "Installing Simplex Chat..."
  
  # Check if simplex-chat is already installed
  if command -v simplex-chat &> /dev/null; then
    echo "Simplex Chat CLI is already installed."
    return
  fi
  
  # Check if the GUI app is already installed
  if [[ -d "/Applications/SimpleX Chat.app" ]]; then
    echo "Simplex Chat GUI is already installed."
  fi
  
  # For ARM64 Macs, install CLI version directly
  if [[ "$ARCH" == "arm64" ]]; then
    echo "ARM64 architecture detected. Installing Simplex Chat CLI via direct download..."
    
    # Create local bin directory if it doesn't exist
    mkdir -p ~/.local/bin
    
    # Get the latest release URL for ARM64
    SIMPLEX_URL=$(curl -s https://api.github.com/repos/simplex-chat/simplex-chat/releases/latest | grep "browser_download_url.*macos-aarch64" | grep -v "dmg" | cut -d '"' -f 4)
    
    if [[ -n "$SIMPLEX_URL" ]]; then
      echo "Downloading Simplex Chat from: $SIMPLEX_URL"
      curl -L "$SIMPLEX_URL" -o ~/.local/bin/simplex-chat
      chmod +x ~/.local/bin/simplex-chat
      
      # Add to PATH if not already there
      if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        echo "Added ~/.local/bin to PATH in ~/.zshrc"
      fi
      
      echo "Simplex Chat CLI installed successfully!"
      echo "Run 'simplex-chat' to start the CLI version"
    else
      echo "Failed to find ARM64 download URL. Falling back to Homebrew..."
      brew install --cask simplex || echo "Homebrew installation also failed"
    fi
  else
    # For Intel Macs, try Homebrew first
    echo "Installing Simplex Chat via Homebrew..."
    brew install --cask simplex || echo "Homebrew installation failed"
  fi
}

install_cloud_drives() {
  echo "Installing selected cloud drive apps..."
  
  # If '10' (None) is selected, skip all installations
  if [[ " ${CLOUD_CHOICES[@]} " =~ " 10 " ]]; then
    echo "No cloud drive apps selected. Skipping cloud drive installation."
  else
    for choice in "${CLOUD_CHOICES[@]}"; do
      case $choice in
        1)
          echo "iCloud Drive is built-in to macOS. No installation needed."
          ;;
        2)
          if [[ -d "/Applications/Google Drive.app" ]]; then
            echo "Google Drive is already installed. Skipping."
          else
            echo "Installing Google Drive..."
            brew install --cask google-drive
          fi
          ;;
        3)
          if [[ -d "/Applications/Dropbox.app" ]]; then
            echo "Dropbox is already installed. Skipping."
          else
            echo "Installing Dropbox..."
            brew install --cask dropbox
          fi
          ;;
        4)
          if [[ -d "/Applications/pCloud Drive.app" ]]; then
            echo "pCloud is already installed. Skipping."
          else
            echo "Installing pCloud..."
            brew install --cask pcloud-drive
          fi
          ;;
        5)
          if [[ -d "/Applications/MEGAsync.app" ]]; then
            echo "MEGA is already installed. Skipping."
          else
            echo "Installing MEGA..."
            brew install --cask megasync
          fi
          ;;
        6)
          if [[ -d "/Applications/OneDrive.app" ]]; then
            echo "OneDrive is already installed. Skipping."
          else
            echo "Installing OneDrive..."
            brew install --cask onedrive
          fi
          ;;
        7)
          if [[ -d "/Applications/Box.app" ]]; then
            echo "Box is already installed. Skipping."
          else
            echo "Installing Box..."
            brew install --cask box-drive
          fi
          ;;
        8)
          if [[ -d "/Applications/Sync.app" ]]; then
            echo "Sync.com is already installed. Skipping."
          else
            echo "Installing Sync.com..."
            brew install --cask sync
          fi
          ;;
        9)
          if command -v syncthing &>/dev/null || [[ -d "/Applications/Syncthing.app" ]]; then
            echo "Syncthing is already installed. Skipping."
          else
            echo "Installing Syncthing..."
            brew install syncthing
            brew services start syncthing
            echo "Syncthing installed and started. Access the web UI at http://localhost:8384"
          fi
          ;;
        *)
          echo "Invalid choice: $choice"
          ;;
      esac
    done
  fi
}

install_gui_apps() {
  echo "Installing selected GUI applications..."
  
  # Install Code Editors based on stored preferences
  if [[ " ${EDITOR_CHOICES[@]} " =~ " 5 " ]]; then
    echo "No code editor selected. Skipping code editor installation."
  else
    for choice in "${EDITOR_CHOICES[@]}"; do
      case $choice in
        1)
          if command -v code &>/dev/null; then
            echo "Visual Studio Code is already installed. Skipping."
          else
            echo "Installing Visual Studio Code..."
            brew install --cask visual-studio-code
          fi
          ;;
        2)
          if command -v cursor &>/dev/null; then
            echo "Cursor is already installed. Skipping."
          else
            echo "Installing Cursor..."
            brew install --cask cursor
          fi
          ;;
        3)
          if command -v windsurf &>/dev/null; then
            echo "Windsurf is already installed. Skipping."
          else
            echo "Installing Windsurf..."
            brew install --cask windsurf
          fi
          ;;
        4)
          if command -v claude-code &>/dev/null; then
            echo "Claude Code is already installed. Skipping."
          else
            echo "Installing Claude Code..."
            brew install claude-code
          fi
          ;;
        *)
          echo "Invalid choice: $choice"
          ;;
      esac
    done
  fi

  # Install AI Apps based on stored preferences
  if [[ " ${AI_CHOICES[@]} " =~ " 5 " ]]; then
    echo "No AI App selected. Skipping AI App installation."
  else
    for choice in "${AI_CHOICES[@]}"; do
      case $choice in
        1)
          if command -v chatgpt &>/dev/null; then
            echo "ChatGpt is already installed. Skipping."
          else
            echo "Installing ChatGpt..."
            brew install --cask chatgpt
          fi
          ;;
        2)
          if command -v claude &>/dev/null; then
            echo "Claude is already installed. Skipping."
          else
            echo "Installing Claude..."
            brew install --cask claude
          fi
          ;;
        3)
          if command -v llm-studio &>/dev/null; then
            echo "LLM Studio is already installed. Skipping."
          else
            echo "Installing LLM Studio..."
            brew install --cask llm-studio
          fi
          ;;
        4)
          if command -v qwen &>/dev/null; then
            echo "Qwen is already installed. Skipping."
          else
            echo "Installing Qwen..."
            brew install --cask qwen
          fi
          ;;
        *)
          echo "Invalid choice: $choice"
          ;;
      esac
    done
  fi

  
  # GUI Apps
  gui_apps=("element" "firefox" "keepassxc" "obsidian" "qbittorrent" "simplex" "tailscale" "docker" "warp" )

  for app in "${gui_apps[@]}"; do
    if [[ -d "/Applications/$app.app" ]]; then
    echo "$app is already installed."
  else
    echo "$app is not installed. Installing..."
    brew install --cask "$app"
    fi
  done
  mullvad_apps=("mullvadvpn" "mullvad-browser")
  proton_apps=("protonvpn" "proton-mail" "proton-pass" "proton-drive")
  
  # Install Proton apps based on stored preference
  if [[ "$INSTALL_PROTON" == "y" ]]; then
    echo "Installing Proton apps..."
    for app in "${proton_apps[@]}"; do
      # check if the app is already installed - check for actual app bundle names
      app_installed=false
      case "$app" in
        "protonvpn")
          if [[ -d "/Applications/Proton VPN.app" ]]; then
            app_installed=true
          fi
          ;;
        "proton-mail")
          if [[ -d "/Applications/Proton Mail.app" ]]; then
            app_installed=true
          fi
          ;;
        "proton-pass")
          if [[ -d "/Applications/Proton Pass.app" ]]; then
            app_installed=true
          fi
          ;;
        "proton-drive")
          if [[ -d "/Applications/Proton Drive.app" ]]; then
            app_installed=true
          fi
          ;;
      esac
      
      if [[ "$app_installed" == true ]]; then
        echo "$app is already installed."
      else
        echo "$app is not installed. Installing..."
        brew install --cask "$app"
      fi
    done
  fi
  
  # Install Mullvad apps based on stored preference
  if [[ "$INSTALL_MULLVAD" == "y" ]]; then
    echo "Installing Mullvad apps..."
    for app in "${mullvad_apps[@]}"; do
      echo "$app is not installed. Installing..."
      brew install --cask "$app"
    done
  fi
}

add_bookmarks() {
  # Parallel arrays for browser names and their application paths
  browser_names=(
    "Google Chrome"
    "Brave Browser"
    "Firefox"
    "Safari"
    "Mullvad Browser"
    "Microsoft Edge"
  )
  browser_paths=(
    "/Applications/Google Chrome.app"
    "/Applications/Brave Browser.app"
    "/Applications/Firefox.app"
    "/Applications/Safari.app"
    "/Applications/Mullvad Browser.app"
    "/Applications/Microsoft Edge.app"
  )

  # Detect installed browsers
  detected_browsers=()
  for ((i=0; i<${#browser_names[@]}; i++)); do
    if [[ -d "${browser_paths[$i]}" ]]; then
      detected_browsers+=("${browser_names[$i]}")
    fi
  done

  echo "Detected browsers: ${detected_browsers[*]}"

  # Bookmarks: parallel arrays for labels and URLs
  bookmark_labels=(
    "Irregular Forum"
    "Irregularpedia"
    "Irregular Matrix"
    "Irregular Videos"
  )
  bookmark_urls=(
    "https://forum.irregularchat.com"
    "https://irregularpedia.org"
    "https://matrix.irregularchat.com"
    "https://videos.irregularchat.com"
  )

  # Open bookmarks in new tabs in Safari (AppleScript cannot add bookmarks directly)
  if [[ " ${detected_browsers[*]} " == *"Safari"* ]]; then
    echo "Opening bookmarks in Safari tabs (AppleScript cannot add bookmarks directly)..."
    for ((i=0; i<${#bookmark_labels[@]}; i++)); do
      url="${bookmark_urls[$i]}"
      osascript <<EOD
      tell application "Safari"
        activate
        if (count of windows) = 0 then
          make new document
        end if
        tell front window
          set current tab to (make new tab with properties {URL:"$url"})
        end tell
      end tell
EOD
    done
  fi

  # Add bookmarks to Chromium-based browsers (Chrome, Brave, Edge)
  # This modifies the Bookmarks file in all profiles. The browser must be closed!
  for chromium in "Google Chrome" "Brave Browser" "Microsoft Edge"; do
    if [[ " ${detected_browsers[*]} " == *"$chromium"* ]]; then
      echo "Adding bookmarks to $chromium..."
      case "$chromium" in
        "Google Chrome")
          base_dir="$HOME/Library/Application Support/Google/Chrome" ;;
        "Brave Browser")
          base_dir="$HOME/Library/Application Support/BraveSoftware/Brave-Browser" ;;
        "Microsoft Edge")
          base_dir="$HOME/Library/Application Support/Microsoft Edge" ;;
      esac
      found_any=false
      if [[ -d "$base_dir" ]]; then
        while IFS= read -r -d '' bookmarks_file; do
          found_any=true
          profile_dir="$(dirname "$bookmarks_file")"
          echo "  Found profile: $profile_dir"
          # Backup bookmarks file
          cp "$bookmarks_file" "$bookmarks_file.bak"
          # Insert bookmarks using jq (must be installed)
          for ((i=0; i<${#bookmark_labels[@]}; i++)); do
            label="${bookmark_labels[$i]}"
            url="${bookmark_urls[$i]}"
            jq --arg name "$label" --arg url "$url" \
              '(.roots.bookmark_bar.children) += [{"type": "url", "name": $name, "url": $url}]' \
              "$bookmarks_file" > "$bookmarks_file.tmp" && mv "$bookmarks_file.tmp" "$bookmarks_file"
          done
        done < <(find "$base_dir" -type f -name "Bookmarks" -print0)
      fi
      if [[ "$found_any" = false ]]; then
        echo "Could not find any bookmarks file for $chromium. Make sure you have run $chromium at least once."
      fi
    fi
  done

  for firefox in "Firefox" "Mullvad Browser"; do
    if [[ " ${detected_browsers[*]} " == *"$firefox"* ]]; then
      echo "Adding bookmarks to $firefox..."
      base_dir="$HOME/Library/Application Support/${firefox}/Profiles"
      if [[ -d "$base_dir" ]]; then
        for db in "$base_dir"/*/places.sqlite; do
          [ -f "$db" ] || continue
          for ((i=0; i<${#bookmark_labels[@]}; i++)); do
            label="${bookmark_labels[$i]}"
            url="${bookmark_urls[$i]}"
            sqlite3 "$db" <<SQL
INSERT OR IGNORE INTO moz_places (url, title) VALUES ('$url', '$label');
INSERT OR IGNORE INTO moz_bookmarks (fk, type, parent, position, title)
  VALUES ((SELECT id FROM moz_places WHERE url='$url'), 1,
          (SELECT id FROM moz_bookmarks WHERE parent=1 AND title='Bookmarks Toolbar' LIMIT 1),
          (SELECT COALESCE(MAX(position),0)+1 FROM moz_bookmarks WHERE parent=(SELECT id FROM moz_bookmarks WHERE parent=1 AND title='Bookmarks Toolbar' LIMIT 1)),
          '$label');
SQL
          done
        done
      fi
    fi
  done
}

configure_macos_settings() {
  echo "======================================"
  echo "Configuring macOS System Settings"
  echo "======================================"
  echo ""
  
  echo -n "Do you want to apply recommended macOS system configurations? (y/n)(Default: y): "
  read APPLY_SETTINGS
  APPLY_SETTINGS=${APPLY_SETTINGS:-y}
  
  if [[ "$APPLY_SETTINGS" != "y" ]]; then
    echo "Skipping macOS system configuration."
    return
  fi
  
  echo "Applying macOS system configurations..."
  
  # Security Settings (1-8)
  echo "Configuring security settings..."
  
  # 1. Enable FileVault disk encryption
  if ! fdesetup status | grep -q "FileVault is On"; then
    echo "Enabling FileVault disk encryption..."
    sudo fdesetup enable -user "$USER" || echo "FileVault setup requires manual completion"
  else
    echo "FileVault already enabled"
  fi
  
  # 2. Enable Firewall with stealth mode
  echo "Configuring firewall..."
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
  
  # 3. Disable automatic login
  echo "Disabling automatic login..."
  sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
  
  # 4. Require password immediately after sleep/screensaver
  echo "Setting password requirements..."
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
  
  # 5. Disable remote login services
  echo "Disabling remote services..."
  echo "⚠️  WARNING: This will disable SSH and Screen Sharing."
  echo "If you are connected remotely (SSH, VNC, etc.), you will lose connection!"
  echo "This does NOT affect:"
  echo "  - Tailscale (uses WireGuard tunnels)"
  echo "  - Cloudflare Tunnel/Zero Trust"
  echo "  - VPN connections"
  echo "  - Web-based remote access tools"
  echo ""
  echo -n "Do you want to disable remote login services? (y/yes/n/no)(Default: n): "
  read DISABLE_REMOTE
  DISABLE_REMOTE=${DISABLE_REMOTE:-n}
  
  if [[ "$DISABLE_REMOTE" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Disabling remote login and screen sharing..."
    sudo systemsetup -setremotelogin off
    sudo launchctl disable system/com.apple.screensharing 2>/dev/null || true
    echo "✅ Remote services disabled"
  else
    echo "⏭️  Keeping remote services enabled"
  fi
  
  # 6. Enable secure keyboard entry in Terminal
  echo "Enabling secure keyboard entry..."
  defaults write com.apple.terminal SecureKeyboardEntry -bool true
  
  # 7. Disable Siri data collection and suggestions
  echo "Disabling Siri data collection..."
  defaults write com.apple.assistant.support "Assistant Enabled" -bool false
  defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true
  
  # 8. Enable Gatekeeper
  echo "Enabling Gatekeeper..."
  sudo spctl --master-enable
  
  # Privacy & Cleanup (9-11)
  echo "Configuring privacy settings..."
  
  # 9. Disable location services for system services
  echo "Configuring location services..."
  defaults write com.apple.locationmenu ShowSystemServices -bool false
  
  # 10. Configure Safari privacy settings
  echo "Configuring Safari privacy..."
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
  
  # 11. Enable advanced security logging and auditing
  echo "Enabling security auditing..."
  sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist 2>/dev/null || true
  sudo defaults write /Library/Preferences/com.apple.loginwindow LoginHook /usr/bin/logger
  sudo defaults write /Library/Preferences/com.apple.loginwindow LogoutHook /usr/bin/logger
  
  # Convenience & Performance (12-17)
  echo "Configuring system performance..."
  
  # 12. Disable Spotlight indexing of external drives
  echo "Configuring Spotlight..."
  sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes" 2>/dev/null || true
  
  # 13. Enable tap to click and three-finger drag
  echo "Configuring trackpad..."
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
  
  # 14. Show hidden files and file extensions
  echo "Configuring Finder visibility..."
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  
  # 15. Disable window animations and speed up Mission Control
  echo "Optimizing animations..."
  defaults write com.apple.dock expose-animation-duration -float 0.1
  defaults write com.apple.dock springboard-show-duration -float 0
  defaults write com.apple.dock springboard-hide-duration -float 0
  
  # 16. Configure Finder preferences for power users
  echo "Configuring Finder preferences..."
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  
  # 17. Set screenshot location and format
  echo "Configuring screenshots..."
  mkdir -p ~/Pictures/Screenshots
  defaults write com.apple.screencapture location ~/Pictures/Screenshots
  defaults write com.apple.screencapture type -string "png"
  
  # System Preferences (18-20)
  echo "Configuring system preferences..."
  
  # 18. Configure energy settings for optimal performance
  echo "Configuring power management..."
  sudo pmset -a displaysleep 10
  sudo pmset -a sleep 30
  sudo pmset -a hibernatemode 0
  
  # 19. Set timezone and enable automatic time sync
  echo "Configuring time settings..."
  sudo systemsetup -settimezone "America/New_York"
  sudo sntp -sS time.apple.com
  
  # 20. Configure system-wide text and input preferences
  echo "Configuring text input preferences..."
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain AppleLanguages -array "en-US"
  defaults write NSGlobalDomain AppleLocale -string "en_US@currency=USD"
  
  # Restart affected services
  echo "Restarting affected services..."
  killall Finder 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  
  echo ""
  echo "✅ macOS system configuration complete!"
  echo "⚠️  Some changes require a logout/restart to take full effect."
  echo ""
}

main() {
    # Check if Homebrew is installed
    
    echo "Checking if Homebrew is installed..."
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Gather all user preferences before starting installations
    gather_user_preferences
    
    echo "Starting initial install..."
    install_terminal_apps
    install_cloud_drives
    install_gui_apps
    add_bookmarks
    configure_macos_settings
    # add bookmarks to all chromium based browsers
    echo "Syncing mac aliases and functions to ~/.zshrc"
    ../macos/install.sh
    echo "Initial install complete."
}
# Run the main function 
main "$@"
