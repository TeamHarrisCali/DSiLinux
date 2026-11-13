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

y on the console: still on, and the kernel printed `dsisd: ARM7 did not answer (cmd 7)`: the ARM7 got stuck in the power-chip code (power_read/power_write wait for the SPI bus with a BIOS delay call, no timeout), so the byte-wait fix was never proven either way.
z build (patch 0028): the power-off uses its own SPI access (bounded waits, no BIOS calls); it writes progress marks (stage 1-4, SPICNT before/after, register values) into the shared block, and the ARM9 prints them after the 3 s timeout even if the ARM7 never answered: `dsi poweroff: still on (ret N). scfg .. ctl-before .. wr-ok .. ctl-after .. stage .. spicnt-start .. spicnt-end ..`. Compiled only.

z on the console: **`poweroff` switches the DSi off** (user report). So the failures were all in the ARM7 power code (the old helpers waited on the bus with a BIOS delay call, and cut the bus before the data byte finished); the I2C route was unnecessary and is gone. The diagnostic line is kept: it prints only if the console stays on.

## Desktop (desk1 build)
Findings from the tree: the DSI build already contains Microwindows/Nano-X (`nano-X`, `nanowm`, `nxterm`, `nxkbd`, `nxclock`, `nxview`, `nxev`, about 420 KB for the server) and they are in `ROOTFS.IMG`. The frame buffer driver registers two devices: `/dev/fb0` (main engine, `0x06000000`, the text console) and `/dev/fb1` (sub engine, `0x06200000`, the touch screen). Opening `/dev/fb1` makes the touch driver leave keyboard mode and report absolute pointer positions on `/dev/touch` (event1); closing it brings the touch keyboard back. Nano-X reads its device from `FRAMEBUFFER=` and its touch input from `/dev/touch`. Stock DSLinux used `fbset -depth 16 -n` and `ifconfig lo up` before starting it.
`/boot/desktop` (patch 0029) does that: `FRAMEBUFFER=/dev/fb1`, `fbset -fb /dev/fb1 -depth 16 -n`, `nano-X -p -e`, `nanowm`, `nxterm` (and `nxkbd` with the `kbd` argument); `/boot/desktop stop` stops it. Output goes to `/tmp/desktop.log`, which `/boot/savelog` adds to `DSILOG.TXT`. `start_desktop="YES"` in `/etc/rc.conf` starts it at boot. Compiled, **not run on the console**; nothing here was ever run in DSi mode.

