#!/bin/sh
# Writes this build's desktop programs (games, accessories, multimedia, bench) into /usr/bin of the DSLinux root image on the SD card.
# Only the essentials stay in the ROM (/boot: nano-X, nanowm, dsdesk, nxterm, dssettings, cmp); the rest run from the card as /usr/bin/<name>.
# A program run from the ext2 image must be loaded into RAM (it cannot run in place like in the ROM), so each copy gets the flat binary's
# RAM flag (flthdr -r, in the build container) before it is written.
# Usage: scripts/install-apps.sh [-i ROOTFS.IMG]     (card in the PC, not in the console; release.sh runs it after copying the ROM)
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
APPS="dsarcade dsmemo dsgl3d dscam landmine dsgx dsplay dsnotes dsfiles nxclock dslock"
# removed at the user's choice (2026-11-19): Bench, 3D Dodge, Tetris, Game Boy. Deleted from the image at the next install, and the
# Game Boy ROMs (sd:/linux/*.gb, *.gbc) with them
RETIRED="dsbench dsgame ntetris dsgb"
# DSLinux programs patched by this project, written as built (no RAM flag: code and data stay two smaller blocks, easier to find in
# fragmented memory); scripts/fix-stacks.sh then sets their stacks
SYSAPPS="tar nano"
SRC=work/dslinux/images/linux/usr/bin
STAGE=out/sd-apps
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
scripts/rootfs-check.sh "$IMG" || exit 1
rm -rf "$STAGE"
mkdir -p "$STAGE"
for a in $APPS $SYSAPPS; do
	[ -f "$SRC/$a" ] || { echo "missing $SRC/$a (build first)"; exit 1; }
	cp "$SRC/$a" "$STAGE/$a"
done
scripts/in-container.sh "arm-linux-elf-flthdr -r $(for a in $APPS; do printf '/out/sd-apps/%s ' $a; done)" > /dev/null || { echo "flthdr failed"; exit 1; }
CMDS=$(mktemp)
for a in $APPS $SYSAPPS; do
	printf 'rm /usr/bin/%s\nwrite %s/%s /usr/bin/%s\nsif /usr/bin/%s mode 0100755\n' $a "$STAGE" $a $a $a >> "$CMDS"
done
for a in $RETIRED; do
	printf 'rm /usr/bin/%s\n' $a >> "$CMDS"
done
# the Game Boy ROMs in the image (/home/roms; their .sav saves are kept)
for g in $(debugfs -R "ls -p /home/roms" "$IMG" 2>/dev/null | awk -F/ '$6 ~ /\.gbc?$/ {print $6}'); do
	printf 'rm /home/roms/%s\n' "$g" >> "$CMDS"
	echo "removing the Game Boy ROM /home/roms/$g (Game Boy app retired)"
done
for g in "$(dirname "$IMG")"/*.gb "$(dirname "$IMG")"/*.gbc; do
	[ -f "$g" ] && { rm -f "$g"; echo "removed the Game Boy ROM $(basename "$g") (Game Boy app retired)"; }
done
debugfs -w -f "$CMDS" "$IMG" > /dev/null 2>&1
rm -f "$CMDS"
sync
# check: every program is there with this build's size
BAD=0
for a in $APPS $SYSAPPS; do
	want=$(stat -c %s "$STAGE/$a")
	got=$(debugfs -R "stat /usr/bin/$a" "$IMG" 2>/dev/null | sed -n 's/.*Size: \([0-9]*\).*/\1/p' | head -1)
	[ "$want" = "$got" ] || { echo "NOT INSTALLED: /usr/bin/$a (image $got, build $want)"; BAD=1; }
done
[ $BAD = 0 ] || exit 1
echo "installed in ROOTFS.IMG /usr/bin: $APPS $SYSAPPS"
