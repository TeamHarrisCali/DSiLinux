#!/bin/sh
# The DSi's time zone: writes /etc/config/TZ in ROOTFS.IMG (uClibc reads it: UCLIBC_TZ_FILE_PATH). The clock itself is set from the
# network after each Wi-Fi connection (ntpclient, in UTC); this decides how the tray, date and ls show it.
# Usage: scripts/set-timezone.sh [-i ROOTFS.IMG] [TZ]      TZ in POSIX form, default California: PST8PDT,M3.2.0,M11.1.0
#        scripts/set-timezone.sh --if-missing              only when none is set yet (release.sh)
#   Examples: EST5EDT,M3.2.0,M11.1.0 (New York)   CST6CDT,M3.2.0,M11.1.0 (Chicago)   MST7 (Arizona)   UTC0
. "$(dirname "$0")/card.sh"
TZV="PST8PDT,M3.2.0,M11.1.0"; ONLY_MISSING=0
while [ $# -gt 0 ]; do
	case "$1" in
	-i) IMG="$2"; shift 2 ;;
	--if-missing) ONLY_MISSING=1; shift ;;
	*) TZV="$1"; shift ;;
	esac
done
cd "$(dirname "$0")/.."
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
CUR=$(debugfs -R "cat /etc/config/TZ" "$IMG" 2>/dev/null)
if [ $ONLY_MISSING = 1 ] && [ -n "$CUR" ]; then
	echo "time zone: $CUR"
	exit 0
fi
mkdir -p out/tz
echo "$TZV" > out/tz/TZ
{ img_mkdir /etc/config; printf 'rm /etc/config/TZ\nwrite out/tz/TZ /etc/config/TZ\nsif /etc/config/TZ mode 0100644\n'; } | debugfs -w -f - "$IMG" > /dev/null 2>&1
sync
[ "$(debugfs -R "cat /etc/config/TZ" "$IMG" 2>/dev/null)" = "$TZV" ] && echo "time zone: $TZV" || { echo "TZ NOT written"; exit 1; }
