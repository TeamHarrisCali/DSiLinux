#!/bin/sh
# Copies Game Boy ROMs (your own games) into /home/roms inside the DSLinux root image on the SD card, for dsgb (Start > Games > Game Boy).
# Usage: scripts/add-roms.sh [-i /path/to/ROOTFS.IMG] game1.gb game2.gb ...
# Needs debugfs (e2fsprogs). The card must be in the PC, not in the console. Existing files with the same name are replaced.
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
[ $# -gt 0 ] || { echo "usage: $0 [-i ROOTFS.IMG] game.gb ..."; exit 1; }
"$(dirname "$0")/rootfs-check.sh" "$IMG" || exit 1
CMDS=$(mktemp)
img_mkdir /home/roms > "$CMDS"
for f in "$@"; do
	case "$f" in *.gb|*.GB|*.gbc|*.GBC) ;; *) echo "skipping $f (not .gb / .gbc)"; continue ;; esac
	name=$(basename "$f" | tr ' ' '_' | tr -cd 'A-Za-z0-9._-')
	[ -f "$f" ] || { echo "skipping $f (not a file)"; continue; }
	[ "$(stat -c %s "$f")" -le 8388608 ] || { echo "skipping $f (over 8 MB)"; continue; }
	echo "rm /home/roms/$name" >> "$CMDS"
	echo "write \"$f\" /home/roms/$name" >> "$CMDS"
	echo "adding $name"
done
debugfs -w -f "$CMDS" "$IMG" > /dev/null 2>&1
rm -f "$CMDS"
echo "now in /home/roms:"
debugfs -R "ls -l /home/roms" "$IMG" 2>/dev/null
