#!/usr/bin/env bash
# Regression tests for the dotfiles: syntax, shell startup, dots, git-wip,
# git-inventory, storage-cleanup, ssh-doctor, harden.sh logic and the setup dry runs.
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
           "$REPO"/shared/bin/git-wip "$REPO"/shared/bin/git-sync-all "$REPO"/shared/bin/secret \
           "$REPO"/shared/bin/claude-switch "$REPO"/shared/bin/claude-z "$REPO"/shared/bin/oz "$REPO"/shared/vibe/run-litellm.sh \
           "$REPO"/scripts/install-claude-aliases.sh "$REPO"/shared/zsh/.zsh_*; do
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
check "launchd plists are valid XML" python3 -c "import plistlib,sys; [plistlib.load(open(f,'rb')) for f in sys.argv[1:]]" "$REPO"/shared/launchd/*.plist
check "git-inventory compiles" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REPO/shared/bin/git-inventory"
check "storage-cleanup compiles" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REPO/shared/bin/storage-cleanup"
if command -v node >/dev/null; then
  check "secrets scripts parse" bash -c "node --check '$REPO/typescript/sync-secrets.js' && node --check '$REPO/typescript/get-secrets.js'"
  check "orca-lanes parses" node --check "$REPO/shared/bin/orca-lanes"
  OL=$(mktemp -d); printf '{"name":"orcastrator","version":"0.0.1"}' > "$OL/package.json"
  expect "orca-lanes refuses an unqualified Orca version" 'built against orcastrator' \
    env ORCA_PACKAGE_DIR="$OL" node "$REPO/shared/bin/orca-lanes" agents
  rm -rf "$OL"
  if [[ "$(npm ls -g --depth=0 --json orcastrator 2>/dev/null)" == *'"version": "0.2.25"'* ]]; then
    expect "orca-lanes registers the extra harnesses" 'alibaba.*claude-edit.*deepseek.*dsh.*opencode.*vibe' \
      bash -c "'$REPO/shared/bin/orca-lanes' agents 2>/dev/null | tr -d '\\n'"
  fi
fi

echo "== Shell startup"
H=$(make_home startup)
if command -v zsh >/dev/null; then
  # Silent and error-free: banners and errors on every shell start were removed
  startup_silent() {
    local out
    # -d: this repo's .zshrc only, not the distro's /etc/zsh files
    out=$(env -i HOME="$H" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -d -i -c exit </dev/null 2>&1)
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
expect "dots -s on a shared/bin command shows its usage" 'secret run PROFILE' env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_functions; dots -s secret'
expect "vcheck checks without converting" '\[false\]' env -i HOME="$H" PATH=/usr/bin:/bin bash -c \
  'source ~/.zsh_functions; check_video_format() { echo "[$2]"; }; vcheck x.mp4'

echo "== shell functions"
mac_ok() {
  local fn; fn=$(sed -n '/^gen_mac_addr() {/,/^}/p' "$REPO/shared/zsh/.zsh_network")
  bash -c "_has_python_mac_manager(){ return 1; }; $fn"$'\n''for i in $(seq 200); do m=$(gen_mac_addr); b=$((16#${m:0:2})); (( (b & 1) == 0 && (b & 2) == 2 )) || exit 1; done'
}
check "random MACs are unicast and locally administered" mac_ok
media_name() { env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_transfer; clean_media_name "Show_Name_S01E02_720p_HDTV.mp4"'; }
expect "clean_media_name works with the system sed/perl" '^Show_Name_S01E02$' media_name
password_once() {
  local out pid
  # SIGPIPE ignored, as on CI runners: `tr < /dev/urandom | head` then never
  # ended. A watchdog turns a hang back into a failure.
  env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'trap "" PIPE; source ~/.zsh_encryption
    for t in chars numbers hex; do generate_password -p $t -l 20 -q >/dev/null; done
    generate_password -p chars -l 20' > "$WORK/gp.out" 2>"$WORK/gp.err" &
  pid=$!
  ( sleep 20; kill $pid 2>/dev/null ) >/dev/null 2>&1 &
  wait $pid || return 1
  out=$(cat "$WORK/gp.out")
  [[ ${#out} -eq 20 ]] && ! grep -qF -- "$out" "$WORK/gp.err"
}
check "generate_password ends with SIGPIPE ignored and prints the password once" password_once
ugr_safe() {
  local d="$WORK/ugr"; mkdir -p "$d/root"
  git init -q --bare "$d/r.git"
  local n; for n in a 'b$(touch PWNED)'; do
    git clone -q "$d/r.git" "$d/root/$n" 2>/dev/null; git -C "$d/root/$n" commit -q --allow-empty -m i
    git -C "$d/root/$n" push -q origin HEAD 2>/dev/null
  done
  local out
  out=$(cd "$d" && env -i HOME="$H" PATH=/usr/bin:/bin GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" GIT_CONFIG_NOSYSTEM=1 bash -c \
    'source ~/.zsh_developer >/dev/null 2>&1; start=$PWD; update_git_repos --search-path "$1" 2>&1; [[ "$PWD" == "$start" ]] && echo CWD-KEPT' _ "$d/root")
  # It must actually have run (both repos), not merely have done nothing harmful
  [[ $(grep -c 'Updating repository' <<< "$out") -eq 2 ]] && grep -q CWD-KEPT <<< "$out" &&
    [[ ! -e "$d/PWNED" && ! -e "$d/root/PWNED" ]] &&
    # ask git: the file stores it as [safe] directory = ..., not "safe.directory"
    [[ -z "$(git config --global --get-all safe.directory)" ]]
}
check "update_git_repos: no code from folder names, cwd kept, no safe.directory pile-up" ugr_safe

zip_aes() {
  local d="$WORK/zip" sz
  sz=$(command -v 7zz || command -v 7z)
  mkdir -p "$d" && echo data > "$d/f.txt"
  (cd "$d" && printf 'pw-test\npw-test\n' | env -i HOME="$H" PATH="$PATH" bash -c 'source ~/.zsh_encryption; secure_zip out.zip f.txt' >/dev/null 2>&1) || return 1
  "$sz" l -slt "$d/out.zip" | grep -q 'Method = .*AES-256'
}
if command -v 7zz >/dev/null || command -v 7z >/dev/null; then
  check "secure_zip makes AES-256 archives with 7-Zip" zip_aes
fi
zip_warns() {
  local d="$WORK/zipw"; mkdir -p "$d/bin" && echo data > "$d/f.txt"
  # Hide 7-Zip so the ZipCrypto fallback runs; it must say it is weak
  (cd "$d" && env -i HOME="$H" PATH=/usr/bin:/bin bash -c 'source ~/.zsh_encryption; secure_zip out.zip f.txt' </dev/null 2>&1) | grep -q 'ZipCrypto encryption is weak'
}
if ! [[ -x /usr/bin/7zz || -x /usr/bin/7z || -x /bin/7z ]]; then
  check "secure_zip warns when it falls back to weak ZipCrypto" zip_warns
fi

echo "== secret (sops + age)"
if command -v sops >/dev/null && command -v age-keygen >/dev/null; then
  SEC="$WORK/secret"; mkdir -p "$SEC/h1" "$SEC/h2"
  d1() { HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file "$REPO/shared/bin/secret" "$@"; }
  d2() { HOME="$SEC/h2" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file "$REPO/shared/bin/secret" "$@"; }
  secret_import() {
    d1 init >/dev/null || return 1
    printf '# c\nexport API_TOKEN="abc def"\nPLAIN=x=y\nbad key=1\n' > "$SEC/plain.env"
    d1 import ai "$SEC/plain.env" >/dev/null 2>&1 || return 1
    [[ "$(d1 list ai | tr '\n' ' ')" == "API_TOKEN PLAIN " ]] &&
      ! grep -q 'abc def' "$SEC/store/ai.env" &&
      [[ "$(d1 get ai API_TOKEN)" == "abc def" && "$(d1 get ai PLAIN)" == "x=y" ]]
  }
  check "secret: import normalizes a .env and stores only ciphertext" secret_import
  secret_run_scoped() {
    [[ "$(d1 run ai -- sh -c 'echo "$API_TOKEN"')" == "abc def" ]] && [[ -z "${API_TOKEN:-}" ]]
  }
  check "secret: run injects values into that command only" secret_run_scoped
  secret_run_missing_profile() {
    local out; out=$(d1 run nosuch -- sh -c 'echo RAN' 2>/dev/null) && return 1
    [[ "$out" != *RAN* ]]
  }
  check "secret: run refuses to start the command without its profile" secret_run_missing_profile
  secret_set_stdin() { printf 'n3w\n' | d1 set ai NEW >/dev/null && [[ "$(d1 get ai NEW)" == "n3w" ]]; }
  check "secret: set reads the value from stdin" secret_set_stdin
  secret_devices() {
    d2 init >/dev/null
    local p2; p2=$(d2 pubkey)
    d2 get ai API_TOKEN >/dev/null 2>&1 && return 1            # not a recipient yet
    d1 add-device h2 "$p2" >/dev/null || return 1
    [[ "$(d2 get ai API_TOKEN)" == "abc def" ]] || return 1    # can decrypt after add
    d1 remove-device h2 >/dev/null || return 1
    ! d2 get ai API_TOKEN >/dev/null 2>&1                      # and not after removal
  }
  check "secret: add-device grants, remove-device revokes" secret_devices
  secret_set_needs_decrypt() {
    local before; before=$(d1 list ai | tr '\n' ' ')
    printf 'x\n' | d2 set ai OTHER >/dev/null 2>&1 && return 1   # h2 is no longer a recipient
    [[ "$(d1 list ai | tr '\n' ' ')" == "$before" && "$(d1 get ai API_TOKEN)" == "abc def" ]]
  }
  check "secret: set on a device that can't decrypt keeps the profile" secret_set_needs_decrypt
  secret_skips_references() {
    printf 'REAL=v\nREF=${OTHER}\nLIT='"'"'a$b'"'"'\n' > "$SEC/refs.env"
    d1 import refs "$SEC/refs.env" 2>"$SEC/refs.err" >/dev/null || return 1
    grep -q 'skipped REF' "$SEC/refs.err" && [[ "$(d1 list refs | tr '\n' ' ')" == "REAL LIT " ]] && [[ "$(d1 get refs LIT)" == 'a$b' ]]
  }
  check "secret: import skips \${VAR} references (stored as text before)" secret_skips_references
  secret_git_history() {
    command -v git >/dev/null || return 0
    git -C "$SEC/store" log --format=%s | grep -q '^secret: import ai' &&
      git -C "$SEC/store" log --format=%s | grep -q '^secret: set ai NEW' &&
      [[ -z "$(git -C "$SEC/store" status --porcelain)" ]]
  }
  check "secret: every change is committed in the store's git history" secret_git_history
  # cc-vibe: the profile wins over a plaintext file that can't be sourced, and
  # the preflight hands the key to curl through a header file, not argv
  claude_switch_vibe_profile() {
    local fake="$SEC/fakebin" log="$SEC/curl.argv" sh rc=0
    mkdir -p "$fake"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\n' "$log" > "$fake/curl"; chmod +x "$fake/curl"
    printf 'DF_API_KEY=${MISTRAL_API_KEY:?unset}\n' > "$SEC/vibe-plain.env"
    printf 'VIBE_API_KEY_FILE=%s\nVIBE_BASE_URL=http://127.0.0.1:9\nVIBE_MODEL=m\nVIBE_MODEL_NAME=n\n' \
      "$SEC/vibe-plain.env" > "$SEC/backends.env"
    printf 'mk-test-123' | d1 set vibe LITELLM_MASTER_KEY >/dev/null || return 1
    for sh in bash zsh; do
      command -v $sh >/dev/null || continue
      : > "$log"
      HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file CLAUDE_BACKENDS_CONFIG="$SEC/backends.env" \
        PATH="$fake:$REPO/shared/bin:$PATH" $sh -c \
        'source "$1" vibe >/dev/null 2>&1 && [ "$ANTHROPIC_AUTH_TOKEN" = mk-test-123 ]' $sh "$REPO/shared/bin/claude-switch" ||
        { echo "$sh: switch_vibe did not take the key from the profile"; rc=1; }
      grep -q '/v1/messages' "$log" || { echo "$sh: preflight never ran"; rc=1; }
      ! grep -q 'mk-test-123' "$log" || { echo "$sh: key on curl's command line"; rc=1; }
    done
    return $rc
  }
  check "claude-switch vibe: profile key, never in curl argv" claude_switch_vibe_profile
  # deepseek: key from the profile, never in curl argv; Pro via DEEPSEEK_MODEL;
  # switching back to cloud clears every override it set
  claude_switch_deepseek() {
    local fake="$SEC/fakebin" log="$SEC/curl.argv" rc=0 out
    printf 'ds-test-456' | d1 set deepseek DEEPSEEK_API_KEY >/dev/null || return 1
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\nprintf "%%s" "${FAKE_HTTP_CODE:-200}"\n' "$log" > "$fake/curl"
    : > "$log"
    out=$(HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file CLAUDE_BACKENDS_CONFIG="$SEC/backends.env" \
      FAKE_HTTP_CODE=402 PATH="$fake:$REPO/shared/bin:$PATH" zsh -fc 'source "$1" deepseek; echo "url:${ANTHROPIC_BASE_URL-}"' _ "$REPO/shared/bin/claude-switch" 2>&1)
    [[ "$out" == *"no balance (HTTP 402)"* && "$out" != *"url:http"* ]] || { echo "402: $out"; rc=1; }
    out=$(HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file CLAUDE_BACKENDS_CONFIG="$SEC/backends.env" \
      PATH="$fake:$REPO/shared/bin:$PATH" zsh -fc '
        source "$1" deepseek >/dev/null 2>&1 || exit 3
        echo "flash:$ANTHROPIC_AUTH_TOKEN:$ANTHROPIC_MODEL:$ANTHROPIC_DEFAULT_OPUS_MODEL"
        DEEPSEEK_MODEL=deepseek-v4-pro source "$1" deepseek >/dev/null 2>&1 || exit 4
        echo "pro:$ANTHROPIC_MODEL"
        source "$1" cloud >/dev/null 2>&1
        echo "cloud:${ANTHROPIC_BASE_URL-}${ANTHROPIC_DEFAULT_OPUS_MODEL-}${CLAUDE_CODE_SUBAGENT_MODEL-}${ANTHROPIC_MODEL-}"' _ "$REPO/shared/bin/claude-switch") ||
      { echo "switch failed: $out"; return 1; }
    [[ "$out" == *"flash:ds-test-456:deepseek-flash[1m]:deepseek-v4-pro[1m]"* ]] || { echo "flash: $out"; rc=1; }
    [[ "$out" == *"pro:deepseek-v4-pro[1m]"* ]] || { echo "pro: $out"; rc=1; }
    [[ "$out" == *$'cloud:\n'* || "$out" == *"cloud:" ]] || { echo "cloud left overrides: $out"; rc=1; }
    grep -q 'api.deepseek.com/anthropic/v1/messages' "$log" || { echo "preflight never ran"; rc=1; }
    ! grep -q 'ds-test-456' "$log" || { echo "key on curl's command line"; rc=1; }
    return $rc
  }
  # alibaba: key from the profile, never in curl argv; the Coding Plan backend
  # wants its own key and refuses the pay-as-you-go one
  claude_switch_alibaba() {
    local fake="$SEC/fakebin" log="$SEC/curl.argv" rc=0 out
    printf 'sk-ws-test-789' | d1 set alibaba DASHSCOPE_API_KEY >/dev/null || return 1
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\nprintf "\\n%%s" "${FAKE_HTTP_CODE:-200}"\n' "$log" > "$fake/curl"
    : > "$log"
    out=$(HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file CLAUDE_BACKENDS_CONFIG="$SEC/backends.env" \
      PATH="$fake:$REPO/shared/bin:$PATH" zsh -fc '
        source "$1" alibaba >/dev/null 2>&1 || exit 3
        echo "payg:$ANTHROPIC_AUTH_TOKEN:$ANTHROPIC_MODEL:$ANTHROPIC_DEFAULT_HAIKU_MODEL"' _ "$REPO/shared/bin/claude-switch" 2>&1) ||
      { echo "switch failed: $out"; return 1; }
    [[ "$out" == *"payg:sk-ws-test-789:qwen3.8-max:qwen3.8-flash"* ]] || { echo "payg: $out"; rc=1; }
    out=$(HOME="$SEC/h1" SECRETS_DIR="$SEC/store" SECRET_KEY_BACKEND=file CLAUDE_BACKENDS_CONFIG="$SEC/backends.env" \
      PATH="$fake:$REPO/shared/bin:$PATH" zsh -fc 'source "$1" alibaba-coding; echo "coding:${ANTHROPIC_AUTH_TOKEN-}"' _ "$REPO/shared/bin/claude-switch" 2>&1)
    [[ "$out" == *"DASHSCOPE_CODING_API_KEY is not in the secret profile"* && "$out" != *"coding:sk-"* ]] || { echo "coding: $out"; rc=1; }
    grep -q 'dashscope-intl.aliyuncs.com/apps/anthropic/v1/messages' "$log" || { echo "preflight never ran"; rc=1; }
    ! grep -q 'sk-ws-test-789' "$log" || { echo "key on curl's command line"; rc=1; }
    return $rc
  }
  command -v zsh >/dev/null && check "claude-switch alibaba: profile key, plan keys kept apart" claude_switch_alibaba
  # Output goes to a file and is checked by structure only
  secret_aws_credentials() {
    printf 'AKIATESTTESTTESTTEST' | d1 set awst AWS_ACCESS_KEY_ID >/dev/null &&
      printf 'sec/ret+x' | d1 set awst AWS_SECRET_ACCESS_KEY >/dev/null || return 1
    d1 aws-credentials awst > "$SEC/aws.json" 2>/dev/null || return 1
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d=={"Version":1,"AccessKeyId":"AKIATESTTESTTESTTEST","SecretAccessKey":"sec/ret+x"} else 1)' "$SEC/aws.json" || return 1
    printf 'x' | d1 set awsbad AWS_ACCESS_KEY_ID >/dev/null || return 1
    ! d1 aws-credentials awsbad > "$SEC/aws-bad.json" 2>/dev/null && [[ ! -s "$SEC/aws-bad.json" ]]
  }
  check "secret: aws-credentials prints credential_process JSON, fails without both keys" secret_aws_credentials
  command -v zsh >/dev/null && check "claude-switch deepseek: profile key, Pro model, 402 named, cloud clears it" claude_switch_deepseek
  secret_no_plaintext_files() { ! ls -a "$SEC/store" | grep -qE '^\.tmp|\.dec$|\.plain$'; }
  check "secret: no plaintext or temp files left in the store" secret_no_plaintext_files
fi

echo "== Claude Code launchers"
CZT="$(mktemp -d)"
# Fakes: nc says every port is up, curl serves a vLLM model list, claude prints its env
mkdir -p "$CZT/bin"
printf '#!/bin/sh\nexit 0\n' > "$CZT/bin/nc"
printf '#!/bin/sh\necho "{\\"data\\":[{\\"id\\":\\"openai/gpt-oss-120b\\",\\"max_model_len\\":49152},{\\"id\\":\\"glm-5.3-flash\\",\\"max_model_len\\":262144},{\\"id\\":\\"DavidAU/Qwen3.6-27B-Fable-711-FP8\\",\\"max_model_len\\":32768}]}"\n' > "$CZT/bin/curl"
printf '#!/bin/sh\necho "args=$*"; env | grep -E "^(ANTHROPIC|CLAUDE_CODE)_" | sort\n' > "$CZT/bin/claude"
chmod +x "$CZT"/bin/*
claude_z_server_env() {
  local out1 out2
  out1=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" 1 -p x 2>/dev/null) || return 1
  out2=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" 2 -p x 2>/dev/null) || return 1
  [[ "$out1" == *"ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3-flash"* && "$out1" == *"CLAUDE_CODE_SUBAGENT_MODEL=glm-5.3-flash"* ]] || { echo "z1 tiers: $out1"; return 1; }
  [[ "$out1" == *"CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144"* && "$out1" != *"SIMPLE_SYSTEM_PROMPT"* ]] || { echo "z1 window: $out1"; return 1; }
  [[ "$out2" == *"CLAUDE_CODE_MAX_CONTEXT_TOKENS=49152"* && "$out2" == *"CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1"* && "$out2" == *"CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192"* ]] || { echo "z2 window: $out2"; return 1; }
  [[ "$out2" != *"ANTHROPIC_SMALL_FAST_MODEL"* ]] || { echo "deprecated var set"; return 1; }
}
check "claude-z: every tier and subagent uses the served model; window from vLLM" claude_z_server_env
claude_z_registry() {
  local out rc=0
  out=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" ensure qwen 2>/dev/null)
  [[ "$out" == "8003 huihui-ai/Huihui-Qwen3.8-27B-abliterated nothink" ]] || { echo "ensure alias: $out"; rc=1; }
  out=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" ensure 1 2>/dev/null)
  [[ "$out" == "8001 glm-5.3-flash -" ]] || { echo "ensure 1: $out"; rc=1; }
  out=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" 2f -p x 2>&1); [[ $? -eq 2 && "$out" == *"zq 2f"* && "$out" != *"args="* ]] || { echo "32K not refused: $out"; rc=1; }
  out=$(PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" embed -p x 2>&1); [[ "$out" == *"embed model"* && "$out" != *"args="* ]] || { echo "embed not refused: $out"; rc=1; }
  PATH="$CZT/bin:$PATH" bash "$REPO/shared/bin/claude-z" nope 2>/dev/null | grep -q "args=nope" || { echo "unknown first arg not passed to claude"; rc=1; }
  return $rc
}
check "claude-z: registry keys and aliases; 32K and non-chat models refused for Claude Code" claude_z_registry
cc_cloud_is_clean() {
  local sh out rc=0
  for sh in bash zsh; do
    command -v $sh >/dev/null || continue
    out=$(PATH="$CZT/bin:$PATH" ANTHROPIC_BASE_URL=http://127.0.0.1:8001 CLAUDE_CODE_SUBAGENT_MODEL=glm \
      $sh -c 'alias cc=claude-z; source "$1"; source "$1"; cc -p x' _ "$REPO/shared/zsh/claude-aliases.zsh" 2>&1) ||
      { echo "$sh: $out"; rc=1; continue; }
    [[ "$out" == *"args=--dangerously-skip-permissions --teammate-mode auto -p x"* ]] || { echo "$sh flags: $out"; rc=1; }
    [[ "$out" != *"ANTHROPIC_BASE_URL"* && "$out" != *"SUBAGENT_MODEL"* ]] || { echo "$sh leaked: $out"; rc=1; }
  done
  return $rc
}
check "cc: cloud run drops self-hosted variables; re-sourcing over old aliases is clean" cc_cloud_is_clean
rm -rf "$CZT"

echo "== ai-policy"
AP="$REPO/shared/bin/ai-policy"
APW="$WORK/ai-policy"; mkdir -p "$APW"
ap_repo() { mkdir -p "$APW/$1" && git -C "$APW/$1" init -q && git -C "$APW/$1" remote add origin "$2"; }
ap_repo ic https://github.com/irregularchat/probe.git
ap_repo zf git@github.com:zenithflowinc/probe.git
ap_repo icgl ssh://git@100.87.20.88:2224/irregulars/irregularchat-monorepo.git
ap_repo own https://git.irregularchat.com/sac/own-project.git
ap_decisions() {
  local rc=0 c
  c() { "$AP" check --cwd "$APW/$1" "${@:3}" 2>/dev/null; [[ $? -eq $2 ]] || { echo "$1 ${*:3}: expected $2"; rc=1; }; }
  c ic 3 --model qwen3.8-max
  c ic 3 --model opencode-go/qwen3.7-plus
  c ic 3 --model qwen3.6:latest
  c ic 3 --model deepseek-v4-pro --base-url https://dashscope-intl.aliyuncs.com/apps/anthropic
  c ic 3 --model alibaba/glm-5.3
  c zf 3 --model qwen3.8-max
  c zf 3 --model huihui-ai/Huihui-Qwen3.8-27B-abliterated   # fine-tune: family after a prefix
  c zf 0 --model openai/gpt-oss-120b
  c zf 0 --model translategemma:12b
  c icgl 3 --model Qwen/Qwen2.5-72B-Instruct
  c ic 0 --model claude-opus-5-5
  c ic 0 --model deepseek-v4-pro --base-url https://api.deepseek.com/anthropic
  c own 0 --model qwen3.8-max --base-url https://dashscope-intl.aliyuncs.com/apps/anthropic
  return $rc
}
check "ai-policy: Alibaba models and services denied only in IrregularChat/ZenithFlow repos" ap_decisions
ap_hook() {
  printf '{"cwd":"%s"}' "$APW/ic" | env -u ANTHROPIC_MODEL ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic "$AP" claude-hook 2>/dev/null
  [[ $? -eq 2 ]] || return 1
  printf '{"cwd":"%s"}' "$APW/ic" | env -u ANTHROPIC_BASE_URL -u ANTHROPIC_MODEL "$AP" claude-hook || return 1
  printf '{"cwd":"%s"}' "$APW/own" | env -u ANTHROPIC_MODEL AI_POLICY_FILE=/nonexistent "$AP" claude-hook 2>/dev/null
  [[ $? -eq 2 ]]
}
check "ai-policy: Claude hook blocks (exit 2) on a denied backend and on an unreadable policy" ap_hook
ap_scan() {
  printf 'const model = env.M || "qwen3.6:latest"\n' > "$APW/ic/ai.ts"
  printf 'We tried Qwen once.\n' > "$APW/ic/notes.md"
  git -C "$APW/ic" add ai.ts notes.md
  local out; out=$("$AP" scan "$APW/ic" 2>/dev/null) && return 1
  [[ "$out" == *"ai.ts:1: vendor:alibaba"* && "$out" != *notes.md* ]] || { echo "$out"; return 1; }
  "$AP" scan "$APW/own" >/dev/null 2>&1
}
check "ai-policy: scan finds Qwen in tracked code, skips docs and unrestricted repos" ap_scan
ap_install() {
  local h="$APW/home"; mkdir -p "$h/.claude"; printf '{"theme":"dark"}' > "$h/.claude/settings.json"
  HOME="$h" "$AP" install >/dev/null && HOME="$h" "$AP" install >/dev/null || return 1
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d["hooks"]["UserPromptSubmit"]; sys.exit(0 if d["theme"]=="dark" and len(e)==1 else 1)' "$h/.claude/settings.json" &&
    [[ -L "$h/.config/opencode/plugins/ai-policy" ]] && HOME="$h" "$AP" install --check >/dev/null
}
check "ai-policy: install adds the hook once and links the OpenCode plugin" ap_install
check "ai-policy: the shipped policy parses" "$AP" explain --cwd "$APW/ic"
if command -v node >/dev/null; then
  check "ai-policy OpenCode plugin parses" node --check "$REPO/shared/opencode/plugins/ai-policy/server.js"
fi

check "paperclip-wait: usage exits 0; unreachable API exits 3" bash -c '
  python3 "$1" --help >/dev/null &&
  { PAPERCLIP_API_URL=http://127.0.0.1:9 python3 "$1" SAC-1 1 >/dev/null 2>&1; [ $? -eq 3 ]; }' _ "$REPO/shared/bin/paperclip-wait"

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

echo "== storage-cleanup"
# sc_project <dir> [nm-file]: an old project with a node_modules, everything dated 2020
sc_project() {
  mkdir -p "$1/node_modules/pkg"; echo '{}' > "$1/package.json"; echo x > "$1/node_modules/pkg/${2:-index.js}"
  find "$1" -exec touch -t 202001010000 {} +
}
sc_setup() {
  local d="$WORK/sc"
  rm -rf "$d"; mkdir -p "$d/home" "$d/roots" "$d/outside/keep"
  sc_project "$d/roots/old"
  sc_project "$d/roots/new"; touch "$d/roots/new/package.json"
  # linked: node_modules is a symlink to data elsewhere, which must survive
  mkdir -p "$d/roots/linked"; echo '{}' > "$d/roots/linked/package.json"; touch -t 202001010000 "$d/roots/linked/package.json"
  echo keep > "$d/outside/keep/file"; ln -s "$d/outside/keep" "$d/roots/linked/node_modules"
  echo "$d"
}
SC=$(sc_setup)
sc_cmd() { HOME="$SC/home" "$REPO/shared/bin/storage-cleanup" "$@"; }
sc_run() { sc_cmd --only node-modules --root "$SC/roots" "$@"; }
expect "storage-cleanup dry run lists only the stale project" 'remove 1 of 2 node_modules' sc_run
sc_dry_keeps() { sc_run >/dev/null; [[ -d "$SC/roots/old/node_modules/pkg" ]]; }
check "storage-cleanup dry run deletes nothing" sc_dry_keeps
expect "storage-cleanup counts overlapping roots once" 'remove 1 of 2 node_modules' \
  sc_run --root "$SC/roots/old"
sc_apply() {
  sc_run --apply >/dev/null && [[ ! -e "$SC/roots/old/node_modules" && -d "$SC/roots/new/node_modules/pkg" \
    && -L "$SC/roots/linked/node_modules" && -f "$SC/outside/keep/file" ]]
}
check "storage-cleanup --apply removes stale node_modules only, never through a symlink" sc_apply

# Each layout below must be kept; the run must report nothing to remove
sc_keeps() { local r="$1"; shift; sc_cmd --only node-modules --root "$r" "$@" | grep -q 'remove [0-9]' && return 1; return 0; }
K="$WORK/sc-keep"; rm -rf "$K"
sc_project "$K/clone"; mkdir -p "$K/clone/node_modules/pkg/.git"
check "storage-cleanup keeps a node_modules that holds a git clone" sc_keeps "$K/clone"
sc_project "$K/edited"; echo patched > "$K/edited/node_modules/pkg/fix.js"
check "storage-cleanup keeps a node_modules edited recently" sc_keeps "$K/edited"
mkdir -p "$K/tools/.nvm/lib/node_modules/npm" "$K/tools/ext/node_modules/x"; echo x > "$K/tools/ext/node_modules/x/a.js"
find "$K/tools" -exec touch -t 202001010000 {} +
check "storage-cleanup ignores node_modules with no package.json or under hidden folders" sc_keeps "$K/tools"
sc_project "$K/tracked"; git -C "$K/tracked" init -q; git -C "$K/tracked" add -A; git -C "$K/tracked" commit -q -m i
find "$K/tracked" -path '*/.git' -prune -o -exec touch -t 202001010000 {} +
check "storage-cleanup keeps a node_modules committed to git" sc_keeps "$K/tracked"
sc_project "$K/locked"; mkdir -p "$K/locked/src/private"; chmod 000 "$K/locked/src/private"
check "storage-cleanup keeps a project it cannot fully read" sc_keeps "$K/locked"
chmod 755 "$K/locked/src/private"
sc_project "$K/running"; printf 'sleep 30\n' > "$K/running/serve.sh"; touch -t 202001010000 "$K/running/serve.sh"
bash "$K/running/serve.sh" & SC_PID=$!
check "storage-cleanup keeps a project a running program uses" sc_keeps "$K/running"
kill "$SC_PID" 2>/dev/null; wait "$SC_PID" 2>/dev/null

