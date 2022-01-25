#!/bin/bash
set -euo pipefail

shopt -s extglob globstar nullglob

function usage() {
  if [[ "$#" != 0 ]]; then
    return 1
  fi
  printf '%s\n' "Usage: $0 [-h] [-k format] [-p package] [-g repository] [command...]" 1>&2
}

function escape() {
  for a in "$@"; do
    printf '%s\n' "${a@Q}"
  done
}

function unescape() {
  for a in "$@"; do
    eval "cat <<< $a"
  done
}

function grubescape() {
  local conv
  for a in "$@"; do
    conv="${a//\\/\\\\}"
    conv="${conv//\"/\\\"}"
    conv="\"$conv\""
    printf '%s\n' "$conv"
  done
}

function parsefmt() {
  local output slice vars fmt
  declare -A vars

  fmt="$1"

  shift

  for assign in "$@"; do
    if [[ "$assign" =~ ([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
      local name val
      name="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      vars["$name"]="$val"
    else
      return 1
    fi
  done

  for ((i = 0; i < ${#fmt}; i++)); do
    slice="$i"
    if [[ "${fmt:i:1}" == '$' ]]; then
      ((i++))
      if [[ "${fmt:i:1}" == '$' ]]; then
        output+='$'
        continue
      elif [[ "${fmt:i:1}" == '{' ]] && ((i < ${#fmt})); then
        ((i++))
        if [[ "${fmt:i:1}" != '}' ]] && ((i < ${#fmt})); then
          local subst
          subst=''
          if [[ "${fmt:i:1}" =~ [a-zA-Z_] ]]; then
            subst+="${fmt:i:1}"
            ((i++))
            while [[ "${fmt:i:1}" =~ [a-zA-Z0-9_] ]] && ((i < ${#fmt})); do
              subst+="${fmt:i:1}"
              ((i++))
            done
            if [[ "${fmt:i:1}" == '}' ]]; then
              if [[ -v "vars[$subst]" ]]; then
                output+="${vars["$subst"]}"
                continue
              fi
            fi
          fi
        fi
      fi
    fi
    len="$((i + 1 - slice))"
    output+="${fmt:slice:len}"
  done

  printf '%s\n' "$output"
}

cmdline_linux_default_fmt='${default}'
packages=(
  base
  base-devel
  linux
  linux-firmware
  linux-headers
  git
  mkinitcpio
  networkmanager
  grub
  sudo
  efibootmgr
  xdg-utils
  xdg-user-dirs
)

while getopts "hp:k:g:" opt; do
  case "$opt" in
  k)
    cmdline_linux_default_fmt="$OPTARG"
    ;;
  g)
    git_repo="$OPTARG"
    ;;
  p)
    packages+=("$OPTARG")
    ;;
  h)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

shift $((OPTIND - 1))

if [[ -v git_repo ]]; then
  export git_repo
  encoded_command="$(escape "$@")"
  export encoded_command
  export -f unescape
elif [[ "$#" != 0 ]]; then
  usage
  exit 1
fi

if efivar -l >/dev/null 2>&1; then
  bios='uefi'
else
  bios='legacy'
fi

pacman -Sy --noconfirm fzy jq

clear

keymap=$(localectl list-keymaps | fzy -p 'enter keymap> ')
localectl set-keymap -- "$keymap"

clear

fdisk --list

block_devices=()

for f in /dev/**/*; do
  if [[ -b "$f" ]]; then
    block_devices+=("$f")
  fi
done

block_device=$(
  unescape "$(
    for dev in "${block_devices[@]}"; do
      printf '%s\n' "$(escape "$dev")"
    done | fzy -p 'enter block device (e.g. /dev/sda)> '
  )"
)

umount --quiet "$block_device" || true

clear
echo "When using an SSD make sure your disk is unfrozen if you choose to encrypt your installation!"
encryption_choice=$(printf 'Yes\nNo\n' | fzy -p 'do you want your drive to be encrypted?')

clear

zones=(/usr/share/zoneinfo/**/*)

zone=$(
  unescape "$(
    for zone in "${zones[@]}"; do
      printf '%s\n' "$(escape "$zone")"
    done | fzy -p 'enter zone information> '
  )"
)

clear

if [[ "$bios" == 'uefi' ]]; then
  read -r -e -p 'enter bootloader id> ' bootloader_id
fi

clear

read -r -e -p 'enter hostname> ' hostname
read -r -e -p 'enter username> ' username
while true; do
  read -r -s -p 'enter password> ' password
  printf '\n'
  read -r -s -p 're-enter password> ' repassword
  printf '\n'
  if [[ "$password" == "$repassword" ]]; then
    hashed_password=$(openssl passwd -1 -stdin <<<"$password")
    break
  fi
  clear
done

if [[ "$encryption_choice" == "Yes" ]]; then
  wipe_choice=$(printf 'Yes\nNo\n' | fzy -p 'do you want to secure wipe your disk?')
  if [[ "$wipe_choice" == "Yes" ]]; then
    drive_choice=$(printf 'SSD\nHDD\n' | fzy -p 'what kind of drive do you have?')
    # Erase disk
    case "$drive_choice" in
    #wont add nvme for now. No way to test
    'SSD')
      frozen_state=$(hdparm -I "$block_device" 2>/dev/null | awk '/frozen/ { print $1,$2 }')
      if [ "${frozen_state}" == "not frozen" ]; then
        hdparm --user-master u --security-set-pass password "$block_device"
        hdparm --user-master u --security-erase password "$block_device"
      else
        echo "Your drive is frozen. Please fix!" >&2
        exit 1
      fi
      ;;
    'HDD')
      cryptsetup open --type plain -d /dev/urandom "$block_device" to_be_wiped
      dd if=/dev/zero of=/dev/mapper/to_be_wiped status=progress bs=1M || true
      cryptsetup close to_be_wiped
      ;;
    esac
  fi

  sgdisk --zap-all "$block_device"

  sgdisk --new=1:0:+512M "$block_device"
  sgdisk --new=2:0:0 "$block_device"

  partitions=()
  query=$(sfdisk --json "$block_device")
  for k in $(jq '.partitiontable.partitions | keys | .[]' <<<"$query"); do
    partitions+=("$(jq --argjson k "$k" -r '.partitiontable.partitions | .[$k] | .node' <<<"$query")")
  done

  boot_fs="${partitions[0]}"
  root_fs="${partitions[1]}"

  cryptsetup -y -v luksFormat "$root_fs"
  cryptsetup open "$root_fs" cryptroot
  mkfs.ext4 /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt

  case "$bios" in
  'uefi')
    mkfs.fat -F32 "$boot_fs"
    ;;
  'legacy')
    mkfs.ext4 "$boot_fs"
    ;;
  esac

  mkdir /mnt/boot
  mount "${partitions[0]}" /mnt/boot
else
  sgdisk --zap-all "$block_device"

  case "$bios" in
  'uefi')
    # boot
    sgdisk --new=1:0:+512M "$block_device"
    # root
    sgdisk --new=2:0:0 "$block_device"
    ;;
  'legacy')
    # root
    parted "$block_device" mklabel msdos mkpart primary 0% 100%
    ;;
  esac

  partitions=()
  query=$(sfdisk --json "$block_device")
  for k in $(jq '.partitiontable.partitions | keys | .[]' <<<"$query"); do
    partitions+=("$(jq --argjson k "$k" -r '.partitiontable.partitions | .[$k] | .node' <<<"$query")")
  done

  case "$bios" in
  'uefi')
    boot_fs="${partitions[0]}"
    root_fs="${partitions[1]}"
    umount --quiet "$boot_fs" "$root_fs" || true
    mkfs.fat -F32 "$boot_fs"
    mkfs.ext4 -F "$root_fs"
    ;;
  'legacy')
    boot_fs="${partitions[0]}"
    root_fs="${partitions[0]}"
    umount --quiet "$root_fs" || true
    mkfs.ext4 -F "$root_fs"
    ;;
  esac

  mount "$root_fs" /mnt

  if [[ "$bios" == 'uefi' ]]; then
    mkdir /mnt/boot
    mount "$boot_fs" /mnt/boot
  fi
fi

pacstrap /mnt "${packages[@]}"

if [[ "$encryption_choice" == "Yes" ]]; then
  sed -i "s/[[:space:]]*HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt filesystems fsck)/" /mnt/etc/mkinitcpio.conf

fi

genfstab -U /mnt >>/mnt/etc/fstab

device_uuid="$(blkid -s UUID -o value "$root_fs")"

export \
  hostname \
  username \
  hashed_password \
  keymap \
  zone \
  bios \
  block_device \
  encryption_choice \
  device_uuid \
  cmdline_linux_default_fmt

if [[ "$bios" == 'uefi' ]]; then
  export bootloader_id
fi

export -f grubescape parsefmt

function chrootsetup() {
  set -euo pipefail

  shopt -s extglob globstar nullglob

  printf 'KEYMAP=%s\n' "$keymap" >/etc/vconsole.conf

  ln -sf "$zone" /etc/localtime

  hwclock --systohc

  printf '%s\n' 'en_US.UTF-8 UTF-8' >/etc/locale.gen
  locale-gen

  printf '%s\n' 'LANG=en_US.UTF-8' >/etc/locale.conf

  printf '%s\n' "$hostname" >/etc/hostname

  default='loglevel=3 quiet'
  crypt="cryptdevice=UUID=$device_uuid:cryptroot root=/dev/mapper/cryptroot"

  if [[ "$encryption_choice" == "Yes" ]]; then
    default="$default $crypt"
  fi

  cmdline_linux_default="$(
    grubescape "$(
      parsefmt "$cmdline_linux_default_fmt" \
        "default=$default" \
        "crypt=$crypt" \
        'kaby_lake_refresh_hang_fix=intel_idle.max_cstate=1 i915.enable_dc=0' \
        'i8042_touchpad_suspend_fix=i8042.reset i8042.nomux i8042.nopnp i8042.noloop'
    )"
  )"

  cat <<EOF >/etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT=$cmdline_linux_default
GRUB_CMDLINE_LINUX=""

GRUB_PRELOAD_MODULES="part_gpt part_msdos"

GRUB_TIMEOUT_STYLE=menu

GRUB_TERMINAL_INPUT=console

GRUB_GFXMODE=auto

GRUB_GFXPAYLOAD_LINUX=keep

GRUB_DISABLE_RECOVERY=true
EOF

  case "$bios" in
  'uefi')
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$bootloader_id"
    ;;
  'legacy')
    grub-install --target=i386-pc "$block_device"
    ;;
  esac

  grub-mkconfig -o /boot/grub/grub.cfg

  mkinitcpio -P

  if [[ "$bios" == 'uefi' ]]; then
    # magic
    mkdir -p /boot/EFI/boot
    cp "/boot/EFI/$bootloader_id/grubx64.efi" /boot/EFI/boot/bootx64.efi
  fi

  useradd -m -G wheel -p "$hashed_password" -- "$username"

  printf '%s\n' '%wheel ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers

  # home dir
  home=$(getent passwd -- "$username" | awk -v RS='' -F ':' '{ print $6 }')
  pushd "$home"
  git clone https://aur.archlinux.org/yay.git
  pushd yay
  chown -R -- "$username:$username" .
  runuser -u "$username" -- makepkg -si --noconfirm
  popd

  if [[ -v git_repo ]]; then
    git clone "$git_repo"
    pushd "$(basename "$git_repo" .git)"
    command=()
    while read -r line; do
      command+=("$(unescape "$line")")
    done <<<"$encoded_command"
    "${command[@]}"
    popd
  fi

  rm --recursive --force yay
  popd

  sed -i -e '$s/.*/%wheel ALL=(ALL) ALL/' /etc/sudoers

  systemctl enable NetworkManager
}

export -f chrootsetup

arch-chroot /mnt /bin/bash -c 'chrootsetup "$@"'

umount -R /mnt
if [[ "$encryption_choice" == "Yes" ]]; then
  cryptsetup close cryptroot
fi
