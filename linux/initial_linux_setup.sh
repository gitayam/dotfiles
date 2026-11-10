#!/bin/bash
# Initial Linux setup for Debian and Ubuntu: apt packages, desktop apps, DFP
# tools, coding agents, vibe-coding config, security settings, then the zsh
# dotfile sync. Safe to re-run: installed packages are skipped.
#
# Every question is asked up front, then the password once; after that the run
# is unattended.
#
# Sources, in order of preference: the distro's apt repos, a vendor's own apt
# repo or checksummed .deb, a vendor's documented install script, and Flathub
# for apps whose publisher Flathub has verified. Anything else is printed as a
# next step with its download page.
#
# DRY_RUN=1 asks the questions, prints the install commands instead of running
# them, and skips sudo, settings and the dotfile sync. It also runs on macOS,
# for testing the flow.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Shared with macos/initial_macos_setup.sh: prompts, summary, vibe-coding, bookmarks
source "$REPO_ROOT/shared/setup/common.sh"

export DEBIAN_FRONTEND=noninteractive

# Global variables to store user preferences
INSTALL_DESKTOP_APPS="n"
EDITOR_CHOICES=()
AI_CHOICES=()
PROTON_CHOICES=()
INSTALL_MULLVAD="n"
DFP_CHOICES=()
APPLY_SETTINGS=""
MAKE_ZSH_DEFAULT="n"
SYNC_ANSWER=""

APT_UPDATED=0
FLATHUB_READY=0

