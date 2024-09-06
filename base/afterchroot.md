Next, modify `/etc/mkinitcpio.d/linux.preset`, as follows, with the appropriate mount point of the EFI system partition: 

Here is a working example linux.preset for the linux kernel and the Arch splash screen. 

```
/etc/mkinitcpio.d/linux.preset
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

#default_config="/etc/mkinitcpio.conf"
#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

#fallback_config="/etc/mkinitcpio.conf"
#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

Finally, to build the **UKI**, make sure that the directory for the UKIs exist.
For example, for the linux preset: 
```
mkdir -p /efi/EFI/Linux
```
```
mkinitcpio -p linux
```

```
passwd
```

Install `systemd-boot` with:

```
bootctl install
```

Reboot into `UEFI`

Now reboot into `UEFI` and put secure boot into **SETUP MODE**. Refer to your motherboard manufaturer's guide on how to do that.

For most systems, you can do this by, just going into **BOOT** tab, **enabling secure boot**, go to **SECURITY** tab and do **Erase all secure boot settings**.

Now save changes and exit.

Now when booting into **Arch Linux** you'll be prompted to enter the passphrase to your LUKS partition.

Enter it and boot into the system. Login as **root**.

Secure Boot

Now to configure secure boot , first install the `sbctl` utility:

```
$ pacman -S sbctl
```

**Note: It might say completed installation with some errors, that's fine because sbctl can't find the key database, because there never was one.

Now run ```sbctl status``` and ensure setup mode is enabled.

Then create your secure boot keys with:

```
$ sbctl create-keys
```

Enroll the keys, with Microsoft's keys, to the UEFI:

```
$ sbctl enroll-keys -m --firmware-builtin
```

```
Options
-m, --microsoft
Enroll UEFI vendor certificates from Microsoft into the signature database. See Option ROM*.

-f, --firmware-builtin
Enroll signatures from dbDefault, KEKDefault or PKDefault. This is usefull if sbctl does not vendor your OEM certificates, or doesn’t include all of them.

Valid values are "db", "KEK" or "PK" passed as a comma
delimitered string.

Default: "db,KEK"
```

Warning: Some firmware is signed and verified with Microsoft's keys when secure boot is enabled. Not validating devices could brick them. To enroll your keys without enrolling Microsoft's, run: `sbctl enroll-keys`. Only do this if you know what you are doing.

Check the secure boot status again:

```
$ sbctl status
```

sbctl should be installed now, but secure boot will not work until the boot files have been signed with the keys you just created. 

Check what files need to be signed for secure boot to work:

```
# sbctl verify
```

Now sign all the unsigned files. Most probably these are the files you need to sign:

```
/efi/EFI/BOOT/BOOTX64.EFI
/efi/EFI/Linux/arch-linux-fallback.efi
/efi/EFI/Linux/arch-linux.efi
/efi/EFI/systemd/systemd-bootx64.efi
```

The files that need to be signed will depend on your system's layout, kernel and boot loader. 

```
$ sbctl sign --save /efi/EFI/BOOT/BOOTX64.EFI
$ sbctl sign --save /efi/EFI/Linux/arch-linux-fallback.efi
$ sbctl sign --save /efi/EFI/Linux/arch-linux.efi
$ sbctl sign --save /efi/EFI/systemd/systemd-bootx64.efi
```

The `--save` flag is used to add a pacman hook to automatically sign all new files whenever the **Linux kernel**, **systemd** or the **boot loader** is updated.

Now reboot, and verify that Secure Boot is enabled by using command `bootctl`

```
bootctl
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
System:
      Firmware: UEFI
 Firmware Arch: x64
   Secure Boot: enabled (user)
  TPM2 Support: yes
  Measured UKI: yes
  Boot into FW: supported
