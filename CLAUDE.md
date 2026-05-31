# Dotfiles — Personal Configs + Ansible Remote Ops

This repo is **dual-purpose**:

1. **Local dev environment** — zsh configs, git aliases, AWS CLI helper functions (33 on macOS / 20 on Linux), Cloudflare file-sharing scripts, Python/TypeScript utilities (`macos/`, `linux/`, `shared/`, `scripts/`, `python/`, `typescript/`, `development/`).
2. **Remote ops automation** — one big Ansible playbook (`ansible/system_management.yml`, 1.5k lines) for system updates, git pulls, Docker image upgrades, and per-service workflows across a small fleet (`ansible/inventory/`).

The two halves are independent. Local install runs `./install.sh` per platform; remote ops runs `ansible-playbook`.

> ⚠️ **This fleet is NOT the same as `ai-coding-env`'s fleet.** This ansible manages home-LAN hosts (`proxmox-main`, `irregularchat-information`, `econ_*`). The johncloud colo Proxmox (`100.87.20.88`), Obelisk (`192.168.1.19`), GCP MX relay (`35.185.0.35`), and Mac mini (`100.76.128.36`) are managed via `~/Git/ai-coding-env/scripts/` (SSH-driven), not by this ansible. If you intend to bring them under ansible, it requires adding inventory + likely a `macos-upgrade.yml` playbook (Homebrew/softwareupdate aren't in `system_management.yml`).

---

## Ansible Quick Reference

**Entry point:** `ansible/system_management.yml` (interactive prompts for host, user, sudo pass — or pass via `-l` / `-e`).

**Inventory** (`ansible/inventory/`):
| File | Hosts | Notes |
|---|---|---|
| `tailscale.yml` | `proxmox-main` (100.107.228.108) | Default — Tailscale-routed |
| `local_network.yml` | `proxmox-main` (192.168.4.222), `irregularchat-information` (192.168.4.4), `econ_proxmox` (192.168.4.164), `econ_matrix` (192.168.4.3) | LAN-direct |
| `proxmox-upgrade.yml` | special-purpose for Proxmox OS upgrades | Different IP — read first before using |
| `custom/services.yaml` | 47 docker-compose services, ~8 disabled | Drives the `docker_compose_update` task |
| `custom/vars.yaml` | `ssh_keys`, `log_path`, `search_path` (default `/home`), `exclude_path` (default `/home/discourse`), `authentik_version` | Required — see `vars.yaml.template` |

**Live state notes** (as of writing): `proxmox-main` is the only consistently online host on Tailscale; `irregularchat-information` has been intermittently offline (DNS-related — see `ansible/USAGE_GUIDE.md`). Verify with `ansible <host> -m ping` before running anything heavy.

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

Interactive sync between `~/.zshrc`/etc. and this repo's `shared/`/`macos/` files:

```bash
./scripts/sync_mac_dotfiles.sh
```

It compares home vs. repo, prompts to overwrite either direction, creates missing files from templates. Doesn't touch anything without confirmation.

The macOS install bootstrap is `macos/install.sh` (Homebrew, taps, casks, Python, Node, AWS CLI). Linux mirror at `linux/install.sh`. Both source `shared/zsh-shared.zsh` so most aliases work cross-platform.

---

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
