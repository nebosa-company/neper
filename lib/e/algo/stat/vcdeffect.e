// R vcd and effectsize, the point estimates: vcd `assocstats` (likelihood-ratio and Pearson chi-squares, phi for a
// 2 by 2 table, the contingency coefficient, Cramer's V) and `Kappa` (unweighted and weighted with its
// asymptotic standard errors); effectsize `cohens_d` (pooled sd), `hedges_g` (exact small-sample factor),
// `glass_delta` (adjusted, with the second group as the control), `rank_biserial` and `cliffs_delta`, and the
// one-way `eta_squared`, `omega_squared` and `epsilon_squared`.
//
// Not here: the confidence intervals (noncentral t and F inversions), the interpret rules, goodfit, oddsratio,
// CMHtest, woolf_test and the Mantel-Haenszel helpers, the other designs of the ANOVA effect sizes.

use e.math
use e.math.nmath as nm
use e.mem

type Assoc = struct { lr: f64, pearson: f64, df: f64, p_lr: f64, p_pearson: f64, phi: f64, contingency: f64, cramer: f64 }

// r by c table of counts, row-major
fn assocstats(a: *mem.Arena, t: []const f64, r: usize, c: usize) -> (Assoc, err) {
    var res: Assoc = zero
    let (rs, e1) = mem.alloc[f64](a, r)
    let (cs, e2) = mem.alloc[f64](a, c)
    if e1 != ok || e2 != ok { ret (res, e1) }
    var n = 0.0f64
    var i = 0usize
    while i < r {
        rs[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < c {
        cs[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < r {
        j = 0usize
        while j < c {
            rs[i] += t[i * c + j]
            cs[j] += t[i * c + j]
            n += t[i * c + j]
            j += 1usize
        }
        i += 1usize
    }
    var lr = 0.0f64
    var pe = 0.0f64
    i = 0usize
    while i < r {
        j = 0usize
        while j < c {
            let e = rs[i] * cs[j] / n
            let o = t[i * c + j]
            if o > 0.0f64 { lr += 2.0f64 * o * math.log[f64](o / e) }
            pe += (o - e) * (o - e) / e
            j += 1usize
        }
        i += 1usize
    }
    res.lr = lr
    res.pearson = pe
    res.df = f64((r - 1usize) * (c - 1usize))
    res.p_lr = nm.pchisq(lr, res.df, false, false)
    res.p_pearson = nm.pchisq(pe, res.df, false, false)
    if r == 2usize && c == 2usize { res.phi = math.sqrt[f64](pe / n) } else { res.phi = 0.0f64 / 0.0f64 }
    res.contingency = math.sqrt[f64](pe / (pe + n))
    var m = r
    if c < m { m = c }
    res.cramer = math.sqrt[f64](pe / (n * f64(m - 1usize)))
    ret (res, ok)
}

fn kappa_std(p: []const f64, pc: f64, kw: f64, w: []const f64, k: usize, rowf: []const f64, colf: []const f64, n: f64) -> f64 {
    // colSums(p) and rowSums(p) as in vcd: the bracket weights
    var sum = 0.0f64
    var i = 0usize
    while i < k {
        var wc = 0.0f64
        var wr = 0.0f64
        var l = 0usize
        while l < k {
            wc += w[i * k + l] * colf[l]
            l += 1usize
        }
        var j = 0usize
        while j < k {
            wr = 0.0f64
            l = 0usize
            while l < k {
                wr += w[j * k + l] * rowf[l]
                l += 1usize
            }
            // sweep(sweep(W, 1, W %*% colSums(p) (1 - kw)), 2, W %*% rowSums(p) (1 - kw)): W[i, j] - wc_i (1 - kw) - wr_j (1 - kw)
            let v = w[i * k + j] - wc * (1.0f64 - kw) - wr * (1.0f64 - kw)
            sum += p[i * k + j] * v * v
            j += 1usize
        }
        i += 1usize
    }
    let num = sum - (kw - pc * (1.0f64 - kw)) * (kw - pc * (1.0f64 - kw))
    ret math.sqrt[f64](num / ((1.0f64 - pc) * (1.0f64 - pc)) / n)
}

// Kappa(x, weights): out = (unweighted, ASE, weighted, ASE); weights 0 equal spacing, 1 Fleiss-Cohen
fn kappa(a: *mem.Arena, t: []const f64, k: usize, wtype: u8, out: []f64) -> err {
    let (p, e1) = mem.alloc[f64](a, k * k)
    let (w, e2) = mem.alloc[f64](a, k * k)
    let (rowf, e3) = mem.alloc[f64](a, k)
    let (colf, e4) = mem.alloc[f64](a, k)
    let (id, e5) = mem.alloc[f64](a, k * k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
    var n = 0.0f64
    var i = 0usize
    while i < k * k {
        n += t[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        rowf[i] = 0.0f64
        colf[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            p[i * k + j] = t[i * k + j] / n
            rowf[i] += p[i * k + j]
            colf[j] += p[i * k + j]
            var d = f64(i) - f64(j)
            if d < 0.0f64 { d = 0.0f64 - d }
            d = d / f64(k - 1usize)
            if wtype == 0u8 { w[i * k + j] = 1.0f64 - d } else { w[i * k + j] = 1.0f64 - d * d }
            if i == j { id[i * k + j] = 1.0f64 } else { id[i * k + j] = 0.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var po = 0.0f64
    var pc = 0.0f64
    var pow_ = 0.0f64
    var pcw = 0.0f64
    i = 0usize
    while i < k {
        po += p[i * k + i]
        pc += colf[i] * rowf[i]
        var j = 0usize
        while j < k {
            pow_ += w[i * k + j] * p[i * k + j]
            pcw += w[i * k + j] * colf[i] * rowf[j]
            j += 1usize
        }
        i += 1usize
    }
    let ku = (po - pc) / (1.0f64 - pc)
    let kw = (pow_ - pcw) / (1.0f64 - pcw)
    out[0usize] = ku
    out[1usize] = kappa_std(p, pc, ku, id, k, rowf, colf, n)
    out[2usize] = kw
    out[3usize] = kappa_std(p, pcw, kw, w, k, rowf, colf, n)
    ret ok
}

fn mean_var(x: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret (m, v / (n - 1.0f64))
}

// the small-sample factor of Hedges: Gamma(df / 2) / (sqrt(df / 2) Gamma((df - 1) / 2))
fn hedges_j(df: f64) -> f64 { ret nm.gammafn(df / 2.0f64) / (math.sqrt[f64](df / 2.0f64) * nm.gammafn((df - 1.0f64) / 2.0f64)) }

// out = (cohens_d, hedges_g, glass_delta adjusted with y as control)
fn smd(x: []const f64, y: []const f64, out: []f64) {
    let n1 = f64(x.len)
    let n2 = f64(y.len)
    let (m1, v1) = mean_var(x)
    let (m2, v2) = mean_var(y)
    let sp = math.sqrt[f64](((n1 - 1.0f64) * v1 + (n2 - 1.0f64) * v2) / (n1 + n2 - 2.0f64))
    let d = (m1 - m2) / sp
    out[0usize] = d
    out[1usize] = d * hedges_j(n1 + n2 - 2.0f64)
    out[2usize] = (m1 - m2) / math.sqrt[f64](v2) * hedges_j(n2 - 1.0f64)
}

// rank_biserial(x, y) = cliffs_delta(x, y): (#x > y - #x < y) / (n1 n2)
fn cliffs(x: []const f64, y: []const f64) -> f64 {
    var g = 0.0f64
    var l = 0.0f64
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < y.len {
            if x[i] > y[j] { g += 1.0f64 } else if x[i] < y[j] { l += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret (g - l) / (f64(x.len) * f64(y.len))
}

// one-way eta, omega and epsilon squared from the group sizes and observations (group g is y[start_g .. start_g + n_g])
fn anova_effects(y: []const f64, sizes: []const usize, out: []f64) {
    var gm = 0.0f64
    var i = 0usize
    while i < y.len {
        gm += y[i]
        i += 1usize
    }
    gm = gm / f64(y.len)
    var sst = 0.0f64
    i = 0usize
    while i < y.len {
        sst += (y[i] - gm) * (y[i] - gm)
        i += 1usize
    }
    var ssb = 0.0f64
    var at = 0usize
    var g = 0usize
    while g < sizes.len {
        var s = 0.0f64
        var j = 0usize
        while j < sizes[g] {
            s += y[at + j]
            j += 1usize
        }
        let mg = s / f64(sizes[g])
        ssb += f64(sizes[g]) * (mg - gm) * (mg - gm)
        at += sizes[g]
        g += 1usize
    }
    let dfb = f64(sizes.len - 1usize)
    let dfw = f64(y.len - sizes.len)
    let msw = (sst - ssb) / dfw
    out[0usize] = ssb / sst
    // effectsize truncates the bias-corrected estimates at zero
    out[1usize] = (ssb - dfb * msw) / (sst + msw)
    out[2usize] = (ssb - dfb * msw) / sst
    if out[1usize] < 0.0f64 { out[1usize] = 0.0f64 }
    if out[2usize] < 0.0f64 { out[2usize] = 0.0f64 }
}
