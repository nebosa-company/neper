// R ks Hpi and Hscv (pre = "sphere") and Hpi.diag and Hscv.diag (pre = "scale") in d dimensions (2 to 4, unbinned, deriv.order 0) with the "dscalar" pilot: the scalar pilot g from
// gdscalar (the normal-scale functionals psins by Isserlis moments, nu by Kan's recursion, the d^4 fourth-order kernel functional estimates for G = g^2 I),
// then optim BFGS (numerical gradient) on the plug-in AMISE over vech of the square root of H (full) or over the diagonal.
//
// Not here: the samse and amse pilots above two dimensions, binned = TRUE above 1000 observations, deriv.order above 0, nstage other than 1 and 2.

use e.algo.stat.ks1d as k1
use e.algo.stat.kslscv as ls
use e.algo.stat.kslocal as kl
use e.algo.stat.ksnd as nd
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm as nm
use e.math
use e.mem

error Failed

// the sum over the pairings of idx[0..m] of the products of c: E[prod omega_idx] for omega ~ N(0, C^-1 ... c = covariance) by Isserlis
fn pairings(idx: []usize, m: usize, c: []const f64, d: usize) -> f64 {
    if m == 0usize { ret 1.0f64 }
    var s = 0.0f64
    var k = 1usize
    while k < m {
        var rest: [8]usize = zero
        var at = 0usize
        var q = 1usize
        while q < m {
            if q != k {
                rest[at] = idx[q]
                at += 1usize
            }
            q += 1usize
        }
        s += c[idx[0usize] * d + idx[k]] * pairings(rest[0usize..8usize], m - 2usize, c, d)
        k += 1usize
    }
    ret s
}

// psins for the index tuple idx (length m): the m-th partial derivative of the N(0, 2 S) density at zero, with c = (2 S)^-1 and k0 its constant
fn psins_at(idx: []usize, m: usize, c: []const f64, d: usize, k0: f64) -> f64 {
    var sign = 1.0f64
    if (m / 2usize) % 2usize == 1usize { sign = 0.0f64 - 1.0f64 }
    ret sign * k0 * pairings(idx, m, c, d)
}

// nu(r, A) of Kan (2008): factorial(r) 2^r times the r-th term of the recursion in the power traces of A
fn nu_r(r: usize, a: []const f64, d: usize) -> f64 {
    var vals: [4]f64 = zero
    var vecs: [16]f64 = zero
    nd.jacobi(a, d, vals[0usize..4usize], vecs[0usize..16usize])
    var tr: [8]f64 = zero
    var p = 1usize
    while p <= r {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += math.pow[f64](vals[j], f64(p))
            j += 1usize
        }
        tr[p - 1usize] = s
        p += 1usize
    }
    var nv: [8]f64 = zero
    nv[0usize] = 1.0f64
    p = 1usize
    while p <= r {
        var s = 0.0f64
        var q = 1usize
        while q <= p {
            s += tr[q - 1usize] * nv[p - q]
            q += 1usize
        }
        nv[p] = s / f64(2usize * p)
        p += 1usize
    }
    var fac = 1.0f64
    p = 2usize
    while p <= r {
        fac = fac * f64(p)
        p += 1usize
    }
    ret fac * math.pow[f64](2.0f64, f64(r)) * nv[r]
}

fn odd_factorial(m: usize) -> f64 {
    var r = 1.0f64
    var k = m - 1usize
    while k >= 1usize {
        r = r * f64(k)
        if k < 2usize { ret r }
        k -= 2usize
    }
    ret r
}

