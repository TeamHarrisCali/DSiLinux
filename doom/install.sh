#!/bin/sh
# Puts dsdoom, the shareware WAD and default.cfg into /home/doom inside the DSLinux root image on the SD card (card in the PC).
# Usage: doom/install.sh [-i ROOTFS.IMG] [path/to/doom1.wad]   (the binary comes from out/doom-build/dsdoom; without a WAD the one already in the image stays)
. "$(dirname "$0")/../scripts/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
WAD="$1"
cd "$(dirname "$0")/.."
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
[ -z "$WAD" ] || [ -f "$WAD" ] || { echo "no such WAD: $WAD"; exit 1; }
[ -f out/doom-build/dsdoom ] || { echo "build first: doom/build.sh"; exit 1; }
"$(dirname "$0")/../scripts/rootfs-check.sh" "$IMG" || exit 1
CMDS=$(mktemp)
cat > "$CMDS" <<EOT
mkdir /home/doom
mkdir /home/doom/save
rm /home/doom/dsdoom
rm /home/doom/default.cfg
write out/doom-build/dsdoom /home/doom/dsdoom
sif /home/doom/dsdoom mode 0100755
write doom/default.cfg /home/doom/default.cfg
EOT
[ -z "$WAD" ] || printf "rm /home/doom/doom1.wad\nwrite \"%s\" /home/doom/doom1.wad\n" "$WAD" >> "$CMDS"
debugfs -w -f "$CMDS" "$IMG" > /dev/null 2>&1
rm -f "$CMDS"
debugfs -R "ls -l /home/doom" "$IMG" 2>/dev/null
