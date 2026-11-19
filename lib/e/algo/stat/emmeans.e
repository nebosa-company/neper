// R emmeans, the lm part: estimated marginal means as linear functions `l' beta` of a fitted linear model, their
// standard errors and t statistics on the residual degrees of freedom, pairwise contrasts, and the Tukey, Holm,
// Bonferroni and Sidak adjustments of their p values. The caller builds the reference-grid row `l` for each
// level (the average of the design rows over the other factors, covariates at their means), as `emmeans` does
// internally.
//
// Not here: building the reference grid from a model frame, glm and mixed models, the scheffe and mvt
// adjustments, contrast families other than pairwise, joint_tests, emtrends, eff_size, regrid, emmip data.

use e.algo.stat.psych as ps
use e.math
use e.math.nmath_beta as nb
use e.mem
use e.algo.stat.flexmixpkg as fxg

type Lm = struct { beta: []f64, cov: []f64, df: f64, p: usize }

// x is n by p column-major; cov = sigma^2 (X'X)^-1 row-major
fn fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (Lm, err) {
    var empty: Lm = zero
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (inv, e2) = mem.alloc[f64](a, p * p)
    let (xty, e3) = mem.alloc[f64](a, p)
    let (beta, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (empty, e1) }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += x[j * n + i] * x[k * n + i]
                i += 1usize
            }
            xtx[j * p + k] = s
            k += 1usize
        }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[j * n + i] * y[i]
            i += 1usize
        }
        xty[j] = s
        j += 1usize
    }
    if !ps.invert(a, xtx, p, inv) { ret (empty, Singular) }
    j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += inv[j * p + k] * xty[k]
            k += 1usize
        }
        beta[j] = s
        j += 1usize
    }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        var f = 0.0f64
        j = 0usize
        while j < p {
            f += x[j * n + i] * beta[j]
            j += 1usize
        }
        rss += (y[i] - f) * (y[i] - f)
        i += 1usize
    }
    let df = f64(n - p)
    let s2 = rss / df
    j = 0usize
    while j < p * p {
        inv[j] = inv[j] * s2
        j += 1usize
    }
    ret (Lm { beta: beta, cov: inv, df: df, p: p }, ok)
}

fn estimate(m: *const Lm, l: []const f64) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < m.p {
        s += l[j] * m.beta[j]
        j += 1usize
    }
    ret s
}

// variance of l1' beta - l2' beta (pass l2 = the same row with sign folded in by the caller if wanted)
fn variance(m: *const Lm, l: []const f64) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < m.p {
        var k = 0usize
        while k < m.p {
            s += l[j] * m.cov[j * m.p + k] * l[k]
            k += 1usize
        }
        j += 1usize
    }
    ret s
}

// two-sided p of a t statistic
fn p_t(t: f64, df: f64) -> f64 { ret 2.0f64 * nb.pt(0.0f64 - math.abs[f64](t), df, true, false) }

// Tukey-adjusted p of a pairwise t among k means
fn p_tukey(t: f64, k: f64, df: f64) -> f64 { ret 1.0f64 - nb.ptukey(math.abs[f64](t) * math.sqrt[f64](2.0f64), 1.0f64, k, df, true, false) }

// adjust = "scheffe": the F statistic t^2 / rank on (rank, df) degrees of freedom, rank the rank of the contrast matrix (the number of levels less one for pairwise comparisons of one factor)
fn p_scheffe(t: f64, rank: f64, df: f64) -> f64 { ret nb.pf(t * t / rank, rank, df, false, false) }

fn p_bonferroni(p: f64, m: f64) -> f64 { ret math.min[f64](1.0f64, p * m) }

fn p_sidak(p: f64, m: f64) -> f64 { ret 1.0f64 - math.pow[f64](1.0f64 - p, m) }

// Holm adjustment of ps in place (ties and order as in p.adjust)
fn holm(ps_: []f64) {
    let m = ps_.len
    var done = 0usize
    var prev = 0.0f64
    var i = 0usize
    // selection by smallest unprocessed p, marking processed ones by their adjusted value kept separately
    var adj: [64]f64 = zero
    var used: [64]bool = zero
    while done < m {
        var best = m
        i = 0usize
        while i < m {
            if !used[i] && (best == m || ps_[i] < ps_[best]) { best = i }
            i += 1usize
        }
        let v = math.min[f64](1.0f64, f64(m - done) * ps_[best])
        if v > prev { prev = v }
        adj[best] = prev
        used[best] = true
        done += 1usize
    }
    i = 0usize
    while i < m {
        ps_[i] = adj[i]
        i += 1usize
    }
}

