#!/bin/sh
# Terminal descriptions for nano and the other curses programs on the DSi: compiled here from the PC's terminfo (infocmp + tic) and
# written into ROOTFS.IMG's /usr/share/terminfo, where the DSi's ncurses 5.4 (2005) looks. Without them every terminal type failed
# ("Error opening terminal: xterm"). ncurses 5.4 reads only the old format (magic 0432) and entries up to 4 KB: entries with more than
# 32767 colour pairs (the *-256color ones) are written by tic in the newer 32-bit format, so their pairs are capped at 32767 first.
# Usage: scripts/install-terminfo.sh [-i ROOTFS.IMG]     (release.sh runs it)
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
TYPES="linux xterm xterm-256color xterm-color vt100 vt102 vt220 screen screen-256color tmux tmux-256color ansi dumb"
command -v tic > /dev/null && command -v infocmp > /dev/null || { echo "needs tic and infocmp (ncurses) on the PC"; exit 1; }
D=out/terminfo
rm -rf $D $D-src
mkdir -p $D $D-src
for t in $TYPES; do
	infocmp -1 -I "$t" > "$D-src/$t.ti" 2>/dev/null || { echo "no description of $t on this PC: skipped"; rm -f "$D-src/$t.ti"; continue; }
	sed -i -E 's/pairs#(0x10000|65536)/pairs#32767/' "$D-src/$t.ti"
	tic -o $D "$D-src/$t.ti" 2> /dev/null || echo "tic failed: $t"
done
# every file in the old format and small enough
BAD=0
for f in $(find $D -type f); do
	[ "$(head -c2 "$f" | od -An -tx1 | tr -d ' ')" = "1a01" ] || { echo "not the old format: $f"; BAD=1; }
	[ $(stat -c %s "$f") -le 4096 ] || { echo "over 4 KB: $f"; BAD=1; }
done
[ $BAD = 0 ] || exit 1
[ -f "$IMG" ] || { echo "built $D (card not mounted: not installed)"; exit 0; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
{
	img_mkdir /usr/share/terminfo
	for d in $(cd $D && ls); do
		img_mkdir /usr/share/terminfo/$d
		for f in $(cd $D/$d && ls); do
			echo "rm /usr/share/terminfo/$d/$f"
			echo "write $D/$d/$f /usr/share/terminfo/$d/$f"
			echo "sif /usr/share/terminfo/$d/$f mode 0100644"
		done
	done
} > $D-src/cmds
debugfs -w -f $D-src/cmds "$IMG" > /dev/null 2>&1
sync
N=0
for f in $(cd $D && find . -type f); do
	debugfs -R "stat /usr/share/terminfo/${f#./}" "$IMG" 2>/dev/null | grep -q "Size: $(stat -c %s $D/$f)" && N=$((N+1)) || { echo "NOT installed: $f"; BAD=1; }
done
[ $BAD = 0 ] && echo "in ROOTFS.IMG /usr/share/terminfo: $N terminal types"
