#!/bin/sh
# Puts two things into the card's ROOTFS.IMG's /etc/profile (read by login shells: tty1 and SSH): the terminal-type mapping for nano
# and friends, and the boot session hook: /etc/profile sources /boot/session from
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
NEED_TERM=1; NEED_SESSION=1
printf '%s\n' "$OLD" | grep -q "DSLinuxDSi: terminal types" && NEED_TERM=0
printf '%s\n' "$OLD" | grep -q "/boot/session" && NEED_SESSION=0
if [ $NEED_TERM = 0 ] && [ $NEED_SESSION = 0 ]; then
	echo "/etc/profile already has the terminal types and /boot/session"
	exit 0
fi
{
	printf '%s\n' "$OLD" | grep -v '^$' | grep -v "boot/session"
	if [ $NEED_TERM = 1 ] || [ $NEED_SESSION = 1 ]; then
		# the terminal types first (the desktop session below runs the desktop in the foreground)
		if ! printf '%s\n' "$OLD" | grep -q "DSLinuxDSi: terminal types"; then
			echo '# DSLinuxDSi: terminal types. nano and the other curses programs know only the types built into them (xterm, linux;'
			echo '# the DSi has no terminfo files): anything else, such as an SSH client'"'"'s xterm-256color, becomes xterm.'
			echo 'case "$TERM" in'
			echo 'xterm|linux) ;;'
			echo '*) TERM=xterm; export TERM ;;'
			echo 'esac'
		fi
	fi
	echo '# DSLinuxDSi: the desktop at boot (the ROM'"'"'s /boot/session; scripts/install-session.sh)'
	echo '[ -f /boot/session ] && . /boot/session'
} > out/session/profile
printf 'rm /etc/profile\nwrite out/session/profile /etc/profile\nsif /etc/profile mode 0100644\n' > out/session/cmds
debugfs -w -f out/session/cmds "$IMG" > /dev/null 2>&1
sync
P=$(debugfs -R "cat /etc/profile" "$IMG" 2>/dev/null)
printf '%s\n' "$P" | grep -q "/boot/session" && printf '%s\n' "$P" | grep -q "DSLinuxDSi: terminal types" && echo "/etc/profile: terminal types, starts /boot/session" || { echo "/etc/profile NOT written"; exit 1; }
