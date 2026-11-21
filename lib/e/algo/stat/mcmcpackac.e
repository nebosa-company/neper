// R MCMCpack::MCMCoprobit with mcmc.method "AC" (Albert and Chib): the cut points are drawn by a Metropolis step whose multivariate t proposal is centred on the
// Scythe BFGS minimum of the negative log likelihood, with its Hessian (Scythe hesscdif, step sqrt(sqrt(eps))) as scale; then the latent data and beta as in the
// Cowles sampler. Every finite difference, line search (Scythe linesearch2 and zoom, which draws from the stream) and update follows optimize.h in order.
//
// At most 8 cut-point parameters (ncat up to 9).

use e.algo.stat.mcmcpackord as mo
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.math.dist as dist
use e.mem

error NotConverged

type Ctx = struct { y: []const f64, xb: []const f64, n: usize, ncat: usize, h: f64 }

fn pn1(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

// Scythe epsilon<double>(), the bisection of optimize.h
fn epsilon() -> f64 {
    var del = 0.5f64
    var eps = 0.0f64
    var neweps = 1.0f64
    while del > 0.0f64 {
        if 1.0f64 + neweps > 1.0f64 {
            eps = neweps
            neweps -= del
        } else {
            neweps += del
        }
        del *= 0.5f64
    }
    ret eps
}

fn loglike(c: *Ctx, th: []const f64) -> f64 {
    let m = c.ncat - 1usize
    var gm: [10]f64 = zero
    gm[0usize] = -300.0f64
    gm[m + 1usize] = 300.0f64
    var j = 1usize
    while j < m + 1usize {
        var s = 0.0f64
        var i = 0usize
        while i < j {
            s += math.exp[f64](th[i])
            i += 1usize
        }
        gm[j] = s
        j += 1usize
    }
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        let yi = usize(c.y[i])
        var p = 0.0f64
        if yi == c.ncat {
            p = 1.0f64 - pn1(gm[c.ncat - 1usize] - c.xb[i])
        } else {
            if yi == 1usize {
                p = pn1(gm[1usize] - c.xb[i])
            } else {
                p = pn1(gm[yi] - c.xb[i]) - pn1(gm[yi - 1usize] - c.xb[i])
            }
        }
        ll += math.log[f64](p)
        i += 1usize
    }
    ret ll
}

fn fobj(c: *Ctx, th: []const f64) -> f64 { ret -1.0f64 * loglike(c, th) }

fn gradfdif(c: *Ctx, th: []const f64, m: usize, out: []f64) {
    var tmp: [8]f64 = zero
    let f0 = fobj(c, th)
    var i = 0usize
    while i < m {
        let e = (th[i] + c.h) - th[i]
        var j = 0usize
        while j < m {
            tmp[j] = th[j]
            j += 1usize
        }
        tmp[i] = th[i] + e
        out[i] = (fobj(c, tmp[0usize..m]) - f0) / e
        i += 1usize
    }
}

fn gradls(c: *Ctx, alpha: f64, th: []const f64, p: []const f64, m: usize) -> f64 {
    var t1: [8]f64 = zero
    var t0: [8]f64 = zero
    let e = (alpha + c.h) - alpha
    var i = 0usize
    while i < m {
        t1[i] = th[i] + (alpha + e) * p[i]
        t0[i] = th[i] + alpha * p[i]
        i += 1usize
    }
    ret (fobj(c, t1[0usize..m]) - fobj(c, t0[0usize..m])) / e
}

