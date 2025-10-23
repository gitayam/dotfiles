# Shell Configuration Files

This directory contains a modular shell configuration for ZSH that separates functionality into dedicated files for better organization and maintainability.

## 🎯 Quick Start

```bash
# Clone the repository
git clone https://github.com/gitayam/dotfiles.git
cd dotfiles/macos

# Run the sync script
./sync_mac_dotfiles.sh

# Reload your shell
source ~/.zshrc
```

## 📁 Files Structure

- `.zshrc` - Main shell configuration file that loads all modular files
- `.zsh_aliases` - Basic shell aliases for common commands
- `.zsh_functions` - General utility functions (video processing, downloads, file operations)
- `.zsh_git` - Git-related functions and aliases
- `.zsh_apps` - Application launcher functions
- `.zsh_network` - Network-related utilities (MAC address management, VPN)
- `.zsh_transfer` - File transfer utilities
- `.zsh_security` - Security-related functions (encryption, virus scanning)
- `.zsh_utils` - Miscellaneous utility functions
- `.zsh_docker` - Docker-related aliases and functions
- `.zsh_aws` - AWS CLI utilities
- `.zsh_encryption` - Encryption/decryption utilities
- `.zsh_handle_files` - Advanced file handling operations

## ✨ Key Features

### Video Processing (Signal/iOS/Android Compatible)
- **Smart video downloads** with format checking and automatic conversion
- **Signal-optimized encoding** - ensures videos display inline, not as file attachments
- Supports Instagram, YouTube, TikTok, and more via yt-dlp
- Quality selection (720p, 1080p, audio-only)
- Video format validation and fixing (H.264, AAC, yuv420p)

```bash
# Download video (no quotes needed!)
dl https://instagram.com/reel/ABC/?param=xyz

# Download and auto-fix for Signal
dlfix https://youtube.com/watch?v=xyz

# Check/fix existing video
signalfix video.mp4
vfix video.mp4
```

### Network Management
- MAC address randomization with vendor lookup
- VPN connection shortcuts
- IP address utilities
- Network diagnostics

### File Operations
- Smart file location handling (defaults to /tmp/)
- Clipboard integration (copy/paste files and text)
- Timestamped backups
- Fuzzy history search

## Installation

### Automatic (Recommended)
```bash
cd /path/to/dotfiles/macos
./sync_mac_dotfiles.sh
```

The sync script will:
1. Create symlinks for macOS-specific files
2. Compare repository files with your home directory
3. Prompt before overwriting (creates timestamped backups)
4. Verify all files are properly installed
5. Offer to reload your configuration

### Manual
1. Copy files from `macos/` to your home directory
2. Ensure `.zshrc` sources all `.zsh_*` files
3. Run `source ~/.zshrc` to load configuration

## Dependencies

### Required
- `zsh` - Shell (macOS default)
- `ffmpeg` - Video processing: `brew install ffmpeg`
- `yt-dlp` - Video downloads: `brew install yt-dlp`

### Optional
- `python3` - Enhanced MAC address management
- `fzf` - Fuzzy history search: `brew install fzf`
- `gh` - GitHub CLI for PR creation: `brew install gh`

## Maintenance

### Adding New Functionality
1. Add functions to the appropriate modular file:
   - Video/downloads → `.zsh_functions`
   - Network utilities → `.zsh_network`
   - Git operations → `.zsh_git`
   - etc.

2. Test your changes:
   ```bash
   source ~/.zsh_functions  # Load updated file
   your_new_function        # Test it
   ```

3. Commit and push:
   ```bash
   git add <files>
   git commit -m "feat: description"
   git push origin main
   ```

### Syncing Changes Across Machines
```bash
# On development machine (after changes)
git push origin main

# On other machines
git pull origin main
./sync_mac_dotfiles.sh
source ~/.zshrc
```

## 📚 Documentation

- **[LESSONS_LEARNED.md](LESSONS_LEARNED.md)** - Critical lessons, gotchas, and best practices
- **[MACOS_FEATURES.md](MACOS_FEATURES.md)** - Complete feature inventory for macOS
- **[LINUX_FEATURES.md](LINUX_FEATURES.md)** - Complete feature inventory for Linux
- **[FEATURE_COMPARISON.md](FEATURE_COMPARISON.md)** - Platform feature comparison
- **[macOS_Configuration_Guide.md](macOS_Configuration_Guide.md)** - Setup and configuration guide

## 🔧 Troubleshooting

### Changes not applying after sync?
```bash
# Make sure you have latest changes
git pull origin main

# Run sync script
./sync_mac_dotfiles.sh

# Reload shell
source ~/.zshrc
```

### "command not found" errors?
```bash
# Check if file is sourced in .zshrc
grep "zsh_functions" ~/.zshrc

# Verify file exists
ls -la ~/.zsh_functions

# Check for syntax errors
zsh -n ~/.zsh_functions
```

### Video downloads failing?
```bash
# Update yt-dlp (frequently needed)
brew upgrade yt-dlp

# Check ffmpeg is installed
ffmpeg -version

# Test with a known-good URL
dl https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

### URL glob expansion errors?
```bash
# Make sure aliases use noglob prefix
alias dl
# Should show: dl='noglob download_video'

# Reload config if needed
source ~/.zshrc
```

## Helper Scripts

- `sync_mac_dotfiles.sh` - Sync repository files to home directory
- `check_zsh_config.sh` - Verify configuration is properly set up
- `initial_macos_setup.sh` - Initial setup script for new macOS installations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and test thoroughly
4. Update documentation (especially LESSONS_LEARNED.md if you learned something)
5. Commit with descriptive message: `git commit -m "feat: add amazing feature"`
6. Push and create a Pull Request

## 📝 License

This project is open source and available for personal use.

## 🙏 Acknowledgments

- Video encoding best practices from Signal GitHub issues and mobile encoding standards
- Shell scripting patterns from the ZSH community
- yt-dlp for excellent video download support 