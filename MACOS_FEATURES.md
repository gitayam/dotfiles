# macOS ZSH Configuration Features

Complete feature inventory for zsh configuration files in `/Users/sac/Git/dotfiles/macos/`

**Last Updated:** 2025-10-22

---

## .zsh_functions

### Video Processing Functions:
- `download_video()` - Download videos from YouTube, Instagram, TikTok, etc. (yt-dlp wrapper)
  - Supports quality selection (720p, 1080p, best)
  - Audio-only mode
  - Subtitle downloads with language selection
  - Video trimming (start/end times)
  - Output directory specification
  - Automatic format checking for Signal/iOS compatibility
  - Defaults to /tmp/ with smart fallback to ./ or ~/
  - Intelligent error detection and user feedback

- `check_video_format()` - Analyze and fix video format compatibility issues
  - Detects codec compatibility (H.264, VP9, HEVC, etc.)
  - Validates pixel format (yuv420p required for iOS/Android)
  - Checks H.264 profile and level for mobile compatibility
  - Warns about file size limits (95 MB for Signal)
  - Converts videos to Signal/iOS/Android-compatible format
  - H.264 Main profile + AAC audio + yuv420p + MP4 container
  - Optimized with +faststart for inline playback
  - Smart output directory with fallback logic

- `trim_vid()` - Trim video using ffmpeg with start/end times

### Clipboard Functions:
- `ccopy()` - Copy file to clipboard
- `cpaste()` - Paste from clipboard
- `clipls()` - List directory and copy to clipboard
- `clipcat()` - Copy file contents to clipboard
- `clippwd()` - Copy current directory to clipboard
- `clipip()` - Copy en0 IP address to clipboard

### Utility Functions:
- `normalize_time()` - Normalize time to hh:mm:ss format
- `fhist()` - Fuzzy-search shell history and re-run command
- `mkd()` - Make directory and cd to it (or make multiple dirs)
- `reset_file()` - Reset file content with backup
- `zipfile()` - Create zip archive (placeholder)
- `backup()` - Create timestamped backup of files/directories
- `cdl()` - Change directory and list contents
- `show_func()` - Show function definition
- `show_alias()` - Show all aliases
- `show_help()` - Show help for function
- `helpmenu()` - Display help menu

### Video Download Aliases (with noglob for URL handling):
- `dl='noglob download_video'` - Download video (no quotes needed for URLs!)
- `dlvid='noglob download_video'` - Same as dl
- `dlaudio='noglob download_video --audio-only'` - Download audio only
- `dl720='noglob download_video --quality 720p'` - Download 720p
- `dl1080='noglob download_video --quality 1080p'` - Download 1080p
- `dlfix='noglob download_video --check-format'` - Download with auto-format checking

### Video Format Checking Aliases:
- `vcheck='check_video_format'` - Check video format compatibility
- `vfix='check_video_format'` - Check and fix video format
- `vinfo='check_video_format'` - Display video format info
- `signalfix='check_video_format'` - Signal-optimized video fixing

### Other Aliases:
- `show_function="show_func"`

---

## .zsh_aliases

### Aliases:
- `..="cd .."`
- `...="cd ../.."`
- `....="cd ../../.."`
- `mkdir="mkdir -p"`
- `rmr="rm -rf"`
- `untar="tar -zxvf"`
- `tarx="tar -xvf"`
- `ls='ls $LS_OPTIONS'`
- `ll='ls -lh $LS_OPTIONS'`
- `la='ls -lha $LS_OPTIONS'`
- `l='ls -lA $LS_OPTIONS'`
- `lt='ls -strhal $LS_OPTIONS'`
- `grep='grep -i --color=auto "$@"'`
- `grepv='grep -vi --color=auto'`
- `findf='find . -type f -name'`
- `findd='find . -type d -name'`
- `nanozsh='nano ~/.zshrc'`
- `reset='reset_file'`

### Environment Variables:
- `LS_OPTIONS='--color=auto'`

---

## .zsh_apps

