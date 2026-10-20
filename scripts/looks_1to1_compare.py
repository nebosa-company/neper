"""Our Windows light renders against the OLD (resampled) and the NEW (true 1:1) v3 captures.

`python -I scripts/looks_1to1_compare.py [name ...]`   (from the repository root)

For each crop a piece of OUR committed sheet (docs/ui/looks/windows/<sheet>.png) is placed in every v3 capture of one set (ref/windows or
ref/windows-1to1: dialogs, states, hover) by normalised correlation on luma; the capture and offset with the best correlation are the screen
the sheet shows. Counted = pixels in the piece whose largest channel difference to that capture is more than 2 levels, glyphs included.
Sharpness = mean absolute horizontal step of the luma over the piece in the capture (resampled text is softer, so lower).
The old and the new set are searched independently, so a different state of the same screen (selected row, hover) is a real difference
the numbers carry; the best-correlation file names are printed so that can be judged.
"""
import glob
import os
import sys
import numpy as np
import cv2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks") + os.sep

# crop name: (our sheet, (x, y, w, h) piece of our sheet)
PIECES = {
    "data_grid_main": ("data_grid_main", (12, 32, 500, 468)),
    "data_grid_main.collection": ("data_grid_main", (14, 256, 480, 240)),
    "data_grid_top.L": ("data_grid_top", (0, 0, 590, 257)),
    "data_grid_top.R": ("data_grid_top", (596, 0, 590, 257)),
    "data_grid_bottom.L": ("data_grid_bottom", (0, 0, 590, 286)),
    "data_grid_bottom.R": ("data_grid_bottom", (596, 0, 590, 286)),
    "data_grid_hover.L": ("data_grid_hover", (0, 0, 590, 257)),
    "data_grid_hover.R": ("data_grid_hover", (596, 0, 590, 257)),
    "data_grid_group2.L": ("data_grid_group2", (0, 0, 590, 257)),
    "data_grid_group2.R": ("data_grid_group2", (596, 0, 590, 257)),
    "tree_list_expanded": ("tree_list_expanded", (0, 0, 644, 363)),
    "vertical_grid": ("vertical_grid", (0, 0, 330, 425)),
    "check_list_box_dialog": ("check_list_box_dialog", (0, 0, 524, 400)),
}


def load(p):
    return cv2.imread(p, cv2.IMREAD_COLOR)[:, :, ::-1].astype(np.int16)  # RGB


def luma(a):
    return (a @ np.array([0.299, 0.587, 0.114], np.float32)).astype(np.float32)


def sharp(a):
    return float(np.abs(np.diff(luma(a), axis=1)).mean())


def captures(sub):
    fs = sorted(glob.glob(ROOT + "ref/%s/**/*@1x.png" % sub, recursive=True))
    return fs


def search(piece, files, cache):
    ph, pw = piece.shape[:2]
    pl = luma(piece)
    best = None
    for f in files:
        if f not in cache:
            cache[f] = load(f)
        c = cache[f]
        if c.shape[0] < ph or c.shape[1] < pw:
            continue
        r = cv2.matchTemplate(luma(c), pl, cv2.TM_CCOEFF_NORMED)
        _, mx, _, loc = cv2.minMaxLoc(r)
        if best is None or mx > best[0]:
            best = (float(mx), f, loc)
    return best


def main(names):
    caches = {"windows": {}, "windows-1to1": {}}
    files = {k: captures(k) for k in caches}
    print("%-22s %-8s %-40s %5s %9s %6s  %s" % ("crop", "set", "capture", "corr", "counted", "sharp", "at"))
    for name in names:
        sheet, (x, y, w, h) = PIECES[name]
        ours = load(ROOT + "windows/%s.png" % sheet)[y:y + h, x:x + w]
        old = search(ours, files["windows"], caches["windows"])
        same = ROOT + "ref/windows-1to1/" + os.path.relpath(old[1], ROOT + "ref/windows") if old else None
        runs = [("old", "windows", old)]
        if same and os.path.exists(same):
            runs.append(("new same", "windows-1to1", search(ours, [same], caches["windows-1to1"])))
        free = search(ours, files["windows-1to1"], caches["windows-1to1"])
        if free and (not same or free[1] != same):
            runs.append(("new best", "windows-1to1", free))
        for tag, k, b in runs:
            if not b:
                print("%-22s %-8s none" % (name, tag))
                continue
            mx, f, (cx, cy) = b
            c = caches[k][f]
            best = None  # refine: the placement with the fewest counted pixels within 2 px of the correlation peak
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if cy + dy < 0 or cx + dx < 0 or cy + dy + h > c.shape[0] or cx + dx + w > c.shape[1]:
                        continue
                    cap = c[cy + dy:cy + dy + h, cx + dx:cx + dx + w]
                    n = int((np.abs(cap - ours).max(axis=2) > 2).sum())
                    if best is None or n < best[0]:
                        best = (n, cx + dx, cy + dy, cap)
            n, bx, by, cap = best
            print("%-22s %-8s %-40s %5.3f %9d %6.2f  (%d,%d) of %d" % (name, tag, os.path.basename(f)[:-7], mx, n, sharp(cap), bx, by, h * w), flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or list(PIECES))
