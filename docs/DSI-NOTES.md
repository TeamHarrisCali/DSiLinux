# What we know about the DSi (XL), for future development

Everything learned while bringing DSLinux up on a **DSi XL in DSi mode** (launched by TWiLight Menu++ through Unlaunch), in one place.
Each fact says how we know it: **measured** (seen on this console: photo, user report or the card log), **code** (it is what our working code
does, so it works on the console), **docs** (from BlocksDS/libnds, dswifi, GBATEK or dsibrew, not separately checked) or **inferred**.
Build numbers (w95x, w97m...) point into [STAGE3.md](STAGE3.md), where the story behind each fact is.
The console's own layout (boot chain, NAND, installed titles, firmware chip, BIOS), read from the user's dumps, is in
[DSI-INTERNALS.md](DSI-INTERNALS.md).

## 1. Starting in DSi mode

- A plain DS header runs in DS mode: 4 MB of RAM (mirrored, which once fooled a "16 MB works" test), locked SD, DS touch. The ROM header must
  say DSi: unit code 3 (DSi only) or 2 (DS or DSi; the loader then needs "DSi mode"). The 2008 DSLinux `ndstool` cannot write DSi headers;
  `scripts/make-dsimode.sh` repacks with BlocksDS's `ndstool` (`-uc 3 -p 1`). **measured**
- Header app-flags bit 0 (`APPFLAGS=1`) puts the touch/sound chip into DSi mode. **measured**
- The ARM9 section that is loaded at `0x02400000` ("DSi9") forces the kernel image plus the romfs to end below `0x02400000`: **the ROM has a 4 MiB
  ceiling** for kernel + all `/boot` programs. Since w98e only the essentials are in /boot; the other programs run from ROOTFS.IMG as
  /usr/bin/<name>, written there by `scripts/install-apps.sh` with the Load-to-RAM flag (828 KB of ROM free). **measured** (w98f: games and Notes start from the card) `scripts/release.sh` prints what is left (51 KB at w97p). Big programs belong in `ROOTFS.IMG`. **measured**
- The loader already runs the ARM9 at 134 MHz (`SCFG_CLK` 0x04004004 bit 0 reads 1 before we touch it; BogoMIPS 66.76, lpj 333824). **measured**
- `SCFG_EXT` (0x04004008) as left by the loader: ARM9 `93fffb06`, ARM7 `93fffb07`. **measured**

## 2. CPUs, memory, caches

- ARM9: ARM946E-S at 134 MHz, no FPU (soft float), 8 KB instruction cache, 4 KB data cache, MPU (no MMU). Our MPU set-up: region 1 = main RAM
  16 MB, cached and buffered; DTCM 16 KB moved to `0x02FF0000` (the top 64 KB of RAM is reserved for it, kernel `DRAM_SIZE 0x00FF0000`);
  ITCM 32 KB at 0 holds the vectors. **code**
- ARM7: about 33 MHz, 64 KB IWRAM; our ARM7 program is linked at `0x03800000` (34 KB at w97m) and does SD, touch, sound, microphone,
  camera I2C, power chip, buttons X/Y and Wi-Fi. It is interrupt driven: **anything slow or stuck on the ARM7 stops the SD card, touch and sound**
  (a stuck ARM7 = "the whole DSi froze"). Every wait on hardware there must be bounded. **measured** (w97k/w97l Wi-Fi freezes)
- RAM: 16 MB at `0x02000000`. `MemTotal` about 12.3 MB after the kernel; about 6.4 MB free with the desktop running. **measured**
- No MMU: every allocation is one physically contiguous block from the buddy allocator, rounded **up to a power of two** (an mmap of 4 MiB plus
  a 4 KB header needs an 8 MiB block). Large programs fail when no block of the needed order is free, even with plenty of total free memory;
  `/proc/buddyinfo` style free lists show it ("DMA: ... 1*2048kB 1*4096kB"). Size allocations as 2^n minus a little (DOOM's zone is
  `N MiB - 32 KB`). **measured** (DOOM)