error Singular

// emmeans::joint_tests of one term: the F statistic (Lb)' (L V L')^-1 (Lb) / r of the r rows of l (row-major r by p, each a linear function of the coefficients), on (r, df) degrees of freedom. out[0] F, out[1] the
// p value; false when L V L' is singular
fn joint_f(a: *mem.Arena, m: *const Lm, l: []const f64, r: usize, out: []f64) -> bool {
    let p = m.p
    let (lb, e1) = mem.alloc[f64](a, r)
    let (aug, e2) = mem.alloc[f64](a, r * (r + 1usize))
    if e1 != ok || e2 != ok { ret false }
    var i = 0usize
    while i < r {
        lb[i] = estimate(m, l[i * p..(i + 1usize) * p])
        var j = 0usize
        while j < r {
            var sv = 0.0f64
            var u = 0usize
            while u < p {
                var w = 0usize
                while w < p {
                    sv += l[i * p + u] * m.cov[u * p + w] * l[j * p + w]
                    w += 1usize
                }
                u += 1usize
            }
            aug[i * (r + 1usize) + j] = sv
            j += 1usize
        }
        aug[i * (r + 1usize) + r] = lb[i]
        i += 1usize
    }
    var col = 0usize
    while col < r {
        var piv = col
        var q = col + 1usize
        while q < r {
            if math.abs[f64](aug[q * (r + 1usize) + col]) > math.abs[f64](aug[piv * (r + 1usize) + col]) { piv = q }
            q += 1usize
        }
        var c2 = 0usize
        while c2 <= r {
            let tmp = aug[col * (r + 1usize) + c2]
            aug[col * (r + 1usize) + c2] = aug[piv * (r + 1usize) + c2]
            aug[piv * (r + 1usize) + c2] = tmp
            c2 += 1usize
        }
        let dv = aug[col * (r + 1usize) + col]
        if math.abs[f64](dv) < 1.0e-300f64 { ret false }
        c2 = 0usize
        while c2 <= r {
            aug[col * (r + 1usize) + c2] = aug[col * (r + 1usize) + c2] / dv
            c2 += 1usize
        }
        q = 0usize
        while q < r {
            if q != col {
                let f = aug[q * (r + 1usize) + col]
                c2 = 0usize
                while c2 <= r {
                    aug[q * (r + 1usize) + c2] = aug[q * (r + 1usize) + c2] - f * aug[col * (r + 1usize) + c2]
                    c2 += 1usize
                }
            }
            q += 1usize
        }
        col += 1usize
    }
    var chi = 0.0f64
    i = 0usize
    while i < r {
        chi += lb[i] * aug[i * (r + 1usize) + r]
        i += 1usize
    }
    out[0usize] = chi / f64(r)
    out[1usize] = nb.pf(out[0usize], f64(r), m.df, false, false)
    ret true
}

// emmeans::eff_size(e, sigma, edf) of a contrast with estimate est and standard error se: the standardised difference d = est / sigma, its delta-method standard error sqrt(se^2 / sigma^2 + d^2 / (2 edf)) and
// the t interval on edf degrees of freedom at `level`. out[0] d, out[1] se, out[2] lower, out[3] upper
fn eff_size(est: f64, se: f64, sigma: f64, edf: f64, level: f64, out: []f64) {
    let d = est / sigma
    let sed = math.sqrt[f64](se * se / (sigma * sigma) + d * d / (2.0f64 * edf))
    let tq = nb.qt(1.0f64 - (1.0f64 - level) / 2.0f64, edf, true, false)
    out[0usize] = d
    out[1usize] = sed
    out[2usize] = d - tq * sed
    out[3usize] = d + tq * sed
}

// emmeans(m, specs, type = "response") for a model of log(y): the mean on the response scale exp(emm), its delta-method standard error exp(emm) se, and the interval exp(emm +- t se) at `level` on df degrees of freedom.
// out[0] response, out[1] SE, out[2] lower, out[3] upper
fn backtransform_log(emm: f64, se: f64, df: f64, level: f64, out: []f64) {
    let tq = nb.qt(1.0f64 - (1.0f64 - level) / 2.0f64, df, true, false)
    let r = math.exp[f64](emm)
    out[0usize] = r
    out[1usize] = r * se
    out[2usize] = math.exp[f64](emm - tq * se)
    out[3usize] = math.exp[f64](emm + tq * se)
}

