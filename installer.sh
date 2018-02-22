#!/usr/bin/env bash
# WARNING: this script will destroy data on the selected disk.
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://nyc3.digitaloceanspaces.com/dangersalad-archlinux/repo/x86_64"

gpg_key_id="21A8557B914A7EA06E99B6AF05041AFE9A54C5FB"
gpg_trusted="/usr/share/pacman/keyrings/archlinux-trusted"

install_details_file="$HOME/.dsinstall"

declare -A lv_defaults=()

lv_defaults[root]=32
lv_defaults[home]=64
lv_defaults[var]=8
lv_defaults[docker]=16
lv_defaults[opt]=8

function should_encrypt () {
    [[ "$do_encrypt" -eq 1 ]]
}

function get_details () {
    ### Get infomation from user ###
    hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
    clear
    : ${hostname:?"hostname cannot be empty"}
    echo "hostname=$hostname" > "$install_details_file"

    user=$(dialog --stdout --inputbox "Enter admin username (default paul)" 0 0) || exit 1
    clear
    user=${user:="paul"}
    echo "user=$user" >> "$install_details_file"

    password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
    clear
    : ${password:?"password cannot be empty"}
    password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
    clear
    [[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )
    echo "password=$password" >> "$install_details_file"

    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
    device=$(dialog --stdout --menu "Select installtion disk" 0 0 0 ${devicelist}) || exit 1
    clear
    echo "device=$device" >> "$install_details_file"

    part_list=(/root $(dialog --stdout --nocancel --checklist "Extra partitions" 0 0 4 "/home" "Home" on "/var" "" 0 "/var/lib/docker" "Docker" 0 "/opt" "" 0))
    clear

    declare -A lv_sizes=()
    declare -A lv_mounts=()

    for part in ${part_list[@]}
    do
        key="$(basename ${part})"
        lv_mounts["$key"]="${part}"
        lv_sizes["$key"]=$(dialog --stdout --inputbox "Initial ${part} size in GiB (Default ${lv_defaults[$key]} GiB)" 0 0) || exit 1
        clear
        lv_sizes["$key"]=${lv_sizes[$key]:-${lv_defaults[$key]}}
    done
    echo "lv_sizes=(${lv_sizes[@]})" >> "$install_details_file"
    echo "lv_mounts=(${lv_mounts[@]})" >> "$install_details_file"

    do_encrypt=0
    dialog --yesno "Encrypt system?" 0 0 && do_encrypt=1
    clear
    echo "do_encrypt=$do_encrypt" >> "$install_details_file"

    luks_password=

    if should_encrypt
    then
        luks_password=$(dialog --stdout --passwordbox "Enter root LUKS password" 0 0) || exit 1
        clear
        : ${luks_password:?"LUKS password cannot be empty"}
        luks_password2=$(dialog --stdout --passwordbox "Enter root LUKS password again" 0 0) || exit 1
        clear
        [[ "$luks_password" == "$luks_password2" ]] || ( echo "LUKS passwords did not match"; exit 1; )
    fi
    echo "luks_password=$luks_password" >> "$install_details_file"

    pkgsel="$(dialog --stdout --no-tags --menu "Package Selection" 0 0 2 "exwm" "EXWM" "none" "No GUI")"
    clear

    pacstrap_pkgs=()

    if [[ "$pkgsel" == "none" ]]
    then
        pacstrap_pkgs=(dangersalad-base)
        if should_encrypt
        then
            pacstrap_pkgs=(dangersalad-base dangersalad-crypt)
        fi

    elif [[ "$pkgsel" == "exwm" ]]
    then
        pacstrap_pkgs=(dangersalad-exwm dangersalad-apps-base)
        if should_encrypt
        then
            pacstrap_pkgs=(dangersalad-crypt dangersalad-exwm dangersalad-apps-base)
        fi
    fi   

    if [[ "$pkgsel" != "none" ]]
    then
        install_dev=0
        dialog --yesno "Install dev apps?" 0 0 && install_dev=1
        clear
        if [[ "$install_dev" -eq 1 ]]
        then
            pacstrap_pkgs=(${pacstrap_pkgs[@]} dangersalad-apps-dev)
        fi
    fi

    hardware_pkg="$(dialog --stdout --no-tags --menu "Harware package" 0 0 2 "none" "None" "dell-5520" "Dell 5520")"
    clear

    if [[ "$hardware_pkg" == "dell-5520" ]]
    then
        pacstrap_pkgs=(${pacstrap_pkgs[@]} dangersalad-dell-5520)
    fi
    
    echo "pacstrap_pkgs=(${pacstrap_pkgs[@]})" >> "$install_details_file"
}


if [[ -f "$install_details_file" ]]
then
    echo "Continuing installation"
else
    get_details
fi
source "$install_details_file"

# check that we have all the details
: ${hostname:?"hostname cannot be empty"}
: ${user:?"user cannot be empty"}
: ${password:?"password cannot be empty"}
: ${device:?"device cannot be empty"}
: ${lv_sizes:?"lv_sizes cannot be empty"}
: ${lv_mounts:?"lv_mounts cannot be empty"}
: ${do_encrypt:?"do_encrypt cannot be empty"}
if should_encrypt
then
    : ${luks_password:?"luks_password cannot be empty"}
fi
: ${pacstrap_pkgs:?"lv_mounts cannot be empty"}

setup_message_format="%20s: %s\n"
function setup_message () {
    if [[ -f "$install_details_file" ]]
    then
        echo -e "Continuing installation\n\nRemove $install_details_file to clear this out\n\n"
    else
        echo -e "Install parameters\n\n"
    fi
    printf "$setup_message_format" "Hostname" "$hostname"
    printf "$setup_message_format" "User" "$user"
    printf "$setup_message_format" "Device" "$device"
    for k in "${!lv_sizes[@]}"
    do
        printf "$setup_message_format" "${lv_mounts[$k]}" "${lv_sizes[$k]} GiB"
    done
    printf "$setup_message_format" "Encrypted?" "$(should_encrypt && echo "Y" || echo "N")"
    echo -e "\n\nPackages\n"
    for pkg in ${pacstrap_pkgs[@]}
    do
        echo "$pkg"
    done
    echo -e "\n\nContinue?"
}

if ! dialog --yesno "$(setup_message)" 0 0
then
    clear
    echo "Aborting install"
    exit 1
fi

clear
echo "Starting install"

vg_name="vg0"

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

if [[ -z "$dsinstall_step_0_partition" ]]
then
    # make sure all crypt partitions are closed
    umount -R /mnt || echo -n

    for k in "${!lv_mounts[@]}"
    do
        cryptsetup luksClose "$k" || echo -n
    done


    # make sure all LVM info is removed
    lvremove -y "${vg_name}" || echo -n
    vgremove -y "${vg_name}" || echo -n
    for dev in
    do
        pvremove -y "${dev}" || echo -n
    done


    ### Setup the disk and partitions ###
    parted --script "${device}" -- mklabel gpt \
           mkpart ESP fat32 1Mib 129MiB \
           set 1 boot on \
           mkpart primary ext4 129MiB 100%

    echo -n "Waiting for partitions"
    while ! ls "${device}"* >/dev/null 2>&1
    do
        echo -n "."
        sleep 0.3
    done
    echo

    # Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1 
    # but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
    part_boot="$(ls ${device}?1)"
    part_lvm="$(ls ${device}?2)"

    wipefs "${part_boot}"
    wipefs "${part_lvm}"

    pvcreate -y "${part_lvm}"
    vgcreate -y "${vg_name}" "${part_lvm}"

    # create partitions to be set up
    for k in "${!lv_sizes[@]}"
    do
        lvcreate -y -L "${lv_sizes[$k]}GiB" -n "$k" "${vg_name}"
    done

    # make swap and temp
    lvcreate -y -L 8GiB -n swap "${vg_name}"
    lvcreate -y -L 2GiB -n tmp "${vg_name}"

    fstab=/mnt/etc/fstab

    if should_encrypt
    then
        printf "$luks_password" | cryptsetup luksFormat --type luks2 -c aes-xts-plain64 -s 512 "/dev/${vg_name}/root" -
        printf "$luks_password" | cryptsetup -d - open "/dev/${vg_name}/root" root
        mkfs.ext4 /dev/mapper/root
        mount /dev/mapper/root /mnt
        mkdir -p /mnt/etc

        crypttab=/mnt/etc/crypttab

        echo "/dev/mapper/root        /       ext4            defaults        0       1" > "$fstab"
        echo "${part_boot}            /boot   vfat            rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro        0       2" >> "$fstab"
        echo "/dev/mapper/tmp         /tmp    tmpfs           defaults        0       0" >> "$fstab"
        echo "/dev/mapper/swap        none    swap            sw              0       0" >> "$fstab"

        echo "swap	/dev/${vg_name}/swap	/dev/urandom	swap,cipher=aes-xts-plain64,size=256" > "$crypttab"
        echo "tmp	/dev/${vg_name}/tmp		/dev/urandom	tmp,cipher=aes-xts-plain64,size=256" >> "$crypttab"

        luks_key_dir=/etc/luks-keys
        mkdir -m 700 "/mnt$luks_key_dir"
        for k in "${!lv_mounts[@]}"
        do
            if [[ "$k" != "root" ]]
            then
                dd if=/dev/random of="/mnt$luks_key_dir/$k" bs=1 count=256 status=progress
                cryptsetup -q luksFormat --type luks2 -v -s 512 "/dev/${vg_name}/$k" "$luks_key_dir/$k"
                cryptsetup -d "/mnt$luks_key_dir/$k" open "/dev/${vg_name}/$k" "$k"
                mkfs.ext4 "/dev/mapper/$k"
                mkdir -p "/mnt${lv_mounts[$k]}"
                mount "/dev/mapper/$k" "/mnt${lv_mounts[$k]}"
                echo "$k	/dev/${vg_name}/$k   ${luks_key_dir}/$k" >> "$crypttab"
                echo "/dev/mapper/$k        ${lv_mounts[$k]}   ext4        defaults        0       2" >> "$fstab"
            fi
        done
    else
        mkfs.ext4 "/dev/${vg_name}/root"
        mount "/dev/${vg_name}/root" /mnt
        mkdir -p /mnt/etc
        
        swapon "/dev/${vg_name}/swap"
        for k in "${!lv_mounts[@]}"
        do
            mkfs.ext4 "/dev/${vg_name}/$k"
            mkdir -p "/mnt${lv_mounts[$k]}"
            mount "/dev/${vg_name}/$k" "/mnt${lv_mounts[$k]}"
        done
    fi


    dd if=/dev/zero of="${part_boot}" bs=1M status=progress || echo -n
    mkfs.vfat -F32 "${part_boot}"
    mkdir /mnt/boot
    mount "${part_boot}" /mnt/boot
    echo "dsinstall_step_0_partition=y" >> "$install_details_file"
fi

### Install and configure the basic system ###
if [[ -z "$dsinstall_step_1_pacman" ]]
then
    # enable multilib
    sed -i 'N;s/#\(\[multilib\]\)\n#\(.*\)/\1\n\2/' /etc/pacman.conf 
    cat >>/etc/pacman.conf <<EOF
[dangersalad]
Server = $REPO_URL
EOF

    echo -n "Getting GPG public key"
    while ! pacman-key --recv-keys "$gpg_key_id" 2>/dev/null
    do
        echo -n "."
        sleep 3
    done
    grep "$gpg_key_id" "$gpg_trusted" || echo "${gpg_key_id}:5:" >> "$gpg_trusted"
    pacman-key --refresh-keys
    pacman-key --lsign-key "$gpg_key_id"

    sed -n 'N;/United States/p' /etc/pacman.d/mirrorlist > /etc/pacman-us.mirrors
    cp /etc/pacman-us.mirrors /etc/pacman.d/mirrorlist
    echo "dsinstall_step_1_pacman=y" >> "$install_details_file"
fi

echo "pacstrapping ${pacstrap_pkgs[@]}"

pacstrap /mnt ${pacstrap_pkgs[@]}

if [[ -z "$dsinstall_step_2_install_setup" ]]
then
    if ! should_encrypt
    then
        genfstab -t PARTUUID /mnt >> "$fstab"
    fi
    echo "${hostname}" > /mnt/etc/hostname

    if ! grep '\[dangersalad\]' /mnt/etc/pacman.conf >/dev/null 2>&1
    then
        cat >>/mnt/etc/pacman.conf <<EOF
[dangersalad]
Server = $REPO_URL
EOF
    fi
    echo -n "Getting GPG public key for installation"
    while ! arch-chroot /mnt pacman-key --recv-keys "$gpg_key_id" 2>/dev/null
    do
        echo -n "."
        sleep 3
    done
    grep "$gpg_key_id" "/mnt$gpg_trusted" || echo "${gpg_key_id}:5:" >> "/mnt${gpg_trusted}"
    arch-chroot /mnt pacman-key --refresh-keys
    arch-chroot /mnt pacman-key --lsign-key "$gpg_key_id"

    for netconf in /etc/netctl/*
    do
        [[ -f "$netconf" ]] && cp "$netconf" "/mnt$netconf"
    done

    echo "dsinstall_step_2_install_setup=y" >> "$install_details_file"
fi

if [[ -z "$dsinstall_step_3_bootloader" ]]
then
    arch-chroot /mnt bootctl install

    cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF

    if should_encrypt
    then
        if [[ "$hardware_pkg" == "dell-5520" ]]
        then
            cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Danger Salad Linux (Arch)
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  cryptdevice=/dev/${vg_name}/root:root root=/dev/mapper/root nvidia_drm.modeset=1 rw
EOF
        else
            cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Danger Salad Linux (Arch)
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  cryptdevice=/dev/${vg_name}/root:root root=/dev/mapper/root rw
EOF
        fi
        
    else
        if [[ "$hardware_pkg" == "dell-5520" ]]
        then
            cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Danger Salad Linux (Arch)
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") nvidia_drm.modeset=1 rw
EOF
        else
            cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Danger Salad Linux (Arch)
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOF
        fi
    fi

    echo "dsinstall_step_3_bootloader=y" >> "$install_details_file"
fi

if [[ -z "$dsinstall_step_4_users" ]]
then
    arch-chroot /mnt groupadd sudo
    arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G sudo,uucp,video,audio,storage,games,input "$user"
    arch-chroot /mnt chsh -s /usr/bin/zsh

    echo "$user:$password" | chpasswd --root /mnt
    echo "root:$password" | chpasswd --root /mnt
    echo "dsinstall_step_4_users=y" >> "$install_details_file"
fi
