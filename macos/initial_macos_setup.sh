#!/bin/bash
# Initial macOS setup: Homebrew packages, apps, bookmarks, system settings,
# then the zsh dotfile sync. Safe to re-run: installed packages are skipped.
#
# Every question is asked up front, then the password once; after that the run
# is unattended. The exceptions are the screen lock delay and FileVault, which
# need the login password and run last, only if the user chose them.
#
# Runs on the stock /bin/bash (3.2), so no associative arrays.
# DRY_RUN=1 asks the questions, prints the brew commands instead of running
# them, and skips sudo, system settings and the dotfile sync.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Shared with linux/initial_linux_setup.sh: prompts, summary, vibe-coding, bookmarks
source "$REPO_ROOT/shared/setup/common.sh"
ARCH=$(uname -m)

# Global variables to store user preferences
EDITOR_CHOICES=()
AI_CHOICES=()
CLOUD_CHOICES=()
PROTON_CHOICES=()
INSTALL_MULLVAD=""
MICROSOFT_CHOICES=()
DFP_CHOICES=()
CASK_QUEUE=()
APPLY_SETTINGS=""
DISABLE_REMOTE=""
ENABLE_FILEVAULT="n"
SET_SCREEN_LOCK="n"
SYNC_ANSWER=""

# Homebrew 7 asks "Do you want to proceed?" before every install. Older
# versions ignore this variable.
export HOMEBREW_NO_ASK=1
export HOMEBREW_NO_ENV_HINTS=1

run_brew() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "  [dry-run] brew $*"
    return 0
  fi
  brew "$@"
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

  # Queued, then installed in one brew call by install_queued_casks
  has_choice "$token" "${CASK_QUEUE[@]}" && return 0
  echo "Queued $token for installation."
  CASK_QUEUE+=("$token")
}

