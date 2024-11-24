export PATH=$PATH:/Users/sac/.local/bin
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
# Applications
# ----------------------
# check if brew is installed and install it if not
if ! command -v brew &> /dev/null; then
  echo "brew is not installed. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Loop through this list checking if the application is installed and if not then install it
apps=("element" "firefox" "keepassxc" "obsidian" "coreutils" "diceware" "git" "gh")
for app in "${apps[@]}"; do
  # Capitalize the first letter of the app name
  capitalized_app="${app:0:1:u}${app:1}"

  # Check if the app is a GUI application
  if [ -d "/Applications/$capitalized_app.app" ] || [ -d "/Applications/$app.app" ]; then
    echo "$app is already installed."
  # Check if the app is a command-line tool
  elif command -v "$app" &> /dev/null; then
    echo "$app is already installed."
  else
    echo "$app is not installed. Installing..."
    brew install "$app" || brew install --cask "$app"
  fi
done

# ----------------------
# Enhanced Prompt with Git Branch and Time
# ----------------------
# autoload -Uz vcs_info
# precmd() { vcs_info }
# zstyle ':vcs_info:*' formats '(%b)'

# export PS1="%n@%m %1~ [%D{%L:%M:%S}] ${vcs_info_msg_0_} %# "

# Use Touch ID for sudo for Macs with Touch Bar if user selects yes 
REPLY="n" # default to no
echo -n "Do you want to use Touch ID for sudo for Macs with Touch Bar? (y/n):(default:n) "
read REPLY
REPLY=${REPLY:-n}
if [[ $REPLY =~ ^[Yy]$ ]]; then
  sudo sed -i '' '1s;^;auth       sufficient     pam_tid.so\n;' /etc/pam.d/sudo
else 
  echo "Touch ID for sudo not enabled. Passwords will be required for sudo."
fi

