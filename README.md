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
not even when booted into Recovery Mode. There are two other ways to get a clean one:
[copy it from another Mac](#copy-it-from-another-mac), or let the script
[extract it from a macOS Sequoia installer](#extract-it-from-a-macos-sequoia-installer), e.g. from the USB stick that OCLP has created.

### Copy it from another Mac

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
3. make sure it is a universal binary that contains both `x86_64` and `arm64e`
   ```
   % file ~/Desktop/screencapture
   /Users/you/Desktop/screencapture: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64e:Mach-O 64-bit executable arm64e]
   ...
   ```
4. compare its checksum with the ones listed in the [FAQs](#do-i-need-a-specific-screencapture-binary-for-my-macos)
   ```
   % shasum -a 256 ~/Desktop/screencapture
   ```
5. transfer the file to the Mac that you want to fix, e.g. by USB stick, AirDrop or a network share.
   Store it next to `screencapture-fix.sh` (see below), and make sure it is named exactly `screencapture`:
   don't rename it, and don't leave it zipped.

### Extract it from a macOS Sequoia installer

If you have installed Sequoia with OCLP, you probably still have the USB stick with the macOS installer that OCLP has created.
The installer contains the entire system, including a clean `screencapture`.
With the option `--get`, the script extracts the binary from the installer and saves it next to the script.

1. [install the script](#how-to-install)
2. plug in the USB stick, it shows up as `/Volumes/Install macOS Sequoia`
3. run
   ```
   % ./screencapture-fix.sh --get "/Volumes/Install macOS Sequoia"
   Installer     : /Volumes/Install macOS Sequoia/Install macOS Sequoia.app
   Mounting SharedSupport.dmg (read-only)
   Installer for : macOS 15.8 (24H23)
   Searching for usr/sbin/screencapture, this can take several minutes ...
   Searching payload.036
   Found usr/sbin/screencapture in payload.036
   Architectures : x86_64 arm64e
   ...
   Check passed. Run the script with sudo and without any option to apply the fix.
   ```

Instead of the USB stick you can also pass an `Install macOS Sequoia.app`, e.g. one that has been downloaded to `/Applications`.
The installer is mounted read-only, so it remains unchanged. Root is not required, and `--get` doesn't patch anything.
It just extracts the binary and checks it the same way as `--check` does.

Use an installer of the same macOS version as the Mac that you want to fix. The script warns you if the versions differ.

## How to install

Create a folder of your choice, and download the `screencapture-fix.sh` file from GitHub into it.

Shortcut:
```
% mkdir ~/screencapture-fix
% cd ~/screencapture-fix
% curl -Ls https://bit.ly/screencapture-fix > screencapture-fix.sh
% chmod +x screencapture-fix.sh
```

Then copy the clean `screencapture` binary into the same folder, or let the script [extract it from a macOS Sequoia installer](#extract-it-from-a-macos-sequoia-installer):
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

### Is my screencapture broken?

Pass a file or a folder to `--check` to find out whether a screencapture binary is broken,
e.g. after a fresh installation or after reapplying the OCLP root patches:

```
% ./screencapture-fix.sh --check /usr/sbin
```

This also works for the system on another volume, e.g. `./screencapture-fix.sh --check "/Volumes/Macintosh HD/usr/sbin"`.
Nothing is changed, and root is not required.

To see a description of the script and all available options (`-c`/`--check [path]`, `-g`/`--get <dir>`, `-f`/`--force`, `-h`/`--help`), run

```
% ./screencapture-fix.sh --help
```

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

### "... is identical to the installed /usr/sbin/screencapture."

The fix has already been applied. If you want to install the binary again anyway, run `sudo ./screencapture-fix.sh --force`.

### "Extracting the payload failed."

The payload appended to the script is truncated or corrupted. Create the single file again as described in [Advanced Usage](#advanced-usage).

### "Expected exactly one "Install macOS *.app" in ..."

`--get` expects either the folder that contains the installer (e.g. the root of the USB stick) or the installer app itself.
Check the name of the USB stick in the Finder or with `ls /Volumes`.

### "... SharedSupport.dmg not found."

The installer app is an install stub only, which downloads the actual installer when it runs.
Use the USB stick created by OCLP, or a full installer instead.

### "Mounting /dev/... failed."

Reboot and try again. Make sure that SIP is disabled, as configured by OCLP.
