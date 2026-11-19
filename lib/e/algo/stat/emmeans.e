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
use e.math.dist as dist
use e.algo.stat.pmcmr as pm
use e.math.nmath as nmx

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

// the contrast coefficients of emmeans' *.emmc functions for k levels, level i of contrast j at out[i m + j] (m returned, 0 when the kind is unknown): kind 0 pairwise, 1 revpairwise, 2 trt.vs.ctrl (first level the control),
// 3 trt.vs.ctrlk (last level), 4 consec, 5 eff, 6 del.eff, 8 mean_chg, 9 identity, 7 poly (orthogonal polynomials of degree 1 .. k - 1 on 1 .. k, scaled to the smallest whole numbers, the last entry positive)
fn contrast_coefs(kind: usize, k: usize, out: []f64) -> usize {
    var m = 0usize
    if kind == 0usize || kind == 1usize {
        m = k * (k - 1usize) / 2usize
    } else if kind == 2usize || kind == 3usize || kind == 4usize || kind == 7usize || kind == 8usize {
        m = k - 1usize
    } else if kind == 5usize || kind == 6usize || kind == 9usize {
        m = k
    } else {
        ret 0usize
    }
    var z = 0usize
    while z < k * m {
        out[z] = 0.0f64
        z += 1usize
    }
    if kind == 0usize || kind == 1usize {
        var j = 0usize
        var a = 0usize
        while a < k {
            var b = a + 1usize
            while b < k {
                if kind == 0usize {
                    out[a * m + j] = 1.0f64
                    out[b * m + j] = 0.0f64 - 1.0f64
                } else {
                    out[a * m + j] = 0.0f64 - 1.0f64
                    out[b * m + j] = 1.0f64
                }
                j += 1usize
                b += 1usize
            }
            a += 1usize
        }
        // revpairwise lists the pairs by the larger level last: 2-1, 3-1, 3-2, 4-1, ... (second index major)
        if kind == 1usize {
            z = 0usize
            while z < k * m {
                out[z] = 0.0f64
                z += 1usize
            }
            j = 0usize
            var hi = 1usize
            while hi < k {
                var lo = 0usize
                while lo < hi {
                    out[lo * m + j] = 0.0f64 - 1.0f64
                    out[hi * m + j] = 1.0f64
                    j += 1usize
                    lo += 1usize
                }
                hi += 1usize
            }
        }
    } else if kind == 2usize {
        var j = 0usize
        while j < m {
            out[j] = 0.0f64 - 1.0f64
            out[(j + 1usize) * m + j] = 1.0f64
            j += 1usize
        }
    } else if kind == 3usize {
        var j = 0usize
        while j < m {
            out[j * m + j] = 1.0f64
            out[(k - 1usize) * m + j] = 0.0f64 - 1.0f64
            j += 1usize
        }
    } else if kind == 4usize {
        var j = 0usize
        while j < m {
            out[j * m + j] = 0.0f64 - 1.0f64
            out[(j + 1usize) * m + j] = 1.0f64
            j += 1usize
        }
    } else if kind == 9usize {
        var j = 0usize
        while j < k {
            out[j * m + j] = 1.0f64
            j += 1usize
        }
    } else if kind == 8usize {
        // mean_chg: contrast j is the mean of the levels above j less the mean of the levels up to j
        var j = 0usize
        while j < m {
            var i = 0usize
            while i < k {
                if i <= j { out[i * m + j] = 0.0f64 - 1.0f64 / f64(j + 1usize) } else { out[i * m + j] = 1.0f64 / f64(k - 1usize - j) }
                i += 1usize
            }
            j += 1usize
        }
    } else if kind == 5usize || kind == 6usize {
        var j = 0usize
        while j < k {
            var i = 0usize
            while i < k {
                if kind == 5usize {
                    if i == j { out[i * m + j] = 1.0f64 - 1.0f64 / f64(k) } else { out[i * m + j] = 0.0f64 - 1.0f64 / f64(k) }
                } else {
                    if i == j { out[i * m + j] = 1.0f64 } else { out[i * m + j] = 0.0f64 - 1.0f64 / f64(k - 1usize) }
                }
                i += 1usize
            }
            j += 1usize
        }
    } else {
        // Gram-Schmidt on the powers of the centred levels, degree d in column d - 1
        let kf = f64(k)
        var d = 1usize
        while d < k {
            var i = 0usize
            while i < k {
                out[i * m + d - 1usize] = math.pow[f64](f64(i) - (kf - 1.0f64) / 2.0f64, f64(d))
                i += 1usize
            }
            // remove the constant
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += out[i * m + d - 1usize]
                i += 1usize
            }
            i = 0usize
            while i < k {
                out[i * m + d - 1usize] = out[i * m + d - 1usize] - s / kf
                i += 1usize
            }
            var e = 1usize
            while e < d {
                var dot = 0.0f64
                var nn = 0.0f64
                i = 0usize
                while i < k {
                    dot += out[i * m + d - 1usize] * out[i * m + e - 1usize]
                    nn += out[i * m + e - 1usize] * out[i * m + e - 1usize]
                    i += 1usize
                }
                i = 0usize
                while i < k {
                    out[i * m + d - 1usize] = out[i * m + d - 1usize] - dot / nn * out[i * m + e - 1usize]
                    i += 1usize
                }
                e += 1usize
            }
            var mn = 1.0e300f64
            i = 0usize
            while i < k {
                let v = math.abs[f64](out[i * m + d - 1usize])
                if v > 1.0e-6f64 && v < mn { mn = v }
                i += 1usize
            }
            var sg = 1.0f64
            if out[(k - 1usize) * m + d - 1usize] < 0.0f64 { sg = 0.0f64 - 1.0f64 }
            i = 0usize
            while i < k {
                out[i * m + d - 1usize] = sg * out[i * m + d - 1usize] / mn
                i += 1usize
            }
            // the smallest integer multiplier that makes every entry a whole number
            var tm = 1usize
            while tm < 200usize {
                var whole = true
                i = 0usize
                while i < k {
                    let v = out[i * m + d - 1usize] * f64(tm)
                    if math.abs[f64](v - math.round[f64](v)) > 1.0e-6f64 { whole = false }
                    i += 1usize
                }
                if whole { break }
                tm += 1usize
            }
            i = 0usize
            while i < k {
                out[i * m + d - 1usize] = out[i * m + d - 1usize] * f64(tm)
                i += 1usize
            }
            d += 1usize
        }
    }
    ret m
}

