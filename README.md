# Wyze Pan v4 SD Card Installer for Thingino

No-open-case installer that replaces the locked Wyze U-Boot with Thingino
U-Boot via SD card. Uses CVE-2026-46728 (FIT hashed-nodes clone attack) to
bypass the RSA-PSS signature verification in the stock U-Boot 2013.07.

## How it works

1. Stock U-Boot `hlupgrade` loads `factory_wcpanv4_uvc` from SD (no auth)
2. `bootm` verifies the FIT RSA-PSS signature - passes via clone attack
3. Stock kernel boots with our installer squashfs as ramdisk
4. Installer backs up entire stock NOR (16 MiB) to SD card with SHA256
5. Installer writes Thingino U-Boot + env to NOR flash
6. Camera reboots into Thingino U-Boot

## Building

```
./build.sh <stock-rom.bin> [uboot.bin] [uboot-env.bin]
```

Requires: `mksquashfs`, `python3`

## Installing

1. Format an SD card as FAT32
2. Copy `factory_wcpanv4_uvc` to the SD card root
3. Insert SD card into the Wyze Pan v4
4. Power on the camera
5. Wait ~30 seconds for the installer to complete
6. Remove SD card - stock backup is in `wyze-backup-panv4/`

## Stock backup

The installer creates a verified backup on the SD card before writing:

```
wyze-backup-panv4/
  full-backup.bin      16 MiB   complete NOR dump
  uboot.bin           192 KiB   stock SPL + U-Boot
  boot.bin            4.4 MiB   stock FIT (kernel+ramdisk+dtb)
  system.bin          5.5 MiB   stock system partition
  back.bin            5.5 MiB   stock backup partition
  cfg.bin             320 KiB   stock config (JFFS2)
  provisioning.bin     64 KiB   stock provisioning
  full-backup.sha256            SHA256 of full dump
  partitions.sha256             SHA256 of all partitions
```

The whole chip is read twice and SHA256-verified, and each file is
size-checked, before any writes happen. If any check fails, the installer
aborts without touching the flash.

## Restoring stock firmware

To restore the stock firmware from the backup:

```
thingino-dfu --host <ip> -w wyze-backup-panv4/full-backup.bin
```

Or from U-Boot console with the backup on SD:

```
fatload mmc 0:1 0x80600000 wyze-backup-panv4/full-backup.bin
sf probe
sf erase 0 0x1000000
sf write 0x80600000 0 0x1000000
reset
```
