# Local OpenCode validation — 2026-10-21

Runtime: OpenCode 2.1.0, native Go Plus login. The installed global core, five shared
skills and native profiles were active. Credentials and unrelated settings were
preserved. [Selected metadata and configuration hashes](opencode-validation-2026-10-21.json)
are versioned; raw private task events remain outside the repository.

| Check | Observed result |
|---|---|
| Skill integrity/frontmatter | Five maintained entrypoints pass the skill-creator validator; no NUL bytes |
| Installer/launcher/gateway controls | Eight offline tests pass, including silent DONE, model metadata, PWD, child cleanup, private-key checks and token-free argv |
| Qwen native build | Read calc.py/test_calc.py, fixed subtraction to addition, ran unittest; independent behavior check passed; test file unchanged; 16.369 seconds, four parent model turns |
| Mixed-model native dispatch | Qwen parent launched scout and reviewer; both completed with retained GLM-5.3-Flash identities, two model turns each; seeded regression identified; fixture files unchanged; parent 36.399 seconds/five turns |
| Actual child permission evaluation | 24/24 checks passed: each role allows source read/glob and denies edit, shell, recursion, execute, external directory, credential reads, grep and an unknown MCP action |
| Reliability skill behavior | Native skill tool completed; Qwen correctly rejected an exit-zero DONE with missing artifact and rejected quiet stdout as sufficient hang diagnosis; 12.323 seconds/two turns |
| Global instruction loading | Without tools or file reads, Qwen identified the global AGENTS.md path and correctly summarized its Proxmox qualification, worktree and kernel-boundary guidance; 6.944 seconds/one turn |
| Claude gateway local setup | `cc-opencode --check` found Claude and the active Console credential; no inference or credential contents printed |

An initial permission-evaluator probe on the parent session with child-role
overrides returned two unexpected denials of allowed scout operations. The cause
was not established. Final checks use the actual role-matched child sessions,
verify their selected agent before evaluation, and include positive controls.
The checks evaluate native policy; they do not execute arbitrary MCP tools or
establish an OS boundary. Completed child sessions really did read the fixture.

The child and skill canaries intentionally had no executable checker passed to
`oc-task`, so its receipts correctly report `acceptance: unchecked`, `complete:
false`, and exit 2. The owner independently inspected their actual outputs, model
identities, tool events and unchanged fixture files. They are not silently counted
as automatically accepted coding tasks. Usage figures in the launcher cover the
parent only; child usage is retained separately.

Reported costs were about $0.00942 for the build parent, $0.01086 for the dispatch
parent, and $0.00829 for the skill parent, plus separately retained child usage.
These are gateway accounting values, not extra Go cash charges. Cache counters
are recorded but no cache-on/off savings experiment was performed.

The original corrupt skill files remain in the first private install backup,
`~/.local/state/opencode-setup/20261021-001410-m_wny87o/`. Existing adjacent skill
resources and the old reliability research log were preserved. The three damaged
entrypoints were all NUL bytes; these are rebuilt workflow adapters, not a claim
to have recovered their lost original text.

These are small synthetic daily-configuration canaries. They are separate from
the earlier 81-attempt benchmark and do not qualify broad autonomous repository
work, Proxmox authenticated workers, token renewal, compaction, long sessions,
Claude mixed-model children or provider policy behavior. The launcher is a bounded
process wrapper; its trusted checker and native tools retain local user authority.

See [installation and usage](opencode-local.md) and the
[audited study](https://irregularpedia.org/ai-ml/agent-reliability-study/).
