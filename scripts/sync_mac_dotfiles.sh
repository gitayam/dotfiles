#!/bin/bash
# Kept for old instructions. The sync lives in macos/install.sh, which copies
# from shared/zsh. This script used to read from scripts/, which holds no zsh
# files, and its `ln -sf` replaced ~/.zsh_handle_files with a dangling symlink.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../macos/install.sh" "$@"
