#!/bin/sh
# One step from source to a ROM on the SD card, the routine every build goes through:
#   1. make in the build container (log in out/<TAG>-build.log); files given with -t are touched first so make rebuilds them
#   2. package the DSi-mode ROMs (scripts/make-variants.sh, scripts/make-dsimode.sh)
#   3. check the ARM9 binary still ends below 0x02400000 (4 MiB: the kernel and romfs must fit, see docs/STAGE3.md)
#   4. move the previous CURRENT ROMs into out/dsi-mode/old/<previous tag>-<what it was> (-o, default "superseded")
#   5. if the card is in the PC: check ROOTFS.IMG, copy the uc3 ROM to the card root, compare checksums, remove older
#      dslinux-dsimode-*.nds from the card root (only those), sync
# Usage: scripts/release.sh TAG [-t file ...] [-o old-description] [-n]      (-n: build and package only, no card)
# Example: scripts/release.sh w97p -t user/microwin/src/demos/nanox/dsdesk.c -o network-menu-fix
set -e
cd "$(dirname "$0")/.."
. scripts/card.sh

TAG="$1"
[ -n "$TAG" ] || { echo "usage: $0 TAG [-t file ...] [-o old-description] [-n]"; exit 1; }
shift
TOUCH=""; OLDDESC="superseded"; NOCARD=0
while [ $# -gt 0 ]; do
	case "$1" in
	-t) TOUCH="$TOUCH $2"; shift 2 ;;
	-o) OLDDESC="$2"; shift 2 ;;
	-n) NOCARD=1; shift ;;
	*) echo "unknown option $1"; exit 1 ;;
	esac
done

OUT=out/dsi-mode
PREV=$(ls $OUT/dslinux-dsimode-*-uc3.nds 2>/dev/null | sed 's/.*dslinux-dsimode-\(.*\)-uc3.nds/\1/' | grep -v "^$TAG$" | head -1)

echo "== 1. build ($TAG)"
T=""
for f in $TOUCH; do T="$T $f"; done
scripts/in-container.sh "cd /work && ${T:+touch$T &&} make > /out/logs/$TAG-build.log 2>&1" || { echo "BUILD FAILED, see out/logs/$TAG-build.log"; grep -n "error" out/logs/$TAG-build.log | grep -v "ignored\|roach" | tail -5; exit 1; }
# the top-level make goes on after a program fails to compile and the old binary is packaged: stop here instead (w97w shipped a stale
# dssettings that way)
if grep -n ": error:\|undefined reference" out/logs/$TAG-build.log | grep -v "roach" | head -5 | grep .; then
	echo "BUILD HAD ERRORS (above), see out/logs/$TAG-build.log"
	exit 1
fi

echo "== 2. package"
scripts/make-variants.sh > /dev/null 2>&1
APPFLAGS=1 TAG=$TAG scripts/make-dsimode.sh > out/logs/$TAG-package.log 2>&1
ROM=$OUT/dslinux-dsimode-$TAG-uc3.nds
[ -f "$ROM" ] || { echo "PACKAGING FAILED: no $ROM (see out/logs/$TAG-package.log)"; exit 1; }

echo "== 3. size"
OFF=$(/opt/wonderful/thirdparty/blocksds/core/tools/ndstool/ndstool -i "$ROM" | grep "DSi9 ROM offset" | awk '{print $NF}')
LEFT=$(( 0x400000 - OFF ))
echo "ROM $(stat -c %s $ROM) bytes, ARM9 part ends at $OFF, $((LEFT / 1024)) KB left below 4 MiB"
[ $LEFT -gt 0 ] || { echo "TOO BIG: remove something from the ROM (docs/STAGE3.md, ROM size)"; exit 1; }

if [ -n "$PREV" ]; then
	echo "== 4. archive $PREV -> old/$PREV-$OLDDESC"
	mkdir -p $OUT/old/$PREV-$OLDDESC
	mv $OUT/dslinux-dsimode-$PREV-uc2.nds $OUT/dslinux-dsimode-$PREV-uc3.nds $OUT/old/$PREV-$OLDDESC/ 2>/dev/null || true
fi

[ $NOCARD = 1 ] && { echo "done (card skipped)"; exit 0; }
echo "== 5. card   (CARD IN USE: do not remove it until SAFE TO REMOVE below)"
if ! card_present; then
	echo "card not in the PC: copy $ROM later and run scripts/install-apps.sh (the games and accessories now live in ROOTFS.IMG)"
	exit 0
fi
scripts/rootfs-check.sh "$CARD/linux/ROOTFS.IMG" || echo "WARNING: ROOTFS.IMG has errors (scripts/rootfs-check.sh -y repairs it)"
cp "$ROM" "$CARD/"
sync
A=$(sha256sum "$ROM" | cut -d' ' -f1); B=$(sha256sum "$CARD/$(basename $ROM)" | cut -d' ' -f1)
[ "$A" = "$B" ] || { echo "CHECKSUM MISMATCH on the card copy"; exit 1; }
for f in "$CARD"/dslinux-dsimode-*.nds; do
	[ "$(basename "$f")" = "$(basename $ROM)" ] || rm -f "$f"
done
sync
echo "on the card, checksum ok: $(basename $ROM)"
# the programs that run from the card (/usr/bin in ROOTFS.IMG) must match this ROM
scripts/install-apps.sh -i "$CARD/linux/ROOTFS.IMG" || { echo "PROGRAMS NOT INSTALLED in ROOTFS.IMG (scripts/install-apps.sh)"; exit 1; }
scripts/install-session.sh -i "$CARD/linux/ROOTFS.IMG" || { echo "BOOT SESSION HOOK NOT INSTALLED (scripts/install-session.sh)"; exit 1; }
scripts/build-tools.sh -i "$CARD/linux/ROOTFS.IMG" | tail -1
scripts/fix-stacks.sh -i "$CARD/linux/ROOTFS.IMG" | tail -1
scripts/install-terminfo.sh -i "$CARD/linux/ROOTFS.IMG" | tail -1
scripts/set-timezone.sh -i "$CARD/linux/ROOTFS.IMG" --if-missing
ls "$CARD"/*.nds | xargs -n1 basename
sync
if scripts/rootfs-check.sh "$CARD/linux/ROOTFS.IMG" > /dev/null; then
	echo "== SAFE TO REMOVE the card ($TAG installed, image clean, written out)"
else
	echo "== ROOTFS.IMG HAS ERRORS: leave the card in (scripts/rootfs-check.sh -y repairs it)"
	exit 1
fi