// Scythe hesscdif: H (m by m row-major) at th
fn hesscdif(c: *Ctx, th: []const f64, m: usize, hm: []f64) {
    let fval = fobj(c, th)
    let h2 = math.sqrt[f64](epsilon())
    let hh = c.h
    var tmp: [8]f64 = zero
    var i = 0usize
    while i < m {
        let ei = (th[i] + hh) - th[i]
        var j = 0usize
        while j < m {
            let ej = (th[j] + hh) - th[j]
            if i == j {
                var k = 0usize
                while k < m {
                    tmp[k] = th[k]
                    k += 1usize
                }
                tmp[i] = th[i] + 2.0f64 * ei
                let f1 = fobj(c, tmp[0usize..m])
                tmp[i] = th[i] + ei
                let f2 = fobj(c, tmp[0usize..m])
                tmp[i] = th[i] - ei
                let f3 = fobj(c, tmp[0usize..m])
                tmp[i] = th[i] - 2.0f64 * ei
                let f4 = fobj(c, tmp[0usize..m])
                hm[i * m + i] = (-1.0f64 * f1 + 16.0f64 * f2 - 30.0f64 * fval + 16.0f64 * f3 - f4) / (12.0f64 * h2)
            } else {
                var k = 0usize
                while k < m {
                    tmp[k] = th[k]
                    k += 1usize
                }
                tmp[i] = th[i] + ei
                tmp[j] = th[j] + ej
                let f1 = fobj(c, tmp[0usize..m])
                tmp[j] = th[j] - ej
                let f2 = fobj(c, tmp[0usize..m])
                tmp[i] = th[i] - ei
                tmp[j] = th[j] + ej
                let f3 = fobj(c, tmp[0usize..m])
                tmp[j] = th[j] - ej
                let f4 = fobj(c, tmp[0usize..m])
                hm[i * m + j] = (f1 - f2 - f3 + f4) / (4.0f64 * h2)
            }
            j += 1usize
        }
        i += 1usize
    }
}

fn zoom(c: *Ctx, lo0: f64, hi0: f64, th: []const f64, p: []const f64, m: usize) -> f64 {
    var lo = lo0
    var hi = hi0
    var aj = (lo + hi) / 2.0f64
    let phi0 = fobj(c, th)
    let fgrad0 = gradls(c, 0.0f64, th, p, m)
    var t1: [8]f64 = zero
    var count = 0usize
    while count < 20usize {
        var i = 0usize
        while i < m {
            t1[i] = th[i] + aj * p[i]
            i += 1usize
        }
        let phij = fobj(c, t1[0usize..m])
        i = 0usize
        while i < m {
            t1[i] = th[i] + lo * p[i]
            i += 1usize
        }
        let philo = fobj(c, t1[0usize..m])
        if phij > phi0 + 0.0001f64 * aj * fgrad0 || phij >= philo {
            hi = aj
        } else {
            let fgj = gradls(c, aj, th, p, m)
            if math.abs[f64](fgj) <= -1.0f64 * 0.5f64 * fgrad0 { ret aj }
            if fgj * (hi - lo) >= 0.0f64 { hi = lo }
            lo = aj
        }
        count += 1usize
    }
    ret aj
}

fn linesearch2(c: *Ctx, g: *ms.Sc, th: []const f64, p: []const f64, m: usize) -> f64 {
    var last = 0.0f64
    var cur = 1.0f64
    let fg0 = gradls(c, 0.0f64, th, p, m)
    var t1: [8]f64 = zero
    var it = 0usize
    while it < 50usize {
        var i = 0usize
        while i < m {
            t1[i] = th[i] + cur * p[i]
            i += 1usize
        }
        let phicur = fobj(c, t1[0usize..m])
        i = 0usize
        while i < m {
            t1[i] = th[i] + last * p[i]
            i += 1usize
        }
        let philast = fobj(c, t1[0usize..m])
        if phicur > fobj(c, th) + 0.0001f64 * cur * fg0 || (phicur >= philast && it > 0usize) {
            ret zoom(c, last, cur, th, p, m)
        }
        let fgc = gradls(c, cur, th, p, m)
        if math.abs[f64](fgc) <= -1.0f64 * 0.5f64 * fg0 { ret cur }
        if fgc >= 0.0f64 { ret zoom(c, cur, last, th, p, m) }
        last = cur
        cur = ms.sc_unif(g) * (10.0f64 - cur) + cur
        it += 1usize
    }
    ret 0.001f64
}

