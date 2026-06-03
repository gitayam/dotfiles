#!/usr/bin/env bash
# Bootstrap script — wire claude-switch + cc-* aliases on a new device.
# Idempotent. Source after `git pull` in ~/Git/dotfiles.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/Git/dotfiles}"
[ -d "$DOTFILES" ] || { echo "dotfiles not found at $DOTFILES"; exit 1; }

# 1. Symlink claude-switch into ~/.local/bin
mkdir -p "$HOME/.local/bin"
ln -sfn "$DOTFILES/shared/bin/claude-switch" "$HOME/.local/bin/claude-switch"
echo "✓ ~/.local/bin/claude-switch → $DOTFILES/shared/bin/claude-switch"

# 2. Source claude-aliases.zsh from every interactive-shell rc file present.
#    The fragment is bash/zsh-compatible (POSIX function syntax + alias).
#    Idempotent via guard markers. Does NOT create rc files that don't exist.
GUARD='# >>> claude-aliases.zsh <<<'
SOURCE_LINE='[ -r "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh" ] && source "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh"'

wire_shellrc() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    if grep -qF "$GUARD" "$rc"; then
        echo "✓ $rc already sources claude-aliases (skipping)"
    else
        printf '\n%s\n%s\n%s\n' "$GUARD" "$SOURCE_LINE" "$GUARD" >> "$rc"
        echo "✓ appended source block to $rc"
    fi
}

wire_shellrc "$HOME/.zshrc"
wire_shellrc "$HOME/.bashrc"

# 3. Ensure ~/.vibe/ exists; print warning if shared backends env not yet synced
mkdir -p "$HOME/.vibe"
if [ ! -f "$HOME/.vibe/claude-backends.env" ]; then
    echo "⚠ ~/.vibe/claude-backends.env not present yet."
    echo "  Either wait for Syncthing 'vibe-config' folder to deliver it,"
    echo "  or copy $DOTFILES/.claude-backends.env.template to $HOME/.vibe/claude-backends.env"
    echo "  and fill in real values."
fi

# 4. Linux: install systemd user unit for LiteLLM autostart (Mac uses launchd plist
#    at ~/Library/LaunchAgents/io.vibe.litellm.plist — NOT touched by this script).
#    `cc-vibe` requires litellm running on :4000; without autostart, you'd have to
#    `nohup ~/.vibe/run-litellm.sh &` after every reboot/login.
if [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    UNIT_SRC="$DOTFILES/shared/systemd/user/io.vibe.litellm.service"
    UNIT_DST="$HOME/.config/systemd/user/io.vibe.litellm.service"
    if [ -f "$UNIT_SRC" ]; then
        mkdir -p "$HOME/.config/systemd/user" "$HOME/.vibe/logs"
        ln -sfn "$UNIT_SRC" "$UNIT_DST"
        echo "✓ symlinked systemd user unit → $UNIT_DST"

        # Reload, enable, start — don't fail loudly if the user session bus isn't running
        # (e.g., headless server where the user hasn't logged in graphically yet)
        if systemctl --user daemon-reload 2>/dev/null; then
            systemctl --user enable --now io.vibe.litellm.service 2>/dev/null \
                && echo "✓ enabled + started io.vibe.litellm.service" \
                || echo "⚠ systemd user unit installed but not enabled (may need 'loginctl enable-linger $USER' first)"
        else
            echo "⚠ systemctl --user not available in this session; run 'systemctl --user enable --now io.vibe.litellm.service' interactively later"
        fi
    fi
fi

echo ""
echo "Done. Open a new shell or 'source ~/.zshrc' (or '.bashrc') to pick up the aliases."