# Homebrew 7 runs `sudo --reset-timestamp` once per brew command, so each
# separate `brew install --cask` of a pkg-based app asked for the password
# again. One brew call for every cask means one prompt (a Touch ID tap once
# enable_touchid_sudo has run).
install_queued_casks() {
  [[ ${#CASK_QUEUE[@]} -eq 0 ]] && return 0
  echo "Installing ${#CASK_QUEUE[@]} apps in one batch: ${CASK_QUEUE[*]}"
  run_brew install --cask "${CASK_QUEUE[@]}"
  is_dry_run && return 0
  # brew carries on past a failed cask; find out which ones didn't install
  local token
  for token in "${CASK_QUEUE[@]}"; do
    brew list --cask "$token" &>/dev/null ||
      note_problem "cask $token: brew install failed (see output above)"
  done
  CASK_QUEUE=()
}

# Touch ID for sudo, so the remaining password prompts are a fingerprint tap.
# harden.sh --touchid does it safely (sudo_local, survives updates).
enable_touchid_sudo() {
  if is_dry_run; then
    echo "[dry-run] Would run: $SCRIPT_DIR/harden.sh --touchid"
    return 0
  fi
  "$SCRIPT_DIR/harden.sh" --touchid || note_problem "Touch ID for sudo not enabled; run: $SCRIPT_DIR/harden.sh --touchid"
}

screen_lock_is_immediate() {
  sysadminctl -screenLock status 2>&1 | grep -qE 'immediate|delay is 0 seconds'
}

# Install a command-line agent unless the command is already on PATH. Their
# native installers (claude, hermes) put them in ~/.local/bin, outside Homebrew.
# Usage: install_cli <command> <brew name> --cask|--formula
install_cli() {
  local cmd="$1" name="$2" kind="$3"
  if command -v "$cmd" &>/dev/null; then
    echo "$cmd is already installed ($(command -v "$cmd"))."
  elif [[ "$kind" == "--cask" ]]; then
    install_cask "$name"
  else
    install_formula "$name"
  fi
}

# Gather all user preferences at the beginning
gather_user_preferences() {
  echo "======================================"
  echo "Initial MacOS Setup - User Preferences"
  echo "======================================"
  echo ""

  # Code Editor and Coding Agent Selection
  echo "Which code editors and coding agents would you like to install?"
  echo "1. Visual Studio Code"
  echo "2. Cursor (Default)"
  echo "3. Devin Desktop (formerly Windsurf)"
  echo "4. Claude Code (CLI)"
  echo "5. Codex (OpenAI, CLI)"
  echo "6. OpenCode (CLI)"
  echo "7. Hermes Agent (Nous Research, CLI)"
  echo "8. DeepSeek Harness (desktop app, Apple Silicon only)"
  echo "9. Orca (runs Codex/Claude/Cursor as observable lanes for an orchestrator; npm)"
  echo "10. None"
  echo -n "Enter your choice (1-10)(Default: 2) (multiple choices separated by commas): "
  read editor_choice
  EDITOR_CHOICES=($(parse_choices "${editor_choice:-2}"))

  echo ""

  ask_vibe_coding

  echo ""

  # AI Apps Selection
  echo "Which AI Apps would you like to install?"
  echo "1. ChatGPT"
  echo "2. Claude"
  echo "3. LM Studio"
  echo "4. Ollama (local models)"
  echo "5. Perplexity"
  echo "6. Qwen (no Homebrew cask; prints the download page)"
  echo "7. None"
  echo -n "Enter your choice (1-7)(Default: 7) (multiple choices separated by commas): "
  read ai_choice
  AI_CHOICES=($(parse_choices "${ai_choice:-7}"))

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
  # Proton Apps Selection. Lumo, Wallet and Docs have no Mac app (web and mobile only).
  echo "Which Proton apps would you like to install?"
  echo "1. Proton VPN"
  echo "2. Proton Mail (includes Calendar)"
  echo "3. Proton Pass"
  echo "4. Proton Drive"
  echo "5. Proton Mail Bridge (paid plans; mail in Apple Mail, Thunderbird, Outlook)"
  echo "6. Proton Meet"
  echo "7. Proton Authenticator (Mac App Store; prints the link)"
  echo "8. All of the above"
  echo "9. None"
  echo "   Lumo (AI), Wallet and Docs have no Mac app: use lumo.proton.me, wallet.proton.me, drive.proton.me"
  echo -n "Enter your choice (1-9)(Default: 9) (multiple choices separated by commas): "
  read proton_choice
  PROTON_CHOICES=($(parse_choices "${proton_choice:-9}"))
  if has_choice 8 "${PROTON_CHOICES[@]}"; then
    PROTON_CHOICES=(1 2 3 4 5 6 7)
  fi

  echo ""

  echo -n "Do you want to install Mullvad apps (MullvadVPN, Browser)? (y/n)(Default: n): "
  read INSTALL_MULLVAD
  INSTALL_MULLVAD=${INSTALL_MULLVAD:-n}

  echo ""

  # Digital Force Protection: picks from Irregularpedia's Quick DFP guide and
  # Privacy Guides. GPG Suite is left out: its last release is 2023.
  echo "Digital Force Protection (DFP): which security and privacy tools would you like?"
  echo "See https://irregularpedia.org/cybersecurity/prevention/quick-dfp"
  echo "  Password managers"
  echo "  1. KeePassXC (offline vault file) (Default)"
  echo "  2. Bitwarden (synced vault)"
  echo "  3. 1Password (synced vault, paid)"
  echo "  Encryption"
  echo "  4. Cryptomator (encrypted vaults inside cloud drives)"
  echo "  5. VeraCrypt (encrypted volumes; uses FUSE-T, no kernel extension)"
  echo "  6. GnuPG with the macOS password prompt (pinentry-mac)"
  echo "  Keys and 2FA"
  echo "  7. YubiKey tools (Yubico Authenticator, ykman)"
  echo "  Network and monitoring (Objective-See)"
  echo "  8. LuLu outbound firewall"
  echo "  9. BlockBlock and OverSight (alerts on new launch items and mic/camera use)"
  echo "  Privacy"
  echo "  10. Metadata scrubbing (exiftool, mat2)"
  echo "  11. Tor Browser"
  echo "  12. All of the above"
  echo "  13. None"
  echo -n "Enter your choice (1-13)(Default: 1) (multiple choices separated by commas): "
  read dfp_choice
  DFP_CHOICES=($(parse_choices "${dfp_choice:-1}"))
  if has_choice 12 "${DFP_CHOICES[@]}"; then
    DFP_CHOICES=(1 2 3 4 5 6 7 8 9 10 11)
  fi

  echo ""

  # Microsoft Apps Selection
  echo "Which Microsoft apps would you like to install?"
  echo "1. Office (Word, Excel, PowerPoint)"
  echo "2. Outlook"
  echo "3. Teams"
  echo "4. OneNote"
  echo "5. None"
  echo -n "Enter your choice (1-5)(Default: 5) (multiple choices separated by commas): "
  read microsoft_choice
  MICROSOFT_CHOICES=($(parse_choices "${microsoft_choice:-5}"))

  echo ""

  # System settings
  echo -n "Do you want to apply recommended macOS system configurations? (y/n)(Default: y): "
  read APPLY_SETTINGS
  APPLY_SETTINGS=${APPLY_SETTINGS:-y}

  if [[ "$APPLY_SETTINGS" == "y" ]]; then
    echo ""
    echo "⚠️  Disabling remote login turns off SSH, Screen Sharing and Remote Management."
    echo "If you are connected remotely (SSH, VNC, etc.), you will lose connection!"
    echo "SSH over Tailscale stops too, unless you use Tailscale SSH (needs the open-source"
    echo "tailscaled, not the App Store app). Tailscale itself and Cloudflare Tunnel keep working."
    echo "Keeping it on hardens SSH instead: keys only and no root login, once you have"
    echo "~/.ssh/authorized_keys (passwords stay on until then, so you aren't locked out)."
    echo -n "Do you want to disable remote login services? (y/yes/n/no)(Default: n): "
    read DISABLE_REMOTE
    DISABLE_REMOTE=${DISABLE_REMOTE:-n}

    # macOS ignores the old com.apple.screensaver askForPassword defaults;
    # only sysadminctl changes the delay, and it needs the login password.
    if ! screen_lock_is_immediate; then
      echo ""
      echo "Your Mac waits before requiring a password after sleep or the screen saver."
      echo -n "Require it immediately? You'll type your password at the end of setup. (y/n)(Default: y): "
      read SET_SCREEN_LOCK
      SET_SCREEN_LOCK=${SET_SCREEN_LOCK:-y}
    fi

    if ! fdesetup status | grep -q "FileVault is On"; then
      echo ""
      echo "FileVault disk encryption is off. Turning it on needs you at the end of setup:"
      echo "you type your login password and must save the recovery key it shows."
      echo -n "Turn on FileVault at the end of setup? (y/n)(Default: y): "
      read ENABLE_FILEVAULT
      ENABLE_FILEVAULT=${ENABLE_FILEVAULT:-y}
    fi
  fi

  echo ""
  echo -n "Replace your shell config files (~/.zshrc, ~/.zsh_*) with this repo's versions? Backups are kept. (y/n)(Default: y): "
  read SYNC_ANSWER
  SYNC_ANSWER=${SYNC_ANSWER:-y}

  echo ""
  echo "======================================"
  echo "Preferences saved. Starting installation..."
  echo "======================================"
  echo ""
}

install_terminal_apps() {
  terminal_apps=("coreutils" "diceware" "git" "gh" "jq" "tree" "python" "ansible" "docker" "kubectl" "gnupg" "age" "magic-wormhole" "wireguard-tools" "ocrmypdf" "pandoc" "tesseract" "clamav" "ghostscript" "imagemagick" "tmux" "mosh")
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
      4) echo "pCloud left Homebrew. Download it from https://www.pcloud.com/download-free-online-cloud-file-storage.html" ;;
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

  if has_choice 10 "${EDITOR_CHOICES[@]}"; then
    echo "No code editor or agent selected. Skipping."
  else
    for choice in "${EDITOR_CHOICES[@]}"; do
      case $choice in
        1) install_cask visual-studio-code ;;
        2) install_cask cursor ;;
        3) install_cask devin-desktop ;;
        4) install_cli claude claude-code --cask ;;
        5) install_cli codex codex --cask ;;
        6) install_cli opencode opencode --formula ;;
        7) install_cli hermes hermes-agent --formula ;;
        8)
          if [[ "$ARCH" == "arm64" ]]; then
            install_cask deepseek-harness
          else
            echo "DeepSeek Harness needs Apple Silicon. Skipping."
          fi
          ;;
        9)
          install_formula node
          install_orca
          ;;
        *) echo "Invalid choice: $choice" ;;
      esac
    done
  fi

  if has_choice 7 "${AI_CHOICES[@]}"; then
    echo "No AI App selected. Skipping AI App installation."
  else
    for choice in "${AI_CHOICES[@]}"; do
      case $choice in
        1) install_cask chatgpt ;;
        2) install_cask claude ;;
        3) install_cask lm-studio ;;
        4) install_cli ollama ollama-app --cask ;;
        5) install_cask perplexity ;;
        6) echo "Qwen has no Homebrew cask. Download it from https://chat.qwen.ai" ;;
        *) echo "Invalid choice: $choice" ;;
      esac
    done
  fi

  # qBittorrent's cask was disabled on 2026-09-01 (fails Gatekeeper); Transmission replaces it
  install_cask element
  install_cask firefox
  install_cask obsidian
  install_cask transmission
  install_cask simplex
  install_cask tailscale-app "Tailscale.app"
  install_cask signal
  install_cask docker-desktop
  install_cask warp

  for choice in "${PROTON_CHOICES[@]}"; do
    case $choice in
      1) install_cask protonvpn "Proton VPN.app" ;;
      2) install_cask proton-mail ;;
      3) install_cask proton-pass ;;
      4) install_cask proton-drive ;;
      5) install_cask proton-mail-bridge ;;
      6) install_cask proton-meet ;;
      7)
        if [[ -d "/Applications/Proton Authenticator.app" ]]; then
          echo "Proton Authenticator is already installed."
        else
          echo "Proton Authenticator is only on the Mac App Store."
          note_next_step "Install Proton Authenticator from the Mac App Store: https://apps.apple.com/app/id6741758667"
        fi
        ;;
      9) ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done

  if [[ "$INSTALL_MULLVAD" == "y" ]]; then
    echo "Installing Mullvad apps..."
    install_cask mullvad-vpn "Mullvad VPN.app"
    install_cask mullvad-browser
  fi

  # Microsoft casks are pkg installers, so name the app bundle for the
  # installed-outside-Homebrew check
  if has_choice 5 "${MICROSOFT_CHOICES[@]}"; then
    echo "No Microsoft apps selected. Skipping Microsoft installation."
  else
    for choice in "${MICROSOFT_CHOICES[@]}"; do
      case $choice in
        1)
          install_cask microsoft-word "Microsoft Word.app"
          install_cask microsoft-excel "Microsoft Excel.app"
          install_cask microsoft-powerpoint "Microsoft PowerPoint.app"
          ;;
        2) install_cask microsoft-outlook "Microsoft Outlook.app" ;;
        3) install_cask microsoft-teams "Microsoft Teams.app" ;;
        4) install_cask microsoft-onenote "Microsoft OneNote.app" ;;
        *) echo "Invalid choice: $choice" ;;
      esac
    done
  fi
}

