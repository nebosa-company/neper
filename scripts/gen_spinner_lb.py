"""The Linux spinner's 32 x 32 alpha tile (lib/e/ui/linuxspin_lb.e): libadwaita's process-working-symbolic.svg (a spiral outline of 81 cubics;
Adwaita icon theme, /usr/share/icons/Adwaita/symbolic-up-to-32/status) filled non-zero at 2 x with 16 x 16 samples per pixel, its cubics cut
into 8 parts. GTK draws this raster turned with a bilinear filter, which is what `linuxspin_lb.paint` does. Run: python -I scripts/gen_spinner_lb.py <svg>
and paste the output into the `tile` function."""
import re
import sys
import numpy as np

t = open(sys.argv[1], encoding="utf-8").read()
d = re.search(r'd="([^"]+)"', t).group(1)
toks = re.findall(r"[a-zA-Z]|-?\d*\.?\d+(?:e-?\d+)?", d)
i = 0
cur = (0.0, 0.0)
last = None
cmd = None
pts = []


def num():
    global i
    v = float(toks[i])
    i += 1
    return v


def cubic(p0, p1, p2, p3):
    for k in range(1, 9):
        u = k / 8
        v = 1 - u
        pts.append(tuple(v**3 * np.array(p0) + 3 * v * v * u * np.array(p1) + 3 * v * u * u * np.array(p2) + u**3 * np.array(p3)))


while i < len(toks):
    if toks[i].isalpha():
        cmd = toks[i]
        i += 1
    if cmd == "m":
        cur = (cur[0] + num(), cur[1] + num())
        pts.append(cur)
        cmd = "l"
    elif cmd == "c":
        p1 = (cur[0] + num(), cur[1] + num())
        p2 = (cur[0] + num(), cur[1] + num())
        p3 = (cur[0] + num(), cur[1] + num())
        cubic(cur, p1, p2, p3)
        last, cur = p2, p3
    elif cmd == "s":
        p1 = (2 * cur[0] - last[0], 2 * cur[1] - last[1])
        p2 = (cur[0] + num(), cur[1] + num())
        p3 = (cur[0] + num(), cur[1] + num())
        cubic(cur, p1, p2, p3)
        last, cur = p2, p3
    elif cmd == "v":
        cur = (cur[0], cur[1] + num())
        pts.append(cur)
    elif cmd == "h":
        cur = (cur[0] + num(), cur[1])
        pts.append(cur)
    elif cmd == "l":
        cur = (cur[0] + num(), cur[1] + num())
        pts.append(cur)
    elif cmd in "zZ":
        break
P = np.array(pts) * 2.0
S = 16
xs = (np.arange(32 * S) + 0.5) / S
X, Y = np.meshgrid(xs, xs)
wn = np.zeros(X.shape, int)
for k in range(len(P)):
    x0, y0 = P[k]
    x1, y1 = P[(k + 1) % len(P)]
    up = (y0 <= Y) & (y1 > Y)
    dn = (y1 <= Y) & (y0 > Y)
    cross = (x1 - x0) * (Y - y0) - (X - x0) * (y1 - y0)
    wn += np.where(up & (cross > 0), 1, 0) - np.where(dn & (cross < 0), 1, 0)
A = (wn != 0).astype(float).reshape(32, S, 32, S).mean(axis=(1, 3))
q = np.round(A * 255).astype(int)
print(",".join(str(v) for v in q.flatten()))
