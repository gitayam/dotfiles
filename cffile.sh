#!/bin/bash

# cffile - Share files via Cloudflare tunnel with Python HTTP server
# Usage: ./cffile.sh [options] [files...]

PORT=8002
PASSWORD=""
USE_MULTI=false
ADMIN_PASSWORD=""
USERS=""
DESCRIPTION=""
FILES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -m|--multi)
            USE_MULTI=true
            shift
            ;;
        -a|--admin)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        -u|--users)
            USERS="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -d|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -h|--help)
            cat << 'EOF'
Usage: cffile [OPTIONS] [files/directories...]

Share files and directories via secure Cloudflare tunnel with built-in Python server.

Options:
  -p, --password PWD    Single-user mode: Set tunnel password
  -m, --multi          Enable multi-user mode
  -a, --admin PWD      Multi-user mode: Admin password
  -u, --users USERS    Multi-user mode: User credentials (user1:pass1;user2:pass2)
  --port PORT          Local server port (default: 8002)
  -d, --description    Description for the tunnel
  -h, --help           Show this help

Examples:
  cffile document.pdf                    # Share single file
  cffile -p secret123 document.pdf      # Share with password
  cffile -m -a admin123 -u "user1:pass1;user2:pass2" files/
EOF
            exit 0
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is required"
    echo "Install it with: brew install python"
    exit 1
fi

# Prepare directory
ORIGINAL_DIR=$(pwd)
TEMP_DIR=""

if [ ${#FILES[@]} -gt 0 ]; then
    echo "📁 Preparing ${#FILES[@]} file(s) for sharing..."
    TEMP_DIR="/tmp/cffile-$$"
    mkdir -p "$TEMP_DIR"
    
    for file in "${FILES[@]}"; do
        if [[ -e "$file" ]]; then
            ln -sf "$(realpath "$file")" "$TEMP_DIR/"
            echo "   ✓ Added: $(basename "$file")"
        else
            echo "   ⚠️  Warning: $file not found"
        fi
    done
    
    cd "$TEMP_DIR" || { echo "❌ Failed to access temp directory"; exit 1; }
else
    echo "📂 Serving current directory: $(pwd)"
fi

# Set description
if [[ -z "$DESCRIPTION" ]]; then
    DESCRIPTION="cffile sharing ($(ls | wc -l | tr -d ' ') items)"
fi

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Shutting down cffile..."
    
    # Kill background processes
    jobs -p | xargs -r kill 2>/dev/null
    
    # Cleanup temp directory
    cd "$ORIGINAL_DIR"
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        echo "   ✓ Cleaned up temporary files"
    fi
    
    echo "✅ cffile stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start Python server
echo "🚀 Starting Python HTTP server on port $PORT..."
python3 -m http.server "$PORT" &
SERVER_PID=$!

# Wait for server
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ Failed to start Python server"
    cleanup
fi

echo "✅ Server running at http://localhost:$PORT"

# Start tunnel
if $USE_MULTI; then
    if [[ -z "$ADMIN_PASSWORD" ]] || [[ -z "$USERS" ]]; then
        echo "❌ Multi-user mode requires -a admin_password and -u users"
        cleanup
    fi
    
    echo "🌐 Creating multi-user tunnel..."
    node "$ORIGINAL_DIR/src/multi-user-client.js" create "$PORT" "$ADMIN_PASSWORD" "$USERS" "$DESCRIPTION"
else
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD="cffile-$(date +%s | tail -c 4)"
        echo "🔑 Generated password: $PASSWORD"
    fi
    
    echo "🌐 Creating single-user tunnel..."
    node "$ORIGINAL_DIR/src/tunnel-client.js" "$PORT" "$PASSWORD" "$DESCRIPTION"
fi