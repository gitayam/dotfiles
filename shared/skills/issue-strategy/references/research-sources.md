# Research foundations

Checked 2026-11-17. This skill is a synthesis, not an official CTO framework or
a statement of any company's policy. Revisit version-sensitive API behavior.

- [Microsoft: architecture decision records](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record): use context, alternatives, tradeoffs, consequences, confidence and proposed/accepted/superseded status for significant decisions. A draft recommendation does not establish acceptance.
- [Martin Fowler: architecture decision records](https://martinfowler.com/bliki/ArchitectureDecisionRecord.html): concise rationale helps future decisions and makes alternatives explicit. Use a superseding record when an accepted direction changes.
- [Google SRE: eliminating toil](https://sre.google/workbook/eliminating-toil/): assess recurring operational work across the workflow, consider simplifying the system, and check whether automation creates work elsewhere. Do not assume every repetitive activity should be automated.
- [Google SRE: example error-budget policy](https://sre.google/workbook/error-budget-policy/): reliability evidence can inform investment choices. Its thresholds and release policy are an example; they are not the operator's SLOs or permission to halt releases.
- [GitHub: issue dependencies](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies) and [REST dependencies](https://docs.github.com/en/rest/issues/issue-dependencies): distinguish formal blocking relationships from inferred sequencing or links in prose. Missing API access does not establish no dependencies.
- [GitHub: sub-issue API](https://docs.github.com/en/rest/issues/sub-issues): parent/child decomposition and blocked-by relationships answer different questions; collect both when relevant.
- [GitHub: issue comments](https://docs.github.com/en/rest/issues/comments): issue-list APIs also contain PRs, and discussion requires its own collection/pagination. An index alone is not a discussion review.
- [Hermes skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) and [Agent Skills specification](https://agentskills.io/specification): keep the discoverable entrypoint compact, load references on demand and verify the effective profile/skill source. Installed metadata is not proof of useful analysis behavior.
