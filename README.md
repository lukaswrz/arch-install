# arch-install

A simple installation script for [Arch Linux](https://archlinux.org/).

## Usage

```bash
curl -O https://raw.githubusercontent.com/lukaswrz/arch-install/main/arch-install.bash
bash arch-install.bash
```

You can automatically install your dotfiles by setting paramters to the script

`Usage: $0 [-h] [-g repository] [argv...]`

For example:

`$ bash arch-install.bash -g https://github.com/rathmerdominik/testrepofordotfiles -- bash testscript.bash `

## Note

This will only create a basic install without any sort of graphical environment.
