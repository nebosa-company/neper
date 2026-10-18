"""Round 21: fits the drawn shadows of lib/e/ui/linuxshadow_l2.e and lib/e/ui/linux_card.e to the GTK captures in docs/ui/looks/ref/linux.
The captures are read here, once, to find numbers; the Neper code holds the numbers, not the pixels.

  python -I scripts/linux/fit_shadow.py alert light|dark [layers]   the AdwAlertDialog card (alert-dialog@1x): rim, radius, layers
  python -I scripts/linux/fit_shadow.py popover [layers]           the popover (dropdown-open@1x alpha): radius, layers
  python -I scripts/linux/fit_shadow.py glow light|dark            the column view's overlay scroll bar (columnview@1x)

A layer is the body rectangle moved down `oy`, grown by `spread`, blurred by a Gaussian of `sigma` and laid on as black at `alpha`; the blur of
an edge is 0.5 * alpha * erfc(d / (sigma * sqrt 2)) of the signed distance d to the rounded rectangle. The glow is the shade (a cone,
`peak * (1 - r)` over an ellipse centred on the right edge) plus the thumb (an ellipse 3.7 px across, half cut off by the edge).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.optimize import least_squares
from scipy.special import erfc

REF = Path(__file__).resolve().parents[2] / "docs/ui/looks/ref/linux/"


def sdf(px, py, l, t, r, b, rad):
    qx = np.abs(px - (l + r) / 2) - (r - l) / 2 + rad
    qy = np.abs(py - (t + b) / 2) - (b - t) / 2 + rad
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad


def layered(px, py, rect, rad, layers):
    left = np.ones(px.shape)
    for oy, sp, sg, al in layers:
        d = sdf(px, py, rect[0] - sp, rect[1] - sp + oy, rect[2] + sp, rect[3] + sp + oy, max(rad + sp, 0.0))
        left *= 1 - al * 0.5 * erfc(d / (max(sg, 0.3) * 1.41421356))
    return 1 - left


def fit_body(name, nl, cx0, cy0, cw, ch, target, face_of, mask_of):
    """target: what the capture shows; face_of(c, shade) the model of a pixel from the face coverage c and the shade."""
    h, w = target.shape
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + .5, yy + .5

    def model(p):
        dl, dt, dr, db, rho = p[:5]
        rect = (cx0 - dl, cy0 - dt, cx0 + cw + dr, cy0 + ch + db)
        c = np.clip(0.5 - sdf(px, py, *rect, rho), 0, 1)
        return face_of(c, layered(px, py, rect, rho, [p[5 + 4 * k:9 + 4 * k] for k in range(nl)]))

    mask = mask_of(sdf(px, py, cx0 - .3, cy0 - .2, cx0 + cw + .3, cy0 + ch + .2, 12), px, py)
    init = [(0, 1, 0.5, 0.1), (2, 0, 4, 0.15), (8, 0, 12, 0.2), (4, -4, 6, 0.1)]
    p0 = [0.3, 0.2, 0.3, 0.2, 12.0] + [v for k in range(nl) for v in init[k]]
    lo = [-1, -1, -1, -1, 6] + [-2, -8, 0.4, 0] * nl
    hi = [1, 1, 1, 1, 24] + [14, 40, 40, 1] * nl
    r = least_squares(lambda p: (model(p) - target)[mask], p0, bounds=(lo, hi), diff_step=1e-3, max_nfev=200)
    print(name, "rms %.3f max %.1f" % (np.sqrt(np.mean(r.fun ** 2)), np.abs(r.fun).max()), "card (left, top, right, bottom grow; radius)", np.round(r.x[:5], 4).tolist())
    for k in range(nl):
        print("  layer oy %.4f spread %.4f sigma %.4f alpha %.4f" % tuple(r.x[5 + 4 * k:9 + 4 * k]))


def alert(scheme, nl):
    a = np.asarray(Image.open(REF / scheme / "alert-dialog@1x.png").convert("RGB")).astype(float)[:, :, 0]
    face, under = {"light": (250.0, 216.0), "dark": (56.0, 18.0)}[scheme]
    fit_body("alert " + scheme, nl, 128.0, 134.0, 294.0, 142.0, a, lambda c, s: c * face + (1 - c) * under * (1 - s),
             lambda sd, px, py: (sd > -0.8) & (sd < 60) & (px > 45) & (px < 505) & (py > 25) & (py < 385))


def popover(nl):
    a = np.asarray(Image.open(REF / "light/dropdown-open@1x.png").convert("RGBA")).astype(float)[:, :, 3] / 255.0
    fit_body("popover", nl, 24.0, 27.07, 158.0, 118.8, a * 255, lambda c, s: (c + (1 - c) * s) * 255, lambda sd, px, py: sd > -0.8)


def glow(scheme):
    im = np.asarray(Image.open(REF / scheme / "columnview@1x.png").convert("RGB")).astype(float)[:, :, 0]
    bg = 255 if scheme == "light" else 30
    d = np.abs(im[1:199, 226:279] - bg)
    h, w = d.shape
    X, Y = np.meshgrid(np.arange(w) + .5, np.arange(h) + .5)

    def model(p):
        L, cone, peak, across, tip, rim, soft = p
        yc = 31 + L / 2
        shade = peak * np.clip(1 - np.sqrt(((X - 53.0) / cone) ** 2 + ((Y - yc) / (L / 2)) ** 2), 0, 1)
        ex, ey = (X - rim) / across, (Y - yc) / (L / 2)
        sd = (ex * ex + ey * ey - 1) / np.maximum(np.hypot(2 * ex / across, 2 * ey / (L / 2)), 1e-6)
        return shade + tip * np.clip(0.5 - sd / soft, 0, 1)

    r = least_squares(lambda p: (model(p) - d).ravel(), [166, 49, 10, 3.7, 23, 53.8, 0.7],
                      bounds=([100, 20, 1, 1.5, 5, 50, 0.3], [230, 80, 40, 10, 60, 56, 6]), diff_step=1e-3)
    print("glow", scheme, "rms %.3f" % np.sqrt(np.mean(r.fun ** 2)), "thumb %.1f cone %.2f peak %.3f across %.3f tip %.3f rim %.3f soft %.3f" % tuple(r.x))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "alert":
        alert(a[1], int(a[2]) if len(a) > 2 else 3)
    elif a[0] == "popover":
        popover(int(a[1]) if len(a) > 1 else 3)
    else:
        glow(a[1])
