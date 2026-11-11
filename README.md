# DSLinuxDSi

DSLinux (uClinux 2.6.14 for the Nintendo DS) made to run on a **Nintendo DSi XL in DSi mode**, with the DSi's 16 MB of RAM,
its internal SD slot and its touchscreen, launched from TWiLight Menu++ through Unlaunch. Nothing is ever written to the DSi NAND.

This repository holds the notes, build scripts and patches. The source tree is a separate clone of
[ipwndev/DSLinux](https://github.com/ipwndev/DSLinux) (GPL-2.0, a mirror of the official SVN) that you create in `work/dslinux`;
the changes are in `patches/` (36 small patches, in order) and explained in `docs/`.

## What works, and how it was tested

"Console" means a real DSi XL, checked from photos of its screen and from the log file read back on a PC.
"melonDS" means the emulator (DSi mode with the user's own dumps; those were never read, copied or committed).
"Compiled" means it builds and was inspected, but nothing has run it.

| Feature | Tested on | Notes |
|---|---|---|
| Unmodified DSLinux builds from source (Debian Wheezy i386 container, 2008 prebuilt toolchain) | compiled; melonDS (DS mode) | Stage 1 |
| DSi-mode start: the ROM header is rewritten to unit code 3 (or 2) so loaders use DSi mode | console | A plain DS header runs in DS mode with 4 MB of RAM mirrored; that was the cause of an early false "16 MB works" |
| 16 MB of real RAM | console | Boot-time test writes two values 12 MB apart; `MemTotal` about 14 MB (the kernel image takes the rest) |
| DSi-mode touchscreen | console | The touch/sound chip is in a different mode in DSi mode; read through the codec registers (port of BlocksDS libnds code, zlib) |
| DSi internal SD card (SDHC) | console | Polling driver on the ARM7, ported from profi200's `dsi_sdmmc` (MIT); partition table, FAT32 mount and directory listing work |
| Card confined to its `linux/` folder | console | Mounted read-only at a scratch directory, only `linux/` bind-mounted, scratch directory unmounted; self-test line `CONF: PASS` and `ls /media` shows only `linux` |
| Userland from the card, shell prompt | console | `/etc`, `/var`, `/home` get RAM copies at boot so the system can write while the card stays untouched (changes are lost at power-off) |
| One writable file on the card: `sd:/linux/DSILOG.TXT` | console | See "Writing to the card" |
| Writable ext2 root image `sd:/linux/ROOTFS.IMG`, card confined to it and the log file (reads too) | console (`v` build) | Reported by the user: files can be written and read. Persistence across a reboot and `e2fsck` of the image on a PC not yet reported |
| Desktop: Nano-X on the top screen (`/boot/desktop`), bottom screen = trackpad above the touch keyboard, Windows 95 look with taskbar, Start menu, Notes, Files | console (`w95a`): everything shows and works (photos of the Start menu, Files and Notes); but redraws take about half a second and the interface is too large. `w95b` (small 8x8 font, smaller frames and windows, incremental repaints, `/boot/dsbench`) compiled, **not yet run** | Pointer: drag on the upper part of the bottom screen, tap = left click, R = left click, L = right click |
| `poweroff` actually powering off the DSi | console (`z` build) | Works (user report). Earlier tries (DS power bit as it was, an I2C write) left the DSi on; the ARM7's own SPI write to the power chip, with bounded waits, is what worked. If it ever fails, the kernel prints a `dsi poweroff: still on ...` line with the chip state |
| Boot self-test (RAM, SD, confinement) printed at the end of boot | console | `/boot/selftest` |
| ARM9 at 134 MHz | console (nothing to change) | The `u` build reads the clock register (read-only) and the self-test shows `CLK : PASS - ARM9 at 134 MHz (the fastest)`; the loader sets it. The optional `CONFIG_NDS_DSI_FASTCPU` writes the same bit and changes nothing |

## Not done, not verified, or out of scope

- **Faster clock:** nothing to do, the loader already runs the ARM9 at 134 MHz in DSi mode. (The ARM7 has no equivalent switch as far as I know; it stays at about 33 MHz.)
- **Wi-Fi:** the DS Wi-Fi driver is left out of the DSi build (the chip does not exist in DSi mode and its setup hung the boot). DSi Wi-Fi (an Atheros chip) is not attempted.
- **Cameras, DSP, DSi-mode sound:** not attempted or not tested.
- **Extra login terminals and `gpm`:** off by default (they stalled the first boots in 16 MB mode); `extra_terminals="YES"` in `/etc/rc.conf` turns them on, untested.
- **`fwver` (DS firmware version at boot):** skipped by default; its firmware read could wait forever in DSi mode.
- **Writes outside `ROOTFS.IMG` and `DSILOG.TXT`:** impossible by design (see above).
- **DS and DS-Lite builds:** the original DSLinux builds are unchanged here; only the Stage 1 build was run (in melonDS).

## Writing to the card, and the rule "nothing outside /linux"

The card is **never** mounted as a FAT filesystem that the system can write. Instead, two preallocated files inside `sd:/linux/` are the only
things that can be touched, and the **ARM7 (not the kernel) enforces it**:

1. `sd:/linux/ROOTFS.IMG`: an **ext2 filesystem image** (512 MiB by default) that holds the whole system. It is the read-write root (`/etc`, `/usr`, `/var`, `/home`, passwords,
   permissions, symlinks, everything persistent), like a real distro. Build it with `scripts/make-rootimg.sh` and copy it onto the card as one file.
2. `sd:/linux/DSILOG.TXT`: the 1 MiB boot-log file (`/dev/dsilog`, `/boot/savelog`).

At boot the ARM7 reads the card's FAT32 itself (MBR, boot sector, `LINUX` folder, each file's directory entry and cluster chain) and keeps the files' sector ranges.
Once `ROOTFS.IMG` is registered it **refuses every read and every write outside those two files**, including raw access by root. The kernel exposes only `/dev/dsiroot`
(the image as a block device, mapped through the extents); the whole card is not a device at all. The files never grow, so no directory entry or FAT entry is ever modified.
A driver bug can therefore at worst damage the image or the log file, never the rest of the card.

Without `ROOTFS.IMG` the build falls back to the earlier mode: the card is mounted read-only, confined to its `linux/` folder, with RAM copies of `/etc /var /home`.

Checked: the ARM7's file-finding and guard code on a PC against test cards containing both files (the extent maps onto the image's real ext2 superblock; the guard accepts exactly the
two files' sectors and rejects neighbours, the MBR, the boot sector and a request that straddles the end; a too-fragmented file is refused); the image itself (`e2fsck` clean, root-owned, only features the 2.6.14 kernel supports).
On the console: the log-file write; the ext2 root (files written and read; a file survived a reboot; self-test `CONF: PASS` and `ROOT: ext2 read-write (persistent)`); `sync; poweroff` switches the DSi off. Not yet checked: an `e2fsck` of the image on a PC after use (it will report the image as not cleanly unmounted, since the root is not remounted read-only at power-off; `e2fsck -fp` is silent about that).
Cautions: ext2 has no journal, so shut down with `sync; poweroff` (after a power loss run `e2fsck -fp ROOTFS.IMG` on the PC); keep the pristine image in `out/dsi-card/sd-root/linux/`; a card with little free space
can fragment the file into more than 255 pieces (then it is refused and the fallback mode is used; the boot log says how many extents it has).
The NAND is never selected (the driver only uses SD port 0).

## Which file to use

All ROMs are built into `out/dsi-mode/` (git-ignored; rebuild with the scripts below). See `out/dsi-mode/README.txt`.

- `dslinux-dsimode-w95e-uc3.nds`: the current build (z plus the desktop on the top screen with the bottom screen as trackpad + keyboard; `old/z-poweroff-works-no-desktop/` is the last build fully confirmed on the console). Before: z (DSi-only header): the writable ext2 root plus a working `poweroff`; needs `ROOTFS.IMG` for the writable root, otherwise it behaves like `u`. `old/u-readonly-card-clock-line/` is the last build confirmed on the console.
- (previous line:) `dslinux-dsimode-u-uc3.nds`: the build before the writable root (DSi-only header). Its self-test also has a `CLK :` line (ARM9 134 MHz or 67 MHz, read from the clock register) and the BogoMIPS line. `-uc2` is the same with a "DS or DSi" header; use it only if uc3 will not launch.
- `old/r-log-file-works/`: the last build that was confirmed on the console (boots to a prompt, writes the log). `s` (tar-only RAM copies, `old/s-tar-m-no-clock-line/`) was run on the console too: clean log, all checks passing. `u` adds only the clock lines.

## Installing on the SD card

Nothing here touches the NAND or Unlaunch. Back up your card first if it matters to you; the build only reads it, except for the log file.

1. Copy `dslinux-dsimode-w95e-uc3.nds` to any folder on the card (for example `sd:/dslinux/`).
2. Copy the whole folder `out/dsi-card/sd-root/linux` to the **root** of the card, so you get `sd:/linux/etc`, `sd:/linux/usr`, `sd:/linux/var`, `sd:/linux/home` and `sd:/linux/lib` (about 109 MB). It must be a folder named `linux` directly at the root.
3. Writable system: `sd:/linux/ROOTFS.IMG` (512 MiB, from `out/dsi-card/sd-root/linux/ROOTFS.IMG`) copied as ONE file, plus `sd:/linux/DSILOG.TXT` (1 MiB), and the card's write-protect slider open. Shut down with `sync; poweroff`.
4. Start the `.nds` from TWiLight Menu++. If it offers a "Run in" setting, choose DSi mode.
5. At the end of boot a self-test prints `RAM`, `SD`, `CONF` lines, then you get a `#` prompt. Logs at the prompt: `cat /tmp/rc.common.log`, `cat /tmp/ramcopy.log`, `dmesg | grep dsisd`. The on-screen keyboard is the touch keyboard on the bottom screen. The busybox `grep` has no `-E`.

## Building

Needs Docker (no sudo if your user can run it), git, and the prebuilt 2008 DSLinux toolchain; downloads go under `~/Documents/Claude/DSLinuxDSi-third-party/`.

```
docker build -t dslinux-wheezy scripts/          # Debian Wheezy i386 with the build dependencies
git clone --depth 1 https://github.com/ipwndev/DSLinux work/dslinux   # then apply patches/ in order (git am)
scripts/prepare-tree.sh                           # recreates empty directories the git mirror drops, fixes autotools timestamps
scripts/build-dsi.sh                              # Nintendo/DSI product (selects it, builds, packs ROMs)
APPFLAGS=1 TAG=w95e scripts/make-dsimode.sh          # re-pack with a DSi header (needs BlocksDS's ndstool)
```

`docs/` has the whole story: `FEASIBILITY.md` (what was known at the start), `STAGE1.md`, `STAGE2.md`, `STAGE3.md` (every step, including the wrong turns and retractions).

## Licences and sources

- DSLinux: GPL-2.0 (ipwndev mirror of svn.dslinux.org). Kernel 2.6.14 (GPL-2.0). Patches here are GPL-2.0.
- `arch/arm/mach-nds/arm7/sdmmc.c`: derived from profi200's `dsi_sdmmc` (MIT, copyright kept in the file).
- `arch/arm/mach-nds/arm7/dsitouch.c`: derived from BlocksDS libnds (zlib, notice kept in the file).
- A third party's unofficial DSi proof of concept (github.com/keiichicom/dslinux) was used only as a comparison binary in the emulator; none of its code is used.
- Console dumps, NAND and firmware were never read, copied, uploaded or committed by this work.
