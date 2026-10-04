"""Reference values for e.gfx.chart colour-vision simulation (D2103): derives the
Vienot-Brettel-Mollon linear-RGB matrices, simulated colours, CIELAB, CIEDE2000
pairs and palette separations that gfx_chart_color_vision checks."""
import numpy as np
from skimage.color import deltaE_ciede2000, rgb2lab
M = np.array([[17.8824, 43.5161, 4.11935], [3.45565, 27.1554, 3.86714], [0.0299566, 0.184309, 1.46709]])
Minv = np.linalg.inv(M)
white = M @ [1, 1, 1]; blue = M @ [0, 0, 1]; red = M @ [1, 0, 0]
def plane(target, others, anchors):
    A = np.array([[a[o] for o in others] for a in anchors]); y = np.array([a[target] for a in anchors])
    return np.linalg.solve(A, y)
coef = {'protan': plane(0, (1, 2), (white, blue)), 'deutan': plane(1, (0, 2), (white, blue)), 'tritan': plane(2, (0, 1), (white, red))}
for k, v in coef.items(): print(k, repr(v.tolist()))
def lin(c): c = np.asarray(c, float); return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def enc(c): c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
def sim(rgb, kind, sev):
    l = lin(rgb); lms = M @ l
    t = {'protan': 0, 'deutan': 1, 'tritan': 2}[kind]; o = [i for i in range(3) if i != t]
    s = lms.copy(); s[t] = coef[kind][0] * lms[o[0]] + coef[kind][1] * lms[o[1]]
    out = Minv @ s; out = l + (out - l) * sev
    return enc(out)
def matrix(kind):
    t = {'protan': 0, 'deutan': 1, 'tritan': 2}[kind]; o = [i for i in range(3) if i != t]
    P = np.eye(3); P[t] = 0; P[t, o[0]] = coef[kind][0]; P[t, o[1]] = coef[kind][1]
    return Minv @ P @ M
for k in coef: print(k, 'linear-RGB matrix', repr(matrix(k).round(9).tolist()))
print('protan red', sim([1, 0, 0], 'protan', 1).tolist(), 'deutan red', sim([1, 0, 0], 'deutan', 1).tolist(), 'tritan blue', sim([0, 0, 1], 'tritan', 1).tolist())
print('deutan half (0.8,0.3,0.2)', sim([0.8, 0.3, 0.2], 'deutan', 0.5).tolist())
lab = lambda c: rgb2lab(np.array([[c]], float))[0, 0]
print('lab red', lab([1, 0, 0]).tolist(), 'lab white', lab([1, 1, 1]).tolist())
pairs = [((50, 2.6772, -79.7751), (50, 0, -82.7485)), ((50, 3.1571, -77.2803), (50, 0, -82.7485)), ((50, -1.3802, -84.2814), (50, 0, -82.7485)), ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387)), ((50, 2.5, 0), (73, 25, -18))]
for p, q in pairs: print('de00', p, q, deltaE_ciede2000(np.array(p, float), np.array(q, float)))
pal_white = [(0, 114, 178), (195, 86, 0), (0, 135, 99), (142, 68, 173), (179, 38, 62), (171, 102, 0)]
for kind in ['typical', 'protan', 'deutan', 'tritan']:
    cols = [np.array(c) / 255 for c in pal_white]
    if kind != 'typical': cols = [sim(c, kind, 1.0) for c in cols]
    # quantize nothing: simulation output is compared unrounded
    best = (1e9, 0, 0)
    for i in range(6):
        for j in range(i + 1, 6):
            d = deltaE_ciede2000(lab(cols[i]), lab(cols[j]))
            if d < best[0]: best = (d, i, j)
    print('separation', kind, best)
