# DSLinuxDSi user guide

How to use DSLinux on the DSi XL: the buttons, the desktop, every program, Wi-Fi, and the card scripts on the PC.
(Status of each feature: the table in the [README](../README.md). Hardware details for developers: [DSI-NOTES.md](DSI-NOTES.md).)

## Starting and stopping

- Start `dslinux-dsimode-<tag>-uc3.nds` from TWiLight Menu++. The boot ends with a self-test (`RAM`, `SD`, `CLK`, `CONF`, `ROOT` should all say PASS)
  and the desktop starts on the top screen.
- **Shut down** (Start menu) powers the DSi off cleanly. Prefer it to the power button: the system lives in an ext2 image without a journal.
- **Exit desktop** returns to the text console; `/boot/desktop` starts it again.

## Buttons and touch

| Control | On the desktop | In the Game Boy emulator | In DOOM |
|---|---|---|---|
| d-pad | arrow keys | d-pad | move / turn |
| A | Enter | A | fire (Enter in menus) |
| B | Space | B | use / open |
| X / Y | Page Up / Page Down | palette / fast forward (held) | next weapon ("y") / run (held, "n") |
| R / L | left / right mouse button | L alone: sound on/off; L + R: quit | strafe right / left |
| Start / Select | | Start / Select | menu / automap; both together: quit |

The **bottom screen**: its upper part is a trackpad (drag moves the pointer, a tap clicks), the lower part is a keyboard. The quick buttons
across its top: Desk, Test (self-test), Log (save the log now), Bench.

## The desktop

- **Start menu** (bottom left): Terminal, Files, the groups Accessories, Multimedia, Games, Puzzles, Network, System, then Exit desktop and Shut down.
  Groups open to the side while the pointer is on them; the menu closes by itself after 8 seconds.
- **Taskbar:** one button per window (click: bring it to the front, click the active one: minimise it). **Tray:** Wi-Fi bars (grey = Wi-Fi on but
  no address yet, black = online), battery (green / yellow / red, a yellow mark while charging), volume (changes pop up a percentage), clock.

## Programs

| Start menu | Program | How to use it |
|---|---|---|
| Terminal | `nxterm` | a shell (busybox): up/down = command history, Tab = completion, left/right edit the line; X / Y (Page Up / Down) scroll back through the last 200 lines; colours work (`ls --color`) |
| Files | `dsfiles` | tap a folder to open it, a file to open it in Notes |
| Accessories > Notes | `dsnotes` | text editor, buttons New / Save / Load (`/home/notes.txt`) |
| Accessories > Clock | `nxclock` | |
| Accessories > Paint | `dsarcade paint` | drag to draw, 12 colours, brush size, flood fill; the picture is kept in `/home/paint.dat` |
| Multimedia > Camera | `dscam` | Space / Enter / tap = photo (`/home/photos`), c = other camera, f = flip, m = mirror, b = swap red/blue, v = viewer |
| Multimedia > Photos | `dscam photos` | left / right = previous / next, d twice = delete, v = back to the camera |
| Multimedia > Voice memos | `dsmemo` | buttons Rec / Stop / Play / < > / Del; memos are WAV files in `/home/memos` |
| Multimedia > Sound test | `dsplay` | plays a scale; `dsplay file.wav` in the terminal plays a WAV |
| Multimedia > 3D gears | `dsgl3d` | arrows turn, a = edge smoothing, c = culling, t = textured cube |
| Games > 3D Dodge | `dsgame` | d-pad hops between the 9 cells; best score in `/home/dodge.best` |
| Games > 3D Breakout | `dsarcade breakout` | pointer or left/right move the paddle, Enter / tap launches |
| Games > Tron | `dsarcade tron` | left / right turn |
| Games > 3D Maze | `dsarcade maze` | up / down walk, left / right turn, m = map; find the green cube |
| Games > Game Boy | `dsgb` | pick a ROM from `/home/roms` (Enter or tap twice); buttons in the table above; saves as `.sav` next to the ROM |
| Games > DOOM | `/home/doom/dsdoom` | shareware episode; buttons in the table above |
| Games > Minesweeper, Tetris | `landmine`, `ntetris` | |
| Puzzles > 2048, Sokoban, Sudoku, Life | `dsarcade ...` | arrows or swipes / taps; Sokoban: Space = undo, X / Y = level; Sudoku: tap a cell, then a digit; Life: tap or drag draws, Enter runs |
| Network > Wi-Fi scan / connect / status, SSH server | `/boot/wifi-*` | see below |
| System > Settings | `dssettings` | brightness, pointer speed, desktop colour / pattern / wallpaper (`/home/wallpapers`, photos), clock, info |
| System > Bench, Save log | `dsbench`, `/boot/savelog` | |

Every program closes with q or Esc, or with the window's close box.

## Wi-Fi and SSH

The DSi's DS-compatible Wi-Fi chip is used: it joins **open or WEP networks on 2.4 GHz** (802.11b), not WPA/WPA2. A phone hotspot works if its
security can be set to "None" (iPhones cannot); a laptop hotspot works if it is open and allows 802.11b rates. Your PC must be on the same network.

1. **Network > Wi-Fi scan:** lists the networks and whether they are encrypted.
2. **Network > Wi-Fi connect:** the first time it asks for the network name and the WEP key (empty = open network) and keeps them in `/home/wifi.conf`;
   then it joins and asks for an address (DHCP). To change network: `rm /home/wifi.conf` in the terminal and connect again.
3. **Network > Wi-Fi status:** address, Wi-Fi state, routes. The tray shows the same at a glance.
4. **Network > SSH server:** makes the host key once (about a minute) and starts Dropbear. Password logins are switched off as soon as
   `/home/.ssh/authorized_keys` exists (an RSA public key). The server is old; from a current PC:

```
ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc root@DSI-ADDRESS
```

Settings can also be written from the PC: `scripts/set-wifi.sh "NAME" [wepkey]`.

## Files on the card, from the PC

The DSi only ever writes inside `sd:/linux/ROOTFS.IMG` (the whole system) and `sd:/linux/DSILOG.TXT` (the log). With the card in the PC:

| Script | |
|---|---|
| `scripts/rootfs-check.sh` | checks the image (read-only); `-y` repairs it |
| `scripts/add-roms.sh game.gb ...` | your own Game Boy games into `/home/roms` |
| `scripts/set-wifi.sh NAME [wepkey]` | Wi-Fi settings and the SSH server |
| `doom/install.sh [doom1.wad]` | DOOM into `/home/doom` |
| `debugfs -R "cat /home/notes.txt" ROOTFS.IMG` | read any file from the image |

## After a freeze, and reading the log

- **After any freeze or hard reset, run `scripts/rootfs-check.sh` on the PC** before writing to the image (the writing scripts refuse a damaged image;
  `-y` repairs it). The image is never unmounted cleanly, so a freeze during a write can leave it inconsistent.
- The log `sd:/linux/DSILOG.TXT` is rewritten at boot, every 10 seconds when something changed, and by Save log. It holds the kernel messages, the
  boot and desktop logs (including "dsdesk: started X" / "cannot start X: reason" for every menu click), DOOM's messages, the Wi-Fi state and more.
  If the console froze, the log shows what happened up to about 10 seconds before.
- "Killed" in the terminal with no other text usually means a crash: the log's kernel messages then have a `Data abort` line.
