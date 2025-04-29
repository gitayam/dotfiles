# General utility functions for bash
# Place bash functions here

# Navigation Function
cdl() {
  if [ -n "$1" ]; then
    cd "$1" && ll
  else
    cd ~ && ll
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

# Nano Functions
reset_file() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: reset_file file1 file2 ..."
        return 0
    fi
  for file in "$@"; do
    backup "$file"
    : > "$file"
    sleep 0.5
    nano "$file"
    ls $file$backup_name
    see_diff="n"
    read -p "Do you want to see the difference between the original and backup file? (y/n):(default:n) " see_diff
    if [ "$see_diff" == "y" ]; then
      diff "$file" "$file$backup_name"
      restore_backup="n"
      read -p "Do you want to restore the backup file? (y/n):(default:n) " restore_backup
      if [ "$restore_backup" == "y" ]; then
        echo "This will delete any changes made to the original file"
        restore_backup_confirm="n"
        read -p "Are you sure you want to restore the backup file? (y/n):(default:n) " restore_backup_confirm
        if [ "$restore_backup_confirm" == "y" ]; then
          mv "$file$backup_name" "$file"
          echo "Backup file restored."
        fi
      fi
    fi
  done
}

# Python virtual environment
pyenv(){
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

# Function and alias helpers
show_func() {
    cat ~/.bash_aliases | grep "$1()"
}
alias show_function="show_func"
show_alias() {
    cat ~/.bash_aliases | grep -E "^alias " | cut -d '=' -f 1 | sort | uniq
}
show_help() {
    grep -E "^\s*${1}\s*\(\)|^\s*function\s+${1}" ~/.bash_aliases
}
helpmenu() {
    echo "Help Menu:"
    echo "----------"
    echo "See all functions: show_function"
    echo "See all aliases: show_alias"
    echo "See help for a function: show_help function_name"
    echo "See help for an alias: show_help alias_name"
}
# --- END: migrated from .bash_aliases ---
