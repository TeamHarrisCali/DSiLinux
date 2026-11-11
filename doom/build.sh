#!/bin/sh
# Builds dsdoom (doomgeneric + doomgeneric_ds.c) with the DSLinux toolchain in the container. Source: out/doom-build/src (a copy of
# ozkl/doomgeneric's doomgeneric/ folder plus doom/doomgeneric_ds.c); result: out/doom-build/dsdoom. Run from the repository root.
set -e
cd "$(dirname "$0")/.."
cp doom/doomgeneric_ds.c out/doom-build/src/
scripts/in-container.sh 'cd /out/doom-build/src && rm -rf ../obj && mkdir ../obj &&
SRC="dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode d_net f_finale f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound i_system i_timer memio m_argv m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random p_ceilng p_doors p_enemy p_floor p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg p_setup p_sight p_spec p_switch p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs r_sky r_things sha1 sounds statdump st_lib st_stuff s_sound tables v_video wi_stuff w_checksum w_file w_main w_wad z_zone w_file_stdc i_input i_video doomgeneric doomgeneric_ds"
CF="-O2 -fomit-frame-pointer -fno-common -mswp-byte-writes -DCONFIG_NDS_ROM8BIT -mcpu=arm946e-s -mfpu=fpe3 -DEMBED -D__PIC__ -fpic -msingle-pic-base -Dlinux -D__linux__ -Dunix -D__uClinux__ -DNORMALUNIX -DLINUX -DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -D_DEFAULT_SOURCE -w -I."
OBJS=""
for f in $SRC; do arm-linux-elf-gcc $CF -c $f.c -o ../obj/$f.o || exit 1; OBJS="$OBJS ../obj/$f.o"; done
arm-linux-elf-gcc -O2 -mcpu=arm946e-s -mfpu=fpe3 -D__PIC__ -fpic -msingle-pic-base -Wl,-elf2flt="-s 262144" $OBJS -o ../dsdoom -lm &&
arm-linux-elf-size ../dsdoom; ls -la ../dsdoom'
