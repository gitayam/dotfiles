# Ansible System Management Usage Guide

## Quick Setup

Your `ansible.cfg` is now configured to use the Tailscale inventory by default:
```bash
inventory = inventory/tailscale.yml
remote_user = root
```

## Current Inventory

**Available hosts:**
- `proxmox-main` (online ✓)
- `irregularchat-information` (offline ✗)

## Command Categories

### 1. System Updates

```bash
# Update package repositories only
ansible-playbook system_management.yml -l proxmox-main --tags update

# Full system upgrade (update + upgrade + cleanup)
ansible-playbook system_management.yml -l proxmox-main --tags 'update,upgrade,cleanup'

# Security updates only
ansible-playbook system_management.yml -l proxmox-main --tags security

# Check if reboot needed
ansible-playbook system_management.yml -l proxmox-main --tags maintenance
```

### 2. Git Repository Updates

```bash
# Update all Git repositories on a host
ansible-playbook system_management.yml -l proxmox-main --tags git

# The git task will:
# - Find all .git directories under /home (excluding /home/discourse)
# - Fetch updates
# - Attempt fast-forward pull
# - Fall back to rebase if needed
# - Fall back to merge if rebase fails
# - Set up branch tracking if missing
```

### 3. Docker Updates

```bash
# Quick update single Docker Compose service (FASTEST - recommended!)
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/researchtoolspy'

# Update all Docker Compose services (WARNING: 47 services, takes 30+ minutes!)
ansible-playbook system_management.yml -l proxmox-main --tags docker_compose_update

# Update all Docker images (WARNING: 143 images, takes hours!)
ansible-playbook system_management.yml -l proxmox-main --tags docker

# Dry run to see what would be found
ansible-playbook system_management.yml -l proxmox-main --tags docker_compose_update --check
```

**Recommended workflow:**
```bash
# Update specific services you care about using docker_quick
ansible-playbook system_management.yml -l proxmox-main --tags docker_quick \
  -e 'compose_path=/home/vaultwarden'

# Or use service-specific tags (even faster)
ansible-playbook system_management.yml -l proxmox-main --tags vaultwarden
```

### 4. Custom Commands (NEW!)

#### a. Send Files with rsync

```bash
# Send a single file
ansible-playbook system_management.yml -l proxmox-main --tags send \
  -e 'src_path=/Users/sac/myfile.txt dest_path=/root/myfile.txt'

# Send a directory
ansible-playbook system_management.yml -l proxmox-main --tags send \
  -e 'src_path=/Users/sac/backups/ dest_path=/var/backups/'

# Features:
# - Uses rsync with compression and checksums
# - Shows progress and stats
# - Creates destination directories automatically
# - Validates source exists before transfer
```

#### b. Execute Custom Commands

```bash
# Run a simple command
ansible-playbook system_management.yml -l proxmox-main --tags custom_command \
  -e 'command="systemctl status docker"'

# Check disk space
ansible-playbook system_management.yml -l proxmox-main --tags custom_command \
  -e 'command="df -h"'

# Run on multiple hosts
ansible-playbook system_management.yml -l my_servers --tags custom_command \
  -e 'command="uptime"'

# Complex command with quotes
ansible-playbook system_management.yml -l proxmox-main --tags custom_command \
  -e 'command="docker ps --format \"table {{.Names}}\t{{.Status}}\""'
```

#### c. Run Custom Scripts

```bash
# Run a local script on remote host
ansible-playbook system_management.yml -l proxmox-main --tags run_script \
  -e 'script_path=./maintenance.sh'

# Run script with arguments
ansible-playbook system_management.yml -l proxmox-main --tags run_script \
  -e 'script_path=./backup.sh script_args="--verbose --compress"'

# Features:
# - Validates script exists locally before transfer
# - Copies to /tmp on remote host
# - Makes executable
# - Cleans up after execution
# - Shows stdout/stderr and exit code
```

### 5. Service-Specific Updates

```bash
# Update specific services
ansible-playbook system_management.yml -l proxmox-main --tags researchtools
ansible-playbook system_management.yml -l proxmox-main --tags vaultwarden
ansible-playbook system_management.yml -l proxmox-main --tags authentik
ansible-playbook system_management.yml -l proxmox-main --tags searxng
ansible-playbook system_management.yml -l irregularchat-information --tags cryptpad

# Update all services from services.yaml inventory
ansible-playbook system_management.yml --tags allservices
```

## Host Selection Options

```bash
# Single host
ansible-playbook system_management.yml -l proxmox-main --tags <tag>

# Multiple hosts
ansible-playbook system_management.yml -l 'proxmox-main,irregularchat-information' --tags <tag>

# Group of hosts
ansible-playbook system_management.yml -l my_servers --tags <tag>

# All hosts
ansible-playbook system_management.yml --tags <tag>

# All except one
ansible-playbook system_management.yml -l 'all:!irregularchat-information' --tags <tag>
```

## Common Workflows

### Daily Maintenance
```bash
# Update everything on proxmox-main
ansible-playbook system_management.yml -l proxmox-main \
  --tags 'update,upgrade,git,docker_compose_update,cleanup'
```

### Quick Docker Service Updates
```bash
# Just update compose services (fastest)
ansible-playbook system_management.yml -l proxmox-main \
  --tags docker_compose_update
```

### Deploy a Configuration File
```bash
# Send config file to remote host
ansible-playbook system_management.yml -l proxmox-main --tags send \
  -e 'src_path=./nginx.conf dest_path=/etc/nginx/nginx.conf'

# Then restart nginx
ansible-playbook system_management.yml -l proxmox-main --tags custom_command \
  -e 'command="systemctl restart nginx"'
```

### Health Check
```bash
# Check all services
ansible-playbook system_management.yml -l proxmox-main --tags custom_command \
  -e 'command="docker ps --filter status=exited"'
```

## Tips

1. **Use `--check` for dry runs:**
   ```bash
   ansible-playbook system_management.yml -l proxmox-main --tags upgrade --check
   ```

2. **View available tags without running:**
   ```bash
   ansible-playbook system_management.yml --list-tags
   ```

3. **Test connectivity first:**
   ```bash
   ansible all -m ping
   ```

4. **Fix irregularchat-information offline issue:**
   - SSH into the host and restart Tailscale
   - Or update inventory to use IP instead of hostname

5. **Avoid the 143 Docker images issue:**
   - Use `docker_compose_update` instead of `docker` tag
   - Or manually specify which images to update
   - Consider cleaning up unused images first

## Troubleshooting

### Host Unreachable
```bash
# Check Tailscale status
tailscale status

# Test SSH connection
ssh root@proxmox-main

# Ping test
ansible proxmox-main -m ping
```

### Permission Denied
```bash
# Add sudo password
ansible-playbook system_management.yml -l proxmox-main --tags <tag> --ask-become-pass
```

### Inventory Issues
```bash
# List all hosts
ansible-inventory --list

# Show specific host details
ansible-inventory --host proxmox-main
```

## Next Steps

1. Fix `irregularchat-information` Tailscale connectivity
2. Clean up unused Docker images on proxmox-main (143 images!)
3. Consider creating separate playbooks for:
   - Daily maintenance (light updates)
   - Weekly maintenance (full updates + cleanup)
   - Monthly maintenance (deep cleaning + security)
