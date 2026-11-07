# conversio-wine

Free Wine builds for **Conversio** by [Theoron](https://github.com/theoron-apps) — the app that runs Windows games from Steam on Apple silicon Macs.

Each build is made from the open-source Wine that CodeWeavers publishes with every CrossOver release, on GitHub Actions, and lands in [Releases](../../releases). Conversio downloads the newest one when you click **Install Everything**.

## What a build contains

| | |
|---|---|
| Wine | CrossOver's Wine from `crossover-sources-<version>.tar.gz`, plus our patches from [`patches/`](patches) |
| Architecture | x86_64; Apple silicon runs it through Rosetta 2 |
| 32-bit programs | Through WoW64, so installers and launchers work without 32-bit macOS libraries |
| Bundled libraries | FreeType (fonts), GnuTLS (HTTPS), SDL2-compat + SDL3 (game controllers), MoltenVK (Vulkan → Metal), GStreamer (game video/audio) |
| Add-ons | Wine Mono (.NET) and Wine Gecko (HTML engine) in the versions this Wine expects, so Wine never asks to download them |
| Not included | Apple's D3DMetal: Apple doesn't allow redistributing it. Conversio imports it from the free Game Porting Toolkit on your Mac |

## Building

**On GitHub:** Actions → **Build Wine** → **Run workflow**. Pick the CrossOver version and turn on **publish** to make a release. A first build takes about two hours; later ones are faster thanks to the compiler cache.

**On a Mac:**

```bash
scripts/build.sh all
```

On Apple silicon the script runs itself under Rosetta and needs Intel Homebrew in `/usr/local`:

```bash
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The result is `dist/conversio-wine-cx<version>-<build>-x86_64.tar.xz`.

## Game input and video

On macOS, mapped SDL controllers provide XInput and DirectInput. Sony pads use
this route by default once SDL starts successfully; the existing winebus
`Devices/<VID[/PID]>/Hidraw` override retains native reports when a game needs them.
See [controller checks](tests/gamepads/README.md) for probes and Steam Input tests.

GStreamer is built from pinned sources with GPL, libav and ugly plugins disabled.
H.264/HEVC decoding uses macOS VideoToolbox and AAC uses AudioToolbox. Plugins,
shared dependencies and the scanner live inside the Wine engine; users do not
need Homebrew. Conversio supplies plugin paths and a registry cache per bottle.
The build checks packaged plugins, H.264/AAC decoding and Wine Media Foundation;
see [media checks](tests/media/README.md).

## A new CrossOver version

1. Run the workflow with the new `cx_version` and an empty `cx_sha256`. The fetch step fails and prints the tarball's checksum.
2. Review the source, add the checksum to `pinned_sha256` in [`scripts/build.sh`](scripts/build.sh) and run it again.

## License

Wine is licensed under the [LGPL-2.1-or-later](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html). Every release carries the exact CodeWeavers source tarball it was built from, and our changes are the patches in this repository. The scripts in this repository are MIT licensed.

GStreamer and its GLib dependencies have their own notices in
`wine/share/licenses/gstreamer`. Releases containing media support also attach
`gstreamer-runtime-sources-<version>.tar.xz`, with the pinned GStreamer tree,
dependency source archives, Homebrew recipes and checksums. These are shared
libraries which can be replaced/relinked. Apple's codec frameworks remain part
of macOS and are not redistributed.

CrossOver is a trademark of CodeWeavers. This project is not affiliated with CodeWeavers, Apple or Valve.

## Tools

[`tools/`](tools) holds small Windows programs that Conversio puts into bottles. They are built by the **Build tools** workflow and published as `tools-N` releases.

- **steamwebhelper wrapper** — Steam's interface is Chromium, and under Wine on Apple silicon its GPU and network processes crash it or paint it black. The wrapper starts Valve's `steamwebhelper` with `--disable-gpu --single-process`. The fix was worked out by [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) and [ByMedion/macos-wine-steam](https://github.com/ByMedion/macos-wine-steam).
