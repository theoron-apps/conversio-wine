# macOS cursor regression

Apply all patches to the CrossOver 26.3 source, then run on macOS:

    python3 tests/winemac-cursor/check.py /path/to/wine-src

The native x86_64 AppKit check compiles the production updateCursor method and
covers visible/hidden transitions, AppKit cursor reset, exit/re-entry, repeated
show/hide, and a changed visible cursor. It does not move the mouse or test Dock.

Manual release gate in GTA V Legacy and Enhanced (Steam -> Rockstar, -nobattleye):
move the camera, approach every Dock edge and configured hot corner, click rapidly,
open/close the pause menu, Cmd-Tab out/back, and exit the game. The pointer must
stay invisible during camera control, visible in other apps and Windows menus
that request it, and Dock/hot corners must work normally after leaving the game.
The app-local HideDock/HideMenuBar presentation options apply only while a
fullscreen Wine window is frontmost and Windows requests a hidden cursor.

The transparent cursor design follows Elvin Hayatov's Wine MR 11880 / MR 11799
v4 1/4. No GCMouse changes are included. NSCursor hide/unhide counters are unused.
