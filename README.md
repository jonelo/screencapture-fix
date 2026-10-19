# screencapture-fix

## Why?

This script helps you fix a broken screencapture on an OCLP-patched MacBookPro8,1 (and probably some other systems around 2011 as well).
See my [blog](https://loefflmann.blogspot.com/2026/03/how-i-fixed-sequoias-screencapture-on-an-OCLP-patched-macbookpro81.html) for why this script was created.

## Prerequisites

- macOS Sequoia (15.7.4 - 15.8) installed on a MacBook Pro (Model ID MacBookPro8,1) using OCLP 2.4.1 or OCLP 2.5
- System Integrity Protection (SIP) disabled, as configured by OCLP
- a clean `screencapture` binary from macOS Sequoia 15.7.4 or later, see [How to get a clean screencapture binary](#how-to-get-a-clean-screencapture-binary)
- this script

## How to get a clean screencapture binary

The `screencapture` binary on the affected Mac itself is the broken one, so you can't take it from there,
not even when booted into Recovery Mode. You need a second Mac instead.

A clean `screencapture` is a universal binary (`x86_64 arm64e`), while the broken one contains `x86_64` only.
Because of that, *any* Mac running macOS Sequoia 15.7.4 or later will do, no matter if it has an Intel or an Apple Silicon CPU,
as long as it is not affected by the problem. Ideally it runs the same macOS version as the Mac that you want to fix.

On the second Mac, open the Terminal and

1. check the macOS version
   ```
   % sw_vers -productVersion
   15.7.4
   ```
2. copy the binary to your Desktop
   ```
   % cp /usr/sbin/screencapture ~/Desktop/screencapture
   ```
3. make sure it is a universal binary
   ```
   % lipo -archs ~/Desktop/screencapture
   x86_64 arm64e
   ```
4. compare its checksum with the ones listed in the [FAQs](#do-i-need-a-specific-screencapture-binary-for-my-macos)
   ```
   % shasum -a 256 ~/Desktop/screencapture
   ```
5. transfer the file to the Mac that you want to fix, e.g. by USB stick, AirDrop or a network share.
   Store it next to `screencapture-fix.sh` (see below), and make sure it is named exactly `screencapture`:
   don't rename it, and don't leave it zipped.

## How to install

Create a folder of your choice, and download the `screencapture-fix.sh` file from GitHub into it.

Shortcut:
```
% mkdir ~/screencapture-fix
% cd ~/screencapture-fix
% curl -Ls https://bit.ly/screencapture-fix > screencapture-fix.sh
% chmod +x screencapture-fix.sh
```

Then copy the clean `screencapture` binary into the same folder:
```
% ls
screencapture		screencapture-fix.sh
```

## Usage

> [!CAUTION]
> Use at your own risk.
> This script modifies system files located in `/usr/sbin/`. While this fix has been tested on MacBookPro8,1 running macOS Sequoia via OCLP, always ensure you have a current backup of your data before modifying system-level binaries. The author is not responsible for any system instability or data loss.

First, let the script check your `screencapture` binary. This doesn't change anything on your system, and it doesn't require root:

```
% ./screencapture-fix.sh --check
```

If the check has passed, fix the broken screencapture on an OCLP patched MacBookPro8,1 by running

```
% sudo ./screencapture-fix.sh
```

The script replaces `/usr/sbin/screencapture` with the binary located in the same folder as the script.
It refuses binaries which are not suitable (e.g. a broken `x86_64`-only binary) before it touches the system volume.
Reapplying OCLP root patches in the future will likely overwrite the fix.
Run the script as often as needed.

## Advanced Usage

You can also append the screencapture binary to the script as its payload to make a single file.
Compressing the payload with bzip2 makes the file considerably smaller.

```
% { cat ./screencapture-fix.sh; bzip2 -c ./screencapture; } > ./screencapture-fix-with-payload.sh
% chmod +x ./screencapture-fix-with-payload.sh
```
An uncompressed payload (`cat ./screencapture-fix.sh ./screencapture > ./screencapture-fix-with-payload.sh`) works as well.
If you run `screencapture-fix-with-payload.sh`, the script extracts its payload and saves `screencapture` if it is not found in the script's working directory.

> [!WARNING]
> You should not publish the script with an embedded `screencapture` binary because that would violate Apple's license terms.


## FAQs

### Do I need a specific screencapture binary for my macOS?

The screencapture binary is the same from macOS 15.7.4 to 15.7.7.
```
e668501ed8406aebcc3572a9b349553a27d429d0acfe26a5b364c2290ea8013d  /usr/sbin/screencapture
```

The screencapture binary from macOS 15.8 is different.
```
15f8ae56fbbe2e51c8ccfd04406e47fc619bd78ec364489585757b2b09471e1b  /usr/sbin/screencapture
```

The script warns you if the checksum of your binary doesn't match your macOS version.

### Does the script support multiple boot volumes?

Yes, just boot from the volume that you want to patch. The script identifies the booted one.

## Troubleshooting

### "zsh: permission denied: ./screencapture-fix.sh"

The script is not executable, because downloads don't keep the executable flag. Run `chmod +x screencapture-fix.sh`.

### "screencapture binary not found" and "The screencapture binary is also not appended to the script."

There is no file called `screencapture` in the folder of the script.
Follow the steps in [How to get a clean screencapture binary](#how-to-get-a-clean-screencapture-binary).
If the script lists a file like `screencapture copy` or `screencapture.zip`, unzip or rename it to `screencapture`.

### "... contains x86_64 only. This looks like the broken binary ..."

The binary has been copied from an affected Mac, probably from the one that you want to fix.
Take it from another Mac, see [How to get a clean screencapture binary](#how-to-get-a-clean-screencapture-binary).

### "Extracting the payload failed."

The payload appended to the script is truncated or corrupted. Create the single file again as described in [Advanced Usage](#advanced-usage).

### "Mounting /dev/... failed."

Reboot and try again. Make sure that SIP is disabled, as configured by OCLP.