desk1 on the console (user): Nano-X came up on the bottom screen in DSi mode, so the framebuffer, touch and Nano-X run here. The terminal window was too big for the screen: `nxterm` ignored `-g` and always opened 80x25 characters (about 640x325 pixels).
desk2 (patch 0030) follows the layout of the user's earlier TwoPaneDSi desktop (desktop on the top screen, trackpad above a keyboard on the bottom screen). What was already in the tree: the touch driver draws the keyboard in the lower 15 tile rows of the bottom screen and leaves the upper 9 rows (72 px) empty. Changes:
- `nds_ts.c`: that empty upper area is now a trackpad with its own input device ("Nintendo DS trackpad", relative X/Y plus left/right buttons), so the input layer offers it as `/dev/input/mice`: a touch that starts there moves the pointer (2 pixels per touch pixel), a short still tap is a left click; a touch that starts on the keyboard only types. The area is filled with a blue-grey panel (palette bank 1 of the keyboard's solid tile).
- `button.c`: R shoulder button = left click, L = right click, through the same device (they still also send their old Ctrl/Shift keys).
- `mou_touchscreen.c` (Nano-X): the Nintendo DS mouse driver now reads 3-byte PS/2 packets from `/dev/input/mice` (relative movement, left/right buttons) instead of grabbing the absolute touch device, which would have taken the keyboard keys away too.
- `nxterm.c`: default window 30x11 characters at (4,4), `-g COLSxROWS` works.
- `/boot/desktop` now uses the top screen: `FRAMEBUFFER=/dev/fb0`, 16 bit colour; Nano-X switches the console to graphics mode itself; `/boot/desktop stop` restores 8 bit. `nano-X` and `nxterm` are copied into the ROM (`/boot`) and used from there, so `ROOTFS.IMG` does not have to be replaced.
Compiled only. Unknowns: whether the Nano-X tty keyboard driver receives the touch keyboard's keys, whether the top screen's text console really goes quiet, pointer speed, and the panel colour.

desk2 on the console (photo): the desktop came up on the top screen (light blue background, a red-titled `nxterm` window that fits, a pointer), the bottom screen shows the blue-grey trackpad area with the K key above the keyboard. Problems: a line of the text console (`# uuf_`) showed under the desktop, so typed keys reached the console shell, and the `nxterm` window stayed empty (no prompt).
Cause of the first (probable): the shell on the console and Nano-X (tty keyboard driver, `/dev/tty`) were both reading the same tty, so keys were split between them. desk3 (patch 0031): `/boot/desktop` now runs the Nano-X server in the foreground (the shell waits), and `/boot/desktop-apps` starts `nanowm` and `nxterm` a few seconds later; `/boot/desktop stop` from inside the terminal ends it. The empty terminal is not explained yet: desk3 logs the pty nodes, `/bin/sh` and the process list to `/tmp/desktop.log` (run `/boot/savelog` after starting the desktop to get it into `DSILOG.TXT`).

desk3 on the console (photo and log): the desktop works: window manager, a fitted `nxterm` that runs `ls` and `/boot/savelog`, typing from the touch keyboard, the pointer. `desktop.log`: nano-X, nanowm and nxterm running, 11.5 MB free with the desktop up. Seen: `ls` printed raw ANSI colour codes (`0;0mtest0m`) because nxterm only knows VT52; the trackpad panel was purple (my RGB555 constant had no green).
w95a (patch 0032), after the user asked for a Windows 95 look: server colour scheme B with a navy active caption and highlight (title bars of every window, including nxterm), teal desktop; new Nano-X programs in `demos/nanox`: `dsdesk` (taskbar with a Start button, flag icon, Start menu with Terminal / Notes / Files / Clock / Shut down, hover highlight, clock in a sunken field), `dsnotes` (text editor, New/Save/Load, default file `/home/notes.txt`, a file name as argument), `dsfiles` (file browser, folders first, tap a folder to enter, tap a small file to open it in Notes, Up button, scroll buttons), all sharing `w95.h` (raised/sunken bevels, buttons, the flag). nxterm now swallows ANSI CSI sequences. Panel colour fixed (0x5a0c). The programs are also copied into the ROM (`/boot`), so `ROOTFS.IMG` stays as it is, and `/boot/desktop-apps` starts `dsdesk` too. Compiled, **not run**. Not done: per-window taskbar buttons and minimise (the window manager here has no window list), a desktop wallpaper image.

w95a on the console (photos): the Windows 95 look works: taskbar with Start and clock, Start menu, Files (listing `/home`: `test`, `.keep`) and Notes (typed text, loaded `test`). User feedback: every redraw takes about half a second (typing, moving windows), and the scale is too large (the windows covered the taskbar).
w95b (patch 0033), scale: a compiled-in 8x8 font named `Tiny` (`rom8x8`, existed in `fonts/` but was not in the font table) is now the server default and used by nxterm and the three apps; window frame 2 px (was 3), caption 10 px (was 12); Notes and Files windows 224x118 client at the top left so the taskbar stays visible; nxterm 30x14 characters. Speed: Notes keeps a table of wrapped line starts and repaints only the rows an edit touches (plus the caret), the Start menu repaints only the two items whose highlight changed. The real cause of the slowness is not measured: the fonts and pixel counts shrank, but if the engine is slow per pixel, that will show. `/boot/dsbench` (new, Nano-X) times 20 fills of 10000 pixels, 100 text lines and 100 bevel boxes and writes the numbers to `/tmp/bench.log` and into its window, so the next photo says what is slow. The Nano-X tree was rebuilt from clean objects because the header with the frame sizes is shared by server and client libraries. Compiled, **not run**.

w95b on the console (photo): the desktop runs and looks right in structure, but the 8x8 font looks squashed (short and wide). The `/boot/dsbench` result in that photo (20 fills of 10000 px 50 ms, 100 text lines 20 ms, 100 bevel boxes 40 ms) is NOT reliable: the program only waited for its own socket, not for the server to finish drawing, so it timed how fast requests could be queued.
w95c (patch 0034): the interface font `Tiny` is now X11 misc-fixed 6x10 (public domain), converted by `scripts/pcf2mwfont.py` from the PCF on the build PC into `fonts/X6x10.c`; captions 11 px; nxterm 40x12 characters; Notes and Files 232x130; `dsbench` now ends each timing with a request that has an answer (`GrGetWindowInfo`), so it waits for the server and the numbers mean something. Compiled, copied to the card, not yet run.

w95c on the console (photo, first reliable benchmark): the 6x10 font is in use and the desktop looks right in proportion. `/boot/dsbench`: 20 fills of 10000 px 80 ms (4 ms each: pixel work is fast); 100 text lines of 25 characters 250 ms (2.5 ms each); 100 bevelled boxes 60x20 1270 ms (12.7 ms each). A box is about nine drawing requests plus eight set-colour requests, so the cost is per Nano-X request (roughly 0.7 to 1.4 ms each), not per pixel. That is why typing and window changes feel slow: they are made of many small requests.
w95d (patch 0035): fewer requests. `w95.h` now keeps one graphics context per colour (no set-colour request between drawing calls), a bevelled box is four or five stacked rectangle fills instead of eight lines plus colour changes, and fields take their interior colour as an argument so no second fill is needed. `dsbench` has finer cases to find where a request's cost sits: 200 set-colour requests, 200 single pixels, 200 fills of 4x4, 100 requests with an answer (round trips), 100 text lines, 100 boxes the old way and 100 the new way. Compiled and copied to the card; **not run**.

w95d on the console (photo): per request costs: 200 set-colour requests 160 ms (0.8 ms each), 200 single pixels 200 ms, 200 4x4 fills 170 ms, 100 text lines 150 ms, 100 old style boxes 910 ms, 100 new style boxes 380 ms (the fewer-requests change worked: 2.4x), but **100 requests that wait for an answer: 4040 ms, i.e. 40 ms for every one**. My drawing helpers asked the server for text sizes (`GrGetGCTextSize`, an answered request) every time they drew a button or the clock, 80 ms per button: that, not the pixels, was the half second per redraw.
w95e (patch 0036): (1) `w95.h` no longer asks the server anything while drawing: the font cell size is read once in `w95_init()` (and the standard colours' graphics contexts are made there), text width is `strlen * cell width`; (2) pointer 8x12 instead of 16x16 (server default cursor in `srvmain.c`); (3) quick buttons on the touch screen: the touch driver draws four buttons in the top two tile rows of the bottom screen (labels from the console's mini 4x6 font at double size, drawn into the free tiles after the keyboard's), and a tap types the command and Enter as key presses: **Desk** `/boot/desktop`, **Test** `/boot/selftest`, **Log** `/boot/savelog`, **Bench** `/boot/dsbench`; the trackpad is the rest of the upper area; (4) Start menu gained Bench and Save log; (5) `dsbench` has a ninth test, 100 ping-pongs over a socket pair with another process and no Nano-X, to tell whether the 40 ms per answered request is the kernel's process switching (then it is a kernel/scheduler matter) or Nano-X's own protocol. Compiled and copied to the card, **not run**.

w95e on the console (photo): all nine bench lines; the same 40 ms for an answered request (100 in 4040 ms) but **100 process ping-pongs over a socket pair: 60 ms**, so the kernel's process switching is fast (0.6 ms per round trip); the delay is inside Nano-X. The quick buttons show and `/boot/savelog` worked, but the buttons were purple: colour index 0 of a 4 bit tile is transparent, so the face showed the backdrop colour (fixed: face is index 4).
Cause of the 40 ms (found by reading the code): the DSLinux port forces Nano-X to use TCP on the loopback interface (`#elif NDSDRIVER` in `client.c` and `srvnet.c`, port 6600, which is why the desktop script runs `ifconfig lo up`). The server answers a request with two separate writes (`GsWriteType` then `GsWrite`); with Nagle's algorithm the second small segment waits for the ACK of the first, and the receiver delays that ACK by 40 ms (the classic write-write-read stall). w95f (patch 0037): `TCP_NODELAY` on the client socket and on every accepted server socket. Expected: answered requests drop from 40 ms to about a millisecond; the per-request cost of about 0.8 ms (TCP loopback processing) stays, and switching the socket to AF_UNIX (the kernel has it: the ping-pong used one) is the next step if that matters.
Window dragging: `nanowm` moved the real window on every pointer step (a full repaint each time: the flicker) after two answered requests (`GrGetWMProperties` twice plus `GrSetWMProperties`: 80+ ms per step). It now uses its own outline mode (`OUTLINE_MOVE`, a dragged XOR rectangle, one real move on release). Compiled and copied to the card, **not run**.
Hardware rendering, assessment: the DS display hardware cannot draw Nano-X's lines, rectangles and text for us; what it can do is (1) page flipping: the frame buffer already has two pages (256x192 of 256x512 virtual), so the server could draw into the hidden page and flip with a scroll register, which removes flicker for any repaint; (2) the pointer as a hardware sprite (OBJ), so moving it costs no drawing and cannot flicker; (3) per-window layers (each window a background or sprite, moving = changing a register), which is a compositor and a large redesign. Suggested order after measuring w95f: (1), then (2).

w95f on the console (photo): TCP_NODELAY worked: 100 answered requests 380 ms (was 4040: 3.8 ms each, 10x), 20 fills of 10000 px 30 ms, 100 text lines 100 ms, 100 new style boxes 350 ms, ping-pong 50 ms. One unexplained regression: 200 set-colour requests 640 ms (was 150), to be watched.
w95g (patch 0038), page flipping, step 1 of the agreed order (page flip, then a hardware pointer, 3D compositor later for 3D applications). Findings: fb0 at 16 bit is 256x512 virtual = two stacked 256 row pages: page 0 in VRAM A (BG2), page 1 in VRAM B (BG3 at 0x06020000), BG2 on top; scrolling both layers by 256 rows (yoffset 0 / 256) swaps which one is shown. Kernel: private ioctl `NDSFB_FLIP` (0x4e01, argument 0 or 256): sets the BG2/BG3 scroll registers from a shared vblank interrupt handler (no tearing) and returns after that vblank; it is not done through FBIOPAN_DISPLAY because the text console may call that in places that cannot sleep. Nano-X: `scr_fb.c` draws on the hidden page (`psd->addr` points at it); `fb_nds_flip()` shows the drawn page and copies it onto the other (VRAM needs 16/32 bit accesses, so a hand written word copy, about 100 KB); `GsSelect` marks the screen dirty after handling anything and, instead of blocking, first polls with a zero timeout: if nothing else is waiting it flips, so a burst of drawing requests is shown as one finished picture. `NANOX_NODBUF=1 /boot/desktop` turns it off; closing Nano-X leaves page 0 shown. Compiled and copied to the card, **not run**. Unknowns: whether the copy plus the wait for the vertical blank (up to 16 ms per flip) makes the pointer feel slower, and that the pointer is still drawn in software on the hidden page; the hardware sprite pointer is the next step.

w95g on the console (photo and report): dragging windows felt **more** laggy than before. Reason: after each handled event (every pointer step) the server flipped: wait for the vertical blank (up to 16 ms) plus a copy of about 100 KB of VRAM, so a drag cost tens of milliseconds per step. Bench in w95g: 20 fills 30 ms, 200 set-colour 300 ms, 200 single pixels 350 ms (noisy: 120 before), 100 answered requests 380 ms, 100 text lines 80 ms, 100 new style boxes 300 ms, ping-pong 70 ms.
w95h (patch 0039), the agreed second step plus flip cost reduction: (1) the **pointer is a hardware sprite**: kernel ioctl `NDSFB_CURSOR` (0x4e04) sets up VRAM bank F as main-screen OBJ memory (0x06400000), turns the OBJ layer on (DISPLAY_CR bits 12 and 4, kept by `set_par`), hides all 128 OAM entries, uploads a 16x16 4 bit sprite plus two palette entries and moves OAM entry 0; the Nano-X engine (`devmouse.c`) has `GdSetHardwareCursor()`: when a screen driver registers a pointer the engine never draws the pointer into the screen, `GdCheckCursor` returns at once (no hide/show around every drawing call) and moving the pointer is one ioctl; shapes up to 16x16 (colour rule as the software pointer: image bit = background colour, masked only = foreground); (2) the flip no longer waits: `NDSFB_FLIP_ASYNC` returns at once and the wait (`NDSFB_FLIP_WAIT`) happens just before the next drawing, when the vertical blank has normally passed; (3) only the area that was drawn is copied to the other page: `scr_fb.c` wraps the screen's drawing functions (DrawPixel, HorzLine, VertLine, FillRect, Blit, DrawArea, the stretch blits) and keeps the bounding box of what was drawn since the last flip; nothing is flipped when nothing was drawn. `NANOX_NODBUF=1` turns off flipping, `NANOX_SWCURSOR=1` the sprite pointer (`NANOX_NODBUF=1 NANOX_SWCURSOR=1 /boot/desktop` is the old behaviour). Start menu: **Exit desktop** is the old "Shut down" (it only ended the desktop session); **Shut down** now runs `/boot/shutdown` (`sync; poweroff`). Compiled and copied to the card, **not run**. Risks: a sprite that does not show (then use `NANOX_SWCURSOR=1`) and an area the wrappers miss (stale patches of screen after a flip).

w95h on the console (two photos): the top screen stayed **black** while the hardware pointer worked (a white arrow over the desktop area, and the terminal's green pointer shape), so the sprite and the kernel side are fine but nothing was ever shown. Cause (by reading): the server calls `fb_setportrait()` during start-up, which re-assigns the screen's drawing functions with `set_subdriver()`, removing my dirty-area wrappers; nothing was then noted as drawn, `fb_nds_flip()` saw an empty area and never flipped, so everything was drawn on the hidden page. w95g did not show it because it flipped after every event without looking at what was drawn.
w95i (patch 0040): `nds_wrap_install()` puts the wrappers in front of whatever the functions currently are and only wraps those that are not already wrapped; it runs at open, at the end of `fb_setportrait()` and before every flip; if it had to wrap anything before a flip, the whole screen is treated as drawn (so a missed drawing can only cost a bigger copy, not a black screen). `/tmp/desktop.log` now says `nano-X: page flipping on` and `nano-X: hardware pointer on` (or why not), and one line if the wrappers had to be re-installed. Compiled and copied to the card, **not run**.

w95i on the console (user): the desktop is back (the wrapper fix worked), Shut down powers the DS off, window dragging is still a little choppy, and (second message) **there is no drag outline: the window contents move**. Correction of an earlier claim: since w95f I said `nanowm` drags an outline. That was never running on the console: `nanowm` is launched from `/usr/bin` in `ROOTFS.IMG` (the original build), and only `nano-X`, `nxterm` and my own programs were copied into the ROM, so none of my `nanowm` changes (outline move, the single XOR GC) reached the DS.
w95j (patch 0041): `nanowm` is copied into the ROM (`/boot/nanowm`) and `/boot/desktop-apps` starts that copy; `/boot/desktop stop` also stops `dsdesk`. With it come the pending drag changes: `actions.c` uses ONE XOR graphics context for the whole drag (before: a new one per pointer step, an answered request that also split every step into two batches, so the server could flip a half-drawn outline) and skips steps where the window did not move; the dirty-area tracking in `scr_fb.c` is now a short list of up to 12 rectangles that merge when they overlap or grow by under 300 pixels, so an outline costs a few KB to copy instead of its bounding box; `dsbench` has two new lines, 100 drag steps with a new GC each and with one GC. Compiled and copied to the card, **not run**.

w95j on the console (photo and report): "feels so much better". Benchmark: 100 drag steps with a new graphics context each 610 ms (6.1 ms per step), with one context 130 ms (1.3 ms per step): the old per-step cost was mostly the answered request that created the context. Other lines: 20 big fills 30 ms, 100 answered requests 410 ms (4.1 ms each, down from 40), 100 text lines 100 ms, 100 new style boxes 340 ms (old style 730 ms), ping-pong 70 ms. Verified on the console so far: desktop on the top screen, trackpad and touch keyboard, quick buttons, hardware sprite pointer, page flipping, outline drags, Start menu, Notes, Files, Shut down. Not done: a taskbar button per window and minimise (no window list in this window manager), a wallpaper, AF_UNIX instead of TCP for the Nano-X socket (the kernel supports it; the TCP loopback still costs about 0.8 ms per request), the 3D compositor (agreed for later, for 3D applications; TinySDGL's `gears` and `triangle` are already on the card image).

Taskbar window buttons (w95k, patch 0042; user's order of work: this, then the Nano-X socket type, then 3D applications). `dsdesk` reads the list of application windows from the root window's children: the window manager puts every application window in a container (a child of the root); a root child that has a child of its own is an application window (the taskbar and the Start menu have none); the title comes from the inner window's WM properties; the list is kept in creation order. It is read when the root window sends child updates (create, map, unmap, destroy, reparent; moves are ignored) and the server has been quiet for 0.3 s, because every read costs answered requests. The focus is checked on activate events and every 1.2 s of quiet (`GrGetFocus`). A button click raises and focuses its window; on the active window it minimises (unmaps the container); on a minimised window it maps, raises and focuses it again. The active window's button is drawn pressed, minimised windows have grey text. Buttons share the space between Start and the clock (at most 90 px each, text cut to fit). Compiled and copied to the card, **not run**.

w95k on the console (user): the taskbar window buttons show up and stay in step with the windows, the pressed highlight follows the right window: "consider it good". Requests: a minimise button next to the X, then the Nano-X socket, then 3D applications.
w95l (patch 0043), three changes. (1) **Minimise box** in the title bar, left of the close box (`nxPaintNCArea` draws it, `nanowm`'s `container_buttondown` handles the press by unmapping the window's container); the taskbar's button for it stays and brings it back; after a minimise or close `dsdesk` hands the keyboard focus to the newest open window. (2) **Cheaper caption painting**: `nxdraw.c` created and destroyed a graphics context per drawing helper and asked the server for about 25 system colours on every title bar repaint, each an answered request (about 4 ms): 100 ms or more per title repaint (activate, drag, focus change). It now uses one cached context and caches the colours (they never change). (3) **Unix socket**: the DS port forced the TCP loopback (`NDSDRIVER` branches in `client.c`/`srvnet.c`, with `ifconfig lo up`); a request through TCP costs about 0.8 ms of protocol processing even with `TCP_NODELAY`. The server now listens on the local socket `/tmp/.nano-X` unless `NANOX_TCP=1` is set, and the client (`GrOpen`) decides the same way from the same variable, so every program in the desktop session agrees; `NXDISPLAY` still overrides the path. The log line is `nano-X: unix socket /tmp/.nano-X` (or `TCP loopback socket (NANOX_TCP)`). Fallback: `NANOX_TCP=1 /boot/desktop`. Expected: the per-request lines of `/boot/dsbench` (set-colour 250 ms/200, single pixels 270 ms/200, answered requests 410 ms/100, drag step 1.3 ms) go down. Compiled and copied to the card, **not run**; the kernel does support unix sockets (the benchmark's ping-pong uses a socket pair).

w95l on the console (photo): the minimise box shows next to the X, taskbar buttons for `nxterm` and `Bench`. Bench with the unix socket and the nxdraw caches: 20 fills 40 ms, 200 set-colour requests 130 ms (was 250), 200 single pixels 80 ms (270), 200 fills of 4x4 140 ms, 100 answered requests 220 ms (410: 2.2 ms each), 100 text lines 90 ms, 100 new style boxes 290 ms, 100 drag steps with one GC 110 ms (1.1 ms per step), ping-pong 60 ms. Roughly twice as fast per request.
3D applications, step 1 (w95m, patch 0044): measure before building. TinySDGL (a Nano-X-less port of TinyGL, a software OpenGL subset) is in the tree and its examples `gears`, `triangle`, `mElite` are on the card image. They use SDL with the `fbcon` driver (`--enable-video-fbcon` in `lib/sdl/Makefile`), so they take over the text screen (/dev/fb0) and cannot run inside the Nano-X desktop; `gears` is already sized 256x192, asks for a 32 bit surface (SDL converts to the 16 bit frame buffer), ends on Esc or q and prints frames per second every few seconds. `/boot/gl` (new) refuses to run while Nano-X runs, otherwise starts `gears`. `dsbench` has two new lines, 100000 float multiply-adds and 100000 fixed point (16.16) multiply-adds: the DS has no floating point hardware, TinyGL does its geometry in float, so the ratio shows how much a fixed point port could gain. Plan after the numbers: if gears is too slow, port TinyGL's transform path to fixed point; a Nano-X window version (render into a buffer, show it with GrArea) for 3D inside the desktop; the hardware 3D engine and the compositor stay later, as agreed. Compiled and copied to the card, **not run**.

w95m on the console (photo and report): **gears runs at about 4 frames per second** on the text screen. Bench: 100000 float multiply-adds 100 ms, **100000 integer (16.16) multiply-adds 20 ms**: floating point costs 5 times as much (soft float: the CPU has no FPU). The scene is about 500 vertices per frame (gear 1 with 20 teeth, gears 2 and 3 with 10), lit, depth tested, flat and smooth shaded; TinyGL's whole geometry path (matrix transform, normal transform and normalisation, lighting, clip tests, projection, viewport) is float, only the triangle filling is integer.
w95n (patch 0045): `dsgears` (examples/dsgears.c, installed in `/boot`) runs the gears as a profiler: five tests of 3 s each (full; lighting off; a 16x12 viewport, lit and unlit, which leaves almost no pixels to fill so `draw` is nearly all geometry; and an empty frame with no drawing) and prints per test frames, fps and ms per frame spent in clear, draw (geometry plus filling), copy (TinyGL buffer to SDL surface) and flip (SDL's 32 bit surface converted to the 16 bit frame buffer). `/boot/gl profile` runs it (stop the desktop first). The table tells what to fix: float geometry (fixed point port of the vertex path), fill (cheaper shading, smaller render size), or the copy/flip conversions (render straight into the DS pixel format, BGR 555 with the alpha bit). Compiled and copied to the card, **not run**.

w95n on the console (photo of `/boot/gl profile`), ms per frame at 256x192 with SDL's 32 bit surface: full scene 5.3 fps (clear 11.3, draw 118.8, copy 19.4, flip 40.0); lighting off 9.1 fps (draw 40.4); geometry only (16x12 viewport) lit 6.1 fps (draw 92.1); geometry only unlit 10.5 fps (draw 24.7); **empty frame 14.6 fps (clear 13.4, copy 16.1, flip 39.1)**. Conclusions: (1) a frame costs 68 ms before any 3D work, SDL's flip (32 bit surface converted to the 16 bit screen) being 40 ms and TinyGL's copy 16 ms, so this pipeline cannot exceed 14.6 fps; (2) lighting costs about 67 ms per frame (about 130 microseconds per vertex of soft float); (3) filling pixels is smaller (about 27 ms lit, 16 ms unlit); main RAM writes are slow here (clearing 2 x 98 KB takes 13 ms). A tuned software path (direct output in the DS pixel format, half resolution, fixed point lighting) might reach 15 to 20 fps for this scene; the hardware engine should do 60 for it.
Hardware 3D step 1 (w95o, patch 0046), following the plan of the user ("3D applications", compositor for 3D applications): the DS main screen can draw a 3D picture on BG0 below the 2D layers; wherever the frame buffer pixel is transparent (bit 15 clear in 16 bit, index 0 in 8 bit) the 3D picture shows through, which is also how a 3D window in the desktop will work later (the window's client area transparent, the 3D viewport set to its rectangle, other windows covering it as usual). The engine registers are kernel-only (MPU), so `ndsfb.c` has two ioctls: `NDSFB_GX_SETUP` (0x4e05: power the geometry and rendering engines, BG0 priority 3, BG0 on and 3D) and `NDSFB_GX_SUBMIT` (0x4e06: count pairs of register offset and value, written in order; accepted offsets are the command ports 0x400-0x5ff and 0x060, 0x350, 0x354). `dsgx` (examples/dsgx.c, `/boot/dsgx`) builds the three gears once (same shapes as gears.c, recorded as vertex lists with normals), then per frame sends matrices (1.19.12), the light (OpenGL position (5,5,10) w=0 as a direction), material (diffuse and ambient) and the vertex lists (NORMAL when it changes, VTX_16), then SWAP_BUFFERS; the engine does transforms, lighting, clipping and filling, and the geometry FIFO stalls the CPU when full, which paces it. `/boot/gl hw` runs the gears, `/boot/gl tri` one colour triangle (the smallest test of the whole pipeline); both need the text screen. Compiled and copied to the card, **not run**: the register formats come from documentation, so a black or wrong picture is possible; the triangle test says whether the pipeline works at all.

w95o on the console (photos): **the hardware 3D engine works at the first attempt**. `/boot/gl tri`: a red/green/blue triangle rotates with smooth colour blending, 1302 frames in 13.54 s (96.2 per second submitted). `/boot/gl hw`: the three gears are drawn in 3D with hardware lighting, 1042 frames in 13.11 s (79.5 per second submitted), against 5.3 for TinyGL in software. The counts are frames sent to the engine, the 60 Hz display shows at most 60 of them; the teeth look rough because the test enables neither culling nor anti-aliasing. So the command formats (1.19.12 matrices, VTX_16, packed normals, light and material commands, polygon attributes) and the kernel path are right.
w95p (patch 0047), 3D inside the desktop, the design agreed for the compositor: (1) a colour key in the Nano-X pixel conversion (`device.h`): on the DS every pixel is opaque (bit 15 set) except the colour magenta (255, 0, 255), which becomes pixel 0 = transparent; (2) `dsgl3d` (Start menu "3D gears", `/boot/dsgl3d`) creates a window whose client area is that colour, switches the 3D engine on, and draws the gears with the 3D viewport set to the window's rectangle on the screen (parent position plus its own), re-read when the root window reports child updates (the window manager moving it) and on exposure; frames are paced by the engine's FIFO; a minimised window stops drawing; any window above it covers the 3D picture because the 3D layer is behind the frame buffer layers (BG0 priority 3); arrow keys turn the view, Esc/q/close end it; the kernel switches the engine off again on exit. One 3D program at a time. The Nano-X tree was rebuilt from clean because `device.h` changed. Compiled and copied to the card, **not run**.

w95p on the console (user): the gears show up in the desktop window. Two bugs: (1) after moving the window and placing it, black lines along the x and y direction appear and sometimes go away when it is moved again; (2) the 3D picture is squashed when the window reaches the bottom of the screen.
w95q (patch 0048): (1) cause: the window manager's drag outline is drawn with XOR. The 16 bit driver forced the opaque bit (bit 15) on after every raster operation, so a see-through pixel (0, the 3D window's colour key) XORed with the outline colour and XORed again to erase it came back as 0x8000, opaque black, instead of 0: every time the outline crossed the 3D window's client area it left black lines. `fblin16.c` now keeps each pixel's own transparency bit for non-copy operations (`APPLYOP_KEEP`), so XOR is reversible; ordinary drawing is unchanged. (2) cause: the engine's viewport cannot go outside the 256x192 screen, so a window partly outside got a clipped viewport but kept the full window's projection, which squeezed the scene into the smaller area. `set_view()` now uses the visible part as the viewport and the matching slice (off-centre frustum) of the full window's projection, so the picture is clipped, not squashed. Also in this build: `NDSFB_VSYNC` (0x4e07, the kernel counts vertical blanks) and `dsgl3d` waits for it each frame, so its fps counter (drawn as text in the window's corner once a second) is the rate really shown, 60 at most; keys `a` (edge smoothing, on by default: DISP3DCNT bit 4) and `c` (hidden face culling, off by default because the face winding is not confirmed) for the quality steps; the window rectangle is re-read twice a second so a missed move heals itself. Compiled and copied to the card, **not run**.

w95r (patch 0049): the small 3D library. `user/microwin/src/demos/nanox/dsgx.h` is a header-only library over the kernel's `NDSFB_GX_*` ioctls: `gx_open/gx_close/gx_flush`, `gx_vsync`, `gx_control(GX_CTRL_AA|GX_CTRL_TEXTURE)`, `gx_viewport` (top-left pixel coordinates), matrices (`gx_mode`, `gx_identity/push/pop/translate/scale/rotate/frustum`, floats converted to the engine's 1.19.12), `gx_light`, `gx_material`, `gx_polyattr(lights, GX_CULL_BACK|FRONT|NONE, alpha)`, immediate vertices (`gx_begin/gx_color/gx_normal/gx_vertex/gx_end`) and recorded meshes (`struct gx_mesh`) that are converted once and replayed each frame. `dsgx_win.h` is the desktop part (the window with the colour-key background, following moves, viewport and frustum slice, text overlay). `dsgl3d` (desktop window) and the console `dsgx` (`/boot/gl hw`, `/boot/gl tri`; moved from TinySDGL to the microwin demos) are rewritten on it. Fix for "I do not see the c": the window now takes the keyboard focus when it opens, and the state line `a:aa on c:cull off` is always drawn under the fps line. Culling is off by default (the face winding of the engine is assumed to be OpenGL's, counter-clockwise front; if the gears vanish with `c` on, the winding is the other way and it is a one-word change). Compiled and copied to the card, **not run**. Next: textures (VRAM bank D as the texture slot).

w95s (patch 0050): textures and arrow keys. (1) Textures: the kernel has `NDSFB_GX_TEXLOAD` (0x4e08): it maps VRAM bank D to the CPU (0x06860000) only for the copy, writes the data and maps it as texture slot 0, so texture offset n in `TEXIMAGE_PARAM` is byte n of the 128 KB bank (n / 8 in the register). `dsgx.h` gets `gx_texture_load`, `gx_texture(offset, w, h, flags)` (direct colour RGB555, format 7, sizes 8..1024, repeat/flip), `gx_texcoord` (12.4 fixed, in texels) and `gx_mesh_texcoord`; `GX_CTRL_TEXTURE` is on (DISP3DCNT bit 0). Texture pixels need bit 15 set (alpha), a lit polygon multiplies the picture with the light. `dsgx_demo.h` now holds the shared scenes (gears, a procedural 64x64 brick picture, a cube with counter clockwise quads); in the 3D window the `t` key switches gears/cube, on the text screen `/boot/gl cube`. Untextured scenes send `TEXIMAGE_PARAM` 0 so the last texture does not stick. (2) Arrow keys: the d-pad already sends KEY_UP etc. in the kernel, but Nano-X's tty keyboard driver passed the console's `ESC [ A` bytes through unchanged, so programs saw Esc (closing the 3D window) then `[` and `A`. `kbd_tty.c` now turns `ESC [ A/B/C/D/H/F` and `ESC [ n ~` into MWKEY_UP/DOWN/RIGHT/LEFT/HOME/END/INSERT/DELETE/PAGEUP/PAGEDOWN (a lone Esc stays Esc); nxterm sends them to the shell as escape sequences again (before it threw special keys away, so the d-pad arrows reached the shell as the three raw bytes). On the touch screen, four 16x16 arrow buttons (left, up, down, right) sit in the bottom right corner of the trackpad area (tile rows 7-8, columns 24-31; the key is held while touched so it repeats). Compiled and copied to the card, **not run**.

w95t (patch 0051): user photos of w95s: the brick cube is textured and runs at 60 fps; the touch arrows appear. Two faults: the fourth arrow button pointed left (the mirroring for "right" flipped rows instead of columns), and the gears looked hollow: the demo's `gear()` (also in the earlier dsgx) had only the front face strip, the outward tooth faces and the inner cylinder, missing what the original OpenGL gears draw, the back face and the front and back sides of the teeth, so the back and the tooth tops were see-through. Now complete (6 vertex lists, about 530 vertices for the big gear, mesh capacity 700). Compiled and copied to the card, **not run**.

w95u (patch 0052): sound output and volume, first test. Findings: DSLinux already had the DS sound path (ARM7 `sound.c` plays a ring buffer through the DS sound channels, the ARM9 ALSA driver `sound/arm/nds-sound.c` with OSS emulation gives `/dev/dsp`; microphone capture via the DS SPI path, which will not work in DSi mode, is for later). What DSi mode adds, from BlocksDS libnds (`audio.c` enableSound, zlib): the power chip's amplifier bit (SPI power register 0 bit 0) and mute bit (bit 1), and the DSi I2S output (`SNDEXTCNT` 0x04004700: enable, 100% ARM output, 32 kHz), which carries the DS mixer's output to the TSC2117 codec. `arm7/dsivol.c` does these when `sound_set_power(1)` runs, with bounded SPI waits (the BIOS delay calls hang the ARM7 in DSi mode). Volume: the DSi's volume buttons only change a number in the power management chip (I2C device 0x4A register 0x40, 0..31); libnds never applies it, so on a bare DSi program nothing would change the loudness. `dsivol_poll()` (about 5 times a second from the vblank interrupt) reads it over I2C (own bounded copy of libnds's sequence), applies it as the codec DAC volume (page 0 registers 0x41/0x42, 1.5 dB per step, 0 dB at 31, mute at 0), and sends it to the ARM9 in a `FIFO_BUTTONS` message with bit 8 set (the existing button message carries only the low 8 bits otherwise); `volume.c` serves `/proc/dsivolume` (`level=N max=31 percent=P status=S`, status 0 ok, 1..4 the I2C step that failed, 5 no message yet) and `dsdesk` shows a 2 second popup with the percentage and a bar when the level changes (and one popup "read failed (step)" if the read does not work). `dsplay` plays a C major scale (no argument) or a PCM WAV file through `/dev/dsp` and prints what it did; Start menu entry "Sound test". Unknown until tested: whether the speaker/headphones make any sound at all, whether the I2C read works in this mode (the earlier poweroff experiment wrote I2C without effect), whether level 31 means 100%. Compiled and copied to the card, **not run**.

w95v (patch 0053): microphone, voice memos, menu groups. Mic: the DS path (touch chip AUX input over SPI) does not exist in DSi mode. libnds uses the TSC2117 codec's ADC (bank 1 registers 0x2E mic bias and 0x2F mic gain, bank 0 0x51 ADC on, 0x52 unmute) and reads samples from a small FIFO (MICCNT 0x04004600, MICDATA 0x04004604, normal format = signed 16 bit, 32.7 kHz). `arm7/microphone.c` keeps the existing design (timer 3 interrupt at the requested sample rate fills the ARM9's capture buffer and tells the ARM9 once per period) and, in DSi mode, switches the amplifier through the codec and takes the newest FIFO sample on each tick (gain index 3 = 33.5 dB like libnds; tune later). The ARM9 ALSA driver now uses 1 KB capture periods (about 60 ms at 16 kHz, so a program sees data often) and flushes the data cache over the bytes it copies (the ARM7 writes them behind its back). `dsmemo` records 16 bit mono 16 kHz WAV files to `/home/memos/memoNNN.wav` (persistent, on the ext2 root), plays them back, and shows a scrolling waveform (the scope scrolls with one blit and draws only new columns) plus a level meter for both recording and playback; buttons Rec, Stop, Play, < >, Del (twice), and keys r s p space left right d q. Menu: the Start menu is a tree (Terminal, Files, Accessories > Notes, Clock; Multimedia > Voice memos, Sound test, 3D gears; Games > Minesweeper, Tetris; System > Bench, Save log; Exit desktop; Shut down); groups open to the side as the pointer rests on them (up to 3 levels). Taskbar: a tray with the volume percent and a speaker next to the clock, a divider after Start, window button titles end in .. when cut. Minesweeper (`landmine`) and Tetris (`ntetris`) from Microwindows are shipped in /boot (ROOTFS.IMG predates them). Compiled and copied to the card, **not run**.

w95w (patch 0054): camera test and photo gallery (done while the user was away, so nothing here is tested). Design, from BlocksDS libnds (zlib): the DSi has two Aptina MT9V113 sensors on the I2C bus (devices 0x7A and 0x78, 16 bit register addresses, plus the sensor's "MCU" registers through 0x098C/0x0990). `arm7/dsicam.c` ports the libnds init (reset, wakeup, PLL, output sizes 256x192 preview / 640x480 capture, sensor read modes, auto exposure and white balance, then both sensors back to standby), activate/deactivate (the camera LED through the power chip, I2C 0x4A register 0x31) and the sequencer commands (preview/capture); every wait is bounded and reports a timeout mask, because the ARM7 also serves the SD card and touch screen. The ARM9 cannot talk to the sensors, so commands travel through the existing SD request block (`NDS_SD_CMD_CAMERA` = 9; count = sub command 0 init / 1 deinit / 2 select / 3 sequencer command, sector = argument; answer in info[0] = value (chip version, 0x2280 means the MT9V113 answered) and info[1] = error mask) and `dsisd_camera_cmd()` in `dldi_c.c`. The camera interface itself is on the ARM9 (`ndsfb.c`, ioctls `NDSFB_CAM_CMD` 0x4e09 and `NDSFB_CAM_FRAME` 0x4e0a): SCFG_CLK camera bits (2 and 8), CAM_MCNT/CAM_CNT at 0x04004200, power rails, the new DMA (NDMA channel 3 from CAM_DATA 0x04004204, 512 word blocks started by the camera) into a 96 KB buffer; frames are 256x192 RGB555 (the interface converts the sensor's YUV when CAM_CNT bit 13 is set), bit 15 is set in the kernel so a frame is usable as a texture. `dscam` loads each frame as a 256x256 texture (frame in the upper 192 rows) and draws it as one quad on the 3D layer inside a desktop window, far faster than pushing pixels through Nano-X; space/Enter/tap saves a photo (24 bit BMP, 256x192, `/home/photos/photoNNN.bmp`, readable on a PC), `c` picks the other camera, `f`/`m` flip/mirror, `b` swaps red and blue (libnds notes that on the DSi the colours or vertical orientation may come out swapped), and the overlay lines show what is happening, including the chip version and error mask if set-up fails and the SCFG_EXT value (the camera and the new DMA must be enabled there). `dsgallery` shows the photos the same way (left/right or a tap on the left/right third, `d` twice deletes, `c` opens the camera). Menu: Multimedia > Camera, Photos. Unknowns for the first test: whether the sensors answer (chip version 0x2280), whether the loader left SCFG_EXT/SCFG_CLK writable, which camera index is which, colour order and orientation, and whether the ARM7 stays responsive during the roughly half second the set-up takes. Compiled and copied to the card, **not run**.

w95x (patch 0055): user photos of w95w. Camera: works. The Camera window shows a live preview at about 9 frames per second (camera 1), `photo003.bmp` was saved and the gallery displays it; the picture looked streaky/banded in the photos (it may be what the camera was pointed at; colours, orientation and which index is the inner camera still to be confirmed). Menu groups and the taskbar volume tray work (19%). Microphone: `dsmemo` records but gets no data ("REC (no microphone data yet)", `memo002.wav` is an empty 44 byte file, playing it says "cannot load memo (-3)"). So the ARM9 ALSA capture side never received samples. Not yet known whether the capture stream starts at all (a non blocking OSS read may not start it), whether the ARM7 timer interrupt runs, whether the codec FIFO has data, or whether the period messages reach the ARM9. w95x adds counters to find out: ARM7 `mic_diag()` (mic_on/start/stop calls, timer interrupts, FIFO full/empty counts at each tick, period messages sent, buffer wraps, and the settings: buffer address, size, period, rate, format, last sample, MICCNT and TM3CNT, IE) served through `NDS_SD_CMD_MICDIAG` (10) and `/proc/dsimic`, plus kernel log lines from the ALSA driver at capture prepare, trigger and the first period messages. Test: record in Voice memos for a few seconds, then `cat /proc/dsimic` in the Terminal and read `/boot/savelog` or DSILOG.TXT for the `nds-sound:` lines.

w95y (patch 0056): automatic logging while testing. The user takes the SD card out after every test run, so the log must already be on the card. `/boot/autolog` (started in the background by `/boot/rc`) runs `/boot/savelog quiet` every 10 seconds: it rebuilds the log (dmesg, rc.common.log, ramcopy.log, desktop.log, `/proc/dsimic` microphone counters, `/proc/dsivolume`, meminfo, listings of `/home/memos` and `/home/photos`) and writes it to `sd:/linux/DSILOG.TXT` through `/dev/dsilog` only when it differs from the last saved copy; `/boot/shutdown` saves once more before powering off. dsmemo and dscam now print what they do (recording start/stop with byte counts, no-data warning, camera init result with chip version, error mask and SCFG_EXT) into desktop.log. The SD writes run on the ARM7 inside its FIFO interrupt and can briefly delay the microphone's timer interrupt, which is acceptable for testing; when the problems are fixed the logging is tuned back by removing the one line in `vendor/.../rc` that starts autolog (the savelog at boot and the Log button stay).

w95z (patch 0057): the w95y autolog wrote nothing. User photo of the console after boot: `/usr/bin/cat: /tmp/bootlog.body: Unknown error 22`, `savelog: could not write`, and the log text printed on the screen instead of going into the file. Cause: the target shell is `msh` (BusyBox minix shell), which does not honour a redirect on a `{ ...; }` group (the commands ran but their output went to the console, and the later `cat` of the never filled file failed). Fix: `/boot/logbody` holds the log commands as plain lines and `savelog` runs it as a child with an ordinary redirect (`/bin/sh /boot/logbody > file 2>&1`, the way `rc` already runs `rc.common`), compares with `cmp -s` in quiet mode, and appends with `>>`. Lesson for all boot scripts: plain commands only. The same photo shows both memo files at 44 bytes (header only: the microphone has delivered no data in either test), four 144 KB photos, and about 10 MB free memory.

w96a (patch 0058): w95z logged to the card correctly (the card log shows the dmesg, `/proc/dsimic` with all counters 0 because no recording had happened yet, memo and photo listings) but boot stopped right after "savelog: written to sd:/linux/DSILOG.TXT": the next rc line was `[ -x /boot/autolog ] && /boot/autolog > /dev/null 2>&1 &`, and msh does not background an AND list, so the endless autolog loop ran in the foreground and rc never finished. Now `if [ -x /boot/autolog ]; then /boot/autolog &; fi` as plain lines, like `/boot/desktop &` in rc.common. Second msh lesson: `&` only on a simple command.

w96b (patch 0059): what the card log of w96a showed (read from the card, no photo needed). (1) The "-s: unknown error 2" after boot: `savelog quiet` ran `/usr/bin/cmp -s ...` every 10 s once a previous copy existed, but the ext2 root image on the card is older than the build and has no `cmp` (error 2 = file not found, and msh names the failing command by its first argument). `cmp` is now shipped in the ROM as `/boot/cmp` (like landmine/ntetris), and savelog only compares if it is there. Lesson: anything a boot script needs must come from the ROM, not from ROOTFS.IMG. (2) The microphone: `nds-sound: capture prepare rate 16000 fmt 2 buffer 8192 period 1024` appears (the ALSA capture stream was set up, so the OSS calls and the driver's prepare work), but no `capture trigger` line, and `/proc/dsimic` shows `mic_on=1 start=0 stop=0 irq=0 period_msgs=0`: the ARM7 was powered up for the mic but never told to start sampling, so the kernel never started the stream. dsmemo's own log says `no microphone data after 2 s (last read errno 22)` and `0 bytes`. So the fault is in the kernel's sound layer (a non blocking OSS read before the stream is running), not in the ARM7 or the codec. The kernel source showed the OSS emulation starts a capture on the first read (start threshold 1) or on SNDCTL_DSP_SETTRIGGER (but only after a trigger-off: `oss.trigger` starts as 1, so a plain enable-input is skipped). w96b makes dsmemo follow the standard OSS recipe (trigger 0, then trigger PCM_ENABLE_INPUT) right after setting the parameters and logs every sound call (ioctl return/errno for fragment, format, channels, rate, the two triggers) and the first reads, so the next card log shows exactly where it goes wrong if it still does.

w96c (patch 0060): the card log of w96b. The explicit trigger worked: `capture trigger 1`, `mic period message` 1, 2, 3, 200 (344 in all), and `/proc/dsimic` `irq=176605 fifo_full=38013 fifo_empty=138591 period_msgs=344 wraps=43`: the ARM7 sampled the microphone, wrote it into the ARM9's buffer and told the ARM9 for every period, so the whole microphone path works. dsmemo's reads still all returned -1 errno 22. Cause, found in `sound/core/pcm_lib.c`: `snd_pcm_lib_read()` returns -EINVAL unless the stream's access mode is `RW_INTERLEAVED` (the write function has an exception for one channel, the read function has none), and the driver's capture hardware description only offered `NONINTERLEAVED` access, which for one channel is the same memory layout. Playback is unaffected (mono writes are allowed, and stereo playback on the ARM7 needs the non interleaved layout). That also explains the first log (w96a): without the trigger, the read that should have started the stream failed before starting anything. Fix: `SNDRV_PCM_INFO_INTERLEAVED` added to the capture hardware flags. One more oddity in that log: the last sample was `0x7fff` (the maximum), which may mean clipping at the 33.5 dB codec gain, so the counters now also show the lowest and highest sample seen since the recording started (`samples: lowest .. highest ..` in `/proc/dsimic`); if they sit at the limits, the gain index in `arm7/microphone.c` (DSI_MIC_GAIN) comes down.

w96d (patch 0061): the card log of w96c, and the memo file itself read from ROOTFS.IMG on the card with `debugfs -R "dump /home/memos/memo002.wav ..."` (read only, our own image). The mic now delivers data to the app: `read returned 1024`, `recording stopped, 529408 bytes of audio` (16.5 s), `/proc/dsimic` `irq=265618 period_msgs=518`, `samples: lowest -15623 highest 14840` (no clipping at the 33.5 dB gain). Analysing the WAV: speech-level signal (RMS 1300 to 4000) for the first ~8 s, then a constant sample (912) for the last ~8 s, and `miccnt` ends as `0x0902`: bit 11 = the FIFO's overrun flag, bit 8 = empty. So the FIFO overran once (the ARM7 does SD requests inside its FIFO interrupt, and the memo was being written to the SD card while recording, plus autolog's every-10-s saves, so timer ticks were missed) and then stayed stopped. Also, 78% of the timer ticks found the FIFO empty and the signal consists of mostly pairs of equal samples: the FIFO delivers about 8.2 kHz, not the 32.7 kHz assumed (the codec's ADC clock is at its default while sound output is not on), so the effective sample rate is about 8 kHz, telephone quality; the file rate 16 kHz just repeats each sample. Fixes in w96d: (1) `arm7/microphone.c` restarts the FIFO (off, clear, on) when MICCNT shows the overrun flag or when 600 ticks in a row found it empty, and counts the restarts (`/proc/dsimic`: `fifo restarts N`); (2) dsmemo keeps the recording in memory (grows by 256 KB up to 4 MB, about 2 minutes, then stops with "time limit") and writes the WAV only when Stop is pressed ("saving..." shown), so the ARM7 sees no SD writes while the microphone runs. Later improvement option: put the ADC at the DAC rate with the libnds clock divider settings to get the full 16 or 32 kHz.

w96e (patch 0062): user report on w96d: recording worked all the time (no freeze: the memo, `memo003.wav`, read from the card with debugfs, has speech throughout and `fifo restarts 125` mean the FIFO was restarted whenever it overran), "but a constant high pitched whine, and my voice was hella deep". Analysis of the file: 645120 bytes = 20.16 s at the file's 16000 Hz, but the ARM7 timer ticked only 323861 times, about 10 s of real time at the actual tick rate: the recording was played back at half speed (voice an octave down). Reason: the ARM7 timer counts the 33.51 MHz bus clock, while the old `MIC_FREQ(rate)` formula (from the DS code, for the sound channel timers that run at 16.76 MHz) assumed half that, so the 16000 Hz tick was really 31.98 kHz. And the FIFO only delivers a new sample every other tick (its rate is 16364 Hz, bus clock / 2048: runs of exactly two equal samples dominate the file), so every sample was stored twice: a zero-order-hold image at the top of the band, visible as the spectrum's strongest peaks at 7.8 to 7.9 kHz (file rate), i.e. the whine. Fix: the ARM7 timer now ticks at bus clock / 1024 (32.7 kHz) only to poll, and each tick stores every sample the FIFO has exactly once (`dsi_timer_tick` / `dsi_push`), so the recording has the FIFO's own rate; the ARM9 driver offers 16364 Hz as the one capture rate on the DSi (so OSS programs get that rate from SNDCTL_DSP_SPEED and no resampler is needed) and dsmemo takes the rate the driver reports into the WAV header. The volume poll (an I2C read of a few ms inside the vblank interrupt) pauses while a recording runs; overrun restarts and stall restarts are counted separately in `/proc/dsimic`.

w96f (patch 0063): user report on w96e: "voice is better, the whine remains, a lot of graphical glitches still". The memo (`memo004.wav`, read from the card): the timing is right now (11.42 s of file for about 11.3 s of real time: 370685 ticks at 32.7 kHz; no repeated samples), the whine is a steady narrow tone at 7867 Hz in every second of the file, also in the quietest one (a fixed tone of the microphone path, not speech: it sits far above the voice band, near the 8182 Hz limit of the 16364 Hz sampling), and the samples reached -31912 and 32767 (clipping at the 33.5 dB gain). The overrun restarts are still 76 in 11 s (small clicks): the ARM7 is blocked for more than about a millisecond now and then by something other than the volume read (now paused during recording); a hardware NDMA transfer from the mic FIFO into the ring buffer would remove that dependency completely (not done yet). Fixes: dsmemo filters every recorded sample (one pole DC blocker, 33 tap windowed sinc low-pass at 3.5 kHz, integer Q14; applied offline to the real memo it takes the 7.7 to 8 kHz band down by 67 dB and keeps 99.8% of the 100 to 3000 Hz energy), and the codec gain is one step lower (27.5 dB). Also checked: the saved camera photos (BMP, read from the card) have normal colours and orientation, so the earlier streaky preview was the scene. The "graphical glitches" are not identified yet (the card log has nothing about them): asked the user where and what.

w96g (patch 0064): the "graphical glitches" the user reported, identified from their photo of the console after a recording: text lines drawn on the screen below the desktop taskbar: `-s: Unknown error 2` four times, and the `nds-sound: capture prepare / capture trigger / mic period message` lines, plus a blue block. Cause: the kernel's text console draws on the same screen as the desktop. Anything that prints to it (printk, or output from a background program) shows up over the desktop. Two sources: (1) my own diagnostic printks in the sound driver (not needed any more now that the microphone works: removed), (2) the background `autolog`: `savelog quiet` ran `/boot/cmp -s a b` every 10 s; this cmp build treats `-s` as a file name, so it printed `-s: Unknown error 2` (the message is cmp's own via strerror, not msh's: msh says "not found"). So the earlier "fix" of shipping cmp in the ROM did not remove the error; it had not been the missing file but the option. Now: savelog compares with plain `cmp a b > /dev/null 2>&1`, autolog and its savelog print nothing at all (redirected), `/boot/desktop` sets the kernel console log level to 1 (`/proc/sys/kernel/printk`, `dmesg -n 1`) before starting Nano-X, and the sound printks are gone. Everything stays available in dmesg and in the card log; only the console is quiet. The Nano-X screen driver does not switch the text console to graphics mode (`HAVETEXTMODE` is off for this driver build): a possible later cleanup so no console text can ever appear over the desktop.

w96h (patch 0065): user report on w96g: "I still see a tiny flickering box on the top screen, bottom left". The card log is clean (no console messages any more), and the newest memo (`memo006.wav`, 13.4 s) shows the fixes working: samples -9980 to 8975 (no clipping at the lower gain), and the 7.7 to 8 kHz tone is at 0.006% of the speech level after the filter. The box is the text console's blinking cursor: the Nano-X screen driver (`scr_fb.c`) had `HAVETEXTMODE 0` ("graphics only systems"), so it never told the kernel that the screen belongs to graphics, and the console kept drawing its cursor at its last cursor position (bottom left; the earlier photo showed it as a `-` at the end of the console text and a blue block). Now the DS driver sets `KDSETMODE KD_GRAPHICS` on /dev/tty0 when the desktop starts (a failure only prints a warning; the existing close path restores `KD_TEXT` when Nano-X ends, as before). dsgx already relies on the same switch on the text screen. The log level change from w96g stays as a second layer. Remaining known issue in the microphone: 159 FIFO overruns in 13 s (about 12 per second, each a short click): the ARM7 is blocked for more than a millisecond now and then; moving the FIFO to RAM with the hardware NDMA is the real fix.

w96i (patch 0066): user report on w96h: the box is gone ("better!"); "recording kinda whines a little, and skips a little; in the camera app you can see the refresh lines and it is still at 9 fps". The card (memo007, 9.5 s) shows: no tonal peaks left in the quiet moments, the noise floor is a low rumble (energy below 100 Hz is the largest by far), about one clear click per second (the mic FIFO overruns about 10 times a second, 96 in 9.5 s; the ARM7 code runs from its own fast memory, so the stalls come from interrupt work, not from bus contention; the real fix, a hardware NDMA from the mic FIFO, is still open), and the camera set-up works (`dscam: init ret 0 chip version 2280 error mask 0`). Changes: (1) voice memo recording: the DC blocker is now an 80 Hz high-pass (rumble); (2) playback: the DS sound channels hold each sample (no interpolation), so 16 kHz audio gets an image of the voice around 16 kHz (a whine); mono memos are now played at twice the rate with a linearly interpolated sample between neighbours (offline on the real memo the 12 to 16 kHz image drops from 3.3% to 0.55% of the voice level) and the end of a playback waits for the sound buffer to empty; (3) camera frame rate: a capture only starts at the beginning of a sensor frame, and the old code armed the next capture only when dscam asked for the next frame, after processing the previous one, so it always missed one: about two sensor frames per picture (9 fps). Now `NDSFB_CAM_FRAME` keeps two buffers: when a capture ends it arms the next one into the other buffer at once (sleeping for most of the measured frame time, then polling closely), and hands over the finished one; (4) camera lines: dscam loaded the full 98 KB frame into the 3D texture memory (bank D) every frame, which takes several milliseconds with the bank unavailable to the 3D engine while it draws. The preview is now a 2x2 averaged 128x96 copy (24 KB) in a 128x128 texture, loaded right after a screen refresh starts (`gx_vsync()`); photos still save the full 256x192 frame.

w96j (patch 0067): user report on w96i: "recording is almost there; counting to 10 I got to 7 and it skipped me saying 8 with whine cutting in. Camera app still flickers the viewport with black horizontal lines." Memo analysis (memo008.wav, 10.86 s, read from the card): no flat stretches, only four waveform discontinuities in the whole file; the largest, a jump of 3097 at 7.042 s (14 times the local scale), is exactly where the word was lost: the microphone FIFO overran while the ARM7 was busy and the restart threw away the audio of that stretch. `fifo restarts: overrun 95` in 10.9 s. The only thing known to keep the ARM7 busy for tens of milliseconds is a write to the SD card (the ARM7 does it inside its interrupt), and the test-time autolog saved the log every 10 seconds, the recording itself puts desktop.log lines into the log (so "changed" was true during it): dsmemo now creates /tmp/rec.lock while recording and `savelog quiet` skips its round while the file exists (a crashed dsmemo would leave it until the next boot, /tmp is RAM). The small overruns (about 9 a second, one or a few samples each) remain: the real fix is still the hardware NDMA from the mic FIFO. Camera lines: with the preview texture down to 24 KB the black lines were still there, so the timing is the point, not the size: while the CPU has VRAM bank D mapped (to write the texture) the 3D engine cannot read textures and every scanline it draws in that time has no texture, so it shows the black backdrop. A program cannot hit the 4 ms vertical blank gap (scheduling). Now `NDSFB_GX_TEXLOAD_VBL` (0x4e0b, up to 32 KB): the program hands the data to the kernel (staging buffer), and the vertical blank interrupt itself does the copy at the very start of the gap (32 bit writes, well under a millisecond for 24 KB); the call returns after it. dscam uses it (`gx_texture_load_vbl`), so every upload lands in the blank. The whine "cutting in": not identified in the file (no tonal peaks in the quiet parts); a restart after an overrun leaves a click and a short stretch of unfiltered start-up, which is a candidate; to be re-checked after the lock.

w96k (patch 0068): user report on w96j: "recording still has whine sometimes; the camera worked at first, then flipping caused the top screen to freeze, I had to force it off". Card: recording is much better (`fifo restarts: overrun 22` in three recordings, was about 9 per second: the log-saver pause works) and the newest memo (11.7 s) has no tonal whine in any of its 371 frames and only two tiny breaks, so the whine is not in the file: it is added on playback. Most likely the speaker path at 100% volume (level 31) with a weak signal (memo peaks are only about a third of full scale): the class D amplifier's own noise is audible. Memos are now normalised at load (loudest peak to about 85% of full scale, at most 8x); a PC listening test of the extracted file would settle it. The freeze: the log has the lines `dscam: init ret 0 chip version 2280 error mask 0 ...` and then `nxclient: lost connection to Nano-X server`, and no log save after that (the autolog saves every 10 s when something changed, so userland stopped within seconds). The key that was pressed is not known ("flipping": c = other camera, f = flip, m = mirror; only c touches the ARM7). Found in `arm7/dsicam.c`: when the I2C bus gets stuck busy, `cwait()` costs 200000 loop passes (20+ ms) per call, and the waits call apt_read() (8 retries, three waits each) up to 1500 times: minutes to hours on the ARM7, which also serves touch, SD and sound: the whole system seems frozen. Now: the first bus timeout sets `cam_dead` and everything else in that command returns at once (and the bus is reset with STOP|ERROR), retries are 3 (was 8), waits at most 400 tries (was 1500), the ARM9 gives up after 6 s. dscam logs `select camera`, `flip`, `mirror`, and the errno of failing frames into desktop.log, so the next freeze report has a trail (the log is saved every 10 s: a hang within 10 s of the key press can still lose the last lines).

w96l (patch 0069): user report on w96k: "listening to the previous recording it still whines at inconsistent times; Photos will not load if the camera is open; the camera hung when I pressed c to switch to the back camera last time, not this time". Card log: `dscam: select camera 1: ret 0 (errno 0) value 1 error mask 0` (the switch worked, no bus timeout), flips logged, then dozens of `dsgx: submit: Unknown error 22` and a `texture load` one: the 3D engine had been switched off under a running program. `NDSFB_GX_SETUP` was a plain on/off: when the Photos app (3D at that time) or any other 3D program called its set-up/quit, the other program's commands failed with EINVAL; the same thing may be what looked like a freeze of the top screen (the picture just stopped updating). Fixes: (1) the engine is reference counted in the kernel (it is switched off when the last user is done; a second user does not re-initialise it); (2) Photos now draws with ordinary Nano-X (192x144, nearest neighbour from the photo, in 16 row strips with GrArea, once per photo, redrawn on exposure) and no longer uses the 3D engine at all, so it works alongside the camera. Whine on playback: the log shows the listening was on the DS (`dsmemo: playback gain 2.48`), and the saved files are clean (no tonal bursts in 371 frames of memo001), so the cause is in the playback path. The ARM9 data cache is write back (the boot log says `D VIVT write-back cache`) and the ALSA driver never writes the sample buffer back: the sound hardware reads main memory, so samples the program just wrote can still be in the cache and the hardware plays the old contents of the buffer for a moment, at random, depending on when the lines get evicted. Now the buffer is written back (`dmac_flush_range`) at the start of the stream and in every period interrupt (the program is always more than a period ahead of the hardware). Also added mic diagnostics: `/proc/dsimic` shows `hi_nonsign` (FIFO words whose upper 16 bits are more than the sign of the lower half) and `lastraw`: if the FIFO words carry a second sample in the upper half we are throwing away half of the 32.7 kHz audio (and the unfiltered decimation would alias speech sibilants into the band: another possible source of inconsistent whine in the recording); a recording will tell.

w96m (patch 0070): user report on w96l (with a photo): "photos now does not work, mic recording does not work, playback still whines". Card log: `dsmemo: playback gain 2.48 ...` then `recording to memo002.wav ... no microphone data after 2 s`, `/proc/dsimic`: `fifo_full=0 fifo_empty=259455 period_msgs=0 ... stall 431`: the mic FIFO received nothing at all. The recording was the first thing after a playback in that boot; when a playback ends the ARM7 sound code (`dsivol_sound_power(0)`) cleared the I2S enable bit of SNDEXTCNT (0x04004700), and the microphone's ADC shares that clock. (Earlier tests recorded before any playback, so it worked.) Now the I2S output is left on, and `mic_start()` turns it on if it is off. Photos: the photo shows the camera preview (cam 1, still 9 fps) with the Photos window dragged half off the screen to the right, the picture cut at the screen edge and the label under the taskbar; the picture itself was drawn, so the 2D drawing works; what exactly "does not work" means is not clear (keys, taps, delete?). Changed: the picture is 160x120 (5/8 of the photo, the camera window's size) so the window is 164 wide, it opens at x 14, and it logs `dsgallery: photoNNN.bmp: loaded/cannot read (n)` into desktop.log. Camera frame rate: still 9 fps with the two buffer capture: either the sensor really delivers about 9 frames a second in this mode (the sensor registers give a frame of 704 lines of 843 pixel clocks) or the capture is still late; dscam now logs `N frames in 5 s, period avg/min/max ms` so the next card shows which (a constant period near 110 ms means the sensor limit). Playback whine remains unexplained: not in the files; added in the playback path or the speaker; candidates not yet tested: the amplifier at 100% volume (level 31) with normalised (loud) memos, the codec's touch scanning running while audio plays, DAC clipping. Needs the user's answer to: does the Sound test (pure tones) whine too, does it also whine on headphones, does the file played on the PC whine.

w96n (patch 0071): user report on w96m: "no whine over the sound test; mic works again; photos and camera do not work; Photos by itself shows a black image on all pictures. Once it works, let's move on." Card log: mic back (`fifo restarts: overrun 26`), `/proc/dsimic` `hi_nonsign=227455` with ~226247 non-empty ticks and `lastraw=00030004`: the upper 16 bits of every FIFO word are a second sample (3), next to the lower one (4), not a sign extension. The FIFO delivers 16364 words a second = 32728 samples a second (the I2S rate), and the ARM7 has been keeping only the lower half: an unfiltered decimation by two, which folds everything above 8.2 kHz (sibilants, noise, the tone near 7.9 kHz) into the voice band: the "whine at inconsistent times" in the recordings. Now both samples of each word are stored (order found from the data: for a smooth signal the right order has the smaller sum of differences between neighbours, measured over the first 2048 words: `/proc/dsimic` `ordLoFirst/ordHiFirst/order`), the capture rate offered by the driver is 32728 Hz, dsmemo reads 32 KB of buffer (32 fragments of 1 KB: the data rate doubled), filters (80 Hz high-pass, 49 tap windowed sinc low-pass at 4 kHz) and keeps every second sample: a clean 16364 Hz file. Camera: `dscam: 37 frames in 5 s, period avg 136 ms min 30 max 480`: irregular, not a clean sensor rate, so capture timing still loses frames at times (min 30 ms = a buffered frame returned at once, max 480 ms = a stall); not solved. Photos: all pictures black in the 2D viewer although the files load (`dsgallery: photo008.bmp: loaded (0)`; the files themselves are fine: mean byte values from 4 to 66 out of 255, some dark); reason not found (the same pixel path displayed a picture in w96l with the camera open). To get a working state quickly Photos is now a mode of dscam: the viewer uses the 3D texture path that worked in w95w, there is only one 3D user (the Start menu entry starts `dscam photos`; a second dscam does not start but signals the running one with SIGUSR1/SIGUSR2 to switch between viewer and camera and raises its window; the pid is in /tmp/dscam.pid); the camera (and its LED) is switched off while photos are shown and re-initialised when going back (key `v` toggles). dsgallery stays built but is not used.

w96n result (user report and card log): "there is whine, let us move on from it for now". Log: the camera preview is steady at 43 frames in 5 s (period avg 117 ms, min 90, max 140), so about 8.6 frames a second is the rate of the sensor's preview mode (frame length 704 lines of 843 pixel clocks set in the libnds sequence), not lost frames; camera switching (`select camera 1: ret 0 ... error mask 0`) and the photo viewer inside dscam (`viewer: photo010.bmp: loaded (0)`, browsing, back to the camera) work. Mic: `ordLoFirst=104730 ordHiFirst=190576 order=2`: the lower half of a FIFO word is the earlier sample; overruns 205 in two recordings. Status: voice memos, camera and photos are in a usable state; remaining known issues for later: whine still audible, the mic FIFO overruns (hardware NDMA from the mic FIFO would fix them), camera frame rate (sensor timing registers), Wi-Fi (needs a firmware file only found on the NAND, blocked by the never-read-NAND rule).

w97a (patch 0072): the Settings app, battery indicator and wallpapers (user request: "Settings app", then "I also want a battery indicator, and desktop wallpaper in settings to change"). Hardware facts (BlocksDS libnds `system.c`, zlib): the DSi power management chip (I2C 0x4A) has register 0x20 = battery (bits 0..3 level 0..15, bit 7 external power), 0x40 = volume buttons level 0..31 (already used), 0x41 = backlight level 0..4 (= levels 1..5; level 0 / backlight off is a different register, deliberately not offered). `NDS_SD_CMD_PM` (11) asks the ARM7 for the three registers and may write register 0x41 (value 0..4 only); the ARM9 side is `dsisd_pm()` in `dldi_c.c`, and `/proc/dsisettings` (volume.c) shows `battery=N charger=0|1 volume=N backlight=1..5 padgain=N` and accepts `backlight N` (1..5) and `padgain N` (1..8; the trackpad's pointer pixels per touch pixel, now a variable `ndspad_gain` in nds_ts.c). The ARM7 does the I2C reads inside its request handler (a few ms), so the desktop never reads it during a recording (/tmp/rec.lock). The Settings app (`dssettings`, Start > System > Settings) has rows Brightness, Pointer speed, Desktop (6 colours, 3 built in patterns Sky/Dusk/Grid, and every .bmp in /home/wallpapers and /home/photos), Time and Date (H+ M+ D+ Mo Y+: sets the system clock until power off), and an info block (battery %, volume %, free memory) and a Sound test button; keys up/down choose a row, left/right change it. Choices are written at once to `/home/settings.conf` (`brightness=`, `padgain=`, `desktop=C:n | P:n | F:/path`); `dssettings apply` (run by /boot/desktop-apps) restores brightness and pointer speed at every start; the desktop line is read by `dsdesk`. Why dsdesk draws the wallpaper: a background is a Nano-X pixmap, and a client's pixmaps are destroyed when it exits, so the long running desktop panel owns it; the Settings app signals it (SIGUSR1; pid in /tmp/dsdesk.pid) and dsdesk rebuilds the pixmap (a 256x192 picture drawn with GrArea in 16 row strips, set with GR_BACKGROUND_TOPLEFT; colours via the root window background). Finding along the way: for 16 bit data `GrArea` (MWPF_TRUECOLOR555) copies the value unchanged as the screen's own pixel, so the pixels must be DS pixels with bit 15 set; my 2D photo viewer (w96l/m) passed values without that bit, which are transparent: the black pictures, and the streaky picture in the w96l screenshot was the camera preview showing through. The battery indicator in the taskbar tray is a small battery picture filled to the level (green, yellow below 40%, red below 20%) with the percentage, a yellow bar when external power is connected, read about every 30 s.

ROM size (patch 0073): the first w97a build did not package: `ld: section .dsi [02400000 -> 02400003] overlaps section .text [02000000 -> 02404323]`. The ROM's kernel image (with the built in /boot file system) has to stay below 0x02400000 (4 MiB from the start of RAM) where the DSi header section sits; with the Settings app and the larger desktop panel it was 17 KB over. Freed: `dsgears` (the software 3D profiler, 360 KB, only for `/boot/gl profile`) and `dsgallery` (the old 2D photo viewer, replaced by the viewer in dscam) are no longer copied into /boot. The ROM is now 3.86 MB, about 340 KB below the limit; anything big added later has to make room the same way (candidates: dsbench, ntetris, landmine, dsgx). Lesson: a build that fails to package must stop the chain; this time the docs and the commit were written as if the ROM existed, and the card still had w96n until this fix.

w97b (patch 0074): a small 3D game, "3D Dodge" (`dsgame`, Start > Games), made on the existing library (dsgx.h, dsgx_win.h, the cube mesh of dsgx_demo.h). Design choices from what the platform gives: (1) input: the tty keyboard path delivers key presses (and their auto repeat) but no key releases, so held keys cannot be tracked: the ship moves one cell of a 3x3 grid per press (animated, about 60 ms) instead of with a held key; the d-pad, the touch arrow buttons and w a s d all work, and a tap in the window moves towards the tapped third/half; (2) fairness: every wall of blocks leaves one free cell, and that free cell is at most one cell (also diagonally) from the previous wall's, the other eight cells are blocked with a probability of 50%, so it can always be dodged by following the path; the gap between walls goes from 1.15 s down to 0.55 s and the speed from 16 to 40 units/s (+1 per wall passed); (3) speed of the engine: all moving parts are boxes (the recorded cube mesh, a push/translate/scale/draw/pop each, about 80 boxes a frame: tunnel strips on the floor and walls, the blocks, the ship), one hit ends the game, the score is the number of walls passed and the best score is kept in /home/dodge.best. ROM: 3.92 MB, about 270 KB below the 4 MiB limit.

## 3b-arcade. More games: `dsarcade` (w97c)

One program, `/boot/dsarcade <game>`, holds eight games (one binary shares the Nano-X and 3D code, about 105 KB in the ROM). The rules are plain C in `arc_logic.h`; `arc_test.c` checks them on a PC (`cc -O1 -o arc_test arc_test.c && ./arc_test`): 2048 merging and game over, every built-in Sokoban level solved by a search, Sudoku grids valid, mazes connected with exactly cells-1 passages, Tron and Breakout played by simple bots. Drawing and input are in `dsarcade.c`.

| Start menu | Game | Controls |
|---|---|---|
| Games > 3D Breakout | 3D window; 4 rows of bricks, 3 lives, speeds up each level | pointer over the window or left/right moves the paddle, Enter / tap launches; best in `/home/breakout.best` |
| Games > Tron | light cycles on a 22x22 grid against the computer, chase camera | left / right turn (queued, one turn per step) |
| Games > 3D Maze | first-person 7x7 maze in the 3D engine, minimap (m toggles it), spinning green cube = exit | up/down walk, left/right turn (a key press keeps moving for 0.35 s, because the console sends no key releases) |
| Puzzles > 2048 | swipe, tap a side of the board, or arrows; best in `/home/arcade2048.best` | n = new game |
| Puzzles > Sokoban | 6 levels, undo, restart; progress in `/home/sokoban.lvl` | arrows, tap towards a square, Space = undo, X / Y = previous / next level |
| Puzzles > Sudoku | new random puzzle (43 givens); clashes show in red | tap a cell then a digit button, or digits / arrows; X / Y change the digit |
| Puzzles > Life | 40x30 torus | tap or drag draws, Enter = run / pause, s = step, r = random, c = clear, X / Y = speed |
| Accessories > Paint | 80x60 canvas drawn at 2x, 12 colours, brush 1..3, flood fill | drag to draw; the picture is kept in `/home/paint.dat` |

The first-person maze uses the DS 3D chip (about 100 boxes a frame) instead of a software raycaster: it is simpler and looks better. FOV is wide (znear 0.7) so the walls need a 0.75 collision radius in 3 unit cells.

Verified: the game rules on a PC; the program builds and the ROM is 4.03 MB (limit 4 MiB). **Not yet run on the console**: drawing, input, frame rate, whether pointer motion events arrive while the touch screen is held (Paint and Life dragging depend on that).

## 3b-gb. Game Boy emulator: `dsgb` (w97d)

Start > Games > Game Boy. The core is [Peanut-GB](https://github.com/deltabeard/Peanut-GB) (`peanut_gb.h`, MIT licence, Mahyar Koshkouei, downloaded unchanged; sha256 `cf777706...cf728`), original Game Boy only. `dsgb_core.h` wraps it (ROM load, `.sav` file for cartridge RAM, four-shade palette, frame in DS pixels); `dsgb.c` is the desktop part; `dsgb_host.c` runs the same core on a PC (`cc -O2 -o dsgb_host dsgb_host.c && ./dsgb_host game.gb 120 0 out.ppm`). Fast LCD renderer, no sound, no Game Boy Color (a Color-only ROM is refused with a message; Color games that also run on the old Game Boy start in black and white).

**Your ROMs**: put games you own into `/home/roms` inside `linux/ROOTFS.IMG` with the card in the PC: `scripts/add-roms.sh game.gb other.gb` (uses debugfs; the image has about 400 MB free, a game is 32 KB to 2 MB). Saves are written next to the ROM as `NAME.sav`. A test ROM of my own (`dsgb_test.gb`, from `scripts/make-testrom.py`: four shades of stripes, the d-pad scrolls them) is already in the image.

**Buttons** (kernel, `button.c`): a program that holds `/proc/dskeys` open is in *game mode*: the driver stops giving the buttons to the input layer (no arrows, Enter or clicks reach the desktop) and the file reads as four hex digits with the raw state, presses *and releases*, which the keyboard path cannot give. Bits: 0 A, 1 B, 2 Select, 3 Start, 4 Right, 5 Left, 6 Up, 7 Down, 8 R, 9 L, 10 X, 11 Y. Closing the file (also when the program dies) ends game mode. In dsgb: A, B, Select, Start, d-pad are the Game Boy's; L + R together quit; X changes the palette; Y held = fast forward.

**Speed**: the first build (w97d) sent each picture through the Nano-X server (60 requests of 46 KB a second plus the server's page copies) and the whole desktop became unusable (user report). From w97e the picture is written straight into the screen memory on both pages (`/dev/fb0` mmap, the window's place is read when the window manager reports a move) and the program waits for the vertical blank once per frame (ioctl 0x4e07), so it uses no server time. When emulating a frame takes nearly a whole refresh, the next picture is skipped (the game keeps full speed). Every two seconds the status line under the picture (and the log) shows "N fps shown, M run, K slow". On the PC the test ROM takes 0.3 ms per frame; what a real game costs on the 134 MHz ARM9 is **not yet measured on the console**.

**Measured on the console (w97e, Pokemon Yellow, DSILOG.TXT)**: the game ran at 20-35 emulated frames per second (60 needed), only 2-20 pictures shown; the desktop was unusable. A frame costs about 30 ms on the ARM9; on a PC the same frame is 0.2 ms, so the core needs roughly 30 host instructions per Game Boy cycle, about twice what a 133 MHz Cortex-M0+ needs. w97f: `peanut_gb.h` is changed (marked "DSLinuxDSi change", `PEANUT_GB_DIRECT_ROM`): ROM, work RAM and VRAM accesses skip the callback and the switch (PC picture identical); the Nano-X server is asked only every 4th frame, the window position at most twice a second (moving a window sends a flood of events, each answered by two round trips); the game runs at `nice 6`; the log line now splits the time per frame into emulate / vblank wait / draw / other. Not enough by itself for 60 fps: the next steps are decided from that breakdown (smaller code for the 8 KB instruction cache, `-Os`, or running the game at 30 fps).

**w97f log (Pokemon Yellow)**: emulate 32 ms per frame (average of rendered and skipped frames), draw 2 ms, other 0.7 ms, 22 emulated and 11 shown frames per second. On the PC the profile is 63% picture rendering (`__gb_draw_line` 48%, my palette conversion 15%) and 27% CPU emulation, so a skipped frame is estimated at ~17 ms and a rendered frame at ~47 ms on the ARM9: even with no pictures at all the core is at the edge of 60 fps.

**w97g**: sound and a better clock. `dsgb_apu.h` is my own sound chip (two squares with sweep, wave, noise, length counters, envelopes, 512 Hz sequencer, DC filter; mono, 16 kHz, free running like minigb_apu), written as `audio_write`/`audio_read` for Peanut-GB's `ENABLE_SOUND`; output through OSS `/dev/dsp` (16 bit mono; the log prints the rate the driver gave, it must say 16000). On the PC the real game's music gives a sensible signal (silent title, then peaks of 8000-11000, no clipping), but I could not listen to it; whether it sounds right on the console is **unknown**. L alone mutes. New kernel ioctl `NDSFB_VBLCOUNT` (0x4e0c) returns the vertical blank counter; dsgb counts screen refreshes against emulated frames: on time -> make the picture, behind -> skip it (the game keeps speed), ahead -> wait. The log line now reads emulate / sound / draw / other / waits.

Next steps for speed, in order of expected gain: a fast picture renderer of my own replacing `__gb_draw_line` (tile rows through lookup tables, straight to DS pixels; checked pixel for pixel against Peanut-GB's on the PC), lazy timer/LCD bookkeeping in the CPU loop (also checkable by picture and LY reads), and compiling the core with `-Os` as a clean A/B test.

Verified: the core on a PC with my test ROM (four shades, d-pad scrolling, exact scroll distance); the program and the kernel change compile; the ROM is 4.11 MB (limit 4.19 MB, about 80 KB left). **Not yet run on the console**: the whole app, `/proc/dskeys`, drawing speed, with a real game.

## 3b-doom. DOOM (w97h)

`doom/` holds the port (see `doom/README.md`): doomgeneric (GPL v2) with my platform layer `doomgeneric_ds.c`, built as a separate program `dsdoom` (440 KB flat binary, 256 KB stack) that lives in `/home/doom` inside `ROOTFS.IMG` together with the shareware `doom1.wad` (md5 checked against the id Software v1.9 shareware value) and `default.cfg`; the ROM only gets the menu entry (Start > Games > DOOM). The 320x200 index picture is scaled to 256x192 through lookup tables and written into both screen pages (about 49,000 pixels a frame), the buttons come raw from `/proc/dskeys`, the clock is the vertical blank counter. Low detail and 9 screen blocks are set in `default.cfg`; the zone is 5 MB. No sound. Start + Select leaves at once, and the desktop picture saved at the start is put back.

**First try on the console: it did not start** (no log). The saved log showed only 6.4 MB free memory next to the desktop (`MemFree 6476 kB`, no-MMU, so the program, its 256 KB stack, a 5 MB zone and a 256 KB picture buffer had to fit in one piece), so the zone is now 4 MB (minimum 3), the picture buffer 64 KB, the stack 128 KB, and dsdoom logs to `/home/doom/dsdoom.log`. Second try: still nothing and no `dsdoom.log`, so the program never reached `main`. Cause (by reading the loader, not yet confirmed on the console): elf2flt makes binaries that run *in place* by default, which only works from the ROM's romfs; from the ext2 root image the loader cannot map the text, so `dsdoom` is now linked with `-r` (flag "load into RAM", header flags 0x3). Third try (w97i): the saved log (one snapshot at 58 s uptime, no BINFMT line for dsdoom, so no `exec` happened by then) does not say whether the menu was used. Important: **DSLinux can write only `DSILOG.TXT` on the card**, so `/home/doom/dsdoom.log` is not readable from the image on the PC; w97i adds two things to the ROM: the desktop logs every menu launch (`dsdesk: started X` or `dsdesk: cannot start X: reason`) to `/tmp/desktop.log`, and `/boot/logbody` (Save log, and the 10 s autolog) includes `/home/doom/dsdoom.log`. Both end up in `DSILOG.TXT`. **Found (log from w97i, `Data abort` twice in dmesg, pc mapped with addr2line)**: the program was loaded (a 1 MB block at 0x02600000, so memory was not the problem) but crashed in `__uClibc_init`, before `main`: I had linked with the toolchain's own libc and headers, whose startup code is not position independent, instead of through `tools/ucfront-gcc` (which uses the tree's uClibc, the same as every other program). `doom/build.sh` now compiles and links through ucfront with `ROOTDIR`, `CONFIG_LIBCDIR=uClibc`; `__uClibc_init` now addresses its data through the GOT register (`[sl, r3]`). **Fourth try (log from w97i + the ucfront build)**: DOOM now starts (`Doom Generic 0.1`, `Z_Init`), but dies in the zone allocation: `Allocation of length 4198400 ... failed` (the zone of 4 MB plus the C library's 4 KB header is one page block too many: the kernel hands out 2^n blocks and the biggest free one is 4 MB), and then the kernel itself oopses (`fput(NULL)` in `do_mmap_pgoff`'s error path in `mm/nommu.c`, hit by any failed anonymous mapping; fixed, patch 0084). Doom's zone is now `N MiB - 32 KB` so 4 MiB fits a 4 MiB block, minimum 2 MiB. Not yet run on the console. Unknowns: whether 5 MB of contiguous memory is available next to the desktop (the log would say "Unable to allocate"), the frame rate on the 134 MHz ARM9 (expect single digits to low teens; if too slow the next steps are a smaller window, `screenblocks` 7, and fixing the renderer hot spots), and whether the scaling and button mapping feel right.

## 3c. Faster ARM9 clock: nothing to do (measured on the console)
`CONFIG_NDS_DSI_FASTCPU` writes `SCFG_CLK` (0x04004004) bit 0 early in boot. On the console the t-fast ROM printed `NDS: ARM9 SCFG_CLK 0001 -> 0001: 134 MHz requested and accepted`: the register already held `0001` before the write, so the loader had
already put the ARM9 at 134 MHz and the option changes nothing. All DSi-mode boots show `66.76 BogoMIPS (lpj=333824)`: with the ARM946E's delay loop taking about 4 cycles per iteration (sub plus a taken branch), 33.4 M iterations per second means roughly 134 MHz.
The normal `r` ROM's saved log (`DSILOG.TXT`) shows the identical `lpj=333824`, so the t-fast write changed nothing. The step from lpj to 134 MHz is an inference from the cycle count, not a direct measurement. The ARM7 has no comparable switch as far as I know. The option stays in the tree (default off); `t-fast` ROMs are in `out/dsi-mode/old/t-fast-noop/`.



## 3e. Wi-Fi: plan and first probe (w97j)

Research (BlocksDS dswifi, MIT; libnds `gpio.h`): the DSi has an NTR (DS) Wi-Fi chip and a TWL (Atheros) chip behind one antenna, selected by `REG_GPIO_WIFI` (0x04004C04, bit 8 = NTR). The DS chip is open/WEP only, 802.11b rates; libnds notes that DWM-W024 boards (the DSi XL / LL) need TWL mode and dsibrew lists only an Atheros on that board, so **the easy route (reuse the DS driver) may not exist on this XL**. `/proc/dsiwifi` (w97j, also in Save log) answers it: the ARM7 reads the DS chip ID register (0x04808000) before and after switching GPIO_WIFI to NTR mode, and dumps the first registers of the TWL SDIO controller (0x04004A00); nothing in it waits on the hardware. **Result (w97j log, user's DSi XL): `NTR chip id: before=0000 after_ntr_switch=c340`, `gpio_wifi=0100` already set by the loader, power bit off until the driver sets it: the DS chip is there and answers.** The easy route works. A DS chip answers an ID like 0x1440 / 0xC340; 0x0000 / 0xFFFF means no chip. If there is none the way is the Atheros route (BlocksDS `arm7/twl/` code, MIT, about 130 KB; BlocksDS does not upload firmware, it relies on the system having loaded it, to be checked on the console).

### 3e-2. DS Wi-Fi switched on in the DSi build (w97k)

`CONFIG_NDS_WIFI=y` for the DSi product. ARM7 (`arm7/wifi.c`): `wifi_open()` first selects the DS chip (`GPIO_WIFI` bit 8) and then powers the block; every wait on the chip is bounded (`Wifi_BBRead`, `Wifi_RFWrite`, the receive loop, the interrupt loop), the status-LED SPI writes are skipped on the DSi. ARM9 (`drivers/net/wireless/nds.c`): all waits for the ARM7 have a 3 s timeout, a fixed fake MAC is used if the ARM7 does not answer. The network interface is called `nds` (not eth0). Userland was already in the root image (original DSLinux): `iwconfig`, `iwlist`, `wnc`, `udhcpc`, `dropbear`, `dropbearkey`, `inetd`, `ping`, `/etc/rc.d/network`; `/etc/rc.conf` takes `essid`, `wepkey`, `ip`, `enable_network_on_boot`. `scripts/set-wifi.sh ESSID [wepkey]` writes `/etc/rc.conf` and an `inetd.conf` that starts Dropbear (the host key is generated once on the console with `dropbearkey`). The DS chip joins only open or WEP networks (2.4 GHz, 802.11b rates). Not yet run on the console.

w97k result (user): `ifconfig nds up` freezes the whole console; the card log (saved every 10 s through the ARM7) stops at 95 s uptime, so the ARM7 stopped too and left no trace. w97l: `wifi_open()` writes numbered steps (1..16, 99 = done) into `stats[WIFI_STATS_HW_1DC]` of the shared array; `nds_open()` on the ARM9 watches it for 6 s and prints `nds wifi: ARM7 step N` and `chip irq rounds / ie / if` with KERN_EMERG (shown over the desktop; a photo of the screen after the freeze shows the last step, or a runaway interrupt as growing counters). Steps: 1 entered, 2/3 chip select, 4 power on, 5 reset, 6 stopped, 7 shut down, 8 chip RAM cleared, 9 woken up, 10 MAC set, 11 RF, 12 baseband, 13/14 channel, 15/16 start.

### Root image corruption after the w97k freeze (2026-11-12)

Symptom: "ERROR: No such user root!" on the text console before the first prompt. Cause: `ROOTFS.IMG` was damaged: one inode-table block (inodes 6657-6664: `/etc/passwd`, `/etc/hosts`, `/home/memos` and `/home/photos`' neighbours) held text instead of inodes, so `/etc/passwd` read as "Invalid argument" and the autologin program could not find root. The ext2 image is never unmounted (power-off, reset, freeze), and the `ifconfig nds up` freeze of w97k hit while it was being written. Repair: backup in `out/rootfs-backup/`, `e2fsck -fy`, `/etc/passwd` and `/etc/hosts` are recreated by `rc.common` at the next boot, the three recovered memo files (memo002-004) were put back into a new `/home/memos`. New: `scripts/rootfs-check.sh` (read-only check, `-y` repairs); `add-roms.sh`, `set-wifi.sh` and `doom/install.sh` now refuse to write to an image with errors. Rule: after a freeze or hard reset, run `scripts/rootfs-check.sh -y` before writing anything to the image.

### w97l result and two bugs found (2026-11-12)

**1. Wi-Fi freeze** (photo of the console after `ifconfig nds up`): `nds wifi: ARM7 step 1`, then nothing: `irq rounds 0, ie 0000 if 0000`. The ARM7 hung between step 1 and step 2 of `wifi_open()`: the first statement there reads the DS power chip over SPI (`power_read(POWER_CONTROL)`, argument of the LED write), and on the DSi that SPI read never finishes (`WAIT_FOR_NOT_BUSY` has no limit). My `wifi_led_write()` skipped the write on the DSi but still evaluated its argument. Now a macro: the argument is not evaluated on the DSi (patch 0089).

**2. Root image corruption, root cause** (the "No such user root!" error, and the corruption that came back after the first repair): the damaged block (group 13's first inode-table block, inodes 6657..: `/etc/passwd`, `/etc/hosts` created by `rc.common` at every first boot) held **log text**: its first 512 bytes equal a sector of DSILOG.TXT. `dsisd_transfer()` (the ext2 root device) copied the sector data into the shared request block *before* `sd_request()` took `sd_mutex`, and copied read data out *after* releasing it; the log writer (`savelog`, at boot and every 10 s) takes the mutex properly, so it could overwrite the shared buffer in between: log text was written to ext2 sectors, ext2 data to the log, and reads could return the wrong data. The race is old; the longer log (more sectors) and the boot-time file creation made it hit. Fix: hold the mutex from filling the buffer to copying the answer out (patch 0088). This is probably also the cause of the "Invalid argument" reads of passwd. After the fix the image should stop getting damaged; keep running `scripts/rootfs-check.sh` after any freeze.

### w97m result and w97n: Wi-Fi works up to the radio; Start > Network (2026-11-12)

w97m (user, photo): the bring-up reaches `step 99`, chip interrupt rounds grow slowly (20 per second, ie 40bb, if c840 = timer and beacon interrupts), no freeze, the user's scan found networks. w97n: **Start > Network** with Wi-Fi scan / Wi-Fi connect / Wi-Fi status / SSH server (scripts `/boot/wifi-*`, each started in an `nxterm` window that stays open): connect asks the network name and WEP key the first time and keeps them in `/home/wifi.conf` (`rm` it to change), then `iwconfig nds essid/key`, `udhcpc -n -q -i nds`; the SSH server script makes the Dropbear host key once and starts `dropbear` (key login only if `/home/.ssh/authorized_keys` exists). Save log (and the 10 s autolog) now also records `ifconfig nds`, `iwconfig nds`, `/proc/net/route` and `/proc/net/arp` in `DSILOG.TXT`, so a session can be read from the card. Dropbear 0.48 is old: from this PC use `ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 root@IP` (client OpenSSH 10.6 still has all of these); keys must be RSA. Not yet run on the console beyond the bring-up.

w97n result (card log, user: "nothing happens when clicking wifi"): `dsdesk: started /boot/nxterm /boot/wifi-scan` was logged twice, so the menu worked, but no window stayed: `nxterm` runs its argument with `execvp()`, uClibc's `execvp()` does not fall back to the shell for a script without a binary header (the kernel has no `#!` support here either: scripts only run because the shell interprets them), so the child failed at once and the window closed. w97o: dsdesk starts `nxterm /bin/sh script`. The same log shows the Wi-Fi interface is healthy: `nds` with the console's own MAC address (Nintendo A4:C0:E1:...), no errors; `iwconfig` warns that the driver speaks wireless extensions v19 and the tool v17 ("some things may be broken": `iwlist nds scan` did work for the user).

### w97p: organisation, UI and speed (2026-11-12)

- **Workflow:** `scripts/release.sh TAG [-t file...] [-o desc] [-n]` replaces the hand routine (make in the container, DSi packaging, the 4 MiB check,
  archiving the previous ROM, image check, copy to the card with checksum, removal of older ROMs from the card root); `scripts/card.sh` holds the card's
  mount point for all card scripts; build logs live in `out/logs/`.
- **Start menu:** every entry has a 9x9 icon (terminal, folder, page, clock, camera, speaker, signal bars, tiles, game pad, gear, power), groups too.
  Each level is drawn on a pixmap and copied in one request: drawn on the window it appeared entry by entry (a user photo caught "Shut down" at the
  top of a half drawn menu). Colours are shared with the taskbar to stay within the 16 graphics contexts of `w95.h`.
- **Wi-Fi tray:** `SIOCGIFFLAGS` / `SIOCGIFADDR` on `nds` every ~3 s (no server round trip): no icon when down, grey bars when up without an address,
  black bars when online.
- **Game Boy renderer:** background and window are drawn a tile row at a time: the two bit planes are spread through a table into a 16 bit word of
  2 bit colours, and a whole tile row becomes two table loads and two 4 byte stores (palette table rebuilt only when the palette changes).
  PC check: identical frames at 600/1500/3000/5000/8000 frames of Pokemon Yellow with scripted input and in the test ROM; drawing 0.53 s -> 0.14 s
  per 6000 frames in the profile, the whole core about 30% faster. (Pitfall found on the way: the PC harness writes the game's `.sav`, so two runs
  only compare when it is deleted in between.)
- **Docs:** README rewritten (current status, workflow, scripts), `docs/USER-GUIDE.md` (controls, every program, Wi-Fi/SSH, card scripts, after a
  freeze), `docs/DSI-NOTES.md` (everything learned about the DSi for future development).
- Not yet run on the console: all of the above (w97p).

### w97p result, the menu bug, and a PC test bed (w97q)

User report (w97p): hovering any entry other than Exit desktop / Shut down made those two move away. Cause: `struct level` kept the entries'
positions in `int ytop[8]`, while the Start menu had grown to 10 entries (Puzzles, Network): `ytop[8]` and `ytop[9]` overwrote the next level's
`list` and `n`, so as soon as a group opened, Exit desktop got a pointer as its position and Shut down the number 8 (drawn at the top: an earlier
photo had caught "Shut down" as the first entry). Fix: `MAXITEMS 16` and a bound in `open_level()` (patch 0093).

The user asked for testing before the DS. melonDS's DSi mode needs the user's console dumps (never read here) and there is no virtual X display on
this PC, so a test bed was built instead: `testbed/` (see the README). The same Microwindows tree compiled natively (`testbed/config.host`: frame
buffer driver, 15 bit colour, no mouse or keyboard driver), `fbshim.so` (LD_PRELOAD) answers the framebuffer ioctls for a 98304 byte file,
`nxctl` injects pointer and key events (`GrInjectPointerEvent`, `GrInjectKeyboardEvent`) and converts the framebuffer file to a picture. It
reproduced the bug with the old dsdesk (Shut down gone after hovering a few groups) and showed the fixed one correct, before w97q went to the card.

### w97q results and the terminal (w97r)

User report (w97q): the Network entries opened an empty terminal. `nxterm` ignored the program it was given: on Linux it always started
`/bin/sh` from `term_init()`, whatever came on its command line. Checked in the test bed (which now also builds nxterm, with Unix 98 ptys, and
maps `/boot/...` under `DSDESK_ROOT` so the desktop's menu entries start the PC builds and the real boot scripts): Wi-Fi status opened a
terminal that ran the script and showed its output.

The user also asked to update nxterm ("looks outdated, maybe get bash working?"). nxterm was a VT52 terminal (wterm, 1990s) that swallowed
every ANSI sequence, so busybox's line editing (cursor moves, erase to end of line) and colours displayed wrongly. It was rewritten (patch
0094): a VT100/ANSI subset (CUU/CUD/CUF/CUB, CUP, ED, EL, ICH, DCH, ECH, IL, DL, SU/SD, DECSTBM scroll regions, SGR 16 colours with bold as bright
and reverse, DECTCEM, DSR/CPR and DA replies, deferred wrap), the screen as cells (correct redraw on expose), a 200 line scrollback on Page
Up / Page Down (X / Y), whole-screen scrolls drawn with one copy request, the program's name as the title, `TERM=vt100` and a coloured prompt.
Bash itself was not added: it needs `fork()`, which a no-MMU system cannot provide; busybox `msh` (vfork) already has history, tab completion
and prompt escapes. Test bed: history recall, an insertion in the middle of a recalled line, `ls --color`, wrapping, scrolling 60 lines and the
scrollback all correct. Not yet run on the console.

### Wi-Fi window, tray pictures and /proc/dswifi (w97s)

User report (w97r): Network > Wi-Fi scan showed no networks. The log had `nds` up with 544 packets received but nothing from `iwlist`. Two
suspects: busybox-era `iwlist` speaks wireless extensions 17 against the driver's 19 (the scan result layout differs), and `nds_get_scan`
read the AP list the ARM7 had just written without invalidating the ARM9 data cache over it. Fix (patch 0095): `/proc/dswifi` in the
driver starts a scan, waits for it (3 s at most), asks for the AP list, invalidates the cache, prints `bssid channel open|wep signal name` per
network; `nds_get_scan` invalidates too. `/boot/wifi-scan` now prints that list.

The user's ideas, done in the same build:
- Tray: battery and volume are pictures only (battery filled to the level, volume with 0-3 sound waves or a red cross when muted); the Wi-Fi
  bars are always shown (white = off, grey = on without address, black = online). Pointing at a picture or tapping it shows a tooltip with
  the percentage, or the network and address. One sunken field holds the three pictures and the clock.
- `dsnet`, the Wi-Fi window (Start > Network > Wi-Fi, or a tap on the Wi-Fi bars): Wi-Fi On/Off, Scan (switches Wi-Fi on first), the list
  strongest first with signal bars, padlock for WEP, saved / online; Connect asks for a WEP key the first time, runs `iwconfig` and
  `udhcpc`, and on success saves the network in `/home/wifi.known` and `/home/wifi.conf`; Forget. The Network menu is now Wi-Fi, Wi-Fi status,
  SSH server (`wifi-connect` stays in /boot for the terminal).
- ROM size: the first w97s build was 15 KB over 4 MiB, because `dsnet` as a program of its own (65 KB) carries its own copy of the Nano-X
  client library. It is now linked into `dssettings` and started as `dssettings wifi` (the way `dsarcade` holds several games): about 12 KB.
Test bed (fake AP list in `testbed/aps.txt`, commands printed instead of run): tray tooltips, the tap opening the window, scan list with the
duplicate name merged, WEP key entry, connect commands (`iwconfig nds key 's:abcde'`), saved files, Forget, On/Off all as intended.
Not yet run on the console.

### w97s results and joining a network (w97t)

User test of w97s with a phone hotspot ("Nothing_Phone_2", open): the scan now lists networks (the `/proc/dswifi` fix works), but connecting
gave no address. Log: ESSID set, key off, no route, nothing saved in `/home/wifi.known`. "TX packets 0" in ifconfig is meaningless: with
`REPORT_RAW_PACKET_STATS` the driver reports `TXRAWPACKETS`, which the ARM7 never counts; TX bytes (710) were real. RX frames: 76.
Cause found in the ARM7 code: `wifi_try_to_associate()` sends one authentication frame when the network is chosen (or when a beacon of it
first arrives) and never retries. A lost frame or answer, or a frame sent while a scan still hops channels, leaves the console unjoined
for good; DHCP then has nobody to talk to. Fix (patch 0096):
- ARM7 `wifi_join_tick()`, from the vblank interrupt: while a network is chosen but not joined, and no scan runs, it resends the
  authentication (or, once authenticated, the association) every second.
- Counters for the join: frames sent (auth, assoc), the access point's last answers (status codes), channels, in four new stats words.
  `/proc/dswifistat` prints them with the state flags named, without scanning; the log includes it, the Wi-Fi window's steps
  (`/tmp/dsnet.log`) and udhcpc's output.
- The Wi-Fi window sets the key before the network name (choosing the network starts the login with the key mode of that moment), waits
  up to 12 s for "associated" showing the tries, says "No answer from X" / "X refused..." when it fails, and only then runs DHCP.
- WPA networks (the ARM7 already noticed them) are marked "WPA" in the list and refused with a message instead of a hopeless attempt.
Still open: WEP always uses shared-key authentication (many WEP routers want open authentication).

### w97t results: no answer to the login (w97u diagnostics)

w97t on the console, phone hotspot "Nothing_Phone_2" (open): `/proc/dswifistat` showed `state 0x0001 up`, `auth 48 assoc 0 status -1 -1`,
channel 6 = wanted 6, 460 frames received. The retries work (48 authentication frames over about 45 s), but no authentication answer
ever came back. Either the phone does not receive what the DS chip sends (the chip transmits only 802.11b, 1-2 Mbit/s; many phone hotspots
require 802.11g rates), or the frames never leave the chip, or answers are dropped. Reading the code: queued frames are started only from the
beacon-time (TBTT) interrupt, which writes the transmit request register (0xAE).
w97u adds counters to tell these apart (patch 0097): transmit-end and transmit-error interrupts, beacon-time interrupts, the transmit status
register, frames from the chosen access point, frames addressed to this console, authentication frames seen. And `/proc/dswifi` gives each
network's rate class from its beacon: `b` (1-2 Mbit/s basic rates), `b11` (5.5/11 basic), `g` (an 802.11g rate is required: the DS chip can
never join). The Wi-Fi window tags `g` networks "11g".

### w97u results: frames "sent", never answered; send at once (w97v)

w97u on the console, same hotspot: `auth 40`, `tx-done 40 tx-err 0`, `tbtt 379` (about one every 100 ms over the attempt), `rx from-ap 156`
(the hotspot's beacons, sent at 1 Mbit/s, so the hotspot does use 802.11b), `to-us 0`, `auth-frames 0`. The chip reports every frame as
transmitted, the hotspot is heard, and nothing at all comes back to the console. The driver never started a transmission itself: the
`W_TXREQ` writes (0xAE) were commented out ("delay for beacon") and the beacon-time interrupt started queued frames, i.e. each frame left
exactly when the access point beacons, which is the likeliest reason it was never received. w97v (patch 0098) starts every frame at once,
as BlocksDS dswifi does, and records the transmit buffer's header after each send (the chip writes the result there) and the chip's
counters 0x1B0-0x1DE (0x1C0 = transmit errors) in `/proc/dswifistat`. Listening with the PC's Wi-Fi is not possible here: it is the PC's
only network link and sits on a 5 GHz channel.

### w97v results: the hotspot was not in the scan (w97x)

User: "didn't even see the hotspot this time". Log: Wi-Fi switched on twice, 161 frames received from other networks during the scans, no
network chosen, nothing sent. w97v changed only how frames are sent, not receiving or scanning, so the hotspot was most likely not on
2.4 GHz at that moment (Android switches an unused hotspot off after a while, and some phones move it to 5 GHz). The log did not say
what the scan found: the Wi-Fi window now writes every scanned network to `/tmp/dsnet.log` (patch 0099), which the log includes.
w97w was built with a compile error in that change (a brace lost while moving a function): the top-level make goes on and the old
`dssettings` was packaged, and release.sh only printed the error. release.sh now stops on any compile error. w97x is the corrected build.
The send-at-once change (w97v) is still untested against an access point.

### w97x results and the channel table bug (w97y)

w97x, hotspot now on channel 11: scan listed only two networks (the hotspot, open, rates `b11`; a hidden WPA network on channel 6), all
with signal 0. Joining: `auth 33`, `tx-done 33`, transmit header word 0 = 1 (sent), and `rx from-ap 0`: tuned to channel 11 the console
heard nothing at all from the hotspot, while on channel 6 (w97u) it had heard 156 of its beacons. So the radio was not really on the
chosen channel. With the user's permission the Wi-Fi calibration section of their firmware dump (`dsfirmware.bin`, read only, nothing
copied into the repository) was decoded: RF type 3, 41 initial RF bytes, then the channel table: a count byte (2 baseband entries:
registers 0x1E, 0x26), then 2 RF entries (RF register 1, the coarse frequency 0x4B-0x4D by channel; RF register 2, the fine part).
DSLinux's `Wifi_SetChannel` walked it with `i <= flash[0x43]` baseband entries (3): it wrote RF entry 0's values into baseband register 1,
then RF register 2 and garbage (0xFF) into RF register 0xFF, and never RF register 1. dswifi reads the count byte. Fixed (patch 0100).
This explains every Wi-Fi symptom so far: few networks in scans, the channel 6 hotspot heard only sometimes, nothing on channel 11, and no
access point ever hearing the console.

### Wi-Fi works (w97y); the "freeze" after ping (w97z)

User: "it was able to see, connect, and ping google.com!" The w97y log: joined Nothing_Phone_2 on channel 6 (`state up associated
authenticated`, auth 3, assoc 4, both answered with status 0), DHCP lease 10.53.221.108 with gateway and DNS, the gateway's MAC in the ARP
table, `rx from-ap 1044`, `to-us 48`. The channel table fix (patch 0100) was the cause of all earlier failures. **Wi-Fi is verified on the
console** (open network; WEP and SSH not yet tried).
Then "after pinging, it froze". The log (written after it, so the kernel was alive): no fault in dmesg, three `nxclient: lost connection to
Nano-X server`, i.e. the graphics server ended and the screen kept its last picture. `ping` with no count never ends, the touch keyboard could
not type Ctrl+C (its Ctrl key is released at once), and nano-X upstream quits when both mouse buttons are down, which on the DSi are R and L
(L+R also quits the Game Boy emulator): the likeliest story is L+R to stop the ping. The desktop log could not confirm it: busybox `msh`
appends with open + seek instead of `O_APPEND`, so the programs logging there at once overwrote each other's lines. w97z (patch 0101):
Ctrl/Alt latch on the touch keyboard (tap Ctrl, then C), no L+R quit in nano-X, `>>` with `O_APPEND` in msh.

### w97z log: hotspot not seen, and a kernel log full of faults (w98a)

User: "I can't connect to my hotspot anymore, doesn't show up". The w97z log: three scans, each listing the same 8 networks on channels 1
and 11 (all WPA), no Nothing_Phone_2. The Wi-Fi code is the one that connected in w97y and the radio clearly scans, so the hotspot was most
likely not on the air on 2.4 GHz (Android turns an idle hotspot off, picks a new channel each time and can move it to 5 GHz). Every network
showed signal 0: the ARM7 keeps the last 8 readings per network and never fills in the `rssi` field. Now the average is shown.
The whole kernel log (160 lines, the boot messages pushed out) was `do_translation_fault? : arch/arm/mm/fault.c 374`: on this no-MMU kernel
a prefetch abort (a jump to an address no MPU region allows) went to a stub that printed that line and returned, so the program re-ran the
bad jump for ever, at full speed, with no name in the message. Which program did it is unknown (Doom, Game Boy, 3D gears, the maze and the
Wi-Fi window had been started). w98a (patch 0102): a prefetch abort prints the program, pid, pc, lr, sp and code start once and stops the
program with SIGSEGV. Scan dwell 150 -> 200 ms per channel.

### w98a: joined, no address; the access point sends the console away (w98b)

w98a log (the hotspot now named "Nothing", channel 6, open, signal 167 of the scan's range 22-167 now that signals are averaged): both
connects joined, then udhcpc sent 3 discovers with no lease; at log time the state was `up` only (auth 4, assoc 2, tx-done 7 since the
last connect). In the ARM7 code only a **deauthentication** from the access point leads to exactly that state (it clears "associated" and
"authenticated" and logs in again), so the hotspot accepted the console and then sent it away. Its reason code was thrown away, and
**disassociation** frames were ignored entirely (the console would keep sending as if joined). w98b (patch 0103): a join event log in
`/proc/dswifistat` (`events: auth-sent(0)@12 auth-answer(0)@13 assoc-sent ... DEAUTH(reason)@... first-data-tx ...`), disassociation
handled (logged, association requested again), the re-login after a deauthentication uses the network's key mode instead of "none", and
the Wi-Fi window logs the join state when DHCP fails and retries once after re-joining. The reason code will say why the phone sends the
console away (e.g. 7 = data from a station it does not consider associated, 4 = inactivity).

### w98b: an address, but a lossy link; the association rate list (w98c)

w98b log: connected on the second try (10.53.221.108, gateway and DNS, the gateway's MAC in the ARP table) but `ping google.com` failed.
DHCP needed three udhcpc runs (11 discovers, 4 selects before one lease), one `DEAUTH(1)` (reason "unspecified") followed by a successful
re-login, data tx 35 / rx 50, the chip's receive-error counters climbing: the link was joined but lost most frames. Cause found in
`Wifi_SendAssocPacket`: to put 1 and 2 Mbit/s in front of the access point's basic rates it shifted the array **from the front**
(`for (j = 1; j < 16; j++) r[j] = r[j - 1]`), which copies one entry over all of them (dswifi shifts from the end). With this hotspot the
request offered 15 rates, "1, 2, 5.5 x 13" (a rates element may hold 8), and so told the phone the console takes 5.5 Mbit/s, which the DS
chip cannot receive. Fixed (patch 0104): the first request offers 1 and 2 Mbit/s only; after a refusal the next ones add the AP's basic
rates (dswifi's list). The event log shows the offer: `assoc-sent(2)` = 1-2 only, `assoc-sent(260+)` = with the basic rates.

### w98c results

Join: `assoc-sent(2)` (1-2 Mbit/s only) was refused with status **18** ("basic rates not supported": the hotspot requires 5.5/11 Mbit/s as
basic rates), then `assoc-sent(260)` (4 rates, with its basic rates) was accepted, as designed. DHCP got a lease on the **first** udhcpc
run (3 discovers, 2 selects; w98b needed three runs), gateway in the ARP table, data tx 19 / rx 25, no deauthentication. The phone's own
MAC changes per hotspot session (the gateway's MAC differs from w98b). Whether the ping then worked is not in the log (the terminal's
output is not saved). The hotspot insisting on 5.5/11 Mbit/s as basic rates means it may still send to the console at rates the DS chip
cannot receive, relying on its retries at lower rates.

### The DSi's own Wi-Fi chip: first bring-up test (w98d)

The user asked for the Atheros chip (WPA2). Step 0 of docs/ATHEROS-PLAN.md: BlocksDS dswifi (MIT) has a complete driver for it and,
importantly, does not upload firmware: it relies on the firmware the System Menu left in the chip. Whether that firmware is still there
when DSLinux runs (after Unlaunch, which skips the System Menu) decides how big the job is. w98d (patch 0105) adds a bring-up test on the
ARM7 (`arm7/twlwifi.c`): antenna, clock, power, the second SDIO controller, card initialisation, manufacturer, chip ID, the firmware flag,
boot ROM version, and if firmware is there, starting it and waiting for "ready". Run from Start > Network > DSi Wi-Fi test (or
`echo 1 > /proc/dsiwifi2`), only on request; the result is in the card log. ARM7 program 41.9 KB of 64 KB, ROM 29 KB free.

### Programs out of the ROM (w98e)

User: "put all programs non essential into SD and not load in ROM". The ROM's /boot now holds only nano-X, nanowm, dsdesk, nxterm,
dssettings (Settings, the Wi-Fi window, settings applied at boot) and cmp (savelog), plus the scripts. dsarcade, dsgb, dsmemo, dsgl3d, dscam,
dsgame, ntetris, landmine, dsbench, dsgx, dsplay, dsnotes, dsfiles (and nxclock) run from ROOTFS.IMG as /usr/bin/<name>; every reference
was changed (menu, Settings' Sound test, Files -> Notes, gl script, the Bench quick button in the kernel). Programs on ext2 cannot run in
place, so `scripts/install-apps.sh` copies this build's binaries, sets the flat binary's Load-to-RAM flag (`flthdr -r`, in the build
container) and writes them into the image with debugfs, then checks the sizes; `release.sh` runs it after copying the ROM. Checked on a
throwaway 256 MB image (all 14 installed, flag `0x3 Load-to-Ram Has-PIC-GOT`). ROM: 828 KB free (was 29 KB). w98e was built while the card
was in the console: copy the ROM and run install-apps.sh when the card is back. Not yet run on the console.

### w98d DSi Wi-Fi test result; w98e/w98f on the card

The w98d test log: `dsisd: ARM7 did not answer (cmd 13)` after 15 s, then `dsiwifi2: step 1, chip 0, ...`, and several log sections
(network, dswifistat, dsiwifi2) missing because the log's own writes timed out while the ARM7 was busy. The ARM7 handles SD requests in
its interrupt handler, so nothing else ran meanwhile; it recovered later (the log was written). "Step 1" cannot be trusted: the ARM9 never
cleared the request block, so after the timeout it may have read an earlier request's leftovers; the ARM7 may equally have been busy
with something else first (the test script switches the DS Wi-Fi off just before). w98f (patch 0107): the block is cleared first, step 1
is split into four (antenna, RTC clock output, power chip, SCFG_WL as a 16-bit write), the ARM9 waits 30 s, and the ARM7 keeps the
results so a later read of /proc/dsiwifi2 shows where the run really ended ("run finished" / "NOT finished").
w98f is on the card together with the programs moved out of the ROM (w98e): install-apps.sh wrote all 14 into ROOTFS.IMG /usr/bin; the
image checks clean.

### w98f result: no step reported; live progress (w98g)

w98f: `dsisd: ARM7 did not answer (cmd 13)` twice, each followed by "step 0", and log sections missing again. With the block now cleared
first, "step 0" meant the ARM7 had not copied anything back: w98f's run wrote its results into its own copy and handed them over only at the
end, so a run that hangs or takes over 30 s shows nothing (a design mistake). w98g (patch 0108): the run writes each step straight into the
request block, and the ARM9 checks it every second while waiting and logs `dsiwifi2: ARM7 at step N after M s`, so the kernel log shows the
timeline even if the ARM7 never finishes.
User (w98f): the games and Notes start from the card. **Programs running from ROOTFS.IMG verified on the console** (w98e/w98f layout).

### w98g timeline: the run is lost at the RTC write (w98h)

w98g's kernel log: `dsiwifi2: ARM7 at step 2 after 0 s`, then nothing until the 30 s limit, and a later report request was answered
normally with an empty result ("NOT finished"). So the ARM7 kept working but never came back into the run: its context was lost at step 2,
the two RTC FOUT writes (w98d's "step 1" contained the same writes). The RTC routine waits with `swiDelay`, a BIOS call, and the run is
interrupt-handler code; if the BIOS lets an interrupt in there, the nested entry overwrites the return address and execution continues
elsewhere. A pending interrupt is likely at that moment: the antenna has just been switched away from the DS chip, whose interrupt is still
enabled. w98h (patch 0109): the run writes the RTC itself with plain delay loops, and masks the DS Wi-Fi interrupt for the duration
(acknowledged and restored at the end). Lesson for the ARM7: no BIOS calls in code that runs from the interrupt handler.

### First contact with the Atheros chip; firmware upload (w98i)

w98h's run finished: **4-bit SDIO bus, card already initialised, manufacturer 0x02010271, chip 0x0D000000 = AR6013, reset cause 2, boot
ROM (BMI) version 0x23000024, firmware loaded: no.** So the RTC fix worked, and after Unlaunch the chip has no firmware: DSLinux must
upload it. The DSi's firmware title HNCA (from the user's SDNAND backup, read with permission) was decoded: after the signature and SHA-1,
an entry table at 0xA0 (2 entries; layout confirmed by dsibrew "WiFi Firmware") points at two blobs, both matching their SHA-1. Blob 1 is
for the AR6002 (boot ROM 0x20000188), blob 2 for AR6013 and AR6014 with boot ROM 0x23000024. A blob header lists its parts: type 1 (LZ
compressed, 0x2EEC bytes) for 0x524C00 (the start address at +0x40), type 2 (0xFC0) for 0x524C00, type 4 (0x312, the data patch) for
0x53F040, type 5 (0x38, executed) for 0x527000; host interest 0x520000 at +0x58. dswifi's disabled upload code uses the same addresses
for A/C/D. Read with the AR6000 host interest layout: +0x18 hi_dset_list_head, +0x54 hi_board_data, +0x58 hi_board_data_initialized,
+0x6C hi_mbox_io_block_sz, +0x74 hi_mbox_isr_yield_limit.
w98i (patch 0110) uploads it: the ARM7 keeps the chip in BMI with the antenna on it and offers BMI operations; the ARM9 (new
`arch/arm/mach-nds/dsiwifi.c`) takes the file through `/proc/dsiwifi2fw`, picks the blob by chip ID and boot ROM version, writes parts 2
and 5, executes 5, LZ-streams part 1 (then closes the stream), sets the app start, writes part 4 and points +0x18 at it, starts the
firmware and waits for +0x58, then gives the antenna back; every step is logged in `/proc/dsiwifi2`. `scripts/add-dsi-wifi-fw.sh`
copies the user's own HNCA into ROOTFS.IMG as `/usr/lib/firmware/dsi-wifi.bin` (checked against its SHA-1 sums; never in the repo or ROM);
done for this card. dswifi also wrote part 2 again after the firmware ("is D needed?"); left out for now.

### w98i: upload stops at "execute" (w98j)

w98i's upload log: the right blob, parts 2 (4032 bytes) and 5 (56 bytes) written, then `BMI_EXECUTE` of part 5 at 0x927000 got no
answer within about 2 s, so the rest was skipped (and the log's "status" number was garbage: a format with one field too many). The
writes had used dswifi's 0x1F0/0x1F8-byte chunks from its disabled code; Linux's AR6000 drivers limit a BMI message to 256 bytes
(BMI_DATASZ_MAX) and take a mailbox credit before each command. An overflowing boot ROM buffer would get the byte stream out of step and
swallow the execute command, which fits. w98j (patch 0111): 240-byte messages, a credit wait before each command (mailbox 0 counter
0x450; a miss is counted and logged, not fatal), a read-back of each part's first 32 bytes compared with the file, and if execute still gets
no answer, a fresh run (reset into the boot ROM) and a second try at the part's plain address 0x527000.

### w98j: writes verified, execute silent; the part table read wrongly (w98k)

w98j: every part's read-back matched the file and no command went without a mailbox credit, so the BMI channel works, but `BMI_EXECUTE`
got no answer at 0x927000 nor, after a reset, at 0x527000. Looking at the bytes: part 5 (56 bytes) is configuration words (0x525000,
0x51FE00, ...), part 4 begins with `36 61 00` (Xtensa `entry a1, 48`), part 2 is a list of 20-byte entries whose "next" pointers
(0x53F054, 0x53F068, ...) are right only if it sits at 0x53F040. So each part entry is **offset, size, type, load address**; the decoder had
taken the address one field too early and executed data. Corrected: type 1 LZ firmware "A" for 0x524C00, type 2 dataset "B" for
0x53F040, type 4 code "C" for 0x527000, type 5 configuration "D" for 0x524C00 - exactly dswifi's A/B/C/D addresses (its B differs, for
another firmware version). The AR6002 blob agrees (code part starts with `entry`, dataset at 0x52D944 pointing at 0x52D958, next to
Linux ar6000's 0x52D6C8). w98k (patch 0112) uploads in dswifi's order: D, C, execute C, A (LZ), D again, B, hi_dset_list_head = B.

### The Atheros firmware runs (w98k)

w98k on the console, all steps: D and C written and read back identical, **execute C answered 0**, the 12012-byte LZ firmware streamed
to 0x524C00, D written again and B (dataset) written and read back identical, hi_dset_list_head set, BMI done: **ready 1**. Board data
(EEPROM) at 0x520E00, version 0x609A0202 (dswifi's comment mentions 0x609C0202). The first word waiting in mailbox 0 is `00 02 10 00`:
an HTC header (endpoint 0, 16-byte payload), the firmware's HTC "ready" message. **Steps 1-3 of docs/ATHEROS-PLAN.md are verified on the
console:** DSLinux brings up the DSi's own Wi-Fi chip, uploads the console's own firmware and starts it. Next: step 4, HTC (read the ready
message, connect the WMI control and data services) and WMI (the ready event with the MAC address, then a scan).

### Step 4: HTC, WMI and a first scan (w98l)

w98l (patch 0113) continues after "ready": it reads the waiting HTC ready message, connects the five HTC services with dswifi's bytes,
sends setup complete, waits for the WMI ready event (the chip's MAC address) and the regulatory domain event, writes the WMI protocol
version (3) where host interest +0 points, sets scan parameters, turns the firmware's debug log off, then scans channels 1-13 one at a time
as dswifi does (channel, scan parameters, BSS filter "all", start scan, BSS info events until scan complete). Each BSS info event gives
channel, RSSI, SNR, BSSID and the beacon, from which the SSID and the security (open, WEP from the privacy bit, WPA from the vendor element,
WPA2 from the RSN element) are read. The ARM7 moves mailbox packets byte by byte (CMD52), slow but simple; block transfers can come with
the data path.

### Step 4 verified: the DSi's own chip scans (w98l), all channels (w98m)

w98l on the console: HTC ready (10 credits of 1544 bytes), all five services connected (status 0, endpoints 1-5), **WMI ready with the MAC
a4:c0:e1:..** (Nintendo's prefix), regulatory domain 0x80000348 (840 = USA), and a scan that found **6 networks including WPA2 ones**
(WorkNet WPA2, GuestNet open, two hidden WPA2) with RSSI -58 to -72 dBm and SNR 23-37. The first scan of the DSi's own Wi-Fi chip under
DSLinux. Flaw: every network on channel 1, and "set channel params" was refused twice (WMI command error 1): the per-channel scan with phy
mode 11ag (dswifi's value; the AR6013 is 2.4 GHz only) never left channel 1. w98m (patch 0114): one scan over all channels, phy mode
11g, empty channel list.
w98m: no command refused, 8 networks (incl. ATTDtsFwBq, WPA2, -87 dBm, SNR 8, which the DS chip had also found on channel 1), but again all
on channel 1 and no "scan complete" event within 6 s. The DS chip saw networks on channels 6 and 11 at the same place, so the scan still
stays on channel 1 or its later results are not read. Unknown WMI events are not logged yet; the next build (step 5) logs them.

### Step 5: wlan0 (w98n)

w98n (patch 0115) makes the Atheros chip a network interface. `wlan0` is registered at boot and stays down; `ifconfig wlan0 up` runs
the firmware upload, HTC/WMI and a scan, then keeps the chip up with the antenna on it, and starts a kernel thread that does every ARM7
request: outgoing frames become mailbox data packets on endpoint 2 (dswifi's 24-byte header: 0, destination, source, big-endian length,
LLC/SNAP, EtherType), and every 20 ms up to 8 received packets are handled (WMI events; data packets become Ethernet frames for the stack).
`echo connect [name] > /proc/dsiwifi2` joins an open network from the scan (the strongest one when no name is given) with dswifi's command
sequence; the connect event turns the carrier on. Unknown WMI events are now logged (for the scan's channel question). The test (Start >
Network > DSi Wi-Fi test) does all of it and then DHCP and pings, with the output in the card log. gcc 4.0.4 crashed ("unrecognizable
insn") on upload() until its part tables were made static.

### w98n: CONNECTED (w98o)

w98n on the console, test run twice: each time the firmware upload, HTC/WMI and scan (9 and 11 networks), then `connect: GuestNet,
channel 1` and the firmware's **WMI connect event: CONNECTED on channel 1** (the open network GuestNet), followed by event 0x1008
(neighbour report). **The DSi's own Wi-Fi chip joined a network under DSLinux.** The card log lost the block that held the DHCP and ping
results (again a contiguous part missing). Some scan entries were garbled (SNR 253, RSSI 158). w98o (patch 0116): the test writes its
output and a copy of dmesg into /home (read from the image with debugfs), scan entries with SNR < 16 or > 127 are dropped.

### w98o: not connected this time (w98p)

w98o's own output (read from /home/wlan0-test.log in the image, which worked): upload, HTC/WMI and scan as before, `connect: GuestNet,
channel 1, signal -58`, then no packet at all from the firmware, no connect event, no error; DHCP sent three discovers into a link
without carrier (0 packets out), ping: network unreachable. w98n had connected twice with the same commands. w98p (patch 0117) adds a
firmware health check (failure state at host interest +0x04 every 3 s), the count and the last 8 received mailbox packets in
/proc/dsiwifi2, a connect retry after 15 s without an event, and the test waits up to 40 s for CONNECTED before DHCP.

### w98p: connected late, data flowing (w98q)

w98p's /home/wlan0-test.log: the firmware stayed healthy (failure state 0); the connect event came only after the third connect command,
past the test's 40 s wait, so DHCP ran on a link without carrier. 291 mailbox packets had arrived, mostly BSS info events (227 before
the first retry): the scan never stops reporting beacons, and the byte-by-byte receive lagged behind so far that the connect was delayed.
After the connect, data packets came in (33 passed to the network stack; the ring shows endpoint 2 packets). w98q (patch 0118): BSS filter
"none" after the scan and during the connect, up to 16 packets per round without pausing while more wait, the test waits up to 90 s and
retries DHCP once. gcc 4.0.4 crashed on upload() again until the helpers it calls were made noinline.

### Step 5 verified: wlan0 on the internet through the DSi's own Wi-Fi chip (w98q)

w98q on the console (/home/wlan0-test.log): connected to the open network GuestNet after about 50 s (again on the third connect command),
**DHCP lease 192.168.1.2** on the first try (gateway 192.168.1.1, two DNS servers), **`ping 8.8.8.8`: 2 of 3 replies, 20-30 ms**, **`ping
google.com`: resolved to 172.253.156.102, 2 of 3 replies, 20 ms**; 144 packets in, 13 out, firmware failure state 0. The BSS report flood
is gone (only 5 packets between the connect retries). Still open: the connect is answered only after the third command (~35 s), the first
ping of each run is lost (ARP), packets move byte by byte (CMD52), and only open networks (WPA2 is step 6).

### Step 6: WPA2-PSK built (w98r, w98s; not yet tried on the console)

Patch 0119. `arch/arm/mach-nds/dsiwpa.c` holds SHA-1, HMAC-SHA1, PBKDF2 (the PMK from password and network name), the PTK PRF, the
EAPOL MIC, AES-128 and the RFC 3394 key unwrap. On the PC (`testbed/wpa_test.sh`, the same file built with DSIWPA_HOST) all 7 test
vectors pass: SHA-1, HMAC, two PBKDF2 vectors (IEEE 802.11i), the PTK, AES and the key unwrap. gcc 4.0.4 crashed on `wpa_pmk` three
times ("unrecognizable insn", a byte store with -mswp-byte-writes) until it worked in 32-bit words. Because the old compiler is the risk,
`scripts/build-wpatest.sh` builds the same test with the kernel's options for the DSi and puts it in the image as `/usr/bin/wpatest`;
the DSi Wi-Fi test runs it first and logs PASS / FAIL per vector. `dsiwifi.c`: `echo "psk PASS" > /proc/dsiwifi2` (8-63 characters,
never logged, wiped with the PMK and PTK at wlan0 down); a WPA2 network is joined with auth mode WPA2-PSK, pairwise AES and the group
cipher from its RSN element; EAPOL message 1 gets message 2 (our nonce, RSN element), message 3 is checked (MIC), its GTK unwrapped
with the KEK and answered with message 4, then both keys go to the firmware (ADD_CIPHER_KEY). No data is sent before the keys are in.
