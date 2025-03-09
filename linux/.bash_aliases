update_git_repos() {
    # Default variables
    search_path="/home/"
    exclude_paths=""

    # Process arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --home) search_path="/home/" ;;
            --exclude) exclude_paths="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done

    # Convert exclude_paths to an array
    IFS=' ' read -r -a exclude_array <<< "$exclude_paths"

    # Build find command with exclusions
    find_cmd="find \"$search_path\" -type d -name \".git\""

    for exclude in "${exclude_array[@]}"; do
        find_cmd+=" ! -path \"$exclude*\""
    done

    find_cmd+=" -print"

    # Execute the find command and update repositories
    eval "$find_cmd" | while read -r gitdir; do
        repo_dir=$(dirname "$gitdir")

        # Set as a safe directory in Git if needed
        git config --global --add safe.directory "$repo_dir"

        echo "Updating repository in $repo_dir"
        cd "$repo_dir" || continue
        git pull
    done
}


update_docker_compose() {
    # Default variables
    search_path="."
    exclude_paths=""
    pull_only=false
    ask=false

    # Show help message
    if [[ "$1" == "--help" ]]; then
        echo "Usage: update_docker_compose [OPTIONS]"
        echo "Options:"
        echo "  --home              Set the search path to /home/"
        echo "  --exclude <path>    Exclude specific paths from the update"
        echo "  --pull-only         Only pull Docker images without running 'up -d'"
        echo "  --ask               Prompt before updating each compose file"
        echo "  --help              Show this help message"
        return 0
    fi

    # Process arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --home) search_path="/home/" ;;
            --exclude) exclude_paths="$2"; shift ;;
            --pull-only) pull_only=true ;;
            --ask) ask=true ;;
            *) echo "Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done

    # Convert exclude_paths to an array
    IFS=' ' read -r -a exclude_array <<< "$exclude_paths"
    exclude_expr=""
    for path in "${exclude_array[@]}"; do
        exclude_expr+=" ! -path \"${path}*\""
    done

    # Find and update Docker Compose files
    find "$search_path" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) ${exclude_expr} -print | while read -r composefile; do
        compose_dir=$(dirname "$composefile")
        echo "Found docker-compose file in $compose_dir"

        # Prompt user if --ask is enabled
        if $ask; then
            read -p "Choose action for $compose_dir (p = pull only, u = pull & up, s = skip): " choice
            case $choice in
                p|P) action="pull" ;;
                u|U) action="pull_and_up" ;;
                s|S) echo "Skipping $compose_dir"; continue ;;
                *) echo "Invalid choice. Skipping $compose_dir"; continue ;;
            esac
        else
            action="pull_and_up"
        fi

        # Execute chosen action
        cd "$compose_dir" || continue
        if [[ $action == "pull" ]] || $pull_only; then
            echo "Running 'docker compose pull' in $compose_dir"
            docker compose pull
        fi

        if [[ $action == "pull_and_up" ]] && ! $pull_only; then
            echo "Running 'docker compose pull' and 'docker compose up -d' in $compose_dir"
            docker compose pull
            docker compose up -d
        fi
    done
}


upgrade_system() {
    echo "Starting system upgrade and cleanup... (running in background)"
    {
        LOG_FILE="/var/log/system_upgrade.log"
        echo "Logging to $LOG_FILE"

        # Check if the script is running as root
        if [[ $EUID -ne 0 ]]; then
            echo "Please run as root or with sudo." | tee -a "$LOG_FILE"
            return 1
        fi

        # Update package index
        echo "Updating package index..." | tee -a "$LOG_FILE"
        apt update >> "$LOG_FILE" 2>&1

        # Upgrade packages
        echo "Upgrading packages..." | tee -a "$LOG_FILE"
        apt full-upgrade -y >> "$LOG_FILE" 2>&1

        # Clean up unused packages
        echo "Cleaning up unused packages..." | tee -a "$LOG_FILE"
        apt autoremove -y >> "$LOG_FILE" 2>&1
        apt autoclean >> "$LOG_FILE" 2>&1

        # Check if a reboot is required
        if [ -f /var/run/reboot-required ]; then
            echo "System reboot is recommended." | tee -a "$LOG_FILE"
        else
            echo "No reboot is required." | tee -a "$LOG_FILE"
        fi

        echo "System upgrade and cleanup complete!" | tee -a "$LOG_FILE"
    } &  # Run the command block in the background

    disown  # Detach the background process
    echo "System upgrade and cleanup is running in the background. Check $LOG_FILE for details."
}

