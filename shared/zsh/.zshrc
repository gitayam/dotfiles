# ~/.zshrc
# PATH entries are prepended further down; no reset here, so /etc/paths.d and
# ~/.zprofile entries survive. typeset -U drops duplicates.
typeset -U path
# Set GPG TTY
export GPG_TTY=$(tty)
# Set the default gpg program, only when it changed (this runs on every shell)
if command -v gpg >/dev/null 2>&1 && [[ "$(git config --global gpg.program)" != "$(command -v gpg)" ]]; then
  git config --global gpg.program "$(command -v gpg)"
fi

# Set the default prompt
export PS1="%n@%m %1~ %# "

# # Enable command auto-suggestions
# autoload -U compinit && compinit

# Load zsh configuration files
for config_file in ~/.zsh_{aliases,aws,functions,developer,apps,network,transfer,security,utils,docker,handle_files,encryption,git,linux_compat}; do
  if [ -f "$config_file" ]; then
    source "$config_file"
  fi
done

# Define OS 
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi


# Enable syntax highlighting if installed
if [ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Load the Zsh history file
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# ----------------------
# Applications
# ----------------------
# check if brew is installed and install it if not

# ----------------------
# Enhanced Prompt with Git Branch and Time
# ----------------------
# autoload -Uz vcs_info
# precmd() { vcs_info }
# zstyle ':vcs_info:*' formats '(%b)'

# export PS1="%n@%m %1~ [%D{%L:%M:%S}] ${vcs_info_msg_0_} %# "

_sudotouch_enabled() {
  # cat, not grep on both files: BSD grep exits 2 when one is missing, even on a match
  cat /etc/pam.d/sudo_local /etc/pam.d/sudo 2>/dev/null | grep -qE "^[[:space:]]*auth[[:space:]].*pam_tid"
}
_SUDOTOUCH_DECLINED="$HOME/.config/dotfiles/sudotouch-declined"

# Function to enable Touch ID for sudo
sudotouch() {
  if _sudotouch_enabled; then
    echo "Touch ID for sudo is already enabled."
    return
  fi

  # Prompt to enable Touch ID for sudo
  echo -n "Touch ID for sudo is not enabled. Use your fingerprint for sudo? (y/n)(Default: y): "
  read REPLY
  REPLY=${REPLY:-y}
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # One implementation: sudo_local (survives updates), written safely
    "$HOME/Git/dotfiles/macos/harden.sh" --touchid
  else
    mkdir -p "${_SUDOTOUCH_DECLINED:h}" && touch "$_SUDOTOUCH_DECLINED"
    echo "Touch ID for sudo not enabled. Run 'sudotouch' to be asked again."
  fi
}
# New-machine setup and Touch ID for sudo, per OS (this file is synced to Linux too)
if [[ "$OSTYPE" == darwin* ]]; then
  alias initial-install="$HOME/Git/dotfiles/macos/initial_macos_setup.sh"
  # Security report (read-only); `harden --apply` fixes what can be scripted
  alias harden="$HOME/Git/dotfiles/macos/harden.sh"
  # Ask about Touch ID for sudo once: silent when enabled or declined, and only
  # in an interactive terminal (editors probe with `zsh -i -c env`)
  if [[ -t 0 && ! -e "$_SUDOTOUCH_DECLINED" ]] && ! _sudotouch_enabled; then
    sudotouch
  fi
else
  alias initial-install="$HOME/Git/dotfiles/linux/initial_linux_setup.sh"
  alias harden="$HOME/Git/dotfiles/linux/harden.sh"
fi

# Add local bin and the dotfiles' own commands (claude-switch, cc-lumo, ...) to PATH
export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/Git/dotfiles/shared/bin" ]] && export PATH="$HOME/Git/dotfiles/shared/bin:$PATH"
# uv / uvx environment, when installed
[[ -r "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# >>> claude-aliases.zsh <<<
[ -r "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh" ] && \
  source "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh"
# >>> claude-aliases.zsh <<<