- The 2.6.14 nommu code oopsed on a failed anonymous mmap (`fput(NULL)`): fixed (patch 0084). **measured**
- Timers: the kernel runs at HZ=100, so `gettimeofday` moves in **10 ms steps**. For frame timing use the vertical blank counter
  (`ioctl(fb, 0x4e0c)`, 59.83 Hz). **measured**

## 3. Programs and the userland

- Programs are elf2flt flat binaries. In the ROM (romfs) they run in place. **From the ext2 image they must be linked with `-elf2flt="-r"`**
  (load into RAM), or they do not start at all. Stack size is fixed at link time (`-s 131072`). **measured** (DOOM)
- Always compile and link through `/work/tools/ucfront-gcc arm-linux-elf-gcc` with `ROOTDIR=/work CONFIG_LIBCDIR=uClibc CONFIG_DEFAULTS_LIBC_UCLIBC=y`:
  plain `arm-linux-elf-gcc` links the toolchain's own libc, whose start-up is not position independent, and the program dies with a data abort in
  `__uClibc_init`. **measured**
- The kernel has no `#!` support here and uClibc's `execvp()` does not fall back to the shell, so **a script started from C must be run as
  `/bin/sh script`** (nxterm with a script argument opened and closed at once). **measured** (w97n)
- **No bash:** bash needs `fork()` (a copy of the process), which a system without an MMU cannot do; busybox's `msh` is built for `vfork()`. It already
  has line editing, history (saved), tab completion and a prompt with `\u \h \w \W \$ \e \[ \]` (cmdedit), which work with the rewritten `nxterm` (w97r);
  the old VT52 nxterm dropped the ANSI sequences cmdedit sends, so editing looked broken. **code/inferred**
- busybox `msh` opened `>>` files with open + seek to the end instead of `O_APPEND`: several programs appending to `/tmp/desktop.log` at
  once overwrote each other's lines ("tarted /boot/dssettings wifi"). Fixed in w97z (patch 0101). **measured**
- nano-X (upstream) quit the whole server when both mouse buttons were down: on the DSi those are R and L. The desktop vanished and the
  screen kept its last picture, which looks like a freeze (w97y, after a `ping` the user could not stop). Removed in w97z. **measured/inferred**
- The touch keyboard is one finger: Ctrl and Alt now latch until the next key, so Ctrl+C can be typed (w97z). **code**
- The shell is `msh`: plain commands only. `{ ...; } > file` is ignored, `a && b &` runs in the foreground, `cmp -s` takes `-s` as a file name,
  `/usr/bin/cat` must be called by its full path in boot scripts, and there is no `tail`. busybox `grep` has `-E` on the console's build. **measured**
- The compiler is gcc 4.0.4 (2008). It does not define the endianness macros newer code expects (`PEANUT_GB_IS_LITTLE_ENDIAN` had to be set). **measured**
- A **prefetch abort** (jump to an address no MPU region allows) used to loop for ever, filling dmesg with `do_translation_fault? :
  arch/arm/mm/fault.c 374` and naming no program. Since w98a it prints `Prefetch abort: <program> (pid) pc= lr= sp= code at` once and kills
  the program; `pc - code at` is the offset for `addr2line`. **code**
- "Killed" from the shell with no other message usually means a fault: look for `Data abort` in `dmesg` and map `pc` with `addr2line` on the
  `.gdb` file (load base + offset). **measured**

## 4. Display

- `/dev/fb0` is the **top screen**, 256x192, 16 bits. Pixel = DS RGB555 with **red in the low bits** and **bit 15 = opaque**; a pixel with bit 15 clear
  shows the 3D layer behind it. **measured**
- The framebuffer has two pages (virtual height 512): page 0 at offset 0, page 1 at `256 * line_length`. The Nano-X server draws on the hidden page
  and flips (`NDSFB_FLIP` 0x4e01, `_ASYNC` 0x4e02, `_WAIT` 0x4e03), copying only the drawn rectangles. A program that writes the screen directly
  must write **both pages**. **code**
