#!/usr/bin/env bash
# Regression tests for the dotfiles: syntax, shell startup, dots, git-wip,
# git-inventory, ssh-doctor, harden.sh logic and the setup dry runs.
# Runs on macOS (bash 3.2 compatible) and Linux; CI runs it on both.
#
#   tests/run.sh            all tests
#   tests/run.sh -v         also print each failing test's output
#
# Every test works in a scratch directory; nothing in $HOME is touched.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=0; [[ "${1:-}" == "-v" ]] && VERBOSE=1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tests.XXXXXX")
PASSED=0; FAILED=0; FAILURES=()
OS=$(uname -s)
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
# A scratch global git config: tests never read or write your ~/.gitconfig
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL="$WORK/gitconfig"
printf '[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

# check <name> <command...>: passes when the command exits 0
check() {
  local name="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    PASSED=$((PASSED + 1)); printf 'ok    %s\n' "$name"
  else
    FAILED=$((FAILED + 1)); FAILURES+=("$name"); printf 'FAIL  %s\n' "$name"
    [[ $VERBOSE -eq 1 ]] && printf '%s\n' "$out" | sed 's/^/      /'
  fi
}
# expect <name> <pattern> <command...>: passes when the output matches the pattern
expect() {
  local name="$1" pattern="$2"; shift 2
  local out
  out=$("$@" 2>&1)
  if grep -qE -- "$pattern" <<< "$out"; then
    PASSED=$((PASSED + 1)); printf 'ok    %s\n' "$name"
  else
    FAILED=$((FAILED + 1)); FAILURES+=("$name"); printf 'FAIL  %s\n' "$name"
    [[ $VERBOSE -eq 1 ]] && printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# A scratch HOME whose zsh files are links to this checkout, like a synced machine
make_home() {
  local h="$WORK/home-$1" f
  mkdir -p "$h/Git"
  ln -sfn "$REPO" "$h/Git/dotfiles"
  for f in "$REPO"/shared/zsh/.zsh_* "$REPO/shared/zsh/.zshrc"; do
    [[ "$f" == *.original ]] && continue
    ln -sfn "$f" "$h/${f##*/}"
  done
  echo "$h"
}

echo "== Syntax"
syntax_bash() {
  local f bad=0
  for f in "$REPO"/macos/*.sh "$REPO"/linux/*.sh "$REPO"/shared/setup/*.sh "$REPO"/tests/*.sh \
           "$REPO"/shared/bin/git-wip "$REPO"/shared/bin/git-sync-all "$REPO"/shared/zsh/.zsh_*; do
    [[ "$f" == *.original ]] && continue
    bash -n "$f" || { echo "bash -n failed: $f"; bad=1; }
  done
  return $bad
}
check "bash parses every script and .zsh_* file (Linux loader)" syntax_bash
if command -v zsh >/dev/null; then
  syntax_zsh() {
    local f bad=0
    for f in "$REPO"/shared/zsh/.zsh_* "$REPO/shared/zsh/.zshrc" "$REPO/shared/zsh/claude-aliases.zsh"; do
      [[ "$f" == *.original ]] && continue
      zsh -n "$f" || { echo "zsh -n failed: $f"; bad=1; }
    done
    return $bad
  }
  check "zsh parses every zsh file" syntax_zsh
fi
check "git-inventory compiles" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REPO/shared/bin/git-inventory"
if command -v node >/dev/null; then
  check "secrets scripts parse" bash -c "node --check '$REPO/typescript/sync-secrets.js' && node --check '$REPO/typescript/get-secrets.js'"
fi

echo "== Shell startup"
H=$(make_home startup)
if command -v zsh >/dev/null; then
  # Silent and error-free: banners and errors on every shell start were removed
  startup_silent() {
    local out
    out=$(env -i HOME="$H" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c exit </dev/null 2>&1)
    [[ -z "$out" ]] || { echo "$out"; return 1; }
  }
  check "zsh -i starts silently with the repo .zshrc" startup_silent
  # Re-sourcing must not trip over aliases that became functions
  resource_clean() {
    local out
    out=$(env -i HOME="$H" TERM=xterm PATH=/usr/bin:/bin zsh -c \
      'alias run-kp="kp --db"; alias vcheck=x; alias dbash=x; source ~/.zshrc </dev/null; source ~/.zshrc </dev/null' 2>&1)
    [[ -z "$out" ]] || { echo "$out"; return 1; }
  }
  check "re-sourcing .zshrc over old aliases is clean" resource_clean
fi
bash_loads() {
  local f err=""
  for f in aliases aws functions developer apps network transfer security utils docker handle_files encryption git linux_compat; do
    err+=$(env -i HOME="$H" PATH=/usr/bin:/bin bash -c "source '$H/.zsh_$f'" 2>&1 >/dev/null)
  done
  [[ -z "$err" ]] || { echo "$err"; return 1; }
}
check "bash sources every .zsh_* file without errors" bash_loads

echo "== dots"
dots_lint() {
  local out
  out=$(env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_functions; dots --lint' | grep -v claude-aliases)
  [[ -z "$out" ]] || { echo "undocumented: $out"; return 1; }
}
check "every command outside claude-aliases has a description" dots_lint
expect "dots search finds genpin" '^genpin' env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_functions; dots password'
expect "dots -s shows a function's description" "without converting it" env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_functions; dots -s vcheck'
if command -v zsh >/dev/null; then
  expect "dots -s works in zsh too" "without converting it" env -i HOME="$H" PATH=/usr/bin:/bin zsh -c 'source ~/.zsh_functions; dots -s vcheck'
fi
expect "vcheck checks without converting" '\[false\]' env -i HOME="$H" PATH=/usr/bin:/bin bash -c \
  'source ~/.zsh_functions; check_video_format() { echo "[$2]"; }; vcheck x.mp4'

echo "== git wip"
wip_setup() {
  local d="$WORK/wip"
  rm -rf "$d"; mkdir -p "$d"
  git init -q --bare "$d/remote.git"
  git clone -q "$d/remote.git" "$d/work" 2>/dev/null
  git -C "$d/work" commit -q --allow-empty -m init
  git -C "$d/work" push -q origin HEAD 2>/dev/null
  echo "$d/work"
}
W=$(wip_setup)
wip_refuses_env() {
  echo ok > "$W/keep.txt"; git -C "$W" add keep.txt
  echo "X=1" > "$W/.env"
  (cd "$W" && "$REPO/shared/bin/git-wip") && return 1
  # Refused, and the index is exactly as before: keep.txt staged, .env not
  [[ "$(git -C "$W" diff --cached --name-only)" == "keep.txt" ]] || return 1
  rm -f "$W/.env"
}
check "git wip refuses .env and restores the index" wip_refuses_env
wip_refuses_key() {
  printf 'key = "AKIA%s"\n' ABCDEFGHIJKLMNOP > "$W/cfg.py"
  local out; out=$(cd "$W" && "$REPO/shared/bin/git-wip" 2>&1) && return 1
  grep -q "AWS access key id" <<< "$out" || return 1
  ! grep -q ABCDEFGHIJKLMNOP <<< "$out"  # names the kind, never the value
  local rc=$?; rm -f "$W/cfg.py"; return $rc
}
check "git wip refuses an AWS-shaped value without printing it" wip_refuses_key
wip_commits() {
  echo "X=" > "$W/.env.example"
  (cd "$W" && "$REPO/shared/bin/git-wip" "tested") >/dev/null || return 1
  [[ "$(git -C "$W" log -1 --format=%s)" == "wip: tested" ]] &&
    [[ "$(git -C "$W" rev-parse HEAD)" == "$(git -C "$W" rev-parse '@{u}')" ]]
}
check "git wip commits and pushes (.env.example allowed)" wip_commits

echo "== git-inventory"
inv_setup() {
  local d="$WORK/inv"
  rm -rf "$d"; mkdir -p "$d/roots"
  git init -q --bare "$d/remote.git"
  git init -q "$d/roots/clean"; git -C "$d/roots/clean" commit -q --allow-empty -m i
  git -C "$d/roots/clean" remote add origin "$d/remote.git"; git -C "$d/roots/clean" push -q origin HEAD 2>/dev/null
  git init -q "$d/roots/noremote"; git -C "$d/roots/noremote" commit -q --allow-empty -m i
  git init -q "$d/roots/secret"; git -C "$d/roots/secret" commit -q --allow-empty -m i
  git -C "$d/roots/secret" remote add origin "https://user:TOKENVALUE@example.invalid/r.git"
  git -C "$d/roots/clean" worktree add -q "$d/outside-wt" -b wt 2>/dev/null
  echo dirty > "$d/outside-wt/new.txt"
  mkdir -p "$d/roots/broken/.git"
  echo "$d"
}
I=$(inv_setup)
inv_run() { (cd "$I" && "$REPO/shared/bin/git-inventory" roots --json "$I/inv.json"); }
expect "git-inventory flags a repo with no remote" 'noremote .*no remote' inv_run
expect "git-inventory finds a dirty worktree outside the roots" 'worktree .*outside-wt.*1 untracked' inv_run
expect "git-inventory reports a broken repo instead of passing it" 'broken .*could not be read' inv_run
inv_redacts() { inv_run >/dev/null; ! grep -q TOKENVALUE "$I/inv.json"; }
check "git-inventory redacts credentials in remote URLs" inv_redacts

echo "== ssh-doctor"
if command -v ssh-agent >/dev/null; then
  SD="$WORK/sshbad"; mkdir -p "$SD/.ssh"; chmod 755 "$SD/.ssh"
  : > "$SD/.ssh/id_test"; chmod 644 "$SD/.ssh/id_test"
  printf 'Host box\n    HostName 10.9.9.9\n    IdentityFile %s/.ssh/missing\n    IdentitiesOnly yes\n' "$SD" > "$SD/.ssh/config"
  ssh_doctor_bad() {
    bash -c "eval \$(ssh-agent -s) >/dev/null; export HOME='$SD'; source '$REPO/shared/zsh/.zsh_network' >/dev/null 2>&1;
             ssh-doctor; rc=\$?; kill \$SSH_AGENT_PID; exit \$rc"
  }
  expect "ssh-doctor: private key readable by others" 'private key .*id_test is 644' ssh_doctor_bad
  expect "ssh-doctor: agent without keys" 'agent is running but has no keys' ssh_doctor_bad
  expect "ssh-doctor: IdentitiesOnly with a missing key" 'Host box: IdentitiesOnly yes' ssh_doctor_bad
fi

echo "== harden.sh logic"
# Linux sysctl check against a fake /proc/sys: stricter values pass, weaker
# ones and unreadable ones fail (an unreadable key used to pass silently)
sysctl_fake() {
  local P="$WORK/proc-$1" fn
  fn=$(sed -n '/^rp_filter_value()/,/^check_sysctl()/p' "$REPO/linux/harden.sh")
  mkdir -p "$P"
  bash -c "$fn"$'\n''command(){ return 1; }; sysctl(){ echo 0; }; sysctl_settings' | grep -v '^#' | grep -v '\*' |
    while IFS== read -r k v; do mkdir -p "$P/$(dirname "${k//.//}")"; echo "$v" > "$P/${k//.//}"; done
  mkdir -p "$P/net/ipv4/conf/eth0"; echo 1 > "$P/net/ipv4/conf/eth0/rp_filter"
  case "$1" in
    stricter) echo 2 > "$P/kernel/yama/ptrace_scope" ;;
    weak) echo 0 > "$P/kernel/kptr_restrict"; echo 2 > "$P/net/ipv4/conf/eth0/rp_filter"
          chmod 000 "$P/net/core/bpf_jit_harden" ;;
  esac
  # sudo stubbed to fail: CI runners have passwordless sudo, which would read it anyway
  PROC_SYS="$P" bash -c "$fn"$'\n''command(){ return 1; }; sysctl(){ echo 0; }; sudo(){ return 1; }; p=$(sysctl_problems); echo "${p:-PASS}"'
  chmod 644 "$P/net/core/bpf_jit_harden" 2>/dev/null
}
expect "linux sysctl: stricter value passes" '^PASS$' sysctl_fake stricter
expect "linux sysctl: weak kptr_restrict fails" 'kernel.kptr_restrict=0' sysctl_fake weak
expect "linux sysctl: loose per-interface rp_filter fails" 'eth0.rp_filter=2' sysctl_fake weak
expect "linux sysctl: unreadable key is reported, not passed" 'bpf_jit_harden unreadable' sysctl_fake weak
# SSH lockout guard: only a working key allows keys-only SSH
key_problem() {
  local h="$WORK/keys-$1" fn
  mkdir -p "$h/.ssh"; chmod 700 "$h/.ssh"
  case "$1" in
    rsa2048) ssh-keygen -q -t rsa -b 2048 -N '' -f "$h/k" ;;
    *) ssh-keygen -q -t ed25519 -N '' -f "$h/k" ;;
  esac
  cp "$h/k.pub" "$h/.ssh/authorized_keys"; chmod 600 "$h/.ssh/authorized_keys"
  local user=alice; [[ "$1" == root ]] && user=root
  fn=$(sed -n '/^writable_by_others()/,/^check_sshd()/p' "$REPO/linux/harden.sh" | grep -v '^check_sshd')
  TARGET_USER=$user TARGET_HOME=$h bash -c "$fn"$'\n''r=$(ssh_key_problem); echo "${r:-OK}"'
}
expect "linux ssh: ed25519 key allows keys-only" '^OK$' key_problem ed25519
expect "linux ssh: RSA-2048 only is refused" 'RSA key of 3072' key_problem rsa2048
expect "linux ssh: running as root is refused" 'running as root' key_problem root
if [[ "$OS" == Darwin ]]; then
  harden_mac_runs() {
    local err; err=$(/bin/bash "$REPO/macos/harden.sh" 2>&1 >/dev/null)
    [[ -z "$err" ]] || { echo "$err"; return 1; }
  }
  check "macos/harden.sh --check runs without errors" harden_mac_runs
fi
if [[ "$OS" == Linux ]]; then
  harden_linux_runs() {
    local out err; out=$(bash "$REPO/linux/harden.sh" 2>"$WORK/harden.err")
    err=$(cat "$WORK/harden.err")
    grep -q '^Summary:' <<< "$out" && [[ -z "$err" ]] || { echo "$out"; echo "$err"; return 1; }
  }
  check "linux/harden.sh --check runs on real Linux without errors" harden_linux_runs
fi

echo "== Setup dry runs"
# Everything the setup asks comes first; after "Preferences saved" nothing may prompt
no_prompts_after() { ! sed -n '/Preferences saved/,$p' "$1" | grep -qE '\(y/n\)|Enter your choice'; }
if [[ "$OS" == Darwin ]]; then
  mac_dry() {
    printf '10\n6\n7\n10\n9\nn\n13\n5\ny\nn\ny\ny\ny\n' | DRY_RUN=1 /bin/bash "$REPO/macos/initial_macos_setup.sh" > "$WORK/mac.log" 2>&1 &&
      no_prompts_after "$WORK/mac.log"
  }
  check "macOS setup dry run: exits 0, no prompts after the questions" mac_dry
fi
linux_dry() {
  printf '8\n6\n3\n13\nn\ny\ny\n' | SHELL=/bin/bash DRY_RUN=1 bash "$REPO/linux/initial_linux_setup.sh" > "$WORK/linux.log" 2>&1 &&
    no_prompts_after "$WORK/linux.log"
}
check "Linux setup dry run: exits 0, no prompts after the questions" linux_dry

echo ""
echo "$PASSED passed, $FAILED failed"
for f in "${FAILURES[@]}"; do echo "  failed: $f"; done
[[ "$WORK" == */dotfiles-tests.* ]] && rm -rf "$WORK"
[[ $FAILED -eq 0 ]]