# Find files matching a pattern and execute a command on them
findex() {
  # Show help menu if -h or --help is passed or no arguments provided
  if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
    echo "Usage: findex [OPTIONS] [PATH] PATTERN COMMAND [--shift] [ARGS...]"
    echo ""
    echo "Required arguments:"
    echo "  PATTERN       File pattern to search for (e.g., '*.txt')"
    echo "  COMMAND       Command to execute on each matching file"
    echo ""
    echo "Optional arguments:"
    echo "  PATH          Directory path to search in (default: current directory)"
    echo "  -d DEPTH      Maximum directory depth to search (default: unlimited)"
    echo "  -t TYPE       File type: f (files), d (directories), l (symlinks)"
    echo "  --shift       Place all arguments after --shift to the right of the file placeholder"
    echo ""
    echo "Examples:"
    echo "  findex '*.txt' ls -l                         # List all text files in current dir"
    echo "  findex /home '*.pdf' ls -l                   # List all PDF files in /home"
    echo "  findex -d 2 '*.sh' chmod 755                 # Make shell scripts executable (max depth 2)"
    echo "  findex -t f /var/log '*.log' grep 'error'    # Search for 'error' in log files"
    echo "  findex '*.txt' sed -i 's/old/new/g'          # Replace text in all text files"
    echo "  findex /tmp '*.jpg' 'convert {} -resize 50% {}.resized'  # Resize all JPG files in /tmp"
    echo "  findex -d 2 ~/Documents '*.pdf' cp --shift /tmp/     # Copy PDFs to /tmp directory"
    return 0
  fi
    
  local max_depth=""
  local file_type=""
  local search_path="."  # Default to current directory
  local pattern=""
  local command=""
  local pre_shift_args=()
  local post_shift_args=()
  local shift_mode=false
  
  # Check for --shift anywhere in the arguments and remove it
  for arg in "$@"; do
    if [[ "$arg" == "--shift" ]]; then
      shift_mode=true
      break
    fi
  done
  
  # Parse options first
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d)
        if [[ -z "$2" || "$2" == -* ]]; then
          echo "Error: -d requires a depth argument"
          return 1
        fi
        max_depth="-maxdepth $2"
        shift 2
        ;;
      -t)
        if [[ -z "$2" || "$2" == -* ]]; then
          echo "Error: -t requires a type argument (f, d, or l)"
          return 1
        fi
        file_type="-type $2"
        shift 2
        ;;
      --shift)
        # Just skip the --shift flag, we already processed it
        shift
        ;;
      -*)
        echo "Unknown option: $1"
        echo "Use 'findex --help' for usage information."
        return 1
        ;;
      *)
        # If pattern is not set yet, check if this is a directory path
        if [[ -z "$pattern" ]]; then
          if [[ -d "$1" ]]; then
            search_path="$1"
          else
            pattern="$1"
          fi
        elif [[ -z "$command" ]]; then
          # This is the command
          command="$1"
        elif [[ "$shift_mode" == true && "$1" != "--shift" ]]; then
          # Add to post-shift arguments
          post_shift_args+=("$1")
        else
          # Add to pre-shift arguments
          pre_shift_args+=("$1")
        fi
        shift
        ;;
    esac
  done
  
  # Check if we have all required arguments
  if [[ -z "$pattern" || -z "$command" ]]; then
    echo "Error: Missing pattern or command. See 'findex --help' for usage."
    return 1
  fi
  
  # Expand the search path to handle ~ and other shell expansions
  search_path=$(eval echo "$search_path")
  
  # Construct and show the find command that will be executed
  local find_cmd=""
  
  # Special handling for common commands that need specific argument order
  if [[ ${#post_shift_args[@]} -gt 0 ]]; then
    # If we have post-shift arguments, construct command with them after the file placeholder
    find_cmd="find \"$search_path\" $max_depth $file_type -name \"$pattern\" -exec $command"
    
    # Add pre-shift arguments if any
    for arg in "${pre_shift_args[@]}"; do
      find_cmd+=" \"$arg\""
    done
    
    # Add the file placeholder
    find_cmd+=" {}"
    
    # Add post-shift arguments
    for arg in "${post_shift_args[@]}"; do
      find_cmd+=" \"$arg\""
    done
    
    find_cmd+=" \\;"
  else
    # Standard execution with all arguments before the file placeholder
    find_cmd="find \"$search_path\" $max_depth $file_type -name \"$pattern\" -exec $command"
    
    # Add all arguments
    for arg in "${pre_shift_args[@]}"; do
      find_cmd+=" \"$arg\""
    done
    
    # Add the file placeholder at the end
    find_cmd+=" {} \\;"
  fi
  
  echo "DEBUG: $find_cmd"
  
  # Additional debug: List files in the search path to verify it exists and is accessible
  echo "DEBUG: Files in search path (first 5):"
  ls -la "$search_path" | head -5
  
  # Get a list of files that will be processed
  echo "Finding files matching pattern: $pattern in $search_path"
  # Use 2>/dev/null to suppress permission errors
  local matching_files=$(find "$search_path" $max_depth $file_type -name "$pattern" 2>/dev/null)
  
  if [[ -z "$matching_files" ]]; then
    echo "No files found matching pattern: $pattern in $search_path"
    # Try a more direct approach to see if the file exists
    echo "DEBUG: Checking for files with ls:"
    
    # Fix the path pattern to avoid double slashes
    local search_pattern
    if [[ "$search_path" == */ ]]; then
      # If path ends with slash, don't add another one
      search_pattern="${search_path}${pattern#\*}"
    else
      # Otherwise add a slash between path and pattern
      search_pattern="${search_path}/${pattern#\*}"
    fi
    
    # Try to list matching files
    local ls_files=$(ls -la "$search_pattern" 2>/dev/null)
    
    if [[ -n "$ls_files" ]]; then
      echo "$ls_files"
      echo "Files found with ls, proceeding with command execution..."
      # Execute the command using the find command we constructed earlier
      eval "$find_cmd"
    else
      # If ls with pattern fails, try a direct find command as a last resort
      echo "Trying direct find command as fallback..."
      
      # Run a test find command and capture its output
      echo "Running test find command: find \"$search_path\" $max_depth $file_type -name \"$pattern\""
      local test_files=$(find "$search_path" $max_depth $file_type -name "$pattern" 2>/dev/null)
      
      # Check if we found any files
      if [[ -n "$test_files" ]]; then
        local file_count=$(echo "$test_files" | wc -l | tr -d ' ')
        echo "Found $file_count file(s) with direct find command:"
        echo "$test_files" | head -10  # Show first 10 files
        if [[ $(echo "$test_files" | wc -l) -gt 10 ]]; then
          echo "... and more ($(echo "$test_files" | wc -l | tr -d ' ') files total)"
        fi
        
        echo "Executing command on found files..."
        # Execute the command directly instead of using the constructed find_cmd
        if [[ ${#post_shift_args[@]} -gt 0 ]]; then
          echo "Running: find \"$search_path\" $max_depth $file_type -name \"$pattern\" -exec $command ${pre_shift_args[*]} {} ${post_shift_args[*]} \\;"
          find "$search_path" $max_depth $file_type -name "$pattern" -exec $command "${pre_shift_args[@]}" {} "${post_shift_args[@]}" \; 2>/dev/null
        else
          echo "Running: find \"$search_path\" $max_depth $file_type -name \"$pattern\" -exec $command ${pre_shift_args[*]} {} \\;"
          find "$search_path" $max_depth $file_type -name "$pattern" -exec $command "${pre_shift_args[@]}" {} \; 2>/dev/null
        fi
        echo "Command execution completed on $file_count file(s)."
        return 0
      else
        echo "No files found with fallback methods either"
      fi
    fi
    return 0
  fi
  
  # Count the number of files
  local file_count=$(echo "$matching_files" | wc -l | tr -d ' ')
  echo "Found $file_count file(s) to process:"
  echo "$matching_files" | sed 's/^/  /'
  
  # Execute the command
  if [[ ${#post_shift_args[@]} -gt 0 ]]; then
    echo "Executing: $command ${pre_shift_args[*]} [FILES] ${post_shift_args[*]}"
    find "$search_path" $max_depth $file_type -name "$pattern" -exec $command "${pre_shift_args[@]}" {} "${post_shift_args[@]}" \; 2>/dev/null
  else
    echo "Executing: $command ${pre_shift_args[*]} [FILES]"
    find "$search_path" $max_depth $file_type -name "$pattern" -exec $command "${pre_shift_args[@]}" {} \; 2>/dev/null
  fi
  
  echo "Command execution completed on $file_count file(s)."
}

# Generate a random password
generate_password() {
    # Default password type is phrases using diceware
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: generate_password [-p type] [-l length] [-m] [-c] [-s] [-q] [-n]"
        echo "Options:"
        echo "  -p type       Password type: phrases (default), chars (random characters), numbers, or hex"
        echo "  -l length     Length of the password (default: 6 words for phrases, 22 chars for others)"
        echo "  -m            Manual mode - prompt for password instead of generating"
        echo "  -c            Copy the generated password to clipboard"
        echo "  -s            Include special characters (for chars type only)"
        echo "  -q            Quiet mode - only output the password (useful for scripting)"
        echo "  -n            No spaces in passphrase (for phrases type only)"
        return 0
    fi
    
    # Check if diceware is installed for phrase passwords
    local has_diceware=false
    if command -v diceware &> /dev/null; then
        has_diceware=true
    fi
    
    local password_type="phrases"
    local length=6  # Default 6 words for phrases
    local char_length=22  # Default 22 chars for character passwords
    local manual_mode=false
    local copy_to_clipboard=false
    local include_special=false
    local quiet_mode=false
    local no_spaces=false
    local password=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -p requires a type argument (phrases, chars, numbers, hex)" >&2
                    return 1
                fi
                password_type="$2"
                shift 2
                ;;
            -l)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -l requires a length argument" >&2
                    return 1
                fi
                if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: Length must be a number" >&2
                    return 1
                fi
                if [[ "$password_type" == "phrases" ]]; then
                    length="$2"
                else
                    char_length="$2"
                fi
                shift 2
                ;;
            -m)
                manual_mode=true
                shift
                ;;
            -c)
                copy_to_clipboard=true
                shift
                ;;
            -s)
                include_special=true
                shift
                ;;
            -q)
                quiet_mode=true
                shift
                ;;
            -n)
                no_spaces=true
                shift
                ;;
            *)
                if ! $quiet_mode; then
                    echo "Unknown option: $1" >&2
                    echo "Use 'generate_password -h' for help." >&2
                fi
                return 1
                ;;
        esac
    done
    
    # If manual mode, prompt for password
    if $manual_mode; then
        if ! $quiet_mode; then
            echo "Enter your password (input will be hidden):" >&2
        fi
        read -s password
        if ! $quiet_mode; then
            echo "Confirm password:" >&2
        fi
        read -s password_confirm
        
        if [[ "$password" != "$password_confirm" ]]; then
            if ! $quiet_mode; then
                echo "Error: Passwords do not match." >&2
            fi
            return 1
        fi
        
        if ! $quiet_mode; then
            echo "Password set manually." >&2
        fi
    else
        # Generate password based on type
        case "$password_type" in
            phrases)
                if ! $has_diceware; then
                    if ! $quiet_mode; then
                        echo "Error: 'diceware' is not installed but required for phrase passwords." >&2
                        echo "You can install it with: sudo apt install diceware" >&2
                        echo -n "Do you want to install diceware now? (y/n): " >&2
                    fi
                    read install_diceware
                    if [[ "$install_diceware" =~ ^[Yy]$ ]]; then
                        sudo apt install diceware
                        has_diceware=true
                    else
                        if ! $quiet_mode; then
                            echo "Falling back to character-based password." >&2
                        fi
                        password_type="chars"
                    fi
                fi
                
                if $has_diceware; then
                    # Use diceware to generate a phrase password
                    password=$(diceware -n "$length" -c -s 2)
                    
                    # Remove spaces if requested
                    if $no_spaces; then
                        password=$(echo "$password" | tr -d ' ')
                    fi
                    
                    if ! $quiet_mode; then
                        echo "Generated passphrase: $password" >&2
                    fi
                else
                    # Fallback if diceware installation failed
                    password=$(openssl rand -base64 $(($char_length * 2)) | tr -d '/+=' | cut -c1-"$char_length")
                    if ! $quiet_mode; then
                        echo "Generated password: $password" >&2
                    fi
                fi
                ;;
                
            chars)
                # Generate a random character password with letters, numbers, and symbols
                if $include_special; then
                    # Include more special characters
                    password=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+=-' < /dev/urandom | head -c "$char_length")
                    
                    # Ensure at least one of each character type for better password strength
                    if [[ ${#password} -ge 4 ]]; then
                        # Get one of each type
                        local lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 1)
                        local upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 1)
                        local number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 1)
                        local special=$(LC_ALL=C tr -dc '!@#$%^&*()_+=-' < /dev/urandom | head -c 1)
                        
                        # Replace first 4 characters with our guaranteed types
                        password="${lower}${upper}${number}${special}${password:4}"
                        
                        # Shuffle the password to avoid predictable pattern
                        password=$(echo "$password" | fold -w1 | shuf | tr -d '\n' | head -c "$char_length")
                    fi
                else
                    # Standard character set
                    password=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$char_length")
                    
                    # Ensure at least one lowercase, one uppercase, and one number
                    if [[ ${#password} -ge 3 ]]; then
                        local lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 1)
                        local upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 1)
                        local number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 1)
                        
                        password="${lower}${upper}${number}${password:3}"
                        password=$(echo "$password" | fold -w1 | shuf | tr -d '\n' | head -c "$char_length")
                    fi
                fi
                
                if ! $quiet_mode; then
                    echo "Generated password: $password" >&2
                fi
                ;;
                
            numbers)
                # Generate a random numeric password
                password=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c "$char_length")
                if ! $quiet_mode; then
                    echo "Generated numeric password: $password" >&2
                fi
                ;;
                
            hex)
                # Generate a random hexadecimal password
                password=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c "$char_length")
                if ! $quiet_mode; then
                    echo "Generated hex password: $password" >&2
                fi
                ;;
                
            *)
                if ! $quiet_mode; then
                    echo "Error: Invalid password type '$password_type'. Use phrases, chars, numbers, or hex." >&2
                fi
                return 1
                ;;
        esac
    fi
    
    # Copy to clipboard if requested
    if $copy_to_clipboard && [[ -n "$password" ]]; then
        if command -v xclip &> /dev/null; then
            echo -n "$password" | xclip -selection clipboard
            if ! $quiet_mode; then
                echo "Password copied to clipboard." >&2
            fi
        elif command -v wl-copy &> /dev/null; then
            # Support for Wayland
            echo -n "$password" | wl-copy
            if ! $quiet_mode; then
                echo "Password copied to clipboard." >&2
            fi
        else
            if ! $quiet_mode; then
                echo "Warning: Could not copy to clipboard. Install xclip or wl-copy." >&2
            fi
        fi
    fi
    
    if ! $quiet_mode; then
        echo "Save this password securely!" >&2
    fi
    
    # Return the password as the function result
    echo "$password"
}

