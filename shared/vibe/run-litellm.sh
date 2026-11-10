#!/usr/bin/env bash
# Run the LiteLLM proxy for cc-vibe on 127.0.0.1:4000, in the foreground
# (launchd io.vibe.litellm and systemd io.vibe.litellm.service restart it).
#
# Keys (MISTRAL_API_KEY, LITELLM_MASTER_KEY) come from the encrypted `secret`
# profile "vibe" and exist only in this process's environment. ~/.vibe/.env is
# used only when there is no profile.
set -euo pipefail
# launchd/systemd start with a minimal PATH: secret, sops and litellm live here
export PATH="$HOME/Git/dotfiles/shared/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
LITELLM="$HOME/.local/bin/litellm"
ARGS=(--config "$HOME/.vibe/litellm-config.yaml" --port 4000 --host 127.0.0.1)

if [[ -f "${SECRETS_DIR:-$HOME/Git/secrets}/vibe.env" ]] && command -v secret >/dev/null; then
  exec secret run vibe -- "$LITELLM" "${ARGS[@]}"
fi
set -a
source "$HOME/.vibe/.env"
set +a
exec "$LITELLM" "${ARGS[@]}"
