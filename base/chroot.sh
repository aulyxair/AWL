#!/bin/bash

# Description    : This is the chroot which should be executed via 'archinstall.sh'
# Author         : @brulliant
# Linkedin       : https://www.linkedin.com/in/schmidbruno/

# Set up the variables
BBlue='\033[1;34m'
NC='\033[0m'

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# The below values will be changed by ArchInstall.sh
DISK='/dev/sda'
CRYPT_NAME='crypt_lvm'
LVM_NAME='lvm_arch'
USERNAME='<user_name_goes_here>'
HOSTNAME='<hostname_goes_here>'
LUKS_KEYS='/etc/luksKeys/boot.key' # Where you will store the root partition key
UUID=$(cryptsetup luksDump "$DISK""2" | grep UUID | awk '{print $2}')
CPU_VENDOR_ID=$(lscpu | grep Vendor | awk '{print $3}')
kernel=$(uname -r)

# Define the URL of the auditd rules to download
RULES_URL="https://raw.githubusercontent.com/bfuzzy1/auditd-attack/master/auditd-attack/auditd-attack.rules"
# Specify the path to the local auditd rules file
LOCAL_RULES_FILE="/etc/audit/rules.d/auditd-attack.rules"
SSH_PORT=36369 # Change to the desired port.

pacman-key --init
pacman-key --populate archlinux

# Set the timezone
echo -e "${BBlue}Setting the timezone...${NC}"
ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime &&
hwclock --systohc --utc

# Set up locale
echo -e "${BBlue}Setting up locale...${NC}"
sed -i '/#en_US.UTF-8/s/^#//g' /etc/locale.gen &&
locale-gen &&
echo 'LANG=en_US.UTF-8' > /etc/locale.conf &&
export LANG=en_US.UTF-8


# Set hostname
echo -e "${BBlue}Setting hostname...${NC}"
echo "$HOSTNAME" > /etc/hostname &&
echo "127.0.0.1 localhost localhost.localdomain $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

echo -e "${BBlue}Configuring IPtables...${NC}"
# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback interface traffic (localhost communication)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related incoming connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH on custom port (36369) with rate limiting
iptables -A INPUT -p tcp --dpt $SSH_PORT -m conntrack --ctstate NEW -m limit --limit 2/min --limit-burst 5 -j ACCEPT

# Drop any other new connections to the custom SSH port beyond the rate limit
iptables -A INPUT -p tcp --dpt $SSH_PORT -m conntrack --ctstate NEW -j DROP

# Drop invalid packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# Save rules for persistency
iptables-save > /etc/iptables/rules.v4


echo -e "${BBlue}Installing and configuring rng-tools...${NC}"
pacman -S rng-tools --noconfirm
systemctl enable rngd

echo -e "${BBlue}Installing and configuring haveged...${NC}"
pacman -S haveged --noconfirm
systemctl enable haveged.service

# ClamAV anti-virus
echo -e "${BBlue}Installing and configuring clamav...${NC}"
pacman -S clamav --noconfirm

# Rootkit Hunter
echo -e "${BBlue}Installing and configuring rkhunter...${NC}"
pacman -S rkhunter --noconfirm
rkhunter --update
rkhunter --propupd

echo -e "${BBlue}Installing and configuring arpwatch...${NC}"
pacman -s arpwatch --noconfirm

echo -e "${BBlue}Configuring usbguard...${NC}"
pacman -S usbguard --noconfirm

sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
systemctl enable usbguard.service

# Hardening /etc/login.defs

echo -e "${BBlue}Configuring Password Hashing Rounds...${NC}"
sed -i '/#SHA_CRYPT_MIN_ROUNDS 5000/s/^#//;/#SHA_CRYPT_MAX_ROUNDS 5000/s/^#//' /etc/login.defs

echo -e "${BBlue}Ensuring the Strongest Encryption Method is Used...${NC}"
sed -i 's/^ENCRYPT_METHOD[[:space:]]\+.*$/ENCRYPT_METHOD YESCRYPT/' /etc/login.defs

