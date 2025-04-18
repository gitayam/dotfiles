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

# Load custom functions if available
if [ -f ~/.bash_functions.sh ]; then
  source ~/.bash_functions.sh
fi

# Load custom aliases if available
if [ -f ~/.bash_aliases ]; then
  source ~/.bash_aliases
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


# History settings
# set history size to 1000 which means 1000 commands will be saved in the history
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



# Colorize the `ls` output and setup useful aliases
export LS_OPTIONS='--color=auto'
alias ls='ls $LS_OPTIONS'
alias ll='ls -lh $LS_OPTIONS'        # Detailed list view
alias la='ls -lha $LS_OPTIONS'       # Show hidden files
alias l='ls -lA $LS_OPTIONS'         # Short list view with hidden files
alias lt='ls -strhal $LS_OPTIONS'       # Sort by date, most recent last

# Safe aliases to prevent accidental file overwrites or deletions
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Navigation Function
# Fast directory navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# change dir and List Directory Contents
cdl() {
  if [ -n "$1" ]; then
    cd "$1" && ll
  else
    cd ~ && ll
  fi
}

# create backup of a file or directory
backup() {
  # human readiable date and time with backup
  # check if dir or files exists
  backup_name=".bak_$(date +%Y-%m-%d_%H-%M-%S)"
  # check if rsync is installed if not set copy command to cp
  if command -v rsync &> /dev/null; then
    COPY_CMD="rsync"
  else
    COPY_CMD="cp"
  fi
  # take files, dictionaries as arguments get full path as needed many args possible
  
  for file in "$@"; do
    if [ -f "$file" ]; then
      $COPY_CMD "$file" "$file$backup_name"
      echo "Backup of $file created as $file$backup_name"
    elif [ -d "$file" ]; then
      $COPY_CMD -r "$file" "$file$backup_name"
      echo "Backup of $file created as $file$backup_name"
    else
      echo "$file does not exist"
    fi
  done

}
# Searching 
# Grep aliases and functions
alias grep='grep -i --color=auto "$@"' # Ignore case and colorize output and pass all arguments to grep in quotes
alias grepv='grep -vi --color=auto' # Ignore case, invert match, and colorize output

# Find aliases and functions
alias findf='find . -type f -name' # Find files by name
alias findd='find . -type d -name' # Find directories by name
alias findex=''

# Nano Editor settings
alias nano='nano -c'                # Enable line numbers
alias nanobash='nano ~/.bashrc'     # Open the bashrc file in nano
alias erase='erase_file'          # Custom function to erase a file content then open with nano

# Nano Functions
reset_file() {
    # usage: reset_file file1 file2 ...
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: reset_file file1 file2 ..."
        return 0
    fi
  # Reset the file content to an empty string
  # use the backup function to create a backup of the file before erasing
  #handle one or multiple files
  # catch escapes and errors to handle prompting user to restore backup or delete
  for file in "$@"; do
    backup "$file"
    echo "" > "$file"
    echo "File content backed up and erased."
    echo "Opening $file in nano editor"
    #echo >> the filename to the file with a # at the beginning
    echo "# $file" >> "$file"
    #sleep half a second
    sleep 0.5
    nano "$file"
    # prompt user to restore backup or delete
    ls $file$backup_name
    # default to no
    see_diff="n"
    read -p "Do you want to see the difference between the original and backup file? (y/n):(default:n) " see_diff
    if [ "$see_diff" == "y" ]; then
      diff "$file" "$file$backup_name"
      restore_backup="n"
      read -p "Do you want to restore the backup file? (y/n):(default:n) " restore_backup
      if [ "$restore_backup" == "y" ]; then
        echo "This will delete any changes made to the original file"
        restore_backup_confirm="n"
        read -p "Are you sure you want to restore the backup file? (y/n):(default:n) " restore_backup_confirm
        if [ "$restore_backup_confirm" == "y" ]; then
          mv "$file$backup_name" "$file"
          echo "Backup file restored."
        fi
      fi
    fi
  done
}

# Python Aliases 
pyenv(){
  python3 -m venv env  # Create the virtual environment
  source env/bin/activate  # Activate the virtual environment (on Linux/Mac)
}

pyserver(){
  #get local ip
  local_ip=$(hostname -I | awk '{print $1}')
  # path for the server else use current dir
  # if multiple files passed in arg then create tmp dir and add those passed files or dir via ln to the temp server dir
  if [ -n "$1" ]; then
    # create temp dir
    mkdir -p /tmp/pyserver
    # add files or dir to the temp dir
    #create python server for the dir
    for file in "$@"; do
      ln -s "$file" /tmp/pyserver
    done
    # change dir to the temp dir
    cd /tmp/pyserver
  fi
}
# Docker Aliases
alias dc="docker compose"
alias docker-compose="dc"
alias dcu="dc pull && dc up -d"
alias dcr="dc down && dc up -d"
alias dcp="dc pull"
alias d="docker"
alias dps="d ps"
alias dbash="d exec -it $1 /bin/bash"
alias dsh="d exec -it $1 /bin/sh"


# Networking shortcuts
alias ports='netstat -tulanp'  # List open ports
alias myip='curl ifconfig.me'  # Check external IP address

# Disk usage shortcuts
alias du='du -h --max-depth=1'  # Show disk usage in human-readable format
alias df='df -h'                # Show free disk space in human-readable format

# Git shortcuts
alias gits='git status'
alias gita='git add .'
alias gitc='git commit -m'
alias gitp='git push'
alias gitpl='git pull'
alias gitl='git log --oneline --graph --decorate'
gitupdate='update_git_repos'
# Quick access to server logs
alias logs='tail -f /var/log/syslog'

# Enable colored output in `grep`
alias grep='grep --color=auto'

# Enable bash completion if available
if [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# Display a concise welcome message with essential server information
display_system_info() {
    # Get the local IP address
    local_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "\n================= Server Status for $(hostname) ($local_ip) =================\n"
    
    # Welcome message with server hostname, local IP, and date
    echo "Welcome, $USER! You are logged into server '$(hostname)' (Local IP: $local_ip) at $(date)."
    echo "-------------------------------------------------------------"

    # Display non-system (human) users
    echo -e "\nNon-system Users:"
    awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | column
    
    # Check for any crashed or stalled services
    echo -e "\nCrashed or Stalled Services:"
    systemctl --failed --no-legend | awk '{print "Service:", $1, "- Status:", $3}' || echo "No crashed or stalled services detected."

    # Display last 3 successful logins with IP address
    echo -e "\nLast 3 Successful Logins:"
    last -a | head -n 3 | awk '{print "User:", $1, "- IP:", $(NF), "- Date:", $4, $5, $6, $7}'

    # Display last 10 failed login attempts with IP address
    echo -e "\nLast 10 Failed Login Attempts:"
    sudo grep "Failed password" /var/log/auth.log | tail -n 10 | awk '{print "Date:", $1, $2, "- Time:", $3, "- IP:", $(NF-3)}'

    echo -e "\n=============================================================\n"
}

# Call the display_system_info function
display_system_info
