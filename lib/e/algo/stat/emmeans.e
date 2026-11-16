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
