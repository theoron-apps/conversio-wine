#!/usr/bin/env bash
# build.sh — builds CrossOver's open-source Wine for Conversio.
#
# The result is an x86_64 Wine (Apple silicon runs it through Rosetta 2) in the new WoW64 mode,
# so 32- and 64-bit Windows programs both work without any 32-bit macOS libraries. Libraries Wine
# loads at runtime (FreeType, GnuTLS, SDL2, MoltenVK) are bundled into wine/lib.
#
# Usage:
#   scripts/build.sh deps        install Homebrew build and runtime dependencies
#   scripts/build.sh fetch       download CrossOver sources, verify the checksum, extract Wine
#   scripts/build.sh apply       apply patches/*.patch in order
#   scripts/build.sh configure   configure Wine (x86_64 + i386 through WoW64)
#   scripts/build.sh build       make
#   scripts/build.sh install     install into build/stage/wine
#   scripts/build.sh addons      add Wine Mono (.NET) and Wine Gecko (HTML) to share/wine
#   scripts/build.sh bundle      copy runtime libraries into wine/lib and sign everything ad hoc
#   scripts/build.sh test        smoke-test the installed Wine
#   scripts/build.sh package     pack dist/conversio-wine-<version>-x86_64.tar.xz
#   scripts/build.sh all         everything above, in order
#
# Environment: CX_VER (default 26.3.0), REVISION (default 3), CX_SHA256 (checksum for a version
# that is not pinned below), BUILD_DIR (default ./build), JOBS (default: all cores).
#
# On Apple silicon the script re-runs itself under Rosetta and needs Intel Homebrew in /usr/local.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CX_VER="${CX_VER:-26.3.0}"
REVISION="${REVISION:-3}"
BUILD_DIR="${BUILD_DIR:-$REPO/build}"
DIST="${DIST:-$REPO/dist}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

SRC_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VER}.tar.gz"
SRC_TGZ="$BUILD_DIR/crossover-sources-${CX_VER}.tar.gz"
WINE_SRC="$BUILD_DIR/wine-src"
WINE_BUILD="$BUILD_DIR/wine-build"
STAGE="$BUILD_DIR/stage"
WINE_ROOT="$STAGE/wine"
PACKAGE="conversio-wine-cx${CX_VER}-${REVISION}-x86_64"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

# Wine for macOS is an Intel program: on Apple silicon, build everything under Rosetta.
if [ "$(uname -m)" = "arm64" ] && [ -z "${CONVERSIO_UNDER_ROSETTA:-}" ]; then
  if [ ! -x /usr/local/bin/brew ]; then
    echo "On Apple silicon this build needs Intel Homebrew in /usr/local. Install it with:"
    echo '  arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  export CONVERSIO_UNDER_ROSETTA=1
  exec arch -x86_64 /bin/bash "$0" "$@"
fi

BREW="${BREW:-}"
if [ -z "$BREW" ]; then
  if [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; else BREW="$(command -v brew)"; fi
fi
BREW_PREFIX="$("$BREW" --prefix)"

BUILD_DEPS="bison flex mingw-w64 pkgconf ccache"
RUNTIME_DEPS="freetype gnutls sdl2 sdl3 molten-vk"

log() { printf '\n==> %s\n' "$*"; }

# SHA-256 of CrossOver source tarballs we have built from.
pinned_sha256() {
  case "$1" in
    26.3.0) echo ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872 ;;
  esac
}

use_tools() {
  export PATH="$("$BREW" --prefix bison)/bin:$("$BREW" --prefix flex)/bin:$BREW_PREFIX/bin:$PATH"
}

cmd_deps() {
  log "Installing Homebrew dependencies"
  # shellcheck disable=SC2086
  "$BREW" install $BUILD_DEPS $RUNTIME_DEPS
}

