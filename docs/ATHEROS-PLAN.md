# Plan: the DSi's second Wi-Fi chip (Atheros, 802.11g, WPA2)

Status: **started 2026-11-13.** Step 0 done; steps 1-3 built as a test (w98d, patch 0105), not yet run on the console.

## Why

The DS-compatible chip now works (scan, join, DHCP, ping; w98c), but it can only do **open or WEP networks at 1-2 Mbit/s**. Most networks
are WPA2, and phone hotspots demand 5.5/11 Mbit/s, so the DS chip loses packets there. The DSi's own Wi-Fi chip, an **Atheros AR6000-family
chip (AR6013G on the DSi XL's DWM-W024 module)**, does 802.11b/g up to 54 Mbit/s and encrypts WPA/WPA2 (CCMP) itself. Goal: a second
network interface `wlan0` that joins WPA2 networks, used by the Wi-Fi window when the network needs it.

## What we already know

| Fact | Source |
|---|---|
| The chip sits behind the DSi's **second SD/SDIO controller at 0x04004A00** (same TMIO controller type as the SD card at 0x04004800); its registers answer (`/proc/dsiwifi` probe: `01000434 80000800 00010100 00001000 status=20800731`) | measured (w97j) |
| One antenna, switched by `GPIO_WIFI` 0x04004C04 **bit 8: 1 = DS chip, 0 = Atheros**; `SCFG_WL` reads 1 | measured |
| The firmware is title **HNCA** (`title/0003000f/484e4341/content/00000002.app`, 97888 bytes): a header, then AR6000 firmware. On this console a plain copy is in the hiyaCFW SDNAND on the SD backup (`~/Desktop/DSIBACKUP/title/...`) | dump |
| The System Menu uploads the firmware. **Unlaunch starts before the System Menu**, so when DSLinux runs (Unlaunch -> TWiLight) the chip has most likely **not** been given its firmware: the driver must be able to upload it | inferred |
| The I/O registers (0x04004xxx) belong to the ARM7 in DSi mode: everything that touches the SDIO controller runs on the ARM7, as the SD card driver does | measured (SD) |
| ARM7 program today: 35.9 KB of 64 KB WRAM (code + data + stack); ROM: 34 KB free of the 4 MiB ceiling | measured (w98c) |

How the chip is talked to (AR6000 family, as in Linux `ath6kl` / the old `ar6000` driver; to be checked against the DSi-specific code):
- **SDIO** commands 52 (one register byte) and 53 (blocks) to function 1; the chip has four **mailboxes** (message queues) and
  interrupt/status registers.
- **BMI** (boot messaging interface) while the chip runs its ROM: read the target ID/version, write memory, upload the firmware (and the
  board data), set the start address, "done" -> the firmware boots.
- **WMI** (wireless module interface) once the firmware runs: a `WMI_READY` event (gives the MAC address), then commands (scan, connect,
  add key, set power mode) and events (scan results, connected, disconnected), and data frames with a small header, over **HTC**
  (host-target communication: endpoints on the mailboxes, credit-based flow control).
- **WPA2-PSK**: the firmware encrypts/decrypts (CCMP) once the keys are installed, but the **4-way handshake** (EAPOL frames) is the host's
  job: PSK = PBKDF2-HMAC-SHA1(passphrase, SSID, 4096 rounds, 32 bytes); then PTK derivation, MIC check, key unwrap (AES key wrap) of the
  group key, then `WMI_ADD_CIPHER_KEY` for both keys.

## Design

```
 ARM9 (Linux 2.6.14)                                     ARM7
 ------------------------------------------------        -------------------------------------
 wlan0 net_device  <->  HTC / WMI / BMI layer            SDIO primitives on the TMIO at 0x04004A00:
 /proc/dsiwifi2 (scan list, state)   |                    CMD52 read/write, CMD53 block read/write,
 WPA2 handshake (PBKDF2, PRF, AES key wrap)  <-- FIFO --> card interrupt -> FIFO message to the ARM9,
 firmware loader (/lib/firmware/dsi-wifi.bin)  shared     antenna switch, power, bounded waits
                                                 buffer
```

- **ARM7 stays small**: only an SDIO "transport" (a few KB): reset/initialise the SDIO card (CMD0/CMD5/CMD3/CMD7, enable function 1, block
  size), CMD52 and CMD53 on request, forward the card interrupt. Requests travel like the SD card ones: a shared request block plus the FIFO.
  The existing SD code (`sdmmc.c`, TMIO) and BlocksDS's `tmio.twl.c` are the models. **Every wait bounded** (a stuck ARM7 freezes the DSi).
- **Everything else in the kernel on the ARM9**: BMI, HTC, WMI, the net device, the handshake. It is easier to debug there (printk, /proc),
  and the ARM9 has the RAM and the speed (PBKDF2 4096 rounds: a few seconds on the ARM9 at 134 MHz; cache the PSK per network).
- **Firmware**: never in this repository or the ROM. A script copies it from the user's own SDNAND (`scripts/add-dsi-wifi-firmware.sh`,
  reading `title/0003000f/484e4341/content/*.app` from a path the user gives) into `ROOTFS.IMG` as `/lib/firmware/dsi-wifi.bin`; the driver
  reads it at `ifconfig wlan0 up`. If the chip already runs a firmware (WMI_READY arrives without BMI), skip the upload.
- **Only one radio at a time**: `nds` (DS chip) and `wlan0` (Atheros) exclude each other (antenna switch, power); bringing one up takes the
  other down.
- **User side**: the Wi-Fi window lists both chips' networks; WPA/WPA2 networks join through `wlan0` (asks for the passphrase, saves it in
  `/home/wifi.known`), open/WEP ones through whichever works; `wifi-status` shows both. udhcpc, DNS, ping, SSH unchanged.
