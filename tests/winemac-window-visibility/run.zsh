#!/bin/zsh
# Usage: run.zsh /absolute/path/to/wine /absolute/path/to/scratch
# No existing bottles or running Wine processes are stopped or changed.
set -eu
engine=${1:A}
scratch=${2:A}
source_dir=${0:A:h}
[[ -x "$engine/bin/wine" && -n "$scratch" && "$scratch" != / ]] || exit 2
mkdir -p "$scratch"
[[ ! -e "$scratch/prefix" ]] || { print -u2 'Use a fresh scratch directory.'; exit 2; }
x86_64-w64-mingw32-gcc -O2 -Wall "$source_dir/visibility-test.c" -o "$scratch/visibility-test.exe" -luser32
swiftc -module-cache-path "$scratch/ModuleCache" "$source_dir/window-list.swift" -o "$scratch/window-list"
export WINEPREFIX="$scratch/prefix" PATH="$engine/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$engine/lib:/usr/lib"
unset DYLD_INSERT_LIBRARIES
export WINEDLLOVERRIDES='winemenubuilder.exe=d;winedbg.exe=d;gameoverlayrenderer,gameoverlayrenderer64=d'
export WINEDEBUG='-all,+timestamp,+macdrv'
export WINEMSYNC=1 CX_FWD_COMPAT_GL_CTX=1
"$engine/bin/wine" wineboot --init > "$scratch/wineboot.log" 2>&1
failures=0
for scenario in hidden zero offscreen minimized visible hidden-after-show zero-after-show rapid; do
  for ownership in owned unowned; do
    name="$scenario-$ownership"
    "$engine/bin/wine" "$scratch/visibility-test.exe" "$scenario" "$ownership" topmost > "$scratch/$name.log" 2>&1 &
    test_pid=$!
    "$scratch/window-list" 30 "$test_pid" > "$scratch/$name.jsonl" &
    observer_pid=$!
    test_status=0
    wait "$test_pid" || test_status=$?
    kill -TERM "$observer_pid" 2>/dev/null || true
    wait "$observer_pid" 2>/dev/null || true
    if [[ "$test_status" == 0 ]] && python3 - "$scratch/$name.jsonl" <<'PY'
import json, sys
windows = [json.loads(line.partition(' ')[2]) for line in open(sys.argv[1])]
sys.exit(0 if any(w['title'] == 'Conversio visibility dialog' and w['onscreen'] for w in windows) else 1)
PY
    then
      print "PASS $name"
    else
      print "FAIL $name (exit $test_status)"
      failures=$((failures + 1))
    fi
  done
done
print "Failures: $failures; logs: $scratch"
(( failures == 0 ))
