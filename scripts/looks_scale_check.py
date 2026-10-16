"""Scale check for the Windows look: is the render at 1.25, 1.5 and 2.0 a clean scaling of the 1.0 render?

For every Windows sheet of every sheet app in examples/looks (the cup_*, material_* and scale_tiles apps are not
Windows sheets) it renders docs/ui/looks/windows/<name>.png at 1.0 and at each scale into a scratch folder (through
NEPER_LOOKS_SCALE / NEPER_LOOKS_OUT / NEPER_LOOKS_ONLY of lib/e/ui/looks.e, so no committed PNG is touched), with the
text left out (NEPER_LOOKS_NOTEXT: text is re-rasterised at every scale and is not what is checked), and compares the
geometry: every run of MIN_RUN or more near-equal pixels in a row or column of the 1.0 image (the sheet background
left out) must be a run of `scale` times the length at `scale` times the offset in the scaled image, each edge on the
device pixel winpx.edge gives it (floor(v * scale + 0.5)): the inside of the run is flat in its colour, and the
pixels just outside its ends stay nearer the 1.0 neighbours than the run's colour (a run that grew or shrank by a
device pixel fails). Anti-aliased vector shapes (hover marks, round radios) match within that tolerance. A sheet
passes when at least THRESHOLD of its runs match; an app that does not run to the end at a scale (an arena
exhausted, a crash) fails every sheet of it as ERROR.

Usage (repository root, Git Bash or PowerShell):
    python scripts/looks_scale_check.py                       # every sheet at 1.25, 1.5 and 2.0
    python scripts/looks_scale_check.py checkbox radio        # some sheets (their apps are run whole)
    python scripts/looks_scale_check.py --scale 1.5           # one scale
    python scripts/looks_scale_check.py --report              # also writes docs/ui/looks/scale-report.md
Needs the compiler (NEPER_SELF, build/windows/neper-self.exe or the main checkout's) and numpy + Pillow.
"""
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SCALES = [1.25, 1.5, 2.0]
# Apps that are not Windows sheets (the other flavors, and the scale_* sheets, which put controls on fractional
# positions on purpose, so they are for the eye).
SKIP_APP = re.compile(r"^(cup_|material_|scale_tiles$)")
# The popup menu draws strokes as vector art (the placeholder icons), which do not scale by whole pixels, so only its
# long runs (frame, separators) are compared.
MIN_RUN_OF = {"popup_menu": 16, "toolbar_button": 16, "page_control": 16, "image_combo_box": 12}  # (the toolbar, tab and list-item glyphs are vector stand-ins too)
MIN_RUN = 8
COLOUR_TOL = 8
RUN_TOL = 1
# The pixel next to a run's end may be anti-aliased (a vector shape is), but must stay nearer the 1.0 neighbour than the run.
OUTSIDE_SHARE = 0.9
OUTSIDE_FLOOR = 8
THRESHOLD = 0.93
NEAR_THRESHOLD = 0.95
# A sheet with fewer runs than this is not judged by a ratio (splitter_live has 6: one grip and its rules).
FEW_RUNS = 20
# Sheets whose Windows look draws the group frame on fractional pixels on purpose (v3's DPI-scaled forms put the frame
# between pixels and the 1.0 render is the blurred two-row line the captures show), so the frame is not a whole-pixel run
# at any scale; their other runs are checked like everyone's, and the numbers are in the report.
EXEMPT = {
    "group_box": "frame on fractional pixels on purpose (group_frame_paint)",
    "radio_group": "frame on fractional pixels on purpose (group_frame_paint)",
    "radio_group_dialog": "frame on fractional pixels on purpose (group_frame_paint)",
}
AUDIT3 = "Audit 3 (the checker rounded half to even, so a tile edge on a half device pixel counted as moved): at 1.5 button 76.4 %, checkbox 89.0, radio 87.2, mask_edit 92.8, popup_menu_file 79.2; at 2.0 mask_edit 92.0 (threshold 93) and edits_hover died with `e.mem.Exhausted`. With the rounding fixed, on master 180 of 253 sheets passed at 1.25, 219 at 1.5 and 223 at 2.0 (the `before` columns); after the round 9 pass all 253 pass at every scale. What changed: the check rounds like `winpx.edge`; menu, frame, selection and border boxes snap to device pixels in the Windows look (`widget.snapped`); the button ring and its focus dots paint from a snapped origin (`winpx.origin`); a sheet run frees each frame's pixels (`looks.drop_shot`), which was the Exhausted arena."
JOBS = int(os.environ.get("NEPER_SCALE_JOBS", "6"))


