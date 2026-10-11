"""Vectors for tests/selfhost/fixtures/link/algo_stat_infer (L056).

Oracle: SciPy (norm, t, nct, chi2, levene, bartlett, chi2_contingency,
tukey_hsd, studentized_range, mode) and NumPy (cov with aweights, weighted
quantile). Run from the repo root; python -m pip install numpy scipy.
"""
import sys
from pathlib import Path

import numpy as np
from scipy import stats

sys.path.insert(0, str(Path(__file__).parent))
from fixture_vectors import emit, fmt

rng = np.random.default_rng(56)
lines = []


def r(v):
    return repr(float(v))


# z-tests (known sigma), then proportions.
for n, mu, sigma in [(5, 0.0, 1.0), (12, 3.0, 2.0), (30, 10.0, 0.5), (8, -1.0, 4.0)]:
    x = np.round(rng.normal(mu + 0.3 * sigma, sigma, n), 4)
    z = (x.mean() - mu) / (sigma / np.sqrt(n))
    p = 2 * stats.norm.sf(abs(z))
    lines.append(f"z1|{r(mu)} {r(sigma)}|{fmt(x)}|{r(z)} {r(p)}")
for na, nb, sa, sb in [(6, 9, 1.0, 2.0), (15, 15, 3.0, 3.0), (4, 20, 0.7, 1.9)]:
    a = np.round(rng.normal(1.0, sa, na), 4)
    b = np.round(rng.normal(0.0, sb, nb), 4)
    z = (a.mean() - b.mean()) / np.sqrt(sa * sa / na + sb * sb / nb)
    lines.append(f"z2|{r(sa)} {r(sb)}|{fmt(a)}|{fmt(b)}|{r(z)} {r(2 * stats.norm.sf(abs(z)))}")
from statsmodels.stats.proportion import proportions_ztest
for x, n, p0 in [(45, 100, 0.5), (7, 40, 0.1), (130, 200, 0.6), (3, 10, 0.5)]:
    z, p = proportions_ztest(x, n, p0, prop_var=p0)
    lines.append(f"p1|{x} {n} {r(p0)}|{r(z)} {r(p)}")
for x1, n1, x2, n2 in [(30, 100, 45, 110), (5, 50, 12, 60), (200, 400, 180, 390)]:
    z, p = proportions_ztest([x1, x2], [n1, n2])
    lines.append(f"p2|{x1} {n1} {x2} {n2}|{r(z)} {r(p)}")

# chi-squared independence.
tables = [
    ((2, 2), [12, 5, 7, 20]),
    ((2, 2), [30, 10, 15, 25]),
    ((2, 3), [10, 20, 30, 6, 9, 17]),
    ((3, 3), [20, 15, 10, 12, 18, 25, 8, 9, 30]),
    ((4, 2), [5, 9, 14, 10, 21, 17, 2, 8]),
]
for (rows, cols), cells in tables:
    t = np.array(cells, float).reshape(rows, cols)
    for yates in (False, True):
        chi, p, dof, exp = stats.chi2_contingency(t, correction=yates)
        v = stats.contingency.association(t.astype(int), method="cramer", correction=False)
        lines.append(
            f"chi|{rows} {cols} {int(yates)}|{fmt(cells)}|{r(chi)} {r(p)} {dof}|{fmt(exp.flatten())}|{r(v)}")

# Levene / Bartlett.
def groups(sizes, scales, shifts):
    out = []
    for n, s, m in zip(sizes, scales, shifts):
        out.append(np.round(rng.normal(m, s, n) + (rng.random(n) < 0.15) * s * 3, 3))
    return out

for sizes, scales in [([8, 9, 10], [1.0, 1.0, 1.0]), ([7, 12, 9], [1.0, 2.5, 0.6]), ([15, 15], [1.0, 3.0]),
                      ([6, 7, 8, 9], [0.5, 1.5, 1.0, 2.2])]:
    g = groups(sizes, scales, [0.0] * len(sizes))
    data = np.concatenate(g)
    sz = " ".join(str(s) for s in sizes)
    for center, code in (("mean", 0), ("median", 1), ("trimmed", 2)):
        if center == "trimmed":
            tr = [s for s in sizes]
        w, p = stats.levene(*g, center=center)
        lines.append(f"lev|{code}|{sz}|{fmt(data)}|{r(w)} {r(p)}")
    chi, p = stats.bartlett(*g)
    lines.append(f"bar|{sz}|{fmt(data)}|{r(chi)} {r(p)}")