cmd_fetch() {
  log "Fetching CrossOver $CX_VER sources"
  mkdir -p "$BUILD_DIR"
  if [ ! -f "$SRC_TGZ" ]; then
    curl -fL --retry 3 --retry-delay 5 -o "$SRC_TGZ.part" "$SRC_URL"
    mv "$SRC_TGZ.part" "$SRC_TGZ"
  fi

  local expected actual
  expected="${CX_SHA256:-$(pinned_sha256 "$CX_VER")}"
  actual="$(shasum -a 256 "$SRC_TGZ" | cut -d ' ' -f 1)"
  if [ -z "$expected" ]; then
    echo "No checksum is pinned for CrossOver $CX_VER. Its SHA-256 is:"
    echo "  $actual"
    echo "Review the source, then add it to pinned_sha256 in scripts/build.sh (or set CX_SHA256)."
    exit 1
  fi
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for $SRC_TGZ"
    echo "  expected $expected"
    echo "  actual   $actual"
    exit 1
  fi
  echo "Checksum OK"

  rm -rf "$WINE_SRC" "$BUILD_DIR/sources"
  tar -xzf "$SRC_TGZ" -C "$BUILD_DIR" sources/wine
  mv "$BUILD_DIR/sources/wine" "$WINE_SRC"
  rm -rf "$BUILD_DIR/sources"
  (
    cd "$WINE_SRC"
    git init -q
    git add -A
    git -c user.name=build -c user.email=build@localhost commit -qm "CrossOver $CX_VER Wine"
  )
  echo "Wine source: $(cat "$WINE_SRC/VERSION")"
}

