# Plan: the touch screen, revamped

Status: **plan only, waiting for the user's feedback** (2026-11-17). Nothing is changed yet. Related plans:
[VIRTUAL-DESKTOPS-PLAN.md](VIRTUAL-DESKTOPS-PLAN.md) (the pager), [FILES-CLEANUP-PLAN.md](FILES-CLEANUP-PLAN.md) (file browsing),
[BUSYBOX-HUSH-PLAN.md](BUSYBOX-HUSH-PLAN.md).

## Today (checked in the source)

The bottom screen is drawn by the kernel's touch driver (`nds_ts.c`) from 8x8 tiles, in three bands:
- **Quick buttons** (top two tile rows): Desk, Test, Log, Bench. A tap types the command into the text console, so they only make
  sense when the console has the keyboard.
- **Trackpad** (the middle): drag moves the pointer, a tap is a left click, with four 16x16 arrow keys in its bottom right corner.
- **Keyboard** (the bottom 15 tile rows, 120 pixels): the 2005 DSLinux keyboard picture, lower and upper case. Ctrl and Alt stay down
  for the next key.

The pieces a revamp can build on are already there:
- **A full-colour bottom screen:** `/dev/fb1` is the touch screen as a framebuffer. Opening it switches the touch screen to bitmap mode
  (`ndstouch_open_fb1`), closing it brings the keyboard back (`ndstouch_close_fb1`).
- **Free buttons:** Select and Start arrive as button events, and the desktop uses neither.
- **A launcher to talk to:** the taskbar program (dsdesk) already starts programs and keeps the window list; it can take commands from
  another program through a small pipe (`/tmp/dsdesk.cmd`).

## The idea: two pages on the touch screen

**Select flips between them** (and a small tab in a corner does too). The top screen stays the desktop.

### Page 1: Input (keyboard + mouse), revamped

- **A new keyboard picture**, drawn for this screen: clearer letters, bigger keys where it counts (space, Enter, Backspace). Layers:
  letters, Shift (one key) or Caps, and a **symbols / numbers layer** (like a phone's `?123`).
- **Always there:** Esc, Tab, Ctrl, Alt and the arrows.
- **A pressed key lights up** while the stylus is on it, so you see what you hit. Holding a key repeats it.
- **Trackpad:**
  - tap = left click; L or a long press = right click;
  - **tap and hold, then drag** = drag (moving a window, selecting text);
  - **a scroll strip along its right edge** = scroll the window under the pointer (Up/Down or Page keys).
- **Layouts:** keyboard + trackpad (the default), a full-screen trackpad, or a full-screen keyboard (bigger keys). Chosen in Settings
  or with a long press on the page tab.
- The quick buttons change meaning: they act on the desktop (not the text console), or become the virtual-desktop pager 1-4.

### Page 2: Dashboard (system, programs, files)

Drawn in full colour by a small program (`dspanel`) on `/dev/fb1`. It is not a second window system, which would cost too much
memory.

- **Status:**
  - the time and date in large type;
  - battery with percentage (and charging);
  - Wi-Fi: chip, network, address, signal;
  - memory and CPU load as bars, the card image's free space, uptime;
  - volume and brightness sliders.
- **Programs:** a grid of icons (Terminal, Files, Notes, Photos, Camera, Game Boy, DOOM, Settings, Wi-Fi...). A tap starts it on the
  top screen (through dsdesk).
- **Open windows:** a list. Tap = bring it to the front; buttons to minimize or close. With virtual desktops, the 1-4 pager lives here
  too.
- **Files:** Home's places (Documents, Pictures, Music, Games, Downloads) and the last few files opened. A tap opens the file in its
  program on the top screen. Full file management stays in the Files window (files plan).
- **Messages:** "Wi-Fi connected 192.168.1.45", "battery low", "SSH login from ...". Shown for a few seconds, kept in a short list.

Memory: dspanel draws directly into the framebuffer with its own small font; it should stay around 100-200 KB of RAM. It redraws the
status once a second, and only what changed.

## How (technical outline)

| Part | Change |
|---|---|
| Kernel, touch driver | A "page" state; Select (or the tab) flips it. On the dashboard page the touches go to an input device that dspanel reads (absolute x/y), not to the keyboard or trackpad. Page 1's new keyboard art, key highlighting, repeat, the drag gesture and the scroll strip are all in the driver (it already draws page 1) |
| `dspanel` (new, C) | Opens `/dev/fb1` while page 2 is shown, draws, reads touches, sends commands to dsdesk; reads the same sources as dsfetch and the tray (`/proc`, `/proc/dsisettings`, the Wi-Fi state) |
| dsdesk | Listens on `/tmp/dsdesk.cmd`: `run PROGRAM`, `raise WINDOW`, `minimize WINDOW`, `close WINDOW`, `desktop N`; writes its window list to `/tmp/dsdesk.windows` for dspanel |
| Settings | Default page, keyboard layout, trackpad speed (exists), left-handed (trackpad and keyboard swapped) |
| PC test bed | A second framebuffer file for the bottom screen and a "touch" command in `nxctl`, so dspanel can be checked with pictures before the console |

## Steps (each ends with something checkable)

| # | Step | Check |
|---|---|---|
| 0 | **Your feedback** (questions below) and **mock-ups**: pictures of both pages made on the PC, for you to mark up before any code | You pick or change the mock-ups |
| 1 | Page switching: Select flips; page 2 shows a test picture on `/dev/fb1`; touches on page 2 reach a test program | On the console: flip back and forth, the keyboard returns intact, touches print their x/y |
| 2 | dspanel v1: status and the program grid; dsdesk's command pipe | A tap on Notes opens Notes on the top screen; the battery and Wi-Fi match the tray |
| 3 | Window list, minimize/close, messages; the pager if virtual desktops are done | Bring a buried window to the front from the touch screen |
| 4 | Files: places and recent files | Open a photo and a note from the touch screen |
| 5 | Page 1 revamp: new keyboard art, symbols layer, highlight, repeat, drag, scroll strip | Type a command with symbols without the Shift dance; scroll the Terminal from the strip; drag a window with tap-and-hold |
| 6 | Settings: default page, layouts, left-handed | Each setting survives a reboot |

## Feedback wanted (step 0)

1. **What bothers you most** on today's touch screen: hard-to-hit keys, missing keys or symbols, the trackpad's feel (speed, clicks,
   no drag), or the quick buttons?
2. **"The other screen":** two pages on the touch screen with Select flipping them, as above? Or did you mean something else, such as
   the dashboard on the top screen (it would cover the desktop while shown)?
3. Which should the touch screen **show at start**: the input page or the dashboard?
4. **The dashboard's priorities:** which of status / programs / windows / files / messages matter most, and what is missing?
5. **Keyboard:** QWERTY as now, bigger keys with fewer per row, or a full-screen keyboard you switch to when typing a lot?
6. **Left- or right-handed** use (where the trackpad and the scroll strip sit)?
