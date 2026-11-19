#!/bin/sh
# A current BusyBox (1.36.1) for the DSi, with the hush shell (docs/BUSYBOX-HUSH-PLAN.md). The source is the release tarball in
# DSLinuxDSi-third-party/busybox-1.36.1-dl/ (checked against busybox.net's SHA-256), unpacked into out/bb/; nothing of it goes into
# the DSLinux tree. Built in the Wheezy container with the 2008 toolchain (uClibc, gcc 4.0.4) as a NOMMU flat binary, the same compiler
# options as scripts/build-tools.sh. The applets are chosen in scripts/busybox.config (a fragment applied to allnoconfig).
# Output: out/bb/busybox (flat binary) and out/bb/busybox.links (the applet names).
# Usage: scripts/build-busybox.sh [clean]
set -e
cd "$(dirname "$0")/.."
V=busybox-1.36.1
TAR=../DSLinuxDSi-third-party/$V-dl/$V.tar.bz2
SUM=b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314
[ "$(sha256sum $TAR | cut -d' ' -f1)" = "$SUM" ] || { echo "checksum of $TAR does not match"; exit 1; }
mkdir -p out/bb
# nothing changed since the last build (same applets, same compiler wrapper): keep it
if [ "$1" != clean ] && [ -f out/bb/busybox ] && [ -f out/bb/applets.txt ] && cmp -s scripts/busybox.config out/bb/fragment.config &&
   cmp -s scripts/bb-cc.sh out/bb/cc.sh; then
	echo "BusyBox up to date: out/bb/busybox ($(wc -l < out/bb/applets.txt) applets)"
	exit 0
fi
if [ "$1" = clean ] || [ ! -d out/bb/$V ]; then
	rm -rf out/bb/$V
	tar -xjf $TAR -C out/bb
fi
cp scripts/busybox.config out/bb/fragment.config
cp scripts/bb-cc.sh out/bb/cc.sh
scripts/in-container.sh '
set -e
export ROOTDIR=/work CONFIG_LIBCDIR=uClibc CONFIG_DEFAULTS_LIBC_UCLIBC=y
cd /out/bb/'$V'
make allnoconfig > /dev/null
# the fragment: every line "CONFIG_X=..." or "# CONFIG_X is not set" replaces the allnoconfig line for X
while IFS= read -r l; do
	case "$l" in
	CONFIG_*=*) k=${l%%=*} ;;
	"# CONFIG_"*" is not set") k=${l#\# }; k=${k%% *} ;;
	*) continue ;;
	esac
	sed -i "/^$k=/d;/^# $k is not set/d" .config
	echo "$l" >> .config
done < /out/bb/fragment.config
yes "" | make oldconfig > /dev/null
# the compiler: scripts/bb-cc.sh (the final link becomes a flat binary)
make -j4 SKIP_STRIP=y CROSS_COMPILE=arm-linux-elf- CC=/out/bb/cc.sh HOSTCC=gcc > /out/bb/build.log 2>&1 || { tail -30 /out/bb/build.log; exit 1; }
cp busybox_unstripped /out/bb/busybox
arm-linux-elf-flthdr -s 32768 /out/bb/busybox > /dev/null	# hush recurses: a 32 KB stack
make busybox.links > /dev/null 2>&1 || true
sed "s:.*/::" busybox.links | sort -u > /out/bb/applets.txt	# the applet names, for the ROM links
' || { echo "BusyBox build failed: out/bb/build.log"; exit 1; }
ls -la out/bb/busybox
