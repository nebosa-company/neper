// R vcd and effectsize, the point estimates: vcd `assocstats` (likelihood-ratio and Pearson chi-squares, phi for a
// 2 by 2 table, the contingency coefficient, Cramer's V) and `Kappa` (unweighted and weighted with its
// asymptotic standard errors); effectsize `cohens_d` (pooled sd), `hedges_g` (exact small-sample factor),
// `glass_delta` (adjusted, with the second group as the control), `rank_biserial` and `cliffs_delta`, and the
// one-way `eta_squared`, `omega_squared` and `epsilon_squared`.
//
// Not here: the confidence intervals (noncentral t and F inversions), the interpret rules, goodfit, oddsratio,
// CMHtest, woolf_test and the Mantel-Haenszel helpers, the other designs of the ANOVA effect sizes.

use e.math
use e.algo.stat.fdrtool as fdr
use e.algo.stat.rnm as rnmv
use e.math.nmath as nmm
use e.math.nmath_beta as nmb
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem
use e.math.scale as scale
use e.math.nchisq as nc
use e.math.dist as dist

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

// effectsize's confidence interval of a noncentral t statistic: the noncentrality parameters at which pt(t, df, ncp) is 1 - alpha / 2 and alpha / 2, by bisection (effectsize finds them with optim, so the two agree to its tolerance, not to the last digit). out[0] lower, out[1] upper.
fn ncp_t_ci(t: f64, df: f64, level: f64, out: []f64) {
    let alpha = 1.0f64 - level
    var side = 0usize
    while side < 2usize {
        var goal = 1.0f64 - alpha / 2.0f64
        if side == 1usize { goal = alpha / 2.0f64 }
        var lo = t - 60.0f64
        var hi = t + 60.0f64
        var it = 0usize
        while it < 200usize {
            let mid = 0.5f64 * (lo + hi)
            let p = nc.pnt(t, df, mid, true, false)
            if p > goal { lo = mid } else { hi = mid }
            it += 1usize
        }
        out[side] = 0.5f64 * (lo + hi)
        side += 1usize
    }
}

// cohens_d(x, y, ci = level) and hedges_g(x, y, ci = level) pooled: out[0], out[1] the d interval, out[2], out[3] the g interval (the d interval times the Hedges correction), out[4], out[5] the adjusted Glass delta interval.
fn smd_ci(x: []const f64, y: []const f64, level: f64, out: []f64) {
    let n1 = f64(x.len)
    let n2 = f64(y.len)
    let (m1, v1) = mean_var(x)
    let (m2, v2) = mean_var(y)
    let sp = math.sqrt[f64](((n1 - 1.0f64) * v1 + (n2 - 1.0f64) * v2) / (n1 + n2 - 2.0f64))
    let d = (m1 - m2) / sp
    let k = math.sqrt[f64](1.0f64 / n1 + 1.0f64 / n2)
    var nci: [2]f64 = zero
    ncp_t_ci(d / k, n1 + n2 - 2.0f64, level, nci[0usize..2usize])
    let j = hedges_j(n1 + n2 - 2.0f64)
    out[0usize] = nci[0usize] * k
    out[1usize] = nci[1usize] * k
    out[2usize] = out[0usize] * j
    out[3usize] = out[1usize] * j
    // glass_delta(x, y, ci = level) adjusted: the sd of y, df n2 - 1, noncentrality scaled by sqrt(1 / n2 + v1 / (n1 v2))
    let hn = 1.0f64 / n2 + v1 / (n1 * v2)
    let tg = (m1 - m2) / (math.sqrt[f64](v2) * math.sqrt[f64](hn))
    ncp_t_ci(tg, n2 - 1.0f64, level, nci[0usize..2usize])
    let jg = hedges_j(n2 - 1.0f64)
    out[4usize] = nci[0usize] * math.sqrt[f64](hn) * jg
    out[5usize] = nci[1usize] * math.sqrt[f64](hn) * jg
}

