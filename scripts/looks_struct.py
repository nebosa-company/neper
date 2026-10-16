"""Structural diff of two same-size RGB images (used by the looks edit evals).

structural = a pixel of the reference that sits in a straight run of 11 or more equal pixels (row or column) whose colour
occurs at least 30 times, and that is not within 1 px of any other (ink) pixel; tolerance 2 levels per channel.
`struct_off(ref, ours, box)` returns (pixels off, max error, (x, y) of the worst) inside box = (x0, y0, x1, y1).
"""
import numpy as np


def flat_mask(a):
    run = run_mask(a)
    key = (a[:, :, 0].astype(np.int64) << 16) | (a[:, :, 1].astype(np.int64) << 8) | a[:, :, 2]
    vals, counts = np.unique(key, return_counts=True)
    common = set(vals[counts >= 30].tolist())
    return run & np.isin(key, list(common))


def run_mask(a):
    """Pixels in a row or column run of 11 or more equal pixels (any colour, any count)."""
    h, w, _ = a.shape
    key = (a[:, :, 0].astype(np.int64) << 16) | (a[:, :, 1].astype(np.int64) << 8) | a[:, :, 2]
    run = np.zeros((h, w), bool)
    for y in range(h):
        x = 0
        while x < w:
            e = x
            while e + 1 < w and key[y, e + 1] == key[y, x]:
                e += 1
            if e - x + 1 >= 11:
                run[y, x:e + 1] = True
            x = e + 1
    for x in range(w):
        y = 0
        while y < h:
            e = y
            while e + 1 < h and key[e + 1, x] == key[y, x]:
                e += 1
            if e - y + 1 >= 11:
                run[y:e + 1, x] = True
            y = e + 1
    return run


def struct_mask(a):
    flat = flat_mask(a)
    ink = ~flat
    h, w = flat.shape
    pad = np.pad(ink, 1)
    near = np.zeros_like(ink)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            near |= pad[dy:dy + h, dx:dx + w]
    return flat & ~near


def struct_off(ref, ours, box=None):
    a = ref.astype(int)
    b = ours.astype(int)
    m = struct_mask(ref)
    if box:
        x0, y0, x1, y1 = box
        z = np.zeros_like(m)
        z[y0:y1, x0:x1] = True
        m &= z
    d = np.abs(a - b).max(axis=2)
    e = np.where(m, d, 0)
    bad = int(((d > 2) & m).sum())
    wy, wx = np.unravel_index(int(e.argmax()), e.shape)
    return bad, int(e.max()), (int(wx), int(wy))
