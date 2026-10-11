"""Vectors for tests/selfhost/fixtures/link/ml_multivariate (L058).

Oracle: scikit-learn (LinearDiscriminantAnalysis svd/lsqr, QuadraticDiscriminantAnalysis,
FactorAnalysis with and without varimax), statsmodels (MANOVA, CanCorr) and a
SciPy whitening/SVD canonical correlation. Run from the repo root.
"""
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import scipy.linalg as sl
from scipy import stats
from sklearn.decomposition import FactorAnalysis
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis, QuadraticDiscriminantAnalysis
from statsmodels.multivariate.manova import MANOVA

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit, fmt

warnings.filterwarnings("ignore")
rng = np.random.default_rng(58)
lines = []


def r(v):
    return repr(float(v))


def signs(rows):
    rows = np.array(rows, float)
    for i in range(rows.shape[0]):
        j = np.argmax(np.abs(rows[i]))
        if rows[i, j] < 0:
            rows[i] = -rows[i]
    return rows


# Discriminant analysis.
for n_per, d, K, spread in [(20, 2, 2, 2.0), (15, 3, 3, 1.5), (25, 4, 3, 1.2), (12, 2, 4, 1.8)]:
    centers = rng.normal(0, spread, (K, d))
    xs, ys = [], []
    for k in range(K):
        a = rng.normal(0, 1, (d, d))
        cov = a @ a.T * 0.3 + np.eye(d)
        xs.append(rng.multivariate_normal(centers[k], cov, n_per))
        ys += [k] * n_per
    x = np.round(np.vstack(xs), 4)
    y = np.array(ys)
    q = np.round(rng.normal(0, spread, (6, d)), 4)
    models = [
        (False, False, 0.0, LinearDiscriminantAnalysis(solver="svd")),
        (False, False, 0.0, LinearDiscriminantAnalysis(solver="lsqr")),
        (True, False, 0.0, QuadraticDiscriminantAnalysis()),
        (True, False, 0.3, QuadraticDiscriminantAnalysis(reg_param=0.3)),
    ]
    for quad, unb, reg, m in models:
        m.fit(x, y)
        prob = m.predict_proba(q)
        lines.append(f"disc|{x.shape[0]} {d} {K} {int(quad)} {int(unb)} {r(reg)}|{fmt(x.flatten())}|"
                     f"{' '.join(str(v) for v in y)}|{fmt(q.flatten())}|{fmt(prob.flatten())}")

    # The unbiased (n - K, n_k - 1) variants have no scikit-learn counterpart: a direct NumPy evaluation.
    for quad, reg in ((False, 0.0), (True, 0.0), (True, 0.25)):
        mu = np.array([x[y == k].mean(0) for k in range(K)])
        pri = np.array([(y == k).mean() for k in range(K)])
        pooled = sum((x[y == k] - mu[k]).T @ (x[y == k] - mu[k]) for k in range(K)) / (len(x) - K)
        sc = np.zeros((len(q), K))
        for k in range(K):
            cov = np.cov(x[y == k].T, ddof=1) if quad else pooled
            if quad:
                cov = (1 - reg) * cov + reg * np.eye(d)
            inv = np.linalg.inv(cov)
            ld = np.linalg.slogdet(cov)[1]
            for i in range(len(q)):
                dv = q[i] - mu[k]
                sc[i, k] = np.log(pri[k]) - 0.5 * (dv @ inv @ dv + ld)
        e = np.exp(sc - sc.max(1, keepdims=True))
        prob = e / e.sum(1, keepdims=True)
        lines.append(f"disc|{x.shape[0]} {d} {K} {int(quad)} 1 {r(reg)}|{fmt(x.flatten())}|"
                     f"{' '.join(str(v) for v in y)}|{fmt(q.flatten())}|{fmt(prob.flatten())}")

