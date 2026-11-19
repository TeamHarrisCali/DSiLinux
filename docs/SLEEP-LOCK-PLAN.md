# Plan: screen sleep, locking, and sleep when the lid closes

Status (2026-11-18): **steps 2 and 3 work on the DSi (w99f)**: `screen off` / `screen on`, the idle timer and the lid (the screen
goes off when it closes and comes back when it opens; `cat /proc/dsisettings` shows `lid=closed`). w99e had frozen the ARM7 (an old
power-chip helper with an unbounded BIOS delay; w99f uses the bounded `pm_xfer`, and the DSi's own System Menu code switches the
backlights the same way, power-chip register 0 bits 0x04 / 0x08).
**w99g** (not yet on the console): Settings has a **"Screen off"** row (never, 30 s, 1, 2, 5, 10, 30 min; saved, applied at every
desktop start; 2 minutes by default), and **step 5**: at a critical battery (the power micro's level 1 or 0) without a charger, on two
checks 10 s apart, `dsautolog` runs `/boot/shutdown`.
**w99h, verified on the DSi** (the PIN set, lock, unlock; the "Screen off" choice works too): **step 4, the lock screen**, as the user chose (a PIN; the desktop still logs in by itself at
boot): Settings > **Lock PIN** sets it (4-8 digits, twice; empty removes it); with a PIN set, **closing the lid locks** (the taskbar
watches `/proc/dslid`), and **Start > Lock** locks now. The lock covers the whole top screen; digits from the touch keyboard or the
on-screen keypad; wrong PINs wait 1, 2, 4 ... 30 s. Stored hashed in `/home/.lockpin`; a forgotten PIN: delete that file (SSH, or
`debugfs -w -R "rm /home/.lockpin" ROOTFS.IMG` on the PC). It keeps out someone holding the DSi; SSH still works with the key.
**w99j** (built, on the card, not yet tried on the DSi):
- **The LCDs go off too**, not just the backlights, in the order the DSi's own System Menu uses (read in the user's dump, below).
  If the display stopped sending its frame interrupt with the LCDs off (the keys and the lid are read on it), the kernel turns the
  LCDs back on after a second, logs `lcdoff=0` and keeps only the backlights off until the next boot.
- **Low-battery warning:** the popup under the taskbar shows "Battery low: plug in" for 8 s when the level drops to 3 without a
  charger, and "Critical: off soon" at 1 (the clean shut down follows about 20 s later). Once per level; plugging in resets it.
- `/proc/uptime` counts from boot (it showed the year-2000 date before).

Not yet: the text console lock, deep sleep (step 6, findings below).

## What the System Menu does (the user's dump, `title/00030017/484e4145`, 2026-11-18)

