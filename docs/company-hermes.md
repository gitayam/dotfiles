# Company Hermes workspace

Company repositories live under `~/zenithflow`; personal repositories remain in
`~/Git`. The workspace root is intentionally not a Git repository. Keep device
inventory, private service settings, model weights, logs and memory in
`~/zenithflow/.workstation`, outside every company checkout.

`scripts/setup_work_hermes.py` installs company launchers, a route guard, an
approved-provider Hermes configuration and a company coding skill. It defaults
to a dry run; use `--apply` after inspecting it. Device addresses, Enterprise
organization UUID and credentials are supplied locally, never checked in here.

```sh
uv run --with pyyaml python scripts/setup_work_hermes.py \
  --hermes-home ~/.hermes/profiles/zenithflow --enterprise-org YOUR_ORG_UUID
# Work-only Mac: --scope device --hermes-home ~/.hermes
# Apply the same arguments with --apply after reviewing the proposed paths.
```

The personal Mac gets a separate Hermes profile and Enterprise Claude config
directory. Its ordinary Hermes profile and personal Claude account remain
available. The work-only Mac uses its existing Hermes home and Enterprise
account, with an organization pin. Configuration changes retain timestamped
backups and existing unrelated Claude hooks.

For a workstation that moves networks, point the SSH relay at a stable private
SSH alias and update that alias's `HostName` when its address changes. Verify the
new address against the previous host key first. Loopback model/decision URLs
remain unchanged. After reconnecting, reconcile existing issues and runs before
retrying: a run can be cancelled while a later controller retry finishes the
same issue. Verify inference and a decision through the relay, not just its port.

On a work-only device the ordinary alias installer detects the private device
configuration and refreshes just that setup. It does not install the personal
provider catalog. `~/.config/ai-policy/device-models.conf` also restricts the
ordinary `claude-z` / `zq` registry to z1/z2, including from stale shells.
Refresh directly with `--from-config ~/zenithflow/.workstation/config.json --apply`.

| Launcher | Purpose |
| --- | --- |
| `hermes-zenithflow` | Company Hermes coordinator; local Gemma by default |
| `zf-local` | Real Claude Code using the work Mac's local Gemma |
| `zf-z1`, `zf-z2` | Real Claude Code on organization GLM / gpt-oss servers |
| `zf-claude` | Real Claude Code using the company Enterprise login |
| `zf-zq local\|1\|2 "prompt"` | Direct model request |
| `zf-decide` | AnyJev decision JSON on stdin; reads its credential file |
| `zf-paperclip` | Company-scoped Paperclip issue, agent and project commands |
| `zf-status` | Check model inventory at the configured endpoints |
| `zf-orca dispatch --agent claude ...` | Read-only Orca lane; `ZF_MODEL` selects local/1/2 |

Hermes Kanban, Paperclip issues and Orca lanes are separate records. Hermes calls
Paperclip/Orca through the terminal, while the actual worker is Claude Code.
The company wrapper supports direct editing and read-only Orca dispatch; no
Paperclip-to-Orca handoff, Orca edit adapter or community shipping service is
configured. Board/lane completion does not authorize publication.

Provision `.workstation/paperclip.json` with the actual `company_id` and approved
agent metadata before refreshing setup. `zf-paperclip` uses a private context,
with explicit company arguments where the native CLI requires them. A personal
Mac uses a separate SSH forward on loopback port 13100 to the work Mac's 3100;
its ordinary Paperclip client/context remains separate. No API credential is
stored in the generated context. Missing metadata fails rather than selecting
another company. Company refreshes also repair a managed Paperclip CLI shim's
stale Homebrew Node pin to the stable `opt/node` path, retaining its pinned CLI
payload and a backup.

```sh
zf-paperclip agent list --json
zf-paperclip project list --json
zf-paperclip issue get ISSUE_ID --json
zf-orca inspect LANE_ID
```

Every model tier and subagent in a self-hosted Claude Code launch uses that
endpoint's served model. z2 has a 49,152-token window: useful for bounded tasks,
below Hermes's 64K main-agent floor. Do not inflate its advertised context.

## Make the Desktop usable

On a configured machine, review any organization bootstrap before rerunning it.
An alias-only `~/.gitconfig` template can erase scoped identity, signing and
credential includes; back up and preserve/merge those settings. A model menu is
not approval to use every model. Preserve an already-working Claude install and
its company login: package channel and Enterprise authentication are separate.
Tags that install npm packages also need Node/npm prerequisites.

Check `zsh -lic 'command -v hermes'` as well as an absolute launcher. The device
installer puts `~/.local/bin` first at the end of `.zshrc`, after Homebrew/shell
initialization, with backup and an idempotent managed block. An earlier PATH
entry can be shadowed later. A symlinked `.zshrc` is preserved and reported for
an explicit source-file fix. Workspace-only setup does not change personal
shell precedence. A model/version string alone does not distinguish two Hermes
installs; inspect `hermes --version`'s install directory and runtime too.

On the company-only work Mac, provision specialist profiles and project boards:

```sh
python3 scripts/setup_work_desktop.py --from-config ~/zenithflow/.workstation/config.json --apply
hermes webapp --build-only
hermes gateway install --no-start-now --if-missing
hermes gateway restart --detach
```

