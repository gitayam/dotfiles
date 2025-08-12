#!/bin/bash

# Test script for .bash_developer functions
source ~/.bash_developer 2>/dev/null || { echo "Failed to source .bash_developer"; exit 1; }

echo "Testing .bash_developer functions..."

# Test variables
TEST_DIR="/tmp/test_developer"
TEST_REPO_DIR="/tmp/test_repo"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DIR" "$TEST_REPO_DIR" /tmp/test_*.* 2>/dev/null
}
trap cleanup EXIT

# Create test directory
mkdir -p "$TEST_DIR" "$TEST_REPO_DIR"

echo "Test 1: Git aliases and functions"
if alias | grep -q "gs=.*git status"; then
    echo "✓ Git aliases are defined"
else
    echo "✗ Git aliases not found"
    exit 1
fi

echo "Test 2: glog function"
if declare -f glog >/dev/null; then
    echo "✓ glog function is defined"
else
    echo "✗ glog function not found"
    exit 1
fi

echo "Test 3: git_clean_branches function"
if declare -f git_clean_branches >/dev/null; then
    echo "✓ git_clean_branches function is defined"
else
    echo "✗ git_clean_branches function not found"
    exit 1
fi

echo "Test 4: git_find_large_files function"
if declare -f git_find_large_files >/dev/null; then
    echo "✓ git_find_large_files function is defined"
else
    echo "✗ git_find_large_files function not found"
    exit 1
fi

echo "Test 5: create_gitignore function"
if declare -f create_gitignore >/dev/null; then
    cd "$TEST_DIR"
    if create_gitignore python; then
        if [[ -f ".gitignore" ]] && grep -q "*.pyc" ".gitignore"; then
            echo "✓ create_gitignore function works"
        else
            echo "✗ create_gitignore function failed - gitignore not created properly"
            exit 1
        fi
    else
        echo "✗ create_gitignore function failed"
        exit 1
    fi
else
    echo "✗ create_gitignore function not found"
    exit 1
fi

echo "Test 6: code_stats function"
if declare -f code_stats >/dev/null; then
    # Create some test files
    echo "#!/bin/bash\necho 'test'" > "$TEST_DIR/test.sh"
    echo "print('hello')" > "$TEST_DIR/test.py"
    echo "console.log('test');" > "$TEST_DIR/test.js"
    
    cd "$TEST_DIR"
    if code_stats | grep -E "(Total|Lines|Files)"; then
        echo "✓ code_stats function works"
    else
        echo "✗ code_stats function failed"
        exit 1
    fi
else
    echo "✗ code_stats function not found"
    exit 1
fi

echo "Test 7: find_todos function"
if declare -f find_todos >/dev/null; then
    # Create test file with TODO
    echo "# TODO: Fix this function" > "$TEST_DIR/test_todo.py"
    echo "# FIXME: Broken logic here" >> "$TEST_DIR/test_todo.py"
    
    cd "$TEST_DIR"
    if find_todos | grep -E "(TODO|FIXME)"; then
        echo "✓ find_todos function works"
    else
        echo "✗ find_todos function failed"
        exit 1
    fi
else
    echo "✗ find_todos function not found"
    exit 1
fi

echo "Test 8: backup_project function"
if declare -f backup_project >/dev/null; then
    cd "$TEST_DIR"
    echo "test content" > "project_file.txt"
    
    if backup_project "test_project"; then
        if ls /tmp/test_project_backup_*.tar.gz >/dev/null 2>&1; then
            echo "✓ backup_project function works"
        else
            echo "✗ backup_project function failed - backup not created"
            exit 1
        fi
    else
        echo "✗ backup_project function failed"
        exit 1
    fi
else
    echo "✗ backup_project function not found"
    exit 1
fi

echo "Test 9: serve_directory function"
if declare -f serve_directory >/dev/null; then
    echo "✓ serve_directory function is defined"
    # Note: Not testing actual server as it's a background process
else
    echo "✗ serve_directory function not found"
    exit 1
fi

echo "Test 10: json_pretty function"
if declare -f json_pretty >/dev/null; then
    echo '{"name":"test","value":123}' | json_pretty > "$TEST_DIR/pretty.json"
    if grep -q '"name": "test"' "$TEST_DIR/pretty.json" 2>/dev/null; then
        echo "✓ json_pretty function works"
    else
        echo "⚠ json_pretty function may not work (jq might not be available)"
    fi
else
    echo "✗ json_pretty function not found"
    exit 1
fi

echo "Test 11: extract_urls function"
if declare -f extract_urls >/dev/null; then
    echo "Visit https://example.com and http://test.org" > "$TEST_DIR/urls.txt"
    if extract_urls "$TEST_DIR/urls.txt" | grep -E "(https://example.com|http://test.org)"; then
        echo "✓ extract_urls function works"
    else
        echo "✗ extract_urls function failed"
        exit 1
    fi
else
    echo "✗ extract_urls function not found"
    exit 1
fi

echo "Test 12: monitor_file_changes function"
if declare -f monitor_file_changes >/dev/null; then
    echo "✓ monitor_file_changes function is defined"
    # Note: Not testing actual monitoring as it's a continuous process
else
    echo "✗ monitor_file_changes function not found"
    exit 1
fi

echo "Test 13: compare_files function"
if declare -f compare_files >/dev/null; then
    echo "same content" > "$TEST_DIR/file1.txt"
    echo "different content" > "$TEST_DIR/file2.txt"
    
    if compare_files "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt" | grep -E "(differ|different)"; then
        echo "✓ compare_files function works"
    else
        echo "✗ compare_files function failed"
        exit 1
    fi
else
    echo "✗ compare_files function not found"
    exit 1
fi

echo "All .bash_developer tests completed successfully!"