def compiler():
    for candidate in (os.environ.get("NEPER_SELF"), ROOT / "build/windows/neper-self.exe",
                      "D:/repos/neper/build/windows/neper-self.exe"):
        if candidate and Path(candidate).exists():
            return str(candidate)
    sys.exit("no neper-self.exe: set NEPER_SELF")


def apps():
    return sorted(p.stem for p in (ROOT / "examples/looks").glob("*.e") if not SKIP_APP.match(p.stem))


EXTRA_CANDIDATES = {
    "menu_bar": [["menu_bar_open_" + k] for k in ("file", "cards", "search", "view", "cardart", "online", "reports", "tools", "admin", "help")],
    "data_grid_dialog_states": [["sh"], ["sh1"], ["sh2"], ["mh"], ["m"], ["sorth"]],
}
SHEETS_JSON = ROOT / "scripts/looks_scale_sheets.json"
BEFORE_JSON = ROOT / "scripts/looks_scale_before.json"


def candidates_of(app):
    """The argument lists to try for an app: the sheet apps pick a sheet by their first argument (a letter and a digit,
    or a name), some by the argument count. Read from the app's source, so a new variant is found by --discover."""
    text = (ROOT / f"examples/looks/{app}.e").read_text(encoding="utf-8")
    out = [[]]
    names = set(re.findall(r'strs\.eq\(args\[1usize\], "([^"]+)"\)', text))
    if app == "popup_menu":
        names |= set(re.findall(r"(popup_menu_(?:sel|sub)_[a-z0-9_]+)@", text)) | {"popup_menu_reports_deck_mode"}
    names |= set(re.findall(r'"(%s[a-z0-9_]*)"' % app.split("_")[0], text))
    out += [[n] for n in sorted(names)]
    out += [[str(d)] for d in range(20)]
    letters = sorted({chr(int(v)) for v in re.findall(r"== (\d+)u8", text) if 48 <= int(v) <= 122})
    for c in letters:
        out.append([c])
        out += [[c + str(d)] for d in range(10)]
        out += [[c + "10"], [c + "11"]]
    out += [["x", "y"], ["x", "y", "z"]]
    # variants a source regex cannot see (a name built from pieces, a prefix of a letter group)
    out += EXTRA_CANDIDATES.get(app, [])
    return out


def jobs_of(app):
    """(argument list) per process of an app, from scripts/looks_scale_sheets.json (written by --discover)."""
    import json
    table = json.loads(SHEETS_JSON.read_text(encoding="utf-8"))
    return [list(a) for a in sorted({tuple(v[1]) for v in table.values() if v[0] == app})]


