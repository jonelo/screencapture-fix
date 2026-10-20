#!/bin/zsh

# screencapture-fix
# Fixes a broken screencapture on an OCLP-patched MacBookPro8,1 running
# macOS Sequoia by replacing /usr/sbin/screencapture with a clean binary.
# https://github.com/jonelo/screencapture-fix

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

PROJECT_URL="https://github.com/jonelo/screencapture-fix"
HOWTO_URL="${PROJECT_URL}#how-to-get-a-clean-screencapture-binary"

# Inside a zsh function $0 is the name of the function, so keep the script's path
SCRIPT="$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="${SCRIPT_DIR}/screencapture"
# The file that is validated, by default the clean binary next to the script,
# or another one given by --check <path>, which is diagnosed only (CHECK_PATH_GIVEN=1)
CHECK_FILE="${BINARY}"
CHECK_PATH_GIVEN=0

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

usage() {
  cat << EOF
screencapture-fix - fixes a broken screencapture on an OCLP-patched
MacBookPro8,1 running macOS Sequoia by replacing /usr/sbin/screencapture
with a clean binary.

Usage: ${SCRIPT:t} [options]

Options:
  (none)              replace /usr/sbin/screencapture by the clean
                      screencapture binary next to the script and reboot
                      (requires sudo)
  -c, --check [path]  validate the clean screencapture binary next to the
                      script, or the one at path (a file or a folder that
                      contains it) to find out whether it is broken,
                      don't change anything
  -g, --get <dir>     extract screencapture from a macOS installer, e.g. from
                      the USB stick created by OCLP, and validate it,
                      don't change anything
  -f, --force         install the clean binary even if it is installed already
  -h, --help          show this help

The clean binary is expected next to the script, named "screencapture",
or appended to the script as its payload.

Examples:
  ./${SCRIPT:t} --get "/Volumes/Install macOS Sequoia"
  ./${SCRIPT:t} --check
  ./${SCRIPT:t} --check /usr/sbin
  sudo ./${SCRIPT:t}
  sudo ./${SCRIPT:t} --force

More information: ${PROJECT_URL}
EOF
}

