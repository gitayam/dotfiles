# ai-policy: which AI services and models a project may use

One policy file, `shared/ai-policy/policy.json`, decides which model families and
inference services each project may use. `shared/bin/ai-policy` evaluates it,
and every place a coding agent starts a model request asks it first:

| Enforcement point | How | On deny |
|---|---|---|
| Claude Code (any backend: `claude-switch`, `cc-opencode`, plain `claude`) | `UserPromptSubmit` hook: `ai-policy claude-hook` reads `ANTHROPIC_BASE_URL`, the model env vars and the models in the session transcript (a `/model` switch shows up there) | Prompt blocked; reason shown |
| `orca-lanes` (all lanes) | Checks the lane's endpoint and model before every dispatch and resume | Lane fails with `agent_unavailable` and the reason |
| OpenCode 2.x | Plugin `shared/opencode/plugins/ai-policy` throws from the `context` hook, which runs before every agent model request | Run ends with an error event carrying the reason |
| Repository contents | `ai-policy scan [dir]` lists tracked files naming a denied model or service host (docs skipped unless `--include-docs`) | Exit 3, `file:line` list |

Install on a machine (idempotent; backs up `~/.claude/settings.json` first):

```sh
ai-policy install          # Claude Code hook + OpenCode plugin link
ai-policy install --check  # report only
```

After installing, stop OpenCode's background service if it was already running
(`pkill -f 'opencode serve --service'`; the next `opencode` run starts a new one).
On 2026-11-12 a service started before the plugin link kept serving the
IrregularChat monorepo without it, while `--standalone` runs were blocked.

## Policy terms

Rules deny terms for named projects:

| Term | Matches | Example |
|---|---|---|
| `vendor:<id>` | Models made by a vendor, wherever they run (self-hosted weights included) | `vendor:alibaba` covers `qwen3.8-max`, `opencode-go/qwen3.7-plus`, `qwen3.6:latest`, `Qwen/Qwen2.5-72B-Instruct` |
| `service:<id>` | Any model served by an endpoint or provider id | `service:alibaba-cloud` covers `dashscope-intl.aliyuncs.com` and OpenCode's `alibaba/*`, so DeepSeek or Kimi served by Alibaba Cloud too |
| `tag:<tag>` | Every vendor or service carrying the tag | `tag:cn-jurisdiction`, `tag:self-hosted` |
| `model:<glob>` | A model id | `model:deepseek-v4-pro*` |

Projects are matched by git remote (`host/group/repo`, normalized from HTTPS, SSH
and scp-style URLs), or by `paths`. A model the catalog doesn't know has no vendor
term, so deny lists stop known families; add new families to `vendors` as they appear.

## Current rules (2026-11-12)

| Projects | Denied | Why |
|---|---|---|
| `irregularchat` (GitLab `irregulars/*`, GitHub `irregularchat/*`), `zenithflow` (GitLab and GitHub `zenithflowinc/*`) | `vendor:alibaba`, `service:alibaba-cloud` | Alibaba models and Alibaba Cloud are prohibited there |

Useful checks:

```sh
ai-policy explain --cwd ~/Git/irregularchat-monorepo
ai-policy check --cwd . --model qwen3.8-max; echo $?    # 3 = denied
ai-policy classify --model opencode-go/qwen3.7-plus
ai-policy scan ~/Git/irregularchat-monorepo
```

The checker fails closed: an unreadable or invalid policy blocks Claude Code
prompts, lanes and OpenCode requests until it is fixed. It governs the coding
agents on this machine; it does not change what deployed apps call at runtime.
Use `scan` (or a CI job running it) for that.
