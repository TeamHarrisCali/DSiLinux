# Plan: screen sleep, locking, and sleep when the lid closes

Status (2026-11-18): **steps 2 and 3 built; w99e froze, w99f fixes it**, not yet tried on the console.
- **w99e:** `echo "screen off" > /proc/dsisettings` left the screens on and froze the console and SSH. The ARM7's backlight command
  used the old power-chip helpers, which wait for the SPI bus with a BIOS delay and no limit: inside the ARM7's interrupt handler
  that hangs it, and with it the SD card, Wi-Fi and touch. The same helpers froze `poweroff` long ago (STAGE3, the y build), fixed
  then with a bounded routine (`pm_xfer`), with which power-off works in DSi mode. The image was not damaged.
- **w99f:** all three power commands (backlight on/off, brightness, power off) use `pm_xfer`; a register read with the power-off bit
  set counts as a bad read and nothing is written. The **2-minute timer is off by default** until `screen off` is confirmed.
- What it does once it works: the backlights go off after the set time without a touch or button (`echo "sleep 120" >
  /proc/dsisettings`, `sleep 0` never) and at once when the lid closes; a touch or button brings them back (the lid must be open),
  and that first touch or press does nothing else; programs keep running; SSH typing does not keep the screen on; `screen off` /
  `screen on` by hand; `cat /proc/dsisettings` shows `sleep= screen= lid=`.
Backlight bits: **confirmed in the DSi's own System Menu code** (its DSi-mode ARM7 switches the backlights by setting and clearing
power-chip register 0 bits 0x04 / 0x08 / 0x0C over SPI, with the same bus values as pm_xfer; DSI-INTERNALS.md), so w99f does what
the DSi does. Still unknown: whether the ARM7's hinge bit reports the lid in DSi mode. Not yet: "Screen off after" in Settings, switching the
LCDs off too, the lock screen (step 4, questions 2-3), low battery shut down (5), deep sleep (6).

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
