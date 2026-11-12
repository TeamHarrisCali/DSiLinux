#!/bin/sh
# Writes the Wi-Fi settings DSLinux reads at boot into /etc/rc.conf inside the root image on the SD card (card in the PC), and an inetd
# line that starts the Dropbear SSH server. The DSi's DS Wi-Fi chip can only join an OPEN network (no password) or a WEP one, 2.4 GHz, 802.11b rates.
# Usage: scripts/set-wifi.sh [-i ROOTFS.IMG] ESSID [wepkey]      (static IP: set ip= / gateway= in rc.conf afterwards; default is DHCP)
IMG=/run/media/sharris/1419-260A/linux/ROOTFS.IMG
if [ "$1" = "-i" ]; then IMG="$2"; shift 2; fi
ESSID="$1"; WEP="$2"
[ -n "$ESSID" ] || { echo "usage: $0 [-i ROOTFS.IMG] ESSID [wepkey]"; exit 1; }
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
"$(dirname "$0")/rootfs-check.sh" "$IMG" || exit 1
T=$(mktemp -d)
cat > $T/rc.conf <<EOT
# DSLinuxDSi: defaults come from /etc/rc.defaults; add overrides here.
enable_network_on_boot="YES"
essid="$ESSID"
wepkey="$WEP"
ip=""
start_inetd="YES"
EOT
cat > $T/inetd.conf <<'EOT'
ssh stream tcp nowait root /usr/bin/dropbear dropbear -i -r /etc/dropbear_rsa_host_key
EOT
printf 'rm /etc/rc.conf\nwrite %s/rc.conf /etc/rc.conf\nrm /etc/inetd.conf\nwrite %s/inetd.conf /etc/inetd.conf\n' "$T" "$T" > $T/cmds
debugfs -w -f $T/cmds "$IMG" > /dev/null 2>&1
debugfs -R "cat /etc/rc.conf" "$IMG" 2>/dev/null
rm -rf $T
echo "done. First SSH use needs a host key: on the console, in the Terminal:  dropbearkey -t rsa -f /etc/dropbear_rsa_host_key"
