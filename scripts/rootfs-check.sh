#!/bin/sh
# Checks the ext2 root image on the SD card (read-only check). Usage: scripts/rootfs-check.sh [ROOTFS.IMG] [-y to repair]
# DSLinux never unmounts the image (power-off, resets and freezes leave it unclean), so metadata can be left half written: after a
# freeze or a hard reset run this with -y BEFORE writing to the image from the PC (add-roms.sh, set-wifi.sh and doom/install.sh refuse to).
. "$(dirname "$0")/card.sh"
[ -n "$1" ] && [ "$1" != "-y" ] && { IMG="$1"; shift; }
if [ "$1" = "-y" ]; then exec e2fsck -fy "$IMG"; fi
e2fsck -fn "$IMG" > /dev/null 2>&1 && { echo "image clean"; exit 0; }
echo "ROOTFS.IMG has errors: run  scripts/rootfs-check.sh -y  first (it repairs; keep a copy if the files matter)"
exit 1