install_dfp_tools() {
  if has_choice 13 "${DFP_CHOICES[@]}"; then
    echo "No DFP tools selected. Skipping."
    return
  fi
  echo "Installing selected DFP tools..."
  for choice in "${DFP_CHOICES[@]}"; do
    case $choice in
      1) install_cask keepassxc ;;
      2)
        install_cask bitwarden
        note_next_step "Bitwarden: set Settings > Security > Key derivation function to Argon2id"
        ;;
      3) install_cask 1password ;;
      4) install_cask cryptomator ;;
      5) install_cask veracrypt-fuse-t "VeraCrypt.app" ;;
      6)
        install_formula gnupg
        install_formula pinentry-mac
        configure_pinentry_mac
        ;;
      7)
        install_cask yubico-authenticator
        install_formula ykman
        ;;
      8)
        install_cask lulu
        note_next_step "LuLu: open it once and approve its network extension in System Settings"
        ;;
      9)
        install_cask blockblock
        install_cask oversight
        note_next_step "BlockBlock and OverSight: open each once and grant the permissions they ask for"
        ;;
      10)
        install_formula exiftool
        install_formula mat2
        ;;
      11) install_cask tor-browser ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

# Point gpg-agent at the macOS password dialog, unless a pinentry is already set
configure_pinentry_mac() {
  local conf="$HOME/.gnupg/gpg-agent.conf"
  if grep -qs '^pinentry-program' "$conf"; then
    echo "gpg-agent already has a pinentry-program. Left as is."
    return 0
  fi
  if is_dry_run; then
    echo "  [dry-run] Would add pinentry-program to $conf"
    return 0
  fi
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> "$conf"
  gpgconf --kill gpg-agent 2>/dev/null
  echo "gpg-agent now uses pinentry-mac."
}

