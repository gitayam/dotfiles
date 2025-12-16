# Service Status Audit - root@100.107.228.108
**Date**: 2025-09-30
**Purpose**: Identify down/missing services and document fixes needed

## Summary

| Status | Count | Services |
|--------|-------|----------|
| ✅ Running | 19 | See "Running Services" section |
| ❌ Down | 1 | OpenSlides (all containers exited) |
| ⚠️ No Compose File | 4 | archive, chat-based-community-dashboard, Muse_and_Co, researchtoolspy |
| ⚠️ Build-Based | 3 | Muse_and_Co, researchtoolspy, rstudio |
| ⚠️ Standalone Containers | 3 | cryptpad, vaultwarden (running outside compose) |
| ⚠️ Multiple Instances | 1 | outline (3 instances: irregularchat✅, alfaren❌, norequirement✅) |
| ⚠️ Missing from Ansible | 14 | See "Missing from Ansible" section |

## Running Services (19)

### System Services
1. **postgres-system** - Port 5434 (external), 5050 (pgadmin) ✅
2. **mariadb-system** - Port 3308 (external), 8081 (phpmyadmin) ✅

### Application Services
3. **authentik** - Ports 28080, 28443 (SSO/Identity) ✅
4. **audiobookshelfuser** - Port 13378 ✅
5. **calibre-web** - Ports 8015, 8016 ✅
6. **forgejo** - Ports 8003 (web), 2223 (ssh) ✅
7. **funkwhale** - Port 8018 ✅
8. **headscale** - Ports 8017, 9090 ✅
9. **infisical** - Port 8014 ✅
10. **jellyfin** - Dynamic ports (32769, 32771, 32772) ✅
11. **linkwarden** - Internal only (needs postgres-network) ✅
12. **mediawiki** - Port 8989 ✅
13. **PeerTube** - Port 1935, internal 9000 ✅
14. **simplelogin-app** - Port 7777 (app), 20381 (email) ✅
15. **syncthing** - Port 8009, 21027, 22000 ✅

### Torrent Suite (consolidated as 1 service)
16. **torrent** - Multiple containers ✅
   - bazarr (6767)
   - clamav
   - flaresolverr (8191)
   - jellyseerr (5055)
   - lidarr (8686)
   - mullvad-vpn (6881, 8112)
   - prowlarr (9696)
   - qbittorrent
   - radarr (7878)
   - readarr (8788)
   - sonarr (8990)

### Outline Instances
17. **outline/irregularchat_outline** - Port 3001 ✅
18. **outline/norequirement_outline** - Port 3002 ✅

### Standalone Containers (not in compose files shown)
19. **cryptpad** - cryptpad-nginx-proxy, cryptpad-tor-hs ✅
20. **vaultwarden** - Port 180 (localhost only) ✅

## Down Services

### 1. OpenSlides ❌
**Location**: `/home/OpenSlides`
**Status**: All 15 containers exited

**Errors**:
- `connection refused` to port 9012 (autoupdate service)
- `no such host: client` (DNS resolution failure)
- Backend services (auth, backendAction, backendManage, backendPresenter, datastoreReader, datastoreWriter) all exited
- Frontend client exited
- Redis exited
- Proxy exited with code 137 (SIGKILL/OOM)

**Root Cause**: Likely OOM (out of memory) or dependency failures causing cascade

**Fix Required**:
```bash
cd /home/OpenSlides
docker compose down
docker compose up -d
# Monitor logs for:
# - Memory usage
# - Service startup order
# - DNS resolution within containers
```

### 2. Outline/alfaren_outline ❌
**Location**: `/home/outline/alfaren_outline`
**Status**: No containers running
**Fix Required**: `cd /home/outline/alfaren_outline && docker compose up -d`

## Build-Based Services (Not Pre-Built Images)

### 1. researchtoolspy ⚠️
**Location**: `/home/researchtoolspy`
**Type**: Next.js frontend + FastAPI backend
**Ports**: 6781 (frontend), 8000 (api)
**Status**: Not running (requires build)
**Fix**: `cd /home/researchtoolspy && docker compose up -d --build`

