#!/bin/sh
# The C compiler for scripts/build-busybox.sh (copied to out/bb/cc.sh, run in the build container): the final link of BusyBox becomes a
# flat binary (-Wl,-elf2flt); that link runs ld with -r, which refuses --gc-sections, so that flag is dropped there. Other links
# (BusyBox's partial links with -r) and all compiles go through unchanged.
case " $* " in
*" -o busybox_unstripped "*)
	for a; do
		shift
		[ "$a" = "-Wl,--gc-sections" ] || set -- "$@" "$a"
	done
	exec /work/tools/ucfront-gcc arm-linux-elf-gcc "$@" -Wl,-elf2flt ;;
esac
exec /work/tools/ucfront-gcc arm-linux-elf-gcc "$@"
