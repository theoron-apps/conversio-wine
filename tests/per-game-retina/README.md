# Per-game Retina probe

Run on the built-in Retina display at its original mode with a complete Wine
archive and a separate prefix. On the reference Mac the logical mode is
1728×1117. Pass `--logical WIDTH HEIGHT` for another built-in display.

```sh
python3 tests/per-game-retina/run-matrix.py /path/to/extracted/wine /path/to/new/scratch
```

The scratch directory must be new. The runner compiles the Windows probe with
MinGW, opens a normal Notepad window, and samples both launch orders, including
overlapping processes. The default probe stays running throughout each bottle
mode. The runner also deletes the override and checks inheritance on the same
executable. It shuts down its wineserver after each bottle configuration.

Compare screen metrics, the current and saved modes, the monitor rectangle,
screen GDI capabilities, and the source mode returned by QueryDisplayConfig.
The executable's Retina policy determines 3456×2234 or 1728×1117 in either
bottle configuration. The DPI and device name stay constant.

To check mouse coordinates, compile `mouse.c` with MinGW and name copies of it
`mouse-on.exe`, `mouse-off.exe`, and `mouse-default.exe`. Set
`HKCU\Software\Wine\AppDefaults\mouse-on.exe\Mac Driver\RetinaMode` to string
`y`, set the corresponding value for `mouse-off.exe` to `n`, and leave the
default executable without an override. Click at two known points in the
client area of each small window. The probe logs the client point and its
screen translation alongside GetMessagePos and GetCursorPos. The window
opens beyond half the display so Retina coordinates can exceed the bounds of
the shared bottle coordinates.

Patch 0013 publishes the bottle's coordinates and monitor identities to
wineserver. Each process projects its own display cache where supported.
Virtual desktops and emulated mode sets use the original cache. Fullscreen
mode changes, games and mixed-process window geometry require separate checks
before enabling the feature in Conversio.
