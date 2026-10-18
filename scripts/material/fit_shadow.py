"""Fits the M3 elevation shadows of lib/e/ui/matshadow.e to the md-elevation captures (elevation-level1..5-rest, docs/ui/looks/ref/material).
A layer is the body rectangle moved down `oy`, grown by `spread`, blurred by a Gaussian of `sigma` and laid on as black at `alpha`
(0.5 * alpha * erfc(d / (sigma * sqrt 2)) of the signed distance to the rounded rectangle), as in scripts/linux/fit_shadow.py.
  python -I scripts/material/fit_shadow.py [light|dark] [layers]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.optimize import least_squares
from scipy.special import erfc

REF = Path(__file__).resolve().parents[2] / "docs/ui/looks/ref/material"
M, W, H, RAD = 56, 120, 64, 12.0


def sdf(px, py, l, t, r, b, rad):
    qx = np.abs(px - (l + r) / 2) - (r - l) / 2 + rad
    qy = np.abs(py - (t + b) / 2) - (b - t) / 2 + rad
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad


def layered(px, py, layers):
    left = np.ones(px.shape)
    for oy, sp, sg, al in layers:
        d = sdf(px, py, M - sp, M - sp + oy, M + W + sp, M + H + sp + oy, max(RAD + sp, 0.0))
        left *= 1 - al * 0.5 * erfc(d / (max(sg, 0.3) * 1.41421356))
    return 1 - left


def fit(scheme, level, nl):
    im = np.asarray(Image.open(REF / scheme / ("elevation-level%d-rest@1x.png" % level)).convert("RGB")).astype(float)[:, :, 0]
    bg = im[2, 2]
    target = 1 - im / bg  # the shade, against the page colour
    h, w = target.shape
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + .5, yy + .5
    out = sdf(px, py, M, M, M + W, M + H, RAD) > 0.8
    init = [(1, 0, 1, 0.3), (2, 1, 3, 0.15), (4, 2, 8, 0.1)]
    p0 = [v for k in range(nl) for v in init[k]]
    lo = [-2, -4, 0.3, 0] * nl
    hi = [20, 20, 30, 1] * nl
    r = least_squares(lambda p: (layered(px, py, [p[4 * k:4 * k + 4] for k in range(nl)]) - target)[out], p0, bounds=(lo, hi), diff_step=1e-3, max_nfev=300)
    print("level %d rms %.5f max %.4f (of 1)" % (level, np.sqrt(np.mean(r.fun ** 2)), np.abs(r.fun).max()))
    for k in range(nl):
        print("    Layer { oy: %.4f, spread: %.4f, sigma: %.4f, alpha: %.4f }" % tuple(r.x[4 * k:4 * k + 4]))


if __name__ == "__main__":
    scheme = sys.argv[1] if len(sys.argv) > 1 else "light"
    nl = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    for level in range(1, 6):
        fit(scheme, level, nl)
