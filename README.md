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

### Python Scripts

*   **`organize_files.py`**: A script to organize files in a directory (by default, `~/Downloads`) into subdirectories based on their file extension.
    *   **Usage:** `python python/organize_files.py [directory]`

*   **`mac_manager.py`**: An advanced tool for managing MAC addresses, with features like live vendor lookup, random address generation, and the ability to set MAC addresses.
    *   **Usage:** `python python/mac_manager.py [command]`

### TypeScript/Node.js Scripts

*   **`check-env.js`**: A script to check if all required environment variables are set. It reads the required variables from a `.env.example` file in the current directory.
    *   **Usage:** `node typescript/check-env.js`

### Dependencies

Before running the Python or JavaScript scripts, you will need to install their dependencies.

*   **Python:** Each Python script that has dependencies should have a corresponding `requirements.txt` file in the same directory. You can install the dependencies using `pip`:
    ```bash
    pip install -r python/requirements.txt
    ```

*   **TypeScript/JavaScript:** The `typescript` directory may contain one or more Node.js projects. Each project will have its own `package.json` file. To install dependencies for a project, navigate to its directory and run `npm install`.

## Useful Shell Functions and Aliases



This repository includes a collection of useful shell functions and aliases to streamline your workflow.



### Functions



*   `extract <file>`: Extracts various archive types (e.g., `.tar`, `.zip`, `.rar`).

*   `listening`: Shows which processes are listening on network ports.



### Git Aliases



*   `gs`: Shows a concise Git status.

*   `ga`: Adds all changes to the staging area.

*   `gac`: Adds all changes and commits with a message.

*   `gc`: Commits with a message.

*   `glog`: Displays a visual and readable Git log graph.

*   `gp`: Pulls and pushes changes.

*   `gco`: Checks out a branch.

*   `gcb`: Creates and checks out a new branch.

*   `back`: Checks out the last branch you were on.

*   `gd`: Shows the Git diff.



### Docker Aliases



*   `d`: Short for `docker`.

*   `dps`: Lists running Docker containers.

*   `dka`: Attaches to a running container.

*   `dkl`: Fetches logs of a container.

*   `dkL`: Fetches and follows logs of a container.

*   `dcu`: Brings up Docker Compose services in detached mode.

*   `dcd`: Brings down Docker Compose services.

*   `dke`: Executes a command in a running container.



## 🤝 Contributing



Contributions are welcome! Please open an issue or submit a pull request with your changes.