# Factor analysis.
for n, d, c in [(150, 6, 2), (200, 8, 3), (120, 5, 1)]:
    load = rng.normal(0, 1, (c, d))
    f = rng.normal(0, 1, (n, c))
    x = np.round(f @ load + rng.normal(0, 0.6, (n, d)) * rng.uniform(0.5, 1.5, d) + rng.normal(0, 2, d), 4)
    for rot in (None, "varimax"):
        fa = FactorAnalysis(n_components=c, tol=1e-9, max_iter=2000, svd_method="lapack", rotation=rot).fit(x)
        comp = signs(fa.components_)
        lines.append(f"fa|{n} {d} {c} {int(rot is not None)} {int(fa.n_iter_)}|{fmt(x.flatten())}|"
                     f"{fmt(comp.flatten())}|{fmt(fa.noise_variance_)}|{r(fa.loglike_[-1])}")

# Canonical correlation.
for n, p, q in [(60, 3, 2), (80, 2, 4), (100, 4, 4), (50, 3, 3)]:
    z = rng.normal(0, 1, (n, 2))
    x = np.round(z @ rng.normal(0, 1, (2, p)) + rng.normal(0, 1, (n, p)), 4)
    y = np.round(z @ rng.normal(0, 1, (2, q)) + rng.normal(0, 1, (n, q)), 4)
    xc, yc = x - x.mean(0), y - y.mean(0)
    sxx, syy = xc.T @ xc / (n - 1), yc.T @ yc / (n - 1)
    sxy = xc.T @ yc / (n - 1)
    wx = np.real(sl.fractional_matrix_power(sxx, -0.5))
    wy = np.real(sl.fractional_matrix_power(syy, -0.5))
    u, s, vt = np.linalg.svd(wx @ sxy @ wy)
    k = min(p, q)
    s = s[:k]
    a = (wx @ u[:, :k]).T
    b = (wy @ vt.T[:, :k]).T
    # Orient the y weights so the variates correlate positively (the library does the same),
    # then normalise the x row sign.
    for i in range(k):
        if np.sum((xc @ a[i]) * (yc @ b[i])) < 0:
            b[i] = -b[i]
    # normalise x sign; flip y with it
    for i in range(k):
        j = np.argmax(np.abs(a[i]))
        if a[i, j] < 0:
            a[i] = -a[i]
            b[i] = -b[i]
    # y rows: largest entry positive unless that breaks correlation sign -> library normalises y first, then
    # re-orients by correlation; reproduce: normalise y, then orient to x.
    b2 = signs(b)
    for i in range(k):
        if np.sum((xc @ a[i]) * (yc @ b2[i])) < 0:
            b2[i] = -b2[i]
    stat = []
    for first in range(k):
        chi = -(n - 1 - (p + q + 1) / 2) * np.sum(np.log(1 - s[first:] ** 2))
        df = (p - first) * (q - first)
        stat.append(f"{r(chi)} {df} {r(stats.chi2.sf(chi, df))}")
    lines.append(f"cca|{n} {p} {q}|{fmt(x.flatten())}|{fmt(y.flatten())}|{fmt(s)}|{fmt(a.flatten())}|{fmt(b2.flatten())}|"
                 + " ".join(stat))

# MANOVA.
for sizes, p, shift in [([12, 15, 10], 3, 0.8), ([20, 20], 2, 0.5), ([10, 11, 12, 9], 3, 0.6), ([14, 14, 14], 4, 0.4)]:
    labels, rows = [], []
    for g, ng in enumerate(sizes):
        mean = rng.normal(0, shift, p)
        a = rng.normal(0, 1, (p, p))
        cov = a @ a.T * 0.2 + np.eye(p)
        rows.append(rng.multivariate_normal(mean, cov, ng))
        labels += [g] * ng
    x = np.round(np.vstack(rows), 4)
    df = pd.DataFrame(x, columns=[f"y{i}" for i in range(p)])
    df["g"] = labels
    res = MANOVA.from_formula(" + ".join(f"y{i}" for i in range(p)) + " ~ C(g)", data=df).mv_test()
    tab = res.results["C(g)"]["stat"]
    out = []
    for name in ["Wilks' lambda", "Pillai's trace", "Hotelling-Lawley trace", "Roy's greatest root"]:
        row = tab.loc[name]
        out.append(f"{r(row['Value'])} {r(row['F Value'])} {r(row['Num DF'])} {r(row['Den DF'])} {r(row['Pr > F'])}")
    lines.append(f"man|{x.shape[0]} {p} {len(sizes)}|{fmt(x.flatten())}|{' '.join(str(v) for v in labels)}|{' '.join(out)}")

