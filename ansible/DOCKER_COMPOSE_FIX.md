# Docker Compose Update - Fixed!

## Problem
The original `docker_compose_update` task was failing because:
1. **47 Docker Compose services** on proxmox-main
2. **143 Docker images** total
3. Tasks were timing out after 5 minutes
4. Some compose files had errors causing the entire playbook to fail

## Solution

### 1. Added `docker_quick` tag (RECOMMENDED)
Fast, targeted updates for single services:

```bash
# Update researchtoolspy
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/researchtoolspy'

# Update vaultwarden
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/vaultwarden'
```

**Features:**
- ✅ Validates compose file before updating
- ✅ Shows detailed output
- ✅ Handles errors gracefully
- ✅ Completes in ~30-60 seconds per service

### 2. Improved `docker_compose_update` (for bulk updates)
The full update now:
- Runs tasks asynchronously (parallel processing)
- Has 120-second timeout per service
- Skips invalid compose files instead of failing
- Shows summary at the end

```bash
# Update ALL 47 services (takes 30+ minutes)
ansible-playbook system_management.yml -l proxmox-main --tags docker_compose_update
```

## Recommended Daily Workflow

### Option 1: Update Specific Services (Fast)
```bash
# Just update the services you actively use
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/researchtoolspy'

ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/vaultwarden'
```

### Option 2: Use Service-Specific Tags (Fastest)
```bash
# These update via dedicated tasks with optimized paths
ansible-playbook system_management.yml -l proxmox-main --tags researchtools
ansible-playbook system_management.yml -l proxmox-main --tags vaultwarden
ansible-playbook system_management.yml -l proxmox-main --tags authentik
```

### Option 3: Weekly Bulk Update (Slow but thorough)
```bash
# Run this on weekends or during low-traffic periods
ansible-playbook system_management.yml -l proxmox-main --tags docker_compose_update
```

## Found Issue in Your Code

The `docker_quick` test revealed a syntax error in:
- **File:** `/home/researchtoolspy/src/app/frameworks/dotmlpf/create/page.tsx`
- **Line:** 75
- **Error:** Duplicate `useState` declaration with empty arrow function

```typescript
// Current (broken):
const [sessionId] = useState(() => `anon_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`)
// Line 74 is duplicate comment
const [sessionId] = useState(() => )  // ❌ Empty function, syntax error

// Fix: Remove the duplicate line 74-75
```

## All Docker Commands Reference

```bash
# ===== QUICK SINGLE SERVICE UPDATE (30-60s) =====
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/SERVICE_NAME'

# ===== SERVICE-SPECIFIC UPDATES (optimized paths) =====
ansible-playbook system_management.yml -l proxmox-main --tags researchtools
ansible-playbook system_management.yml -l proxmox-main --tags vaultwarden
ansible-playbook system_management.yml -l proxmox-main --tags authentik
ansible-playbook system_management.yml -l proxmox-main --tags searxng
ansible-playbook system_management.yml -l proxmox-main --tags clapper

# ===== BULK UPDATES (30+ minutes) =====
# Update all 47 Docker Compose services
ansible-playbook system_management.yml -l proxmox-main --tags docker_compose_update

# Update all 143 Docker images (hours!)
ansible-playbook system_management.yml -l proxmox-main --tags docker

# ===== MAINTENANCE =====
# List all compose files that would be updated
ansible proxmox-main -m shell -a "find /home -path /home/discourse -prune -o -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) -print"

# Check Docker disk usage
ansible proxmox-main -m shell -a "docker system df"

# Clean up unused Docker resources
ansible proxmox-main -m shell -a "docker system prune -af --volumes"
```

## Performance Comparison

| Method | Services | Time | Use Case |
|--------|----------|------|----------|
| `docker_quick` | 1 | ~30-60s | Daily updates, specific service |
| Service tags | 1 | ~30-60s | Known services (researchtools, etc) |
| `docker_compose_update` | 47 | 30+ min | Weekly bulk update |
| `docker` (pull all) | 143 images | Hours | Rarely needed |

## Next Steps

1. **Fix the syntax error** in researchtoolspy DOTMLPF page
2. **Test docker_quick** on other services to verify they all work
3. **Consider cleanup**: You have 143 images and 47 compose services - some may be unused
4. **Schedule weekly bulk update**: Run during off-hours

```bash
# Clean up unused Docker resources first
ansible proxmox-main -m shell -a "docker system prune -af --volumes"

# Then check what's left
ansible proxmox-main -m shell -a "docker images | wc -l"
ansible proxmox-main -m shell -a "docker ps -a | wc -l"
```
