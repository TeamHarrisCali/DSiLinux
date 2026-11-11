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

## Results of the "g" build (user's photo, DSi mode)
- `RAM : PASS - 16 MB real` (MemTotal 14084 kB) and now an honest `SD : FAIL`: `init result 3`, `info 1` (failing step CMD0), `sectors 0`.
- `SCFG_EXT 93fffb07` after, `ext 93fffb06` before: the libnds SCFG bits were written (bit 0 set). So that was not the cause.
- `st@fail ffffffff` (software timeout), `st 208004a0`, `seen 608004a0`, `cmd/n 0001`: only CMD0 was sent. The accumulated status shows `CMD_BUSY` (bit 30) was seen and no error bits,
  but never `RESP_END` (bit 0). The controller accepted and finished the command without ever reporting a response end.
- Hypothesis: my polling loop acknowledged the status register on **every poll**; libnds acknowledges once per interrupt, after the hardware has latched the bits.
  Acknowledging continuously can clear RESP_END the moment it appears.
"h" ROMs (`out/dsi-mode/dslinux-dsimode-h-uc3.nds`, `-uc2`): polling is now read-only (bits stay latched) and the status is acknowledged only before each command. Built; not run.
If it still fails the diag line (`seen`) will show what the controller reports.

## SD card WORKS on the console: "h" build (user's photo, DSi mode, uc3)
Self-test: `RAM : PASS - 16 MB real` (MemTotal 14084 kB), `SD : PASS - card found`, `dsisd: init result 0, SCFG_EXT 93fffb07, TMIO rev 0009, info 00000002, sectors 7744512`
(2 = SDHC; 7,744,512 sectors x 512 B = about 3.7 GiB), diag line all zero (no failing command). The card initialised through my ARM7 driver on real hardware.
What fixed it (from the g to the h build): polling the TMIO status read-only (acknowledge only before each command) instead of acknowledging on every poll. The earlier SCFG bit-0 change did not matter for CMD0
but was kept (it is what libnds does).
Not yet verified: reading actual sectors/mounting. The photo cut off the mount lines, and the card in this test had no `linux/` folder, so `/etc/rc.common` and `/var/run` are missing
(`mount none /var/run failed`, `rc.common: cannot open`); that is expected and not an SD error. Next test: copy the `linux` folder to the card root and boot again.
Writes are still compiled out (`CONFIG_NDS_DSISD_WRITE` off).

## Quiet build "i"
The live `dsitouch:` console lines printed a new line on every touch and made the shell unusable. They are now behind `CONFIG_NDS_DSISD_TOUCHDIAG` (default off, not set in the DSI product).
The boot-time self-test and the two `dsisd:` lines stay (they appear once at boot). ROMs: `out/dsi-mode/dslinux-dsimode-i-uc3.nds` and `-uc2`. Built; not run.

## SD card mounted and listed on the console (user's photos, "h"/"i" build, DSi mode)
- `grep dldi /proc/partitions`: `dldi` 3,872,256 KB and `dldi1` 3,860,160 KB. The kernel read the card's partition table (sector 0) through the ARM7 driver.
- `ls /media` listed the real FAT32 filesystem of the user's DSi SD card: long names, mixed case and the usual DSi/TWiLight folders (names only; the driver is read-only and nothing was opened).
  So reads, the FAT mount and directory listing work on real hardware.
- `free: not found` and `ls /usr/bin: Unknown error 2` are expected without the `linux/` userland on the card. `ls /media/linux` printed nothing: a `linux` folder exists on the card but the kernel listed it **empty**.
  Most likely the folder was created but its contents were not copied (to be confirmed on a PC). The tree to copy is `out/dsi-card/sd-root/linux` (subfolders `etc home lib usr var`, about 109 MB).
- Note for the repository: the listing showed a folder named after the console's ID; it is not recorded here.

