# DSLinux on the Nintendo DSi XL: Stage 0 feasibility finding

Written 2026-11-10. "Verified" means I checked it myself this session (HTTP, GitHub API, hashing,
parsing the binary). "Claimed" means a third party says so and I have not reproduced it.
Nothing has been built or booted yet.

## Short answer

DSLinux booting on a DSi XL is **plausible and has probably been done once already**, which changes
the picture from the earlier answer ("unclear DSi support"). Using the full DSi hardware is
**mixed**: 16 MB RAM is mostly a configuration job, the DSi SD slot is a real driver project
that is feasible but unproven, a faster ARM9 clock is small, and Wi-Fi, cameras and DSP are not
realistic here.

## 1. Sources

| Source | What it is | Status |
|---|---|---|
| [ipwndev/DSLinux](https://github.com/ipwndev/DSLinux) | Git mirror of the official SVN. 1816 commits, about 300 MB, GPL-2.0, last push 2024-05-24. Contains `linux-2.6.x`, `uClibc`, `user`, `vendors`, `toolchain`. | Verified (GitHub API, README) |
| svn.dslinux.org/svn/trunk | Original SVN, still online. Last-modified header 2012-09-18. Builds page says r2449, 2012-02-27. | Verified (HTTP 200) |
| dslinux.org toolchain `dslinux-toolchain-2008-01-24-i686.tbz` | Prebuilt i686 cross toolchain, 25 MB. The kernel string reports gcc 4.0.4. | Verified (HTTP 200, size) |
| [keiichicom/dslinux](https://github.com/keiichicom/dslinux) | One person's fork. GPLv3 LICENSE file (the kernel itself is GPLv2). Release `Linux` (2025-12-29) holds `dsilinux.nds`. Release `dslinux` (2026-02-04) is a clean DS/DS Lite build. Source is in Git LFS tarballs. | Verified (API) |
| [profi200/dsi_sdmmc](https://github.com/profi200/dsi_sdmmc) | MIT-licensed DSi SD/MMC code, last push 2023-12-31. Written for devkitPro. | Verified (API) |

### The DSi build that exists

Announced on [GBAtemp, 2025-11-26](https://gbatemp.net/threads/dslinux-on-nintendo-dsi-dsi-xl-pre-release-published.677494/)
by keiichicom as a proof of concept. **Claimed:** it runs on a DSi XL launched through TWiLight Menu++, uses
the DSi's 16 MB of RAM (set by changing the RAM address and size in the kernel's System Type
options), has DLDI disabled, and ships one program (Colossal Cave, `advent4`) inside the romfs
because Linux has no way to read the DSi SD card. By 2025-12-20 the author "gave up" on the DSi SD driver and returned to
plain DS/DS Lite work. Wi-Fi was never done for the DSi.

I downloaded `dsilinux.nds` (2,365,504 bytes) into
`~/Documents/Claude/DSLinuxDSi-third-party/keiichicom-dsilinux-release/`. Its SHA-256
(`ecd8e12d...ace23`) matches GitHub's. **Verified by parsing the file:**

- It is an ordinary DS-format ROM: unit code 0, no DSi extended header.
- ARM9 image 2.3 MB, loaded and entered at 0x02000000. ARM7 image at 0x03840000.
- Embedded version string: `Linux version 2.6.14-hsc0ds (gcc 4.0.4) #5 Wed Nov 26 00:33:20 EST 2025`.

So the DSi "port" is not a DSi-native binary. It is a DS-mode ROM that relies on TWiLight
Menu++ to hand it the DSi's 16 MB. That matters for everything below.
It is an unaudited binary from an individual, so I have not run it and would only run it in the
emulator, never copy it to the real console.

### How the earlier conflicting sources fit together

- The blog saying "no DSi support" and the 2019
  [mailing-list thread](https://mailman.dslinux.in-berlin.de/pipermail/dslinux-devel-dslinux.in-berlin.de/2019-September/001229.html)
  ("possible in principle, never shipped", DSLinux only showing a splash and scrolling errors) predate the 2025 proof of concept.
- The 2019 thread also states the key blocker: extra RAM is not reachable by a `.nds` run in DS mode.
  Consistent with the DSi memory facts below.

## 2. Toolchain and build host

- Official build: GNU make, gcc, binutils, bison, ncurses, zlib, gettext, gawk, then
  `make menuconfig` (DLDI or NDS build type) and `make`; output lands in `images/`.
- The wiki says the AMD64 tools segfault and the toolchain will not build with gcc 4.3 or newer, so use the **prebuilt i686 toolchain**.
  The one working DSi build was made in a Debian Wheezy 7.11 i386 VM.
- Host facts, verified here: Docker 29.9.2 works for this user (no sudo), the kernel has
  `CONFIG_IA32_EMULATION=y`, and `i386/debian:wheezy` exists on Docker Hub (one 40.5 MB layer).
- Plan: build inside an `i386/debian:wheezy` container with the 2008 toolchain mounted in. No
  sudo and nothing installed on the host.
- Risk: Wheezy is long out of support, so `apt` needs archive.debian.org. That is a known
  workaround, but I have not tried it yet.

## 3. How it launches

DSLinux is a `.nds` plus a root filesystem. The DLDI build reads a `linux/` directory from a
FAT card through a DLDI driver patched into the `.nds`. The original builds require RAM in
GBA slot 2, because a DS has only 4 MB. Upstream says its builds work on real hardware and
that "emulators aren't supported". That is a Stage 1 risk for melonDS, since DS mode there
may need an emulated slot-2 RAM pack, and I do not yet know whether melonDS 1.1 provides one.

## 4. DSi facts checked against the BlocksDS docs

(`/opt/wonderful/thirdparty/blocksds/core/docs/content/docs/internal/memory_map.md`)

- The ARM946E-S has an MPU, not an MMU. Only no-MMU uClinux can run, which DSLinux is.
- A DS has 4 MB of main RAM at 0x02000000; DSi mode has 16 MB. The GBA slot is filled with 0xFF
  on a DSi, so slot-2 RAM cannot exist there. 16 MB must therefore come from main RAM and
  needs the console to be in DSi mode (SCFG_EXT). I have not yet confirmed from the docs whether
  TWiLight does this for a unit-code-0 ROM, which is what the proof of concept relies on.
- DSi SD uses the TMIO/SDMMC controller, not the DS cartridge or DLDI path. libnds in BlocksDS carries
  headers for both sides (`nds/arm7/sdmmc.h`, `nds/arm9/sdmmc.h`, `nds/arm7/tmio.h`).
  It also has an Atheros Wi-Fi example (`examples/atheros/basic_test`), the DSi's Wi-Fi chip.

## 5. Feasibility per stage

| Stage | Assessment | Main risk |
|---|---|---|
| 1. Unmodified build, melonDS DS mode | Likely feasible once the Wheezy container and toolchain work. | melonDS may not emulate slot-2 RAM, so DS mode might boot with 4 MB or not at all. Fallback is to test the 16 MB layout in DSi mode. |
| 2. DSi mode in melonDS, and real DSi XL via TWiLight | Plausible: a proof of concept reportedly works. We would reproduce it from source (kernel RAM base/size, plus checking the ARM7/ARM9 shared-memory layout fits 16 MB). | The proof of concept is unverified by me. The user's TWiLight setup cannot be reproduced inside melonDS without reading their dumps, which I will not do. Real-hardware results are only the user's to confirm. |
| 3a. Use all 16 MB RAM | Mostly configuration; the proof of concept did it. | Memory map conflicts, cache/MPU regions. |
| 3b. DSi SD card | Feasible but a real driver project. Cheapest first test: does TWiLight patch DLDI to the DSi SD, in which case the stock DLDI build might already read the card? Otherwise port `dsi_sdmmc` (MIT) or the libnds TMIO code behind DSLinux's existing block interface. | Written against a 2.6.14 kernel with an old toolchain. A buggy raw-sector driver could damage the FAT card, so first versions should be read-only and tried on a spare or backed-up SD. melonDS emulates the DSi SD, so this part can be emulator-tested. |
| 3c. Faster clocks | Small. ARM9 doubling (about 67 to 134 MHz) is a register write once SCFG_EXT is unlocked, as I understand it; I do not believe the ARM7 has an equivalent switch, so "faster ARM7" is probably not available. To be verified in GBATEK. | melonDS may not model the speed change, so the effect would be hardware-only. |
| 3d. Wi-Fi, cameras, DSP | **Not realistic.** DSi Wi-Fi is an Atheros SDIO chip needing its own firmware-loading stack under a 2.6.14 kernel. Cameras and DSP would each be a large driver effort with no way to test beyond the real console. | Out of scope unless the earlier items go very well. |

## 6. Downloads I need your OK for (nothing below is downloaded yet)

| Item | Size | Needed for |
|---|---|---|
| ipwndev/DSLinux shallow clone (`--depth 1`) | about 100 to 150 MB (full history is 300 MB) | clean unmodified base |
| 2008 prebuilt i686 toolchain | 25 MB | compiling |
| `i386/debian:wheezy` Docker image | 40 MB | build host |
| keiichicom source tarball (Git LFS, for diffing their RAM settings) | about 60 to 130 MB | reading the proof-of-concept changes only |
| profi200/dsi_sdmmc | small | Stage 3b |

None needs sudo.

## 7. Proposed layout

- `~/Documents/Claude/DSLinuxDSi` (this repo): docs, build scripts, and `patches/` with our changes
  as `git format-patch` output.
- `work/dslinux` (git-ignored): shallow upstream clone with a local `dsi` branch; all edits happen there.
- `~/Documents/Claude/DSLinuxDSi-third-party/`: toolchain, keiichicom files, the dsi_sdmmc checkout
  and anything else downloaded, kept apart from the tree being edited.
- Branches follow your rules: work on `development`, nothing to `beta` or `main` until you say so.
