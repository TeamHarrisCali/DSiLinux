# Stage 3: DSi hardware features

Date: 2026-11-10. Status per item. **Nothing in 3b is verified yet: it compiles, and the emulator test was not completed.**

## First real-hardware result (user's photo, DSi XL, via TWiLight Menu++)

A Stage 2 build (almost certainly the 16 MB one) **booted the DSLinux kernel on the real console** and printed its boot log up to
`Real Time Clock Driver v1.12` / `io scheduler noop registered`, then panicked:
`Data abort: pc=0x020bfd28 ... Process swapper (pid: 1) ... Kernel panic - not syncing: Attempted to kill init!`.

What this shows:
- **16 MB on real hardware:** the init task's stack was at `0x02FEBFB4`, near the top of the 16 MB bank. A 4 MB build cannot place
  anything above `0x023FFFFF`. So TWiLight gave the ROM the full 16 MB and the kernel used it. (I have not been told which file was run; confirm.)
- **TWiLight patches DLDI:** the faulting address is inside the 32 KB DLDI driver area of the image (`0x020BF300-0x020C7300`).
  That is the block-device startup calling a *real* driver that TWiLight patched in; the stock stub would just return 0.
  That driver then faulted (a data abort, so an MPU permission fault, on an address the photo reads as `0x04004054`).
  I did not reverse-engineer the patched driver; it is outside our tree.
- **Consequence:** every earlier test build that has DLDI enabled panics on real hardware at that point, including the 4 MB control.
  The melonDS runs never showed this, because melonDS's DLDI is an emulated image.

## 3a. All 16 MB of RAM
Done in Stage 2 and now seen on hardware (above) and in melonDS (`MemTotal: 14072 kB`).
Left alone on purpose: the top 64 KB (DTCM + DSi system area).

## 3b. DSi internal SD card (this commit)
Avoids the DLDI driver entirely:
- **ARM7** (`arch/arm/mach-nds/arm7/sdmmc.c`): polling SD-card driver for the TMIO controller, derived from profi200's MIT-licensed
  `dsi_sdmmc`, reduced to SD init and sector read/write. Port 0 (the SD slot) only. The NAND is on another port and is never selected.
- **ARM9** (`drivers/block/dldi_c.c`, `CONFIG_NDS_DSISD`): the existing `/dev/dldi` block device gets a backend that sends a request block
  (`include/asm-arm/arch-nds/dsisd.h`) to the ARM7 over the FIFO and waits for the answer. Userland sees the same device as before.
- **Read-only by default.** Writes are compiled out unless `CONFIG_NDS_DSISD_WRITE`; they return an error. This build writes nothing to the card.
- The `Nintendo/DSI` product now sets `CONFIG_NDS_DSISD=y`. The ARM7 interrupt stack grew from 256 B to 1 KB because the SD code runs from the FIFO interrupt.

### Status
| Claim | Status |
|---|---|
| Builds clean (`make` exit 0, no warnings from the new files); ARM7 image grew from 0x4958 to 0x5344 bytes; 32 KB of IWRAM budget remains | **Verified** (compile) |
| Boots in melonDS DSi mode with the emulated DSi SD | **Not verified.** One run was started but I saw no usable output: my screenshot method was capturing the wrong window and your private desktop (see below), and a later attempt to use melonDS's GDB stub to read the kernel log was cut off when a safety check blocked a third DSi-mode launch |
| Real hardware | **Not tested** |

### First real-hardware run of the SD build (user's photo)
Both SD builds boot on the console (no panic: the DLDI driver is no longer called). `dmesg | grep dsisd` printed
`dsisd: init result 3, SCFG_EXT 00000000, TMIO rev 0009, info 00000002, sectors 0`:
- The ARM7 **can** talk to the controller (revision register reads 9) and a card was detected.
- Init failed at step 2 (CMD8) with an error that is not a plain timeout.
- **SCFG_EXT reads 0 on the ARM7**, which looks like DS compatibility mode (SCFG locked). So the DSi SD interface may be switched off for
  the ARM7, or its clock is. That is a hypothesis, not a finding.
- The missing `linux/` folder is unrelated: the mount error is the consequence of this failed init.
- **Correction to Stage 2/3 text above:** I said the init stack at `0x02FEBFB4` proves 16 MB of real RAM. It only proves the kernel *believes* it has 16 MB.
  If the console really runs in DS mode, RAM is 4 MB mirrored and a 16 MB kernel would alias memory. The v2 build probes this (below).

### v2 build (`out/dsi-sd/dslinux-dsi-sd2*.nds`): more diagnostics, same read-only behaviour
- Kernel line `NDS: main RAM above 4 MB is real (16 MB)` or `MIRRORED (only 4 MB real!)`: writes two different values 12 MB apart and checks for aliasing.
- Second line `dsisd: diag ext .. clk .. rom .. rev .. st@fail .. st .. resp .. cmd/n ..`: SCFG_EXT7, SCFG_CLK7, SCFG_ROM, TMIO revision,
  TMIO status at the failing command, status now, last response, failing command index and number of commands sent.
- A CMD8 failure that carries the timeout bit plus other bits is now treated as a v1 card instead of an error (upstream compares exactly).
- The ARM7 turns the SD interface on (SCFG_EXT bit 18) only if SCFG_EXT is writable; if SCFG is locked nothing is written.
- Read on the console: `dmesg | grep -E 'NDS:|dsisd'`.

### The kernel prints one diagnostic line at init
`dsisd: init result R, SCFG_EXT xxxxxxxx, TMIO rev xxxx, info xxxxxxxx, sectors N`
- `R=0`: card found and initialised; `sectors` is its size in 512-byte sectors; `info` 1 = SDSC, 2 = SDHC.
- `R=2`: controller unreachable or no card. `SCFG_EXT` and `info` (the raw TMIO status) say why.
- `R=3`: card init failed; `info` is the failing step (1 CMD0, 2 CMD8, 3 CMD8 echo, 4 ACMD41, 5 ACMD41 timeout, 6 CMD2, 7 CMD3, 8 CMD9, 9 CMD7, 10 ACMD42, 11 ACMD6, 12 voltage).
- Read it on the console with `dmesg | grep dsisd` at the prompt.

## 3c. Faster ARM9 clock, 3d. Wi-Fi/cameras/DSP
Not started. 3c is small but needs the SD result first; 3d unchanged from the feasibility finding.

## Process note
My desktop screenshots (used to read the emulator's console) captured unrelated windows of your desktop, including chat messages.
I deleted every saved full-screen frame and crop under `out/`, and I will not take desktop screenshots again. The kernel log is read
from emulator RAM through melonDS's GDB stub instead (`scripts/klog.py`, `scripts/melon-klog.sh`); that works only once a DSi-mode run can be started.
