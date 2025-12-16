# Dotfiles

This repository contains my personal dotfiles for `zsh`, `git`, and other tools, organized by operating system.

## 🎯 Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/gitayam/dotfiles.git ~/.dotfiles
    ```

2.  **Run the installation script for your OS:**
    *   **macOS:**
        ```bash
        cd ~/.dotfiles/macos
        ./install.sh
        ```
    *   **Linux:**
        ```bash
        cd ~/.dotfiles/linux
        ./install.sh
        ```

3.  **Reload your shell:**
    ```bash
    source ~/.zshrc
    ```

## 📁 Directory Structure

The repository is organized into three main directories:

*   `macos/`: Contains configuration files and scripts specific to macOS.
*   `linux/`: Contains configuration files and scripts specific to Linux.
*   `shared/`: Contains configuration files and scripts that are shared between all operating systems.

```
.
├── macos/
│   ├── install.sh
│   └── ... (macOS-specific files)
├── linux/
│   ├── install.sh
│   └── ... (Linux-specific files)
└── shared/
    ├── zsh/
    │   ├── .zshrc
    │   ├── .zsh_aliases
    │   └── ... (zsh files)
    ├── git/
    │   └── .gitconfig
    ├── python/
    │   └── ... (advanced Python scripts)
    ├── javascript/
    │   └── ... (advanced JavaScript scripts)
    └── ... (other shared files)
```

## 🐍 Python & ☕ JavaScript Scripts

The `shared/python` and `shared/javascript` directories contain more advanced, cross-platform scripts. These scripts are intended to be run directly and are not part of the shell configuration.

### Dependencies

Before running the Python or JavaScript scripts, you will need to install their dependencies.

*   **Python:** Each Python script that has dependencies should have a corresponding `requirements.txt` file in the same directory. You can install the dependencies using `pip`:
    ```bash
    pip install -r requirements.txt
    ```

*   **JavaScript:** The JavaScript scripts use Node.js. Make sure you have Node.js and `npm` installed. You can install the dependencies for all scripts from the `shared/javascript` directory:
    ```bash
    cd shared/javascript
    npm install
    ```

## ✨ Key Features

This setup is designed to be modular and easy to maintain. The `install.sh` script in each OS-specific directory creates symlinks to the appropriate files in your home directory.

For a detailed list of features, please see the documentation for each platform:

- **[macOS Features](docs/MACOS_FEATURES.md)**
- **[Linux Features](docs/LINUX_FEATURES.md)**

## 🔧 Installation

The `install.sh` script in each OS-specific directory will guide you through the installation process. It will:

1.  Create symlinks to the shared and OS-specific dotfiles in your home directory.
2.  Install any necessary dependencies (e.g., `brew` packages for macOS).
3.  Back up any existing dotfiles before overwriting them.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request with your changes.