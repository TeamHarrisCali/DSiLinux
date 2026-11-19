#!/bin/sh
# Quick checks before a release build (docs/DEV-PROCESS.md, step 4): seconds instead of a failed build minutes later.
#   kernel files (linux-2.6.x/...c): compiled alone in the build container with the real 2008 gcc (catches its crashes);
#   ARM7 files: the mach-nds directory is built, which links the whole ARM7 binary (catches missing symbols too)
#   It fails if make's output does not show the file being compiled (a "nothing to do" is not a pass).
#   desktop programs (user/microwin/src/demos/nanox/*.c): syntax-checked with the PC's gcc against the test bed's headers
#   tools (vendors/Nintendo/DSI/*.c): syntax-checked with the PC's gcc
#   any new file in the repo or the tree: its name checked against .gitignore (names with nand/bios/firmware/dsisd are refused)
# Usage: scripts/precheck.sh FILE...    (paths relative to work/dslinux, as release.sh -t takes them)
# Exit status 1 if anything failed.
cd "$(dirname "$0")/.."
fail=0
for f in "$@"; do
	case "$f" in
	linux-2.6.x/*.c)
		o=${f#linux-2.6.x/}; o=${o%.c}.o
		want="CC      $o"
		case "$o" in arch/arm/mach-nds/arm7/*) want="arm7.elf"; o=arch/arm/mach-nds/ ;; esac	# the ARM7 side builds and links as one binary
		out=$(scripts/in-container.sh "cd /work/linux-2.6.x && touch ${f#linux-2.6.x/} && make ARCH=arm CROSS_COMPILE=arm-linux-elf- $o 2>&1")
		if echo "$out" | grep -q "error\|Error [0-9]"; then
			echo "FAIL $f"; echo "$out" | grep -v "^  CC\|^  CHK\|^make" | head -20; fail=1
		elif ! echo "$out" | grep -q "$want"; then
			echo "FAIL $f: it was not rebuilt (no \"$want\" in make's output); output:"; echo "$out" | tail -5; fail=1
		else
			w=$(echo "$out" | grep -c "warning")
			echo "ok   $f (kernel gcc 4.0.4, $w warnings)"
			[ "$w" -gt 0 ] && echo "$out" | grep "warning" | head -5
		fi ;;
	user/microwin/src/demos/nanox/*.c)
		if [ ! -d out/testbed/src/include ]; then echo "skip $f (run testbed/build.sh once for the headers)"; continue; fi
		if gcc -fsyntax-only -w -std=gnu99 -DNANOX_TESTBED -Iout/testbed/src/include -Iwork/dslinux/user/microwin/src/demos/nanox "work/dslinux/$f" 2>/tmp/precheck.$$; then
			echo "ok   $f (PC gcc syntax)"
		else
			echo "FAIL $f"; head -20 /tmp/precheck.$$; fail=1
		fi
		rm -f /tmp/precheck.$$ ;;
	vendors/Nintendo/DSI/*.c)
		if gcc -fsyntax-only -Wall "work/dslinux/$f" 2>/tmp/precheck.$$; then
			echo "ok   $f (PC gcc syntax)"
		else
			echo "FAIL $f"; head -20 /tmp/precheck.$$; fail=1
		fi
		rm -f /tmp/precheck.$$ ;;
	*) echo "--   $f (no check for this kind of file)" ;;
	esac
done
# files in the repo's own folders that .gitignore would refuse to commit (names with nand/bios/firmware/dsisd are blocked)
for p in $(git status --porcelain --ignored -- patches docs scripts testbed 2>/dev/null | sed -n 's/^!! //p'); do
	echo "IGNORED by .gitignore: $p (rename it before committing)"; fail=1
done
exit $fail
