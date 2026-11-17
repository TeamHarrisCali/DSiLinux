#!/bin/sh
# Builds dsfetch (vendors/Nintendo/DSI/dsfetch.c: neofetch for the DSi) with the DSi's compiler and writes it into the card's ROOTFS.IMG
# as /usr/bin/dsfetch. Usage: scripts/build-dsfetch.sh [-i ROOTFS.IMG]
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
mkdir -p out/dsfetch
cp work/dslinux/vendors/Nintendo/DSI/dsfetch.c out/dsfetch/
scripts/in-container.sh 'export ROOTDIR=/work CONFIG_LIBCDIR=uClibc CONFIG_DEFAULTS_LIBC_UCLIBC=y; CCF="/work/tools/ucfront-gcc arm-linux-elf-gcc"; cd /out/dsfetch &&
CF="-O2 -fomit-frame-pointer -fno-common -mswp-byte-writes -DCONFIG_NDS_ROM8BIT -mcpu=arm946e-s -mfpu=fpe3 -DEMBED -D__PIC__ -fpic -msingle-pic-base -Dlinux -D__linux__ -Dunix -D__uClinux__ -w" &&
$CCF $CF -c dsfetch.c -o dsfetch.o &&
$CCF -O2 -mcpu=arm946e-s -mfpu=fpe3 -D__PIC__ -fpic -msingle-pic-base -Wl,-elf2flt="-r -s 8192" dsfetch.o -o dsfetch -lc -lgcc' || { echo "build failed"; exit 1; }
[ -f "$IMG" ] || { echo "built out/dsfetch/dsfetch (card not mounted: not installed)"; exit 0; }
scripts/rootfs-check.sh "$IMG" || exit 1
printf 'rm /usr/bin/dsfetch\nwrite out/dsfetch/dsfetch /usr/bin/dsfetch\nsif /usr/bin/dsfetch mode 0100755\n' > out/dsfetch/cmds
debugfs -w -f out/dsfetch/cmds "$IMG" > /dev/null 2>&1
sync
debugfs -R "stat /usr/bin/dsfetch" "$IMG" 2>/dev/null | grep -q "Size: $(stat -c %s out/dsfetch/dsfetch)" && echo "in ROOTFS.IMG: /usr/bin/dsfetch" || { echo "NOT installed"; exit 1; }
