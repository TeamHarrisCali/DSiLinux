#!/bin/sh
# Starts the PC test bed's desktop in the background: Nano-X server (framebuffer = /dev/shm/dsi-testbed-fb), nanowm, dsdesk.
# testbed/run.sh stop   ends it.   Then: out/testbed/bin/nxctl click 20 185 shot /tmp/x.ppm ...
cd "$(dirname "$0")/.."
B=$PWD/out/testbed/bin
export FRAMEBUFFER=/dev/shm/dsi-testbed-fb
if [ "$1" = stop ]; then
	pkill -f "$B/dsdesk"; pkill -f "$B/nxterm"; pkill -f "$B/dsnet"; pkill -f "$B/nanowm"; pkill -f "$B/nano-X"
	rm -f /tmp/.nano-X
	exit 0
fi
truncate -s 98304 $FRAMEBUFFER
LD_PRELOAD=$B/fbshim.so $B/nano-X -p > out/testbed/server.log 2>&1 &
sleep 1
$B/nanowm > out/testbed/nanowm.log 2>&1 &
sleep 0.5
(cd out/testbed && HOME=$PWD DSDESK_ROOT=$PWD/root DSNET_APS=$PWD/../../testbed/aps.txt DSNET_DRYRUN=1 $B/dsdesk > dsdesk.log 2>&1 &)
sleep 1
echo "test bed running (framebuffer $FRAMEBUFFER)"
