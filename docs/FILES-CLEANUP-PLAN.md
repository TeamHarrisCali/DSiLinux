# Plan: file management, a tidy file layout, and a leaner system

Status: **plan only** (2026-11-17). Nothing is changed yet. This plan sits next to [BUSYBOX-HUSH-PLAN.md](BUSYBOX-HUSH-PLAN.md) and
[VIRTUAL-DESKTOPS-PLAN.md](VIRTUAL-DESKTOPS-PLAN.md); the order between the three is the user's choice.

## Where things stand (checked in the tree)

**The Files program (`dsfiles`, 219 lines)** only browses: tap a folder to open it, tap a file to open it in Notes. It cannot delete,
rename, copy, move or make folders, and it opens everything as text.

**How the file system is put together:**

| Where | What | Writable |
|---|---|---|
| ROM (inside the `.nds` file, loaded into RAM at start) | `/bin` (BusyBox 1.00), `/sbin`, `/boot` (the desktop, Terminal, Settings, Wi-Fi window and the system scripts), `/dev`, mount points | No, replaced with each new ROM |
| `sd:/linux/ROOTFS.IMG` (512 MB ext2 image, about 117 MB used), mounted at `/media/linux` | `/etc`, `/home`, `/lib`, `/usr`, `/var` (the ROM's `/etc` etc. are links into it) | Yes, survives reboots |
| RAM | `/tmp`, `/var/run` | Yes, lost at power-off |
| The rest of the SD card | Not visible at all: the ARM7 lets DSLinux reach only `sd:/linux/ROOTFS.IMG` and `sd:/linux/DSILOG.TXT`, so a bug can never touch your other files or the console | No |

**`/home` is one flat folder** holding:
- **your files:** `notes.txt`, `memos/`, `photos/`, `roms/`, `doom/`, `paint.dat`, `screen.bmp`;
- **settings:** `settings.conf`, `wifi.known`, `wifi.conf`, `wifi.auto`, `wifi.lastip`;
- **game records:** `dodge.best`, `breakout.best`, `arcade2048.best`, `sokoban.lvl`, `.savegame`;
- **test logs:** `wlan0-test.log`, `wlan0-dmesg.txt`;
- **switches:** `.desktop-starting`, `.no-desktop`.

About 17 of these paths are written into 19 program and script files.

**`/usr/bin` holds 191 programs, 93 MB**, mostly from the 2007 DSLinux distribution:
- **ImageMagick:** 11 separate full copies of about 3.4 MB each, roughly 36 MB.
- **Network services:** Samba (smbd/nmbd, about 2.3 MB each), OpenVPN, boa (a web server), iptables, inadyn.
- **Old desktop pieces:** `npanel`, `launcher`, `nxkbd`, `dsgallery`, `dsgears`, the PIXIL suite (7 MB in `/usr/pixil`).
- **Sound servers:** esd*.
- **Stale copies** of `nano-X`, `nanowm`, `nxterm`, `dsdesk` and `dssettings`. The desktop runs the ROM's copies in `/boot`; the old
  ones in `/usr/bin` can still be started by mistake.
- **Still useful:** `links`, `irssi`, `mc` (Midnight Commander, a file manager for the terminal), `less`, `nano`, `sqlite3`, `perl`,
  `wget`, `scp`, `bc`, `zip`/`unzip`.

## 1. The Files program, rebuilt

What it should do, Windows-95 style, fitting 256x192:
- **Places bar** at the top: Home, Documents, Pictures, Music, Games, Downloads, and "System" (the whole tree, see safety). A path line
  and Up, Back buttons; a scroll bar.
- **Select** a file or folder with a tap (highlighted), **open** with a second tap or A. L (right click) opens a menu.
- **Menu / toolbar actions:** Open, Open with..., Rename, Delete, Copy, Cut, Paste, New folder, Properties (size, date, type), Select
  all.
- **Delete goes to a Recycle Bin** (`/home/.trash`, with where each item came from), so a mistake can be undone; the bin can be
  emptied (asks first: "Delete 12 items permanently?") and restored item by item. Folders are deleted with what is in them, after a
  confirmation that says how many files that is.
- **Opening by type:** `.txt`, `.conf`, `.log`, `.sh` → Notes; `.jpg`/`.bmp`/photos → the Photos viewer; `.wav` → Voice memos player;
  `.gb`/`.gbc` → Game Boy; `.wad` → DOOM; folders → open; anything else → "Open with...".
- **Safety:** the ROM folders are read-only anyway; the system folders on the card (`/etc`, `/usr`, `/lib`, `/var`) are shown only
  under "System" and their Delete / Rename ask a second time with a warning; your files under Home have the normal one-step delete
  (to the bin).
- **Keys** for the touch keyboard: Delete, F2 (rename), Ctrl+C / Ctrl+X / Ctrl+V, Backspace (Up).
- Copy / move of large folders run in steps with a progress bar, so the window keeps answering; a power-off in the middle never
  leaves a half-moved file (copy first, then delete the original).

## 2. A tidy layout for your files

```
/home/
  Documents/      notes.txt and other text
  Pictures/       Photos/ (camera), Wallpapers/, Paint/
  Music/          Recordings/ (voice memos), and music you add
  Games/          GameBoy/ (ROMs and .sav files), DOOM/
  Downloads/      where wget and the browser save, and files copied in over SSH
  .config/dslinux/  settings.conf, wifi.known, wifi.auto, wifi.lastip, wifi.conf, no-desktop
  .local/share/dslinux/  game records (*.best, sokoban.lvl, .savegame)
/var/log/         wlan0-test.log, the Wi-Fi window's log, boot logs (cleared or kept small)
```

- Every program and script uses the new places (the 17 paths above, collected in one header `dspaths.h` for the C programs and one
  file `/boot/paths` for the scripts, so a later change is one edit).
- **Moving the existing files happens once, at the first boot of the new ROM** (`/boot/migrate`): each old file or folder moves to its
  new place, a short report goes to the card log, and a file `/home/.config/dslinux/layout` marks it done. Nothing is deleted; a file
  that cannot move stays where it is and is listed.
- `scripts/add-roms.sh`, `doom/install.sh`, the USER-GUIDE and the PC scripts follow the new places.

## 3. Leaner and more modern

- **Remove what is unused** (about 50 MB and 60+ programs), after the user approves the list: ImageMagick, Samba, OpenVPN, boa,
  iptables, inadyn, esd*, the old desktop pieces and PIXIL, and the stale `/usr/bin` copies of the ROM's desktop programs. They are
  kept in a compressed archive on the PC (`out/removed-programs.tar.gz`) so any of them can come back; later they could become
  packages (dspkg).
- **Modern conventions:**
  - `/etc/os-release` (dsfetch and similar tools read it), the hostname `dsi` instead of `NintendoDS`;
  - one `/etc/profile` for both msh and hush: `PATH`, a prompt with user and folder, `ls --color`, the editor `nano`;
  - log files kept small: rotate at a size limit;
  - the clock from the network (`ntpd`, from the BusyBox plan).
- **Tidy ROM:** `/boot` holds only programs and scripts the system needs; the test scripts (`wifi-dsi-test`, `gl`) move to
  `/boot/tests/`.
- Unchanged on purpose: DSLinux still reaches only `sd:/linux/` on the card (see the question below).

## Steps (each ends with something checkable)

| # | Step | Check |
|---|---|---|
| 1 | Files program: places bar, selection, Delete to the Recycle Bin, Restore, Empty bin, Rename, New folder | Testbed pictures; on the console: delete a test folder, restore it, empty the bin |
| 2 | Copy / Cut / Paste with progress, Properties, Open with by type | Copy a 1 MB file and a folder on the console, open a photo, a WAV and a ROM from Files |
| 3 | `dspaths.h` / `/boot/paths`, every program on the new layout, `/boot/migrate` | Testbed: a copy of the user's `/home` migrated, every program finds its files; on the console: notes, photos, memos, ROMs, Wi-Fi, records all still there after the first boot |
| 4 | The removal list for the user's OK, then the archive and the removal | `df` before and after; every Start menu item still starts |
| 5 | `/etc/os-release`, hostname, one profile, log size limits, `/boot/tests/` | dsfetch shows the new host; a day of use keeps `/var/log` small |

## Open questions for the user

- The folder names (Documents, Pictures, Music, Games, Downloads): as proposed, or different?
- The removal list in step 4: anything there you want to keep (for example `perl`, `sqlite3`, `mc`, `irssi` stay in any case)?
- **The rest of the SD card:** today DSLinux cannot see it at all, by design. Showing it **read-only** (for example to copy ROMs or
  music from the card's own folders) is possible later; writing to it is riskier (the 2007 FAT driver, and the card also holds
  TWiLight Menu++ and your other files) and is not part of this plan.
