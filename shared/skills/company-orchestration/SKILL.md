---
name: company-orchestration
description: Choose and run company workstation work through native Hermes, a Paperclip Hermes team, approved Claude Code or read-only Orca, with one execution owner and independent acceptance.
---

Read `~/zenithflow/WORKSTATION.md` and
`~/zenithflow/.workstation/PAPERCLIP-HERMES.md` for actual qualified routes and
current coverage. Work under `~/zenithflow`; private IDs and credentials stay
in `.workstation`, outside repositories. Use approved company/local inference.

For maintenance, run dotfiles `scripts/audit_work_paperclip.py --check-releases`
on the enrolled work Mac. It is read-only. A newer stable release still needs
workspace, callback and data-migration acceptance; preserve the qualified
runtime until then. A passing hello with agents still verifying and tasks queued
is not acceptance. Its company queue check is not a machine-wide restart gate.

For ongoing service/board checks, use `scripts/audit_work_paperclip.py --health --board zenithflow`.
The enrolled work Mac can install `scripts/setup_work_monitor.py --apply` after
reviewing its dry run. This read-only LaunchAgent checks every five minutes and
writes `.workstation/monitor/paperclip-latest.json`; check its timestamp and
`fresh_until` before trusting it. It never calls models, dispatches or recovers
tasks, changes inference routes or restarts the gateway/Paperclip. Instance-wide
recovery counters can describe historical or other-company issues; inspect exact
task/run evidence rather than automatically retrying them. Enrollment/service
failures produce a failed receipt instead of leaving an old success as current.
The monitor retains only board counts, not task bodies. A card's creation age
does not establish how long it has been ready. Before a review, locate its exact
evidence and existing acceptance file; stop with the missing input/owner decision
if those are absent. Preserve an operator's no-retry hold and check downstream
dependencies before completing a diagnostic card: completion can release a
writer that overwrites accepted evidence. More turns or a different model do
not resolve missing owner decisions.

Choose the lightest useful workflow:

- Direct Hermes tools for a small bounded task; native children for independent
  leaf investigations or reviews. Give children concrete ownership and join
  their artifacts. Profiles on a board are not proof that subagents ran.
- Paperclip for tracked work with assignment, durable history and enforced
  review. Its native Hermes agents reuse existing profiles, skills and memory;
  Claude-backed agents remain an optional harness choice.
- Orca for an independent bounded read-only lane. Its current company adapter
  does not edit or provide a Paperclip handoff. Check actual results.
- AnyJev for advisory decisions; its score grants no execution/publication power.

For Paperclip intake, write JSON with exactly `request_key`, `kind` (`coding`
or `analysis`), `title`, `description`, `project_id`, `project_workspace_id`.
Include owned paths, the evidence needed, acceptance commands, prohibited
actions, owner decisions and a stop condition. IDs come from the private `.workstation/paperclip-intake-projects.json` catalog
or company-scoped `zf-paperclip` client. Preview with `~/.local/bin/zf-orchestrate --request FILE`;
use `--apply --start` only within the requested work and accepted qualification.
The helper requires explicit private-project membership and project shared-workspace serialization, records source HEAD and creates an isolated Git worktree per request. Dirty source changes are preserved and not copied.
No second heartbeat is needed. Preserve an unresolved creation journal instead
of repeating the write. Reuse the same request key only for the same work.

Coding creates fixed-owner plan, development and review children, with a final
approval parent depending on every child. Analysis creates analysis and review
children, then final approval; no developer or policy adoption is implied.
Native dependency events schedule phases. A local gate verifies the exact prior
run succeeded and its Hermes session, descendants and CLI group terminated
before the next worker starts. Same-issue handoffs are not the qualified default.
A reviewer must check actual evidence. Use changes for a material defect; that
blocks for bounded coordinator rework rather than automatically resubmitting.

Inside a Paperclip-owned run, use the ephemeral `paperclip-run` helper for
`start`, `show`, and one evidence-backed `finish` or review/approval `changes`.
Graph assignments are fixed: do not hand off or self-reassign.
Never use intake to resubmit that issue, mirror it into an executing Kanban card,
read token files or replace callbacks with raw credential-bearing commands.
Native Paperclip owns leases, fixed assignments and dependency transitions. Do not remove review policy
or reset execution fences to force progress. Reconcile native runs, callbacks,
partial files and backend termination before retrying after interruption.

Tasks on existing boards and owner-decision holds do not move automatically.
Timers are off; assignment/dependency events wake the team. Per-agent concurrency
limits do not raise the machine's writer capacity. Worktrees separate edits,
not macOS credentials. Keep Git review, merge, deployment and communication
within task-specific authority; a decision brief does not authorize its advice.