# Alias for generate_password with common settings
alias gen-passphrase="generate_password -p phrases -l 3"

# Encrypt files with various methods
encrypt_file() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: encrypt_file [-m method] [-r recipient] file1 file2 ..."
        echo "Options:"
        echo "  -m method       Encryption method: age (default), gpg, or aes"
        echo "  -r recipient    Use recipient's public key instead of passphrase (only for age)"
        echo "  -e, --encrypt   Optional flag (for consistency with other functions)"
        return 0
    fi

    # Check if encryption tools are installed
    local has_age=false
    local has_gpg=false
    local has_openssl=false
    
    if command -v age &> /dev/null; then
        has_age=true
    fi
    if command -v gpg &> /dev/null; then
        has_gpg=true
    fi
    if command -v openssl &> /dev/null; then
        has_openssl=true
    fi
    
    # If no encryption tools are available, prompt to install age
    if ! $has_age && ! $has_gpg && ! $has_openssl; then
        echo "Error: No encryption tools found (age, gpg, or openssl)."
        echo -n "Do you want to install 'age'? (y/n):(default:y) "
        read install_age
        if [[ $install_age =~ ^[Yy]$ || -z "$install_age" ]]; then
            sudo apt install age
            has_age=true
        else
            return 1
        fi
    fi

    # Initialize variables
    local recipient=""
    local use_passphrase=true
    local encrypt_method="age"  # Default encryption method
    local zip_file=""
    local password=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--encrypt)
                # Just a flag for consistency with other functions
                shift
                ;;
            -m)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -m requires a method argument (age, gpg, or aes)"
                    return 1
                fi
                encrypt_method="$2"
                shift 2
                ;;
            -r)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -r requires a recipient argument"
                    return 1
                fi
                recipient="$2"
                use_passphrase=false
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                echo "Usage: encrypt_file [-m method] [-r recipient] file1 file2 ..."
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    # Validate encryption method
    case "$encrypt_method" in
        age)
            if ! $has_age; then
                echo "Error: 'age' is not installed but specified as encryption method."
                return 1
            fi
            ;;
        gpg)
            if ! $has_gpg; then
                echo "Error: 'gpg' is not installed but specified as encryption method."
                return 1
            fi
            ;;
        aes)
            if ! $has_openssl; then
                echo "Error: 'openssl' is not installed but specified as encryption method."
                return 1
            fi
            ;;
        *)
            echo "Error: Invalid encryption method '$encrypt_method'. Use age, gpg, or aes."
            return 1
            ;;
    esac

    # Check if files are provided
    if [[ "$#" -eq 0 ]]; then
        echo "Error: No files provided for encryption."
        return 1
    fi

    # If multiple files are passed, zip them and encrypt the zip file
    local files_to_encrypt
    if [[ "$#" -gt 1 ]]; then
        # zip the files
        zip_file="./$(basename "$1")_encrypted_$(date +%Y%m%d%H%M%S).zip"
        echo "Creating zip file with multiple files..."
        zip -q "$zip_file" "$@"
        files_to_encrypt="$zip_file"
    else
        # if only one file is passed then set the file to encrypt
        files_to_encrypt="$1"
    fi

    # Encrypt the file(s) based on the selected method
    local encrypted_file
    case "$encrypt_method" in
        age)
            encrypted_file="${files_to_encrypt}.age"
            echo "Encrypting with age..."
            
            if $use_passphrase; then
                # Capture the passphrase from age output
                echo "Using passphrase encryption..."
                local age_output=$(age -p -o "$encrypted_file" "$files_to_encrypt" 2>&1)
                # Extract the passphrase from the output
                password=$(echo "$age_output" | grep -o 'passphrase: "[^"]*"' | cut -d '"' -f 2)
                if [[ -z "$password" ]]; then
                    # Try alternate format
                    password=$(echo "$age_output" | grep -o 'passphrase "[^"]*"' | cut -d '"' -f 2)
                fi
                
                if [[ -n "$password" ]]; then
                    echo "Generated passphrase: $password"
                    echo "Save this passphrase securely - you'll need it to decrypt the file."
                fi
            else
                echo "Using recipient key encryption..."
                age -r "$recipient" -o "$encrypted_file" "$files_to_encrypt"
                echo "Recipient key used for encryption: $recipient"
            fi
            ;;
            
        gpg)
            encrypted_file="${files_to_encrypt}.gpg"
            echo "Encrypting with GPG..."
            echo "You will be prompted to enter a passphrase for encryption."
            gpg --output "$encrypted_file" --symmetric "$files_to_encrypt"
            echo "File encrypted with GPG. Remember your passphrase for decryption."
            ;;
            
        aes)
            encrypted_file="${files_to_encrypt}.aes"
            echo "Encrypting with OpenSSL AES-256-CBC..."
            echo "You will be prompted to enter a passphrase for encryption."
            openssl enc -aes-256-cbc -salt -in "$files_to_encrypt" -out "$encrypted_file"
            echo "File encrypted with AES-256. Remember your passphrase for decryption."
            ;;
    esac

    # Verify the encrypted file was created
    if [[ ! -f "$encrypted_file" ]]; then
        echo "Error: Encryption failed. Encrypted file not created."
        # Clean up zip file if it was created
        [[ -n "$zip_file" && -f "$zip_file" ]] && rm -f "$zip_file"
        return 1
    fi

    # Clean up zip file if it was created
    if [[ -n "$zip_file" && -f "$zip_file" ]]; then
        rm -f "$zip_file"
    fi

    # Instructions for decryption
    echo "Encrypted file created: $encrypted_file"
    echo ""
    echo "To decrypt the file:"
    
    case "$encrypt_method" in
        age)
            if $use_passphrase; then
                echo "age --decrypt --output ${encrypted_file%.age} $encrypted_file"
                echo "You will be prompted for the passphrase shown above."
            else
                echo "age --decrypt --identity ~/.age/keys/your_private_key.key --output ${encrypted_file%.age} $encrypted_file"
            fi
            ;;
            
        gpg)
            echo "gpg --output ${encrypted_file%.gpg} --decrypt $encrypted_file"
            echo "You will be prompted for the passphrase you entered during encryption."
            ;;
            
        aes)
            echo "openssl enc -d -aes-256-cbc -in $encrypted_file -out ${encrypted_file%.aes}"
            echo "You will be prompted for the passphrase you entered during encryption."
            ;;
    esac
    
    echo ""
    echo "File successfully encrypted: $encrypted_file"
    return 0
}