// B3 of gdscalar: |sum over b of (sum over i of psins(e_i + e_i + b))^2| with b over the d^bl tuples of length bl = m - 2
fn b3_of(s: []const f64, d: usize, m: usize) -> f64 {
    var s2: [16]f64 = zero
    var q = 0usize
    while q < d * d {
        s2[q] = 2.0f64 * s[q]
        q += 1usize
    }
    var inv: [16]f64 = zero
    let det = nd.inv_det(s2[0usize..16usize], d, inv[0usize..16usize])
    let k0 = nd.norm_const(det, d)
    let bl = m - 2usize
    let nb = nd.pow_usize(d, bl)
    var tot = 0.0f64
    var b = 0usize
    while b < nb {
        var idx: [8]usize = zero
        var r = b
        var t = 0usize
        while t < bl {
            idx[2usize + t] = r % d
            r = r / d
            t += 1usize
        }
        var inner = 0.0f64
        var i = 0usize
        while i < d {
            idx[0usize] = i
            idx[1usize] = i
            inner += psins_at(idx[0usize..8usize], m, inv[0usize..16usize], d, k0)
            i += 1usize
        }
        tot += inner * inner
        b += 1usize
    }
    ret math.abs[f64](tot)
}

// gdscalar(x, r = 0, nstage) for the pre-transformed data xs (n by d): g2r4, the pilot for the fourth-order functionals
fn gdscalar(a: *mem.Arena, xs: []const f64, n: usize, d: usize, nstage: usize, scv: bool) -> f64 {
    var s: [16]f64 = zero
    nd.cov_nd(xs, n, d, s[0usize..16usize])
    var sinv: [16]f64 = zero
    let dets = nd.inv_det(s[0usize..16usize], d, sinv[0usize..16usize])
    let pi = 3.141592653589793f64
    let df = f64(d)
    let twopi_d = math.pow[f64](2.0f64 * pi, 0.0f64 - df)
    var b1 = 0.0f64
    var b2 = 0.0f64
    var b3 = 0.0f64
    var g = 0.0f64
    if nstage == 1usize {
        var pr = 1.0f64
        var k = 0usize
        while k <= 2usize {
            pr = pr * (df + 2.0f64 * f64(k))
            k += 1usize
        }
        b1 = 2.0f64 * twopi_d * odd_factorial(4usize) * pr
        b2 = 0.0f64 - (df + 2.0f64) * math.pow[f64](2.0f64, 0.0f64 - df / 2.0f64) * twopi_d / math.sqrt[f64](dets) * odd_factorial(4usize) * nu_r(2usize, sinv[0usize..16usize], d)
        b3 = b3_of(s[0usize..16usize], d, 6usize)
        if scv {
            let fp = math.pow[f64](4.0f64 * pi, 0.0f64 - df)
            b1 = 0.125f64 * fp * odd_factorial(6usize) * pr
            b2 = 0.0f64 - (df + 2.0f64) * 0.0625f64 * fp / math.sqrt[f64](dets) * odd_factorial(4usize) * nu_r(2usize, sinv[0usize..16usize], d)
            b3 = 4.0f64 * b3
        }
        g = math.pow[f64](2.0f64 * b1 / (0.0f64 - b2 + math.sqrt[f64](b2 * b2 + 4.0f64 * b1 * b3)), 1.0f64 / (df + 8.0f64)) * math.pow[f64](f64(n), 0.0f64 - 1.0f64 / (df + 8.0f64))
        ret g
    }
    var pr = 1.0f64
    var k = 0usize
    while k <= 3usize {
        pr = pr * (df + 2.0f64 * f64(k))
        k += 1usize
    }
    b1 = 2.0f64 * twopi_d * odd_factorial(6usize) * pr
    b2 = 0.0f64 - (df + 4.0f64) * math.pow[f64](2.0f64, 0.0f64 - df / 2.0f64 + 2.0f64) * twopi_d / math.sqrt[f64](dets) * odd_factorial(6usize) * nu_r(4usize, sinv[0usize..16usize], d)
    b3 = b3_of(s[0usize..16usize], d, 8usize)
    var cf1 = 1.0f64
    var cf2 = 1.0f64
    var cf3 = 1.0f64
    if scv {
        let fp = math.pow[f64](4.0f64 * pi, 0.0f64 - df)
        b1 = 0.03125f64 * fp * odd_factorial(6usize) * pr
        b2 = 0.0f64 - (df + 4.0f64) * 0.015625f64 * fp / math.sqrt[f64](dets) * odd_factorial(6usize) * nu_r(4usize, sinv[0usize..16usize], d)
        b3 = 4.0f64 * b3
        cf1 = math.pow[f64](2.0f64, 0.0f64 - df)
        cf2 = math.pow[f64](2.0f64, 0.0f64 - df / 2.0f64 + 1.0f64)
        cf3 = 4.0f64
    }
    let g6 = math.pow[f64](2.0f64 * b1 / (0.0f64 - b2 + math.sqrt[f64](b2 * b2 + 4.0f64 * b1 * b3)), 1.0f64 / (df + 8.0f64)) * math.pow[f64](f64(n), 0.0f64 - 1.0f64 / (df + 8.0f64))
    // eta2r6 = Qr(x, deriv.order = 6, Sigma = g6^2 I, inc = 1): the mean over all pairs of the cubed Laplacian of the N(0, g6^2 I) density
    var eta = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var dv: [16]f64 = zero
            var c = 0usize
            while c < d {
                let z = xs[i * d + c] - xs[j * d + c]
                dv[c * 4usize] = k1.dnorm_deriv(z, g6, 0usize)
                dv[c * 4usize + 1usize] = k1.dnorm_deriv(z, g6, 2usize)
                dv[c * 4usize + 2usize] = k1.dnorm_deriv(z, g6, 4usize)
                dv[c * 4usize + 3usize] = k1.dnorm_deriv(z, g6, 6usize)
                c += 1usize
            }
            var t = 0usize
            while t < nd.pow_usize(d, 3usize) {
                var r = t
                var ord: [4]usize = zero
                var u = 0usize
                while u < 3usize {
                    ord[r % d] += 1usize
                    r = r / d
                    u += 1usize
                }
                var pv = 1.0f64
                c = 0usize
                while c < d {
                    pv = pv * dv[c * 4usize + ord[c]]
                    c += 1usize
                }
                eta += pv
                t += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    eta = eta / (f64(n) * f64(n))
    let l0 = math.pow[f64](2.0f64 * pi, 0.0f64 - df / 2.0f64)
    var ident: [16]f64 = zero
    var q = 0usize
    while q < d {
        ident[q * d + q] = 1.0f64
        q += 1usize
    }
    let a1 = cf1 * (2.0f64 * df + 8.0f64) * l0 * l0 * odd_factorial(4usize) * nu_r(2usize, ident[0usize..16usize], d)
    let a2 = cf2 * (df + 2.0f64) * l0 * odd_factorial(4usize) * eta
    let a3 = cf3 * eta * eta
    ret math.pow[f64](2.0f64 * a1 / ((0.0f64 - a2 + math.sqrt[f64](a2 * a2 + 4.0f64 * a1 * a3)) * f64(n)), 1.0f64 / (df + 6.0f64))
}

// the fourth-order kernel functional estimates for G = g^2 I as a table over count vectors: tab[sum_j count_j 5^j]
fn psi4_table(xs: []const f64, n: usize, d: usize, g: f64, tab: []f64) {
    var code = 0usize
    while code < nd.pow_usize(5usize, d) {
        var r = code
        var cnt: [4]usize = zero
        var tot = 0usize
        var j = 0usize
        while j < d {
            cnt[j] = r % 5usize
            tot += cnt[j]
            r = r / 5usize
            j += 1usize
        }
        tab[code] = 0.0f64
        if tot == 4usize {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                var k = 0usize
                while k < n {
                    var pv = 1.0f64
                    j = 0usize
                    while j < d {
                        pv = pv * k1.dnorm_deriv(xs[i * d + j] - xs[k * d + j], g, cnt[j])
                        j += 1usize
                    }
                    s += pv
                    k += 1usize
                }
                i += 1usize
            }
            tab[code] = s / (f64(n) * f64(n))
        }
        code += 1usize
    }
}

