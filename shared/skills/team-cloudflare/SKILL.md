---
name: team-cloudflare
description: Coordinate a requested multi-agent Cloudflare implementation or review with bounded ownership and one deployment owner.
---

# Cloudflare team workflow

Use the claudeflare skill to select the current project CLI and official product
guidance. Define disjoint file ownership and a shared interface for concurrent
work. Read-only reviewers should receive prepared diffs, test results and target
constraints; they must not mutate the account or deploy competing candidates.

Keep one integration and deployment owner. Review the combined changes, run the
project checks, and publish through the repository's authorized CI/deployment path.
Verify the deployed version and behavior, including mobile checks when relevant.
Do not treat green CI alone as evidence of the final user-visible behavior.

Native child permissions do not inherit the parent's limits. Use qualified roles
and explicit boundaries; consult team-swarm for this machine's controller gate.
This skill supplies coordination, not extra account access or authority to alter
production databases, DNS, credentials or mail infrastructure.
