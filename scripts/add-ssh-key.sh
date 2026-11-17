#!/bin/sh
# Lets a PC log in to the DSi by key, without a password: adds a public key (default ~/.ssh/id_rsa_dsi.pub) to /home/.ssh/authorized_keys
# in the card's ROOTFS.IMG, with the permissions Dropbear insists on (/home, /home/.ssh and the file writable by root only). Dropbear 0.48
# knows RSA keys only (ssh-keygen -t rsa). Once the file exists, Network > SSH server allows key logins only.
# Usage: scripts/add-ssh-key.sh [key.pub] [-i ROOTFS.IMG]
. "$(dirname "$0")/card.sh"
KEY="$HOME/.ssh/id_rsa_dsi.pub"
while [ $# -gt 0 ]; do
	case "$1" in
	-i) IMG="$2"; shift 2 ;;
	*) KEY="$1"; shift ;;
	esac
done
cd "$(dirname "$0")/.."
[ -f "$KEY" ] || { echo "no key $KEY (ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa_dsi)"; exit 1; }
grep -q "^ssh-rsa " "$KEY" || { echo "$KEY is not an RSA key: Dropbear 0.48 on the DSi only knows ssh-rsa"; exit 1; }
[ -f "$IMG" ] || { echo "no image: $IMG (card not mounted?)"; exit 1; }
scripts/rootfs-check.sh "$IMG" > /dev/null || { echo "image has errors: scripts/rootfs-check.sh -y first"; exit 1; }
mkdir -p out/sshkey
debugfs -R "cat /home/.ssh/authorized_keys" "$IMG" 2>/dev/null > out/sshkey/authorized_keys
grep -qF "$(cut -d' ' -f2 "$KEY")" out/sshkey/authorized_keys && { echo "already in /home/.ssh/authorized_keys"; exit 0; }
cat "$KEY" >> out/sshkey/authorized_keys
{
	echo "mkdir /home/.ssh"
	echo "rm /home/.ssh/authorized_keys"
	echo "write out/sshkey/authorized_keys /home/.ssh/authorized_keys"
	echo "sif /home mode 040755"
	echo "sif /home/.ssh mode 040700"
	echo "sif /home/.ssh/authorized_keys mode 0100600"
	echo "sif /home/.ssh uid 0"
	echo "sif /home/.ssh gid 0"
	echo "sif /home/.ssh/authorized_keys uid 0"
	echo "sif /home/.ssh/authorized_keys gid 0"
} > out/sshkey/cmds
debugfs -w -f out/sshkey/cmds "$IMG" > /dev/null 2>&1
sync
debugfs -R "cat /home/.ssh/authorized_keys" "$IMG" 2>/dev/null | grep -qF "$(cut -d' ' -f2 "$KEY")" && echo "added to /home/.ssh/authorized_keys: $(cut -d' ' -f3- "$KEY")" || { echo "NOT added"; exit 1; }
