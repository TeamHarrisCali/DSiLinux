# Plan: a current BusyBox with the hush shell

**Status (2026-11-19, w99v on the card, not yet tried):** the user asked for it, which answers question 1 (download). Questions 2 and 3
took the plan's proposals: the listed tools, and hush first as the interactive shell only.
- **Done:** steps 0-4 at once, with the binary straight in the ROM (half of step 5).
  - BusyBox 1.36.1 (busybox.net, SHA-256 checked) is built by scripts/build-busybox.sh. Applets: scripts/busybox.config. The compiler
    wrapper scripts/bb-cc.sh makes the final link a flat binary and drops --gc-sections there.
  - It is /bin/bb in the ROM, 369 KB, data compressed. 48 applets: hush, awk, sed, less, top, free, ps, watch, uptime, sort, uniq,
    diff, cmp, tar (gz/bz2/xz), gzip, bunzip2, unxz, sha256sum, md5sum, wget, ntpd, head, tail, cut, tr, wc, xargs, seq, cat, cp, mv,
    rm, mkdir, rmdir, ln, tee, yes, realpath, stty, reset, printf and more.
  - The links sit in /bin only where no program of that name was there, so the boot scripts keep the old BusyBox 1.00 (msh, ls,
    grep...). /bin comes before /usr/bin in PATH, so cat, cp, tar etc. now run in place from the ROM instead of being copied into RAM
    from the card.
  - /etc/profile ends with a hand-over: login shells (Terminal, SSH, the text console) exec /bin/hush, with history in
    /home/.hush_history and the prompt root@dsi:/home#. The login shell in /etc/passwd stays /bin/sh, so a ROM without hush keeps msh.
- **Left out:** stat, touch and date (their system calls or C library functions are newer than this 2.6.14 kernel and uClibc 0.9.27;
  the card's versions stay), and large-file support (uClibc built without it).
- **Next:** test hush on the DSi (the step 4 checks); then step 6 (boot scripts under hush, /bin/sh = hush, the old BusyBox out of the
  ROM) and step 7 (wget over HTTPS, ntpd).
