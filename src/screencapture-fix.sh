#!/bin/zsh

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

HOWTO_URL="https://github.com/jonelo/screencapture-fix#how-to-get-a-clean-screencapture-binary"

# With --check the script only locates and validates the screencapture binary
# and exits before the system volume is touched. That does not require root.
# --get <dir> does the same, but extracts the binary from a macOS installer first.
CHECK_ONLY=0
GET_DIR=""
case "$1" in
  --check)
    CHECK_ONLY=1
    ;;
  --get)
    if [ -z "$2" ]; then
      echo "Usage: $0 --get <dir>"
      echo "  <dir> is a USB stick with a macOS installer or the installer app itself, e.g."
      echo "  $0 --get \"/Volumes/Install macOS Sequoia\""
      exit 1
    fi
    CHECK_ONLY=1
    GET_DIR="$2"
    ;;
esac

if [[ $CHECK_ONLY == 0 && $UID != 0 ]]; then
  echo "This script must be run as root."
  echo "Tip: run it with --check first to validate your screencapture binary without root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="${SCRIPT_DIR}/screencapture"
# Inside a zsh function $0 is the name of the function, so keep the script's path
SCRIPT="$0"

how_to_get_binary() {
  printf "Copy a clean screencapture binary from another Mac running macOS Sequoia 15.7.4 or later\n"
  printf "to %s (the file must be named exactly \"screencapture\"),\n" "${BINARY}"
  printf "or extract it from a macOS Sequoia installer, e.g. from a USB stick created by OCLP:\n"
  printf "  %s --get \"/Volumes/Install macOS Sequoia\"\n" "${SCRIPT}"
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

# Extract the screencapture binary from a macOS installer
if [ -n "${GET_DIR}" ]; then

  if [ -e "${BINARY}" ]; then
    printf "Error: %s exists already. Remove it first to get it from the installer.\n" "${BINARY}"
    exit 1
  fi

  # GET_DIR is either the installer app itself or a folder that contains it,
  # e.g. the root of a USB stick created by OCLP. %/ strips a trailing slash.
  # The zsh glob qualifier (N/) expands to nothing if there is no match
  # and matches directories only.
  if [[ "${GET_DIR%/}" == *.app && -d "${GET_DIR}" ]]; then
    installers=( "${GET_DIR%/}" )
  else
    installers=( "${GET_DIR%/}"/Install\ macOS*.app(N/) )
  fi
  if [ ${#installers} -ne 1 ]; then
    printf "Error: Expected exactly one \"Install macOS *.app\" in %s, but found %d.\n" "${GET_DIR}" ${#installers}
    exit 1
  fi
  echo "Installer     : ${installers[1]}"

  SHARED_SUPPORT="${installers[1]}/Contents/SharedSupport/SharedSupport.dmg"
  if [ ! -f "${SHARED_SUPPORT}" ]; then
    printf "Error: %s not found.\n" "${SHARED_SUPPORT}"
    echo "This is either an install stub only or an installer that is too old."
    exit 1
  fi

  # The temporary folder holds the mount point and the extracted binary.
  # The traps make sure that nothing is left behind, not even on Ctrl+C.
  # rmdir only removes empty folders, so it never touches a still mounted image.
  GET_TMP="$(mktemp -d -t screencapture-fix)"
  GET_MOUNT="${GET_TMP}/SharedSupport"
  mkdir "${GET_MOUNT}"
  cleanup_get() {
    hdiutil detach "${GET_MOUNT}" &> /dev/null
    rm -rf "${GET_TMP}/usr"
    rmdir "${GET_MOUNT}" "${GET_TMP}" 2> /dev/null
  }
  trap cleanup_get EXIT
  trap 'cleanup_get; exit 130' INT TERM

  # -readonly guarantees that the installer remains unchanged, -noverify skips
  # the lengthy verification of the big image, -nobrowse hides it from the Finder.
  echo "Mounting ${SHARED_SUPPORT:t} (read-only)"
  if ! hdiutil attach "${SHARED_SUPPORT}" -readonly -noverify -nobrowse -mountpoint "${GET_MOUNT}" &> /dev/null; then
    printf "Error: Could not mount %s.\n" "${SHARED_SUPPORT}"
    exit 1
  fi

  # The image contains a MobileAsset zip archive with the entire system,
  # some installers keep it in an SFR subfolder.
  if [ -d "${GET_MOUNT}/SFR" ]; then
    ASSET_DIR="${GET_MOUNT}/SFR/com_apple_MobileAsset_SFRSoftwareUpdate"
  else
    ASSET_DIR="${GET_MOUNT}/com_apple_MobileAsset_MacSoftwareUpdate"
  fi
  zips=( "${ASSET_DIR}"/*.zip(N.) )
  if [ ${#zips} -ne 1 ]; then
    printf "Error: Expected exactly one zip archive in %s, but found %d.\n" "${ASSET_DIR}" ${#zips}
    exit 1
  fi
  ZIP="${zips[1]}"

  # unzip -p writes a file from the archive to stdout. plutil reads it from
  # stdin (the trailing -), and "-extract <key> raw" prints the plain value.
  plist="$(unzip -p "${ZIP}" AssetData/boot/SystemVersion.plist 2> /dev/null)"
  installerVersion="$(plutil -extract ProductVersion raw -o - - <<< "${plist}" 2> /dev/null)"
  installerBuild="$(plutil -extract ProductBuildVersion raw -o - - <<< "${plist}" 2> /dev/null)"
  if [ -z "${installerVersion}" ]; then
    printf "Error: No SystemVersion.plist found in %s.\n" "${ZIP}"
    exit 1
  fi
  echo "Installer for : macOS ${installerVersion} (${installerBuild})"
  if [[ "${installerVersion}" != "$(sw_vers -productVersion)" || "${installerBuild}" != "$(sw_vers -buildVersion)" ]]; then
    echo "Warning: This Mac runs macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))."
    echo "         Use an installer of the same version as the Mac that you want to fix."
  fi

  # The system files are spread over the chunks payload.000, payload.001, ...
  # Each chunk is a pbzx compressed Apple Archive. The chunks are not sorted by
  # path, so they are streamed one after another to aa until it has extracted
  # screencapture. unzip -Z1 lists the names only, but in zip order, hence the sort.
  # -include-regex restricts the extraction to exactly that one file.
  echo "Searching for usr/sbin/screencapture, this can take several minutes ..."
  for chunk in $(unzip -Z1 "${ZIP}" 'AssetData/payloadv2/payload.[0-9][0-9][0-9]' 2> /dev/null | sort); do
    # \r returns to the start of the line, so the progress stays on one line
    printf "\rSearching %s" "${chunk:t}"
    unzip -p "${ZIP}" "${chunk}" | aa extract -d "${GET_TMP}" -include-regex '^usr/sbin/screencapture$'
    if [ -f "${GET_TMP}/usr/sbin/screencapture" ]; then
      break
    fi
  done
  printf "\n"

  if [ ! -f "${GET_TMP}/usr/sbin/screencapture" ]; then
    printf "Error: usr/sbin/screencapture not found in %s.\n" "${ZIP}"
    exit 1
  fi
  printf "Found usr/sbin/screencapture in %s\n" "${chunk:t}"

  # -X skips extended attributes. chmod is required, because the file
  # extracted by aa can lack the executable bits (seen when not run as root).
  if ! cp -X "${GET_TMP}/usr/sbin/screencapture" "${BINARY}"; then
    printf "Error: Could not copy the screencapture binary to %s.\n" "${BINARY}"
    exit 1
  fi
  chmod 755 "${BINARY}"

  cleanup_get
  trap - EXIT INT TERM
fi

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
  echo "Check passed. Run the script with sudo and without any option to apply the fix."
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
