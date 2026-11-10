#!/bin/bash
# Initial macOS setup: Homebrew packages, apps, bookmarks, system settings,
# then the zsh dotfile sync. Safe to re-run: installed packages are skipped.
#
# Runs on the stock /bin/bash (3.2), so no associative arrays.
# DRY_RUN=1 prints the brew commands instead of running them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCH=$(uname -m)

# Global variables to store user preferences
EDITOR_CHOICES=()
AI_CHOICES=()
CLOUD_CHOICES=()
INSTALL_PROTON=""
INSTALL_MULLVAD=""

# Problems collected during the run, printed together at the end
PROBLEMS=()

note_problem() {
  PROBLEMS+=("$1")
}

run_brew() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "  [dry-run] brew $*"
    return 0
  fi
  brew "$@"
}

# Split a comma-separated answer into unique, trimmed choices.
# Usage: parse_choices "1, 2,2" -> prints "1" and "2" on separate lines
parse_choices() {
  local seen=" " item
  local IFS=','
  for item in $1; do
    item=$(echo "$item" | xargs)
    if [[ -n "$item" && "$seen" != *" $item "* ]]; then
      echo "$item"
      seen="$seen$item "
    fi
  done
}

# True if the space-separated list contains the value
has_choice() {
  local value="$1"; shift
  [[ " $* " == *" $value "* ]]
}

# Install a Homebrew formula unless Homebrew already has it.
install_formula() {
  local formula="$1"
  if brew list --formula "$formula" &>/dev/null; then
    echo "$formula is already installed."
    return 0
  fi
  echo "Installing $formula..."
  run_brew install "$formula" || note_problem "formula $formula: brew install failed (see output above)"
}

# Install a Homebrew cask. Skips it when Homebrew installed it already, when its
# app bundle is already in /Applications (installed outside Homebrew), or when
# Homebrew has disabled the cask.
# Usage: install_cask <token> ["Extra App Name.app"]
# Pass the app name for pkg-based casks, whose app bundle Homebrew does not list.
install_cask() {
  local token="$1" extra_app="$2" info status reason replacement app

  if brew list --cask "$token" &>/dev/null; then
    echo "$token is already installed."
    return 0
  fi

  # status|reason|replacement|app bundle path (empty for pkg casks). Not tabs:
  # read collapses consecutive whitespace separators, which shifts empty fields.
  info=$(brew info --cask --json=v2 "$token" 2>/dev/null | python3 -c '
import json, sys
c = json.load(sys.stdin)["casks"][0]
apps = [a["target"] for a in c["artifacts"] if "app" in a and "target" in a]
if not apps:
    apps = ["/Applications/" + a["app"][0] for a in c["artifacts"] if "app" in a]
status = "disabled" if c.get("disabled") else "ok"
reason = c.get("disable_reason") or ""
if c.get("disable_date"):
    reason += " since " + c["disable_date"]
replacement = c.get("disable_replacement_cask") or c.get("disable_replacement_formula") or ""
print("|".join([status, reason, replacement, apps[0] if apps else ""]))
' 2>/dev/null)

  if [[ -z "$info" ]]; then
    echo "⚠️  $token: no such Homebrew cask. Skipping."
    note_problem "cask $token: not found in Homebrew"
    return 1
  fi
  IFS='|' read -r status reason replacement app <<< "$info"

  for candidate in "$app" "${extra_app:+/Applications/$extra_app}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      echo "$token is already installed ($(basename "$candidate"), not managed by Homebrew)."
      return 0
    fi
  done

  if [[ "$status" == "disabled" ]]; then
    echo "⚠️  $token: Homebrew has disabled this cask ($reason). Skipping."
    note_problem "cask $token: disabled by Homebrew ($reason)${replacement:+; replacement: $replacement}"
    return 1
  fi

  echo "Installing $token..."
  run_brew install --cask "$token" || note_problem "cask $token: brew install failed (see output above)"
}

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
  EDITOR_CHOICES=($(parse_choices "${editor_choice:-2}"))

  echo ""

  # AI Apps Selection
  echo "Which AI Apps would you like to install?"
  echo "1. ChatGPT"
  echo "2. Claude"
  echo "3. LM Studio"
  echo "4. Qwen (no Homebrew cask; prints the download page)"
  echo "5. None"
  echo -n "Enter your choice (1-5)(Default: 5) (multiple choices separated by commas): "
  read ai_choice
  AI_CHOICES=($(parse_choices "${ai_choice:-5}"))

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
  CLOUD_CHOICES=($(parse_choices "${cloud_choice:-10}"))

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

install_terminal_apps() {
  terminal_apps=("coreutils" "diceware" "git" "gh" "jq" "tree" "python" "ansible" "docker" "kubectl" "gnupg" "age" "magic-wormhole" "wireguard-tools" "ocrmypdf" "pandoc" "tesseract" "clamav" "ghostscript" "imagemagick")
  for app in "${terminal_apps[@]}"; do
    install_formula "$app"
  done
}

install_cloud_drives() {
  echo "Installing selected cloud drive apps..."

  if has_choice 10 "${CLOUD_CHOICES[@]}"; then
    echo "No cloud drive apps selected. Skipping cloud drive installation."
    return
  fi

  for choice in "${CLOUD_CHOICES[@]}"; do
    case $choice in
      1) echo "iCloud Drive is built-in to macOS. No installation needed." ;;
      2) install_cask google-drive ;;
      3) install_cask dropbox ;;
      4) install_cask pcloud-drive ;;
      5) install_cask megasync ;;
      6) install_cask onedrive ;;
      7) install_cask box-drive ;;
      8) install_cask sync ;;
      9)
        if brew list --formula syncthing &>/dev/null || [[ -d "/Applications/Syncthing.app" ]]; then
          echo "Syncthing is already installed. Skipping."
        else
          echo "Installing Syncthing..."
          run_brew install syncthing && run_brew services start syncthing &&
            echo "Syncthing installed and started. Access the web UI at http://localhost:8384"
        fi
        ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