# Studentized range cdf and quantile.
for q, k, df in [(1.0, 2, 5), (3.0, 3, 10), (3.5, 3, 12), (4.0, 4, 20), (5.2, 5, 30), (2.0, 6, 8),
                 (6.5, 10, 60), (3.3, 3, 120), (7.0, 8, 15), (0.5, 2, 3), (3.9, 4, 1000), (4.4, 7, 2)]:
    lines.append(f"srcdf|{r(q)} {k} {df}|{r(stats.studentized_range.cdf(q, k, df))}")
for p, k, df in [(0.95, 3, 12), (0.99, 4, 20), (0.9, 5, 30), (0.95, 2, 40), (0.5, 6, 10)]:
    lines.append(f"srq|{r(p)} {k} {df}|{r(stats.studentized_range.ppf(p, k, df))}")

# Tukey HSD.
for sizes, shifts in [([6, 6, 6], [0.0, 1.0, 2.5]), ([5, 8, 7, 6], [0.0, 0.2, 1.4, 1.5]), ([9, 11], [0.0, 1.0])]:
    g = [np.round(rng.normal(m, 1.0, n), 3) for n, m in zip(sizes, shifts)]
    data = np.concatenate(g)
    res = stats.tukey_hsd(*g)
    ci = res.confidence_interval(confidence_level=0.95)
    k = len(sizes)
    mse = sum(((x - x.mean()) ** 2).sum() for x in g) / (len(data) - k)
    out = []
    for i in range(k):
        for j in range(i + 1, k):
            diff = g[i].mean() - g[j].mean()
            se = np.sqrt(mse / 2 * (1 / sizes[i] + 1 / sizes[j]))
            q = diff / se
            assert abs(stats.studentized_range.sf(abs(q), k, len(data) - k) - res.pvalue[i, j]) < 1e-9
            assert abs(res.statistic[i, j] - diff) < 1e-12
            out.append(f"{r(diff)} {r(q)} {r(res.pvalue[i, j])} {r(ci.low[i, j])} {r(ci.high[i, j])}")
    lines.append(f"tuk|0.95|{' '.join(str(s) for s in sizes)}|{fmt(data)}|{' '.join(out)}")

# Noncentral t, power and sample size.
for t, df, nc in [(1.5, 10, 1.0), (-0.5, 5, 0.8), (2.5, 20, 2.0), (0.0, 9, 1.2), (4.0, 30, 3.5), (1.0, 3, -1.5),
                  (6.0, 50, 5.0), (2.2, 8, 0.0)]:
    lines.append(f"nct|{r(t)} {df} {r(nc)}|{r(stats.nct.cdf(t, df, nc))}")


def power_t(design, n, d, alpha, two):
    if design == 2:
        df, nc = 2 * n - 2, d * np.sqrt(n / 2)
    else:
        df, nc = n - 1, d * np.sqrt(n)
    if two:
        c = stats.t.ppf(1 - alpha / 2, df)
        return stats.nct.sf(c, df, nc) + stats.nct.cdf(-c, df, nc)
    c = stats.t.ppf(1 - alpha, df)
    return stats.nct.sf(c, df, nc)


def power_z(design, n, d, alpha, two):
    sh = d * np.sqrt(n / 2) if design == 2 else d * np.sqrt(n)
    if two:
        c = stats.norm.ppf(1 - alpha / 2)
        return stats.norm.sf(c - sh) + stats.norm.cdf(-c - sh)
    return stats.norm.sf(stats.norm.ppf(1 - alpha) - sh)


def smallest(fn, lo, design, d, alpha, pw, two):
    n = lo
    while fn(design, n, d, alpha, two) < pw:
        n += 1
    return n


for design in (0, 2):
    for n, d, alpha, two in [(10, 0.5, 0.05, 1), (25, 0.8, 0.05, 1), (50, 0.3, 0.01, 1), (15, 0.6, 0.05, 0),
                             (8, 1.2, 0.1, 1), (100, 0.2, 0.05, 1)]:
        lines.append(f"pwt|{design} {n} {r(d)} {r(alpha)} {int(two)}|{r(power_t(design, n, d, alpha, two))}")
        lines.append(f"pwz|{design} {n} {r(d)} {r(alpha)} {int(two)}|{r(power_z(design, n, d, alpha, two))}")
    for d, alpha, pw, two in [(0.5, 0.05, 0.8, 1), (0.8, 0.05, 0.9, 1), (0.3, 0.05, 0.8, 0), (1.0, 0.01, 0.95, 1)]:
        lines.append(f"szt|{design} {r(d)} {r(alpha)} {r(pw)} {int(two)}|{smallest(power_t, 2, design, d, alpha, pw, two)}")
        lines.append(f"szz|{design} {r(d)} {r(alpha)} {r(pw)} {int(two)}|{smallest(power_z, 1, design, d, alpha, pw, two)}")

