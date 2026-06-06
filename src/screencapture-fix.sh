#!/bin/zsh

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

if [[ $UID != 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Searching for the screencapture binary
if [ ! -f "${SCRIPT_DIR}/screencapture" ]; then

  printf "screencapture binary not found in %s\n" "${SCRIPT_DIR}"

  # Is there a screencapture binary appended to the script?
  mark="$(grep -a -n "^# --payload_start--" "$0")"
  mark="${mark%%:*}"

  if [ -z "$mark" ]; then
    echo "The screencapture binary is also not appended to the script."
    exit 1
  fi

  lines="$(wc -l "$0")"
  lines="${lines% *}"
  lines="${lines##* }"

  if [ $lines -gt $mark ]; then
    echo "Extracting the payload"

    mark=$((mark + 1))
    tail -n +$mark "$0" > "${SCRIPT_DIR}/screencapture.bz2"
    bunzip2 -f "${SCRIPT_DIR}/screencapture.bz2"
    chmod 755 "${SCRIPT_DIR}/screencapture"
  else
    echo "The screencapture binary is also not appended to the script."
    exit 1
  fi
fi

# Create a Mount-Point
MOUNTPOINT="${HOME}/mount.$$"
mkdir -p "${MOUNTPOINT}"

# Identify the currently booted APFS container disk dynamically.
# "diskutil info /" reports "Part of Whole" as the container disk (e.g. "disk1", "disk2").
#
# Example output of `diskutil info /`:
#   Part of Whole:             disk1
#
# ##*: strips everything up to and including the colon,
# ##*  strips all leading spaces, leaving just e.g. "disk1".
#
line="$(diskutil info / | grep 'Part of Whole:')"
containerDisk="${line##*:}"
containerDisk="${containerDisk##* }"
if [ -z "$containerDisk" ]; then
  echo "Error: Could not determine the APFS container disk. Aborting."
  rmdir "${MOUNTPOINT}"
  exit 1
fi
echo "APFS container: /dev/${containerDisk}"

# Identify the System-Volume from the APFS Snapshot entry in that container.
# The snapshot device (e.g. "disk1s4s1") minus the trailing "s<n>" gives
# the writable System volume (e.g. "disk1s4").
#
# Example diskutil list output:
#    5:              APFS Snapshot com.apple.bless.FBDB... 12.5 GB    disk1s4s1
#
# %s[0-9]* strips "s" plus all following digits, handling multi-digit slice numbers.
#
line="$(diskutil list /dev/${containerDisk} | grep "APFS Snapshot")"
if [ -z "$line" ]; then
  echo "Error: No APFS Snapshot found on /dev/${containerDisk}. Aborting."
  rmdir "${MOUNTPOINT}"
  exit 1
fi

temp="${line#* disk}"
snapshotDisk="disk${temp%% *}"          # e.g. disk1s4s1
systemDisk="${snapshotDisk%s[0-9]*}"    # strip trailing "s<n>" -> e.g. disk1s4

echo "APFS Snapshot : /dev/${snapshotDisk}"
echo "System Volume : /dev/${systemDisk}"

# Mount the System-Volume writable
mount -o nobrowse -t apfs /dev/${systemDisk} "${MOUNTPOINT}"
if [ "$?" -ne 0 ]; then
  echo "Error: Mounting /dev/${systemDisk} failed. Reboot first and try again."
  rmdir "${MOUNTPOINT}"
  exit 1
fi

# Backup the old file and copy the new one
if ! mv "${MOUNTPOINT}/usr/sbin/screencapture" "${MOUNTPOINT}/usr/sbin/screencapture.old"; then
  echo "Error: Could not back up the original screencapture binary."
  umount "${MOUNTPOINT}"
  rmdir "${MOUNTPOINT}"
  exit 1
fi

if ! cp -f "${SCRIPT_DIR}/screencapture" "${MOUNTPOINT}/usr/sbin/screencapture"; then
  echo "Error: Could not copy new screencapture binary. Restoring original."
  mv "${MOUNTPOINT}/usr/sbin/screencapture.old" "${MOUNTPOINT}/usr/sbin/screencapture"
  umount "${MOUNTPOINT}"
  rmdir "${MOUNTPOINT}"
  exit 1
fi

chmod 755 "${MOUNTPOINT}/usr/sbin/screencapture"

echo "screencapture has been replaced:"
ls -la "${MOUNTPOINT}/usr/sbin/screencapture"*

# Make changes persistent (Snapshot blessen)
if ! bless --folder "${MOUNTPOINT}/System/Library/CoreServices" --bootefi --create-snapshot; then
  echo "Error: bless failed. Restoring original screencapture binary."
  mv "${MOUNTPOINT}/usr/sbin/screencapture.old" "${MOUNTPOINT}/usr/sbin/screencapture"
  umount "${MOUNTPOINT}"
  rmdir "${MOUNTPOINT}"
  exit 1
fi

# Unmount the System-Volume and remove the mount point
umount "${MOUNTPOINT}"
if [ "$?" -ne 0 ]; then
  echo "Warning: Unmounting ${MOUNTPOINT} failed. Please unmount manually before rebooting."
else
  rmdir "${MOUNTPOINT}"
fi

# Reboot
read "dummy?Press any key to reboot (or hit Ctrl+C to abort)> "
echo "Rebooting the system ..."
reboot

exit
# --payload_start--