### 2. Muse_and_Co ⚠️
**Location**: `/home/Muse_and_Co`
**Type**: Node.js dev server
**Port**: 4480
**Status**: Not running (requires build)
**Fix**: `cd /home/Muse_and_Co && docker compose up -d --build`

### 3. rstudio ⚠️
**Location**: `/home/rstudio`
**Type**: RStudio Server
**Port**: 8787
**Status**: Not running (requires build)
**Fix**: `cd /home/rstudio && docker compose up -d --build`

## Empty/Archived Services

### 1. archive
**Location**: `/home/archive`
**Status**: Empty docker-compose (no services defined)

### 2. chat-based-community-dashboard
**Location**: `/home/chat-based-community-dashboard`
**Status**: Empty docker-compose (no services defined)

## Standalone Services (Outside Standard Compose Files)

### cryptpad
- **Location**: `/home/cryptpad/cryptpad`
- **Containers**: cryptpad-nginx-proxy, cryptpad-tor-hs
- **Status**: Running ✅ (managed via PM2 or separate compose)
- **Note**: Main cryptpad directory has cryptpad subdirectory with actual compose

### vaultwarden
- **Container**: vaultwarden
- **Port**: 127.0.0.1:180
- **Status**: Running ✅
- **Location**: Unknown compose location (running container found)

## Missing from Ansible Playbook

These services have docker-compose files but are NOT in the ansible playbook custom tag:

1. ✅ **audiobookshelfuser** - /home/audiobookshelfuser
2. ✅ **calibre-web** - /home/calibre-web
3. ✅ **forgejo** - /home/forgejo (EXISTS in playbook!)
4. ✅ **funkwhale** - /home/funkwhale
5. ✅ **headscale** - /home/headscale
6. ✅ **infisical** - /home/infisical
7. ✅ **jellyfin** - /home/jellyfin
8. ✅ **linkwarden** - /home/linkwarden
9. ✅ **mediawiki** - /home/mediawiki
10. ✅ **PeerTube** - /home/PeerTube
11. ✅ **simplelogin-app** - /home/simplelogin-app
12. ✅ **syncthing** - /home/syncthing
13. ✅ **torrent** - /home/torrent
14. ✅ **outline** (all 3 instances) - /home/outline/*

## Currently in Ansible Playbook

From `/Users/sac/Git/dotfiles/ansible/system_management.yml`:

1. ✅ **authentik** - `/home/authentik`
2. ✅ **clapper** - `/home/clapper/Claper`
3. ✅ **cryptpad** - `/home/cryptpad`
4. ✅ **researchtoolspy** - `/home/researchtoolspy`
5. ✅ **searxng** - `/home/searxng`
6. ✅ **vaultwarden** - (path unknown)

## Recommended Ansible Improvements

### 1. Create Service Inventory File

Create `/Users/sac/Git/dotfiles/ansible/inventory/custom/services.yaml`:

```yaml
---
docker_compose_services:
  # System databases
  - name: postgres-system
    path: /home/postgres-system
    tags: [postgres, system, database]

  - name: mariadb-system
    path: /home/mariadb-system
    tags: [mariadb, system, database]

  # Authentication & Security
  - name: authentik
    path: /home/authentik
    tags: [authentik, sso, auth, custom]

  - name: vaultwarden
    path: /home/vaultwarden
    tags: [vaultwarden, vault, passwords, custom]

  - name: headscale
    path: /home/headscale
    tags: [headscale, vpn, tailscale, custom]

  # Media Services
  - name: jellyfin
    path: /home/jellyfin
    tags: [jellyfin, media, custom]

  - name: audiobookshelf
    path: /home/audiobookshelfuser
    tags: [audiobookshelf, audiobooks, media, custom]

  - name: funkwhale
    path: /home/funkwhale
    tags: [funkwhale, music, media, custom]

  - name: peertube
    path: /home/PeerTube
    tags: [peertube, video, media, custom]

  - name: torrent
    path: /home/torrent
    tags: [torrent, arr, media, custom]

  # Knowledge & Documentation
  - name: cryptpad
    path: /home/cryptpad
    tags: [cryptpad, docs, custom]

  - name: mediawiki
    path: /home/mediawiki
    tags: [mediawiki, wiki, docs, custom]

  - name: outline-irregularchat
    path: /home/outline/irregularchat_outline
    tags: [outline, docs, wiki, custom]

  - name: outline-alfaren
    path: /home/outline/alfaren_outline
    tags: [outline, docs, wiki, custom]

  - name: outline-norequirement
    path: /home/outline/norequirement_outline
    tags: [outline, docs, wiki, custom]

  - name: calibre-web
    path: /home/calibre-web
    tags: [calibre, books, library, custom]

  # Development & Tools
  - name: forgejo
    path: /home/forgejo
    tags: [forgejo, git, dev, custom]

  - name: researchtoolspy
    path: /home/researchtoolspy
    tags: [research, tools, custom]
    needs_build: true

  - name: rstudio
    path: /home/rstudio
    tags: [rstudio, r, stats, custom]
    needs_build: true

  # Productivity
  - name: clapper
    path: /home/clapper/Claper
    tags: [clapper, clap, presentations, custom]

  - name: openslides
    path: /home/OpenSlides
    tags: [openslides, slides, meetings, custom]

  - name: linkwarden
    path: /home/linkwarden
    tags: [linkwarden, bookmarks, custom]

  - name: infisical
    path: /home/infisical
    tags: [infisical, secrets, custom]

  # Communication
  - name: simplelogin
    path: /home/simplelogin-app
    tags: [simplelogin, email, privacy, custom]

  # Sync & Backup
  - name: syncthing
    path: /home/syncthing
    tags: [syncthing, sync, backup, custom]

  # Search
  - name: searxng
    path: /home/searxng
    tags: [searxng, search, custom]

  # Other
  - name: muse-and-co
    path: /home/Muse_and_Co
    tags: [muse, custom]
    needs_build: true
```

### 2. Update Playbook with Loop

Replace individual service tasks with:

```yaml
- name: Update docker-compose services
  block:
    - name: Load service inventory
      set_fact:
        services: "{{ lookup('file', 'inventory/custom/services.yaml') | from_yaml }}"

    - name: Update docker compose services
      shell: |
        if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
          echo "Updating {{ item.name }}..."
          {% if item.needs_build | default(false) %}
          docker compose pull || true
          docker compose up -d --build
          {% else %}
          docker compose pull
          docker compose up -d
          {% endif %}
        else
          echo "No docker-compose file found in {{ item.path }}"
        fi
      args:
        chdir: "{{ item.path }}"
      loop: "{{ services.docker_compose_services }}"
      when:
        - item.path is defined
        - "'custom' in (item.tags | default([]))"
      tags: "{{ item.tags }}"
      register: service_updates
  tags: [custom, docker]
```

## Action Items

1. ❌ **Fix OpenSlides**: Restart and monitor for OOM/dependency issues
2. ❌ **Fix alfaren outline**: Start containers
3. ⚠️ **Build-based services**: Decide if they should auto-start
4. ✅ **Create services.yaml**: Service inventory for ansible
5. ✅ **Update playbook**: Replace individual tasks with loop
6. ✅ **Test ansible**: Run with custom tag on test server
7. ❌ **Document**: Update SERVICE_AUDIT.md with latest findings

## Notes

- **postgres-network strategy**: Based on LESSONS_LEARNED.md, services should use host gateway method (172.18.0.1:5434) for system-postgres connectivity
- **Cloudflare Tunnel**: Services route via cloudflared.service, not nginx/traefik
- **Port management**: Many services use localhost-only ports, routed through Cloudflare tunnel
- **Build services**: researchtoolspy, Muse_and_Co, rstudio require `--build` flag
- **cryptpad special case**: Has subdirectory structure, main service in /home/cryptpad/cryptpad
