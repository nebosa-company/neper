// R MCMCpack samplers on the Scythe Mersenne-Twister the package's C++ uses (seeded from the integer `seed`, which MCMCpack hands the generator
// as rep(seed, 6)): MCMCregress (Gibbs, with the Chib marginal likelihood), MCMClogit and MCMCpoisson (random-walk Metropolis). Matrices are row-major slices.
//
// Not here: the Laplace marginal likelihood, L'Ecuyer streams, and the samplers beyond these.

use e.math
use e.math.nmath as nm
use e.mem

error NotPd

const NMT: usize = 624usize
const MMT: usize = 398usize

// Scythe's mersenne (its M is 398, not 397), the polar-method normal with its stored second variate, and the uniform on (0, 1) from (int + 0.5) / 2^32
type Sc = struct { mt: [624]u64, mti: usize, cnt: i64, x2: f64 }

fn sc_seed(r: *Sc, s: u64) {
    let mask = 4294967295u64
    r.mt[0usize] = s & mask
    var i = 1usize
    while i < NMT {
        let prev = r.mt[i - 1usize]
        r.mt[i] = (1812433253u64 * (prev ^ (prev >> 30u64)) + u64(i)) & mask
        i += 1usize
    }
    r.mti = NMT
    r.cnt = 1i64
    r.x2 = 0.0f64
}

