#!/bin/bash

# Performance test script for bash functions
# Tests response times and resource usage of key functions

set -euo pipefail

echo "Performance Testing Bash Functions"
echo "=================================="

# Performance test helper
time_function() {
    local func_name="$1"
    local test_cmd="$2"
    local iterations="${3:-5}"
    
    echo "Testing $func_name performance..."
    
    local total_time=0
    local success_count=0
    
    for i in $(seq 1 $iterations); do
        local start_time=$(date +%s.%N)
        
        if eval "$test_cmd" >/dev/null 2>&1; then
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
            total_time=$(echo "$total_time + $duration" | bc -l 2>/dev/null || echo "$total_time")
            success_count=$((success_count + 1))
            echo "  Run $i: ${duration}s"
        else
            echo "  Run $i: FAILED"
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        local avg_time=$(echo "scale=4; $total_time / $success_count" | bc -l 2>/dev/null || echo "N/A")
        echo "  Average time: ${avg_time}s ($success_count/$iterations successful)"
    else
        echo "  All runs failed"
    fi
    echo ""
}

# Source all function files
for file in ~/.bash_*; do
    [ -r "$file" ] && [ -f "$file" ] && source "$file" 2>/dev/null
done

# Create test files
echo "Setting up test files..."
mkdir -p /tmp/perf_test
echo "Performance test content" > /tmp/perf_test/test.txt
echo '{"test": "performance", "value": 123}' > /tmp/perf_test/test.json

# Test file operations
echo "1. File Operations Performance"
echo "------------------------------"
time_function "findex" "findex /tmp/perf_test -name '*.txt'"
time_function "find_large_files" "find_large_files /tmp 1K"

# Test system operations
echo "2. System Operations Performance" 
echo "--------------------------------"
time_function "sysinfo" "sysinfo"
time_function "process_monitor" "process_monitor | head -10"
time_function "disk_usage" "disk_usage"

# Test network operations (if available)
echo "3. Network Operations Performance"
echo "--------------------------------"
if command -v ping >/dev/null 2>&1; then
    time_function "check_connectivity" "check_connectivity google.com"
fi
if declare -f myip >/dev/null; then
    time_function "myip" "myip"
fi

# Test utility functions
echo "4. Utility Functions Performance"
echo "--------------------------------"
if command -v bc >/dev/null 2>&1; then
    time_function "calc" "calc '2 + 2'"
fi
time_function "extract_urls" "extract_urls /tmp/perf_test/test.txt"

# Test security functions
echo "5. Security Functions Performance"
echo "--------------------------------"
if command -v openssl >/dev/null 2>&1; then
    time_function "hash_file" "hash_file /tmp/perf_test/test.txt"
fi
if declare -f generate_password >/dev/null; then
    time_function "generate_password" "generate_password 16"
fi

# Memory usage test
echo "6. Memory Usage Test"
echo "-------------------"
echo "Current memory usage:"
if command -v free >/dev/null 2>&1; then
    free -h
elif command -v vm_stat >/dev/null 2>&1; then
    vm_stat
else
    echo "Memory info not available"
fi

# Cleanup
rm -rf /tmp/perf_test

echo "Performance testing completed!"
