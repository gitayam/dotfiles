#!/bin/bash
# Linux hardening for Debian 13 and Ubuntu 24.04/26.04: check (read-only, the
# default) or apply.
#
#   harden.sh            report each control as PASS / FAIL / INFO / MANUAL
#   harden.sh --apply    apply the scriptable controls, then re-check them
#
# Sources: CIS Debian 13 / Ubuntu 24.04 benchmarks (levels in brackets), KSPP
# recommended settings, ssh-audit hardening guides, Docker and Tailscale docs.
# Settings that break common desktops are left out on purpose: user namespaces
# stay on (Flatpak, Chrome and Electron sandboxes), squashfs and overlay stay
# loadable (snaps, Docker), /tmp keeps exec, IPv6 stays on.
#
# Every config goes into a drop-in file named *dotfiles-hardening*, so it is
# easy to find and remove. sshd and sudoers changes are validated before they
# take effect and removed again if validation fails.

MODE="check"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

PASS=0; FAIL=0; MANUAL=0
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
TARGET_HOME="${TARGET_HOME:-$HOME}"

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

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

write_root_file() {  # write_root_file <path> <mode>; content on stdin
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  sudo install -D -m "$2" -o root -g root "$tmp" "$1"
  rm -f "$tmp"
}

# --- Kernel and network sysctls ------------------------------------------------

