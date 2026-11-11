#!/bin/sh
# Create the preallocated log file DSLinux may write on the SD card: a 1 MiB file of zeros named DSILOG.TXT.
# Copy it into the card's linux/ folder (so it is sd:/linux/DSILOG.TXT) from a PC. The kernel's SD driver refuses every
# write that is not inside this file's sectors. Usage: scripts/make-logfile.sh [output-path]
OUT="${1:-out/dsi-card/sd-root/linux/DSILOG.TXT}"
python3 -I -c "import sys; open(sys.argv[1],'wb').write(b'\0'*1048576)" "$OUT" && ls -la "$OUT"
