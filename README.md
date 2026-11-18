# DSLinuxDSi

**Next steps, plans and open questions:** [docs/ROADMAP.md](docs/ROADMAP.md).

DSLinux (uClinux 2.6.14 for the Nintendo DS) made to run on a **Nintendo DSi XL in DSi mode**: 16 MB of RAM, the internal SD slot,
the DSi touchscreen, hardware 3D, sound, microphone, cameras and Wi-Fi, with a Windows 95 style desktop and a set of apps and games.
It starts from TWiLight Menu++ (through Unlaunch). **Nothing is ever written to the DSi NAND**, and the system cannot touch the SD card
outside two files in `sd:/linux/` (enforced by the ARM7, see below).

This repository holds the patches, build scripts and notes. The source tree is a separate clone of
[ipwndev/DSLinux](https://github.com/ipwndev/DSLinux) in `work/dslinux` (git-ignored); the changes are in `patches/` (131 patches, in order).

- **Using it:** [docs/USER-GUIDE.md](docs/USER-GUIDE.md): buttons, the desktop, every app, Wi-Fi and SSH, the card scripts, what to do after a freeze.
- **How the DSi itself works** (boot chain, NAND, installed titles, firmware chip, BIOS, which driver talks to what): [docs/DSI-INTERNALS.md](docs/DSI-INTERNALS.md).
- **Developing for it:** [docs/DSI-NOTES.md](docs/DSI-NOTES.md): everything learned about the DSi hardware and this system (registers, limits, pitfalls, numbers).
- **How it was done:** [docs/STAGE3.md](docs/STAGE3.md) (every build, including wrong turns), [docs/FEASIBILITY.md](docs/FEASIBILITY.md), [docs/STAGE1.md](docs/STAGE1.md), [docs/STAGE2.md](docs/STAGE2.md).

## Status

"Console" = run on the real DSi XL (photos, user reports, the log file read back on a PC). "Not yet run" = builds, nothing has run it yet.

| Area | Status | Notes |
|---|---|---|
| DSi-mode boot, 16 MB RAM, touchscreen, SD card, ARM9 at 134 MHz | console | Boot self-test prints `RAM`, `SD`, `CLK`, `CONF`, `ROOT` lines |
| Writable ext2 root `sd:/linux/ROOTFS.IMG`, log file `sd:/linux/DSILOG.TXT` | console | The SD buffer race that corrupted the image (log text in inode tables) is fixed in w97m; check the image with `scripts/rootfs-check.sh` after any freeze |
| Desktop: taskbar, cascading Start menu, window buttons, tray (battery, volume, clock), hardware pointer, page flipping | console | w97p adds menu icons, a menu drawn off-screen (no half drawn menus) and a Wi-Fi tray indicator; w97s: tray pictures with tooltips, tap Wi-Fi to open the Wi-Fi window (test bed only) |
| Hardware 3D (`dsgx.h`), textures, 3D in desktop windows at 60 fps | console | |
| Sound out, volume popup | console | 100% is still quiet (test tone level) |
| Microphone, voice memos | console | Works; a whine and small clicks remain (parked) |
| Cameras (about 8.6 fps, the sensor's rate), photo viewer | console | |
| Settings (brightness, pointer, wallpaper, clock), battery tray | console | |
| Games: 3D Dodge, 3D Breakout, Tron, 3D Maze, 2048, Sokoban, Sudoku, Life, Paint | console | |
| Game Boy emulator (Peanut-GB) | console: runs, about 22 of 60 frames per second (w97f) | w97g sound and frame clock, w97p tile-row renderer (drawing 4x faster on a PC, identical frames): **not yet run** |
| DOOM (doomgeneric, shareware WAD) | console: runs, "a little sluggish" | Lives in `ROOTFS.IMG` (`/home/doom`), not in the ROM |
| Wi-Fi (the DS chip: open or WEP networks, 802.11b) | **console: scan, join, DHCP and `ping google.com` work (w97y, phone hotspot)** | WEP and SSH not yet tried; w97z: Ctrl+C on the touch keyboard |
| Power off | console | |
| The DSi's Atheros Wi-Fi (WPA2) | **console: firmware upload, scan (WPA2 networks listed), `wlan0` joins an open network, DHCP, ping 8.8.8.8 / google.com (w98q)** | WPA2-PSK login built, not yet tried on the console (w98t, step 6 of docs/ATHEROS-PLAN.md) |

## The SD card rule: nothing outside `/linux`

The card is never mounted as a writable FAT filesystem. At boot the ARM7 reads the FAT itself, finds the sector ranges of `sd:/linux/ROOTFS.IMG`
(the 512 MiB ext2 root: `/etc`, `/usr`, `/home`, everything persistent) and `sd:/linux/DSILOG.TXT` (the 1 MiB log), and from then on **refuses every
read and write outside those two files**, including raw access by root. The files never grow, so no FAT or directory entry is ever changed; a driver
bug can at worst damage the image or the log. ext2 has no journal and the image is never unmounted cleanly (power-off, freezes): see
"After a freeze" in the user guide.

## Installing

1. Copy the ROM `out/dsi-mode/dslinux-dsimode-<tag>-uc3.nds` anywhere on the card (the build script puts it in the card root).
2. Put `sd:/linux/ROOTFS.IMG` (built by `scripts/make-rootimg.sh`, copied as ONE file) and `sd:/linux/DSILOG.TXT` (1 MiB) on the card; the card's write-protect slider must be open.
3. Start the ROM from TWiLight Menu++ (DSi mode). The self-test runs, then the desktop starts.

## Building

Needs Docker, git, the prebuilt 2008 DSLinux toolchain and BlocksDS's `ndstool` (for the DSi header); downloads live in `~/Documents/Claude/DSLinuxDSi-third-party/`.

```
docker build -t dslinux-wheezy scripts/                                  # Debian Wheezy i386 with the build dependencies
git clone --depth 1 https://github.com/ipwndev/DSLinux work/dslinux     # then apply patches/ in order (git am)
scripts/prepare-tree.sh                                                  # empty directories the mirror drops, autotools timestamps
scripts/build-dsi.sh                                                     # first full build of the Nintendo/DSI product
scripts/release.sh w97p -t user/microwin/src/demos/nanox/dsdesk.c       # every build after that, see below
```

`scripts/release.sh TAG [-t file ...] [-o what-the-previous-build-was] [-n]` does the whole routine: `make` in the container (log in
`out/logs/TAG-build.log`), DSi-mode packaging, the 4 MiB ROM limit check (prints what is left), archiving the previous ROM into
`out/dsi-mode/old/`, and, if the card is in the PC, an image check, the copy, a checksum comparison and removal of older DSLinux ROMs from
the card root. The card's mount point is set in `scripts/card.sh` (`CARD=...` overrides it).

| Script | What it does |
|---|---|
| `scripts/release.sh` | build, package, size check, archive, copy to the card |
| `scripts/rootfs-check.sh [-y]` | `e2fsck` of the card's `ROOTFS.IMG` (read-only; `-y` repairs). The scripts below refuse a damaged image |
| `scripts/add-roms.sh game.gb ...` | your own Game Boy ROMs into `/home/roms` |
| `scripts/set-wifi.sh ESSID [wepkey]` | Wi-Fi settings and the SSH server into the image (also possible on the console: Start > Network) |
| `doom/build.sh`, `doom/install.sh [doom1.wad]` | build DOOM and put it into `/home/doom` |
| `scripts/make-testrom.py out.gb` | a small Game Boy test ROM of our own (stripes, d-pad scrolls) |
| `scripts/in-container.sh 'cmd'` | run anything in the build container (`/work` = the tree, `/out` = `out/`) |

**PC test bed for the desktop** (`testbed/`): `testbed/build.sh` compiles the same Nano-X server (Microwindows from the tree, with our
patches) and the desktop programs for the PC, drawing into a 256x192 framebuffer file (`fbshim.so` answers the framebuffer ioctls like the DS
top screen); nothing shows on the PC's screen. `testbed/run.sh` starts server, window manager and desktop; `out/testbed/bin/nxctl` clicks, moves,
types and saves pictures (`nxctl click 20 184 wait 500 move 40 80 shot menu.ppm`). It reproduced the w97p menu bug exactly and showed the fix
before the build went to the console. It does not emulate the DS hardware (3D engine, sound, Wi-Fi, buttons): UI logic and drawing only.

On a PC, `dsgb_host.c` (Game Boy core: ms per frame, a frame as PPM, `GB_WAV=x.wav` for the sound, `auto` presses buttons) and `arc_test.c`
(game rules) in `work/dslinux/user/microwin/src/demos/nanox/` test code without the console. The Game Boy harness writes the ROM's `.sav`
next to it: delete it between runs you want to compare.

## Licences and sources

- DSLinux and the Linux 2.6.14 kernel: GPL-2.0; the patches here are GPL-2.0.
- `arm7/sdmmc.c`: derived from profi200's `dsi_sdmmc` (MIT). `arm7/dsitouch.c` and the DSi microphone/camera sequences: from BlocksDS libnds (zlib).
- Game Boy core `peanut_gb.h`: Peanut-GB by Mahyar Koshkouei (MIT), with marked DSLinuxDSi changes. DOOM: doomgeneric (GPL-2.0) with the shareware `doom1.wad` (freely distributable).
- The Wi-Fi bring-up on the DSi follows what BlocksDS dswifi and libnds document (MIT/zlib); the driver itself is DSLinux's original DS Wi-Fi code.
- Console dumps, NAND and firmware were never read, copied, uploaded or committed by this work.
