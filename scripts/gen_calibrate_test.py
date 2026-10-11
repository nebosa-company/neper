"""Vectors for tests/selfhost/fixtures/link/ml_calibrate (L063, calibration).

Oracle: scikit-learn `_sigmoid_calibration` (Platt with smoothed targets),
`IsotonicRegression(out_of_bounds="clip")`, `brier_score_loss`, `log_loss` and
`calibration_curve(strategy="uniform")`. Run from the repo root.
"""
import sys
import warnings
from pathlib import Path

import numpy as np
from sklearn.calibration import _sigmoid_calibration, calibration_curve
from sklearn.isotonic import IsotonicRegression
from sklearn.metrics import brier_score_loss, log_loss

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit

warnings.filterwarnings("ignore")
rng = np.random.default_rng(632)
lines = []


def flat(a):
    return " ".join(repr(float(v)) for v in np.asarray(a, float).flatten())


# Platt scaling and isotonic regression on scores of varying quality, with ties.
for n, sep, rounding in [(60, 1.0, None), (90, 2.5, 1), (45, 0.4, 0), (120, 1.5, 2), (30, 3.0, None)]:
    y = (rng.random(n) < 0.45).astype(float)
    f = rng.normal(0, 1, n) + sep * (y - 0.5)
    if rounding is not None:
        f = np.round(f, rounding)
    a, b = _sigmoid_calibration(f, y)
    q = np.concatenate([np.sort(f)[:: max(1, n // 12)], [f.min() - 1.0, f.max() + 1.0, float(np.median(f))]])
    p = 1.0 / (1.0 + np.exp(a * q + b))
    iso = IsotonicRegression(out_of_bounds="clip").fit(f, y)
    lines.append(f"cal|{n}|{flat(f)}|{flat(y)}|{flat(q)}|{flat([a, b])}|{flat(p)}|{flat(iso.predict(q))}")

# Metrics and reliability bins.
for n, bins in [(80, 5), (150, 10), (60, 4), (200, 8)]:
    prob = np.clip(rng.beta(0.8, 0.8, n), 0, 1)
    y = (rng.random(n) < prob ** 0.8).astype(float)
    frac, mean_pred = calibration_curve(y, prob, n_bins=bins, strategy="uniform")
    # Counts per bin from the same edges.
    edges = np.linspace(0.0, 1.0 + 1e-8, bins + 1)
    ids = np.searchsorted(edges[1:-1], prob)
    counts = np.bincount(ids, minlength=bins)
    ece = float(np.sum(counts[counts > 0] * np.abs(frac - mean_pred)) / n)
    lines.append(f"met|{n} {bins}|{flat(prob)}|{flat(y)}|{flat([brier_score_loss(y, prob), log_loss(y, prob)])}|"
                 f"{flat(counts)}|{flat(mean_pred)}|{flat(frac)}|{ece!r}")

HARNESS = r'''
fn check(a: *mem.Arena, f: []str, nf: usize) -> bool {
    var head: [4]f64 = zero
    load(f[1usize], head[..])
    let n = usize(head[0usize])
    let (x, xe) = mem.alloc[f64](a, n + 1usize)
    let (y, ye) = mem.alloc[f64](a, n + 1usize)
    if xe != ok || ye != ok { ret false }
    let nx = nums(f[2usize], x)
    let ny = nums(f[3usize], y)
    if nx != n || ny != n { ret false }
    if str.eq(f[0usize], "cal") {
        let (q, qe) = mem.alloc[f64](a, 32usize)
        let (ab, abe) = mem.alloc[f64](a, 2usize)
        let (want_p, wpe) = mem.alloc[f64](a, 32usize)
        let (want_i, wie) = mem.alloc[f64](a, 32usize)
        let (targets, te) = mem.alloc[f64](a, n)
        let (order, oe) = mem.alloc[usize](a, n)
        let (weight, we) = mem.alloc[f64](a, n)
        let (kx, kxe) = mem.alloc[f64](a, n)
        let (ky, kye) = mem.alloc[f64](a, n)
        if qe != ok || abe != ok || wpe != ok || wie != ok || te != ok || oe != ok || we != ok || kxe != ok || kye != ok { ret false }
        let nq = nums(f[4usize], q)
        load(f[5usize], ab)
        let np = nums(f[6usize], want_p)
        let ni = nums(f[7usize], want_i)
        if np != nq || ni != nq { ret false }
        let (s, e) = calibrate.platt_fit(x[..n], y[..n], n, 0.000000000001f64, 200u32, targets)
        if e != ok || !near(s.a, ab[0usize], 0.000001f64) || !near(s.b, ab[1usize], 0.000001f64) { ret false }
        let (count, ie) = calibrate.isotonic_fit(x[..n], y[..n], n, order, weight, kx, ky)
        if ie != ok { ret false }
        var i = 0usize
        while i < nq {
            if !near(calibrate.platt_apply(s, q[i]), want_p[i], 0.000001f64) { ret false }
            if !near(calibrate.isotonic_predict(kx[..count], ky[..count], count, q[i]), want_i[i], 0.000000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(f[0usize], "met") {
        let bins = usize(head[1usize])
        var want_scores: [2]f64 = zero
        var want_counts: [16]f64 = zero
        var want_mean: [16]f64 = zero
        var want_frac: [16]f64 = zero
        var want_ece: [1]f64 = zero
        load(f[4usize], want_scores[..])
        let nc = nums(f[5usize], want_counts[..])
        let nm = nums(f[6usize], want_mean[..])
        let nfp = nums(f[7usize], want_frac[..])
        load(f[8usize], want_ece[..])
        if !near(calibrate.brier_score(x[..n], y[..n]), want_scores[0usize], 0.000000001f64) { ret false }
        if !near(calibrate.log_loss(x[..n], y[..n], 0.000000000000001f64), want_scores[1usize], 0.000000001f64) { ret false }
        var count: [16]usize = zero
        var mean_predicted: [16]f64 = zero
        var fraction: [16]f64 = zero
        if calibrate.reliability(x[..n], y[..n], bins, count[..], mean_predicted[..], fraction[..]) != ok { ret false }
        var i = 0usize
        var kept = 0usize
        while i < bins {
            if usize(want_counts[i]) != count[i] { ret false }
            if count[i] > 0usize {
                if !near(mean_predicted[i], want_mean[kept], 0.000000001f64) || !near(fraction[i], want_frac[kept], 0.000000001f64) { ret false }
                kept += 1usize
            }
            i += 1usize
        }
        if kept != nm || kept != nfp || nc != bins { ret false }
        ret near(calibrate.expected_calibration_error(count[..], mean_predicted[..], fraction[..], bins), want_ece[0usize], 0.000000001f64)
    }
    ret false
}
'''

emit("ml_calibrate",
     "// `e.ml.calibrate` against scikit-learn (scripts/gen_calibrate_test.py): Platt scaling with smoothed targets, isotonic\n"
     "// regression with ties and clipping, Brier score, log loss, reliability bins and the expected calibration error.",
     ["use e.ml.calibrate as calibrate"], HARNESS, lines, "ml calibrate ok", per_chunk=3, arena=True)