type PiCtx = struct { n: usize, d: usize, diag: bool, tab: []const f64 }

fn pi_obj(c: *PiCtx, v: []const f64) -> f64 {
    let d = c.d
    var h: [16]f64 = zero
    ls.make_h(v, d, c.diag, h[0usize..16usize])
    var inv: [16]f64 = zero
    let det = nd.inv_det(h[0usize..16usize], d, inv[0usize..16usize])
    let ivar = 1.0f64 / (math.sqrt[f64](det) * f64(c.n)) * math.pow[f64](2.0f64, 0.0f64 - f64(d)) * math.pow[f64](3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64)
    var pw: [4]usize = zero
    var p = 1usize
    var j = 0usize
    while j < d {
        pw[j] = p
        p = p * 5usize
        j += 1usize
    }
    var q = 0.0f64
    var i1 = 0usize
    while i1 < d {
        var i2 = 0usize
        while i2 < d {
            var i3 = 0usize
            while i3 < d {
                var i4 = 0usize
                while i4 < d {
                    q += c.tab[pw[i1] + pw[i2] + pw[i3] + pw[i4]] * h[i1 * d + i2] * h[i3 * d + i4]
                    i4 += 1usize
                }
                i3 += 1usize
            }
            i2 += 1usize
        }
        i1 += 1usize
    }
    ret ivar + 0.25f64 * q
}

