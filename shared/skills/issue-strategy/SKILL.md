---
name: issue-strategy
description: "Analyze an issue or backlog at CTO level: establish the problem and evidence, assess business and system risks, compare options and recommend decisions, sequencing and measurable next steps. Use for issue research, portfolio reviews and technical strategy; implementation is a separate request."
---

# Issue strategy

Load and follow [the shared workflow](WORKFLOW.md) before analyzing the current
request. It defines evidence coverage, problem framing, non-code alternatives,
decision ownership and the boundary between analysis and implementation. Load
linked references only as needed.

The optional collector is `scripts/collect_github.py`; use its manifest to
distinguish a census from a deep sample and incomplete reads. Keep private
artifacts outside publishable repositories and use the workspace's approved
models and credentials.

Use the current request as the decision question. Agent-specific entrypoints
are selected at installation; all versions carry the same WORKFLOW.md,
references and collector.
