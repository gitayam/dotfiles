#!/bin/bash

# Validation script for bash function files
# Checks syntax, completeness, and compatibility

set -euo pipefail

echo "Validating Bash Function Files"
echo "=============================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
total_files=0
valid_files=0
total_functions=0
valid_functions=0

# Function to check bash syntax
check_syntax() {
    local file="$1"
    if bash -n "$file" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to count functions in a file
count_functions() {
    local file="$1"
    grep -c "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file" 2>/dev/null || echo 0
}

# Function to list functions in a file
list_functions() {
    local file="$1"
    grep "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file" 2>/dev/null | \
    sed 's/^[[:space:]]*//' | \
    sed 's/[[:space:]]*(.*//' | \
    sort
}

# Navigate to linux directory
cd "$(dirname "$0")/.."

echo "Checking bash function files in: $(pwd)"
echo ""

# Check each .bash_* file
for file in .bash_*; do
    if [[ -f "$file" ]]; then
        total_files=$((total_files + 1))
        echo -e "${BLUE}Checking $file${NC}"
        echo "----------------------------------------"
        
        # Check if file is readable
        if [[ ! -r "$file" ]]; then
            echo -e "${RED}✗ File is not readable${NC}"
            continue
        fi
        
        # Check syntax
        if check_syntax "$file"; then
            echo -e "${GREEN}✓ Syntax is valid${NC}"
        else
            echo -e "${RED}✗ Syntax errors found${NC}"
            echo "Syntax check details:"
            bash -n "$file" || true
            continue
        fi
        
        # Count functions
        func_count=$(count_functions "$file")
        total_functions=$((total_functions + func_count))
        echo "📊 Functions found: $func_count"
        
        # List functions
        if [[ $func_count -gt 0 ]]; then
            echo "📋 Function list:"
            list_functions "$file" | sed 's/^/   - /'
            valid_functions=$((valid_functions + func_count))
        else
            echo -e "${YELLOW}⚠ No functions found (may be aliases only)${NC}"
        fi
        
        # Check for common patterns
        echo "🔍 Content analysis:"
        
        # Check for aliases
        alias_count=$(grep -c "^[[:space:]]*alias" "$file" 2>/dev/null || echo 0)
        echo "   - Aliases: $alias_count"
        
        # Check for exports
        export_count=$(grep -c "^[[:space:]]*export" "$file" 2>/dev/null || echo 0)
        echo "   - Exports: $export_count"
        
        # Check for command dependencies
        if grep -q "command -v\|which\|type" "$file" 2>/dev/null; then
            echo -e "   - ${GREEN}✓ Has dependency checks${NC}"
        else
            echo -e "   - ${YELLOW}⚠ No dependency checks found${NC}"
        fi
        
        # Check for error handling
        if grep -q "set -e\|errexit\|\|\|&&" "$file" 2>/dev/null; then
            echo -e "   - ${GREEN}✓ Has error handling${NC}"
        else
            echo -e "   - ${YELLOW}⚠ Limited error handling${NC}"
        fi
        
        # Check file size
        file_size=$(wc -l < "$file")
        echo "   - Lines of code: $file_size"
        
        valid_files=$((valid_files + 1))
        echo -e "${GREEN}✓ $file is valid${NC}"
        echo ""
    fi
done

# Check .bashrc file
echo -e "${BLUE}Checking .bashrc integration${NC}"
echo "----------------------------------------"
if [[ -f ".bashrc" ]]; then
    if grep -q "bash_" ".bashrc"; then
        echo -e "${GREEN}✓ .bashrc sources bash function files${NC}"
    else
        echo -e "${YELLOW}⚠ .bashrc may not source all function files${NC}"
    fi
else
    echo -e "${YELLOW}⚠ .bashrc file not found${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}Validation Summary${NC}"
echo "=================="
echo "Files checked: $total_files"
echo -e "Valid files: ${GREEN}$valid_files${NC}"
echo "Total functions: $total_functions"
echo -e "Valid functions: ${GREEN}$valid_functions${NC}"

if [[ $valid_files -eq $total_files ]]; then
    echo ""
    echo -e "${GREEN}🎉 All bash function files are valid!${NC}"
    
    # Create function inventory
    echo ""
    echo "Creating function inventory..."
    {
        echo "# Bash Functions Inventory"
        echo "Generated on: $(date)"
        echo "Total files: $total_files"
        echo "Total functions: $total_functions"
        echo ""
        
        for file in .bash_*; do
            if [[ -f "$file" ]]; then
                func_count=$(count_functions "$file")
                echo "## $file ($func_count functions)"
                echo ""
                if [[ $func_count -gt 0 ]]; then
                    list_functions "$file" | sed 's/^/- /'
                else
                    echo "- (No functions - aliases/exports only)"
                fi
                echo ""
            fi
        done
    } > "function_inventory.md"
    
    echo -e "${GREEN}✓ Function inventory created: function_inventory.md${NC}"
    
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some files have issues. Please review and fix.${NC}"
    exit 1
fi