F="$WORK/sc-fail"; rm -rf "$F"; sc_project "$F/p"; chmod 555 "$F/p/node_modules/pkg"
sc_fail() { local out rc; out=$(sc_cmd --only node-modules --root "$F" --apply 2>&1); rc=$?
  [[ $rc -eq 1 ]] && grep -q 'FAILED *node-modules' <<< "$out"; }
check "storage-cleanup reports a deletion it could not finish and exits 1" sc_fail
chmod -R u+w "$F"
sc_refuses() {
  local h="$WORK/sc-home"; rm -rf "$h"
  mkdir -p "$h/.claude/projects" "$h/Library/Mobile Documents/x" "$h/Library/CloudStorage/d/y" "$h/proj/node_modules" "$h/Documents"
  ln -s "$h/proj" "$h/link"
  HOME="$h" PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO/shared/bin/storage-cleanup" "$h" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("sc", sys.argv[1])
sc = importlib.util.module_from_spec(importlib.util.spec_from_loader("sc", loader))
loader.exec_module(sc)
h = os.path.realpath(sys.argv[2])
for p in (h, h + "/.claude", h + "/Documents", h + "/Library", h + "/Library/Mobile Documents/x",
          h + "/Library/CloudStorage/d/y", h + "/link", "/"):
    errs = sc.remove(p)
    assert errs and "refused" in errs[0], (p, errs)
    assert os.path.lexists(p), p
assert sc.remove(h + "/proj/node_modules") == [] and not os.path.exists(h + "/proj/node_modules")
PY
}
check "storage-cleanup refuses home, protected, cloud-synced and symlinked paths" sc_refuses
expect "storage-cleanup rejects --node-modules below 1 day" 'at least 1' sc_run --node-modules 0
expect "storage-cleanup rejects an unknown category" 'unknown categories: bogus' sc_cmd --only bogus
if command -v npm >/dev/null; then
  mkdir -p "$SC/home/.npm/_npx/abc"; printf 'sleep 30\n' > "$SC/home/.npm/_npx/abc/mcp.sh"
  bash "$SC/home/.npm/_npx/abc/mcp.sh" & SC_PID=$!
  expect "storage-cleanup skips the npx cache while a program runs from it" 'SKIPPED: 1 running' sc_cmd --only npx
  kill "$SC_PID" 2>/dev/null; wait "$SC_PID" 2>/dev/null
