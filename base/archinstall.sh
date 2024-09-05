#!/bin/bash

#Description    : Fully encrypted LVM2 on LUKS with UEFI Arch installation script.
#Author         : @brulliant
#Linkedin       : https://www.linkedin.com/in/schmidbruno/

# Set up the color variables
BBlue='\033[1;34m'
NC='\033[0m'

# Check if user is root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

# Take action if UEFI is supported.
if [ ! -d "/sys/firmware/efi/efivars" ]; then
  echo -e "${BBlue}UEFI is not supported.${NC}"
  exit 1
else
   echo -e "${BBlue}\n UEFI is supported, proceeding...\n${NC}"
fi

# Get user input for the settings
echo -e "${BBlue}The following disks are available on your system:\n${NC}"
lsblk -d | grep -v 'rom' | grep -v 'loop'
echo -e "\n"

read -p 'Select the target disk: ' TARGET_DISK
echo -e "\n"

echo -e "${BBlue}Choosing a username and a hostname:\n${NC}"

read -p 'Enter the new user: ' NEW_USER
read -p 'Enter the new hostname: ' NEW_HOST
echo -e "\n"

echo -e "${BBlue}Set / and Swap partition size:\n${NC}"

read -p 'Enter the size of SWAP in GB: ' SIZE_OF_SWAP
read -p 'Enter the size of / in GB, the remaining space will be allocated to /home: ' SIZE_OF_ROOT
echo -e "\n"

# Use the correct variable name for the target disk
DISK="/dev/$TARGET_DISK"
USERNAME="$NEW_USER"
HOSTNAME="$NEW_HOST"
SWAP_SIZE="${SIZE_OF_SWAP}G" # Modern systems don't really need swap.
ROOT_SIZE="${SIZE_OF_ROOT}G"
CRYPT_NAME='crypt_lvm' # the name of the LUKS container.
LVM_NAME='lvm_arch' # the name of the logical volume.
LUKS_KEYS='/etc/luksKeys' # Where you will store the root partition key


# Setting time correctly before installation
timedatectl set-ntp true

# Partition the disk 1G EFI + REST 

# Create the LUKS container
echo -e "${BBlue}Creating the LUKS container...${NC}"
#read -ps 'Enter a password for the LUKS container: ' LUKS_PASS

# Encrypts with the best key size.
cryptsetup luksFormat --type luks2 --cipher=aes-xts-plain64 $DISK"2" &&\


# Create the LVM physical volume, volume group and logical volume
echo -e "${BBlue}Creating LVM logical volumes on $LVM_NAME...${NC}"
pvcreate /dev/mapper/cryptlvm &&\
vgcreate --verbose lvm_arch /dev/mapper/cryptlvm &&\
lvcreate --verbose -L $ROOT_SIZE lvm_arch -n root &&\
lvcreate --verbose -L $SWAP_SIZE lvm_arch -n swap &&\
lvcreate --verbose -l 100%FREE lvm_arch -n home &&\
lvreduce -L -256M lvm_arch/home

# Format the partitions 
echo -e "${BBlue}Formating filesystems...${NC}"
mkfs.ext4 /dev/lvm_arch/root
mkfs.ext4 /dev/lvm_arch/home
mkswap /dev/lvm_arch/swap
swapon /dev/lvm_arch/swap &&\

# Mount filesystem
echo -e "${BBlue}Mounting filesystems...${NC}"
mount /dev/lvm_arch/root /mnt
mount --mkdir /dev/lvm_arch/home /mnt/home

# Mount efi
echo -e "${BBlue}Preparing the EFI partition...${NC}"
mkfs.fat -F32 $DISK"1"
sleep 2
mkdir --verbose /mnt/efi
sleep 1
mount --mkdir -o uid=0,gid=0,fmask=0077,dmask=0077 $DISK"1" /mnt/efi

# Update the keyring for the packages
echo -e "${BBlue}Updating Arch Keyrings...${NC}" 
pacman -Sy archlinux-keyring --noconfirm

# Install Arch Linux base system. Add or remove packages as you wish.
echo -e "${BBlue}Installing Arch Linux base system...${NC}" 
echo -ne "\n\n\n" | pacstrap -i /mnt base base-devel archlinux-keyring linux linux-headers nvidia nvidia-dkms nvidia-utils intel-ucode\
                    linux-firmware zsh lvm2 mtools networkmanager iwd dhcpcd wget curl git efibootmgr\
                    openssh neovim unzip unrar p7zip zip unarj arj cabextract xz pbzip2 pixz \
                    alsa-firmware alsa-tools alsa-utils fuse3 ntfs-3g zsh-completions net-tools sbctl \
                    lrzip cpio gdisk go rust nasm rsync vim nano dosfstools nano-syntax-highlighting usbutils

# Generate fstab file 
echo -e "${BBlue}Generating fstab file...${NC}" 
genfstab -pU /mnt >> /mnt/etc/fstab &&\

# Preparing the chroot script to be executed
echo -e "${BBlue}Preparing the chroot script to be executed...${NC}"
sed -i "s|^DISK=.*|DISK='${DISK}'|g" ./chroot.sh
sed -i "s|^USERNAME=.*|USERNAME='${USERNAME}'|g" ./chroot.sh
sed -i "s|^HOSTNAME=.*|HOSTNAME='${HOSTNAME}'|g" ./chroot.sh
cp ./chroot.sh /mnt &&\
chmod +x /mnt/chroot.sh &&\
shred -u ./chroot.sh


# Chroot into new system and configure it 
echo -e "${BBlue}Chrooting into new system and configuring it...${NC}"
arch-chroot /mnt 