// the same for other transformations of the response that emmeans recognises: kind 0 log, 1 sqrt (the mean emm^2 with standard error 2 emm se and limits (emm +- t se)^2), 2 log10 (10^emm, standard error 10^emm ln(10) se)
fn backtransform(kind: usize, emm: f64, se: f64, df: f64, level: f64, out: []f64) {
    if kind == 0usize {
        backtransform_log(emm, se, df, level, out)
        ret
    }
    let tq = nb.qt(1.0f64 - (1.0f64 - level) / 2.0f64, df, true, false)
    let lo = emm - tq * se
    let hi = emm + tq * se
    if kind == 1usize {
        out[0usize] = emm * emm
        out[1usize] = 2.0f64 * emm * se
        out[2usize] = lo * lo
        out[3usize] = hi * hi
        ret
    }
    let r = math.pow[f64](10.0f64, emm)
    out[0usize] = r
    out[1usize] = r * 2.302585092994046f64 * se
    out[2usize] = math.pow[f64](10.0f64, lo)
    out[3usize] = math.pow[f64](10.0f64, hi)
}

// the Lm of a logistic regression of the binary y on the design x (n by p column-major): the maximum-likelihood coefficients by IRLS and the covariance (X' W X)^-1 with W = mu (1 - mu); df is infinite (1e300) as emmeans
// treats a glm with a known dispersion
fn logit_glm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (Lm, err) {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (sz, e2) = mem.alloc[f64](a, n)
    let (w, e3) = mem.alloc[f64](a, n)
    let (xwx, e4) = mem.alloc[f64](a, p * p)
    let (inv, e5) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret (zero, e1) }
    if e2 != ok { ret (zero, e2) }
    if e3 != ok { ret (zero, e3) }
    if e4 != ok { ret (zero, e4) }
    if e5 != ok { ret (zero, e5) }
    var i = 0usize
    while i < n {
        sz[i] = 1.0f64
        w[i] = 1.0f64
        i += 1usize
    }
    let e6 = fxg.binom_glm(a, x, n, p, y, sz, w, beta, false)
    if e6 != ok { ret (zero, e6) }
    var j = 0usize
    while j < p * p {
        xwx[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        var eta = 0.0f64
        j = 0usize
        while j < p {
            eta += x[j * n + i] * beta[j]
            j += 1usize
        }
        let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        let wv = mu * (1.0f64 - mu)
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                xwx[j * p + k] += wv * x[j * n + i] * x[k * n + i]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    if !ps.invert(a, xwx, p, inv) { ret (zero, Singular) }
    ret (Lm { beta: beta, cov: inv, df: 1.0e300f64, p: p }, ok)
}

// emmeans(m, specs, type = "response") of a logistic regression: plogis(emm), its delta-method standard error p (1 - p) se and the interval plogis(emm +- z se) at `level` (a z quantile, the degrees of freedom being infinite)
fn backtransform_logit(emm: f64, se: f64, level: f64, out: []f64) {
    let z = nb.qt(1.0f64 - (1.0f64 - level) / 2.0f64, 1.0e10f64, true, false)
    let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - emm))
    out[0usize] = pr
    out[1usize] = pr * (1.0f64 - pr) * se
    out[2usize] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - (emm - z * se)))
    out[3usize] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - (emm + z * se)))
}

// the Lm of a Poisson regression of the counts y on the design x (n by p column-major): IRLS coefficients and the covariance (X' W X)^-1 with W = mu; df infinite as for a glm with known dispersion
fn pois_glm_lm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (Lm, err) {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (w, e2) = mem.alloc[f64](a, n)
    let (xwx, e3) = mem.alloc[f64](a, p * p)
    let (inv, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret (zero, e1) }
    if e2 != ok { ret (zero, e2) }
    if e3 != ok { ret (zero, e3) }
    if e4 != ok { ret (zero, e4) }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let e5 = fxg.pois_glm(a, x, n, p, y, w, beta, false)
    if e5 != ok { ret (zero, e5) }
    var j = 0usize
    while j < p * p {
        xwx[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        var eta = 0.0f64
        j = 0usize
        while j < p {
            eta += x[j * n + i] * beta[j]
            j += 1usize
        }
        let mu = math.exp[f64](eta)
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                xwx[j * p + k] += mu * x[j * n + i] * x[k * n + i]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    if !ps.invert(a, xwx, p, inv) { ret (zero, Singular) }
    ret (Lm { beta: beta, cov: inv, df: 1.0e300f64, p: p }, ok)
}
