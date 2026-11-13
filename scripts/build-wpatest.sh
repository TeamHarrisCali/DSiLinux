#!/bin/sh
# Builds wpatest (testbed/wpa_test.c + the kernel's arch/arm/mach-nds/dsiwpa.c) for the DSi with the kernel's compiler options
# (-mswp-byte-writes included: gcc 4.0.4 has crashed on this code before), so the WPA2 crypto is checked on the console itself,
# and writes it into the card's ROOTFS.IMG as /usr/bin/wpatest (Start > Network > DSi Wi-Fi test runs it first).
# Usage: scripts/build-wpatest.sh [-i ROOTFS.IMG]
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
mkdir -p out/wpatest
cp testbed/wpa_test.c work/dslinux/linux-2.6.x/arch/arm/mach-nds/dsiwpa.c out/wpatest/
scripts/in-container.sh 'export ROOTDIR=/work CONFIG_LIBCDIR=uClibc CONFIG_DEFAULTS_LIBC_UCLIBC=y; CCF="/work/tools/ucfront-gcc arm-linux-elf-gcc"; cd /out/wpatest &&
CF="-O2 -fomit-frame-pointer -fno-common -mswp-byte-writes -DCONFIG_NDS_ROM8BIT -mcpu=arm946e-s -mfpu=fpe3 -DEMBED -D__PIC__ -fpic -msingle-pic-base -Dlinux -D__linux__ -Dunix -D__uClinux__ -DDSIWPA_HOST -w -I. -I/work/include" &&
$CCF $CF -c wpa_test.c -o wpa_test.o && $CCF $CF -c dsiwpa.c -o dsiwpa.o &&
$CCF -O2 -mcpu=arm946e-s -mfpu=fpe3 -D__PIC__ -fpic -msingle-pic-base -Wl,-elf2flt="-r -s 16384" wpa_test.o dsiwpa.o -o wpatest -lc -lgcc' || { echo "build failed"; exit 1; }
[ -f "$IMG" ] || { echo "built out/wpatest/wpatest (card not mounted: not installed)"; exit 0; }
scripts/rootfs-check.sh "$IMG" || exit 1
printf 'rm /usr/bin/wpatest\nwrite out/wpatest/wpatest /usr/bin/wpatest\nsif /usr/bin/wpatest mode 0100755\n' > out/wpatest/cmds
debugfs -w -f out/wpatest/cmds "$IMG" > /dev/null 2>&1
sync
debugfs -R "stat /usr/bin/wpatest" "$IMG" 2>/dev/null | grep -q "Size: $(stat -c %s out/wpatest/wpatest)" && echo "in ROOTFS.IMG: /usr/bin/wpatest" || { echo "NOT installed"; exit 1; }
