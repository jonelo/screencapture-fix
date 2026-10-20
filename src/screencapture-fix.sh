#!/bin/zsh

# screencapture-fix 2.0.0
# Fixes a broken screencapture on an OCLP-patched MacBookPro8,1 running
# macOS Sequoia by replacing /usr/sbin/screencapture with a clean binary.
# https://github.com/jonelo/screencapture-fix

PATH="/sbin:/usr/sbin:/bin:/usr/bin"

PROJECT_URL="https://github.com/jonelo/screencapture-fix"
# The version of the script, see RELEASE_NOTES.md
VERSION="2.0.0"

# Inside a zsh function $0 is the name of the function, so keep the script's path
SCRIPT="$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The clean binary next to the script, --get stores the extracted binary there
BINARY="${SCRIPT_DIR}/screencapture"
# The binary that is broken on an OCLP-patched MacBookPro8,1
INSTALLED="/usr/sbin/screencapture"
OS_VERSION="$(sw_vers -productVersion)"
OS_BUILD="$(sw_vers -buildVersion)"

# The binary that is validated and installed, see select_binary
CHECK_FILE=""
# The action given by an option: install, check or get
MODE=""
# The binary given by -p <file>
PAYLOAD_FILE=""
# 1 if --force has been given
FORCE=0
# The temporary folder that holds the payload extracted from the script
PAYLOAD_TMP=""

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# All output is kept within 79 columns, so that nothing wraps in a terminal
# with the default width of 80 columns. That is why paths, which can be of any
# length, are printed on separate lines.

