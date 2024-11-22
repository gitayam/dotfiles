export PATH=$PATH:/Users/sac/.local/bin
alias age_pub='/private/tmp/age-py/age.sh'
# ~/.zshrc

# Set the default prompt
export PS1="%n@%m %1~ %# "

# # Enable command auto-suggestions
# autoload -U compinit && compinit

# Load aliases from ~/.zsh_aliases
if [ -f ~/.zsh_aliases ]; then
  source ~/.zsh_aliases
fi

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
# Enhanced Prompt with Git Branch and Time
# ----------------------
# autoload -Uz vcs_info
# precmd() { vcs_info }
# zstyle ':vcs_info:*' formats '(%b)'

# export PS1="%n@%m %1~ [%D{%L:%M:%S}] ${vcs_info_msg_0_} %# "

# Use Touch ID for sudo for Macs with Touch Bar if user selects yes 
echo -n "Do you want to use Touch ID for sudo for Macs with Touch Bar? (y/n) "
read REPLY
REPLY=${REPLY:-n}
if [[ $REPLY =~ ^[Yy]$ ]]; then
  sudo sed -i '' '1s;^;auth       sufficient     pam_tid.so\n;' /etc/pam.d/sudo
else 
  echo "Touch ID for sudo not enabled. Passwords will be required for sudo."
fi
