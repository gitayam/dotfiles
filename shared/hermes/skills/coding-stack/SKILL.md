---
name: coding-stack
description: "Run coding work on this Mac's stack: Claude Code on Anthropic or the two model servers, Paperclip issues, Orca lanes, direct model calls."
version: 1.0.0
author: dotfiles (shared/hermes/skills/coding-stack)
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [Coding-Agent, Claude, Paperclip, Orca, Self-Hosted, Delegation]
    related_skills: [claude-code, paperclip]
prerequisites:
  commands: [claude]
---

# Coding stack on this Mac

Use this skill when the user asks you to build, fix, review or investigate code, check on the model servers, or hand work to Paperclip or Orca. You coordinate; Claude Code does the coding. Every path below is absolute, because the Hermes app may start without the user's shell PATH.

```
BIN=$HOME/Git/dotfiles/shared/bin    # claude-z, zq, oz, ai-policy
CLAUDE=/opt/homebrew/bin/claude
PAPERCLIP=/opt/homebrew/bin/paperclipai
```

## Pick the backend

| Work | Run | Why |
|---|---|---|
| Hard or ambiguous work, architecture, security, final review | `$CLAUDE -p` (Anthropic, Opus) | Best judgment; uses the user's Anthropic plan |
| Bounded coding with a clear check (fix this test, add this endpoint) | `$BIN/claude-z 1 -p` (server 1, GLM-5.3-Flash, 256K) | Private server, no per-token cost |
| Short bounded task, small context | `$BIN/claude-z 2 -p` (server 2, gpt-oss-120b, 48K) | Second server; keep prompts and files small |
| One-shot question, summary, translation, embeddings | `$BIN/zq <key> "prompt"` | No Claude Code needed (`zq --help`) |
| Several questions about a repo, in parallel | `$BIN/oz dispatch --agent claude --cwd <repo> "<question>"` | Read-only Orca lanes on server 1 |
| A small edit as a tracked lane | `$BIN/oz dispatch --agent claude-edit --cwd <repo> "<change>"` | Edit/Write allowed, shell denied; check the result yourself (lanes always report outcome "unknown") |
| Work the user wants tracked on the board | Paperclip issue (below) | Assigned agents work it and comment |

Check first when unsure: `$BIN/claude-z status` lists every server model as UP or DOWN, with its port and context window.

## Claude Code, headless

Run it in the repository, with a contract, and read the result before reporting:

```
cd /path/to/repo && $BIN/claude-z 1 -p --dangerously-skip-permissions --output-format text \
  "Goal: <one sentence>. Only change: <files>. Do not: push, deploy, touch .env. Done when: <command> passes. Report the diff summary and the command output."
```

- Use `$CLAUDE` instead of `$BIN/claude-z 1` for the cloud. Don't pick cloud for routine work without saying so.
- A safety hook in Claude Code blocks rsync `--delete` without a dry-run, force pushes to main, `--no-verify`, `.env` overwrites without a backup and GPU resets. If it blocks something, tell the user; don't work around it.
- A model policy (`$BIN/ai-policy`) refuses Qwen models in IrregularChat and ZenithFlow repos. If claude-z or zq exits with an `ai-policy` message, pick another model; never bypass it.
- The 32K models (keys `2q`, `2s`, `2f`) can't run Claude Code; use them only through `zq`.
- Afterwards, run the project's checks yourself (`git -C <repo> status`, its tests) before telling the user it's done.

## Paperclip (issue board at http://127.0.0.1:3100)

Company `3809d0ba-0e17-4f9b-bc8a-e014670114d6`. Agents that run the real Claude Code CLI:

| Agent | ID | Use for |
|---|---|---|
| Claude Code Cloud (Opus), the lead | `bd03e97b-8ca8-4693-b802-c7a933c33f62` | Planning, review, hard calls |
| Claude Code z1 (GLM) | `35f35fad-2c51-42e7-b4a2-31f2b9d36c50` | Bounded implementation |

(The third agent, Hermes GLM, is you; don't assign yourself through Paperclip.)

```
$PAPERCLIP issue create -C 3809d0ba-0e17-4f9b-bc8a-e014670114d6 --standalone \
  --title "<title>" --description "<goal, files, done-when>" --assignee-agent-id <agent id> --status todo --json
$PAPERCLIP issue get <issue id> --json          # status: todo, in_progress, done, blocked
curl -s http://127.0.0.1:3100/api/issues/<issue id>/comments
$PAPERCLIP service status                         # is the board running?
```

Assigning starts the agent; nothing runs on a timer. Report the issue identifier (e.g. SAC-7) and its final status and comment.

## Health checks

```
$BIN/claude-z status                                   # server models
launchctl list | grep io.zenithflow.tunnel            # the two SSH tunnels (launchd)
$PAPERCLIP service status                              # Paperclip
```

If a server model is DOWN, say so and offer cloud instead; don't restart servers yourself.

## Ask first

Production changes, deploys, pushes, merges, anything irreversible, and switching a task to the paid cloud backend for more than a quick call.
