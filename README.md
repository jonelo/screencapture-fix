# screencapture-fix


See my [blog](https://loefflmann.blogspot.com/2026/03/how-i-fixed-sequoias-screencapture-on-an-OCLP-patched-macbookpro81.html) why this script has been created.

> [!CAUTION]
> Use at your own risk.
> This script modifies system files located in /usr/sbin. While this fix has been tested on MacBookPro8,1 running macOS Sequoia via OCLP, always ensure you have a current backup of your data before modifying system-level binaries. The author is not responsible for any system instability or data loss.

To fix a broken screencapture on an OCLP patched MacBookPro8,1 disable SIP at the OCLP if not done yet (build and install OpenCore to the internal drive) and after that simply run 

```
% sudo ./screencapture-fix.sh
```

The script replaces `/usr/sbin/screencapture` with the binary located in the same folder as the script.
Reapplying OCLP root patches in the future would likely overwrite the fix.
Run the script as often as need.