# Prints the lines $2... with the prefix $1 in front of the first line and
# indents the following lines by the length of the prefix.
# printf "%*s" prints the empty string padded to the given width.
message() {
  local prefix="$1" line
  shift
  printf "%s%s\n" "${prefix}" "$1"
  shift
  for line in "$@"; do
    printf "%*s%s\n" ${#prefix} "" "${line}"
  done
}

error() {
  message "Error: " "$@"
}

warning() {
  message "Warning: " "$@"
}

note() {
  message "Note: " "$@"
}

# Prints a status line such as "SHA-256   : <checksum>", the label $1 is
# padded to 9 characters. Further lines $3... are aligned with the value $2.
status() {
  message "$(printf "%-9s : " "$1")" "${@:2}"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

usage() {
  cat << EOF
screencapture-fix ${VERSION} - fixes a broken screencapture on an OCLP-patched
MacBookPro8,1 running macOS Sequoia by replacing /usr/sbin/screencapture
with a clean binary.

Usage: ${SCRIPT:t} [options]

Options:
  (none)                show this help and the status of the embedded payload
  -i, --install         replace /usr/sbin/screencapture by the clean binary
                        and reboot (requires sudo)
  -c, --check           find out whether /usr/sbin/screencapture is broken,
                        with -p whether <file> is a clean binary,
                        don't change anything
  -g, --get <dir>       extract screencapture from a macOS installer, e.g.
                        from the USB stick created by OCLP, to the folder of
                        the script and validate it, don't change anything else
  -p, --payload <file>  use <file> as the clean binary instead of the payload
                        embedded in the script
  -f, --force           install the clean binary even if it is installed
                        already
  -h, --help            show this help
  -v, --version         show the version

The clean binary is taken from -p <file>, otherwise from the payload
embedded in the script, otherwise from the file "screencapture" next to
the script.

Examples:
  ./${SCRIPT:t} --check
  ./${SCRIPT:t} --get "/Volumes/Install macOS Sequoia"
  ./${SCRIPT:t} --check -p ~/Desktop/screencapture
  sudo ./${SCRIPT:t} --install
  sudo ./${SCRIPT:t} --install -p ~/Desktop/screencapture

More information: ${PROJECT_URL}
EOF
}

how_to_get_binary() {
  local candidate

  echo "A clean screencapture binary from macOS Sequoia 15.7.4 or later is required."
  echo "Copy it from another Mac to"
  echo "  ${BINARY}"
  echo "or pass it with -p <file>, or extract it from a macOS Sequoia installer,"
  echo "e.g. from the USB stick created by OCLP:"
  echo "  ${SCRIPT} --get \"/Volumes/Install macOS Sequoia\""
  echo "Step-by-step instructions: see \"How to get a clean screencapture binary\""
  echo "at ${PROJECT_URL}"

  # List files whose names start with "screencapture" (e.g. "screencapture copy"
  # or "screencapture.zip") to reveal naming mistakes. The zsh glob qualifier (N)
  # expands to nothing instead of failing if there is no match, (.) matches
  # regular files only. The script itself (screencapture-fix*) and a correctly
  # named but unsuitable binary are skipped. ${candidate:t} is the file name only.
  for candidate in "${SCRIPT_DIR}"/screencapture*(N.); do
    if [[ "${candidate:t}" != screencapture-fix* && "${candidate:t}" != screencapture ]]; then
      note "Found \"${candidate:t}\" next to the script." \
           "Rename it to \"screencapture\" if it is the clean binary."
    fi
  done
}

# Prints how to install the binary that has passed the check.
# $1 is the file for -p, without $1 the binary is selected by --install itself.
install_hint() {
  echo "Install it with:"
  if [ -n "$1" ]; then
    echo "  sudo ${SCRIPT} --install -p $1"
  else
    echo "  sudo ${SCRIPT} --install"
  fi
}

# ---------------------------------------------------------------------------
# Getting the screencapture binary from a macOS installer
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
    error "Expected exactly one \"Install macOS *.app\", but found ${#installers} in" \
          "$1"
    exit 1
  fi
  INSTALLER="${installers[1]}"
  status "Installer" "${INSTALLER}"
}

# Mounts the SharedSupport.dmg of the INSTALLER to GET_MOUNT.
# -readonly guarantees that the installer remains unchanged, -noverify skips
# the lengthy verification of the big image, -nobrowse hides it from the Finder.
mount_shared_support() {
  local sharedSupport="${INSTALLER}/Contents/SharedSupport/SharedSupport.dmg"

  if [ ! -f "${sharedSupport}" ]; then
    error "Not found:" \
          "${sharedSupport}" \
          "This is either an install stub only or an installer that is too old."
    exit 1
  fi

  echo "Mounting ${sharedSupport:t} (read-only)"
  if ! hdiutil attach "${sharedSupport}" -readonly -noverify -nobrowse -mountpoint "${GET_MOUNT}" &> /dev/null; then
    error "Could not mount" \
          "${sharedSupport}"
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
    error "Expected exactly one zip archive, but found ${#zips} in" \
          "${assetDir}"
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
    error "No SystemVersion.plist found in" \
          "${ZIP}"
    exit 1
  fi
  status "Release" "macOS ${installerVersion} (${installerBuild})"
  if [[ "${installerVersion}" != "${OS_VERSION}" || "${installerBuild}" != "${OS_BUILD}" ]]; then
    warning "This Mac runs macOS ${OS_VERSION} (${OS_BUILD})." \
            "Use an installer of the same version as the Mac that you want to fix."
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
    error "usr/sbin/screencapture not found in" \
          "${ZIP}"
    exit 1
  fi
  CHUNK="${chunk:t}"
  status "Found" "usr/sbin/screencapture in ${CHUNK}"
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
    error "The screencapture binary exists already:" \
          "${BINARY}" \
          "Remove it first to get it from the installer."
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
    error "Could not copy the screencapture binary to" \
          "${BINARY}"
    exit 1
  fi
  chmod 755 "${BINARY}"
}

# ---------------------------------------------------------------------------
# Selecting the screencapture binary
# ---------------------------------------------------------------------------

# Sets PAYLOAD_MARK to the line number of the payload mark and succeeds,
# if a payload is appended to the script, i.e. if there are lines after the mark.
has_payload() {
  local lines

  PAYLOAD_MARK="$(grep -a -n "^# --payload_start--" "${SCRIPT}")"
  PAYLOAD_MARK="${PAYLOAD_MARK%%:*}"
  if [ -z "${PAYLOAD_MARK}" ]; then
    return 1
  fi

  lines="$(wc -l "${SCRIPT}")"
  lines="${lines% *}"
  lines="${lines##* }"
  [ ${lines} -gt ${PAYLOAD_MARK} ]
}

# Removes the payload extracted by extract_payload.
cleanup_payload() {
  if [ -n "${PAYLOAD_TMP}" ]; then
    rm -rf "${PAYLOAD_TMP}"
  fi
}

# Extracts the payload appended to the script to a temporary folder
# and sets PAYLOAD_BINARY. It is removed by cleanup_payload on exit.
extract_payload() {
  PAYLOAD_TMP="$(mktemp -d -t screencapture-fix)"
  PAYLOAD_BINARY="${PAYLOAD_TMP}/screencapture"

  tail -n +$((PAYLOAD_MARK + 1)) "${SCRIPT}" > "${PAYLOAD_BINARY}.bz2"
  # bunzip2 replaces screencapture.bz2 by screencapture. Because of -f an
  # uncompressed payload is passed through unchanged, but a truncated or
  # corrupted bzip2 payload makes bunzip2 fail.
  if ! bunzip2 -f "${PAYLOAD_BINARY}.bz2" 2> /dev/null; then
    error "Extracting the payload failed. See \"Advanced Usage\" in the README."
    exit 1
  fi
  chmod 755 "${PAYLOAD_BINARY}"
}

# Sets CHECK_FILE to the clean binary that is going to be installed:
# the one given by -p <file>, otherwise the payload, otherwise BINARY.
select_binary() {
  if [ -n "${PAYLOAD_FILE}" ]; then
    use_payload_file
  elif has_payload; then
    extract_payload
    CHECK_FILE="${PAYLOAD_BINARY}"
    status "Binary" "the payload embedded in the script"
  elif [ -f "${BINARY}" ]; then
    CHECK_FILE="${BINARY}"
    status "Binary" "${CHECK_FILE}"
  else
    error "No clean screencapture binary found."
    how_to_get_binary
    exit 1
  fi
}

# Sets CHECK_FILE to the binary given by -p <file>.
use_payload_file() {
  if [ ! -f "${PAYLOAD_FILE}" ]; then
    error "File not found:" \
          "${PAYLOAD_FILE}"
    exit 1
  fi
  CHECK_FILE="${PAYLOAD_FILE}"
  status "Binary" "${CHECK_FILE}"
}

# ---------------------------------------------------------------------------
# Validating a screencapture binary
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
# Fails if CHECK_FILE is not a clean binary.
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
  status "Archs" "${archs:-none}"
  if [[ " ${archs} " != *" x86_64 "* ]]; then
    error "This is not an executable for Intel Macs:" \
          "${CHECK_FILE}"
    return 1
  fi
  if [[ " ${archs} " != *" arm64e "* ]]; then
    error "This binary contains x86_64 only:" \
          "${CHECK_FILE}" \
          "It looks like the broken binary of an OCLP-patched Mac." \
          "A clean one is universal (x86_64 arm64e)."
    return 1
  fi
}

