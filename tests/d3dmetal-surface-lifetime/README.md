# D3DMetal surface lifetime regression

On Apple silicon with Rosetta, MinGW and a complete extracted Wine build with
D3DMetal installed (imported locally from Apple's GPTK, never redistributed):

```sh
zsh tests/d3dmetal-surface-lifetime/run.zsh /absolute/path/to/wine /private/tmp/surface-r6-fresh
```

The scratch prefix must not exist. The test has two Windows threads with their
own windows, devices and immediate contexts. One presents and pumps events while
the other creates and destroys 20 swapchain windows. It returns 0 only after both
threads finish; a 60-second in-process watchdog returns 124 on a possible hang.
A timeout alone is not proof: sample the hung process to identify its locks.
The runner rejects native-library crashes as invalid test conditions.

Revision 5 hung after five destructions on the owner's Mac. `sample` showed one
thread in `macdrv_DestroyWindow → CFRelease → client_surface_release`, waiting for
win32u's `surfaces_lock`, while the other was updating a client surface and waiting
for `win_data_mutex`. Revision 6 moves the array release outside `win_data_mutex`.

The test uses only its own prefix. No input is injected and no Steam process is
started or stopped. Wine runs directly, without `nohup`, `perl` or injected native
libraries. Test a whole build; do not transplant a driver from another build.
