#!/bin/bash
# Shared by macos/initial_macos_setup.sh and linux/initial_linux_setup.sh.
# Source it after setting REPO_ROOT. Stays bash 3.2 compatible for macOS.

# Problems collected during the run, printed together at the end
PROBLEMS=()
# Things the user does after the run (approve an extension, App Store installs)
NEXT_STEPS=()

VIBE_CODING_CHOICES=()
VIBE_CODING_URL="https://git.juntogroups.org/public-repos/vibe-coding.git"
VIBE_CODING_DIR="$(dirname "$REPO_ROOT")/vibe-coding"

note_problem() {
  PROBLEMS+=("$1")
}

note_next_step() {
  NEXT_STEPS+=("$1")
}

is_dry_run() {
  [[ "${DRY_RUN:-0}" == "1" ]]
}

# Ask for the password once and keep the sudo ticket fresh, so Homebrew's pkg
# installers and the system settings never stop to ask again.
start_sudo_keepalive() {
  echo "Enter your password once. The rest of the setup runs without questions."
  if ! sudo -v; then
    echo "❌ Setup needs administrator rights. Re-run as an admin user."
    exit 1
  fi
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
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

# The vibe-coding question, asked after the editor/agent question on both OSes
ask_vibe_coding() {
  echo "Add the shared AI coding setup from vibe-coding (git.juntogroups.org/public-repos/vibe-coding)?"
  echo "It is cloned to $VIBE_CODING_DIR and linked in, so 'git pull' there updates it."
  echo "Files you already have are never overwritten."
  echo "1. Claude Code rules and skills (~/.claude/rules, looper, vibe-orchestrator, cloud-escalator)"
  echo "2. claude-switch: switch Claude Code between cloud and self-hosted backends (~/.local/bin)"
  echo "3. Mistral Vibe skills and agents (~/.vibe)"
  echo "4. OpenCode config template (~/.config/opencode/opencode.json, only if you have none)"
  echo "5. All of the above"
  echo "6. None"
  echo -n "Enter your choice (1-6)(Default: 6) (multiple choices separated by commas): "
  read vibe_choice
  VIBE_CODING_CHOICES=($(parse_choices "${vibe_choice:-6}"))
  if has_choice 5 "${VIBE_CODING_CHOICES[@]}"; then
    VIBE_CODING_CHOICES=(1 2 3 4)
  fi
}

# Orca (github.com/happycatlabs/orca, npm "orcastrator"): dispatches Codex,
# Claude or Cursor work as observable "lanes" for an orchestrator. Pinned: the
# project is young (one maintainer); bump after reading its changelog. Checked
# by npm package, not by `orca` on PATH: on Linux that is the GNOME screen reader.
ORCA_VERSION="0.2.25"
# Usage: install_orca [npm prefix]  (a prefix avoids sudo for apt's npm)
install_orca() {
  local prefix="$1"
  local -a npm_prefix=()
  [[ -n "$prefix" ]] && npm_prefix=(--prefix "$prefix")
  if ! command -v npm &>/dev/null; then
    is_dry_run || { note_problem "Orca: npm not found (install Node.js first)"; return 1; }
  fi
  if command -v npm &>/dev/null && npm ls -g "${npm_prefix[@]}" orcastrator &>/dev/null; then
    echo "Orca is already installed."
    return 0
  fi
  if is_dry_run; then
    echo "  [dry-run] npm install -g ${npm_prefix[*]} --ignore-scripts orcastrator@$ORCA_VERSION"
    return 0
  fi
  echo "Installing Orca $ORCA_VERSION..."
  # --ignore-scripts: it has none today; a later release can't add one silently
  npm install -g "${npm_prefix[@]}" --ignore-scripts "orcastrator@$ORCA_VERSION" ||
    { note_problem "Orca: npm install of orcastrator@$ORCA_VERSION failed"; return 1; }
  note_next_step "Orca: run 'orca agents' to see which of Codex/Claude/Cursor it can drive"
}

# Symlink src to dst unless something is already there. Never overwrites.
link_if_missing() {
  local src="$1" dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "  kept existing $dst"
    return 0
  fi
  if is_dry_run; then
    echo "  [dry-run] Would link $dst -> $src"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" && echo "  linked $dst"
}

# Clone or update vibe-coding and link the chosen parts in
install_vibe_coding() {
  if has_choice 6 "${VIBE_CODING_CHOICES[@]}"; then
    echo "No vibe-coding setup selected. Skipping."
    return
  fi
  echo "Setting up shared AI coding config from vibe-coding..."
  if [[ -d "$VIBE_CODING_DIR/.git" ]]; then
    # A failed fast-forward (local changes, diverged, no upstream) keeps the
    # checkout as is
    if is_dry_run; then
      echo "  [dry-run] Would update $VIBE_CODING_DIR (git pull --ff-only)"
    elif ! git -C "$VIBE_CODING_DIR" pull --ff-only --quiet 2>/dev/null; then
      note_problem "vibe-coding: could not fast-forward $VIBE_CODING_DIR; used it as is"
    fi
  elif is_dry_run; then
    echo "  [dry-run] Would clone $VIBE_CODING_URL to $VIBE_CODING_DIR"
    return 0
  elif ! git clone --quiet "$VIBE_CODING_URL" "$VIBE_CODING_DIR"; then
    note_problem "vibe-coding: clone of $VIBE_CODING_URL failed"
    return 1
  fi

  local repo="$VIBE_CODING_DIR" f name
  for choice in "${VIBE_CODING_CHOICES[@]}"; do
    case $choice in
      1)
        for f in "$repo"/rules/*.md; do
          [[ -e "$f" ]] && link_if_missing "$f" "$HOME/.claude/rules/$(basename "$f")"
        done
        link_if_missing "$repo/skills/looper" "$HOME/.claude/skills/looper"
        # Single-file skills: Claude Code wants <name>/SKILL.md
        link_if_missing "$repo/orchestrator/vibe-orchestrator-skill.md" "$HOME/.claude/skills/vibe-orchestrator/SKILL.md"
        link_if_missing "$repo/orchestrator/cloud-escalator-skill.md" "$HOME/.claude/skills/cloud-escalator/SKILL.md"
        ;;
      2)
        # The dotfiles ship their own copy in shared/bin
        if command -v claude-switch &>/dev/null; then
          echo "  kept existing $(command -v claude-switch)"
        else
          link_if_missing "$repo/claude-selfhosted/claude-switch.sh" "$HOME/.local/bin/claude-switch"
        fi
        ;;
      3)
        for f in "$repo"/vibe-config/skills/*/; do
          [[ -d "$f" ]] || continue
          name=$(basename "$f")
          link_if_missing "${f%/}" "$HOME/.vibe/skills/$name"
        done
        for f in "$repo"/vibe-config/agents/*.toml; do
          [[ -e "$f" ]] && link_if_missing "$f" "$HOME/.vibe/agents/$(basename "$f")"
        done
        ;;
      4)
        # A copy, not a link: it is a template to edit
        if [[ -e "$HOME/.config/opencode/opencode.json" ]]; then
          echo "  kept existing $HOME/.config/opencode/opencode.json"
        elif is_dry_run; then
          echo "  [dry-run] Would copy the OpenCode template to ~/.config/opencode/opencode.json"
        else
          mkdir -p "$HOME/.config/opencode"
          cp "$repo/opencode-config/opencode.json" "$HOME/.config/opencode/opencode.json"
          note_next_step "OpenCode: review ~/.config/opencode/opencode.json, then run 'opencode auth login'"
        fi
        ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

SETUP_SECRETS="n"

# Asked up front with the other questions
ask_secrets() {
  echo "Encrypted secrets (secret: sops + age): API keys and .env values stay encrypted in"
  echo "${SECRETS_DIR:-$HOME/Git/secrets} and are decrypted only into the command that needs them."
  echo "This creates this device's key (in the Keychain / Secret Service) and the store."
  echo -n "Set it up now? (y/n)(Default: y): "
  read SETUP_SECRETS
  SETUP_SECRETS=${SETUP_SECRETS:-y}
}

setup_secrets() {
  [[ "$SETUP_SECRETS" =~ ^[Yy] ]] || return 0
  echo "Setting up encrypted secrets..."
  if is_dry_run; then
    echo "  [dry-run] Would run: $REPO_ROOT/shared/bin/secret init"
    return 0
  fi
  if "$REPO_ROOT/shared/bin/secret" init; then
    note_next_step "Secrets: keep ${SECRETS_DIR:-~/Git/secrets} in a PRIVATE repo or Syncthing folder; add other devices with secret add-device; move plaintext keys in with secret import (harden.sh lists them)"
  else
    note_problem "Encrypted secrets not set up; run: secret init"
  fi
}

# Copy a shared config into place only when the user has none. Never overwrites.
install_config_if_missing() {
  local src="$1" dst="$2" mode="$3"
  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "  kept existing ${dst/#$HOME/~}"
    return 0
  fi
  if is_dry_run; then
    echo "  [dry-run] Would copy ${src/#$REPO_ROOT/dotfiles} to ${dst/#$HOME/~}"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst" && chmod "$mode" "$dst" && echo "  installed ${dst/#$HOME/~}"
}

# SSH client, git and tmux defaults from shared/ (ssh-doctor checks the result)
setup_shell_tools() {
  echo "Setting up SSH, git and tmux defaults..."
  if ! is_dry_run; then
    # ControlPath sockets and per-host files; ssh refuses group/world-writable dirs
    mkdir -p "$HOME/.ssh/sockets" "$HOME/.ssh/config.d"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" "$HOME/.ssh/config.d"
  fi
  install_config_if_missing "$REPO_ROOT/shared/ssh/config.template" "$HOME/.ssh/config" 600
  install_config_if_missing "$REPO_ROOT/shared/tmux/.tmux.conf" "$HOME/.tmux.conf" 644

  # Shared git settings (git wip, git inventory, per-forge identity), appended
  # last so its includeIf identities win over the [user] defaults
  if git config --global --get-all include.path 2>/dev/null | grep -qF "shared/.gitconfig"; then
    echo "  kept existing git include of shared/.gitconfig"
  elif is_dry_run; then
    echo "  [dry-run] Would add include.path $REPO_ROOT/shared/.gitconfig to ~/.gitconfig"
  else
    git config --global --add include.path "$REPO_ROOT/shared/.gitconfig" &&
      echo "  git now includes $REPO_ROOT/shared/.gitconfig"
  fi
  note_next_step "SSH: check your setup with ssh-doctor; sign commits with git_sign_setup"
}

# Write the community bookmarks as a standard bookmarks file that every browser
# can import. Writing browser databases directly is unsafe while the browser
# runs, and adding them again on every re-run creates duplicates.
write_bookmarks_file() {
  local bookmarks_file="$HOME/Downloads/irregularchat-bookmarks.html"
  if is_dry_run; then
    echo "[dry-run] Would write IrregularChat bookmarks to $bookmarks_file"
    return 0
  fi
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
  if [[ ${#NEXT_STEPS[@]} -gt 0 ]]; then
    echo ""
    echo "Next steps for you:"
    for step in "${NEXT_STEPS[@]}"; do
      echo "  - $step"
    done
  fi
  echo "======================================"
}
