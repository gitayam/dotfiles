# Ansible Configuration Review and Improvement Plan

**Generated:** 2025-09-29
**Test Target:** root@100.107.228.108

---

## Executive Summary

The Ansible setup is comprehensive but has several critical issues that need fixing before safe deployment. The playbook includes excellent features (system updates, hardening, Docker management, service-specific updates) but has configuration problems, potential security risks, and usability issues.

---

## Critical Issues Found

### 1. **CRITICAL: SSH Hardening Will Lock You Out**
**File:** `system_management.yml:742`

```yaml
- { regexp: '^#?PermitRootLogin', line: 'PermitRootLogin no' }
```

**Problem:** This will immediately disable root login, but:
- All inventory hosts use `ansible_user: root`
- No non-root users are configured first
- Will lock you out of all servers

**Impact:** ⚠️ **WILL BREAK SSH ACCESS**

---

### 2. **Missing Custom Vars File Check**
**File:** `system_management.yml:20`

```yaml
custom_vars: "{{ lookup('file', 'inventory/custom/vars.yaml') | from_yaml }}"
```

**Problem:**
- No validation that file exists
- Will fail immediately if `inventory/custom/vars.yaml` doesn't exist
- Error message unclear

**Impact:** Playbook won't run without proper setup

---

### 3. **Inventory Configuration Issues**

**Current Inventories:**
- `tailscale.yml` - Uses Tailscale hostnames (100.x.x.x IPs)
- `local_network.yml` - Uses local network IPs (192.168.x.x)

