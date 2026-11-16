// R hetGP mleHomGP with known hyperparameters: the homoskedastic Gaussian-process regression with the Gaussian kernel k(x, x') = exp(-sum (x_d - x'_d)^2 / theta_d), a nugget g (plus the jitter sqrt(eps) hetGP adds to the diagonal), a profiled constant mean beta0 and variance nu_hat; the log-likelihood and the predictive mean, latent variance sd2 and nugget variance at new points.
//
// Not here: hyperparameter optimisation, the Matern kernels, heteroskedastic noise models, replicated designs, derivatives and the sequential design criteria.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// x is n by d, xt is m by d; out: beta0, nu_hat, log-likelihood, then m means, m sd2, m nugget variances
fn homgp(a: *mem.Arena, x: []const f64, z: []const f64, n: usize, d: usize, theta: []const f64, g: f64, xt: []const f64, m: usize, out: []f64) -> err {
    let (kk, e1) = mem.alloc[f64](a, n * n)
    let (kv, e2) = mem.alloc[f64](a, n)
    let (ki1, e3) = mem.alloc[f64](a, n)
    let (kiz, e4) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                let dd = x[i * d + c] - x[j * d + c]
                s += dd * dd / theta[c]
                c += 1usize
            }
            kk[i * n + j] = math.exp[f64](0.0f64 - s)
            if i == j { kk[i * n + j] += g + 1.4901161193847656e-8f64 }
            j += 1usize
        }
        i += 1usize
    }
    let (ki, ge) = gp.invert(a, kk, n)
    if ge != ok { ret ge }
    // log determinant by the diagonal of an LDL-free Cholesky
    let (ch, e5) = mem.alloc[f64](a, n * n)
    if e5 != ok { ret e5 }
    var logdet = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = kk[i * n + j]
            var l = 0usize
            while l < j {
                s -= ch[i * n + l] * ch[j * n + l]
                l += 1usize
            }
            if i == j {
                ch[i * n + i] = math.sqrt[f64](s)
                logdet += 2.0f64 * math.log[f64](ch[i * n + i])
            } else {
                ch[i * n + j] = s / ch[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    var s11 = 0.0f64
    var s1z = 0.0f64
    i = 0usize
    while i < n {
        var a1 = 0.0f64
        var az = 0.0f64
        var j = 0usize
        while j < n {
            a1 += ki[i * n + j]
            az += ki[i * n + j] * z[j]
            j += 1usize
        }
        ki1[i] = a1
        s11 += a1
        s1z += az
        i += 1usize
    }
    let beta0 = s1z / s11
    var q = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        var r = 0.0f64
        while j < n {
            r += ki[i * n + j] * (z[j] - beta0)
            j += 1usize
        }
        kiz[i] = r
        q += (z[i] - beta0) * r
        i += 1usize
    }
    let nf = f64(n)
    let nu = q / nf
    out[0usize] = beta0
    out[1usize] = nu
    out[2usize] = 0.0f64 - nf / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - nf / 2.0f64 * math.log[f64](nu) - 0.5f64 * logdet - nf / 2.0f64
    var t = 0usize
    while t < m {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                let dd = xt[t * d + c] - x[i * d + c]
                s += dd * dd / theta[c]
                c += 1usize
            }
            kv[i] = math.exp[f64](0.0f64 - s)
            i += 1usize
        }
        var mean = beta0
        var kk2 = 0.0f64
        var k1 = 0.0f64
        i = 0usize
        while i < n {
            mean += kv[i] * kiz[i]
            var j = 0usize
            var r = 0.0f64
            while j < n {
                r += ki[i * n + j] * kv[j]
                j += 1usize
            }
            kk2 += kv[i] * r
            k1 += kv[i] * ki1[i]
            i += 1usize
        }
        out[3usize + t] = mean
        out[3usize + m + t] = nu * (1.0f64 - kk2 + (1.0f64 - k1) * (1.0f64 - k1) / s11)
        out[3usize + 2usize * m + t] = nu * g
        t += 1usize
    }
    ret ok
}
