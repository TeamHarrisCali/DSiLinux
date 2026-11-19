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
if printf '%s\n' "$OLD" | grep -q "DSLinuxDSi: terminal types (3)" && printf '%s\n' "$OLD" | grep -q "/boot/session" &&
   printf '%s\n' "$OLD" | grep -q "DSLinuxDSi: hush (1)"; then
	echo "/etc/profile already has the terminal types, /boot/session and the hush hand-over"
	exit 0
fi
{
	# what is there, without an older terminal-types block and the session lines (both are written again below)
	printf '%s\n' "$OLD" | sed '/DSLinuxDSi: terminal types/,/^esac$/d;/DSLinuxDSi: hush/,/^fi$/d' | grep -v "boot/session" | grep -v '^$'
	echo '# DSLinuxDSi: terminal types (3). The DSi'"'"'s ncurses has no default directory: TERMINFO says where the descriptions are'
	echo '# (scripts/install-terminfo.sh). Those types stay as they are; anything else becomes xterm.'
	echo 'TERMINFO=/usr/share/terminfo'
	echo 'export TERMINFO'
	echo 'case "$TERM" in'
	echo 'linux|xterm|xterm-256color|xterm-color|vt100|vt102|vt220|screen|screen-256color|tmux|tmux-256color|ansi|dumb) ;;'
	echo '*) TERM=xterm; export TERM ;;'
	echo 'esac'
	echo '# DSLinuxDSi: the desktop at boot (the ROM'"'"'s /boot/session; scripts/install-session.sh)'
	echo '[ -f /boot/session ] && . /boot/session'
	# the hand-over to hush comes last: the desktop session above starts first at boot (docs/BUSYBOX-HUSH-PLAN.md, step 4)
	echo '# DSLinuxDSi: hush (1). The interactive shell is BusyBox 1.36.1'"'"'s hush (/bin/hush in the ROM): this login shell (msh)'
	echo '# hands over to it (Terminal, SSH, the text console). The boot scripts stay with msh. A ROM without hush keeps msh.'
	echo 'if [ -x /bin/hush ]'
	echo 'then'
	echo '	if [ -z "$HUSH_LOGIN" ]'
	echo '	then'
	echo '		HUSH_LOGIN=1'
	echo '		HISTFILE=/home/.hush_history'
	echo "		PS1='\\u@\\h:\\w\\$ '"
	echo '		export HUSH_LOGIN HISTFILE PS1'
	echo '		exec /bin/hush'
	echo '	fi'
	echo 'fi'
} > out/session/profile
printf 'rm /etc/profile\nwrite out/session/profile /etc/profile\nsif /etc/profile mode 0100644\n' > out/session/cmds
debugfs -w -f out/session/cmds "$IMG" > /dev/null 2>&1
sync
P=$(debugfs -R "cat /etc/profile" "$IMG" 2>/dev/null)
printf '%s\n' "$P" | grep -q "/boot/session" && printf '%s\n' "$P" | grep -q "DSLinuxDSi: terminal types (3)" &&
	printf '%s\n' "$P" | grep -q "DSLinuxDSi: hush (1)" && echo "/etc/profile: terminal types, starts /boot/session, hands over to hush" ||
	{ echo "/etc/profile NOT written"; exit 1; }