**Problems:**
- No test server (100.107.228.108) configured
- Hostnames used as ansible_host values (won't resolve)
- No unified inventory approach

---

### 4. **Service Tag Logic Confusion**
**File:** `system_management.yml:39-54`

```yaml
service_tag_host_map:
  authentik: "irregularchat-information"
  researchtools: "proxmox-main"
```

**Problem:**
- Complex host selection logic
- Debugging output but not properly utilized
- Confusing for users

---

### 5. **Dangerous SSH Hardening Settings**
**File:** `system_management.yml:744-765`

Multiple settings that will break functionality:
```yaml
- { regexp: '^#?AllowTcpForwarding', line: 'AllowTcpForwarding no' }  # Breaks tunneling
- { regexp: '^#?TCPKeepAlive', line: 'TCPKeepAlive no' }              # Connection issues
```

---

### 6. **Package Installation Issues**
**File:** `system_management.yml:380-387`

```yaml
loop:
  - diceware
  - gh
  - kubectl
  - age
  - magic-wormhole
```

**Problem:**
- Many packages don't exist in default repos
- No repo setup first
- Will fail on fresh Ubuntu/Debian

---

### 7. **Inefficient Git Updates**
**File:** `system_management.yml:495-514`

**Problems:**
- Stashes everything without cleanup
- Complex merge logic prone to issues
- No conflict resolution strategy
- No way to skip repos with local changes

---

### 8. **Docker Compose Updates Without Safety**
**File:** `system_management.yml:572-581`

```yaml
docker compose pull && docker compose up -d
```

**Problem:**
- No validation of compose file
- No backup before update
- No rollback mechanism
- Could break running services

---

### 9. **Hardcoded Paths Everywhere**
Examples:
- `/home/researchtoolspy` (line 348)
- `/home/cryptpad/cryptpad` (line 607)
- `/home/vaultwarden` (line 617)
- `/home/authentik/authentik` (line 639)
- `/home/searxng/searxng-docker` (line 654)

**Problem:**
- Not configurable
- Will fail if paths differ
- Should be in inventory or vars

---

### 10. **No Idempotency for Swap Creation**
**File:** `system_management.yml:864`

```yaml
command: dd if=/dev/zero of=/swapfile bs=1M count=2048
```

**Problem:**
- `dd` always reports changed even when not needed
- Could overwrite existing swap
- Should use `creates` parameter

---

## Improvements Needed

### Security Improvements

1. **SSH Hardening Sequence**
   - Create non-root user FIRST
   - Test sudo access
   - THEN disable root login
   - Add --check mode warning

2. **Fail2ban Configuration**
   - More aggressive settings needed
   - Add jail for other services
   - Email notifications

3. **Firewall Rules**
   - Currently only opens basic ports
   - Needs Tailscale port allowance
   - Should close after setup

### Functionality Improvements

4. **Better Error Handling**
   - Validate all file paths before use
   - Check service existence before restart
   - Graceful degradation

5. **Idempotency**
   - Fix swap creation
   - Git stash cleanup
   - Docker operations

6. **Package Management**
   - Add snap/flatpak support
   - Setup third-party repos
   - Optional package groups

7. **Inventory Management**
   - Create unified inventory
   - Add host groups properly
   - Document network types

8. **Service Paths**
   - Move all paths to vars
   - Per-host service configuration
   - Validation before operations

### Usability Improvements

9. **Documentation**
   - Quick start guide
   - Common operations
   - Troubleshooting

10. **Dry Run Support**
    - Better `--check` mode support
    - Show what would change
    - Validation phase

11. **Logging**
    - Structured logging
    - Per-run log files
    - Error summary

12. **Testing**
    - Molecule tests
    - Linting (ansible-lint)
    - Syntax checking script

---

## Recommended Action Plan

### Phase 1: Critical Fixes (MUST DO BEFORE TESTING)

1. ✅ **Fix SSH Hardening**
   - Comment out `PermitRootLogin no`
   - Add warning in comments
   - Create safe hardening task with user creation

2. ✅ **Add Test Server to Inventory**
   - Create test inventory file
   - Add 100.107.228.108
   - Verify connectivity

3. ✅ **Fix Vars Loading**
   - Add file existence check
   - Provide clear error message
   - Create template if missing

4. ✅ **Remove Dangerous Settings**
   - Comment out AllowTcpForwarding no
   - Keep TCPKeepAlive yes
   - Add documentation

### Phase 2: Improvements (CAN DO AFTER TESTING)

5. ⏳ **Move Hardcoded Paths to Vars**
   - Create service_paths dictionary
   - Update all service tasks
   - Document in vars.yaml

6. ⏳ **Improve Git Updates**
   - Add skip option for dirty repos
   - Better conflict handling
   - Cleanup stashes

7. ⏳ **Better Package Installation**
   - Conditional package lists
   - Add repo setup tasks
   - Handle missing packages gracefully

8. ⏳ **Docker Safety**
   - Add compose file validation
   - Create backups before update
   - Add rollback capability

### Phase 3: Testing Procedure

9. ⏳ **Syntax Check**
   ```bash
   ansible-playbook system_management.yml --syntax-check
   ```

10. ⏳ **Dry Run**
    ```bash
    ansible-playbook -i inventory/test.yml system_management.yml \
      -l test-server --check --diff --tags "update"
    ```

11. ⏳ **Limited Test**
    ```bash
    ansible-playbook -i inventory/test.yml system_management.yml \
      -l test-server --tags "update,upgrade,cleanup"
    ```

12. ⏳ **Full Test**
    ```bash
    ansible-playbook -i inventory/test.yml system_management.yml \
      -l test-server --skip-tags "reboot,ssh_hardening"
    ```

---

## Safe Test Command for 100.107.228.108

```bash
# Step 1: Test connectivity
ansible test-server -i inventory/test.yml -m ping

# Step 2: Check syntax
ansible-playbook -i inventory/test.yml system_management.yml --syntax-check

# Step 3: Dry run (see what would change)
ansible-playbook -i inventory/test.yml system_management.yml \
  -l test-server --check --diff --tags "update,upgrade,cleanup"

# Step 4: Actual run (safe tags only)
ansible-playbook -i inventory/test.yml system_management.yml \
  -l test-server --tags "update,upgrade,cleanup" \
  --skip-tags "ssh_hardening,reboot"
```

---

## Files That Need Changes

### Create New:
1. `inventory/test.yml` - Test server inventory
2. `inventory/custom/vars.yaml` (if missing) - From template
3. `ansible/README.md` - Usage documentation
4. `ansible/test-playbook.sh` - Safe testing script

### Modify:
1. `system_management.yml` - Fix critical issues
2. `ansible.cfg` - Add better defaults
3. `inventory/custom/vars.yaml` - Add service paths

---

## Priority Ranking

| Priority | Item | Risk if Not Fixed | Effort |
|----------|------|-------------------|--------|
| 🔴 P0 | SSH hardening lockout | CRITICAL - Will lock you out | Low |
| 🔴 P0 | Test inventory creation | HIGH - Can't test safely | Low |
| 🔴 P0 | Vars file validation | HIGH - Playbook won't run | Low |
| 🟡 P1 | Remove dangerous SSH settings | MEDIUM - Connection issues | Low |
| 🟡 P1 | Package installation fixes | MEDIUM - Tasks will fail | Medium |
| 🟢 P2 | Hardcoded paths | LOW - Works if paths match | High |
| 🟢 P2 | Git update improvements | LOW - Current works mostly | Medium |
| 🟢 P3 | Documentation | LOW - Usability issue | Low |

---

## Conclusion

The playbook is well-structured and comprehensive but **MUST NOT BE RUN** in its current state without fixes. The SSH hardening alone will lock you out of all servers.

**Recommendation:** Implement Phase 1 fixes immediately, then test carefully on 100.107.228.108 with limited tags before any production use.

---

**Next Steps:**
1. Apply Phase 1 fixes (see detailed fixes below)
2. Create test inventory
3. Test on 100.107.228.108
4. Review results
5. Implement Phase 2 improvements