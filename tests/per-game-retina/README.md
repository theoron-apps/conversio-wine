# Per-game Retina probe

Compile probe.c to retina-on.exe and copy it as retina-off.exe. In a fresh prefix,
keep Mac Driver RetinaMode=n; set AppDefaults\retina-on.exe\Mac Driver RetinaMode=y
and AppDefaults\retina-off.exe\Mac Driver RetinaMode=n. Run on/off sequentially
and concurrently (`retina-on.exe 30000`), with an ordinary GUI process already
running, to exercise Wine's shared display cache. Compare screen/current size,
not just native_modes: native modes can exist without Retina. Repeat with the
bottle Retina=y and with the AppDefaults value deleted. DPI should not change.
