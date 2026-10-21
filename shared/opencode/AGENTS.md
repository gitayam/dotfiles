# Personal OpenCode guidance

Work within the user's requested scope and existing authorization. Read repository
AGENTS.md and relevant project instructions before edits. Preserve unrelated dirty
work. Follow the repository's canonical remote, review, test and deployment policy.
Continue authorized work through verification and publication when requested.

Verify work through files, diffs and actual behavior. Exit zero, a completion
message or another agent's approval is insufficient. Record partial work and the
reason when a deadline or tool boundary prevents completion. Do not repeat calls
with external side effects just because their output is quiet.

Use only the necessary rules and skills. OpenCode does not import Claude hooks,
rules or agent profiles automatically. Read the relevant file under
~/.claude/rules/ for operations involving Docker, identity, production databases,
web security or remote hosts. For email infrastructure, first read
~/.claude/rules/email-infrastructure.md and use the email-operations skill.
Do not print credentials, auth exports, token-bearing links or secret file values.
Refer to credential locations by path or item name only.

Use explicit provider/model identities; disclose routing changes. Hosted gateways
and Go subscriptions have quotas and provider policies. Tool permissions do not
remove model policies or provide an OS sandbox. Worktrees separate edits; LXC
shares its host kernel. The Proxmox controller's authenticated model lanes remain
blocked until their separate qualification gates pass.

Delegate when requested or useful within the authorized task, with bounded file
ownership, baseline, evidence, checks and a stop condition. Scout/reviewer children
are read-only aids, not final security approval. Their permissions are independent
of the parent. Run compiler/lint/tests explicitly; this V2 setup has no active LSP.
Keep stable prompt prefixes and load large references on demand. Measure cache
usage, retries and accepted results; cache hits alone do not establish savings.