# Mode, weighted descriptives.
for data in ([3, 1, 2, 3, 2, 3, 1], [5, 5, 4, 4, 9], [1.5], [2, 2, 2, 2], [0.5, 1.5, 1.5, 0.5, -2.0, 7.0, 7.0]):
    m = stats.mode(np.array(data, float), keepdims=False)
    lines.append(f"mode|{fmt(data)}|{r(m.mode)} {int(m.count)}")
for n in (6, 11, 25):
    x = np.round(rng.normal(5, 2, n), 3)
    w = np.round(rng.random(n) * 3 + 0.2, 3)
    mean = np.average(x, weights=w)
    vb = np.cov(x, aweights=w, bias=True)
    vu = np.cov(x, aweights=w)
    qs = [0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
    qv = [np.quantile(x, q, weights=w, method="inverted_cdf") for q in qs]
    lines.append(f"wm|{fmt(x)}|{fmt(w)}|{r(mean)} {r(vb)} {r(vu)}")
    lines.append(f"wq|{fmt(x)}|{fmt(w)}|{fmt(qs)}|{fmt(qv)}")

HARNESS = r'''
fn center_of(code: usize) -> infer.Center {
    if code == 0usize { ret .Mean }
    if code == 1usize { ret .Median }
    ret .Trimmed
}

fn design_of(code: usize) -> infer.Design {
    if code == 0usize { ret .OneSample }
    if code == 1usize { ret .Paired }
    ret .TwoSample
}

fn sizes_of(field: str, out: []usize) -> usize {
    var tmp: [16]f64 = zero
    let n = nums(field, tmp[..])
    var i = 0usize
    while i < n {
        out[i] = usize(tmp[i])
        i += 1usize
    }
    ret n
}

fn same(o: infer.Outcome, want_stat: f64, want_p: f64) -> bool {
    ret near(o.statistic, want_stat, 0.000000001f64) && near(o.p_value, want_p, 0.000000001f64)
}

fn check(f: []str, nf: usize) -> bool {
    let op = f[0usize]
    var data: [160]f64 = zero
    var other: [160]f64 = zero
    var head: [8]f64 = zero
    var want: [160]f64 = zero
    var scratch: [400]f64 = zero
    var sizes: [16]usize = zero
    if str.eq(op, "z1") {
        let h = nums(f[1usize], head[..])
        let n = nums(f[2usize], data[..])
        load(f[3usize], want[..])
        let (o, e) = infer.z_test(data[..n], head[0usize], head[1usize])
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "z2") {
        let h = nums(f[1usize], head[..])
        let na = nums(f[2usize], data[..])
        let nb = nums(f[3usize], other[..])
        load(f[4usize], want[..])
        let (o, e) = infer.z_test_two(data[..na], other[..nb], head[0usize], head[1usize])
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "p1") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        let (o, e) = infer.proportion_z(u64(head[0usize]), u64(head[1usize]), head[2usize])
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "p2") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        let (o, e) = infer.proportion_z_two(u64(head[0usize]), u64(head[1usize]), u64(head[2usize]), u64(head[3usize]))
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "chi") {
        let h = nums(f[1usize], head[..])
        let cells = nums(f[2usize], data[..])
        load(f[3usize], want[..])
        let ne = nums(f[4usize], other[..])
        let rows = usize(head[0usize])
        let cols = usize(head[1usize])
        var expected: [64]f64 = zero
        let (o, e) = infer.chi_squared_independence(data[..cells], rows, cols, head[2usize] != 0.0f64, expected[..])
        if e != ok || !same(o, want[0usize], want[1usize]) || o.df != want[2usize] { ret false }
        var i = 0usize
        var total = 0.0f64
        while i < ne {
            if !near(expected[i], other[i], 0.000000001f64) { ret false }
            i += 1usize
        }
        i = 0usize
        while i < cells {
            total += data[i]
            i += 1usize
        }
        // Cramer's V is defined on the uncorrected statistic, so recompute it.
        var uncorrected: [64]f64 = zero
        let (u, ue) = infer.chi_squared_independence(data[..cells], rows, cols, false, uncorrected[..])
        let wv = nums(f[5usize], head[..])
        ret ue == ok && near(infer.cramers_v(u.statistic, total, rows, cols), head[0usize], 0.000000001f64)
    }
    if str.eq(op, "lev") {
        let h = nums(f[1usize], head[..])
        let k = sizes_of(f[2usize], sizes[..])
        let n = nums(f[3usize], data[..])
        load(f[4usize], want[..])
        let (o, e) = infer.levene(data[..n], sizes[..k], center_of(usize(head[0usize])), scratch[..])
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "bar") {
        let k = sizes_of(f[1usize], sizes[..])
        let n = nums(f[2usize], data[..])
        load(f[3usize], want[..])
        let (o, e) = infer.bartlett(data[..n], sizes[..k])
        ret e == ok && same(o, want[0usize], want[1usize])
    }
    if str.eq(op, "srcdf") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        ret near(infer.studentized_range_cdf(head[0usize], head[1usize], head[2usize]), want[0usize], 0.0000001f64)
    }
    if str.eq(op, "srq") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        ret near(infer.studentized_range_quantile(head[0usize], head[1usize], head[2usize]), want[0usize], 0.000001f64)
    }
    if str.eq(op, "tuk") {
        let h = nums(f[1usize], head[..])
        let k = sizes_of(f[2usize], sizes[..])
        let n = nums(f[3usize], data[..])
        let w = nums(f[4usize], want[..])
        var out: [16]infer.Pair = zero
        let (count, e) = infer.tukey_hsd(data[..n], sizes[..k], head[0usize], out[..])
        if e != ok || count * 5usize != w { ret false }
        var i = 0usize
        while i < count {
            let b = i * 5usize
            if !near(out[i].mean_diff, want[b], 0.000000001f64) || !near(out[i].statistic, want[b + 1usize], 0.000001f64) { ret false }
            if !near(out[i].p_value, want[b + 2usize], 0.0000001f64) { ret false }
            if !near(out[i].ci_low, want[b + 3usize], 0.00001f64) || !near(out[i].ci_high, want[b + 4usize], 0.00001f64) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(op, "nct") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        ret near(infer.noncentral_t_cdf(head[0usize], head[1usize], head[2usize]), want[0usize], 0.0000001f64)
    }
    if str.eq(op, "pwt") || str.eq(op, "pwz") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        let design = design_of(usize(head[0usize]))
        let two = head[4usize] != 0.0f64
        if str.eq(op, "pwt") { ret near(infer.power_t(design, usize(head[1usize]), head[2usize], head[3usize], two), want[0usize], 0.0000001f64) }
        ret near(infer.power_z(design, usize(head[1usize]), head[2usize], head[3usize], two), want[0usize], 0.0000001f64)
    }
    if str.eq(op, "szt") || str.eq(op, "szz") {
        let h = nums(f[1usize], head[..])
        load(f[2usize], want[..])
        let design = design_of(usize(head[0usize]))
        let two = head[4usize] != 0.0f64
        if str.eq(op, "szt") {
            let (n, e) = infer.sample_size_t(design, head[1usize], head[2usize], head[3usize], two)
            ret e == ok && n == usize(want[0usize])
        }
        let (n, e) = infer.sample_size_z(design, head[1usize], head[2usize], head[3usize], two)
        ret e == ok && n == usize(want[0usize])
    }
    if str.eq(op, "mode") {
        let n = nums(f[1usize], data[..])
        load(f[2usize], want[..])
        let (m, c, e) = infer.mode(data[..n], scratch[..])
        ret e == ok && m == want[0usize] && c == usize(want[1usize])
    }
    if str.eq(op, "wm") {
        let n = nums(f[1usize], data[..])
        load(f[2usize], other[..n])
        load(f[3usize], want[..])
        let (m, e1) = infer.weighted_mean(data[..n], other[..n])
        let (vb, e2) = infer.weighted_variance(data[..n], other[..n], false)
        let (vu, e3) = infer.weighted_variance(data[..n], other[..n], true)
        ret e1 == ok && e2 == ok && e3 == ok && near(m, want[0usize], 0.000000001f64) && near(vb, want[1usize], 0.000000001f64) && near(vu, want[2usize], 0.000000001f64)
    }
    if str.eq(op, "wq") {
        let n = nums(f[1usize], data[..])
        load(f[2usize], other[..n])
        var ps: [16]f64 = zero
        var vs: [16]f64 = zero
        let np = nums(f[3usize], ps[..])
        load(f[4usize], vs[..])
        var order: [160]usize = zero
        var i = 0usize
        while i < np {
            let (q, e) = infer.weighted_quantile(data[..n], other[..n], ps[i], order[..])
            if e != ok || q != vs[i] { ret false }
            i += 1usize
        }
        ret true
    }
    ret false
}
'''

emit("algo_stat_infer",
     "// `e.algo.stat.infer` against SciPy, statsmodels and NumPy (scripts/gen_infer_test.py): z and proportion tests, chi-squared\n"
     "// independence with Yates and Cramer's V, Levene (three centres) and Bartlett, the studentized range cdf and quantile, Tukey\n"
     "// HSD with confidence intervals, noncentral t, power and sample size, mode and weighted descriptives.",
     ["use e.algo.stat.infer as infer"], HARNESS, lines, "algo stat infer ok")
