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
for config_file in ~/.zsh_{aliases,functions,git,apps,network,transfer,security,utils,docker}; do
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
  if grep -q "auth       sufficient     pam_tid.so" /etc/pam.d/sudo; then
    echo "Touch ID for sudo is already enabled."
    return
  fi

  # Prompt to enable Touch ID for sudo
  REPLY="n" # default to no
  echo -n "Touch ID for sudo is not enabled. Do you want to enable it for Macs with Touch Bar? (y/n):(default:n) "
  read REPLY
  REPLY=${REPLY:-n}
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo sed -i '' '1s;^;auth       sufficient     pam_tid.so\n;' /etc/pam.d/sudo
    echo "Touch ID for sudo has been enabled."
  else 
    echo "Touch ID for sudo not enabled. Passwords will be required for sudo."
  fi
}
# alias for initial-setup.sh
alias initial-install="./initial-setup.sh"
# call sudotouch to enable Touch ID for sudo if not already enabled
sudotouch

# Add local bin to PATH
export PATH=$PATH:$HOME/.local/bin