Only findings are kept here; nothing from the dump is copied into the repo.
- **LCD power** (the ARM9's SDK routine at 0x26c7610):
  - **Off:** it asks the ARM7 to switch the backlights off (PM command 16, sent only while the LCDs are on), waits until at least 2
    frames have passed since the last change, then clears POWCNT1 bit 0. It saves the frame counter.
  - **On:** it refuses (unless forced) until 8 frames have passed since off, sets POWCNT1 bit 0, then sends the saved backlight state
    to the ARM7.
  - Because it counts frames while the LCDs are off, the frame interrupt keeps running then.
- **Backlights:** power-chip register 0 bits 0x04 / 0x08 (w99f, the same code).
- **Deep sleep:** not found yet.
  - The ARM7 part has the BIOS Sleep wrapper (SWI 7), but no direct branch to it.
  - The System Menu copies much of its ARM7 code into WRAM at run time (its literals point at 0x037xxxxx), so the caller has to be
    found after mapping those copies.
  - The routine near the interrupt registers (0x2f4c828) is a reset, not sleep.
  - Next: map the ARM7's copy table and find the caller.

## Today (checked in the source)

| Piece | State |
|---|---|
| **Lid** | The button driver (`arch/arm/mach-nds/button.c`) already reports the lid as a switch event (`SW_0`, from the hinge bit in the ARM7's button state) on `/dev/input/event0`. Not yet checked in DSi mode |
| **Lid daemon** | `hinged` (DSLinux 2007) waits for that event and runs `/usr/bin/lidclose` / `lidopen`: scripts that play a sound and write to `/sys/class/backlight/ndsbl/power`, which this build does not have. Off at boot (`start_hinged="NO"`) |
| **Backlight** | `/proc/dsisettings`: `backlight N`, levels 1-5, deliberately never 0 (off) |
| **Screens** | The ARM9's display power register (`POWCNT1`) switches both LCDs and the graphics engines on and off |
| **Power management** | None: `CONFIG_PM` is off, so the kernel has no suspend; the CPU only idles between interrupts |
| **Idle time** | Nano-X has a screensaver timeout and event (`GrSetScreenSaverTimeout`), unused; the text console has its own blanking |
| **Locking** | None. Anyone holding the DSi can use it; SSH has key login only (w98z) |

## 1. Screen sleep (backlight off after idle)

- **After a set time without input** (touch, buttons, keyboard): the backlights go off, then the LCDs.
- **Any input wakes it.** That first touch or button press is swallowed, so waking never clicks or types anything. Programs keep
  running (downloads, SSH, music).
- **Where:** in the kernel, next to the input drivers. They see every touch and button whether the desktop or the text console is
  running. One timer, reset on every input event, set by `/proc/dsisettings` (`sleep SECONDS`, 0 = never).
- **Kernel parts:**
  - the ARM7 command that turns the backlight off and on again;
  - `POWCNT1` to switch the LCDs off and on (both screens);
  - the "level 0" the driver refuses today, allowed only for sleep.
- **Settings:** "Screen off after" Never / 30 s / 1 min / 2 min / 5 min / 10 min (default 2 min on battery, never while charging).
  Also "Dim first" (level 1 for 10 s before going off).

## 2. Locking

- **A lock screen** (`dslock`, a Nano-X program): a full-screen window above everything, with the clock and the battery. It asks for a
  **PIN** (4-8 digits) on a large number pad, or a password from the keyboard.
- **When it locks:**
  - Start menu > **Lock**, or a button chord (Select + Start);
  - when the screen wakes from sleep, if "Lock after screen sleep" is on;
  - at boot, if "Lock at start" is on.
- **The PIN is stored hashed** (salted, `crypt()`), in `/home/.config/dslinux/lock`, never as plain text. Wrong attempts make it wait
  longer each time (1 s, 2 s, 4 s ... up to 30 s).
- **The bottom screen while locked:** only the number pad or keyboard works. The trackpad and quick buttons are off, so other windows
  cannot be reached. With the dashboard page (touch plan), the number pad is drawn there.
- **If the desktop is not running:** the text console is locked with the same PIN (a `vlock`-like prompt), started by the same trigger.
- **Said plainly:** this protects against someone picking up the DSi. It is not encryption:
  - the card can still be read in a PC (`ROOTFS.IMG` is not encrypted);
  - SSH still works with your key while the screen is locked;
  - a forgotten PIN is removed by deleting the lock file from the PC (`scripts/lock-reset.sh`).

## 3. When the lid closes

Two levels, one after the other:

### 3a. Light sleep (first)

- **Lid closed:** screens and backlights off, the same as screen sleep, but at once. Everything keeps running: Wi-Fi stays
  connected, SSH answers, downloads finish. Optionally the lock comes up.
- **Lid opened:** screens back on, the lock screen if set.
- **How:** the kernel turns the switch event into "screen off now" directly, no daemon needed. `hinged` and the 2007 scripts are
  retired (or kept for user hooks: `/home/.config/dslinux/lid-close` runs if it exists).
- **Saving:** the backlight and the LCDs are most of the DSi's power draw, so this already saves most of the battery.

### 3b. Deep sleep (if possible, later)

What a DSi game does when you close the lid: the ARM7 halts in the BIOS sleep function and the ARM9 stops, until the lid opens.
For Linux that needs:

| Need | How |
|---|---|
| Nothing in the middle of a card write | `sync`, and the SD driver holds new requests until wake |
| The kernel's clock | Timer interrupt off; on wake, the time is set again from the RTC (`do_settimeofday`, fixed in w98y), so uptime and timers jump correctly |
| The DSi's Wi-Fi chip | It loses its firmware when powered down: `wlan0` goes down before sleep, and the boot Auto connection runs again after wake (about a minute) |
| Sound, camera, microphone | Off before sleep, back on after |
| Wake source | Lid open (and the power button) only |
| A way out if wake fails | Holding the power button still powers off as today; the next boot's crash guard brings the text console |

- **Risk:** this is the hardest part of all the plans. The DSi's power-management chip in DSi mode, and the ARM7's sleep with our
  own ARM7 code, are both untested. So deep sleep comes after light sleep works, and only as a Settings option ("Lid closed: screen
  off / sleep").
- **Battery check:** the battery level is only 0-15, so the saving is measured over hours, comparing the level before and after.

## 4. Low battery (small, on the way)

At level 1 and not charging: a warning, then a clean shut down (save the log, `sync`, power off) instead of losing power in the
middle of a card write.

## Steps (each ends with something checkable)

| # | Step | Check |
|---|---|---|
| 1 | Check the lid event in DSi mode; the kernel's backlight off/on and LCD off/on, by a test command | Over SSH: `cat /dev/input/event0` shows close/open; `echo screen off > /proc/dsisettings` darkens both screens, `on` brings them back |
| 2 | Screen sleep: idle timer in the kernel, first input swallowed; Settings "Screen off after" | Leave it 30 s: dark; a tap wakes it without clicking; typing over SSH does not keep it awake (only local input counts) |
| 3 | Lid: light sleep in the kernel; `hinged` retired | Close the lid during a download over SSH: it continues; open: screens back |
| 4 | Lock screen with PIN; Start > Lock, Select + Start, after sleep, at start; text console lock; `scripts/lock-reset.sh` | Lock, wrong PIN waits, right PIN unlocks; the trackpad cannot reach other windows while locked |
| 5 | Low battery shut down | Simulated level (a test switch) shuts down cleanly |
| 6 | Deep sleep (optional, after 1-5) | Lid closed an hour: wakes on opening, the time is right, Wi-Fi reconnects by itself, the battery dropped less than with light sleep |

## Questions for the user

- Default "Screen off after": 2 minutes?
- Lock: PIN, password, or both? Lock after every screen sleep, or only when the lid closes?
- Lid closed: should Wi-Fi stay on (SSH keeps working) or go off to save more battery?
- Is deep sleep worth the risk to you, or is light sleep enough?