echo -e "${BBlue}Increasing YESCRYPT Cost Factor...${NC}"
sed -i 's/^#YESCRYPT_COST_FACTOR[[:space:]]\+.*$/YESCRYPT_COST_FACTOR 7/' /etc/login.defs

echo -e "${BBlue}Setting HMAC Crypto Algorithm to SHA512...${NC}"
sed -i 's/^#HMAC_CRYPTO_ALGO[[:space:]]\+.*$/HMAC_CRYPTO_ALGO SHA512/' /etc/login.defs

echo -e "${BBlue}Disabling unwanted protocols...${NC}"
# Disable unwanted protocols
echo "install dccp /bin/true" >> /etc/modprobe.d/disable-protocols.conf
echo "install sctp /bin/true" >> /etc/modprobe.d/disable-protocols.conf
echo "install rds /bin/true" >> /etc/modprobe.d/disable-protocols.conf
echo "install tipc /bin/true" >> /etc/modprobe.d/disable-protocols.conf

# Disabling core dump. Comment if you need it.
echo "* hard core 0" >> /etc/security/limits.conf

# Monitoring critical files
echo -e "${BBlue}Installing Aide to Monitor Changes to Critical and Sensitive Files...${NC}"
pacman -Sy aide --noconfirm
aide --init
mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Using NTP for better reliability
echo -e "${BBlue}Using NTP Daemon or NTP Client to Prevent Time Issues...${NC}"
pacman -Sy chrony --noconfirm
pacman -Sy ntp --noconfirm
systemctl enable --now chronyd
systemctl enable --now ntpd

# Process monitoring tool
echo -e "${BBlue}Enabling Process Accounting...${NC}"
pacman -Sy acct --noconfirm
systemctl enable --now psacct

# Sysstem monitoring tool
echo -e "${BBlue}Enabling sysstat to Collect Accounting...${NC}"
pacman -Sy sysstat --noconfirm
systemctl enable --now sysstat

# System auditing tool
echo -e "${BBlue}Enabling auditd to Collect Audit Information...${NC}"
pacman -Sy audit --noconfirm

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    echo "wget could not be found, please install wget and try again."
    exit 1
fi

# Download the auditd rules
echo "Downloading auditd rules from $RULES_URL..."
wget -O "$LOCAL_RULES_FILE" "$RULES_URL"

# Verify download success
if [ $? -ne 0 ]; then
    echo "Failed to download auditd rules."
    exit 1
else
    echo "Auditd rules downloaded successfully."
fi

# Restart auditd to apply the new rules
echo "Restarting auditd to apply the new rules..."
systemctl restart auditd

if [ $? -ne 0 ]; then
    echo "Failed to restart auditd. Check the service status for details."
    exit 1
else
    echo "Auditd restarted successfully. New rules are now active."
fi

systemctl enable --now auditd
sleep 1

# Enable and configure necessary services
echo -e "${BBlue}Enabling NetworkManager...${NC}"
systemctl enable NetworkManager

echo -e "${BBlue}Enabling NetworkManager...${NC}"
systemctl enable iwd

echo -e "${BBlue}Enabling OpenSSH...${NC}"
systemctl enable sshd

echo -e "${BBlue}Enabling DHCP...${NC}"
systemctl enable dhcpcd.service

# Configure sudo
echo -e "${BBlue}Hardening sudo...${NC}"
# Create a group for sudo
groupadd sudo

# Set the secure path for sudo.
echo "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" > /etc/sudoers

# Disable the ability to run commands with root password.
echo "Defaults !rootpw" >> /etc/sudoers

# Set the default umask for sudo.
echo "Defaults umask=077" >> /etc/sudoers

# Set the default editor for sudo.
echo "Defaults editor=/usr/bin/vim" >> /etc/sudoers

