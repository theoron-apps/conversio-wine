# Retina display checks

Run `python3 tests/display/check-gdi.py build/wine-src/dlls/winemac.drv/gdi.c`
after applying patches. It compiles the actual caps method against physical
display dimensions returned by win32u, checking Retina on/off, millimetres,
DPI and a virtual desktop with another monitor. The old Retina multiplier fails.

Compile `gdi-dimensions.c` with MinGW and `-lgdi32`, then run in fresh test
prefixes with bottle-wide RetinaMode enabled and disabled. At 96 DPI, compare
primary screen dimensions with HORZRES/VERTRES; they must not double again.
For NFB also check the complete 16:9 menu, resolution selector and minimize/restore.
On a 3456x2234 panel the game's 3456x1944 image has expected letterbox bars.

This fixes bottle-wide Retina caps. It does not declare per-process display
coordinate isolation; do not add the perProcessRetina capability marker yet.
