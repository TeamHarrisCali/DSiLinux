# Plan: a current BusyBox with the hush shell

Status: **plan only** (2026-11-17). Nothing is downloaded or built yet. The download of the BusyBox source needs the user's OK.

## Why

Today's tools are from 2004-2005: BusyBox 1.00 (about 45 tools, in the ROM as `/bin/busybox`, 256 KB), the shell `msh` (no `$(( ))`,
no functions worth using, no tab completion, odd rules such as "a && b &" running in the foreground) and nano 1.2.5. bash and fish
cannot run here (see "Limits"). A current BusyBox is the realistic modern toolbox: one program, written to work on systems like this one.

What it would add:
- **hush**, BusyBox's shell for systems without an MMU (memory-management unit), close to bash in daily use:
  - `$(( ))` arithmetic, functions with `local`, `[[ ]]` (partly), `source`, here-documents;
  - tab completion, command history kept in a file, a prompt with user and folder;
  - job control in the terminal (`&`, `jobs`, `fg`, `bg`, Ctrl+Z).
- **Tools that are missing or very old today:**
  - text: `awk`, `sed`, `less`, `head`, `tail`, `sort`, `uniq`, `cut`, `tr`, `wc`, `xargs`, `diff`, `patch`;
  - system: `top`, `free`, `uptime`, `watch`;
  - archives and checksums: `tar` with `gzip`/`bzip2`/`xz` unpacking, `md5sum`, `sha256sum`;
  - other: `hexdump`, `seq`, `date`, `nc`, `stty`, `clear` and more.
- **`wget` with HTTPS:** BusyBox has its own small TLS 1.2, so the DSi could download from HTTPS sites such as GitHub. It does not
  check certificates, so it is encryption without identity checks. This is also what a package manager (dspkg) would need.
- **`ntpd`:** sets the clock from the network. The DSi's clock says December 2016 today.

## How it fits this system (facts checked in the tree)

| Fact | Consequence |
|---|---|
| CPU without an MMU; programs are bFLT flat binaries, made by `elf2flt` | BusyBox's `CONFIG_NOMMU` build; link with `-Wl,-elf2flt` (as dsfetch and wpatest are). **ash cannot be used** (it needs `fork()`); hush is the shell BusyBox makes for this case: it runs its own subshells by starting itself again |
| Compiler gcc 4.0.4, binutils 2.17, uClibc 0.9.27 (2005), kernel headers 2.6.14 | A 2023 BusyBox may need fixes: missing C library functions (BusyBox has fallbacks for some, the rest go in a small compatibility file); system calls the kernel does not have yet (the `openat` family came in 2.6.16, `pipe2` in 2.6.27): the tools that need them are left out or patched. gcc 4.0.4 has crashed on our code before ("unrecognizable insn"); the fix was `-O1` or small code changes |
| Programs in the ROM (`/bin`, `/boot`) run where they are and share their code; programs on the card (`ROOTFS.IMG`) are copied into RAM **each time they run** | **The shell must be in the ROM.** A BusyBox of 600-800 KB loaded from the card would cost that much RAM for every open shell and every tool started; there are about 6 MB free with the desktop up |
| ROM: 772 KB left below the 4 MiB limit, plus the 256 KB of today's BusyBox that it replaces | About 1 MB for the new BusyBox. If the full set does not fit: two binaries, a core one in the ROM (hush and the everyday tools) and an extra one on the card (`awk`, `wget` with TLS, `tar`/`xz`: started now and then, so the RAM copy is acceptable) |
| The boot scripts (`/boot/rc`, `rc.common`, `session`, the Wi-Fi scripts) are written for msh | hush is more standard than msh, but each script is tested before `/bin/sh` changes. Until then hush is the interactive shell only (Terminal and SSH) |

## Steps (each ends with something checkable)

| # | Step | Check |
|---|---|---|
| 0 | Download BusyBox 1.36.1 (busybox.net, with its published SHA-256) into `DSLinuxDSi-third-party/`. **Needs the user's OK.** | Checksum matches |
| 1 | Build **hush alone** for the DSi (NOMMU, flat binary, the kernel's compiler options); fix what the 2005 toolchain trips over. If 1.36.1 cannot be made to build: 1.31.1, then 1.24.2 (older, fewer demands) | Over SSH: `/usr/bin/hush -c 'f() { echo $(( $1 * 7 )); }; f 6'` prints 42; `( echo sub )` and `$(echo cmd)` work (the self-restart) |
| 2 | Choose the tools, build the full binary, measure | A size table; the decision ROM-only or ROM + card |
| 3 | Install: the binary plus its links in `/usr/local/bin`, put first in `PATH` by `/etc/profile`, so the old tools stay as a fallback | `which awk less top` point to the new ones; a short test script runs each tool once |
| 4 | **hush as the interactive shell**: the Terminal (nxterm) and SSH logins (root's shell in `/etc/passwd`); history in `/home/.hush_history`; a prompt `root@dsi:/home#` | In the Terminal and over SSH: tab completion, Up for history after a reboot, `sleep 100 &` / `jobs` / `fg` / Ctrl+C; the desktop still starts at boot (`/etc/profile` is read by hush too) |
| 5 | Into the ROM (or the core part of it), the old BusyBox 1.00 out | ROM size check passes (release.sh step 3); `free` with three Terminals open: no more used than today |
| 6 | Boot scripts under hush, then `/bin/sh` = hush and msh retired | The full boot on the console: desktop, Wi-Fi Auto, SSH server, Save log, Shut down |
| 7 | Extras: `wget` over HTTPS (BusyBox TLS) and `ntpd` for the clock | `wget https://github.com/` saves a page; `date` is right after `ntpd -q -p pool.ntp.org` |

Rough size: steps 1 and 2 are the uncertain part (the old toolchain); 3-5 are mostly installation and testing; 6 is careful but
small; 7 is optional.

## Limits (said plainly)

- **bash and fish will not run.** They need `fork()`, which a CPU without an MMU cannot provide in the usual way; fish 4 is also
  written in Rust, which has no target for this CPU and kernel. hush covers most of what people type day to day, but bash scripts
  that use arrays or other bash-only features will not run unchanged.
- **The compiler stays old.** A current compiler needs a newer kernel (this kernel only runs programs built the "old ABI" way; newer
  compilers only build the "EABI" way, which the kernel learned in 2.6.16). That is the long "full modernization" path, separate from
  this plan.
- **Memory:** every running program still needs RAM for its data and stack; hush with tab completion and history uses somewhat more
  than msh. Step 5 measures it.

## Open questions for the user

- Which tools matter most to you (the list above is a proposal)?
- hush as the shell for scripts too (step 6), or only for typing (stop after step 5)?
