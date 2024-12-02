# Project Overview

This repository contains configuration files and scripts for setting up and maintaining development environments on macOS and Linux systems. It includes:

- **Ansible playbooks** for server maintenance.
  - Tags:
    - `update`: Updates packages on the server.
    - `upgrade`: Upgrades packages on the server.
    - `cleanup`: Removes unused packages on the server.
    - `custom`: Performs custom tasks on the server.
    - `docker`: Performs docker tasks on the server.
    - `git_update`: Performs git update tasks on the server.
- **Shell configuration files** for customization.
- **Dotfile syncing scripts** for macOS and Linux.

## Directory Structure

```
.
├── Configurations
│   └── community_bot_config
├── README.md
├── ansible
│   ├── ansible.cfg
│   ├── inventory
│   │   ├── hosts
│   │   └── hosts-template
│   ├── update_upgrade.yml
│   └── update_upgrade_maintenance.yml
├── linux
│   ├── cron_config.txt
│   └── sync-linux_dotfiles.sh
└── macos
    ├── cron_config.txt
    ├── cron_config.txt.zip
    ├── initial-setup.sh
    └── sync_mac_dotfiles.sh
```

## Getting Started

Repo can be found at https://github.com/gitayam/dotfiles

### Downloading the Repository

#### Using it without Contributing
If you just want to use it without contributing to the repo you can clone it and use it as a local repo.

**Download the repo**
```bash
# Using the Terminal in the directory you want to clone the repo
git clone https://github.com/gitayam/dotfiles.git 
# move into the repo
cd dotfiles
```
**Update the repo**
```bash
# move into the repo
cd dotfiles
# pull the latest changes
git pull
```
#### Contributing 
If you want to contribute to the repo you can fork it and use it as a remote repo.

**Fork the repo**
Click the fork URL and create the fork in your own github account.
https://github.com/gitayam/dotfiles/fork

Using gh on terminal
```bash
gh repo fork gitayam/dotfiles
```

**Clone the forked repo**
```bash
# Using the Terminal in the directory you want to clone the repo
git clone https://github.com/YOUR_GITHUB_USERNAME/dotfiles.git 
# move into the repo
cd dotfiles
```

**Push changes to the remote repo**
```bash
# add all changes
git add .
# commit the changes
git commit -m "commit message"
# push the changes
git push
```

**Create a pull request**
Go to your forked repo on github and create a pull request. This will notify the maintainer to review and merge the changes.

### Initial Setup

1. **macOS:**
   - Run the `initial-setup.sh` script to install necessary applications and set up your environment.
   - This script checks for Homebrew and installs it if not present, then installs terminal and GUI applications.

   ```bash
   cd macos
   ./initial-setup.sh
   ```

2. **Linux:**
   - Ensure you have the necessary permissions to run scripts and install packages.
   - Use the `sync-linux_dotfiles.sh` script to sync your dotfiles.

   ```bash
   cd linux
   ./sync-linux_dotfiles.sh
   ```

### Syncing Dotfiles

- **macOS:**
  - Use the `sync_mac_dotfiles.sh` script to sync your macOS-specific dotfiles.

  ```bash
  cd macos
  ./sync_mac_dotfiles.sh
  ```

- **Linux:**
  - Use the `sync-linux_dotfiles.sh` script to sync your Linux-specific dotfiles.

  ```bash
  cd linux
  ./sync-linux_dotfiles.sh
  ```

### Ansible Playbooks
You can run the playbooks without doing the initial setup or syncing the dotfiles but you will need to setup the hosts file in the inventory directory.
```bash
# copy the hosts-template to hosts and edit the hosts file
cd ansible
cp inventory/hosts-template inventory/hosts
nano inventory/hosts
```


- **Update and Upgrade:**
  - Use the `update_upgrade.yml` playbook to update and upgrade packages on your servers.

  ```bash
  # example using update tag
  sudo ansible-playbook -i inventory/hosts update_upgrade_maintenance.yml --tags=update
  ```

- **Maintenance:**
  - Use the `update_upgrade_maintenance.yml` playbook for comprehensive maintenance, including updating Git repositories and Docker services.
```bash
  # example using all tags which is the same as running the full script
  sudo ansible-playbook -i inventory/hosts update_upgrade_maintenance.yml --tags=docker,git_update
  ```

- **Full Maintenance:**
  - Use the `update_upgrade_maintenance.yml` playbook for comprehensive maintenance, including updating Git repositories and Docker services.

  ```bash
  # example using all tags which is the same as running the full script
  sudo ansible-playbook -i inventory/hosts update_upgrade_maintenance.yml --tags=update,upgrade,cleanup,custom,docker,git_update
  ```

## Additional Information

- **Configurations:** Contains configuration files for community bots and other services.
- **Ansible Inventory:** Customize the `hosts` file in the `ansible/inventory` directory to specify your target servers.
#TODO
- **Cron Configurations:** Use the `cron_config.txt` files to set up scheduled tasks on macOS and Linux.

## Contributing

Feel free to contribute by submitting pull requests or opening issues for any bugs or feature requests.

