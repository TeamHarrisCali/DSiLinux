#!/bin/sh
# What the DSi recorded, in one go, with the card in the PC (docs/DEV-PROCESS.md, step 1 and 7). Checks ROOTFS.IMG, saves the
# current card log to out/logs/card-<time>.txt and prints the parts the next decision usually needs, so nobody has to type commands
# on the DSi and copy their output.
# Usage: scripts/cardlog.sh [-a] [saved-log]   (-a: also the whole kernel log; a saved log (out/logs/card-*.txt): read that instead)
cd "$(dirname "$0")/.."
ALL=0; [ "$1" = "-a" ] && { ALL=1; shift; }
IMG=""
if [ -n "$1" ]; then
	L="$1"
else
	. scripts/card.sh
	card_present || { echo "card not in the PC (give a saved log to read it instead)"; exit 1; }
	IMG="$CARD/linux/ROOTFS.IMG"
	scripts/rootfs-check.sh "$IMG" || echo "WARNING: ROOTFS.IMG has errors: scripts/rootfs-check.sh -y repairs it"
	mkdir -p out/logs
	L=out/logs/card-$(date +%Y%m%d-%H%M%S).txt
	tr -d '\000' < "$CARD/linux/DSILOG.TXT" | sed -n '1,/^--- end ---/p' > "$L"	# rewritten from the start: older text follows
	echo "saved: $L"
fi
sec() { sed -n "\\|^--- $1|,\\|^--- |p" "$L" | sed '1d;$d'; }
echo "== $(head -1 "$L")"
grep -a -m1 "^Linux version" "$L" | sed 's/(gcc.*#/#/'
echo "== problems"
grep -a -n -i "oops\|panic\|killed\|out of memory\|not enough memory\|segfault\|unable to\|no answer\|did not\|refused\|timed out\|failed\|error" "$L" |
	grep -v -i "errors:0\|error detail 00000000\|unknown error 101" | head -25
echo "== Wi-Fi joining"
W=$(grep -a "connect:\|CONNECTED\|disconnected\|wifi auto:\|No answer\|chip up\|connect attempt" "$L" | grep -v "Joining GuestNet: [0-9]*[1-9] s")
n=$(echo "$W" | grep -c .)
if [ "$n" -gt 24 ]; then echo "$W" | head -8; echo "   ... ($n lines; attempts: $(echo "$W" | grep -c 'commands sent'))"; echo "$W" | tail -12; else echo "$W"; fi
echo "== sleep / screen"
grep -a "deep sleep\|^sleep:\|lcdoff\|screensleep" "$L" | head -15
T=""; [ -n "$IMG" ] && T=$(debugfs -R "cat /home/sleep.trace" "$IMG" 2>/dev/null)
[ -n "$T" ] && { echo "-- /home/sleep.trace"; echo "$T"; }
echo "== desktop"
sec desktop.log | grep -a -v "^\s*$\|geometry\|timings\|accel\|rgba\|endmode\|^mode\|# D:" | tail -15
echo "== memory"
sec /proc/meminfo | grep -a "MemTotal\|MemFree\|Cached"
grep -a -A12 "^--- memreport" "$L" | head -14
[ $ALL = 1 ] && { echo "== kernel log"; sec dmesg; }
exit 0