has_desktop() {
  [[ -n "${XDG_CURRENT_DESKTOP:-}${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]
}

# Run a command as root, or print it in a dry run
as_root() {
  if is_dry_run; then
    echo "  [dry-run] sudo $*"
    return 0
  fi
  sudo "$@"
}

apt_update_once() {
  [[ $APT_UPDATED -eq 1 ]] && return 0
  as_root apt-get update -qq && APT_UPDATED=1
}

is_deb_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Install apt packages one at a time, so one missing name (packages differ
# between Debian and Ubuntu releases) doesn't block the rest.
apt_install() {
  local pkg
  for pkg in "$@"; do
    if is_deb_installed "$pkg"; then
      echo "$pkg is already installed."
      continue
    fi
    echo "Installing $pkg..."
    apt_update_once
    as_root apt-get install -y -qq "$pkg" ||
      note_problem "apt package $pkg: install failed (not in this release's repos?)"
  done
}

# Install a Flathub app. Only call this for apps whose publisher Flathub has
# verified, or say in the menu that the package is community-maintained.
flatpak_install() {
  local app_id="$1" label="$2"
  if command -v flatpak &>/dev/null && flatpak info "$app_id" &>/dev/null; then
    echo "$label is already installed."
    return 0
  fi
  if [[ $FLATHUB_READY -eq 0 ]]; then
    apt_install flatpak
    as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
      FLATHUB_READY=1
  fi
  echo "Installing $label from Flathub..."
  as_root flatpak install -y --noninteractive flathub "$app_id" ||
    note_problem "$label: flatpak install of $app_id failed"
}

# Run a vendor's documented install script. Downloads it first, so a failed
# download never runs half a script.
# Usage: run_vendor_installer <label> <command that must exist after> <url> <sh|bash>
run_vendor_installer() {
  local label="$1" cmd="$2" url="$3" shell="$4" tmp
  if command -v "$cmd" &>/dev/null; then
    echo "$label is already installed ($(command -v "$cmd"))."
    return 0
  fi
  if is_dry_run; then
    echo "  [dry-run] curl -fsSL $url | $shell"
    return 0
  fi
  echo "Installing $label with its official installer..."
  tmp=$(mktemp)
  if curl -fsSL "$url" -o "$tmp" && "$shell" "$tmp"; then
    rm -f "$tmp"
  else
    rm -f "$tmp"
    note_problem "$label: installer from $url failed"
  fi
}

# Install the newest stable .deb from a Proton release feed after checking its
# SHA-512 against the feed. Feeds: proton.me/download/<product>/linux/version.json
install_proton_deb() {
  local label="$1" package="$2" feed="$3" info url sum tmp
  if is_deb_installed "$package"; then
    echo "$label is already installed."
    return 0
  fi
  if [[ "$(dpkg --print-architecture 2>/dev/null)" != "amd64" ]] && ! is_dry_run; then
    note_next_step "$label: Proton ships amd64 packages only; see https://proton.me/download"
    return 0
  fi
  info=$(curl -fsSL "$feed" | python3 -c '
import json, sys
for release in json.load(sys.stdin)["Releases"]:
    if release.get("CategoryName") != "Stable":
        continue
    for f in release["File"]:
        if f["Url"].endswith(".deb"):
            print(f["Url"], f["Sha512CheckSum"])
            sys.exit()
' 2>/dev/null)
  if [[ -z "$info" ]]; then
    note_problem "$label: could not read Proton's release feed $feed"
    return 1
  fi
  read -r url sum <<< "$info"
  if is_dry_run; then
    echo "  [dry-run] download $url, check SHA-512, apt install it"
    return 0
  fi
  echo "Installing $label from $url..."
  tmp="$(mktemp -d)/$(basename "$url")"
  if ! curl -fsSL "$url" -o "$tmp"; then
    note_problem "$label: download of $url failed"
    return 1
  fi
  if ! echo "$sum  $tmp" | sha512sum --check --status -; then
    note_problem "$label: SHA-512 mismatch for $url; not installed"
    return 1
  fi
  apt_update_once
  as_root apt-get install -y -qq "$tmp" || note_problem "$label: apt install of $tmp failed"
}

# Signal's own apt repo (https://signal.org/download/linux/)
install_signal() {
  if is_deb_installed signal-desktop; then
    echo "Signal is already installed."
    return 0
  fi
  echo "Adding Signal's apt repository..."
  if ! is_dry_run; then
    curl -fsSL https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor |
      sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null &&
    curl -fsSL https://updates.signal.org/static/desktop/apt/signal-desktop.sources |
      sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null ||
      { note_problem "Signal: could not add its apt repository"; return 1; }
    APT_UPDATED=0
  fi
  apt_install signal-desktop
}

# Mullvad's own apt repo (https://mullvad.net/en/download/vpn/linux)
install_mullvad() {
  if ! [[ -f /etc/apt/sources.list.d/mullvad.list ]]; then
    echo "Adding Mullvad's apt repository..."
    if ! is_dry_run; then
      sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc &&
      echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" |
        sudo tee /etc/apt/sources.list.d/mullvad.list > /dev/null ||
        { note_problem "Mullvad: could not add its apt repository"; return 1; }
      APT_UPDATED=0
    fi
  fi
  apt_install mullvad-vpn mullvad-browser
}

# Proton VPN's repo package, checked against the hash on Proton's install page
# (https://protonvpn.com/support/official-linux-vpn-debian/). When Proton
# publishes a new repo package the hash stops matching and this fails closed.
install_protonvpn() {
  local deb="protonvpn-stable-release_1.0.10_all.deb"
  local sha256="c8a9fffb4ebdd63db08ce7f11c9b0ac394064ae6a210feb9ab63a0f7d8d060a7"
  local tmp
  if is_deb_installed proton-vpn-gnome-desktop; then
    echo "Proton VPN is already installed."
    return 0
  fi
  if ! is_deb_installed protonvpn-stable-release; then
    echo "Adding Proton VPN's apt repository..."
    if ! is_dry_run; then
      tmp="$(mktemp -d)/$deb"
      if ! curl -fsSL "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/$deb" -o "$tmp" ||
         ! echo "$sha256  $tmp" | sha256sum --check --status -; then
        note_problem "Proton VPN: repo package $deb missing or changed; follow https://protonvpn.com/support/official-linux-vpn-debian/"
        return 1
      fi
      sudo dpkg -i "$tmp" || { note_problem "Proton VPN: dpkg -i $deb failed"; return 1; }
      APT_UPDATED=0
    fi
  fi
  apt_install proton-vpn-gnome-desktop
}

gather_user_preferences() {
  echo "======================================"
  echo "Initial Linux Setup - User Preferences"
  echo "======================================"
  echo ""

  if has_desktop; then
    echo -n "A desktop session was detected. Install desktop apps? (y/n)(Default: y): "
    read INSTALL_DESKTOP_APPS
    INSTALL_DESKTOP_APPS=${INSTALL_DESKTOP_APPS:-y}
  else
    echo "No desktop session detected: only command-line tools will be offered."
    INSTALL_DESKTOP_APPS="n"
  fi
  echo ""

  # Code Editor and Coding Agent Selection
  echo "Which code editors and coding agents would you like to install?"
  echo "1. Visual Studio Code (snap; prints the download page without snap)"
  echo "2. Cursor (prints the download page)"
  echo "3. Claude Code (CLI)"
  echo "4. Codex (OpenAI, CLI)"
  echo "5. OpenCode (CLI)"
  echo "6. Hermes Agent (Nous Research, CLI)"
  echo "7. None (Default)"
  echo -n "Enter your choice (1-7)(Default: 7) (multiple choices separated by commas): "
  read editor_choice
  EDITOR_CHOICES=($(parse_choices "${editor_choice:-7}"))

  echo ""
  ask_vibe_coding
  echo ""

  # AI Apps Selection. ChatGPT, Claude and Perplexity have no Linux desktop app.
  echo "Which AI apps would you like to install?"
  echo "1. Ollama (local models)"
  echo "2. LM Studio (prints the download page)"
  echo "3. None"
  echo -n "Enter your choice (1-3)(Default: 3) (multiple choices separated by commas): "
  read ai_choice
  AI_CHOICES=($(parse_choices "${ai_choice:-3}"))

  echo ""

  if [[ "$INSTALL_DESKTOP_APPS" == "y" ]]; then
    # Proton Apps Selection. Drive and Lumo have no Linux app.
    echo "Which Proton apps would you like to install?"
    echo "1. Proton VPN"
    echo "2. Proton Mail (includes Calendar)"
    echo "3. Proton Pass"
    echo "4. Proton Meet"
    echo "5. Proton Authenticator"
    echo "6. Proton Mail Bridge (paid plans; prints the download page)"
    echo "7. All of the above"
    echo "8. None"
    echo "   Drive, Lumo (AI), Wallet and Docs have no Linux app: use drive.proton.me, lumo.proton.me"
    echo -n "Enter your choice (1-8)(Default: 8) (multiple choices separated by commas): "
    read proton_choice
    PROTON_CHOICES=($(parse_choices "${proton_choice:-8}"))
    if has_choice 7 "${PROTON_CHOICES[@]}"; then
      PROTON_CHOICES=(1 2 3 4 5 6)
    fi

    echo ""
    echo -n "Do you want to install Mullvad apps (Mullvad VPN, Mullvad Browser)? (y/n)(Default: n): "
    read INSTALL_MULLVAD
    INSTALL_MULLVAD=${INSTALL_MULLVAD:-n}

    echo ""
    echo "Microsoft Office, Outlook and Teams have no Linux desktop apps: use office.com and teams.microsoft.com."
    echo ""
  fi

  # Digital Force Protection, from Irregularpedia's Quick DFP guide and Privacy Guides
  echo "Digital Force Protection (DFP): which security and privacy tools would you like?"
  echo "See https://irregularpedia.org/cybersecurity/prevention/quick-dfp"
  echo "  Password managers"
  echo "  1. KeePassXC (offline vault file) (Default)"
  echo "  2. Bitwarden (synced vault; Flathub, verified publisher)"
  echo "  3. 1Password (synced vault, paid; Flathub, verified publisher)"
  echo "  Encryption"
  echo "  4. Cryptomator (encrypted vaults inside cloud drives; Flathub, verified publisher)"
  echo "  5. VeraCrypt (encrypted volumes; prints the download page)"
  echo "  6. GnuPG with the desktop password prompt (pinentry-gnome3)"
  echo "  Keys and 2FA"
  echo "  7. YubiKey tools (ykman)"
  echo "  Network and monitoring"
  echo "  8. OpenSnitch outbound firewall (Linux counterpart of LuLu)"
  echo "  9. Lynis and rkhunter (security audit and rootkit scan)"
  echo "  Privacy"
  echo "  10. Metadata scrubbing (exiftool, mat2)"
  echo "  11. Tor Browser (Flathub, verified publisher)"
  echo "  12. All of the above"
  echo "  13. None"
  echo -n "Enter your choice (1-13)(Default: 1) (multiple choices separated by commas): "
  read dfp_choice
  DFP_CHOICES=($(parse_choices "${dfp_choice:-1}"))
  if has_choice 12 "${DFP_CHOICES[@]}"; then
    DFP_CHOICES=(1 2 3 4 5 6 7 8 9 10 11)
  fi

  echo ""
  echo "Recommended security settings: ufw firewall (deny incoming, allow outgoing;"
  echo "SSH stays allowed if the SSH server is installed) and automatic security updates."
  echo -n "Apply them? (y/n)(Default: y): "
  read APPLY_SETTINGS
  APPLY_SETTINGS=${APPLY_SETTINGS:-y}

  if [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
    echo ""
    echo -n "Make zsh your login shell? The dotfiles are written for it. (y/n)(Default: y): "
    read MAKE_ZSH_DEFAULT
    MAKE_ZSH_DEFAULT=${MAKE_ZSH_DEFAULT:-y}
  fi

  echo ""
  echo -n "Replace your shell config files (~/.zshrc, ~/.zsh_*) with links to this repo's versions? Backups are kept. (y/n)(Default: y): "
  read SYNC_ANSWER
  SYNC_ANSWER=${SYNC_ANSWER:-y}

  echo ""
  echo "======================================"
  echo "Preferences saved. Starting installation..."
  echo "======================================"
  echo ""
}

install_terminal_apps() {
  # Debian/Ubuntu names; kubectl is not in their repos (see the summary)
  apt_install curl zsh git gh jq tree python3 ansible docker.io gnupg age diceware \
    magic-wormhole wireguard-tools ocrmypdf pandoc tesseract-ocr clamav ghostscript imagemagick
  run_vendor_installer "Tailscale" tailscale https://tailscale.com/install.sh sh
  if ! command -v kubectl &>/dev/null; then
    note_next_step "kubectl is not in Debian/Ubuntu repos: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
  fi
}

install_editors_and_agents() {
  if has_choice 7 "${EDITOR_CHOICES[@]}"; then
    echo "No code editor or agent selected. Skipping."
    return
  fi
  for choice in "${EDITOR_CHOICES[@]}"; do
    case $choice in
      1)
        if command -v code &>/dev/null; then
          echo "Visual Studio Code is already installed."
        elif command -v snap &>/dev/null; then
          # Microsoft publishes this snap
          as_root snap install code --classic || note_problem "VS Code: snap install failed"
        else
          note_next_step "VS Code: install the .deb from https://code.visualstudio.com/download"
        fi
        ;;
      2) note_next_step "Cursor: download it from https://cursor.com/downloads" ;;
      3) run_vendor_installer "Claude Code" claude https://claude.ai/install.sh bash ;;
      4) run_vendor_installer "Codex" codex https://chatgpt.com/codex/install.sh sh ;;
      5) run_vendor_installer "OpenCode" opencode https://opencode.ai/v2/install bash ;;
      6) run_vendor_installer "Hermes Agent" hermes https://hermes-agent.nousresearch.com/install.sh bash ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

