#!/bin/zsh

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

HOWTO_URL="https://github.com/jonelo/screencapture-fix#how-to-get-a-clean-screencapture-binary"

# With --check the script only locates and validates the screencapture binary
# and exits before the system volume is touched. That does not require root.
CHECK_ONLY=0
if [ "$1" = "--check" ]; then
  CHECK_ONLY=1
fi

if [[ $CHECK_ONLY == 0 && $UID != 0 ]]; then
  echo "This script must be run as root."
  echo "Tip: run it with --check first to validate your screencapture binary without root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="${SCRIPT_DIR}/screencapture"

how_to_get_binary() {
  printf "Copy a clean screencapture binary from another Mac running macOS Sequoia 15.7.4 or later\n"
  printf "to %s (the file must be named exactly \"screencapture\").\n" "${BINARY}"
  printf "Step-by-step instructions: %s\n" "${HOWTO_URL}"

  # List files whose names start with "screencapture" (e.g. "screencapture copy"
  # or "screencapture.zip") to reveal naming mistakes. The zsh glob qualifier (N)
  # expands to nothing instead of failing if there is no match, (.) matches
  # regular files only. The script itself (screencapture-fix*) and a correctly
  # named but unsuitable binary are skipped. ${candidate:t} is the file name only.
  for candidate in "${SCRIPT_DIR}"/screencapture*(N.); do
    if [[ "${candidate:t}" != screencapture-fix* && "${candidate:t}" != screencapture ]]; then
      printf "Found \"%s\" - rename it to \"screencapture\" if it is the clean binary.\n" "${candidate:t}"
    fi
  done
}

# Searching for the screencapture binary
if [ ! -f "${BINARY}" ]; then

  printf "screencapture binary not found in %s\n" "${SCRIPT_DIR}"

  # Is there a screencapture binary appended to the script?
  mark="$(grep -a -n "^# --payload_start--" "$0")"
  mark="${mark%%:*}"

  if [ -z "$mark" ]; then
    echo "The screencapture binary is also not appended to the script."
    how_to_get_binary
    exit 1
  fi

  lines="$(wc -l "$0")"
  lines="${lines% *}"
  lines="${lines##* }"

  if [ $lines -gt $mark ]; then
    echo "Extracting the payload"

    mark=$((mark + 1))
    tail -n +$mark "$0" > "${BINARY}.bz2"
    # bunzip2 replaces screencapture.bz2 by screencapture. Because of -f an
    # uncompressed payload is passed through unchanged, but a truncated or
    # corrupted bzip2 payload makes bunzip2 fail.
    if ! bunzip2 -f "${BINARY}.bz2"; then
      echo "Error: Extracting the payload failed. See \"Advanced Usage\" in the README."
      rm -f "${BINARY}.bz2" "${BINARY}"
      exit 1
    fi
    chmod 755 "${BINARY}"
  else
    echo "The screencapture binary is also not appended to the script."
    how_to_get_binary
    exit 1
  fi
fi

# Validate the screencapture binary before the system volume is touched.
#
# lipo -archs prints the architectures of a Mach-O file, e.g. "x86_64 arm64e".
# A clean screencapture from macOS Sequoia is a universal binary, while the
# broken one on an OCLP-patched MacBookPro8,1 contains x86_64 only.
# The blanks around $archs let us match whole words only.
#
archs="$(lipo -archs "${BINARY}" 2>/dev/null)"
echo "Architectures : ${archs:-none}"
if [[ " ${archs} " != *" x86_64 "* ]]; then
  printf "Error: %s is not an executable for Intel Macs.\n" "${BINARY}"
  how_to_get_binary
  exit 1
fi
if [[ " ${archs} " != *" arm64e "* ]]; then
  printf "Error: %s contains x86_64 only. This looks like the broken binary\n" "${BINARY}"
  echo "of an OCLP-patched Mac. A clean one is universal (x86_64 arm64e)."
  how_to_get_binary
  exit 1
fi

# codesign --verify fails if the binary has been modified or truncated.
# The requirement "anchor apple" additionally demands that Apple signed it.
if ! codesign --verify -R="anchor apple" "${BINARY}" 2>/dev/null; then
  printf "Error: %s does not carry a valid Apple code signature.\n" "${BINARY}"
  how_to_get_binary
  exit 1
fi

# cmp -s compares both files byte by byte without any output,
# exit code 0 means that they are identical.
if cmp -s "${BINARY}" /usr/sbin/screencapture; then
  printf "Error: %s is identical to the installed /usr/sbin/screencapture.\n" "${BINARY}"
  echo "Either the fix has already been applied or the binary has been taken from this Mac."
  exit 1
fi

# Compare the SHA-256 checksum with the known clean binaries (see FAQs in the README).
# shasum prints "<checksum>  <file>", %% * keeps the checksum only.
# An unknown checksum is not an error, because newer macOS versions ship other binaries.
checksum="$(shasum -a 256 "${BINARY}")"
checksum="${checksum%% *}"
osVersion="$(sw_vers -productVersion)"
echo "SHA-256       : ${checksum}"
echo "macOS version : ${osVersion}"
binaryVersion=""
versionMatches=0
case "${checksum}" in
  e668501ed8406aebcc3572a9b349553a27d429d0acfe26a5b364c2290ea8013d)
    binaryVersion="15.7.4 - 15.7.7"
    [[ "${osVersion}" == 15.7.[4-7] ]] && versionMatches=1
    ;;
  15f8ae56fbbe2e51c8ccfd04406e47fc619bd78ec364489585757b2b09471e1b)
    binaryVersion="15.8"
    [[ "${osVersion}" == 15.8 || "${osVersion}" == 15.8.* ]] && versionMatches=1
    ;;
esac
if [ -z "${binaryVersion}" ]; then
  echo "Warning: Unknown SHA-256 checksum. Make sure the binary comes from macOS ${osVersion}."
elif [ ${versionMatches} -eq 0 ]; then
  echo "Warning: The binary is from macOS ${binaryVersion}, but this is macOS ${osVersion}."
else
  echo "The binary is the clean screencapture from macOS ${binaryVersion}."
fi

# csrutil status prints e.g. "System Integrity Protection status: enabled."
# OCLP usually reports "unknown (Custom Configuration)" which is fine,
# but with fully enabled SIP the system volume can't be mounted writable.
if [[ "$(csrutil status 2>/dev/null)" == *"status: enabled."* ]]; then
  echo "Warning: System Integrity Protection (SIP) is enabled. Patching will most likely fail."
fi

if [ ${CHECK_ONLY} -eq 1 ]; then
  echo "Check passed. Run the script with sudo and without --check to apply the fix."
  exit 0
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

# -X skips extended attributes, so e.g. the quarantine flag of a binary
# received by AirDrop or a browser download doesn't end up on the system volume.
if ! cp -fX "${BINARY}" "${MOUNTPOINT}/usr/sbin/screencapture"; then
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
