# Company Hermes workspace

For durable per-role/auxiliary assignments and reproducible model/effort checks,
see [company model policy](company-model-policy.md).
For roaming SSH, separate tailnets and a restricted bastion design, see
[company connectivity](company-connectivity.md).

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
ordinary `claude-z` / `zq` registry to server1/server2, including from stale shells.
Refresh directly with `--from-config ~/zenithflow/.workstation/config.json --apply`.

| Launcher | Purpose |
| --- | --- |
| `hermes-zenithflow` | Company Hermes coordinator; local Gemma by default |
| `zf-local` | Real Claude Code using the work Mac's local Gemma |
| `zf-server1`, `zf-server2` | Real Claude Code on organization GLM / gpt-oss servers |
| `zf-claude` | Real Claude Code using the company Enterprise login |
| `zf-zq local\|1\|2 "prompt"` | Direct model request |
| `zf-decide` | AnyJev decision JSON on stdin; reads its credential file |
| `zf-paperclip` | Company-scoped Paperclip issue, agent and project commands |
| `zf-status` | Check model inventory at the configured endpoints |
| `zf-orca dispatch --agent claude ...` | Read-only Orca lane; `ZF_MODEL` selects local/1/2 |

Hermes Kanban, Paperclip issues and Orca lanes are separate records. Hermes calls
Paperclip/Orca through the terminal. Paperclip can orchestrate the actual Hermes
profiles through its native adapter; its Claude-backed agents are a separate
harness choice. See [Hermes under Paperclip](company-paperclip.md) for the
comparison, accepted qualification, release audit and request-graph review workflow.
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
endpoint's served model. server2 has a 49,152-token window: useful for bounded tasks,
below Hermes's 64K main-agent floor. Do not inflate its advertised context.

For CTO-level issue and backlog research, use the installed `issue-strategy`
skill: `/issue-strategy Review OWNER/REPO and recommend decisions`. It evaluates
problems, evidence, business/system tradeoffs, non-code alternatives and proposed
next steps. It does not automatically create cards, mutate issues or implement
fixes. See the [workflow, collector and installation guide](issue-strategy.md).

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
enable **Desktop: Kanban** and **Desktop: Bots**. Hermes 0.23.2 and 0.23.3 ship
Kanban's Desktop pane off by default. Backend `kanban` tools and a running dispatcher do
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
Hermes uses an approved fallback chain between local Gemma and organization server1.
The selected primary is omitted from its own chain; routes below the 64K main
context floor are excluded. server2 remains available for bounded CLI work. Text
auxiliary and explicitly pinned delegated calls have their own approved chains;
vision stays on the verified local multimodal route. Media tools using other cloud
providers are excluded from this profile's toolsets. Memory/skill write approvals
stay on; board intake and dispatch are enabled with a ten-second tick and bounded
worker concurrency.

### Remote fallback setup and task ownership

`hermes fallback add` is interactive. The installed CLI accepts structured JSON
or YAML through `config set`, so a company-only device can be configured over SSH:

```sh
hermes config set fallback_providers '[{"provider":"server1","model":"glm-5.3-flash"}]'
hermes fallback check --live --json
```

On a personal workstation, select the company profile explicitly. Named providers
resolve their endpoint and credentials from that profile; do not put tokens in
command arguments. The managed installer refreshes primary, text auxiliary and
delegation chains together and removes the legacy fallback key. It sets one
Hermes-level API retry and one recovery cycle, with a 120-second provider request
timeout. SDK retries still apply; these are not a hard whole-task deadline.
Verify an isolated synthetic primary failure, not only readiness or a model list.
New sessions/workers use the new configuration; preserve existing live runs rather
than forcing a gateway restart to change their route.

Native fallback handles provider failures, not Kanban `blocked` states, weak
recommendations or acceptance failures. The installed `smart_model_routing` key
has no runtime routing implementation; enabling it is not evidence of switching.
Use bounded, verified escalation to server1 or real Enterprise Claude Code for work
that needs it. AnyJev advice does not replace that verification.

