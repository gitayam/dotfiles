#!/bin/bash
# macOS hardening: check (read-only, the default) or apply.
#
#   harden.sh            report each control as PASS / FAIL / INFO / MANUAL
#   harden.sh --apply    apply the scriptable controls, then re-check them
#   --keep-remote        keep Remote Login and Screen Sharing (Tailscale/SSH
#                        access); SSH is hardened instead of turned off
#   --touchid            only enable Touch ID for sudo (used by the setup
#                        script before it installs apps)
#
# Controls follow the NIST macOS Security Compliance Project (mSCP) baselines
# for macOS 27 (rule IDs in brackets) and the CIS benchmark levels they map
# to. Controls that macOS only honours through a configuration profile or
# System Settings are reported as MANUAL, never "applied".
#
# Runs on the stock /bin/bash (3.2). --apply needs sudo; initial_macos_setup.sh
# calls it after priming sudo.

MODE="check"
KEEP_REMOTE=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --keep-remote) KEEP_REMOTE=1 ;;
    --touchid) MODE="touchid" ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

# Run as yourself: under sudo, $HOME and the per-user settings (Siri, Terminal,
# Bluetooth) would be root's, and the report would describe the wrong account
if [[ $EUID -eq 0 ]]; then
  echo "Run harden.sh as your own user, not with sudo; it asks for sudo itself."
  exit 2
fi
PATH="$PATH:/usr/sbin:/sbin"

FW=/usr/libexec/ApplicationFirewall/socketfilterfw
PASS=0; FAIL=0; MANUAL=0

IS_LAPTOP=0
pmset -g batt 2>/dev/null | grep -q InternalBattery && IS_LAPTOP=1

report() {  # report <PASS|FAIL|INFO|MANUAL> <label> [detail]
  local status="$1" label="$2" detail="$3"
  case "$status" in
    PASS) PASS=$((PASS + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
    MANUAL) MANUAL=$((MANUAL + 1)) ;;
  esac
  printf '%-6s %s%s\n' "$status" "$label" "${detail:+ — $detail}"
}

# control <label> <check function> [apply function]
# The check returns 0 when compliant. In apply mode a failing control is
# applied and checked again, so the report shows the real end state.
control() {
  local label="$1" check="$2" apply="$3"
  if $check; then
    report PASS "$label"
  elif [[ "$MODE" == "apply" && -n "$apply" ]]; then
    $apply >/dev/null 2>&1
    if $check; then
      report PASS "$label" "applied"
    else
      report FAIL "$label" "apply did not take effect"
    fi
  else
    report FAIL "$label"
  fi
}

disabled_in_launchd() {  # service label is listed as disabled
  launchctl print-disabled system 2>/dev/null | grep -q "\"$1\" => disabled"
}

listening_on() {  # TCP port has a listener on any interface
  local out
  out=$(netstat -anp tcp 2>/dev/null)
  # No output means netstat failed: count it as listening rather than pass blind
  [[ -z "$out" ]] && return 0
  grep -qE "[.*]$1 .*LISTEN" <<< "$out"
}

# --- System integrity --------------------------------------------------------

check_sip() { csrutil status 2>/dev/null | grep -q "status: enabled\."; }
check_sealed() { mount | grep ' on / ' | grep -q sealed; }
check_gatekeeper() { spctl --status 2>/dev/null | grep -q "assessments enabled"; }
# --master-enable was renamed --global-enable in macOS 15
apply_gatekeeper() { sudo spctl --global-enable 2>/dev/null || sudo spctl --master-enable; }
check_xprotect() {
  local out
  out=$(xprotect status 2>/dev/null) || return 1
  [[ -n "$out" ]] && ! grep -qi disabled <<< "$out"
}

# --- Encryption and updates --------------------------------------------------

check_filevault() { fdesetup status 2>/dev/null | grep -q "FileVault is On"; }
check_auto_updates() {
  local key
  for key in AutomaticDownload AutomaticallyInstallMacOSUpdates CriticalUpdateInstall ConfigDataInstall; do
    [[ "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate "$key" 2>/dev/null)" == "1" ]] || return 1
  done
}

# --- Firewall ----------------------------------------------------------------

