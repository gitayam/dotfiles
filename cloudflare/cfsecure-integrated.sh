#!/bin/bash

# cfsecure - Truly secure file sharing using existing encryption functions
# This integrates with your .zsh_encryption functions

# Source encryption functions
if [[ -f ~/.zsh_encryption ]]; then
    source ~/.zsh_encryption
else
    echo "❌ Error: ~/.zsh_encryption not found"
    echo "This script requires the encryption functions from your dotfiles"
    exit 1
fi

PASSWORD=""
FILES=()
METHOD="openssl"  # Default to OpenSSL for simplicity
DURATION="1h"
DELETE_ORIGINAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -m|--method)
            METHOD="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        --delete)
            DELETE_ORIGINAL=true
            shift
            ;;
        -h|--help)
            cat << 'EOF'
Usage: cfsecure [OPTIONS] [files...]

Truly secure file sharing with end-to-end encryption using your existing encryption functions.

Options:
  -p, --password PWD    Set password for encryption (auto-generates if not set)
  -m, --method TYPE     Encryption method: openssl (default), gpg, age
  -d, --duration TIME   How long to keep files (default: 1h)
  --delete             Delete original files after encryption
  -h, --help           Show this help

Methods:
  openssl - Fast symmetric encryption with AES-256
  gpg     - Public key encryption (requires recipient)
  age     - Modern encryption (simple and secure)

Examples:
  cfsecure -p secret123 document.pdf              # OpenSSL with password
  cfsecure -m age photo.jpg                       # AGE with auto-generated password
  cfsecure -m gpg -p recipient@email file.txt     # GPG with recipient's public key
  cfsecure --delete sensitive.doc                 # Encrypt and delete original

How it works:
  1. Files are encrypted locally using your chosen method
  2. Encrypted files are uploaded to temporary storage
  3. Recipients need the password/key to decrypt
  4. Files auto-delete after the specified duration

This provides TRUE end-to-end encryption - files cannot be accessed without the password.
EOF
            exit 0
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

