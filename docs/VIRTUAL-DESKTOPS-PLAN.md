# Plan: virtual desktops on the DSLinuxDSi desktop

Status: **plan only** (2026-11-17). Nothing is built yet. Window maximize/restore, L+drag resizing and the terminal's scroll bar came first (w98z).

## What it should do

- Four desktops. Each window lives on one of them, and the taskbar shows only the windows of the current desktop.
- Switching: a pager in the taskbar (four small numbered boxes next to the tray, the current one pressed in), and four quick buttons on the
  bottom screen (where Desk / Test / Log / Bench are now, or a second row).
- Moving a window to another desktop: from its taskbar button (L = right click: a small menu "Desktop 1 / 2 / 3 / 4"), and new windows
  open on the current desktop.
- Minimized windows stay minimized per desktop; a maximized window stays maximized when its desktop comes back.

## How (the parts that already exist)

- **The window manager (nanowm) does not need to know.** The taskbar (dsdesk) already follows every top-level window through the root
  window's child events (map, unmap, destroy), and minimizing is just an unmap that dsdesk notices. A desktop switch is the same thing in
  bulk: dsdesk unmaps the containers of the desktop being left and maps those of the desktop being shown.
- **dsdesk keeps the table:** for each window, its desktop and whether the user minimized it (so a window hidden by a desktop switch is not
  shown as minimized, and a minimized one is not mapped again by a switch).
- **Bottom-screen buttons:** the touch driver (`nds_ts.c`) draws the quick buttons and types a command when one is tapped. For desktops it
  would send a key that only dsdesk listens for (for example Ctrl+Alt+1..4 through the input layer), instead of typing a shell command.
- **Nothing new in the kernel or the Nano-X server.**

## Costs and limits

- Memory is the real limit, not the number of desktops. A hidden window's program keeps running and keeps its memory: the DSi has 12.6 MB
  and about 6 MB free with the desktop up. Four desktops are bookkeeping, and how many programs run at once stays the same as today.
- Each map or unmap is one Nano-X request (about 1 ms on the DS), so switching between desktops with a handful of windows takes a few
  milliseconds plus the redraw of what becomes visible.

## Steps (each ends with something checkable)

| # | Step | Check |
|---|---|---|
| 1 | dsdesk: desktop table, switch function, Ctrl+Alt+1..4 from the touch keyboard. | Testbed: two windows on desktop 1, switch to 2: empty desktop, back to 1: both windows where they were |
| 2 | Pager in the taskbar (four boxes, current pressed); the taskbar lists only the current desktop's windows. | Testbed pictures, then the console |
| 3 | "Move to desktop" menu on a taskbar button (L tap). | A window moved to desktop 3 disappears here and is there on desktop 3 |
| 4 | Bottom-screen buttons 1-4 (touch driver draws them, sends the key). | On the console: switch with one tap on the bottom screen |
| 5 | Remember each window's desktop by program name across restarts (`/home/desktops.conf`), optional. | The Terminal opens on desktop 2 after a reboot if that is where it was |

## Open questions for the user

- Four desktops, or two (less taskbar room used)?
- Bottom-screen buttons: replace Bench (rarely used) with the pager, or a second row?
