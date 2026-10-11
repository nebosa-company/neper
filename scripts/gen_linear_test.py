"""Vectors for tests/selfhost/fixtures/link/ml_linear_robust (L057).

Oracle: scikit-learn (ElasticNet, PolynomialFeatures, QuantileRegressor with the
HiGHS LP solver) and statsmodels (RLM with HuberT). Run from the repo root.
"""
import sys
import warnings
from pathlib import Path

import numpy as np
from sklearn.linear_model import ElasticNet, QuantileRegressor
from sklearn.preprocessing import PolynomialFeatures
import statsmodels.api as sm

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit, fmt

warnings.filterwarnings("ignore")
rng = np.random.default_rng(57)
lines = []


def r(v):
    return repr(float(v))


def design(n, d, noise=0.5, outliers=0):
    x = np.round(rng.normal(0, 1, (n, d)), 3)
    beta = rng.normal(0, 2, d)
    y = x @ beta + 1.5 + rng.normal(0, noise, n)
    for i in range(outliers):
        y[i] += rng.choice([-1, 1]) * rng.uniform(8, 15)
    return x, np.round(y, 3)


# Elastic net, including the lasso (ratio 1) and ridge-like (ratio 0.05) ends.
for n, d, alpha, ratio in [(25, 3, 0.1, 0.5), (30, 5, 0.3, 0.2), (20, 4, 0.05, 1.0), (40, 6, 0.5, 0.8),
                           (18, 3, 0.2, 0.05), (50, 8, 0.15, 0.6)]:
    x, y = design(n, d)
    m = ElasticNet(alpha=alpha, l1_ratio=ratio, tol=1e-14, max_iter=1000000).fit(x, y)
    coef = np.append(m.coef_, m.intercept_)
    lines.append(f"enet|{n} {d} {r(alpha)} {r(ratio)}|{fmt(x.flatten())}|{fmt(y)}|{fmt(coef)}")

# Polynomial features.
for n, d, degree, inter, bias in [(4, 2, 2, 0, 1), (5, 3, 2, 0, 0), (3, 2, 3, 0, 1), (4, 3, 3, 1, 1), (3, 4, 2, 1, 0),
                                  (3, 1, 4, 0, 1), (2, 3, 4, 0, 1)]:
    x = np.round(rng.normal(0, 1.5, (n, d)), 3)
    p = PolynomialFeatures(degree=degree, interaction_only=bool(inter), include_bias=bool(bias)).fit_transform(x)
    lines.append(f"poly|{n} {d} {degree} {inter} {bias} {p.shape[1]}|{fmt(x.flatten())}|{fmt(p.flatten())}")

# Quantile regression.
for n, d, tau in [(40, 2, 0.5), (40, 2, 0.1), (40, 2, 0.9), (60, 3, 0.25), (35, 1, 0.75), (80, 4, 0.5)]:
    x = np.round(rng.normal(0, 1, (n, d)), 3)
    y = np.round(x @ rng.normal(0, 2, d) + 1.0 + rng.standard_t(3, n) * (0.5 + np.abs(x[:, 0])), 3)
    m = QuantileRegressor(quantile=tau, alpha=0.0, solver="highs").fit(x, y)
    coef = np.append(m.coef_, m.intercept_)
    lines.append(f"qr|{n} {d} {r(tau)}|{fmt(x.flatten())}|{fmt(y)}|{fmt(coef)}")

# Huber (statsmodels RLM, HuberT, MAD scale).
for n, d, t, out in [(40, 2, 1.345, 4), (30, 3, 1.345, 3), (50, 1, 1.0, 5), (60, 4, 2.0, 6), (25, 2, 1.345, 0)]:
    x, y = design(n, d, 0.6, out)
    res = sm.RLM(y, sm.add_constant(x, prepend=False), M=sm.robust.norms.HuberT(t=t)).fit(maxiter=1000, tol=1e-14)
    lines.append(f"hub|{n} {d} {r(t)}|{fmt(x.flatten())}|{fmt(y)}|{fmt(res.params)}")

HARNESS = r'''
fn check(f: []str, nf: usize) -> bool {
    let op = f[0usize]
    var head: [8]f64 = zero
    var x: [640]f64 = zero
    var y: [160]f64 = zero
    var want: [640]f64 = zero
    var got: [640]f64 = zero
    var scratch: [4000]f64 = zero
    load(f[1usize], head[..])
    let n = usize(head[0usize])
    let d = usize(head[1usize])
    let k = d + 1usize
    if str.eq(op, "poly") {
        let nx = nums(f[2usize], x[..])
        let nw = nums(f[3usize], want[..])
        let (width, e) = linear.polynomial_features(x[..nx], n, d, usize(head[2usize]), head[3usize] != 0.0f64, head[4usize] != 0.0f64, got[..])
        if e != ok || width != usize(head[5usize]) || nw != n * width { ret false }
        if linear.polynomial_width(d, usize(head[2usize]), head[3usize] != 0.0f64, head[4usize] != 0.0f64) != width { ret false }
        var i = 0usize
        while i < nw {
            if !near(got[i], want[i], 0.000000000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    let nx = nums(f[2usize], x[..])
    let ny = nums(f[3usize], y[..])
    load(f[4usize], want[..])
    if nx != n * d || ny != n { ret false }
    var i = 0usize
    if str.eq(op, "enet") {
        if linear.elastic_net(x[..nx], y[..ny], n, d, head[2usize], head[3usize], 0.0000000000001f64, 1000000u32, got[..], scratch[..]) != ok { ret false }
        while i < k {
            if !near(got[i], want[i], 0.000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(op, "qr") {
        let (iterations, e) = linear.quantile_regression(x[..nx], y[..ny], n, d, head[2usize], 0.000000001f64, 500u32, got[..], scratch[..])
        if e != ok { ret false }
        let have = linear.pinball_loss(x[..nx], y[..ny], n, d, head[2usize], got[..k])
        let best = linear.pinball_loss(x[..nx], y[..ny], n, d, head[2usize], want[..k])
        if !near(have, best, 0.000000001f64) { ret false }
        while i < k {
            if !near(got[i], want[i], 0.000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(op, "hub") {
        let (iterations, e) = linear.huber(x[..nx], y[..ny], n, d, head[2usize], 0.00000000001f64, 1000u32, got[..], scratch[..])
        if e != ok { ret false }
        while i < k {
            if !near(got[i], want[i], 0.000001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    ret false
}
'''

emit("ml_linear_robust",
     "// `e.ml.linear` regularized and robust regression against scikit-learn and statsmodels (scripts/gen_linear_test.py): elastic net,\n"
     "// polynomial features, quantile regression (the HiGHS LP optimum) and Huber M-estimation.",
     ["use e.ml.linear as linear"], HARNESS, lines, "ml linear robust ok")