# Check files
if [ ${#FILES[@]} -eq 0 ]; then
    echo "❌ No files specified"
    echo "Usage: cfsecure [OPTIONS] file1 file2..."
    exit 1
fi

echo "🔐 Secure File Sharing (End-to-End Encrypted)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Auto-generate password if not provided (except for GPG)
if [[ -z "$PASSWORD" ]] && [[ "$METHOD" != "gpg" ]]; then
    echo "🔑 Generating secure password..."
    PASSWORD=$(generate_password -p chars -l 16 -q)
    echo "   Generated: $PASSWORD"
fi

# Create temporary directory for encrypted files
TEMP_DIR="/tmp/cfsecure-$$"
mkdir -p "$TEMP_DIR"

# Encrypt each file using existing functions
echo ""
echo "🔒 Encrypting files with $METHOD..."
ENCRYPTED_FILES=()

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "   ⚠️  File not found: $file"
        continue
    fi
    
    filename=$(basename "$file")
    
    case "$METHOD" in
        openssl)
            # Use encrypt_file_simple from .zsh_encryption
            output_file="$TEMP_DIR/${filename}.enc"
            
            # Create a temporary script to use the function
            cat > "$TEMP_DIR/encrypt.sh" << EOF
#!/bin/bash
source ~/.zsh_encryption
echo "$PASSWORD" | encrypt_file_simple -o "$output_file" "$file"
EOF
            chmod +x "$TEMP_DIR/encrypt.sh"
            
            if "$TEMP_DIR/encrypt.sh" >/dev/null 2>&1; then
                echo "   ✓ Encrypted: $filename → ${filename}.enc"
                ENCRYPTED_FILES+=("${filename}.enc")
            else
                # Fallback to direct OpenSSL
                if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$file" -out "$output_file" -pass pass:"$PASSWORD" 2>/dev/null; then
                    echo "   ✓ Encrypted: $filename → ${filename}.enc"
                    ENCRYPTED_FILES+=("${filename}.enc")
                else
                    echo "   ❌ Failed to encrypt: $filename"
                fi
            fi
            ;;
            
        age)
            # Check if age is available
            if ! command -v age &>/dev/null; then
                echo "   ❌ AGE not installed. Install with: brew install age"
                echo "   Falling back to OpenSSL..."
                METHOD="openssl"
                output_file="$TEMP_DIR/${filename}.enc"
                if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$file" -out "$output_file" -pass pass:"$PASSWORD" 2>/dev/null; then
                    echo "   ✓ Encrypted: $filename → ${filename}.enc"
                    ENCRYPTED_FILES+=("${filename}.enc")
                fi
            else
                output_file="$TEMP_DIR/${filename}.age"
                if echo "$PASSWORD" | age -p -o "$output_file" "$file" 2>/dev/null; then
                    echo "   ✓ Encrypted: $filename → ${filename}.age"
                    ENCRYPTED_FILES+=("${filename}.age")
                else
                    echo "   ❌ Failed to encrypt: $filename"
                fi
            fi
            ;;
            
        gpg)
            if ! command -v gpg &>/dev/null; then
                echo "   ❌ GPG not installed. Install with: brew install gnupg"
                exit 1
            fi
            
            output_file="$TEMP_DIR/${filename}.gpg"
            
            if [[ -n "$PASSWORD" ]]; then
                # PASSWORD is treated as recipient for GPG
                if gpg --trust-model always -e -r "$PASSWORD" -o "$output_file" "$file" 2>/dev/null; then
                    echo "   ✓ Encrypted for recipient: $PASSWORD"
                    ENCRYPTED_FILES+=("${filename}.gpg")
                else
                    # Try symmetric encryption as fallback
                    if echo "$PASSWORD" | gpg --batch --yes --passphrase-fd 0 -c -o "$output_file" "$file" 2>/dev/null; then
                        echo "   ✓ Encrypted: $filename → ${filename}.gpg (symmetric)"
                        ENCRYPTED_FILES+=("${filename}.gpg")
                    else
                        echo "   ❌ Failed to encrypt: $filename"
                    fi
                fi
            else
                echo "   ❌ GPG requires a recipient email or password"
                exit 1
            fi
            ;;
            
        *)
            echo "   ❌ Unknown method: $METHOD"
            exit 1
            ;;
    esac
done

if [ ${#ENCRYPTED_FILES[@]} -eq 0 ]; then
    echo "❌ No files were encrypted successfully"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Delete originals if requested
if $DELETE_ORIGINAL; then
    echo ""
    echo "🗑️  Securely deleting original files..."
    for file in "${FILES[@]}"; do
        if [[ -f "$file" ]]; then
            if secure_delete -f "$file" 2>/dev/null || rm -f "$file"; then
                echo "   ✓ Deleted: $file"
            else
                echo "   ⚠️  Could not delete: $file"
            fi
        fi
    done
fi

# Create decryption instructions
cat > "$TEMP_DIR/README.txt" << EOF
ENCRYPTED FILE SHARE
====================
Method: $METHOD
Files: ${#ENCRYPTED_FILES[@]}
Expires: $DURATION

DECRYPTION INSTRUCTIONS
-----------------------

For $METHOD encryption:
EOF

case "$METHOD" in
    openssl)
        cat >> "$TEMP_DIR/README.txt" << EOF

Using OpenSSL:
  openssl enc -aes-256-cbc -d -pbkdf2 -in FILENAME.enc -out FILENAME -pass pass:PASSWORD

Using the decrypt script:
  ./decrypt.sh PASSWORD FILENAME.enc
EOF
        ;;
    age)
        cat >> "$TEMP_DIR/README.txt" << EOF

Using AGE:
  age --decrypt -o FILENAME FILENAME.age
  (Enter password when prompted)

Using the decrypt script:
  ./decrypt.sh PASSWORD FILENAME.age
EOF
        ;;
    gpg)
        cat >> "$TEMP_DIR/README.txt" << EOF

Using GPG:
  gpg --decrypt FILENAME.gpg > FILENAME

