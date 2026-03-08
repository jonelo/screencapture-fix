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
  mark="$(grep -a -n "^# --script_start--" "$0")"
  mark="${mark%%:*}"

  lines="$(wc -l "$0")"
  lines="${lines% *}"
  lines="${lines##* }"

  if [ $lines -gt $mark ]; then
    echo "Extracting the payload"

    mark=$((mark + 1))
    tail -n +$mark "$0" > "${SCRIPT_DIR}/sceencapture.bz2"
    bunzip2 -f "${SCRIPT_DIR}/screencapture.bz2"
    chmod 755 "${SCRIPT_DIR}/screencapture"
  else
    echo "screencapture binary is also not appended to the script."
    exit
  fi
fi

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
if [ "$?" -eq 0 ]; then

  # Backup the old file and copy the new one
  mv ~/mount/usr/sbin/screencapture ~/mount/usr/sbin/screencapture.old
  cp -f ${SCRIPT_DIR}/screencapture ~/mount/usr/sbin/screencapture

  echo "screencapture has been replaced:"
  ls -la ~/mount/usr/sbin/screencapture*

  # Make changes persistent (Snapshot blessen)
  sudo bless --folder ~/mount/System/Library/CoreServices --bootefi --create-snapshot
else
  echo "Mounting failed, reboot first, and try to run the script again"
fi

# Reboot
read "dummy?Press any key to reboot (or hit Ctrl+C to abort)> "
echo "Rebooting the system ..."
reboot

exit
# --script_start--