install_ai_apps() {
  for choice in "${AI_CHOICES[@]}"; do
    case $choice in
      1) run_vendor_installer "Ollama" ollama https://ollama.com/install.sh sh ;;
      2) note_next_step "LM Studio: download it from https://lmstudio.ai/download" ;;
      3) ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

install_desktop_apps() {
  if [[ "$INSTALL_DESKTOP_APPS" != "y" ]]; then
    echo "Skipping desktop apps."
    return
  fi
  echo "Installing desktop apps..."
  install_signal
  apt_install transmission-gtk
  flatpak_install md.obsidian.Obsidian "Obsidian"
  flatpak_install chat.simplex.simplex "SimpleX Chat"
  # Element's Flathub package is community-maintained; Element's own apt repo
  # is at https://element.io/download
  flatpak_install im.riot.Riot "Element (community Flathub package)"

  for choice in "${PROTON_CHOICES[@]}"; do
    case $choice in
      1) install_protonvpn ;;
      2) install_proton_deb "Proton Mail" proton-mail https://proton.me/download/mail/linux/version.json ;;
      3) install_proton_deb "Proton Pass" proton-pass https://proton.me/download/PassDesktop/linux/x64/version.json ;;
      4) install_proton_deb "Proton Meet" proton-meet https://proton.me/download/meet/linux/version.json ;;
      5) install_proton_deb "Proton Authenticator" proton-authenticator https://proton.me/download/authenticator/linux/version.json ;;
      6) note_next_step "Proton Mail Bridge: download it from https://proton.me/mail/bridge#download" ;;
      8) ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done

  if [[ "$INSTALL_MULLVAD" == "y" ]]; then
    install_mullvad
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
      1) apt_install keepassxc ;;
      2)
        flatpak_install com.bitwarden.desktop "Bitwarden"
        note_next_step "Bitwarden: set Settings > Security > Key derivation function to Argon2id"
        ;;
      3) flatpak_install com.onepassword.OnePassword "1Password" ;;
      4) flatpak_install org.cryptomator.Cryptomator "Cryptomator" ;;
      5) note_next_step "VeraCrypt: download it from https://veracrypt.fr/en/Downloads.html" ;;
      6) apt_install gnupg pinentry-gnome3 ;;
      7) apt_install yubikey-manager ;;
      8) apt_install opensnitch python3-opensnitch-ui ;;
      9) apt_install lynis rkhunter ;;
      10) apt_install libimage-exiftool-perl mat2 ;;
      11) flatpak_install org.torproject.torbrowser-launcher "Tor Browser" ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