# codesign --verify fails if the binary has been modified or truncated.
# The requirement "anchor apple" additionally demands that Apple signed it.
# Fails if CHECK_FILE is not signed by Apple.
check_signature() {
  if ! codesign --verify -R="anchor apple" "${CHECK_FILE}" 2>/dev/null; then
    error "This binary does not carry a valid Apple code signature:" \
          "${CHECK_FILE}"
    return 1
  fi
}

# cmp -s compares both files byte by byte without any output,
# exit code 0 means that they are identical. Being identical is an error
# for --install only, unless --force (FORCE=1) installs it anyway.
# -ef is true if both paths refer to the same file. Sets IDENTICAL to 1
# if the binary is identical to the installed one.
check_not_installed() {
  IDENTICAL=0
  if [[ "${CHECK_FILE}" -ef "${INSTALLED}" ]] || ! cmp -s "${CHECK_FILE}" "${INSTALLED}"; then
    return
  fi
  IDENTICAL=1

  if [ "${MODE}" != "install" ]; then
    note "The binary is identical to the installed ${INSTALLED}," \
         "so no fix is necessary."
  elif [ ${FORCE} -eq 1 ]; then
    warning "The binary is identical to the installed ${INSTALLED}." \
            "Installing it anyway because of --force."
  else
    error "The binary is identical to the installed ${INSTALLED}." \
          "Either the fix has been applied already, or the binary has been" \
          "taken from this Mac. Use --force to install it anyway."
    exit 1
  fi
}

# Sets CHECKSUM to the SHA-256 checksum of CHECK_FILE, BINARY_VERSION to the
# macOS version of a known clean binary (see FAQs in the README), and
# VERSION_MATCHES to 1 if that version is the one of this Mac.
# shasum prints "<checksum>  <file>", %% * keeps the checksum only.
lookup_checksum() {
  CHECKSUM="$(shasum -a 256 "${CHECK_FILE}")"
  CHECKSUM="${CHECKSUM%% *}"
  BINARY_VERSION=""
  VERSION_MATCHES=0
  case "${CHECKSUM}" in
    e668501ed8406aebcc3572a9b349553a27d429d0acfe26a5b364c2290ea8013d)
      BINARY_VERSION="15.7.4 - 15.7.7"
      [[ "${OS_VERSION}" == 15.7.[4-7] ]] && VERSION_MATCHES=1
      ;;
    15f8ae56fbbe2e51c8ccfd04406e47fc619bd78ec364489585757b2b09471e1b)
      BINARY_VERSION="15.8"
      [[ "${OS_VERSION}" == 15.8 || "${OS_VERSION}" == 15.8.* ]] && VERSION_MATCHES=1
      ;;
  esac
}

