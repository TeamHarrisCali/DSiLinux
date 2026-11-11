#!/bin/sh
# Build a partitioned FAT32 test SD image (MBR, one partition at 1 MiB) holding DSLinux's linux/ tree at the root,
# like a real SD card. Usage: scripts/make-sd-image.sh <image> <size-MiB> <dir-containing-linux/>
set -e
IMG="$1"; MB="$2"; SRC="$3"
rm -f "$IMG"
truncate -s "${MB}M" "$IMG"
echo 'start=2048, type=c' | sfdisk -q "$IMG"
mkfs.fat -F 32 -s 4 --offset 2048 "$IMG" >/dev/null
MTOOLS_SKIP_CHECK=1 mcopy -i "$IMG@@1048576" -s -p "$SRC/linux" ::/
mdir -i "$IMG@@1048576" ::/linux | head -5
