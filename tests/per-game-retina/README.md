# Per-game Retina probe

Compile probe.c to retina-on.exe and copy it as retina-off.exe. In a fresh prefix,
keep Mac Driver RetinaMode=n; set AppDefaults\retina-on.exe\Mac Driver RetinaMode=y
and AppDefaults\retina-off.exe\Mac Driver RetinaMode=n. Run on/off sequentially
and concurrently (`retina-on.exe 30000`), with an ordinary GUI process already
running, to exercise Wine's shared display cache. Compare screen/current size,
not just native_modes: native modes can exist without Retina. Repeat with the
bottle Retina=y and with the AppDefaults value deleted. DPI should not change.

## Revision 14 candidate

Patch 0013 keeps enumeration, monitor handles, registry writes and wineserver
monitor publication in the bottle's coordinate space. Only a process with a
different AppDefaults policy projects the win32u cache. Mode lists are freshly
enumerated with that policy; the original mode alone gets the Retina alias.
The projected current mode, primary monitor rectangle, work area and saved mode
can be compared in the probe output. On the reference built-in display at its
original mode, expect 1728×1117 off and 3456×2234 on, with identical system DPI
and device name. Re-query the off process after the on process starts, and
reverse the launch order. Repeat with the bottle default enabled.

This branch is an experimental CI artifact. Use a complete archive and a
scratch prefix. Do not add a Conversio capability marker or replace the
installed engine. This patch does not isolate all wineserver window and pointer
coordinates; validate pointer positions, clipping, Steam coexistence,
mode changes and return to the desktop before any rollout. The projection is
not applied to Wine virtual desktops or emulated mode sets.
