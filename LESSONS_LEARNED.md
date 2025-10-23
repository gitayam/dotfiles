# Lessons Learned: Dotfiles Development & Troubleshooting

**Last Updated:** 2025-10-22
**Repository:** https://github.com/gitayam/dotfiles

This document captures critical lessons learned, gotchas, and best practices discovered during the development and maintenance of this dotfiles repository. Use this as a reference when troubleshooting issues or implementing new features.

---

## Table of Contents

1. [Video Format Compatibility](#video-format-compatibility)
2. [Shell URL Handling & Glob Expansion](#shell-url-handling--glob-expansion)
3. [File Location Strategies](#file-location-strategies)
4. [Git Workflow & Sync Scripts](#git-workflow--sync-scripts)
5. [FFmpeg Best Practices](#ffmpeg-best-practices)
6. [Python Integration](#python-integration)
7. [Shell Function Design](#shell-function-design)

---

## Video Format Compatibility

### Lesson: Signal/iOS/Android Require Specific Video Encoding

**Problem:**
Videos downloaded from Instagram/YouTube were showing as file attachments in Signal messenger instead of inline playable videos, even though they were MP4 files.

**Root Cause:**
Signal/iOS/Android require very specific video encoding parameters for inline playback:
- **Codec:** H.264 (NOT VP9, VP8, AV1, or HEVC/H.265)
- **Pixel Format:** yuv420p (mandatory for iOS/Android)
- **Profile:** Main or Baseline (not High 4:4:4 or High 10)
- **Container:** MP4 (MOV has cross-platform issues on Signal Android)
- **Audio:** AAC codec, 128kbps stereo
- **Moov Atom:** Must be at beginning of file (`-movflags +faststart`)

**Solution Implemented:**
Enhanced `check_video_format()` function in `.zsh_functions:73-369` with:
```bash
# Signal-optimized FFmpeg conversion
ffmpeg -i "$input" \
  -c:v libx264 \          # H.264 codec
  -profile:v main \        # Mobile-compatible profile
  -level 3.1 \             # Supports up to 720p
  -pix_fmt yuv420p \       # REQUIRED for iOS/Android
  -c:a aac -b:a 128k -ac 2 \  # Optimized audio
  -movflags +faststart \   # Moov atom at start
  -preset medium -crf 23 \ # Quality/speed balance
  -y "$output"
```

**Key Takeaways:**
1. **yuv420p pixel format is critical** - Videos without it show as file attachments
2. **VP9/HEVC codecs don't work in Signal** - Even if container is MP4
3. **File size limit:** Signal has 95-100 MB cross-platform limit
4. **Profile matters:** High 4:4:4 profile fails on mobile devices
5. **Always use +faststart flag** - Enables progressive/inline playback

**References:**
- Signal GitHub Issues: #8709 (H.265 not supported), #12679 (cross-platform issues)
- iOS encoding standards: Baseline/Main profiles for maximum compatibility
- Mobile video best practices: yuv420p required by Apple devices

**Testing:**
```bash
# Check current format
vcheck video.mp4

# Fix for Signal compatibility
signalfix video.mp4
# or
vfix video.mp4

# Download and auto-fix
dlfix https://instagram.com/reel/...
```

---

## Shell URL Handling & Glob Expansion

### Lesson: URLs with Special Characters Break in Zsh Without Protection

**Problem:**
```bash
dl https://instagram.com/reel/ABC/?igsh=XYZ
# Error: zsh: no matches found: https://...
```

**Root Cause:**
Zsh interprets `?`, `*`, `[`, `]` as glob patterns and tries to expand them as file paths before passing to the function. This fails for URLs containing query parameters.

**Solution Implemented:**
Added `noglob` prefix to all download aliases in `.zsh_functions:15-22`:
```bash
alias dl='noglob download_video'
alias dlvid='noglob download_video'
alias dlaudio='noglob download_video --audio-only'
alias dlfix='noglob download_video --check-format'
```

**Why This Works:**
- `noglob` disables glob expansion for that command only
- URLs are passed literally to the function
- No need to quote URLs anymore

**Key Takeaways:**
1. **Always use `noglob` for functions that accept URLs**
2. **Don't rely on users remembering to quote URLs**
3. **Test with URLs containing `?`, `&`, `*` characters**
4. **Regular functions (not aliases) still need quoting or noglob**

**Alternative Solutions:**
```bash
# User can manually disable globbing
noglob command url

# Or quote the URL
command "url?param=value"

# Or use setopt
setopt noglob
command url
unsetopt noglob
```

---

## File Location Strategies

### Lesson: Default to /tmp/ with Smart Fallback for Better UX

**Problem:**
Downloaded files were cluttering the current working directory, making cleanup difficult. Users often forgot where files were saved.

**Solution Implemented:**
Implemented tiered fallback logic in `download_video()` and `check_video_format()`:

```bash
# Priority order:
1. User-specified directory (if provided via -d flag)
2. /tmp/ (preferred for temporary downloads)
3. ./ (current directory fallback)
4. ~/ (home directory last resort)
```

**Implementation Pattern:**
```bash
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

# Then try locations in order
if [[ -n "$user_specified" ]]; then
  output_dir="$user_specified"
elif _test_write_permission "/tmp"; then
  output_dir="/tmp"
elif _test_write_permission "."; then
  output_dir="."
elif _test_write_permission "$HOME"; then
  output_dir="$HOME"
else
  echo "ERROR: No writable directory found"
  return 1
fi
```

**Key Takeaways:**
1. **Always test write permissions before attempting operations**
2. **Use /tmp/ for temporary downloads** - auto-cleanup on reboot
3. **Provide override option** - `-d` or `--output-dir` flag
4. **Show the user where files are saved** - Echo the directory
5. **Use process ID in test files** - `$$` prevents conflicts

**Why /tmp/ First?**
- Automatically cleaned on reboot
- Fast (often in RAM on macOS)
- Doesn't clutter user directories
- Expected location for temporary files

---

## Git Workflow & Sync Scripts

### Lesson: Changes Must Be Pulled Before Sync Can Apply Them

**Problem:**
User ran `./sync_mac_dotfiles.sh` but changes weren't applying to their shell, even though git push succeeded.

**Root Cause:**
1. Changes were pushed to remote from development session
2. User's local git repo HEAD was at old commit
3. Sync script copies files from local repo to `~/`
4. Shell was loading old files because local repo was outdated

**Solution Workflow:**
```bash
# When Claude pushes changes:
1. git add <files>
2. git commit -m "message"
3. git push origin main

# User must do:
1. git pull origin main          # Get latest changes
2. ./sync_mac_dotfiles.sh        # Sync to home directory
3. source ~/.zshrc               # Reload shell config
```

**Key Takeaways:**
1. **Sync script works on local files only** - doesn't auto-pull
2. **Always pull before syncing** after remote changes
3. **Check git log to verify you have latest commits**
4. **source ~/.zshrc is required** - shell doesn't auto-reload
5. **Consider adding git pull to sync script** - but user may have local changes

**Improved Sync Script Idea:**
```bash
# Add to sync_mac_dotfiles.sh
echo "Checking for remote updates..."
git fetch origin
if [ $(git rev-list HEAD...origin/main --count) -gt 0 ]; then
  echo "⚠️  Remote has new commits. Run 'git pull' first!"
  read -p "Pull now? (y/n): " pull_choice
  if [[ "$pull_choice" == "y" ]]; then
    git pull origin main
  fi
fi
```

---

## FFmpeg Best Practices

### Lesson: FFmpeg Command Construction Requires Careful Ordering

**Problem:**
FFmpeg commands failed with cryptic errors or produced unexpected results.

**Correct Parameter Order:**
```bash
ffmpeg [global options] \
  -i input.mp4 \              # Input ALWAYS after global options
  [input options] \
  [output options] \          # Codec, quality, filters
  output.mp4                  # Output file LAST
```

**Common Gotchas:**

1. **Input Options Go BEFORE `-i`:**
```bash
# WRONG - framerate ignored
ffmpeg -i input.mp4 -r 30 output.mp4

# RIGHT - framerate applied to input
ffmpeg -r 30 -i input.mp4 output.mp4
```

2. **Codec Selection Order Matters:**
```bash
# WRONG - profile applied before codec specified
ffmpeg -i input.mp4 -profile:v main -c:v libx264 output.mp4

# RIGHT - codec first, then profile
ffmpeg -i input.mp4 -c:v libx264 -profile:v main output.mp4
```

3. **Always Use `-y` or `-n` for Non-Interactive Scripts:**
```bash
# Without -y, ffmpeg prompts to overwrite
ffmpeg -i input.mp4 output.mp4  # Will hang if output exists

# Force overwrite (use in scripts)
ffmpeg -i input.mp4 -y output.mp4

# Never overwrite (safe mode)
ffmpeg -i input.mp4 -n output.mp4
```

4. **Pixel Format Must Come After Codec:**
```bash
# RIGHT
-c:v libx264 -pix_fmt yuv420p

# WRONG
-pix_fmt yuv420p -c:v libx264
```

**Quality vs Bitrate:**
```bash
# Use CRF for quality-based encoding (recommended)
-crf 23  # 0-51, lower = better quality, 23 is default

# Use bitrate for size-based encoding
-b:v 1M  # Fixed bitrate

# DON'T use both - CRF overrides bitrate
```

**Key Takeaways:**
1. **Read ffmpeg errors carefully** - they tell you what's wrong
2. **Test commands on small files first**
3. **Use `-t 10` to test on first 10 seconds**
4. **Check output with ffprobe after conversion**
5. **Log successful commands for reuse**

---

## Python Integration

### Lesson: Python Can Enhance Shell Functions for Complex Operations

**Problem:**
MAC address validation and formatting in pure bash was complex, error-prone, and hard to maintain.

**Solution Implemented:**
Created Python helper scripts that shell functions call for complex operations:

```bash
# Shell function delegates to Python
change_mac_address() {
  local interface="$1"
  local new_mac="$2"

  # Python handles validation, formatting, vendor lookup
  python3 "${SCRIPT_DIR}/mac_utils.py" \
    --validate "$new_mac" \
    --interface "$interface"

  # Shell handles system commands
  sudo ifconfig "$interface" ether "$new_mac"
}
```

**When to Use Python:**
- Complex string parsing/validation
- API calls with JSON responses
- Advanced data structures (dicts, lists)
- Regular expression complexity
- Cross-platform compatibility

**When to Keep in Bash:**
- Simple file operations
- System commands (ifconfig, networksetup, etc.)
- Environment variable manipulation
- Quick text processing with grep/sed/awk

**Key Takeaways:**
1. **Python for logic, Bash for glue** - use best tool for each part
2. **Pass data via command line args or stdin/stdout**
3. **Make Python scripts standalone testable**
4. **Include shebang and make executable** - `#!/usr/bin/env python3`
5. **Handle missing Python gracefully** - check if installed

**Example Pattern:**
```bash
# Check Python availability
if ! command -v python3 &>/dev/null; then
  echo "❌ Python 3 required but not installed"
  return 1
fi

# Call Python with error handling
if ! python3 script.py "$arg"; then
  echo "❌ Python script failed"
  return 1
fi
```

---

## Shell Function Design

### Lesson: Well-Designed Functions Follow Consistent Patterns

**Best Practices from This Project:**

1. **Always Validate Input First:**
```bash
my_function() {
  local required_param="$1"

  if [[ -z "$required_param" ]]; then
    echo "Usage: my_function <required_param>"
    return 1
  fi

  if [[ ! -f "$required_param" ]]; then
    echo "❌ Error: File not found: $required_param"
    return 1
  fi

  # Function logic here...
}
```

2. **Use Named Local Variables:**
```bash
# GOOD - clear and maintainable
download_video() {
  local url="$1"
  local quality="$2"
  local output_dir="$3"

  # Use named variables
  echo "Downloading from: $url"
}

# BAD - unclear what parameters mean
download_video() {
  echo "Downloading from: $1"
  some_command "$2" "$3"
}
```

3. **Provide Usage Help:**
```bash
my_function() {
  if [[ -z "$1" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    cat << 'EOF'
Usage: my_function <param1> [param2]

Description of what this function does.

Examples:
  my_function value1
  my_function value1 value2

Options:
  -h, --help    Show this help message
EOF
    return 0
  fi

  # Function logic...
}
```

4. **Use Meaningful Return Codes:**
```bash
# 0 = success
# 1 = user error (bad input)
# 2 = environment error (missing tool)
# 3+ = specific error codes

check_requirements() {
  if ! command -v ffmpeg &>/dev/null; then
    echo "❌ ffmpeg not found"
    return 2
  fi
  return 0
}
```

5. **Provide Visual Feedback:**
```bash
# Use emojis sparingly and consistently
echo "🔍 Analyzing..."
echo "✅ Success!"
echo "❌ Error occurred"
echo "⚠️  Warning: ..."
echo "📁 Output: /path/to/file"
echo "🔧 Converting..."
```

6. **Handle Errors Gracefully:**
```bash
download_video() {
  local url="$1"

  # Check dependencies
  if ! command -v yt-dlp &>/dev/null; then
    echo "❌ yt-dlp not installed"
    echo "Install with: brew install yt-dlp"
    return 2
  fi

  # Attempt operation with error checking
  if ! yt-dlp "$url" -o "%(title)s.%(ext)s"; then
    echo "❌ Download failed. Check URL and network connection."
    return 1
  fi

  echo "✅ Download complete!"
  return 0
}
```

7. **Support Dry-Run Mode:**
```bash
my_function() {
  local dry_run=false

  # Parse flags
  if [[ "$1" == "--dry-run" ]]; then
    dry_run=true
    shift
  fi

  local file="$1"

  if [[ "$dry_run" == true ]]; then
    echo "[DRY RUN] Would process: $file"
    return 0
  fi

  # Actual operation
  process_file "$file"
}
```

---

## Common Debugging Techniques

### 1. Enable Debug Mode
```bash
# At top of function
set -x  # Enable command tracing
# ... function code ...
set +x  # Disable tracing

# Or run with debug flag
bash -x script.sh
```

### 2. Check Variable Contents
```bash
# Print with labels
echo "DEBUG: url=$url"
echo "DEBUG: quality=$quality"

# Print array contents
echo "DEBUG: files=(${files[@]})"

# Print variable type
declare -p variable_name
```

### 3. Test Commands Independently
```bash
# Extract command and test separately
cmd="ffmpeg -i input.mp4 output.mp4"
echo "Would run: $cmd"  # Verify command looks right
eval "$cmd"              # Then execute
```

### 4. Use shellcheck
```bash
# Install shellcheck
brew install shellcheck

# Check script
shellcheck script.sh

# Check function in file
shellcheck -x .zsh_functions
```

---

## Version History

### 2025-10-22: Video Format Compatibility & URL Handling
- Added Signal/iOS/Android video format compatibility
- Fixed zsh glob expansion issues with URLs
- Implemented /tmp/ default for downloads
- Enhanced FFmpeg conversion with mobile-optimized parameters

### 2025-10-XX: Python MAC Address Management
- Integrated Python for MAC address validation
- Added vendor lookup functionality
- Improved error handling and user feedback

### 2025-09-XX: Initial Documentation
- Created modular zsh configuration structure
- Established sync script workflow
- Documented feature inventory

---

## Contributing

When adding new lessons to this document:

1. **Use the established format:**
   - Clear problem statement
   - Root cause analysis
   - Solution with code examples
   - Key takeaways list

2. **Include working code examples** - not pseudocode

3. **Add references** to relevant files (with line numbers)

4. **Link to external resources** when applicable

5. **Update the version history** at the bottom

---

## Related Documentation

- [README.md](README.md) - Main project documentation
- [MACOS_FEATURES.md](MACOS_FEATURES.md) - Feature inventory
- [macOS_Configuration_Guide.md](macOS_Configuration_Guide.md) - Setup instructions
- [FEATURE_COMPARISON.md](FEATURE_COMPARISON.md) - macOS vs Linux features

---

**Questions or issues?** Open an issue at https://github.com/gitayam/dotfiles/issues
