# NVAPI forwarding regression probe

Compile `probe.c` with x86_64-w64-mingw32-gcc. Use a separate prefix and a full
Wine engine with the imported GPTK. Install the original nvapi64.dll and .so under
builtin alias conversio_nvapi64, and the native tools/nvapi-version-proxy DLL as
system32/nvapi64.dll. Set AppDefaults for probe.exe: nvapi64=native,builtin and
conversio_nvapi64=builtin; NVAPI DriverVersion DWORD=58082.

Run `wine probe.exe 58082`: checks both version APIs, initialization, pointer
identity for five other interfaces (including an unknown ID), and preservation
of the invalid display-struct error. Delete DriverVersion and run with the
original GPTK version (GPTK 4.0b3: 57602). Set 57000 and expect 57602: newer
original versions must never be downgraded. No D3DMetal binary patching.
