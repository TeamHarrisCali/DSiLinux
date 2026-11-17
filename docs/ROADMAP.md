# Roadmap: where things stand and what comes next

Written 2026-11-17 at the end of a long session, so work can pick up from here. Each plan has its own file with the details; this page
lists them, where each one stopped, and **every question still waiting for an answer**.

## Where things stand

- **On the card now: w98z** (`dslinux-dsimode-w98z-uc3.nds`, checksum checked). **Not yet run on the DSi.** It brings:
  - uptime fixed (it showed the date), dsfetch fixed and installed as `/usr/bin/dsfetch`;
  - the DSi asks DHCP for its last address again (`/home/wifi.lastip`), so `ssh dsi` keeps finding it;
  - **key login over SSH:** the PC's `~/.ssh/id_rsa_dsi` is in the DSi's `/home/.ssh/authorized_keys`, so the SSH server is
    key-only (no password) from its next start;
  - windows: maximize / restore box, resize with L + drag on the title bar;
  - the Terminal's scroll bar, and the Terminal fits itself to a resized window.
- **First thing next time:**
  1. Boot w98z.
  2. Check the desktop starts by itself and Wi-Fi Auto joins GuestNet.
  3. Start Network > SSH server, then run `ssh dsi` from the PC: no password.
  4. Try the maximize box, L + drag on a title bar, and the Terminal's scroll bar.
  5. Run `dsfetch`.
- Verified on the console so far:
  - the DSi's own Wi-Fi chip on open networks (DHCP, ping, `wget`), the Wi-Fi window, the desktop at boot;
  - SSH through inetd (w98x), and dsfetch (w98x, before the w98y fixes).
