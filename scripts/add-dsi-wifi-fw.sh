#!/bin/sh
# Copies the DSi's Wi-Fi firmware (the console's own title HNCA, "WLFIRM") into the DSLinux root image as /usr/lib/firmware/dsi-wifi.bin,
# for the Atheros chip (docs/ATHEROS-PLAN.md). The file is Nintendo's and comes only from your own console's NAND or SDNAND backup:
# it is never put in this repository or the ROM.
# Usage: scripts/add-dsi-wifi-fw.sh [-i ROOTFS.IMG] [path/to/HNCA/content/0000000x.app]
#   default source: ~/Desktop/DSIBACKUP/title/0003000f/484e4341/content/*.app (a hiyaCFW SDNAND copy on an SD card backup)
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
SRC="$1"
[ -n "$SRC" ] || SRC=$(ls "$HOME"/Desktop/DSIBACKUP/title/0003000f/484e4341/content/*.app 2>/dev/null | head -1)
[ -f "$SRC" ] || { echo "no firmware file (give the path to title 0003000f/484e4341/content/*.app)"; exit 1; }
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
python3 -I - "$SRC" <<'PY' || exit 1
import sys, struct, hashlib
d = open(sys.argv[1], 'rb').read()
n = d[0xA2]
ok = 0x80 < len(d) < 0x40000 and 0 < n < 8
for i in range(n if ok else 0):
    off, ln = struct.unpack('<II', d[0xA4 + i * 0x20:0xAC + i * 0x20])
    sha = d[0xB0 + i * 0x20:0xC4 + i * 0x20]
    ok = ok and off + ln <= len(d) and hashlib.sha1(d[off:off + ln]).digest() == sha
if not ok:
    sys.exit("not a Wi-Fi firmware file (WLFIRM): the blob table or its SHA-1 sums do not match")
print("Wi-Fi firmware: %d bytes, %d blobs, SHA-1 sums ok" % (len(d), n))
PY
"$(dirname "$0")/rootfs-check.sh" "$IMG" || exit 1
CMDS=$(mktemp)
{ img_mkdir /usr/lib/firmware; printf 'rm /usr/lib/firmware/dsi-wifi.bin\nwrite "%s" /usr/lib/firmware/dsi-wifi.bin\n' "$SRC"; } > "$CMDS"
debugfs -w -f "$CMDS" "$IMG" > /dev/null 2>&1
rm -f "$CMDS"
sync
got=$(debugfs -R "stat /usr/lib/firmware/dsi-wifi.bin" "$IMG" 2>/dev/null | sed -n 's/.*Size: \([0-9]*\).*/\1/p' | head -1)
[ "$got" = "$(stat -c %s "$SRC")" ] || { echo "NOT WRITTEN (image size $got)"; exit 1; }
echo "in ROOTFS.IMG: /usr/lib/firmware/dsi-wifi.bin ($got bytes)"