check_firewall() { "$FW" --getglobalstate 2>/dev/null | grep -q "enabled"; }
apply_firewall() { sudo "$FW" --setglobalstate on && sudo pkill -HUP socketfilterfw; }
check_stealth() { "$FW" --getstealthmode 2>/dev/null | grep -q " on"; }
apply_stealth() { sudo "$FW" --setstealthmode on && sudo pkill -HUP socketfilterfw; }

# --- Accounts and login ------------------------------------------------------

check_autologin_off() { sysadminctl -autologin status 2>&1 | grep -q "disabled"; }
apply_autologin_off() { sudo sysadminctl -autologin off; }
check_guest_off() { sysadminctl -guestAccount status 2>&1 | grep -q "disabled"; }
apply_guest_off() { sudo sysadminctl -guestAccount off; }
check_smb_guest_off() {
  sysadminctl -smbGuestAccess status 2>&1 | grep -q "disabled" &&
    sysadminctl -afpGuestAccess status 2>&1 | grep -q "disabled"
}
apply_smb_guest_off() { sudo sysadminctl -smbGuestAccess off; sudo sysadminctl -afpGuestAccess off; }
check_login_fields() {
  [[ "$(defaults read /Library/Preferences/com.apple.loginwindow SHOWFULLNAME 2>/dev/null)" == "1" ]]
}
apply_login_fields() { sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true; }
check_no_hints() {
  [[ "$(defaults read /Library/Preferences/com.apple.loginwindow RetriesUntilHint 2>/dev/null)" == "0" ]]
}
apply_no_hints() { sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0; }
check_screenlock() { sysadminctl -screenLock status 2>&1 | grep -qE 'immediate|delay is 0 seconds'; }

# --- sudo --------------------------------------------------------------------

# Touch ID belongs in sudo_local, which survives OS updates; a pam_tid line in
# /etc/pam.d/sudo itself is wiped by the next update.
# Any active pam_tid line counts, whatever path it uses for the module
check_touchid_sudo_local() { grep -qsE '^[[:space:]]*auth[[:space:]].*pam_tid' /etc/pam.d/sudo_local; }
has_touchid() { bioutil -rs 2>/dev/null | grep -q 'Biometrics functionality: 1'; }
# sudo_local is included at the top of /etc/pam.d/sudo and survives updates.
# Created whole when absent; otherwise appended after making sure the file ends
# in a newline: a line glued onto the last one breaks PAM, and sudo, for everyone.
apply_touchid_sudo_local() {
  local f=/etc/pam.d/sudo_local tmp
  if [[ ! -e "$f" ]]; then
    tmp=$(mktemp)
    printf '%s\n' '# sudo_local: local sudo PAM config that survives macOS updates' \
      '# Managed by dotfiles macos/harden.sh' 'auth       sufficient     pam_tid.so' > "$tmp"
    sudo install -m 0444 -o root -g wheel "$tmp" "$f"
    rm -f "$tmp"
  else
    [[ -n "$(tail -c 1 "$f")" ]] && printf '\n' | sudo tee -a "$f" >/dev/null
    echo 'auth       sufficient     pam_tid.so' | sudo tee -a "$f" >/dev/null
  fi
}
# zz-: sudo applies the last matching Defaults, so this must sort after other
# drop-ins (e.g. Amphetamine's)
SUDOERS_DROPIN=/etc/sudoers.d/zz-dotfiles-hardening
# Per-terminal tickets and a log line for every sudo command (CIS 5.5, 5.11).
# The timeout stays at the default 5 minutes: CIS's 0 would prompt on every
# command and break the setup's own sudo keepalive.
check_sudoers() { grep -qs '^Defaults timestamp_type=tty' "$SUDOERS_DROPIN" && grep -qs '^Defaults log_allowed' "$SUDOERS_DROPIN"; }
apply_sudoers() {
  local tmp
  tmp=$(mktemp)
  printf '%s\n' '# Managed by dotfiles macos/harden.sh' 'Defaults timestamp_type=tty' 'Defaults log_allowed' > "$tmp"
  # visudo validates before anything is installed; a bad sudoers file locks sudo
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 0440 -o root -g wheel "$tmp" "$SUDOERS_DROPIN"
  fi
  rm -f "$tmp"
}

# --- Sharing services --------------------------------------------------------

