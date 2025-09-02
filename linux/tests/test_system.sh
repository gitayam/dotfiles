#!/bin/bash

# Test script for .bash_system functions
source ~/.bash_system 2>/dev/null || { echo "Failed to source .bash_system"; exit 1; }

echo "Testing .bash_system functions..."

echo "Test 1: sysinfo function"
if declare -f sysinfo >/dev/null; then
    if sysinfo | grep -E "(System|CPU|Memory|Disk|Uptime)"; then
        echo "✓ sysinfo function works"
    else
        echo "✗ sysinfo function failed"
        exit 1
    fi
else
    echo "✗ sysinfo function not found"
    exit 1
fi

echo "Test 2: disk_usage function"
if declare -f disk_usage >/dev/null; then
    if disk_usage | grep -E "(Filesystem|Available|Use%)"; then
        echo "✓ disk_usage function works"
    else
        echo "✗ disk_usage function failed"
        exit 1
    fi
else
    echo "✗ disk_usage function not found"
    exit 1
fi

echo "Test 3: memory_info function"
if declare -f memory_info >/dev/null; then
    if memory_info | grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached)"; then
        echo "✓ memory_info function works"
    else
        echo "✗ memory_info function failed"
        exit 1
    fi
else
    echo "✗ memory_info function not found"
    exit 1
fi

echo "Test 4: cpu_info function"
if declare -f cpu_info >/dev/null; then
    if cpu_info | grep -E "(processor|model name|cpu cores|cpu MHz)"; then
        echo "✓ cpu_info function works"
    else
        echo "✗ cpu_info function failed"
        exit 1
    fi
else
    echo "✗ cpu_info function not found"
    exit 1
fi

echo "Test 5: process_monitor function"
if declare -f process_monitor >/dev/null; then
    if process_monitor | head -10 | grep -E "(PID|USER|CPU|MEM|COMMAND)"; then
        echo "✓ process_monitor function works"
    else
        echo "✗ process_monitor function failed"
        exit 1
    fi
else
    echo "✗ process_monitor function not found"
    exit 1
fi

echo "Test 6: system_load function"
if declare -f system_load >/dev/null; then
    if system_load | grep -E "(load average|CPU|Memory)"; then
        echo "✓ system_load function works"
    else
        echo "✗ system_load function failed"
        exit 1
    fi
else
    echo "✗ system_load function not found"
    exit 1
fi

echo "Test 7: service_status function"
if declare -f service_status >/dev/null; then
    # Test with a common service
    if service_status sshd 2>/dev/null | grep -E "(active|inactive|enabled|disabled)" || \
       service_status ssh 2>/dev/null | grep -E "(active|inactive|enabled|disabled)"; then
        echo "✓ service_status function works"
    else
        echo "⚠ service_status function may not work (no testable service found)"
    fi
else
    echo "✗ service_status function not found"
    exit 1
fi

echo "Test 8: cleanup_system function"
if declare -f cleanup_system >/dev/null; then
    echo "✓ cleanup_system function is defined"
    # Note: Not running actual cleanup as it modifies system
else
    echo "✗ cleanup_system function not found"
    exit 1
fi

echo "Test 9: check_updates function"
if declare -f check_updates >/dev/null; then
    echo "✓ check_updates function is defined"
    # Note: Not running actual check as it can be slow
else
    echo "✗ check_updates function not found"
    exit 1
fi

echo "Test 10: system_backup function"
if declare -f system_backup >/dev/null; then
    echo "✓ system_backup function is defined"
    # Note: Not running actual backup as it can be time-consuming
else
    echo "✗ system_backup function not found"
    exit 1
fi

echo "Test 11: monitor_logs function"
if declare -f monitor_logs >/dev/null; then
    echo "✓ monitor_logs function is defined"
    # Note: Not running actual monitoring as it's a continuous process
else
    echo "✗ monitor_logs function not found"
    exit 1
fi

echo "Test 12: system_temperature function"
if declare -f system_temperature >/dev/null; then
    # Try to get temperature info
    temp_result=$(system_temperature 2>/dev/null)
    if echo "$temp_result" | grep -E "(°C|Temperature|Core)" || [[ -z "$temp_result" ]]; then
        echo "✓ system_temperature function works (may not have sensors)"
    else
        echo "✗ system_temperature function failed"
        exit 1
    fi
else
    echo "✗ system_temperature function not found"
    exit 1
fi

echo "Test 13: uptime_detailed function"
if declare -f uptime_detailed >/dev/null; then
    if uptime_detailed | grep -E "(up|days|hours|minutes|users|load average)"; then
        echo "✓ uptime_detailed function works"
    else
        echo "✗ uptime_detailed function failed"
        exit 1
    fi
else
    echo "✗ uptime_detailed function not found"
    exit 1
fi

echo "Test 14: kernel_info function"
if declare -f kernel_info >/dev/null; then
    if kernel_info | grep -E "(Linux|kernel|version|release)"; then
        echo "✓ kernel_info function works"
    else
        echo "✗ kernel_info function failed"
        exit 1
    fi
else
    echo "✗ kernel_info function not found"
    exit 1
fi

echo "All .bash_system tests completed successfully!"
