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

## Why "16 MB" was never real: the ROM header (found from the user's v2 screenshot)
The v2 screenshot (taken to be melonDS; the numbers differ from the console's) read:
`dsisd: init result 2, SCFG_EXT 93ff3b06, TMIO rev 0000 ...` / `NDS: main RAM above 4 MB is MIRRORED (only 4 MB real!)`.
- `93ff3b06` is the DSi-unlocked SCFG value *with the RAM-limit bits (15:14) at 0 = 4 MB*. The emulator gave my ROM DS-mode memory.
- Cause: the ROMs are built with the 2008 `ndstool`, which writes a plain **DS header (unit code 0)**. Loaders (melonDS, TWiLight Menu++) start such a
  ROM in DS mode: 4 MB of RAM, mirrored. Everything I said about "16 MB working" (Stage 2 `MemTotal: 14072 kB`, the init stack address, the photo) only shows the
  kernel *believed* 16 MB. That statement is retracted for Stage 2 as well; the Stage 2 doc is corrected below.
- The real console earlier reported `SCFG_EXT 00000000` for the ARM7, consistent with DS mode as well (SCFG locked, SD interface off).
- Fix attempt (this commit): re-pack the same kernel with BlocksDS's `ndstool` so the header says **unit code 3 (DSi only)** or 2 (DS or DSi),
  with a DSi title ID and a dummy ARM9i segment. `-uc` alone does nothing with raw binaries or plain ELFs; ndstool writes the DSi header only when the ARM9 ELF
  carries a DSi segment, so `scripts/dsi-elf.sh` wraps the binaries in ELFs with a 4-byte segment at 0x02400000 (`scripts/make-dsimode.sh`).
  Verified: `ndstool -i` shows `Unit code 0x03`, `TWL flags 0x01`, `DSi9 RAM address 0x2400000`. Not yet verified: that melonDS/TWiLight then give 16 MB.

## Boot self-test (no typing)
`/boot/selftest` runs at the end of boot (`rc`) and prints, for example:
```
======== DSLinuxDSi self-test ========
MemTotal:  14072 kB
RAM : PASS - 16 MB real          (or: FAIL - only 4 MB real (DS mode))
SD  : FAIL - see below           (or: PASS - card found)
dsisd: init result ...           (+ the diag line)
======================================
```
It sits just above the prompt, so a single photo of the top screen is enough.

## First DSi-mode boot (user report): hang after the "NDS Wireless <bthaeler@aol.com>" banner
The DSi-header ROM got further than any build before, which suggests the loader honoured the header. The boot then stopped right after the DS Wi-Fi driver's banner.
Cause (from the source, not yet confirmed on the console): the DS Wi-Fi chip does not exist in DSi mode (the DSi has a different Wi-Fi chip). The ARM7's `wifi_init()` spins
in `while (WIFI_BBSIOBUSY & 1);` loops on the absent hardware, so the ARM7 never answers; the ARM9 driver sends a MAC query and waits with no timeout
(`wait_event_interruptible`, drivers/net/wireless/nds.c).
Fix: the DSI product builds without `CONFIG_NDS_WIFI`, and the ARM7 skips Wi-Fi init and Wi-Fi interrupt handling in that case. DS builds are unchanged.
Files: `out/dsi-mode/dslinux-dsimode-b-uc3.nds` and `-b-uc2.nds` (the "b" build). Verified: it builds, the Wi-Fi banner string is gone from the image. Not verified on the console.
Wi-Fi in DSi mode would need a driver for the Atheros chip (out of scope).

## DSi-mode ROM boots; touchscreen dead on the uc3 build (user report)
The "b" uc3 ROM booted on the console (the self-test result is still to be reported). The touchscreen did not work.
Likely cause (not yet confirmed): DSi header byte 0x1BF ("app flags") had bit 0 set (ndstool's default). BlocksDS's own `cdcIsAvailable()` is
`isDSiMode() && (appflags & 1)`: with that bit set the touch/sound chip runs in its DSi register mode, and DSLinux's ARM7 only speaks the DS-style SPI touch
protocol, which gets no answer. Clearing the bit should keep the chip in DS-compatible mode.
- "c" ROMs (`out/dsi-mode/dslinux-dsimode-c-uc3.nds`, `-c-uc2.nds`): same kernel as "b", header byte 0x1BF = 0 (`APPFLAGS=0 TAG=c scripts/make-dsimode.sh`). Header bytes verified, behaviour not.
- If the loader ignores the flag, the fallback is a DSi-mode touch reader in the ARM7 (TSC2117 "codec" registers, see BlocksDS `nds/arm7/codec.h`); not started.
- Side effect to expect: sound uses the same chip, so DSi-mode sound is untested either way.

## Touchscreen in DSi mode (user: DSi mode still no touch with the flag cleared; DS mode works)
So the loader leaves the touch/sound chip in its DSi register mode whatever header flag we set, and DSLinux's DS-style SPI touch commands get no answer.
Fix (this commit): `arch/arm/mach-nds/arm7/dsitouch.c`, a port of the BlocksDS libnds codec touch code (zlib licence, credited in the file):
when the ARM7 is in DSi mode (`SCFG_EXT` bit 31 readable) it sets up the codec touch scanner at start-up, asks the codec whether the pen is down, and reads five X/Y samples
through the codec's data buffer, filtered (sort, average the middle three, reject noisy samples). DS mode still uses the old path (unchanged). In DSi mode the old start-up
"dummy read" is skipped, because it would send DS touch bytes to a codec in register mode.
- ROMs: `out/dsi-mode/dslinux-dsimode-d-uc3.nds` (and `-d-uc2`): header app-flags bit 0 = 1, which is what BlocksDS pairs with codec touch.
  `-dz-uc3.nds`/`-dz-uc2.nds`: same kernel, flag 0, in case the loader behaves differently.
- Status: builds clean; **not run anywhere**. In melonDS the codec is probably not emulated at all, so the console is the only real test.
- Risks: the pen-down test and the register sequence are copied from libnds, not verified on this console. Calibration is the existing one. Sound uses the same chip and is untested.

## DSi touch still dead (user: d ROM, DSi mode): diagnostics build "e"
No data on why. Possible causes: my `SCFG_EXT` bit-31 gate kept the reader off; the codec register sequence is wrong for this console; the pen/data reads fail.
"e" ROMs (`out/dsi-mode/dslinux-dsimode-e-uc3.nds`, `-e-uc2.nds`):
- No SCFG gate: the ARM7 selects codec page 3 and reads the page register back; 3 means the chip is in register mode and the codec reader is enabled.
- Counters in the ARM7 (pen polls, pen-down count, valid/invalid/noisy reads, last raw X/Y, key register values) fetched by the ARM9 with a new request command and printed as
  `dsitouch: a/p/st/pn <active|probe|status|penreg> scfg <SCFG_EXT> adc <adc1|adc2|first raw bytes> calls <n> pen <n> rd <ok|bad> noisy <n> xy <x|y>` every 2 s **while the counters change**.
- Reading it: `a/p/st/pn` low byte = active (1 = codec reader on); next byte = probe readback (03 expected). `calls` rising = the ARM7 loop runs. `pen` rising on touch = pen detect works.
  `rd` low half = valid reads, high half = invalid (garbage) reads; `xy` = last raw position.
Builds clean; not run anywhere.

## First readings from the "e" diagnostics build (user's photo, DSi mode, uc3)
`dsitouch: a/p/st/pn ad400301 scfg 93fffb06 adc 040d8b18 calls 738 pen 25 rd 00020017 noisy 0 xy 095a0403`:
- `scfg 93fffb06`: the ARM7 is in real DSi mode (SCFG unlocked, RAM-limit bits at "extended"). The DSi-header ROM works as intended. (RAM is still to be confirmed by the self-test.)
- Low byte `01`, probe `03`: the codec reader is on and the chip answered the page-register readback. `calls 738`: the ARM7 loop runs. `pen 25`: pen-down was detected 25 times.
  `rd 00020017`: 23 valid reads, 2 invalid. `xy 095a0403`: last raw X = 0x403, Y = 0x95a, plausible 12-bit values. So the touch hardware path works.
- Likely remaining bug (fixed in "f"): the ARM7 computed its calibration from `0x027FFC80`, which is only the DS-mode copy. In DSi mode that address is plain RAM, so the calibration
  was garbage (a zero divisor was possible), mapping every touch to the wrong place. `0x02FFFC80` is correct in both modes. A fallback now maps the raw 12-bit range to the screen if no calibration is present.
- The console also showed `dsisd: read sector 0 x1 failed: result 5` and `FAT: unable to read boot sector`: the SD card init failed earlier (the init line had scrolled off), and later reads report "not initialised".
- The self-test never printed: `rc` ended with `. /etc/rc.common`, and sourcing the missing file aborts the script. Fixed in "f": the self-test now runs before it.
"f" ROMs: `out/dsi-mode/dslinux-dsimode-f-uc3.nds` (and `-uc2`). Built; not run.

## Results of the "f" build on the console (user's photo, DSi mode, uc3)
- **Touch works** (the user is pressing the on-screen keyboard). Cause was the calibration address (see above).
- Self-test: `MemTotal: 14084 kB`, `RAM : PASS - 16 MB real`. So the console really runs the ROM in DSi mode with 16 MB. (14084 kB = 16320 kB minus the kernel image and built-in filesystem.)
- The SD line said `PASS - card found`, `init result 0`, but the same lines showed `info 00000001, sectors 0` and a diag line with `st@fail ffffffff`, `cmd/n 0001`. These contradict each other. Explanation:
  the touch-diagnostics work item (scheduled 3 s before the SD init request) used the same shared request block with no locking, so its reply overwrote `result` (0 = OK) while the SD init had actually
  failed (`info 1` = failing step CMD0, `sectors 0` never set, `st@fail ffffffff` = software timeout, `cmd/n 0001` = one command sent). So **the SD init really failed at CMD0 (no response), and the PASS was wrong.**
  Status after the failure `208004a0`: card detected (bit 5), not write protected (bit 7), idle.
- BlocksDS's own TMIO init enables four ARM7 SCFG_EXT bits first (`SDMMC|INTERRUPT|AES|DMA`, bits 18, 8, 17, 0; "some loaders ... don't set the SCFG bits correctly"). The console read `93fffb06`: bits 18, 8, 17 set, **bit 0 (DMA) clear**; my driver never set it. Plausible cause; not confirmed.
"g" ROMs (`out/dsi-mode/dslinux-dsimode-g-uc3.nds`, `-uc2`): sets those four bits before touching the controller; a mutex now serializes all ARM7 requests; the failure diagnostics now include the OR of all status bits seen (`seen`). Built; not run.

## 3c. Faster ARM9 clock, 3d. Wi-Fi/cameras/DSP
Not started. 3c is small but needs the SD result first; 3d unchanged from the feasibility finding.

## Process note: no emulator output for me
- The screenshot scripts were removed from the repo: they captured the whole desktop (including private windows).
- melonDS 1.1 exits right after boot when its GDB stub is enabled, so reading the kernel log through it does not work.
- Capturing only the focused window does not work either: melonDS does not take focus, so the safeguard (reject anything that is not a small melonDS window) rejected every frame.
- Net effect: I can launch melonDS but cannot see what the emulated DSLinux prints. Emulator results in this project therefore come from the user's screenshots.
  Also, an emulator run cannot answer the open question (what mode the real console runs the ROM in).
- Use `dmesg | egrep 'dsisd|NDS:'` on the console; this busybox `grep` has no `-E`.