check_ssh_off() { ! listening_on 22; }
apply_ssh_off() {
  sudo systemsetup -setremotelogin -f off
  sudo launchctl disable system/com.openssh.sshd
}
SSHD_DROPIN=/etc/ssh/sshd_config.d/01-hardening.conf
# Must sort before macOS's 100-macos.conf: sshd keeps the first value it reads
check_sshd_hardened() {
  local cfg
  if cfg=$(sudo -n sshd -T 2>/dev/null); then
    grep -qx 'passwordauthentication no' <<< "$cfg" && grep -qx 'permitrootlogin no' <<< "$cfg"
  else
    [[ -f "$SSHD_DROPIN" ]]  # the effective config needs sudo to read
  fi
}
writable_by_others() { local m; m=$(stat -f %Lp "$1" 2>/dev/null) || return 0; (( (8#$m & 8#022) != 0 )); }
# Why the user's keys would not work once passwords are off; empty when they will
ssh_key_problem() {
  local ak="$HOME/.ssh/authorized_keys"
  [[ -s "$ak" ]] || { echo "no ~/.ssh/authorized_keys yet"; return; }
  writable_by_others "$HOME/.ssh" && { echo "~/.ssh is writable by group/others (sshd would ignore the keys)"; return; }
  writable_by_others "$ak" && { echo "authorized_keys is writable by group/others (sshd would ignore the keys)"; return; }
  ssh-keygen -lf "$ak" >/dev/null 2>&1 || echo "no valid key in ~/.ssh/authorized_keys"
}
apply_sshd_hardened() {
  # Never turn off passwords for someone whose key won't work: that locks them out
  [[ -z "$(ssh_key_problem)" ]] || return 1
  printf '%s\n' '# Managed by dotfiles macos/harden.sh' \
    'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' |
    sudo tee "$SSHD_DROPIN" >/dev/null
  # Remove it again if sshd rejects the result
  sudo sshd -t || { sudo rm -f "$SSHD_DROPIN"; return 1; }
}
check_screensharing_off() { disabled_in_launchd com.apple.screensharing; }
apply_screensharing_off() { sudo launchctl disable system/com.apple.screensharing; sudo launchctl bootout system/com.apple.screensharing 2>/dev/null; return 0; }
check_ard_off() { ! pgrep -qx ARDAgent; }
apply_ard_off() {
  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
}
check_smbd_off() { disabled_in_launchd com.apple.smbd; }
apply_smbd_off() { sudo launchctl disable system/com.apple.smbd; sudo launchctl bootout system/com.apple.smbd 2>/dev/null; return 0; }
check_rae_off() { disabled_in_launchd com.apple.AEServer; }
apply_rae_off() { sudo launchctl disable system/com.apple.AEServer; sudo launchctl bootout system/com.apple.AEServer 2>/dev/null; return 0; }
check_printer_sharing_off() { cupsctl 2>/dev/null | grep -q '_share_printers=0'; }
apply_printer_sharing_off() { cupsctl --no-share-printers; }
check_bt_sharing_off() {
  [[ "$(defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled 2>/dev/null)" == "0" ]]
}
apply_bt_sharing_off() { defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false; }

# --- Privacy -----------------------------------------------------------------

check_siri_sharing_off() {
  [[ "$(defaults read com.apple.assistant.support "Siri Data Sharing Opt-In Status" 2>/dev/null)" == "2" ]]
}
apply_siri_sharing_off() { defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2; }
check_search_sharing_off() {
  [[ "$(defaults read com.apple.assistant.support "Search Queries Data Sharing Status" 2>/dev/null)" == "2" ]]
}
apply_search_sharing_off() { defaults write com.apple.assistant.support "Search Queries Data Sharing Status" -int 2; }
check_secure_keyboard() { [[ "$(defaults read com.apple.Terminal SecureKeyboardEntry 2>/dev/null)" == "1" ]]; }
apply_secure_keyboard() { defaults write com.apple.Terminal SecureKeyboardEntry -bool true; }
check_location_icon() {
  [[ "$(defaults read /Library/Preferences/com.apple.locationmenu ShowSystemServices 2>/dev/null)" == "1" ]]
}
apply_location_icon() { sudo defaults write /Library/Preferences/com.apple.locationmenu ShowSystemServices -bool true; }
check_auto_time() { sysadminctl -automaticTime status 2>&1 | grep -q "enabled"; }
apply_auto_time() { sudo sysadminctl -automaticTime on; }

# --- Power -------------------------------------------------------------------

pmset_value() { pmset -g custom 2>/dev/null | awk -v k="$1" '$1 == k {print $2}' | sort -u; }
check_powernap_off() { [[ "$(pmset_value powernap)" == "0" ]]; }
apply_powernap_off() { sudo pmset -a powernap 0; }
# Laptops only: an always-on Mac mini keeps wake-for-network so SSH/Tailscale
# can wake it
check_womp_off() { [[ "$(pmset_value womp)" == "0" ]]; }
apply_womp_off() { sudo pmset -a womp 0; }
check_battery_sleep() {
  local sleep
  sleep=$(pmset -g custom 2>/dev/null | awk '/Battery Power/{b=1} /AC Power/{b=0} b && $1=="sleep"{print $2}')
  [[ -n "$sleep" && "$sleep" -gt 0 && "$sleep" -le 15 ]]
}
apply_battery_sleep() { sudo pmset -b sleep 15 displaysleep 10; }

run_controls() {
  echo "== System integrity"
  control "[L1 5.1.2] System Integrity Protection on" check_sip
  control "[L1 5.1.4] Sealed system volume" check_sealed
  control "[L1 2.6.5] Gatekeeper on" check_gatekeeper apply_gatekeeper
  control "[L1 5.10] XProtect scans on" check_xprotect

  echo "== Encryption and updates"
  if check_filevault; then
    report PASS "[L1 2.6.6] FileVault on"
  else
    report MANUAL "[L1 2.6.6] FileVault on" "initial_macos_setup.sh offers it, or System Settings > Privacy & Security"
  fi
  if check_auto_updates; then
    report PASS "[L1 1.2-1.5] Automatic updates on"
  else
    report MANUAL "[L1 1.2-1.5] Automatic updates on" "System Settings > General > Software Update > Automatic updates (MDM-only on macOS 27)"
  fi

  echo "== Firewall"
  control "[L1 2.2.1] Application firewall on" check_firewall apply_firewall
  control "[L1 2.2.2] Firewall stealth mode" check_stealth apply_stealth

  echo "== Accounts and login"
  control "[L1 2.13.3] Automatic login off" check_autologin_off apply_autologin_off
  control "[L1 2.13.1] Guest account off" check_guest_off apply_guest_off
  control "[L1 2.13.2] SMB/AFP guest access off" check_smb_guest_off apply_smb_guest_off
  control "[L1 2.11.4] Login window asks for name and password" check_login_fields apply_login_fields
  control "[L1 2.11.5] No password hints" check_no_hints apply_no_hints
  if check_screenlock; then
    report PASS "[L1 2.11.2] Password immediately after sleep/screen saver"
  else
    report MANUAL "[L1 2.11.2] Password immediately after sleep/screen saver" "sysadminctl -screenLock immediate -password -"
  fi

  echo "== sudo"
  if has_touchid; then
    control "Touch ID for sudo in sudo_local (survives updates)" check_touchid_sudo_local apply_touchid_sudo_local
  else
    report INFO "No Touch ID sensor" "sudo keeps asking for the password"
  fi
  if grep -qs '^auth[[:space:]]*sufficient[[:space:]]*pam_tid.so' /etc/pam.d/sudo; then
    report INFO "pam_tid is also in /etc/pam.d/sudo" "macOS updates reset that file; sudo_local is the durable place"
  fi
  control "[L1 5.5, 5.11] sudo tty tickets and command logging" check_sudoers apply_sudoers

  echo "== Sharing services"
  if [[ $KEEP_REMOTE -eq 1 ]]; then
    if check_ssh_off; then
      report INFO "Remote Login (SSH) is off" "--keep-remote leaves it as is"
    elif [[ -z "$(ssh_key_problem)" ]]; then
      control "SSH: keys only, no root login" check_sshd_hardened apply_sshd_hardened
      [[ "$MODE" == "apply" ]] && report INFO "If SSH changed" "open a NEW ssh session and log in before closing this one"
    else
      report MANUAL "SSH: keys only" "not changed: $(ssh_key_problem); passwords stay on so you aren't locked out"
    fi
    report INFO "Screen Sharing / Remote Management left as is (--keep-remote)"
  else
    control "[L1 2.3.3.4] Remote Login (SSH) off" check_ssh_off apply_ssh_off
    control "[L1 2.3.3.1] Screen Sharing off" check_screensharing_off apply_screensharing_off
    control "[L1 2.3.3.5] Remote Management (ARD) off" check_ard_off apply_ard_off
  fi
  control "[L1 2.3.3.2] File Sharing (SMB) off" check_smbd_off apply_smbd_off
  control "[L1 2.3.3.6] Remote Apple Events off" check_rae_off apply_rae_off
  control "[L1 2.3.3.3] Printer Sharing off" check_printer_sharing_off apply_printer_sharing_off
  control "[L1 2.3.3.10] Bluetooth Sharing off" check_bt_sharing_off apply_bt_sharing_off
  if listening_on 7000; then
    report MANUAL "[L1 2.3.1.2] AirPlay Receiver off" "System Settings > General > AirDrop & Handoff (listens on all interfaces, ports 5000/7000)"
  else
    report PASS "[L1 2.3.1.2] AirPlay Receiver off"
  fi
  if [[ "$(defaults read com.apple.sharingd DiscoverableMode 2>/dev/null)" == "Everyone" ]]; then
    report MANUAL "[L1 2.3.1.1] AirDrop not open to everyone" "Control Center > AirDrop > Contacts Only"
  else
    report PASS "[L1 2.3.1.1] AirDrop not open to everyone"
  fi

  echo "== Privacy"
  control "[L1 2.6.3.2] Improve Siri & Dictation off" check_siri_sharing_off apply_siri_sharing_off
  control "[L1 2.9.1] Improve Search off" check_search_sharing_off apply_search_sharing_off
  control "[L1 6.4.1] Terminal Secure Keyboard Entry" check_secure_keyboard apply_secure_keyboard
  control "[L2 2.6.1.2] Location icon shown when used" check_location_icon apply_location_icon
  control "[L1 2.3.2.1] Automatic time" check_auto_time apply_auto_time

  echo "== Power"
  control "Power Nap off (no wake-ups to sync while closed)" check_powernap_off apply_powernap_off
  if [[ $IS_LAPTOP -eq 1 ]]; then
    control "[L1 2.10.2] Wake for network access off" check_womp_off apply_womp_off
    control "[L2 2.10.1] Battery: sleep within 15 min" check_battery_sleep apply_battery_sleep
  else
    report INFO "Desktop Mac: wake for network access kept, so SSH/Tailscale can wake it"
  fi

  echo "== Advice"
  if [[ "$(sysctl -n security.mac.lockdown_mode_state 2>/dev/null)" == "1" ]]; then
    report PASS "Lockdown Mode on"
  else
    report INFO "Lockdown Mode off" "for high-risk users: System Settings > Privacy & Security (can't be scripted)"
  fi
  report INFO "Review login and background items" "System Settings > General > Login Items, or KnockKnock"
  report INFO "Pending updates" "softwareupdate -l (install: sudo softwareupdate -i -a -R)"
}

if [[ "$MODE" != "check" ]] && ! sudo -n true 2>/dev/null; then
  echo "harden.sh --$MODE needs sudo. Enter your password:"
  sudo -v || exit 1
fi

if [[ "$MODE" == "touchid" ]]; then
  if ! has_touchid; then
    echo "No Touch ID sensor found; sudo keeps asking for the password."
  elif check_touchid_sudo_local; then
    echo "Touch ID for sudo is already enabled."
  else
    apply_touchid_sudo_local
    if check_touchid_sudo_local; then
      echo "✅ Touch ID for sudo enabled (works in local terminals, not over SSH)."
    else
      echo "⚠️  Could not enable Touch ID for sudo."; exit 1
    fi
  fi
  exit 0
fi

echo "macOS hardening ($MODE) — macOS $(sw_vers -productVersion), $([[ $IS_LAPTOP -eq 1 ]] && echo laptop || echo desktop)"
run_controls
echo ""
echo "Summary: $PASS pass, $FAIL fail, $MANUAL to do by hand"
[[ "$MODE" == "check" && $FAIL -gt 0 ]] && echo "Run with --apply to fix the scriptable ones."
[[ $FAIL -eq 0 ]]