def discover(only):
    """Finds which (app, arguments) writes which Windows sheet at 1.0 and writes scripts/looks_scale_sheets.json
    (with app names given, only those apps are probed again and merged into the file)."""
    import json
    table = json.loads(SHEETS_JSON.read_text(encoding="utf-8")) if only else {}
    if only:
        table = {k: v for k, v in table.items() if v[0] not in only}
    with tempfile.TemporaryDirectory(prefix="looks-discover-") as tmp:
        work = Path(tmp)
        chosen = [a for a in apps() if not only or a in only]
        for a in chosen:
            (work / a).mkdir()
            e = build(a, work / a)
            if e:
                sys.exit(e)
        for a in chosen:
            cands = candidates_of(a)
            folder = work / a
            def probe(i):
                scratch = work / f"{a}-{i}"
                scratch.mkdir()
                shutil.copy(folder / (a + ".exe"), scratch / (a + ".exe"))
                err = render(a, cands[i], 1.0, scratch, notext=False, exact=False)
                names = sheets_in(scratch, 1.0)
                return err, {n: same_as_committed(scratch, n) for n in names}
            with ThreadPoolExecutor(JOBS) as pool:
                results = list(pool.map(probe, range(len(cands))))
            exact_of = {}
            for cand, (err, names) in zip(cands, results):
                for n in sorted(names):
                    # the first argument that writes the sheet, unless a later one writes the committed picture
                    if n not in table or (names[n] and not exact_of.get(n)):
                        table[n] = [a, cand]
                        exact_of[n] = names[n]
            print(a, len(cands), "probes,", sum(1 for v in table.values() if v[0] == a), "sheets", flush=True)
    SHEETS_JSON.write_text(json.dumps(table, indent=1, sort_keys=True) + chr(10), encoding="utf-8")
    print(len(table), "sheets")


def build(app, work):
    exe = work / (app + ".exe")
    kept = os.environ.get("NEPER_SCALE_EXES")  # a folder of built apps to reuse (delete one to rebuild it)
    if kept and (Path(kept) / (app + ".exe")).exists():
        shutil.copy(Path(kept) / (app + ".exe"), exe)
        return None
    out = subprocess.run([compiler(), "emit-executable", f"examples/looks/{app}.e", str(ROOT), "x64", "windows",
                          str(exe), "--arena", "4g"], cwd=ROOT, capture_output=True, text=True)
    if not out.stdout.strip().endswith("executable written"):
        return f"compile {app}: {out.stdout[-300:]}{out.stderr[-300:]}"
    if kept:
        Path(kept).mkdir(parents=True, exist_ok=True)
        shutil.copy(exe, Path(kept) / (app + ".exe"))
    return None


def same_as_committed(work, name):
    """Whether the 1.0 picture the run wrote is the committed docs/ui/looks/windows picture (text and all)."""
    committed = ROOT / "docs/ui/looks/windows" / f"{name}.png"
    if not committed.exists():
        return False
    try:
        return bool((png_of(work, name, 1.0) == np.asarray(Image.open(committed).convert("RGB")).astype(int)).all())
    except Exception:
        return False


def render(app, args, scale, work, notext=True, exact=True):
    """Runs the app at `scale`; returns an error text or None."""
    env = dict(os.environ, NEPER_LOOKS_EXACT="1", NEPER_LOOKS_SCALE=str(scale), NEPER_LOOKS_ONLY="windows",
               NEPER_LOOKS_OUT=str(work / f"out{scale}"))
    if notext:
        env["NEPER_LOOKS_NOTEXT"] = "1"
    if not exact:
        env.pop("NEPER_LOOKS_EXACT")
    done = subprocess.run([str(work / (app + ".exe"))] + args, cwd=ROOT, env=env, capture_output=True, text=True)
    if done.returncode != 0:
        tail = (done.stderr or done.stdout).strip().splitlines()[-1:] or ["exit %d" % done.returncode]
        return f"exit {done.returncode}: {tail[0][:80]}"
    return None


def png_of(work, name, scale):  # work: the app's folder
    suffix = "" if scale == 1.0 else ("@2x" if scale == 2.0 else f"@{scale}x")
    return np.asarray(Image.open(work / f"out{scale}" / "windows" / f"{name}{suffix}.png").convert("RGB")).astype(int)


def sheets_in(work, scale):
    folder = work / f"out{scale}" / "windows"
    if not folder.exists():
        return set()
    tail = "" if scale == 1.0 else ("@2x" if scale == 2.0 else f"@{scale}x")
    return {p.stem[:len(p.stem) - len(tail)] for p in folder.glob("*.png")
            if p.stem.endswith(tail) and (scale != 1.0 or "@" not in p.stem) and not p.stem.endswith("-vs-ref" + tail)}


