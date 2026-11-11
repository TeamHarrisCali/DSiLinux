# DSLinuxDSi

Attempt to boot DSLinux (uClinux 2.6.14 for the Nintendo DS) on a Nintendo DSi XL and then use DSi-only hardware.

| Stage | State |
|---|---|
| 0 Research and feasibility | Done: [docs/FEASIBILITY.md](docs/FEASIBILITY.md) |
| 1 Unmodified build, boot in melonDS DS mode | Done and emulator-verified: [docs/STAGE1.md](docs/STAGE1.md) |
| 2 16 MB DSi-mode build | Boots in melonDS DSi mode (user-run); not on real hardware; `MemTotal: 14072 kB` read in melonDS: [docs/STAGE2.md](docs/STAGE2.md) |
| 3 DSi features | DSi mode, 16 MB RAM, DSi-mode touch and SD card init **verified on a real DSi XL** (SD card reads and FAT mount confirmed; DSLinux userland from the card still to confirm; writes off); clocks not started: [docs/STAGE3.md](docs/STAGE3.md) |

Nothing in this repo has been run on real hardware yet. A final README replaces this one at the end.