fn sc_int32(r: *Sc) -> u64 {
    if r.mti >= NMT {
        var kk = 0usize
        while kk < NMT - MMT {
            let y = (r.mt[kk] & 2147483648u64) | (r.mt[kk + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            r.mt[kk] = r.mt[kk + MMT] ^ (y >> 1u64) ^ mag
            kk += 1usize
        }
        while kk < NMT - 1usize {
            let y = (r.mt[kk] & 2147483648u64) | (r.mt[kk + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            r.mt[kk] = r.mt[kk + MMT - NMT] ^ (y >> 1u64) ^ mag
            kk += 1usize
        }
        let y = (r.mt[NMT - 1usize] & 2147483648u64) | (r.mt[0usize] & 2147483647u64)
        var mag = 0u64
        if (y & 1u64) != 0u64 { mag = 2567483615u64 }
        r.mt[NMT - 1usize] = r.mt[MMT - 1usize] ^ (y >> 1u64) ^ mag
        r.mti = 0usize
    }
    var y = r.mt[r.mti]
    r.mti += 1usize
    y = y ^ (y >> 11u64)
    y = y ^ (((y << 7u64) & 4294967295u64) & 2636928640u64)
    y = y ^ (((y << 15u64) & 4294967295u64) & 4022730752u64)
    y = y ^ (y >> 18u64)
    ret y
}

fn sc_unif(r: *Sc) -> f64 { ret (f64(sc_int32(r)) + 0.5f64) * (1.0f64 / 4294967296.0f64) }

fn sc_norm1(r: *Sc) -> f64 {
    if r.cnt == 1i64 {
        var nu1 = 0.0f64
        var nu2 = 0.0f64
        var rs = 0.0f64
        var go = true
        while go {
            nu1 = -1.0f64 + 2.0f64 * sc_unif(r)
            nu2 = -1.0f64 + 2.0f64 * sc_unif(r)
            rs = nu1 * nu1 + nu2 * nu2
            go = rs >= 1.0f64 || rs == 0.0f64
        }
        let st = math.sqrt[f64](-2.0f64 * math.log[f64](rs) / rs)
        r.x2 = nu2 * st
        r.cnt = 2i64
        ret nu1 * st
    }
    r.cnt = 1i64
    ret r.x2
}

fn sc_rnorm(r: *Sc, mean: f64, sd: f64) -> f64 { ret mean + sc_norm1(r) * sd }

// Marsaglia-Tsang-free gamma of the package: the rejection scheme of rgamma1 for alpha > 1
fn sc_gamma1(r: *Sc, alpha: f64) -> f64 {
    let b = alpha - 1.0f64
    let c = 3.0f64 * alpha - 0.75f64
    while true {
        let u = sc_unif(r)
        let v = sc_unif(r)
        let w = u * (1.0f64 - u)
        let y = math.sqrt[f64](c / w) * (u - 0.5f64)
        let x = b + y
        if x > 0.0f64 {
            let z = 64.0f64 * math.pow[f64](v, 2.0f64) * math.pow[f64](w, 3.0f64)
            if z <= 1.0f64 - 2.0f64 * math.pow[f64](y, 2.0f64) / x { ret x }
            if 2.0f64 * (b * math.log[f64](x / b) - y) >= math.log[f64](z) { ret x }
        }
    }
    ret 0.0f64
}

fn sc_rgamma(r: *Sc, shape: f64, rate: f64) -> f64 {
    if shape > 1.0f64 { ret sc_gamma1(r, shape) / rate }
    if shape == 1.0f64 { ret (0.0f64 - math.log[f64](sc_unif(r))) / rate }
    let g = sc_gamma1(r, shape + 1.0f64)
    ret g * math.pow[f64](sc_unif(r), 1.0f64 / shape) / rate
}

fn sc_rigamma(r: *Sc, alpha: f64, beta: f64) -> f64 { ret math.pow[f64](sc_rgamma(r, alpha, beta), -1.0f64) }

// lower Cholesky factor of a symmetric positive-definite p by p matrix; false when not positive definite
fn chol(a: []const f64, p: usize, l: []f64) -> bool {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            l[i * p + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j <= i {
            var s = a[i * p + j]
            var k = 0usize
            while k < j {
                s -= l[i * p + k] * l[j * p + k]
                k += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret false }
                l[i * p + i] = math.sqrt[f64](s)
            } else {
                l[i * p + j] = s / l[j * p + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// inverse of a symmetric positive-definite matrix from its Cholesky factor; the log determinant comes back through ld
fn inv_pd(a: *mem.Arena, m: []const f64, p: usize, out: []f64, ld: *f64) -> err {
    let (l, e1) = mem.alloc[f64](a, p * p)
    let (li, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if !chol(m, p, l) { ret NotPd }
    var d = 0.0f64
    var i = 0usize
    while i < p {
        d += 2.0f64 * math.log[f64](l[i * p + i])
        i += 1usize
    }
    *ld = d
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            li[i * p + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j <= i {
            var s = 0.0f64
            if i == j { s = 1.0f64 }
            var k = j
            while k < i {
                s -= l[i * p + k] * li[k * p + j]
                k += 1usize
            }
            li[i * p + j] = s / l[i * p + i]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += li[k * p + i] * li[k * p + j]
                k += 1usize
            }
            out[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// log density of N(mu, inverse(prec)) at x
fn lndmvn_prec(a: *mem.Arena, x: []const f64, mu: []const f64, prec: []const f64, p: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let (inv, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret nan }
    var ld = 0.0f64
    if inv_pd(a, prec, p, inv, &ld) != ok { ret nan }
    var q = 0.0f64
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            q += (x[i] - mu[i]) * prec[i * p + j] * (x[j] - mu[j])
            j += 1usize
        }
        i += 1usize
    }
    ret -f64(p) / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) + 0.5f64 * ld - 0.5f64 * q
}

fn lndnorm(x: f64, mean: f64, sd: f64) -> f64 {
    let z = (x - mean) / sd
    ret -(0.9189385332046728f64 + 0.5f64 * z * z + math.log[f64](sd))
}

fn dig(theta: f64, sh: f64, sc: f64) -> f64 {
    ret math.exp[f64](sh * math.log[f64](sc) - lgam(sh) - (sh + 1.0f64) * math.log[f64](theta) - sc / theta)
}

fn lgam(x: f64) -> f64 { ret nm.lgammafn(x) }

// MCMCregress: Y = X beta + e, beta ~ N(b0, inverse(B0)), sigma2 ~ IG(c0/2, d0/2). out holds nstore rows of (beta, sigma2); ml receives the Chib log marginal likelihood when chib
fn regress(a: *mem.Arena, g: *Sc, y: []const f64, x: []const f64, n: usize, k: usize, beta0: []const f64, b0: []const f64, bb0: []const f64, c0: f64, d0: f64, burnin: usize, mcmc: usize, thin: usize, chib: bool, out: []f64, ml: *f64) -> err {
    let tot = burnin + mcmc
    let nstore = mcmc / thin
    let (xpx, e1) = mem.alloc[f64](a, k * k)
    let (xpy, e2) = mem.alloc[f64](a, k)
    let (beta, e3) = mem.alloc[f64](a, k)
    let (m1, e4) = mem.alloc[f64](a, k * k)
    let (sb, e5) = mem.alloc[f64](a, k * k)
    let (cc, e6) = mem.alloc[f64](a, k * k)
    let (rhs, e7) = mem.alloc[f64](a, k)
    let (hat, e8) = mem.alloc[f64](a, k)
    let (zz, e9) = mem.alloc[f64](a, k)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += x[t * k + i] * x[t * k + j]
                t += 1usize
            }
            xpx[i * k + j] = s
            j += 1usize
        }
        var sy = 0.0f64
        var t = 0usize
        while t < n {
            sy += x[t * k + i] * y[t]
            t += 1usize
        }
        xpy[i] = sy
        beta[i] = beta0[i]
        i += 1usize
    }
    var count = 0usize
    var iter = 0usize
    var ld = 0.0f64
    while iter < tot {
        var sse = 0.0f64
        var t = 0usize
        while t < n {
            var eta = 0.0f64
            i = 0usize
            while i < k {
                eta += x[t * k + i] * beta[i]
                i += 1usize
            }
            let r = y[t] - eta
            sse += r * r
            t += 1usize
        }
        let s2 = sc_rigamma(g, (c0 + f64(n)) * 0.5f64, (d0 + sse) * 0.5f64)
        let inv_s2 = 1.0f64 / s2
        i = 0usize
        while i < k * k {
            m1[i] = bb0[i] + xpx[i] * inv_s2
            i += 1usize
        }
        if inv_pd(a, m1, k, sb, &ld) != ok { ret NotPd }
        if !chol(sb, k, cc) { ret NotPd }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += bb0[i * k + j] * b0[j]
                j += 1usize
            }
            rhs[i] = s + xpy[i] * inv_s2
            i += 1usize
        }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += sb[i * k + j] * rhs[j]
                j += 1usize
            }
            hat[i] = s
            i += 1usize
        }
        i = 0usize
        while i < k {
            zz[i] = sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var s = hat[i]
            var j = 0usize
            while j <= i {
                s += cc[i * k + j] * zz[j]
                j += 1usize
            }
            beta[i] = s
            i += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            i = 0usize
            while i < k {
                out[count * (k + 1usize) + i] = beta[i]
                i += 1usize
            }
            out[count * (k + 1usize) + k] = s2
            count += 1usize
        }
        iter += 1usize
    }
    if chib {
        var s2star = 0.0f64
        let (bstar, e10) = mem.alloc[f64](a, k)
        if e10 != ok { ret e10 }
        i = 0usize
        while i < k {
            bstar[i] = 0.0f64
            i += 1usize
        }
        var q = 0usize
        while q < nstore {
            s2star += out[q * (k + 1usize) + k]
            i = 0usize
            while i < k {
                bstar[i] += out[q * (k + 1usize) + i]
                i += 1usize
            }
            q += 1usize
        }
        s2star = s2star / f64(nstore)
        i = 0usize
        while i < k {
            bstar[i] = bstar[i] / f64(nstore)
            i += 1usize
        }
        var dsum = 0.0f64
        q = 0usize
        while q < nstore {
            var sse = 0.0f64
            var t = 0usize
            while t < n {
                var eta = 0.0f64
                i = 0usize
                while i < k {
                    eta += x[t * k + i] * out[q * (k + 1usize) + i]
                    i += 1usize
                }
                let r = y[t] - eta
                sse += r * r
                t += 1usize
            }
            dsum += dig(s2star, (c0 + f64(n)) * 0.5f64, (d0 + sse) * 0.5f64)
            q += 1usize
        }
        let pdf_s2 = math.log[f64](dsum / f64(nstore))
        i = 0usize
        while i < k * k {
            m1[i] = bb0[i] + xpx[i] / s2star
            i += 1usize
        }
        let (bn_var, e11) = mem.alloc[f64](a, k * k)
        if e11 != ok { ret e11 }
        if inv_pd(a, m1, k, bn_var, &ld) != ok { ret NotPd }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += bb0[i * k + j] * b0[j]
                j += 1usize
            }
            rhs[i] = s + xpy[i] / s2star
            i += 1usize
        }
        let (bn, e12) = mem.alloc[f64](a, k)
        if e12 != ok { ret e12 }
        i = 0usize
        while i < k {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += bn_var[i * k + j] * rhs[j]
                j += 1usize
            }
            bn[i] = s
            i += 1usize
        }
        var pdf_beta = 0.0f64
        if k == 1usize { pdf_beta = lndnorm(bstar[0usize], bn[0usize], math.sqrt[f64](bn_var[0usize])) } else { pdf_beta = lndmvn_prec(a, bstar, bn, m1, k) }
        var ll = 0.0f64
        let sstar = math.sqrt[f64](s2star)
        var t = 0usize
        while t < n {
            var eta = 0.0f64
            i = 0usize
            while i < k {
                eta += x[t * k + i] * bstar[i]
                i += 1usize
            }
            ll += lndnorm(y[t], eta, sstar)
            t += 1usize
        }
        var lp = math.log[f64](dig(s2star, c0 / 2.0f64, d0 / 2.0f64))
        if k == 1usize { lp += lndnorm(bstar[0usize], b0[0usize], 1.0f64 / math.sqrt[f64](bb0[0usize])) } else { lp += lndmvn_prec(a, bstar, b0, bb0, k) }
        *ml = ll + lp - pdf_beta - pdf_s2
    }
    ret ok
}