On the company-only device, default board ownership is `zf-developer`, with `zf-planner` coordinating
decomposition. Select actual profile names from the roster. A ready card assigned
to a nonexistent `developer` or `frontend-developer` profile cannot dispatch.
An operator hold requires an ownership handoff: reconcile live runs, worktrees,
artifacts and contracts before releasing it. Write the worker contract before
authorized execution; approvals being off alone does not justify an indefinite
hold, and a written contract is not an execution sandbox.

Unattended specialist profiles omit `code_execution`: native single-query policy
requires separate approval for arbitrary Python cells, so advertising the tool
caused a denied call and wasted generation. Ordinary file/terminal tools remain
subject to their existing guards. The installer does not set
`approvals.single_query_mode: approve`; interactive host sessions retain the tool.
Specialist profiles default to a 900-second conversation-turn budget and 16 tool
iterations, retaining explicit existing values (a planner raised to 24 by hand
stays at 24; a fresh install gives every role 16). The private input
`role_max_turns` (for example `{"zf-developer": 40, "zf-reviewer": 24}`, whole
numbers from 8 to 100) sets a role's limit whatever its profile holds, and is the
way to raise it: on one board seven cards that edited files died at 16 steps in
one night with their work finished or nearly so. It rewrites that role's
`config.yaml`, which the Paperclip qualification pins, so plan the acceptance
run with it. A task's native `--max-runtime`
is the separate whole-worker cap; set it and `--max-retries 1` for one attempt.
Large assignments need bounded milestones or an explicit profile budget change.

The Claude hook checks both the exact endpoint and model tiers. It applies to
the whole work-only device, and only company paths/remotes on the personal Mac.
It is a workflow guard, not an operating-system egress firewall. The owner can
still change settings or invoke other programs directly. Existing project
Alibaba/Qwen and Lumo restrictions remain applicable.

### Cards that finish: what the board's own records show

`scripts/report_work_board.py` summarises a board read-only: runs by profile and
model, by who created the card, attempts per card, steps used against each
profile's limit, exhausted budgets, block loops and waiting time. It prints
counts only, never a title or a body. Every figure covers the board's whole
history unless `--since-hours N` is given: after a limit, a model or a prompt
changes, give the hours since the change, or one row mixes two systems. The
window keeps runs that started inside it and the cards created or run inside
it. On one company board after three days
(334 cards, 348 runs) it showed the following. This is one board's history, not
a model benchmark.

- **Who wrote the card predicted the outcome more than the role or the model.**
  Cards created through the CLI from a written contract completed 259 of 268
  worker runs. Cards typed free-form into the default profile completed 9 of 27.
  Cards the automatic decomposer created completed 7 of 14 and took 5 of the 9
  exhausted step budgets. Look at how a card is written before changing a model
  or a limit.
- **Count attempts, not rows.** A `blocked` run with no worker is a hold someone
  placed (17 of them here), not a failed run. The model a run used is in the
  worker's session. A completed run names its session in its own record; a run
  that ended any other way names none there, but the board's admission event
  for that run does, and the report reads it. Only a run with neither is
  assumed from the card or the profile. A first count that ignored both points
  reported one route at 45% when 5 of its 6 real runs had completed. A later
  one that assumed where the admission record existed (65 of 65 failed runs
  had one) showed a role at 16 of 16 on its local model; the sessions put it
  at 16 of 37, because 22 of that role's 37 failed runs had been charged to
  the model the role runs today.
- **Steps.** Completed runs used a median of 7 tool-calling turns and a 90th
  percentile of 11 or 12, against limits of 16 (24 for a planner whose explicit
  value was kept). Write a contract for about 7 to 11 steps. A card that needs
  more than the limit cannot finish however often it is retried.
- **Waiting.** With two workers in total and one per profile, a card with no
  parent waited a median of 6 minutes and a 90th percentile of 23; a run took a
  median of 2.5 minutes. Spread a wave across the profiles. After the limits
  were raised to 16 and 8, a ready card was claimed after a median of 6 seconds
  (260 runs over two days, up to 12 workers at once).
