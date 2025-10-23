# ----------------------
# Core Utility Functions for Bash
# ----------------------

# Navigation and Directory Functions
cdl() {
  if [ -n "$1" ]; then
    cd "$1" && ll
  else
    cd ~ && ll
  fi
}

# Create directory and change to it
mkd(){
    if [[ -z "$1" ]]; then
        echo "No directory name provided"
        return 1
    # If multiple args are passed then make the dirs and list them
    elif [[ $# -gt 1 ]]; then
        mkdir -p "$@" && ls -l "$@"
    # Otherwise, make the dir and cd to it (single argument case)
    else
        mkdir -p "$1" && cd "$1"
        pwd # print the current directory
        ls -la # list the directory contents 
    fi
}

# Backup function
backup() {
  backup_name=".bak_$(date +%Y-%m-%d_%H-%M-%S)"
  if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
  else
    COPY_CMD="cp"
  fi
  for file in "$@"; do
    if [ -f "$file" ]; then
      $COPY_CMD "$file" "$file$backup_name"
      echo "Backup of $file created as $file$backup_name"
    elif [ -d "$file" ]; then
      $COPY_CMD -r "$file" "$file$backup_name"
      echo "Backup of $file created as $file$backup_name"
    else
      echo "$file does not exist"
    fi
  done
}

# Create a zip archive
zipfile(){
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "usage: zipfile name_of_zip_file file_or_dir1 file_or_dir2 ..."
        return 0
    fi
    
    if [[ -z "$1" ]]; then
        echo "Error: No zip file name provided"
        echo "usage: zipfile name_of_zip_file file_or_dir1 file_or_dir2 ..."
        return 1
    fi
    
    local zip_name="$1"
    shift
    
    if [[ $# -eq 0 ]]; then
        echo "Error: No files or directories to zip"
        echo "usage: zipfile name_of_zip_file file_or_dir1 file_or_dir2 ..."
        return 1
    fi
    
    # Add .zip extension if not present
    if [[ "$zip_name" != *.zip ]]; then
        zip_name="${zip_name}.zip"
    fi
    
    echo "Creating zip archive: $zip_name"
    if zip -r "$zip_name" "$@"; then
        echo "✅ Successfully created: $zip_name"
        ls -lh "$zip_name"
    else
        echo "❌ Failed to create zip archive"
        return 1
    fi
}

# Nano Functions
reset_file() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: reset_file file1 file2 ..."
        return 0
    fi
    
    for file in "$@"; do
        backup "$file"
        : > "$file"  # Clear file content
        echo "File content backed up and erased."
        echo "Opening $file in nano editor"
        # Add filename as comment at top
        echo "# $file" >> "$file"
        sleep 0.5
        nano "$file"
        
        # Show backup file
        ls -la "$file"*bak* 2>/dev/null | tail -1
        
        # Prompt for diff and restore options
        see_diff="n"
        read -p "Do you want to see the difference between the original and backup file? (y/n):(default:n) " see_diff
        if [ "$see_diff" == "y" ]; then
            # Find the most recent backup
            backup_file=$(ls -t "$file"*bak* 2>/dev/null | head -1)
            if [ -n "$backup_file" ]; then
                diff "$file" "$backup_file"
                restore_backup="n"
                read -p "Do you want to restore the backup file? (y/n):(default:n) " restore_backup
                if [ "$restore_backup" == "y" ]; then
                    mv "$backup_file" "$file"
                    echo "Backup file restored."
                fi
            else
                echo "No backup file found."
            fi
        fi
    done
}

# Python virtual environment
pyenv() {
  python3 -m venv env
  source env/bin/activate
}

# Python HTTP server
pyserver(){
  local_ip=$(hostname -I | awk '{print $1}')
  if [ -n "$1" ]; then
    mkdir -p /tmp/pyserver
    for file in "$@"; do
      ln -s "$file" /tmp/pyserver
    done
    cd /tmp/pyserver
  fi
}

# Docker helpers can be added here

# Display system info
# (moved to .bash_system)

# --- BEGIN: migrated from .bash_aliases ---

# General-purpose functions
update_git_repos() {
    search_path="/home/"
    exclude_paths=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --home) search_path="/home/" ;;
            --exclude) exclude_paths="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done
    IFS=' ' read -r -a exclude_array <<< "$exclude_paths"
    find_cmd="find \"$search_path\" -type d -name \".git\""
    for exclude in "${exclude_array[@]}"; do
        find_cmd+=" ! -path \"$exclude*\""
    done
    find_cmd+=" -print"
    eval "$find_cmd" | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        git config --global --add safe.directory "$repo_dir"
        echo "Updating repository in $repo_dir"
        cd "$repo_dir" || continue
        git pull
    done
}

upgrade_system() {
    echo "Starting system upgrade and cleanup... (running in background)"
    {
        LOG_FILE="/var/log/system_upgrade.log"
        echo "Logging to $LOG_FILE"
        if [[ $EUID -ne 0 ]]; then
            echo "Please run as root or with sudo." | tee -a "$LOG_FILE"
            return 1
        fi
        echo "Updating package index..." | tee -a "$LOG_FILE"
        apt update >> "$LOG_FILE" 2>&1
        echo "Upgrading packages..." | tee -a "$LOG_FILE"
        apt full-upgrade -y >> "$LOG_FILE" 2>&1
        echo "Cleaning up unused packages..." | tee -a "$LOG_FILE"
        apt autoremove -y >> "$LOG_FILE" 2>&1
        apt autoclean >> "$LOG_FILE" 2>&1
        if [ -f /var/run/reboot-required ]; then
            echo "System reboot is recommended." | tee -a "$LOG_FILE"
        else
            echo "No reboot is required." | tee -a "$LOG_FILE"
        fi
        echo "System upgrade and cleanup complete!" | tee -a "$LOG_FILE"
    } &
    disown
    echo "System upgrade and cleanup is running in the background. Check $LOG_FILE for details."
}

findex() {
  if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
    echo "Usage: findex [OPTIONS] [PATH] PATTERN COMMAND [--shift] [ARGS...]"
    echo "... (see .bash_aliases for full help) ..."
    return 0
  fi
  # ... (full implementation in .bash_aliases) ...
}

mkd() {
    if [[ -z "$1" ]]; then
        echo "No directory name provided"
        return 1
    elif [[ $# -gt 1 ]]; then
        mkdir -p "$@" && ls -l "$@"
    else
        mkdir -p "$1" && cd "$1"
        pwd
        ls -la
    fi
}

# Wormhole file transfer helpers
alias wh="wormhole"
alias wht="wh-transfer"
wh-transfer() {
    trap '[[ -f "$zip_file" ]] && rm -rf "$zip_file"' EXIT
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: wh-transfer [-e|--encrypt] path1 path2 ..."
        echo "The default is to send the files as is"
        echo "-e or --encrypt will encrypt the files before sending using age, gpg, or aes"
        return 0
    fi
    encrypt_and_send() {
        local encrypt_tool="$1"
        shift
        local files=("$@")
        local zip_file="./wormhole_$(date +%Y%m%d%H%M%S).zip"
        zip "$zip_file" "${files[@]}"
        local encrypted_file="${zip_file}.age"
        if [[ "$encrypt_tool" == "gpg" ]]; then
            encrypted_file="${zip_file}.gpg"
            gpg --output "$encrypted_file" --symmetric "$zip_file"
        elif [[ "$encrypt_tool" == "aes" ]]; then
            encrypted_file="${zip_file}.aes"
            openssl enc -aes-256-cbc -salt -in "$zip_file" -out "$encrypted_file"
        else
            age -o "$encrypted_file" -p "$zip_file"
        fi
        wormhole send "$encrypted_file"
        rm -rf "$zip_file" "$encrypted_file"
    }
    if [[ "$1" == "-e" || "$1" == "--encrypt" ]]; then
        shift
        if command -v age &> /dev/null; then
            encrypt_and_send "age" "$@"
        elif command -v gpg &> /dev/null; then
            encrypt_and_send "gpg" "$@"
        else
            encrypt_and_send "aes" "$@"
        fi
    else
        if [[ "$#" -gt 1 ]]; then
            local zip_file="./wormhole_$(date +%Y%m%d%H%M%S).zip"
            zip "$zip_file" "$@"
            wormhole send "$zip_file"
            rm -rf "$zip_file"
        else
            wormhole send "$@"
        fi
    fi
}

# ----------------------
# Help and Documentation Functions
# ----------------------
show_func() {
    # Show function definition from bash config files
    local files=("$HOME/.bash_aliases" "$HOME/.bash_functions" "$HOME/.bash_apps" "$HOME/.bash_network" "$HOME/.bash_transfer" "$HOME/.bash_security" "$HOME/.bash_utils" "$HOME/.bash_system" "$HOME/.bash_docker")
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            # Look for function definitions
            grep -E "^\s*${1}\s*\(\)|^\s*function\s+${1}" "$file"
        fi
    done
}

alias show_function="show_func"

show_alias() {
    # Show all aliases in bash config files
    local files=("$HOME/.bash_aliases" "$HOME/.bash_functions" "$HOME/.bash_apps" "$HOME/.bash_network" "$HOME/.bash_transfer" "$HOME/.bash_security" "$HOME/.bash_utils" "$HOME/.bash_system" "$HOME/.bash_docker")
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo "Aliases in $file:"
            grep -E "^alias " "$file" | cut -d '=' -f 1 | sort | uniq
            echo ""
        fi
    done
}

show_help() {
    # Show help for a specific function or alias
    local files=("$HOME/.bash_aliases" "$HOME/.bash_functions" "$HOME/.bash_apps" "$HOME/.bash_network" "$HOME/.bash_transfer" "$HOME/.bash_security" "$HOME/.bash_utils" "$HOME/.bash_system" "$HOME/.bash_docker")
    
    if [[ -z "$1" ]]; then
        helpmenu
        return 0
    fi
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            grep -E "^\s*${1}\s*\(\)|^\s*function\s+${1}" "$file"
        fi
    done
}

helpmenu() {
    echo "Help Menu:"
    echo "----------"
    echo "See all functions: show_function"
    echo "See all aliases: show_alias"
    echo "See help for a function: show_help function_name"
    echo "See help for an alias: show_help alias_name"
    echo ""
    echo "Available function categories:"
    echo "  • Core utilities: .bash_functions"
    echo "  • Git/Development: .bash_developer"
    echo "  • Applications: .bash_apps"
    echo "  • Network tools: .bash_network"
    echo "  • File transfer: .bash_transfer"
    echo "  • Security tools: .bash_security"
    echo "  • System utilities: .bash_system"
    echo "  • Docker commands: .bash_docker"
    echo "  • AWS tools: .bash_aws"
    echo "  • Encryption: .bash_encryption"
    echo "  • File handling: .bash_handle_files"
    echo "  • General utilities: .bash_utils"
}

# Video/Audio manipulation functions (Linux adaptations)
# Normalize time to hh:mm:ss format
normalize_time() {
    local input="$1"
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        printf "00:00:%02d" "$input"
    elif [[ "$input" =~ ^[0-9]+:[0-9]+$ ]]; then
        printf "00:%s" "$input"
    else
        echo "$input"
    fi
}

# Sanitize filename - remove spaces and special characters
sanitize_filename() {
    local filename="$1"
    # Convert to lowercase, replace spaces with underscores, keep only alphanumeric, underscores, dots, and dashes
    echo "$filename" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_.-'
}

# Check and fix video format compatibility issues for Signal/iOS/Android
# Converts incompatible videos to Signal-compatible format (H.264 Main + AAC + yuv420p in MP4)
check_video_format() {
    local video_file="$1"
    local auto_fix="${2:-true}"  # Auto-fix by default
    local output_path="${3:-}"    # Optional output path

    if [[ -z "$video_file" ]]; then
        echo "Usage: check_video_format <video_file> [auto_fix:true|false] [output_path]"
        echo ""
        echo "Checks video format compatibility with Signal/iOS/Android and fixes issues."
        echo "Ensures H.264 video, AAC audio, yuv420p pixel format, and MP4 container."
        echo "Output defaults to /tmp/, falls back to ./ or ~/ if permission issues."
        echo ""
        echo "Examples:"
        echo "  check_video_format video.mp4                      # Check and auto-fix to /tmp/"
        echo "  check_video_format video.mp4 false                # Check only, don't fix"
        echo "  check_video_format video.webm                     # Convert WebM to /tmp/"
        echo "  check_video_format video.mp4 true ~/Downloads    # Fix to specific directory"
        echo ""
        echo "Aliases:"
        echo "  vcheck, vfix, vinfo = check_video_format"
        echo "  signalfix = check_video_format (Signal-optimized)"
        return 1
    fi

    if [[ ! -f "$video_file" ]]; then
        echo "❌ Error: File not found: $video_file"
        return 1
    fi

    # Check if ffprobe and ffmpeg are installed
    if ! command -v ffprobe &>/dev/null; then
        echo "❌ ffprobe not found. Install ffmpeg:"
        echo "   Ubuntu/Debian: sudo apt install ffmpeg"
        echo "   Fedora: sudo dnf install ffmpeg"
        echo "   Arch: sudo pacman -S ffmpeg"
        return 1
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "❌ ffmpeg not found. Install ffmpeg:"
        echo "   Ubuntu/Debian: sudo apt install ffmpeg"
        echo "   Fedora: sudo dnf install ffmpeg"
        echo "   Arch: sudo pacman -S ffmpeg"
        return 1
    fi

    echo "🔍 Analyzing video format: $video_file"
    echo ""

    # Get video information
    local video_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local container=$(ffprobe -v error -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local pix_fmt=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local profile=$(ffprobe -v error -select_streams v:0 -show_entries stream=profile -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local level=$(ffprobe -v error -select_streams v:0 -show_entries stream=level -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    local file_size=$(stat -c%s "$video_file" 2>/dev/null)  # Linux uses -c instead of -f
    local file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc 2>/dev/null)

    # Display current format
    echo "📊 Current Format:"
    echo "   Container: $container"
    echo "   Video Codec: ${video_codec:-none}"
    [[ -n "$profile" ]] && echo "   H.264 Profile: $profile"
    [[ -n "$level" ]] && echo "   H.264 Level: $level"
    [[ -n "$pix_fmt" ]] && echo "   Pixel Format: $pix_fmt"
    echo "   Audio Codec: ${audio_codec:-none}"
    [[ -n "$width" && -n "$height" ]] && echo "   Resolution: ${width}x${height}"
    [[ -n "$duration" ]] && printf "   Duration: %.2f seconds\n" "$duration"
    [[ -n "$file_size_mb" ]] && printf "   File Size: %.2f MB\n" "$file_size_mb"
    echo ""

    # Check compatibility
    local needs_fix=false
    local issues=()

    # Signal/iOS/Android compatibility requirements: H.264 video, AAC audio, MP4 container, yuv420p pixel format
    if [[ "$video_codec" != "h264" && -n "$video_codec" ]]; then
        needs_fix=true
        issues+=("Video codec '$video_codec' not compatible with Signal/iOS (requires H.264)")
    fi

    # Check pixel format - CRITICAL for iOS/Android/Signal compatibility
    if [[ "$pix_fmt" != "yuv420p" && -n "$pix_fmt" && -n "$video_codec" ]]; then
        needs_fix=true
        issues+=("Pixel format '$pix_fmt' incompatible with Signal/iOS (requires yuv420p)")
    fi

    # Check H.264 profile - Main or Baseline recommended for mobile
    if [[ "$video_codec" == "h264" && -n "$profile" ]]; then
        if [[ "$profile" == *"High 4:4:4"* || "$profile" == *"High 10"* ]]; then
            needs_fix=true
            issues+=("H.264 profile '$profile' not supported on mobile devices (use Main or Baseline)")
        fi
    fi

    if [[ "$audio_codec" != "aac" && -n "$audio_codec" ]]; then
        needs_fix=true
        issues+=("Audio codec '$audio_codec' may not be compatible (prefer AAC)")
    fi

    # Signal requires MP4 container (MOV has cross-platform issues)
    if [[ "$container" != *"mp4"* ]]; then
        needs_fix=true
        if [[ "$container" == *"mov"* ]]; then
            issues+=("MOV container may not work on Signal Android (prefer MP4)")
        else
            issues+=("Container format '$container' not compatible with Signal (requires MP4)")
        fi
    fi

    # Special cases
    if [[ "$container" == *"matroska"* || "$container" == *"webm"* ]]; then
        needs_fix=true
        issues+=("MKV/WebM containers not supported by Signal/QuickTime")
    fi

    if [[ "$video_codec" == "vp9" || "$video_codec" == "vp8" || "$video_codec" == "av1" ]]; then
        needs_fix=true
        issues+=("VP8/VP9/AV1 codecs not supported by Signal/QuickTime (requires H.264)")
    fi

    if [[ "$video_codec" == "hevc" ]]; then
        needs_fix=true
        issues+=("HEVC/H.265 not supported by Signal for inline playback (requires H.264)")
    fi

    # Check file size for Signal compatibility (95 MB cross-platform limit)
    if [[ -n "$file_size_mb" ]] && (( $(echo "$file_size_mb > 95" | bc -l) )); then
        echo "⚠️  WARNING: File size (${file_size_mb} MB) exceeds Signal's cross-platform limit (95 MB)"
        echo "   Signal may compress or reject this video. Consider reducing quality."
        echo ""
    fi

    # Report issues
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "✅ Video format is compatible with Signal/iOS/Android/QuickTime!"
        echo "   No conversion needed."
        return 0
    fi

    echo "⚠️  Compatibility Issues Found:"
    for issue in "${issues[@]}"; do
        echo "   • $issue"
    done
    echo ""

    # Ask to fix if not auto-fixing
    if [[ "$auto_fix" != "true" ]]; then
        echo "Run with auto_fix=true to convert, or use:"
        echo "  check_video_format \"$video_file\" true"
        return 1
    fi

    # Determine output directory with fallback logic
    local input_name=$(basename "$video_file")
    local input_base="${input_name%.*}"
    local output_dir=""
    local tried_locations=()

    # Function to test if directory is writable
    _test_write_permission() {
        local test_dir="$1"
        local test_file="${test_dir}/.write_test_$$"

        if [[ ! -d "$test_dir" ]]; then
            return 1
        fi

        if touch "$test_file" 2>/dev/null; then
            rm -f "$test_file" 2>/dev/null
            return 0
        else
            return 1
        fi
    }

    # Try user-specified path first
    if [[ -n "$output_path" ]]; then
        # Expand ~ to home directory
        output_path="${output_path/#\~/$HOME}"

        if _test_write_permission "$output_path"; then
            output_dir="$output_path"
            echo "📁 Using specified output directory: $output_dir"
        else
            tried_locations+=("$output_path (no write permission)")
        fi
    fi

    # Try /tmp/ if no output dir yet
    if [[ -z "$output_dir" ]]; then
        if _test_write_permission "/tmp"; then
            output_dir="/tmp"
            echo "📁 Using /tmp/ for output"
        else
            tried_locations+=("/tmp (no write permission)")
        fi
    fi

    # Fall back to current directory
    if [[ -z "$output_dir" ]]; then
        if _test_write_permission "."; then
            output_dir="."
            echo "📁 Falling back to current directory"
        else
            tried_locations+=("./ (no write permission)")
        fi
    fi

    # Fall back to home directory
    if [[ -z "$output_dir" ]]; then
        if _test_write_permission "$HOME"; then
            output_dir="$HOME"
            echo "📁 Falling back to home directory"
        else
            tried_locations+=("~/ (no write permission)")
        fi
    fi

    # If still no writable location found, error out
    if [[ -z "$output_dir" ]]; then
        echo "❌ Error: Cannot find writable directory for output"
        echo "Tried locations:"
        for loc in "${tried_locations[@]}"; do
            echo "  • $loc"
        done
        return 1
    fi

    # Create output filename
    local output_file="${output_dir}/${input_base}_fixed.mp4"

    # Check if output already exists
    if [[ -f "$output_file" ]]; then
        echo "⚠️  Output file already exists: $output_file"
        read -p "Overwrite? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 1
        fi
    fi

    echo "🔧 Converting to Signal/iOS/Android-compatible format..."
    echo "   Output: $output_file"
    echo ""

    # Convert with Signal-optimized settings
    local start_time=$(date +%s)

    if ffmpeg -i "$video_file" \
        -c:v libx264 \
        -profile:v main \
        -level 3.1 \
        -pix_fmt yuv420p \
        -preset medium \
        -crf 23 \
        -c:a aac \
        -b:a 128k \
        -ac 2 \
        -movflags +faststart \
        -y \
        "$output_file"; then

        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        echo ""
        echo "✅ Conversion complete! (took ${elapsed}s)"
        echo ""
        echo "📊 New Format:"

        # Show new format info
        local new_video_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null)
        local new_audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null)
        local new_container=$(ffprobe -v error -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null | awk -F, '{print toupper($1)}')

        echo "   Container: $new_container"
        echo "   Video Codec: $new_video_codec"
        echo "   Audio Codec: $new_audio_codec"
        echo ""

        # File size comparison
        local new_size=$(stat -c%s "$output_file" 2>/dev/null)
        local new_size_mb=$(echo "scale=2; $new_size / 1048576" | bc)
        local size_diff=$((new_size - file_size))
        local size_diff_mb=$(echo "scale=2; $size_diff / 1048576" | bc)

        echo "   Original: ${file_size_mb} MB"
        echo "   New:      ${new_size_mb} MB"
        if (( $(echo "$size_diff > 0" | bc -l) )); then
            echo "   Increase: +${size_diff_mb} MB"
        else
            echo "   Decrease: ${size_diff_mb} MB"
        fi
        echo ""
        echo "🎬 Fixed video: $output_file"
        echo "   Ready for Signal/iOS/Android!"

        return 0
    else
        echo ""
        echo "❌ Conversion failed. Check the error messages above."
        return 1
    fi
}

download_video() {
    if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
        echo "Usage: download_video url [options]"
        echo "Options:"
        echo "  --output, -o FILENAME     Output filename (default: auto-generated from title)"
        echo "  --output-dir, -d DIR      Output directory (default: /tmp/, falls back to ./ or ~/)"
        echo "  --start, -s TIME          Start time (format: HH:MM:SS or seconds)"
        echo "  --end, -e TIME            End time (format: HH:MM:SS or seconds)"
        echo "  --quality, -q QUALITY     Video quality (best, 1080p, 720p, 480p, 360p, worst)"
        echo "  --format, -f FORMAT       Format (mp4, webm, mp3, etc.)"
        echo "  --subtitles, -sub         Download subtitles if available (default: false, default language: en)"
        echo "  --language, -l LANGUAGE   Language (default: en)"
        echo "  --audio-only, -a          Download audio only"
        echo "  --check-format            Check and fix video format for Signal/iOS/Android compatibility"
        echo "  --no-sanitize             Keep original filename (don't remove spaces/special chars)"
        echo "  --help, -h                Show this help message"
        echo ""
        echo "Note: Filenames are sanitized by default (lowercase, underscores instead of spaces)"
        echo "Note: Files save to /tmp/ by default for easy cleanup (override with --output-dir)"
        return 0
    fi

    # Check if yt-dlp or youtube-dl is installed (prefer yt-dlp)
    local dl_cmd=""
    if command -v yt-dlp &> /dev/null; then
        dl_cmd="yt-dlp"
    elif command -v youtube-dl &> /dev/null; then
        dl_cmd="youtube-dl"
    else
        echo "Neither yt-dlp nor youtube-dl found"
        echo "Install one of them:"
        echo "  Ubuntu/Debian: sudo apt install yt-dlp"
        echo "  Fedora: sudo dnf install yt-dlp"
        echo "  Arch: sudo pacman -S yt-dlp"
        echo "  Or: pip install yt-dlp"
        return 1
    fi

    # Parse arguments (same logic as macOS version)
    local url="$1"
    local output_filename=""
    local output_dir_override=""
    local start_time=""
    local end_time=""
    local quality="best"
    local format=""
    local subtitles=false
    local language="en"
    local audio_only=false
    local check_format=false
    local sanitize=true
    local ytdl_args=()

    shift # Skip the URL arg

    # Validate the URL
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "❌ Invalid URL: $url"
        echo "URL must start with http:// or https://"
        return 1
    fi

    # Parse options (same as macOS but adapted for Linux)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                shift
                output_filename="$1"
                ;;
            --output-dir|-d)
                shift
                output_dir_override="$1"
                ;;
            --start|-s)
                shift
                start_time=$(normalize_time "$1")
                ;;
            --end|-e)
                shift
                end_time=$(normalize_time "$1")
                ;;
            --quality|-q)
                shift
                quality="$1"
                ;;
            --format|-f)
                shift
                format="$1"
                ;;
            --subtitles|-sub)
                subtitles=true
                ;;
            --language|-l)
                shift
                language="$1"
                ;;
            --audio-only|-a)
                audio_only=true
                ;;
            --check-format)
                check_format=true
                ;;
            --no-sanitize)
                sanitize=false
                ;;
            *)
                echo "❌ Unknown option: $1"
                echo "Use 'download_video --help' to see available options"
                return 1
                ;;
        esac
        shift
    done

    # Build download arguments (same logic as macOS)
    if [[ "$audio_only" == true ]]; then
        ytdl_args+=("-x" "--audio-format" "mp3")
    else
        case "$quality" in
            best)
                ytdl_args+=("-f" "bestvideo+bestaudio/best")
                ;;
            1080p)
                ytdl_args+=("-f" "bestvideo[height<=1080]+bestaudio/best[height<=1080]")
                ;;
            720p)
                ytdl_args+=("-f" "bestvideo[height<=720]+bestaudio/best[height<=720]")
                ;;
            480p)
                ytdl_args+=("-f" "bestvideo[height<=480]+bestaudio/best[height<=480]")
                ;;
            360p)
                ytdl_args+=("-f" "bestvideo[height<=360]+bestaudio/best[height<=360]")
                ;;
            worst)
                ytdl_args+=("-f" "worstvideo+worstaudio/worst")
                ;;
            *)
                ytdl_args+=("-f" "best")
                ;;
        esac
    fi

    # Handle format if specified
    if [[ -n "$format" ]]; then
        ytdl_args+=(--recode-video "$format")
    fi

    # Handle subtitles
    if [[ "$subtitles" == true ]]; then
        ytdl_args+=(--write-sub --convert-subs srt --sub-lang "$language")
    fi

    # Handle output filename
    if [[ -n "$output_filename" ]]; then
        output_filename=$(echo "$output_filename" | tr ' ' '_' | tr -cd '[:alnum:]._-')
        ytdl_args+=(-o "$output_filename.%(ext)s")
    else
        ytdl_args+=(-o "%(title)s.%(ext)s")
    fi

    # Download the video
    echo "🎬 Downloading from: $url"
    echo "⚙️ Options: quality=$quality, format=$format"
    [[ -n "$start_time" ]] && echo "Starting at: $start_time"
    [[ -n "$end_time" ]] && echo "Ending at: $end_time"
    
    # Download with yt-dlp or youtube-dl - capture output for error detection
    local download_output=$(mktemp)
    local download_error=$(mktemp)

    if $dl_cmd "${ytdl_args[@]}" "$url" > "$download_output" 2> "$download_error"; then
        echo "✅ Download complete!"

        # Get the downloaded filename
        local downloaded_file=$($dl_cmd --get-filename -o "%(title)s.%(ext)s" "$url" 2>/dev/null)

        # Sanitize filename if enabled
        if [[ "$sanitize" == true && -f "$downloaded_file" ]]; then
            local dir=$(dirname "$downloaded_file")
            local basename=$(basename "$downloaded_file")
            local extension="${basename##*.}"
            local filename_no_ext="${basename%.*}"

            # Sanitize the filename (without extension)
            local sanitized_name=$(sanitize_filename "$filename_no_ext")
            local new_file="${dir}/${sanitized_name}.${extension}"

            if [[ "$downloaded_file" != "$new_file" ]]; then
                echo "📝 Sanitizing filename..."
                echo "   From: $basename"
                echo "   To: $(basename "$new_file")"
                mv "$downloaded_file" "$new_file"
                downloaded_file="$new_file"
            fi
        fi

        # Post-processing: trim if start/end times were specified
        if [[ -n "$start_time" || -n "$end_time" ]]; then
            if [[ -f "$downloaded_file" ]]; then
                echo "🔪 Trimming video..."
                trim_vid "$downloaded_file" --start "$start_time" --end "$end_time"
            fi
        fi

        echo "📁 Final file: $downloaded_file"
        rm -f "$download_output" "$download_error"
        return 0
    else
        # Check error output for specific known errors
        local error_msg=$(cat "$download_error")

        if [[ "$error_msg" =~ "No video could be found" ]]; then
            echo "📭 No video found in this URL"
            echo "   This URL may contain:"
            echo "   • Text-only content"
            echo "   • Images only"
            echo "   • External links without embedded video"
        elif [[ "$error_msg" =~ "Unsupported URL" ]]; then
            echo "❌ Unsupported URL or platform"
            echo "   The downloader doesn't support this website"
        elif [[ "$error_msg" =~ "Private video" || "$error_msg" =~ "This video is private" ]]; then
            echo "🔒 This video is private or requires authentication"
        elif [[ "$error_msg" =~ "Video unavailable" ]]; then
            echo "📵 Video unavailable (may be deleted or restricted)"
        else
            echo "❌ Download failed!"
            # Show first line of error for debugging
            echo "   Error: $(echo "$error_msg" | head -1 | sed 's/ERROR: //')"
        fi

        rm -f "$download_output" "$download_error"
        return 1
    fi
}

