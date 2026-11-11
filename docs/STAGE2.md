# Stage 2: 16 MB DSi-mode build

Date: 2026-11-10. **Compiled, and checked in DS mode as a negative control by me. The user ran it in melonDS DSi mode and reports it boots to the init prompt (screenshot). Not tested on a real console.**

## What changed (patch `patches/0001-*.patch`, from upstream `74f4eda53`)

- `CONFIG_NDS_DSI` (Kconfig, "Nintendo DS Options"): for a DSi in DSi mode.
- `arch/arm/mach-nds/head.S`: the ARM9 MPU main-RAM region was hardcoded as `PAGE_4M`; with `NDS_DSI` it is `PAGE_16M`.
  The DTCM base `0x027C0000` lies *inside* RAM at 16 MB (ARM7 and DMA cannot reach DTCM, so handing those pages out would be a latent bug),
  so with `NDS_DSI` DTCM moves to `0x02FF0000`.
- New product `vendors/Nintendo/DSI`: the DLDI build with `CONFIG_NDS_DSI=y` and `CONFIG_DRAM_SIZE=0x00FF0000`
  (RAM `0x02000000-0x02FF0000`; the top 64 KB is left alone because the DSi's system structures live there, and DTCM now sits in it).
- Select it with `scripts/build-dsi.sh` (answers the `make config` prompts: `DSI`, then "Default all settings").

## Results

| Claim | Status |
|---|---|
| `make` for the DSI product exits 0; kernel has `CONFIG_NDS_DSI`, `DRAM_SIZE=0x00FF0000` | **Verified** (compile) |
| The binary differs from the Stage 1 build only in a few dozen bytes (the constants above) | **Verified** (`cmp`) |
| The 16 MB build does not run with 4 MB RAM | **Verified** in melonDS DS mode: the console floods with kernel fault messages ([shot](shots/stage2-16mb-build-in-ds-mode-faults.png)). This shows the build really depends on 16 MB; it is not a DSi result |
| It boots in melonDS **DSi mode** with 16 MB | **Boot verified by the user** (their screenshot, [docs/shots/stage2-dsi-mode-user-run.png](shots/stage2-dsi-mode-user-run.png)): `dslinux-dsi.nds` reaches the init prompt in melonDS DSi mode. DLDI was off, so the card mount fails as expected. The TCP hash tables are 1024 entries (the 4 MB build had 256), which means the kernel sees more RAM, and the user then read `MemTotal: 14072 kB` with `grep MemTotal /proc/meminfo` ([shot](shots/stage2-meminfo-user-run.png)). That matches the configuration: 0x00FF0000 = 16320 kB of RAM minus about 2.2 MB for the kernel image and built-in filesystem. Original expectation was the init prompt like Stage 1, and, if DLDI is on, no "Extra RAM NOT detected!" banner plus tty2/tty3 starting (the init scripts test `MemTotal > 4000 KB`) |
| It boots on a real DSi XL via TWiLight Menu++ | **Not tested** |
| Third-party proof of concept boots in melonDS DSi mode | **Verified** (screenshot, DLDI off): same kernel family, TCP hash table sized for more RAM (1024 entries vs 256). So melonDS DSi mode with direct boot hands a unit-code-0 ROM the extra RAM |

## Open questions for real hardware (none of these is verified)

1. Does TWiLight Menu++ give a unit-code-0 homebrew `.nds` 16 MB (a "Run in DSi mode" style per-game setting)? I believe it can but could not check.
2. Which ARM7 header address does it accept: `0x03800000` or `0x03840000` (the proof of concept's)? Both builds are provided; the kernel is the same.
3. Stock DLDI is flashcart-only. If TWiLight does not patch DLDI to the DSi SD, DSLinux boots with the romfs only (init prompt, no `/etc`, no userland from the card). That is the Stage 3 SD driver's job.

## melonDS DSi runs: the NAND image

melonDS opens `nand.bin` read-write on every DSi-mode start and its modification time changed at each of my two DSi-mode starts (size unchanged). I tried a flatpak `:ro` bind of the folder and melonDS still opened it read-write, so I did not rely on it. After you asked for it,
I stopped running DSi mode and left the test to you.

## How to run the DSi-mode test yourself

Files: `~/Documents/Claude/DSLinuxDSi/out/dsi-card/` (see its `README.txt`). In melonDS with your normal DSi setup, open `dslinux-dsi.nds`.
For the userland, enable Config > Emu settings > DLDI, choose "Folder" or "Image": use the FAT image
`out/dldi-img-dsi/dldi.img` (folder mode does not work with this build, see STAGE1). Use the on-screen keyboard (click) to type `cat /proc/meminfo`.

## Real hardware (added after the user's photo)
See [STAGE3.md](STAGE3.md): a Stage 2 build booted the kernel on a real DSi XL with the 16 MB RAM in use, then panicked in the DLDI driver that TWiLight patched in.

## Correction (later)
The 16 MB claims above are withdrawn: the ROM header was a DS header, so loaders gave 4 MB mirrored RAM. See the "Why 16 MB was never real" section in STAGE3.md.
