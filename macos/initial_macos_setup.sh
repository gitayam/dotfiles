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
  terminal_apps=("coreutils" "diceware" "git" "gh" "python" "ansible" "docker" "kubectl" "gpg" "age" "magic-wormhole" "wireguard-tools" "ocrmypdf" "pandoc" "tesseract" "clamav" "ghostscript")
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
  # Prompt user for which Code Editor to install
  echo "Which code editor would you like to install?"
  echo "1. Visual Studio Code"
  echo "2. Cursor (Default)"
  echo "3. Windsurf"
  echo "4. None"
  echo -n "Enter your choice (1-4)(Default: 2) (multiple choices separated by commas): "
  read editor_choice
  editor_choice=${editor_choice:-2}

  # Convert comma separated choices to array, trim whitespace, remove duplicates (zsh compatible)
  raw_choices=()
  local IFS=','
  for item in $editor_choice; do
    raw_choices+=("$item")
  done

  typeset -A seen_editors
  editor_choices=()
  for raw in "${raw_choices[@]}"; do
    choice=$(echo "$raw" | xargs)
    if [[ -n "$choice" && -z "${seen_editors[$choice]}" ]]; then
      editor_choices+=("$choice")
      seen_editors[$choice]=1
    fi
  done

  # If '4' (None) is selected, skip all installations
  if [[ " ${editor_choices[@]} " =~ " 4 " ]]; then
    echo "No code editor selected. Skipping code editor installation."
  else
    for choice in "${editor_choices[@]}"; do
      case $choice in
        1)
          if command -v code &>/dev/null; then
            echo "Visual Studio Code is already installed. Skipping."
          else
            echo "Installing Visual Studio Code..."
            brew install --cask visual-studio-code
          fi
          ;;
        2)
          if command -v cursor &>/dev/null; then
            echo "Cursor is already installed. Skipping."
          else
            echo "Installing Cursor..."
            brew install --cask cursor
          fi
          ;;
        3)
          if command -v windsurf &>/dev/null; then
            echo "Windsurf is already installed. Skipping."
          else
            echo "Installing Windsurf..."
            brew install --cask windsurf
          fi
          ;;
        *)
          echo "Invalid choice: $choice"
          ;;
      esac
    done
  fi

  # Install selected code editors
  for choice in "${editor_choices[@]}"; do
    case $choice in
      1)
        echo "Installing Visual Studio Code..."
        brew install --cask visual-studio-code
        ;;
      2)
        echo "Installing Cursor..."
        brew install --cask cursor
        ;;
      3)
        echo "Installing Windsurf..."
        brew install --cask windsurf
        ;;
      4)
        echo "No code editor selected."
        ;;
      *)
        echo "Invalid choice: $choice"
        ;;
    esac
  done

  # GUI Apps
  gui_apps=("element" "firefox" "keepassxc" "obsidian" "qbittorrent" "simplex" "tailscale")

  for app in "${gui_apps[@]}"; do
    if [[ -d "/Applications/$app.app" ]]; then
    echo "$app is already installed."
  else
    echo "$app is not installed. Installing..."
    brew install --cask "$app"
    fi
  done
  mullvad_apps=("mullvadvpn" "mullvad-browser")
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
  install_mullvad="n"
  read -p "Do you want to install the Mullvad apps? (y/n): " install_mullvad
  if [[ "$install_mullvad" == "y" ]]; then
    for app in "${mullvad_apps[@]}"; do
      echo "$app is not installed. Installing..."
      brew install --cask "$app"
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