cmd_apply() {
  log "Applying patches"
  shopt -s nullglob
  local patches=("$REPO"/patches/*.patch)
  shopt -u nullglob
  if [ ${#patches[@]} -eq 0 ]; then
    echo "No patches"
    return
  fi
  local patch
  for patch in "${patches[@]}"; do
    echo "applying $(basename "$patch")"
    (cd "$WINE_SRC" && git apply --whitespace=nowarn "$patch")
  done
}

cmd_configure() {
  log "Configuring Wine (x86_64 + i386 through WoW64)"
  use_tools
  rm -rf "$WINE_BUILD"
  mkdir -p "$WINE_BUILD"
  cd "$WINE_BUILD"

  # Use MoltenVK directly instead of a Vulkan loader, the way CrossOver does.
  export ac_cv_lib_soname_vulkan=""

  # Cache the Windows (PE) half of the build too; it's about half of all compiling.
  if command -v ccache >/dev/null 2>&1; then
    export x86_64_CC="ccache x86_64-w64-mingw32-gcc"
    export i386_CC="ccache i686-w64-mingw32-gcc"
  fi

  CC="${CC:-clang}" \
  CXX="${CXX:-clang++}" \
  CFLAGS="-O2 -g0 -Wno-deprecated-declarations -Wno-format -Wno-incompatible-function-pointer-types -Wno-int-conversion" \
  CROSSCFLAGS="-O2 -g0" \
  CPPFLAGS="-I$BREW_PREFIX/include" \
  LDFLAGS="-Wl,-headerpad_max_install_names -L$BREW_PREFIX/lib" \
  "$WINE_SRC/configure" \
    --prefix=/wine \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --with-coreaudio \
    --with-freetype \
    --with-gnutls \
    --with-sdl \
    --with-vulkan \
    --without-alsa \
    --without-capi \
    --without-cups \
    --without-dbus \
    --without-gphoto \
    --without-gstreamer \
    --without-krb5 \
    --without-oss \
    --without-pcap \
    --without-pulse \
    --without-sane \
    --without-udev \
    --without-usb \
    --without-v4l2 \
    --without-x

  log "Runtime libraries Wine will load"
  grep -E '^#define SONAME_' include/config.h || true
  local missing=""
  for name in LIBFREETYPE LIBGNUTLS LIBSDL2 LIBMOLTENVK; do
    grep -q "#define SONAME_$name " include/config.h || missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    echo "Configure did not find:$missing"
    exit 1
  fi
}

cmd_build() {
  log "Building Wine with $JOBS jobs"
  use_tools
  make -C "$WINE_BUILD" -j"$JOBS"
}

cmd_install() {
  log "Installing into $WINE_ROOT"
  use_tools
  rm -rf "$STAGE"
  make -C "$WINE_BUILD" install-lib DESTDIR="$STAGE"
  [ -x "$WINE_ROOT/bin/wine" ] || { echo "No wine binary in $WINE_ROOT/bin"; exit 1; }
}

# Wine Mono (.NET) and Wine Gecko (the HTML engine) in the exact versions this Wine asks for,
# so Wine finds them in share/wine instead of asking people to download them.
cmd_addons() {
  log "Adding Wine Mono and Wine Gecko"
  local addons="$WINE_SRC/dlls/appwiz.cpl/addons.c" mono gecko
  mono="$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' "$addons")"
  gecko="$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' "$addons")"
  [ -n "$mono" ] && [ -n "$gecko" ] || { echo "Could not read add-on versions from $addons"; exit 1; }
  echo "Wine Mono $mono, Wine Gecko $gecko"

  local cache="$BUILD_DIR/addons"
  mkdir -p "$cache" "$WINE_ROOT/share/wine/mono" "$WINE_ROOT/share/wine/gecko"
  fetch_addon "https://dl.winehq.org/wine/wine-mono/$mono/wine-mono-$mono-x86.msi" "$cache" "$WINE_ROOT/share/wine/mono"
  fetch_addon "https://dl.winehq.org/wine/wine-gecko/$gecko/wine-gecko-$gecko-x86.msi" "$cache" "$WINE_ROOT/share/wine/gecko"
  fetch_addon "https://dl.winehq.org/wine/wine-gecko/$gecko/wine-gecko-$gecko-x86_64.msi" "$cache" "$WINE_ROOT/share/wine/gecko"
}

fetch_addon() { # url cache-dir target-dir
  local name
  name="$(basename "$1")"
  [ -f "$2/$name" ] || curl -fL --retry 3 --retry-delay 5 -o "$2/$name" "$1"
  cp "$2/$name" "$3/$name"
  echo "added $name"
}

# Copies a Homebrew library and, recursively, the Homebrew libraries it links against into
# wine/lib, pointing their references at each other with @loader_path.
bundle_dylib() {
  local source="$1" name target dependency dependency_name
  name="$(basename "$source")"
  target="$WINE_ROOT/lib/$name"
  [ -f "$target" ] && return 0
  cp -L "$source" "$target"
  chmod u+w "$target"
  install_name_tool -id "@loader_path/$name" "$target"
  while read -r dependency; do
    case "$dependency" in
      "$BREW_PREFIX"/*|/usr/local/*|/opt/homebrew/*)
        dependency_name="$(basename "$dependency")"
        bundle_dylib "$dependency"
        install_name_tool -change "$dependency" "@loader_path/$dependency_name" "$target"
        ;;
    esac
  done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
}

cmd_bundle() {
  log "Bundling runtime libraries"
  mkdir -p "$WINE_ROOT/lib"
  local soname
  for soname in $(grep -E '^#define SONAME_' "$WINE_BUILD/include/config.h" | sed -E 's/.*"(.*)".*/\1/'); do
    if [ -f "$BREW_PREFIX/lib/$soname" ]; then
      echo "bundling $soname"
      bundle_dylib "$BREW_PREFIX/lib/$soname"
    else
      echo "from macOS: $soname"
    fi
  done

  # Homebrew's SDL2 is sdl2-compat: it loads SDL3 at runtime and, if SDL3 is missing, shows an
  # error dialog from a background thread, which crashes Wine's controller service.
  if [ -f "$WINE_ROOT/lib/libSDL2-2.0.0.dylib" ]; then
    local sdl3
    sdl3="$(ls "$BREW_PREFIX"/lib/libSDL3.0.dylib "$BREW_PREFIX"/lib/libSDL3.*.dylib 2>/dev/null | head -n 1)"
    [ -n "$sdl3" ] || { echo "SDL2 needs SDL3, but no libSDL3 in $BREW_PREFIX/lib"; exit 1; }
    echo "bundling $(basename "$sdl3") for SDL2"
    bundle_dylib "$sdl3"
  fi

  log "Signing ad hoc"
  local file
  while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q 'Mach-O'; then
      codesign --force --sign - "$file" 2>/dev/null || echo "could not sign $file"
    fi
  done < <(find "$WINE_ROOT" -type f -print0)
}

cmd_test() {
  log "Smoke test"
  # Conversio points dlopen at the bundled libraries the same way.
  export DYLD_FALLBACK_LIBRARY_PATH="$WINE_ROOT/lib:/usr/lib"
  "$WINE_ROOT/bin/wine" --version

  local dir
  for dir in x86_64-windows i386-windows x86_64-unix; do
    echo "lib/wine/$dir: $(ls "$WINE_ROOT/lib/wine/$dir" 2>/dev/null | wc -l | tr -d ' ') files"
  done
  for dir in x86_64-windows i386-windows; do
    ls -la "$WINE_ROOT/lib/wine/$dir/kernel32.dll" "$WINE_ROOT/lib/wine/$dir/ntdll.dll" 2>&1 || true
  done
  du -sh "$WINE_ROOT" "$WINE_ROOT"/lib/wine/* 2>/dev/null || true

  local prefix="$BUILD_DIR/test-prefix" trace="$BUILD_DIR/smoke-test.log"
  rm -rf "$prefix"
  # macOS has no `timeout`; perl's alarm does the same. The trace shows which DLL fails to load.
  if WINEPREFIX="$prefix" WINEDEBUG="err+all,+loaddll" \
     perl -e 'alarm shift; exec @ARGV' 300 "$WINE_ROOT/bin/wine" cmd /c echo conversio-ok > "$trace" 2>&1; then
    echo "Windows command line works:"
    grep -a "conversio-ok" "$trace" || true
  else
    echo "warning: wine cmd did not finish"
  fi
  if grep -a -q -E "NSInternalInconsistencyException|Terminating app" "$trace"; then
    echo "error: a native library crashed while Wine was starting:"
    grep -a -B2 -A12 "Terminating app" "$trace" | head -n 40
    exit 1
  fi
  echo "--- loaded and failed DLLs (first 60 lines) ---"
  grep -a -E "Loaded|err:|Failed|not found|c0000135" "$trace" | head -n 60 || true
  WINEPREFIX="$prefix" "$WINE_ROOT/bin/wineserver" -k 2>/dev/null || true
}

cmd_package() {
  log "Packaging $PACKAGE"
  mkdir -p "$DIST"
  cp "$WINE_SRC/COPYING.LIB" "$WINE_ROOT/COPYING.LIB"
  cp "$WINE_SRC/LICENSE" "$WINE_ROOT/LICENSE" 2>/dev/null || true
  {
    echo "Conversio Wine $CX_VER-$REVISION"
    echo "Wine: $(cat "$WINE_SRC/VERSION")"
    echo "Source: $SRC_URL"
    echo "Source SHA-256: $(shasum -a 256 "$SRC_TGZ" | cut -d ' ' -f 1)"
    echo "Patches: $(cd "$REPO/patches" 2>/dev/null && ls ./*.patch 2>/dev/null | tr '\n' ' ')"
    echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ) on macOS $(sw_vers -productVersion) $(uname -m)"
    echo "Builder: https://github.com/theoron-apps/conversio-wine"
    echo "License: LGPL-2.1-or-later (see COPYING.LIB). Sources are attached to the release."
  } > "$WINE_ROOT/CONVERSIO-BUILD.txt"
  XZ_OPT="-T0 -6" tar -C "$STAGE" -cJf "$DIST/$PACKAGE.tar.xz" wine
  (cd "$DIST" && shasum -a 256 "$PACKAGE.tar.xz" > "$PACKAGE.tar.xz.sha256")
  ls -lh "$DIST"
}

case "${1:-all}" in
  deps|fetch|apply|configure|build|install|addons|bundle|test|package) "cmd_$1" ;;
  all)
    cmd_deps; cmd_fetch; cmd_apply; cmd_configure; cmd_build
    cmd_install; cmd_addons; cmd_bundle; cmd_test; cmd_package
    ;;
  *)
    echo "usage: $0 [all|deps|fetch|apply|configure|build|install|bundle|test|package]"
    exit 1
    ;;
esac