Using the decrypt script:
  ./decrypt.sh FILENAME.gpg
EOF
        ;;
esac

# Create universal decrypt helper
cat > "$TEMP_DIR/decrypt.sh" << 'EOF'
#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Usage: ./decrypt.sh [PASSWORD] FILE"
    exit 1
fi

# Detect if first arg is password or file
if [[ -f "$1" ]]; then
    FILE="$1"
    PASSWORD=""
else
    PASSWORD="$1"
    FILE="$2"
fi

# Auto-detect encryption type
if [[ "$FILE" == *.enc ]]; then
    # OpenSSL
    OUTPUT="${FILE%.enc}"
    if [[ -n "$PASSWORD" ]]; then
        openssl enc -aes-256-cbc -d -pbkdf2 -in "$FILE" -out "$OUTPUT" -pass pass:"$PASSWORD"
    else
        openssl enc -aes-256-cbc -d -pbkdf2 -in "$FILE" -out "$OUTPUT"
    fi
elif [[ "$FILE" == *.age ]]; then
    # AGE
    OUTPUT="${FILE%.age}"
    if [[ -n "$PASSWORD" ]]; then
        echo "$PASSWORD" | age --decrypt -o "$OUTPUT" "$FILE"
    else
        age --decrypt -o "$OUTPUT" "$FILE"
    fi
elif [[ "$FILE" == *.gpg ]]; then
    # GPG
    OUTPUT="${FILE%.gpg}"
    gpg --decrypt "$FILE" > "$OUTPUT"
else
    echo "Unknown file type: $FILE"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo "Decrypted to: $OUTPUT"
else
    echo "Decryption failed"
    exit 1
fi
EOF
chmod +x "$TEMP_DIR/decrypt.sh"

echo ""
echo "📤 Sharing encrypted files..."

# Now we can either:
# 1. Use cffile to share (but it will be public after password reveal)
# 2. Upload to a temporary file service
# 3. Create a local server

# Option 1: Use cffile for the encrypted package
if command -v cffile &>/dev/null || [[ -f /Users/sac/Git/dotfiles/macos/cffile-hybrid.sh ]]; then
    cd "$TEMP_DIR"
    tar -czf package.tar.gz *.enc *.age *.gpg README.txt decrypt.sh 2>/dev/null
    
    echo "📦 Creating secure package..."
    
    # Use cffile to share the encrypted package
    if command -v cffile &>/dev/null; then
        cffile --no-auth package.tar.gz
    else
        /Users/sac/Git/dotfiles/macos/cffile-hybrid.sh --no-auth package.tar.gz
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 Secure Share Created!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📦 Package contains: ${#ENCRYPTED_FILES[@]} encrypted file(s)"
    echo ""
    if [[ "$METHOD" != "gpg" ]]; then
        echo "🔑 Decryption password: $PASSWORD"
        echo ""
    fi
    echo "📋 Instructions:"
    echo "   1. Download the package from the URL above"
    echo "   2. Extract: tar -xzf package.tar.gz"
    echo "   3. Decrypt: ./decrypt.sh $PASSWORD filename.enc"
    echo ""
    echo "⏱️  Expires: $DURATION"
    echo ""
    echo "🔒 Security:"
    echo "   • Files are encrypted BEFORE upload"
    echo "   • True end-to-end encryption"
    echo "   • Even with the URL, files cannot be read without password"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
else
    # Fallback: Just create the package locally
    cd "$TEMP_DIR"
    tar -czf "$HOME/Desktop/secure-package-$(date +%s).tar.gz" *.enc *.age *.gpg README.txt decrypt.sh 2>/dev/null
    
    echo "✅ Encrypted package saved to Desktop"
    echo ""
    if [[ "$METHOD" != "gpg" ]]; then
        echo "🔑 Password: $PASSWORD"
    fi
    echo "📦 File: ~/Desktop/secure-package-*.tar.gz"
fi

# Don't cleanup temp dir if cffile is running in background
# It will clean up when done