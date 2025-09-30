# Linux vs macOS Feature Comparison

Generated: 2025-09-29

This document compares bash (Linux) and zsh (macOS) configuration features to identify gaps and differences.

---

## Summary Statistics

| System | Functions | Aliases | Total Features |
|--------|-----------|---------|----------------|
| **Linux (Bash)** | 172 | 93 | 265 |
| **macOS (Zsh)** | 110 | 110 | 220 |
| **Difference** | +62 Linux | +17 macOS | +45 Linux |

---

## MISSING IN macOS - Functions Present in Linux but NOT in macOS

### Critical Missing Functions (Core Utilities):
1. **update_docker_compose()** - Linux has advanced docker-compose update functionality
2. **upgrade_system()** - Linux has background system upgrade with logging
3. **display_system_info()** - Comprehensive server status display (Linux only)
4. **sysinfo()** - System information summary
5. **myip()** - Show local and public IP addresses
6. **note()** - Quick note taking utility
7. **notes()** - Show all notes
8. **uuidgen_util()** - Generate random UUID
9. **show_disk_usage()** - Show disk usage for directory

### Missing Apps Functions:
10. **open_browser()** - Open URL in default browser
11. **open_pdf()** - Open PDF in default viewer
12. **edit_file()** - Open file in text editor
13. **open_file_manager()** - Open file manager
14. **run_terminal()** - Launch terminal emulator
15. **install_app()** - Install package using detected package manager
16. **search_app()** - Search for packages

### Missing Network Functions:
17. **show_interfaces()** - Show all network interfaces and IPs
18. **ping_summary()** - Ping host with count and summary
19. **network_info()** - Display comprehensive network information summary

### Missing Transfer Functions:
20. **scp_transfer()** - Transfer file via scp
21. **fetch_url()** - Download file via wget or curl
22. **upload_to_cloud()** - Generic cloud upload using rclone
23. **share_files()** - Start HTTP file server on specified port
24. **sync_dirs()** - Synchronize directories using rsync with options

### Missing Security Functions:
25. **check_ports_by_process()** - Check for open ports by process using lsof
26. **find_world_writable()** - Find world-writable files
27. **decrypt_file()** - Linux has enhanced decrypt with auto-detection
28. **check_suspicious_processes()** - Check for suspicious processes and network activity
29. **security_check()** - Comprehensive security check report
30. **check_password_strength()** - Analyze password strength with recommendations
31. **hash_password()** - Generate SHA-256 hash of password

### Missing Utilities:
32. **calc()** - Quick calculator using bc
33. **extract()** - Extract various archive formats automatically
34. **archive()** - Create archives in various formats (zip, tar, tar.gz, etc.)
35. **find_large_files()** - Find files larger than specified size
36. **psg()** - Search for processes by name
37. **killall_by_name()** - Kill all processes matching name

### Missing Docker Functions:
38. **docker_cleanup()** - Clean up Docker system with optional --all flag
39. **docker_stop_all()** - Stop all running containers
40. **docker_remove_all()** - Remove all containers with optional --force
41. **docker_remove_dangling()** - Remove dangling images
42. **docker_stats()** - Show Docker container resource usage
43. **docker_logs_tail()** - Show last N lines of container logs
44. **docker_inspect_container()** - Show detailed container information
45. **docker_network_inspect()** - Show Docker network information
46. **docker_volume_inspect()** - Show Docker volume information
47. **docker_info()** - Show Docker system information

### Missing AWS Functions (Linux has 29, macOS has 12):
48. **aws_set_profile()** - Set AWS profile for session
49. **aws_unset_profile()** - Unset AWS profile
50. **aws_whoami()** - Show current AWS identity
51. **aws_list_users()** - List all IAM users
52. **aws_list_groups()** - List all IAM groups
53. **aws_list_roles()** - List all IAM roles
54. **aws_list_policies()** - List all IAM policies
55. **aws_create_user()** - Create new IAM user
56. **aws_delete_user()** - Delete IAM user with confirmation
57. **aws_user_info()** - Get detailed user information
58. **aws_create_access_key()** - Create access key for user
59. **aws_list_access_keys()** - List access keys for user
60. **aws_delete_access_key()** - Delete access key with confirmation
61. **aws_list_buckets()** - List all S3 buckets
62. **aws_bucket_size()** - Get S3 bucket size
63. **aws_sync_s3()** - Sync local directory to S3
64. **aws_list_instances()** - List EC2 instances
65. **aws_instance_info()** - Get EC2 instance details
66. **aws_start_instance()** - Start EC2 instance
67. **aws_stop_instance()** - Stop EC2 instance with confirmation

### Missing File Handling Functions:
68. **safe_rm()** - Safely move file to trash or use rm -i
69. **batch_rename()** - Batch rename files with pattern replacement
70. **pdf_merge()** - Merge multiple PDF files into one
71. **pdf_extract_images()** - Extract images from PDF file