configure_macos_settings() {
  echo "======================================"
  echo "Configuring macOS System Settings"
  echo "======================================"
  echo ""

  if [[ "$APPLY_SETTINGS" != "y" ]]; then
    echo "Skipping macOS system configuration."
    return
  fi
  if is_dry_run; then
    echo "[dry-run] Skipping macOS system configuration."
    return
  fi

  echo "Applying macOS system configurations..."

  # Security: macos/harden.sh applies the scriptable mSCP/CIS controls and
  # re-checks each one. Run it with no arguments any time for a read-only report.
  echo "Applying security hardening..."
  local harden_flags=(--apply)
  [[ "$DISABLE_REMOTE" =~ ^[Yy]([Ee][Ss])?$ ]] || harden_flags+=(--keep-remote)
  local harden_output line
  harden_output=$("$SCRIPT_DIR/harden.sh" "${harden_flags[@]}")
  echo "$harden_output"
  while IFS= read -r line; do
    case "$line" in
      # Screen lock and FileVault are handled by the last steps when chosen
      *screen\ saver*) [[ "$SET_SCREEN_LOCK" =~ ^[Yy] ]] && continue ;;
      *FileVault*) [[ "$ENABLE_FILEVAULT" =~ ^[Yy] ]] && continue ;;
    esac
    case "$line" in
      MANUAL*) note_next_step "Hardening: ${line#MANUAL }" ;;
      FAIL*) note_problem "Hardening: ${line#FAIL   }" ;;
    esac
  done <<< "$harden_output"

  # Safari keeps its preferences in a sandbox container, which the terminal
  # can only write with Full Disk Access
  echo "Configuring Safari..."
  if defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null; then
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  else
    echo "⚠️  Skipped Safari settings: this terminal needs Full Disk Access to write them."
    note_problem "Safari settings skipped: grant your terminal Full Disk Access (System Settings > Privacy & Security), then re-run"
  fi

  # Convenience & Performance (12-17)
  echo "Configuring system performance..."

  # 13. Enable tap to click and three-finger drag on built-in and Bluetooth
  # trackpads; tapBehavior applies tap to click at the login screen too
  echo "Configuring trackpad..."
  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    defaults write "$domain" Clicking -bool true
    defaults write "$domain" TrackpadThreeFingerDrag -bool true
  done
  defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

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

  # Power settings live in harden.sh: Power Nap off, and on laptops 15 min
  # battery sleep and no wake-for-network. hibernatemode stays at the macOS
  # default (0 here dropped the hibernate image on laptops).

  # 19. Set timezone (automatic time sync is in harden.sh)
  echo "Configuring time settings..."
  local timezone="America/New_York"
  if [[ "$(readlink /etc/localtime)" == *"/zoneinfo/$timezone" ]]; then
    echo "Timezone already $timezone"
  else
    # systemsetup prints a harmless "### Error:-99 ... InternetServices.m" line on recent macOS
    sudo systemsetup -settimezone "$timezone" 2>&1 | grep -v '### Error:-99'
  fi

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