fn pi_grad(c: *PiCtx, v: []const f64, g: []f64) {
    var np = c.d * (c.d + 1usize) / 2usize
    if c.diag { np = c.d }
    var w: [10]f64 = zero
    var j = 0usize
    while j < np {
        var k = 0usize
        while k < np {
            w[k] = v[k]
            k += 1usize
        }
        w[j] = v[j] + 0.001f64
        let v1 = pi_obj(c, w[0usize..np])
        w[j] = v[j] - 0.001f64
        let v2 = pi_obj(c, w[0usize..np])
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// the pre-transformed data xs = x S^(-1/2) (sphere) or x diag(sd)^-1 (scale) and S12 (the square root or diag(sd)) that maps H back
fn pre_transform(a: *mem.Arena, x: []const f64, n: usize, d: usize, diag: bool, xs: []f64, s12: []f64) {
    var s: [16]f64 = zero
    nd.cov_nd(x, n, d, s[0usize..16usize])
    var si12: [16]f64 = zero
    if diag {
        var j = 0usize
        while j < d {
            s12[j * d + j] = math.sqrt[f64](s[j * d + j])
            si12[j * d + j] = 1.0f64 / s12[j * d + j]
            j += 1usize
        }
    } else {
        var sinv: [16]f64 = zero
        let _dd = nd.inv_det(s[0usize..16usize], d, sinv[0usize..16usize])
        kl.sqrtm(s[0usize..16usize], d, s12)
        kl.sqrtm(sinv[0usize..16usize], d, si12[0usize..16usize])
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            var t = 0.0f64
            var k = 0usize
            while k < d {
                t += x[i * d + k] * si12[k * d + j]
                k += 1usize
            }
            xs[i * d + j] = t
            j += 1usize
        }
        i += 1usize
    }
}

// the optimiser start: vech (or the diagonal) of the square root of Hns(xs); returns the number of parameters
fn start_par(xs: []const f64, n: usize, d: usize, diag: bool, par: []f64) -> usize {
    var hn: [16]f64 = zero
    nd.hns(xs, n, d, 0usize, hn[0usize..16usize])
    var hs: [16]f64 = zero
    kl.sqrtm(hn[0usize..16usize], d, hs[0usize..16usize])
    var np = 0usize
    if diag {
        np = d
        var j = 0usize
        while j < d {
            par[j] = hs[j * d + j]
            j += 1usize
        }
    } else {
        var c = 0usize
        while c < d {
            var r = c
            while r < d {
                par[np] = hs[r * d + c]
                np += 1usize
                r += 1usize
            }
            c += 1usize
        }
    }
    ret np
}

// H = S12 H* S12 from the optimiser result
fn back_transform(s12: []const f64, par: []const f64, d: usize, diag: bool, h: []f64) {
    var hh: [16]f64 = zero
    ls.make_h(par, d, diag, hh[0usize..16usize])
    var t1: [16]f64 = zero
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            var t = 0.0f64
            var k = 0usize
            while k < d {
                t += s12[i * d + k] * hh[k * d + j]
                k += 1usize
            }
            t1[i * d + j] = t
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            var t = 0.0f64
            var k = 0usize
            while k < d {
                t += t1[i * d + k] * s12[k * d + j]
                k += 1usize
            }
            h[i * d + j] = t
            j += 1usize
        }
        i += 1usize
    }
}

