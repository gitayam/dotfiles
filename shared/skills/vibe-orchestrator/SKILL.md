---
name: vibe-orchestrator
description: Coordinate bounded coding or research work across Claude Code, native OpenCode, and Mistral Vibe when the user requests multi-agent work or delegation. Qualify model routing, preserve isolated ownership, and verify results before integration.
---

# Bounded cross-harness orchestration

Use the user's chosen harness and provider. This skill supports requested delegation; it does not authorize new accounts, paid providers, publication, production changes, or extra access.

## Establish the real lane

Check the installed tool version, available models, active workspace, and selected endpoint without printing credentials. A non-Anthropic `ANTHROPIC_BASE_URL` may be a hosted metered gateway. Neither an alias such as `opus` nor an endpoint's reachability proves the served model, quota, or coding quality.

Qualify the exact lane on a disposable read/edit/test task before using it as a repository writer. Distinguish a working text reply from tool use and accepted code. If unavailable, report the cause and continue through an already authorized qualified lane; do not hide provider or cost changes.

## Work contract and acceptance

Give each worker:

- Exact repository/worktree and baseline revision, plus existing dirty paths.
- A narrow question or disjoint owned paths, and prohibited changes.
- Applicable project guidance and only the necessary evidence.
- Objective acceptance commands, expected artifacts, budget/deadline, and stop conditions.

Keep one integration owner. Use separate worktrees for concurrent writers and an appropriate execution boundary; worktrees do not constrain tools or credentials. Start small and expand only when accepted throughput improves. Do not recursively delegate by default.

Capture the actual diff, check output, model/provider, usage, termination reason, and unresolved questions. Verify findings in the code. An assistant-written PASS, exit zero, or a second model's approval does not replace acceptance checks. Integrate and test from the combined tree.

## Native OpenCode V2

Use installed help and [current CLI documentation](https://opencode.ai/v2/docs/cli/commands/):

```sh
opencode --version
opencode run --help
opencode models
opencode run --model opencode-go/qwen3.7-plus "Explain the failing test"
```

Choose an available model rather than assuming the example is present. V2 supports `--continue`, `--session`, `--server`, and `--standalone`. `--auto` approves asks but preserves explicit denies; use it only within the intended execution boundary. Old `--attach` and `--dangerously-skip-permissions` are not V2.1 flags.

Native `agents` configuration can assign `provider/model#variant` per role. Children have fresh context, use their own permissions, and inherit the parent model only when no model is set. A prose-only readonly profile is insufficient: deny editing, general shell, recursive dispatch, and any other enabled write-capable tools as appropriate. Read-only reviewers can receive a prepared diff and test evidence.

V2 discovers `AGENTS.md` and compatible Claude skill directories, but does not automatically load `CLAUDE.md`, Claude global rules, or Claude agent profiles. It currently has no active LSP diagnostics. Run real compiler, lint, and tests explicitly. See [setup and configuration](https://irregularpedia.org/ai-ml/opencode/).

## Claude Code using a Go gateway

This keeps Claude's tools, skills, rules, and profile system. Native OpenCode configuration does not govern Claude child agents. The gateway needs an Anthropic-compatible model and private credentials, with explicit tier/subagent mappings. A change in base URL does not make every Claude feature compatible. See [gateway setup](https://irregularpedia.org/ai-ml/claude-code-self-hosted/#opencode-go-with-the-claude-harness).

## Mistral Vibe

Inspect the selected provider/profile and current `vibe --help`. Specify an agent on each scripted invocation; an interactive default does not prove headless permissions. Keep a wall deadline and usage/turn bounds independent of buffered stdout. Empty output alone does not establish a stall, and HTTP 402, 429, authentication failure, and unreachable inference are different failures. See [Vibe headless guidance](https://irregularpedia.org/ai-ml/vibe-headless-gotchas/).

## Cost discipline

Record retries, cache reads/writes, output, warm calls, wall time, and rework. Stable prefixes may reduce eligible input cost; separate model contexts and worker output remain billable. Go subscriptions have per-model quotas. Private GPUs have capacity and operating costs. Do not infer unlimited inference, universal cache sharing, or a fixed saving percentage.
