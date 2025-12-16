#!/bin/bash

# cffile-hybrid - Share files with authentication via Worker + cloudflared proxy
# Enhanced by Gemini

# ==============================================================================
# Configuration
# ==============================================================================

PORT=8010
PASSWORD=""
DESCRIPTION=""
FILES=()
WORKER_URL=${CFFILE_WORKER_URL:-"https://secure-tunnel.wemea-5ahhf.workers.dev"}
NO_AUTH=false
QUIET=false

# ==============================================================================
# Helper Functions
# ==============================================================================

# Print a message if not in quiet mode
log() {
    if [[ "$QUIET" == false ]]; then
        echo "$@"
    fi
}

# Print an error message
error() {
    echo "❌ Error: $@" >&2
}

# Check for required command-line tools
check_dependencies() {
    log "🔍 Checking dependencies..."
    local missing=0
    for cmd in python3 cloudflared lsof realpath;
    do
        if ! command -v "$cmd" &>/dev/null;
        then
            error "'$cmd' is not installed. Please install it to continue."
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
    log "✅ All dependencies are installed."
}

# Parse command-line arguments
parse_arguments() {
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
            -q|--quiet)
                QUIET=true
                shift
                ;; 
            -h|--help)
                print_help
                exit 0
                ;; 
            *)
                FILES+=("$1")
                shift
                ;; 
        esac
    done
}

# Print the help message
print_help() {
    cat << 'EOF'
Usage: cffile-hybrid [OPTIONS] [files/directories...]

Hybrid file sharing: Cloudflare Worker authentication + cloudflared proxy.

Options:
  -p, --password PWD    Set password for access (auto-generates if not provided).
  --no-auth, --public   No authentication required (PUBLIC access).
  --port PORT           Local server port to start searching from (default: 8010).
  -d, --description     A description for the share.
  -q, --quiet           Suppress informational output.
  -h, --help            Show this help message.

Environment Variables:
  CFFILE_WORKER_URL     Set the URL for the authentication worker.
EOF
}

