# Hermes profiles orchestrated by Paperclip

Paperclip can orchestrate the existing Hermes planner, developer and reviewer,
including their models, memory, skills and native children. The previous setup
had enrolled only Claude Code agents. Installed Paperclip 2026.1106.0 includes
both `hermes_local` and `hermes_gateway`; this workstation uses `hermes_local`
with a narrow profile-pinning launcher. Existing Claude agents remain available.

## Choosing a workflow

| Option | Good fit | Workstation evidence and decision |
| --- | --- | --- |
| Direct Hermes / Kanban and native children | Small bounded tasks and independent investigations | Retain the existing writer limits; join actual child artifacts |
| Paperclip parent with fixed-owner children | Tracked planning, implementation, review and approval | Selected graph; native dependencies schedule phases, local receipts gate predecessor termination |
| Same issue reassigned through native execution stages | Compact history and native review policy | Real artifacts passed, but required operator continuations on this installed version; not qualified for unattended use |
| Native `hermes_local` without a launcher | Standard local Hermes execution | Installed adapter adds `--yolo`; launcher removes it and pins approved profile/route |
| Native `hermes_gateway` | Durable API execution, SSE and cancellation | Candidate, not qualified here; needs authenticated per-profile API and callback credential design |
| Claude-backed Paperclip agents | A task needs Claude Code's harness | Retain as a distinct optional execution harness |
| Generic process / HTTP adapter | No native adapter exists | Duplicates transcript, session and callback integration here |
| Bidirectional executing Kanban mirror | Shared task visibility | Avoid duplicate claims and feedback loops; use one execution owner |
| AnyJev / Orca | Advisory routing / bounded read-only investigation | Neither automatically edits or orchestrates these Paperclip children |

The selected coding graph has one final-approval parent and three children:
`plan -> develop -> review`. The parent depends on every child. Analysis uses
`analysis -> review`, then parent approval; it has no developer and does not
adopt recommendations as company policy. Every node has a fixed assignee.
Independent review and final verification require actual artifacts and evidence.
A `changes` disposition blocks the node for explicit coordinator rework. It does
not implement an automatic correction loop or authorize a duplicate request.

The first stock-scheduler coding graph completed all four nodes automatically
with real Hermes/tool runs and nine frozen independent assertions. It also
showed that native Done can precede CLI exit and that different native workspace
IDs can refer to the same cwd. Project serialization alone was insufficient to
prove writer exclusion. The launcher therefore waits for each exact predecessor
run to succeed and for its CLI group, Hermes session and all descendants to end
before spawning the next worker. The revised coding and analysis graphs both passed independently with no manual
continuations, and each successor started after predecessor termination. Analysis
also loaded the installed skill and joined two real overlapping, model-only
server1 children. A live terminal-tool cancellation also passed: no late marker,
exact tool PID absent, CLI group absent, session/descendants terminal, unresolved
fence retained and no dependent execution. Consult the private receipt for
current accepted fingerprints.
Synthetic acceptance is not a model-quality benchmark or a business deployment.

The same-issue experiment exposed both a lost stage wake during lease cleanup
and an acknowledged-cancellation replay guard. A pinned wake patch was tested,
then rolled back: it deferred the wake but did not qualify unattended recovery.
The selected graph uses stock native scheduler source and does not weaken that
guard. Recheck installed scheduler fingerprints and behavior after an upgrade.

## Current release and upgrade review

