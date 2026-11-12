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

Use this skill when the user asks you to build, fix, review or investigate code, check on the model servers, or hand work to Paperclip or Orca. You coordinate; Claude Code does the coding. Every command below uses a full path, because the Hermes app starts without the user's shell PATH. Copy the paths as written; don't define shell variables for them (each command runs in a fresh shell).

## Pick the backend

| Work | Run | Why |
|---|---|---|
| Hard or ambiguous work, architecture, security, final review | `/opt/homebrew/bin/claude -p` (Anthropic, Opus) | Best judgment; uses the user's Anthropic plan |
| Bounded coding with a clear check (fix this test, add this endpoint) | `$HOME/Git/dotfiles/shared/bin/claude-z 1 -p` (server 1, GLM-5.3-Flash, 256K) | Private server, no per-token cost |
| Short bounded task, small context | `$HOME/Git/dotfiles/shared/bin/claude-z 2 -p` (server 2, gpt-oss-120b, 48K) | Second server; keep prompts and files small |
| One-shot question, summary, translation, embeddings | `$HOME/Git/dotfiles/shared/bin/zq <key> "prompt"` | No Claude Code needed (`zq --help`) |
| Several questions about a repo, in parallel | `$HOME/Git/dotfiles/shared/bin/oz dispatch --agent claude --cwd <repo> "<question>"` | Read-only Orca lanes on server 1 |
| A small edit as a tracked lane | `$HOME/Git/dotfiles/shared/bin/oz dispatch --agent claude-edit --cwd <repo> "<change>"` | Edit/Write allowed, shell denied; check the result yourself (lanes always report outcome "unknown") |
| Work the user wants tracked on the board | Paperclip issue (below) | Assigned agents work it and comment |

Check first when unsure: `$HOME/Git/dotfiles/shared/bin/claude-z status` lists every server model as UP or DOWN, with its port and context window.

## Claude Code, headless

Write the contract to a file with your file tool, then run Claude Code in the repository with the file on stdin:

```
# ~/.hermes/cache/scratch/<task>.txt
Goal: <one sentence>.
Only change: <files or directories>.
Do not: push, deploy, touch .env, edit tests, or add stub/fake packages to make checks pass.
If a tool or dependency is missing, stop and report it instead of working around it.
Done when: <exact command> passes. Report the diff summary and that command's output.
```

```
cd /path/to/repo && $HOME/Git/dotfiles/shared/bin/claude-z 1 -p --dangerously-skip-permissions --output-format text < ~/.hermes/cache/scratch/<task>.txt
```

Never put the contract in quotes on the command line. Backticks or `$( )` inside quotes run as commands, and Hermes's approval guard stops it.

- Use `/opt/homebrew/bin/claude` instead of `$HOME/Git/dotfiles/shared/bin/claude-z 1` for the cloud. Don't pick cloud for routine work without saying so.
- A safety hook in Claude Code blocks rsync `--delete` without a dry-run, force pushes to main, `--no-verify`, `.env` overwrites without a backup and GPU resets. If it blocks something, tell the user; don't work around it.
- A model policy (`$HOME/Git/dotfiles/shared/bin/ai-policy`) refuses Qwen models in IrregularChat and ZenithFlow repos. If claude-z or zq exits with an `ai-policy` message, pick another model; never bypass it.
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
/opt/homebrew/bin/paperclipai issue create -C 3809d0ba-0e17-4f9b-bc8a-e014670114d6 --standalone \
  --title "<title>" --description "<goal, files, done-when>" --assignee-agent-id <agent id> --status todo --json
$HOME/Git/dotfiles/shared/bin/paperclip-wait <SAC-n or issue id> [seconds]   # waits (default 300 s), prints status + comments
/opt/homebrew/bin/paperclipai service status                         # is the board running?
```

Assigning starts the agent; nothing runs on a timer. The create command prints JSON; read `identifier` (e.g. SAC-7) from it. Then run `paperclip-wait` once and report the identifier, final status and the agent's comment. Don't write polling loops or inline scripts (`python3 -c`, `node -e`): Hermes asks the user to approve each one, and `paperclip-wait` needs no approval. Exit codes: 0 done, 1 blocked or cancelled, 2 still open at the timeout.

## Health checks

```
$HOME/Git/dotfiles/shared/bin/claude-z status                                   # server models
launchctl list | grep io.zenithflow.tunnel            # the two SSH tunnels (launchd)
/opt/homebrew/bin/paperclipai service status                              # Paperclip
```

If a server model is DOWN, say so and offer cloud instead; don't restart servers yourself.

## Credentials and memory

- Never mint, sign, forge or re-sign tokens, and never read service secrets (for example under `~/.paperclip/`, `.env` files or keychains) to get past an authorization error. A 401, 403, 409 or 422 from a service means stop and tell the user what failed.
- Don't save workarounds for access controls to memory or skills. Memory holds preferences and facts; if a lesson involves credentials or permissions, describe it to the user instead of writing it down.

## Ask first

Production changes, deploys, pushes, merges, anything irreversible, and switching a task to the paid cloud backend for more than a quick call.

Force pushes, history rewrites (`reset --hard`, rebases of pushed commits) and `rm -rf` are the user's to run. Don't attempt them or ask Claude Code to: explain what you found (for example, which commits differ between local and remote) and give the exact command for the user to run.
