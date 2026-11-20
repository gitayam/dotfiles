# Hermes coding board: orchestration lessons

The operator's cloud Hermes coding bot (Proxmox front end, broker and sandboxed worker on
the coding guest, ship service for merge request, CI, merge and deploy) runs a Kanban
board of planner, coder and reviewer profiles. Its code and runbooks live in
`ai-coding-env`; this page keeps the orchestration lessons this Mac's operator needs.
Public, generalised versions are vibe-coding `lessons-learned/hermes-agent.md` lessons
73-83. The company work-Mac board is a separate setup: [company-hermes.md](company-hermes.md).

## Dispatch sizing (2026-11-20)

`kanban.max_in_progress: 8`, `max_in_progress_per_profile: 3`, dispatch tick every 10 s.
The gateway reads these at start, so a change needs a gateway restart, and a restart
interrupts running cards: use the guarded `hermes-ops restart` and pick an idle moment.

## Lessons from 2026-11-19/20

1. **Isolate each healer action.** The board healer aborted its whole pass on one refused
   action (a dependency link that would close a cycle), and the board stalled for 105
   minutes. Fault-isolate each action, check for a cycle before linking, and walk only the
   cards the planner itself created (record creator ids).
2. **Name numbered files by rule.** Cards wait in a queue, so they say "the next free
   migration number on main, today N", never a fixed number: another change took 0004 while
   a card waited, and the card blocked.
3. **A pinned test is part of the change.** An existing test that fails only because it
   pins what the card was asked to change belongs to the change. A strict file-count limit
   made the coder block for a fourth file instead; say so in the contract.
4. **Repeated rejections mean the approach is wrong.** Four rejections in a row on an
   image-metadata stripper: fix the class (allowlist, rebuild the output, refuse what you
   cannot parse), not the instance. One level deeper, the compressed image data had to be
   inflated, size-checked and recompressed.
5. **A reviewer finding needs evidence.** A stand-in model claimed a correct PNG
   reserved-bit check broke tests while CI was green. Require the failing output, and check
   byte and bit claims against the bytes.
6. **Throughput comes from disjoint lanes.** Parked cards (waiting on review, CI or deploy)
   did not hold worker slots; long serial chains did. The ship rule "any file both changes
   touch = conflict" makes shared files (one locale JSON, the router, navigation) conflict
   magnets: split work into lanes by file area and add parallel cards only to lanes with
   disjoint files.
7. **Operator hand edits go through the board.** Hand edits outside the board collided with
   queued cards twice (the migration number in 2, the pinned test in 3). Route operator
   changes through the board, or leave a note on every affected card.
8. **Monitors match by a structured link.** A monitoring script matched shipped work by ids
   in free-text summaries; workers started citing merge-request numbers and it raised false
   "done without shipping" flags. Match on the ship job description, which starts with the
   card id.
9. **Frontend guidance is a skill on the card.** `frontend-ui` (start from the repo's design,
   the UI floor, form patterns, banned patterns, prove with interaction tests and real
   screenshots) is attached by the planner to every card that changes what people see.
10. **Refresh model choices.** Alibaba listed a newer model (`qwen4-max`) while the reviewer
    still ran an older one. Check provider model lists, and run a tool-call smoke test
    before switching a role; see [model-providers.md](model-providers.md).
11. **Check engine semantics before declaring a stall.** In Hermes' dispatcher an archived
    parent counts as finished, so its children are ready, not stuck.
12. **Model-policy isolation needs its own sandbox.** A coder on a policy-restricted
    provider (Qwen, allowed only for some projects by [ai-policy](ai-policy.md)) cannot use
    the shared sandbox, which holds clones of projects that provider is denied for. Give it
    its own sandbox and a project-scoped read token only. Built 2026-11-20 as `coder-alibaba`
    (`qwen4-max`, lunarnewyear only, `hermes-coding-sandbox-lny`): it needs a GitLab **deploy
    token**; a project access token's bot user still cloned the internal IrregularChat
    monorepo in the isolation check (revoked). It can't read other repos, so give it
    self-contained lunarnewyear cards.
13. **Keep headroom under `context_file_max_chars`.** The coding SOUL reached 38,730 chars
    against a 40,000 cap; past it Hermes cuts the end, where the owner's rules sit. A test
    keeps 2,000 chars of margin; the cap is now 60,000.
14. **A failed command still empties its redirect target.** A zsh loop staged nothing and
    `cat missing > config.yaml` emptied the live coder config for a minute (restored from the
    backup). Deploy through a script that refuses missing or empty staged files.