// Hpi(x, nstage, pilot = "dscalar", binned = FALSE) (diag false, pre = "sphere") and Hpi.diag(x, nstage, pilot = "dscalar") (diag true, pre = "scale")
fn hpi(a: *mem.Arena, x: []const f64, n: usize, d: usize, nstage: usize, diag: bool, h: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret e1 }
    var s12: [16]f64 = zero
    pre_transform(a, x, n, d, diag, xs, s12[0usize..16usize])
    let g = gdscalar(a, xs, n, d, nstage, false)
    let (tab, e2) = mem.alloc[f64](a, nd.pow_usize(5usize, d))
    if e2 != ok { ret e2 }
    psi4_table(xs, n, d, g, tab)
    var par: [10]f64 = zero
    let np = start_par(xs, n, d, diag, par[0usize..10usize])
    var ctx = PiCtx{ n: n, d: d, diag: diag, tab: tab }
    let fmin = bf.vmmin[PiCtx](a, &ctx, pi_obj, pi_grad, par[0usize..np], 1.4901161193847656e-08f64, 100usize)
    if fmin != fmin { ret Failed }
    back_transform(s12[0usize..16usize], par[0usize..np], d, diag, h)
    ret ok
}

// (1 / n^2) times the sum over all pairs of the N(0, sigma) density at x_i - x_j
fn q_all(a: *mem.Arena, x: []const f64, n: usize, d: usize, sigma: []const f64) -> f64 {
    var inv: [16]f64 = zero
    let det = nd.inv_det(sigma, d, inv[0usize..16usize])
    // Qr.cumulant at r = 0: M = a_i + a_j - 2 x_i G^-1 x_j' with a = rowSums((x G^-1) * x), as the expansion is written in ks
    let (xg, e1) = mem.alloc[f64](a, n * d)
    let (av, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var k = 0usize
        var sa = 0.0f64
        while k < d {
            var t = 0.0f64
            var l = 0usize
            while l < d {
                t += x[i * d + l] * inv[l * d + k]
                l += 1usize
            }
            xg[i * d + k] = t
            sa += t * x[i * d + k]
            k += 1usize
        }
        av[i] = sa
        i += 1usize
    }
    var s = 0.0f64
    var j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            var dot = 0.0f64
            var k = 0usize
            while k < d {
                dot += xg[i * d + k] * x[j * d + k]
                k += 1usize
            }
            let m = (av[i] + av[j]) - 2.0f64 * dot
            s += math.exp[f64](0.0f64 - m / 2.0f64)
            i += 1usize
        }
        j += 1usize
    }
    ret nd.norm_const(det, d) * s / (f64(n) * f64(n))
}

type ScvCtx = struct { arena: *mem.Arena, x: []const f64, n: usize, d: usize, diag: bool, g2: f64, scv3: f64 }

// scv.mat at r = 0: the integrated variance plus the non-negative bias term from the three Gaussian sums with pilot G = g^2 I
fn scv_obj(c: *ScvCtx, v: []const f64) -> f64 {
    let d = c.d
    var h: [16]f64 = zero
    ls.make_h(v, d, c.diag, h[0usize..16usize])
    var inv: [16]f64 = zero
    let det = nd.inv_det(h[0usize..16usize], d, inv[0usize..16usize])
    var s1: [16]f64 = zero
    var s2: [16]f64 = zero
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            s1[i * d + j] = 2.0f64 * h[i * d + j]
            s2[i * d + j] = h[i * d + j]
            if i == j {
                s1[i * d + j] = s1[i * d + j] + 2.0f64 * c.g2
                s2[i * d + j] = s2[i * d + j] + 2.0f64 * c.g2
            }
            j += 1usize
        }
        i += 1usize
    }
    let mk = mem.mark(c.arena)
    var bias2 = q_all(c.arena, c.x, c.n, d, s1[0usize..16usize]) - 2.0f64 * q_all(c.arena, c.x, c.n, d, s2[0usize..16usize]) + c.scv3
    mem.reset(c.arena, mk)
    if bias2 < 0.0f64 { bias2 = 0.0f64 }
    ret 1.0f64 / (math.sqrt[f64](det) * f64(c.n)) * math.pow[f64](2.0f64, 0.0f64 - f64(d)) * math.pow[f64](3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64) + bias2
}

