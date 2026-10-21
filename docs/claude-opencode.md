# Claude Code with OpenCode Go Plus

`cc-opencode` keeps the Claude Code harness and connects directly to OpenCode's
Go subscription endpoint. The OpenCode CLI and a local LiteLLM proxy are not needed.
The executable lives in `shared/bin`, already on this Mac's PATH.

## Credential and launch

If you have signed into the Go Plus workspace with OpenCode, launch directly:

```sh
opencode auth login opencode
cc-opencode --check
cc-opencode
```

The launcher captures `opencode auth export opencode` privately and uses only the
active account's access token. It does not copy or print the refresh token and
does not edit OpenCode's database. When access expires, it asks OpenCode to load
models to refresh through its shared service, then rereads the credential once.
If that fails, renew the login through OpenCode. Login workspace selection must
match the workspace that owns Go Plus.

Alternatively, create or select an API key in that workspace and save it locally
with hidden input:

```sh
cc-opencode --setup-key
cc-opencode --check
cc-opencode
```

The key is saved to `~/.config/claude-opencode/api-key` with mode 600. This file is
outside the dotfiles repository. Environment variables `OPENCODE_GO_API_KEY` and
then `OPENCODE_API_KEY` take precedence over the key file and saved Console login.
The launcher never prints the credential
or puts it in process arguments. `--setup-key` replaces a previously saved key.

The initial model is `qwen3.7-plus`, listed with an Anthropic Messages endpoint.
All tier aliases and the default subagent model use that same model initially.
For another model confirmed to support Go's Anthropic Messages API:

```sh
OPENCODE_GO_MODEL=qwen3.8-flash cc-opencode
```

Claude arguments are forwarded, for example `cc-opencode -p "Say hello"`.
`cc-opencode -- --help` displays Claude's own help. The launcher uses Claude's
normal permission behavior; explicit CLI options and existing settings still apply.
Inherited Anthropic credential and provider-routing variables are cleared only
in the child process. The saved Claude login and global settings are not edited.
Explicit model choices in custom agent definitions can override the default
subagent mapping and must refer to models served by the gateway.

## Verification status

Verified on 2026-10-20 with Claude Code 2.1.292 and OpenCode 2.1.0:

- The active Console OAuth login fetched the workspace configuration and Go models.
- A direct Go Anthropic Messages request to Qwen3.7 Plus returned HTTP 200 and
  the exact requested synthetic known answer.
- Claude Code completed a five-turn read/edit/test task in a disposable directory
  in 14 seconds. It corrected addition implemented as subtraction, used the
  requested tools, and returned the expected completion marker.
- An independent Python test run passed; the test file was unchanged.
- Synthetic local checks covered credential precedence, private key permissions,
  expiry handling, provider-variable cleanup, model mappings, and argument forwarding.

The existing Console login works without creating a separate API key. A local
`--check` does not send inference or reverify the subscription. Subagent execution,
compaction, long sessions, real token expiry, and detached background credentials
have not been live-qualified by these checks.

After adding the key, verify `/status` in the launched Claude session shows
`https://opencode.ai/inference/go/anthropic` and the gateway auth token.
Check a subagent, compaction, and long-session behavior before using it for
unattended repository work.
Background sessions must also be checked: nonsecret routing is provided through
`--settings`, but detached sessions may need separate credential provisioning.
Do not assume every model in the Go catalog supports Claude Code's API format.

## Sources checked 2026-10-20

- [OpenCode Claude Code harness guide](https://dev.opencode.ai/v2/docs/console/harnesses/claude-code/)
- [Go and Go Plus plans, endpoints and limits](https://opencode.ai/v2/docs/console/go/)
- [Claude Code gateway authentication and background sessions](https://code.claude.com/docs/en/llm-gateway-connect)
- [Claude Code model mappings](https://code.claude.com/docs/en/model-config)
- [OpenCode credential commands and storage](https://opencode.ai/v2/docs/cli/providers/)
- [Console device tokens and workspace binding](https://opencode.ai/v2/docs/console/api/)

The dedicated harness guide currently lives on OpenCode's development docs host.
Its broader model claims need runtime verification; Qwen3.7 Plus is also listed
with an Anthropic Messages endpoint in the main Go documentation.

## Customization audit (2026-10-20)

The launcher still uses Claude Code's instruction loading and extensions. Native
OpenCode uses a different customization system:

| Asset on this Mac | Claude through `cc-opencode` | Native OpenCode 2.1.0 |
|---|---|---|
| Seven global Claude rule files | Loaded by Claude | Not automatically imported |
| Repository `CLAUDE.md` | Claude discovery/import behavior | Requires explicit instructions or migration to shared `AGENTS.md` |
| Claude skill directories | Claude skill behavior | Discovered, but tools and frontmatter need compatibility review |
| Two global Claude agent profiles | Claude profile behavior | Must be converted to native profiles and permissions |
| Claude/Codex plugins | Remain specific to their harness | Require an equivalent OpenCode integration |

There is no global `~/.claude/CLAUDE.md` on this Mac; the rule directory still
applies in Claude. Codex's global `AGENTS.md` currently points at the shared email
infrastructure rule rather than mirroring all seven Claude rules. Vibe's generated
global instructions include only the operational and web security sources.

Native OpenCode's skill API reported 56 entries: two built-ins and 54 discovered
from Claude directories. Nine account-synced skill IDs have duplicate on-disk
copies; their contents were identical at audit time. Discovery is not proof that
Claude-specific tools, scripts, or agent dispatch work in OpenCode. Preserve
managed synced directories and inspect the resolved source for duplicate IDs.

The installed legacy `vibe-orchestrator` skill incorrectly treats every
non-Anthropic gateway as unlimited self-hosting and contains V1 OpenCode flags.
The maintained repository refresh replaces those assumptions with explicit lanes,
quotas, ownership, and checks. Review the repository diff before replacing a
locally customized skill. That initial audit did not install native configuration.
The follow-up [scoped local setup](opencode-local.md) now installs the native core,
role profiles and repaired shared skills; Claude's own rule/hook files are preserved.

For native OpenCode, start with project-scoped `AGENTS.md`, explicitly list the
remaining relevant `CLAUDE.md` files under `instructions`, reuse portable skills,
and convert agent profiles with actual permissions. Avoid globally importing every
project's large instruction files: the seven current global Claude rules alone
are approximately 51 KB. Load domain-specific detail when it applies.

Documentation and model templates were merged into the canonical GitLab
`irregulars/irregularchat-monorepo` and `public-repos/vibe-coding` repositories.
See the native setup's dated receipt for subsequent mixed-model dispatch checks.
Those checks do not qualify Claude child/background behavior through this gateway.
