#!/bin/sh
# Launch the user's Flatpak melonDS with an ISOLATED config (never the user's real config, BIOS, firmware or NAND).
# Usage: scripts/melon-ds.sh <config-name> <rom.nds>
# The config lives in ~/.var/app/net.kuribo64.melonDS/config-dslinuxtest-<name>/melonDS/melonDS.toml (see docs/EMULATOR-CONFIGS.md).
# XDG_CONFIG_HOME must be set INSIDE the sandbox (flatpak --env is ignored for it).
NAME="$1"; ROM="$(readlink -f "$2")"
CFG="$HOME/.var/app/net.kuribo64.melonDS/config-dslinuxtest-$NAME"
[ -f "$CFG/melonDS/melonDS.toml" ] || { echo "no config $CFG/melonDS/melonDS.toml" >&2; exit 1; }
exec flatpak run --command=sh net.kuribo64.melonDS -c "XDG_CONFIG_HOME='$CFG' exec stdbuf -oL -eL melonDS '$ROM'"
