export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
alias age_pub='/private/tmp/age-py/age.sh'
# ~/.zshrc
# Set GPG TTY
export GPG_TTY=$(tty)
# Set the default gpg program
git config --global gpg.program $(which gpg)

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

# Function to enable Touch ID for sudo
sudotouch() {
  # Check if Touch ID is already enabled for sudo
  # cat, not grep on both files: BSD grep exits 2 when one is missing, even on a match
  if cat /etc/pam.d/sudo_local /etc/pam.d/sudo 2>/dev/null | grep -q "^auth[[:space:]]*sufficient[[:space:]]*pam_tid.so"; then
    echo "Touch ID for sudo is already enabled."
    return
  fi

  # Prompt to enable Touch ID for sudo
  REPLY="n" # default to no
  echo -n "Touch ID for sudo is not enabled. Do you want to enable it for Macs with Touch Bar? (y/n):(default:n) "
  read REPLY
  REPLY=${REPLY:-n}
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # sudo_local survives macOS updates; edits to /etc/pam.d/sudo are reset by them
    echo "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
    echo "Touch ID for sudo has been enabled."
  else 
    echo "Touch ID for sudo not enabled. Passwords will be required for sudo."
  fi
}
# New-machine setup and Touch ID for sudo, per OS (this file is synced to Linux too)
if [[ "$OSTYPE" == darwin* ]]; then
  alias initial-install="$HOME/Git/dotfiles/macos/initial_macos_setup.sh"
  # call sudotouch to enable Touch ID for sudo if not already enabled
  sudotouch
else
  alias initial-install="$HOME/Git/dotfiles/linux/initial_linux_setup.sh"
fi

# Add local bin to PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# >>> claude-aliases.zsh <<<
[ -r "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh" ] && \
  source "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh"
# >>> claude-aliases.zsh <<<