- Other framebuffer ioctls: hardware pointer sprite `0x4e04`, 3D engine set-up `0x4e05`, command submit `0x4e06`, wait for vblank `0x4e07`,
  texture load `0x4e08` (and at the next vblank `0x4e0b`), camera command `0x4e09`, camera frame `0x4e0a`, vblank counter `0x4e0c`. **code**
- The 3D engine (GX) draws on BG0 behind the framebuffer: 60 fps with edge smoothing and textures in a desktop window; a window painted magenta
  becomes transparent. The kernel refcounts the engine (one 3D program at a time in practice). **measured**
- Nano-X costs: about **1 ms per request** and about **40 ms per round trip** (anything that waits for an answer, e.g. `GrGetWindowInfo`).
  Draw with few requests (one GC per colour, filled rectangles), draw menus on a pixmap and copy once, and **never stream per-frame pictures
  through the server** (the Game Boy emulator at 60 frames of 46 KB made the whole desktop unusable; it now writes the screen memory directly). **measured**
- `GrArea(..., MWPF_TRUECOLOR555)` copies raw DS pixels: set bit 15 or the picture is invisible. **measured**
- Moving any window floods `CHLD_UPDATE` events to every program that listens on the root window. **measured**

## 5. Input

- Buttons A, B, Select, Start, d-pad, R, L are in `REG_KEYINPUT` (0x04000130, bit 0..9, 0 = pressed), polled at every vblank; X and Y come from the
  ARM7 through the FIFO. **code**
- The keyboard path (tty) gives presses with auto-repeat but **no releases**. d-pad = arrow keys, A = Enter, B = Space, X/Y = Page Up/Down,
  R/L = left/right mouse button. **measured**
- `/proc/dskeys` (patch 0076): while a program holds it open, the desktop does not see the buttons and the file reads as 4 hex digits of raw state
  (bit 0 A ... 9 L, 10 X, 11 Y, 1 = held), presses and releases. **measured**
- The bottom screen is the touch input: top part = trackpad (drag moves the pointer, tap clicks), bottom part = on-screen keyboard. In DSi mode the
  touch controller is read through the codec registers (BlocksDS method). **measured**

## 6. SD card

- Internal SD (SDHC) on the TMIO controller at `0x04004800`, driven by the ARM7 (polling driver after profi200's `dsi_sdmmc`). The NAND is never
  selected (only SD port 0). **measured**
- The ARM7 reads the FAT32 itself, keeps the sector ranges of `ROOTFS.IMG` and `DSILOG.TXT` (it accepts up to 255 extents for the image) and refuses
  every other sector. **measured**
- The ARM9 and ARM7 share one request block (`struct nds_sd_block`, data buffer included). **The mutex must be held from filling the buffer to
  copying the answer out**: holding it only around the request let the log writer swap the data, and log text landed in ext2 inode tables
  (patch 0088). **measured**
- Non-SD helpers ride on the same block: power chip (`NDS_SD_CMD_PM`), microphone counters, camera, power-off, Wi-Fi probe. **code**
- The ext2 image is never unmounted cleanly (freezes, resets, power-off), so check it with `scripts/rootfs-check.sh` after any freeze. Files written
  on the console do reach the image. **measured**

## 7. Sound and microphone

- Output through the DS sound channels (kernel ALSA `nds-sound.c`, OSS `/dev/dsp`, 16 bit mono or stereo), mixed at about 32.7 kHz with no
  interpolation. In DSi mode the ARM7 also switches on the amplifier and the I2S output (`SNDEXTCNT` 0x04004700), which must stay on (the microphone
  FIFO also stops when it is cleared). **measured**
- Volume: the DSi volume buttons are read from the power chip register 0x40 over I2C (0..31) and applied to the codec. **measured**
- Microphone: codec ADC plus `MICCNT` (0x04004600) / `MICDATA` (0x04004604), FIFO of 32 bit words that each hold **two** 16 bit samples (the low half is
  the earlier one), 32728 samples/s (capture offers only that rate). Long ARM7 work (SD transfers) causes FIFO overruns (small clicks); the real fix
  would be NDMA from the FIFO. Mic gain setting 2 of 0..3 (27.5 dB); 33.5 dB clipped speech. A whine remains in recordings. **measured**

## 8. Power chip, buttons on the side, battery

- The power management chip is on the DSi's I2C bus (`I2CDATA` 0x04004500, `I2CCNT` 0x04004501), device `0x4A`: register `0x20` battery level (0..15
  in our reading) and charger bit, `0x40` volume, `0x41` backlight (0..4; never set it to "off"). **measured**
