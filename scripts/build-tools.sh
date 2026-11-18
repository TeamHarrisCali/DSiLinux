#!/bin/sh
# Builds the small DSi tools in vendors/Nintendo/DSI with the DSi's compiler and writes them into the card's ROOTFS.IMG as /usr/bin/<name>:
#   dsfetch    neofetch for the DSi
#   memreport  where the RAM goes: per process, free memory by block size, the largest free block
# Usage: scripts/build-tools.sh [-i ROOTFS.IMG]     (release.sh runs it)
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
TOOLS="dsfetch memreport"
mkdir -p out/tools
for t in $TOOLS; do cp work/dslinux/vendors/Nintendo/DSI/$t.c out/tools/; done
scripts/in-container.sh 'export ROOTDIR=/work CONFIG_LIBCDIR=uClibc CONFIG_DEFAULTS_LIBC_UCLIBC=y; CCF="/work/tools/ucfront-gcc arm-linux-elf-gcc"; cd /out/tools &&
CF="-O2 -fomit-frame-pointer -fno-common -mswp-byte-writes -DCONFIG_NDS_ROM8BIT -mcpu=arm946e-s -mfpu=fpe3 -DEMBED -D__PIC__ -fpic -msingle-pic-base -Dlinux -D__linux__ -Dunix -D__uClinux__ -w" &&
for t in '"$TOOLS"'; do $CCF $CF -c $t.c -o $t.o && $CCF -O2 -mcpu=arm946e-s -mfpu=fpe3 -D__PIC__ -fpic -msingle-pic-base -Wl,-elf2flt="-r -s 8192" $t.o -o $t -lc -lgcc || exit 1; done' || { echo "build failed"; exit 1; }
[ -f "$IMG" ] || { echo "built out/tools: $TOOLS (card not mounted: not installed)"; exit 0; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
: > out/tools/cmds
for t in $TOOLS; do printf 'rm /usr/bin/%s\nwrite out/tools/%s /usr/bin/%s\nsif /usr/bin/%s mode 0100755\n' $t $t $t $t >> out/tools/cmds; done
debugfs -w -f out/tools/cmds "$IMG" > /dev/null 2>&1
sync
for t in $TOOLS; do
	debugfs -R "stat /usr/bin/$t" "$IMG" 2>/dev/null | grep -q "Size: $(stat -c %s out/tools/$t)" || { echo "NOT installed: /usr/bin/$t"; exit 1; }
done
echo "in ROOTFS.IMG /usr/bin: $TOOLS"