# Set the default environment variables for sudo.
echo "Defaults env_reset" >> /etc/sudoers
echo "Defaults env_reset,env_keep=\"COLORS DISPLAY HOSTNAME HISTSIZE INPUTRC KDEDIR LS_COLORS\"" >> /etc/sudoers
echo "Defaults env_keep += \"MAIL PS1 PS2 QTDIR USERNAME LANG LC_ADDRESS LC_CTYPE\"" >> /etc/sudoers
echo "Defaults env_keep += \"LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES\"" >> /etc/sudoers
echo "Defaults env_keep += \"LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE\"" >> /etc/sudoers
echo "Defaults env_keep += \"LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY\"" >> /etc/sudoers

# Set the security tweaks for sudoers file
echo "Defaults timestamp_timeout=30" >> /etc/sudoers
echo "Defaults !visiblepw" >> /etc/sudoers
echo "Defaults always_set_home" >> /etc/sudoers
echo "Defaults match_group_by_gid" >> /etc/sudoers
echo "Defaults always_query_group_plugin" >> /etc/sudoers
echo "Defaults passwd_timeout=10" >> /etc/sudoers # 10 minutes before sudo times out
echo "Defaults passwd_tries=3" >> /etc/sudoers # Nr of attempts to enter password
echo "Defaults loglinelen=0" >> /etc/sudoers
echo "Defaults insults" >> /etc/sudoers # Insults user when wrong password is entered :)
echo "Defaults lecture=once" >> /etc/sudoers
echo "Defaults requiretty" >> /etc/sudoers # Forces to use real tty and not cron or cgi-bin
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers
echo "Defaults log_input, log_output" >> /etc/sudoers # Log input and output of sudo commands
echo "%sudo ALL=(ALL) ALL" >> /etc/sudoers
echo "@includedir /etc/sudoers.d" >> /etc/sudoers

# Set permissions for /etc/sudoers
echo -e "${BBlue}Setting permissions for /etc/sudoers${NC}"
chmod 440 /etc/sudoers 
chown root:root /etc/sudoers

# add a user
echo -e "${BBlue}Adding the user $USERNAME...${NC}"
groupadd $USERNAME
useradd -g $USERNAME -G sudo,wheel -s /bin/zsh -m $USERNAME &&\
passwd $USERNAME &&\

echo -e "${BBlue}Setting up /home and .ssh/ of the user $USERNAME...${NC}"
mkdir /home/$USERNAME/.ssh
touch /home/$USERNAME/.ssh/authorized_keys &&\
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME

# Set default ACLs on home directory 
echo -e "${BBlue}Setting default ACLs on home directory${NC}"
setfacl -d -m u::rwx,g::---,o::--- ~



# GRUB hardening setup and encryption
echo -e "${BBlue}Adjusting /etc/mkinitcpio.conf for encryption...${NC}"
sed -i "s|^HOOKS=.*|HOOKS=(base systemd autodetect microcode modconf kms keyboard block sd-encrypt lvm2 filesystems fsck)|g" /etc/mkinitcpio.conf

mkdir /etc/cmdline.d
touch /etc/cmdline.d/root.conf
echo "rd.luks.name=" > /etc/cmdline.d/root.conf
blkid | grep -o "sda2.*LUKS" >> /etc/cmdline.d/root.conf
echo "=cryptlvm root=/dev/lvm_arch/root" >> /etc/cmdline.d/root.conf





# Checking for NVIDIA GPUs
NVIDIA_CARD=true
echo -e "${BBlue}Found Nvidia GPU...${NC}"

echo -e "${BBlue}Installing NVIDIA drivers...${NC}"
touch /etc/modprobe.d/blacklist-nouveau.conf

echo "blacklist nouveau" >> /etc/modprobe.d/blacklist-nouveau.conf
sed -i "s|^MODULES=.*|MODULES=(nvidia nvidia_drm nvidia_modeset)|g" /etc/mkinitcpio.conf





# Creating a cool /etc/issue
echo -e "${BBlue}Creating Banner (/etc/issue).${NC}"

