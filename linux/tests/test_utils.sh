#!/bin/bash

# Test script for .bash_utils functions
source ~/.bash_utils 2>/dev/null || { echo "Failed to source .bash_utils"; exit 1; }

echo "Testing .bash_utils functions..."

# Test variables
TEST_FILE="/tmp/test_utils.txt"
TEST_DIR="/tmp/test_utils_dir"
LARGE_FILE="/tmp/large_test_file.txt"

# Cleanup function
cleanup() {
    rm -rf "$TEST_FILE" "$TEST_DIR" "$LARGE_FILE" /tmp/test_*.txt 2>/dev/null
}
trap cleanup EXIT

echo "Test 1: calc function"
if command -v bc >/dev/null 2>&1; then
    result=$(calc "2 + 2")
    if [[ "$result" == *"4"* ]]; then
        echo "✓ calc function works"
    else
        echo "✗ calc function failed: got '$result'"
        exit 1
    fi
else
    echo "⚠ bc not available, skipping calc test"
fi

echo "Test 2: mkcd function"
test_dir="/tmp/test_mkcd_$$"
if mkcd "$test_dir" && [[ "$PWD" == "$test_dir" ]]; then
    echo "✓ mkcd function works"
    cd /tmp && rm -rf "$test_dir"
else
    echo "✗ mkcd function failed"
    exit 1
fi

echo "Test 3: findex function"
# Create test files
mkdir -p "$TEST_DIR"
echo "test content" > "$TEST_DIR/test1.txt"
echo "another test" > "$TEST_DIR/test2.log"

if findex "$TEST_DIR" -name "*.txt" | grep -q "test1.txt"; then
    echo "✓ findex function works"
else
    echo "✗ findex function failed"
    exit 1
fi

echo "Test 4: extract function"
# Create a test archive
cd "$TEST_DIR"
echo "archive content" > archive_test.txt
if command -v tar >/dev/null 2>&1; then
    tar -czf test_archive.tar.gz archive_test.txt
    rm archive_test.txt
    
    if extract test_archive.tar.gz; then
        if [[ -f "archive_test.txt" ]]; then
            echo "✓ extract function works"
        else
            echo "✗ extract function failed - file not extracted"
            exit 1
        fi
    else
        echo "✗ extract function failed"
        exit 1
    fi
else
    echo "⚠ tar not available, skipping extract test"
fi

echo "Test 5: find_large_files function"
# Create a large file
dd if=/dev/zero of="$LARGE_FILE" bs=1M count=2 2>/dev/null
if find_large_files /tmp 1M | grep -q "$(basename "$LARGE_FILE")"; then
    echo "✓ find_large_files function works"
else
    echo "✗ find_large_files function failed"
    exit 1
fi

echo "Test 6: psg function"
if psg bash | grep -q bash; then
    echo "✓ psg function works"
else
    echo "✗ psg function failed"
    exit 1
fi

echo "Test 7: myip function"
if myip | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; then
    echo "✓ myip function works"
else
    echo "⚠ myip function may have failed (network dependent)"
fi

echo "Test 8: sysinfo function"
if sysinfo | grep -E "(CPU|Memory|Disk)"; then
    echo "✓ sysinfo function works"
else
    echo "✗ sysinfo function failed"
    exit 1
fi

echo "Test 9: weather function"
# This is network dependent, so just check if function exists
if declare -f weather >/dev/null; then
    echo "✓ weather function is defined"
else
    echo "✗ weather function not found"
    exit 1
fi

echo "Test 10: note functions"
test_note="Test note content"
if note_add "test" "$test_note" && note_list | grep -q "test"; then
    echo "✓ note functions work"
    note_delete "test" 2>/dev/null
else
    echo "✗ note functions failed"
    exit 1
fi

echo "All .bash_utils tests completed successfully!"