# Prints the checksum and whether it belongs to the macOS version of this Mac.
# An unknown checksum is not an error, because newer macOS versions ship other binaries.
check_checksum() {
  lookup_checksum
  status "SHA-256" "${CHECKSUM}"
  status "macOS" "${OS_VERSION}"
  if [ -z "${BINARY_VERSION}" ]; then
    warning "Unknown SHA-256 checksum." \
            "Make sure the binary comes from macOS ${OS_VERSION}."
  elif [ ${VERSION_MATCHES} -eq 0 ]; then
    warning "The binary is from macOS ${BINARY_VERSION}, but this is macOS ${OS_VERSION}."
  else
    echo "The binary is the clean screencapture from macOS ${BINARY_VERSION}."
  fi
}

# csrutil status prints e.g. "System Integrity Protection status: enabled."
# OCLP usually reports "unknown (Custom Configuration)" which is fine,
# but with fully enabled SIP the system volume can't be mounted writable.
check_sip() {
  if [[ "$(csrutil status 2>/dev/null)" == *"status: enabled."* ]]; then
    warning "System Integrity Protection (SIP) is enabled." \
            "Patching will most likely fail."
  fi
}

# Validates CHECK_FILE as the clean binary and exits if it is not suitable.
validate_binary() {
  if ! check_architectures || ! check_signature; then
    how_to_get_binary
    exit 1
  fi
  check_not_installed
  check_checksum
  check_sip
}

# Prints the status of the payload embedded in the script.
# The checks run silently, their results are summarized in a few lines.
# Succeeds if the payload is suitable for this Mac.
payload_status() {
  local suitable=0
  local -a lines

  if ! has_payload; then
    status "Payload" "none"
    return 1
  fi

  extract_payload
  CHECK_FILE="${PAYLOAD_BINARY}"
  if ! check_architectures &> /dev/null; then
    status "Payload" "not a clean screencapture binary," \
                     "it does not contain both x86_64 and arm64e."
    return 1
  fi
  if ! check_signature &> /dev/null; then
    status "Payload" "not a clean screencapture binary," \
                     "it does not carry a valid Apple code signature."
    return 1
  fi

  lookup_checksum
  if [ -z "${BINARY_VERSION}" ]; then
    lines=( "clean screencapture from an unknown macOS version" )
    suitable=1
  elif [ ${VERSION_MATCHES} -eq 1 ]; then
    lines=( "clean screencapture from macOS ${BINARY_VERSION}" )
    suitable=1
  else
    lines=( "clean screencapture from macOS ${BINARY_VERSION}," \
            "but this Mac runs macOS ${OS_VERSION}" )
  fi
  if cmp -s "${CHECK_FILE}" "${INSTALLED}"; then
    lines+=( "It is installed already." )
  fi
  status "Payload" "${lines[@]}"

  if [ ${suitable} -eq 1 ]; then
    install_hint
    return 0
  fi
  return 1
}

# Checks whether the installed screencapture is broken, i.e. whether
# a fix is necessary, and exits with 0 if not, otherwise with 1.
check_installed() {
  CHECK_FILE="${INSTALLED}"
  status "Binary" "${CHECK_FILE}"

  if check_architectures && check_signature; then
    check_checksum
    echo "No fix necessary, ${INSTALLED} is a clean binary."
    exit 0
  fi

  echo "A fix is necessary, ${INSTALLED} is broken."
  check_sip
  if ! payload_status; then
    how_to_get_binary
  fi
  exit 1
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
    error "Could not determine the APFS container disk. Aborting."
    exit 1
  fi
  status "Container" "/dev/${containerDisk}"

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
    error "No APFS Snapshot found on /dev/${containerDisk}. Aborting."
    exit 1
  fi

  temp="${line#* disk}"
  snapshotDisk="disk${temp%% *}"          # e.g. disk1s4s1
  SYSTEM_DISK="${snapshotDisk%s[0-9]*}"   # strip trailing "s<n>" -> e.g. disk1s4

  status "Snapshot" "/dev/${snapshotDisk}"
  status "System" "/dev/${SYSTEM_DISK}"
}

