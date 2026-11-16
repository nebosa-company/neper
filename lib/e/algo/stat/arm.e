// R arm: logit and invlogit, se.coef of a linear model, and binned.resids (the binned-residual table behind binnedplot).
//
// Not here: sim, bayesglm, discrete, corrplot data and standardize.

use e.algo.stat.carlmtest as ols
use e.algo.stat.desctools as dt
use e.math
use e.mem

fn logit(p: f64) -> f64 { ret math.log[f64](p / (1.0f64 - p)) }

fn invlogit(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

// se.coef(lm): sqrt(diag(sigma^2 (X'X)^-1)) with sigma^2 = RSS / (n - p), into out (p values); x is n by p row-major
fn se_coef(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret e }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    i = 0usize
    while i < p {
        out[i] = math.sqrt[f64](s2 * f.xtx_inv[i * p + i])
        i += 1usize
    }
    ret ok
}

// binned.resids(x, y, nclass)$binned: rows of (xbar, ybar, n, x.lo, x.hi, 2se) into out (at most nclass rows of 6); returns the number of bins
fn binned_resids(a: *mem.Arena, x: []const f64, y: []const f64, nclass0: usize, out: []f64) -> usize {
    let n = x.len
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0usize }
    var nclass = nclass0
    var i = 1usize
    while i < nclass {
        if n * i / nclass == 0usize { nclass = 1usize }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    let (br, e2) = mem.alloc[f64](a, nclass + 1usize)
    if e2 != ok { ret 0usize }
    var nb = 0usize
    br[0usize] = 0.0f64 - inf
    nb = 1usize
    if nclass > 1usize {
        var q = 1usize
        while q < nclass {
            let bi = n * q / nclass
            var lo = s[bi - 1usize]
            let hi = s[bi]
            if lo == hi {
                if lo == s[0usize] {
                    lo = 0.0f64 - inf
                } else {
                    var m = 0.0f64 - inf
                    var t = 0usize
                    while t < n {
                        if x[t] < lo && x[t] > m { m = x[t] }
                        t += 1usize
                    }
                    lo = m
                }
            }
            let b = (lo + hi) / 2.0f64
            if b != br[nb - 1usize] {
                br[nb] = b
                nb += 1usize
            }
            q += 1usize
        }
    } else {
        let b = (s[0usize] + s[n - 1usize]) / 2.0f64
        br[nb] = b
        nb += 1usize
    }
    // the last break is +Inf; bins are (br[b], br[b + 1]]
    let bins = nb
    var b = 0usize
    while b < bins {
        var cnt = 0.0f64
        var sx = 0.0f64
        var sy = 0.0f64
        var xlo = inf
        var xhi = 0.0f64 - inf
        var t = 0usize
        while t < n {
            let above = x[t] > br[b]
            var inside = above
            if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
            if inside {
                cnt += 1.0f64
                sx += x[t]
                sy += y[t]
                if x[t] < xlo { xlo = x[t] }
                if x[t] > xhi { xhi = x[t] }
            }
            t += 1usize
        }
        let ybar = sy / cnt
        var sd = 0.0f64
        if cnt > 1.0f64 {
            var ss = 0.0f64
            t = 0usize
            while t < n {
                let above = x[t] > br[b]
                var inside = above
                if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
                if inside { ss += (y[t] - ybar) * (y[t] - ybar) }
                t += 1usize
            }
            sd = math.sqrt[f64](ss / (cnt - 1.0f64))
        }
        out[b * 6usize] = sx / cnt
        out[b * 6usize + 1usize] = ybar
        out[b * 6usize + 2usize] = cnt
        out[b * 6usize + 3usize] = xlo
        out[b * 6usize + 4usize] = xhi
        out[b * 6usize + 5usize] = 2.0f64 * sd / math.sqrt[f64](cnt)
        b += 1usize
    }
    ret bins
}