cat > /etc/issue.net << EOF
Arch Linux \r (\l)

                     .ed"""" """\$\$\$\$be.
                   -"           ^""**\$\$\$e.
                 ."                   '\$\$\$c
                /                      "4\$\$b
               d  3                     \$\$\$\$
               \$  *                   .\$\$\$\$\$\$
              .\$  ^c           \$\$\$\$\$e\$\$\$\$\$\$\$\$.
              d\$L  4.         4\$\$\$\$\$\$\$\$\$\$\$\$\$\$b
              \$\$\$\$b ^ceeeee.  4\$\$ECL.F*\$\$\$\$\$\$\$
  e\$""=.      \$\$\$\$P d\$\$\$\$F \$ \$\$\$\$\$\$\$\$\$- \$\$\$\$\$\$
 z\$\$b. ^c     3\$\$\$F "\$\$\$\$b   \$"\$\$\$\$\$\$\$  \$\$\$\$*"      .=""\$c
4\$\$\$\$L   \     \$\$P"  "\$\$b   .\$ \$\$\$\$\$...e\$\$        .=  e\$\$\$.
^*\$\$\$\$\$c  %..   *c    ..    \$\$ 3\$\$\$\$\$\$\$\$\$\$eF     zP  d\$\$\$\$\$
  "**\$\$\$ec   "\   %ce""    \$\$\$  \$\$\$\$\$\$\$\$\$\$*    .r" =\$\$\$\$P""
        "*\$b.  "c  *\$e.    *** d\$\$\$\$\$"L\$\$    .d"  e\$\$***"
          ^*\$\$c ^\$c \$\$\$      4J\$\$\$\$\$% \$\$\$ .e*".eeP"
             "\$\$\$\$\$\$"'\$=e....\$*\$\$**\$cz\$\$" "..d\$*"
               "*\$\$\$  *=%4.\$ L L\$ P3\$\$\$F \$\$\$P"
                  "\$   "%*ebJLzb\$e\$\$\$\$\$b \$P"
                    %..      4\$\$\$\$\$\$\$\$\$\$ "
                     \$\$\$e   z\$\$\$\$\$\$\$\$\$\$%
                      "*\$c  "\$\$\$\$\$\$\$P"
                       ."""*\$\$\$\$\$\$\$\$bc
                    .-"    .\$***\$\$\$"""*e.
                 .-"    .e\$"     "*\$c  ^*b.
          .=*""""    .e\$*"          "*bc  "*\$e..
        .\$"        .z*"               ^*\$e.   "*****e.
        \$\$ee\$c   .d"                     "*\$.        3.
        ^*\$E")\$..\$"                         *   .ee==d%
           \$.d\$\$\$*                           *  J\$\$\$e*
            """""                             "\$\$\$"

********************************************************************
*                                                                  *
* This system is for the use of authorized users only. Usage of    *
* this system may be monitored and recorded by system personnel.   *
*                                                                  *
* Anyone using this system expressly consents to such monitoring   *
* and is advised that if such monitoring reveals possible          *
* evidence of criminal activity, system personnel may provide the  *
* evidence from such monitoring to law enforcement officials.      *
*                                                                  *
********************************************************************
EOF


echo -e "${BBlue}Setting permission on config files...${NC}"

chmod 0700 /boot
chmod 644 /etc/passwd
chown root:root /etc/passwd
chmod 644 /etc/group
chown root:root /etc/group
chmod 600 /etc/shadow
chown root:root /etc/shadow
chmod 600 /etc/gshadow
chown root:root /etc/gshadow
chown root:root /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config
chown root:root /etc/fstab
chown root:root /etc/issue
chmod 644 /etc/issue
chown root:root /boot/grub/grub.cfg
chmod og-rwx /boot/grub/grub.cfg
chown root:root /etc/sudoers.d/
chmod 750 /etc/sudoers.d
chown -c root:root /etc/sudoers
chmod -c 0440 /etc/sudoers
chmod 02750 /bin/ping 
chmod 02750 /usr/bin/w 
chmod 02750 /usr/bin/who
chmod 02750 /usr/bin/whereis
chmod 0600 /etc/login.defs
chown root:root /etc/issue
chmod 644 /etc/issue

echo -e "${BBlue}Setting root password...${NC}"
passwd &&\


exit