fn scv_grad(c: *ScvCtx, v: []const f64, g: []f64) {
    var np = c.d * (c.d + 1usize) / 2usize
    if c.diag { np = c.d }
    var w: [10]f64 = zero
    var j = 0usize
    while j < np {
        var k = 0usize
        while k < np {
            w[k] = v[k]
            k += 1usize
        }
        w[j] = v[j] + 0.001f64
        let v1 = scv_obj(c, w[0usize..np])
        w[j] = v[j] - 0.001f64
        let v2 = scv_obj(c, w[0usize..np])
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// Hscv(x, nstage, pilot = "dscalar", binned = FALSE) (diag false, pre = "sphere", optim BFGS) and Hscv.diag (diag true, pre = "scale", Nelder-Mead)
fn hscv(a: *mem.Arena, x: []const f64, n: usize, d: usize, nstage: usize, diag: bool, h: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret e1 }
    var s12: [16]f64 = zero
    pre_transform(a, x, n, d, diag, xs, s12[0usize..16usize])
    let g = gdscalar(a, xs, n, d, nstage, true)
    var par: [10]f64 = zero
    let np = start_par(xs, n, d, diag, par[0usize..10usize])
    var s3: [16]f64 = zero
    var i = 0usize
    while i < d {
        s3[i * d + i] = 2.0f64 * g * g
        i += 1usize
    }
    var ctx = ScvCtx{ arena: a, x: xs, n: n, d: d, diag: diag, g2: g * g, scv3: q_all(a, xs, n, d, s3[0usize..16usize]) }
    if diag {
        var out: [10]f64 = zero
        let (fv, cnt, fail) = nm.nmmin[ScvCtx](a, &ctx, scv_obj, par[0usize..np], 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out[0usize..np])
        if fv != fv { ret Failed }
        back_transform(s12[0usize..16usize], out[0usize..np], d, diag, h)
    } else {
        let fmin = bf.vmmin[ScvCtx](a, &ctx, scv_obj, scv_grad, par[0usize..np], 1.4901161193847656e-08f64, 100usize)
        if fmin != fmin { ret Failed }
        back_transform(s12[0usize..16usize], par[0usize..np], d, diag, h)
    }
    ret ok
}

type KfeCtx = struct { n: usize, d: usize, psi: []const f64 }

// the squared stage-two AMSE of Hpi.kfe: (K0 / (sqrt(det H) n) + vec(H)' psi2 / 2)^2
fn kfe_obj(c: *KfeCtx, v: []const f64) -> f64 {
    let d = c.d
    var h: [16]f64 = zero
    ls.make_h(v, d, false, h[0usize..16usize])
    var inv: [16]f64 = zero
    let det = nd.inv_det(h[0usize..16usize], d, inv[0usize..16usize])
    var q = 0.0f64
    var i = 0usize
    while i < d * d {
        q += h[i] * c.psi[i]
        i += 1usize
    }
    let k0 = math.pow[f64](2.0f64 * 3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64)
    let val = 1.0f64 / (math.sqrt[f64](det) * f64(c.n)) * k0 + 0.5f64 * q
    ret val * val
}

fn kfe_grad(c: *KfeCtx, v: []const f64, g: []f64) {
    let np = c.d * (c.d + 1usize) / 2usize
    var w: [10]f64 = zero
    var j = 0usize
    while j < np {
        var k = 0usize
        while k < np {
            w[k] = v[k]
            k += 1usize
        }
        w[j] = v[j] + 0.001f64
        let v1 = kfe_obj(c, w[0usize..np])
        w[j] = v[j] - 0.001f64
        let v2 = kfe_obj(c, w[0usize..np])
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// Hpi.kfe(x, nstage, pilot = "dscalar", pre = "sphere", binned = FALSE) in d dimensions
fn hpi_kfe(a: *mem.Arena, x: []const f64, n: usize, d: usize, nstage: usize, h: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret e1 }
    var s12: [16]f64 = zero
    pre_transform(a, x, n, d, false, xs, s12[0usize..16usize])
    var s: [16]f64 = zero
    nd.cov_nd(xs, n, d, s[0usize..16usize])
    var s2: [16]f64 = zero
    var q = 0usize
    while q < d * d {
        s2[q] = 2.0f64 * s[q]
        q += 1usize
    }
    var c: [16]f64 = zero
    let det2 = nd.inv_det(s2[0usize..16usize], d, c[0usize..16usize])
    let k0 = nd.norm_const(det2, d)
    var psi2: [16]f64 = zero
    if nstage == 2usize {
        // stage one: h2 from the normal-scale fourth-order functionals, then psi2 from the kernel functional estimate with G = h2^2 I
        let kk = math.pow[f64](2.0f64 * 3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64)
        let a1 = f64(d) * kk * kk
        var a2 = 0.0f64
        var a3 = 0.0f64
        var ce = 0usize
        while ce < d * d {
            var inner = 0.0f64
            var i = 0usize
            while i < d {
                var idx: [8]usize = zero
                idx[0usize] = i
                idx[1usize] = i
                idx[2usize] = ce / d
                idx[3usize] = ce % d
                inner += psins_at(idx[0usize..8usize], 4usize, c[0usize..16usize], d, k0)
                i += 1usize
            }
            if ce / d == ce % d { a2 += (0.0f64 - kk) * inner }
            a3 += inner * inner
            ce += 1usize
        }
        let h2 = math.pow[f64](0.0f64 - a1 / (2.0f64 * a2 * f64(n)), 1.0f64 / (f64(d) + 4.0f64))
        ce = 0usize
        while ce < d * d {
            let ci = ce / d
            let cj = ce % d
            var sum = 0.0f64
            var i = 0usize
            while i < n {
                var k = 0usize
                while k < n {
                    var pv = 1.0f64
                    var j = 0usize
                    while j < d {
                        var ord = 0usize
                        if j == ci { ord += 1usize }
                        if j == cj { ord += 1usize }
                        pv = pv * k1.dnorm_deriv(xs[i * d + j] - xs[k * d + j], h2, ord)
                        j += 1usize
                    }
                    sum += pv
                    k += 1usize
                }
                i += 1usize
            }
            psi2[ce] = sum / (f64(n) * f64(n))
            ce += 1usize
        }
    } else {
        var ce = 0usize
        while ce < d * d {
            var idx: [8]usize = zero
            idx[0usize] = ce / d
            idx[1usize] = ce % d
            psi2[ce] = psins_at(idx[0usize..8usize], 2usize, c[0usize..16usize], d, k0)
            ce += 1usize
        }
    }
    // the start: sqrt of Gns(r = 0, n, var(x.star)) = (2 / (n d))^(2 / (d + 2)) 2 S
    let gc = math.pow[f64](2.0f64 / (f64(n) * f64(d)), 2.0f64 / (f64(d) + 2.0f64)) * 2.0f64
    var gs: [16]f64 = zero
    q = 0usize
    while q < d * d {
        gs[q] = gc * s[q]
        q += 1usize
    }
    var gr: [16]f64 = zero
    kl.sqrtm(gs[0usize..16usize], d, gr[0usize..16usize])
    var par: [10]f64 = zero
    var np = 0usize
    var cc = 0usize
    while cc < d {
        var r = cc
        while r < d {
            par[np] = gr[r * d + cc]
            np += 1usize
            r += 1usize
        }
        cc += 1usize
    }
    var ctx = KfeCtx{ n: n, d: d, psi: psi2[0usize..16usize] }
    let fmin = bf.vmmin[KfeCtx](a, &ctx, kfe_obj, kfe_grad, par[0usize..np], 1.4901161193847656e-08f64, 100usize)
    if fmin != fmin { ret Failed }
    back_transform(s12[0usize..16usize], par[0usize..np], d, false, h)
    ret ok
}