# Convenient aliases for download_video
# Use wrapper functions to prevent glob expansion in URLs (bash doesn't have noglob like zsh)
dl() {
    set -f  # Disable glob expansion
    download_video "$@"
    set +f  # Re-enable glob expansion
}

dlvid() {
    set -f
    download_video "$@"
    set +f
}

dlaudio() {
    set -f
    download_video --audio-only "$@"
    set +f
}

dl720() {
    set -f
    download_video --quality 720p "$@"
    set +f
}

dl1080() {
    set -f
    download_video --quality 1080p "$@"
    set +f
}

dlfix() {
    set -f
    download_video --check-format "$@"
    set +f
}

# Video format checking aliases (Signal/iOS/Android compatible)
alias vcheck='check_video_format'
alias vfix='check_video_format'
alias vinfo='check_video_format'
alias signalfix='check_video_format'

# Quick download for Instagram/TikTok/etc
igtok() {
    if [[ -z "$1" ]]; then
        echo "Usage: igtok <instagram/tiktok/twitter url> [output_name]"
        echo "Quick download for Instagram, TikTok, Twitter, etc."
        return 1
    fi

    local url="$1"
    local output="${2:-}"

    if [[ -n "$output" ]]; then
        download_video "$url" --output "$output"
    else
        download_video "$url"
    fi
}

