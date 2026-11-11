#!/bin/sh
# Build the ext2 root image ROOTFS.IMG for sd:/linux/ from the DSLinux userland tree.
# Usage: scripts/make-rootimg.sh [size-MiB (default 512)] [output (default out/dsi-card/sd-root/linux/ROOTFS.IMG)]
# Copy the result into the card's linux/ folder from a PC, as ONE file, so it ends up as sd:/linux/ROOTFS.IMG. At boot the ARM7 finds the
# file's sectors itself and from then on lets the card be reached only inside this file and sd:/linux/DSILOG.TXT.
# The filesystem is plain ext2 limited to features the 2.6.14 kernel knows (no dir_index, resize_inode, ext_attr, extra_isize ...).
set -e
cd "$(dirname "$0")/.."
MB="${1:-512}"
OUT="${2:-out/dsi-card/sd-root/linux/ROOTFS.IMG}"
TREE=work/dslinux/images/linux
STAGE=$(mktemp -d)
mkdir -p "$STAGE/root"
cp -a "$TREE/." "$STAGE/root/"
# a quiet rc.conf (the big "rc.conf does not exist" banner), written once here instead of at every boot
[ -e "$STAGE/root/etc/rc.conf" ] || echo '# DSLinuxDSi: defaults come from /etc/rc.defaults; add overrides here.' > "$STAGE/root/etc/rc.conf"
mkdir -p "$STAGE/root/home" "$STAGE/root/var/run" "$STAGE/root/var/log" "$STAGE/root/var/tmp" "$STAGE/root/var/lock" "$STAGE/root/var/mail"
rm -f "$OUT"
truncate -s "${MB}M" "$OUT"
# fakeroot: every file in the image is owned by root (uid/gid 0), whatever owns the files on this PC
fakeroot sh -c "chown -R 0:0 '$STAGE/root' && mke2fs -q -t ext2 -O none,sparse_super,filetype,large_file -r 1 -I 128 -b 1024 -m 0 -L dsilinux -E root_owner=0:0 -d '$STAGE/root' '$OUT'"
rm -rf "$STAGE"
echo "created $OUT"
ls -la "$OUT"
e2fsck -fn "$OUT" 2>&1 | tail -3
dumpe2fs -h "$OUT" 2>/dev/null | grep -E 'features|Block size|Block count|Inode count'
