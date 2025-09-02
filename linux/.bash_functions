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

download_video() {
    if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
        echo "Usage: download_video url [options]"
        echo "Options:"
        echo "  --output, -o FILENAME    Output filename (default: auto-generated from title)"
        echo "  --start, -s TIME         Start time (format: HH:MM:SS or seconds)"
        echo "  --end, -e TIME           End time (format: HH:MM:SS or seconds)"
        echo "  --quality, -q QUALITY    Video quality (best, 1080p, 720p, 480p, 360p, worst)"
        echo "  --format, -f FORMAT      Format (mp4, webm, mp3, etc.)"
        echo "  --subtitles, -sub        Download subtitles if available (default: false, default language: en)"
        echo "  --language, -l LANGUAGE  Language (default: en)"
        echo "  --audio-only, -a         Download audio only"
        echo "  --help, -h               Show this help message"
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
    local start_time=""
    local end_time=""
    local quality="best"
    local format=""
    local subtitles=false
    local language="en"
    local audio_only=false
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
    
    if $dl_cmd "${ytdl_args[@]}" "$url"; then
        echo "✅ Download complete!"
        
        # Post-processing: trim if start/end times were specified
        if [[ -n "$start_time" || -n "$end_time" ]]; then
            local downloaded_file=$($dl_cmd --get-filename -o "%(title)s.%(ext)s" "$url" 2>/dev/null)
            if [[ -f "$downloaded_file" ]]; then
                echo "🔪 Trimming video..."
                trim_vid "$downloaded_file" --start "$start_time" --end "$end_time"
            fi
        fi
        
        return 0
    else
        echo "❌ Download failed!"
        return 1
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