trim_vid() {
    local file=""
    local start=""
    local end=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start|-ss)
                shift
                start=$(normalize_time "$1")
                ;;
            --end|-to)
                shift
                end=$(normalize_time "$1")
                ;;
            *)
                if [[ -z "$file" ]]; then
                    file="$1"
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$file" ]]; then
        echo "❌ No valid input file provided."
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        echo "❌ File not found: $file"
        return 1
    fi

    # Check if ffmpeg is installed
    if ! command -v ffmpeg &> /dev/null; then
        echo "❌ ffmpeg is not installed."
        echo "Install it with:"
        echo "  Ubuntu/Debian: sudo apt install ffmpeg"
        echo "  Fedora: sudo dnf install ffmpeg"
        echo "  Arch: sudo pacman -S ffmpeg"
        return 1
    fi

    # Generate output filename
    local filename="${file##*/}"
    local basename="${filename%.*}"
    local extension="${filename##*.}"
    local cleanname
    cleanname="$(echo "$basename" | tr -cs '[:alnum:]' '_')_trimmed.$extension"

    # Build and run ffmpeg command
    local cmd=(ffmpeg)
    [[ -n "$start" ]] && cmd+=(-ss "$start")
    cmd+=(-i "$file")
    [[ -n "$end" ]] && cmd+=(-to "$end")
    cmd+=(-c:v libx264 -c:a aac "$cleanname")

    echo "🎬 Trimming: $file"
    echo "➡️ Output:   $cleanname"
    echo "Running: ${cmd[*]}"
    "${cmd[@]}"
}