---
name: issue-strategy
description: "CTO-level issue and backlog analysis for Hermes: assess evidence and business/system risks, compare code and non-code options, and recommend decisions, sequencing and measurable next steps."
---

# Issue strategy for Hermes

Use the current request or the text following `/issue-strategy` as the decision
question. Load [the shared workflow](WORKFLOW.md) before analyzing, using
`skill_view(name="issue-strategy", file_path="WORKFLOW.md")`. Linked references
and `scripts/collect_github.py` can be viewed through the same skill directory.

Follow the current profile and workspace's approved model/credential policy.
For terminal collection, use the selected checkout's scoped Git helper and an
explicit private output path; inspect the collection manifest before reporting
coverage. A denied read remains a gap; respect tool approval denials.

Return a proposed decision brief. Do not automatically create Hermes cards,
assign Paperclip work, mutate GitHub, implement fixes or persist lessons merely
because this analysis skill was invoked. Preserve explicit authority for actions
the user separately requested. Never treat board completion or model confidence
as acceptance of a strategic recommendation.