# Prepare files for sharing in a temporary directory
prepare_files() {
    if [ ${#FILES[@]} -eq 0 ]; then
        log "📂 Serving current directory: $(pwd)"
        return
    fi

    log "📁 Preparing ${#FILES[@]} file(s) for sharing..."
    TEMP_DIR=$(mktemp -d /tmp/cffile-hybrid.XXXXXX)
    
    for file in "${FILES[@]}"; do
        if [[ -e "$file" ]]; then
            # Using rsync for more robust copying of directories
            rsync -a --relative "$file" "$TEMP_DIR/"
            log "   ✓ Added: $(basename "$file")"
        else
            log "   ⚠️  Warning: '$file' not found, skipping."
        fi
    done
    
    cd "$TEMP_DIR" || { error "Failed to access temp directory"; exit 1; }
}

# Find an available port
find_available_port() {
    log "🔍 Finding an available port starting from $PORT..."
    while lsof -ti:$PORT >/dev/null 2>&1; do
        log "   Port $PORT is in use, trying next..."
        PORT=$((PORT + 1))
    done
    log "✅ Port $PORT is available."
}

# Start the local Python HTTP server
start_local_server() {
    log "🚀 Starting local HTTP server on port $PORT..."
    python3 -m http.server "$PORT" > /dev/null 2>&1 &
    PYTHON_PID=$!
    sleep 1 # Give the server a moment to start

    if ! kill -0 "$PYTHON_PID" 2>/dev/null;
    then
        error "Failed to start Python server."
        exit 1
    fi
    log "✅ Local server running at http://localhost:$PORT (PID: $PYTHON_PID)"
}

# Start the cloudflared tunnel
start_cloudflared() {
    log "🌐 Creating cloudflared tunnel..."
    CLOUDFLARED_OUTPUT=$(mktemp)
    cloudflared tunnel --url "http://localhost:$PORT" > "$CLOUDFLARED_OUTPUT" 2>&1 &
    CLOUDFLARED_PID=$!

    log "⏳ Waiting for tunnel URL..."
    local attempts=0
    while [[ -z "$TUNNEL_URL" && $attempts -lt 15 ]]; do
        sleep 1
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare\.com' "$CLOUDFLARED_OUTPUT")
        attempts=$((attempts + 1))
    done

    if [[ -z "$TUNNEL_URL" ]]; then
        error "Failed to get cloudflared tunnel URL."
        cat "$CLOUDFLARED_OUTPUT"
        exit 1
    fi
    log "✅ Tunnel URL: $TUNNEL_URL (PID: $CLOUDFLARED_PID)"
}

# Register the tunnel with the authentication worker
register_with_worker() {
    if $NO_AUTH;
    then
        return
    fi
    
    log "🔐 Registering with authentication worker..."
    local tunnel_id="hybrid-$(date +%s | tail -c 6)-$$"
    
    local register_payload
    register_payload=$(jq -n \
      --arg id "$tunnel_id" \
      --arg pass "$PASSWORD" \
      --arg port "$PORT" \
      --arg url "$TUNNEL_URL" \
      --arg desc "$DESCRIPTION" \
      '{tunnelId: $id, password: $pass, port: $port, cloudflaredUrl: $url, description: $desc}')

    REGISTER_RESPONSE=$(curl -s -X POST "$WORKER_URL/api/register" \
      -H "Content-Type: application/json" \
      -d "$register_payload")

    if ! echo "$REGISTER_RESPONSE" | jq -e .success &>/dev/null;
    then
        error "Failed to register with authentication worker."
        echo "$REGISTER_RESPONSE" | jq .
        exit 1
    fi
    
    AUTH_URL=$(echo "$REGISTER_RESPONSE" | jq -r .authUrl)
    log "✅ Authentication layer registered."
}

# Print the final summary
print_summary() {
    local border="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if $NO_AUTH;
    then
        log "\n$border\n🎉 [bold green]Public file sharing is now active![/bold green]\n$border"
        log "🔗 [bold]Public URL:[/bold] $TUNNEL_URL"
        log "[yellow]⚠️  Warning: This URL is PUBLIC - anyone can access.[/yellow]"
    else
        log "\n$border\n🎉 [bold green]Password-protected sharing is now active![/bold green]\n$border"
        log "🔐 [bold]Gated URL:[/bold] $AUTH_URL"
        log "   [bold]Password:[/bold] $PASSWORD"
        log "\n[yellow]⚠️  Security Note: The password only gates access to the direct tunnel URL.[/yellow]"
        log "[yellow]   For true end-to-end encryption, use a tool like 'cfsecure'.[/yellow]"
    fi
    
    log "\n🖥️  [bold]Local Server:[/bold] http://localhost:$PORT"
    log "🛑 Press Ctrl+C to stop sharing."
    log "$border"

    # Copy the appropriate URL to the clipboard
    if command -v pbcopy &>/dev/null;
    then
        local url_to_copy=${AUTH_URL:-$TUNNEL_URL}
        echo "$url_to_copy" | pbcopy
        log "📋 Sharable URL copied to clipboard."
    fi
}

# Main loop to keep the script alive
main_loop() {
    while true;
    do
        if ! kill -0 "$PYTHON_PID" 2>/dev/null;
        then
            error "Python server stopped unexpectedly."
            break
        fi
        if ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null;
        then
            error "cloudflared tunnel stopped unexpectedly."
            break
        fi
        sleep 5
    done
}

# Cleanup function on exit
cleanup() {
    echo "" # Newline for cleaner exit
    log "🛑 Shutting down..."
    
    if [[ -n "$CLOUDFLARED_PID" ]]; then
        kill "$CLOUDFLARED_PID" 2>/dev/null && log "   ✓ cloudflared tunnel stopped."
    fi
    if [[ -n "$PYTHON_PID" ]]; then
        kill "$PYTHON_PID" 2>/dev/null && log "   ✓ Python server stopped."
    fi
    
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "   ✓ Temporary files cleaned up."
    fi
    
    log "✅ Shutdown complete."
    exit 0
}

# ==============================================================================
# Main Execution
# ==============================================================================

trap cleanup SIGINT SIGTERM EXIT

parse_arguments "$@"
check_dependencies

if ! $NO_AUTH && [[ -z "$PASSWORD" ]]; then
    PASSWORD="cffile-$(date +%s | tail -c 5)"
    log "🔑 No password provided, auto-generating one: [bold cyan]$PASSWORD[/bold cyan]"
fi

if [[ -z "$DESCRIPTION" ]]; then
    if [[ ${#FILES[@]} -gt 0 ]]; then
        DESCRIPTION="${#FILES[@]} item(s)"
    else
        DESCRIPTION="Current directory"
    fi
fi

ORIGINAL_DIR=$(pwd)
prepare_files
find_available_port
start_local_server
start_cloudflared
register_with_worker
print_summary
main_loop