# The only steps that need the user again, run once everything else is done:
# both ask for the login password, and FileVault prints a recovery key.
finish_steps_needing_user() {
  [[ "$SET_SCREEN_LOCK" =~ ^[Yy] || "$ENABLE_FILEVAULT" =~ ^[Yy] ]] || return 0
  if is_dry_run; then
    [[ "$SET_SCREEN_LOCK" =~ ^[Yy] ]] && echo "[dry-run] Would set the screen lock to immediate now."
    [[ "$ENABLE_FILEVAULT" =~ ^[Yy] ]] && echo "[dry-run] Would turn on FileVault now."
    return 0
  fi
  echo ""
  echo "======================================"
  echo "Last steps: your input is needed."
  echo "======================================"
  if [[ "$SET_SCREEN_LOCK" =~ ^[Yy] ]]; then
    echo "Requiring your password immediately after sleep. Enter your login password:"
    # "-password -" prompts, so the password never appears in the command line
    sysadminctl -screenLock immediate -password - ||
      note_problem "Screen lock not changed: System Settings > Lock Screen > Require password after screen saver begins > Immediately"
  fi
  if [[ "$ENABLE_FILEVAULT" =~ ^[Yy] ]]; then
    echo "Turning on FileVault. Save the recovery key it prints somewhere other than this Mac."
    sudo fdesetup enable -user "$USER" ||
      note_problem "FileVault not turned on: System Settings > Privacy & Security > FileVault"
  fi
}

