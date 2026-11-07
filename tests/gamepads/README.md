# Controller release checks

Build sdl-gamepads.c and windows-gamepads.c using the commands in each source.
Run SDL against the packaged SDL2 library, not Homebrew, and the Windows probe in
the game bottle. Poll buttons, both sticks and both triggers. A disconnected slot
returns 1167; a connected mapped pad must return 0 and changing packet/input data.
joyGetNumDevs reports capacity, not the connected device count.

For each available USB/Bluetooth device: compare Steam Input disabled/enabled in
GTA and a second game, reconnect while running, and ensure a single logical pad
with no double actions. Verify joy.cpl axes as well as DirectInput and raw-input
usages from the probe. Do not claim Xbox/Switch/MFi hardware tests without devices.

macOS Sony defaults now prefer mapped SDL, preserving per-device native HID opt-in:
HKLM\System\CurrentControlSet\Services\winebus\Devices\054c/0ce6
Hidraw=1 (DWORD). Delete the value to restore the engine default. Native Sony
reports/touchpad are a different mode from the mapped XInput-compatible report.
The existing EnableHidraw list also overrides the default. An SDL initialization
failure or Map Controllers=0 retains the existing raw IOHID fallback.