// contrast(emmeans(lm(y ~ g), "g"), method, adjust = "none") for a one-way layout: grp holds the level (0 .. k - 1) of each of the n observations, kind as in `contrast_coefs`. For contrast j out[10 j ..] = the estimate, its standard
// error, the degrees of freedom n - k, the t ratio, the unadjusted p, the Tukey-adjusted p (for the pairwise kinds 0 and 1, NaN otherwise), then the Scheffe (rank k - 1), Bonferroni, Sidak and Holm adjusted p over the m contrasts;
// returns the number of contrasts, 0 when the fit fails
fn contrast_oneway(a: *mem.Arena, grp: []const f64, y: []const f64, xc: []const f64, n: usize, k: usize, kind: usize, out: []f64) -> usize {
    var q = k
    if xc.len > 0usize { q = k + xc.len / n }
    let (x, e1) = mem.alloc[f64](a, n * q)
    let (cf, e2) = mem.alloc[f64](a, k * k * k)
    let (l, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var z = 0usize
    while z < n * q {
        x[z] = 0.0f64
        z += 1usize
    }
    var i = 0usize
    while i < n {
        x[usize(grp[i]) * n + i] = 1.0f64
        i += 1usize
    }
    var cx = 0usize
    while cx * n < xc.len {
        i = 0usize
        while i < n {
            x[(k + cx) * n + i] = xc[cx * n + i]
            i += 1usize
        }
        cx += 1usize
    }
    let (fm, fe) = fit(a, x, y, n, q)
    if fe != ok { ret 0usize }
    let m = contrast_coefs(kind, k, cf)
    if m == 0usize { ret 0usize }
    let df = f64(n - q)
    var j = 0usize
    while j < m {
        var lv = 0usize
        while lv < q {
            l[lv] = 0.0f64
            if lv < k { l[lv] = cf[lv * m + j] }
            lv += 1usize
        }
        let est = estimate(&fm, l)
        let se = math.sqrt[f64](variance(&fm, l))
        let t = est / se
        out[10usize * j] = est
        out[10usize * j + 1usize] = se
        out[10usize * j + 2usize] = df
        out[10usize * j + 3usize] = t
        out[10usize * j + 4usize] = p_t(t, df)
        out[10usize * j + 5usize] = 0.0f64 / 0.0f64
        if kind <= 1usize { out[10usize * j + 5usize] = p_tukey(t, f64(k), df) }
        j += 1usize
    }
    var pv: [64]f64 = zero
    j = 0usize
    while j < m {
        pv[j] = out[10usize * j + 4usize]
        out[10usize * j + 6usize] = p_scheffe(out[10usize * j + 3usize], f64(k - 1usize), df)
        out[10usize * j + 7usize] = p_bonferroni(pv[j], f64(m))
        out[10usize * j + 8usize] = p_sidak(pv[j], f64(m))
        j += 1usize
    }
    holm(pv[0usize..m])
    j = 0usize
    while j < m {
        out[10usize * j + 9usize] = pv[j]
        j += 1usize
    }
    ret m
}

// Dunnett's adjusted two-sided p of the many-to-one comparisons of a one-way layout with control size n0 and treatment sizes ns: the t statistics are multivariate t with the one-factor correlation lambda_i lambda_j,
// lambda_i = sqrt(n_i / (n_i + n0)), so the p is 1 - P(all |T_i| < t), which pmcmr's `mvt_one_factor_upper` integrates (the one implementation of that integral)
fn dunnett_p(t: f64, n0: f64, ns: []const f64, df: f64) -> f64 {
    var lam: [32]f64 = zero
    var i = 0usize
    while i < ns.len {
        lam[i] = math.sqrt[f64](ns[i] / (ns[i] + n0))
        i += 1usize
    }
    ret 1.0f64 - pm.mvt_one_factor_upper(math.abs[f64](t), lam[0usize..ns.len], df, true)
}

// adjust = "dunnettx" (the default for trt.vs.ctrl): emmeans' approximation to Dunnett's p for m comparisons, 1 - (w ptukey(sqrt 2 |t|, (1 + sqrt(1 + 8 m)) / 2, df) + (1 - w) pf(t^2, 1, df)^m) with w = (m - 1) / m
fn p_dunnettx(t: f64, m: f64, df: f64) -> f64 {
    let x = math.abs[f64](t)
    let tk = nb.ptukey(x * math.sqrt[f64](2.0f64), 1.0f64, (1.0f64 + math.sqrt[f64](1.0f64 + 8.0f64 * m)) / 2.0f64, df, true, false)
    let sd = math.pow[f64](nb.pf(x * x, 1.0f64, df, true, false), m)
    let w = (m - 1.0f64) / m
    ret 1.0f64 - (w * tk + (1.0f64 - w) * sd)
}

// contrast(emmeans(lm(y ~ g * h), "g"), method, adjust = "none") (and the adjustments of `contrast_oneway`, same ten values per contrast): the marginal mean of level i of g is the equal-weight average of its nh cell means, taken from the cell-means fit of the k nh cells
// (every cell must hold an observation); returns the number of contrasts, 0 when the fit fails
fn contrast_twoway_int(a: *mem.Arena, grp: []const f64, hgrp: []const f64, y: []const f64, n: usize, k: usize, nh: usize, kind: usize, out: []f64) -> usize {
    let q = k * nh
    let (x, e1) = mem.alloc[f64](a, n * q)
    let (cf, e2) = mem.alloc[f64](a, k * k * k)
    let (l, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var z = 0usize
    while z < n * q {
        x[z] = 0.0f64
        z += 1usize
    }
    var i = 0usize
    while i < n {
        x[(usize(grp[i]) * nh + usize(hgrp[i])) * n + i] = 1.0f64
        i += 1usize
    }
    let (fm, fe) = fit(a, x, y, n, q)
    if fe != ok { ret 0usize }
    let m = contrast_coefs(kind, k, cf)
    if m == 0usize { ret 0usize }
    let df = f64(n - q)
    // the Scheffe rank is k - 1; emmeans' own rank for the eff and del.eff matrices in an interaction model came out as k on some data and k - 1 on others, which looks like a numerical tolerance, so those two are not compared
    let srank = f64(k - 1usize)
    var j = 0usize
    while j < m {
        var c = 0usize
        while c < q {
            l[c] = cf[(c / nh) * m + j] / f64(nh)
            c += 1usize
        }
        let est = estimate(&fm, l)
        let se = math.sqrt[f64](variance(&fm, l))
        let t = est / se
        out[10usize * j] = est
        out[10usize * j + 1usize] = se
        out[10usize * j + 2usize] = df
        out[10usize * j + 3usize] = t
        out[10usize * j + 4usize] = p_t(t, df)
        out[10usize * j + 5usize] = 0.0f64 / 0.0f64
        if kind <= 1usize { out[10usize * j + 5usize] = p_tukey(t, f64(k), df) }
        j += 1usize
    }
    var pv: [64]f64 = zero
    j = 0usize
    while j < m {
        pv[j] = out[10usize * j + 4usize]
        out[10usize * j + 6usize] = p_scheffe(out[10usize * j + 3usize], srank, df)
        out[10usize * j + 7usize] = p_bonferroni(pv[j], f64(m))
        out[10usize * j + 8usize] = p_sidak(pv[j], f64(m))
        j += 1usize
    }
    holm(pv[0usize..m])
    j = 0usize
    while j < m {
        out[10usize * j + 9usize] = pv[j]
        j += 1usize
    }
    ret m
}

// contrast(emmeans(glm(y ~ g, family), "g"), method, adjust = "none") for a one-way layout, fam 0 binomial with a 0/1 response (logit) or 1 Poisson (log), on the link scale and on the response scale (contrast(regrid(...))): the group means are logistic(beta_i) or exp(beta_i) from the
// cell-means fit, a contrast of the logits has variance L' V L, and a contrast of the means the delta-method variance (L' diag(dmu / deta) V diag(dmu / deta) L); tests are z (df infinite). For contrast j out[8 j ..] = the link estimate, its
// standard error, z, the two-sided p, then the same four on the response scale; returns the number of contrasts, 0 when a fit fails
fn contrast_glm_oneway(a: *mem.Arena, grp: []const f64, y: []const f64, n: usize, k: usize, kind: usize, fam: usize, out: []f64) -> usize {
    let (x, e1) = mem.alloc[f64](a, n * k)
    let (cf, e2) = mem.alloc[f64](a, k * k * k)
    let (l, e3) = mem.alloc[f64](a, k)
    let (l2, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var z = 0usize
    while z < n * k {
        x[z] = 0.0f64
        z += 1usize
    }
    var i = 0usize
    while i < n {
        x[usize(grp[i]) * n + i] = 1.0f64
        i += 1usize
    }
    var gm: Lm = zero
    var ge = ok
    if fam == 0usize {
        let (g0, e0) = logit_glm(a, x, y, n, k)
        gm = g0
        ge = e0
    } else {
        let (g1, e1b) = pois_glm_lm(a, x, y, n, k)
        gm = g1
        ge = e1b
    }
    if ge != ok { ret 0usize }
    let m = contrast_coefs(kind, k, cf)
    if m == 0usize { ret 0usize }
    var j = 0usize
    while j < m {
        var lv = 0usize
        while lv < k {
            l[lv] = cf[lv * m + j]
            var dm = 0.0f64
            if fam == 0usize {
                let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - gm.beta[lv]))
                dm = pr * (1.0f64 - pr)
            } else {
                dm = math.exp[f64](gm.beta[lv])
            }
            l2[lv] = l[lv] * dm
            lv += 1usize
        }
        let est = estimate(&gm, l)
        let se = math.sqrt[f64](variance(&gm, l))
        var pe = 0.0f64
        lv = 0usize
        while lv < k {
            if fam == 0usize { pe += l[lv] / (1.0f64 + math.exp[f64](0.0f64 - gm.beta[lv])) } else { pe += l[lv] * math.exp[f64](gm.beta[lv]) }
            lv += 1usize
        }
        let se2 = math.sqrt[f64](variance(&gm, l2))
        out[8usize * j] = est
        out[8usize * j + 1usize] = se
        out[8usize * j + 2usize] = est / se
        out[8usize * j + 3usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](est / se), 0.0f64, 1.0f64, true, false)
        out[8usize * j + 4usize] = pe
        out[8usize * j + 5usize] = se2
        out[8usize * j + 6usize] = pe / se2
        out[8usize * j + 7usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](pe / se2), 0.0f64, 1.0f64, true, false)
        j += 1usize
    }
    ret m
}

fn contrast_logit_oneway(a: *mem.Arena, grp: []const f64, y: []const f64, n: usize, k: usize, kind: usize, out: []f64) -> usize { ret contrast_glm_oneway(a, grp, y, n, k, kind, 0usize, out) }