def edge(v, scale):
    return int(math.floor(v * scale + 0.5))


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


def soft_end(a_line, at, step, colour):
    """The 1.0 pixel just outside a run end (`at`, going `step`) is a blend of the run colour and the pixel beyond it: the
    shape's true edge sat on a fractional logical position (a progress fill of 37.4 px), so where the scaled edge falls is
    not defined by the run."""
    n1, n2 = at, at + step
    if n1 < 0 or n2 < 0 or n1 >= len(a_line) or n2 >= len(a_line):
        return False
    p1, p2 = a_line[n1], a_line[n2]
    lo, hi = np.minimum(colour, p2), np.maximum(colour, p2)
    return bool((p1 >= lo - 2).all() and (p1 <= hi + 2).all() and np.abs(p1 - colour).max() > 3 and np.abs(p1 - p2).max() > 3)


def holds(a_line, b_line, start, length, colour, scale):
    """The 1.0 run (start, length) is a run of scale x its length in the scaled line: its inside (one device pixel
    in from each end, where anti-aliasing may sit) is flat in its colour, and the pixel just outside each end is
    close to the pixel just outside the 1.0 run. An end that is soft in the 1.0 render (`soft_end`) is not held to
    a place: its last logical pixel of the scaled line is left out of the inside."""
    lo = edge(start, scale)
    hi = edge(start + length, scale)
    soft_lo = soft_end(a_line, start - 1, -1, colour)
    soft_hi = soft_end(a_line, start + length, 1, colour)
    trim = int(math.ceil(scale)) + 1
    inside = b_line[lo + (trim if soft_lo else 1):hi - (trim if soft_hi else 1)]
    if len(inside) == 0 or np.abs(inside - colour).max() > COLOUR_TOL:
        return False
    # A run that grew or shrank by a device pixel makes this neighbour the run's colour instead of its own.
    if not soft_lo and lo > 0 and start > 0 and ends_off(b_line[lo - 1], a_line[start - 1], colour):
        return False
    if not soft_hi and hi < len(b_line) and start + length < len(a_line) and ends_off(b_line[hi], a_line[start + length], colour):
        return False
    return True


def holds_near(b, ry, start, length, colour, scale):
    """The relaxed test: the run's inside, two device pixels in from each end, is flat in its colour on the line the run
    maps to or one device pixel either side of it. This is what a shape on a fractional logical position, or a text-derived
    width that is not the 1.0 width times the scale, still satisfies; a smeared, doubled, recoloured or missing line is not."""
    lo = edge(start, scale) + 2
    hi = edge(start + length, scale) - 2
    if hi <= lo:
        return True
    for r in (ry, ry - 1, ry + 1):
        if 0 <= r < b.shape[0] and np.abs(b[r][lo:hi] - colour).max() <= COLOUR_TOL:
            return True
    return False


def check(one, big, scale, min_run):
    """Checks rows then columns; returns (checked, matched, near, examples of misses): `near` counts the runs that
    `holds_near`, a superset of the exact ones."""
    flat = one.reshape(-1, 3)
    values, counts = np.unique(flat, axis=0, return_counts=True)
    background = values[counts.argmax()]
    checked = matched = near = 0
    misses = []
    for axis in (0, 1):
        a = one if axis == 0 else one.transpose(1, 0, 2)
        b = big if axis == 0 else big.transpose(1, 0, 2)
        for y in range(a.shape[0]):
            ry = edge(y, scale)
            if ry >= b.shape[0]:
                continue
            for start, length, colour in runs_of(a[y], min_run):
                if np.abs(colour - background).max() <= 2:
                    continue
                checked += 1
                if holds(a[y], b[ry], start, length, colour, scale):
                    matched += 1
                    near += 1
                elif holds_near(b, ry, start, length, colour, scale):
                    near += 1
                elif len(misses) < 6:
                    misses.append(("row" if axis == 0 else "col", y, start, length, tuple(colour)))
    return checked, matched, near, misses