// inverse of a general m by m matrix (LU with partial pivoting)
fn inv_lu(a: []const f64, m: usize, out: []f64) -> bool {
    var w: [64]f64 = zero
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            w[i * m + j] = a[i * m + j]
            out[i * m + j] = 0.0f64
            j += 1usize
        }
        out[i * m + i] = 1.0f64
        i += 1usize
    }
    var col = 0usize
    while col < m {
        var piv = col
        var j = col + 1usize
        while j < m {
            if math.abs[f64](w[j * m + col]) > math.abs[f64](w[piv * m + col]) { piv = j }
            j += 1usize
        }
        if w[piv * m + col] == 0.0f64 { ret false }
        if piv != col {
            var k = 0usize
            while k < m {
                let t1 = w[col * m + k]
                w[col * m + k] = w[piv * m + k]
                w[piv * m + k] = t1
                let t2 = out[col * m + k]
                out[col * m + k] = out[piv * m + k]
                out[piv * m + k] = t2
                k += 1usize
            }
        }
        let d = w[col * m + col]
        var k = 0usize
        while k < m {
            w[col * m + k] = w[col * m + k] / d
            out[col * m + k] = out[col * m + k] / d
            k += 1usize
        }
        var r = 0usize
        while r < m {
            if r != col {
                let f = w[r * m + col]
                k = 0usize
                while k < m {
                    w[r * m + k] -= f * w[col * m + k]
                    out[r * m + k] -= f * out[col * m + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    ret true
}

fn mmul(a: []const f64, b: []const f64, m: usize, out: []f64) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var k = 0usize
            while k < m {
                s += a[i * m + k] * b[k * m + j]
                k += 1usize
            }
            out[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// Scythe BFGS(fun, theta, runif, 100, 1e-5): the minimiser lands in th (in place)
fn bfgs(c: *Ctx, g: *ms.Sc, th: []f64, m: usize) -> err {
    var hm: [64]f64 = zero
    var hi: [64]f64 = zero
    hesscdif(c, th, m, hm[0usize..m * m])
    if !inv_lu(hm[0usize..m * m], m, hi[0usize..m * m]) { ret NotConverged }
    var fg: [8]f64 = zero
    var fgn: [8]f64 = zero
    gradfdif(c, th, m, fg[0usize..m])
    var i = 0usize
    while i < m {
        fgn[i] = fg[i]
        i += 1usize
    }
    var count = 0usize
    while true {
        var gg = 0.0f64
        i = 0usize
        while i < m {
            gg += fgn[i] * fgn[i]
            i += 1usize
        }
        if !(gg > 0.00001f64) { break }
        var p: [8]f64 = zero
        i = 0usize
        while i < m {
            var s = 0.0f64
            var j = 0usize
            while j < m {
                s += -1.0f64 * hi[i * m + j] * fg[j]
                j += 1usize
            }
            p[i] = s
            i += 1usize
        }
        let alpha = linesearch2(c, g, th, p[0usize..m], m)
        var tn: [8]f64 = zero
        var sv: [8]f64 = zero
        var y: [8]f64 = zero
        i = 0usize
        while i < m {
            tn[i] = th[i] + alpha * p[i]
            i += 1usize
        }
        gradfdif(c, tn[0usize..m], m, fgn[0usize..m])
        var ys = 0.0f64
        i = 0usize
        while i < m {
            sv[i] = tn[i] - th[i]
            y[i] = fgn[i] - fg[i]
            ys += y[i] * sv[i]
            i += 1usize
        }
        let rho = 1.0f64 / ys
        var l1: [64]f64 = zero
        var l2: [64]f64 = zero
        var t1: [64]f64 = zero
        var t2: [64]f64 = zero
        i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                var id = 0.0f64
                if i == j { id = 1.0f64 }
                l1[i * m + j] = id - (rho * sv[i]) * y[j]
                l2[i * m + j] = id - (rho * y[i]) * sv[j]
                j += 1usize
            }
            i += 1usize
        }
        mmul(l1[0usize..m * m], hi[0usize..m * m], m, t1[0usize..m * m])
        mmul(t1[0usize..m * m], l2[0usize..m * m], m, t2[0usize..m * m])
        i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                hi[i * m + j] = t2[i * m + j] + (rho * sv[i]) * sv[j]
                j += 1usize
            }
            th[i] = tn[i]
            fg[i] = fgn[i]
            i += 1usize
        }
        count += 1usize
        if count > 100usize { ret NotConverged }
    }
    ret ok
}

// Scythe cholesky and invpd with the package's checks compiled out (SCYTHE_DEBUG=0): a matrix that is not positive definite gives NaN or Inf, never an error,
// and the Metropolis step then rejects (u < NaN is false)
fn chol_t(a: []const f64, m: usize, l: []f64) {
    var i = 0usize
    while i < m * m {
        l[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < m {
        i = j
        while i < m {
            var h = a[i * m + j]
            var k = 0usize
            while k < j {
                h -= l[j * m + k] * l[i * m + k]
                k += 1usize
            }
            if i == j {
                l[j * m + j] = math.sqrt[f64](h)
            } else {
                l[i * m + j] = (1.0f64 / l[j * m + j]) * h
            }
            i += 1usize
        }
        j += 1usize
    }
}

fn invpd_t(a: []const f64, m: usize, out: []f64) {
    var l: [64]f64 = zero
    chol_t(a, m, l[0usize..m * m])
    var cidx = 0usize
    while cidx < m {
        var y: [8]f64 = zero
        var x: [8]f64 = zero
        var i = 0usize
        while i < m {
            var b = 0.0f64
            if i == cidx { b = 1.0f64 }
            var s = 0.0f64
            var j = 0usize
            while j < i {
                s += l[i * m + j] * y[j]
                j += 1usize
            }
            y[i] = (b - s) / l[i * m + i]
            i += 1usize
        }
        i = m
        while i > 0usize {
            i -= 1usize
            var s = 0.0f64
            var j = i + 1usize
            while j < m {
                s += l[j * m + i] * x[j]
                j += 1usize
            }
            x[i] = (y[i] - s) / l[i * m + i]
        }
        i = 0usize
        while i < m {
            out[i * m + cidx] = x[i]
            i += 1usize
        }
        cidx += 1usize
    }
}

// log density of N(mu, V) at x as lndmvn_jhp, with the inverse and log determinant of V handed over
fn lndmvn(x: []const f64, mu: []const f64, vinv: []const f64, logdet: f64, m: usize) -> f64 {
    let first = (-1.0f64 * f64(m) / 2.0f64) * math.log[f64](2.0f64 * 3.141592653589793f64) - 0.5f64 * logdet
    var d: [8]f64 = zero
    var i = 0usize
    while i < m {
        d[i] = x[i] - mu[i]
        i += 1usize
    }
    var sec = 0.0f64
    i = 0usize
    while i < m {
        var r = 0.0f64
        var j = 0usize
        while j < m {
            r += vinv[i * m + j] * d[j]
            j += 1usize
        }
        sec += d[i] * r
        i += 1usize
    }
    ret first - 0.5f64 * sec
}

// lnmulttdens with C the transposed Cholesky factor of the proposal precision
fn lnmultt(th: []const f64, mu: []const f64, cm: []const f64, df: f64, m: usize) -> f64 {
    var ss = 0.0f64
    var i = 0usize
    while i < m {
        var z = 0.0f64
        var j = 0usize
        while j < m {
            z += cm[i * m + j] * (th[j] - mu[j])
            j += 1usize
        }
        ss += math.pow[f64](z, 2.0f64)
        i += 1usize
    }
    ret (-1.0f64 * (df + f64(m)) / 2.0f64) * math.log[f64](1.0f64 + (1.0f64 / df) * ss)
}

// y holds 1..ncat, x is n by k row-major, bb0 the k by k prior precision of beta, a0 and aprec the prior mean and precision of alpha (m = ncat - 1), tune the scalar
// tuning, tdf the proposal degrees of freedom. gamma0 (ncat + 1 entries) and beta0 are the start values; out is nstore rows of (beta[k], gamma[2..ncat-1])
// after R's normalisation by gamma[1].
fn oprobit_ac(a: *mem.Arena, g: *ms.Sc, y: []const f64, x: []const f64, n: usize, k: usize, ncat: usize, tune: f64, tdf: f64, a0: []const f64, aprec: []const f64, gamma0: []const f64, beta0: []const f64, b0: []const f64, bb0: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let m = ncat - 1usize
    let nstore = mcmc / thin
    let width = k + ncat - 2usize
    let (xb, e1) = mem.alloc[f64](a, n)
    let (zv, e2) = mem.alloc[f64](a, n)
    let (beta, e3) = mem.alloc[f64](a, k)
    let (bn_var, e4) = mem.alloc[f64](a, k * k)
    let (cc, e5) = mem.alloc[f64](a, k * k)
    let (m1, e6) = mem.alloc[f64](a, k * k)
    let (rhs, e7) = mem.alloc[f64](a, k)
    let (zz, e8) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var gamma: [10]f64 = zero
    var alpha: [8]f64 = zero
    var avar: [64]f64 = zero
    var vinv: [64]f64 = zero
    var ld = 0.0f64
    var ld2 = 0.0f64
    if ms.inv_pd(a, aprec, m, avar[0usize..m * m], &ld) != ok { ret ms.NotPd }
    if ms.inv_pd(a, avar[0usize..m * m], m, vinv[0usize..m * m], &ld2) != ok { ret ms.NotPd }
    var s = 0usize
    while s <= ncat {
        gamma[s] = gamma0[s]
        s += 1usize
    }
    // R's C++ starts the search from gamma2alpha(gamma + 1)
    alpha[0usize] = math.log[f64](gamma[1usize] + 1.0f64)
    var j = 1usize
    while j < m {
        alpha[j] = math.log[f64]((gamma[j + 1usize] + 1.0f64) - (gamma[j] + 1.0f64))
        j += 1usize
    }
    j = 0usize
    while j < k {
        beta[j] = beta0[j]
        j += 1usize
    }
    var i = 0usize
    while i < k {
        j = 0usize
        while j < k {
            var sm = 0.0f64
            var t = 0usize
            while t < n {
                sm += x[t * k + i] * x[t * k + j]
                t += 1usize
            }
            m1[i * k + j] = bb0[i * k + j] + sm
            j += 1usize
        }
        i += 1usize
    }
    if ms.inv_pd(a, m1, k, bn_var, &ld) != ok { ret ms.NotPd }
    if !ms.chol(bn_var, k, cc) { ret ms.NotPd }
    var cx: Ctx = zero
    cx.y = y
    cx.xb = xb
    cx.n = n
    cx.ncat = ncat
    cx.h = math.sqrt[f64](math.sqrt[f64](epsilon()))
    var count = 0usize
    var iter = 0usize
    while iter < burnin + mcmc {
        let start = mem.mark(a)
        var t = 0usize
        while t < n {
            var e = 0.0f64
            i = 0usize
            while i < k {
                e += x[t * k + i] * beta[i]
                i += 1usize
            }
            xb[t] = e
            t += 1usize
        }
        var ah: [8]f64 = zero
        var hm: [64]f64 = zero
        var av: [64]f64 = zero
        var pv: [64]f64 = zero
        var pp: [64]f64 = zero
        var lp: [64]f64 = zero
        var lc: [64]f64 = zero
        var cm: [64]f64 = zero
        var zn: [8]f64 = zero
        var can: [8]f64 = zero
        i = 0usize
        while i < m {
            ah[i] = alpha[i]
            i += 1usize
        }
        if bfgs(&cx, g, ah[0usize..m], m) != ok { ret NotConverged }
        hesscdif(&cx, ah[0usize..m], m, hm[0usize..m * m])
        invpd_t(hm[0usize..m * m], m, av[0usize..m * m])
        i = 0usize
        while i < m {
            j = 0usize
            while j < m {
                pv[i * m + j] = (tune * av[i * m + j]) * tune
                j += 1usize
            }
            i += 1usize
        }
        invpd_t(pv[0usize..m * m], m, pp[0usize..m * m])
        chol_t(pp[0usize..m * m], m, lp[0usize..m * m])
        i = 0usize
        while i < m {
            j = 0usize
            while j < m {
                cm[i * m + j] = lp[j * m + i]
                j += 1usize
            }
            i += 1usize
        }
        chol_t(pv[0usize..m * m], m, lc[0usize..m * m])
        i = 0usize
        while i < m {
            zn[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        let chi = ms.sc_rgamma(g, tdf / 2.0f64, 0.5f64)
        i = 0usize
        while i < m {
            var sm = 0.0f64
            j = 0usize
            while j <= i {
                sm += lc[i * m + j] * zn[j]
                j += 1usize
            }
            can[i] = ah[i] + (0.0f64 + sm) / math.sqrt[f64](chi / tdf)
            i += 1usize
        }
        let lpc = loglike(&cx, can[0usize..m]) + lndmvn(can[0usize..m], a0, vinv[0usize..m * m], ld2, m)
        let ljc = lnmultt(can[0usize..m], ah[0usize..m], cm[0usize..m * m], tdf, m)
        let lpu = loglike(&cx, alpha[0usize..m]) + lndmvn(alpha[0usize..m], a0, vinv[0usize..m * m], ld2, m)
        let lju = lnmultt(alpha[0usize..m], ah[0usize..m], cm[0usize..m * m], tdf, m)
        let ratio = math.exp[f64](lpc - ljc - lpu + lju)
        if ms.sc_unif(g) < ratio {
            i = 0usize
            while i < m {
                alpha[i] = can[i]
                i += 1usize
            }
            gamma[0usize] = -300.0f64
            gamma[m + 1usize] = 300.0f64
            j = 1usize
            while j < m + 1usize {
                var sm = 0.0f64
                i = 0usize
                while i < j {
                    sm += math.exp[f64](alpha[i])
                    i += 1usize
                }
                gamma[j] = sm
                j += 1usize
            }
        }
        // latent data and beta
        t = 0usize
        while t < n {
            var e = 0.0f64
            i = 0usize
            while i < k {
                e += x[t * k + i] * beta[i]
                i += 1usize
            }
            xb[t] = e
            let yi = usize(y[t])
            zv[t] = mo.rtnorm_combo(g, e, 1.0f64, gamma[yi - 1usize], gamma[yi])
            t += 1usize
        }
        i = 0usize
        while i < k {
            var sm = 0.0f64
            j = 0usize
            while j < k {
                sm += bb0[i * k + j] * b0[j]
                j += 1usize
            }
            t = 0usize
            while t < n {
                sm += x[t * k + i] * zv[t]
                t += 1usize
            }
            rhs[i] = sm
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sm = 0.0f64
            j = 0usize
            while j < k {
                sm += bn_var[i * k + j] * rhs[j]
                j += 1usize
            }
            m1[i] = sm
            zz[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sm = m1[i]
            j = 0usize
            while j <= i {
                sm += cc[i * k + j] * zz[j]
                j += 1usize
            }
            beta[i] = sm
            i += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            out[count * width] = beta[0usize] - gamma[1usize]
            j = 1usize
            while j < k {
                out[count * width + j] = beta[j]
                j += 1usize
            }
            j = 2usize
            while j < ncat {
                out[count * width + k + j - 2usize] = gamma[j] - gamma[1usize]
                j += 1usize
            }
            count += 1usize
        }
        mem.reset(a, start)
        iter += 1usize
    }
    ret ok
}