// effectsize's .get_ncp_F: the noncentrality parameters at which pf(f, df, dfe, ncp) is alpha / 2 and 1 - alpha / 2, sorted, bisected on `pnf`; the upper is set to 0 when f is at or below the central alpha / 2
// quantile and the lower to 0 when at or below the central 1 - alpha / 2 quantile, as effectsize does after its optim. out[0] lower, out[1] upper.
fn ncp_f_ci(f: f64, df: f64, dfe: f64, level: f64, out: []f64) {
    let alpha = 1.0f64 - level
    var r: [2]f64 = zero
    var side = 0usize
    while side < 2usize {
        var goal = alpha / 2.0f64
        if side == 1usize { goal = 1.0f64 - alpha / 2.0f64 }
        var lo = 0.0f64
        var hi = 1.0e5f64
        if nc.pnf(f, df, dfe, 0.0f64, true, false) <= goal {
            hi = 0.0f64
        }
        var it = 0usize
        while it < 200usize {
            let mid = 0.5f64 * (lo + hi)
            if nc.pnf(f, df, dfe, mid, true, false) > goal { lo = mid } else { hi = mid }
            it += 1usize
        }
        r[side] = 0.5f64 * (lo + hi)
        side += 1usize
    }
    var a1 = r[0usize]
    var a2 = r[1usize]
    if a1 > a2 {
        a1 = r[1usize]
        a2 = r[0usize]
    }
    if nc.pnf(f, df, dfe, 0.0f64, true, false) <= alpha / 2.0f64 { a2 = 0.0f64 }
    if nc.pnf(f, df, dfe, 0.0f64, true, false) <= 1.0f64 - alpha / 2.0f64 { a1 = 0.0f64 }
    out[0usize] = a1
    out[1usize] = a2
}

// the confidence interval effectsize gives eta_squared, omega_squared and epsilon_squared of a one-way fit (all three go through the partial eta squared scale of the F recomputed from the estimate es):
// ci is the level asked, greater is the default one-sided interval (the level becomes 2 ci - 1 and the upper bound 1). out[0] lower, out[1] upper.
fn pve_ci(es: f64, df: f64, dfe: f64, ci: f64, greater: bool, out: []f64) {
    var lev = ci
    if greater { lev = 2.0f64 * ci - 1.0f64 }
    var f = (es / df) / ((1.0f64 - es) / dfe)
    if f < 0.0f64 { f = 0.0f64 }
    var n: [2]f64 = zero
    ncp_f_ci(f, df, dfe, lev, n[0usize..2usize])
    out[0usize] = n[0usize] / (n[0usize] + dfe)
    out[1usize] = n[1usize] / (n[1usize] + dfe)
    if out[0usize] < 0.0f64 { out[0usize] = 0.0f64 }
    if greater { out[1usize] = 1.0f64 }
}

// rank_biserial(x, y, ci = level) for two independent samples: tanh(atanh(r) +- z sqrt((n1 + n2 + 1) / (3 n1 n2))). out[0] lower, out[1] upper.
fn rbs_ci(x: []const f64, y: []const f64, level: f64, out: []f64) {
    let r = cliffs(x, y)
    let n1 = f64(x.len)
    let n2 = f64(y.len)
    let z = dist.qnorm(1.0f64 - (1.0f64 - level) / 2.0f64, 0.0f64, 1.0f64, true, false)
    let se = math.sqrt[f64]((n1 + n2 + 1.0f64) / (3.0f64 * n1 * n2))
    let f = 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r))
    out[0usize] = scale.tanh(f - z * se)
    out[1usize] = scale.tanh(f + z * se)
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

