#!/bin/bash

# Test script for .bash_encryption functions
source ~/.bash_encryption 2>/dev/null || { echo "Failed to source .bash_encryption"; exit 1; }

echo "Testing .bash_encryption functions..."

# Test variables
TEST_FILE="/tmp/test_encryption.txt"
TEST_CONTENT="This is secret test content for encryption testing"

# Cleanup function
cleanup() {
    rm -rf "$TEST_FILE" "$TEST_FILE"* /tmp/test_*.* /tmp/*.key /tmp/*.pub 2>/dev/null
}
trap cleanup EXIT

echo "Test 1: GPG functions"
if command -v gpg >/dev/null 2>&1; then
    echo "✓ GPG is available"
    
    # Test gpg_encrypt function
    if declare -f gpg_encrypt >/dev/null; then
        echo "✓ gpg_encrypt function is defined"
    else
        echo "✗ gpg_encrypt function not found"
        exit 1
    fi
    
    # Test gpg_decrypt function
    if declare -f gpg_decrypt >/dev/null; then
        echo "✓ gpg_decrypt function is defined"
    else
        echo "✗ gpg_decrypt function not found"
        exit 1
    fi
    
    # Test gpg_list_keys function
    if declare -f gpg_list_keys >/dev/null; then
        echo "✓ gpg_list_keys function is defined"
        
        # Test listing keys
        if gpg_list_keys >/dev/null 2>&1; then
            echo "✓ gpg_list_keys function works"
        else
            echo "⚠ gpg_list_keys function may not work (no GPG keys configured)"
        fi
    else
        echo "✗ gpg_list_keys function not found"
        exit 1
    fi
else
    echo "⚠ GPG not available, skipping GPG tests"
fi

echo "Test 2: OpenSSL functions"
if command -v openssl >/dev/null 2>&1; then
    echo "✓ OpenSSL is available"
    
    # Test ssl_encrypt function
    if declare -f ssl_encrypt >/dev/null; then
        echo "✓ ssl_encrypt function is defined"
        
        # Test encryption/decryption
        echo "$TEST_CONTENT" > "$TEST_FILE"
        if echo "testpassword" | ssl_encrypt "$TEST_FILE"; then
            if [[ -f "${TEST_FILE}.enc" ]]; then
                echo "✓ ssl_encrypt function works"
                
                # Test ssl_decrypt function
                if declare -f ssl_decrypt >/dev/null; then
                    echo "✓ ssl_decrypt function is defined"
                    
                    if echo "testpassword" | ssl_decrypt "${TEST_FILE}.enc"; then
                        if cmp -s "$TEST_FILE" "${TEST_FILE}.enc.dec" 2>/dev/null; then
                            echo "✓ ssl_decrypt function works"
                        else
                            echo "✗ ssl_decrypt function failed - content mismatch"
                            exit 1
                        fi
                    else
                        echo "✗ ssl_decrypt function failed"
                        exit 1
                    fi
                else
                    echo "✗ ssl_decrypt function not found"
                    exit 1
                fi
            else
                echo "✗ ssl_encrypt function failed - no output file"
                exit 1
            fi
        else
            echo "✗ ssl_encrypt function failed"
            exit 1
        fi
    else
        echo "✗ ssl_encrypt function not found"
        exit 1
    fi
    
    # Test generate_key function
    if declare -f generate_key >/dev/null; then
        echo "✓ generate_key function is defined"
        
        if generate_key 2048 "test" >/dev/null 2>&1; then
            if [[ -f "test.key" ]] && [[ -f "test.pub" ]]; then
                echo "✓ generate_key function works"
            else
                echo "✗ generate_key function failed - key files not created"
                exit 1
            fi
        else
            echo "✗ generate_key function failed"
            exit 1
        fi
    else
        echo "✗ generate_key function not found"
        exit 1
    fi
    
    # Test create_cert function
    if declare -f create_cert >/dev/null; then
        echo "✓ create_cert function is defined"
    else
        echo "✗ create_cert function not found"
        exit 1
    fi
    
    # Test hash_file function
    if declare -f hash_file >/dev/null; then
        echo "✓ hash_file function is defined"
        
        echo "test content" > "$TEST_FILE"
        if hash_file "$TEST_FILE" | grep -E "[a-f0-9]{64}"; then
            echo "✓ hash_file function works"
        else
            echo "✗ hash_file function failed"
            exit 1
        fi
    else
        echo "✗ hash_file function not found"
        exit 1
    fi
else
    echo "⚠ OpenSSL not available, skipping OpenSSL tests"
fi

echo "Test 3: Age encryption functions"
if command -v age >/dev/null 2>&1; then
    echo "✓ Age is available"
    
    # Test age_encrypt function
    if declare -f age_encrypt >/dev/null; then
        echo "✓ age_encrypt function is defined"
    else
        echo "✗ age_encrypt function not found"
        exit 1
    fi
    
    # Test age_decrypt function
    if declare -f age_decrypt >/dev/null; then
        echo "✓ age_decrypt function is defined"
    else
        echo "✗ age_decrypt function not found"
        exit 1
    fi
    
    # Test age_keygen function
    if declare -f age_keygen >/dev/null; then
        echo "✓ age_keygen function is defined"
        
        if age_keygen >/dev/null 2>&1; then
            echo "✓ age_keygen function works"
        else
            echo "✗ age_keygen function failed"
            exit 1
        fi
    else
        echo "✗ age_keygen function not found"
        exit 1
    fi
else
    echo "⚠ Age not available, skipping Age encryption tests"
fi

echo "Test 4: Base64 encoding functions"
if command -v base64 >/dev/null 2>&1; then
    echo "✓ Base64 is available"
    
    # Test base64_encode function
    if declare -f base64_encode >/dev/null; then
        echo "✓ base64_encode function is defined"
        
        echo "$TEST_CONTENT" > "$TEST_FILE"
        if base64_encode "$TEST_FILE"; then
            if [[ -f "${TEST_FILE}.b64" ]]; then
                echo "✓ base64_encode function works"
                
                # Test base64_decode function
                if declare -f base64_decode >/dev/null; then
                    echo "✓ base64_decode function is defined"
                    
                    if base64_decode "${TEST_FILE}.b64"; then
                        if cmp -s "$TEST_FILE" "${TEST_FILE}.b64.dec" 2>/dev/null; then
                            echo "✓ base64_decode function works"
                        else
                            echo "✗ base64_decode function failed - content mismatch"
                            exit 1
                        fi
                    else
                        echo "✗ base64_decode function failed"
                        exit 1
                    fi
                else
                    echo "✗ base64_decode function not found"
                    exit 1
                fi
            else
                echo "✗ base64_encode function failed - no output file"
                exit 1
            fi
        else
            echo "✗ base64_encode function failed"
            exit 1
        fi
    else
        echo "✗ base64_encode function not found"
        exit 1
    fi
else
    echo "⚠ Base64 not available, skipping Base64 tests"
fi

echo "Test 5: Password generation"
if declare -f generate_password >/dev/null; then
    echo "✓ generate_password function is defined"
    
    password=$(generate_password 16)
    if [[ ${#password} -eq 16 ]]; then
        echo "✓ generate_password function works"
    else
        echo "✗ generate_password function failed - wrong length"
        exit 1
    fi
else
    echo "✗ generate_password function not found"
    exit 1
fi

echo "Test 6: Secure file deletion"
if declare -f secure_delete >/dev/null; then
    echo "✓ secure_delete function is defined"
    
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
else
    echo "✗ secure_delete function not found"
    exit 1
fi

echo "All .bash_encryption tests completed successfully!"