# Share files via Tailscale funnel
funnel() {
    # usage: funnel file1 file2 dir1 dir2 ...
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: funnel <target>"
        echo "Funnel enables you to share a local server on the internet using Tailscale."
        echo "For more information, see: https://tailscale.com/kb/1223/funnel"
        return 0
    fi
    
    # Default port and allow override with FUNNEL_PORT env variable
    local port=${FUNNEL_PORT:-8080}
    use_python=true

    # Check if tailscale is running
    if ! command -v tailscale &> /dev/null; then
        echo "Error: Tailscale is not installed. Please install it first."
        return 1
    fi

    if ! tailscale status &> /dev/null; then
        echo "Tailscale is not running. Attempting to start it with 'tailscale up'..."
        tailscale up
        
        # Check again if tailscale is running after attempting to start it
        if ! tailscale status &> /dev/null; then
            echo "Error: Failed to start Tailscale. Please start it manually."
            return 1
        fi
        echo "Tailscale started successfully. Continuing..."
    fi

    # Use current directory if no target is specified
    if [ -z "$1" ]; then
        echo "No target specified. Using current directory as target."
        target="."
    else
        target="$@"
    fi

    # Kill any existing Python HTTP servers on our port
    local existing_pid=$(lsof -ti:$port 2>/dev/null)
    if [[ -n "$existing_pid" ]]; then
        echo "Killing existing process on port $port (PID: $existing_pid)"
        kill -9 $existing_pid 2>/dev/null
        sleep 1
    fi

    # Function to clean up background processes
    cleanup() {
        echo "Cleaning up..."
        # Find and kill the Python HTTP server process
        if [[ -n "$server_pid" ]]; then
            echo "Killing server process (PID: $server_pid)"
            kill -9 $server_pid 2>/dev/null
            wait $server_pid 2>/dev/null
        fi
        
        # Also try to find any process using our port
        local port_pid=$(lsof -ti:$port 2>/dev/null)
        if [[ -n "$port_pid" ]]; then
            echo "Killing process using port $port (PID: $port_pid)"
            kill -9 $port_pid 2>/dev/null
            sleep 1
        fi
    }

    # Start the server in the background
    python3 -m http.server $port &
    server_pid=$!

    # Wait for the server to start
    sleep 1

    # Share the files via Tailscale
    echo "Sharing files via Tailscale..."
    tailscale funnel $target

    # Clean up background processes
    cleanup

    echo "Files shared successfully via Tailscale."
}

