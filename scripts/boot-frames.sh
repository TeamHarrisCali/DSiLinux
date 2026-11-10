#!/bin/sh
# Boot a ROM in an isolated melonDS config and capture cropped top-screen frames of the boot.
# Usage: scripts/boot-frames.sh <config-name> <rom> <outdir> <frames> <interval-seconds> [flatpak-args]
# Needs a graphical session; melonDS is killed at the end.
NAME="$1"; ROM="$2"; OUT="$3"; N="$4"; DT="$5"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
FLATPAK_ARGS="$6" "$HERE/melon-ds.sh" "$NAME" "$ROM" > "$OUT/melon.log" 2>&1 &
sleep 3
i=0
while [ $i -lt "$N" ]; do
  i=$((i+1)); n=$(printf %02d $i)
  spectacle -b -n -f -o "$OUT/full-$n.png" 2>/dev/null
  python3 -I "$HERE/topscreen.py" "$OUT/full-$n.png" "$OUT/top-$n.png" >/dev/null 2>&1
  # full screenshots are kept (local only, out/ is git-ignored): the crop can fail on an all-black screen
  sleep "$DT"
done
# Kill only the melonDS instance that runs with OUR test config (never one the user has open).
for p in $(pgrep -x melonDS); do
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "config-dslinuxtest-$NAME\$"; then kill -KILL "$p"; fi
done
