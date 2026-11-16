// R MCMCpack density functions: dwish and diwish (Wishart and inverse Wishart with degrees of freedom v and scale matrix S), dinvgamma and ddirichlet.
//
// Not here: the samplers (MCMCregress, MCMClogit, MCMCfactanal and the rest), rwish, riwish, the posterior summaries, Bayes factors, the marginal likelihood approximations.

use e.algo.stat.gparot as gp
use e.math
use e.math.nmath as nm
use e.mem

// log |A| and the inverse of a symmetric positive-definite p by p matrix by Cholesky; returns the log determinant (NaN if not positive definite)
fn chol_logdet(a: []const f64, p: usize, l: []f64) -> f64 {
    var ld = 0.0f64
    var i = 0usize
    while i < p {
        var j = 0usize
        while j <= i {
            var s = a[i * p + j]
            var k = 0usize
            while k < j {
                s -= l[i * p + k] * l[j * p + k]
                k += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret 0.0f64 / 0.0f64 }
                l[i * p + i] = math.sqrt[f64](s)
                ld += 2.0f64 * math.log[f64](l[i * p + i])
            } else {
                l[i * p + j] = s / l[j * p + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ld
}

fn log_gamma_p(x: f64, p: usize) -> f64 {
    var s = f64(p) * f64(p - 1usize) / 4.0f64 * math.log[f64](3.141592653589793f64)
    var j = 0usize
    while j < p {
        s += nm.lgammafn(x - f64(j) / 2.0f64)
        j += 1usize
    }
    ret s
}

fn trace_prod(a: []const f64, b: []const f64, p: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            t += a[i * p + j] * b[j * p + i]
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

// the density (or its log) of W ~ Wishart(v, S); inverse true gives the inverse Wishart density of W with scale matrix S
fn wishart(a: *mem.Arena, w: []const f64, s: []const f64, p: usize, v: f64, inverse: bool, lg: bool) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let (l1, e1) = mem.alloc[f64](a, p * p)
    let (l2, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret nan }
    let ldw = chol_logdet(w, p, l1)
    let lds = chol_logdet(s, p, l2)
    let (wi, e3) = gp.invert(a, w, p)
    let (si, e4) = gp.invert(a, s, p)
    if e3 != ok || e4 != ok { ret nan }
    let pf = f64(p)
    var out = 0.0f64
    if inverse {
        out = v / 2.0f64 * lds - (v + pf + 1.0f64) / 2.0f64 * ldw - trace_prod(s, wi, p) / 2.0f64 - v * pf / 2.0f64 * math.log[f64](2.0f64) - log_gamma_p(v / 2.0f64, p)
    } else {
        out = (v - pf - 1.0f64) / 2.0f64 * ldw - trace_prod(si, w, p) / 2.0f64 - v * pf / 2.0f64 * math.log[f64](2.0f64) - v / 2.0f64 * lds - log_gamma_p(v / 2.0f64, p)
    }
    if lg { ret out }
    ret math.exp[f64](out)
}

fn dinvgamma(x: f64, shape: f64, scale: f64) -> f64 {
    ret math.exp[f64](shape * math.log[f64](scale) - nm.lgammafn(shape) - (shape + 1.0f64) * math.log[f64](x) - scale / x)
}

fn ddirichlet(x: []const f64, alpha: []const f64) -> f64 {
    var s = 0.0f64
    var sa = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (alpha[i] - 1.0f64) * math.log[f64](x[i]) - nm.lgammafn(alpha[i])
        sa += alpha[i]
        i += 1usize
    }
    ret math.exp[f64](s + nm.lgammafn(sa))
}