# Mounts the SYSTEM_DISK writable to MOUNTPOINT.
mount_system_volume() {
  MOUNTPOINT="${HOME}/mount.$$"
  mkdir -p "${MOUNTPOINT}"

  if ! mount -o nobrowse -t apfs /dev/${SYSTEM_DISK} "${MOUNTPOINT}"; then
    error "Mounting /dev/${SYSTEM_DISK} failed. Reboot first and try again."
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

# Backs up the old file and copies the new one (CHECK_FILE).
replace_binary() {
  if ! mv "${MOUNTPOINT}/usr/sbin/screencapture" "${MOUNTPOINT}/usr/sbin/screencapture.old"; then
    error "Could not back up the original screencapture binary."
    abort_patch
  fi

  # -X skips extended attributes, so e.g. the quarantine flag of a binary
  # received by AirDrop or a browser download doesn't end up on the system volume.
  if ! cp -fX "${CHECK_FILE}" "${MOUNTPOINT}/usr/sbin/screencapture"; then
    error "Could not copy the new screencapture binary. Restoring the original."
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
    error "bless failed. Restoring the original screencapture binary."
    restore_original
    abort_patch
  fi
}

# Unmounts the system volume and removes the mount point.
unmount_system_volume() {
  if ! umount "${MOUNTPOINT}"; then
    warning "Unmounting failed:" \
            "${MOUNTPOINT}" \
            "Please unmount it manually before rebooting."
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

# Prints the usage of the option $1 that lacks its argument and exits.
# $2 is the name of the argument, $3 its description, $4 an example.
missing_argument() {
  echo "Usage: ${SCRIPT} $1 <$2>"
  echo "  <$2> is $3, e.g."
  echo "  ${SCRIPT} $1 $4"
  exit 1
}

# Sets MODE to the action $1, only one action can be given.
set_mode() {
  if [[ -n "${MODE}" && "${MODE}" != "$1" ]]; then
    error "--install, --check and --get can't be combined."
    exit 1
  fi
  MODE="$1"
}

main() {
  local getDir=""

  # The options can be combined, shift drops the option that has been processed.
  # An argument that starts with - is the next option, not the missing argument.
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        echo "screencapture-fix ${VERSION}"
        exit 0
        ;;
      -i|--install)
        set_mode install
        ;;
      -c|--check)
        set_mode check
        ;;
      -g|--get)
        if [[ -z "$2" || "$2" == -* ]]; then
          missing_argument "$1" "dir" \
            "a USB stick with a macOS installer or the installer app itself" \
            "\"/Volumes/Install macOS Sequoia\""
        fi
        set_mode get
        getDir="$2"
        shift
        ;;
      -p|--payload)
        if [[ -z "$2" || "$2" == -* ]]; then
          missing_argument "$1" "file" "a clean screencapture binary" \
            "~/Desktop/screencapture"
        fi
        PAYLOAD_FILE="$2"
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

  case "${MODE}" in
    "")
      # Without any action show the help and whether the payload is suitable
      usage
      echo
      payload_status
      exit 0
      ;;
    check)
      # --check finds out whether a fix is necessary,
      # --check -p <file> whether <file> is a clean binary
      if [ -z "${PAYLOAD_FILE}" ]; then
        check_installed
      fi
      use_payload_file
      validate_binary
      echo "Check passed."
      if [ ${IDENTICAL} -eq 0 ]; then
        install_hint "${PAYLOAD_FILE}"
      fi
      exit 0
      ;;
    get)
      if [ -n "${PAYLOAD_FILE}" ]; then
        error "--get can't be combined with --payload."
        exit 1
      fi
      get_from_installer "${getDir}"
      CHECK_FILE="${BINARY}"
      status "Binary" "${CHECK_FILE}"
      validate_binary
      echo "Check passed."
      # --install prefers the payload, so name the extracted binary if there is one
      if [ ${IDENTICAL} -eq 1 ]; then
        :
      elif has_payload; then
        install_hint "${BINARY}"
      else
        install_hint
      fi
      exit 0
      ;;
  esac

  # --install
  if [[ $UID != 0 ]]; then
    error "--install must be run as root, e.g." \
          "sudo ${SCRIPT} --install"
    echo "Tip: Run it with --check first to find out whether a fix is necessary."
    exit 1
  fi

  select_binary
  validate_binary

  find_system_volume
  mount_system_volume
  replace_binary
  bless_snapshot
  unmount_system_volume
  reboot_system
}

# The payload extracted to a temporary folder is removed when the script exits
trap cleanup_payload EXIT
trap 'cleanup_payload; exit 130' INT TERM

main "$@"

exit
# --payload_start--
