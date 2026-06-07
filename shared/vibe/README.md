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

Secrets (`MISTRAL_API_KEY`, `LITELLM_MASTER_KEY`) live in `~/.vibe/.env`
and are referenced from the YAML via `os.environ/...` — the YAML itself
contains no secrets and is safe to commit.

## Install / refresh

```bash
~/Git/dotfiles/scripts/install-vibe-trim.sh
```

That script copies the two `~/.vibe/` files into place and restarts the
proxy. The runner script `~/.vibe/run-litellm.sh` and the env file
`~/.vibe/.env` are NOT touched (those exist outside the dotfiles repo).

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
