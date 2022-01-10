# arch-install

A simple installation script for [Arch Linux](https://archlinux.org/).

## Usage

Clone the repository:

```bash
git clone https://github.com/lukaswrz/arch-install
```

## Synopsis

`arch-install/arch-install.bash [-h] [-p package] [-k format] [-g repository] [command...]`

## Dotfiles

Use `-g` to install your dotfiles via a Git repository. The operands will be
the command which will be executed as soon as the repository has been cloned.
The command will run within the cloned repository.

Example:

`# arch-install/arch-install.bash -g https://github.com/me/my-dotfiles -- ./my-install-script.bash --my-option`

## Encryption

If you use a SATA SSD and want to securely wipe the drive, you should make sure
that the drive is not frozen. To achieve this, run `systemctl suspend` before
running the `arch-install.bash` script.

## Packages

To add more packages to your installation use `-p`. E.g this can be helpful if you need to install dependencies for your dotfiles

## Kernel parameters

Use `-k` to pass a format string that will be inserted in
`GRUB_CMDLINE_LINUX_DEFAULT` from `/etc/default/grub`. Make sure to escape the
dollar signs or use single quotes to prevent variables from being expanded by
the shell.

### Syntax

`# arch-install/arch-install.bash -p package -p anotherpackage`

### Syntax

Example:

`# arch-install/arch-install.bash -k '${default} ${kaby_lake_refresh_hang_fix} additional=parameter $${escaped}'`

Here, `${default}` will be expanded to the kernel parameters which would be
inserted by default. `$${escaped}` will turn into `${escaped}`.

### Available parameters

- `default`
  - Default kernel parameters. These will include the ones required for
    encrypted partitions in case that option has been chosen.
- `kaby_lake_refresh_hang_fix`
  - Fixes glitches and freezes for some Kaby Lake Refresh systems.
- `i8042_touchpad_suspend_fix`
  - Fixes i8042-based touchpads which would otherwise not work properly after
    suspending the system.

## Note

This will only create a basic install without any sort of graphical environment.
