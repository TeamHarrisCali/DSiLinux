#!/bin/sh
# The DSi's time zone: writes /etc/config/TZ in ROOTFS.IMG (uClibc reads it: UCLIBC_TZ_FILE_PATH). Normally not needed: after each
# Wi-Fi connection "httpdate -z" finds the zone from where the network is and writes it. A zone given here is kept: it also writes
# /etc/config/TZ.manual, which turns the automatic zone off (delete it on the DSi, or "scripts/set-timezone.sh auto", to turn it back on).
# Usage: scripts/set-timezone.sh [-i ROOTFS.IMG] [TZ | auto]   TZ in POSIX form; without one: Central, CST6CDT,M3.2.0,M11.1.0
#        scripts/set-timezone.sh --if-missing                 the default only when none is set yet, not marked manual (release.sh)
#   Examples: EST5EDT,M3.2.0,M11.1.0 (New York)   PST8PDT,M3.2.0,M11.1.0 (Los Angeles)   MST7 (Arizona)   UTC0
. "$(dirname "$0")/card.sh"
TZV="CST6CDT,M3.2.0,M11.1.0"; ONLY_MISSING=0
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
if [ "$TZV" = auto ]; then
	{ img_mkdir /etc/config; echo "rm /etc/config/TZ.manual"; } | debugfs -w -f - "$IMG" > /dev/null 2>&1
	sync
	echo "time zone: automatic (after each Wi-Fi connection); now: ${CUR:-none}"
	exit 0
fi
echo manual > out/tz/manual
{
	img_mkdir /etc/config
	printf 'rm /etc/config/TZ\nwrite out/tz/TZ /etc/config/TZ\nsif /etc/config/TZ mode 0100644\n'
	[ $ONLY_MISSING = 1 ] || printf 'rm /etc/config/TZ.manual\nwrite out/tz/manual /etc/config/TZ.manual\n'
} | debugfs -w -f - "$IMG" > /dev/null 2>&1
sync
[ "$(debugfs -R "cat /etc/config/TZ" "$IMG" 2>/dev/null)" = "$TZV" ] && echo "time zone: $TZV" || { echo "TZ NOT written"; exit 1; }
