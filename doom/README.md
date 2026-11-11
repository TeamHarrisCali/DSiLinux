# DOOM on the DSi (dsdoom)

`doomgeneric_ds.c` is the platform layer for [doomgeneric](https://github.com/ozkl/doomgeneric) (GPL v2; id Software's DOOM source, commit
`e257a09`, not included here: `git clone` it and copy its `doomgeneric/` folder to `out/doom-build/src`). The game data is the **shareware**
`DOOM1.WAD` v1.9 (md5 `f0cefca49926d00903cf57551d901abe`, 4,196,020 bytes, freely distributable; it comes out of `doom19s.zip` by joining
`DOOMS_19.1` + `DOOMS_19.2` and unpacking the result with 7z). The registered `DOOM.WAD` / `DOOM2.WAD` of a purchased copy also work if renamed
`doom1.wad` (or pass `-iwad`).

* `doom/build.sh` builds `out/doom-build/dsdoom` (about 440 KB flat binary, 256 KB stack) with the DSLinux toolchain in the container.
* `doom/install.sh doom1.wad` copies binary, WAD and `default.cfg` to `/home/doom` in `linux/ROOTFS.IMG` (card in the PC). It is not in the ROM (the ROM
  is full); Start > Games > DOOM starts `/home/doom/dsdoom`.
* `doom/doomgeneric-ds.patch` (apply to the doomgeneric sources before building): zone 4 MB (minimum 3 MB) instead of 6 MB, and a 64 KB instead of 256 KB picture buffer, because the console had only about 6.4 MB free next to the desktop.
* dsdoom writes everything it prints (free memory, start-up messages, errors) to `/home/doom/dsdoom.log` in the image: read it on the PC with `debugfs -R "cat /home/doom/dsdoom.log" ROOTFS.IMG` after a try.
* Picture 320x200 -> 256x192 (4:3), low detail, 9 screen blocks (`default.cfg`), zone memory 4 MB, no sound, no music.
* Buttons: d-pad move/turn, A fire (Enter in menus), B use, L/R strafe, Y run, X next weapon ("y" in the quit question), Start menu, Select automap,
  Start + Select leave at once.