- **The DS-style SPI power chip does not answer on the DSi**: `power_read()` over the DS SPI bus waits forever (it froze the ARM7 when the old Wi-Fi
  code blinked the LED). Power-off works through the ARM7's own write to the power chip with bounded waits. **measured**

## 9. Cameras

- Two Aptina MT9V113 sensors on I2C (`0x7A` inner, `0x78` outer), set up by the ARM7 with BlocksDS's sequence and bounded waits; the ARM9 reads
  256x192 RGB555 frames through the camera interface and NDMA. About **8.6 frames per second** (period 117 ms), which is the sensor mode's own rate.
  Frames are shown as a 3D texture; uploading in the vblank interrupt removed tearing lines. **measured**

## 10. Wi-Fi

- The DSi has two Wi-Fi chips behind one antenna, selected by `GPIO_WIFI` (0x04004C04, **bit 8 = DS/NTR chip**). The loader leaves it at `0x0100`. **measured**
- **The DSi XL's board (DWM-W024) does have a working DS chip**: after powering the block (`POWCNT2` 0x04000304 bit 1) the DS chip's ID register
  (0x04808000) reads **`0xC340`**; unpowered it reads 0. **measured** (w97j probe, `/proc/dsiwifi`)
- **Wi-Fi works on the console (w97y):** scan, join an open network (phone hotspot, 2.4 GHz), DHCP address, DNS, `ping google.com`.
  `/proc/dswifistat` after joining: `state up associated authenticated`, auth 3, assoc 4 (status 0 0), rx from-ap 1044, to-us 48. **measured**
- DSLinux's original DS Wi-Fi driver works once the DS-only LED write is gone: radio up, interrupts at a normal rate, scans find networks, MAC from the
  firmware flash (`A4:C0:E1:...`, Nintendo). Interface name `nds`. Open or WEP networks only, 802.11b. `WIFIWAITCNT` (0x04000206) = 0x30. **measured** (w97m)
- `iwconfig` (wireless extensions 17) warns about the driver's version 19. One manual `iwlist nds scan` listed networks (w97m), but from the
  Network menu (w97r) the scan printed nothing. Two suspects: the WE17/WE19 scan-result format mismatch, and `nds_get_scan` reading the ARM7's AP
  list without invalidating the ARM9's data cache after the ARM7 filled it. **measured** (the empty scan) / **inferred** (the cause)
- Hence `/proc/dswifi` (w97s): reading it starts a scan, waits for it, asks the ARM7 for its AP list, invalidates the cache over the list and prints
  one line per network, `bssid channel open|wep signal name`. The Wi-Fi window (`dsnet.c`, inside `dssettings wifi`) and `/boot/wifi-scan` use it; no wireless-extensions
  tool is involved. **built, not yet run on the console**
- **Channel tuning (RF type 3, which this DSi XL's firmware reports at 0x40):** after the 0x42 initial RF bytes at 0xCE comes one byte
  with the number of baseband entries, then those entries, then 0x43 RF entries; each entry is a register number plus 14 per-channel
  values. Here: 2 baseband entries (registers 0x1E, 0x26), 2 RF entries (RF registers 1 = coarse frequency, 2 = fine). DSLinux's original
  loop took 0x43 + 1 as the baseband count, so RF register 1 was never set per channel: the radio did not really tune, scans found few
  networks, and no access point heard the console. Fixed in w97y (as dswifi reads it). **read from the user's firmware dump** (the fix is
  not yet run on the console)