- **Width.** The report prints how many model turns a minute the board made at
  each number of workers running, from the times the sessions recorded. Over
  the two days after the limits were raised (319 runs, all but 13 on one
  served model) a worker running alone made 2.9 turns a minute and a worker among eleven or
  more made 0.6: a card took about five times as long in a wave that wide. The
  board as a whole made 2.9 turns a minute at width one, 5.9 at seven or
  eight, 7.9 at nine or ten and 7.7 at eleven or more, the last over only 22
  minutes. So the binding number is now what the model server answers at once,
  not a board limit: width bought about two and a half times the work at five
  times the time per card. This is what happened, not a test. The middle bands moved
  between windows (5 or 6 workers made 2.5 turns a minute over fifteen hours
  and 6.3 over the last six), which the board cannot explain: the bands differ
  in hour and in what the cards asked, and the server has other users. Look at
  two windows before changing a limit, and size a card's time limit for the
  width it will run in.
- **Chains.** A card created with `--parent <id>` stays in `todo` until every
  parent is done and then starts by itself: a four-card chain started each next
  card within a second of its parent finishing.

A card that finishes is created like this, with the model set at creation
(`set-model` on a running card ends its worker):

```bash
hermes kanban --board <board> create "<title>" --body-file contract.md \
  --assignee <profile> --workspace dir:<folder> --max-runtime 900 --max-retries 1 \
  --model <model> --provider <provider> --idempotency-key <key> \
  --created-by <who> [--parent <card id> ...]
```

Its contract names one input file that holds everything the worker needs, the
one file it writes, the commands it may run, what is prohibited, and a stop
condition with the first line of the summary. Tell the worker to write "not in
the input" where the input is silent: a worker told to use only what a filter
prints reports everything the filter dropped as absent. Fold several reads into
one command. Tell it to complete and say what stopped it rather than block: a
second block on the same card is treated as a loop and, with automatic
decomposition on, hands the card to the decomposer, which writes premises it
cannot check. Use two retries only for a card that is safe to run twice.

A card's summary is the worker's claim. `scripts/audit_work_cards.py` lists the
tool calls a worker made, from the profile's session store, and flags a command
outside the patterns the contract allowed, a prohibited command, a command run
inside another (`$( )` or backticks) and a file written elsewhere:

```bash
python3 scripts/audit_work_cards.py --board <board> --cards-file cards.txt \
  --allow-read-under <input folder> --allow '^cat > <output folder>/[A-Z][0-9]\.md' \
  --write-suffix .md
```

It sets here-documents and quoted text aside before splitting a command. Without
that, a worker that writes its notes with `cat > file <<'EOF'` has every sentence
containing a semicolon reported as a command. A plain name set in the call
(`F=<path>`, then `$F`) is put in place before a command is checked: on one card,
67 reads through such a name and the 6 lines that set the names had been
reported, 73 flags and none a real departure. A read counts as under the input
folder only when its path stays there (`<folder>/../x` does not). Over 39 real
cards the audit gave 75 flags before these changes, 74 of them false, and 4
after, each true.

A command run inside another is flagged whatever it is, because quoting hides it
from the other checks. Two were on real cards: an `echo "... $(wc -l < file)"`,
harmless, and a `grep -c "has a `precision`" file`, where backticks meant as
markdown sat inside double quotes, so the shell ran the word as a command and
the search looked for something else. Tell a worker to quote a search pattern
that holds backticks with single quotes, and to write notes through a
here-document whose delimiter is quoted (`<<'EOF'`): with a bare delimiter the
shell expands the body, and markdown is full of backticks.