---

## PRESENT IN macOS but NOT in Linux - macOS Advantages

### Enhanced Functions in macOS:
1. **ccopy()** - Copy file to clipboard (macOS-specific)
2. **cpaste()** - Paste from clipboard
3. **clipls()** - List directory and copy to clipboard
4. **clipcat()** - Copy file contents to clipboard
5. **clippwd()** - Copy current directory to clipboard
6. **clipip()** - Copy en0 IP address to clipboard
7. **fhist()** - Fuzzy-search shell history and re-run command
8. **matrix_setup()** - Matrix server setup
9. **matrix_setup_user()** - Matrix user setup
10. **restore_original_mac()** - Restore original MAC address (better naming)
11. **analyze_network_traffic()** - Analyze PCAP files with tshark
12. **capture_network_traffic()** - Capture network traffic with tcpdump
13. **clamav_maintenance()** - Maintain ClamAV installation
14. **ocr_files()** - OCR processing for PDFs
15. **clean_media_name()** - Sanitize media filenames
16. **transfer_media()** - Transfer media files with automatic organization
17. **aws_check_profile()** - Check AWS profile and credentials
18. **aws_list_profiles()** - List available AWS profiles
19. **aws_use_profile()** - Set active AWS profile
20. **aws_install()** - Install AWS CLI and tools
21. **aws_config()** - Configure AWS profile
22. **aws_create_group()** - Create IAM group with permissions
23. **aws_reset_password()** - Reset IAM user password

### Enhanced Encryption in macOS (19 functions vs 4 in Linux):
24. **encrypt_file_simple()** - Simple OpenSSL encryption
25. **encrypt_file_age()** - Modern encryption with AGE
26. **decrypt_file_simple()** - Decrypt OpenSSL files
27. **decrypt_file_age()** - Decrypt AGE files
28. **secure_zip()** - Create password-protected ZIP
29. **batch_encrypt()** - Batch encrypt multiple files
30. **import_gpg_key()** - Import GPG key from keyserver/GitHub
31. **gpg_key_info()** - Display GPG key information
32. **encrypt_for_github()** - Encrypt for GitHub user
33. **generate_age_key()** - Generate AGE key pair
34. **list_age_keys()** - List AGE keys
35. **age_encrypt()** - Quick AGE passphrase encryption
36. **age_decrypt()** - Quick AGE decryption
37. **check_age_setup()** - Check AGE installation
38. **compare_encryption_methods()** - Show encryption methods comparison

### Enhanced Development Tools in macOS:
39. **open_repo_dir()** - Prompt and open repo in editor
40. **handle_existing_repo()** - Handle existing repository scenarios
41. **cdproj()** - Fuzzy search and cd to project
42. **pyenv_setup()** - Setup Python environment and install requirements
43. **hackathon_setup()** - Setup virtual hackathon repository
44. **claude_checks()** - Check Claude Code installation
45. **claude_code()** - Run Claude Code with options

### Enhanced File Handling in macOS:
46. **ensure_tex_path()** - Ensure TeX is in PATH for Pandoc

### Enhanced Git Functions in macOS (.zsh_git):
47. **git_status()** - Enhanced git status with branch info
48. **git_diff()** - Git diff with color
49. **git_log()** - Git log with graph
50. **git_push()** - Git push with tracking

---

## DIFFERENT IMPLEMENTATIONS - Functions in Both but Different

1. **funnel()** - Linux version checks Tailscale, ngrok, localtunnel, serveo.net; macOS only uses Tailscale
2. **update_all()** - Linux updates system packages; macOS updates brew + App Store + macOS + git repos
3. **encrypt_file()** - Both have it but different implementations and options
4. **decrypt_file()** - macOS has auto-detection; Linux version may differ
5. **generate_password()** - Both have but may have different options/implementations

---

## COMMON FUNCTIONS - Present in Both Systems

### Core Functions (Present in Both):
- **cdl()** - Change directory and list
- **mkd()** - Make directory and cd to it
- **backup()** - Create timestamped backup
- **reset_file()** - Reset file content with backup
- **zipfile()** - Create zip archive
- **download_video()** - Download videos with quality/format options
- **trim_vid()** - Trim video using ffmpeg
- **normalize_time()** - Normalize time format
- **show_func()** / **show_function** - Show function definition
- **show_alias()** - Show all aliases
- **show_help()** - Show help for function
- **helpmenu()** - Display help menu
- **update_git_repos()** - Update all git repositories
- **findex()** - Find files and execute command

### Common Network Functions:
- **check_ip()** - Check public IP
- **flushdns()** - Flush DNS cache
- **digc()** - DNS lookup with cache flush
- **pings()** - Quick ping summary
- **gen_mac_addr()** - Generate random MAC address
- **show_current_mac()** - Show current MAC address
- **change_mac_address()** - Change MAC address
- **change_mac_menu()** - Interactive MAC address menu
- **scan_ports()** - Scan ports with nmap
- **pyserver()** - Python HTTP server
- **funnel()** - Share files over internet

