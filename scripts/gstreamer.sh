# Sourced by build.sh. Build a small LGPL GStreamer instead of redistributing
# Homebrew's all-plugins build (which links GPL FFmpeg/x264/x265).
GST_VERSION=1.26.8
GST_SHA256=fa4014bfcc64ba6ec04459b7e0812c91e9680d0dc2e972bc2123c9d2e2106930
GST_ARCHIVE="$BUILD_DIR/gstreamer-$GST_VERSION.tar.gz"
GST_SOURCE="$BUILD_DIR/gstreamer-$GST_VERSION"
GST_PREFIX="$BUILD_DIR/gst-stage"
GST_BUILD="$BUILD_DIR/gst-build"

cmd_gstreamer() {
  use_tools
  log "Building LGPL GStreamer $GST_VERSION (Apple H.264/HEVC/AAC decoders)"
  mkdir -p "$BUILD_DIR"
  if [ ! -f "$GST_ARCHIVE" ]; then
    curl -fL --retry 3 -o "$GST_ARCHIVE.part" "https://github.com/GStreamer/gstreamer/archive/refs/tags/$GST_VERSION.tar.gz"
    mv "$GST_ARCHIVE.part" "$GST_ARCHIVE"
  fi
  [ "$(shasum -a 256 "$GST_ARCHIVE" | awk '{print $1}')" = "$GST_SHA256" ] || { echo "GStreamer checksum mismatch"; exit 1; }
  [ -d "$GST_SOURCE" ] || tar -xzf "$GST_ARCHIVE" -C "$BUILD_DIR"
  local setup_command=(meson setup)
  [ ! -f "$GST_BUILD/build.ninja" ] || setup_command+=(--reconfigure)
  CC="ccache clang" CXX="ccache clang++" OBJC="ccache clang" OBJCXX="ccache clang++" \
  CFLAGS='-O2 -g0' CXXFLAGS='-O2 -g0' LDFLAGS='-Wl,-headerpad_max_install_names' \
  "${setup_command[@]}" "$GST_BUILD" "$GST_SOURCE" \
    --prefix="$GST_PREFIX" --libdir=lib --buildtype=release \
    --auto-features=disabled --wrap-mode=nofallback \
    -Ddefault_library=shared -Dbuild-tools-source=system -Dorc-source=system \
    -Dgpl=disabled -Dorc=disabled -Dtests=disabled -Dexamples=disabled \
    -Dintrospection=disabled -Dnls=disabled -Dbase=enabled -Dgood=enabled -Dbad=enabled \
    -Dugly=disabled -Dlibav=disabled -Dpython=disabled -Ddevtools=disabled \
    -Dgstreamer:tools=enabled -Dgstreamer:ptp-helper=disabled \
    -Dgst-plugins-base:app=enabled -Dgst-plugins-base:audioconvert=enabled \
    -Dgst-plugins-base:audioresample=enabled -Dgst-plugins-base:playback=enabled \
    -Dgst-plugins-base:typefind=enabled -Dgst-plugins-base:videoconvertscale=enabled \
    -Dgst-plugins-base:volume=enabled -Dgst-plugins-base:rawparse=enabled \
    -Dgst-plugins-base:gl=enabled -Dgst-plugins-base:gl_api=opengl \
    -Dgst-plugins-base:gl_platform=cgl -Dgst-plugins-base:gl_winsys=cocoa \
    -Dgst-plugins-good:isomp4=enabled -Dgst-plugins-good:audioparsers=enabled \
    -Dgst-plugins-good:osxaudio=enabled -Dgst-plugins-good:avi=enabled \
    -Dgst-plugins-good:deinterlace=enabled -Dgst-plugins-good:videofilter=enabled \
    -Dgst-plugins-good:wavparse=enabled -Dgst-plugins-good:matroska=enabled \
    -Dgst-plugins-bad:videoparsers=enabled -Dgst-plugins-bad:gl=enabled \
    -Dgst-plugins-bad:applemedia=enabled
  meson compile -C "$GST_BUILD" -j "$JOBS"
  meson install -C "$GST_BUILD"
}