HARNESS = r'''
fn labels_of(field: str, out: []usize) -> usize {
    var tmp: [320]f64 = zero
    let n = nums(field, tmp[..])
    var i = 0usize
    while i < n {
        out[i] = usize(tmp[i])
        i += 1usize
    }
    ret n
}

fn close_rows(got: []const f64, want: []const f64, count: usize, eps: f64) -> bool {
    var i = 0usize
    while i < count {
        if !near(got[i], want[i], eps) { ret false }
        i += 1usize
    }
    ret true
}

fn check_disc(f: []str, head: []const f64) -> bool {
    let n = usize(head[0usize])
    let d = usize(head[1usize])
    let classes = usize(head[2usize])
    var x: [400]f64 = zero
    var labels: [320]usize = zero
    var query: [40]f64 = zero
    var want: [40]f64 = zero
    var means: [16]f64 = zero
    var priors: [4]f64 = zero
    var factors: [64]f64 = zero
    var log_det: [4]f64 = zero
    var scratch: [64]f64 = zero
    var probs: [4]f64 = zero
    var work: [8]f64 = zero
    let nx = nums(f[2usize], x[..])
    let nl = labels_of(f[3usize], labels[..])
    let nq = nums(f[4usize], query[..])
    let nw = nums(f[5usize], want[..])
    var model = multivariate.Discriminant{ classes: 0usize, features: 0usize, quadratic: false, means: means[..], priors: priors[..], factors: factors[..], log_det: log_det[..] }
    var no_priors: [0]f64 = zero
    let quad = head[3usize] != 0.0f64
    if multivariate.discriminant_fit(x[..nx], labels[..nl], n, d, classes, quad, head[4usize] != 0.0f64, head[5usize], no_priors[..], &model, scratch[..]) != ok { ret false }
    var q = 0usize
    while q < nq / d {
        if multivariate.discriminant_posterior(&model, query[q * d..q * d + d], probs[..], work[..]) != ok { ret false }
        if !close_rows(probs[..], want[q * classes..], classes, 0.000000001f64) { ret false }
        let (best, e) = multivariate.discriminant_predict(&model, query[q * d..q * d + d], probs[..], work[..])
        var arg = 0usize
        var c = 1usize
        while c < classes {
            if want[q * classes + c] > want[q * classes + arg] { arg = c }
            c += 1usize
        }
        if e != ok || best != arg { ret false }
        q += 1usize
    }
    ret nw == (nq / d) * classes
}

fn check_fa(f: []str, head: []const f64) -> bool {
    let n = usize(head[0usize])
    let d = usize(head[1usize])
    let c = usize(head[2usize])
    var x: [1600]f64 = zero
    var want: [32]f64 = zero
    var noise_want: [8]f64 = zero
    var ll: [1]f64 = zero
    var loadings: [32]f64 = zero
    var noise: [8]f64 = zero
    var scratch: [400]f64 = zero
    var rotate_scratch: [800]f64 = zero
    let nx = nums(f[2usize], x[..])
    load(f[3usize], want[..])
    load(f[4usize], noise_want[..])
    load(f[5usize], ll[..])
    let (fit, e) = multivariate.factor_analysis(x[..nx], n, d, c, 0.000000001f64, 2000u32, loadings[..], noise[..], scratch[..])
    if e != ok { ret false }
    if head[3usize] != 0.0f64 {
        if multivariate.varimax(loadings[..], c, d, 0.000001f64, 100u32, rotate_scratch[..]) != ok { ret false }
    }
    if !near(fit.log_likelihood, ll[0usize], 0.0000001f64) { ret false }
    if !close_rows(noise[..], noise_want[..], d, 0.000001f64) { ret false }
    ret close_rows(loadings[..], want[..], c * d, 0.00001f64)
}

fn check_cca(f: []str, head: []const f64) -> bool {
    let n = usize(head[0usize])
    let p = usize(head[1usize])
    let q = usize(head[2usize])
    var k = p
    if q < k { k = q }
    var x: [800]f64 = zero
    var y: [800]f64 = zero
    var want_r: [8]f64 = zero
    var want_a: [32]f64 = zero
    var want_b: [32]f64 = zero
    var want_t: [32]f64 = zero
    var got_r: [8]f64 = zero
    var got_a: [32]f64 = zero
    var got_b: [32]f64 = zero
    var scratch: [800]f64 = zero
    let nx = nums(f[2usize], x[..])
    let ny = nums(f[3usize], y[..])
    load(f[4usize], want_r[..])
    load(f[5usize], want_a[..])
    load(f[6usize], want_b[..])
    load(f[7usize], want_t[..])
    if multivariate.canonical_correlation(x[..nx], y[..ny], n, p, q, got_r[..], got_a[..], got_b[..], scratch[..]) != ok { ret false }
    if !close_rows(got_r[..], want_r[..], k, 0.000000001f64) { ret false }
    if !close_rows(got_a[..], want_a[..], k * p, 0.0000001f64) { ret false }
    if !close_rows(got_b[..], want_b[..], k * q, 0.0000001f64) { ret false }
    var first = 0usize
    while first < k {
        let (stat, df, pv) = multivariate.canonical_test(got_r[..k], n, p, q, first)
        if !near(stat, want_t[first * 3usize], 0.000001f64) || df != want_t[first * 3usize + 1usize] || !near(pv, want_t[first * 3usize + 2usize], 0.0000001f64) { ret false }
        first += 1usize
    }
    ret true
}

fn same_test(t: multivariate.ManovaTest, w: []const f64) -> bool {
    ret near(t.statistic, w[0usize], 0.000000001f64) && near(t.f, w[1usize], 0.000000001f64) && near(t.df1, w[2usize], 0.000000001f64) && near(t.df2, w[3usize], 0.000000001f64) && near(t.p_value, w[4usize], 0.0000001f64)
}

fn check_man(f: []str, head: []const f64) -> bool {
    let n = usize(head[0usize])
    let p = usize(head[1usize])
    let groups = usize(head[2usize])
    var x: [400]f64 = zero
    var labels: [100]usize = zero
    var want: [20]f64 = zero
    var eigenvalues: [4]f64 = zero
    var scratch: [400]f64 = zero
    let nx = nums(f[2usize], x[..])
    let nl = labels_of(f[3usize], labels[..])
    load(f[4usize], want[..])
    var result: multivariate.Manova = zero
    if multivariate.manova_oneway(x[..nx], labels[..nl], n, p, groups, &result, eigenvalues[..], scratch[..]) != ok { ret false }
    ret same_test(result.wilks, want[0usize..5usize]) && same_test(result.pillai, want[5usize..10usize]) && same_test(result.hotelling, want[10usize..15usize]) && same_test(result.roy, want[15usize..20usize])
}

fn check(f: []str, nf: usize) -> bool {
    var head: [8]f64 = zero
    load(f[1usize], head[..])
    if str.eq(f[0usize], "disc") { ret check_disc(f, head[..]) }
    if str.eq(f[0usize], "fa") { ret check_fa(f, head[..]) }
    if str.eq(f[0usize], "cca") { ret check_cca(f, head[..]) }
    if str.eq(f[0usize], "man") { ret check_man(f, head[..]) }
    ret false
}
'''

emit("ml_multivariate",
     "// `e.ml.multivariate` against scikit-learn, statsmodels and a SciPy whitening-SVD canonical correlation\n"
     "// (scripts/gen_multivariate_test.py): LDA (pooled n - K and n divisors) and QDA with shrinkage posteriors, maximum-likelihood\n"
     "// factor analysis with and without varimax, canonical correlations with Bartlett's tests, and one-way MANOVA.",
     ["use e.ml.multivariate as multivariate"], HARNESS, lines, "ml multivariate ok")