def fraction_of(checked, matched):
    return matched / checked if checked else 1.0


def passes(r):
    """A sheet passes at THRESHOLD of its runs exact, or NEAR_THRESHOLD of them within a device pixel."""
    checked, matched, near = r
    if checked < FEW_RUNS:
        return True
    return fraction_of(checked, matched) >= THRESHOLD or fraction_of(checked, near) >= NEAR_THRESHOLD


def finish(result, misses_of, scales, report, before):
    """Prints the table (and writes the report); returns the exit code."""
    names = sorted({n for s in scales for n in result[s]})
    bad = {s: [] for s in scales}
    lines = []
    for n in names:
        cells = []
        for s in scales:
            r = result[s].get(n)
            if isinstance(r, str):
                cells.append(("ERR", r))
                bad[s].append(n)
            else:
                text = f"{fraction_of(r[0], r[1]) * 100:.1f}/{fraction_of(r[0], r[2]) * 100:.1f}"
                cells.append((text, "" if passes(r) or n in EXEMPT else "FAIL"))
                if not passes(r) and n not in EXEMPT:
                    bad[s].append(n)
        lines.append((n, cells))
    for n, cells in lines:
        flag = "  <-- " + " ".join(f"{s}" for s, c in zip(scales, cells) if c[1]) if any(c[1] for c in cells) else ""
        print(f"{n:42s}" + "".join(f"{c[0]:>12s}" for c in cells) + flag)
        for s, c in zip(scales, cells):
            if c[1] and c[0] != "ERR":
                for m in misses_of.get((n, s), [])[:3]:
                    print(f"      {s} miss", m)
            elif c[1]:
                print(f"      {s} {c[1]}")
    total = {s: len(names) for s in scales}
    for s in scales:
        print(f"scale {s}: {len(names) - len(bad[s])} of {len(names)} sheets pass (exact {THRESHOLD * 100:.0f} % or within a device pixel {NEAR_THRESHOLD * 100:.0f} %)")
    if report:
        write_report(lines, scales, bad, len(names), before)
    failed = sorted({n for s in scales for n in bad[s]})
    if failed:
        print("scale check failed:", " ".join(failed))
        return 1
    print("scale check passed")
    return 0


def write_report(lines, scales, bad, total, before):
    import json
    was = json.loads(BEFORE_JSON.read_text(encoding="utf-8")) if BEFORE_JSON.exists() else {}
    out = ["# Windows look at other scales", "",
           "Written by `python scripts/looks_scale_check.py --report`. For every Windows sheet (light look, text left out) the "
           "table gives the share of runs of 8 or more equal pixels of the 1.0 render (16 for the popup menus, the toolbar and the page "
           "control) that are a clean scaling in the 1.25, 1.5 and 2.0 renders. Each cell is `exact/near`: the share of runs that are "
           "exactly the 1.0 run scaled, and the share that are flat and within a device pixel of it (a shape on a fractional logical "
           f"position, a text-derived width). A sheet passes at {THRESHOLD * 100:.0f} % exact or {NEAR_THRESHOLD * 100:.0f} % near "
           f"(or with fewer than {FEW_RUNS} runs); `ERR` is an app that did not run to the end at that scale. The 1.0 reference is "
           "rendered with the whole-pixel snapping on too (`NEPER_LOOKS_EXACT`), so a shape the sheet put on a fractional logical "
           "position is not blurred in it. Method and tolerances: the header of the script. `before` is the exact share of the same "
           "sheets before the round 9 scale pass (master renders, this checker with only its rounding fixed).", "",
           "| scale | " + " | ".join(f"{s}" for s in scales) + " |", "|---|" + "---|" * len(scales),
           "| sheets passing | " + " | ".join(f"{total - len(bad[s])} of {total}" for s in scales) + " |", ""]
    if before:
        out += [before, ""]
    out += ["| sheet | " + " | ".join(f"{s} before | {s} now" for s in scales) + " | note |", "|---|" + "---:|---:|" * len(scales) + "---|"]
    for n, cells in lines:
        row = []
        for k, c in enumerate(cells):
            old = was.get(n, ["", "", ""])
            row.append(old[k] if k < len(old) else "")
            row.append(f"**{c[0].strip()}**" if c[1] else c[0].strip())
        note = "exempt: " + EXEMPT[n] if n in EXEMPT else ""
        out.append(f"| {n} | " + " | ".join(row) + f" | {note} |")
    (ROOT / "docs/ui/looks/scale-report.md").write_text(chr(10).join(out) + chr(10), encoding="utf-8")


