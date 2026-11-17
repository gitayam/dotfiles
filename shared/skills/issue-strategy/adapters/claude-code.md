---
name: issue-strategy
description: "CTO-level issue and backlog analysis: establish evidence and business/system risks, compare options including non-code interventions, and recommend decisions and measurable next steps."
argument-hint: "[issue URL or OWNER/REPO] [decision question]"
---

# Issue strategy for Claude Code

Decision question: $ARGUMENTS

If arguments are empty, use the current user request. Read and follow
[the shared workflow](WORKFLOW.md) before analyzing; it defines the evidence,
scope and recommendation contract. Supporting references and the optional
GitHub collector are relative to this skill directory.

Respect the workspace's CLAUDE.md/AGENTS.md, approved provider/account and normal
Claude Code permissions. This skill adds no tool pre-approvals or automatic
commands. Use permitted reads to establish facts; collect GitHub evidence with
the helper only when the request and existing permissions allow it.

Keep private artifacts outside source checkouts. Return a decision brief with
evidence, options, proposed owner roles and measurable next steps. Preserve
explicit implementation authority if the user also requested it, while keeping
analysis-only requests free of issue/code mutations and persistent policy writes.
