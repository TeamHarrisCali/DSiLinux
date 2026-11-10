# Stage 1: unmodified DSLinux, built from source, booted in melonDS (DS mode)

Date: 2026-11-10. **Source changes: none** (`patches/` is empty). Only the build tree was prepared.

## Result

| Claim | Status |
|---|---|
| Unmodified DSLinux (Nintendo/DLDI build, kernel `2.6.14-hsc0ds`, gcc 4.0.4) builds from source in a Debian Wheezy i386 container with the 2008 prebuilt toolchain | **Verified**: `make` exits 0 and produces `dslinux.nds` (2,268,224 bytes), `dslinuxm.nds` and `dslinux-dldi.tgz` |
| It boots in melonDS 1.1 in **DS mode** (FreeBIOS, generated firmware, direct boot, no user dumps) to the init prompt | **Verified** by screenshot ([docs/shots/stage1-ds-mode-boot.png](shots/stage1-ds-mode-boot.png)) |
| The `linux/` userland on a FAT image mounts through DLDI and `/etc/rc*` runs | **Verified** (same screenshot). `/dev/dldi1` fails (error 6) and the whole-disk `/dev/dldi` is what mounts; the card has no partition table |
| 4 MB main RAM only in melonDS DS mode | **Verified**: boot prints "Extra RAM NOT detected! You may experience crashes due to lack of memory." |
| melonDS "DLDI folder" mode | **Does not work** with this build: `FAT: bogus logical sector size 65535` ([shot](shots/stage1-ds-mode-folder-dldi-fail.png)). Use a FAT image instead |
| Real hardware | **Not tested.** Nothing from Stage 1 was run on a DS/DSi |

Not done: I could not type into the emulator (no input tool), so `free`/`dmesg` output beyond the boot log was not captured,
and the interactive shell was not exercised.

## How to reproduce

```sh
docker build -t dslinux-wheezy scripts/          # Wheezy i386 + build deps (archive.debian.org)
scripts/build-stage1.sh                           # prepare tree, config defaults (Nintendo/DLDI), dep, make
# FAT image for melonDS DLDI (256 MB FAT32) holding the linux/ tree from the tgz:
mkdir -p out/sdtest && tar -xzf work/dslinux/images/dslinux-dldi.tgz -C out/sdtest
mkdir -p out/dldi-img && mkfs.fat -F 32 -s 4 -C out/dldi-img/dldi.img 262144 && mcopy -i out/dldi-img/dldi.img -s -p out/sdtest/linux ::/
scripts/melon-ds.sh ds-img out/sdtest/dslinux.nds # config: scripts/melonds-configs/ds-img.toml (see docs/EMULATOR-CONFIGS.md)
```

Third-party inputs (kept outside this repo in `~/Documents/Claude/DSLinuxDSi-third-party/`):
- Toolchain `dslinux-toolchain-2008-01-24-i686.tbz`, SHA-256 `40e938b5...3aed`.
- Upstream `ipwndev/DSLinux` at commit `74f4eda53860ca989335ad441bbf098b6dd6835b` (shallow clone in `work/dslinux`).
- Build outputs: `dslinux.nds` SHA-256 `002b1d88...0a43`, `dslinux-dldi.tgz` SHA-256 `89531b78...f2c5`.

## Problems met and how they were handled (full errors in the build logs)

1. **Docker image would not install packages.** The `i386/debian:wheezy` base is older than the archive. Fix: add the
   `debian-security wheezy/updates` source and `dist-upgrade` first (`scripts/Dockerfile`).
2. **`user/TinySDGL` link error `cannot find -lTinyGLU`.** The git mirror drops empty directories; `user/TinySDGL/lib` did not exist,
   so `mv libTinySDGL.a ../lib` created a *file* called `lib`. Fix: create the directory (`scripts/prepare-tree.sh`).
3. **`cmatrix`: `aclocal-1.4 is needed`.** A git checkout gives all files one mtime, so make tried to regenerate autotools output.
   Fix: set increasing mtimes (sources oldest, generated files in dependency order) in `scripts/prepare-tree.sh`.
   A first attempt used the wrong direction (made the generated files older than the sources) and failed with `automake-1.4`; the second fixed it.
4. **melonDS config isolation.** My first launch passed `XDG_CONFIG_HOME` with `flatpak run --env`, which flatpak ignores for XDG variables.
   melonDS therefore started with **your real config in DSi mode**, and melonDS itself opened your BIOS/firmware/`nand.bin`
   (I never read them). `nand.bin` has a modification time of that start-up (17:03:47), same size as before, and the emulator was killed
   about two minutes later. It is worth checking that image if you value it. After that I set the variable *inside* the sandbox
   (`flatpak run --command=sh ... 'XDG_CONFIG_HOME=... melonDS'`), confirmed from the log that only the test config was opened, and
   all later runs used it (`scripts/melon-ds.sh`).
   That first accidental run did show the same unmodified kernel booting in melonDS **DSi mode** to the same prompt (the DLDI mount failed
   because your config has DLDI off). That is a data point for Stage 2, not a verified Stage 2 result.
