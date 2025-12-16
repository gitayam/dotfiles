#!/usr/bin/env bash
# Safe Ansible Playbook Testing Script
# Tests the system_management.yml playbook against test server 100.107.228.108

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INVENTORY="inventory/test.yml"
PLAYBOOK="system_management.yml"
TEST_HOST="test-server"
TEST_IP="100.107.228.108"

# Print colored message
print_msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Print section header
print_header() {
    echo ""
    print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_msg "$BLUE" "$1"
    print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Run command with logging
run_step() {
    local description=$1
    shift
    print_msg "$YELLOW" "▶ $description"
    if "$@"; then
        print_msg "$GREEN" "✓ $description succeeded"
        return 0
    else
        print_msg "$RED" "✗ $description failed"
        return 1
    fi
}

# Main script
main() {
    print_header "Ansible Playbook Safety Testing Suite"
    print_msg "$YELLOW" "Target: $TEST_HOST ($TEST_IP)"
    echo ""

    # Step 1: Verify we're in the ansible directory
    print_header "Step 1: Environment Check"
    if [[ ! -f "$PLAYBOOK" ]]; then
        print_msg "$RED" "Error: $PLAYBOOK not found!"
        print_msg "$YELLOW" "Please run this script from the ansible directory"
        exit 1
    fi
    print_msg "$GREEN" "✓ Found $PLAYBOOK"

    if [[ ! -f "$INVENTORY" ]]; then
        print_msg "$RED" "Error: $INVENTORY not found!"
        exit 1
    fi
    print_msg "$GREEN" "✓ Found $INVENTORY"

    # Step 2: Check Ansible installation
    print_header "Step 2: Ansible Installation Check"
    if ! command -v ansible-playbook &> /dev/null; then
        print_msg "$RED" "Error: ansible-playbook not found!"
        print_msg "$YELLOW" "Install with: brew install ansible"
        exit 1
    fi
    ansible_version=$(ansible-playbook --version | head -1)
    print_msg "$GREEN" "✓ $ansible_version"

    # Step 3: Test connectivity
    print_header "Step 3: Connectivity Test"
    if ! run_step "Testing SSH connectivity to $TEST_IP" \
        ansible $TEST_HOST -i $INVENTORY -m ping; then
        print_msg "$RED" "Cannot connect to test server!"
        print_msg "$YELLOW" "Verify:"
        print_msg "$YELLOW" "  1. Server is running"
        print_msg "$YELLOW" "  2. Tailscale is connected"
        print_msg "$YELLOW" "  3. SSH key is authorized"
        print_msg "$YELLOW" "  4. Try: ssh root@$TEST_IP"
        exit 1
    fi

    # Step 4: Syntax check
    print_header "Step 4: Syntax Validation"
    run_step "Checking playbook syntax" \
        ansible-playbook $PLAYBOOK --syntax-check || exit 1

    # Step 5: Dry run (check mode) - Safe tags only
    print_header "Step 5: Dry Run (Check Mode)"
    print_msg "$YELLOW" "This will show what WOULD change without making changes"
    print_msg "$YELLOW" "Tags: update, upgrade, cleanup (SAFE)"
    echo ""

    if run_step "Running dry-run with safe tags" \
        ansible-playbook -i $INVENTORY $PLAYBOOK \
            -l $TEST_HOST \
            --check \
            --diff \
            --tags "update,upgrade,cleanup" \
            --skip-tags "ssh_hardening,reboot,firewall"; then
        echo ""
        print_msg "$GREEN" "Dry run completed successfully!"
    else
        print_msg "$RED" "Dry run failed!"
        exit 1
    fi

    # Step 6: Ask for confirmation before actual run
    print_header "Step 6: Confirmation"
    print_msg "$YELLOW" "About to run playbook with SAFE tags on $TEST_IP"
    print_msg "$YELLOW" "Tags that will run: update, upgrade, cleanup, maintenance"
    print_msg "$RED" "Tags that will be SKIPPED: ssh_hardening, reboot, firewall"
    echo ""
    print_msg "$BLUE" "Do you want to proceed with the actual run? (yes/no)"
    read -r response

    if [[ "$response" != "yes" ]]; then
        print_msg "$YELLOW" "Aborted by user"
        exit 0
    fi

    # Step 7: Actual run with safe tags
    print_header "Step 7: Actual Playbook Run (Safe Tags Only)"
    if run_step "Running playbook with safe tags" \
        ansible-playbook -i $INVENTORY $PLAYBOOK \
            -l $TEST_HOST \
            --tags "update,upgrade,cleanup,maintenance" \
            --skip-tags "ssh_hardening,reboot,firewall"; then
        print_msg "$GREEN" "✓ Playbook completed successfully!"
    else
        print_msg "$RED" "✗ Playbook failed!"
        print_msg "$YELLOW" "Check the output above for errors"
        exit 1
    fi

    # Step 8: Post-run connectivity test
    print_header "Step 8: Post-Run Connectivity Test"
    if run_step "Testing connectivity after playbook run" \
        ansible $TEST_HOST -i $INVENTORY -m ping; then
        print_msg "$GREEN" "✓ Server is still accessible"
    else
        print_msg "$RED" "✗ Cannot connect to server after playbook run!"
        print_msg "$RED" "This is CRITICAL - SSH may have been misconfigured"
        exit 1
    fi

    # Summary
    print_header "Testing Complete!"
    print_msg "$GREEN" "✓ All tests passed successfully"
    print_msg "$BLUE" "Server $TEST_IP is ready for more extensive testing"
    echo ""
    print_msg "$YELLOW" "Next steps:"
    print_msg "$YELLOW" "  1. Review changes on the server"
    print_msg "$YELLOW" "  2. Test additional tags if needed"
    print_msg "$YELLOW" "  3. Consider running with more tags: docker, git, monitoring"
    echo ""
}

# Run main function
main "$@"