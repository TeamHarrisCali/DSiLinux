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
