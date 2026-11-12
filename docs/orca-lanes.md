# orca-lanes: more harnesses behind Orca's lane contract

`shared/bin/orca-lanes` runs Orca's own `orca/v1` lane verbs (`dispatch`,
`inspect`, `resume`, `kill`, `lanes`, `agents`, `contract`) with a registry
that adds harnesses Orca 0.2.25 doesn't ship. Lane records, envelopes, exit
codes, deadlines and process-group kills are Orca's; the wrapper adds adapters.

```sh
orca-lanes agents
orca-lanes dispatch --agent vibe --cwd ~/Code/scratch "Fix the flaky store test"
orca-lanes dispatch --agent opencode --model opencode/deepseek-v4.1-flash-free --cwd . "…"
orca-lanes inspect lane_1234abcd
orca-lanes resume lane_1234abcd "Now run the tests"
orca-lanes kill lane_1234abcd
```

| Agent | Harness and command | Writes | Continuity check |
|---|---|---|---|
| `claude` | Orca's adapter, default permissions | No: Write lands in `permission_denials`, yet the lane reports `completed` | session id + transcript growth |
| `claude-edit` | Claude Code, `--permission-mode acceptEdits` | Edit/Write; Bash denied | same as `claude` |
| `codex` | Orca's app-server adapter | Yes | thread id |
| `deepseek` | Claude Code on DeepSeek, through `cc-opencode` (OpenCode Go) or, with `ORCA_DEEPSEEK_ROUTE=api`, the DeepSeek API key from `secret` profile `deepseek` | Edit/Write; Bash denied | same as `claude` |
| `alibaba` | Claude Code on Alibaba Model Studio (Singapore): pay-as-you-go (`DASHSCOPE_API_KEY`) or, with `ORCA_ALIBABA_PLAN=coding`, the Coding Plan (`DASHSCOPE_CODING_API_KEY`), both in `secret` profile `alibaba`. `--model` picks Qwen, DeepSeek, Kimi or GLM | Edit/Write; Bash denied | same as `claude` |
| `dsh` | DeepSeek Harness, `dsh --profile headless --json -`; key from `secret` profile `deepseek` | not yet observed | `--session-id` (unknown ids fail) + echo |
| `opencode` | `opencode run --standalone --format json` | Per `opencode.json`; anything set to "ask" is rejected and reported | `session export` before and after (`--session` would silently create a new one) |
| `vibe` | `vibe -p --output streaming --trust --agent accept-edits` | Edit/Write; shell denied | `--resume` (unknown ids fail) + `export.json` session id |

Every lane reports `semanticOutcome: unknown`. Denied tools surface as
`permissionDenials` progress events, but a lane whose work was blocked can still
say `completed`. Check the files, tests or diff yourself.

## Probe, 2026-11-12 (Orca 0.2.25, Mac)

Read = "reply with the secret word in README.md"; write = "create `hello-<agent>.txt` containing `hi`".

| Agent | Read | Write | Resume | Notes |
|---|---|---|---|---|
| `claude` | 6 s | blocked, reported `completed` | | earlier probe |
| `claude-edit` | | 5 s, file correct | verified | |
| `codex` | | 10 s, file correct | | earlier probe |
| `opencode` (`deepseek-v4.1-flash-free`) | 6 s | 13 s, file correct | verified; deleted session → exit 4 `continuity_unverified` | 5 s deadline → exit 5, group killed |
| `vibe` (Mistral) | 16 s | 19 s, file correct | verified | `kill` mid-run stopped the process group before any file was written |
| `deepseek` | fails: OpenCode Go monthly limit (429); with `ORCA_DEEPSEEK_ROUTE=api`, 402 Insufficient Balance | | | key stored and accepted (`/models` 200); the account balance is $0.00 |
| `dsh` | fails: 402 Insufficient Balance (`QUOTA`) | | | same key and account |
| `alibaba` (pay-as-you-go, `qwen3.8-max`) | 19 s | 16 s, file correct | verified | `--model deepseek-v4-pro` and `--model kimi-k3` also wrote correct files (20 s, 18 s) |
| `opencode` (`alibaba/qwen3.8-max`) | 9 s | 33 s, file correct | | key from `secret` profile `alibaba` for that run only |

Alibaba's pay-as-you-go key works only on the Singapore endpoint (`dashscope-intl`); the
Beijing and US endpoints return 401. The Coding Plan (`sk-sp-` keys) has its own endpoint
and a shorter model list (`qwen3.7-plus`, `qwen3.6-plus`, `qwen3.5-plus`, `kimi-k2.5`,
`glm-5`, `MiniMax-M2.5`). Claude Code logs `unrecognized_model` for these models and
prices them as Anthropic models, so ignore its `costUsd`; check spend in the Model Studio
console. `source claude-switch alibaba` (or `alibaba-coding`) gives an interactive
session on the same routes.

OpenCode Zen's pay-as-you-go DeepSeek models need Zen credit (402 without it).
Zen `*-free` models may use prompts for training: public or throwaway code only.

## Where these lanes fit

These lanes run on the operator's Mac with the operator's logins, guarded only
by each harness's permission mode. Use them for fan-out you supervise: research
and read-only questions, a second opinion from another model family (Mistral,
DeepSeek, OpenAI, Anthropic), and bounded edits in a scratch worktree. Hermes
coding jobs go through the broker and the sandboxed worker on the coding guest,
where each harness becomes a qualified lane with its own relay and credential
(see `ai-coding-env/docs/swappable-coding-stack.md`). Don't point an
`orca-lanes` lane at a production checkout, and never put secrets in a prompt.

The wrapper imports Orca's internal modules, so it refuses any orcastrator
version other than the one it was qualified on (0.2.25). After an upgrade,
rerun the probes and update `PINNED_ORCA`.
