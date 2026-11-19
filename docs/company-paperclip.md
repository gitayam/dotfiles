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
