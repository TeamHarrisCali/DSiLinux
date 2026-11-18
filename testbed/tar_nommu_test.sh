#!/bin/sh
# Tests the DSi's GNU tar (work/dslinux/user/tar, with the no-MMU compressor patch, patch 0131) on the PC: builds the same source
# natively with -D__uClinux__ (so it takes the vfork + exec path), then packs and unpacks with -z and -j, through files and through
# stdin/stdout, with fork() made to fail as uClibc's does on the DSi (testbed/nofork.c as LD_PRELOAD). The PC's own tar is run the same
# way as the control: it must fail with "Cannot fork: Function not implemented", the DSi's message.
# The copy's 2006 gnulib clashes with the current C library's futimens; it is renamed in the copy only.
# Usage: testbed/tar_nommu_test.sh        (work in out/tar-nommu-test)
set -e
cd "$(dirname "$0")/.."
W=$PWD/out/tar-nommu-test
rm -rf "$W" && mkdir -p "$W"
cp -a work/dslinux/user/tar/src/. "$W/src/"
cd "$W/src"
make distclean > /dev/null 2>&1 || true
grep -rl "futimens" lib src | xargs sed -i 's/\bfutimens\b/tar_futimens/g'
CFLAGS="-O1 -w -std=gnu89 -fcommon -D__uClinux__" ./configure --disable-nls > ../configure.log 2>&1
make -j8 > ../make.log 2>&1 || { echo "build failed: $W/make.log"; exit 1; }
T=$W/src/src/tar
gcc -shared -fPIC -o "$W/nofork.so" "$OLDPWD/testbed/nofork.c"
P="LD_PRELOAD=$W/nofork.so"
cd "$W" && mkdir -p in/sub/deep && seq 1 20000 > in/a.txt && head -c 300000 /dev/urandom > in/sub/b.bin && echo hi > in/sub/deep/c
env $P "$T" czf t.tgz in && mkdir x1 && (cd x1 && env $P "$T" xzf ../t.tgz) && diff -r in x1/in && echo "ok: -z through files"
env $P "$T" cjf t.tbz in && mkdir x2 && (cd x2 && env $P "$T" xjf ../t.tbz) && diff -r in x2/in && echo "ok: -j through files"
env $P "$T" czf - in > s.tgz && mkdir x3 && (cd x3 && env $P "$T" xzf - < ../s.tgz) && diff -r in x3/in && echo "ok: -z through stdin/stdout"
gzip -t t.tgz s.tgz && echo "ok: valid gzip"
if env $P tar xzf t.tgz -C x1 2>&1 | grep -q "Cannot fork"; then echo "ok: the unpatched tar fails as on the DSi (control)"; fi
