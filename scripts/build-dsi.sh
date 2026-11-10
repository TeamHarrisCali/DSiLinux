#!/bin/sh
# Stage 2: build the Nintendo/DSI product (16 MB DSi-mode RAM). Same prerequisites as build-stage1.sh, plus the patch applied
# (the `dsi` branch of work/dslinux, exported in patches/). Output: work/dslinux/images/ and out/dsi-card/.
set -e
cd "$(dirname "$0")/.."
scripts/prepare-tree.sh
# build-type prompt = DSI; then release build? (default); libc (default); "Default all settings" = y; the rest default.
scripts/in-container.sh 'cd /work && (printf "DSI\n\n\ny\n"; yes "") | make config > /out/dsi-config.log 2>&1 && make dep > /out/dsi-dep.log 2>&1 && make > /out/dsi-build.log 2>&1'
scripts/make-variants.sh
ls -la out/dsi-card
