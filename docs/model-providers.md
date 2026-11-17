# Model providers: how each route is reached

Every model family these machines use, where its credential lives, and how a remote
Hermes server gets its own access. Checked 2026-11-17. Which project may use which
family is decided by [ai-policy](ai-policy.md); run `ai-policy check --cwd <repo> --model <id>`
before pointing a repository at a new route.

Ground rules for every route:

- Credentials live in the encrypted `secret` store (`secret list` shows names only) or in
  the tool's own login store. Never paste a value into chat, a prompt or a command line.
- A **subscription login** (OAuth with a rotating refresh token) belongs to one holder.
  Copying it to a server makes both holders refresh the same token, and one signs the
  other out. Give the server its own login or its own API key instead.
- An **API key** may be copied, through stdin only (see the end of this page).

## Codex / ChatGPT subscription

- Mac: `~/.codex/auth.json` (`auth_mode: chatgpt`), used by the Codex CLI and the
  `codex` lane of `orca-lanes`.
- Never copy that file to a server.
- Hermes server: `hermes auth add openai-codex --no-browser`, then enter the shown code
  at `https://auth.openai.com/codex/device`. Hermes keeps its own session; the Mac login
  is untouched. Every profile of that Hermes home shares the credential.
- Models through this login include `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini` and `gpt-5.6-*`.
  In a profile: `model: {provider: openai-codex, default: gpt-5.5}`.

## Lumo

Direct OpenAI-compatible provider `lumo` (`lumo-max`, `lumo-lite`); setup and the
Claude Code bridge are in [claude-lumo.md](claude-lumo.md). Non-streaming replies come
back double-encoded, so a Hermes profile on Lumo pins its auxiliary tasks (title
generation, compression, vision) to another provider. Denied for ZenithFlow.

## Beam (Reflection AI)

- Direct API: `https://api.reflection.ai/openai/v1`, key `REFLECTION_API_KEY`, model
  `Beam-1.0-501B-A23B` (open weights, 1M context, tool calls, reasoning). About 200
  tokens/s. No key is stored yet: `secret set reflection REFLECTION_API_KEY`.
- Through OpenCode: `opencode/beam-free` and `opencode-go/beam-free` both answered on
  2026-11-17 and are outside the Go monthly cap.
- Free tiers may use prompts for training. Check the provider's data terms before
  sending private code.
- ai-policy vendor `reflection` (`beam*`, `Beam-*`), service `reflection-api`.

## DeepSeek

- Direct API: secret profile `deepseek` (`DEEPSEEK_API_KEY`), models `deepseek-flash`
  and `deepseek-v4-pro`. The balance was $0.00 on 2026-11-17, so every call returns 402
  until the account is topped up. `claude-switch deepseek` uses the Anthropic-compatible
  endpoint of the same account.
- Through Alibaba Model Studio: secret profile `alibaba` (`DASHSCOPE_API_KEY`),
  OpenAI-compatible base `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`.
  `deepseek-v4.1-flash` and `deepseek-v4-pro` both answered on 2026-11-17.
  ai-policy denies `service:alibaba-cloud` for IrregularChat and ZenithFlow, so this
  route is for other repositories only; a server bot that also works on those
  repositories must not use it.

## OpenCode (Zen and Go)

- Mac: the OpenCode Console login is OAuth, stored in OpenCode's own database. Don't
  copy it.
- Go models hit the monthly cap in November 2026 (resets around 2026-11-20); free models
  (`beam-free`, `*-free`) keep working. Free models may train on prompts.
- A server needs its own OpenCode API key (`OPENCODE_API_KEY`) from the console. Base
  URLs: `https://opencode.ai/inference/openai/v1` (Zen) and
  `https://opencode.ai/inference/go/openai/v1` (Go).

## Local models

- llama.cpp behind Tailscale Serve on the local model host: reachable on the tailnet
  only, with the key in secret profile `vibe` (`PANGOLIN_API_KEY`).
- A container on a Docker bridge can't resolve MagicDNS names: add the host name with
  `extra_hosts` and keep the TLS name.
- Hermes refuses a main model with less than 64K context. The Gemma server runs a 32K
  window today, so it can serve auxiliary tasks but not a profile's main model until
  its `--ctx-size` is raised.
- Alibaba-family local models (Qwen and fine-tunes named after it) are denied for
  IrregularChat and ZenithFlow, wherever they run.

## Mistral

Hermes bots and the Vibe lane use the Mistral API (keys in secret profiles `vibe` and
the bot-specific profiles). See [orca-lanes.md](orca-lanes.md) for the local lanes.

## Giving a server an API key

Pipe the value from the secret store into a script that runs on the server and reads
stdin, so the value never appears in argv, `ps`, shell history or terminal output:

```sh
secret get deepseek DEEPSEEK_API_KEY | ssh server 'bash ~/bin/add-env.sh /path/to/.env DEEPSEEK_API_KEY'
```

The server-side script should: read one line from stdin; refuse an empty value or one
with characters Docker Compose would interpolate (`$`); refuse when the name already
exists; back up the `.env` first; append `NAME=value`; and print only the name and the
value's length. Recreate the container afterwards (`docker compose up -d
--force-recreate`): `restart` keeps the old environment.
