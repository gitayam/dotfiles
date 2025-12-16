#!/bin/zsh

# Simple test version of cffile
cffile() {
    echo "cffile test function works!"
    echo "Arguments: $@"
    
    # Test help
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        cat << 'EOF'
Usage: cffile [OPTIONS] [files/directories...]

Share files and directories via secure Cloudflare tunnel with built-in Python server.

Options:
  -p, --password PWD    Single-user mode: Set tunnel password
  -m, --multi          Enable multi-user mode
  -h, --help           Show this help

Examples:
  cffile document.pdf                    # Share single file
  cffile -p secret123 document.pdf      # Share with password
  cffile -m -a admin123 -u "user1:pass1;user2:pass2" files/
EOF
        return 0
    fi
    
    echo "This is a test version - full function is in .zsh_network"
}