### Functions:
- `setup_profiles()` - Create and cd to ~/Profiles directory
- `run-element()` - Open Element app with optional profile
- `run-firefox()` - Open Firefox with optional profile
- `run-discord()` - Open Discord with optional profile
- `update_all()` - Update brew, App Store apps, macOS, git repos

### Aliases:
- `kp="keepassxc"`
- `run-kp="kp --db $1"`
- `run-matrix="run-element"`
- `run-irregular="run-element irregularchat"`

---

## .zsh_network

### Functions:
- `check_ip()` - Lookup public IP via multiple services
- `flushdns()` - Flush DNS cache
- `digc()` - DNS lookup with cache flush
- `pings()` - Quick ping summary
- `gen_mac_addr()` - Generate random MAC address
- `show_current_mac()` - Show current MAC address for interface
- `change_mac_address()` - Change MAC address for interface
- `change_mac_menu()` - Interactive MAC address change menu
- `restore_original_mac()` - Restore original MAC address
- `analyze_network_traffic()` - Analyze PCAP files with tshark
- `capture_network_traffic()` - Capture network traffic with tcpdump
- `scan_ports()` - Scan ports with nmap
- `pyserver()` - Start Python HTTP server
- `funnel()` - Share files/services over internet with Tailscale

### Aliases:
- `ports='netstat -tulanp'`
- `myip='curl ifconfig.me'`
- `http="curl -I"`
- `tsf=funnel`
- `postfile=funnel`
- `openport="funnel -d -p"`

---

## .zsh_transfer

### Functions:
- `clean_media_name()` - Sanitize media filenames
- `transfer_file()` - Transfer files to remote host using rsync
- `transfer_media()` - Transfer media files with automatic organization
- `wh-transfer()` - Transfer using magic-wormhole
- `upload_to_pcloud()` - Upload to pCloud using rclone
- `fsend()` - Send files using Firefox Send (ffsend)

### Aliases:
None

---

## .zsh_security

### Functions:
- `setup_age()` - Setup age encryption keys
- `encrypt_file()` - Encrypt file using age/gpg/aes
- `clean_file()` - Clean filename
- `virus_scan()` - Scan files with ClamAV
- `clamav_maintenance()` - Maintain ClamAV installation
- `ocr_files()` - OCR processing for PDFs

### Aliases:
- `json="jq ."`
- `scan_file="virus_scan"`
- `scan_dir="virus_scan"`
- `scan_files="virus_scan"`
- `scan_dirs="virus_scan"`
- `ocr-pdf="handle_pdf -o"`
- `extract-text="handle_pdf -t"`
- `compress-pdf="handle_pdf -c"`
- `rotate-pdf="handle_pdf -r"`
- `sanitize-pdf="handle_pdf -s"`
- `metadata-pdf="handle_pdf -m"`

---

## .zsh_utils

### Functions:
- `findex()` - Find files matching pattern and execute command
- `matrix_setup()` - Matrix server setup
- `matrix_setup_user()` - Matrix user setup

### Aliases:
- `du='du -h --max-depth=1'`
- `df='df -h'`

---

## .zsh_docker

### Functions:
- `dexec()` - Interactive docker exec helper
- `docker_auto()` - Auto-run docker compose with detected port

### Aliases:
- `dc="docker compose"`
- `dcp="dc pull"`
- `dcs="docker compose stop"`
- `dcrm="docker compose rm"`
- `docker-compose="dc"`
- `dcu="dcp && dc up -d"`
- `dcd="dcs;dcrm;dc down --volumes"`
- `dcdr="dcd --volumes; docker network rm $(docker network ls -q); docker volume rm $(docker volume ls -q)"`
- `dcb="dcu --build"`
- `dcr="dcd && dcu"`
- `dcnet="docker network prune"`
- `dcvol="docker volume prune"`
- `dcpur="dcd && dcp && dcnet && dcvol"`
- `d="docker"`
- `dps="d ps"`
- `dbash="d exec -it $1 /bin/bash"`
- `dsh="d exec -it $1 /bin/sh"`

---

## .zsh_aws

