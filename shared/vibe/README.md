# shared/vibe — local LiteLLM proxy for `cc-vibe`

Canonical sources for the local LiteLLM proxy that `cc-vibe` (and any other
Claude Code session routed through `http://127.0.0.1:4000`) talks to. The
proxy translates Anthropic `/v1/messages` ↔ Mistral so the same `claude`
CLI binary can run against either backend.

## Files

| File | Deployed to | Purpose |
|---|---|---|
| `litellm-config.yaml` | `~/.vibe/litellm-config.yaml` | Model list (Mistral + Claude-tier aliases), drop-params, master key, registers the trim callback |
| `litellm_trim.py` | `~/.vibe/litellm_trim.py` | Pre-call hook that auto-trims oversize prompts before they hit Mistral's 131072-token cap. Full doc in the file header. |
| `../systemd/user/io.vibe.litellm.service` | `~/.config/systemd/user/` (Linux) | Service that runs the proxy |
| `../launchd/io.vibe.litellm.plist` | `~/Library/LaunchAgents/` (Mac) | launchd job that runs the proxy |
| `run-litellm.sh` | `~/.vibe/run-litellm.sh` (symlink) | Runner both services call; loads the keys, then execs litellm |

Secrets (`MISTRAL_API_KEY`, `LITELLM_MASTER_KEY`) live in the encrypted
`secret` profile `vibe` (`~/Git/secrets/vibe.env`); `run-litellm.sh` starts
the proxy under `secret run vibe`, so the keys exist only in that process.
`~/.vibe/.env` is read only when there is no profile. The YAML references
the keys via `os.environ/...`, contains no secrets and is safe to commit.
`scripts/install-claude-aliases.sh` links the runner and loads the service.

The Vibe CLI itself (`vibe`) does not use the profile: it reads its keys from
the macOS Keychain / Secret Service (service `ai.mistral.vibe`, account = the
variable name). Store one with Vibe's own Python, value on stdin:

```bash
secret run vibe -- sh -c 'printf %s "$PANGOLIN_API_KEY"' |
  ~/.local/share/uv/tools/mistral-vibe/bin/python3 -I -c \
  'import sys,keyring; keyring.set_password("ai.mistral.vibe","PANGOLIN_API_KEY",sys.stdin.read())'
```

The first `vibe` run afterwards may ask to allow Keychain access; choose
Always Allow.

The proxy needs litellm itself. Pin a reviewed version and refuse anything
uploaded later (1.107.0 and 1.82.7/1.82.8 were compromised releases):

```bash
uv tool install --exclude-newer 2026-10-21T11:00:00Z 'litellm[proxy]==1.106.2'
```

## Install / refresh

```bash
~/Git/dotfiles/scripts/install-vibe-trim.sh
```

That script copies the two `~/.vibe/` files into place and restarts the
proxy. It does not touch the runner (`install-claude-aliases.sh` links it)
or any keys.

## Why the trim handler exists

Without it, `cc-vibe` sessions that grow past ~131K tokens (system prompt +
every loaded tool schema + transcript + file reads) hit Mistral with:

    400 ... Prompt contains 131761 tokens ... too large for model
    with 131072 maximum context length

The hook drops oldest middle messages, preserves system + last 6 turns,
and injects a `[N earlier messages trimmed ...]` marker into the system
prompt so the model knows context was reduced. Audit log at
`~/.vibe/logs/trim.log`. Tunables documented in `litellm_trim.py`.

## See also

- `~/Git/llms-local/docs/cc-backends.md` — the full backend table (cc-cloud / cc-vibe / cc-local / cc-mac / ...)
- `~/Git/llms-local/docs/vibe-headless-gotchas.md` — separate tool (`vibe -p`), same `~/.vibe/` dir, different failure modes
