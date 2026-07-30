# dotfiles

My personal dotfiles, managed with [stow](https://www.gnu.org/software/stow/)
enhanced with flavour system and [Age](https://age-encryption.org/) encryption.

## Features

- **Flavours**: Different configurations for different machines (personal/work/server/etc.)
- **Age Encryption**: Secure encryption for sensitive config files
- **Multi-Machine**: Automatic setup and key management across machines
- **Stow Integration**: Seamless deployment with GNU Stow

## Installation

1. Install dependencies:
```bash
# macOS
brew install age stow

# Ubuntu/Debian
sudo apt install age stow

# Arch
sudo pacman -S age stow

2. Clone the repository
```bash
> git clone --recursive https://github.com/rverst/dotfiles.git ~/.dotfiles
```

3. Install the dotfiles
```bash
> cd ~/.config
> ./bootstrap
```

