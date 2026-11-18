#!/bin/sh
# Raises the stack size of the programs in ROOTFS.IMG's /usr/bin, without using more RAM.
# Each program's stack size is a field in its bFLT header (most of DSLinux's programs have 4 KB). The loader (fs/binfmt_flat.c) allocates
# data + max(bss + stack + arguments, relocations) + 4 bytes in one block, rounded up to a power of two by the kernel's allocator, and
# puts the stack at the block's end, so the rounding slack already works as extra stack. This script raises the header's stack
# towards 64 KB (big programs: tar, gzip, nano, perl, ...) or 16 KB (the rest), but only as far as the block the program already gets
# (minus 8 KB for arguments): no program needs a bigger block afterwards. A real overflow then stops at a known size instead of
# running into the bss.
# Usage: scripts/fix-stacks.sh [-i ROOTFS.IMG] [-n]     (-n: show what would change, write nothing). release.sh runs it.
. "$(dirname "$0")/card.sh"
DRY=0
while [ $# -gt 0 ]; do
	case "$1" in
	-i) IMG="$2"; shift 2 ;;
	-n) DRY=1; shift ;;
	*) echo "unknown option $1"; exit 1 ;;
	esac
done
cd "$(dirname "$0")/.."
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
D=out/stacks
rm -rf $D
mkdir -p $D/bin
debugfs -R "rdump /usr/bin $D/bin" "$IMG" > /dev/null 2>&1
[ -d $D/bin/bin ] && SRC=$D/bin/bin || SRC=$D/bin
python3 -I - "$SRC" "$D/changed.txt" <<'EOF'
import os, struct, sys
src, out = sys.argv[1], sys.argv[2]
BIG = set('tar gzip bzip2 bzip2recover unzip zip perl sqlite3 links mc irssi nano less diff wget scp ssh dropbear sed bc dc '
          'hexedit ncftp tt++ smbclient'.split())
PAGE = 4096
def block(n):                         # what SLOB hands out for n bytes: a power-of-two number of pages
    pages = (n + PAGE - 1) // PAGE
    b = 1
    while b < pages:
        b *= 2
    return b * PAGE
changed = []
for name in sorted(os.listdir(src)):
    p = os.path.join(src, name)
    if not os.path.isfile(p) or os.path.islink(p):
        continue
    with open(p, 'rb') as f:
        h = f.read(64)
    if len(h) < 40 or h[:4] != b'bFLT':
        continue
    rev, entry, ds, de, be, stack, rs, rc, flags = struct.unpack('>9I', h[4:40])
    data_len, bss_len = de - ds, be - de
    ram = flags & 0x1 or flags & 0x4     # FLAT_FLAG_RAM / FLAT_FLAG_GZIP: text, data and the rest in one block
    def alloc(st):
        n = data_len + max(bss_len + st + 8192, rc * 4) + 4
        return n + (ds if ram else 0)
    blk = block(alloc(stack))
    target = 65536 if name in BIG else 16384
    new = stack
    if stack < target:
        room = blk - alloc(stack)        # what still fits in the same block
        new = min(target, stack + room) & ~15
    if new > stack and block(alloc(new)) == blk:
        with open(p, 'r+b') as f:
            f.seek(24)
            f.write(struct.pack('>I', new))
        changed.append((name, stack, new, blk))
with open(out, 'w') as f:
    for name, a, b, blk in changed:
        f.write('%s %d %d %d\n' % (name, a, b, blk))
print('%d programs get a bigger stack (same memory block)' % len(changed))
EOF
[ -s $D/changed.txt ] || { echo "nothing to change"; exit 0; }
awk '{printf "  %-14s %6d -> %6d bytes (block %d KB)\n", $1, $2, $3, $4/1024}' $D/changed.txt | head -200 > $D/report.txt
if [ $DRY = 1 ]; then cat $D/report.txt; echo "(dry run: nothing written)"; exit 0; fi
: > $D/cmds
while read name a b blk; do
	printf 'rm /usr/bin/%s\nwrite %s/%s /usr/bin/%s\nsif /usr/bin/%s mode 0100755\n' "$name" "$SRC" "$name" "$name" "$name" >> $D/cmds
done < $D/changed.txt
debugfs -w -f $D/cmds "$IMG" > /dev/null 2>&1
sync
BAD=0
while read name a b blk; do
	debugfs -R "stat /usr/bin/$name" "$IMG" 2>/dev/null | grep -q "Size: $(stat -c %s "$SRC/$name")" || { echo "NOT written: $name"; BAD=1; }
done < $D/changed.txt
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "IMAGE CHECK FAILED after writing"; exit 1; }
[ $BAD = 0 ] && echo "stacks raised: $(wc -l < $D/changed.txt) programs (list: $D/report.txt)"
