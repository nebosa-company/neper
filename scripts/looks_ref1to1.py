"""Rebuilds a Windows reference sheet from the true 1:1 v3 captures: `python -I scripts/looks_ref1to1.py <sheet> [...] [--dry]`.

docs/ui/looks/ref/windows/<sheet>.png is a composite of crops of the old (resampled) captures. Each connected cell of it is located
exactly (least mean absolute difference) in the old captures under ref/windows (dialogs, states, hover); the same rectangle of the same
file under ref/windows-1to1 replaces it, and the result is written to ref/windows-1to1/<sheet>.png. A cell that is not found exactly in
an old capture, or whose capture has no 1:1 twin, stays as it was, and the report says so; a cell whose 1:1 twin shows another state
(more than 12 levels mean difference once both are blurred) is replaced all the same but flagged `state`, because ours cannot match it.
"""
import glob
import os
import sys
import numpy as np
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
from scipy import ndimage  # noqa: E402

ROOT = lc.ROOT
CACHE = {}
# the 1:1 run could not reach these dialogs (see windows-1to1/README.md); the same screen was grabbed under another name
ALIAS = {"dialogs/deck-properties@1x.png": "states/dialog-deck-properties-rest@1x.png"}


def load(p):
    if p not in CACHE:
        CACHE[p] = cv2.imread(p, cv2.IMREAD_COLOR)[:, :, ::-1]
    return CACHE[p]


def old_files():
    return sorted(glob.glob(ROOT + "ref/windows/**/*@1x.png", recursive=True))


def locate(cell, files):
    h, w = cell.shape[:2]
    g = cv2.cvtColor(cell[:, :, ::-1].copy(), cv2.COLOR_BGR2GRAY).astype(np.float32)
    best = None
    for f in files:
        c = load(f)
        if c.shape[0] < h or c.shape[1] < w:
            continue
        cg = cv2.cvtColor(c[:, :, ::-1].copy(), cv2.COLOR_BGR2GRAY).astype(np.float32)
        r = cv2.matchTemplate(cg, g, cv2.TM_SQDIFF)
        mn, _, loc, _ = cv2.minMaxLoc(r)
        if best is None or mn < best[0]:
            best = (mn, f, loc)
    mn, f, (x, y) = best
    crop = load(f)[y:y + h, x:x + w]
    return float(np.abs(crop.astype(int) - cell.astype(int)).mean()), f, x, y


def cell_boxes(ref):
    """looks_cells.cells without its 2 px shrink where the cell touches the sheet's edge (the dilation is clipped there)."""
    bg = tuple(int(v) for v in ref[0, 0])
    m = np.abs(ref.astype(int) - np.array(bg)).max(axis=2) > 0
    m = ndimage.binary_dilation(m, structure=np.ones((3, 3), bool), iterations=2)
    lab, n = ndimage.label(m, structure=np.ones((3, 3), bool))
    H, W = m.shape
    out = []
    for sl in ndimage.find_objects(lab):
        ys, xs = sl
        out.append((0 if xs.start == 0 else xs.start + 2, 0 if ys.start == 0 else ys.start + 2,
                    W if xs.stop == W else xs.stop - 2, H if ys.stop == H else ys.stop - 2))
    return sorted(out, key=lambda b: (b[1] // 8, b[0]))


def build(name, dry):
    ref = np.array(load(ROOT + "ref/windows/%s.png" % name))
    out = ref.copy()
    files = old_files()
    boxes = cell_boxes(ref)
    H, W = ref.shape[:2]
    if W <= 800 and H <= 600:
        whole = (0, 0, W, H)  # a sheet that is one crop touching its corner has no background to find cells by
        if locate(ref, files)[0] <= 1.0:
            boxes = [whole]
    stats = []
    for (x0, y0, x1, y1) in boxes:
        cell = ref[y0:y1, x0:x1]
        if cell.shape[0] < 12 or cell.shape[1] < 12:
            continue
        err, f, x, y = locate(cell, files)
        rel = os.path.relpath(f, ROOT + "ref/windows")
        new = ROOT + "ref/windows-1to1/" + ALIAS.get(rel.replace("\\", "/"), rel)
        if err > 1.0:
            stats.append((name, (x0, y0, x1, y1), "not exact in old captures (%.2f)" % err))
            continue
        if not os.path.exists(new):
            stats.append((name, (x0, y0, x1, y1), "no 1:1 twin of %s" % rel))
            continue
        h, w = cell.shape[:2]
        n = load(new)[y:y + h, x:x + w]
        if n.shape != cell.shape:
            stats.append((name, (x0, y0, x1, y1), "1:1 twin %s is another size, kept old" % rel))
            continue
        o = cell
        d = float(np.abs(cv2.GaussianBlur(n, (0, 0), 2).astype(int) - cv2.GaussianBlur(o, (0, 0), 2).astype(int)).mean())
        tag = "ok" if d <= 12 else "state"
        out[y0:y1, x0:x1] = n
        stats.append((name, (x0, y0, x1, y1), "%s %s at (%d,%d) blurred diff %.1f" % (tag, rel, x, y, d)))
    for s in stats:
        print("%s %s %s" % s)
    if not dry:
        cv2.imwrite(ROOT + "ref/windows-1to1/%s.png" % name, out[:, :, ::-1])


if __name__ == "__main__":
    for n in [a for a in sys.argv[1:] if not a.startswith("-")]:
        build(n, "--dry" in sys.argv)
