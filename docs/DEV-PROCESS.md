# How changes are made from here on

Written 2026-11-19, after a run of avoidable round trips:
- deep sleep took six builds and ended pinned;
- the Wi-Fi connect fix made things worse once;
- two builds died on compiler crashes after minutes of building;
- a patch name was refused by `.gitignore`;
- the card was pulled during an install twice;
- the user was asked again and again to run commands and copy their output.

Each rule below answers one of those.

## The loop, per change

1. **Read first.**
   - Run `scripts/cardlog.sh` when the card is in the PC: it checks the image and prints everything the last run recorded (kernel
     log highlights, Wi-Fi joining, sleep trace, crashes, memory). Don't ask the user for command output the card already has.
   - Then the code, then the reference: dswifi or libnds in `DSLinuxDSi-third-party/`, or the user's dumps (System Menu, BIOS)
     for hardware behaviour.
   - Compare with the reference byte for byte before deciding what is different.
2. **Decide with the data in hand.**
   - Read every timestamp and counter the logs have before naming a cause. (The "third connect attempt" was really the first one
     completing after 30 s; one look at the timing would have shown it.)
   - Write down the hypothesis and what result would disprove it.
3. **One build per test cycle.** Batch independent small fixes into it. An experiment changes one variable, and its build says,
   in the log, which outcome happened ("deep sleep: N s; woken with IF ..."), so the next step does not need another round.
4. **Precheck before building:** `scripts/precheck.sh <files>`. It runs in seconds:
   - kernel and ARM7 files: compiled alone in the build container with the real 2008 gcc, so its crashes and errors show at once;
   - desktop programs and tools: syntax-checked with the PC's gcc;
   - new files: names checked against `.gitignore`.
5. **Build and install:** `scripts/release.sh TAG -t files -o desc`.
   - The card may be removed only after the last line says **SAFE TO REMOVE**.
   - If the card is not in the PC, use `-n` (build only) and install later.
6. **Hand over one short test**, and say what success and failure each look like on the screen. The DSi records the details
   itself, so the user only reports what they saw.
7. **After the test:**
   - `scripts/cardlog.sh`;
   - commit (the source tree's patch, then the repo with the docs);
   - a STAGE3 entry and the ROADMAP status line. Then the next session can start from the docs alone.

## Rules learned on the hardware

- **Every wait has a limit and logs when it hits it.** An endless wait under a lock froze the desktop (w99l).
- **System actions run in a resident C program (dsautolog), not new shells.** With the desktop and Wi-Fi up, starting a script
  was "Killed": there was no block of memory big enough for another shell (w99k).
- **Risky hardware features ship switched off** and are switched on at run time for a test (e.g. `deepsleep enable`). A bad
  experiment must never cost a boot.
- **An experiment that fails twice is paused.** Write down where it stands and what to try next (as SLEEP-LOCK-PLAN.md does for
  deep sleep), and ask the user before a third attempt.
- **ARM7:**
  - code in its interrupt handler never waits without a bound;
  - BIOS calls are safe there (the dispatcher keeps interrupts masked, bios7i 0x8C), but HALTCNT only works from BIOS code (use
    SWI 6/7).
- **gcc 4.0.4 crashes** ("unrecognizable insn", "internal compiler error") on big functions with many locals: use static buffers
  and noinline helpers. `precheck.sh` finds this in seconds.
- **`lg()` in dsiwifi.c takes at most three values.**
- **File names** must not contain nand, bios, firmware or dsisd: `.gitignore` blocks them to protect the dumps.
- **The dumps:**
  - read them freely for behaviour;
  - never copy them, or anything console-unique, into the repo or the ROM;
  - record findings (addresses, register meanings) in docs instead.

## Spending less per change

- Scripts for anything done twice (cardlog.sh, precheck.sh), instead of hand-written greps each time.
- Read files by line range, not whole; keep large outputs in files and print summaries.
- Read-only subagents only for wide surveys (like the 2026-11-19 optimization audit), with a precise brief. Never for a lookup
  whose target is known.
- Don't rebuild to find out whether something compiles: precheck.
- Keep STAGE3, ROADMAP and the plans current, so no session has to re-derive what an earlier one learned.
