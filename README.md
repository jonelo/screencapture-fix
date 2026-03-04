# screencapture-fix


See my [blog](https://loefflmann.blogspot.com/2026/03/how-i-fixed-sequoias-screencapture-on-an-OCLP-patched-macbookpro81.html) why this script has been created.

To fix a broken screencapture on an OCLP patched MacBookPro8,1 disable SIP at the OCLP if not done yet (build and install OpenCore to the internal drive) and after that simply run 

```
% sudo ./screencapture-fix.sh
```

The script replaces `/usr/sbin/screencapture` with the binary located in the same folder as the script.
Reapplying OCLP root patches in the future would likely overwrite the fix.
Run the script as often as need.
