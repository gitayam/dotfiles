#!/bin/bash

# Fix cfps to support password protection

echo "🔧 Fixing cfps to support password protection..."

# Create the updated function
cat > /tmp/cfpage-shot-new.sh << 'EOF'
# Take screenshot and upload to Pages (with optional password protection)
cfpage-shot() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="screenshot_${timestamp}.png"
    local temp_file="/tmp/$filename"
    local password=""
    
    # Parse arguments for password
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                password="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo "📸 Taking screenshot..."
    echo "Press Cmd+Shift+4 and select area to capture"
    
    # Take screenshot
    screencapture -i "$temp_file"
    
    if [[ ! -f "$temp_file" ]]; then
        echo "❌ Screenshot cancelled"
        return 1
    fi
    
    if [[ -n "$password" ]]; then
        # Use cffile for password-protected sharing
        echo "🔐 Creating password-protected share..."
        cffile -p "$password" "$temp_file"
        # cffile handles cleanup of temp file
    else
        # Upload publicly using cfpage-upload
        cfpage-upload "$temp_file"
        # Clean up
        rm "$temp_file"
    fi
}
EOF

# Backup original
cp ~/.zsh_network ~/.zsh_network.backup-cfps

# Remove old cfpage-shot function and add new one
awk '
/^cfpage-shot\(\) \{/ {
    in_func = 1
    print "# OLD cfpage-shot function (replaced)"
    next
}
in_func && /^}$/ {
    in_func = 0
    system("cat /tmp/cfpage-shot-new.sh")
    next
}
in_func {
    print "# " $0
    next
}
!in_func {
    print
}
' ~/.zsh_network > ~/.zsh_network.tmp && mv ~/.zsh_network.tmp ~/.zsh_network

echo "✅ Updated cfpage-shot function to support password protection"
echo ""
echo "Now you can use:"
echo "  cfps -p PASSWORD   # Password-protected screenshot"
echo "  cfps              # Public screenshot"
echo ""
echo "Please run: source ~/.zsh_network"