#!/bin/bash

# cffile-hybrid - Share files with authentication via Worker + cloudflared proxy
# Usage: ./cffile-hybrid.sh [options] [files...]

PORT=8010
PASSWORD=""
DESCRIPTION=""
FILES=()
WORKER_URL="https://secure-tunnel.wemea-5ahhf.workers.dev"
NO_AUTH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --no-auth|--public)
            NO_AUTH=true
            shift
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

Hybrid file sharing: Cloudflare Worker authentication + cloudflared proxy

Options:
  -p, --password PWD    Set password for access (auto-generates if not provided)
  --no-auth, --public   No authentication required (PUBLIC access)
  --port PORT          Local server port (default: 8010)
  -d, --description    Description for the tunnel
  -h, --help           Show this help

Examples:
  cffile document.pdf                    # Auto-generates password
  cffile -p secret123 document.pdf      # Custom password
  cffile --no-auth ./                   # PUBLIC access (no password)
  cffile --public document.pdf          # PUBLIC access (alternative)
  cffile -p mypass -d "Project files" ~/Documents
EOF
            exit 0
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

# Handle authentication mode
if $NO_AUTH; then
    echo "🌐 Running in PUBLIC mode (no authentication required)"
else
    # Generate password if not provided
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD="cffile-$(date +%s | tail -c 5)"
        echo "ℹ️  Setting up optional password protection (auto-generated): $PASSWORD"
        echo "   Tip: Use --no-auth to share without any password"
    fi
fi

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is required"
    echo "Install it with: brew install python"
    exit 1
fi

if ! command -v cloudflared &> /dev/null; then
    echo "❌ Error: cloudflared is required"
    echo "Install it with: brew install cloudflared"
    exit 1
fi

# Prepare directory
ORIGINAL_DIR=$(pwd)
TEMP_DIR=""

