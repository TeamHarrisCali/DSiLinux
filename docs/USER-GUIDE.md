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
- **Screen off:** after 2 minutes without a touch or button the screens go dark, and at once when the lid closes; a touch or button
  (with the lid open) brings them back, without clicking or typing anything. Programs keep running. Settings > Screen off sets the time
  (or never). The backlights and the LCDs both go off.
- **Sleep with the lid closed:** not available yet (it switched the DSi off; work paused). Closing the lid turns the screens off and
  everything keeps running.
- **Low battery:** a popup under the taskbar says "Battery low: plug in" when the battery gets low, and "Critical: off soon" when it is
  nearly empty; about 20 s later, without a charger, the DSi shuts down cleanly by itself.
- **Lock:** Settings > Lock PIN sets a PIN (4-8 digits). With a PIN, closing the lid locks the desktop, and Start > Lock locks it now;
  type the PIN with the touch keyboard's digits or tap the keypad, then Enter / OK. There is no lock at boot. Forgot it: delete
  `/home/.lockpin` (over SSH, or on the PC: `debugfs -w -R "rm /home/.lockpin" ROOTFS.IMG`).

## Buttons and touch

| Control | On the desktop | (Game Boy, removed 2026-11-19) | In DOOM |
|---|---|---|---|
| d-pad | arrow keys | d-pad | move / turn |
| A | Enter | A | fire (Enter in menus) |
| B | Space | B | use / open |
| X / Y | Page Up / Page Down | palette / fast forward (held) | next weapon ("y") / run (held, "n") |
| R / L | left / right mouse button | L alone: sound on/off; L + R: quit | strafe right / left |
| Start / Select | | Start / Select | menu / automap; both together: quit |

The **bottom screen**: its upper part is a trackpad (drag moves the pointer, a tap clicks), the lower part is a keyboard. The quick buttons
across its top: Desk, Test (self-test), Log (save the log now), Mem (memory report).

## The desktop

- **Start menu** (bottom left): Terminal, Files, the groups Accessories, Multimedia, Games, Puzzles, Network, System, then Exit desktop and Shut down.
  Groups open to the side while the pointer is on them; the menu closes by itself after 8 seconds.
- **Taskbar:** one button per window (click: bring it to the front, click the active one: minimise it). **Tray**, pictures only: Wi-Fi bars
  (white = Wi-Fi off, grey = on but no address yet, black = online), battery (filled to the level, green / yellow / red, a yellow mark while
  charging), volume (0-3 sound waves, a red cross when muted), then the clock. Point at a picture (or tap it) to see the details: battery and
  volume percentage, the network and address. A tap on the Wi-Fi bars opens the Wi-Fi window. Volume changes also pop up a bar at the top.

**Windows:** the three boxes at the right of a title bar are minimize (the taskbar button brings it back), maximize (the whole screen
above the taskbar; the box then shows two frames: restore, back to the old size and place) and close. Drag the title bar to move a
window. **Resize:** hold **L** (the right mouse button) on the title bar and drag: the bottom right corner follows. The Terminal fits
itself to the new size; most other programs keep their layout.

## Programs

| Start menu | Program | How to use it |
|---|---|---|
| Terminal | `nxterm` | a shell (busybox): up/down = command history, Tab = completion, left/right edit the line; X / Y (Page Up / Down) or the scroll bar at the right (arrows: 3 lines, above or below the thumb: a page) scroll back through the last 200 lines; colours work (`ls --color`) |
| Files | `dsfiles` | tap a folder to open it, a file to open it in Notes |
| Accessories > Notes | `dsnotes` | text editor, buttons New / Save / Load (`/home/notes.txt`) |
| Accessories > Clock | `nxclock` | |
| Accessories > Paint | `dsarcade paint` | drag to draw, 12 colours, brush size, flood fill; the picture is kept in `/home/paint.dat` |
| Multimedia > Camera | `dscam` | Space / Enter / tap = photo (`/home/photos`), c = other camera, f = flip, m = mirror, b = swap red/blue, v = viewer |
| Multimedia > Photos | `dscam photos` | left / right = previous / next, d twice = delete, v = back to the camera |
| Multimedia > Voice memos | `dsmemo` | buttons Rec / Stop / Play / < > / Del; memos are WAV files in `/home/memos` |
| Multimedia > Sound test | `dsplay` | plays a scale; `dsplay file.wav` in the terminal plays a WAV |
| Multimedia > 3D gears | `dsgl3d` | arrows turn, a = edge smoothing, c = culling, t = textured cube |
| Games > 3D Breakout | `dsarcade breakout` | pointer or left/right move the paddle, Enter / tap launches |
| Games > Tron | `dsarcade tron` | left / right turn |
| Games > 3D Maze | `dsarcade maze` | up / down walk, left / right turn, m = map; find the green cube |
| Games > DOOM | `/home/doom/dsdoom` | shareware episode; buttons in the table above |
| Games > Minesweeper | `landmine` | |
| Puzzles > 2048, Sokoban, Sudoku, Life | `dsarcade ...` | arrows or swipes / taps; Sokoban: Space = undo, X / Y = level; Sudoku: tap a cell, then a digit; Life: tap or drag draws, Enter runs |
| Network > Wi-Fi | `dssettings wifi` | the Wi-Fi window, see below (also a tap on the Wi-Fi bars in the tray) |
| Network > SSH server | `/boot/wifi-ssh` | see below |
| System > Settings | `dssettings` | brightness, pointer speed, desktop colour / pattern / wallpaper (`/home/wallpapers`, photos), clock, info |
| System > Save log | `/boot/savelog` | |
| (Terminal or SSH) | `dsfetch` | neofetch for the DSi: the system at a glance (`dsfetch -n`: no colours) |
| (Terminal or SSH) | `memreport` | where the RAM goes: each program's memory, free memory by block size, the largest free block (a program needing more in one piece cannot start) |

