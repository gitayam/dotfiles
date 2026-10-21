---
name: claudeflare
description: Choose the maintained Cloudflare CLI and project workflow for a requested Cloudflare task, including existing Wrangler applications and account or resource operations.
---

# Cloudflare workflow adapter

Inspect the project configuration and instructions first. Preserve existing
Wrangler build/deploy workflows for projects with wrangler.toml/json/jsonc; use
the project's pinned tool and checks. For Cloudflare API/resource work, consult
the installed cloudflare-cf skill or the official cf CLI skill and current
[cf documentation](https://developers.cloudflare.com/cf/). Do not substitute
cf deploy for an existing Wrangler application without a requested migration.

Confirm the selected account, environment and target without displaying tokens.
Prepare and review the concrete change, use available preview/dry-run support,
then perform already authorized changes. Verify the resulting deployment/resource
through its actual API or URL. Keep production secrets outside source and logs.

This adapter works across coding harnesses; it does not assume Claude-only tools,
plugins or credentials. Load a product-specific official skill when needed.
For email infrastructure, read ~/.claude/rules/email-infrastructure.md and use
email-operations before configuring mail or DNS. Adjacent legacy references are
historical and need current documentation verification before use.
