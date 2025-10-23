# Linux Bash Configuration Features

This document provides a comprehensive list of all functions and aliases defined in the bash configuration files located in `/linux/`.

## Table of Contents
- [.bash_functions](#bash_functions)
- [.bash_aliases](#bash_aliases)
- [.bash_apps](#bash_apps)
- [.bash_network](#bash_network)
- [.bash_transfer](#bash_transfer)
- [.bash_security](#bash_security)
- [.bash_utils](#bash_utils)
- [.bash_system](#bash_system)
- [.bash_docker](#bash_docker)
- [.bash_aws](#bash_aws)
- [.bash_encryption](#bash_encryption)
- [.bash_handle_files](#bash_handle_files)
- [.bash_developer](#bash_developer)

---

## .bash_functions

### Video Processing Functions (NEW - Signal Compatible):
- **check_video_format()**: Analyze and fix video format compatibility for Signal/iOS/Android
  - Detects codec compatibility (H.264, VP9, HEVC, etc.)
  - Validates pixel format (yuv420p required for iOS/Android)
  - Checks H.264 profile and level for mobile compatibility
  - Warns about file size limits (95 MB for Signal)
  - Converts to H.264 Main profile + AAC audio + yuv420p + MP4
  - Smart output directory (defaults to /tmp/, falls back to ./ or ~/)

- **download_video()**: Download videos from YouTube, Instagram, TikTok with yt-dlp/youtube-dl
  - Quality selection (best, 1080p, 720p, 480p, 360p)
  - Audio-only mode
  - Subtitle downloads with language selection
  - Video trimming (start/end times)
  - Output directory specification (defaults to /tmp/)
  - Automatic format checking for Signal/iOS compatibility (--check-format)
  - Filename sanitization
  - Intelligent error detection and user feedback

- **trim_vid()**: Trim video using ffmpeg with start/end times

### General Utility Functions:
- **cdl()**: Change directory and list contents with ll
- **mkd()**: Make directory and cd to it (single arg) or make multiple directories and list them
- **backup()**: Create timestamped backup of files/directories using rsync or cp
- **zipfile()**: Create zip archive of files/directories with optional .zip extension
- **reset_file()**: Backup file, clear content, open in nano, with diff/restore options
- **pyenv()**: Create and activate Python virtual environment
- **pyserver()**: Start Python HTTP server for file sharing, optionally with specific files
- **update_git_repos()**: Find and update all git repositories in specified path
- **upgrade_system()**: System upgrade and cleanup running in background (apt-based)
- **findex()**: Find files matching pattern and execute command on them
- **wh-transfer()**: Transfer files via Magic Wormhole with optional encryption
- **show_func()**: Show function definition from bash config files
- **show_alias()**: Show all aliases in bash config files
- **show_help()**: Show help for specific function or alias
- **helpmenu()**: Display help menu with available categories
- **normalize_time()**: Normalize time to hh:mm:ss format
- **sanitize_filename()**: Remove spaces and special characters from filenames

### Video Download Aliases (with glob expansion protection):
- **dl()**: Download video (wrapper prevents URL glob expansion - no quotes needed!)
- **dlvid()**: Same as dl
- **dlaudio()**: Download audio only
- **dl720()**: Download 720p quality
- **dl1080()**: Download 1080p quality
- **dlfix()**: Download with automatic format checking for Signal

### Video Format Checking Aliases:
- **vcheck**: Check video format compatibility
- **vfix**: Check and fix video format
- **vinfo**: Display video format info
- **signalfix**: Signal-optimized video fixing

### Other Aliases:
- **wh**="wormhole"
- **wht**="wh-transfer"
- **show_function**="show_func"

---

## .bash_aliases

### Functions:
- **update_git_repos()**: Find and update git repositories with exclusion options
- **update_docker_compose()**: Find and update all docker-compose files in directory tree
- **upgrade_system()**: Background system upgrade with logging to /var/log/system_upgrade.log
- **findex()**: Advanced file finder with pattern matching and command execution
- **generate_password()**: Generate secure passwords (phrases, chars, numbers, hex) with multiple options
- **gen-passphrase**: Shortcut for generate_password with 3-word phrases
- **encrypt_file()**: Encrypt files using age, gpg, or aes with optional recipient key
- **funnel()**: Share files via Tailscale funnel on port 8080
- **cdl()**: Change directory and list with ls -l
- **mkd()**: Make directory and cd to it or make multiple directories
- **backup()**: Create timestamped backup using rsync or cp
- **reset_file()**: Backup, clear, and edit file with restore options
- **wh-transfer()**: Transfer files via wormhole with optional encryption
- **show_func()**: Show function definitions
- **show_alias()**: Show all aliases
- **show_help()**: Show help for functions/aliases
- **helpmenu()**: Display help menu
- **privateip()**: Show private IP address

### Aliases:
- **grep**='grep -i --color=auto'
- **grepv**='grep -vi --color=auto'
- **findf**='find . -type f -name'
- **findd**='find . -type d -name'
- **..**="cd .."
- **...**="cd ../.."
- **....**="cd ../../.."
- **ports**='netstat -tulanp'
- **mypublicip**='curl ifconfig.me'
- **myprivateip**='privateip'
- **du**='du -h --max-depth=1'
- **df**='df -h'
- **rm**='rm -i'
- **cp**='cp -i'
- **mv**='mv -i'
- **gits**='git status'
- **gita**='git add .'
- **gitc**='git commit -m'
- **gitp**='git push'
- **gitpl**='git pull'
- **gitl**='git log --oneline --graph --decorate'
- **logs**='tail -f /var/log/syslog'
- **pyenv**='python3 -m venv env && source env/bin/activate'

---

## .bash_apps

### Functions:
- **open_browser()**: Open URL in default browser (xdg-open, gnome-open, kde-open)
- **open_pdf()**: Open PDF in default viewer (xdg-open, evince, okular)
- **edit_file()**: Open file in text editor (nano, micro, vi)
- **open_file_manager()**: Open file manager (nautilus, thunar, xdg-open)
- **setup_profiles()**: Create ~/Profiles directory and cd to it
- **run_kp()**: Launch KeePassXC with optional database file
- **run_element()**: Launch Element Matrix client with profile support
- **run_firefox()**: Launch Firefox with profile and URL support
- **run_discord()**: Launch Discord with profile support (native, flatpak, snap)
- **run_vscode()**: Launch VS Code or VSCodium with optional path
- **run_terminal()**: Launch terminal emulator (gnome-terminal, konsole, xfce4-terminal, etc.)
- **install_app()**: Install package using detected package manager (apt, dnf, yum, pacman, zypper, apk)
- **search_app()**: Search for packages using detected package manager

### Aliases:
- **kp**="keepassxc"
- **run-matrix**="run_element"
- **run-irregular**="run_element irregularchat"

---

## .bash_network

### Functions:
- **show_interfaces()**: Show all network interfaces and IPs
- **ping_summary()**: Ping host with count and summary
- **scan_ports()**: Scan network ports using nmap with auto-install prompt
- **pyserver()**: Start Python HTTP server for sharing files
- **check_ip()**: Check public IP via multiple services
- **flushdns()**: Flush DNS cache (systemd-resolved, nscd, dnsmasq)
- **digc()**: DNS lookup with cache flushing
- **pings()**: Quick ping summary with configurable count
- **gen_mac_addr()**: Generate random MAC address
- **show_current_mac()**: Show current MAC address for interface
- **change_mac_address()**: Change MAC address for interface with backup
- **restore_mac_address()**: Restore original MAC address
- **change_mac_menu()**: Interactive MAC address management menu
- **network_info()**: Display comprehensive network information summary
- **funnel()**: Share local server using Tailscale, ngrok, localtunnel, or serveo.net

### Aliases:
- **ports**='netstat -tulanp'
- **myip**='curl ifconfig.me'
- **http**="curl -I"

---

## .bash_transfer

### Functions:
- **scp_transfer()**: Transfer file via scp
- **fetch_url()**: Download file via wget or curl
- **transfer_file()**: Robust rsync transfer to remote host with options
- **upload_to_pcloud()**: Upload to pCloud using rclone
- **fsend()**: Send files using ffsend (Firefox Send alternative)
- **wh_transfer()**: Transfer using Magic Wormhole
- **upload_to_cloud()**: Generic cloud upload using rclone
- **share_files()**: Start HTTP file server on specified port
- **sync_dirs()**: Synchronize directories using rsync with options

---

## .bash_security

### Functions:
- **check_ports_by_process()**: Check for open ports by process using lsof
- **find_world_writable()**: Find world-writable files
- **setup_age()**: Setup age encryption with key generation
- **encrypt_file()**: Encrypt files using age, gpg, or aes methods
- **decrypt_file()**: Decrypt files with auto-detection of method
- **clean_file()**: Clean filename to alphanumeric characters
- **virus_scan()**: Scan files/directories for viruses using ClamAV
- **secure_delete()**: Securely delete files using shred or wipe
- **check_suspicious_processes()**: Check for suspicious processes and network activity
- **security_check()**: Comprehensive security check report

### Aliases:
- **json**="jq ."
- **scan_file**="virus_scan"
- **scan_dir**="virus_scan"

---

## .bash_utils

### Functions:
- **findex()**: Find files matching pattern and execute command (partial implementation)
- **calc()**: Quick calculator using bc
- **extract()**: Extract various archive formats automatically
- **archive()**: Create archives in various formats (zip, tar, tar.gz, etc.)
- **find_large_files()**: Find files larger than specified size
- **psg()**: Search for processes by name
- **killall_by_name()**: Kill all processes matching name
- **sysinfo()**: Display system information summary
- **myip()**: Show local and public IP addresses
- **note()**: Quick note taking utility
- **notes()**: Show all notes
- **uuidgen_util()**: Generate random UUID
- **show_disk_usage()**: Show disk usage for directory
- **convert_to_pdf()**: Convert markdown and office files to PDF
- **pyserver()**: Python HTTP server helper

### Aliases:
- **mdpdf**="convert_to_pdf"

---

## .bash_system

### Functions:
- **display_system_info()**: Display comprehensive server status and information
- **update_all()**: Universal system update for multiple package managers

### Aliases:
- **du**='du -h --max-depth=1'
- **df**='df -h'
- **rm**='rm -i'
- **cp**='cp -i'
- **mv**='mv -i'
- **gits**='git status'
- **gita**='git add .'
- **gitc**='git commit -m'
- **gitp**='git push'
- **gitpl**='git pull'
- **gitl**='git log --oneline --graph --decorate'
- **logs**='tail -f /var/log/syslog'

---

## .bash_docker

### Functions:
- **dexec()**: Interactive docker exec with container selection menu
- **docker_auto()**: Auto-run docker compose with build if Dockerfile exists
- **docker_cleanup()**: Clean up Docker system with optional --all flag
- **docker_stop_all()**: Stop all running containers
- **docker_remove_all()**: Remove all containers with optional --force
- **docker_remove_dangling()**: Remove dangling images
- **docker_stats()**: Show Docker container resource usage
- **docker_logs_tail()**: Show last N lines of container logs
- **update_docker_compose()**: Find and update all docker-compose files
- **docker_inspect_container()**: Show detailed container information
- **docker_network_inspect()**: Show Docker network information
- **docker_volume_inspect()**: Show Docker volume information
- **docker_info()**: Show Docker system information

### Aliases:
- **dc**="docker compose"
- **dcp**="dc pull"
- **dcs**="docker compose stop"
- **dcrm**="docker compose rm"
- **docker-compose**="dc"
- **dcu**="dcp && dc up -d"
- **dcd**="dcs;dcrm;dc down --volumes"
- **dcdr**='dcd --volumes; docker network rm $(docker network ls -q) 2>/dev/null; docker volume rm $(docker volume ls -q) 2>/dev/null'
- **dcb**="dcu --build"
- **dcr**="dcd && dcu"
- **dcnet**="docker network prune -f"
- **dcvol**="docker volume prune -f"
- **dcpur**="dcd && dcp && dcnet && dcvol"
- **d**="docker"
- **dps**="d ps"
- **dpsa**="d ps -a"
- **di**="d images"
- **dlog**="d logs"
- **dlogf**="d logs -f"
- **dbash**="d exec -it $1 /bin/bash"
- **dsh**="d exec -it $1 /bin/sh"

---

## .bash_aws

### Functions:
- **load_env()**: Load environment variables from .env file
- **run_aws_cmd()**: Run AWS commands with proper profile handling and credential prompts
- **aws_command_list()**: Display comprehensive AWS CLI helper reference
- **aws_set_profile()**: Set AWS profile for session
- **aws_unset_profile()**: Unset AWS profile
- **aws_whoami()**: Show current AWS identity
- **aws_list_users()**: List all IAM users
- **aws_list_groups()**: List all IAM groups
- **aws_list_roles()**: List all IAM roles
- **aws_list_policies()**: List all IAM policies
- **aws_create_user()**: Create new IAM user
- **aws_delete_user()**: Delete IAM user with confirmation
- **aws_user_info()**: Get detailed user information
- **aws_create_access_key()**: Create access key for user
- **aws_list_access_keys()**: List access keys for user
- **aws_delete_access_key()**: Delete access key with confirmation
- **aws_list_buckets()**: List all S3 buckets
- **aws_bucket_size()**: Get S3 bucket size
- **aws_sync_s3()**: Sync local directory to S3
- **aws_list_instances()**: List EC2 instances
- **aws_instance_info()**: Get EC2 instance details
- **aws_start_instance()**: Start EC2 instance
- **aws_stop_instance()**: Stop EC2 instance with confirmation

### Aliases:
- **awshelp**="aws_command_list | less -R"

---

## .bash_encryption

### Functions:
- **generate_password()**: Generate secure passwords with multiple types and options
- **check_password_strength()**: Analyze password strength with recommendations
- **hash_password()**: Generate SHA-256 hash of password
- **secure_delete()**: Securely delete files with multiple overwrites

### Aliases:
- **genpass**="generate_password"
- **checkpass**="check_password_strength"
- **hashpass**="hash_password"
- **sdelete**="secure_delete"

---

## .bash_handle_files

### Functions:
- **safe_rm()**: Safely move file to trash or use rm -i
- **process_single_image()**: Process single image with EXIF sanitization, rotation, conversion, OCR
- **handle_image()**: Comprehensive image handler with multiple options
- **batch_rename()**: Batch rename files with pattern replacement
- **pdf_merge()**: Merge multiple PDF files into one
- **pdf_extract_images()**: Extract images from PDF file
- **clean_markdown()**: Clean markdown files by handling problematic separators
- **backup()**: Create timestamped backup using rsync or cp
- **reset_file()**: Backup, clear, and edit file with restore options

---

## .bash_developer

### Functions:
- **git_commit()**: Git commit with optional message or interactive editor
- **git_add()**: Git add files (defaults to git add .)
- **git_undo()**: Undo last local commit, keep changes staged
- **git_clean_merged()**: Delete all merged local branches except main/master/develop
- **git_recent_branches()**: Show branches sorted by last commit date
- **update_git_repos()**: Update all git repositories in search path with exclusions
- **git_clone()**: Clone git repositories with smart URL handling and multi-repo support
- **pyenv()**: Create and activate Python virtual environment with version selection
- **pyserver()**: Start Python HTTP server for directory
- **create_repo()**: Create GitHub repository using gh CLI with options

### Aliases:
- **gita**="git_add"
- **gitcg**="git_commit"
- **gitp**="git push"
- **gitpl**="git pull"
- **gitco**="git checkout"
- **gitcb**="git checkout -b"
- **gitlog**="git log --oneline --graph --all"
- **gitup**="update_git_repos"
- **gitcl**="git_clone"
- **gitcr**="create_repo"
- **clone_repo**="git_clone"

---

## Summary Statistics

### Total Functions by File:
- .bash_functions: 19 functions
- .bash_aliases: 21 functions
- .bash_apps: 12 functions
- .bash_network: 16 functions
- .bash_transfer: 9 functions
- .bash_security: 12 functions
- .bash_utils: 17 functions
- .bash_system: 2 functions
- .bash_docker: 13 functions
- .bash_aws: 29 functions
- .bash_encryption: 4 functions
- .bash_handle_files: 8 functions
- .bash_developer: 10 functions

### Total Aliases by File:
- .bash_functions: 3 aliases
- .bash_aliases: 27 aliases
- .bash_apps: 3 aliases
- .bash_network: 3 aliases
- .bash_transfer: 0 aliases
- .bash_security: 3 aliases
- .bash_utils: 1 alias
- .bash_system: 13 aliases
- .bash_docker: 23 aliases
- .bash_aws: 1 alias
- .bash_encryption: 4 aliases
- .bash_handle_files: 0 aliases
- .bash_developer: 12 aliases

### Grand Totals:
- **Total Functions**: 172
- **Total Aliases**: 93

---

## Usage Tips

1. Use `show_help <function_name>` to see help for any function
2. Use `show_alias` to list all available aliases
3. Use `helpmenu` to see categorized help menu
4. Most functions support `-h` or `--help` flags for detailed usage information
5. Functions are organized by category for easy discovery

## Diff-Friendly Format

This document is structured to be easily compared with similar feature lists:
- Consistent function/alias naming format
- Alphabetical sorting within sections
- Clear section headers with markdown anchors
- Uniform description format
- Summary statistics for quick comparison