Use the same PyYAML-capable Python as the main setup. This adds `zf-planner`,
`zf-developer` and `zf-reviewer`, pins their main/auxiliary/delegated inference to
approved routes, and gives each its own memory and company skill. The host
gateway serves the profiles. It preserves the default board and existing work.
Company project boards get a repository default workdir; select a project/worktree
for source edits. Use the work Mac's Desktop/relay from a personal machine rather
than creating these device-wide roles in a personal default Hermes installation.

**Required UI step:** in Hermes Desktop, open **Capabilities → Plugins** and
enable **Desktop: Kanban** and **Desktop: Bots**. Hermes 0.23.2 ships Kanban's
Desktop pane off by default. Backend `kanban` tools and a running dispatcher do
not enable that pane. This script cannot change renderer-local preferences: it
prints the required switches and writes `.workstation/DESKTOP-SETUP.md` plus
`desktop-readiness.json`, initially `action-required`. After the user enables
them, rerun with `--confirm-desktop-plugins` to record `user-confirmed`; that is
not an automated UI observation or proof of task acceptance. New browser
profiles/origins need their own plugin switches, separate from Electron Desktop.

In Desktop, select the local work-Mac connection, open Bots for the three roles,
then Kanban for the intended board. `hermes profile list`, `hermes kanban boards
list` and `hermes kanban --board <slug> stats` verify backend state. Test a fresh
Triage card and independently check its artifact before declaring readiness.

The optional browser workspace listens only on `127.0.0.1:9120`; `hermes webapp`
opens a private one-use sign-in. Do not publish this listener on the LAN. Enabling
it requires a gateway restart. A live-work refusal means preserve the active
turn/process and wait; do not force a restart. The installed login service and
the currently running gateway are separate states: verify both after a safe
restart. Native Desktop can use the existing gateway while that restart waits.
Hermes background/auxiliary tasks are explicitly pinned to the selected local
route, with empty fallback chains. Media generators that choose unrelated cloud
providers are excluded from this profile's toolsets. Memory/skill write approvals
stay on; board intake and dispatch are enabled with a ten-second tick and bounded
worker concurrency.

The Claude hook checks both the exact endpoint and model tiers. It applies to
the whole work-only device, and only company paths/remotes on the personal Mac.
It is a workflow guard, not an operating-system egress firewall. The owner can
still change settings or invoke other programs directly. Existing project
Alibaba/Qwen and Lumo restrictions remain applicable.

## Local inference and AnyJev on Apple silicon

Use a Metal-enabled `llama-server` bound to loopback and an official Gemma GGUF
with its matching multimodal projector. Pin the model repository revision and
verify both LFS SHA-256 hashes before starting it. Record actual per-slot context
from `/props`: the total `--ctx-size` is divided across `--parallel` slots.
The company workspace configuration must match that per-slot context.

Verified on November 17, 2026: an Apple M5 Max with 64 GiB ran
`ggml-org/gemma-4-26B-A4B-it-GGUF` at revision
`1ca99aae748b4b01f609fa51eb23682ee5f00b85`, Q4_0 weights and Q8_0 projector,
with llama.cpp 1.0.0 (build 12359, `b1b770d90`). A 262,144-token total context and
two slots produced **131,072 tokens per slot**, confirmed through `/props`.
Flash Attention, Metal offload and q8_0 K/V caches were enabled. A direct request,
a Claude Code source edit, and Hermes coordinating AnyJev plus Claude Code all
passed independent checks. This is one machine's acceptance evidence, not a
general performance benchmark.

AnyJev 0.3.0's training-free `Decider` can use the same llama-server through the
tested native token-logprob adapter maintained in the private infrastructure
repository's `servers/pangolin-decide`. The adapter's name is historical: on a
work Mac both processes run locally, with `LLAMA_SERVER_URL` on loopback. There
is no Pangolin connection. Install the actual AnyJev package and NumPy in a
separate virtual environment; verify platform-specific wheel hashes. Keep the
service key in a mode-600 local file. Run the adapter's tests against the real
AnyJev package, then real yes/no, choice and score requests through the API.

LaunchAgents in `gui/$UID` supervise local inference and decisions. Log only
service diagnostics, never API credentials or full company prompts. Stop just
the named jobs when changing them; do not kill unrelated model servers or SSH
tunnels. On macOS an SSH audit session may be unable to read Claude's Keychain
credential even while the desktop is signed in. Test Enterprise Claude from a
GUI LaunchAgent before requesting another token; do not copy subscription OAuth
into Hermes's generic inference loop.

AnyJev provides advisory routing, not permission to archive cards, merge or deploy.
Confidence needs task-specific validation. Preserve ambiguous jobs for review.
Use descriptive score levels: bare labels `1` through `5` confidently chose the
wrong severity in a live outage example. Descriptions from `No user impact` to
`Complete production outage for all users` chose the correct last level. The
numeric result is a zero-based expected level index, not the original 1–5 label.
Inspect Paperclip's existing company and agent IDs before editing them; use its
legacy runner with **command `claude`**, approved model-tier environment variables,
and heartbeats off. A custom launcher command skips the adapter's hello probe;
use the route environment instead. Keep provider and model paired on Hermes
adapters when changing the default provider.

For headless Claude CLI tests, put `--` before a positional prompt when the last
option is variadic (`--tools`, `--allowedTools`, `--disallowedTools`). Otherwise
it may consume the prompt as tool names and fail before inference.

Validation: `python3 -B -m unittest discover -s scripts -p test_work_hermes.py`.
Also verify actual inference, tool use, independent file/test artifacts, service
restart recovery, company Git identity and clean sibling checkouts on each Mac.
