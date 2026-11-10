# Dotfiles — Personal Configs + Ansible Remote Ops

This repo is **dual-purpose**:

1. **Local dev environment** — zsh configs, git aliases, AWS CLI helper functions (33 on macOS / 20 on Linux), Cloudflare file-sharing scripts, Python/TypeScript utilities (`macos/`, `linux/`, `shared/`, `scripts/`, `python/`, `typescript/`, `development/`).
2. **Remote ops automation** — one big Ansible playbook (`ansible/system_management.yml`, 1.5k lines) for system updates, git pulls, Docker image upgrades, and per-service workflows across a small fleet (`ansible/inventory/`).

The two halves are independent. Local install runs `./install.sh` per platform; remote ops runs `ansible-playbook`.

> ⚠️ **Check the target before any ansible run (verified 2026-11-09).**
> - `ansible/inventory/tailscale.yml` points `proxmox-main` at `100.107.228.108`, which is **not on the current tailnet** (inventory unchanged since 2025-12-16).
> - The online Proxmox is `100.87.20.88` (the johncloud colo host that `ai-coding-env` and the `host-upgrades` skill manage). Decide which machine you mean and fix the inventory deliberately; don't point this playbook at the colo host by accident.
> - Obelisk (`192.168.1.19`) was decommissioned on 2026-06-22. The Mac mini (`100.76.128.36`) is on the tailnet but usually offline. `ai-coding-env/scripts/` has no Mac mini or GCP relay scripts; those hosts are managed by hand.
> - Bringing macOS hosts under ansible would need inventory plus a playbook (Homebrew/softwareupdate aren't in `system_management.yml`).

---

## Ansible Quick Reference

**Entry point:** `ansible/system_management.yml` (interactive prompts for host, user, sudo pass — or pass via `-l` / `-e`).

**Inventory** (`ansible/inventory/`):
| File | Hosts | Notes |
|---|---|---|
| `tailscale.yml` | `proxmox-main` (100.107.228.108) | Default — Tailscale-routed. **Address not on the tailnet as of 2026-11-09; see the warning above** |
| `local_network.yml` | `proxmox-main` (192.168.4.222), `irregularchat-information` (192.168.4.4), `econ_proxmox` (192.168.4.164), `econ_matrix` (192.168.4.3) | LAN-direct |
| `proxmox-upgrade.yml` | special-purpose for Proxmox OS upgrades | Different IP — read first before using |
| `custom/services.yaml` | 47 docker-compose services, ~8 disabled | Drives the `docker_compose_update` task |
| `custom/vars.yaml` | `ssh_keys`, `log_path`, `search_path` (default `/home`), `exclude_path` (default `/home/discourse`), `authentik_version` | Required — see `vars.yaml.template` |

**Live state notes** (verified 2026-11-09): the inventory's `proxmox-main` address is not on the tailnet, so `ansible <host> -m ping` will fail until the inventory is fixed; `irregularchat-information` has been intermittently offline (DNS-related — see `ansible/USAGE_GUIDE.md`). Always `ansible <host> -m ping` before anything heavy.

### Task → tag mapping

| Intent | Command |
|---|---|
| System packages (apt) — full | `ansible-playbook system_management.yml -l <host> --tags 'update,upgrade,cleanup'` |
| Security-only system updates | `--tags 'security,update'` |
| Pull all git repos under `/home` | `--tags git` (recursive find, **excludes `/home/discourse`**) |
| Update ONE docker service | `--tags docker_quick -e 'compose_path=/home/<service>'` (fastest, <1 min) |
| Update ALL docker services on host | `--tags docker_compose_update` (⚠️ 30+ min, 47 services) |
| Pull all docker images | `--tags docker_pull` (⚠️ hours, 143 images) |
| Per-service workflows (auto-targets the right host) | `--tags authentik` / `cryptpad` / `vaultwarden` / `researchtools` / `searxng` / `clapper` |
| SSH hardening | `--tags 'ssh_hardening,hardening'` |
| Monitoring tools install | `--tags monitoring` |
| Backup script + cron | `--tags backup` |
| Push a file to a host | `--tags send -e 'src=<local> dest=<remote>'` |
| Run an arbitrary shell command | `--tags custom_command -e 'cmd=...'` |
| Run a local script on remote | `--tags run_script -e 'script_path=<local>'` |
| Fresh-install bundle | `--tags fresh_install` (ssh + packages + perf + monitoring + apps) |

> The playbook has `service_tag_host_map` — e.g. `authentik` and `cryptpad` auto-target `irregularchat-information`; `researchtools`, `vaultwarden`, `searxng` auto-target `proxmox-main`. You don't need `-l <host>` when using a service tag, though you can override.

### Service-specific update workflows (hardcoded in the playbook)

| Service | What it does |
|---|---|
| `authentik` | Backs up compose, wgets latest `docker-compose.yml` from `docs.goauthentik.io`, `compose pull && up -d` |
| `cryptpad` | `git pull` → copy config → `install-onlyoffice.sh` → `npm ci` → `pm2 restart cryptpad` |
| `vaultwarden` | Runs `/home/vaultwarden/docker-cmd.sh` |
| `searxng` | `git stash` → `git pull` → `git stash pop` → `compose pull && up -d` |
| `researchtools` | `git pull` (if tracking set) → `compose pull` → `compose up -d --build` |
| `clapper` | `compose pull && up -d` |

---

## Safety Notes

- **Always dry-run unknown ops first:** `--check` previews changes without applying. Time-intensive ops (`docker_compose_update`, `docker_pull`) should be `--check`-ed even if you've run them before — the change set may surprise you.
- **Recursive git pull behavior:** The `git` tag finds every `.git` directory under `search_path` (default `/home`) and attempts `pull --ff-only → --rebase → merge`. Uncommitted work in a repo can interact badly with this. `/home/discourse` is explicitly excluded because Discourse manages its own repo state via the rebuild script.
- **Docker IPAM is all-or-none in a user-defined bridge.** If you add a new service to a compose file that already pins some services' `ipv4_address`, pin the new one too (or unpin all). See `~/.claude/rules/docker-ops.md`.
- **`docker compose restart` does NOT pick up env var changes** in compose.yml. After editing env: use `up -d` to recreate.
- **Don't commit `.env` or anything in `inventory/custom/vars.yaml`** — `ssh_keys` and sudo configs live there.
- **Production:** Never run an unfamiliar `--tags` combo against production first. Test against a sacrificial host or use `--limit` + `--check`.

---

## Local Config Sync (Mac)

Interactive sync from this repo's `shared/zsh/` (the canonical copies) to `~/.zshrc`, `~/.zsh_*`:

```bash
./macos/install.sh        # Linux: ./linux/install.sh
```

For each differing file it asks before overwriting and keeps a timestamped backup. `scripts/sync_mac_dotfiles.sh` is a stub that runs it. `macos/.zshrc` is a stale copy; edit `shared/zsh/.zshrc`.

The new-Mac bootstrap is `macos/initial_macos_setup.sh` (alias `initial-install`): Homebrew formulae and casks, IrregularChat bookmarks file, macOS security/defaults, then the sync above. All questions come first, then one sudo prompt (kept alive), then it runs unattended with `HOMEBREW_NO_ASK=1`; only the screen-lock delay and FileVault, if chosen, ask for the password again at the very end. Re-runnable; `DRY_RUN=1` asks the questions but only prints brew commands and skips sudo, settings and sync. It skips casks Homebrew has disabled and lists every skipped or failed item, plus next steps, at the end.

The Linux counterpart is `linux/initial_linux_setup.sh` (Debian/Ubuntu; same alias on Linux), with the same flow and `DRY_RUN=1` (which also runs on macOS to test the flow). Sources in order: distro apt, vendor apt repos or checksummed .debs (Signal, Mullvad, Proton VPN, Proton's `version.json` feeds with SHA-512), vendor install scripts (Tailscale, Claude Code, Codex, OpenCode, Hermes, Ollama), Flathub only for publisher-verified apps (Element is the labelled exception). Anything else becomes a next step with its download page.

Both scripts source `shared/setup/common.sh` (prompt parsing, sudo keepalive, summary, bookmarks file, and the vibe-coding step that clones `git.juntogroups.org/public-repos/vibe-coding` beside this repo and symlinks rules/skills/agents without overwriting existing files). Change shared behaviour there, OS-specific package lists in each script. Both have a DFP (Digital Force Protection) menu based on Irregularpedia's Quick DFP guide and Privacy Guides.

OS hardening lives in `macos/harden.sh` and `linux/harden.sh` (alias `harden`). With no arguments they only read and report PASS/FAIL/MANUAL/INFO per control; `--apply` fixes the scriptable ones and re-checks each. macOS controls map to NIST mSCP macOS 27 / CIS levels; anything macOS only honours via a profile or System Settings is reported MANUAL, never claimed. Linux follows CIS Debian 13 / Ubuntu 24.04, KSPP and ssh-audit, writes only `*dotfiles-hardening*` drop-ins, validates sshd/sudoers before they take effect, and deliberately skips settings that break Flatpak, snaps, Docker or IPv6. SSH is only switched to keys-only when `~/.ssh/authorized_keys` exists. The setup scripts call `--apply` and copy FAIL/MANUAL lines into their summary.

---

## Secrets (`secret`: sops + age)

`shared/bin/secret` keeps API keys and `.env` values encrypted in a store (`$SECRETS_DIR`, default `~/Git/secrets`) that belongs in a **private** repo or Syncthing folder, never in this public repo. Values are decrypted only into the one command that needs them.

- **Store:** `devices.txt` (one `name age1…` per device), a generated `.sops.yaml`, and `<profile>.env` files (dotenv; values encrypted, key names readable, so `git diff` stays useful).
- **Device keys:** one standard age X25519 key per device, in the macOS Keychain, the Linux Secret Service (GNOME Keyring/KeePassXC via `secret-tool`), or `~/.config/sops/age/keys.txt` (600) on headless machines. `init` records the backend it used in `~/.config/sops/age/backend`, and falls back to the file if the keyring can't store it.
  - Not Secure Enclave keys: sops 3.13 can't encrypt to `age1tag`/`age1se` recipients without a plugin that only exists for macOS, so Linux devices couldn't add devices or edit.
- **Values never on disk or argv:**
  - the Keychain is written via `security -i` on stdin;
  - `import` and `set` encrypt from stdin;
  - `run` exports in-process and then `exec`s, reading via process substitution because bash writes here-strings to temp files;
  - the one exception is `secret edit`, which uses sops' private temp file.
- **Commands:** `init`, `pubkey`, `devices`, `add-device NAME KEY` (re-encrypts everything), `remove-device NAME` (re-encrypts, then rotate values), `reencrypt`, `import PROFILE FILE`, `set`/`unset PROFILE KEY`, `edit`, `list [PROFILE]` (names only), `get PROFILE KEY`, `run P1[,P2] -- cmd`, `env PROFILE` (for sourced loaders; refuses a terminal), `codex-keyring`, `doctor`.
- **New device:** run `secret init` there and share its public key, then run `secret add-device NAME KEY` on a device that can already decrypt.

How each tool should get its credentials:

| Tool | Do this |
|---|---|
| Claude Code, subscription | macOS: nothing (Keychain). Linux: `claude setup-token`, then `secret set ai CLAUDE_CODE_OAUTH_TOKEN`, and start it with `secret run ai -- claude`. |
| Claude Code, API key | `apiKeyHelper: "secret get ai ANTHROPIC_API_KEY"` in `~/.claude/settings.json`. Opt-in only: it outranks the subscription login, so it switches billing to the API. |
| `claude-switch` / `cc-*` | Settings stay in `~/.claude-backends.env`. Tokens move to the profiles `claude` (e.g. `LOCAL_AUTH_TOKEN`) and `vibe` (`LITELLM_MASTER_KEY`), which `claude-switch` overlays when they exist. |
| Codex | `secret codex-keyring` (sets `cli_auth_credentials_store = "keyring"`, with a backup), then log in again. |
| Vibe, OpenCode, AWS, any `.env` | `secret run PROFILE -- tool`. For OpenCode, don't save an account in the app (it outranks env vars). |

Both setup scripts install sops and age (Linux: pinned sops release, checked against its sha256 list) and offer `secret init`. Both `harden.sh` scripts list plaintext credential files with the right migration route for each. `.stignore` keeps `.env` files, keys and backups out of Syncthing: this repo folder is synced, and Syncthing ignores `.gitignore`.

## Tests

`tests/run.sh` (`-v` prints failing output) checks: every script parses in bash and zsh, the repo `.zshrc` starts silently and re-sources cleanly over old aliases, every `.zsh_*` loads in bash (Linux loader), `dots --lint` is empty, `git wip` refusals and index restore, `git-inventory` detection and redaction, `ssh-doctor` failure paths, the Linux sysctl and SSH-lockout logic against fakes, `harden.sh --check`, and both setup dry runs. It works in a scratch dir with its own git config and never touches `$HOME`. CI (`.github/workflows/tests.yml`) runs it on macOS and Ubuntu on every push, which is the only place `linux/harden.sh --check` and the Linux setup run on real Linux. Run it before pushing; add a test (and see it fail on the broken code) when you fix a bug.

## Workstation tools (git, SSH, tmux, Tailscale)

| Tool | Where | Does |
|---|---|---|
| `git-inventory` / `git inventory` | `shared/bin/git-inventory` | Per repository under `~/Git` and `~/Code`: commits on no remote (per branch), stashes, uncommitted files per checkout incl. linked worktrees anywhere, remotes (credentials redacted). Read-only (`GIT_OPTIONAL_LOCKS=0`). `--attention`, `--fetch`, `--ignored`, `--json FILE` (mode 600). Exit 1 if anything needs attention. Run before migrating or wiping a machine. |
| `git wip [msg]` | `shared/bin/git-wip` | `add -A`, commit `wip: …`, push. Refuses (and restores the index exactly) when staged names look like secrets (.env, keys, keystores) or added lines contain AWS/GitHub/GitLab/Slack/Anthropic/OpenAI/PEM shapes. Hooks run. `--dry-run`, `--no-push`. |
| `shared/.gitconfig` | included last from `~/.gitconfig` | Aliases `wip`/`inventory`, per-forge identity via `includeIf hasconfig:remote.*.url` (`~/.gitconfig-github`, `~/.gitconfig-gitlab`), LFS. No identity, credential helpers or paths: those stay machine-local. |
| `git_sign_setup [key.pub]` | `.zsh_git` | SSH commit/tag signing + `allowed_signers`. |
| `shared/ssh/config.template` | copied to `~/.ssh/config` only if absent | `Include ~/.ssh/config.d/*.conf`, `IgnoreUnknown UseKeychain` first (Linux), `ForwardAgent no`, keep-alives, ControlMaster sockets in `~/.ssh/sockets/%C`. |
| `ssh-doctor [host]` | `.zsh_network` | Permissions as ssh enforces them, config parses, agent has keys, `IdentitiesOnly yes` with missing IdentityFile; with a host, resolved settings + key-only login test. `SSH_DOCTOR_CONFIG=file` checks another config. |
| `ts-expiry [days]` | `.zsh_network` | This machine's and peers' Tailscale key expiry (online/offline, last seen). Finds the CLI inside Tailscale.app too. |
| `tm [name]` | `.zsh_utils` | `tmux new -A -s main`; config in `shared/tmux/.tmux.conf` (copied only if absent). tmux and mosh are installed by both setup scripts. |

Both setup scripts run `setup_shell_tools` (in `shared/setup/common.sh`) for the SSH/tmux/git pieces; both `harden.sh` scripts report backups (Time Machine age on macOS; scheduled restic/borg/Timeshift/… on Linux, reported as INFO since recency needs the tool's credentials).

## Finding commands (`dots`)

`dots` (in `shared/zsh/.zsh_functions`) indexes every function and alias in the loaded `~/.zsh_*` files plus `claude-aliases.zsh`, straight from the source, so it never goes stale:

| Command | Does |
|---|---|
| `dots` | overview and categories (one per file: shell, git, docker, files, encryption, network, ...) |
| `dots <words>` | search names, alias targets and descriptions (all words must match) |
| `dots -s <name>` | description, usage, file:line and the loaded source; Tab completes names with descriptions |
| `dots -c <category>` / `dots -l` | list a category / everything |
| `dots -i` | fzf picker; Enter puts the command on the prompt |
| `dots --lint` | commands with no description (keep this empty, except `claude-aliases.zsh`) |

Conventions it relies on (keep them when adding code):
- Every user-facing function gets a one-line `# description` directly above it; aliases get a trailing `# description` (an alias to a documented function inherits its description). The first comment line is the summary; section banners (`# -----`) and short headings ("Git aliases") are ignored.
- Names starting with `_` are internal and hidden; functions nested in other functions are skipped.
- Don't shadow real commands except deliberate wrappers (`ls`, `grep`, `du`, `df`, `mkdir`). `reset` and `pyenv` were removed for that reason (`reset_file`, `venv`); `gs` (git status) still hides Ghostscript, so code calls `command gs`.
- These files are also sourced by bash on Linux: keep syntax bash-compatible or guard zsh-only parts with `[[ -n "$ZSH_VERSION" ]]` and `eval`.

## Related Docs

| File | What it covers |
|---|---|
| `ansible/USAGE_GUIDE.md` | Step-by-step playbook invocations + troubleshooting |
| `ansible/ANSIBLE_REVIEW_AND_PLAN.md` | Architecture notes |
| `ansible/SERVICE_AUDIT.md`, `SERVICE_STATUS_AUDIT.md` | Service-by-service state |
| `ansible/DOCKER_COMPOSE_FIX.md` | Compose-specific incident history |
| `docs/` | Older guides — sift for relevance, some are stale |

## Cross-References

- Claude skill: `~/.claude/skills/host-upgrades/SKILL.md` — invoke this skill when about to run ansible against a host
- Global rule: `~/.claude/rules/remote-ops-safety.md` — ARP test, IPv6 LLA SSH, multi-VPN routing
- Global rule: `~/.claude/rules/docker-ops.md` — IPAM all-or-none, restart vs up -d
- Sibling tooling: `~/Git/ai-coding-env/scripts/` — SSH-driven ops for the colo fleet (separate from this ansible)