### Functions:
- `load_env()` - Load environment variables from .env
- `run_aws_cmd()` - Run AWS commands with profile handling
- `aws_check_profile()` - Check AWS profile and credentials
- `aws_list_profiles()` - List available AWS profiles
- `aws_use_profile()` - Set active AWS profile
- `aws_command_list()` - Display AWS command help
- `aws_install()` - Install AWS CLI and tools
- `aws_config()` - Configure AWS profile
- `aws_create_group()` - Create IAM group with permissions
- `aws_reset_password()` - Reset IAM user password

### Aliases:
- `awshelp="aws_command_list | less -R"`
- `aws_help="aws_command_list | less -R"`

---

## .zsh_encryption

### Functions:
- `generate_password()` - Generate secure passwords (phrases, chars, numbers, hex)
- `encrypt_file()` - Encrypt file with GPG
- `decrypt_file()` - Decrypt file (auto-detect method)
- `encrypt_file_simple()` - Simple OpenSSL encryption
- `encrypt_file_age()` - Modern encryption with AGE
- `decrypt_file_simple()` - Decrypt OpenSSL files
- `decrypt_file_age()` - Decrypt AGE files
- `secure_delete()` - Securely delete files
- `secure_zip()` - Create password-protected ZIP
- `batch_encrypt()` - Batch encrypt multiple files
- `import_gpg_key()` - Import GPG key from keyserver/GitHub
- `gpg_key_info()` - Display GPG key information
- `encrypt_for_github()` - Encrypt for GitHub user
- `generate_age_key()` - Generate AGE key pair
- `list_age_keys()` - List AGE keys
- `age_encrypt()` - Quick AGE passphrase encryption
- `age_decrypt()` - Quick AGE decryption
- `check_age_setup()` - Check AGE installation
- `compare_encryption_methods()` - Show encryption methods comparison

### Aliases:
- `genpass="generate_password -c"`
- `genpassphrase="generate_password -p phrases -c"`
- `genpin="generate_password -p numbers -l 6 -c"`
- `encrypt="encrypt_file"`
- `decrypt="decrypt_file"`
- `encrypt_simple="encrypt_file_simple"`
- `decrypt_simple="decrypt_file_simple"`
- `encrypt_delete="encrypt_file -d"`
- `encrypt_simple_delete="encrypt_file_simple -d"`
- `batch_enc="batch_encrypt"`
- `batch_enc_simple="batch_encrypt -s"`
- `batch_enc_github="batch_encrypt -g"`
- `secure_rm="secure_delete"`
- `secure_del="secure_delete"`
- `wipe="secure_delete -p 7 -r"`
- `gpg_keys="gpg_key_info"`
- `gpg_list="gpg --list-keys --keyid-format SHORT"`
- `gpg_list_secret="gpg --list-secret-keys --keyid-format SHORT"`
- `gpg_import="import_gpg_key"`
- `gpg_import_github="import_gpg_key -g"`
- `encrypt_github="encrypt_for_github"`
- `github_key="import_gpg_key -g"`
- `github_encrypt="encrypt_for_github"`

---

## .zsh_handle_files

### Functions:
- `process_single_image()` - Process single image file
- `handle_image()` - Handle image processing (convert, rotate, sanitize, OCR)
- `handle_pdf()` - Handle PDF processing (compress, OCR, sanitize, rotate, combine)
- `ensure_tex_path()` - Ensure TeX is in PATH for Pandoc
- `convert_to_pdf()` - Convert files to PDF
- `clean_markdown()` - Clean markdown files

### Aliases:
- `ocr-pdf="handle_pdf -o"`
- `extract-text="handle_pdf -t"`
- `compress-pdf="handle_pdf -c"`
- `convert-to-pdf="handle_pdf -C"`
- `rotate-pdf="handle_pdf -r"`
- `sanitize-pdf="handle_pdf -s"`
- `metadata-pdf="handle_pdf -m"`
- `to-pdf="convert_to_pdf"`
- `pdf-convert="convert_to_pdf"`
- `to_pdf="convert_to_pdf"`
- `mdpdf="convert_to_pdf"`

---

## .zsh_developer (Same as .zsh_git)

