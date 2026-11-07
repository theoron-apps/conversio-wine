#!/bin/zsh
# Complete engine + D3DMetal, fresh test prefix; never touches the Steam bottle.
set -eu
race_engine=${1:A}
race_scratch=${2:A}
race_source=${0:A:h}
[[ -x "$race_engine/bin/wine" && -f "$race_engine/lib/external/libd3dshared.dylib" ]] || {
  print -u2 'Use a complete Wine engine with D3DMetal installed.'
  exit 2
}
[[ ! -e "$race_scratch/prefix" ]] || { print -u2 'Use a fresh scratch directory.'; exit 2; }
mkdir -p "$race_scratch"
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Werror "$race_source/surface-race.c" \
  -o "$race_scratch/surface-race.exe" -ld3d11 -ldxgi -luser32
export WINEPREFIX="$race_scratch/prefix" PATH="$race_engine/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$race_engine/lib:/usr/lib"
export CX_APPLEGPTK_LIBD3DSHARED_PATH="$race_engine/lib/external/libd3dshared.dylib"
export WINEDLLOVERRIDES='winemenubuilder.exe=d;winedbg.exe=d;gameoverlayrenderer,gameoverlayrenderer64=d;d3d11,dxgi=b'
export WINEMSYNC=1 CX_FWD_COMPAT_GL_CTX=1 WINEDEBUG='-all,err+all'
unset DYLD_INSERT_LIBRARIES MTL_HUD_ENABLED MTL_HUD_LOG_ENABLED
trap '"$race_engine/bin/wineserver" -k 2>/dev/null || true' EXIT
"$race_engine/bin/wine" wineboot --init > "$race_scratch/wineboot.log" 2>&1
race_status=0
"$race_engine/bin/wine" "$race_scratch/surface-race.exe" > "$race_scratch/race.log" 2>&1 || race_status=$?
cat "$race_scratch/race.log"
if grep -E -q 'Terminating app|NSInternalInconsistencyException' "$race_scratch/"*.log; then
  print -u2 'A native library crashed; inspect the logs before using this result.'
  exit 2
fi
exit $race_status
