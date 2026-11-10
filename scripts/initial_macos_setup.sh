#!/bin/bash
# Kept for old instructions; the setup script lives in macos/.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../macos/initial_macos_setup.sh" "$@"
