# Release Notes

## 2.0.0 (2026-10-20)

### Breaking changes

- Running the script without any option no longer patches the system.
  It shows the help and the status of the payload embedded in the script instead.
  Apply the fix with `sudo ./screencapture-fix.sh --install`.
- The payload embedded in the script is extracted to a temporary folder, which is removed when the script exits.
  It is no longer saved as `screencapture` next to the script.
- The clean binary is taken from `-p <file>`, otherwise from the embedded payload, otherwise from the file `screencapture` next to the script.
  If both a payload and a `screencapture` file exist, the payload is preferred now.

### New features

- `-i`, `--install` replaces `/usr/sbin/screencapture` by the clean binary and reboots (requires root).
- `-c`, `--check` finds out whether the installed `/usr/sbin/screencapture` is broken, i.e. whether a fix is necessary at all.
- `-c -p <file>` checks whether `<file>` is a clean screencapture binary.
- `-g`, `--get <dir>` extracts a clean screencapture from a macOS Sequoia installer, e.g. from the USB stick created by OCLP,
  or from an `Install macOS Sequoia.app`. The installer is mounted read-only and remains unchanged (#2).
- `-x`, `--extract` extracts the payload embedded in the script to a file, `-p` sets the destination.
- `-p`, `--payload <file>` uses `<file>` as the clean binary and ignores an embedded payload.
- `-f`, `--force` installs the clean binary even if it is identical to the installed one.
- `-h`, `--help` shows a description of the script and all available options.
- `-v`, `--version` shows the version of the script.
- Options can be combined, e.g. `--install --force`. Unknown options and conflicting options are reported.

### Improvements

- The clean binary is validated before the system volume is touched:
  - its architectures: a clean binary is universal (`x86_64 arm64e`), while the broken one contains `x86_64` only,
  - its Apple code signature,
  - whether it is identical to the installed binary,
  - its SHA-256 checksum, compared with the known clean binaries of macOS 15.7.4 - 15.7.7 and 15.8,
    with a warning if it doesn't match the macOS version of the Mac,
  - and a warning is shown if System Integrity Protection (SIP) is enabled.
- If no clean binary is found, the script explains how to get one,
  and it points out files with similar names such as `screencapture copy` or `screencapture.zip`.
- Extended attributes such as the quarantine flag of a downloaded binary are no longer copied to the system volume.
- The script relies on tools that are part of macOS only, the Command Line Developer Tools are not required.
- All output fits into a terminal with the default width of 80 columns.
- The script has been restructured into functions.

### Fixes

- A truncated or corrupted payload is detected. Before, the script continued after a failed extraction.

### Documentation

- New step-by-step guide [How to get a clean screencapture binary](README.md#how-to-get-a-clean-screencapture-binary):
  copy it from another Mac, or extract it from a macOS Sequoia installer (#2).
- The misleading tip to take the binary from Recovery Mode has been removed,
  because the binary on the affected Mac itself is the broken one.
- The installation instructions add the missing `chmod +x` after the download.
- New sections for finding out whether a fix is necessary, for checking the clean binary and for applying the fix.
- New [Troubleshooting](README.md#troubleshooting) section that explains the error messages.
- The payload description in [Advanced Usage](README.md#advanced-usage) has been updated.
- Supported versions: macOS Sequoia 15.7.4 - 15.8 with OCLP 2.4.1 or OCLP 2.5.
  The checksum of the clean binary of macOS 15.8 has been added to the FAQs.

## 1.0.0 (2026-06-06)

- Added support for multiple boot volumes, the script patches the booted one (#1).
- Fixed the file permissions of the copy in `/usr/sbin`.
- Improved error handling.
- Tested up to macOS Sequoia 15.7.7.

## Before 1.0.0

- 2026-03-08: The clean binary can also be appended to the script as its payload.
- 2026-03-04: Initial version of the script and the README.
