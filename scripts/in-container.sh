#!/bin/sh
# Run a command in the Wheezy build container with the DSLinux tree and the 2008 toolchain mounted.
# Usage: scripts/in-container.sh [-t] command...     (-t = interactive tty, needed for menuconfig)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$HOME/Documents/Claude/DSLinuxDSi-third-party/toolchain/extracted/dslinux-toolchain-2008-01-24-i686"
TTY=""; [ "$1" = "-t" ] && { TTY="-t"; shift; }
exec docker run --rm -i $TTY --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$ROOT/work/dslinux:/work" -v "$TC:/opt/toolchain:ro" -v "$ROOT/out:/out" \
  -e PATH=/opt/toolchain/bin:/usr/local/bin:/usr/bin:/bin -e TERM=xterm \
  dslinux-wheezy sh -c "$*"
