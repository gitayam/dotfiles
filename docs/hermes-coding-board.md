# Hermes coding board: orchestration lessons

The operator's cloud Hermes coding bot (Proxmox front end, broker and sandboxed worker on
the coding guest, ship service for merge request, CI, merge and deploy) runs a Kanban
board of planner, coder and reviewer profiles. Its code and runbooks live in
`ai-coding-env`; this page keeps the orchestration lessons this Mac's operator needs.
Public, generalised versions are vibe-coding `lessons-learned/hermes-agent.md` lessons
73-110. The company work-Mac board is a separate setup: [company-hermes.md](company-hermes.md).

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
15. **A rewritten tool schema empties structured output.** `qwen4-max` and `kimi-k3.1-pro`
    finished review cards with `metadata: {}`: Hermes turns a free-form object parameter
    into `{"type":"object","properties":{},"required":[]}` and strict decoders obey it
    (A/B: `additionalProperties: true` fixes it; upstream hermes-agent #96610, fixes in PRs
    #147306 and #96913, unreleased on 2026-11-20). The quality reviewer moved to
    `kimi-k2.7-code`. Prove a role's model on a real card before switching.
16. **Merge caps per project.** A global 6 merges/hour queued approved MRs for up to 79
    minutes once several lanes ran. Ship config now has `maxMergesPerHour` 24 and
    `maxMergesPerHourPerProject` 12; the queue drained to under 2 minutes.
17. **Feature-sized operator cards go to the planner.** Six cards I gave the coder each
    spent a turn discovering they exceeded the three-file job limit before handing off.
18. **Check the token cap before blaming a model.** My eval harness capped output at 2,500
    tokens; every "ended without a verdict" run had used 2,524-2,551. Record
    `finish_reason`. Model comparison: [model-providers.md](model-providers.md).
19. **Price a real card, and check the cache counter.** `qwen3.6-plus` had zero cached
    tokens over 96 review cards: about $0.27 and 206 s each against `kimi-k2.7-code`'s $0.10
    and 69 s. Per-card costs per model are on the Irregularpedia comparison
    pages; Hermes keeps `cache_read_tokens` per session in each profile's `state.db`.
20. **Pin reasoning effort per role.** GLM 5.3 at its default effort overran 8K output
    tokens; at `reasoning_effort: low` (Mistral endpoint) it passed 6/6 in 3 s.

## Lessons from 2026-11-20 (afternoon), ai-coding-env !184-!193

21. **Hand-offs by creator.** The healer held whole plans behind the vendor UX plan's integration
    card because my operator-created plan (and six cards I reassigned to the planner) looked like
    a coder hand-off; the board ran 0-1 cards with 30 waiting. A hand-off is now a planner card its
    parent coder created (!185). Chain my own cards only on file overlap.
22. **Migration numbers.** Three lanes took 0008, then two took 0011. The ship service refuses a
    duplicate number at merge (!187) and the healer keeps one migration card in flight per
    project (!188, !189: a woken card that has run is in flight, not unstarted). The planner has
    no `kanban_list`, so a planner-only rule could not work.
23. **Review template.** "Every required test must be in the patch" rejected tests already on
    main and tests titled differently; reviewers now judge whether requirements are met, by the
    patch or already in the project via `ship_search`/`ship_file` (!186).
24. **Security floor for coders.** A short section in the coding SOUL from the day's security
    rejections (!191); the next four jobs passed first time.
25. **Releases are not waits.** `waited_cards` read "releasing child t_…" as a wait, so the
    deadlock rule cut chains and a parallel patch conflicted (!192).
26. **Busy means full.** One running card made a profile busy, so parked cards waited up to 50
    minutes; busy is now all 3 slots (!193, `PROFILE_SLOTS` mirrors the config).
27. **No follow-up after a hand-off** (!190), and **no coder edits to `AGENTS.md`**: protected
    files wait for an approval nobody gives; notes go to `DIRECTION.md` (!186).
28. **Measure the queue first.** Ready-to-claimed was 6 s median, 9 s p90 for the default coder:
    slots are not the limit, so no overflow lane for `coder-alibaba` (3 runs vs 300). The limit
    is chain length and each card's review/CI/deploy cycle. No coder or planner hit its step
    budget; the Lumo shadow reviewer hit 30/30 twice and had 4 protocol violations.

## Lessons from 2026-11-21, ai-coding-env !199-!200

29. **A red main is not the card's fault.** lunarnewyear !318 and !319 each passed CI, merged a
    minute apart, and together pushed the catalogs past the translation API's 32 KB source cap;
    main went red and !319's deploy failed. !321 and !323 were built on that commit, failed the
    same test, and went back to their cards, which re-shipped unchanged patches through three
    reviews each (2 of 7 jobs redone). The ship service now holds a failure whose base commit
    was already red on the branch, waits for the branch to pass, re-applies the same patch once
    (force-with-lease over its own head only) and re-runs CI (!199). Not covered: two changes
    that pass alone and fail together; that needs merge-result testing before each merge.
30. **Quote search patterns.** The company board's audit found a worker whose double-quoted
    search for a markdown phrase ran a backticked word as a command and reported "0 found"
    (vibe-coding lesson 108). The coding SOUL now says to single-quote any pattern holding
    backticks or `$` (!200); it already sent file writes through the file tools. Our board's
    budget deaths in the last three days were the Lumo shadow reviewer at 30/30 (12) and two
    coders at 60/60; every one finished on its retry.