- **Association rates:** the DS chip sends and receives only 1 and 2 Mbit/s. DSLinux's association request mangled the rate list (an
  array shift in the wrong direction: "1, 2, 5.5 x 13"), claiming 5.5 Mbit/s; the link then lost most frames (w98b). Since w98c the
  request offers 1 and 2 Mbit/s only, and the access point's basic rates only after a refusal. **code** (not yet run on the console)
- Transmissions: the original driver started queued frames only from the beacon-time interrupt (the `W_TXREQ` 0xAE writes were commented
  out); since w97v they start at once, as in dswifi. **built**
- A plan for driving the Atheros chip (WPA2, 802.11g) is in [ATHEROS-PLAN.md](ATHEROS-PLAN.md) (not started).
- The Atheros chip (AR6013G on DWM-W024) sits behind the second SDIO controller at `0x04004A00` (its registers answer). BlocksDS's DSi-mode driver
  (`dswifi`, `arm7/twl/`, MIT, about 130 KB) runs on the ARM7 and does not upload firmware: it relies on the chip already holding it. Not tried. **docs/measured**
- SSH: the image has Dropbear 0.48 (RSA host keys, `diffie-hellman-group1-sha1`, `aes128-cbc`, `hmac-sha1`). A current OpenSSH client connects with
  `-o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc`;
  client keys must be RSA. **inferred** (algorithms read from the source and the client's `ssh -Q` lists; not yet connected)

## 11. Logging and diagnosis without a cable

- The only writable file outside the image is `DSILOG.TXT`, written by `/boot/savelog` (at boot, from the menu, and every 10 s by `/boot/autolog` when
  the content changed). What goes in is `/boot/logbody` (dmesg, boot logs, desktop log, `/proc` diagnostics, network state, DOOM's log). **code**
- Anything that freezes the ARM7 also stops the log. For hangs, a step counter written by the ARM7 into shared memory and printed by the ARM9 with
  `KERN_EMERG` (shown on the screen) located the Wi-Fi hang from one photo. **measured**
- `dmesg` keeps `Data abort` reports with `pc`/`lr`; the ARM9 is still alive after most ARM7 problems. **measured**

## 12. Performance numbers (ARM9, 134 MHz)

| What | Number |
|---|---|
| Nano-X request / round trip | ~1 ms / ~40 ms |
| 3D engine in a window | 58-60 fps, several hundred boxes per frame |
| Peanut-GB (Pokemon Yellow), emulate + draw | ~32 ms per frame at w97f (60 needed); 0.2 ms on a desktop PC |
| DOOM, 320x200 low detail, scaled to 256x192 | runs, "a little sluggish" (not yet measured) |
| Camera preview | 8.6 fps (sensor) |
| Direct writes to both framebuffer pages | ~2 ms for 160x144 |

## 13. Testing without the console

- `testbed/` runs the desktop's Nano-X server and programs on the PC against a 256x192 framebuffer file; `nxctl` clicks, types and takes pictures.
  Good for UI logic and drawing; it has no 3D engine, sound, Wi-Fi or DS buttons. **measured** (it reproduced a menu bug seen on the console)
- `dsgb_host.c` (Game Boy core), `arc_test.c` (game rules) and the DOOM/Peanut code paths build and run natively for checks of logic and speed.
- melonDS (Flatpak) is set up with isolated configs for DS mode (`scripts/melon-ds.sh`). Its DSi mode needs the console dumps; the user allowed
  reading them (2026-11-13), see [DSI-INTERNALS.md](DSI-INTERNALS.md) section 9 (the user prefers to start DSi-mode runs themselves).
