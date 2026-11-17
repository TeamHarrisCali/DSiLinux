# DSLinuxDSi user guide

How to use DSLinux on the DSi XL: the buttons, the desktop, every program, Wi-Fi, and the card scripts on the PC.
(Status of each feature: the table in the [README](../README.md). Hardware details for developers: [DSI-NOTES.md](DSI-NOTES.md).)

## Starting and stopping

- Start `dslinux-dsimode-<tag>-uc3.nds` from TWiLight Menu++. The boot ends with a self-test (`RAM`, `SD`, `CLK`, `CONF`, `ROOT` should all say PASS)
  and the desktop starts on the top screen by itself (from w98w).
- **Text console instead:** after a crash while the desktop was starting (a panic or a freeze in its first minute) the next boot stops at
  the text console once, so a crash cannot repeat at every boot; tap **Desk** to start the desktop. `touch /home/.no-desktop` always
  boots to the console (`rm /home/.no-desktop` undoes it). A kernel panic while the desktop runs switches the screen back to text so
  the message can be read.
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
- **Taskbar:** one button per window (click: bring it to the front, click the active one: minimise it). **Tray**, pictures only: Wi-Fi bars
  (white = Wi-Fi off, grey = on but no address yet, black = online), battery (filled to the level, green / yellow / red, a yellow mark while
  charging), volume (0-3 sound waves, a red cross when muted), then the clock. Point at a picture (or tap it) to see the details: battery and
  volume percentage, the network and address. A tap on the Wi-Fi bars opens the Wi-Fi window. Volume changes also pop up a bar at the top.

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
| Network > Wi-Fi | `dssettings wifi` | the Wi-Fi window, see below (also a tap on the Wi-Fi bars in the tray) |
| Network > Wi-Fi status, SSH server | `/boot/wifi-*` | see below |
| Network > DSi Wi-Fi test | `/boot/wifi-dsi-test` | the DSi's own Wi-Fi chip (development, docs/ATHEROS-PLAN.md): needs the firmware file in the image (`scripts/add-dsi-wifi-fw.sh` on the PC); asks for a network name and password (empty password: an open network; WPA2: 8-63 characters, never written to the log), brings `wlan0` up, joins, DHCP, ping; result in the card log. `wlan0` stays up (`ifconfig wlan0 down` gives the antenna back to the DS Wi-Fi) |
| System > Settings | `dssettings` | brightness, pointer speed, desktop colour / pattern / wallpaper (`/home/wallpapers`, photos), clock, info |
| System > Bench, Save log | `dsbench`, `/boot/savelog` | |
| (Terminal or SSH) | `dsfetch` | neofetch for the DSi: the system at a glance (`dsfetch -n`: no colours) |

Every program closes with q or Esc, or with the window's close box.

**Stopping a program in the terminal (Ctrl+C):** tap **Ctrl** on the touch keyboard (it stays down, shown pressed), then **C**. Ctrl and Alt
stay down until the next key; a second tap releases them. Holding the R button works as Ctrl too. `ping` runs until stopped: `ping -c 4 host`
sends four and ends by itself. (Up to w97y, pressing L and R together closed the whole desktop and the screen looked frozen; that is gone.)

## Wi-Fi and SSH

The DSi has two Wi-Fi chips sharing one antenna; the Wi-Fi window uses one at a time (button **DSi chip** / **DS chip**, key c):

- **DSi chip** (the default when its firmware file is installed, `scripts/add-dsi-wifi-fw.sh`): **open and WPA2 networks** on 2.4 GHz.
  Switching it on uploads its firmware and scans: up to a minute. Joining takes up to about a minute too. New (w98u), in development; joining an open network from the window works:
  its scan only sees networks on channel 1 so far, and WPA2 has not yet joined a network on the console (open networks work).
- **DS chip**: **open or WEP networks** on 2.4 GHz (802.11b). A phone hotspot works if its security can be set to "None" (iPhones
  cannot); a laptop hotspot works if it is open and allows 802.11b rates.

Your PC must be on the same network for SSH.

