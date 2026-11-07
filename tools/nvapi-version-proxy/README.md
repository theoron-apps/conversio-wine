# NVAPI version proxy

A native x64 Windows DLL, built with MinGW (`make`). No proprietary libraries are distributed.
Conversio installs the imported GPTK nvapi64.dll/.so in Wine under the builtin alias
`conversio_nvapi64`, and places this native proxy in the bottle as nvapi64.dll.
Only GTA5_Enhanced.exe selects native,builtin for nvapi64. Other games keep builtin.

`HKCU\Software\Wine\AppDefaults\<exe>\NVAPI` DWORD `DriverVersion` is a minimum
in NVAPI integer units (58082 = 580.82). Zero/absent forwards everything unchanged.
The original functions run first; errors, branch strings, adapter names, all other
query IDs and newer driver versions are preserved. DLL lifetime is process-wide.

Interface IDs and ABI: https://github.com/NVIDIA/nvapi/blob/main/nvapi_interface.h
and https://docs.nvidia.com/nvapi/group__driverapi.html .
