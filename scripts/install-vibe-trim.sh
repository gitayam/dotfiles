#!/usr/bin/env bash
# install-vibe-trim.sh — deploy the canonical LiteLLM proxy config + trim
# handler from this dotfiles repo into ~/.vibe/, then restart the proxy.
#
# Idempotent: re-run any time to pick up edits in shared/vibe/.
#
# Does NOT touch ~/.vibe/.env (secrets) or ~/.vibe/run-litellm.sh (host-
# specific runner). Those are managed outside the dotfiles repo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_DIR/shared/vibe"
DST_DIR="$HOME/.vibe"

if [ ! -d "$DST_DIR" ]; then
  echo "ERROR: $DST_DIR does not exist. Set up vibe first (install mistral-vibe,"
  echo "       create ~/.vibe/.env with MISTRAL_API_KEY + LITELLM_MASTER_KEY,"
  echo "       deploy ~/.vibe/run-litellm.sh)."
  exit 1
fi

deploy() {
  local rel="$1"
  local src="$SRC_DIR/$rel"
  local dst="$DST_DIR/$rel"
  if [ ! -f "$src" ]; then
    echo "  skip $rel (not in repo)"
    return
  fi
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  ok   $rel (already current)"
    return
  fi
  if [ -f "$dst" ]; then
    local backup="$dst.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$dst" "$backup"
    echo "  back $rel -> $(basename "$backup")"
  fi
  cp "$src" "$dst"
  echo "  copy $rel"
}

echo "Deploying vibe config from $SRC_DIR -> $DST_DIR"
deploy litellm-config.yaml
deploy litellm_trim.py

# Restart proxy so it picks up changes.
if [ "$(uname)" = "Darwin" ]; then
  if launchctl list 2>/dev/null | grep -q '^[0-9-]\+\s\+[0-9-]\+\s\+io\.vibe\.litellm$'; then
    echo "Restarting launchd job io.vibe.litellm ..."
    launchctl kickstart -k "gui/$UID/io.vibe.litellm"
  else
    echo "(io.vibe.litellm not loaded in launchd — not restarting)"
  fi
elif command -v systemctl >/dev/null 2>&1; then
  if systemctl --user list-unit-files io.vibe.litellm.service >/dev/null 2>&1; then
    echo "Restarting systemd unit io.vibe.litellm ..."
    systemctl --user restart io.vibe.litellm.service
  else
    echo "(io.vibe.litellm.service not installed in --user systemd — not restarting)"
  fi
fi

# Quick health probe.
sleep 3
if curl -fsS -m 5 -o /dev/null http://127.0.0.1:4000/health/liveliness 2>/dev/null; then
  echo "Proxy healthy on 127.0.0.1:4000"
else
  echo "WARN: proxy did not respond on 127.0.0.1:4000 — tail ~/.vibe/logs/litellm.log"
fi
