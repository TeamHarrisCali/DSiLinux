# Sourced by the scripts that touch the SD card: where it is mounted on this PC. Override with CARD=/path/to/card.
CARD=${CARD:-/run/media/sharris/1419-260A}
IMG=${IMG:-$CARD/linux/ROOTFS.IMG}

card_present() {
	[ -d "$CARD/linux" ]
}
