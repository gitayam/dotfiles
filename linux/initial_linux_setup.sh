#!/bin/bash
# ./initial-install.sh
# Linux Install

# Define OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi

# Function to install terminal applications
install_terminal_apps() {
  terminal_apps=("diceware" "git" "gh" "python3" "ansible" "docker" "kubectl" "gpg" "age" "magic-wormhole" "wireguard-tools")
  for app in "${terminal_apps[@]}"; do
    if command -v "$app" &> /dev/null; then
      echo "$app is already installed."
    else
      echo "$app is not installed. Installing..."
      sudo apt-get install -y "$app" || sudo snap install "$app"
    fi
  done
}

# Function to install GUI applications
install_gui_apps() {
  gui_apps=("element-desktop" "firefox" "keepassxc" "obsidian" "qbittorrent" "simplex" "tailscale")

  for app in "${gui_apps[@]}"; do
    if command -v "$app" &> /dev/null; then
      echo "$app is already installed."
    else
      echo "$app is not installed. Installing..."
      sudo apt-get install -y "$app" || sudo snap install "$app"
    fi
  done

  proton_apps=("protonvpn" "proton-mail" "proton-pass" "proton-drive")
  install_proton="n"
  read -p "Do you want to install the Proton apps? (y/n): " install_proton
  if [[ "$install_proton" == "y" ]]; then
    for app in "${proton_apps[@]}"; do
      if command -v "$app" &> /dev/null; then
        echo "$app is already installed."
      else
        echo "$app is not installed. Installing..."
        sudo apt-get install -y "$app" || sudo snap install "$app"
      fi
    done
  fi
}

main() {
    echo "Starting initial install..."
    install_terminal_apps
    # Detect if desktop environment is running if so ask about installing GUI apps if not skip entirely 
    if [[ "$OS" == "Ubuntu" || "$OS" == "Debian" ]]; then
        # check if desktop environment is running
        if [[ $(pgrep -c -f "gnome-session") -gt 0 ]]; then
            read -p "Do you want to install GUI apps? (y/n): " install_gui
            if [[ "$install_gui" == "y" ]]; then
                install_gui_apps
            else
                echo "No GUI apps installed."
            fi
        else
            echo "No GUI apps installed because no desktop environment is running."
        fi
    else
        echo "No GUI apps installed because not on Ubuntu or Debian."
    fi
    echo "Syncing Linux aliases and functions to ~/.bashrc"
    ./sync_linux_dotfiles.sh
    echo "Initial install complete."
}

# Run the main function
main
