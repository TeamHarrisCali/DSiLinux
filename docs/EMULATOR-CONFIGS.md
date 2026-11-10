# melonDS test configs

`scripts/melon-ds.sh <name> <rom>` runs the Flatpak melonDS with `XDG_CONFIG_HOME` pointing at
`~/.var/app/net.kuribo64.melonDS/config-dslinuxtest-<name>/`, so the real config (and its DSi BIOS/firmware/NAND paths) is never used.
Copy `scripts/melonds-configs/<name>.toml` to `<that dir>/melonDS/melonDS.toml` first (replace `$HOME`).

- `ds-img.toml`: DS console, FreeBIOS, direct boot, DLDI backed by a FAT image. **This is the working Stage 1 setup.**
- `ds-dldi.toml`: same but DLDI "folder" mode, which this DSLinux build cannot mount.

DS-mode configs need no dumps. DSi-mode configs would need your dumps; they are not created here, and I do not read them.
