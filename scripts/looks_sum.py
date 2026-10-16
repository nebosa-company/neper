"""usage: python -I looks_sum.py [--dir windows|windows-dark] sheet ... : struct_off per cell (cells larger than 40x40 only), the way looks_cells.py counts, compact."""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_struct, looks_cells
R = looks_cells.ROOT
args = sys.argv[1:]
d = "windows"
if "--dir" in args:
    i = args.index("--dir"); d = args[i + 1]; del args[i:i + 2]
tot = 0
import json
ART = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "looks_art.json")))
def art_for(n):
    for k, v in ART.items():
        if n.startswith(k):
            return v
    return []
for n in args:
    rp = R + "ref/windows/%s.png" % n; op = R + "%s/%s.png" % (d, n)
    if not os.path.exists(rp) or not os.path.exists(op):
        print(n, "missing"); continue
    ref = np.array(Image.open(rp).convert("RGB")); ours = np.array(Image.open(op).convert("RGB"))
    if ref.shape != ours.shape:
        # the ref is a plain crop of the live capture, ours a sheet with captions: find each ref cell's place in ours
        refm = looks_struct.struct_mask(ref)
        ourm = looks_struct.struct_mask(ours)
        out = []
        for b in looks_cells.cells(ref):
            x0, y0, x1, y1 = b
            if x1 - x0 <= 40 or y1 - y0 <= 40:
                continue
            ys, xs = np.where(refm[y0:y1, x0:x1])
            if len(ys) > 3000:
                pick = np.random.RandomState(1).choice(len(ys), 3000, replace=False); ys = ys[pick]; xs = xs[pick]
            best = (-1, 0, 0)
            for dy in range(-2, 70):
                for dx in range(-2, 60):
                    yy = ys + y0 + dy; xx = xs + x0 + dx
                    ok = (yy >= 0) & (yy < ours.shape[0]) & (xx >= 0) & (xx < ours.shape[1])
                    if not ok.all():
                        continue
                    sc = int((np.abs(ref[ys + y0, xs + x0].astype(int) - ours[yy, xx].astype(int)).max(axis=1) <= 2).sum())
                    if sc > best[0]:
                        best = (sc, dx, dy)
            sc, dx, dy = best
            w, h = x1 - x0, y1 - y0
            if y1 + dy > ours.shape[0] or x1 + dx > ours.shape[1]:
                out.append(-1); continue
            a = ref[y0:y1, x0:x1].astype(int); o = ours[y0 + dy:y1 + dy, x0 + dx:x1 + dx].astype(int)
            m = refm[y0:y1, x0:x1] & ourm[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
            k = int(((np.abs(a - o).max(axis=2) > 2) & m).sum()); out.append(k); tot += k
            out.append("(%+d,%+d)" % (dx, dy))
        print("%-28s %s" % (n, " ".join(str(k) for k in out)))
        continue
    sm = looks_struct.struct_mask(ref) & looks_struct.struct_mask(ours)
    bad = (np.abs(ref.astype(int) - ours.astype(int)).max(axis=2) > 2) & sm
    out = []
    for b in looks_cells.cells(ref):
        for r in art_for(n):
            sm_x0, sm_y0 = b[0] + r[0], b[1] + r[1]
            bad[sm_y0:b[1] + r[3], sm_x0:b[0] + r[2]] = False
        x0, y0, x1, y1 = b
        if x1 - x0 > 40 and y1 - y0 > 40:
            k = int(bad[y0:y1, x0:x1].sum()); out.append(k); tot += k
    print("%-28s %s" % (n, " ".join(str(k) for k in out)))
print("total", tot)
