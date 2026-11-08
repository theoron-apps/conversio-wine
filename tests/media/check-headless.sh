#!/usr/bin/env bash
set -euo pipefail
root="$1" probe="$2" fixture="$3"
export WINEPREFIX="$PWD/build/headless-prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$root/lib:/usr/lib"
export CONVERSIO_RUNTIME_LIBRARIES="$DYLD_FALLBACK_LIBRARY_PATH"
export GST_PLUGIN_SYSTEM_PATH_1_0="$root/lib/gstreamer-1.0"
export GST_PLUGIN_PATH_1_0='' GST_PLUGIN_PATH='' GST_PLUGIN_SYSTEM_PATH=''
export GST_PLUGIN_SCANNER_1_0="$root/libexec/gst-plugin-scanner"
export GST_REGISTRY_1_0="$PWD/build/headless-gst-registry.bin"
export WINEDLLOVERRIDES='winemac.drv=d;winemenubuilder.exe=d;winedbg.exe=d'
mkdir -p "$WINEPREFIX"
cat > "$WINEPREFIX/user.reg" <<'REG'
WINE REGISTRY Version 2

[Software\\Wine\\DllOverrides] 0
"winemac.drv"=""

[Software\\Wine\\Drivers] 0
"Graphics"="null"
REG
WINEDEBUG='-all,+timestamp,+loaddll,+explorer,+wineboot,+win32u' \
  python3 scripts/run-with-timeout.py 180 "$root/bin/wine" cmd /c echo conversio-headless-ok \
  > build/headless-cmd.log 2>&1 &
test_pid=$!
sleep 15
# CI-only snapshots: no user processes or environment values are collected.
for pid in $(ps -axo pid,comm | awk '$2 ~ /[\\]windows[\\]system32[\\](explorer|rundll32|wineboot).exe$/ {print $1}'); do
  sample "$pid" 1 1 -file "build/headless-stack-$pid.log" || true
done
wait "$test_pid" || { tail -n 100 build/headless-cmd.log; exit 1; }
cat build/headless-cmd.log
fixture="Z:$(printf '%s' "$fixture" | sed 's|/|\\|g')"
WINEDEBUG='-all,+gstreamer' python3 scripts/run-with-timeout.py 90 "$root/bin/wine" "$probe" "$fixture" \
  > build/headless-mf.log 2>&1 || { cat build/headless-mf.log; exit 1; }
cat build/headless-mf.log
"$root/bin/wineserver" -k
