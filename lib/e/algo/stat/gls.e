// R nlme::gls with a fixed correlation structure: generalised least squares for one group,
// `beta = (X' S^-1 X)^-1 X' S^-1 y`, the residual standard error `sigma` (divisor `n - p` for REML, `n` for ML)
// and the maximised log-likelihood. The correlation matrix `S` is corAR1 (`rho^|t_i - t_j|`), corCompSymm
// (`rho` off the diagonal) or corExp (`exp(-|t_i - t_j| / range)`) at a given parameter.
//
// Not here: estimating the correlation parameters, several groups, variance functions, lme, lmList, the other
// correlation classes, anova between models, intervals, nls self-start models.

use e.algo.stat.psych as ps
use e.math
use e.mem

type Fit = struct { sigma: f64, loglik: f64 }

// kind 0 AR1, 1 compound symmetry, 2 exponential
fn corr_matrix(kind: u8, par: f64, t: []const f64, s: []f64) {
    let n = t.len
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let d = math.abs[f64](t[i] - t[j])
            var v = 1.0f64
            if i != j {
                if kind == 0u8 { v = math.pow[f64](par, d) } else if kind == 1u8 { v = par } else { v = math.exp[f64](0.0f64 - d / par) }
            }
            s[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// x is n by p column-major; coef receives p values
fn gls(a: *mem.Arena, x: []const f64, y: []const f64, t: []const f64, n: usize, p: usize, kind: u8, par: f64, reml: bool, coef: []f64) -> (Fit, err) {
    var empty: Fit = zero
    let (s, e1) = mem.alloc[f64](a, n * n)
    let (si, e2) = mem.alloc[f64](a, n * n)
    let (xtx, e3) = mem.alloc[f64](a, p * p)
    let (xtxi, e4) = mem.alloc[f64](a, p * p)
    let (xty, e5) = mem.alloc[f64](a, p)
    let (sx, e6) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (empty, e1) }
    corr_matrix(kind, par, t, s)
    if !ps.invert(a, s, n, si) { ret (empty, Singular) }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            var v = 0.0f64
            var k = 0usize
            while k < n {
                v += si[i * n + k] * x[j * n + k]
                k += 1usize
            }
            sx[j * n + i] = v
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var v = 0.0f64
            var i = 0usize
            while i < n {
                v += x[j * n + i] * sx[k * n + i]
                i += 1usize
            }
            xtx[j * p + k] = v
            k += 1usize
        }
        var v = 0.0f64
        var i = 0usize
        while i < n {
            v += sx[j * n + i] * y[i]
            i += 1usize
        }
        xty[j] = v
        j += 1usize
    }
    if !ps.invert(a, xtx, p, xtxi) { ret (empty, Singular) }
    j = 0usize
    while j < p {
        var v = 0.0f64
        var k = 0usize
        while k < p {
            v += xtxi[j * p + k] * xty[k]
            k += 1usize
        }
        coef[j] = v
        j += 1usize
    }
    // rss = r' S^-1 r
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        var ri = y[i]
        j = 0usize
        while j < p {
            ri -= x[j * n + i] * coef[j]
            j += 1usize
        }
        var k = 0usize
        while k < n {
            var rk = y[k]
            j = 0usize
            while j < p {
                rk -= x[j * n + k] * coef[j]
                j += 1usize
            }
            rss += ri * si[i * n + k] * rk
            k += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    let pf = f64(p)
    let ldet = ps.logdet(a, s, n)
    let two_pi = 2.0f64 * 3.141592653589793f64
    if reml {
        let s2 = rss / (nf - pf)
        let ll = 0.0f64 - (nf - pf) / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - 0.5f64 * ps.logdet(a, xtx, p) - (nf - pf) / 2.0f64
        ret (Fit { sigma: math.sqrt[f64](s2), loglik: ll }, ok)
    }
    let s2 = rss / nf
    ret (Fit { sigma: math.sqrt[f64](s2), loglik: 0.0f64 - nf / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - nf / 2.0f64 }, ok)
}

error Singular
