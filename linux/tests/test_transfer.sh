#!/bin/bash

# Test script for .bash_transfer functions
source ~/.bash_transfer 2>/dev/null || { echo "Failed to source .bash_transfer"; exit 1; }

echo "Testing .bash_transfer functions..."

# Test variables
TEST_FILE="/tmp/test_transfer.txt"
TEST_DIR="/tmp/test_transfer_dir"
DEST_DIR="/tmp/test_dest"

# Cleanup function
cleanup() {
    rm -rf "$TEST_FILE" "$TEST_DIR" "$DEST_DIR" /tmp/test_*.txt 2>/dev/null
    pkill -f "python.*http.server" 2>/dev/null || true
}
trap cleanup EXIT

echo "Test 1: transfer_file function with rsync"
echo "test transfer content" > "$TEST_FILE"
mkdir -p "$DEST_DIR"

if command -v rsync >/dev/null 2>&1; then
    if transfer_file "$TEST_FILE" "$DEST_DIR/"; then
        if [[ -f "$DEST_DIR/$(basename "$TEST_FILE")" ]]; then
            echo "✓ transfer_file function works with rsync"
        else
            echo "✗ transfer_file function failed - file not transferred"
            exit 1
        fi
    else
        echo "✗ transfer_file function failed"
        exit 1
    fi
else
    echo "⚠ rsync not available, skipping transfer_file test"
fi

echo "Test 2: sync_dirs function"
mkdir -p "$TEST_DIR/subdir"
echo "sync test 1" > "$TEST_DIR/file1.txt"
echo "sync test 2" > "$TEST_DIR/subdir/file2.txt"

if command -v rsync >/dev/null 2>&1; then
    if sync_dirs "$TEST_DIR/" "$DEST_DIR/"; then
        if [[ -f "$DEST_DIR/file1.txt" ]] && [[ -f "$DEST_DIR/subdir/file2.txt" ]]; then
            echo "✓ sync_dirs function works"
        else
            echo "✗ sync_dirs function failed - files not synced"
            exit 1
        fi
    else
        echo "✗ sync_dirs function failed"
        exit 1
    fi
else
    echo "⚠ rsync not available, skipping sync_dirs test"
fi

echo "Test 3: share_files function"
cd "$TEST_DIR"
echo "shared content" > shared_file.txt

# Start HTTP server in background and test if it responds
if share_files . 8888 & then
    server_pid=$!
    sleep 2
    
    # Test if server is responding
    if curl -s http://localhost:8888/ | grep -q "shared_file.txt"; then
        echo "✓ share_files function works"
        kill $server_pid 2>/dev/null
    else
        echo "✗ share_files function failed - server not responding"
        kill $server_pid 2>/dev/null
        exit 1
    fi
else
    echo "✗ share_files function failed to start"
    exit 1
fi

echo "Test 4: wh_transfer function"
if command -v wormhole >/dev/null 2>&1; then
    # Just test that the function is defined and can be called
    if declare -f wh_transfer >/dev/null; then
        echo "✓ wh_transfer function is defined"
    else
        echo "✗ wh_transfer function not found"
        exit 1
    fi
else
    echo "⚠ magic-wormhole not available, skipping wh_transfer test"
fi

echo "Test 5: upload_to_cloud function"
if command -v rclone >/dev/null 2>&1; then
    # Just test that the function is defined
    if declare -f upload_to_cloud >/dev/null; then
        echo "✓ upload_to_cloud function is defined"
    else
        echo "✗ upload_to_cloud function not found"
        exit 1
    fi
else
    echo "⚠ rclone not available, skipping upload_to_cloud test"
fi

echo "Test 6: compress_and_transfer function"
echo "compress test" > "$TEST_FILE"
if command -v tar >/dev/null 2>&1; then
    if compress_and_transfer "$TEST_FILE" /tmp/; then
        if [[ -f "/tmp/$(basename "$TEST_FILE").tar.gz" ]]; then
            echo "✓ compress_and_transfer function works"
        else
            echo "✗ compress_and_transfer function failed - no compressed file"
            exit 1
        fi
    else
        echo "✗ compress_and_transfer function failed"
        exit 1
    fi
else
    echo "⚠ tar not available, skipping compress_and_transfer test"
fi

echo "Test 7: scp_with_progress function"
# Just test that the function is defined (requires SSH setup for real testing)
if declare -f scp_with_progress >/dev/null; then
    echo "✓ scp_with_progress function is defined"
else
    echo "✗ scp_with_progress function not found"
    exit 1
fi

echo "Test 8: monitor_transfer function"
# Test with a simple file copy operation
echo "monitor test" > "$TEST_FILE"
if monitor_transfer cp "$TEST_FILE" "$DEST_DIR/"; then
    if [[ -f "$DEST_DIR/$(basename "$TEST_FILE")" ]]; then
        echo "✓ monitor_transfer function works"
    else
        echo "✗ monitor_transfer function failed - file not copied"
        exit 1
    fi
else
    echo "✗ monitor_transfer function failed"
    exit 1
fi

echo "All .bash_transfer tests completed successfully!"
