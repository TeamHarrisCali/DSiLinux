# DSLinuxDSi

DSLinux (uClinux 2.6.14 for the Nintendo DS) made to run on a **Nintendo DSi XL in DSi mode**, with the DSi's 16 MB of RAM,
its internal SD slot and its touchscreen, launched from TWiLight Menu++ through Unlaunch. Nothing is ever written to the DSi NAND.

This repository holds the notes, build scripts and patches. The source tree is a separate clone of
[ipwndev/DSLinux](https://github.com/ipwndev/DSLinux) (GPL-2.0, a mirror of the official SVN) that you create in `work/dslinux`;
the changes are in `patches/` (22 small patches, in order) and explained in `docs/`.

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
| Boot self-test (RAM, SD, confinement) printed at the end of boot | console | `/boot/selftest` |
| ARM9 at 134 MHz instead of 67 MHz | compiled only | Separate ROM (`t-fast`); the boot log's BogoMIPS and a `NDS: ARM9 SCFG_CLK` line say whether it took effect |

## Not done, not verified, or out of scope

- **Faster clock:** only compiled. If a console misbehaves with the `t-fast` ROM, use the normal one.
- **Wi-Fi:** the DS Wi-Fi driver is left out of the DSi build (the chip does not exist in DSi mode and its setup hung the boot). DSi Wi-Fi (an Atheros chip) is not attempted.
- **Cameras, DSP, DSi-mode sound:** not attempted or not tested.
- **Extra login terminals and `gpm`:** off by default (they stalled the first boots in 16 MB mode); `extra_terminals="YES"` in `/etc/rc.conf` turns them on, untested.
- **`fwver` (DS firmware version at boot):** skipped by default; its firmware read could wait forever in DSi mode.
- **General SD writing:** deliberately not provided (see below).
- **DS and DS-Lite builds:** the original DSLinux builds are unchanged here; only the Stage 1 build was run (in melonDS).
- The `s` and `t-fast` ROMs are newer than the last console run (see "Which file to use").

## Writing to the card (the only way it can happen)

You asked that nothing go outside `/linux`. General read-write FAT would also change the card's allocation tables and directory entries,
so there is none. The one exception is a log file:

1. On a PC, put a 1 MiB file named exactly `DSILOG.TXT` (zeros; `scripts/make-logfile.sh`) into the card's `linux/` folder.
2. At boot the ARM7 reads the card's FAT32 itself, finds that file's sectors and **refuses every write outside them**, including raw writes from a root shell. The write-protect slider is honoured.
3. The file never grows, so no directory or FAT entry changes. `/dev/dsilog` (character device 241:0) writes into it; `/boot/savelog` saves dmesg and the boot logs there at the end of every boot.
4. Read the file on a PC (text, followed by zeros).

Checked: the parser on a PC against a test image with the same layout (the guard accepts exactly the file's sectors, nothing next to them);
on the console, the log was written and read back (1,048,576 bytes unchanged, about 10 KiB of log, no errors).
Not checked: the rest of the card byte for byte before and after, so an independent filesystem check on the PC is a sensible extra step.
The NAND is never selected (the driver only uses SD port 0).

## Which file to use

All ROMs are built into `out/dsi-mode/` (git-ignored; rebuild with the scripts below). See `out/dsi-mode/README.txt`.

- `dslinux-dsimode-s-uc3.nds`: the current build (DSi-only header). `-uc2` is the same with a "DS or DSi" header; use it only if uc3 will not launch.
- `old/r-log-file-works/`: the last build that was confirmed on the console (boots to a prompt, writes the log). `s` differs only by quieter log output (`tar -m`), but has not been run.
- `dslinux-dsimode-t-fast-uc3.nds`: `s` plus the 134 MHz clock. Experimental.

## Installing on the SD card

Nothing here touches the NAND or Unlaunch. Back up your card first if it matters to you; the build only reads it, except for the log file.

1. Copy `dslinux-dsimode-s-uc3.nds` to any folder on the card (for example `sd:/dslinux/`).
2. Copy the whole folder `out/dsi-card/sd-root/linux` to the **root** of the card, so you get `sd:/linux/etc`, `sd:/linux/usr`, `sd:/linux/var`, `sd:/linux/home` and `sd:/linux/lib` (about 109 MB). It must be a folder named `linux` directly at the root.
3. For logging: `sd:/linux/DSILOG.TXT` (1 MiB) as above, and the card's write-protect slider open.
4. Start the `.nds` from TWiLight Menu++. If it offers a "Run in" setting, choose DSi mode.
5. At the end of boot a self-test prints `RAM`, `SD`, `CONF` lines, then you get a `#` prompt. Logs at the prompt: `cat /tmp/rc.common.log`, `cat /tmp/ramcopy.log`, `dmesg | grep dsisd`. The on-screen keyboard is the touch keyboard on the bottom screen. The busybox `grep` has no `-E`.

## Building

Needs Docker (no sudo if your user can run it), git, and the prebuilt 2008 DSLinux toolchain; downloads go under `~/Documents/Claude/DSLinuxDSi-third-party/`.

```
docker build -t dslinux-wheezy scripts/          # Debian Wheezy i386 with the build dependencies
git clone --depth 1 https://github.com/ipwndev/DSLinux work/dslinux   # then apply patches/ in order (git am)
scripts/prepare-tree.sh                           # recreates empty directories the git mirror drops, fixes autotools timestamps
scripts/build-dsi.sh                              # Nintendo/DSI product (selects it, builds, packs ROMs)
APPFLAGS=1 TAG=s scripts/make-dsimode.sh          # re-pack with a DSi header (needs BlocksDS's ndstool)
```

`docs/` has the whole story: `FEASIBILITY.md` (what was known at the start), `STAGE1.md`, `STAGE2.md`, `STAGE3.md` (every step, including the wrong turns and retractions).

## Licences and sources

- DSLinux: GPL-2.0 (ipwndev mirror of svn.dslinux.org). Kernel 2.6.14 (GPL-2.0). Patches here are GPL-2.0.
- `arch/arm/mach-nds/arm7/sdmmc.c`: derived from profi200's `dsi_sdmmc` (MIT, copyright kept in the file).
- `arch/arm/mach-nds/arm7/dsitouch.c`: derived from BlocksDS libnds (zlib, notice kept in the file).
- A third party's unofficial DSi proof of concept (github.com/keiichicom/dslinux) was used only as a comparison binary in the emulator; none of its code is used.
- Console dumps, NAND and firmware were never read, copied, uploaded or committed by this work.
