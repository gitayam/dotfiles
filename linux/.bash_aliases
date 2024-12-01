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
        exclude_expr+="! -path \"${path}\" -a "
    done
    # Find and update Docker Compose files
    find "$search_path" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) $exclude_expr -print | while read -r composefile; do
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
