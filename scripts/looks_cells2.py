"""Audit-4 metric: a reference flat pixel is off when OURS differs by more than 2 levels there, whether or not ours is flat.

`python -I scripts/looks_cells2.py <sheet> [...] [--dir windows|windows-dark] [-v] [--save out.png]`
Mask = looks_struct.struct_mask(ref) only (never ANDed with ours). Cells = ref connected non-background regions (see looks_cells.py).
Also reports `any_off` (every pixel off by more than 2 levels, text included) and the ink-box agreement of looks_cells.py.
Exclusions: none unless `x0,y0,x1,y1` boxes are given on the command line (v3 artwork), which are painted out of both images.
`--save` writes ref | ours | diff (3x) of the whole sheet for viewing.
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_struct  # noqa: E402
import looks_cells  # noqa: E402

ROOT = looks_cells.ROOT
CLUSTERS = 0


def run(name, look="windows", verbose=False, masks=(), save=None):
    ref = np.array(Image.open(ROOT + "ref/windows/%s.png" % name).convert("RGB"))
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, name)).convert("RGB"))
    if ref.shape != ours.shape:
        print("%s: SIZE ref %s ours %s" % (name, ref.shape, ours.shape))
        return None
    for (x0, y0, x1, y1) in masks:
        ref[y0:y1, x0:x1] = ref[0, 0]
        ours[y0:y1, x0:x1] = ref[0, 0]
    sm = looks_struct.struct_mask(ref)
    # the text zone: within 2 px of a dark non-flat reference pixel (glyphs and v3's icon bitmaps), reported apart as `text`
    flat = looks_struct.flat_mask(ref)
    lum = (ref.astype(float) * np.array([0.299, 0.587, 0.114])).sum(axis=2)
    ink = (~flat) & (lum < 200)
    from scipy import ndimage as _nd
    zone = _nd.binary_dilation(ink, structure=np.ones((3, 3), bool), iterations=2)
    d = np.abs(ref.astype(int) - ours.astype(int)).max(axis=2)
    tot = 0
    allt = 0
    npass = 0
    bs = looks_cells.cells(ref)
    inside = np.zeros(d.shape, bool)
    for (x0, y0, x1, y1) in bs:
        inside[y0:y1, x0:x1] = True
    for i, b in enumerate(bs):
        x0, y0, x1, y1 = b
        dd = d[y0:y1, x0:x1]
        m = sm[y0:y1, x0:x1]
        bad = int(((dd > 2) & m).sum())
        anyoff = int((dd > 2).sum())
        e = np.where(m, dd, 0)
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        bg = looks_cells.cellkey(ref, b)
        a = ref[y0:y1, x0:x1]
        o = ours[y0:y1, x0:x1]
        ok = {t: looks_cells.agree(looks_cells.lines(a, bg, t), looks_cells.lines(o, bg, t)) for t in (60, 100, 150)}
        ink = ok[60] and (ok[100] or ok[150])
        tot += bad
        allt += anyoff
        npass += (bad == 0 and ink)
        if verbose or bad or not ink:
            print("  cell %2d %-18s chrome_off %5d max %3d at (%d,%d) any_off %5d ink %s" % (i, str(b), bad, int(e.max()), x0 + wx, y0 + wy, anyoff, ink))
    tot = int(((d > 2) & sm & inside).sum())
    allt = int(((d > 2) & inside).sum())
    txt = int(((d > 2) & sm & inside & zone).sum())
    print("%s [%s]: %d of %d cells pass, chrome_off %d (union of cells; %d within 2 px of dark ink = text, %d outside), any_off %d" % (name, look, npass, len(bs), tot, txt, tot - txt, allt))
    if CLUSTERS:
        from scipy import ndimage
        bad = (d > 2) & sm & inside & ~zone
        lab, n = ndimage.label(ndimage.binary_dilation(bad, structure=np.ones((3, 3), bool), iterations=3))
        out = []
        for i, sl in enumerate(ndimage.find_objects(lab), 1):
            cnt = int((bad[sl] & (lab[sl] == i)).sum())
            if cnt:
                out.append((cnt, sl[1].start, sl[0].start, sl[1].stop, sl[0].stop))
        out.sort(reverse=True)
        for c in out[:CLUSTERS]:
            print("   cluster %5d px  x %d-%d y %d-%d" % (c[0], c[1], c[3], c[2], c[4]))
    if save:
        diff = np.zeros(ref.shape, np.uint8)
        diff[...] = 255
        diff[d > 2] = (255, 0, 0)
        diff[(d > 2) & sm] = (0, 0, 0)
        im = np.concatenate([ref, ours, diff], axis=0)
        Image.fromarray(im).save(save)
    return tot


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    masks = []
    save = None
    look = "windows"
    if "--clusters" in sys.argv:
        CLUSTERS = int(sys.argv[sys.argv.index("--clusters") + 1])
        args.remove(str(CLUSTERS))
    if "--save" in sys.argv:
        save = sys.argv[sys.argv.index("--save") + 1]
        args.remove(save)
    if "--dir" in sys.argv:
        look = sys.argv[sys.argv.index("--dir") + 1]
        args.remove(look)
    for a in list(args):
        if a.count(",") == 3 and a.replace(",", "").isdigit():
            masks.append(tuple(int(v) for v in a.split(",")))
            args.remove(a)
    for n in args:
        run(n, look, "-v" in sys.argv, masks, save)
