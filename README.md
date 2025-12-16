# Dotfiles

This repository contains my personal dotfiles for `zsh`, `git`, and other tools, organized by platform and technology.

## 📁 Directory Structure

The repository is organized into the following top-level directories:

*   `macos/`: Contains installation scripts and configuration files specific to macOS.
*   `linux/`: Contains installation scripts and configuration files specific to Linux.
*   `ansible/`: Contains Ansible playbooks for system configuration.
*   `python/`: Contains advanced, cross-platform Python scripts.
*   `typescript/`: Contains TypeScript and JavaScript projects and scripts.
*   `development/`: Contains configurations for development environments, such as Cloudflare workers.
*   `scripts/`: A collection of useful shell scripts.
*   `docs/`: Documentation, guides, and notes.
*   `assets/`: Image assets.
*   `shared/`: Contains configurations and scripts that are shared across multiple platforms, primarily the `zsh` configuration.

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

## 🐍 Python & ☕ TypeScript/JavaScript

The `python` and `typescript` directories contain more advanced, cross-platform scripts. These scripts are intended to be run directly and are not part of the shell configuration.

### Dependencies

Before running the Python or JavaScript scripts, you will need to install their dependencies.

*   **Python:** Each Python script that has dependencies should have a corresponding `requirements.txt` file in the same directory. You can install the dependencies using `pip`:
    ```bash
    pip install -r python/requirements.txt
    ```

*   **TypeScript/JavaScript:** The `typescript` directory may contain one or more Node.js projects. Each project will have its own `package.json` file. To install dependencies for a project, navigate to its directory and run `npm install`.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request with your changes.