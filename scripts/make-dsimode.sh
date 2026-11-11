#!/bin/sh
# Re-pack the built DSLinux (DSI product) into ROMs whose header marks them as DSi programs, using BlocksDS's ndstool
# (the 2008 ndstool in the DSLinux toolchain cannot write DSi headers). Loaders start unit code 2/3 ROMs in DSi mode,
# which is what gives the program 16 MB of real RAM and an unlocked SD controller; a plain DS header gets DS mode.
# Output: out/dsi-mode/dslinux-dsimode-uc3.nds (DSi only) and -uc2.nds (DS or DSi; choose DSi mode in the loader).
set -e
cd "$(dirname "$0")/.."
NT=/opt/wonderful/thirdparty/blocksds/core/tools/ndstool/ndstool
OUT=out/dsi-mode
T=$(mktemp -d)
mkdir -p $OUT
scripts/in-container.sh "mkdir -p /out/dsi-mode/tmp && cd /out/dsi-mode/tmp && ndstool -x /work/images/dslinux.nds -9 arm9.bin -7 arm7.bin >/dev/null"
scripts/dsi-elf.sh >/dev/null
for UC in 3 2; do
  $NT -c $OUT/dslinux-dsimode-uc$UC.nds -9 $OUT/elf/arm9.elf -7 $OUT/elf/arm7.elf \
      -b work/dslinux/vendors/Nintendo/common/tux.bmp "DSLinux;Port of Linux;to the DSi" -uc $UC
done
for f in $OUT/*.nds; do echo $f; $NT -i $f | grep -E 'Unit code|TWL flags|ROM header size|DSi9|title ID'; done
sha256sum $OUT/*.nds | cut -c1-16,65-
