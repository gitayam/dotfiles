# Native OpenCode local setup

Maintained for OpenCode 2.1.0 on 2026-10-21. This installs the personal native
configuration, five compatible shared skills and two launchers. It does not
configure remote hosts or modify authentication, service.json, databases, plugins
or Claude hooks. Read the payload before using this personal setup on another Mac.

```sh
python3 scripts/install_opencode.py
opencode reload
```

The scoped installer copies only managed files, atomically replaces each file,
and saves replaced bytes (including corrupt NUL files) under a private
`~/.local/state/opencode-setup/<timestamp>/` directory with a manifest. Existing
adjacent skill resources and historical RESEARCH_LOG.md are retained. A failure
mid-install can leave a partial update; use the receipt to inspect/restore exact
targets, then rerun the installer. It never runs the broad dotfiles bootstrap.
Copies are independent of the checkout; rerun after reviewing future updates.

| Maintained source | Installed destination |
|---|---|
| `shared/opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `shared/opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| `shared/skills/*` | `~/.claude/skills/*` (compatible Claude/OpenCode discovery) |
| `shared/bin/oc-task`, `cc-opencode` | `~/.local/bin/` |

The default remains native `build` with its provider coding prompt and explicit
`opencode-go/qwen3.7-plus`. Scout and reviewer use `opencode-go/glm-5.3-flash`, fresh
contexts, and a deny-all policy with only file reads and glob discovery reenabled.
Shell, edit/write/patch, execute/Code Mode, grep, recursive children and unknown MCP
actions remain denied. External file access and common credential paths are denied.
Grep is omitted because its permission resource is the regex, not a path filter.
Local reads still may reveal sensitive source; these profiles are not an OS sandbox
or a comprehensive secret scanner. Do not supply an untrusted repository with
operator credentials or claim final security sign-off from these roles.

The main agent asks for shell and external-directory use. `--auto` approves asks,
so use it only for deliberately bounded authorized work; configured denies remain.
Project config and later agent rules can change permissions. Audit effective
configuration in the target location. This is personal configuration, not an
enterprise managed policy. The controller's Proxmox model lanes remain separately
blocked; native fixture success does not activate them.

## Bounded native tasks

```sh
oc-task --cwd /path/to/trusted/project --timeout 300 \
  --prompt 'Fix the failing unit test and run its checker' \
  --check-command '["python3", "-m", "unittest", "-v"]'
```

Choose the deadline for the task; there is no universal timeout. `--auto` is an
explicit opt-in. `--prompt-file` can replace `--prompt`. The launcher aligns
the actual cwd and inherited PWD (required by the tested V2.1.0 runtime), uses a
private `--standalone` server and closes stdin. It terminates the process group on
deadline/interruption, preserves partial files, and never automatically retries.
Reconcile partial state before a retry, especially around external side effects.

Evidence is private under `~/.local/state/oc-task/` or a new `--artifacts` directory
outside the task workspace. Raw task events can contain source or sensitive text;
do not publish them without review. Only selected model/usage fields are retained
from sanitized session export. Parent model turns and cache counters exclude child
sessions; collect child receipts separately when measuring a team. Reported gateway
cost is not incremental cash expense on Go. Warming is disabled.

Exit 0 requires normal completion, no session errors, recorded expected parent
model identity, and a passing explicit checker. Without a checker, acceptance is
`unchecked` and exit is 2; deadline is 124, interruption 130. A checker may pass on
partial output while the overall task remains incomplete. The task deadline covers
inference; metadata export and the separately bounded checker add wall time.

The checker runs trusted operator code with the local environment. It is not a
credential-free generated-code validator. Execute untrusted generated code only
inside a suitable isolated validator. The launcher itself does not contain the
agent's shell, filesystem or network access.

`cc-opencode` is a separate Claude-harness gateway launcher; see
[Claude routing and qualification](claude-opencode.md). Native configuration does
not govern Claude children. No model API keys are copied into this repository.

## Verification

```sh
python3 -m unittest discover -s scripts -p test_opencode_setup.py -v
```

The tests verify silent DONE without artifacts fails, actual checked output passes,
missing model metadata and unchecked tasks cannot claim acceptance, deadlines kill
a surviving subprocess, and installation preserves adjacent auth files and backs
up corrupt skill bytes. See [the dated live receipt](opencode-validation-2026-10-21.md)
for native runtime checks. These are scoped qualification fixtures, not a product
ranking or a production reliability estimate.

Project customization: retain real repository test commands in AGENTS.md and add
only needed legacy CLAUDE.md paths under native `instructions`. Claude hooks,
agent profiles and global rules are not automatically imported into native V2.
The repaired skills load detailed references on demand rather than embedding the
full study in every prompt. [Current V2 documentation](https://opencode.ai/v2/docs/)
and [the audited study](https://irregularpedia.org/ai-ml/agent-reliability-study/)
explain the evidence and limits.
