# winemac window visibility regression

The `rapid` case reproduces a stale native z-order sibling without Steam or a
launcher: create a topmost Win32 window, call `ShowWindow(SW_MINIMIZE)`, immediately
call `ShowWindow(SW_RESTORE)`, then show a non-topmost, unowned MessageBox. Windows
has already cleared `WS_MINIMIZE` while Cocoa still reports the sibling as
miniaturized and invisible. Revision 4 passes that sibling to `orderBelow:` with
no `next` window; `getSiblingWindowsForWindow:nil` throws, so the dialog is never
ordered in. Revision 5 uses its existing order-front path instead.

`visibility-test.c` closes dialogs automatically after 1.8 seconds, with an
8-second watchdog for the old driver's blocked main-thread request queue.
`window-list.swift` checks WindowServer's `kCGWindowIsOnscreen` for the exact Wine
process. Hidden/zero-sized/offscreen/minimized/visible owner controls are included,
with and without a MessageBox owner. They must all show their dialog. Moving an
application's deliberately offscreen windows onto the display is outside this fix.

On macOS with Xcode command-line tools, Python 3, MinGW and Rosetta installed:

```sh
zsh tests/winemac-window-visibility/run.zsh \
  /absolute/path/to/extracted/wine /private/tmp/visibility-r5-fresh
```

The scratch path must be fresh. The suite creates only its own prefix, unsets any
injected libraries, launches Wine directly (no SIP-protected process wrapper),
checks 16 dialogs and exits nonzero on any failure. It never kills a wineserver,
changes the installed engine, or accesses another prefix. Use the complete
extracted build; do not mix `.so` files from different Wine builds. D3DMetal is not
needed. UI animation settings can affect reproducing the race on the old build;
the fix must pass whether the minimize animation is enabled or disabled.

For diagnosis only, `observe-ordering.m` logs native visibility and catches the
old driver's exception so the MessageBox timer can close it. It never hides or
reorders a window. Build it with `clang -arch x86_64 -dynamiclib -O2
-Wno-deprecated-declarations -framework Cocoa observe-ordering.m -o observer.dylib`
and set `DYLD_INSERT_LIBRARIES` to its absolute path before a direct Wine launch.
The normal suite does **not** load this observer.