install_gui_apps() {
  echo "Installing selected GUI applications..."

  if has_choice 5 "${EDITOR_CHOICES[@]}"; then
    echo "No code editor selected. Skipping code editor installation."
  else
    for choice in "${EDITOR_CHOICES[@]}"; do
      case $choice in
        1) install_cask visual-studio-code ;;
        2) install_cask cursor ;;
        3) install_cask windsurf ;;
        4)
          # The native installer puts `claude` in ~/.local/bin, outside Homebrew
          if command -v claude &>/dev/null; then
            echo "Claude Code is already installed ($(command -v claude))."
          else
            install_cask claude-code
          fi
          ;;
        *) echo "Invalid choice: $choice" ;;
      esac
    done
  fi

  if has_choice 5 "${AI_CHOICES[@]}"; then
    echo "No AI App selected. Skipping AI App installation."
  else
    for choice in "${AI_CHOICES[@]}"; do
      case $choice in
        1) install_cask chatgpt ;;
        2) install_cask claude ;;
        3) install_cask lm-studio ;;
        4) echo "Qwen has no Homebrew cask. Download it from https://chat.qwen.ai" ;;
        *) echo "Invalid choice: $choice" ;;
      esac
    done
  fi

  # qBittorrent's cask was disabled on 2026-09-01 (fails Gatekeeper); Transmission replaces it
  install_cask element
  install_cask firefox
  install_cask keepassxc
  install_cask obsidian
  install_cask transmission
  install_cask simplex
  install_cask tailscale-app "Tailscale.app"
  install_cask docker
  install_cask warp

  if [[ "$INSTALL_PROTON" == "y" ]]; then
    echo "Installing Proton apps..."
    install_cask protonvpn "Proton VPN.app"
    install_cask proton-mail
    install_cask proton-pass
    install_cask proton-drive
  fi

  if [[ "$INSTALL_MULLVAD" == "y" ]]; then
    echo "Installing Mullvad apps..."
    install_cask mullvad-vpn "Mullvad VPN.app"
    install_cask mullvad-browser
  fi
}

# Write the community bookmarks as a standard bookmarks file that every browser
# can import. Writing browser databases directly is unsafe while the browser
# runs, and adding them again on every re-run creates duplicates.
write_bookmarks_file() {
  local bookmarks_file="$HOME/Downloads/irregularchat-bookmarks.html"
  mkdir -p "$HOME/Downloads"
  cat > "$bookmarks_file" <<'HTML'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
  <DT><H3>IrregularChat</H3>
  <DL><p>
    <DT><A HREF="https://forum.irregularchat.com">Irregular Forum</A>
    <DT><A HREF="https://irregularpedia.org">Irregularpedia</A>
    <DT><A HREF="https://matrix.irregularchat.com">Irregular Matrix</A>
    <DT><A HREF="https://videos.irregularchat.com">Irregular Videos</A>
  </DL><p>
</DL><p>
HTML
  echo "Wrote IrregularChat bookmarks to $bookmarks_file"
  echo "  Import it once per browser:"
  echo "  Safari: File > Import From > Bookmarks HTML File"
  echo "  Firefox: Bookmarks > Manage Bookmarks > Import and Backup > Import Bookmarks from HTML"
  echo "  Chrome/Brave/Edge: Bookmarks > Import Bookmarks and Settings > Bookmarks HTML File"
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

  # 10. Configure Safari privacy settings. Safari keeps its preferences in a
  # sandbox container, which the terminal can only write with Full Disk Access.
  echo "Configuring Safari privacy..."
  if defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null; then
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
    defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
  else
    echo "⚠️  Skipped Safari settings: this terminal needs Full Disk Access to write them."
    note_problem "Safari settings skipped: grant your terminal Full Disk Access (System Settings > Privacy & Security), then re-run"
  fi

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
  local timezone="America/New_York"
  if [[ "$(readlink /etc/localtime)" == *"/zoneinfo/$timezone" ]]; then
    echo "Timezone already $timezone"
  else
    # systemsetup prints a harmless "### Error:-99 ... InternetServices.m" line on recent macOS
    sudo systemsetup -settimezone "$timezone" 2>&1 | grep -v '### Error:-99'
  fi
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

print_summary() {
  echo "======================================"
  if [[ ${#PROBLEMS[@]} -eq 0 ]]; then
    echo "✅ Initial install complete, no problems."
  else
    echo "Initial install complete with ${#PROBLEMS[@]} item(s) needing attention:"
    for problem in "${PROBLEMS[@]}"; do
      echo "  - $problem"
    done
  fi
  echo "======================================"
}

main() {
  echo "Detected: macOS $(sw_vers -productVersion) on $ARCH"

  echo "Checking if Homebrew is installed..."
  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # A fresh install is not on PATH yet
    [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
    if ! command -v brew &> /dev/null; then
      echo "❌ Homebrew installation failed. Fix it and re-run this script."
      exit 1
    fi
  fi

  gather_user_preferences

  echo "Starting initial install..."
  install_terminal_apps
  install_cloud_drives
  install_gui_apps
  write_bookmarks_file
  configure_macos_settings

  echo "Syncing zsh dotfiles to your home directory..."
  # macos/install.sh syncs from shared/zsh, the canonical copies
  "$REPO_ROOT/macos/install.sh" || note_problem "dotfile sync failed: run $REPO_ROOT/macos/install.sh"

  print_summary
}

# Run only when executed, so the functions can be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