### Functions:
- `git_commit()` - Git commit with message or editor
- `git_add()` - Git add files (default: all)
- `git_undo()` - Undo last local commit
- `git_clean_merged()` - Delete merged branches
- `git_recent_branches()` - Show branches by commit date
- `update_git_repos()` - Update all git repos in path
- `git_clone()` - Clone git repositories
- `open_repo_dir()` - Prompt and open repo in editor
- `handle_existing_repo()` - Handle existing repository scenarios
- `create_repo()` - Create GitHub repository
- `cdproj()` - Fuzzy search and cd to project
- `pyenv()` - Python virtual environment management
- `pyenv_setup()` - Setup Python environment and install requirements
- `hackathon_setup()` - Setup virtual hackathon repository
- `claude_checks()` - Check Claude Code installation
- `claude_code()` - Run Claude Code with options

### Aliases:
- `gita="git_add"`
- `gitcg="git_commit"`
- `gitp="git push"`
- `gitpl="git pull"`
- `gitco="git checkout"`
- `gitcb="git checkout -b"`
- `gitlog="git log --oneline --graph --all"`
- `gitup="update_git_repos"`
- `gitcl="git_clone"`
- `gitcr="create_repo"`
- `clone_repo="git_clone"`
- `git_create="create_repo"`
- `psetup="pyenv_setup"`

---

## .zsh_git

### Functions:
- `git_status()` - Enhanced git status with branch info
- `git_diff()` - Git diff with color
- `git_log()` - Git log with graph
- `git_push()` - Git push with tracking

### Aliases:
- `gs="git_status"`
- `gd="git_diff"`
- `gl="git_log"`
- `gp="git_push"`

---

## Summary Statistics

### Total Features by File:
- `.zsh_functions`: 19 functions, 1 alias
- `.zsh_aliases`: 0 functions, 19 aliases, 1 environment variable
- `.zsh_apps`: 4 functions, 4 aliases
- `.zsh_network`: 12 functions, 6 aliases
- `.zsh_transfer`: 6 functions, 0 aliases
- `.zsh_security`: 6 functions, 11 aliases
- `.zsh_utils`: 3 functions, 2 aliases
- `.zsh_docker`: 2 functions, 20 aliases
- `.zsh_aws`: 12 functions, 2 aliases
- `.zsh_encryption`: 19 functions, 19 aliases
- `.zsh_handle_files`: 6 functions, 9 aliases
- `.zsh_developer`: 17 functions, 13 aliases
- `.zsh_git`: 4 functions, 4 aliases

### Grand Total:
- **110 Functions**
- **110 Aliases**
- **1 Environment Variable**

---

## Feature Categories

### System Administration
- File management (backup, reset, zip)
- Directory navigation (cd, mkdir, ls variations)
- System updates (brew, App Store, macOS)

### Networking
- IP address management
- DNS operations
- MAC address spoofing
- Network traffic capture/analysis
- Port scanning
- File sharing (Tailscale funnel, Python server)

### Security & Encryption
- Password generation
- File encryption (GPG, AGE, OpenSSL)
- Secure file deletion
- GPG key management
- Virus scanning (ClamAV)

### Cloud & Infrastructure
- AWS CLI management
- IAM user/group management
- VPC management
- EC2 instance management
- Docker container management

### Development Tools
- Git repository management
- GitHub CLI integration
- Python virtual environments
- Claude Code integration
- Project navigation

### Media Processing
- Video downloading and trimming
- Image processing (rotation, conversion, EXIF sanitization)
- PDF handling (OCR, compression, sanitization)
- File format conversion

### File Transfer
- rsync-based file transfer
- Media file organization
- Magic Wormhole integration
- pCloud integration
- Firefox Send integration

---

## Usage Notes

This document is designed to be easily diffable. Each section follows a consistent format:
- Functions are listed with brief descriptions
- Aliases show the command mapping
- Categories help locate related functionality

To compare with another system's configuration, diff this file against a similarly formatted list from that system.

---

## Maintenance

Last updated: 2025-09-29
Source: `/Users/sac/Git/dotfiles/macos/macos/`

To regenerate this document, analyze all `.zsh*` files in the source directory.