#!/bin/bash

# Test script for .bash_docker functions
source ~/.bash_docker 2>/dev/null || { echo "Failed to source .bash_docker"; exit 1; }

echo "Testing .bash_docker functions..."

# Test variables
TEST_CONTAINER="test_bash_functions"
TEST_IMAGE="hello-world"

# Cleanup function
cleanup() {
    docker rm -f "$TEST_CONTAINER" 2>/dev/null || true
    docker rmi "$TEST_IMAGE" 2>/dev/null || true
}
trap cleanup EXIT

echo "Test 1: Docker command aliases"
# Test basic aliases exist
if alias | grep -q "dk=.*docker"; then
    echo "✓ Docker aliases are defined"
else
    echo "✗ Docker aliases not found"
    exit 1
fi

echo "Test 2: docker_clean function"
if declare -f docker_clean >/dev/null; then
    echo "✓ docker_clean function is defined"
    # Run it to test functionality
    docker_clean 2>/dev/null || echo "⚠ docker_clean may have warnings (expected)"
else
    echo "✗ docker_clean function not found"
    exit 1
fi

echo "Test 3: docker_auto function"
if declare -f docker_auto >/dev/null; then
    echo "✓ docker_auto function is defined"
else
    echo "✗ docker_auto function not found"
    exit 1
fi

echo "Test 4: dexec function"
if declare -f dexec >/dev/null; then
    echo "✓ dexec function is defined"
else
    echo "✗ dexec function not found"
    exit 1
fi

echo "Test 5: docker_logs_follow function"
if declare -f docker_logs_follow >/dev/null; then
    echo "✓ docker_logs_follow function is defined"
else
    echo "✗ docker_logs_follow function not found"
    exit 1
fi

echo "Test 6: docker_network_inspect function"
if declare -f docker_network_inspect >/dev/null; then
    echo "✓ docker_network_inspect function is defined"
else
    echo "✗ docker_network_inspect function not found"
    exit 1
fi

echo "Test 7: docker_volume_backup function"
if declare -f docker_volume_backup >/dev/null; then
    echo "✓ docker_volume_backup function is defined"
else
    echo "✗ docker_volume_backup function not found"
    exit 1
fi

echo "Test 8: update_docker_compose function"
if declare -f update_docker_compose >/dev/null; then
    echo "✓ update_docker_compose function is defined"
else
    echo "✗ update_docker_compose function not found"
    exit 1
fi

echo "Test 9: docker_system_info function"
if declare -f docker_system_info >/dev/null; then
    echo "✓ docker_system_info function is defined"
    
    # Test if it produces output
    if docker_system_info 2>/dev/null | grep -E "(Docker|Version|Storage|Network)"; then
        echo "✓ docker_system_info function works"
    else
        echo "⚠ docker_system_info may not work correctly (Docker may not be available)"
    fi
else
    echo "✗ docker_system_info function not found"
    exit 1
fi

echo "Test 10: Docker availability check"
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        echo "✓ Docker is available and running"
        
        # Test a simple docker command
        if docker run --rm --name "$TEST_CONTAINER" "$TEST_IMAGE" >/dev/null 2>&1; then
            echo "✓ Docker can run containers"
        else
            echo "⚠ Docker may not be able to run containers"
        fi
    else
        echo "⚠ Docker is installed but not running"
    fi
else
    echo "⚠ Docker is not available"
fi

echo "Test 11: Docker Compose availability"
if command -v docker-compose >/dev/null 2>&1; then
    echo "✓ Docker Compose is available"
    
    # Test version command
    if docker-compose --version >/dev/null 2>&1; then
        echo "✓ Docker Compose is functional"
    else
        echo "⚠ Docker Compose may not be functional"
    fi
else
    echo "⚠ Docker Compose is not available"
fi

echo "All .bash_docker tests completed successfully!"
