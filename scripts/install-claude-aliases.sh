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

# 1b. claude-z (self-hosted servers) and its per-backend names z1 z2 z2q zl.
#     An existing non-link claude-z is backed up first.
CZ_DST="$HOME/.local/bin/claude-z"
if [ -e "$CZ_DST" ] && [ ! -L "$CZ_DST" ]; then
    mv "$CZ_DST" "$CZ_DST.bak.$(date +%Y%m%d%H%M%S)"
fi
ln -sfn "$DOTFILES/shared/bin/claude-z" "$CZ_DST"
# one z<key> per chat model in shared/llm/models.conf
for n in z1 z2 z2q z2s z2f z2f2 zl; do ln -sfn claude-z "$HOME/.local/bin/$n"; done
echo "✓ ~/.local/bin/claude-z (+ z1 z2 z2q z2s z2f z2f2 zl) → $DOTFILES/shared/bin/claude-z"

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

# 4. The LiteLLM runner (keys from the encrypted `secret` profile "vibe"), linked
#    from the repo; an existing different runner is backed up first.
mkdir -p "$HOME/.vibe/logs"
RUNNER_SRC="$DOTFILES/shared/vibe/run-litellm.sh"
RUNNER_DST="$HOME/.vibe/run-litellm.sh"
if [ "$(readlink "$RUNNER_DST" 2>/dev/null)" != "$RUNNER_SRC" ]; then
    [ -e "$RUNNER_DST" ] && mv "$RUNNER_DST" "$RUNNER_DST.bak.$(date +%Y%m%d%H%M%S)"
    ln -s "$RUNNER_SRC" "$RUNNER_DST" && echo "✓ linked $RUNNER_DST → repo runner"
fi

# 5. macOS: launchd job for LiteLLM autostart (__HOME__ filled in; launchd
#    doesn't expand ~), reloaded so a changed plist takes effect.
if [ "$(uname -s)" = "Darwin" ]; then
    PLIST_DST="$HOME/Library/LaunchAgents/io.vibe.litellm.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    sed "s|__HOME__|$HOME|g" "$DOTFILES/shared/launchd/io.vibe.litellm.plist" > "$PLIST_DST.tmp" &&
        plutil -lint -s "$PLIST_DST.tmp" && mv "$PLIST_DST.tmp" "$PLIST_DST"
    # Not loaded yet is fine (set -e would otherwise stop here)
    launchctl bootout "gui/$(id -u)/io.vibe.litellm" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"; then
        echo "✓ loaded launchd job io.vibe.litellm (logs: ~/.vibe/logs/litellm.log)"
    else
        echo "⚠ could not load io.vibe.litellm; try: launchctl bootstrap gui/$(id -u) $PLIST_DST"
    fi
fi

# 5b. macOS: one always-on tunnel per model server in shared/llm/models.conf.
#     Ad-hoc tunnels that claude-z started earlier hold the same ports, so they
#     are stopped first; launchd then owns the forwards.
if [ "$(uname -s)" = "Darwin" ]; then
    hosts=$(awk '!/^[[:space:]]*(#|$)/ && $3 != "-" { print $3 }' "$DOTFILES/shared/llm/models.conf" | sort -u)
    pkill -f "autossh -M 0 -N -o ControlMaster=no" 2>/dev/null || true
    for host in $hosts; do
        label="io.zenithflow.tunnel.$host"
        dst="$HOME/Library/LaunchAgents/$label.plist"
        sed "s|__HOME__|$HOME|g; s|__HOST__|$host|g" "$DOTFILES/shared/launchd/io.zenithflow.tunnel.plist" > "$dst.tmp" &&
            plutil -lint -s "$dst.tmp" && mv "$dst.tmp" "$dst"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$dst"; then
            echo "✓ loaded $label (log: ~/Library/Logs/zenithflow-tunnel-$host.log)"
        else
            echo "⚠ could not load $label; try: launchctl bootstrap gui/$(id -u) $dst"
        fi
    done
fi

# 5c. macOS: Paperclip's service plist (written by `paperclipai service install`)
#     has no PATH, so its agents get Apple's Python 3.9 and miss Homebrew tools.
#     Add one when it's missing and reload the service; reinstalls drop it again,
#     so this step is idempotent and safe to rerun.
PAPERCLIP_PLIST="$HOME/Library/LaunchAgents/ing.paperclip.paperclipai.plist"
if [ "$(uname -s)" = "Darwin" ] && [ -f "$PAPERCLIP_PLIST" ]; then
    if /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:PATH" "$PAPERCLIP_PLIST" >/dev/null 2>&1; then
        echo "✓ Paperclip service already has a PATH"
    else
        pc_path="$DOTFILES/shared/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:PATH string $pc_path" "$PAPERCLIP_PLIST"
        launchctl bootout "gui/$(id -u)/ing.paperclip.paperclipai" 2>/dev/null || true
        # bootout returns before the old process is gone; bootstrap fails (EIO) until then
        for _ in $(seq 1 60); do launchctl print "gui/$(id -u)/ing.paperclip.paperclipai" >/dev/null 2>&1 || break; sleep 1; done
        if launchctl bootstrap "gui/$(id -u)" "$PAPERCLIP_PLIST"; then
            echo "✓ added PATH to the Paperclip service and reloaded it"
        else
            echo "⚠ PATH added; reload with: launchctl bootstrap gui/$(id -u) $PAPERCLIP_PLIST"
        fi
    fi
fi

# 6. Linux: install systemd user unit for LiteLLM autostart.
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