- Still open from the Wi-Fi work:
  - WPA2 has not joined a network yet (the hotspot was off channel 1 before w98v's scan fix);
  - connecting takes about 50 s;
  - data moves one byte at a time (CMD53 block transfers would speed it up).

## Small fixes to do (TODO)

- **nano over SSH: "Error opening terminal: xterm-256color"** (seen 2026-11-17). The PC sends its terminal type, and the DSi has no
  terminal-description files at all. nano only knows the two types built into it, `xterm` and `linux`.
  - **For now:** run `export TERM=xterm` in the SSH session, then `nano`.
  - **Fix:** `/etc/profile` maps unknown types (`xterm-256color`, `xterm-kitty`, ...) to `xterm`.
  - **To check:** nano in the desktop's Terminal too. nxterm sets `TERM=vt100`, which is not among nano's built-in types either, so it
    probably fails there as well. Either nxterm says `xterm` (then check that its escape-sequence support is enough for nano and `mc`),
    or a small terminfo set (`vt100`, `xterm`, `linux`) goes into `/usr/share/terminfo` on the card.
  - The BusyBox plan's `less`/`top` and the files plan's `mc` depend on this too.

- **tar with compression fails** (`-z`, `-j`: "Cannot fork", seen 2026-11-17). GNU tar 1.16 (`/usr/bin/tar`) starts gzip or bzip2 by
  forking a child that runs it, plus a second child that keeps copying data. The C library's `fork()` only returns "Function not
  implemented" on this CPU (no MMU). Plain `tar cf` / `xf` / `tf` work (no fork); so do the shell's pipes.
  - **For now:** unpack with `gzip -dc file.tar.gz | tar xf -` (or `bzip2 -dc file.tar.bz2 | tar xf -`), pack with
    `tar cf - folder | gzip > folder.tar.gz`.
  - **Fix, preferred:** BusyBox's tar (BusyBox plan) unpacks gz, bz2 and xz inside itself, with no second process at all.
  - **Fix, sooner if wanted:** patch GNU tar's `sys_child_open_for_compress` / `_uncompress` in `src/system.c`: start gzip with
    `vfork()` + `exec` directly on a pipe and drop the copying child.

- **Memory is getting low** (user, 2026-11-17; dsfetch showed 6.1 of 12.6 MiB used with the desktop and Wi-Fi up). Of the 16 MB, the
  4 MiB ROM image (kernel + `/boot`) sits in RAM, so 12.6 MiB is all the programs get.
  - **Step 1, measure:** a small `memreport` (how much each process holds: on this no-MMU system that is its whole program copy,
    data and stack; plus the kernel's buffers, `/tmp` and the page cache), run with the desktop, Wi-Fi and SSH up. Cut from the top
    of that list, not by guessing.
  - **Known suspects to check:**
    - the Wi-Fi firmware buffer: 128 KB kept in the kernel after the upload (`/proc/dsiwifi2fw`), which could be freed and the file
      read again when needed;
    - programs started from the card are copied whole into RAM each time (`/usr/bin`: the games, dsfiles, dsnotes, nxclock...),
      while ROM programs share their code; the busiest ones could move into the ROM (772 KB free there) or be rebuilt smaller (`-Os`);
    - every Nano-X program carries its own copy of the Nano-X library (no shared libraries here);
    - `/tmp` is RAM: the logs written there (`desktop.log`, `dsnet.log`, `wifi-*.log`, the DHCP log) only grow; cap them or keep
      them on the card;
    - stack sizes given to programs at link time (`elf2flt -s`), possibly larger than needed;
    - each Terminal keeps 200 lines of scrollback (about 38 KB);
    - kernel parts for DS-only hardware (the GBA-slot CF drivers and so on) that the DSi never uses;
    - the `autolog` loop that saves the log every 10 s.
  - Overlaps: the BusyBox plan (hush runs many tools inside itself, without a new process) and the files plan (removing unused
    programs saves card space, not RAM, unless they were running).

- **`gzip -dc make-4.3.tar.gz | tar xf -` ends in SIGSEGV** (user, 2026-11-17, the 2.3 MB make source). Likely cause: **tiny
  stacks.** On this system each program's stack size is fixed in its file when it is built (`elf2flt -s`). `tar` and `gzip` have
  **4 KB**, and GNU tar needs far more while extracting deep paths. Without an MMU an overflow is not caught: it overwrites memory,
  and that shows up as SIGSEGV. **129 of the 185 programs in `/usr/bin` have 4 KB**, including tar, gzip, bzip2, unzip, nano, less,
  links, mc, perl, sqlite3, irssi, scp and dropbear (the list is in `out/flt/stacks.txt` on the PC).
  - **Confirm:** `dmesg | tail` on the DSi after the crash names the program that faulted (the fault handler prints it).
  - **Approved by the user (2026-11-17): do this the next time the card is in the PC.**
  - **Fix:** an install step (like `install-apps.sh`) rewrites each program's stack size in the image with `flthdr -s`, without
    rebuilding: 16 KB for the small tools, 64 KB for tar, gzip, bzip2, unzip, perl, sqlite3, links, mc, irssi and nano. RAM cost: only
    while a program runs (a few tens of KB each), within the memory TODO's budget.
  - Also: tar's file holds about 860 KB of data that is copied into RAM on every run (the BusyBox plan's tar is much smaller).
- **Downloads run at about 17 KB/s** over the DSi's Wi-Fi chip (`wget` of 2.3 MB took 2 min 15 s, 2026-11-17): the cost of moving
  data over the chip's bus one byte at a time. CMD53 block transfers (Wi-Fi list above) should make this many times faster.

## The plans (none started)

| Plan | File | Next step | Waiting on |
|---|---|---|---|
| Virtual desktops | [VIRTUAL-DESKTOPS-PLAN.md](VIRTUAL-DESKTOPS-PLAN.md) | Step 1: the desktop table and switching in dsdesk | Questions A |
| A current BusyBox with the hush shell | [BUSYBOX-HUSH-PLAN.md](BUSYBOX-HUSH-PLAN.md) | Step 0: download BusyBox 1.36.1 | **Your OK for the download**, questions B |
| File management, tidy layout, leaner system | [FILES-CLEANUP-PLAN.md](FILES-CLEANUP-PLAN.md) | Step 1: the Files program with Delete / Recycle Bin | Questions C |
| Touch screen revamp (input page + dashboard) | [TOUCHSCREEN-PLAN.md](TOUCHSCREEN-PLAN.md) | Step 0: your feedback, then mock-ups | Questions D |
| Screen sleep, locking, lid sleep | [SLEEP-LOCK-PLAN.md](SLEEP-LOCK-PLAN.md) | Step 1: check the lid event, backlight off/on | Questions E |
| Later, bigger: a package manager (`dspkg`) | (no file yet) | After BusyBox: `wget` with HTTPS makes it possible | Your choice |
| Later, much bigger: new kernel and modern compiler | (no file yet) | Needed for anything that a 2005 compiler cannot build | Months of work; your choice |

Which plan goes first is your choice. A suggestion:
- **Sleep + lock** and **BusyBox + hush** are the most useful day to day.
- **The touch screen** needs your feedback before any code.
- **Virtual desktops** fit best after the touch screen's dashboard (its pager lives there).

## All open questions

**A. Virtual desktops**
1. Four desktops, or two?
2. The bottom-screen buttons 1-4: replace Bench, or a second row of buttons?

**B. BusyBox + hush**
1. OK to download BusyBox 1.36.1 from busybox.net (with its published checksum)?
2. Which tools matter most to you? (Proposed: awk, sed, less, top, free, sort, diff, tar/xz, sha256sum, wget with HTTPS, ntpd.)
3. hush also for the boot scripts (replacing msh everywhere), or only as the shell you type in?

**C. Files and cleanup**
1. The folder names Documents, Pictures, Music, Games, Downloads: as proposed, or different?
2. The removal list (ImageMagick, Samba, OpenVPN, boa, iptables, inadyn, esd, PIXIL, old desktop pieces, stale copies): anything to keep?
3. The rest of the SD card: should DSLinux be able to see it read-only later? (Writing to it stays off.)

**D. Touch screen**
1. What bothers you most today: hard-to-hit keys, missing keys or symbols, the trackpad's feel, or the quick buttons?
2. "The other screen": two pages on the touch screen with Select flipping them, or something else (for example the dashboard on the
   top screen)?
3. Which page at start: input or dashboard?
4. Dashboard priorities: status, programs, windows, files, messages: what matters most, what is missing?
5. Keyboard: QWERTY as now, bigger keys with fewer per row, or a full-screen keyboard to switch to?
6. Left- or right-handed?

**E. Sleep and lock**
1. "Screen off after": 2 minutes by default?
2. Lock with a PIN, a password, or both? Lock after every screen sleep, or only when the lid closes?
3. Lid closed: Wi-Fi stays on (SSH keeps working) or goes off (more battery)?
4. Deep sleep worth the risk, or is light sleep enough?

**From earlier**
- Set `passwd` on the DSi? With key login (w98z) the SSH server no longer accepts passwords at all, so this matters only on the
  console itself.

## Where the work lives

- **The project:** `~/Documents/Claude/DSLinuxDSi`, branch `development`. Nothing is pushed.
  - `docs/STAGE3.md` is the running log of every build and console result.
  - `docs/USER-GUIDE.md` is how to use the system.
- **The DSLinux source:** `work/dslinux` (its own git, branch `dsi`). Every change is also exported to `patches/` (128 patches).
- **Builds:** `scripts/release.sh TAG -t file... -o description` builds, packages and copies to the card when it is in the PC.
  Run `scripts/rootfs-check.sh` after any freeze.