if [ ${#FILES[@]} -gt 0 ]; then
    echo "📁 Preparing ${#FILES[@]} file(s) for sharing..."
    TEMP_DIR="/tmp/cffile-hybrid-$$"
    mkdir -p "$TEMP_DIR"
    
    for file in "${FILES[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ -d "$file" ]]; then
                if [[ "$file" == "." || "$file" == "./" ]]; then
                    echo "   ✓ Adding current directory contents..."
                    cp -r ./* "$TEMP_DIR/" 2>/dev/null || true
                else
                    echo "   ✓ Adding directory: $(basename "$file")"
                    cp -r "$file" "$TEMP_DIR/"
                fi
            else
                ln -sf "$(realpath "$file")" "$TEMP_DIR/"
                echo "   ✓ Added file: $(basename "$file")"
            fi
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
    DESCRIPTION="cffile hybrid sharing ($(ls | wc -l | tr -d ' ') items)"
fi

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Shutting down cffile-hybrid..."
    
    # Kill background processes
    if [[ -n "$PYTHON_PID" ]]; then
        kill "$PYTHON_PID" 2>/dev/null && echo "   ✓ Python server stopped"
    fi
    
    if [[ -n "$CLOUDFLARED_PID" ]]; then
        kill "$CLOUDFLARED_PID" 2>/dev/null && echo "   ✓ cloudflared tunnel stopped"
    fi
    
    # Cleanup temp directory
    cd "$ORIGINAL_DIR"
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        echo "   ✓ Cleaned up temporary files"
    fi
    
    echo "✅ cffile-hybrid stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Find available port
echo "🔍 Finding available port..."
while lsof -ti:$PORT >/dev/null 2>&1; do
    echo "   Port $PORT is in use, trying $((PORT + 1))..."
    PORT=$((PORT + 1))
done

# Start Python server
echo "🚀 Starting HTTP server on port $PORT..."

# Check if we're serving a single file that should be displayed directly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ${#FILES[@]} -eq 1 ] && [ -f "${FILES[0]}" ]; then
    # Single file - create index.html for better display
    FILE_NAME="$(cd "$TEMP_DIR" && ls -1 | head -1)"
    if [[ "$FILE_NAME" =~ \.(png|jpg|jpeg|gif|webp|svg|pdf|mp4|webm|mov)$ ]]; then
        # Create index.html for better display
        "$SCRIPT_DIR/create-index.sh" "$TEMP_DIR" "$FILE_NAME"
    fi
fi

# Start standard Python HTTP server
python3 -m http.server "$PORT" > /dev/null 2>&1 &
PYTHON_PID=$!

# Wait for server
sleep 2

if ! kill -0 "$PYTHON_PID" 2>/dev/null; then
    echo "❌ Failed to start Python server"
    exit 1
fi

echo "✅ Local server running at http://localhost:$PORT"

# Start cloudflared tunnel
echo "🌐 Creating cloudflared tunnel..."
CLOUDFLARED_OUTPUT=$(mktemp)
cloudflared tunnel --url "http://localhost:$PORT" > "$CLOUDFLARED_OUTPUT" 2>&1 &
CLOUDFLARED_PID=$!

# Wait for cloudflared to start and get URL
echo "⏳ Waiting for tunnel to connect..."
TUNNEL_URL=""
ATTEMPTS=0
while [[ -z "$TUNNEL_URL" ]] && [[ $ATTEMPTS -lt 30 ]]; do
    sleep 1
    TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare\.com' "$CLOUDFLARED_OUTPUT" 2>/dev/null | head -1)
    ATTEMPTS=$((ATTEMPTS + 1))
done

if [[ -z "$TUNNEL_URL" ]]; then
    echo "❌ Failed to get cloudflared tunnel URL"
    cat "$CLOUDFLARED_OUTPUT"
    exit 1
fi

echo "✅ Cloudflared tunnel created: $TUNNEL_URL"

if $NO_AUTH; then
    # No authentication - just use cloudflared directly
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Public file sharing is now active!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔗 Public Access URL: $TUNNEL_URL"
    echo "⚠️  Warning: This URL is PUBLIC - anyone with the link can access"
    echo ""
    echo "📁 Files being served: $(ls | wc -l | tr -d ' ') items"
    echo "🖥️  Local server: http://localhost:$PORT"
    echo ""
    echo "🛑 Press Ctrl+C to stop sharing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Copy to clipboard if available
    if command -v pbcopy &> /dev/null; then
        echo "$TUNNEL_URL" | pbcopy
        echo "📋 Public URL copied to clipboard"
    fi
    
    # Keep running
    while true; do
        sleep 1
        if ! kill -0 "$PYTHON_PID" 2>/dev/null; then
            echo "⚠️  Python server stopped unexpectedly"
            break
        fi
        if ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
            echo "⚠️  cloudflared tunnel stopped unexpectedly"
            break
        fi
    done
else
    # With authentication - register with Worker
    echo "🔐 Registering authentication layer..."
    
    # Generate tunnel ID for Worker
    TUNNEL_ID="hybrid-$(date +%s | tail -c 6)-$$"
    
    REGISTER_RESPONSE=$(curl -s -X POST "$WORKER_URL/api/register" \
      -H "Content-Type: application/json" \
      -d "{
        \"tunnelId\": \"$TUNNEL_ID\",
        \"password\": \"$PASSWORD\",
        \"port\": $PORT,
        \"cloudflaredUrl\": \"$TUNNEL_URL\",
        \"description\": \"$DESCRIPTION\"
      }")

    # Check if registration was successful
    if echo "$REGISTER_RESPONSE" | grep -q "success"; then
        AUTH_URL=$(echo "$REGISTER_RESPONSE" | grep -o '"authUrl":"[^"]*' | cut -d'"' -f4)
        
        if [[ -z "$AUTH_URL" ]]; then
            AUTH_URL="$WORKER_URL/tunnel/$TUNNEL_ID"
        fi
        
        echo "✅ Authentication layer registered"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎉 File sharing is now active!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "🌐 Direct URL (always public, no password):"
        echo "   $TUNNEL_URL"
        echo ""
        echo "🔐 Gated URL (password reveals the direct URL):"
        echo "   $AUTH_URL"
        echo "   Password: $PASSWORD"
        echo ""
        echo "⚠️  Note: The password only hides the direct URL."
        echo "   Once revealed, the direct URL can be shared freely."
        echo ""
        echo "📁 Files being served: $(ls | wc -l | tr -d ' ') items"
        echo "🖥️  Local server: http://localhost:$PORT"
        echo ""
        echo "💡 Tip: Use --no-auth flag to skip password protection entirely"
        echo ""
        echo "🛑 Press Ctrl+C to stop sharing"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Copy to clipboard if available (copy public URL by default)
        if command -v pbcopy &> /dev/null; then
            echo "$TUNNEL_URL" | pbcopy
            echo "📋 Public URL copied to clipboard (no password needed)"
        fi
        
        # Keep running
        while true; do
            sleep 1
            
            # Check if processes are still running
            if ! kill -0 "$PYTHON_PID" 2>/dev/null; then
                echo "⚠️  Python server stopped unexpectedly"
                break
            fi
            
            if ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
                echo "⚠️  cloudflared tunnel stopped unexpectedly"
                break
            fi
        done
        
    else
        echo "❌ Failed to register authentication layer"
        echo "$REGISTER_RESPONSE"
        exit 1
    fi
fi