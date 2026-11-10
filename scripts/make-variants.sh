#!/bin/sh
# Re-pack the DSI build's arm9.bin with the ARM7 header address variant used by the third-party proof of concept.
# DSLinux's ARM7 code is linked at 0x03800000; 0x03840000 is the same 64 KB IWRAM through a mirror on a DS.
# Which header address TWiLight Menu++ accepts on a DSi is unverified, so both are shipped.
set -e
cd "$(dirname "$0")/.."
OUT=out/dsi-card
mkdir -p $OUT
cp -p work/dslinux/images/dslinux.nds $OUT/dslinux-dsi.nds
# images/arm9.bin belongs to the last image built (dslinuxm), so unpack the arm9/arm7 parts from dslinux.nds itself.
scripts/in-container.sh 'mkdir -p /tmp/x && cd /tmp/x && ndstool -x /work/images/dslinux.nds -9 arm9.bin -7 arm7.bin >/dev/null && \
  ndstool -c /out/dsi-card/dslinux-dsi-arm7b.nds -9 arm9.bin -r9 0x02000000 -e9 0x02000000 \
  -7 arm7.bin -r7 0x03840000 -e7 0x03840000 \
  -b /work/vendors/Nintendo/common/tux.bmp "DSLinux;Port of Linux;to the DS!"'
cp -p out/stage1-images/dslinux.nds $OUT/dslinux-ds4mb-control.nds