November 18 audit: Hermes CLI 0.23.2 and Orca 0.2.25 matched stable releases on
both Macs. The work Mac has run Hermes 0.23.3 since November 21 (see the
`hermes` entry below). The native graph and cancellation acceptance was repeated
on that revision on November 22 and its receipt names it; see "Repeating the
acceptance after a runtime update". Paperclip 2026.1117.0 is newer than the accepted 2026.1106.0 runtime.
Its [release notes](https://github.com/paperclipai/paperclip/releases/tag/v2026.1117.0)
change child workspace and rollback contracts. Keep the qualified runtime until
a separate canary and backup/restore test accept the replacement. The isolated
new-version diagnostics passed actual Hermes hello probes but stayed in managed
verification with work queued, so the upgrade was not accepted. Workspace
transfer and production migration remain unqualified; the cause is not yet
isolated between launcher compatibility and the newer lifecycle.

```sh
python3 scripts/audit_work_paperclip.py --check-releases
```

Run the read-only audit on the enrolled work Mac. It checks source, receipt and
profile fingerprints, native agent bindings, timers and run limits; the optional
release lookup reads official GitHub metadata. Matching files do not replace
real model/artifact/cancellation acceptance. An idle company queue is not
permission to restart a service used by another company or gateway session.

### Native profile metadata migrations

Hermes can add `_config_version` and reformat a profile when it runs a native
configuration migration. The exact-byte guard correctly refuses the changed
file even if its model, tool and budget settings stayed identical. Do not
remove that guard or overwrite an intentionally tuned profile to clear it.

For this narrow case, preview the metadata-only requalification on the work
device, then apply it with a new private receipt path:

```sh
uv run --with PyYAML==6.0.3 --no-project python scripts/requalify_work_profile_metadata.py
uv run --with PyYAML==6.0.3 --no-project python scripts/requalify_work_profile_metadata.py \
  --apply --receipt ~/zenithflow/.workstation/reviews/profile-metadata-REVIEW/qualification.json
```

The helper removes only the added integer version marker in memory and uses
the installer’s YAML rendering to reconstruct the prior bytes. Their SHA-256
must match the accepted profile exactly. Changed model/tool/budget settings,
duplicate YAML keys, runtime or receipt drift, busy Paperclip agents and
concurrent manifest changes all refuse the operation. A new receipt links the
preceding qualification; the registry keeps exact current-byte fingerprints.
No profile, worker, model route, service or existing receipt is rewritten.
Existing native graph/cancellation evidence is retained, with the limited
metadata scope recorded explicitly; this does not qualify an engine upgrade.

Afterward run `audit_work_paperclip.py --health --board zenithflow` and check the
fresh scheduled monitor result. An interrupted write leaves a prior-manifest
snapshot and receipt to reconcile rather than silently retrying.

For ongoing read-only checks on the enrolled macOS work device:

```sh
python3 scripts/audit_work_paperclip.py --health --board zenithflow
python3 scripts/setup_work_monitor.py             # inspect the dry run
python3 scripts/setup_work_monitor.py --apply
```

The `io.zenithflow.agent-audit` LaunchAgent runs every five minutes after login.
It writes a private, atomic snapshot to
`~/zenithflow/.workstation/monitor/paperclip-latest.json`, including an explicit
failed snapshot if enrollment or the service becomes unavailable. Check
`observed_at` and `fresh_until`: a sleeping or logged-out computer cannot report
new results. Monitoring does not call models, poll releases, dispatch work,
resume tasks or restart services. Only this new monitor is loaded; the existing
gateway and Paperclip processes remain untouched.

`--health` also compares the running server version with its enrolled source,
checks startup readiness and database backup health. Instance-wide native
recovery counters can include historical or other-company issues; they are
advisory, not proof that an active company worker is stuck. Read the issue,
run and dependency records before considering recovery. Likewise, a successful
audit does not accept artifacts or prove that blocked Kanban cards can proceed.
Use native `hermes kanban --board BOARD stats` for the intended board, followed
by `show TASK --json` and `runs TASK --json` when investigating an individual card.

Every report also carries a `hermes` entry: the installed revision, when the
checkout last moved to it, and, when Hermes wrote an update receipt for that
exact revision, the version, the version it replaced and what started the
update. It is read from the checkout's `HEAD` and reflog and from
`logs/update_receipts`, with no command run; an install that is not a Git
checkout reports `unverified`. Read the installed version here before stating
one or deciding about an upgrade: a guide that names a version is a dated claim.
The Hermes Desktop app's update replaces the runtime and restarts the gateway
without any of these scripts running, so this entry is where such an update
first shows.

Installed is not accepted. A qualification receipt may name the runtime it
accepted as `"hermes_runtime": {"revision": "<full revision>"}`. The audit then
adds the check `hermes_runtime_accepted`, which fails as soon as the installed
revision differs, so an update from the Desktop app shows up under its own name
within one monitor cycle. A receipt that names no runtime adds no check, and
`accepted_revision` stays `null`: the audit cannot say which runtime was
accepted. Write the field only in a receipt whose acceptance actually ran on
that revision; the metadata-only requalification above does not add it.

Each agent in the report also carries `run_turn_limit`, the adapter's
`maxTurnsPerRun`, beside the profile's `max_turns`. Setup keeps an adapter limit
that is lower than the profile's, because it cannot tell a limit an operator
chose from the default it wrote before the profile was raised. So raising a
profile does not by itself raise what a Paperclip run of that role may take:
after the November 20 raise the developer and reviewer adapters still said 16
where the profiles said 40 and 24. The difference is reported, not failed.

### Repeating the acceptance after a runtime update

A narrower requalification (profile-only, metadata-only) carries the original
receipts forward without running anything. Each is honest about that, but a
chain of them can go on asserting a path nobody has executed: before November
22 the Paperclip team had not run once since the day it was accepted, while
the runtime, two role profiles and the installed skill all changed. After a
runtime update, run the battery again; do not extend the chain.

Use a new private review folder, new request keys and the helpers unchanged, so
a difference in the result is a difference in the system:

1. Confirm the contract and profile fingerprints match the registry, the three
   agents are idle and no run is live. Back up the registry.
2. A coding graph staged and activated as a pilot, then its acceptance.
3. An analysis graph, its acceptance, and the check of its two leaves.
4. The cancellation fixture: cancel while the terminal tool is alive, wait past
   the tool's deadline, then accept.
5. A coding graph through normal intake (`--apply --start`), its acceptance,
   then the same request again: same native IDs, same worktree, no new run.
6. Check the frozen oracles still fail their bad controls. Write the receipt
   with `hermes_runtime.revision` read from the checkout, and assert that
   revision is the same as before step 2. Run the audit before and after.

Run nothing else of your own on the machine meanwhile. On November 22 the first
coding graph ran while a 4,000-test suite used eight workers on the same Mac,
and it was the only graph the unchanged helper rejected; the two causes can no
longer be told apart.

What that run showed, on Hermes 0.23.3 with other board work on the same model
server: 17 native runs, 15 succeeded, one was cancelled on purpose and one was
refused before launch. The analysis graph, its leaves, the cancellation, the
normal-intake coding graph and the repeat all passed unchanged at the first
attempt. The pilot coding graph passed on its second run. Its first run
finished without an operator and its code passed the frozen oracle, but one
phase had two native runs and its evidence files were under `.agent-work/`,
the phase contract's default, not at the names the request gave.

The two native runs are the predecessor wait doing its job. The launcher gives
a predecessor 20 seconds to exit after its native Done. On November 18 that
took 3 to 12 seconds over 11 runs. On November 22 it took 5 to 15 seconds in
14 of 15 runs, a model call being 1.4 times slower, and 26 seconds once, when
a planner ran two more commands after `finish`. The next phase's first launch
was then refused with "The prior phase is still closing; no second Hermes
writer was started", the native run failed with exit 2 and no launch record,
and Paperclip started it again 35 seconds later without anyone asking. A phase
with a failed first run of that shape and one succeeded run has had one
writer. The margin is thin under load: the wait is part of the pinned launcher,
so widening it is a contract change with its own acceptance.

To stop only this monitor, use
`launchctl bootout gui/$(id -u)/io.zenithflow.agent-audit`. Keep its latest
snapshot as historical evidence; it will become stale at `fresh_until`.

The monitor also uses native Hermes JSON output to summarize the existing
`zenithflow` board. Only status counts and the oldest ready card's creation age
are retained, with no task bodies, titles or credentials. Creation age is not
time in Ready. Missing boards fail the check rather than being created. Held
cards and dependency-waiting todo cards do not become failures or automatic
retries merely because no worker is running.

The personal Mac's company workspace is a client of the work Mac. Refresh its
isolated profile with `setup_work_hermes.py --from-config ...`; preserve personal
defaults and credentials. A November 18 refresh restored the friendly server
aliases and bounded child routing, then passed a real local-model parent with
two overlapping server1 children through the relay. The work Mac remains the
company execution owner; do not create another executing board mirror here.

## Install and intake

```sh
uv run --with pyyaml --no-project python scripts/setup_work_paperclip.py \
  --from-config ~/zenithflow/.workstation/config.json
# Inspect the dry run; repeat with --apply while the enrolled roles are idle.
```

The work Mac must already have its company-only configuration, three Hermes
profiles and private Paperclip company metadata. Setup enrolls those profiles,
installs callbacks, intake and skills, and leaves timer heartbeats off. Assignment
and native dependency events drive work. New configurations remain unqualified:
only named synthetic pilot issues may run. Runtime, intake, native scheduler and
profile fingerprints invalidate acceptance when changed. Existing Claude agents,
boards, profiles and services are preserved; no gateway restart is needed.

Create a request JSON with exactly these six string fields:

```json
{
  "request_key": "stable-key-for-this-request",
  "kind": "coding",
  "title": "A bounded engineering task",
  "description": "Owned paths, evidence, acceptance commands, prohibited actions, decisions and stop condition.",
  "project_id": "company-project-uuid",
  "project_workspace_id": "configured-source-workspace-uuid"
}
```

Use `kind: analysis` for a decision brief with evidence, uncertainty, business and
system tradeoffs, non-code options and measurable next steps. Company IDs come
from the company-scoped `zf-paperclip` client and stay in private local files.

```sh
zf-orchestrate --request REQUEST.json                 # preview only
zf-orchestrate --request REQUEST.json --apply         # create in backlog
zf-orchestrate --request REQUEST.json --apply --start # native activation
```

Apply requires accepted qualification; `--stage-pilot` only stages an unqualified
fixture in backlog and cannot start models. To enroll a named existing project, repeat setup with `--project PROJECT_UUID`
(and `--apply` after review). This requires no live company runs, preserves other
project policy fields and records its primary source IDs in the private
`paperclip-intake-projects.json` catalog. The project must explicitly grant
all enrolled roles access if private and have
`executionWorkspacePolicy.sharedWorkspaceConcurrency: serialize`. Intake does
not grant access or silently alter project policy. Select a local Git source
inside `~/zenithflow`. Intake records its HEAD, creates a detached worktree per
request and preserves dirty source files. Dirty changes are not copied. A
worktree separates edits, not macOS tools or credentials.

All issues are created unassigned in backlog before activation. Native parent,
dependency and role bindings are recorded privately. Repeating the same key and
identical request returns the same graph. Native titles include a short request
hash because this version may deduplicate identical titles across different
client idempotency keys. A different body with the same key is
refused. A journal records intent before writes. Unknown outcomes are reconciled
using positive native receipts, never blind POST retries. Preserve partial
worktrees and unknown journals for investigation. Do not reset them to recover. A lost parent-dependency update can require
operator reconciliation before staging completes; it does not authorize a new
POST. To start from the UI, ask the coordinator to create this request graph;
assigning an arbitrary unregistered issue to a Hermes agent is refused.

No global adapter cwd is set: it would override the issue's leased workspace.
One run per agent is not a machine-wide capacity pool and does not raise Hermes
Kanban limits. Do not mirror an executing request to Kanban, resubmit from its
own worker or invoke an extra heartbeat after an event already wakes it. Owner
holds and existing boards do not migrate automatically.

## Runtime and recovery

The launcher removes the native adapter's `--yolo`, rejects route/tool/flag
bypasses and pins the actual enrolled profile. Main, fallback, auxiliary and
child routes must use approved full-context local or server1 inference. Server2
remains a separately qualified bounded CLI route. Profile changes require a
refresh and new acceptance. No personal cloud fallback is introduced.

Inside a worker, use the ephemeral `paperclip-run` helper for `start`, `show`,
then one evidence-backed `finish FILE` or review/approval `changes FILE`.
Evidence must be inside the leased workspace. Graph workers cannot hand off or
self-reassign. Native Paperclip owns issues, dependencies, runs and authorization.
The supervisor checks native company/agent/issue/run/workspace binding and keeps
its run credential in memory behind a private Unix socket. The model receives
an opaque context path, never the key. Same-user processes are not OS-isolated.

Fresh runs use fresh Hermes sessions; profile memory persists and issue history
carries phase evidence. Resume is disabled until callback credential rotation is
qualified. The exact CLI stderr session ID binds termination checks. One tested
local-model row omitted cwd and system_prompt, so a latest-session lookup is not
sufficient. Missing or conflicting session evidence leaves the fence unresolved.

Callbacks journal intent before mutation and reconcile a lost response against
a unique native comment marker. Nonzero or interrupted workers leave an issue
fence. Do not clear it because a PID disappeared: verify native run outcome,
CLI process group and exact Hermes session plus descendants. Cancelling a CLI
alone does not prove gateway tools stopped. User cancellation is never treated
as an automatic handoff. For this legacy CLI runner, use the native board
cancel-run route without `cancellationRequestId`: the installed correlated Stop
option requires a native-runner session and returns 409 for this runner. Shipping, external communication and policy adoption
need task-specific authority beyond a successful worker result.

The installed generic adapter test guesses cloud keys and default Hermes home.
Setup instead selects its existing `managedAiRouting` readiness test: a literal,
bounded, tool-free hello using the enrolled profile and built-in empty
`bot_room` toolset. This is a real call, not an AI-account binding or fabricated
result. `--toolsets none` is invalid in this Hermes runtime. Recheck these
version-specific details after upgrades.

Sources: [native Hermes adapter](https://docs.paperclip.ing/reference/adapters/hermes/),
[gateway adapter](https://docs.paperclip.ing/reference/adapters/hermes-gateway/),
[execution policy](https://docs.paperclip.ing/guides/power/execution-policy/),
[delegation](https://docs.paperclip.ing/guides/org/delegation/).
