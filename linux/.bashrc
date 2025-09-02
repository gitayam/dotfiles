# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don’t do anything
[[ $- != *i* ]] && return

# Basic environment setup
export EDITOR="nano"
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Enable NVM (Node Version Manager) if installed
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # Loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # Loads nvm bash_completion

# Modular sourcing of bash config files (added for maintainability)
for config_file in ~/.bash_{aliases,functions,system,docker,apps,network,security,transfer,utils,handle_files}; do
  if [ -f "$config_file" ]; then
    source "$config_file"
  fi
done

# Remove duplicate or now-modularized function/alias definitions from here if present

# Define OS 
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi

# History settings
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoredups:erasedups  # No duplicate entries
shopt -s histappend                # Append to history, don't overwrite

# Enhanced command-line editing
shopt -s cdspell                   # Correct minor spelling errors in cd
shopt -s autocd                    # Allow directory paths as commands
shopt -s checkwinsize              # Adjust window size after each command
shopt -s globstar                  # Enable recursive globbing (e.g., **/*.txt)

# Custom prompt with color (optional, can be adjusted as needed)
export PS1='\[\e[0;32m\]\u@\h\[\e[m\]:\[\e[0;34m\]\w\[\e[m\]$ '

# Display a concise welcome message with essential server information
display_system_info() {
    local_ip=$(hostname -I | awk '{print $1}')
    echo -e "\n================= Server Status for $(hostname) ($local_ip) =================\n"
    echo "Welcome, $USER! You are logged into server '$(hostname)' (Local IP: $local_ip) at $(date)."
    echo "-------------------------------------------------------------"
    echo -e "\nNon-system Users:"
    awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | column
    echo -e "\nCrashed or Stalled Services:"
    systemctl --failed --no-legend | awk '{print "Service:", $1, "- Status:", $3}' || echo "No crashed or stalled services detected."
    echo -e "\nLast 3 Successful Logins:"
    last -a | head -n 3 | awk '{print "User:", $1, "- IP:", $(NF), "- Date:", $4, $5, $6, $7}'
    echo -e "\nLast 10 Failed Login Attempts:"
    sudo grep "Failed password" /var/log/auth.log | tail -n 10 | awk '{print "Date:", $1, $2, "- Time:", $3, "- IP:", $(NF-3)}'
    echo -e "\n=============================================================\n"
}

display_system_info