```
Enrolling the TPM

Make sure Secure Boot is active and in user mode when binding to PCR 7, otherwise, unauthorized boot devices could unlock the encrypted volume.
The state of PCR 7 can change if firmware certificates change, which can risk locking the user out. This can be implicitly done by fwupd or explicitly by rotating Secure Boot keys.

To begin, run the following command to list your installed TPMs and the driver in use:

```
$ systemd-cryptenroll --tpm2-device=list
```
Now change pbkdf2 to argon2id

```
cryptsetup luksConvertKey /dev/whatever --pbkdf argon2id
```

Now, let's generate a recovery key in case it all gets messed up some time in the future:

```
$ sudo systemd-cryptenroll /dev/nvme0n1p2 --recovery-key
```

Save or write down the recovery key in some safe and secure place.

To check that the new recovery key was enrolled, dump the LUKS configuration and look for a systemd-tpm2 token entry, as well as an additional entry in the Keyslots section: 

```
$ cryptsetup luksDump /dev/nvme0n1p2
```

It will most probably be in `keyslot 1`.

We'll now enroll our system firmware and secure boot state.
This would allow our TPM to unlock our encrypted drive, as long as the state hasn't changed.

```
$ sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

```
Additional Flags

--tpm2-with-pin=BOOL
When enrolling a TPM2 device, controls whether to require the user to enter a PIN when unlocking the volume in addition to PCR binding, based on TPM2 policy authentication. Defaults to "no". Despite being called PIN, any character can be used, not just numbers.
Note that incorrect PIN entry when unlocking increments the TPM dictionary attack lockout mechanism, and may lock out users for a prolonged time, depending on its configuration. The lockout mechanism is a global property of the TPM, systemd-cryptenroll does not control or configure the lockout mechanism. You may use tpm2-tss tools to inspect or configure the dictionary attack lockout, with tpm2_getcap(1) and tpm2_dictionarylockout(1) commands, respectively.
```

**Note**: Including PCR0 in the PCRs can cause the entry to become invalid after every firmware update. This happens because PCR0 reflects measurements of the firmware, and any update to the firmware will change these measurements, invalidating the TPM2 entry. If you prefer to avoid this issue, you might exclude PCR0 and use only PCR7 or other suitable PCRs.

Info on all additional PCRs can be found [here](https://wiki.archlinux.org/title/Trusted_Platform_Module#Accessing_PCR_registers)

If all is well, reboot , and you won't be prompted for a passphrase, unless secure boot is disabled or secure boot state has changed.


Tips

Now if at some point later in time, our secure boot state has changed, the TPM won't unlock our encrypted drive anymore. To fix it, do the following.

This can be done in a very short step and is less prone to error by running the following command:

```
systemd-cryptenroll --wipe-slot=tpm2 /dev/<device> --tpm2-pcrs=0+7
```

Or, if you prefer to do it manually, do the following:

First enter UEFI, and clear the TPM.

Then boot into Arch Linux, as root.

Then we need to kill keyslots previously used by the **TPM**.

Remove TPM Keyslot:

Figure out which keyslot is being used by the tpm by runnging `cryptsetup luksDump /dev/nvme0n1p2`.

In the **Tokens**: section, look for systemd-tmp2, and under it find the keyslot used:

```
Tokens:
  0: systemd-recovery
	Keyslot:    1
  1: systemd-tpm2
  ...
  ...
	Keyslot:    2
```
As you can see keyslot **1** is used by `systemd-recovery` and **2** is used by `systemd-tpm2`

Now to kill it run:

```
$ sudo cryptsetup luksKillSlot /dev/nvme0n1p2 2
```

After killing the keyslot, we need to remove the Token associated with it.

```
$ sudo cryptsetup token remove --token-id 1 /dev/nvme0n1p2
```
Here we specify `token-id` as `1` based on the previous output of `luksDump`. Specify it correspondingy depending on what the token number is on your output of `luksDump`.

Now repeat the steps from [TPM enrollment](https://github.com/joelmathewthomas/archinstall-luks2-lvm2-secureboot-tpm2?tab=readme-ov-file#13-enrolling-the-tpm) to renroll to the TPM.


With this, the guide has mostly covered on how to install Arch Linux, Encrypt disk with LUKS2 , use logical volumes with LVM2, how to setup Secure Boot, and how to enroll the TPM.

The only steps remaining are to install a Desktop Environment or a Window Manager, which this guide, unfortunately, will not cover.