fi

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

echo "== Gas Town installer (Linux)"
# Pinned sums are complete; a matching archive installs, a mismatch installs nothing
gastown_fetch_checked() {
  local d="$WORK/gtfetch"; mkdir -p "$d/src"
  printf '#!/bin/sh\necho gt\n' > "$d/src/gt"; chmod +x "$d/src/gt"
  tar -czf "$d/fixture.tar.gz" -C "$d/src" gt
  bash -c '
    source "$1" >/dev/null 2>&1 || exit 1
    d="$2"; problems=0
    for a in amd64 arm64; do
      for n in "gastown_${GASTOWN_VERSION}_linux_$a.tar.gz" "beads_${BEADS_VERSION}_linux_$a.tar.gz" "dolt-linux-$a.tar.gz"; do
        [[ "$(gastown_sha256 "$n")" =~ ^[0-9a-f]{64}$ ]] || { echo "no pinned sum for $n"; exit 6; }
      done
    done
    note_problem() { problems=$((problems + 1)); }
    curl() { local o; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && { o="$2"; shift; }; shift; done; cp "$d/fixture.tar.gz" "$o"; }
    good=$(sha256sum "$d/fixture.tar.gz" | cut -d" " -f1)
    gastown_sha256() { case "$1" in good.tar.gz) echo "$good" ;; bad.tar.gz) printf "%064d\n" 0 ;; esac; }
    _fetch_checked https://x/good.tar.gz good.tar.gz gt "$d/out/good" && [[ -x "$d/out/good" ]] || { echo "good archive not installed"; exit 2; }
    _fetch_checked https://x/bad.tar.gz bad.tar.gz gt "$d/out/bad" && { echo "bad archive accepted"; exit 3; }
    [[ ! -e "$d/out/bad" && $problems -eq 1 ]] || { echo "bad archive installed or not reported"; exit 4; }
  ' _ "$REPO/linux/initial_linux_setup.sh" "$d"
}
check "gastown: pinned sums complete; checksum mismatch installs nothing" gastown_fetch_checked

