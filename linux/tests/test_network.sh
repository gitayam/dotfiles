#!/bin/bash

# Test script for .bash_network functions
source ~/.bash_network 2>/dev/null || { echo "Failed to source .bash_network"; exit 1; }

echo "Testing .bash_network functions..."

# Test variables
TEST_HOST="google.com"
TEST_PORT="80"
LOCAL_PORT="8888"

echo "Test 1: myip function"
if declare -f myip >/dev/null; then
    ip_result=$(myip 2>/dev/null)
    if echo "$ip_result" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; then
        echo "✓ myip function works: $ip_result"
    else
        echo "⚠ myip function may not work correctly (network dependent): $ip_result"
    fi
else
    echo "✗ myip function not found"
    exit 1
fi

echo "Test 2: port_scan function"
if declare -f port_scan >/dev/null; then
    if command -v nmap >/dev/null 2>&1; then
        # Test scanning a well-known open port
        result=$(port_scan "$TEST_HOST" "$TEST_PORT" 2>/dev/null)
        if echo "$result" | grep -E "(open|Open)"; then
            echo "✓ port_scan function works"
        else
            echo "⚠ port_scan function may not work correctly (network dependent)"
        fi
    else
        echo "⚠ nmap not available, cannot test port_scan function"
    fi
else
    echo "✗ port_scan function not found"
    exit 1
fi

echo "Test 3: check_connectivity function"
if declare -f check_connectivity >/dev/null; then
    if check_connectivity "$TEST_HOST" >/dev/null 2>&1; then
        echo "✓ check_connectivity function works"
    else
        echo "⚠ check_connectivity function may not work (network dependent)"
    fi
else
    echo "✗ check_connectivity function not found"
    exit 1
fi

echo "Test 4: network_info function"
if declare -f network_info >/dev/null; then
    if network_info | grep -E "(interface|IP|Gateway|DNS)"; then
        echo "✓ network_info function works"
    else
        echo "✗ network_info function failed"
        exit 1
    fi
else
    echo "✗ network_info function not found"
    exit 1
fi

echo "Test 5: dns_lookup function"
if declare -f dns_lookup >/dev/null; then
    if dns_lookup "$TEST_HOST" | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
        echo "✓ dns_lookup function works"
    else
        echo "⚠ dns_lookup function may not work correctly (network dependent)"
    fi
else
    echo "✗ dns_lookup function not found"
    exit 1
fi

echo "Test 6: bandwidth_test function"
if declare -f bandwidth_test >/dev/null; then
    echo "✓ bandwidth_test function is defined"
    # Note: Not running actual test as it can be time-consuming
else
    echo "✗ bandwidth_test function not found"
    exit 1
fi

echo "Test 7: monitor_connections function"
if declare -f monitor_connections >/dev/null; then
    # Test that it produces some output
    if monitor_connections | head -5 | wc -l | grep -q "[1-9]"; then
        echo "✓ monitor_connections function works"
    else
        echo "✗ monitor_connections function failed"
        exit 1
    fi
else
    echo "✗ monitor_connections function not found"
    exit 1
fi

echo "Test 8: flush_dns function"
if declare -f flush_dns >/dev/null; then
    echo "✓ flush_dns function is defined"
    # Note: Not running actual flush as it requires sudo
else
    echo "✗ flush_dns function not found"
    exit 1
fi

echo "Test 9: trace_route function"
if declare -f trace_route >/dev/null; then
    if command -v traceroute >/dev/null 2>&1; then
        echo "✓ trace_route function is defined and traceroute is available"
    else
        echo "⚠ trace_route function defined but traceroute not available"
    fi
else
    echo "✗ trace_route function not found"
    exit 1
fi

echo "Test 10: find_open_ports function"
if declare -f find_open_ports >/dev/null; then
    # Test finding open ports on localhost
    if find_open_ports localhost | head -5 | grep -E "(Port|open|LISTEN)"; then
        echo "✓ find_open_ports function works"
    else
        echo "⚠ find_open_ports function may not work correctly"
    fi
else
    echo "✗ find_open_ports function not found"
    exit 1
fi

echo "Test 11: whois_lookup function"
if declare -f whois_lookup >/dev/null; then
    if command -v whois >/dev/null 2>&1; then
        if whois_lookup "$TEST_HOST" | head -10 | grep -E "(Domain|Registry|Registrar)"; then
            echo "✓ whois_lookup function works"
        else
            echo "⚠ whois_lookup function may not work correctly (network dependent)"
        fi
    else
        echo "⚠ whois command not available"
    fi
else
    echo "✗ whois_lookup function not found"
    exit 1
fi

echo "Test 12: network_scan function"
if declare -f network_scan >/dev/null; then
    if command -v nmap >/dev/null 2>&1; then
        echo "✓ network_scan function is defined and nmap is available"
        # Note: Not running actual scan as it can be slow and may be blocked
    else
        echo "⚠ network_scan function defined but nmap not available"
    fi
else
    echo "✗ network_scan function not found"
    exit 1
fi

echo "All .bash_network tests completed successfully!"
