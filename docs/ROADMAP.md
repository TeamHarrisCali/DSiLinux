# Roadmap: where things stand and what comes next

Written 2026-11-17 at the end of a long session, so work can pick up from here. Each plan has its own file with the details; this page
lists them, where each one stopped, and **every question still waiting for an answer**.

## Where things stand

- **On the card now: w99j** (2026-11-18), not yet tried on the DSi:
  - the LCDs go off with the backlights (System Menu order, from the dump), with a guard that turns them back on if the display's
    frame interrupt stops;
  - a low-battery warning in the taskbar popup (level 3: "Battery low: plug in"; 1: "Critical: off soon");
  - `/proc/uptime` counts from boot.
- **Verified on the DSi:** screen sleep and the lid (w99f), the "Screen off" choice in Settings, **the PIN lock** (set, lock, unlock;
  w99h), Sound test, including while the Wi-Fi chip connects (the processors' message-queue deadlock, fixed in w99i; the user:
  "it works"). Everything in the
  TODO list below is **verified on the DSi** as of w99d: tar `-z`, the memory reserve and memreport, the clock and time zone (and
  the DSi's clock chip keeps the time across a restart), about 1.5 MB less memory in use, **nano over SSH**.
- **w98z** (2026-11-17) brought:
  - uptime fixed (it showed the date), dsfetch fixed and installed as `/usr/bin/dsfetch`;
  - the DSi asks DHCP for its last address again (`/home/wifi.lastip`), so `ssh dsi` keeps finding it;
  - **key login over SSH:** the PC's `~/.ssh/id_rsa_dsi` is in the DSi's `/home/.ssh/authorized_keys`, so the SSH server is
    key-only (no password) from its next start;
  - windows: maximize / restore box, resize with L + drag on the title bar;
  - the Terminal's scroll bar, and the Terminal fits itself to a resized window.
- **First thing next time:**
  1. Boot w99d (it includes everything before it).
  2. Check the desktop starts by itself and Wi-Fi Auto joins GuestNet.
  3. Start Network > SSH server, then run `ssh dsi` from the PC: no password.
  4. Try the maximize box, L + drag on a title bar, and the Terminal's scroll bar.
  5. Run `dsfetch`.
- Verified on the console so far:
  - the DSi's own Wi-Fi chip on open networks (DHCP, ping, `wget`), the Wi-Fi window, the desktop at boot;
  - SSH through inetd (w98x), and dsfetch (w98x, before the w98y fixes).
- Still open from the Wi-Fi work: see "The DSi's Wi-Fi chip" below.

## Small fixes to do (TODO)

**All done and verified on the DSi (w99a-w99d, 2026-11-18)** except the download speed (Wi-Fi chip item 1). Last results: nano
works over SSH (w99d); the time is right after Wi-Fi and stays right after a restart without Wi-Fi (w99c's clock-chip write);
memreport: programs 2.9 MB, 7.4 MB free, largest free block 4 MB.

- **Memory (the real cause of "tar: SIGSEGV").** The card log showed `tar: page allocation failure. order:8`: 2.1 MB free, tar needing
  868 KB in one piece. A free 1 MB block existed, but the kernel's reserve check refused it: the reserve (`min_free_kbytes`) was
  508 KB, and part of it must sit in large pieces. The shell shows the process killed after exec's point of no return as SIGSEGV.
  The 4 KB stacks were not the cause: the loader puts the stack at the end of a power-of-two block, so the rounding slack below it
  already works as stack (tar had about 180 KB).
  - **Done:**
    - the reserve is 192 KB. w99a tried this from the boot script, but this kernel has no `/proc/sys`, so it did nothing; w99b sets it
      in the kernel;
    - the Wi-Fi firmware copy (up to 128 KB) is freed once the chip runs it;
    - the loader's message says "not enough memory in one piece ... out of memory";
    - the Wi-Fi window's logs in `/tmp` (RAM) are capped at 32 KB each;
    - **`memreport`**: each process's own memory, rounding slack and shared memory, the reserve, the free blocks by size and the
      largest one. w99b fills in the kernel's `/proc/PID/maps` (an empty stub on no-MMU before) so these numbers are real; the old
      per-process figures were wrong (the kernel sized regions from a page field its allocator never sets).
  - w99a's memreport, totals: 2.7 MB free, largest free block 1 MB. **w99b** (reserve in the kernel): **5.8 MB free, largest free
    block 4 MB**; per process (own memory): dropbear 524 KB, nano-X 520 KB, **six shells of about 400 KB each** (2.4 MB: the SSH
    session, the Terminal's, the `desktop` script, the login shell behind it, `autolog` and one more), dsdesk 280 KB, autolog's
    `sleep` 256 KB, nanowm 132 KB.
  - **w99c on the DSi:** programs 2.9 MB (was 4.4), free 7.4 MB (was 5.8), largest free block 4 MB; dropbear 524, nano-X 456, three
    shells of 400 KB (the Terminal's, the SSH session's, the `desktop` script), dsdesk 280, init and nanowm 132, dsautolog 64 KB.
  - **Done in w99c:** `autolog` (a shell plus a resident `sleep`, about 650 KB, and savelog's burst of programs every 10 s) is
    replaced by `dsautolog`, a small C program that saves only when the kernel log or a log file changed (or every 5 minutes); the
    login shell gives its place to the desktop instead of waiting behind it (about 400 KB); the SSH server window closes on Enter
    instead of keeping a shell (about 400 KB while it was open).
  - **Next:**
    - the shells that remain (the Terminal's, the SSH session's, the `desktop` script): the BusyBox plan's hush may be smaller
      (msh 1.00 holds about 250 KB of data each);
    - whether the RAM flag on our card programs (one big block for code + data) or two smaller blocks fragments less;
    - an "exact size" allocator: it would give back the rounding slack, but that slack doubles as stack space today, so it needs the
      stack sizes below and testing on the console.
  - Other suspects from before, still to measure: every Nano-X program carries its own copy of the Nano-X library; kernel parts for
    DS-only hardware; 200 lines of scrollback per Terminal (about 38 KB).
- **Stack sizes:** done (approved 2026-11-17).
  - `scripts/fix-stacks.sh` raised the stack field of **149 programs** in the image, towards 64 KB for the big ones (tar, gzip, nano,
    perl, links ...) and 16 KB for the rest. Each raise stays **within the memory block the program already gets**, so nothing needs
    more RAM.
  - `release.sh` runs it after every install; the list of changes is in `out/stacks/report.txt`.
- **nano: "Error opening terminal".** Three layers, found one at a time:
  - w99b installed the terminal descriptions in `/usr/share/terminfo` (the DSi had none);
  - w99c set `TERMINFO` (the library had no default directory) and linked `/home/.terminfo`: still failing;
  - **the real cause:** the DSi's ncurses 5.4 was built **without file support at all** (no `USE_DATABASE`): its only terminal was
    the built-in `linux`. Built on the PC with file support, the same ncurses reads every installed description. **w99d** rebuilds
    it with file support and the `/usr/share/terminfo` default, and relinks nano (installed with the other system programs).
  - Still to relink with the new ncurses: mc and irssi (built through their own configure stamps); dialog, hexedit, sc and the
    other small users if they are ever needed.
  - The DSi's ncurses (5.4, 2005) reads terminal descriptions from `/usr/share/terminfo`, and the DSi had none, so every type
    failed. `scripts/install-terminfo.sh` compiles 16 (linux, xterm, xterm-256color, vt100, screen, tmux, ...) on the PC in the old
    format that ncurses reads and writes them into the image (release.sh runs it).
  - `/etc/profile` keeps those types and turns anything else into `xterm`.
  - The desktop's Terminal says `linux`, with Home/End sending the Linux console's codes. Fixed on the way: the Terminal answered
    nano's "hide the cursor" sequence as if asked "what are you?", typing garbage into nano.
- **tar `-z` / `-j` ("Cannot fork").** Done, **works on the DSi** (w99a).
  - tar starts gzip or bzip2 with `vfork()` + `exec`, straight on the archive file or its stdin/stdout, joined by a pipe.
  - Not covered: remote tapes (rmt) and `--to-command`, which still need fork().
- **The clock: works on the DSi (w99c).** (tar: "time stamp ... in the future"; the DSi's clock said December 2016.) Asked for (2026-11-18): when it connects to
  Wi-Fi, find its time zone and correct the DSi's own date and time.
  - w99b tried `ntpclient`: NTP is blocked on GuestNet, it never got an answer and stayed in memory; `date` still said 2016.
  - **w99c: `httpdate`**, run by the Wi-Fi window after each connection (also the automatic one at boot):
    - the time from a web server's `Date:` header over plain HTTP (works wherever `wget` does), about a second accurate;
    - the **time zone from where the network is** (worldtimeapi.org, then ip-api.com: free services over plain HTTP that see the
      DSi's public address), written to `/etc/config/TZ`; `scripts/set-timezone.sh ZONE` picks one by hand and turns this off,
      `scripts/set-timezone.sh auto` turns it back on;
    - the local time **written into the DSi's clock chip** (new: the kernel can write the RTC), so the DSi's own menu shows it and
      the next boot starts right even without Wi-Fi (`httpdate -L` at boot converts the chip's local time to UTC).
  - The card is set to Central with automatic detection on.

- **Card scripts and `debugfs mkdir`** (found and fixed 2026-11-18): `debugfs`'s `mkdir` on a directory that already exists orphans a
  new one and damages the image's counts. A second run of a script hit it (repaired with `rootfs-check.sh -y`; the empty orphan is
  `/lost+found/#866`, an older one `#820`). All six scripts that make directories now use `img_mkdir` (scripts/card.sh), which skips
  existing ones; tested twice in a row on a scratch image, clean.
- **Downloads run at about 17 KB/s** over the DSi's Wi-Fi chip (`wget` of 2.3 MB took 2 min 15 s, 2026-11-17): the cost of moving
  data over the chip's bus one byte at a time. CMD53 block transfers should make this many times faster. **Not started** (larger:
  the ARM7's SDIO code).

## The plans (none started)

| Plan | File | Next step | Waiting on |
|---|---|---|---|
| Virtual desktops | [VIRTUAL-DESKTOPS-PLAN.md](VIRTUAL-DESKTOPS-PLAN.md) | Step 1: the desktop table and switching in dsdesk | Questions A |
| A current BusyBox with the hush shell | [BUSYBOX-HUSH-PLAN.md](BUSYBOX-HUSH-PLAN.md) | Step 0: download BusyBox 1.36.1 | **Your OK for the download**, questions B |
| File management, tidy layout, leaner system | [FILES-CLEANUP-PLAN.md](FILES-CLEANUP-PLAN.md) | Step 1: the Files program with Delete / Recycle Bin | Questions C |
| Touch screen revamp (input page + dashboard) | [TOUCHSCREEN-PLAN.md](TOUCHSCREEN-PLAN.md) | Step 0: your feedback, then mock-ups | Questions D |
| Screen sleep, locking, lid sleep | [SLEEP-LOCK-PLAN.md](SLEEP-LOCK-PLAN.md) | **Steps 2-4 verified** (screen off when idle and on lid close, the Settings choice, the PIN lock); step 5 (critical battery) built; w99j: LCDs off too and the battery warning (untested); left: deep sleep (System Menu findings in the plan), text console lock | E3 (Wi-Fi with the lid closed), E4 (deep sleep) |
| The DSi's Wi-Fi chip: faster, quicker to connect, WPA2 | (this page, below) | Speed: the 4-bit bus and block transfers | Questions F |
| Later, bigger: a package manager (`dspkg`) | (no file yet) | After BusyBox: `wget` with HTTPS makes it possible | Your choice |
| Later, much bigger: new kernel and modern compiler | (no file yet) | Needed for anything that a 2005 compiler cannot build | Months of work; your choice |

### The DSi's Wi-Fi chip (Atheros AR6013), what is left

Added 2026-11-18 at the user's request. Today it joins open networks, gets an address and stays connected (wget, SSH, NTP work), but:

| # | Item | Today | Idea | Check |
|---|---|---|---|---|
| 1 | **Speed** | about 17 KB/s (`wget` 2.3 MB in 2 min 15 s) | Two separate costs: the bus runs **1 bit wide** (the bring-up log says "bus 1-bit"; the chip can do 4) and data moves **one byte per command** (CMD52). 4-bit mode and CMD53 block transfers (up to 512 bytes per command) in the ARM7's SDIO code | the same `wget` many times faster |
| 2 | **Connecting** | about 50 s: the chip answers only the third connect command | find why the first two are ignored (timing after the scan, a missing setup command); dswifi's order as the reference | joins within a few seconds |
| 3 | **WPA2** | built and the crypto verified on the DSi, but it has never joined a network (the hotspot was on a channel the old scan missed; w98v scans every channel) | a test on a WPA2 phone hotspot (2.4 GHz, channel 1-11). WorkNet cannot be the test: it asks for a username and password (WPA2-Enterprise) | DHCP and ping over WPA2 |
| 4 | **Staying connected** | a dropped connection is not noticed or rejoined | rejoin after a disconnect event; signal strength in the tray; scan while connected | walk out of range and back: it rejoins by itself |
| 5 | **Power** | the chip always runs at full power | its power-save mode while idle (ties in with the sleep plan) | longer battery life with Wi-Fi on |
| 7 | **WPA2-Enterprise** (username and password, like WorkNet) | not supported: only WPA2 with one shared password | 802.1X with PEAP/MSCHAPv2 on top of the WPA2 code: a TLS client, MSCHAPv2, more memory; a project of its own | joins WorkNet |
| 6 | **Firmware** | the chip runs the firmware from your DSi's own system files (copied from your dump with `scripts/add-dsi-wifi-fw.sh`) | Nintendo never released a newer one for this chip (the "update" you meant was the time and date on connecting: done in w99c, see the TODO list) | (nothing to do) |

Items 1 and 2 are the ARM7 and the kernel's `dsiwifi.c`; 3 needs only a test; 4 and 5 build on 1 and 2.

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
2. ~~Lock with a PIN or a password?~~ **A PIN, and log in automatically at boot** (user, 2026-11-18): it locks when the lid closes.
3. Lid closed: Wi-Fi stays on (SSH keeps working) or goes off (more battery)?
4. Deep sleep worth the risk, or is light sleep enough?

**F. The DSi's Wi-Fi chip**
1. Speed first (item 1), or the quicker connect (item 2)?
2. ~~WPA2 test on WorkNet?~~ No: WorkNet needs a username and password (WPA2-Enterprise, item 7). The test needs a WPA2 phone hotspot.

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
