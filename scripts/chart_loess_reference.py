"""Reference for e.gfx.chart.loess_interval (L068): statsmodels' LOWESS (it=0)
for the local-linear fit, and the residual scale and pointwise standard error
from an explicit n x n smoother matrix L (Cleveland & Grosse: s^2 = RSS /
trace((I-L)'(I-L)), se(x0) = s * |l(x0)|). Prints the values gfx_chart_loess
checks, in data units."""
import numpy as np
from statsmodels.nonparametric.smoothers_lowess import lowess

X = [7.0, 1.0, 4.0, 9.0, 2.0, 11.0, 5.0, 0.0, 8.0, 3.0, 10.0, 6.0]
Y = [4.1, 1.9, 3.8, 3.2, 2.7, 1.2, 4.6, 1.0, 3.9, 3.1, 2.0, 4.8]
SPAN = 0.5


def weights(x, at, q):
    d = np.abs(x - at)
    h = np.sort(d)[q - 1]
    r = np.minimum(d / h, 1.0)
    w = (1.0 - r ** 3) ** 3
    u = x - at
    s0, s1, s2 = w.sum(), (w * u).sum(), (w * u * u).sum()
    return w * (s2 - s1 * u) / (s0 * s2 - s1 * s1)


if __name__ == "__main__":
    x, y = np.array(X), np.array(Y)
    n = len(x)
    q = int(SPAN * n + 1e-10)
    grid = np.linspace(x.min(), x.max(), 5)
    ours = np.array([weights(x, g, q) @ y for g in grid])
    theirs = lowess(y, x, frac=SPAN, it=0, delta=0.0, xvals=grid)
    assert np.allclose(ours, theirs, atol=1e-9), (ours, theirs)
    L = np.array([weights(x, xi, q) for xi in x])
    residual = y - L @ y
    m = np.eye(n) - L
    delta1 = np.trace(m.T @ m)
    s = np.sqrt(residual @ residual / delta1)
    print(f"q {q} delta1 {delta1:.6f} s {s:.6f}")
    for g, fit in zip(grid, theirs):
        norm2 = weights(x, g, q) @ weights(x, g, q)
        se, pe = s * np.sqrt(norm2), s * np.sqrt(1.0 + norm2)
        print(f"x {g:.2f} fit {fit:.6f} se {se:.6f} confidence(2) {fit - 2 * se:.6f} {fit + 2 * se:.6f}"
              f" prediction(2) {fit - 2 * pe:.6f} {fit + 2 * pe:.6f}")