## Confinement to the card's linux/ folder (user requirement: nothing may go outside /linux)
Rule from the user: DSLinux must never touch anything on the SD card outside `sd:/linux`. State before this change: writes are compiled out (nothing can be written), but reads were not confined
(`ls /media` showed the whole card, including the user's own files).
"j" build: `rc` mounts the card **read-only** at `/mnt`, bind-mounts only its `linux/` folder at `/media/linux`, then unmounts `/mnt`. After that the rest of the card has no path in the filesystem
(`..` cannot leave a bind mount). Every step fails closed: if the card or its `linux/` folder is missing or the bind fails, the card is unmounted and a message is printed.
The self-test has a `CONF:` line: `PASS - only /linux is reachable`, `FAIL - whole card visible at /mnt`, or `card/linux not mounted or empty`.
Honest limits:
- A root shell can still mount `/dev/dldi1` by hand and see the whole card. This confines the normal system and its scripts, not a user who deliberately does that.
- `rc.d/update` (a DSLinux script that downloads and unpacks a new release into `/media`) now fails harmlessly, because `/media` is the read-only built-in filesystem.
- When writes are enabled later, writes will be reachable only through the bind mount, i.e. inside `linux/` (plus the card's FAT tables, which any file creation changes). The mount stays read-only until then.
- Not yet run on the console. Linux 2.6.14 kernel and busybox both support `mount -o bind` (checked in the source); the behaviour on the console is unverified.
ROMs: `out/dsi-mode/dslinux-dsimode-j-uc3.nds` and `-uc2`.

## First userland boot (user's photo, "j" build): what happened
- DSLinux's real startup ran from the card (`/etc/rc.conf does not exist ... default configuration`). Reading the card works well enough to start the userland.
- `Creating default /etc/passwd` -> `/etc/passwd: cannot create` (x4), `/etc/hosts: cannot create`: the startup writes into `/etc`, which sits on the read-only card. Expected with writes off.
- `dsisd: ARM7 did not answer (cmd 1)`, then `read sector 4702080 x2 failed: result -1` and buffer I/O errors on that sector: one 2-sector read request got no answer within the ARM9's 10 s timeout.
  The ARM7's own waits can add up to about 10 s, so it may simply have been stuck in a failing read. Cause not known.
  A side risk: a late answer could have been taken for the next request.
"k" build (`out/dsi-mode/dslinux-dsimode-k-uc3.nds`, `-uc2`):
- RAM copies: `rc` copies `/etc`, `/var`, `/home` from the (read-only, confined) card into ramfs and bind-mounts the copy over the card's folder, so the system can write while the card stays untouched.
  Changes are lost at power-off. Skipped per folder if the copy fails.
- Reads: the ARM7 retries a failed read up to 3 times after sending CMD12 and resetting the controller; waits are shorter (about 0.5 s each); the ARM9 waits up to 30 s. Requests carry a sequence number (`seq`/`done_seq`) and a late
  answer to an old request is ignored. The request header grew to 128 bytes.
Built; not run.

## "k" build on the console (user's photo): card confined, startup still broken
- `CONF: PASS - only /linux is reachable`; `ls /media` shows only `linux`; `ls /media/linux` shows `etc home lib usr var`. **The confinement works on the console.**
- RAM `PASS` (MemTotal 14080 kB), SD `PASS`.
- But `/etc/rc.common: cannot open` (the j build ran it) and the `mknod: /var/run/ttyp*: Unknown error 2` lines are back: `/var/run` missing. Most likely the RAM copies of `/etc` and `/var` came out empty although
  `cp` reported success, and an empty copy bind-mounted over the folder hid the card's files. Not confirmed (the lines that would say so scrolled off).
"l" build (`out/dsi-mode/dslinux-dsimode-l-uc3.nds`, `-uc2`): copies the folder itself (`cp -a /media/linux/$d /tmp/$d`, no pre-created target), and only bind-mounts the copy if it is non-empty when the card's folder is non-empty;
otherwise prints `RAM copy of /x is empty: not used.` and leaves the card's folder visible. The self-test now also prints `ls /tmp`, `ls /etc/rc.common` and `ls /var/run` so the result of the copies is visible. Built; not run.

## "l" build on the console (user's photo), plus the user's note about I/O errors
- `/etc/rc.common` found and run, `/var/run` present (`ttyp0..f` listed), so the startup now proceeds. `/etc/passwd: cannot create` and `/etc/hosts: cannot create` remain: `ls /tmp` printed nothing, i.e. **no RAM copy was made**
  (cause unknown; the messages from the copy step had scrolled off). `rc.common` now produces about 25 lines after the self-test, which pushes the self-test off the screen.
- The user also reports `end_request: I/O error, dev dldi` and `Buffer I/O error on device dldi1`: reads at some sectors (earlier: sector 4,702,080, a 2-sector read, with the 1-sector retries failing too) still fail.
"m" build (`out/dsi-mode/dslinux-dsimode-m-uc3.nds`, `-uc2`):
- RAM copy step logs to `/tmp/ramcopy.log` (shown by the self-test), tries `cp -a`, then `tar` through a pipe, binds a copy only if non-empty.
- The self-test also runs after `rc.common`, so it is on screen when boot ends.
- On a failed read the kernel asks the ARM7 what it was doing and prints one line:
  `dsisd: ARM7 alive; req <sector> x<count> cmd <1 read> tries <n> inited <n> | last st <status> seen <bits> stage/cmd/n <stage:1 start 2 response 3 data 4 data-end, cmd, count> now <status>`,
  or `dsisd: ARM7 does not answer at all (stuck)` (5 s). The ARM7 also retries a failed read up to 3 times (CMD12 + controller reset), then re-initialises the card once and tries a last time.
Built; not run.

## "m" build on the console (user's photo): RAM copies work
- `ls /tmp`: `etc home ramcopy.log var` (the RAM copies exist); `/etc/rc.common` found; `Creating default /etc/passwd` with **no** `cannot create` lines; RAM/SD/CONF all PASS.
- `/usr/bin/head: not found`: my self-test used `head`, which is not in the card's `usr/bin`. Fixed in "n" (uses `cat`).
- The photo ends at `Not starting ntpclient: network is down` with no prompt yet: either still booting (rc.common next starts extra terminals and `gpm` from the card) or stuck there. To be reported by the user. No `dsisd:`/I/O error lines were on screen at that moment.
"n" ROMs: `out/dsi-mode/dslinux-dsimode-n-uc3.nds`, `-uc2`. Built; not run.

## "n" build on the console (user's photo): boot stops after the ntpclient line
Visible: the RAM-copy log (tar warnings "time stamp ... in the future" are only the DS clock being behind the PC's file dates; `bound var`, `bound home (empty)`), self-test lines, the rc.common banner, then nothing after `Not starting ntpclient: network is down`.
Reading `rc.common`: after that line it runs `hostname`, writes `/etc/hosts`, then tests `MemTotal > 4000`. With 16 MB this is true for the first time ever (all earlier test boots were 4 MB), so it starts two extra `agetty` login terminals and `gpm`
in the background. That branch is the prime suspect (not confirmed). Also, `rc.common` ends with `exit 0`, which also ends the sourcing `rc`, so the second self-test call never ran.
"o" build (`out/dsi-mode/dslinux-dsimode-o-uc3.nds`, `-uc2`): the DSI build ships its own `rc.common` in the built-in filesystem (`/boot/rc.common`); `rc` copies it over the **RAM copy** of `/etc` (the card's copy is untouched, so no re-copy is needed).
Differences from the original: progress markers (`rc: hostname/hosts`, `rc: extra terminals`, `rc: done`), the extra terminals and gpm are off unless `extra_terminals="YES"` in `/etc/rc.conf`, and the self-test runs once more just before `exit 0`. Built; not run.
If it still stops, the last `rc:` marker on screen says which step.

## "o" build on the console (user's photo): markers show where it stops
Printed: `rc: hostname/hosts`, `rc: extra terminals`, `Extra terminals and gpm: off`; then nothing, no `rc: done`. So the extra terminals/gpm branch was not the (only) problem.
The only external command in the remaining part of `rc.common` is `fwver` (default `show_firmware_version="YES"`), which reads the DS firmware version through `/dev/firmware`, i.e. through the kernel's firmware MTD driver and the ARM7.
That driver waited for the ARM7 with `wait_event_interruptible` and no timeout. It worked in DS mode (printed "Unknown firmware.") but this is its first run in DSi mode. Hypothesis: the ARM7's firmware read does not answer in DSi mode. Not confirmed.
Another hypothesis, not excluded: the `fwver` binary itself lives on a card region where reads fail (an earlier I/O error was at sector 4,702,080).
"p" build (`out/dsi-mode/dslinux-dsimode-p-uc3.nds`, `-uc2`): `fwver` only runs if `show_firmware_version_dsi="YES"` in `/etc/rc.conf`; marker `rc: firmware version`; the firmware MTD read now times out after 5 s (`-EIO`) instead of blocking forever. Built; not run.
If it still stops after `rc: firmware version`, wait 1-2 minutes and look for `dsisd:` / I/O error lines; the ARM9 read timeout is 30 s.

## "p" build: FIRST BOOT TO A `#` PROMPT on the real console (user report)
With `fwver` skipped the startup completes and the shell prompt appears. (The user also saw "a warning that flew by"; most likely the big `WARNING ... /etc/rc.conf does not exist` banner, harmless.)
"q" build (`out/dsi-mode/dslinux-dsimode-q-uc3.nds`, `-uc2`): `rc` creates a near-empty `/etc/rc.conf` in the RAM copy of `/etc` (silences the banner; `rc.defaults` still applies), and runs `rc.common` as a child shell with its output kept in
`/tmp/rc.common.log` and shown. Logs to read at the prompt: `cat /tmp/rc.common.log`, `cat /tmp/ramcopy.log`, `dmesg | grep dsisd`. Built; not run.
Not yet checked on the console: touch at the prompt, typing commands, what is on the card (`ls /usr/bin`, `free`), I/O errors during real use.

## SD writes: one preallocated log file, nothing else ("r" build)
User decision: logs should be writable to the card, but nothing may go outside `/linux`. General read-write FAT would also change the FAT tables and directory entries (outside the folder) with a never-run write path, so it was not done.
Design:
- A fixed-size file `sd:/linux/DSILOG.TXT` (1 MiB of zeros, short name `DSILOG.TXT`) is created on a PC (`scripts/make-logfile.sh`; a copy is at `out/dsi-card/sd-root/linux/DSILOG.TXT`).
- At boot (`NDS_SD_CMD_LOGINIT`) the **ARM7** reads the card's FAT32 itself (MBR, boot sector, root directory, `LINUX` folder, the file's directory entry, its cluster chain) and keeps the file's sector extents.
  **Every write the ARM7 does must lie entirely inside those extents; everything else is refused**, including raw writes to `/dev/dldi` from a root shell. There is no unrestricted write path in the build (`CONFIG_NDS_DSISD_WRITE` is unused).
  The write-protect slider is honoured too. The file never grows, so no directory entry and no FAT entry is changed.
- The ARM9 gets the extents back and offers `/dev/dsilog` (char 241:0, write-only): each open starts at the file's beginning, the last partial sector is zero padded on close.
- `/boot/savelog` writes dmesg, `/tmp/rc.common.log` and `/tmp/ramcopy.log` into it at the end of every boot (and can be run by hand: `/boot/savelog`). Read `DSILOG.TXT` on a PC. The mount of the card stays read-only.
Tested on the PC only: the ARM7's parser code was compiled with a host compiler against a test image with the same layout (MBR, FAT32, `linux/` folder): it found the file as one 2048-sector extent, the sector numbers point exactly at the first and last sector of the file
(markers checked), the guard accepts only those sectors (rejects the neighbours, the MBR and the boot sector), and with the file missing it reports "not found" at the file step.
**Not tested on the console**: the real write command (CMD24/25), the character device, and fragmented files (up to 32 extents are supported). Needs the SD card's write-protect slider open.

## SD LOG FILE WRITE VERIFIED ON THE CONSOLE ("r" build, user's card)
First attempt: `dsisd: no log file ... result 7 step 4` (file not yet on the card): the guard refused everything and nothing was written.
After the user put `DSILOG.TXT` into `sd:/linux/`: `dsisd: log file sd:/linux/DSILOG.TXT: 2048 sectors in 1 extents, first at 5274752`, and at the end of boot `/boot/savelog` wrote the log through `/dev/dsilog`.
Read back on the PC: the file is still exactly 1,048,576 bytes; 10.5 KiB of text (dmesg, `rc.common.log`, self-test, `ramcopy.log`) ending in `--- end ---`, all zeros after it; no I/O errors and no `dsisd:` failures in it.
So the ARM7's FAT32 parser, the sector guard, the real write command (CMD24/25), `/dev/dsilog` and `savelog` all work on a real DSi XL. (Checking the rest of the card for unwanted changes was not done beyond the file itself.)
Noise seen in that log, fixed in "s": `cp -a` of a folder always fails here ("not a directory") so tar did the copy, and tar printed a "time stamp ... in the future" warning per file (the console's clock is years behind the PC's).
"s" (`out/dsi-mode/dslinux-dsimode-s-uc3.nds`, `-uc2`) uses `tar -xmf` only (no restored dates, no failing cp). Built; not run. The "r" ROMs are kept in `old/r-log-file-works/` as the known-good build.

## "s"/"t-fast" first console photo
A boot of one of the tar-only builds: log lines `tar etc`, `bound etc`, `tar var`, `bound var`, `tar home`, `bound home (empty)` with no time-stamp warnings and no failing `cp`; self-test RAM/SD/CONF all PASS; `MemTotal: 14072 kB`; `dsisd: log file ... 2048 sectors in 1 extents`; `Savelog: written to sd:/linux/DSILOG.TXT`;
`rc: done`. `dmesg | grep Cal` printed `Calibrating delay loop... 66.76 BogoMIPS (lpj=333824)`. That is the expected value for the normal `s` ROM; for `t-fast` it would mean the 134 MHz request was not accepted (or not made).
The user later confirmed that the second photo (the one with the `SCFG_CLK` line) was the `t-fast` ROM.

## Clock check in the self-test ("u" build)
The `s` ROM's saved log (kernel `#25`) shows `Calibrating delay loop... 66.76 BogoMIPS (lpj=333824)`, identical to `t-fast` and to the `r` ROM, so the ARM9 speed is the same in all of them.
The `u` build (`out/dsi-mode/dslinux-dsimode-u-uc3.nds`, `-uc2`) reads `SCFG_CLK` (read-only, only when DSi mode is proven), logs `NDS: ARM9 clock 134 MHz (SCFG_CLK xxxx)` or `67 MHz`, and the end-of-boot self-test prints
`CLK : PASS - ARM9 at 134 MHz (the fastest)` (or `ARM9 at 67 MHz (not the fastest)` / `? (no clock line)`) plus the `Calibrating delay loop` line. **Verified on the console** (user's photo of the `u` ROM): `CLK : PASS - ARM9 at 134 MHz (the fastest)`, `Calibrating delay loop... 66.76 BogoMIPS (lpj=333824)`, RAM/SD/CONF PASS, `Savelog: written to sd:/linux/DSILOG.TXT`. (A first attempt at this build still had the fast option on, left over in the kernel config; it was caught by checking
the image for the write message and rebuilt with the option off.)

## Writable ext2 root ("v" build), confined by the ARM7
User request: real filesystem writes, not only logs, but nothing may go outside `/linux`, and it must feel like a real distro.
Why not plain FAT: FAT has no ownership, permissions or symlinks (not a distro), and every file creation changes the FAT tables and directory entries outside the folder.
Design: an **ext2 image file** `sd:/linux/ROOTFS.IMG` (preallocated on a PC, never grows) is the root. The ARM7 finds its sectors from the FAT32 itself (same code as for `DSILOG.TXT`, generalised to two files, up to 255 extents for the image)
and, once the image is registered, **refuses every card read or write outside the image and the log file**. The kernel registers only `/dev/dsiroot` (block device 240:8, sector n = sector n of the file, translated through the extents),
not the whole card; `rc` mounts it as ext2 read-write at `/media/linux`, where the old symlinks (`/etc`, `/usr`, `/bin`, `/var`, `/home`, `/lib`) already point. No RAM copies, no loop driver, no FAT mount.
Without the image the previous read-only FAT mode (now `/boot/rc.fat`) is used. `rc.common` always comes from the built-in filesystem (`/boot/rc.common`).
Image: `scripts/make-rootimg.sh [MiB]` (ext2 rev 1, 1 KiB blocks, 128-byte inodes, features only `filetype sparse_super large_file`, owned by root via fakeroot, quiet `rc.conf` included); kernel gets `CONFIG_EXT2_FS=y` (+40 KB).
Tests done on the PC only: the ARM7 code compiled with a host compiler against a 600 MiB test card holding `DSILOG.TXT` and a 160 MiB `ROOTFS.IMG`: one extent each; the extent maps onto the image's ext2 superblock (magic `53ef`);
the guard accepts exactly the two files' sectors and rejects the sectors next to them, the MBR, boot sector, FAT area, the end of the card, and a 4-sector request straddling the image end; with too small an extent limit the file is refused;
`e2fsck -fn` clean; `debugfs` shows root ownership and permissions. **Not run on the console.** First things to look at there: the log line `dsisd: root image sd:/linux/ROOTFS.IMG: N sectors in M extents; card now confined to it`, then `CONF:`/`ROOT:` in the self-test,
then a persistence test (`echo x > /home/t; sync; poweroff`, boot again, `cat /home/t`).
Known limits/risks: ext2 has no journal (use `sync; poweroff`; `e2fsck -fp` on the PC repairs); a heavily fragmented image (over 255 pieces) is refused; the old FAT copy of the userland in `sd:/linux/etc usr ...` becomes unreachable in this mode and can be deleted on the PC;
writes are single 2 KiB requests to a polling ARM7 driver, so they are slow.

### v on the console, then the power-off fix ("w" build)
User report: the v build boots and files can be written and read on the ext2 root. `poweroff` did not power the DSi off.
Cause: the kernel's power-off sends the ARM7 a DS-style command that sets the DS power register's system-power bit over SPI; in DSi mode that bit does nothing, the DSi shuts down through its power-management chip on I2C.
Fix (w): in DSi mode the ARM7 writes I2C device 0x4A register 0x11 = 0x40, the byte sequence libnds uses (`systemShutDown`, read from the libnds7 object code; `i2cWriteRegister` does the same address/register/data steps with ACK checks and retries), up to four times, then the old DS write as a fallback.
Also `poweroff()` on the ARM9 now calls `sys_sync()` first, because nothing in this system's shutdown path flushed the disk cache. Not changed: the ext2 root is not remounted read-only at power off, so `e2fsck` on a PC will report it as not cleanly unmounted (`-fp` fixes that silently).
Status: compiled and the I2C register address is in the ARM7 image; **not run on the console**. Where it fails, the console stays on and the kernel prints "Power down" before it hangs.

Result of w on the console: the shutdown sequence ran ("Sending SIGTERM/SIGKILL", "Power Down.") but the DSi stayed on and the prompt returned, so the ARM7's I2C write to the power chip did not shut it down (or never ran).
Note: libnds' own `systemShutDown` uses the plain DS SPI power write; the I2C 0x11 = 0x40 value comes from my recollection of homebrew code, not from libnds, so it may be wrong.
x build (patch 0026): a new ARM7 request, `NDS_SD_CMD_POWEROFF`, reads power-chip registers 0x00, 0x11, 0x10, 0x20, writes 0x11 = 0x40, waits, reads 0x11 again, and the ARM9 prints one `dsi poweroff: still on. scfg ... ver ... pwrcnt ... wr_ack ...` line if the console is still on. That line tells whether I2C works at all (ver 1ff = no) and whether the chip acknowledged the write.

x on the console (photo): self-test all PASS including `CONF` and `ROOT: ext2 read-write (persistent)`; a file written in an earlier boot (`test`, content `hi`) was still there after a reboot, so persistence is confirmed. The poweroff line read: `scfg 93fffb07 ver bb pwrcnt 00 pwrif 00 batt 0f wr_ack 1 i2ccnt 55 pwrcnt-after 40`: the I2C chip answers and acknowledges, register 0x11 latches 0x40, and the console stays on. DSiBrew documents 0x11 as 1 = reset, 2 = power off DSi-only hardware; 0x40 is not documented, so the I2C route was a wrong guess.
The Nintendo TWL SDK documents `PM_ForceToPowerOff` as an ARM7 write to the `PMIC_CTL` register over SPI, i.e. the same DS-style bit 6 write the kernel already sent. Cause found in `arm7/spi.c`: `power_write()` set `REG_SPI_CR = 0` straight after writing the data byte, switching the bus off before the byte went out (libnds waits for the transfer first). Fix (y, patch 0027): wait for not-busy before switching off; the I2C code is removed; `NDS_SD_CMD_POWEROFF` now performs the SPI write itself and prints `dsi poweroff: still on. scfg .. pwrctl-before .. batt .. backlight .. pwrctl-after ..` only if the console stays on. Compiled, **not yet run on the console**.

## 3c. Faster ARM9 clock: nothing to do (measured on the console)
`CONFIG_NDS_DSI_FASTCPU` writes `SCFG_CLK` (0x04004004) bit 0 early in boot. On the console the t-fast ROM printed `NDS: ARM9 SCFG_CLK 0001 -> 0001: 134 MHz requested and accepted`: the register already held `0001` before the write, so the loader had
already put the ARM9 at 134 MHz and the option changes nothing. All DSi-mode boots show `66.76 BogoMIPS (lpj=333824)`: with the ARM946E's delay loop taking about 4 cycles per iteration (sub plus a taken branch), 33.4 M iterations per second means roughly 134 MHz.
The normal `r` ROM's saved log (`DSILOG.TXT`) shows the identical `lpj=333824`, so the t-fast write changed nothing. The step from lpj to 134 MHz is an inference from the cycle count, not a direct measurement. The ARM7 has no comparable switch as far as I know. The option stays in the tree (default off); `t-fast` ROMs are in `out/dsi-mode/old/t-fast-noop/`.

