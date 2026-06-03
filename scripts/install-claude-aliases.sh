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

# 2. Source claude-aliases.zsh from ~/.zshrc (idempotent — guard markers)
SHRC="$HOME/.zshrc"
GUARD='# >>> claude-aliases.zsh <<<'
if [ -f "$SHRC" ] && grep -qF "$GUARD" "$SHRC"; then
    echo "✓ ~/.zshrc already sources claude-aliases.zsh (skipping)"
else
    cat >> "$SHRC" <<EOF

$GUARD
[ -r "\$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh" ] && \\
  source "\$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh"
$GUARD
EOF
    echo "✓ appended source-line to $SHRC (guard: $GUARD)"
fi

# 3. Ensure ~/.vibe/ exists; print warning if shared backends env not yet synced
mkdir -p "$HOME/.vibe"
if [ ! -f "$HOME/.vibe/claude-backends.env" ]; then
    echo "⚠ ~/.vibe/claude-backends.env not present yet."
    echo "  Either wait for Syncthing 'vibe-config' folder to deliver it,"
    echo "  or copy $DOTFILES/.claude-backends.env.template to $HOME/.vibe/claude-backends.env"
    echo "  and fill in real values."
fi

echo ""
echo "Done. Open a new shell or 'source ~/.zshrc' to pick up the aliases."