# All copied plugins/tools/libraries link only to siblings in the engine or macOS.
relocate_gst_file() {
  local target="$1" dependency name relative
  relative="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],os.path.dirname(sys.argv[2])))' "$WINE_ROOT/lib" "$target")"
  while read -r dependency; do
    case "$dependency" in
      @rpath/*)
        name="$(basename "$dependency")"
        # Wine's Unix modules keep their existing sibling @rpath/ntdll.so links
        # (otool also lists each module's own @rpath ID).
        [ ! -f "$(dirname "$target")/$name" ] || continue
        if [ -f "$GST_PREFIX/lib/$name" ]; then
          bundle_dylib "$GST_PREFIX/lib/$name"
        elif [ -f "$BREW_PREFIX/lib/$name" ]; then
          bundle_dylib "$BREW_PREFIX/lib/$name"
        else
          echo "Unresolved dependency $dependency in $target"; exit 1
        fi
        install_name_tool -change "$dependency" "@loader_path/$relative/$name" "$target"
        ;;
      "$GST_PREFIX"/*|"$BREW_PREFIX"/*|/usr/local/*|/opt/homebrew/*)
        name="$(basename "$dependency")"
        # A dylib's own LC_ID_DYLIB is also listed by otool.
        [ "$dependency" = "$target" ] && continue
        bundle_dylib "$dependency"
        install_name_tool -change "$dependency" "@loader_path/$relative/$name" "$target"
        ;;
    esac
  done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
}

bundle_gstreamer() {
  log "Bundling GStreamer libraries, plugins, scanner and tools"
  local file target
  mkdir -p "$WINE_ROOT/lib/gstreamer-1.0" "$WINE_ROOT/libexec" "$WINE_ROOT/share/licenses/gstreamer"
  while IFS= read -r -d '' file; do bundle_dylib "$file"; done < <(find "$GST_PREFIX/lib" -maxdepth 1 -name '*.dylib' -type f -print0)
  for file in "$GST_PREFIX"/lib/gstreamer-1.0/*.dylib; do
    target="$WINE_ROOT/lib/gstreamer-1.0/$(basename "$file")"
    cp -L "$file" "$target"; chmod u+w "$target"
    install_name_tool -id "@loader_path/$(basename "$file")" "$target"
    relocate_gst_file "$target"
  done
  for file in "$GST_PREFIX/bin/gst-inspect-1.0" "$GST_PREFIX/bin/gst-launch-1.0" "$GST_PREFIX/libexec/gstreamer-1.0/gst-plugin-scanner"; do
    [ -f "$file" ] || { echo "Missing GStreamer tool: $file"; exit 1; }
    case "$file" in *gst-plugin-scanner) target="$WINE_ROOT/libexec/gst-plugin-scanner";; *) target="$WINE_ROOT/bin/$(basename "$file")";; esac
    cp -L "$file" "$target"; chmod u+w "$target"; relocate_gst_file "$target"
  done
  while IFS= read -r -d '' file; do relocate_gst_file "$file"; done < <(find "$WINE_ROOT/lib/wine" -name '*.so' -type f -print0)
  for file in gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad; do
    cp "$GST_SOURCE/subprojects/$file/COPYING" "$WINE_ROOT/share/licenses/gstreamer/$file-COPYING"
  done
  cp "$REPO/scripts/gstreamer.sh" "$WINE_ROOT/share/licenses/gstreamer/build-recipe.sh"
  # Record exact shared dependency versions, source URLs/checksums and notices.
  "$BREW" info --json=v2 glib gettext pcre2 libffi > "$WINE_ROOT/share/licenses/gstreamer/homebrew-sources.json"
  for file in glib gettext pcre2 libffi; do
    local prefix
    prefix="$("$BREW" --prefix "$file")"
    "$BREW" cat "$file" > "$WINE_ROOT/share/licenses/gstreamer/$file.rb"
    mkdir -p "$WINE_ROOT/share/licenses/gstreamer/$file"
    [ -d "$prefix" ] || continue # libffi can be supplied by macOS.
    find -L "$prefix" -maxdepth 1 -type f \( -iname '*copying*' -o -iname '*license*' -o -iname '*copyright*' \) \
      -exec cp {} "$WINE_ROOT/share/licenses/gstreamer/$file/" \;
  done
  cat > "$WINE_ROOT/share/licenses/gstreamer/README.txt" <<NOTES
GStreamer $GST_VERSION, SHA-256 $GST_SHA256.
Source: https://github.com/GStreamer/gstreamer/archive/refs/tags/$GST_VERSION.tar.gz
Built with GPL and libav/ugly plugins disabled. H.264/HEVC: Apple VideoToolbox;
AAC: Apple AudioToolbox. Apple frameworks are provided by macOS, not redistributed.
Shared libraries may be replaced/relinked. LGPL notices and the build recipe are
included here; exact corresponding sources are attached to the Wine release.
NOTES
}

test_gstreamer() {
  log "Testing packaged GStreamer without Homebrew paths"
  local registry="$BUILD_DIR/gst-test-registry.bin" element
  export GST_PLUGIN_SYSTEM_PATH_1_0="$WINE_ROOT/lib/gstreamer-1.0"
  export GST_PLUGIN_PATH_1_0="" GST_PLUGIN_PATH="" GST_PLUGIN_SYSTEM_PATH=""
  export GST_PLUGIN_SCANNER_1_0="$WINE_ROOT/libexec/gst-plugin-scanner" GST_REGISTRY_1_0="$registry"
  for element in appsrc appsink decodebin qtdemux h264parse aacparse vtdec atdec videoconvert videoflip deinterlace audioconvert audioresample; do
    "$WINE_ROOT/bin/gst-inspect-1.0" "$element" > "$BUILD_DIR/gst-inspect-$element.log" 2>&1 || { cat "$BUILD_DIR/gst-inspect-$element.log"; exit 1; }
    grep -E 'Long-name|License|Filename' "$BUILD_DIR/gst-inspect-$element.log" || true
  done
  CONVERSIO_RUNTIME_LIBRARIES="$WINE_ROOT/lib:/usr/lib" python3 "$REPO/scripts/run-with-timeout.py" 60 \
    "$WINE_ROOT/bin/gst-launch-1.0" -q \
    filesrc location="$REPO/tests/media/h264-aac.mp4" ! qtdemux name=demux \
    demux.video_0 ! queue ! h264parse ! vtdec ! videoconvert ! 'video/x-raw,format=NV12' ! fakesink sync=false \
    demux.audio_0 ! queue ! aacparse ! atdec ! audioconvert ! fakesink sync=false
  if otool -L "$WINE_ROOT/lib/wine/x86_64-unix/winegstreamer.so" | grep -E '/usr/local/|/opt/homebrew/|/gst-stage/'; then
    echo 'Unrelocated winegstreamer dependency'; exit 1
  fi
}

package_gstreamer_sources() {
  log "Packaging corresponding GStreamer/GLib sources"
  local source_dir="$BUILD_DIR/gstreamer-runtime-sources" manifest="$WINE_ROOT/share/licenses/gstreamer/homebrew-sources.json"
  mkdir -p "$source_dir"
  cp "$GST_ARCHIVE" "$source_dir/"
  cp "$manifest" "$source_dir/manifest.json"
  cp "$WINE_ROOT"/share/licenses/gstreamer/*.rb "$source_dir/"
  python3 "$REPO/scripts/fetch-runtime-sources.py" "$manifest" "$source_dir"
  tar -cJf "$DIST/gstreamer-runtime-sources-$GST_VERSION.tar.xz" -C "$source_dir" .
}