configure_linux_settings() {
  if [[ "$APPLY_SETTINGS" != "y" ]]; then
    echo "Skipping security settings."
    return
  fi
  if is_dry_run; then
    echo "[dry-run] Skipping security settings."
    return
  fi
  echo "Applying security settings..."

  apt_install ufw unattended-upgrades
  # Allow SSH before enabling, so a remote session survives
  if is_deb_installed openssh-server; then
    sudo ufw allow OpenSSH >/dev/null || sudo ufw allow 22/tcp >/dev/null
  fi
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw --force enable || note_problem "ufw could not be enabled"

  # The non-interactive form of dpkg-reconfigure unattended-upgrades
  echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' |
    sudo debconf-set-selections
  sudo dpkg-reconfigure -f noninteractive unattended-upgrades ||
    note_problem "automatic security updates not enabled"

  if [[ "$MAKE_ZSH_DEFAULT" =~ ^[Yy] ]] && command -v zsh &>/dev/null; then
    # sudo, so chsh doesn't ask for the password again
    sudo chsh -s "$(command -v zsh)" "$USER" &&
      note_next_step "zsh is your login shell from your next login"
  fi
}

main() {
  if ! command -v apt-get &>/dev/null; then
    if is_dry_run; then
      echo "[dry-run] No apt-get here; continuing to show the flow."
    else
      echo "❌ This script supports Debian and Ubuntu (apt). Install packages by hand on other distros,"
      echo "   then run $SCRIPT_DIR/install.sh to sync the dotfiles."
      exit 1
    fi
  fi
  [[ -f /etc/os-release ]] && . /etc/os-release
  echo "Detected: ${PRETTY_NAME:-$(uname -s)} on $(uname -m)"

  gather_user_preferences

  is_dry_run || start_sudo_keepalive

  echo "Starting initial install..."
  install_terminal_apps
  install_editors_and_agents
  install_ai_apps
  install_desktop_apps
  install_dfp_tools
  install_vibe_coding
  write_bookmarks_file
  configure_linux_settings

  if is_dry_run; then
    echo "[dry-run] Skipping the dotfile sync."
  else
    echo "Syncing zsh dotfiles to your home directory..."
    SYNC_ANSWER="$SYNC_ANSWER" "$SCRIPT_DIR/install.sh" ||
      note_problem "dotfile sync failed: run $SCRIPT_DIR/install.sh"
  fi

  print_summary
}

# Run only when executed, so the functions can be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
