# Sourced by the scripts that touch the SD card: where it is mounted on this PC. Override with CARD=/path/to/card.
CARD=${CARD:-/run/media/sharris/1419-260A}
IMG=${IMG:-$CARD/linux/ROOTFS.IMG}

card_present() {
	[ -d "$CARD/linux" ]
}

# "mkdir PATH" lines for debugfs, only for directories that are not in the image yet. debugfs's mkdir on an existing directory is not
# harmless: e2fsprogs 1.47 allocates the new directory, fails to link it and leaves it orphaned (found 2026-11-18, repaired with
# rootfs-check.sh -y; the orphans end up in /lost+found).
img_mkdir() {
	for _img_d in "$@"; do		# (a name of its own: sh has no local variables, callers loop over $d)
		debugfs -R "stat $_img_d" "$IMG" 2>/dev/null | grep -q "Type: directory" || echo "mkdir $_img_d"
	done
}
