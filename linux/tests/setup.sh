#!/bin/bash

# Setup script for bash function tests
# Makes all scripts executable and prepares the test environment

set -euo pipefail

echo "Setting up Bash Function Test Environment"
echo "========================================"

# Get the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "1. Making test scripts executable..."
chmod +x *.sh
echo "   ✓ All test scripts are now executable"

echo "2. Creating output directories..."
mkdir -p test_output test_logs
echo "   ✓ Output directories created"

echo "3. Checking Docker availability..."
if command -v docker >/dev/null 2>&1; then
    echo "   ✓ Docker is available"
    
    if docker info >/dev/null 2>&1; then
        echo "   ✓ Docker daemon is running"
    else
        echo "   ⚠ Docker daemon may not be running"
    fi
else
    echo "   ✗ Docker is not available"
    echo "   Please install Docker to run the containerized tests"
fi

echo "4. Checking Docker Compose availability..."
if command -v docker-compose >/dev/null 2>&1; then
    echo "   ✓ Docker Compose is available"
elif docker compose version >/dev/null 2>&1; then
    echo "   ✓ Docker Compose (v2) is available"
else
    echo "   ⚠ Docker Compose not found"
fi

echo "5. Validating test configuration..."
if [[ -f "Dockerfile" ]]; then
    echo "   ✓ Dockerfile exists"
else
    echo "   ✗ Dockerfile missing"
fi

if [[ -f "docker-compose.yml" ]]; then
    echo "   ✓ Docker Compose file exists"
else
    echo "   ✗ Docker Compose file missing"
fi

echo ""
echo "Setup Complete!"
echo "==============="
echo ""
echo "Available test commands:"
echo ""
echo "📋 Run all tests in Docker:"
echo "   docker-compose up --build bash-function-tests"
echo ""
echo "🔍 Run specific test module:"
echo "   docker-compose run --rm bash-function-tests bash tests/test_utils.sh"
echo ""
echo "🏃 Run quick test summary:"
echo "   docker-compose run --rm bash-function-tests bash tests/test_all.sh"
echo ""
echo "⚡ Run performance tests:"
echo "   docker-compose run --rm bash-function-tests bash tests/performance_test.sh"
echo ""
echo "🐚 Interactive testing:"
echo "   docker-compose run --rm bash-function-tests bash"
echo ""
echo "📊 View test results:"
echo "   ls -la test_output/"
echo "   ls -la test_logs/"
echo ""
echo "For more details, see README.md"