### Common Security Functions:
- **setup_age()** - Setup age encryption
- **encrypt_file()** - Encrypt files
- **clean_file()** - Clean filename
- **virus_scan()** - Scan with ClamAV
- **generate_password()** - Generate secure passwords
- **secure_delete()** - Securely delete files

### Common Transfer Functions:
- **wh-transfer()** - Magic Wormhole file transfer
- **upload_to_pcloud()** - Upload to pCloud
- **fsend()** - Firefox Send integration
- **transfer_file()** - rsync-based file transfer

### Common Developer Functions:
- **git_commit()** - Git commit helper
- **git_add()** - Git add helper
- **git_undo()** - Undo last commit
- **git_clean_merged()** - Delete merged branches
- **git_recent_branches()** - Show branches by date
- **git_clone()** - Clone repositories
- **create_repo()** - Create GitHub repository
- **pyenv()** - Python virtual environment

### Common Docker Functions:
- **dexec()** - Interactive docker exec
- **docker_auto()** - Auto-run docker compose

### Common AWS Functions:
- **load_env()** - Load .env variables
- **run_aws_cmd()** - Run AWS commands with profile handling
- **aws_command_list()** - Display AWS command help

### Common File Handling:
- **process_single_image()** - Process single image
- **handle_image()** - Handle image processing
- **handle_pdf()** - Handle PDF processing
- **convert_to_pdf()** - Convert files to PDF
- **clean_markdown()** - Clean markdown files

---

## ALIAS DIFFERENCES

### Linux-Only Aliases (Not in macOS):
- **grepv** (in aliases)
- **..., ....** (extra navigation)
- **ports**
- **mypublicip**, **myprivateip**
- **logs**
- **gits, gita, gitc, gitp, gitpl, gitl**
- **findf, findd**
- **awshelp**
- **genpass, checkpass, hashpass, sdelete**
- **mdpdf**
- Docker aliases: **dcp, dcs, dcrm, dcu, dcd, dcdr, dcb, dcr, dcnet, dcvol, dcpur, dps, dpsa, di, dlog, dlogf**

### macOS-Only Aliases (Not in Linux):
- **clipls, clipcat, clippwd, clipip** (clipboard operations)
- **nanozsh**
- **reset** (alias to reset_file)
- **tsf, postfile, openport** (Tailscale funnel aliases)
- **scan_file, scan_dir, scan_files, scan_dirs**
- **ocr-pdf, extract-text, compress-pdf, rotate-pdf, sanitize-pdf, metadata-pdf**
- **genpass, genpassphrase, genpin** (enhanced encryption aliases)
- **encrypt, decrypt, encrypt_simple, decrypt_simple**
- **batch_enc, secure_rm, secure_del, wipe**
- **gpg_keys, gpg_list, gpg_list_secret, gpg_import, encrypt_github**
- **to-pdf, pdf-convert, to_pdf**
- **gs, gd, gl, gp** (git shortcuts in .zsh_git)
- **psetup**

---

## RECOMMENDATIONS

### Priority 1 - Port to macOS Immediately:
1. **update_docker_compose()** - Very useful for managing multiple docker-compose files
2. **docker_cleanup(), docker_stop_all(), docker_remove_all()** - Essential Docker management
3. **docker_stats(), docker_logs_tail()** - Monitoring functions
4. **display_system_info()** - Useful for server management
5. **upgrade_system()** - Background system upgrade
6. **calc()** - Quick calculator
7. **extract()** - Auto-extract archives
8. **archive()** - Create archives easily
9. **find_large_files()** - Disk management
10. **psg()** - Process search

### Priority 2 - Port AWS Functions to macOS:
11. All missing AWS IAM, S3, and EC2 management functions

### Priority 3 - Port Utility Functions:
12. **sysinfo(), myip(), note(), notes()** - General utilities
13. **show_disk_usage()** - Disk utilities
14. **safe_rm()** - Safety feature
15. **batch_rename()** - File management
16. **pdf_merge(), pdf_extract_images()** - PDF utilities

### Priority 4 - Consider Platform Differences:
- Keep macOS-specific clipboard functions
- Keep macOS-specific app launchers
- Preserve macOS's enhanced encryption suite
- Keep Claude Code integration on macOS

---

## ACTION ITEMS

1. ✅ Create LINUX_FEATURES.md
2. ✅ Create MACOS_FEATURES.md
3. ✅ Create this comparison document
4. ⏳ Port Priority 1 functions to macOS
5. ⏳ Port Priority 2 AWS functions to macOS
6. ⏳ Port Priority 3 utility functions to macOS
7. ⏳ Test all ported functions
8. ⏳ Update documentation
9. ⏳ Git commit changes

---

**End of Comparison Document**