Every attempt of a card is audited, not only the one that completed. A
completed run names its session in its own record; a run that timed out, gave
up or crashed names none there, but the board's admission event for that run
does, and the audit reads it. Before it did, 72 ended runs on one board were
never opened and 34 cards were reported as having no session when each had one.
Those runs held a `git reset --hard`, a `git checkout` of a commit, two `rm` and
a file patched twice in a repository's main checkout by a card whose workspace
was a scratch folder. A flag from an attempt other than the newest names its
run (`run 12 (timed_out): ...`). `git merge-base` and `git merge-tree` only read
and are not counted as prohibited: four of the first eight "prohibited" git
commands found in those runs were `merge-base --is-ancestor`.

A card with no session in either record, or whose session the profile's store
does not hold, is reported as unaudited, never as clean. A clean audit says the
worker stayed inside its contract; it does not accept what the worker wrote.

`scripts/report_work_blocks.py` says why each open card is open, read-only and
with ids and counts only: it waits for a person (and whether a person has
commented since the block, because a comment does not release a card), it ran out
of steps, it failed another way, or it waits behind another card, whose root is
named. It also splits waiting time by what else was running: a card of the same
role, the total limit, or nothing. On one board that read 68% and 27% before the
limits were raised.

`scripts/report_work_landing.py` says where the work of finished cards stands,
because done says a run ended and nothing about where the commit is. For every
done or archived card whose workspace is a git checkout it gives the checkout one
class: on the default branch, uncommitted, committed on no remote branch, pushed
but not merged, gone, or a plain folder. It lists the checkouts whose work is not
on a default branch with their card ids, branch, age and the age of the last
fetch, and never prints a title or a diff:

```bash
python3 scripts/report_work_landing.py --board <board> --older-than-hours 24
```

An ancestry test alone would call every squash merge unlanded, so commits also
count as landed when each has an equivalent patch on the default branch, when the
default branch holds every file they touched as the tip has it, or when one of
its commits carries the same change as all of them together. It runs git read
commands only, with optional locks off: reading the status of a checkout a worker
is using does not rewrite its index. It never fetches, so "not on the default
branch" is as of the last fetch, and a commit cherry-picked onto another pushed
branch reads as local until that branch merges. On one board it found five
accepted changes, each committed on its own branch four days earlier, that were
on no remote: no card was open, no decision listed them, and one of the five no
longer merged cleanly onto the branch it was written for. Give every checkout it
lists an end: a request opened or merged, a decision written where the owner
reads decisions, or the work rejected and the checkout removed.

What a refresh keeps: explicit turn budgets and delegation limits survive
`setup_work_desktop.py`. The board limits, `kanban.auto_decompose`, each role's
model and the worker toolsets are written again on every refresh, so a hand edit
of those is reverted; change the private configuration instead. The installer
sets `auto_decompose` on unless the private configuration has
`"kanban_auto_decompose": false` (true or false only; anything else is refused).
That input survives a refresh and changes the root configuration only, which is
the one the dispatcher reads on every tick, so no restart is needed. The three
role profiles deliberately keep `auto_decompose` on whatever it says: the
Paperclip qualification pins a hash of each role's `config.yaml`, and a role
configuration that never changes leaves that qualification untouched. Only that file is pinned for
a role: its prompt (`SOUL.md`) and its skills are not hashed, so the role prompt
and skill text can change on any refresh. The role prompt names the personal
repositories and the repository map with each checkout's `DIRECTION.md`,
`AGENTS.md` and `CLAUDE.md`, and tells the worker to settle a question from those
and from the card before blocking.

The board limits are private inputs too: `"kanban_max_in_progress"` and
`"kanban_max_in_progress_per_profile"`, each a whole number from 1 to 32
(anything else, including `true` or `null`, is refused). Absent, the installer
writes 2 and 1 as before, so a refresh without the inputs reproduces the older
configuration byte for byte. Unlike `auto_decompose`, the dispatcher reads these
two once when the gateway starts: a change needs a gateway restart, taken with
no card running, and that restart interrupts whatever is in flight. Size them to
what the machine and the model routes can carry at once, not to the number of
cards waiting; a queue that waits is normal, a queue that fails is not. The
report's width table shows what the routes carried: once turns a minute stop
rising with width, a higher limit adds waiting, and the next step is another
model route, not a bigger number.

