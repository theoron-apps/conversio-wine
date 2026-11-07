#!/bin/bash
# Verify the production dylib/plugin relocation with both @rpath and absolute deps.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d /private/tmp/conversio-gst-relocation.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
BUILD_DIR="$scratch/build"; WINE_ROOT="$scratch/wine"; BREW_PREFIX="$scratch/brew"
source "$REPO/scripts/gstreamer.sh"
mkdir -p "$GST_PREFIX/lib" "$BREW_PREFIX/lib" "$WINE_ROOT/lib/gstreamer-1.0"
python3 - "$REPO/scripts/build.sh" "$scratch/functions.sh" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(s[s.index('bundle_dylib() {'):s.index('cmd_bundle() {')])
PY
source "$scratch/functions.sh"
echo 'int leaf(void) { return 42; }' > "$scratch/leaf.c"
echo 'extern int leaf(void); int core(void) { return leaf(); }' > "$scratch/core.c"
echo 'extern int core(void); int answer(void) { return core(); }' > "$scratch/plugin.c"
cat > "$scratch/main.c" <<'C'
#include <dlfcn.h>
#include <stdio.h>
int main(int n, char**v) { void *p=dlopen(v[1],RTLD_NOW); if(!p){puts(dlerror());return 1;} int(*f)(void)=dlsym(p,"answer"); return !f||f()!=42; }
C
clang -dynamiclib -Wl,-headerpad_max_install_names "$scratch/leaf.c" -Wl,-install_name,"$BREW_PREFIX/lib/libleaf.dylib" -o "$BREW_PREFIX/lib/libleaf.dylib"
clang -dynamiclib -Wl,-headerpad_max_install_names "$scratch/core.c" -L"$BREW_PREFIX/lib" -lleaf -Wl,-install_name,@rpath/libcore.dylib -o "$GST_PREFIX/lib/libcore.dylib"
clang -dynamiclib -Wl,-headerpad_max_install_names "$scratch/plugin.c" -L"$GST_PREFIX/lib" -lcore -Wl,-install_name,@rpath/libplugin.dylib -o "$scratch/plugin.dylib"
clang "$scratch/main.c" -o "$scratch/check"
cp "$scratch/plugin.dylib" "$WINE_ROOT/lib/gstreamer-1.0/plugin.dylib"
install_name_tool -id @loader_path/plugin.dylib "$WINE_ROOT/lib/gstreamer-1.0/plugin.dylib"
relocate_gst_file "$WINE_ROOT/lib/gstreamer-1.0/plugin.dylib"
# Remove every original dependency from its old path, without deleting user data.
mv "$GST_PREFIX" "$scratch/hidden-gst"; mv "$BREW_PREFIX" "$scratch/hidden-brew"
for file in "$WINE_ROOT/lib/"*.dylib "$WINE_ROOT/lib/gstreamer-1.0/plugin.dylib"; do codesign --force --sign - "$file" 2>/dev/null; done
unset DYLD_FALLBACK_LIBRARY_PATH DYLD_LIBRARY_PATH DYLD_INSERT_LIBRARIES
"$scratch/check" "$WINE_ROOT/lib/gstreamer-1.0/plugin.dylib"
echo 'PASS: nested plugin loads with @rpath/absolute originals removed'
