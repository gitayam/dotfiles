#!/bin/bash

# Master test script to run all individual tests
# This script runs each test module and provides a summary

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_MODULES=0
PASSED_MODULES=0
FAILED_MODULES=0

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Bash Functions Comprehensive Test Suite${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to run a test module
run_module_test() {
    local module_name="$1"
    local test_script="$2"
    
    TOTAL_MODULES=$((TOTAL_MODULES + 1))
    
    echo -e "${BLUE}Testing module: $module_name${NC}"
    echo "----------------------------------------"
    
    if bash "$test_script"; then
        echo -e "${GREEN}✓ $module_name tests PASSED${NC}"
        PASSED_MODULES=$((PASSED_MODULES + 1))
        echo ""
        return 0
    else
        echo -e "${RED}✗ $module_name tests FAILED${NC}"
        FAILED_MODULES=$((FAILED_MODULES + 1))
        echo ""
        return 1
    fi
}

# Test all modules
echo "Starting comprehensive bash function tests..."
echo ""

# Core utility functions
run_module_test "Utils" "test_utils.sh"
run_module_test "System" "test_system.sh"
run_module_test "Apps" "test_apps.sh"

# Security and encryption
run_module_test "Security" "test_security.sh"
run_module_test "Encryption" "test_encryption.sh"

# File and transfer operations
run_module_test "File Handling" "test_handle_files.sh"
run_module_test "Transfer" "test_transfer.sh"

# Network and connectivity
run_module_test "Network" "test_network.sh"

# Development tools
run_module_test "Developer" "test_developer.sh"

# Cloud and containerization
run_module_test "AWS" "test_aws.sh"
run_module_test "Docker" "test_docker.sh"

# Generate final summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "Total modules tested: $TOTAL_MODULES"
echo -e "${GREEN}Passed: $PASSED_MODULES${NC}"
echo -e "${RED}Failed: $FAILED_MODULES${NC}"

if [ $FAILED_MODULES -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed successfully!${NC}"
    echo -e "${GREEN}All bash functions are working correctly.${NC}"
    exit 0
else
    echo ""
    echo -e "${YELLOW}⚠️  Some tests failed or had warnings.${NC}"
    echo -e "${YELLOW}This may be due to missing dependencies or network issues.${NC}"
    echo -e "${YELLOW}Check individual test logs for details.${NC}"
    exit 1
fi
