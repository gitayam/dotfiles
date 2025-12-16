# Service Audit for test-server (100.107.228.108)

**Generated:** 2025-09-30
**Server:** root@100.107.228.108

---

## Running Docker Services

| Service Name | Image | Directory |
|--------------|-------|-----------|
| matrix-* | Various | (Matrix Ansible managed) |
| funkwhale | funkwhale/all-in-one | /home/funkwhale |
| readarr | ghcr.io/hotio/readarr | /home/torrent |
| lidarr | lscr.io/linuxserver/lidarr | /home/torrent |
| qbittorrent | lscr.io/linuxserver/qbittorrent | /home/torrent |
| prowlarr | lscr.io/linuxserver/prowlarr | /home/torrent |
| mullvad-vpn | ghcr.io/qdm12/gluetun | /home/torrent |
| jellyseerr | fallenbagel/jellyseerr | /home/torrent |
| bazarr | lscr.io/linuxserver/bazarr | /home/torrent |
| radarr | lscr.io/linuxserver/radarr | /home/torrent |
| sonarr | lscr.io/linuxserver/sonarr | /home/torrent |
| flaresolverr | ghcr.io/flaresolverr/flaresolverr | /home/torrent |
| clamav | clamav/clamav | (System-wide) |
| peertube-* | pomerium/pomerium, chocobozzz/peertube | /home/PeerTube |
| vaultwarden | vaultwarden/server | /home/vaultwarden |
| authentik-* | ghcr.io/goauthentik/server:2025.8.3 | /home/authentik |
| system-pgadmin | dpage/pgadmin4 | /home/postgres-system |

---

## Services with Docker Compose Files

Found 21 services with docker-compose files:

1. /home/archive - Archive service
2. /home/audiobookshelfuser - Audiobook management
3. /home/authentik - Identity provider (SSO)
4. /home/calibre-web - E-book management
5. /home/chat-based-community-dashboard - Chat dashboard
6. /home/forgejo - Git forge (Gitea fork)
7. /home/funkwhale - Music streaming
8. /home/headscale - Tailscale control server
9. /home/infisical - Secret management
10. /home/jellyfin - Media server
11. /home/linkwarden - Bookmark manager
12. /home/mariadb-system - Database server
13. /home/mediawiki - Wiki platform
14. /home/Muse_and_Co - Custom service
15. /home/PeerTube - Video platform
16. /home/postgres-system - PostgreSQL database
17. /home/researchtoolspy - Research tools
18. /home/rstudio - RStudio server
19. /home/simplelogin-app - Email alias service
20. /home/syncthing - File sync service
21. /home/torrent - Torrent suite (Arr stack)

---

## Services with Git Repositories

Many services have git repos for source control:
- /home/researchtoolspy
- /home/links/chhoto-url
- /home/linkwarden
- /home/Muse_and_Co
- /home/authentik/authentik_dir (NOT /home/authentik/authentik!)
- /home/cryptpad/cryptpad
- /home/discourse/discourse (huge - 300+ plugins)
- /home/full-stack-invite/Full-Stack-Chat
- And many more...

---

## Issues Found in Ansible Playbook

### 1. Wrong Path for Authentik
**Current:** `/home/authentik/authentik`
**Correct:** `/home/authentik`

### 2. Wrong Host Conditions
**Current:** `when: inventory_hostname == 'proxmox-main'`
**Should be:** Dynamic or configurable

### 3. Missing Services
Services that should have update tasks but don't:
- funkwhale
- jellyfin
- peertube
- forgejo
- headscale
- infisical
- linkwarden
- simplelogin-app
- syncthing
- torrent (Arr stack)
- mediawiki
- calibre-web
- audiobookshelf
- rstudio

### 4. Cryptpad Service Not Running
- Cryptpad has git repo at `/home/cryptpad/cryptpad`
- But no docker container running
- Uses PM2 process manager
- Not on test-server

### 5. Searxng Service Not Running
- Path `/home/searxng/searxng-docker` doesn't exist on test-server
- Not on this server

---

## Recommendations

### 1. Create Service Variables File
Create `/home/ansible/inventory/custom/services.yaml`:
```yaml
services:
  authentik:
    path: /home/authentik
    update_method: docker-compose
    enabled: true
  funkwhale:
    path: /home/funkwhale
    update_method: docker-compose
    enabled: true
  # ... etc
```

### 2. Generic Service Update Task
Instead of hardcoded tasks, create a generic loop:
```yaml
- name: Update Docker Compose services
  shell: |
    cd {{ item.path }}
    docker compose pull
    docker compose up -d
  loop: "{{ services | dict2items }}"
  when: item.value.enabled and item.value.update_method == 'docker-compose'
```

### 3. Per-Host Service Mapping
Use inventory to define which services run on which host:
```yaml
test-server:
  services: [authentik, funkwhale, vaultwarden, jellyfin, peertube, ...]
proxmox-main:
  services: [researchtools, vaultwarden, searxng, ...]
```

### 4. Fix Path Issues
- Correct Authentik path
- Check all paths exist before operations
- Add validation tasks

---

## Priority Actions

1. ✅ Fix git dubious ownership (DONE)
2. ⏳ Fix Authentik path from `/home/authentik/authentik` → `/home/authentik`
3. ⏳ Make host conditions dynamic
4. ⏳ Add missing services to update tasks
5. ⏳ Create service inventory/variables
6. ⏳ Test on test-server with corrected paths

---

## Next Steps

1. Update `system_management.yml` with correct paths
2. Create service inventory file
3. Add generic service update tasks
4. Test selective service updates
5. Document per-service update procedures

---

**End of Service Audit**