- **Size**: the ROM has 34 KB left. The ARM9 driver plus the handshake will likely exceed that: make room first (move `dsbench`, `landmine`,
  `ntetris` or `dsgx` out of the ROM into `ROOTFS.IMG`, as was done for DOOM), or build the driver as small as possible.

## Steps (each ends with something checkable in the card log)

| # | Step | Done when |
|---|---|---|
| 0 | Gather references (needs the user's OK for downloads): BlocksDS **dswifi** source (MIT; its DSi part drives this chip on the ARM7), its `examples/atheros/basic_test`, the DSi Atheros/SDIO section of GBATEK, Linux `ath6kl` headers for the WMI/HTC/BMI structures (GPL, matches DSLinux's licence). Decode the HNCA header (what is signature, where the firmware and board data start, load addresses). | notes in this file |
| 1 | ARM7 SDIO transport: switch the antenna, power, initialise the card, read the CIS (manufacturer/card ID) with CMD52. | `/proc/dsiwifi2` shows the Atheros manufacturer ID |
| 2 | BMI: read the target version/ID (tells AR6002/AR6013/AR6014 and which firmware layout applies). | target ID in the log |
| 3 | Firmware upload (+ board data) from `/lib/firmware`, start it, receive `WMI_READY` with the MAC address. | "WMI ready, MAC xx:..." in the log |
| 4 | HTC endpoints + WMI scan -> `/proc/dsiwifi2` lists networks **including WPA2 ones**, with signal and security. | WPA2 networks in the scan list |
| 5 | `wlan0` net device, connect to an **open** network, data path both ways, DHCP. | an address, `ping` the gateway |
| 6 | WPA2-PSK: PBKDF2 (cached), 4-way handshake, install pairwise + group keys. | joins a WPA2 network, DHCP, `ping google.com` |
| 7 | Wi-Fi window + scripts: both chips, passphrase entry, chip chosen by the network's security; mutual exclusion with `nds`. | the user connects to their home WPA2 network from the window |
| 8 | Robustness: reconnect after a disconnect, scan while connected, power save off/on, error paths with bounded waits; docs (USER-GUIDE, DSI-NOTES, DSI-INTERNALS). | an hour connected without a freeze |

Rough size: steps 1-3 are the risky part (new hardware path, no emulator for the chip unless melonDS's DSi mode emulates it well enough;
the user prefers to start DSi-mode melonDS runs themselves). Steps 4-6 are mostly protocol work that can be checked on the PC first
(the handshake maths against known test vectors from IEEE 802.11i).

## Testing

- Every step adds its result to `/proc/dsiwifi2`, which `logbody` puts in `DSILOG.TXT`: one boot per step on the console, as with the DS chip.
- The handshake code (PBKDF2, PRF, MIC, key unwrap) gets a PC test program with the IEEE 802.11i test vectors before it goes near the
  console.
- melonDS in DSi mode (with the user's dumps) may emulate enough of the Atheros chip for steps 1-4; to check, and only started by the user.

## Risks

- The ARM7 locking up on an SDIO wait (bounded waits everywhere; the step counter trick from the DS chip bring-up shows where it stops).
- The firmware's header/layout and the board data for this exact chip revision are not documented in our sources yet (step 0).
- ROM space (see Size). ARM7 WRAM: the transport must stay small.
- Licences: dswifi is MIT (usable with attribution in GPL code); `ath6kl` is GPL/ISC; the Nintendo firmware is the user's own copy and is
  never distributed.

## Step 0 results (2026-11-13)

- Reference: BlocksDS **dswifi** (MIT), cloned to `~/Documents/Claude/DSLinuxDSi-third-party/dswifi` (commit 84d91e8). Its
  `source/arm7/twl/` is a complete driver for this chip: SDIO (`sdio.twl.c`), chip set-up and BMI (`card.twl.c`), HTC/WMI (`ath/`), WPA2
  handshake (`ieee/wpa.twl.c`, mbedtls for the crypto). Enough protocol reference; the Linux `ath6kl` headers and the BlocksDS example were
  not needed and not downloaded.
- **dswifi does not upload firmware.** Its upload code is disabled (`#if 0`); it reads the "host interest" word at +0x58 (non-zero =
  firmware present, left there by the System Menu), resets the chip into its boot ROM (the firmware stays in RAM), makes a few BMI settings
  and starts it with BMI_DONE. The disabled code shows what an upload would need for an AR6014: part D and C written and C executed (ROM
  patches), part A **LZ-compressed** (BMI_LZ_STREAM) to 0x524C00, part B (a database) to 0x53FE18 with its address stored at host
  interest +0x18. These parts live in HNCA. So whether DSLinux needs an upload depends on whether the firmware survives until DSLinux runs
  (Unlaunch -> TWiLight skips the System Menu): **the w98d test reads that flag.**
- Hardware preparation (from dswifi): `GPIO_WIFI` bit 8 clear (Atheros), RTC FOUT registers (commands 0x72 = 0x80, 0x74 = 0x00: the
  module's 32 kHz clock), power chip register 0x30 = 0x13, `SCFG_WL` bit 0. SDIO controller 2 at 0x04004A00, clock divider 0, 4-bit bus,
  128-byte blocks. Chip IDs: AR6002 0x02000001, AR6013 0x0D000000, AR6014 0x0D000001; host interest at 0x00520000 (AR601x) or 0x00500400.
- Our test (`arm7/twlwifi.c`, `/proc/dsiwifi2`, Start > Network > DSi Wi-Fi test) runs steps 1-12 of that sequence with bounded waits and
  reports where it got to.
