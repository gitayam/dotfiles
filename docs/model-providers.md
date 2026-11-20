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
- The served list changes with the plan. On 2026-11-17 the login refused `gpt-5.5` twice
  ("not entitled") while listing `gpt-6-sol`, `gpt-6-sol-900k`, `gpt-6-luna`,
  `gpt-6-luna-900k` and `gpt-5.6-sol`; a profile pinned to `gpt-5.5` silently ran on its
  fallback. Name a model explicitly (`model: {provider: openai-codex, default: gpt-6-sol}`)
  and probe it after any plan change:
  `hermes -p <profile> chat -Q -q "Reply with exactly: ok" --provider openai-codex -m <model>`.
  Picking the provider without a model sends `auto`, which the subscription refuses.

## Claude (Team seats)

- Subscription logins (Pro, Max, Team …) are for Claude Code and Anthropic's own apps,
  run as published ([legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)).
  Another agent's own loop (Hermes, the Agent SDK) needs a Console API key instead. Team,
  Max and Ultra plans include [monthly API credits](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-ultra-and-team-plans).
- Mac: Claude Code's own Keychain login.
- Server: run `claude setup-token` on your own machine, then
  `secret set claude-sandbox CLAUDE_CODE_OAUTH_TOKEN_<SEAT>`; one key per seat
  (`_ISSA`, `_IDUNN`, both the owner's paid Team seats). The Hermes coding bot runs the real
  Claude Code CLI in its sandbox (`claude -p`), with each seat's token in a read-only
  `claude-<n>.env`; a wrapper switches to the next seat when a run ends on Claude Code's
  own "usage limit reached" message.
- The standalone CLI comes from npm's `@anthropic-ai/claude-code-linux-x64` package (the
  main package needs Node 22+); pin the version and its sha512.

## Lumo

Direct OpenAI-compatible provider `lumo` (`lumo-max`, `lumo-lite`); setup and the
Claude Code bridge are in [claude-lumo.md](claude-lumo.md). Non-streaming replies come
back double-encoded, so a Hermes profile on Lumo pins its auxiliary tasks (title
generation, compression, vision) to another provider. Denied for ZenithFlow.

## Beam (Reflection AI)

- Direct API: `https://api.reflection.ai/openai/v1`, key `REFLECTION_API_KEY`, model
  `Beam-1.0-501B-A23B` (open weights, 1M context, tool calls, reasoning). Measured
  2026-11-17: 0.3 s to the first token and about 125 tokens/s on a short answer (the owner
  sees about 200 on longer ones). The key is in secret profile `reflection`
  (`secret run reflection -- …`); a Hermes server gets it in its `.env` over stdin.
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

## Alibaba Model Studio (Qwen) on the coding board

- Model lists move: on 2026-11-19 Model Studio listed `qwen4-max` while the board's Qwen
  reviewer still ran an older model. Re-read the provider's model list now and then, and
  before switching a role run a smoke test that makes a real tool call, not just a
  one-line reply.
- A Qwen coder needs its own sandbox. The shared coding sandbox holds clones of projects
  ai-policy denies Alibaba for, so give the Qwen lane a separate sandbox and a GitLab
  **deploy token** per allowed project. A project access token is not enough: its bot user
  could still clone internal projects. More board lessons:
  [hermes-coding-board.md](hermes-coding-board.md).
- Reviewer-role comparison (2026-11-20, public write-up on Irregularpedia, "Alibaba Model
  Studio Coding Models"): `kimi-k2.7-code` is the board's quality reviewer, `qwen4-max`
  the Qwen coder; `qwen4-max` and `kimi-k3.1-pro` return empty structured output through
  Hermes (lesson 15 in hermes-coding-board.md).

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
  only (Serve exposes the OpenAI routes under `/api`, not `/completion` or `/tokenize`).
- One key per consumer since 2026-11-17: each is a line in the host's root-only
  `/etc/llama/api-key` (loaded by `LoadCredential` into all three servers), with a copy in
  `/root/.secrets/llama-keys/<name>` on that host. This Mac's is `vibe/PANGOLIN_API_KEY`
  (`operator-mac`). To rotate one: add a line, restart the servers, move that consumer,
  remove the old line, restart again. Root on the host: `secret get pangolin SUDO_PASSWORD`
  piped to `sudo -S`.
- A container on a Docker bridge can't resolve MagicDNS names: add the host name with
  `extra_hosts` and keep the TLS name.
- Hermes refuses a main model with less than 64K context. The Gemma server runs a 64K
  window since 2026-11-17, so a profile can use it as its main model.
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

Never put a key on the same stdin as a program: `secret get … | ssh host 'python3 -'` with
the script appended makes the key line 1 of the code, and the error traceback prints it
(it happened on 2026-11-17). Copy the script to the host first and pipe only the key.
