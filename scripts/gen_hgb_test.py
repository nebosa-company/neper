"""Vectors for tests/selfhost/fixtures/link/ml_hgb (L063, histogram gradient boosting).

Oracle: scikit-learn HistGradientBoostingRegressor / Classifier (no early
stopping, no subsampling). Gradients are float32 inside scikit-learn, so
predictions agree to about 1e-5 relative, not bit for bit. Run from the repo root.
"""
import sys
import warnings
from pathlib import Path

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit

warnings.filterwarnings("ignore")
rng = np.random.default_rng(63)
lines = []


def num(v):
    if v != v:
        return "nan"
    return repr(float(v))


def flat(a):
    return " ".join(num(v) for v in np.asarray(a, float).flatten())


def case(n, d, rounds, lr, leaves, depth, min_leaf, l2, bins, logistic, missing=0.0, rounding=None, test_nan=False,
         train_clean=False):
    x = rng.normal(0, 1, (n, d))
    if rounding is not None:
        x = np.round(x, rounding)
    signal = np.sin(2 * x[:, 0]) + 0.5 * x[:, 1] * (x[:, 2 % d] > 0) + 0.3 * x[:, d - 1] ** 2
    if logistic:
        y = (signal + rng.normal(0, 0.4, n) > np.median(signal)).astype(float)
    else:
        y = signal + rng.normal(0, 0.2, n)
    if missing > 0:
        mask = rng.random((n, d)) < missing
        x = np.where(mask, np.nan, x)
    xt = rng.normal(0, 1, (14, d))
    if rounding is not None:
        xt = np.round(xt, rounding)
    if test_nan:
        xt[::3, 0] = np.nan
        xt[1::4, d - 1] = np.nan
    common = dict(max_iter=rounds, learning_rate=lr, max_leaf_nodes=leaves, max_depth=depth or None,
                  min_samples_leaf=min_leaf, l2_regularization=l2, max_bins=bins, early_stopping=False,
                  random_state=0)
    if logistic:
        m = HistGradientBoostingClassifier(loss="log_loss", **common).fit(x, y)
        pred = m.predict_proba(xt)[:, 1]
    else:
        m = HistGradientBoostingRegressor(loss="squared_error", **common).fit(x, y)
        pred = m.predict(xt)
    lines.append(f"hgb|{n} {d} {rounds} {lr!r} {leaves} {depth} {min_leaf} {l2!r} {bins} {int(logistic)}|"
                 f"{flat(x)}|{flat(y)}|{flat(xt)}|{flat(pred)}")


import os

STANDARD = [
    ((120, 4, 25, 0.1, 8, 0, 5, 0.0, 255, False), dict(rounding=1)),       # midpoint thresholds (few distinct values)
    ((300, 3, 20, 0.1, 12, 0, 10, 0.0, 255, False), dict()),               # quantile thresholds (300 > 255 distinct)
    ((150, 4, 20, 0.2, 10, 0, 5, 0.5, 64, False), dict(missing=0.12, test_nan=True)),
    ((200, 4, 30, 0.1, 8, 0, 10, 0.0, 255, True), dict(rounding=2)),
    ((220, 5, 25, 0.15, 16, 4, 8, 1.5, 128, True), dict(missing=0.1, test_nan=True)),
    ((100, 3, 15, 0.3, 6, 3, 4, 2.0, 255, False), dict(rounding=1)),
    ((180, 4, 20, 0.1, 8, 0, 6, 0.0, 255, False), dict(rounding=1, test_nan=True)),   # NaN only at prediction time
    ((260, 6, 15, 0.1, 31, 0, 20, 0.0, 255, True), dict()),
]
for args, kwargs in (eval(os.environ["HGB_DEBUG"]) if os.environ.get("HGB_DEBUG") else STANDARD):
    case(*args, **kwargs)

HARNESS = r'''
fn check(a: *mem.Arena, f: []str, nf: usize) -> bool {
    var head: [12]f64 = zero
    load(f[1usize], head[..])
    let n = usize(head[0usize])
    let d = usize(head[1usize])
    let (x, xe) = mem.alloc[f64](a, n * d + 1usize)
    let (y, ye) = mem.alloc[f64](a, n + 1usize)
    let (xt, xte) = mem.alloc[f64](a, 14usize * d + 1usize)
    let (want, we) = mem.alloc[f64](a, 15usize)
    if xe != ok || ye != ok || xte != ok || we != ok { ret false }
    let nx = nums(f[2usize], x)
    let ny = nums(f[3usize], y)
    let nt = nums(f[4usize], xt)
    let nw = nums(f[5usize], want)
    if nx != n * d || ny != n || nt != 14usize * d || nw != 14usize { ret false }
    var p = hgb.default_params()
    p.rounds = usize(head[2usize])
    p.learning_rate = head[3usize]
    p.max_leaf_nodes = usize(head[4usize])
    p.max_depth = usize(head[5usize])
    p.min_samples_leaf = usize(head[6usize])
    p.l2 = head[7usize]
    p.max_bins = usize(head[8usize])
    p.logistic = head[9usize] != 0.0f64
    let (m, e) = hgb.fit(a, x[..nx], y[..ny], n, d, p)
    if e != ok { ret false }
    var i = 0usize
    while i < 14usize {
        let got = hgb.predict(&m, xt[i * d..i * d + d])
        var scale = want[i]
        if scale < 0.0f64 { scale = 0.0f64 - scale }
        if scale < 1.0f64 { scale = 1.0f64 }
        var diff = got - want[i]
        if diff < 0.0f64 { diff = 0.0f64 - diff }
        if diff > 0.0001f64 * scale {
            let (sb, sbe) = str.builder(a, 96usize)
            var out_text = sb
            let p1 = str.push_f64(&out_text, got)
            let p2 = str.push_byte(&out_text, 32u8)
            let p3 = str.push_f64(&out_text, want[i])
            let shown = io.print(str.done(&out_text))
            let nl = io.print("|")
            ret false
        }
        i += 1usize
    }
    ret true
}
'''

emit("ml_hgb",
     "// `e.ml.hgb` against scikit-learn's HistGradientBoosting (scripts/gen_hgb_test.py): midpoint and quantile bin thresholds,\n"
     "// leaf-wise growth with min_samples_leaf, depth and L2 limits, missing values in training and at prediction time, and the\n"
     "// regression and binary log-loss objectives.",
     ["use e.ml.hgb as hgb"], HARNESS, lines, "ml hgb ok", per_chunk=2, arena=True)
