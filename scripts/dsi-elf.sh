#!/bin/sh
# Wrap the raw ARM9/ARM7 binaries (from out/dsi-mode/tmp) in ELF files for BlocksDS's ndstool.
# ndstool only writes a DSi header (unit code, TWL flags, DSi title id) when the ARM9 ELF carries a "DSi" segment
# (PT_LOAD with flag 0x100000, the way BlocksDS's crt0 linker scripts mark ARM9i/ARM7i code); -uc alone does nothing here.
# So the ARM9 ELF gets a 4-byte dummy ARM9i segment at 0x02400000, which the loader copies before the kernel starts.
set -e
cd "$(dirname "$0")/.."
scripts/in-container.sh 'mkdir -p /out/dsi-mode/elf && cd /out/dsi-mode/elf &&
printf ".section .dsi,\"a\"\n.long 0\n" > dsi9.s && arm-linux-elf-as -o dsi9.o dsi9.s &&
arm-linux-elf-objcopy -I binary -O elf32-littlearm -B arm ../tmp/arm9.bin arm9.o &&
printf "ENTRY(_start)\nPHDRS { main PT_LOAD FLAGS(7); dsi PT_LOAD FLAGS(0x100007); }\nSECTIONS { . = 0x02000000; .text : { *(.data) } :main . = 0x02400000; .dsi : { *(.dsi) } :dsi }\n" > arm9.ld &&
arm-linux-elf-ld -T arm9.ld -e 0x02000000 -o arm9.elf arm9.o dsi9.o &&
arm-linux-elf-objcopy -I binary -O elf32-littlearm -B arm ../tmp/arm7.bin arm7.o &&
printf "ENTRY(_start)\nSECTIONS { . = 0x03800000; .text : { *(.data) } }\n" > arm7.ld &&
arm-linux-elf-ld -T arm7.ld -e 0x03800000 -o arm7.elf arm7.o &&
arm-linux-elf-readelf -l arm9.elf | sed -n 4,9p'
