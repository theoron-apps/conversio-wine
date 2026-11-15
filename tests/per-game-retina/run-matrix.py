#!/usr/bin/env python3
"""Run the Retina regression on the current built-in display with a scratch Wine prefix."""
import argparse
import contextlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


DEADLINE = 30
MAC_DRIVER = r"HKCU\Software\Wine\Mac Driver"
APP_DEFAULTS = r"HKCU\Software\Wine\AppDefaults"
ROW = re.compile(
    r"^pid=\d+ screen=(\d+x\d+) current=(\d+x\d+) gdi=(\d+x\d+) config=(\d+x\d+) dpi=(\d+)$",
    re.MULTILINE,
)
MONITOR = re.compile(r"^device=(\S+) monitor=(-?\d+),(-?\d+),(-?\d+),(-?\d+) .* saved=(\d+x\d+)$", re.MULTILINE)


def run_matrix(wine_root, scratch, width, height):
    wine = wine_root / "bin/wine"
    server = wine_root / "bin/wineserver"
    scratch.mkdir()
    prefix = scratch / "prefix"
    env = os.environ | {
        "WINEPREFIX": str(prefix),
        "PATH": f"{wine_root / 'bin'}:{os.environ['PATH']}",
        "DYLD_FALLBACK_LIBRARY_PATH": f"{wine_root / 'lib'}:/usr/lib",
        "WINEDLLOVERRIDES": "winemenubuilder.exe=d",
        "WINEDEBUG": "-all",
    }
    native = f"{width * 2}x{height * 2}"
    logical = f"{width}x{height}"
    identity = set()

    def run(exe, *args, **kwargs):
        return subprocess.run([exe, *args], env=env, check=True, timeout=DEADLINE, **kwargs)

    def reg(*args):
        run(wine, "reg", *args, stdout=subprocess.DEVNULL)

    def set_mode(key, value):
        reg("add", key, "/v", "RetinaMode", "/t", "REG_SZ", "/d", value, "/f")

    def run_probe(name, label, hold=0):
        log = scratch / f"{label}.log"
        with log.open("w") as stream:
            process = subprocess.Popen(
                [wine, f"C:\\retina-{name}.exe", str(hold)], env=env,
                stdout=stream, stderr=subprocess.STDOUT,
            )
        return process, log

    def wait_for_sample(process, log):
        deadline = time.monotonic() + DEADLINE
        while not ROW.search(log.read_text()):
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError(f"{log.name}: no sample\n{log.read_text()}")
            time.sleep(0.05)

    def verify(process, log, expected, minimum=1):
        if process is not None and process.wait(timeout=DEADLINE):
            raise RuntimeError(f"{log.name}: Wine probe failed\n{log.read_text()}")
        data = log.read_text()
        rows = ROW.findall(data)
        monitors = MONITOR.findall(data)
        if min(len(rows), len(monitors)) < minimum:
            raise RuntimeError(f"{log.name}: too few samples\n{data}")
        for *sizes, dpi in rows:
            if sizes != [expected] * 4:
                raise RuntimeError(f"{log.name}: expected {expected}\n{data}")
            identity.add(("DPI", dpi))
        for device, left, top, right, bottom, saved in monitors:
            if f"{int(right) - int(left)}x{int(bottom) - int(top)}" != expected or saved != expected:
                raise RuntimeError(f"{log.name}: expected monitor and saved mode {expected}\n{data}")
            identity.add(("device", device))

    probe_src = Path(__file__).with_name("probe.c")
    compiler = os.environ.get("MINGW_CC", "x86_64-w64-mingw32-gcc")
    subprocess.run([compiler, "-Wall", "-Wextra", "-O2", probe_src, "-o", scratch / "probe.exe",
                    "-luser32", "-lgdi32"], check=True, timeout=DEADLINE)
    for bottle, expected_default in (("n", logical), ("y", native)):
        try:
            with (scratch / f"wineboot-{bottle}.log").open("w") as log:
                run(wine, "wineboot", "-u", stdout=log, stderr=subprocess.STDOUT)
            for name in ("on", "off", "default"):
                shutil.copy2(scratch / "probe.exe", prefix / "drive_c" / f"retina-{name}.exe")
            on_key = APP_DEFAULTS + r"\retina-on.exe\Mac Driver"
            off_key = APP_DEFAULTS + r"\retina-off.exe\Mac Driver"
            set_mode(MAC_DRIVER, bottle)
            set_mode(on_key, "y")
            set_mode(off_key, "n")
            run(server, "-w")
            ordinary = subprocess.Popen([wine, "notepad.exe"], env=env, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
            default, default_log = run_probe("default", f"{bottle}-ordinary", 120000)
            wait_for_sample(default, default_log)
            for a, b in (("on", "off"), ("off", "on")):
                for name in (a, b):
                    verify(*run_probe(name, f"{bottle}-{a}-then-{b}-{name}"),
                           native if name == "on" else logical)
                first, first_log = run_probe(a, f"{bottle}-{a}-overlap-{b}-{a}", 4500)
                wait_for_sample(first, first_log)
                second, second_log = run_probe(b, f"{bottle}-{a}-overlap-{b}-{b}", 2000)
                wait_for_sample(second, second_log)
                if first.poll() is not None:
                    raise RuntimeError("The two probe processes did not overlap")
                verify(second, second_log, native if b == "on" else logical, minimum=2)
                verify(first, first_log, native if a == "on" else logical, minimum=3)
                print(f"Retina={bottle} {a} → {b}: sequential and overlapping passed", flush=True)
            reg("delete", on_key, "/v", "RetinaMode", "/f")
            verify(*run_probe("on", f"{bottle}-override-deleted"), expected_default)
            verify(None, default_log, expected_default, minimum=4)
            if ordinary.poll() is not None or default.poll() is not None:
                raise RuntimeError("The ordinary process did not remain running")
            print(f"Retina={bottle} ordinary process and removed override: {expected_default}", flush=True)
        finally:
            with contextlib.suppress(subprocess.CalledProcessError):
                run(server, "-k")
            run(server, "-w")
    if len(identity) != 2:
        raise RuntimeError(f"Display identity or DPI changed: {identity}")
    print("PASS", " ".join(f"{key}={value}" for key, value in sorted(identity)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wine_root", type=Path)
    parser.add_argument("scratch", type=Path, help="new directory for logs and the Wine prefix")
    parser.add_argument("--logical", nargs=2, type=int, default=[1728, 1117], metavar=("WIDTH", "HEIGHT"))
    options = parser.parse_args()
    run_matrix(options.wine_root.resolve(), options.scratch.resolve(), *options.logical)
