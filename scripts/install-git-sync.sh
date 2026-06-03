#!/usr/bin/env bash
# Bootstrap git-sync-all on this device.
#   - symlinks ~/.local/bin/git-sync-all to the dotfiles copy
#   - Linux: installs systemd user unit + timer, enables + starts
#   - macOS: installs launchd plist, loads + starts
# Idempotent. Run after the Mac/qube has pulled the dotfiles repo.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/Git/dotfiles}"
[ -d "$DOTFILES" ] || { echo "dotfiles not found at $DOTFILES"; exit 1; }

SCRIPT_SRC="$DOTFILES/shared/bin/git-sync-all"
[ -f "$SCRIPT_SRC" ] || { echo "Error: $SCRIPT_SRC not present yet (qube may still be transporting it)"; exit 1; }

# 1. Symlink the script into ~/.local/bin
mkdir -p "$HOME/.local/bin" "$HOME/.local/state/git-sync"
ln -sfn "$SCRIPT_SRC" "$HOME/.local/bin/git-sync-all"
echo "✓ ~/.local/bin/git-sync-all → $SCRIPT_SRC"

# 2. Ensure ignore list exists (the canonical copy at ~/Git/.git-sync-ignore
#    rides Syncthing's git-sac-mac folder, but each device should be able
#    to add device-local entries via a sidecar if needed)
if [ ! -f "$HOME/Git/.git-sync-ignore" ]; then
    echo "⚠ ~/Git/.git-sync-ignore missing — wait for Syncthing to deliver"
    echo "  or create with one repo-name-per-line and re-run."
fi

# 3. Per-OS service install
OS="$(uname -s)"
case "$OS" in
  Linux)
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_SRC="$DOTFILES/shared/systemd/user/git-sync.service"
        TIMER_SRC="$DOTFILES/shared/systemd/user/git-sync.timer"
        if [ -f "$SERVICE_SRC" ] && [ -f "$TIMER_SRC" ]; then
            mkdir -p "$HOME/.config/systemd/user"
            ln -sfn "$SERVICE_SRC" "$HOME/.config/systemd/user/git-sync.service"
            ln -sfn "$TIMER_SRC"   "$HOME/.config/systemd/user/git-sync.timer"
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user enable --now git-sync.timer 2>/dev/null \
                && echo "✓ git-sync.timer enabled + started" \
                || echo "⚠ systemd user units symlinked but not enabled (need 'loginctl enable-linger \$USER'?)"
        else
            echo "⚠ Linux systemd units not yet in dotfiles; only the script is installed"
        fi
    fi
    ;;
  Darwin)
    PLIST_SRC="$DOTFILES/shared/launchd/io.gitsync.plist"
    PLIST_DST="$HOME/Library/LaunchAgents/io.gitsync.plist"
    if [ ! -f "$PLIST_SRC" ]; then
        echo "⚠ macOS plist not in dotfiles yet"
    else
        mkdir -p "$HOME/Library/LaunchAgents"
        # Symlink so updates to the plist in dotfiles flow through
        ln -sfn "$PLIST_SRC" "$PLIST_DST"
        # Unload first (idempotent — safe on a fresh install)
        launchctl unload "$PLIST_DST" 2>/dev/null || true
        launchctl load -w "$PLIST_DST"
        echo "✓ ~/Library/LaunchAgents/io.gitsync.plist loaded"
        echo "  next run scheduled in ~1h; run 'git-sync-all --status' for an offline report now"
    fi
    ;;
  *)
    echo "⚠ Unsupported OS for autostart: $OS (script still installed manually)"
    ;;
esac

echo ""
echo "Done."
echo ""
echo "Quick checks:"
echo "  git-sync-all --status         # offline dirty/ahead/behind summary"
echo "  git-sync-all                  # fetch + ff-pull cycle"
echo "  cat ~/.local/state/git-sync/last-run.log"
