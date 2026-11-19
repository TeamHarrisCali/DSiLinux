# How the DSi works: hardware, boot, NAND, firmware, drivers

A map of the Nintendo DSi (XL) as far as this project needs it, written from **the user's own dumps of this console** (read with their permission
on 2026-11-13) plus public documentation (GBATEK, dsibrew, BlocksDS/libnds, dswifi). Measured details of how DSLinux drives each part are in
[DSI-NOTES.md](DSI-NOTES.md); the history is in [STAGE3.md](STAGE3.md).

Each fact is marked: **dump** (read from the user's files), **measured** (seen on the console), **docs** (public documentation, not checked here).

> **Nothing console-unique is reproduced here.** The dumps hold the serial number, the console ID and eMMC CID, the per-console device key pair,
> saved Wi-Fi keys, the owner's name and birthday, and Nintendo's keys and certificates. None of that is quoted, and the dump files are never copied
> into this repository (the TwoPaneDSi `.gitignore` lists them). Never write to the NAND.

## 1. The files and what they are

They live in `~/Desktop/DSIBACKUP/` (an SD card backup) and in copies under `~/Documents/Claude/TwoPaneDSi/` (`DSINAND/`, `dsidump/`).

| File | Size | What it is | Source |
|---|---|---|---|
| `dsidump/nand.bin` (= `TwoPaneDSi/DSINAND/nand.bin` = `TwoPaneDSi/dsidump/nand.bin`) | 240 MiB (0xF000000) | raw image of the internal eMMC, **without** the console footer | dump |
| `DT…/nand.bin` (+ `.sha1`) | 240 MiB + 64 bytes | a second raw eMMC image of the same console (5 of the 240 MiB differ), **with** the 64-byte footer `DSi eMMC CID/CPU` + eMMC CID + console ID, which is what decryption tools and melonDS need | dump |
| `dsidump/dsfirmware.bin` | 128 KB | the SPI flash ("firmware" chip): Wi-Fi calibration, access-point settings, user settings | dump |
| `dsidump/bios7.bin`, `bios9.bin` | 16 KB, 4 KB | the DS-mode (NTR) boot ROMs of the ARM7 and ARM9 (SHA-1 `24f67bde…`, `bfaac75f…`, the usual DS BIOS images) | dump |
| `dsidump/bios7i.bin`, `bios9i.bin` | 64 KB each | the DSi-mode (TWL) boot ROMs; both halves have content (the first halves are locked by the console after boot, so only an exploit-based dumper gets them) | dump |
| SD root `sys/ title/ ticket/ shared1/ shared2/ private/ tmp/ import/ progress/` | | **SDNAND**: the NAND's main file system copied to the SD card for hiyaCFW. Plain files, no decryption needed. Used for sections 4-5 | dump |
| `UNLAUNCH.DSI`, `hiya.dsi` + `hiya/`, `BOOT.NDS`, `_nds/` | | the custom-firmware chain (section 3) | dump |

## 2. Hardware overview

| Part | What | How it is driven | |
|---|---|---|---|
| ARM9 | ARM946E-S, 67 or **134 MHz** (DSi mode), 8 KB I-cache / 4 KB D-cache, MPU, ITCM 32 KB, DTCM 16 KB | runs the game / DSLinux kernel | measured |
| ARM7 | ARM7TDMI, ~33 MHz, 64 KB own WRAM | owns the I/O: SD/eMMC, sound, touch, Wi-Fi, I2C, SPI | measured |
| RAM | 16 MB main RAM at 0x02000000 (4 MB in DS mode), plus shared WRAM | | measured |
| SCFG | `SCFG_EXT` 0x04004008 enables DSi extras (NDMA, new SD, camera, AES, ...), `SCFG_CLK` 0x04004004 the 134 MHz clock; locked by the launcher's settings for each app | | measured / docs |
| eMMC | 240 MiB usable (an eMMC behind the TMIO SD controller, port 1); the SD slot is port 0 of the same controller at 0x04004800 | ARM7 | dump / measured |
| SPI flash | 128 KB, on the DS-style SPI bus | ARM7 | dump |
| Power/MCU | the "BPTWL" microcontroller on I2C (address 0x4A): battery, volume, backlight, power button, power-off | ARM7 over I2C | measured |
| Power chip (SPI) | the DS-style power chip is still there in DSi mode: SPI device 0 (SPICNT 0x8802 for the command byte, 0x8002 for the data byte), register 0 bit 0 sound amplifier, bit 2 lower backlight, bit 3 upper backlight, bit 6 power off | ARM7 over SPI | **System Menu code** (HNAE's DSi-mode ARM7: its power thread sets and clears register 0 bits 0x04 / 0x08 / 0x0C for the backlights, 0x01, 0x40 for power off; sets 0x0C at start), 2026-11-18; power off measured (z build) |
| DS-style SPI power chip | does **not** answer on the DSi (reads hang) | — | measured |
| Sound | TSC2117-style codec (sound, microphone **and** the touch screen), I2S out (`SNDEXTCNT` 0x04004700), DS mixer as the source | ARM7 | measured |
| Touch | through the codec registers in DSi mode | ARM7 | measured |
| Cameras | two Aptina MT9V113 on I2C (0x7A inner, 0x78 outer), camera interface + NDMA | ARM7 sets up, ARM9 reads | measured |
| RTC | DS-style real-time clock (serial) | ARM7 | docs |
| Wi-Fi | module DWM-W024: the **DS-compatible chip** (MAC + baseband + RF "type 3", 802.11b, open/WEP) and an **Atheros AR6013G** (802.11b/g, WPA2) behind the second SDIO controller (0x04004A00); one antenna, switched by `GPIO_WIFI` 0x04004C04 bit 8 | DS chip: ARM7 registers at 0x04800000; Atheros: SDIO + firmware upload | measured / docs |
| AES | hardware AES-CCM/CTR engine with key slots (keys from the TWL BIOS + console ID) used for NAND and title crypto | | docs |
| DSP | XpertTeak DSP (used by the DSi Sound app) | not used here | docs |

## 3. How it boots, and how DSLinux gets started

1. **Boot ROMs** (`bios9i`/`bios7i`): set up the AES keys from the console ID, read the **stage 2 loader** from the eMMC, decrypt and check it. docs
2. **Stage 2** is described by a plain (unencrypted) block at NAND 0x200: from 0x220, for the ARM9 then the ARM7: offset, size, load address,
   rounded size. Here: ARM9 code at **0x800**, 0x26410 bytes, loaded to 0x037B8000; ARM7 code at **0x26E00**, 0x27588 bytes, loaded to 0x037B8000.
   It mounts the main partition and starts the **launcher** (System Menu) title from `title/00030017/…`. dump (block) / docs (meaning)
3. **Launcher** (`HNAE`, v512): the System Menu; checks each title's ticket/TMD signature, applies the title's SCFG settings and starts it.
4. **This console's custom chain** (on the SD backup): **Unlaunch** (installed into the real NAND through the launcher's `title.tmd`; its installer
   `UNLAUNCH.DSI` is on the card, and the SDNAND copy still shows the normal 520-byte TMD, so the installed copy is not visible there) takes over before the System Menu → **hiyaCFW** (`hiya.dsi`, `hiya/settings.ini`: title autoboot
   on, DSi splash on) can run the System Menu from the SD card copy ("SDNAND") → **TWiLight Menu++** (`_nds/TWiLightMenu`, with nds-bootstrap release
   0.35.1) lists and starts homebrew → `dslinux-dsimode-*.nds`, a DSi-mode ROM (header unit code 3), which gets 16 MB RAM, 134 MHz and
   the DSi SD controller. dump
5. **DS games** run in a DS mode the launcher sets up through SCFG (4 MB, 67 MHz, DS touch/sound/Wi-Fi only), using `bios7`/`bios9`. docs

## 4. The NAND (eMMC)

- **Encryption.** Every sector is AES-CTR encrypted with a key derived from the console ID (plus constants from the TWL BIOS); the counter comes from
  the eMMC CID. A raw image is therefore useless on another console and is only readable with this console's footer. Only the stage-2 info block
  at 0x200 is plain. dump (entropy) / docs
- **Layout** (offsets from dsibrew; the observed map agrees):

| Range | What | Seen in this dump |
|---|---|---|
| 0x0 | MBR (encrypted), partition table | encrypted |
| 0x200 | stage-2 info block (plain) | plain, decoded above |
| 0x800 - ~0x4E400 | stage-2 ARM9 and ARM7 code | encrypted |
| 0x10EE00 - | **main** partition ("TWL-MAIN", FAT16, ~205 MiB): `sys`, `title`, `ticket`, `shared1/2`, `import`, `progress`, `tmp` | data up to ~107 MiB, then never written (zeros) up to ~207 MiB |
| 0xCF09A00 - | **photo** partition (FAT12, ~32 MiB): pictures of the DSi Camera | data from ~207 MiB to ~236 MiB |
| 0xF000000 | (image end; dumpers append the 64-byte footer here) | footer only in the `DT…` copy |

- `user_area_size.bin` in the version data (section 5) gives the user area for titles as 0x08000000 bytes (128 MiB). dump

## 5. The file system on the main partition (from the SDNAND copy)

### Installed titles

Title IDs are `high/low`; the low half is the 4-letter code in hex (`484E4145` = `HNAE`). The last letter is the region (E = USA, J, P, U, K, C...).
Header unit code 3 = DSi only, 0 = DS. Sizes are the `.app` (an SRL, i.e. a DS/DSi ROM image) or data file.

| Title | Code | What | Version | Size | ARM9 / ARM7 / ARM9i / ARM7i code |
|---|---|---|---|---|---|
| 00030017/484E4145 | HNAE | **Launcher** (System Menu, USA) | v512 | 1657 KB | 726 / 42 / 0 / 401 KB |
| 00030017/484E41{43,4A,4B,50,55} | HNAC/J/K/P/U | launcher folders for other regions, TMD only (no `.app`) | v512 | — | |
| 00030015/484E4245 | HNBE | **System Settings** | v768 | 2584 KB | 1055 / 1 / 45 / 428 |
| 00030015/484E4645 | HNFE | **DSi Shop** | v3072 | 5279 KB | (+ `data/ec.cfg`) |
| 00030015/484E4F45 | HNOE | **Data Management** ("CARDBOARD") | v256 | 2325 KB | |
| 00030015/534C524E | SLRN | TWiLight Menu++ "TWLMENUPP-LR" forwarder (homebrew, installed by the user) | v0 | 288 KB | |
| 00030005/484E4441 | HNDA | **DS Download Play** (DS mode, unit 0) | v256 | 422 KB | 255 / 141 / — / — |
| 00030005/484E4541 | HNEA | **PictoChat** (DS mode) | v0 | 467 KB | |
| 00030005/484E4945 | HNIE | **DSi Camera** ("PHOTO") | v1024 | 4367 KB | |
| 00030005/484E4A45 | HNJE | **Nintendo Zone** | v768 | 1316 KB | |
| 00030005/484E4B45 | HNKE | **DSi Sound** ("DSSOUND") | v512 | 4420 KB | 862 / 163 / 2043 / 313 |
| 00030004/484E4745 | HNGE | **DSi Browser** (Opera) | v768 | 9918 KB | |
| 00030004/4B574445 | KWDE | a DSiWare clock app ("PHOTOCLOCK") | v256 | 614 KB | |
| 00030004/53524C41 | SRLA | TWiLight Menu++ forwarder ("TWLMENUPP") | v0 | 280 KB | |
| 0003000F/484E4341 | HNCA | **Wi-Fi firmware** for the Atheros chip (data, not a program) | v512 | 95.6 KB | |
| 0003000F/484E4841 | HNHA | **DS cartridge whitelist** (`NDHT` table of DS game codes + hashes the launcher checks) | v1536 | 308 KB | |
| 0003000F/484E4C45 | HNLE | **Version data** (a NARC archive) | v9 | 7 KB | |

Every title folder has `content/title.tmd` (title metadata: version, content hashes) and `content/000000xx.app`; programs that keep data have
`data/private.sav` / `data/public.sav`. The matching tickets are in `ticket/<high>/<low>.tik` (two more tickets belong to DSiWare that is no longer installed). dump

- **Version data (HNLE)**: `version.bin` = **"1.4.5U"** (the system version), `nup_host.bin` (the update server, `nus.t.shop.nintendowifi.net:443`),
  `eula_url.bin`, `time_stamp.bin`, `user_area_size.bin` (128 MiB), plus Nintendo's CA certificate and the update/shop client certificates and
  private keys (not extracted). dump
- **Wi-Fi firmware (HNCA)**: 97888 bytes; it starts with what looks like a hash or signature, then Atheros AR6000-family firmware (its strings, e.g. "unable
  to reset hardware", are visible). The System Menu uploads it into the Atheros chip; DSi-mode programs started afterwards find the chip already
  running it. This is the file any future **WPA2** driver for DSLinux would need (load it from the NAND or from an SDNAND copy and upload it
  over SDIO), since the DS chip can only do open/WEP. dump / docs
- **Wi-Fi firmware layout (decoded 2026-11-13):** after the RSA signature and SHA-1, an entry table at 0xA0 (count at 0xA2) of
  {offset, length, ID, SHA-1}; here 2 blobs: one for the AR6002 (boot ROM 0x20000188), one for AR6013/AR6014 (boot ROM 0x23000024). A blob:
  a flags word, four parts {offset, size, type (bit 31 = LZ), load address}, then chip ID/boot ROM pairs from +0x44 and the host interest
  address at +0x58. Parts: 1 the LZ-compressed firmware, 2 a dataset list, 4 code executed during the upload, 5 configuration written over
  the firmware's start. dump

### System files

| File | Size | What (only the non-personal fields were read) |
|---|---|---|
| `sys/HWINFO_S.dat` | 16 KB | signed hardware info: region **1 (USA)**, languages **0x26** (English, French, Spanish), launcher **HNAE**; also the serial number (not read) |
| `sys/HWINFO_N.dat` | 16 KB | further hardware info (not decoded) |
| `sys/HWID.sgn` | 256 B | signature binding the console |
| `sys/dev.kp` | 446 B | the console's **device key pair** (ECC), used for shop/ticket crypto: private, never copy |
| `sys/cert.sys` | 3904 B | Nintendo's certificate chain for title signatures |
| `sys/TWLFontTable.dat` | 843 KB | the system font |
| `sys/log/sysmenu.log`, `product.log`, `shop.log` | | System Menu, factory and shop logs |
| `shared1/TWLCFG0.dat`, `TWLCFG1.dat` | 16 KB each | the DSi user settings (two copies): owner profile, language, parental controls, touch calibration (not read: name and birthday) |
| `shared2/0000` | 2 MB | the DSi Sound app's recordings store |
| `shared2/launcher/wrap.bin` | 16 KB | launcher state |
| `private/ds/app/484E494A/pit.bin` | 47 KB | the DSi Camera's picture index (the pictures are on the photo partition / SD `DCIM`) |
| `tmp/es`, `import/`, `progress/` | | the title installer's work areas (empty) |

## 6. The SPI flash ("firmware" chip, 128 KB)

On a DS this chip holds the firmware program; **on the DSi the program area 0x200-0x1F3FF is empty (all 0xFF)**: the DSi's system lives on the
NAND, and the chip only keeps settings for DS mode and the Wi-Fi calibration. dump

| Range | What | Seen |
|---|---|---|
| 0x00-0x1F | header; byte **0x1D = 0x57 = DSi** (0xFF DS, 0x20 DS Lite) | |
| 0x20 | offset of the user settings / 8 = 0x1FE00 | |
| 0x2A-0x1FF | **Wi-Fi calibration** for the DS chip: MAC address (0x36), enabled channels 0x3C = 0x3FFE (1-13), **RF type 0x40 = 3**, RF bits 0x41 = 0x94, 41 initial RF values (0x42), 2 RF channel entries (0x43), 16 MAC register values (0x44), 0x69 baseband values (0x64), then the RF init bytes (0xCE) and the channel table | dump |
| 0x1F400-0x1F9FF | DSi access-point slots 4-6 (WPA capable, used by DSi-mode programs) | slot 4 in use |
| 0x1FA00-0x1FCFF | DS access-point slots 1-3 (open/WEP, used by DS games) | empty |
| 0x1FE00-0x1FFFF | DS user settings, two copies (name, birthday, language, touch calibration, alarm) | not read |

**The channel table** (RF type 3), which caused the Wi-Fi failures of w97s-w97x: after the 41 initial RF bytes at 0xCE comes **one byte with the
number of baseband entries** (here 2), then the baseband entries, then the 0x43 RF entries (here 2). Each entry is a register number and 14
per-channel values. Here the baseband registers are 0x1E and 0x26; the RF entries are RF register 1 (coarse frequency, three steps across
channels 1-14) and RF register 2 (fine). Changing channel = write those registers with the column for the channel. DSLinux's original code read
the count wrongly and never set RF register 1 (fixed in w97y, patch 0100). dump

## 7. The boot ROMs

- `bios9.bin` (4 KB) and `bios7.bin` (16 KB): the DS-mode ROMs, needed by DS-mode software and by emulators for DS mode. dump
- `bios9i.bin` and `bios7i.bin` (64 KB each): the DSi-mode ROMs: the boot code that loads stage 2, the AES key data, the RSA public keys for the
  signature checks, and the SWI functions DSi programs call. The console locks the first half of each after boot, so normal homebrew (and
  DSLinux) cannot read it; this dump has both halves. Do not reproduce their contents. dump / docs

## 8. Drivers: who talks to what

| Function | Official system | DSLinux (this project) |
|---|---|---|
| eMMC | stage 2 + launcher through the TMIO controller, AES-CTR on every sector | never touched: the ARM7 driver only selects port 0 (SD) |
| SD card | TMIO port 0, FAT via the system or homebrew (libfat/DLDI) | ARM7 polling TMIO driver; the ARM7 itself confines access to `sd:/linux/ROOTFS.IMG` and `DSILOG.TXT` |
| Wi-Fi, DS games | DS chip (open/WEP), set up from the SPI-flash calibration | same chip, DSLinux's 2008 driver with DSi fixes (patches 0090-0100) |
| Wi-Fi, DSi programs | Atheros over SDIO, firmware HNCA uploaded by the system, WPA2 | not yet: would need an SDIO + WMI driver on the ARM7 or ARM9 |
| Touch, sound, microphone | the codec (DSi mode) | the codec through the ARM7 (BlocksDS method) |
| Battery, volume, backlight, power | the BPTWL MCU over I2C | the same, over I2C from the ARM7 |
| Cameras | I2C + camera interface + NDMA | the same |
| Clock | RTC | kernel RTC driver |

## 9. What the dumps make possible next

- **melonDS in DSi mode** for testing: needs `bios7i.bin`, `bios9i.bin`, `dsfirmware.bin` and the NAND **with footer** (the `DT…` copy). Running
  it changes the NAND image's timestamps; the user prefers to start DSi-mode runs themselves.
- **WPA2 Wi-Fi**: the Atheros firmware (HNCA) is available from the SDNAND copy without any decryption; BlocksDS's dswifi (MIT) shows the SDIO
  and WMI side.
- **Exact hardware constants** (Wi-Fi calibration, RF type) can be checked against the flash dump instead of guessing, as for the channel bug.

## The System Menu's Wi-Fi (WMI) code (read 2026-11-19, the user's dump)

The System Menu's ARM7i (HNAE, not modcrypted) carries the Atheros WMI layer. Its code is relocated at run time: file address +
0x857ffc.
- WMI command send: 0x2f440f8 (wmi, buffer, command, sync flag).
- SET_SCAN_PARAMS builder: 0x2f44234 (the ath6kl 20-byte layout).
- At initialisation (0x2f41134) it sets periods 0xFFFF, dwell 20 / 50 ms, ratio 3, scan control flags 0, then power mode 1.
- No START_SCAN or CONNECT in this copy.
- DSi Settings (HNBE) does the connection setup but is modcrypted. dsiwifi.c follows these values (x04).