// log posterior of the logit (kind 0) or Poisson (kind 1) regression with the N(b0, inverse(B0)) prior (dropped when B0[0, 0] is zero)
fn glm_logpost(a: *mem.Arena, kind: usize, y: []const f64, x: []const f64, n: usize, k: usize, beta: []const f64, b0: []const f64, bb0: []const f64) -> f64 {
    var ll = 0.0f64
    var t = 0usize
    while t < n {
        var eta = 0.0f64
        var i = 0usize
        while i < k {
            eta += x[t * k + i] * beta[i]
            i += 1usize
        }
        if kind == 0usize {
            let p = 1.0f64 / (1.0f64 + math.exp[f64](-eta))
            ll += y[t] * math.log[f64](p) + (1.0f64 - y[t]) * math.log[f64](1.0f64 - p)
        } else {
            ll += y[t] * eta - math.exp[f64](eta)
        }
        t += 1usize
    }
    if bb0[0usize] != 0.0f64 {
        // Scythe's lndmvn answers NaN for a 1 by 1 matrix, so a one-coefficient model with a proper prior never accepts a proposal
        if k == 1usize { ret 0.0f64 / 0.0f64 }
        ll += lndmvn_prec(a, beta, b0, bb0, k)
    }
    ret ll
}

// MCMClogit (kind 0) and MCMCpoisson (kind 1): proposal beta + chol(tune inverse(B0 + inverse(V)) tune) z; tune is the length-k scale vector (a diagonal matrix in R)
fn metrop_glm(a: *mem.Arena, g: *Sc, kind: usize, y: []const f64, x: []const f64, n: usize, k: usize, tune: []const f64, beta0: []const f64, b0: []const f64, bb0: []const f64, vv: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let (vi, e1) = mem.alloc[f64](a, k * k)
    let (m1, e2) = mem.alloc[f64](a, k * k)
    let (pv, e3) = mem.alloc[f64](a, k * k)
    let (pc, e4) = mem.alloc[f64](a, k * k)
    let (beta, e5) = mem.alloc[f64](a, k)
    let (can, e6) = mem.alloc[f64](a, k)
    let (zz, e7) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var ld = 0.0f64
    if inv_pd(a, vv, k, vi, &ld) != ok { ret NotPd }
    var i = 0usize
    while i < k * k {
        m1[i] = bb0[i] + vi[i]
        i += 1usize
    }
    if inv_pd(a, m1, k, pv, &ld) != ok { ret NotPd }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            pv[i * k + j] = tune[i] * pv[i * k + j] * tune[j]
            j += 1usize
        }
        beta[i] = beta0[i]
        i += 1usize
    }
    if !chol(pv, k, pc) { ret NotPd }
    var cur = glm_logpost(a, kind, y, x, n, k, beta, b0, bb0)
    let tot = burnin + mcmc
    var count = 0usize
    var iter = 0usize
    while iter < tot {
        i = 0usize
        while i < k {
            zz[i] = sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var s = beta[i]
            var j = 0usize
            while j <= i {
                s += pc[i * k + j] * zz[j]
                j += 1usize
            }
            can[i] = s
            i += 1usize
        }
        let lc = glm_logpost(a, kind, y, x, n, k, can, b0, bb0)
        let ratio = math.exp[f64](lc - cur)
        if sc_unif(g) < ratio {
            i = 0usize
            while i < k {
                beta[i] = can[i]
                i += 1usize
            }
            cur = lc
        }
        if iter >= burnin && iter % thin == 0usize {
            i = 0usize
            while i < k {
                out[count * k + i] = beta[i]
                i += 1usize
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}
