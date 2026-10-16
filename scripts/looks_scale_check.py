#!/usr/bin/env python
"""Scale check for the Windows look: is the 2.0 render a clean 2x of the 1.0 render?

For each sheet it renders docs/ui/looks/windows/<name>.png at 1.0 and <name>@2x.png at 2.0 (into a scratch
folder, through NEPER_LOOKS_SCALE / NEPER_LOOKS_OUT of lib/e/ui/looks.e, so no committed PNG is touched), with the
text left out (NEPER_LOOKS_NOTEXT: text is re-rasterised at every scale and is not what is checked), and compares the
geometry: every run of MIN_RUN or more near-equal pixels in a row or column of the 1.0 image (the sheet background
left out) must be a run of twice the length at twice the offset in the 2.0 image: the inside of the run is flat in
its colour, and the pixels just outside its ends stay nearer the 1.0 neighbours than the run's colour (a run that grew
or shrank by a device pixel fails). Anti-aliased vector shapes (hover marks, round radios) match within that
tolerance. A sheet passes when at least THRESHOLD of its runs match.

Usage (repository root, Git Bash or PowerShell):
    python scripts/looks_scale_check.py                   # every sheet in SHEETS at 2.0
    python scripts/looks_scale_check.py checkbox radio    # some
    python scripts/looks_scale_check.py --scale 1.5       # another scale: informational only (a tile edge lands on
                                                          # a rounded device pixel, so run ends move by one)
Needs the compiler (NEPER_SELF, build/windows/neper-self.exe or the main checkout's) and numpy + Pillow.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ["button", "checkbox", "radio", "mask_edit", "spin_edit", "button_edit", "text_edit",
          "popup_menu_file", "data_grid"]
# popup_menu_file is a sheet of the popup_menu app (one sheet per process); the others are their own apps.
APP_OF = {"popup_menu_file": ("popup_menu", ["popup_menu_file"])}
# The scale_* sheets (examples/looks/scale_tiles.e) put controls on fractional positions on purpose, so they are for the
# eye, not for this check. The popup menu's placeholder icons are strokes drawn as vector art, which do not scale by
# whole pixels, so only its long runs (frame, separators) are compared.
MIN_RUN_OF = {"popup_menu_file": 16}
MIN_RUN = 8
COLOUR_TOL = 8
RUN_TOL = 1
# The pixel next to a run's end may be anti-aliased (a vector shape is), but must stay nearer the 1.0 neighbour than the run.
OUTSIDE_SHARE = 0.9
OUTSIDE_FLOOR = 8
THRESHOLD = 0.93


def compiler():
    for candidate in (os.environ.get("NEPER_SELF"), ROOT / "build/windows/neper-self.exe",
                      "D:/repos/neper/build/windows/neper-self.exe"):
        if candidate and Path(candidate).exists():
            return str(candidate)
    sys.exit("no neper-self.exe: set NEPER_SELF")


def render(name, scale, work):
    app, args = APP_OF.get(name, (name, []))
    exe = work / (app + ".exe")  # one build per app, reused for its sheets
    if not exe.exists():
        out = subprocess.run([compiler(), "emit-executable", f"examples/looks/{app}.e", str(ROOT), "x64", "windows",
                              str(exe), "--arena", "4g"], cwd=ROOT, capture_output=True, text=True)
        if not out.stdout.strip().endswith("executable written"):
            sys.exit(f"compile {app}: {out.stdout[-400:]}{out.stderr[-400:]}")
    env = dict(os.environ, NEPER_LOOKS_NOTEXT="1", NEPER_LOOKS_SCALE=str(scale), NEPER_LOOKS_OUT=str(work / f"out{scale}"))
    subprocess.run([str(exe)] + args, cwd=ROOT, env=env, capture_output=True, check=True)


def png_of(work, name, scale):
    suffix = "" if scale == 1.0 else ("@2x" if scale == 2.0 else f"@{scale}x")
    return np.asarray(Image.open(work / f"out{scale}" / "windows" / f"{name}{suffix}.png").convert("RGB")).astype(int)


def runs_of(line, min_run):
    """Maximal runs (start, length, colour) of near-equal pixels, length >= MIN_RUN."""
    out = []
    n = len(line)
    i = 0
    while i < n:
        j = i + 1
        while j < n and np.abs(line[j] - line[i]).max() <= RUN_TOL:
            j += 1
        if j - i >= min_run:
            out.append((i, j - i, line[i]))
        i = j
    return out


def ends_off(big_out, one_out, colour):
    contrast = np.abs(colour - one_out).max()
    return np.abs(big_out - one_out).max() > OUTSIDE_SHARE * contrast + OUTSIDE_FLOOR


def holds(a_line, b_line, start, length, colour, scale):
    """The 1.0 run (start, length) is a run of scale x its length in the 2.0 line: its inside (one device pixel
    in from each end, where anti-aliasing may sit) is flat in its colour, and the pixel just outside each end is
    close to the pixel just outside the 1.0 run."""
    lo = int(round(start * scale))
    hi = int(round((start + length) * scale))
    inside = b_line[lo + 1:hi - 1]
    if len(inside) == 0 or np.abs(inside - colour).max() > COLOUR_TOL:
        return False
    # A run that grew or shrank by a device pixel makes this neighbour the run's colour instead of its own.
    if lo > 0 and start > 0 and ends_off(b_line[lo - 1], a_line[start - 1], colour):
        return False
    if hi < len(b_line) and start + length < len(a_line) and ends_off(b_line[hi], a_line[start + length], colour):
        return False
    return True


def check(one, big, scale, min_run):
    """Checks rows then columns; returns (checked, matched, examples of misses)."""
    flat = one.reshape(-1, 3)
    values, counts = np.unique(flat, axis=0, return_counts=True)
    background = values[counts.argmax()]
    checked = matched = 0
    misses = []
    for axis in (0, 1):
        a = one if axis == 0 else one.transpose(1, 0, 2)
        b = big if axis == 0 else big.transpose(1, 0, 2)
        for y in range(a.shape[0]):
            ry = int(round(y * scale))
            if ry >= b.shape[0]:
                continue
            for start, length, colour in runs_of(a[y], min_run):
                if np.abs(colour - background).max() <= 2:
                    continue
                checked += 1
                if holds(a[y], b[ry], start, length, colour, scale):
                    matched += 1
                elif len(misses) < 6:
                    misses.append(("row" if axis == 0 else "col", y, start, length, tuple(colour)))
    return checked, matched, misses


def main():
    args = sys.argv[1:]
    scale = 2.0
    if "--scale" in args:
        i = args.index("--scale")
        scale = float(args[i + 1])
        del args[i:i + 2]
    names = args or SHEETS
    failed = []
    with tempfile.TemporaryDirectory(prefix="looks-scale-") as tmp:
        work = Path(tmp)
        for name in names:
            render(name, 1.0, work)
            render(name, scale, work)
            checked, matched, misses = check(png_of(work, name, 1.0), png_of(work, name, scale), scale, MIN_RUN_OF.get(name, MIN_RUN))
            fraction = matched / checked if checked else 1.0
            status = "ok  " if fraction >= THRESHOLD else "FAIL"
            if status == "FAIL" and scale == int(scale):
                failed.append(name)
            print(f"{status} {name:16s} runs {checked:6d} matched {matched:6d} ({fraction * 100:5.1f} %)")
            if status == "FAIL":
                for m in misses:
                    print("       miss", m)
    if failed:
        print("scale check failed:", " ".join(failed))
        sys.exit(1)
    print("scale check passed")


if __name__ == "__main__":
    main()
