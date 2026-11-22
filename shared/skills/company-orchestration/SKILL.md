---
name: company-orchestration
description: Choose and run company workstation work through native Hermes, a Paperclip Hermes team, approved Claude Code or read-only Orca, with one execution owner and independent acceptance.
---

Read `~/zenithflow/WORKSTATION.md` and
`~/zenithflow/.workstation/PAPERCLIP-HERMES.md` for actual qualified routes and
current coverage. Work under `~/zenithflow`; private IDs and credentials stay
in `.workstation`, outside repositories. Use approved company/local inference.

Find a repository through `~/zenithflow/.workstation/REPOSITORIES.md` (written
by dotfiles `scripts/map_work_repositories.py`; regenerate it with `--apply`
after checkouts change), not by guessing a path or searching the disk. Before
changing a repository, read its `DIRECTION.md`, then its `AGENTS.md` and
`CLAUDE.md` where the map lists them, and settle questions from those files and
the card before blocking: do the part of the work the rules allow and record a
limitation for the rest. A draft direction is an inference for the owner to
correct; the repository's own files and the card win over it. A project-linked
card already has its own worktree and branch — work there, never in a main
checkout.

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
tasks, changes inference routes or restarts the gateway/Paperclip. On a laptop,
install `scripts/setup_work_sleep_compensate.py --board <board> --apply` (the
main installer records the choice with `--sleep-compensate` and prints this
command): every minute it pushes running workers' active starts forward by the
time the Mac slept, so closing the lid pauses work instead of the dispatcher
killing it as timed out on wake. Instance-wide
recovery counters can describe historical or other-company issues; inspect exact
task/run evidence rather than automatically retrying them. Enrollment/service
failures produce a failed receipt instead of leaving an old success as current.
The snapshot's `hermes` entry is the installed runtime: revision, version, when
it changed and what changed it. Read it before stating a version or deciding
about an upgrade; a version in a note or a guide is a dated claim. The Hermes
Desktop app's update replaces the runtime and restarts the gateway, so start
one only with no card running. Installed is not accepted: `accepted_revision`
is what the qualification receipt names, and `null` means it names none.
If native Hermes adds `_config_version` and reformats qualified YAML, preserve
the exact-byte guard. The explicit `requalify_work_profile_metadata.py` helper
can preview a narrowly scoped repair: removing only that metadata in memory and
rendering with the installer must reproduce the accepted bytes exactly. Apply
only with an idle enrolled Paperclip team and a new private receipt. Behavioral,
runtime, binding or receipt changes require ordinary qualification. The helper
never rewrites profiles or interrupts workers; it preserves prior evidence and
pins the actual current bytes rather than ignoring future drift.
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

For a direct Kanban card, write the contract first: one input file that holds
everything the worker needs, the one file it writes, the commands it may run,
what is prohibited and a stop condition, sized for about 7 to 11 steps. Tell it
to write "not in the input" where the input is silent, and to complete and say
what stopped it rather than block. Create the card with `--body-file`, the model
and provider, `--max-runtime`, an idempotency key and, for a chain, `--parent`:
a child stays in todo until its parents finish. Size `--max-runtime` from the
loaded board, never from an idle one: on the measured board every time-limit
death had a limit written at creation (900 to 1800 seconds, so a bigger number
alone did not save it), and under a wide wave runs took 1.3 to 1.5 times the
limit. Read the running 90th percentile from `report_work_board.py` before a
wave and set the limit above it; a card left without a limit is not killed for
time. Set the model at creation, never
on a running card. How many cards run at once, in total and per profile, is set
by the installer's inputs (two and one unless raised): read the configured limits
before sizing a wave, and spread it across the profiles. Have the worker write
its file through a here-document whose delimiter is quoted (`<<'EOF'`) and put
single quotes round a search pattern that holds backticks: inside double quotes
and inside a bare here-document the shell runs them as commands. On the measured
board, cards written from a contract finished far more often than free-form or
automatically decomposed cards. Afterwards run
dotfiles `scripts/audit_work_cards.py` on the cards and
`scripts/report_work_board.py` on the board. A clean audit says the worker stayed
inside its contract; it is not acceptance of what it wrote. Run
`scripts/report_work_blocks.py` to see why each open card is open. A comment does
not release a blocked card: a decision answered in a comment still needs the
card unblocked or completed by its owner, with the answer recorded.

A card marked done says a run ended, not that its work left the checkout. When a
wave finishes, run `scripts/report_work_landing.py --board <board>` and give
every checkout it lists an end: a request opened or merged, a decision written
where the owner reads decisions, or the work rejected and the checkout removed.
Work that needs someone's word before it is pushed is itself a decision to
queue, with its age: on the measured board five accepted changes sat committed
on one laptop for four days with no card open and no decision listed, and one no
longer merged cleanly onto the branch it was written for.

Where the private configuration sets `kanban_auto_decompose` false and the board
intake job is installed, a rough request typed into Triage is specified within
about a minute into ONE card (goal, approach, acceptance criteria, out of scope)
and is not split into children. Such a card keeps its assignee and has no review
step; write a second card with a parent link when review is needed. Check the
root Hermes configuration, not a role profile, to see which mode a board is in.

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