1. **Network > Wi-Fi** (or tap the Wi-Fi bars in the tray) opens the Wi-Fi window:
   - **Wi-Fi: On / Off** switches the radio. **Scan** lists the networks (switching Wi-Fi on first if it is off), strongest first, with signal
     bars, a padlock for WEP, and "saved" / "online".
   - Choose one (d-pad, or tap) and **Connect** (A / Enter, or tap it again). A WEP network (DS chip) asks for its key the first time (5 or
     13 letters, or 10 / 26 hex digits), a WPA2 network (DSi chip) for its password (8 to 63 characters); after a working connection it is
     saved in `/home/wifi.known` (and a DS-chip network in `/home/wifi.conf`). **Forget** removes a saved key or password.
   - **Auto** (key a) on a saved network: it is joined at every boot, in the background (up to a minute or two with the DSi chip);
     Auto again turns that off. The result is in the card log ("wifi auto: ...").
   - Keys: s or B = scan, w = Wi-Fi on/off, c = the other chip, a = auto at boot, f = forget, q / Esc = close.
2. In the terminal: `/boot/wifi-scan` prints the same list (`cat /proc/dswifi` is the raw list), `/boot/wifi-connect` asks for name and key.
   Tested: scan, connect, address by DHCP and `ping google.com` over a phone hotspot (open, 2.4 GHz) work (w97y).
3. **Network > Wi-Fi status:** address, Wi-Fi state, routes. The tray shows the same at a glance.
4. **Network > SSH server:** makes the host key once (about a minute) and starts the SSH server (inetd, which starts Dropbear for each
   connection; from w98x, before that it never listened); it says "SSH server running" and the address, and runs until the DSi is
   switched off. Without a key, log in as root with the root password (DSLinux's default unless you changed it with `passwd`). Password logins are switched off as soon as
   `/home/.ssh/authorized_keys` exists (an RSA public key). The server is old; from a current PC:

```
ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc root@DSI-ADDRESS
```

On the PC used for this project, `ssh dsi` already knows the DSi's host key and these options (`~/.ssh/config`, address 192.168.1.2 on
GuestNet; elsewhere `ssh -o HostName=ADDRESS dsi`). The key is checked, so a "host key changed" warning means a different device or a
new key (Network > SSH server makes one only if `/etc/dropbear_rsa_host_key` is missing).

Settings can also be written from the PC: `scripts/set-wifi.sh "NAME" [wepkey]`.

## Files on the card, from the PC

The DSi only ever writes inside `sd:/linux/ROOTFS.IMG` (the whole system) and `sd:/linux/DSILOG.TXT` (the log). With the card in the PC:

| Script | |
|---|---|
| `scripts/rootfs-check.sh` | checks the image (read-only); `-y` repairs it |
| `scripts/add-roms.sh game.gb ...` | your own Game Boy games into `/home/roms` |
| `scripts/set-wifi.sh NAME [wepkey]` | Wi-Fi settings and the SSH server |
| `scripts/install-session.sh` | the boot hook in `/etc/profile` that starts the desktop (release.sh does it) |
| `scripts/install-apps.sh` | the games, accessories and multimedia programs into `/usr/bin` (release.sh does it; they are no longer in the ROM) |
| `doom/install.sh [doom1.wad]` | DOOM into `/home/doom` |
| `debugfs -R "cat /home/notes.txt" ROOTFS.IMG` | read any file from the image |

## After a freeze, and reading the log

- **After any freeze or hard reset, run `scripts/rootfs-check.sh` on the PC** before writing to the image (the writing scripts refuse a damaged image;
  `-y` repairs it). The image is never unmounted cleanly, so a freeze during a write can leave it inconsistent.
- The log `sd:/linux/DSILOG.TXT` is rewritten at boot, every 10 seconds when something changed, and by Save log. It holds the kernel messages, the
  boot and desktop logs (including "dsdesk: started X" / "cannot start X: reason" for every menu click), DOOM's messages, the Wi-Fi state and more.
  If the console froze, the log shows what happened up to about 10 seconds before.
- "Killed" in the terminal with no other text usually means a crash: the log's kernel messages then have a `Data abort` line.
