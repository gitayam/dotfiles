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

## ⚡ AWS Power Functions

A comprehensive collection of AWS CLI helper functions for IAM management, VPC operations, security compliance, and infrastructure management. Functions are available on both macOS (33 functions) and Linux (20 functions).

### Profile & Region Management

*   **Automatic Profile Detection:** Functions use `AWS_PROFILE` or fall back to `default`.
*   **Per-Command Overrides:** Override profile and region with `--profile` and `--region` flags.
*   **`aws_use_profile <profile>`:** Switch the active AWS profile for the session.
*   **`aws_check_profile`**: Verify authentication and IAM permissions.
*   **`aws_temp_credentials`**: Set temporary credentials interactively (macOS).

### IAM User & Group Management

*   **`aws_create_user <name> [-g group]`**: Create IAM user with group assignment and auto-generated password.
*   **`aws_create_group <name> [--type <type>]`**: Create group with predefined permissions (readonly, fullstack, frontend, backend, devops, database, security).
*   **`aws_reset_password <user>`**: Reset console password with auto-generation.
*   **`aws_delete_user`**, **`aws_add_user_to_group`**, **`aws_list_users_in_group`**: Full user lifecycle management.

### VPC Management (macOS)

*   **`aws_vpc_list`**, **`aws_vpc_info`**, **`aws_vpc_create`**, **`aws_vpc_delete`**: Full VPC lifecycle.
*   **`aws_vpc_secure <vpc-id>`**: Interactive security audit — checks IGWs, routes, security groups, NACLs, and public subnets.

### Security & Compliance (macOS)

*   **`aws_enforce_mfa <group>`**: Enforce MFA for all users in an IAM group.
*   **`aws_list_users_without_mfa`**: Audit MFA coverage across the account.
*   **`aws_secure_sg <sg-id>`**: Restrict SSH access to your IP only.
*   **`aws_config_enable`**, **`aws_config_restrict_ssh`**: Set up AWS Config compliance monitoring.

### EC2, S3 & CloudWatch

*   **`aws_ec2_instances`** / **`aws_list_instances`**: List instances with filtering.
*   **`aws_ssm_session <instance_id>`**: Start an interactive SSM session.
*   **`aws_s3_ls [s3://path]`**: User-friendly S3 listing.
*   **`aws_cw_logs <group> [--follow]`**: Tail CloudWatch log groups.
*   **`aws_help`** / **`awshelp`**: Display full command reference.

## ☁️ Cloudflare Scripts

This repository includes powerful scripts for sharing files using Cloudflare Tunnels and Workers.

*   **`cffile-hybrid.sh`**: Share files or directories through a secure tunnel with an optional password protection layer provided by a Cloudflare Worker. This is great for quickly sharing files with a layer of authentication.
    *   **Usage:** `development/cloudflare/cffile-hybrid.sh [options] [file]`

*   **`cfsecure-integrated.sh`**: Provides true end-to-end encrypted file sharing. It encrypts files locally before uploading them, ensuring that only someone with the password can decrypt them.
    *   **Usage:** `development/cloudflare/cfsecure-integrated.sh [options] [file]`

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