echo "== Setup dry runs"
# Everything the setup asks comes first; after "Preferences saved" nothing may prompt
no_prompts_after() { ! sed -n '/Preferences saved/,$p' "$1" | grep -qE '\(y/n\)|Enter your choice'; }
if [[ "$OS" == Darwin ]]; then
  mac_dry() {
    # 10,11: Paperclip and Gas Town
    printf '10,11\n6\n7\n10\n9\nn\n13\n5\ny\nn\ny\ny\ny\n' | DRY_RUN=1 /bin/bash "$REPO/macos/initial_macos_setup.sh" > "$WORK/mac.log" 2>&1 &&
      no_prompts_after "$WORK/mac.log" &&
      grep -q "paperclipai@" "$WORK/mac.log" && grep -qE "gastown" "$WORK/mac.log"
  }
  check "macOS setup dry run: exits 0, no prompts after the questions" mac_dry
fi
linux_dry() {
  # 8,9: Paperclip and Gas Town
  printf '8,9\n6\n3\n13\nn\ny\ny\n' | SHELL=/bin/bash DRY_RUN=1 bash "$REPO/linux/initial_linux_setup.sh" > "$WORK/linux.log" 2>&1 &&
    no_prompts_after "$WORK/linux.log" &&
    grep -q "paperclipai@" "$WORK/linux.log" && grep -q "gt 1.2.1, bd 1.0.4" "$WORK/linux.log"
}
check "Linux setup dry run: exits 0, no prompts after the questions" linux_dry

echo ""
echo "$PASSED passed, $FAILED failed"
for f in "${FAILURES[@]}"; do echo "  failed: $f"; done
[[ "$WORK" == */dotfiles-tests.* ]] && rm -rf "$WORK"
[[ $FAILED -eq 0 ]]
