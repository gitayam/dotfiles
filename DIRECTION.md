# Direction: Dotfiles

The owner's personal workstation setup for macOS and Linux (zsh config, setup and
hardening scripts, git and SSH tools, encrypted secrets, Claude Code launchers), plus an
older Ansible playbook for remote host operations. Public on GitHub (CLAUDE.md, README.md).

Status: active (last change 2026-11-19). About 117 commits in November 2026 after a quiet
summer; the Ansible half last changed 2026-07-31.

## Where it is heading

- A reproducible workstation: re-runnable macOS and Linux setup that asks every question
  first, then runs unattended, with a `DRY_RUN=1` mode and a list of what was skipped
  (7536668, 73510e1, 50d69f2, 6506f10, CLAUDE.md "Local Config Sync").
- Hardening that reports before it changes anything: `harden.sh` checks by default and
  applies only with `--apply`, mapped to mSCP/CIS (macOS) and CIS/KSPP/ssh-audit (Linux)
  (30e13a3, 749a788, 80779e5).
- Secrets never on disk, argv or screen: the `secret` tool (sops + age, per-device keys in
  the OS keychain) replaces plaintext env files (20eab44, 82022f7, 5a0f636, 0ae1f47).
- Claude Code as the only coding harness, on Anthropic or on private model servers through
  one registry (`shared/llm/models.conf`) and `claude-z`, with Paperclip, Hermes and Orca
  lanes on the same backends (ef8de31, cb3d5c5, 816c26d, 0cf10ea, CLAUDE.md "Claude Code
  backends").
- Per-project AI policy enforced before any model request (Claude Code hook, orca-lanes,
  OpenCode plugin), failing closed (71fa985, 85b785c, docs/ai-policy.md).
- Tested and portable: a regression suite in bash and zsh with CI on macOS and Ubuntu, and
  `dots` to find and document every function (fc0d601, 9f57f07, tests/run.sh).
- A company workstation agent stack kept apart from the personal one: scripts that set up
  company Hermes profiles and a Paperclip team, a read-only monitor, and tools that report
  a task board from its own records (a05210e, ab1049c, 3e03988, a0ab33f,
  docs/company-hermes.md).

## Priorities

1. Keep `tests/run.sh` green on both OSes and add a test that fails on the broken code
   with every bug fix (CLAUDE.md "Tests", fc0d601).
2. Keep the coding-stack launchers working across machines and upgrades: tunnels only to
   reachable servers, Paperclip surviving Node upgrades, IDs looked up rather than copied
   (918e46e, 15dd4d0, 11a6bdb).
3. Extend the AI policy as new providers are added; every new backend gets a vendor and
   service entry and its deny rules (85b785c, d0f0df0, docs/ai-policy.md) (inferred).
4. Decide the Ansible half's target before any run: the default inventory points at an
   address no longer on the tailnet (CLAUDE.md warning, verified 2026-11-09).
5. Keep `dots --lint` empty: every user-facing function gets a one-line description
   (CLAUDE.md "Finding commands").
6. Change the company agent setup in the setup scripts with a test, never by hand on the
   device: a refresh reverts hand edits. Keep what the scripts write into each role's
   `config.yaml` byte for byte unless a requalification is planned
   (docs/company-hermes.md, a0ab33f).

## Non-goals and constraints

- Public repo: no `.env`, `inventory/custom/vars.yaml`, keys or secret values; the secret
  store lives in a private repo or Syncthing folder (CLAUDE.md, .stignore, 8349ee1).
- Secrets never in argv, files or terminal output; `run` decrypts into the one command
  that needs them (20eab44, CLAUDE.md "Secrets").
- Claude Code is the only coding harness; other front ends drive it (CLAUDE.md "Claude
  Code backends", owner's global instructions).
- Alibaba models and services are denied for IrregularChat and ZenithFlow; Lumo is denied
  for ZenithFlow (71fa985, 85b785c).
- Hardening and setup default to read-only or dry run; Linux hardening writes only its
  own drop-ins and skips settings that break Flatpak, snaps, Docker or IPv6 (CLAUDE.md).
- Shell files stay bash-compatible because Linux sources them with bash; no shadowing of
  real commands except deliberate wrappers (CLAUDE.md "Finding commands").
- Canonical zsh files are in `shared/zsh/`; `macos/.zshrc` is a stale copy (CLAUDE.md).
- Ansible: `--check` first, never an unfamiliar tag combination against production first,
  and `ansible <host> -m ping` before anything heavy (CLAUDE.md "Safety Notes").
- Downloaded installers are pinned and checksum-verified; Flathub only for verified
  publishers (CLAUDE.md "Local Config Sync").
- Review-only for the Hermes ship service: bot changes open a merge request and are never
  merged automatically (ai-coding-env servers/hermes-coding/SHIP.md, e60e44a there).
- Company device details (addresses, ids, private paths, task text) never appear here;
  they stay in the device's private workspace (docs/company-hermes.md).
- On a work device the main checkout is live: a monitor and a scheduled board intake run
  from it. Work in a separate worktree; never switch its branch or leave edits in it.

## Decisions

- 2026-11-19: A task board can specify a rough request into one card instead of
  decomposing it: a private input turns decomposition off in the root configuration only,
  and a one-minute intake job specifies Triage cards (a0ab33f, e8b5c5e).
- 2026-11-19: Read-only tools report a board's outcomes by who wrote the card and audit a
  worker's recorded tool calls against its contract (3e03988, fd11992).
- 2026-11-19: A read-only audit of the company agent stack runs every five minutes
  (ab1049c).
- 2026-11-18: Company Hermes profiles can run as a Paperclip team through request graphs
  (a05210e).
- 2026-11-16: Add Lumo as a Claude Code and OpenCode backend, denied for ZenithFlow
  (85b785c).
- 2026-11-12: Per-project AI policy; Alibaba denied for IrregularChat and ZenithFlow
  (71fa985).
- 2026-11-12: One model registry and `claude-z`; drop the Vibe, DeepSeek and Mistral
  launchers from the aliases (`claude-switch` kept as legacy) (ef8de31).
- 2026-11-10: Encrypted secrets with sops + age and per-device keys; not Secure Enclave
  keys, because Linux devices could not use them (20eab44).
- 2026-11-09: Regression suite and CI on macOS and Ubuntu (fc0d601).
- 2026-11-09: Hardening scripts read-only by default with explicit `--apply` (30e13a3,
  749a788).
- 2026-07-31: Version-control the Proxmox host's Docker runtime recovery and alerting in
  `ansible/files/` (81d5e3a, c8bca94).
- 2026-06-03: Add CLAUDE.md as the Ansible quick reference; remove an env backup
  (111aacd, ee44408).

## For agents working here

- Find out whether the thing already exists before adding it: search the repository and
  the decisions above. Lumo, for example, is already a Claude Code and OpenCode backend
  (`cc-lumo`, docs/claude-lumo.md).
- An application for a new machine goes into the question-first setup scripts
  (`macos/initial_macos_setup.sh`, `linux/initial_linux_setup.sh`), beside the nearest
  existing example, and must behave under `DRY_RUN=1` (CLAUDE.md "Local Config Sync").
  A download is pinned and checksum-verified, or comes from Homebrew or a verified Flathub
  publisher. A "manual install" line with an unpinned link does not meet that.
- Every change comes with a test in `tests/run.sh` that fails without it; run the whole
  script before pushing (priority 1).
- Open a pull request from a branch named `<feat|fix|docs>/<slug>-YYYYMMDD`; nothing is
  committed to `main` directly.
- When the request does not say which of two readings is meant, take the one the nearest
  existing example supports, say so in the pull request, and leave the other as a question
  there rather than stopping.

## Open questions for the owner

- What is the future of `ansible/`: fix the inventory for the current Proxmox host, or
  retire it in favour of the ai-coding-env scripts? Several tracked files in this public
  repo name internal addresses and host paths.
- Should the old clutter in `docs/` (test_*.txt, demo-file.txt, older guides) be removed?
  CLAUDE.md calls some of it stale.
- Is `claude-switch` due for removal now that no alias uses it?

## Related documents

- CLAUDE.md (main reference: setup, secrets, backends, tests, tools)
- docs/ai-policy.md, docs/orca-lanes.md, docs/claude-lumo.md, docs/claude-opencode.md,
  docs/opencode-local.md
- ansible/USAGE_GUIDE.md, ansible/ANSIBLE_REVIEW_AND_PLAN.md
- tests/run.sh