main() {
  echo "Detected: macOS $(sw_vers -productVersion) on $ARCH"

  gather_user_preferences

  is_dry_run || start_sudo_keepalive
  enable_touchid_sudo

  echo "Checking if Homebrew is installed..."
  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing..."
    # NONINTERACTIVE skips the installer's "Press RETURN"; it uses the sudo ticket above
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # A fresh install is not on PATH yet
    [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
    if ! command -v brew &> /dev/null; then
      echo "❌ Homebrew installation failed. Fix it and re-run this script."
      exit 1
    fi
  fi

  echo "Starting initial install..."
  install_terminal_apps
  install_cloud_drives
  install_gui_apps
  install_dfp_tools
  install_queued_casks
  install_vibe_coding
  setup_shell_tools
  write_bookmarks_file
  configure_macos_settings

  if is_dry_run; then
    echo "[dry-run] Skipping the dotfile sync."
  else
    echo "Syncing zsh dotfiles to your home directory..."
    # macos/install.sh syncs from shared/zsh, the canonical copies; SYNC_ANSWER
    # answers its per-file question
    SYNC_ANSWER="$SYNC_ANSWER" "$REPO_ROOT/macos/install.sh" ||
      note_problem "dotfile sync failed: run $REPO_ROOT/macos/install.sh"
  fi

  finish_steps_needing_user
  print_summary
}

# Run only when executed, so the functions can be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