Worktrees per card: `hermes project create <name> <path> --board <board>`
registers a project, and a card created with `--project <name> --workspace
worktree` then gets its own `<repo>/.worktrees/<task id>` and a deterministic
branch, whatever profile claims it — the repo path is stored absolute, so the
dispatching profile needs no project state of its own. Two cards on one
repository are safe in parallel exactly because of this; register a project
before fanning work out on it. `scripts/map_work_repositories.py` writes a
private map of the checkouts a worker can be sent to (`--root label=path`,
`--output` outside every checkout, dry run by default): each checkout's path,
origin cleaned to `host/owner/name`, which of `DIRECTION.md`, `AGENTS.md`,
`CLAUDE.md` and `README.md` it has, and the first heading of its direction file.
It never prints a remote's scheme, user, password or query, never lists a folder
named `secrets`, and refuses to write the map inside any checkout — the map
holds this machine's paths, so it stays in the private state folder.

Intake with decomposition off: a card in Triage then stays there until
`hermes kanban --board <board> specify <id>` or `specify --all` runs.
`scripts/setup_work_intake.py --board <board>` (dry run; `--apply` to install)
adds a LaunchAgent that runs `specify --all --author intake` every 60 seconds.
Each Triage card becomes one tightened card (goal, approach, acceptance
criteria, out of scope) in `todo`, with no child cards, at the cost of one
auxiliary model call (`triage_specifier`) per Triage card. It does not dispatch,
retry, decompose or restart anything. It refuses to install unless the root
configuration says `auto_decompose: false`: with decomposition on, the
dispatcher already handles Triage and a second intake would race it. Its output
goes to `intake/board-intake.log` under the state folder, so a failed sweep can
be read. `--remove --apply` unloads the job and deletes only its own plist; do
that before turning decomposition back on or changing its board, since a loaded
job is never rewritten.

