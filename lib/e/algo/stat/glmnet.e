// R glmnet, the gaussian family: the elastic-net objective
// `(1 / 2n) sum (y - b0 - x b)^2 + lambda sum vf_j ((1 - alpha) / 2 b_j^2 + alpha |b_j|)` by cyclic coordinate
// descent run to a tight tolerance, with glmnet's conventions (y is scaled to unit variance inside, which makes the
// ridge part of the penalty `lambda (1 - alpha) / sd(y)`): columns standardised to unit variance (divisor n)
// inside when `standardize`, the penalty factors rescaled to sum to p, coefficients answered on the original scale
// and the intercept from the means. Answers the exact minimiser, which glmnet reaches to its `thresh` of 1e-7.
//
// Not here: the lambda path generator, other families, weights, offsets, bounds, cv.glmnet, relax, predict.

use e.math
use e.mem

fn soft(z: f64, g: f64) -> f64 {
    if z > g { ret z - g }
    if z < 0.0f64 - g { ret z + g }
    ret 0.0f64
}

// x is n by p column-major; lambdas are visited in order with warm starts; coef receives, for lambda k, the
// intercept at k * (p + 1) and the p slopes after it
fn gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    let nf = f64(n)
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p)
    let (r, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / nf
    var yv = 0.0f64
    i = 0usize
    while i < n {
        yv += (y[i] - ybar) * (y[i] - ybar)
        i += 1usize
    }
    let ys = math.sqrt[f64](yv / nf)
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += x[j * n + i]
            i += 1usize
        }
        m = m / nf
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += (x[j * n + i] - m) * (x[j * n + i] - m)
            i += 1usize
        }
        var s = 1.0f64
        if standardize { s = math.sqrt[f64](v / nf) }
        sc[j] = s
        mx[j] = m
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - m) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        b[j] = 0.0f64
        j += 1usize
    }
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        i = 0usize
        while i < n {
            var f = 0.0f64
            j = 0usize
            while j < p {
                f += xs[j * n + i] * b[j]
                j += 1usize
            }
            r[i] = y[i] - ybar - f
            i += 1usize
        }
        var sweep = 0usize
        while sweep < 100000usize {
            var dmax = 0.0f64
            j = 0usize
            while j < p {
                var cj = 0.0f64
                var xr = 0.0f64
                i = 0usize
                while i < n {
                    cj += xs[j * n + i] * xs[j * n + i]
                    xr += xs[j * n + i] * r[i]
                    i += 1usize
                }
                cj = cj / nf
                let z = xr / nf + cj * b[j]
                let nb = soft(z, lam * alpha * pf[j]) / (cj + lam * (1.0f64 - alpha) * pf[j] / ys)
                let d = nb - b[j]
                if d != 0.0f64 {
                    i = 0usize
                    while i < n {
                        r[i] -= d * xs[j * n + i]
                        i += 1usize
                    }
                    b[j] = nb
                    if math.abs[f64](d) * math.sqrt[f64](cj) > dmax { dmax = math.abs[f64](d) * math.sqrt[f64](cj) }
                }
                j += 1usize
            }
            if dmax < 1.0e-14f64 { break }
            sweep += 1usize
        }
        var b0 = ybar
        j = 0usize
        while j < p {
            coef[k * (p + 1usize) + 1usize + j] = b[j] / sc[j]
            b0 -= b[j] / sc[j] * mx[j]
            j += 1usize
        }
        coef[k * (p + 1usize)] = b0
        k += 1usize
    }
    ret ok
}

// glmnet's automatic lambda sequence (gaussian): lambda_max = max over j of |x_j' (y - ybar)| / (n max(alpha, 0.001) vf_j) with the columns centred and (when standardize) scaled to unit variance (divisor n)
// and the penalty factors rescaled to sum to p, then nlambda values equally spaced on the log scale down to lambda_max times 1e-4 (1e-2 when n < p); returns the sequence in out
fn lambda_path(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let nf = f64(n)
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / nf
    var vsum = 0.0f64
    var j = 0usize
    while j < p {
        vsum += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var mj = 0.0f64
        i = 0usize
        while i < n {
            mj += x[j * n + i]
            i += 1usize
        }
        mj = mj / nf
        var ss = 0.0f64
        var sxy = 0.0f64
        i = 0usize
        while i < n {
            ss += (x[j * n + i] - mj) * (x[j * n + i] - mj)
            sxy += (x[j * n + i] - mj) * (y[i] - ybar)
            i += 1usize
        }
        var g = sxy / nf
        if standardize { g = g / math.sqrt[f64](ss / nf) }
        let vj = vf[j] * f64(p) / vsum
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let v = math.abs[f64](g) / (al * vj)
            if v > lmax { lmax = v }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
    ret ok
}
