#!/bin/sh
# Stage 1: unmodified DSLinux (Nintendo/DLDI build) in the Wheezy container. Output: work/dslinux/images/
# Prerequisites: docker image `dslinux-wheezy` (docker build -t dslinux-wheezy scripts/), toolchain extracted under
# ~/Documents/Claude/DSLinuxDSi-third-party/toolchain/extracted/, upstream clone at work/dslinux.
set -e
cd "$(dirname "$0")/.."
scripts/prepare-tree.sh
# Default answers pick the Nintendo/DLDI build.
scripts/in-container.sh 'cd /work && yes "" | make config > /out/config.log 2>&1 && make dep > /out/dep.log 2>&1 && make > /out/build.log 2>&1'
ls -la work/dslinux/images
