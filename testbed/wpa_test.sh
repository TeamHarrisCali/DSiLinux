#!/bin/sh
# Builds testbed/wpa_test.c with the kernel's dsiwpa.c for the PC and runs it; the expected PTK comes from Python's hmac/hashlib.
cd "$(dirname "$0")/.."
WANT=$(python3 -I -c '
import hmac, hashlib
pmk = bytes(range(32)); an = bytes(0x40 + i for i in range(32)); sn = bytes(0x80 + i for i in range(32))
spa = bytes.fromhex("a4c0e1d74709"); aa = bytes.fromhex("001122334455")
d = b"Pairwise key expansion\0" + min(aa, spa) + max(aa, spa) + min(an, sn) + max(an, sn)
print(b"".join(hmac.new(pmk, d + bytes([i]), hashlib.sha1).digest() for i in range(3))[:48].hex())')
gcc -O2 -Wall -DDSIWPA_HOST -o out/wpa_test testbed/wpa_test.c work/dslinux/linux-2.6.x/arch/arm/mach-nds/dsiwpa.c && out/wpa_test "$WANT"
