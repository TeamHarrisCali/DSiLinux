#!/bin/sh
# Puts the boot session hook into the card's ROOTFS.IMG: /etc/profile (read by the login shell on tty1) sources /boot/session from
# the ROM, which starts the desktop at boot (see vendors/Nintendo/DSI/session). A ROM without /boot/session skips it, so an older ROM
# still boots to the text console. Run by release.sh; safe to repeat.
# Usage: scripts/install-session.sh [-i ROOTFS.IMG]
. "$(dirname "$0")/card.sh"
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
cd "$(dirname "$0")/.."
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
mkdir -p out/session
OLD=$(debugfs -R "cat /etc/profile" "$IMG" 2>/dev/null)
if printf '%s\n' "$OLD" | grep -q "/boot/session"; then
	echo "/etc/profile already starts /boot/session"
	exit 0
fi
{ printf '%s\n' "$OLD" | grep -v '^$'; echo '# DSLinuxDSi: the desktop at boot (the ROM'"'"'s /boot/session; scripts/install-session.sh)'; echo '[ -f /boot/session ] && . /boot/session'; } > out/session/profile
printf 'rm /etc/profile\nwrite out/session/profile /etc/profile\nsif /etc/profile mode 0100644\n' > out/session/cmds
debugfs -w -f out/session/cmds "$IMG" > /dev/null 2>&1
sync
debugfs -R "cat /etc/profile" "$IMG" 2>/dev/null | grep -q "/boot/session" && echo "/etc/profile: starts /boot/session" || { echo "/etc/profile NOT written"; exit 1; }
