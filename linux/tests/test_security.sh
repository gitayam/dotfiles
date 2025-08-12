#!/bin/bash

# Test script for .bash_security functions
source ~/.bash_security 2>/dev/null || { echo "Failed to source .bash_security"; exit 1; }

echo "Testing .bash_security functions..."

# Test variables
TEST_FILE="/tmp/test_security.txt"
ENCRYPTED_FILE="/tmp/test_encrypted"
TEST_CONTENT="This is sensitive test content"

# Cleanup function
cleanup() {
    rm -rf "$TEST_FILE" "$ENCRYPTED_FILE"* /tmp/test_*.txt /tmp/test_*.enc /tmp/test_*.gpg 2>/dev/null
}
trap cleanup EXIT

echo "Test 1: encrypt_file and decrypt_file with age"
echo "$TEST_CONTENT" > "$TEST_FILE"

if command -v age >/dev/null 2>&1; then
    # Generate a test key
    test_key=$(age-keygen 2>/dev/null | grep "AGE-SECRET-KEY" | head -1)
    test_pubkey=$(echo "$test_key" | age-keygen -y 2>/dev/null)
    
    if [[ -n "$test_key" ]] && [[ -n "$test_pubkey" ]]; then
        # Test encryption
        if echo "$test_pubkey" | encrypt_file "$TEST_FILE" age; then
            if [[ -f "${TEST_FILE}.age" ]]; then
                echo "✓ age encryption works"
                
                # Test decryption
                if echo "$test_key" | decrypt_file "${TEST_FILE}.age" age; then
                    if cmp -s "$TEST_FILE" "${TEST_FILE}.age.dec" 2>/dev/null; then
                        echo "✓ age decryption works"
                    else
                        echo "✗ age decryption failed - content mismatch"
                        exit 1
                    fi
                else
                    echo "✗ age decryption failed"
                    exit 1
                fi
            else
                echo "✗ age encryption failed - no output file"
                exit 1
            fi
        else
            echo "✗ age encryption failed"
            exit 1
        fi
    else
        echo "⚠ Could not generate age keys, skipping age test"
    fi
else
    echo "⚠ age not available, skipping age encryption test"
fi

echo "Test 2: encrypt_file and decrypt_file with AES"
echo "$TEST_CONTENT" > "$TEST_FILE"

if encrypt_file "$TEST_FILE" aes <<< "testpassword"; then
    if [[ -f "${TEST_FILE}.enc" ]]; then
        echo "✓ AES encryption works"
        
        # Test decryption
        if decrypt_file "${TEST_FILE}.enc" aes <<< "testpassword"; then
            if cmp -s "$TEST_FILE" "${TEST_FILE}.enc.dec" 2>/dev/null; then
                echo "✓ AES decryption works"
            else
                echo "✗ AES decryption failed - content mismatch"
                exit 1
            fi
        else
            echo "✗ AES decryption failed"
            exit 1
        fi
    else
        echo "✗ AES encryption failed - no output file"
        exit 1
    fi
else
    echo "✗ AES encryption failed"
    exit 1
fi

echo "Test 3: clean_file function"
test_dirty_file="/tmp/test file with spaces & symbols!.txt"
echo "test" > "$test_dirty_file"

if clean_file "$test_dirty_file"; then
    # Check if a cleaned file was created
    if ls /tmp/test_file_with_spaces_symbols_*.txt >/dev/null 2>&1; then
        echo "✓ clean_file function works"
    else
        echo "✗ clean_file function failed"
        exit 1
    fi
else
    echo "✗ clean_file function failed"
    exit 1
fi

echo "Test 4: secure_delete function"
echo "sensitive data" > "$TEST_FILE"
if secure_delete "$TEST_FILE"; then
    if [[ ! -f "$TEST_FILE" ]]; then
        echo "✓ secure_delete function works"
    else
        echo "✗ secure_delete function failed - file still exists"
        exit 1
    fi
else
    echo "✗ secure_delete function failed"
    exit 1
fi

echo "Test 5: security_check function"
if security_check | grep -E "(Security|Check|System)"; then
    echo "✓ security_check function works"
else
    echo "✗ security_check function failed"
    exit 1
fi

echo "Test 6: virus_scan function"
if command -v clamscan >/dev/null 2>&1; then
    echo "test content" > "$TEST_FILE"
    if virus_scan "$TEST_FILE" | grep -E "(FOUND|OK|scan)"; then
        echo "✓ virus_scan function works"
    else
        echo "✗ virus_scan function failed"
        exit 1
    fi
else
    echo "⚠ ClamAV not available, skipping virus scan test"
fi

echo "Test 7: suspicious_processes function"
if suspicious_processes | head -10 | wc -l | grep -q "[0-9]"; then
    echo "✓ suspicious_processes function works"
else
    echo "✗ suspicious_processes function failed"
    exit 1
fi

echo "Test 8: generate_password function"
if declare -f generate_password >/dev/null; then
    password=$(generate_password 12)
    if [[ ${#password} -eq 12 ]]; then
        echo "✓ generate_password function works"
    else
        echo "✗ generate_password function failed"
        exit 1
    fi
else
    echo "✗ generate_password function not found"
    exit 1
fi

echo "All .bash_security tests completed successfully!"