The same sweep also parks raw dashboard cards (`scripts/guard_raw_cards.py`,
installed to the state folder's `bin/`). A request typed into the dashboard
becomes a card with no work contract and dispatches the moment it exists, and a
request that bundles research, a multi-file build and verification cannot finish
within any step budget: it dies at the ceiling twice, trips the circuit breaker
and waits for a human anyway. The guard catches such a card within the sweep
interval — a dashboard card younger than ten minutes, still queued or running,
whose body carries no work contract — reclaims and blocks it with a comment that
names the sizing rule and the way out. A card that finishes inside the interval
escapes; a card whose body carries the contract marker is left alone; unblocking
runs it as-is. Size the work where it is created when you can; the guard is the
net under the one entry point no contract writer sees.

Sleep-aware run timers: the dispatcher measures a worker's runtime and a
claim's age from wall-clock epochs, so a Mac that sleeps bills every running
worker — on wake it kills workers as timed out and reclaims claims that never
went stale, though the work was frozen, not slow.
the main installer records the choice (`setup_work_hermes.py --sleep-compensate`,
carried on refreshes, validated like the other private inputs and printed as a
follow-up command, since the board is chosen per install) and then
`scripts/setup_work_sleep_compensate.py --board <board>` (dry run; `--apply`)
adds a LaunchAgent that runs `work_sleep_compensate.py --apply` every 60
seconds: it records the machine's slept seconds since boot
(`mach_continuous_time - mach_absolute_time`, both declared 64-bit — ctypes'
32-bit default truncates them into negative nonsense) and, on the tick after a
sleep, pushes running workers' active starts forward by exactly the sleep, so
elapsed time counts only awake time. The state ledger beside the board database advances every tick,
with or without `--apply`, so a dry run followed by an apply never shifts the
same sleep twice; the shift is capped at the wall time between ticks plus one
interval; a reboot resets the ledger; a run started inside the sleep window is
left alone, at most one interval under-compensated. `--remove --apply` unloads
the job and deletes only its own plist.

What the shift does not do, measured on one device on 2026-11-23: of 66 ticks
that saw a sleep, 3 still found a running card to shift. A worker does not
survive a sleep of more than a few minutes whatever its timers say: its turn
lease (300 seconds, wall clock) lapses and it is interrupted on wake with
"session turn lease lost", and the dispatcher's own pass runs within seconds of
the wake, before the minute's tick, so a card with a short limit is timed out
with the sleep billed. Closing the lid STOPS the cards in flight; each is left
blocked after its one attempt. Install with `--recover` to have them released
again without a person: on each tick the tool looks for blocked cards whose
last record is a `gave_up` from outside (a timer, a claim taken back, an
interrupted or lost worker; never one that ran out of steps, never one a person
or its worker blocked afterwards), reads `pmset -g log` only when there is such
a card, and releases those stopped within three minutes of a wake that followed
at least two minutes asleep. It releases through `hermes kanban unblock`, only
while the lid is open and the Mac has been awake for ninety seconds (a dark
wake lasts under a minute, and a card released into one is stopped again), and
at most three times a card. The work in flight when the lid closed is lost and
starts again; a card's worktree keeps what was written. Keeping the Mac awake
with the lid closed on battery is a system setting and its owner's decision.

Observed on one device after turning decomposition off and installing the
intake: the refresh changed one key of the root configuration and left the three
role configurations byte for byte as they were, so the setup audit passed all of
its checks before and after. A one-line request typed into Triage was specified
61 seconds later into one card with a goal, an approach, acceptance criteria and
an out-of-scope list, started eight seconds after that, and finished in eleven
seconds with the exact file asked for. No child card was created. Before the
change, the same kind of request had been split into four cards within 23
seconds; two of them ran out of steps twice and blocked the fourth.

Two limits of the intake as built. The specified card keeps the assignee the
request was given and has no review step: a request that needs one should be
written as two cards with a parent link. And the log gains one line a minute
while Triage is empty ("No triage tasks.") and is not rotated: about 1,400 short
lines a day.

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
explicit CLI engine (`adapterConfig.engine: cli`) with **command `claude`**,
approved model-tier environment variables and heartbeats off. The installed
adapter can default an unset engine to ACP. A custom launcher skips its hello probe;
use the route environment instead. Keep provider and model paired on Hermes
adapters when changing the default provider.

Read-only Paperclip acceptance does not qualify editing. An earlier editing
canary returned exit 0 with denied tools and no artifact; its cancelled history
remains intact. A new, distinct synthetic fixture later passed Enterprise Claude
editing with an exact-file task-scoped `Read`/`Edit` grant: four independent
assertions passed, frozen tests were unchanged, the operator closed the issue,
and the temporary override was removed. This qualifies that scoped path, not
arbitrary company-repository writes. No blanket permission mode was enabled.

Use authorized owned-path `Edit`/`Read` selectors with absolute `//` paths;
`Write(path)` does not match Claude file permissions. Paperclip supports
`assigneeAdapterOverrides.adapterConfig.extraArgs` for a per-task CLI grant.
Keep its required issue-disposition step executable: forbidding all API access
while expecting the worker to record a disposition caused automatic repair
turns in the fixture. If the operator owns final acceptance, reconcile every
run and queued continuation before closing the issue and removing its grant.
Respect execution reconciliation and real denies; do not reset or duplicate
blocked work. See [Claude permissions](https://code.claude.com/docs/en/permissions).

For headless Claude CLI tests, put `--` before a positional prompt when the last
option is variadic (`--tools`, `--allowedTools`, `--disallowedTools`). Otherwise
it may consume the prompt as tool names and fail before inference.

Validation: `tests/run.sh` runs every suite; the work suites are
`python3 -B -m unittest discover -s scripts -p 'test_work_*.py'`.
Also verify actual inference, tool use, independent file/test artifacts, service
restart recovery, company Git identity and clean sibling checkouts on each Mac.