def main():
    args = sys.argv[1:]
    scales = SCALES
    if "--scale" in args:
        i = args.index("--scale")
        scales = [float(args[i + 1])]
        del args[i:i + 2]
    if "--discover" in args:
        args.remove("--discover")
        discover(set(args))
        return 0
    report = "--report" in args
    if report:
        args.remove("--report")
    wanted = set(args)
    result = {s: {} for s in scales}  # result[scale][sheet] = (checked, matched) or an error text
    misses_of = {}
    with tempfile.TemporaryDirectory(prefix="looks-scale-") as tmp:
        work = Path(tmp)
        chosen = apps()
        if wanted:
            chosen = [a for a in chosen if any(w == a or w.startswith(a + "_") or a.startswith(w + "_") for w in wanted)]
        for a in chosen:
            (work / a).mkdir()
        errors = [build(a, work / a) for a in chosen]  # the compiler does not run twice at once (arena exhausted)
        built = []
        for a, e in zip(chosen, errors):
            if e:
                print("BUILD ERROR", e)
            else:
                built.append(a)
        tasks = [(a, args_, s) for a in built for args_ in jobs_of(a) for s in [1.0] + scales]
        with ThreadPoolExecutor(JOBS) as pool:
            outcomes = list(pool.map(lambda t: render(t[0], t[1], t[2], work / t[0]), tasks))
        failed_run = {}
        for (a, args_, s), e in zip(tasks, outcomes):
            if e:
                failed_run[(a, s)] = f"{' '.join(args_)} {e}".strip()
        for a in built:
            folder = work / a
            names = sorted(sheets_in(folder, 1.0))
            if wanted:
                names = [n for n in names if n in wanted]
            for n in names:
                min_run = MIN_RUN_OF.get(a, MIN_RUN)
                for s in scales:
                    if (a, 1.0) in failed_run:
                        result[s][n] = "ERROR " + failed_run[(a, 1.0)]
                    elif (a, s) in failed_run:
                        result[s][n] = "ERROR " + failed_run[(a, s)]
                    elif n not in sheets_in(folder, s):
                        result[s][n] = "ERROR no png"
                    else:
                        try:
                            checked, matched, near, misses = check(png_of(folder, n, 1.0), png_of(folder, n, s), s, min_run)
                            result[s][n] = (checked, matched, near)
                            misses_of[(n, s)] = misses
                        except Exception as e:  # e.g. a size mismatch
                            result[s][n] = f"ERROR {type(e).__name__}"
        # sheets an app wrote at 1.0 but not at a scale because the run died before it are already ERROR above
        for a in built:
            for s in scales:
                if (a, s) in failed_run:
                    for n in sheets_in(work / a, 1.0):
                        if not wanted or n in wanted:
                            result[s].setdefault(n, "ERROR " + failed_run[(a, s)])
        # an app that failed at a scale before writing anything has no sheet to name: list it by app
        for a in built:
            for s in scales:
                if (a, s) in failed_run and not sheets_in(work / a, 1.0):
                    result[s][a + " (app)"] = "ERROR " + failed_run[(a, s)]
    return finish(result, misses_of, scales, report, os.environ.get("NEPER_SCALE_BEFORE", AUDIT3))


if __name__ == "__main__":
    sys.exit(main())