SYSCTL_FILE=/etc/sysctl.d/60-dotfiles-hardening.conf
# Loose reverse-path filtering where traffic legitimately arrives asymmetrically:
# Docker hosts and anything forwarding (Tailscale subnet routers/exit nodes)
rp_filter_value() {
  if command -v docker &>/dev/null || [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]; then
    echo 2
  else
    echo 1
  fi
}
sysctl_settings() {
  cat <<EOF
# Managed by dotfiles linux/harden.sh. Network: CIS L1 3.3.x. Kernel: CIS L1/L2 and KSPP.
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0
net.ipv4.conf.all.rp_filter=$(rp_filter_value)
net.ipv4.conf.default.rp_filter=$(rp_filter_value)
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
kernel.yama.ptrace_scope=1
kernel.perf_event_paranoid=3
kernel.randomize_va_space=2
kernel.sysrq=0
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
fs.suid_dumpable=0
dev.tty.ldisc_autoload=0
vm.unprivileged_userfaultfd=0
EOF
}
check_sysctl() {
  local line key want have
  while IFS= read -r line; do
    [[ "$line" == \#* || -z "$line" ]] && continue
    key=${line%%=*}; want=${line#*=}
    have=$(sysctl -n "$key" 2>/dev/null) || continue  # key absent on this kernel
    [[ "$have" == "$want" ]] || return 1
  done <<< "$(sysctl_settings)"
}
apply_sysctl() {
  sysctl_settings | write_root_file "$SYSCTL_FILE" 0644
  sudo sysctl --system
}
sysctl_mismatches() {
  local line key want have out=""
  while IFS= read -r line; do
    [[ "$line" == \#* || -z "$line" ]] && continue
    key=${line%%=*}; want=${line#*=}
    have=$(sysctl -n "$key" 2>/dev/null) || continue
    [[ "$have" == "$want" ]] || out+="${key}=${have} (want ${want}) "
  done <<< "$(sysctl_settings)"
  echo "$out"
}

# --- SSH server ------------------------------------------------------------------

SSHD_FILE=/etc/ssh/sshd_config.d/10-dotfiles-hardening.conf
openssh_version() { ssh -V 2>&1 | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\1 \2/p'; }
sshd_settings() {
  local major minor kex
  read -r major minor <<< "$(openssh_version)"
  major=${major:-0}; minor=${minor:-0}
  # ssh-audit's Ubuntu 24.04 list; OpenSSH 10 adds ML-KEM post-quantum key exchange
  kex="sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512"
  [[ $major -ge 10 ]] && kex="mlkem768x25519-sha256,$kex"
  echo "# Managed by dotfiles linux/harden.sh (ssh-audit.com hardening guides)"
  echo "PermitRootLogin no"
  echo "PasswordAuthentication no"
  echo "KbdInteractiveAuthentication no"
  echo "AuthenticationMethods publickey"
  echo "PermitEmptyPasswords no"
  echo "MaxAuthTries 3"
  echo "LoginGraceTime 30"
  echo "X11Forwarding no"
  echo "AllowAgentForwarding no"
  echo "PermitUserEnvironment no"
  echo "ClientAliveInterval 300"
  echo "ClientAliveCountMax 3"
  echo "KexAlgorithms $kex"
  echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-gcm@openssh.com,aes128-ctr"
  echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com"
  # RequiredRSASize arrived in OpenSSH 9.4
  if [[ $major -gt 9 || ( $major -eq 9 && $minor -ge 4 ) ]]; then
    echo "RequiredRSASize 3072"
  fi
}
check_sshd() { [[ -f "$SSHD_FILE" ]]; }
apply_sshd() {
  # Never turn off passwords for someone without a key: that locks them out
  [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]] || return 1
  sshd_settings | write_root_file "$SSHD_FILE" 0644
  # 10- sorts before cloud images' 50-cloud-init.conf; sshd keeps the first value
  if sudo sshd -t; then
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
  else
    sudo rm -f "$SSHD_FILE"
    return 1
  fi
}

# --- Kernel modules ----------------------------------------------------------------

MODPROBE_FILE=/etc/modprobe.d/60-dotfiles-hardening.conf
# CIS L1 filesystems nobody mounts on a workstation, and CIS L2 network
# protocols with a history of kernel bugs. Left loadable: hfs/hfsplus (Mac
# drives), udf (DVDs), usb-storage (thumb drives), squashfs (snaps), overlay
# (Docker).
BLOCKED_MODULES="cramfs freevxfs jffs2 dccp tipc rds sctp"
check_modules() {
  local m
  for m in $BLOCKED_MODULES; do
    modprobe -n -v "$m" 2>/dev/null | grep -q 'install /bin/false' || return 1
  done
}
apply_modules() {
  local m
  {
    echo "# Managed by dotfiles linux/harden.sh"
    for m in $BLOCKED_MODULES; do
      echo "install $m /bin/false"
      echo "blacklist $m"
    done
  } | write_root_file "$MODPROBE_FILE" 0644
}

# --- Core dumps ----------------------------------------------------------------

check_coredumps() {
  [[ -f /etc/security/limits.d/60-dotfiles-hardening.conf && -f /etc/systemd/coredump.conf.d/60-dotfiles-hardening.conf ]]
}
apply_coredumps() {
  printf '%s\n' '# Managed by dotfiles linux/harden.sh (CIS 1.5.x)' '* hard core 0' |
    write_root_file /etc/security/limits.d/60-dotfiles-hardening.conf 0644
  printf '%s\n' '# Managed by dotfiles linux/harden.sh' '[Coredump]' 'Storage=none' 'ProcessSizeMax=0' |
    write_root_file /etc/systemd/coredump.conf.d/60-dotfiles-hardening.conf 0644
}

# --- Firewall ------------------------------------------------------------------

check_ufw() { sudo -n ufw status 2>/dev/null | grep -q "Status: active"; }
apply_ufw() {
  is_installed ufw || sudo apt-get install -y -qq ufw
  # Allow SSH before enabling, so a remote session survives
  if is_installed openssh-server; then
    sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow 22/tcp >/dev/null
  fi
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw --force enable
}

# --- Updates -------------------------------------------------------------------

check_auto_updates() {
  apt-config dump APT::Periodic::Unattended-Upgrade 2>/dev/null | grep -q '"1"'
}
apply_auto_updates() {
  is_installed unattended-upgrades || sudo apt-get install -y -qq unattended-upgrades
  echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' |
    sudo debconf-set-selections
  sudo dpkg-reconfigure -f noninteractive unattended-upgrades
}

# --- sudo, logging, misc ---------------------------------------------------------

SUDOERS_FILE=/etc/sudoers.d/60-dotfiles-hardening
is_sudo_rs() { sudo --version 2>/dev/null | grep -qi 'sudo-rs'; }
check_sudoers() { is_sudo_rs || [[ -f "$SUDOERS_FILE" ]]; }
apply_sudoers() {
  local tmp
  tmp=$(mktemp)
  printf '%s\n' '# Managed by dotfiles linux/harden.sh (CIS 5.2.x)' 'Defaults use_pty' \
    'Defaults logfile="/var/log/sudo.log"' > "$tmp"
  # visudo validates before anything is installed; a bad sudoers file locks sudo
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 0440 -o root -g root "$tmp" "$SUDOERS_FILE"
  fi
  rm -f "$tmp"
}
check_journald() { [[ -f /etc/systemd/journald.conf.d/60-dotfiles-hardening.conf ]]; }
apply_journald() {
  printf '%s\n' '# Managed by dotfiles linux/harden.sh' '[Journal]' 'Storage=persistent' 'SystemMaxUse=1G' |
    write_root_file /etc/systemd/journald.conf.d/60-dotfiles-hardening.conf 0644
  sudo systemctl restart systemd-journald
}
check_ctrl_alt_del() { [[ "$(systemctl is-enabled ctrl-alt-del.target 2>/dev/null)" == "masked" ]]; }
apply_ctrl_alt_del() { sudo systemctl mask ctrl-alt-del.target; }
LEGACY_PACKAGES="telnet rsh-client nis talk"
check_no_legacy() {
  local p
  for p in $LEGACY_PACKAGES; do is_installed "$p" && return 1; done
  return 0
}
apply_no_legacy() {
  local p
  for p in $LEGACY_PACKAGES; do is_installed "$p" && sudo apt-get purge -y -qq "$p"; done
}

# Wi-Fi MAC randomization (Privacy Guides). "stable" keeps one address per
# network, so captive portals don't ask again on every connect.
NM_FILE=/etc/NetworkManager/conf.d/00-dotfiles-macrandomize.conf
has_wifi() { compgen -G '/sys/class/net/*/wireless' >/dev/null; }
check_mac_random() { [[ -f "$NM_FILE" ]]; }
apply_mac_random() {
  printf '%s\n' '# Managed by dotfiles linux/harden.sh' '[device]' 'wifi.scan-rand-mac-address=yes' \
    '' '[connection]' 'wifi.cloned-mac-address=stable' 'ethernet.cloned-mac-address=stable' |
    write_root_file "$NM_FILE" 0644
}

run_controls() {
  echo "== Disk and boot"
  if lsblk -no TYPE 2>/dev/null | grep -q crypt; then
    report PASS "Full-disk encryption (LUKS) in use"
  else
    report MANUAL "Full-disk encryption (LUKS)" "not detected; it can't be added in place: back up and reinstall with encryption"
  fi
  if command -v mokutil &>/dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
      report PASS "Secure Boot on"
    else
      report INFO "Secure Boot off" "turn it on in firmware settings; DKMS modules (NVIDIA, VirtualBox) then need MOK signing"
    fi
  fi
  if command -v aa-enabled &>/dev/null && [[ "$(aa-enabled 2>/dev/null)" == "Yes" ]]; then
    report PASS "[L1] AppArmor enabled"
  else
    report FAIL "[L1] AppArmor enabled" "install apparmor and apparmor-utils"
  fi

  echo "== Kernel and network"
  if check_sysctl; then
    report PASS "[L1/L2, KSPP] Kernel and network sysctls"
  elif [[ "$MODE" == "apply" ]]; then
    apply_sysctl >/dev/null 2>&1
    if check_sysctl; then
      report PASS "[L1/L2, KSPP] Kernel and network sysctls" "applied"
    else
      report FAIL "[L1/L2, KSPP] Kernel and network sysctls" "still differ: $(sysctl_mismatches)"
    fi
  else
    report FAIL "[L1/L2, KSPP] Kernel and network sysctls" "$(sysctl_mismatches)"
  fi
  control "[L1/L2] Unused filesystems and network protocols blocked" check_modules apply_modules
  control "[L1 1.5.x] Core dumps off" check_coredumps apply_coredumps

  echo "== Firewall and exposure"
  if command -v ufw &>/dev/null && ! sudo -n true 2>/dev/null && [[ "$MODE" == "check" ]]; then
    report INFO "ufw status" "needs sudo to read; run 'sudo ufw status'"
  else
    control "[L1] ufw on (deny incoming, allow outgoing)" check_ufw apply_ufw
  fi
  if command -v docker &>/dev/null; then
    local ports exposed
    # docker ps, not ss: without root, ss can't see docker-proxy and would
    # report nothing exposed without having looked
    if ports=$(docker ps --format '{{.Ports}}' 2>/dev/null || sudo -n docker ps --format '{{.Ports}}' 2>/dev/null); then
      exposed=$(tr ',' '\n' <<< "$ports" | grep -cE '(0\.0\.0\.0|\[?::\]?):[0-9]+->')
      if [[ "$exposed" -gt 0 ]]; then
        report MANUAL "Docker publishes $exposed port(s) on all interfaces" "ufw does not filter these; publish as 127.0.0.1:PORT:PORT or filter in DOCKER-USER"
      else
        report PASS "No Docker ports published on all interfaces"
      fi
    else
      report INFO "Docker port exposure not checked" "no access to the Docker daemon; run: sudo docker ps"
    fi
  fi
  if ip link show tailscale0 &>/dev/null && is_installed openssh-server; then
    report INFO "Tailscale host" "consider SSH on the tailnet only: ufw allow in on tailscale0 to any port 22 proto tcp, then delete the public OpenSSH rule"
  fi

  echo "== SSH server"
  if ! is_installed openssh-server; then
    report PASS "No SSH server installed"
  elif [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
    control "SSH: keys only, no root, modern algorithms (ssh-audit)" check_sshd apply_sshd
  else
    report FAIL "SSH: keys only" "no $TARGET_HOME/.ssh/authorized_keys yet; passwords left on so you aren't locked out"
  fi

  echo "== Updates"
  control "[L1 1.2.2.1] Automatic security updates" check_auto_updates apply_auto_updates
  if command -v fwupdmgr &>/dev/null; then
    report INFO "Firmware updates" "fwupdmgr refresh && fwupdmgr get-updates"
  fi

  echo "== Accounts, logging and services"
  if is_sudo_rs; then
    report INFO "sudo-rs in use" "use_pty is on by default; it has no logfile option"
  fi
  control "[L1 5.2.x] sudo uses a pty and logs to /var/log/sudo.log" check_sudoers apply_sudoers
  control "[L1] Persistent, size-capped journal" check_journald apply_journald
  control "[STIG] Ctrl-Alt-Del reboot off" check_ctrl_alt_del apply_ctrl_alt_del
  control "[L1] Legacy clients removed (telnet, rsh, nis, talk)" check_no_legacy apply_no_legacy
  if has_wifi && [[ -d /etc/NetworkManager ]]; then
    control "Wi-Fi MAC address randomization (NetworkManager)" check_mac_random apply_mac_random
  fi

  echo "== Advice"
  if command -v lynis &>/dev/null; then
    report INFO "Score the result" "sudo lynis audit system"
  fi
  report INFO "Flatpak permissions" "review with Flatseal or 'flatpak override'"
}

if [[ "$MODE" == "apply" ]] && ! sudo -n true 2>/dev/null; then
  echo "--apply needs sudo. Enter your password:"
  sudo -v || exit 1
fi

[[ -f /etc/os-release ]] && . /etc/os-release
echo "Linux hardening ($MODE) — ${PRETTY_NAME:-unknown}, kernel $(uname -r)"
run_controls
echo ""
echo "Summary: $PASS pass, $FAIL fail, $MANUAL to do by hand"
[[ "$MODE" == "check" && $FAIL -gt 0 ]] && echo "Run with --apply to fix the scriptable ones."
if [[ "$MODE" == "apply" ]]; then
  echo "Some changes take effect after a reboot or reconnect (modules, MAC randomization)."
fi
[[ $FAIL -eq 0 ]]
