#!/bin/sh
# PC test bed for the DSLinuxDSi desktop: the same Nano-X server (Microwindows from work/dslinux, with our patches) and the same desktop
# programs, compiled for the PC, drawing into a 256x192 framebuffer file instead of the DSi's top screen. Nothing appears on the PC's
# own screen: testbed/nxctl clicks, types and takes pictures. Output in out/testbed/.
# Usage: testbed/build.sh            (then testbed/run.sh)
set -e
cd "$(dirname "$0")/.."
T=out/testbed
mkdir -p $T/bin
rsync -a --delete --exclude '*.o' --exclude '*.a' --exclude '.depend' --exclude 'bin/' work/dslinux/user/microwin/src/ $T/src/
chmod -R u+w $T/src
cp testbed/config.host $T/src/config
# a current gcc: old C, no warnings as errors, common symbols; and an include of a 2005 kernel header
sed -i 's/^GCC_WARNINGS := .*/GCC_WARNINGS := -w -fcommon -std=gnu89 -fno-strict-aliasing/' $T/src/Arch.rules
sed -i 's#^\#include <asm/page.h>#\#include <unistd.h>\n\#ifndef PAGE_SIZE\n\#define PAGE_SIZE 4096\n\#endif#' $T/src/nanox/clientfb.c
(cd $T/src && make -j8 > ../build.log 2>&1) || { echo "Microwindows build failed: $T/build.log"; exit 1; }
gcc -shared -fPIC -O1 -o $T/bin/fbshim.so testbed/fbshim.c -ldl
CF="-w -fcommon -std=gnu99 -O1 -I$T/src/include -I$T/src/demos/nanox -DNANOX_TESTBED"
gcc $CF -o $T/bin/nxctl testbed/nxctl.c -L$T/src/lib -lnano-X
for p in dsdesk dsnotes dsfiles dssettings dsarcade dsgb; do
	gcc $CF -o $T/bin/$p $T/src/demos/nanox/$p.c -L$T/src/lib -lnano-X -lm || echo "($p did not build for the PC)"
done
cp $T/src/bin/nano-X $T/src/bin/nanowm $T/bin/
echo "built: $(ls $T/bin | tr '\n' ' ')"
