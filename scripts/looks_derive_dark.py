"""`python -I scripts/looks_derive_dark.py prefix...` (round 15): for each sheet of docs/ui/looks/windows/ with a same-size windows-dark twin, how consistently does the
dark sheet follow a light->dark colour map: pixels of the light sheet are grouped by colour; the dark colour of a group is its
mode; a pixel is `off` when its dark colour differs from its group's mode by more than 2 levels. Text anti-aliasing blends
differ with the ink, so pixels within 2 px of text ink (more than 60 levels from the light sheet's background) are counted apart."""
import sys, glob, os
import numpy as np
from PIL import Image
from scipy import ndimage
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'ui', 'looks') + os.sep
tot = 0
for pre in sys.argv[1:]:
    for f in sorted(glob.glob(R + 'windows/%s*.png' % pre)):
        n = os.path.basename(f)
        if '@' in n or '-vs-ref' in n:
            continue
        g = R + 'windows-dark/' + n
        if not os.path.exists(g):
            continue
        a = np.array(Image.open(f).convert('RGB')).astype(int)
        b = np.array(Image.open(g).convert('RGB')).astype(int)
        if a.shape != b.shape:
            print('%-40s size differs %s %s' % (n, a.shape[:2], b.shape[:2]))
            continue
        key = (a[..., 0] << 16) | (a[..., 1] << 8) | a[..., 2]
        h, w = key.shape
        flat = key.reshape(-1)
        dk = b.reshape(-1, 3)
        order = np.argsort(flat, kind='stable')
        fs = flat[order]
        starts = np.r_[0, np.nonzero(np.diff(fs))[0] + 1]
        off = np.zeros(flat.shape, bool)
        for s0, s1 in zip(starts, np.r_[starts[1:], len(fs)]):
            idx = order[s0:s1]
            cols = dk[idx]
            ck = (cols[:, 0] << 16) | (cols[:, 1] << 8) | cols[:, 2]
            vals, cnt = np.unique(ck, return_counts=True)
            m = vals[cnt.argmax()]
            mc = np.array([(m >> 16) & 255, (m >> 8) & 255, m & 255])
            off[idx] = np.abs(cols - mc).max(axis=1) > 2
        off = off.reshape(h, w)
        bg = np.array(Image.open(f).convert('RGB'))[0, 0].astype(int)
        ink = np.abs(a - bg).max(axis=2) > 60
        zone = ndimage.binary_dilation(ink, iterations=2)
        print('%-40s px %7d  off %6d  outside text zone %6d' % (n, h * w, off.sum(), (off & ~zone).sum()))
