#!/bin/sh
# Checks the terminal descriptions scripts/install-terminfo.sh puts on the card (out/terminfo) against the DSi's own ncurses 5.4: builds
# work/dslinux/lib/libncurses natively on the PC (with a terminfo database, as the DSi build has since patch 0134) and asks it to read
# and set up each type. "read_file_entry=1 setupterm=0 err=1" = usable by nano and the other curses programs on the DSi.
# Usage: testbed/terminfo_test.sh [type ...]       (default: every type in out/terminfo; run scripts/install-terminfo.sh first)
set -e
cd "$(dirname "$0")/.."
[ -d out/terminfo ] || { echo "no out/terminfo: run scripts/install-terminfo.sh first"; exit 1; }
W=$PWD/out/terminfo-test
if [ ! -f "$W/nc/lib/libncurses.a" ]; then
	rm -rf "$W" && mkdir -p "$W"
	cp -a work/dslinux/lib/libncurses/. "$W/nc/"
	cd "$W/nc"
	make distclean > /dev/null 2>&1 || true
	CFLAGS="-O1 -w -std=gnu89 -fcommon" ./configure --without-cxx --without-ada --without-progs --without-debug \
		--with-default-terminfo-dir=/nonexistent > ../configure.log 2>&1
	make -C include > ../make.log 2>&1 && make -C ncurses >> ../make.log 2>&1 || { echo "ncurses build failed: $W/make.log"; exit 1; }
	cd "$OLDPWD"
fi
gcc -w -I "$W/nc/include" -I "$W/nc/ncurses" -o "$W/tt" testbed/terminfo_test.c "$W/nc/lib/libncurses.a"
TYPES="$*"
[ -n "$TYPES" ] || TYPES=$(cd out/terminfo && ls */ | grep -v ":" | grep . | tr '\n' ' ')
TERMINFO=$PWD/out/terminfo "$W/tt" "$PWD/out/terminfo" $TYPES