# Grep aliases and functions
alias grep='grep -i --color=auto'  # Ignore case and colorize output
alias grepv='grep -vi --color=auto' # Ignore case, invert match, and colorize output

# Find aliases and functions
alias findf='find . -type f -name' # Find files by name
alias findd='find . -type d -name' # Find directories by name

# Navigation Function
# Fast directory navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# change dir and List Directory Contents
cdl() {
  if [ -n "$1" ]; then
    cd "$1" && ls -l
  else
    cd ~ && ls -l
  fi
}

# Make Directory and cd to it if only one arg is passed else just make the dir
mkd() {
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

# create backup of a file or directory
backup() {
  # human readable date and time with backup
  backup_name=".bak_$(date +%Y-%m-%d_%H-%M-%S)"
  # check if rsync is installed if not set copy command to cp
  if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
  else
    COPY_CMD="cp"
  fi
  
  # take files, dictionaries as arguments get full path as needed many args possible
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

# Reset file content and open in editor
reset_file() {
    # usage: reset_file file1 file2 ...
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: reset_file file1 file2 ..."
        return 0
    fi
  # Reset the file content to an empty string
  # use the backup function to create a backup of the file before erasing
  for file in "$@"; do
    backup "$file"
    echo "" > "$file"
    echo "File content backed up and erased."
    echo "Opening $file in editor"
    #echo >> the filename to the file with a # at the beginning
    echo "# $file" >> "$file"
    #sleep half a second
    sleep 0.5
    ${EDITOR:-nano} "$file"
    # prompt user to restore backup or delete
    ls $file$backup_name
    # default to no
    see_diff="n"
    echo -n "Do you want to see the difference between the original and backup file? (y/n):(default:n) "
    read see_diff
    if [ "$see_diff" == "y" ]; then
      diff "$file" "$file$backup_name"
      restore_backup="n"
      echo -n "Do you want to restore the backup file? (y/n):(default:n) "
      read restore_backup
      if [ "$restore_backup" == "y" ]; then
          mv "$file$backup_name" "$file"
          echo "Backup file restored."
      fi
    fi
  done
}

# Wormhole file transfer
alias wh="wormhole"
alias wht="wh-transfer"
# Transfer file with wormhole many or one file
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

# Menu with all functions in ~/.bash_aliases
show_func() {
    # usage: show_help function_name
    # show the help for a specific function
    cat ~/.bash_aliases | grep "$1()"
}
alias show_function="show_func"

show_alias() {
    # usage: show_alias
    # show all the aliases in the ~/.bash_aliases file
    cat ~/.bash_aliases | grep -E "^alias " | cut -d '=' -f 1 | sort | uniq
}

show_help() {
    # usage: show_help function_name
    # show the help for a specific function
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
privateip() {
    # usage: privateip
    # show the private ip address
    if command -v ip &> /dev/null; then
        ip a | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}'
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}'
    else
        echo "ip command not found"
    fi
}

# Networking shortcuts
alias ports='netstat -tulanp'  # List open ports
alias mypublicip='curl ifconfig.me'  # Check external IP address
alias myprivateip='privateip'  # Check private IP address
# Disk usage shortcuts
alias du='du -h --max-depth=1'  # Show disk usage in human-readable format
alias df='df -h'                # Show free disk space in human-readable format

# Safe aliases to prevent accidental file overwrites or deletions
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
