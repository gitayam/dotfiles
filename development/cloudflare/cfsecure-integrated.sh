#!/bin/bash

# cfsecure - Truly secure, end-to-end encrypted file sharing.
# Enhanced by Gemini

# ==============================================================================
# Configuration & Globals
# ==============================================================================
PASSWORD=""
FILES=()
METHOD="openssl"
DURATION="1h"
DELETE_ORIGINAL=false
QUIET=false
CFFILE_PATH=""

# ==============================================================================
# Helper Functions
# ==============================================================================

log() {
    if [[ "$QUIET" == false ]]; then
        echo "$@"
    fi
}

error() {
    echo "❌ Error: $@" >&2
}

check_dependencies() {
    log "🔍 Checking dependencies..."
    local missing=0
    local required_cmds="tar gzip"

    case "$METHOD" in
        openssl) required_cmds+=" openssl" ;; 
        age) required_cmds+=" age" ;; 
        gpg) required_cmds+=" gpg" ;; 
    esac

    for cmd in $required_cmds; do
        if ! command -v "$cmd" &>/dev/null; then
            error "'$cmd' is not installed. Please install it to continue."
            missing=1
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

find_cffile_script() {
    if [[ -n "$CFFILE_PATH" && -x "$CFFILE_PATH" ]]; then
        return 0
    fi
    
    # Search in common locations
    local search_paths=(
        "$(dirname "$0")/cffile-hybrid.sh"
        "~/Git/dotfiles/development/cloudflare/cffile-hybrid.sh"
        "../scripts/cffile-hybrid.sh"
    )
    for path in "${search_paths[@]}"; do
        local expanded_path="${path/#\~/$HOME}"
        if [[ -x "$expanded_path" ]]; then
            CFFILE_PATH="$expanded_path"
            log "✅ Found cffile script at: $CFFILE_PATH"
            return 0
        fi
    done
    
    if command -v cffile &>/dev/null; then
        CFFILE_PATH="$(command -v cffile)"
        log "✅ Found cffile command in PATH: $CFFILE_PATH"
        return 0
    fi

    return 1
}


# ==============================================================================
# Encryption Functions (Self-Contained)
# ==============================================================================

_encrypt_openssl() {
    local input_file="$1"
    local output_file="$2"
    local pass="$3"
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$input_file" -out "$output_file" -pass pass:"$pass"
}

_encrypt_age() {
    local input_file="$1"
    local output_file="$2"
    local pass="$3"
    echo "$pass" | age -p -o "$output_file" "$input_file"
}

_encrypt_gpg() {
    local input_file="$1"
    local output_file="$2"
    local recipient="$3" # For GPG, password is the recipient
    
    # Try public key encryption first
    if gpg --trust-model always -e -r "$recipient" -o "$output_file" "$input_file" &>/dev/null; then
        log "   🔑 Encrypted for GPG recipient: $recipient"
        return 0
    fi
    
    # Fallback to symmetric encryption if recipient key not found
    log "   ⚠️ GPG recipient key not found, falling back to symmetric encryption..."
    echo "$recipient" | gpg --batch --yes --passphrase-fd 0 -c -o "$output_file" "$input_file"
}


# ==============================================================================
# Main Logic
# ==============================================================================

# Parse arguments... (This is a simplified version, can be expanded)
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password) PASSWORD="$2"; shift 2 ;; 
        -m|--method) METHOD="$2"; shift 2 ;; 
        # ... other arguments
        *) FILES+=("$1"); shift ;; 
    esac
done

# --- Main Execution Flow ---

check_dependencies

if [ ${#FILES[@]} -eq 0 ]; then
    error "No files specified."
    # print_help
    exit 1
fi

log "🔐 Secure File Sharing (End-to-End Encrypted)"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -z "$PASSWORD" && "$METHOD" != "gpg" ]]; then
    log "🔑 No password provided. Generating a secure one..."
    PASSWORD=$(openssl rand -base64 16)
    log "   [bold cyan]Generated Password:[/bold cyan] $PASSWORD"
fi

TEMP_DIR=$(mktemp -d /tmp/cfsecure.XXXXXX)
ENCRYPTED_FILES=()

log "\n🔒 Encrypting files with [bold]$METHOD[/bold]..."
for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        log "   ⚠️  File not found: $file"
        continue
    fi
    
    filename=$(basename "$file")
    output_file="$TEMP_DIR/$filename.$METHOD.enc"
    
    log -n "   Encrypting '$filename'...";
    case "$METHOD" in
        openssl) _encrypt_openssl "$file" "$output_file" "$PASSWORD" ;; 
        age) _encrypt_age "$file" "$output_file" "$PASSWORD" ;; 
        gpg) _encrypt_gpg "$file" "$output_file" "$PASSWORD" # Password is recipient 
        *) error "Unknown encryption method: $METHOD"; exit 1 ;; 
    esac
    
    if [[ $? -eq 0 ]]; then
        log " [bold green]✓[/bold green]"
        ENCRYPTED_FILES+=("$output_file")
    else
        log " [bold red]✗ FAILED[/bold red]"
    fi
done

if [ ${#ENCRYPTED_FILES[@]} -eq 0 ]; then
    error "No files were encrypted successfully."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Create README and decrypt script...
# (Logic for creating README.txt and decrypt.sh can be added here)

log "\n📦 Creating secure package..."
cd "$TEMP_DIR" || exit 1
PACKAGE_NAME="secure-package-$(date +%s).tar.gz"
tar -czf "$PACKAGE_NAME" ./*

log "📤 Uploading secure package..."
if ! find_cffile_script; then
    error "cffile script not found. Cannot upload."
    log "Your encrypted package is available at: $TEMP_DIR/$PACKAGE_NAME"
    exit 1
fi

# Use the cffile script to share the encrypted package
CFFILE_OUTPUT=$("$CFFILE_PATH" --no-auth "$PACKAGE_NAME")
UPLOAD_URL=$(echo "$CFFILE_OUTPUT" | grep -o 'https://.*\.trycloudflare\.com')

log "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "✅ [bold green]Secure Share Created![/bold green]"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🔗 [bold]Download URL:[/bold] $UPLOAD_URL"
if [[ "$METHOD" != "gpg" ]]; then
    log "🔑 [bold]Decryption Password:[/bold] $PASSWORD"
fi
log "⏱️  [bold]Expires:[/bold] (Based on cffile settings)"
log "\n[bold]Instructions for recipient:[/bold]"
log "   1. Download and extract the package."
log "   2. Use the password and the appropriate tool ($METHOD) to decrypt the files."
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup
rm -rf "$TEMP_DIR"
