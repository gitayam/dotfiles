#!/bin/bash

# Main test runner for bash functions
# This script orchestrates all function tests and generates reports

set -euo pipefail

# Configuration
TEST_DIR="/home/testuser/tests"
OUTPUT_DIR="/home/testuser/test_output"
LOG_DIR="/home/testuser/test_logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
}

log_success() {
    echo -e "${GREEN}[PASS] $1${NC}" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
}

log_error() {
    echo -e "${RED}[FAIL] $1${NC}" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
}

log_warning() {
    echo -e "${YELLOW}[SKIP] $1${NC}" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
}

# Function to run a test and capture result
run_test() {
    local test_name="$1"
    local test_script="$2"
    local timeout="${3:-30}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log "Running test: $test_name"
    
    # Create test-specific log file
    local test_log="$LOG_DIR/${test_name}_$TIMESTAMP.log"
    
    # Run test with timeout
    if timeout "$timeout" bash "$test_script" > "$test_log" 2>&1; then
        log_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "$test_name (TIMEOUT after ${timeout}s)"
        else
            log_error "$test_name (Exit code: $exit_code)"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        # Show last few lines of error log
        echo "Last 10 lines of error log:" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
        tail -10 "$test_log" | tee -a "$LOG_DIR/test_runner_$TIMESTAMP.log"
        return 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Setup test environment
setup_test_environment() {
    log "Setting up test environment..."
    
    # Create directories
    mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
    
    # Source all bash function files
    for file in ~/.bash_*; do
        if [ -r "$file" ] && [ -f "$file" ]; then
            log "Sourcing $file"
            source "$file" || log_warning "Failed to source $file"
        fi
    done
    
    # Create test files
    echo "Test content for utilities" > "$OUTPUT_DIR/test_file.txt"
    echo '{"test": "json", "number": 42}' > "$OUTPUT_DIR/test.json"
    
    # Generate a small test image (if ImageMagick is available)
    if command_exists convert; then
        convert -size 100x100 xc:red "$OUTPUT_DIR/test_image.png" 2>/dev/null || true
    fi
    
    log "Test environment setup complete"
}

# Generate test report
generate_report() {
    local report_file="$OUTPUT_DIR/test_report_$TIMESTAMP.html"
    
    log "Generating test report: $report_file"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Bash Functions Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; padding: 15px; border-left: 4px solid #007cba; }
        .pass { color: #28a745; }
        .fail { color: #dc3545; }
        .skip { color: #ffc107; }
        .test-section { margin: 20px 0; border: 1px solid #ddd; border-radius: 5px; }
        .test-header { background: #f8f9fa; padding: 10px; font-weight: bold; }
        .test-content { padding: 15px; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Bash Functions Test Report</h1>
        <p>Generated on: $(date)</p>
        <p>Test Environment: Docker Container (Ubuntu 22.04)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $TOTAL_TESTS</p>
        <p class="pass"><strong>Passed:</strong> $PASSED_TESTS</p>
        <p class="fail"><strong>Failed:</strong> $FAILED_TESTS</p>
        <p class="skip"><strong>Skipped:</strong> $SKIPPED_TESTS</p>
        <p><strong>Success Rate:</strong> $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%</p>
    </div>
EOF

    # Add test details
    for log_file in "$LOG_DIR"/*_"$TIMESTAMP".log; do
        if [ -f "$log_file" ] && [ "$(basename "$log_file")" != "test_runner_$TIMESTAMP.log" ]; then
            local test_name=$(basename "$log_file" "_$TIMESTAMP.log")
            echo "    <div class=\"test-section\">" >> "$report_file"
            echo "        <div class=\"test-header\">$test_name</div>" >> "$report_file"
            echo "        <div class=\"test-content\">" >> "$report_file"
            echo "            <pre>$(cat "$log_file")</pre>" >> "$report_file"
            echo "        </div>" >> "$report_file"
            echo "    </div>" >> "$report_file"
        fi
    done
    
    echo "</body></html>" >> "$report_file"
    
    log "Report generated: $report_file"
}

# Main execution
main() {
    log "Starting bash function tests - $TIMESTAMP"
    
    setup_test_environment
    
    # Run all test scripts
    for test_script in "$TEST_DIR"/test_*.sh; do
        if [ -f "$test_script" ]; then
            local test_name=$(basename "$test_script" .sh)
            run_test "$test_name" "$test_script"
        fi
    done
    
    # Generate final report
    generate_report
    
    log "Test execution complete"
    log "Summary: $PASSED_TESTS passed, $FAILED_TESTS failed, $SKIPPED_TESTS skipped out of $TOTAL_TESTS total"
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
