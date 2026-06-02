# screencapture-fix

## Why?

See my [blog](https://loefflmann.blogspot.com/2026/03/how-i-fixed-sequoias-screencapture-on-an-OCLP-patched-macbookpro81.html) why this script has been created.

## Prerequisites

- macOS Sequoia installed on a a MacBook Pro (model 8,1) using OCLP 2.4.1
- A clean `screencapture` binary from macOS Sequoia 15.7.4 or later
- this script

> [!TIP]
> When booted into a macOS installer or Recovery Mode, you can access the screencapture binary via the Terminal, often located at `/Volumes/Macintosh\ HD/usr/sbin/screencapture` if the main drive is mounted, or by copying it from a running system.

## How to install

Download the screencapture-fix.sh file from GitHub to a folder of your choice, and set execute permissions.

Shortcut:
```
% curl -Ls https://bit.ly/4ug5Jmt > screencapture-fix.sh
% chmod 700 ./screencapture-fix.sh
```

## Usage

> [!CAUTION]
> Use at your own risk.
> This script modifies system files located in `/usr/sbin/`. While this fix has been tested on MacBookPro8,1 running macOS Sequoia via OCLP, always ensure you have a current backup of your data before modifying system-level binaries. The author is not responsible for any system instability or data loss.

To fix a broken screencapture on an OCLP patched MacBookPro8,1 simply run 

```
% sudo ./screencapture-fix.sh
```

The script replaces `/usr/sbin/screencapture` with the binary located in the same folder as the script.
Reapplying OCLP root patches in the future would likely overwrite the fix.
Run the script as often as need.

## Advanced Usage

You can also append the screencapture binary to the script as its payload to make a single file.

```
% cat ./screencapture-fix.sh ./screencapture > ./screencapture-fix-with-payload.sh
```
If you run `screencatpure-fix-with-payload.sh` the script extracts its payload and saves screencapture if if is not found in the script's working directory.

> [!WARNING]
> You should not publish the binary with embedded screencapture binary because it would be a violation of Apple's license terms.


## FAQs

### Do I need a specific screencapture binary for my macOS?

The screencapture binary is the same from macOS 15.7.4 to 15.7.7.