Every program closes with q or Esc, or with the window's close box.

**Stopping a program in the terminal (Ctrl+C):** tap **Ctrl** on the touch keyboard (it stays down, shown pressed), then **C**. Ctrl and Alt
stay down until the next key; a second tap releases them. Holding the R button works as Ctrl too. `ping` runs until stopped: `ping -c 4 host`
sends four and ends by itself. (Up to w97y, pressing L and R together closed the whole desktop and the screen looked frozen; that is gone.)

## Wi-Fi and SSH

Wi-Fi uses the DSi's own chip. (The DSi also has the old DS chip, for open and WEP networks only; its support was removed on
2026-11-19 to save memory, so the Wi-Fi window's **DS chip** button no longer finds a network.)

- **DSi chip** (the default when its firmware file is installed, `scripts/add-dsi-wifi-fw.sh`): **open and WPA2 networks** on 2.4 GHz.
  Switching it on uploads its firmware and scans: up to a minute. Joining takes up to about a minute too. New (w98u), in development; joining an open network from the window works:
  its scan only sees networks on channel 1 so far, and WPA2 has not yet joined a network on the console (open networks work).

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
2. The tray's Wi-Fi bars show the state at a glance (tap them for the details).
3. **Network > SSH server:** makes the host key once (about a minute) and starts the SSH server (inetd, which starts Dropbear for each
   connection; from w98x, before that it never listened); it says "SSH server running" and the address, and runs until the DSi is
   switched off. Without a key, log in as root with the root password (DSLinux's default unless you changed it with `passwd`). Password logins are switched off as soon as
   `/home/.ssh/authorized_keys` exists (an RSA public key). The server is old; from a current PC:

```
ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc root@DSI-ADDRESS
```

On the PC used for this project, `ssh dsi` already knows the DSi's host key, these options and the PC's key `~/.ssh/id_rsa_dsi`
(`~/.ssh/config`; elsewhere `ssh -o HostName=ADDRESS dsi`). From w98y the DSi asks DHCP for the address it had last time on that
network (`/home/wifi.lastip`), so the address usually stays the same. **Key login:** `scripts/add-ssh-key.sh` (card in the PC) puts
the PC's public key into `/home/.ssh/authorized_keys`; then Network > SSH server allows key logins only, no password. The key is checked, so a "host key changed" warning means a different device or a
new key (Network > SSH server makes one only if `/etc/dropbear_rsa_host_key` is missing).

Settings can also be written from the PC: `scripts/set-wifi.sh "NAME" [wepkey]`.

## Files on the card, from the PC

The DSi only ever writes inside `sd:/linux/ROOTFS.IMG` (the whole system) and `sd:/linux/DSILOG.TXT` (the log). With the card in the PC:

| Script | |
|---|---|
| `scripts/rootfs-check.sh` | checks the image (read-only); `-y` repairs it |
| `scripts/add-roms.sh game.gb ...` | your own Game Boy games into `/home/roms` |
| `scripts/set-wifi.sh NAME [wepkey]` | Wi-Fi settings and the SSH server |
| `scripts/add-ssh-key.sh [key.pub]` | key login over SSH (`~/.ssh/id_rsa_dsi.pub` by default; RSA only) |
| `scripts/set-timezone.sh [TZ\|auto]` | normally not needed: after each Wi-Fi connection the DSi finds its time zone and sets the clock (and the DSi's own clock chip). A zone given here (default Central, `CST6CDT,M3.2.0,M11.1.0`) is kept and turns the automatic one off; `auto` turns it back on |
| `scripts/install-terminfo.sh` | terminal descriptions for nano and the other full-screen programs (release.sh does it) |
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
