# conversio-wine

Free Wine builds for **Conversio** by [Theoron](https://github.com/theoron-apps) — the app that runs Windows games from Steam on Apple silicon Macs.

Each build is made from the open-source Wine that CodeWeavers publishes with every CrossOver release, on GitHub Actions, and lands in [Releases](../../releases). Conversio downloads the newest one when you click **Install Everything**.

## What a build contains

| | |
|---|---|
| Wine | CrossOver's Wine from `crossover-sources-<version>.tar.gz`, plus our patches from [`patches/`](patches) |
| Architecture | x86_64; Apple silicon runs it through Rosetta 2 |
| 32-bit programs | Through WoW64, so installers and launchers work without 32-bit macOS libraries |
| Bundled libraries | FreeType (fonts), GnuTLS (HTTPS), SDL2 (game controllers), MoltenVK (Vulkan → Metal) |
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

## A new CrossOver version

1. Run the workflow with the new `cx_version` and an empty `cx_sha256`. The fetch step fails and prints the tarball's checksum.
2. Review the source, add the checksum to `pinned_sha256` in [`scripts/build.sh`](scripts/build.sh) and run it again.

## License

Wine is licensed under the [LGPL-2.1-or-later](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html). Every release carries the exact CodeWeavers source tarball it was built from, and our changes are the patches in this repository. The scripts in this repository are MIT licensed.

CrossOver is a trademark of CodeWeavers. This project is not affiliated with CodeWeavers, Apple or Valve.
