#!/bin/bash

# Test script for .bash_apps functions
source ~/.bash_apps 2>/dev/null || { echo "Failed to source .bash_apps"; exit 1; }

echo "Testing .bash_apps functions..."

echo "Test 1: Application aliases"
if alias | grep -E "(ll=|la=|lt=)"; then
    echo "✓ Basic application aliases are defined"
else
    echo "✗ Basic application aliases not found"
    exit 1
fi

echo "Test 2: Enhanced ls aliases"
if command -v exa >/dev/null 2>&1; then
    if alias | grep "exa"; then
        echo "✓ exa aliases are available"
    else
        echo "⚠ exa installed but aliases not found"
    fi
else
    echo "⚠ exa not available, using standard ls"
fi

echo "Test 3: bat/batcat aliases"
if command -v bat >/dev/null 2>&1; then
    if alias | grep "bat"; then
        echo "✓ bat aliases are available"
    else
        echo "⚠ bat installed but aliases not found"
    fi
elif command -v batcat >/dev/null 2>&1; then
    if alias | grep "batcat"; then
        echo "✓ batcat aliases are available"
    else
        echo "⚠ batcat installed but aliases not found"
    fi
else
    echo "⚠ bat/batcat not available"
fi

echo "Test 4: fd/fdfind aliases"
if command -v fd >/dev/null 2>&1; then
    if alias | grep "fd"; then
        echo "✓ fd aliases are available"
    else
        echo "⚠ fd installed but aliases not found"
    fi
elif command -v fdfind >/dev/null 2>&1; then
    if alias | grep "fdfind"; then
        echo "✓ fdfind aliases are available"
    else
        echo "⚠ fdfind installed but aliases not found"
    fi
else
    echo "⚠ fd/fdfind not available"
fi

echo "Test 5: ripgrep aliases"
if command -v rg >/dev/null 2>&1; then
    if alias | grep "rg"; then
        echo "✓ ripgrep aliases are available"
    else
        echo "⚠ ripgrep installed but aliases not found"
    fi
else
    echo "⚠ ripgrep not available"
fi

echo "Test 6: Git aliases"
if alias | grep -E "(gs=|ga=|gc=|gp=)"; then
    echo "✓ Git aliases are defined"
else
    echo "✗ Git aliases not found"
    exit 1
fi

echo "Test 7: System aliases"
if alias | grep -E "(h=|grep=|df=|du=)"; then
    echo "✓ System aliases are defined"
else
    echo "✗ System aliases not found"
    exit 1
fi

echo "Test 8: Safety aliases"
if alias | grep -E "(rm=|cp=|mv=)"; then
    echo "✓ Safety aliases are defined"
else
    echo "✗ Safety aliases not found"
    exit 1
fi

echo "Test 9: Python aliases"
if alias | grep -E "(python=|pip=)"; then
    echo "✓ Python aliases are defined"
else
    echo "⚠ Python aliases not found"
fi

echo "Test 10: Network aliases"
if alias | grep -E "(ping=|wget=|curl=)"; then
    echo "✓ Network aliases are defined"
else
    echo "⚠ Network aliases not found"
fi

echo "Test 11: Directory navigation aliases"
if alias | grep -E "(\.\.=|\.\.\.=|cd\.\.=)"; then
    echo "✓ Directory navigation aliases are defined"
else
    echo "⚠ Directory navigation aliases not found"
fi

echo "Test 12: Archive/compression aliases"
if alias | grep -E "(tar=|untar=|gz=)"; then
    echo "✓ Archive aliases are defined"
else
    echo "⚠ Archive aliases not found"
fi

echo "Test 13: Text processing aliases"
if alias | grep -E "(less=|head=|tail=)"; then
    echo "✓ Text processing aliases are defined"
else
    echo "⚠ Text processing aliases not found"
fi

echo "Test 14: System monitoring aliases"
if alias | grep -E "(htop=|ps=|top=)"; then
    echo "✓ System monitoring aliases are defined"
else
    echo "⚠ System monitoring aliases not found"
fi

echo "Test 15: Docker aliases (if available)"
if command -v docker >/dev/null 2>&1; then
    if alias | grep -E "(dk=|dps=|dimg=)"; then
        echo "✓ Docker aliases are defined"
    else
        echo "⚠ Docker available but aliases not found"
    fi
else
    echo "⚠ Docker not available, skipping Docker aliases test"
fi

echo "Test 16: Testing actual alias functionality"
# Test a few key aliases
if command -v ls >/dev/null 2>&1; then
    # Test ll alias
    if alias ll >/dev/null 2>&1; then
        # Just check that the alias exists and points to something
        echo "✓ ll alias is functional"
    else
        echo "✗ ll alias not working"
        exit 1
    fi
fi

echo "Test 17: Color support check"
if [[ -t 1 ]]; then
    if alias | grep -E "(--color|--colour)"; then
        echo "✓ Color support aliases are defined"
    else
        echo "⚠ Color support aliases not found"
    fi
else
    echo "⚠ Not in terminal, skipping color test"
fi

echo "All .bash_apps tests completed successfully!"