how_to_get_binary() {
  local candidate

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

# ---------------------------------------------------------------------------
# Getting the screencapture binary
# ---------------------------------------------------------------------------

# Sets INSTALLER to the macOS installer app in $1.
# $1 is either the installer app itself or a folder that contains it,
# e.g. the root of a USB stick created by OCLP. %/ strips a trailing slash.
# The zsh glob qualifier (N/) expands to nothing if there is no match
# and matches directories only.
find_installer() {
  local dir="${1%/}"
  local -a installers

  if [[ "${dir}" == *.app && -d "${dir}" ]]; then
    installers=( "${dir}" )
  else
    installers=( "${dir}"/Install\ macOS*.app(N/) )
  fi
  if [ ${#installers} -ne 1 ]; then
    printf "Error: Expected exactly one \"Install macOS *.app\" in %s, but found %d.\n" "$1" ${#installers}
    exit 1
  fi
  INSTALLER="${installers[1]}"
  echo "Installer     : ${INSTALLER}"
}

# Mounts the SharedSupport.dmg of the INSTALLER to GET_MOUNT.
# -readonly guarantees that the installer remains unchanged, -noverify skips
# the lengthy verification of the big image, -nobrowse hides it from the Finder.
mount_shared_support() {
  local sharedSupport="${INSTALLER}/Contents/SharedSupport/SharedSupport.dmg"

  if [ ! -f "${sharedSupport}" ]; then
    printf "Error: %s not found.\n" "${sharedSupport}"
    echo "This is either an install stub only or an installer that is too old."
    exit 1
  fi

  echo "Mounting ${sharedSupport:t} (read-only)"
  if ! hdiutil attach "${sharedSupport}" -readonly -noverify -nobrowse -mountpoint "${GET_MOUNT}" &> /dev/null; then
    printf "Error: Could not mount %s.\n" "${sharedSupport}"
    exit 1
  fi
}

# Sets ZIP to the MobileAsset zip archive in GET_MOUNT that contains the
# entire system. Some installers keep it in an SFR subfolder.
find_asset_zip() {
  local assetDir
  local -a zips

  if [ -d "${GET_MOUNT}/SFR" ]; then
    assetDir="${GET_MOUNT}/SFR/com_apple_MobileAsset_SFRSoftwareUpdate"
  else
    assetDir="${GET_MOUNT}/com_apple_MobileAsset_MacSoftwareUpdate"
  fi
  zips=( "${assetDir}"/*.zip(N.) )
  if [ ${#zips} -ne 1 ]; then
    printf "Error: Expected exactly one zip archive in %s, but found %d.\n" "${assetDir}" ${#zips}
    exit 1
  fi
  ZIP="${zips[1]}"
}

# Prints the macOS version of the installer and warns if it differs from this Mac.
# unzip -p writes a file from the archive to stdout. plutil reads it from
# stdin (the trailing -), and "-extract <key> raw" prints the plain value.
print_installer_version() {
  local plist installerVersion installerBuild

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
}

# Extracts usr/sbin/screencapture from the ZIP to GET_TMP and sets CHUNK.
# The system files are spread over the chunks payload.000, payload.001, ...
# Each chunk is a pbzx compressed Apple Archive. The chunks are not sorted by
# path, so they are streamed one after another to aa until it has extracted
# screencapture. unzip -Z1 lists the names only, but in zip order, hence the sort.
# -include-regex restricts the extraction to exactly that one file.
extract_from_payload() {
  local chunk

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
  CHUNK="${chunk:t}"
  printf "Found usr/sbin/screencapture in %s\n" "${CHUNK}"
}

# Removes the mount point and the extracted file of get_from_installer.
# rmdir only removes empty folders, so it never touches a still mounted image.
cleanup_get() {
  hdiutil detach "${GET_MOUNT}" &> /dev/null
  rm -rf "${GET_TMP}/usr"
  rmdir "${GET_MOUNT}" "${GET_TMP}" 2> /dev/null
}

# Extracts the screencapture binary from the macOS installer in $1 to BINARY.
get_from_installer() {
  # localtraps restores the INT and TERM traps when the function returns
  setopt localoptions localtraps

  if [ -e "${BINARY}" ]; then
    printf "Error: %s exists already. Remove it first to get it from the installer.\n" "${BINARY}"
    exit 1
  fi

  find_installer "$1"

  # The temporary folder holds the mount point and the extracted binary.
  # The traps make sure that nothing is left behind, not even on Ctrl+C.
  # An EXIT trap set within a function runs as soon as the function ends.
  GET_TMP="$(mktemp -d -t screencapture-fix)"
  GET_MOUNT="${GET_TMP}/SharedSupport"
  mkdir "${GET_MOUNT}"
  trap cleanup_get EXIT
  trap 'cleanup_get; exit 130' INT TERM

  mount_shared_support
  find_asset_zip
  print_installer_version
  extract_from_payload

  # -X skips extended attributes. chmod is required, because the file
  # extracted by aa can lack the executable bits (seen when not run as root).
  if ! cp -X "${GET_TMP}/usr/sbin/screencapture" "${BINARY}"; then
    printf "Error: Could not copy the screencapture binary to %s.\n" "${BINARY}"
    exit 1
  fi
  chmod 755 "${BINARY}"
}

# Extracts the screencapture binary appended to the script to BINARY.
extract_appended_payload() {
  local mark lines

  # Is there a screencapture binary appended to the script?
  mark="$(grep -a -n "^# --payload_start--" "${SCRIPT}")"
  mark="${mark%%:*}"

  if [ -z "$mark" ]; then
    echo "The screencapture binary is also not appended to the script."
    how_to_get_binary
    exit 1
  fi

  lines="$(wc -l "${SCRIPT}")"
  lines="${lines% *}"
  lines="${lines##* }"

  if [ $lines -le $mark ]; then
    echo "The screencapture binary is also not appended to the script."
    how_to_get_binary
    exit 1
  fi

  echo "Extracting the payload"
  mark=$((mark + 1))
  tail -n +$mark "${SCRIPT}" > "${BINARY}.bz2"
  # bunzip2 replaces screencapture.bz2 by screencapture. Because of -f an
  # uncompressed payload is passed through unchanged, but a truncated or
  # corrupted bzip2 payload makes bunzip2 fail.
  if ! bunzip2 -f "${BINARY}.bz2"; then
    echo "Error: Extracting the payload failed. See \"Advanced Usage\" in the README."
    rm -f "${BINARY}.bz2" "${BINARY}"
    exit 1
  fi
  chmod 755 "${BINARY}"
}

# Sets CHECK_FILE to the screencapture binary given by --check <path>.
# $1 is either the binary itself or a folder that contains it, e.g. /usr/sbin.
resolve_check_path() {
  if [ -d "$1" ]; then
    CHECK_FILE="${1%/}/screencapture"
  else
    CHECK_FILE="$1"
  fi
  if [ ! -f "${CHECK_FILE}" ]; then
    printf "Error: %s not found.\n" "${CHECK_FILE}"
    exit 1
  fi
  CHECK_PATH_GIVEN=1
  echo "Checking      : ${CHECK_FILE}"
}

# Makes sure that BINARY exists, if necessary from the payload of the script.
locate_binary() {
  if [ ! -f "${BINARY}" ]; then
    printf "screencapture binary not found in %s\n" "${SCRIPT_DIR}"
    extract_appended_payload
  fi
}

# ---------------------------------------------------------------------------
# Validating the screencapture binary before the system volume is touched
# ---------------------------------------------------------------------------

# A clean screencapture from macOS Sequoia is a universal binary, while the
# broken one on an OCLP-patched MacBookPro8,1 contains x86_64 only.
#
# The architectures are taken from the output of file, because lipo is part
# of the Command Line Developer Tools and asks for installing them otherwise.
# For a universal binary file prints one line per architecture, e.g.
#   Mach-O universal binary with 2 architectures: [x86_64:...] [arm64e:...]
#   /path/screencapture (for architecture x86_64):	Mach-O 64-bit executable x86_64
#   /path/screencapture (for architecture arm64e):	Mach-O 64-bit executable arm64e
# and for a binary with a single architecture just
#   Mach-O 64-bit executable x86_64
# ${(@f)...} splits the output into lines, $match[1] is the first group of
# the regular expression, and ${line##* } is the last word of the line.
# ${(j: :)list} joins the list with blanks, e.g. "x86_64 arm64e", and
# the blanks around $archs let us match whole words only.
check_architectures() {
  local line archs
  local -a list

  for line in "${(@f)$(file -b "${CHECK_FILE}" 2>/dev/null)}"; do
    if [[ "${line}" =~ '\(for architecture ([^)]+)\)' ]]; then
      list+=( "${match[1]}" )
    elif [[ "${line}" == "Mach-O 64-bit executable "* ]]; then
      list+=( "${line##* }" )
    fi
  done
  archs="${(j: :)list}"
  echo "Architectures : ${archs:-none}"
  if [[ " ${archs} " != *" x86_64 "* ]]; then
    printf "Error: %s is not an executable for Intel Macs.\n" "${CHECK_FILE}"
    how_to_get_binary
    exit 1
  fi
  if [[ " ${archs} " != *" arm64e "* ]]; then
    printf "Error: %s contains x86_64 only. This looks like the broken binary\n" "${CHECK_FILE}"
    echo "of an OCLP-patched Mac. A clean one is universal (x86_64 arm64e)."
    how_to_get_binary
    exit 1
  fi
}

# codesign --verify fails if the binary has been modified or truncated.
# The requirement "anchor apple" additionally demands that Apple signed it.
check_signature() {
  if ! codesign --verify -R="anchor apple" "${CHECK_FILE}" 2>/dev/null; then
    printf "Error: %s does not carry a valid Apple code signature.\n" "${CHECK_FILE}"
    how_to_get_binary
    exit 1
  fi
}

# cmp -s compares both files byte by byte without any output,
# exit code 0 means that they are identical. --force (FORCE=1) installs it anyway.
# A binary given by --check <path> is diagnosed only, so being identical is fine.
# -ef is true if both paths refer to the same file, e.g. --check /usr/sbin.
check_not_installed() {
  if [ ${CHECK_PATH_GIVEN} -eq 1 ]; then
    if [[ ! "${CHECK_FILE}" -ef /usr/sbin/screencapture ]] && cmp -s "${CHECK_FILE}" /usr/sbin/screencapture; then
      printf "Note: %s is identical to the installed /usr/sbin/screencapture.\n" "${CHECK_FILE}"
    fi
    return
  fi

  if cmp -s "${CHECK_FILE}" /usr/sbin/screencapture; then
    if [ ${FORCE} -eq 1 ]; then
      printf "Warning: %s is identical to the installed /usr/sbin/screencapture.\n" "${CHECK_FILE}"
      echo "         Installing it anyway because of --force."
      return
    fi
    printf "Error: %s is identical to the installed /usr/sbin/screencapture.\n" "${CHECK_FILE}"
    echo "Either the fix has already been applied or the binary has been taken from this Mac."
    echo "Use --force to install it anyway."
    exit 1
  fi
}

# Compares the SHA-256 checksum with the known clean binaries (see FAQs in the README).
# shasum prints "<checksum>  <file>", %% * keeps the checksum only.
# An unknown checksum is not an error, because newer macOS versions ship other binaries.
check_checksum() {
  local checksum osVersion binaryVersion=""
  local versionMatches=0

  checksum="$(shasum -a 256 "${CHECK_FILE}")"
  checksum="${checksum%% *}"
  osVersion="$(sw_vers -productVersion)"
  echo "SHA-256       : ${checksum}"
  echo "macOS version : ${osVersion}"
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
}

# csrutil status prints e.g. "System Integrity Protection status: enabled."
# OCLP usually reports "unknown (Custom Configuration)" which is fine,
# but with fully enabled SIP the system volume can't be mounted writable.
check_sip() {
  if [[ "$(csrutil status 2>/dev/null)" == *"status: enabled."* ]]; then
    echo "Warning: System Integrity Protection (SIP) is enabled. Patching will most likely fail."
  fi
}

validate_binary() {
  check_architectures
  check_signature
  check_not_installed
  check_checksum
  check_sip
}

# ---------------------------------------------------------------------------
# Patching the system volume
# ---------------------------------------------------------------------------

# Sets SYSTEM_DISK to the system volume of the booted APFS container.
find_system_volume() {
  local line temp containerDisk snapshotDisk

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
    exit 1
  fi

  temp="${line#* disk}"
  snapshotDisk="disk${temp%% *}"          # e.g. disk1s4s1
  SYSTEM_DISK="${snapshotDisk%s[0-9]*}"   # strip trailing "s<n>" -> e.g. disk1s4

  echo "APFS Snapshot : /dev/${snapshotDisk}"
  echo "System Volume : /dev/${SYSTEM_DISK}"
}

# Mounts the SYSTEM_DISK writable to MOUNTPOINT.
mount_system_volume() {
  MOUNTPOINT="${HOME}/mount.$$"
  mkdir -p "${MOUNTPOINT}"

  if ! mount -o nobrowse -t apfs /dev/${SYSTEM_DISK} "${MOUNTPOINT}"; then
    echo "Error: Mounting /dev/${SYSTEM_DISK} failed. Reboot first and try again."
    rmdir "${MOUNTPOINT}"
    exit 1
  fi
}

# Unmounts the system volume, removes the mount point and exits with an error.
abort_patch() {
  umount "${MOUNTPOINT}"
  rmdir "${MOUNTPOINT}"
  exit 1
}

# Puts the backup of the original screencapture binary back in place.
restore_original() {
  mv "${MOUNTPOINT}/usr/sbin/screencapture.old" "${MOUNTPOINT}/usr/sbin/screencapture"
}

# Backs up the old file and copies the new one.
replace_binary() {
  if ! mv "${MOUNTPOINT}/usr/sbin/screencapture" "${MOUNTPOINT}/usr/sbin/screencapture.old"; then
    echo "Error: Could not back up the original screencapture binary."
    abort_patch
  fi

  # -X skips extended attributes, so e.g. the quarantine flag of a binary
  # received by AirDrop or a browser download doesn't end up on the system volume.
  if ! cp -fX "${BINARY}" "${MOUNTPOINT}/usr/sbin/screencapture"; then
    echo "Error: Could not copy new screencapture binary. Restoring original."
    restore_original
    abort_patch
  fi

  chmod 755 "${MOUNTPOINT}/usr/sbin/screencapture"

  echo "screencapture has been replaced:"
  ls -la "${MOUNTPOINT}/usr/sbin/screencapture"*
}

# Makes the changes persistent by blessing a new snapshot.
bless_snapshot() {
  if ! bless --folder "${MOUNTPOINT}/System/Library/CoreServices" --bootefi --create-snapshot; then
    echo "Error: bless failed. Restoring original screencapture binary."
    restore_original
    abort_patch
  fi
}

# Unmounts the system volume and removes the mount point.
unmount_system_volume() {
  if ! umount "${MOUNTPOINT}"; then
    echo "Warning: Unmounting ${MOUNTPOINT} failed. Please unmount manually before rebooting."
  else
    rmdir "${MOUNTPOINT}"
  fi
}

reboot_system() {
  read "dummy?Press any key to reboot (or hit Ctrl+C to abort)> "
  echo "Rebooting the system ..."
  reboot
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # --check only locates and validates the screencapture binary and exits
  # before the system volume is touched. That does not require root.
  # --check <path> validates the binary at path instead, e.g. /usr/sbin.
  # --get <dir> does the same, but extracts the binary from a macOS installer first.
  # --force installs the binary even if it is identical to the installed one.
  local checkOnly=0 checkPath="" getDir=""
  FORCE=0

  # The options can be combined, shift drops the option that has been processed
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -c|--check)
        checkOnly=1
        # the path is optional, a following option such as -f is not a path
        if [[ -n "$2" && "$2" != -* ]]; then
          checkPath="$2"
          shift
        fi
        ;;
      -g|--get)
        # a following option such as -f is not a directory
        if [[ -z "$2" || "$2" == -* ]]; then
          echo "Usage: ${SCRIPT} $1 <dir>"
          echo "  <dir> is a USB stick with a macOS installer or the installer app itself, e.g."
          echo "  ${SCRIPT} $1 \"/Volumes/Install macOS Sequoia\""
          exit 1
        fi
        checkOnly=1
        getDir="$2"
        shift
        ;;
      -f|--force)
        FORCE=1
        ;;
      *)
        echo "Unknown option: $1"
        echo "Run \"${SCRIPT} --help\" to see the available options."
        exit 1
        ;;
    esac
    shift
  done

  if [[ -n "${checkPath}" && -n "${getDir}" ]]; then
    echo "Error: --check <path> can't be combined with --get."
    exit 1
  fi

  # Diagnose the binary at path only, nothing else is done
  if [ -n "${checkPath}" ]; then
    resolve_check_path "${checkPath}"
    validate_binary
    echo "Check passed. ${CHECK_FILE} looks like a clean screencapture binary."
    exit 0
  fi

  if [[ ${checkOnly} == 0 && $UID != 0 ]]; then
    echo "This script must be run as root."
    echo "Tip: run it with --check first to validate your screencapture binary without root."
    exit 1
  fi

  if [ -n "${getDir}" ]; then
    get_from_installer "${getDir}"
  fi
  locate_binary
  validate_binary

  if [ ${checkOnly} -eq 1 ]; then
    echo "Check passed. Run the script with sudo and without any option to apply the fix."
    exit 0
  fi

  find_system_volume
  mount_system_volume
  replace_binary
  bless_snapshot
  unmount_system_volume
  reboot_system
}

main "$@"

exit
# --payload_start--
