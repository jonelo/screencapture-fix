#!/bin/zsh

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

if [[ $UID != 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create a Mount-Point
mkdir -p ~/mount

# Identify the System-Volume (APFS Snapshot)
# Example diskutil's output:
#    5:              APFS Snapshot com.apple.bless.FBDB... 12.5 GB    disk1s4s1
#
line="$(diskutil list /dev/disk1 | grep "APFS Snapshot")"
temp=${line#* disk}
disk="disk${temp%s?}"

# Mount the System-Volume writable
sudo mount -o nobrowse -t apfs /dev/${disk} ~/mount

# Backup the old file and copy the new one
mv ~/mount/usr/sbin/screencapture ~/mount/usr/sbin/screencapture.old
cp -f ${SCRIPT_DIR}/screencapture ~/mount/usr/sbin/screencapture

echo "screencapture has been replaced:"
ls -la ~/mount/usr/sbin/screencapture*

# Make changes persistent (Snapshot blessen)
sudo bless --folder ~/mount/System/Library/CoreServices --bootefi --create-snapshot

# Reboot
read "dummy?Press any key to reboot (or hit Ctrl+C to abort)> "
echo "Rebooting the system ..."
reboot