// vcd::woolf_test on a 2 by 2 by k table x (column-major: cell (i, j, s) at s * 4 + j * 2 + i): the log odds ratios o_s, their inverse-variance
// weights w_s = 1 / sum(1 / cell), the weighted mean e, and the statistic sum w (o - e)^2 on k - 1 degrees of freedom. Any zero cell adds 1/2 to
// every cell first. Returns the statistic and its upper tail p value.
fn woolf(a: *mem.Arena, x: []const f64, k: usize) -> (f64, f64, err) {
    let (t, e) = mem.alloc[f64](a, 4usize * k)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    var zero_cell = false
    var i = 0usize
    while i < 4usize * k {
        if x[i] == 0.0f64 { zero_cell = true }
        i += 1usize
    }
    i = 0usize
    while i < 4usize * k {
        t[i] = x[i]
        if zero_cell { t[i] += 0.5f64 }
        i += 1usize
    }
    let (o, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    let (w, e3) = mem.alloc[f64](a, k)
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    var sw = 0.0f64
    var swo = 0.0f64
    var s = 0usize
    while s < k {
        let c = s * 4usize
        o[s] = math.log[f64](t[c] * t[c + 3usize] / (t[c + 2usize] * t[c + 1usize]))
        w[s] = 1.0f64 / (1.0f64 / t[c] + 1.0f64 / t[c + 1usize] + 1.0f64 / t[c + 2usize] + 1.0f64 / t[c + 3usize])
        sw += w[s]
        swo += w[s] * o[s]
        s += 1usize
    }
    let em = swo / sw
    var stat = 0.0f64
    s = 0usize
    while s < k {
        let d = o[s] - em
        stat += w[s] * d * d
        s += 1usize
    }
    ret (stat, nm.pchisq(stat, f64(k - 1usize), false, false), ok)
}

// vcd::oddsratio (loddsratio with no reference categories) on an r by c by s table x (column-major): for each stratum, and each adjacent pair of rows
// and of columns, the log odds ratio log x(i,j) - log x(i+1,j) - log x(i,j+1) + log x(i+1,j+1), with its variance sum 1 / x over the four cells.
// Stratum-major, then column by column, as the contrasts of loddsratio are ordered. Any zero cell adds one half to every cell.
// Returns the (r - 1)(c - 1)s coefficients and their variances.
fn loddsratio(a: *mem.Arena, x: []const f64, r: usize, c: usize, s: usize, coef: []f64, vdiag: []f64) -> err {
    var zero_cell = false
    var i = 0usize
    while i < r * c * s {
        if x[i] == 0.0f64 { zero_cell = true }
        i += 1usize
    }
    var add = 0.0f64
    if zero_cell { add = 0.5f64 }
    var k = 0usize
    while k < s {
        var j = 0usize
        while j + 1usize < c {
            i = 0usize
            while i + 1usize < r {
                let idx = k * (r - 1usize) * (c - 1usize) + j * (r - 1usize) + i
                let p00 = x[k * r * c + j * r + i] + add
                let p10 = x[k * r * c + j * r + i + 1usize] + add
                let p01 = x[k * r * c + (j + 1usize) * r + i] + add
                let p11 = x[k * r * c + (j + 1usize) * r + i + 1usize] + add
                coef[idx] = math.log[f64](p00) - math.log[f64](p10) - math.log[f64](p01) + math.log[f64](p11)
                vdiag[idx] = 1.0f64 / p00 + 1.0f64 / p10 + 1.0f64 / p01 + 1.0f64 / p11
                i += 1usize
            }
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// confint(oddsratio(x, log = log), level) from the coefficients and variances of `loddsratio`: the Wald interval coef +- z sd on the log scale, exponentiated when log is false.
// lo and hi receive the bounds; vexp receives the variances vcov(oddsratio(x, log = FALSE)) = v exp(coef)^2 on the odds ratio scale (the log scale ones are `vdiag`).
fn loddsratio_ci(coef: []const f64, vdiag: []const f64, level: f64, logscale: bool, lo: []f64, hi: []f64, vexp: []f64) {
    let z = dist.qnorm((1.0f64 - level) / 2.0f64, 0.0f64, 1.0f64, true, false)
    var i = 0usize
    while i < coef.len {
        let sd = math.sqrt[f64](vdiag[i])
        lo[i] = coef[i] + z * sd
        hi[i] = coef[i] - z * sd
        vexp[i] = vdiag[i] * math.exp[f64](coef[i]) * math.exp[f64](coef[i])
        if !logscale {
            lo[i] = math.exp[f64](lo[i])
            hi[i] = math.exp[f64](hi[i])
        }
        i += 1usize
    }
}

// effectsize::interpret_* label index: the number of thresholds of the rule that |x| reaches (findInterval with right = FALSE, so a value on a threshold takes the higher label). rule: 0 .. 3 interpret_cohens_d with
// cohen1988, sawilowsky2009, gignac2016 (its thresholds are on r, so d is first turned into d / sqrt(d^2 + 4)), lovakov2021; 4 .. 7 interpret_r with funder2019, gignac2016, cohen1988, lovakov2021 (interpret_rank_biserial is rule 4); 8, 9 interpret_eta_squared (and omega and
// epsilon) with field2013, cohen1992; 10 interpret_oddsratio (log(OR) sqrt(3) / pi on the cohen1988 d rule).
fn interpret_rule_values(rule: usize, th: []f64) -> usize {
    if rule == 0usize {
        th[0usize] = 0.2f64
        th[1usize] = 0.5f64
        th[2usize] = 0.8f64
        ret 3usize
    }
    if rule == 1usize {
        th[0usize] = 0.1f64
        th[1usize] = 0.2f64
        th[2usize] = 0.5f64
        th[3usize] = 0.8f64
        th[4usize] = 1.2f64
        th[5usize] = 2.0f64
        ret 6usize
    }
    if rule == 2usize {
        th[0usize] = 0.1f64
        th[1usize] = 0.2f64
        th[2usize] = 0.3f64
        ret 3usize
    }
    if rule == 3usize {
        th[0usize] = 0.15f64
        th[1usize] = 0.36f64
        th[2usize] = 0.65f64
        ret 3usize
    }
    if rule == 4usize {
        th[0usize] = 0.05f64
        th[1usize] = 0.1f64
        th[2usize] = 0.2f64
        th[3usize] = 0.3f64
        th[4usize] = 0.4f64
        ret 5usize
    }
    if rule == 5usize {
        th[0usize] = 0.1f64
        th[1usize] = 0.2f64
        th[2usize] = 0.3f64
        ret 3usize
    }
    if rule == 6usize {
        th[0usize] = 0.1f64
        th[1usize] = 0.3f64
        th[2usize] = 0.5f64
        ret 3usize
    }
    if rule == 7usize {
        th[0usize] = 0.12f64
        th[1usize] = 0.24f64
        th[2usize] = 0.41f64
        ret 3usize
    }
    if rule == 8usize {
        th[0usize] = 0.01f64
        th[1usize] = 0.06f64
        th[2usize] = 0.14f64
        ret 3usize
    }
    if rule == 9usize {
        th[0usize] = 0.02f64
        th[1usize] = 0.13f64
        th[2usize] = 0.26f64
        ret 3usize
    }
    ret 0usize
}

fn interpret_index(rule: usize, x: f64) -> usize {
    var th: [6]f64 = zero
    var v = math.abs[f64](x)
    var rl = rule
    if rule == 10usize {
        v = math.abs[f64](math.log[f64](x)) * math.sqrt[f64](3.0f64) / 3.141592653589793f64
        rl = 0usize
    }
    if rule == 2usize { v = v / math.sqrt[f64](v * v + 4.0f64) }
    let n = interpret_rule_values(rl, th[0usize..6usize])
    var k = 0usize
    var idx = 0usize
    while k < n {
        if v >= th[k] { idx += 1usize }
        k += 1usize
    }
    ret idx
}

// vcd::goodfit(x, type = "poisson") by maximum likelihood on a one-way table of counts freq[c] for c = 0 .. K - 1: lambda = the weighted mean of the
// counts, the fitted counts N dpois(c, lambda), and the degrees of freedom (the number of non-empty counts) - 2. Returns lambda and the degrees of
// freedom; the fitted counts go to fit; the chi-square of summary(goodfit) is sum (obs - fit)^2 / fit over the fitted counts, computed by the caller.
fn goodfit_poisson(freq: []const f64, fit: []f64) -> (f64, f64, err) {
    let k = freq.len
    var nsum = 0.0f64
    var wsum = 0.0f64
    var nonzero = 0.0f64
    var c = 0usize
    while c < k {
        nsum += freq[c]
        wsum += f64(c) * freq[c]
        if freq[c] > 0.0f64 { nonzero += 1.0f64 }
        c += 1usize
    }
    let lambda = wsum / nsum
    c = 0usize
    while c < k {
        fit[c] = nsum * nm.dpois(f64(c), lambda, false)
        c += 1usize
    }
    ret (lambda, nonzero - 2.0f64, ok)
}

// vcd::goodfit(type = "binomial", method = "ML", par = list(size)) on the counts freq[c], c = 0 .. K - 1 with K - 1 <= size: prob = the weighted mean
// of c / size, the fitted counts N dpois-style dbinom(c, size, prob), and the degrees of freedom (non-empty counts) - 2.
fn goodfit_binomial(freq: []const f64, size: f64, fit: []f64) -> (f64, f64, err) {
    let k = freq.len
    var nsum = 0.0f64
    var wsum = 0.0f64
    var nonzero = 0.0f64
    var c = 0usize
    while c < k {
        nsum += freq[c]
        wsum += (f64(c) / size) * freq[c]
        if freq[c] > 0.0f64 { nonzero += 1.0f64 }
        c += 1usize
    }
    let prob = wsum / nsum
    c = 0usize
    while c < k {
        fit[c] = nsum * nb.dbinom(f64(c), size, prob, false)
        c += 1usize
    }
    ret (prob, nonzero - 2.0f64, ok)
}

// goodfit(method = "MinChisq") for the Poisson (kind 0) and the binomial with a given size (kind 1) on the counts freq[c], c = 0 .. K - 1: the parameter minimising sum (obs - exp)^2 / exp with
// exp = N times the differences of the cumulative distribution (the last cell taking the remainder), by R's optimize over range(count) (Poisson) or (0, 1); df = K - 2
type McCtx = struct { freq: []const f64, k: usize, kind: usize, size: f64 }

fn mc_chi2(c: *McCtx, x: f64) -> f64 {
    var tot = 0.0f64
    var nn = 0.0f64
    var i = 0usize
    while i < c.k {
        nn += c.freq[i]
        i += 1usize
    }
    var prev = 0.0f64
    var chi = 0.0f64
    i = 0usize
    while i < c.k {
        var cum = 1.0f64
        if i + 1usize < c.k {
            if c.kind == 0usize { cum = nmm.ppois(f64(i), x, true, false) } else { cum = nmb.pbinom(f64(i), c.size, x, true, false) }
        }
        let ex = nn * (cum - prev)
        chi += (c.freq[i] - ex) * (c.freq[i] - ex) / ex
        prev = cum
        i += 1usize
    }
    tot = chi
    ret tot
}

fn goodfit_minchisq(freq: []const f64, kind: usize, size: f64, fit: []f64) -> (f64, f64) {
    var c = McCtx{ freq: freq, k: freq.len, kind: kind, size: size }
    var lo = 0.0f64
    var hi = 1.0f64
    if kind == 0usize { hi = f64(freq.len - 1usize) }
    let par = fdr.brent_min[McCtx](&c, mc_chi2, lo, hi)
    var nn = 0.0f64
    var i = 0usize
    while i < freq.len {
        nn += freq[i]
        i += 1usize
    }
    i = 0usize
    while i < freq.len {
        if kind == 0usize { fit[i] = nn * nmm.dpois(f64(i), par, false) } else { fit[i] = nn * nmb.dbinom(f64(i), size, par, false) }
        i += 1usize
    }
    ret (par, f64(freq.len) - 2.0f64)
}

// goodfit(type = "nbinomial") on counts freq[c], c = 0 .. K - 1: ML (MASS::fitdistr: mu = the sample mean and the size maximising the likelihood, found on log(size) by Brent to 1e-12; prob = size / (size + mu))
// out receives (size, prob); MinChisq (no size given): Nelder-Mead on (size, prob) from the moment estimates under R's optim defaults, chi-square as for the other families
type NbCtx2 = struct { freq: []const f64, k: usize, mu: f64 }

fn nbg_negll(c: *NbCtx2, lsz: f64) -> f64 {
    let size = math.exp[f64](lsz)
    var ll = 0.0f64
    var i = 0usize
    while i < c.k {
        ll += c.freq[i] * nmb.dnbinom_mu(f64(i), size, c.mu, true)
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn goodfit_nb_ml(freq: []const f64, out: []f64) {
    var nn = 0.0f64
    var sm = 0.0f64
    var i = 0usize
    while i < freq.len {
        nn += freq[i]
        sm += freq[i] * f64(i)
        i += 1usize
    }
    let mu = sm / nn
    var c = NbCtx2{ freq: freq, k: freq.len, mu: mu }
    let l = fdr.brent_min_tol[NbCtx2](&c, nbg_negll, math.log[f64](0.001f64), math.log[f64](1.0e6f64), 1.0e-12f64)
    let size = math.exp[f64](l)
    out[0usize] = size
    out[1usize] = size / (size + mu)
}

type NbMcCtx = struct { freq: []const f64, k: usize }

fn nbmc_chi2(c: *NbMcCtx, x: []const f64) -> f64 {
    var nn = 0.0f64
    var i = 0usize
    while i < c.k {
        nn += c.freq[i]
        i += 1usize
    }
    var prev = 0.0f64
    var chi = 0.0f64
    i = 0usize
    while i < c.k {
        var cum = 1.0f64
        if i + 1usize < c.k { cum = nmb.pnbinom(f64(i), x[0usize], x[1usize], true, false) }
        let ex = nn * (cum - prev)
        chi += (c.freq[i] - ex) * (c.freq[i] - ex) / ex
        prev = cum
        i += 1usize
    }
    ret chi
}

fn goodfit_nb_minchisq(a: *mem.Arena, freq: []const f64, out: []f64) {
    var nn = 0.0f64
    var sm = 0.0f64
    var i = 0usize
    while i < freq.len {
        nn += freq[i]
        sm += freq[i] * f64(i)
        i += 1usize
    }
    let xbar = sm / nn
    var ss = 0.0f64
    i = 0usize
    while i < freq.len {
        ss += freq[i] * (f64(i) - xbar) * (f64(i) - xbar)
        i += 1usize
    }
    let s2 = ss / (nn - 1.0f64)
    var start: [2]f64 = zero
    start[0usize] = xbar * xbar / (s2 - xbar)
    start[1usize] = xbar / s2
    var best: [2]f64 = zero
    var c = NbMcCtx{ freq: freq, k: freq.len }
    let (fmin, cnt, fail) = rnmv.nmmin[NbMcCtx](a, &c, nbmc_chi2, start[0usize..2usize], 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, best[0usize..2usize])
    out[0usize] = best[0usize]
    out[1usize] = best[1usize]
}
