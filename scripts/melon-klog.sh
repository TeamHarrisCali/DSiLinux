#!/bin/sh
# Boot a ROM in an isolated melonDS config that has the GDB stub on, wait, print the kernel log from RAM, close our melonDS.
# Usage: scripts/melon-klog.sh <config-name> <rom> <seconds-to-wait>
# Needs the DSLinux build tree for symbol addresses. Never touches a melonDS the user has open.
NAME="$1"; ROM="$2"; WAIT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
SYMS=$("$HERE/in-container.sh" 'cd /work/linux-2.6.x && arm-linux-elf-nm linux | grep -E " (__log_buf|log_end)$"')
BUF=$(echo "$SYMS" | awk '$3=="__log_buf"{print $1}'); END=$(echo "$SYMS" | awk '$3=="log_end"{print $1}')
"$HERE/melon-ds.sh" "$NAME" "$ROM" > "${LOGDIR:-/tmp}/melon-$NAME.log" 2>&1 &
sleep "$WAIT"
python3 -I "$HERE/klog.py" "$BUF" "$END"
for p in $(pgrep -x melonDS); do
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "config-dslinuxtest-$NAME\$"; then kill -KILL "$p"; fi
done
