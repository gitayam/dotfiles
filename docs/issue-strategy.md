# Issue strategy across agents

`shared/skills/issue-strategy` teaches CTO-level issue and backlog analysis:
understand the underlying problem, assess evidence and consequences, compare
choices, and recommend decisions and sequencing. Its output can be discovery,
an ownership/process change, simplification, deferral or implementation.
An analysis request does not implicitly authorize issue mutations or code work.

## Use it

The company installer selects a native entrypoint while keeping `WORKFLOW.md`,
references and the collector identical across agents. Refreshing updates the
whole bundle; do not copy an entrypoint without its resources.

| Agent | Installation |
| --- | --- |
| Hermes | Selected Hermes home, `skills/management/issue-strategy`; Desktop setup also refreshes planner, developer and reviewer profiles |
| Claude Code | Company workspace `.claude/skills/issue-strategy` and the selected Claude config's `skills/issue-strategy` |
| Codex on a personal workstation | Company `.workstation/skills/codex/issue-strategy`, linked from the user's Codex skills when that link is managed or absent |

On a company-only device, Claude Code also gets user-level discovery through
`~/.claude/skills`, including sessions started outside the company root. On a
personal workstation, the user-level copy goes into the isolated company
Enterprise config instead. Existing unrelated Codex installations are retained;
the device scope does not install a Codex runtime or authorize a new provider.
Claude Code uses native skill discovery and `$ARGUMENTS`; no duplicate legacy
`.claude/commands` file is needed. Hermes loads the shared workflow with
`skill_view`; Codex follows the linked file without Claude-specific substitution.

Refresh the existing private configuration; no gateway restart is required:

```sh
uv run --with pyyaml python scripts/setup_work_hermes.py \
  --from-config ~/zenithflow/.workstation/config.json --apply
# On the company-only device, refresh existing specialist profiles too:
python3 scripts/setup_work_desktop.py \
  --from-config ~/zenithflow/.workstation/config.json --apply
```

In Hermes Desktop/chat or Claude Code (use the company Enterprise launcher):

```text
/issue-strategy Review OWNER/REPO issue 42. Explain the problem, evidence,
alternatives and recommendation, including non-code options. Identify what
we must learn before committing. Return a decision brief; keep it read-only.
```

For a bounded terminal session, start in the intended workspace:

```sh
hermes-zenithflow chat --skills issue-strategy --oneshot --max-turns 8 \
  -q "Review the supplied issue snapshot at CTO level and recommend decisions."
```

On the gateway-backed CLI, a wall-clock budget comes from the selected profile's
`agent.run_budget_seconds` configuration; this runtime rejects `--run-budget` on
that path. A rejected launch has not run the analysis. Preserve active sessions
and do not change routing or approval policy to bypass the rejection.

Check the effective profile with `hermes skills list`. Installed discovery does
not prove loading: invoke `/issue-strategy` in a fresh Claude Code session and
verify the shared workflow is read, and exercise Hermes's `skill_view` in the
intended profile. Then test a representative issue and inspect whether the
report distinguishes evidence from inference, compares alternatives and supplies
measurable next steps. Keep private issue data and reports outside repositories
intended for publication. Follow the company's inference/provider rules.

## Collect a trustworthy snapshot

The included Python collector uses only GitHub REST GET endpoints. It prefers
the selected checkout's scoped Git credential helper. This supports a machine
whose default `gh` token is invalid while repository Git access still works;
it neither changes the global CLI login nor prints credentials. An explicitly
selected token environment is optional, never a token command-line argument.

```sh
python3 shared/skills/issue-strategy/scripts/collect_github.py \
  --repo OWNER/REPO --repo-dir /absolute/checkout \
  --output /private/reviews/new-index

python3 shared/skills/issue-strategy/scripts/collect_github.py \
  --repo OWNER/REPO --repo-dir /absolute/checkout --issues 12 35 90 \
  --output /private/reviews/new-details
```

The open index excludes pull requests, records the default-branch revision and
uses 200-record shards. Detail mode reads bodies, comments, timeline references,
parent/sub-issues and blocking relationships. Each paginated source reports
coverage. A partial listing or permission-denied relationship is not an empty
backlog/graph. Parent 404s remain unverified rather than silently meaning none.
Output directories are new and private; existing attempts are preserved.
An incomplete open listing or unavailable selected issue returns a failure exit
code while retaining its evidence. Relationship coverage must still be checked
individually; a missing parent is not silently converted into verified absence.

A large backlog should receive a metadata census and an explained deep sample,
not one oversized model request. The report must say exactly which evidence was
reviewed and which was unavailable. Labels, issue status, merged code and deployed
behavior establish different facts. Do not invent business impact, priorities,
owners, SLOs or deadlines from the index.

## Expected decision brief

- Problem and affected outcome, with reported/verified/inferred/unknown evidence.
- Options including the status quo and a minimum useful intervention; tradeoffs
  in impact, uncertainty, reversibility, ownership and ongoing maintenance.
- A small set of proposed decisions, dependency order, accountable roles to
  verify, next evidence-gathering steps, outcome measures and revisit triggers.
- Issue/source links and an honest coverage statement; proposed ADRs remain
  proposed until accepted by the authorized decision owner.

The skill's [research sources](../shared/skills/issue-strategy/references/research-sources.md)
link primary guidance on ADRs, operational toil, reliability investment, GitHub
relationships and skill loading. Those sources inform the method; their example
policies do not become local company policy.
