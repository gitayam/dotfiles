#!/bin/bash
#./initial-install.sh
# MacOS Install
# Define OS 
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi

# Loop through this list checking if the application is installed and if not then install it
install_terminal_apps() {
  terminal_apps=("coreutils" "diceware" "git" "gh" "python" "ansible" "docker" "kubectl" "gpg" "age" "magic-wormhole" "wireguard-tools" "ocrmypdf")
  for app in "${terminal_apps[@]}"; do
    # Capitalize the first letter of the app name
    capitalized_app="$(echo "${app:0:1}" | tr '[:lower:]' '[:upper:]')${app:1}"

    # Check if the app is a GUI application
    if [[ -d "/Applications/$capitalized_app.app" ]] || [[ -d "/Applications/$app.app" ]]; then
      echo "$app is already installed."
    # Check if the app is a command-line tool
    elif command -v "$app" &> /dev/null; then
      echo "$app is already installed."
    else
      echo "$app is not installed. Installing..."
      brew install "$app" || brew install --cask "$app"
    fi
  done
}

install_gui_apps() {
  gui_apps=("element" "firefox" "keepassxc" "obsidian" "qbittorrent" "simplex" "tailscale")

  for app in "${gui_apps[@]}"; do
    if [[ -d "/Applications/$app.app" ]]; then
    echo "$app is already installed."
  else
    echo "$app is not installed. Installing..."
    brew install --cask "$app"
    fi
  done
  proton_apps=("protonvpn" "proton-mail" "proton-pass" "proton-drive")
  # ask the user if they want to install the proton apps
  # default to no
  install_proton="n"
  read -p "Do you want to install the Proton apps? (y/n): " install_proton
  if [[ "$install_proton" == "y" ]]; then
    for app in "${proton_apps[@]}"; do
      # check if the app is already installed
      if [[ -d "/Applications/$app.app" ]]; then
        echo "$app is already installed."
      else
        echo "$app is not installed. Installing..."
        brew install --cask "$app"
      fi
    done
  fi
  
}

main() {
    # Check if Homebrew is installed
    
    echo "Checking if Homebrew is installed..."
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    echo "Starting initial install..."
    install_terminal_apps
    install_gui_apps
    echo "Syncing mac aliases and functions to ~/.zshrc"
    ./sync_mac_dotfiles.sh
    echo "Initial install complete."
}
# Run the main function 
main