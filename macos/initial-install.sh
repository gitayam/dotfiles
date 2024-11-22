#!/bin/zsh

# MacOS Install
# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Dictionary of commands to install to then loop through and install
# gpg, age, gh, python, pip, virtualenv, poetry, pipx, ansible, ansible-lint, ansible-lint-action, docker, docker-compose, kubectl,  

# Dictionary of Applications to install to then loop through and install --cask
