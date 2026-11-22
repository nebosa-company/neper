// R ks, two dimensions: the bandwidth matrices Hpi (two-stage and one-stage plug-in with the sphering pre-transformation and the SAMSE pilot,
// optim BFGS on the plug-in AMISE), Hlscv and Hlscv.diag (optim Nelder-Mead on the unbinned LSCV), with Hns and the exact covariance as R sums it.
//
// Not here: the binned estimates used by ks above 500 observations, the scaling pre-transformation, the AMSE and unconstrained pilots, Hscv and
// the diagonal plug-in.

use e.algo.stat.ks1d as k1
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm as nm
use e.math
use e.mem

error Failed

// var / cov of two columns as R's cov.c: the refined mean rounded to double, products in double, the sum and the division in extended precision
fn cov_cols(x: []const f64, n: usize, ja: usize, jb: usize) -> f64 {
    var ma = 0.0f64
    var mb = 0.0f64
    var s = 0usize
    while s < 2usize {
        var j = ja
        if s == 1usize { j = jb }
        var sh = 0.0f64
        var sl = 0.0f64
        var i = 0usize
        while i < n {
            let (t, e) = k1.two_sum(sh, x[i * 2usize + j])
            sh = t
            sl += e
            i += 1usize
        }
        let nf = f64(n)
        let mh = sh / nf
        let (ph, pl) = k1.two_prod(mh, nf)
        let m = mh + ((sh - ph) - pl + sl) / nf
        if s == 0usize { ma = m } else { mb = m }
        s += 1usize
    }
    var qh = 0.0f64
    var ql = 0.0f64
    var i = 0usize
    while i < n {
        let (t, e) = k1.two_sum(qh, (x[i * 2usize + ja] - ma) * (x[i * 2usize + jb] - mb))
        qh = t
        ql += e
        i += 1usize
    }
    let n1 = f64(n) - 1.0f64
    let q1 = qh / n1
    let (ph, pl) = k1.two_prod(q1, n1)
    ret q1 + ((qh - ph) - pl + ql) / n1
}

// var(x) for the n by 2 row-major x into s (2 by 2)
fn cov2(x: []const f64, n: usize, s: []f64) {
    s[0usize] = cov_cols(x, n, 0usize, 0usize)
    s[1usize] = cov_cols(x, n, 0usize, 1usize)
    s[2usize] = s[1usize]
    s[3usize] = cov_cols(x, n, 1usize, 1usize)
}

// the symmetric positive definite square root of a 2 by 2
fn sqrt2(m: []const f64, o: []f64) {
    let det = m[0usize] * m[3usize] - m[1usize] * m[2usize]
    let sd = math.sqrt[f64](det)
    let t = math.sqrt[f64](m[0usize] + m[3usize] + 2.0f64 * sd)
    o[0usize] = (m[0usize] + sd) / t
    o[1usize] = m[1usize] / t
    o[2usize] = m[2usize] / t
    o[3usize] = (m[3usize] + sd) / t
}

fn inv2(m: []const f64, o: []f64) {
    let det = m[0usize] * m[3usize] - m[1usize] * m[2usize]
    o[0usize] = m[3usize] / det
    o[1usize] = 0.0f64 - m[1usize] / det
    o[2usize] = 0.0f64 - m[2usize] / det
    o[3usize] = m[0usize] / det
}

fn mul2(a: []const f64, b: []const f64, o: []f64) {
    o[0usize] = a[0usize] * b[0usize] + a[1usize] * b[2usize]
    o[1usize] = a[0usize] * b[1usize] + a[1usize] * b[3usize]
    o[2usize] = a[2usize] * b[0usize] + a[3usize] * b[2usize]
    o[3usize] = a[2usize] * b[1usize] + a[3usize] * b[3usize]
}

// Hns(x, deriv.order = 0) for 2 dimensions into o
fn hns2(x: []const f64, n: usize, o: []f64) {
    cov2(x, n, o)
    let c = math.pow[f64](4.0f64 / (f64(n) * 4.0f64), 2.0f64 / 6.0f64)
    var i = 0usize
    while i < 4usize {
        o[i] = o[i] * c
        i += 1usize
    }
}

// the unique derivative counts of the 16 entries of the fourth-order derivative vector, and of the first seven of the sixth-order one (the way ks indexes them)
fn d4count(p: usize) -> usize {
    // the number of derivatives in the first variable, positions 0 to 15 in Kronecker order
    var c = 0usize
    var q = p
    var k = 0usize
    while k < 4usize {
        if q % 2usize == 0usize { c += 1usize }
        q = q / 2usize
        k += 1usize
    }
    ret c
}

// psi (a, b): the kernel functional estimate of the derivative with a in the first variable and b in the second, bandwidth g (G = g^2 I), unbinned, inc = 1
fn psi_ab(x: []const f64, n: usize, g: f64, a: usize, b: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            s += k1.dnorm_deriv(x[i * 2usize] - x[j * 2usize], g, a) * k1.dnorm_deriv(x[i * 2usize + 1usize] - x[j * 2usize + 1usize], g, b)
            j += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    let k0 = k1.dnorm_deriv(0.0f64, g, a) * k1.dnorm_deriv(0.0f64, g, b)
    ret (2.0f64 * s + nf * k0) / (nf * nf)
}

fn half_even_l(l: usize) -> usize {
    // symconv: round(N / 2) + 1 with N / 2 = l - 0.5, R rounding half to even
    if (l - 1usize) % 2usize == 0usize { ret l }
    ret l + 1usize
}

// the 1-D filtering step of the separable binned convolution: out[t] = sum_j k[j] v[N + t + 1 - j - lp] over the 1-based indices, along one axis of an m1 by m2 column-major array
fn conv_axis(src: []const f64, dst: []f64, m1: usize, m2: usize, k: []const f64, lp: usize, axis: usize) {
    let nn = k.len
    var t2 = 0usize
    while t2 < m2 {
        var t1 = 0usize
        while t1 < m1 {
            var s = 0.0f64
            var j = 1usize
            while j <= nn {
                var t = t1 + 1usize
                if axis == 1usize { t = t2 + 1usize }
                let c = i64(nn + t + 1usize) - i64(j) - i64(lp)
                var lim = m1
                if axis == 1usize { lim = m2 }
                if c >= 1i64 && c <= i64(lim) {
                    if axis == 0usize { s += k[j - 1usize] * src[t2 * m1 + usize(c) - 1usize] } else { s += k[j - 1usize] * src[(usize(c) - 1usize) * m1 + t1] }
                }
                j += 1usize
            }
            dst[t2 * m1 + t1] = s
            t1 += 1usize
        }
        t2 += 1usize
    }
}

// kfe(x, G = g^2 I, deriv.order = a + b, binned = TRUE) for the (a, b) derivative: linear binning on the 151 by 151 grid of massdist2d,
// kdde.binned.nd and symconv.nd as separable direct sums (the kernel is a product of one-dimensional derivatives)
fn psi_binned(a: *mem.Arena, x: []const f64, n: usize, g: f64, ra: usize, rb: usize) -> f64 {
    let m = 151usize
    var lo: [2]f64 = zero
    var hi: [2]f64 = zero
    var dl: [2]f64 = zero
    var j = 0usize
    while j < 2usize {
        var mn = x[j]
        var mx = x[j]
        var i = 1usize
        while i < n {
            if x[i * 2usize + j] < mn { mn = x[i * 2usize + j] }
            if x[i * 2usize + j] > mx { mx = x[i * 2usize + j] }
            i += 1usize
        }
        lo[j] = mn - 3.7f64 * g
        hi[j] = mx + 3.7f64 * g
        dl[j] = (hi[j] - lo[j]) / f64(m - 1usize)
        j += 1usize
    }
    let start = mem.mark(a)
    let (cnt, e1) = mem.alloc[f64](a, m * m)
    let (tmp, e2) = mem.alloc[f64](a, m * m)
    let (est, e3) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < m * m {
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let p1 = (x[i * 2usize] - lo[0]) / dl[0]
        let p2 = (x[i * 2usize + 1usize] - lo[1]) / dl[1]
        let i1 = i64(math.floor[f64](p1))
        let i2 = i64(math.floor[f64](p2))
        let f1 = p1 - f64(i1)
        let f2 = p2 - f64(i2)
        if i1 >= 0i64 && i2 >= 0i64 && i2 <= i64(m) - 2i64 && i1 <= i64(m) - 2i64 {
            let u1 = usize(i1)
            let u2 = usize(i2)
            cnt[u2 * m + u1] += (1.0f64 - f1) * (1.0f64 - f2)
            cnt[u2 * m + u1 + 1usize] += f1 * (1.0f64 - f2)
            cnt[(u2 + 1usize) * m + u1] += (1.0f64 - f1) * f2
            cnt[(u2 + 1usize) * m + u1 + 1usize] += f1 * f2
        }
        i += 1usize
    }
    var ll: [2]usize = zero
    j = 0usize
    while j < 2usize {
        var l = usize(math.ceil[f64](f64(4usize + ra + rb) * g / dl[j]))
        if l > m - 1usize { l = m - 1usize }
        ll[j] = l
        j += 1usize
    }
    let n1 = 2usize * ll[0usize] - 1usize
    let n2 = 2usize * ll[1usize] - 1usize
    let (k1v, e4) = mem.alloc[f64](a, n1)
    let (k2v, e5) = mem.alloc[f64](a, n2)
    if e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    var q = 0usize
    while q < n1 {
        k1v[q] = k1.dnorm_deriv(dl[0usize] * (f64(q) - f64(ll[0usize] - 1usize)), g, ra) / f64(n)
        q += 1usize
    }
    q = 0usize
    while q < n2 {
        k2v[q] = k1.dnorm_deriv(dl[1usize] * (f64(q) - f64(ll[1usize] - 1usize)), g, rb)
        q += 1usize
    }
    conv_axis(cnt, tmp, m, m, k2v, half_even_l(ll[1usize]), 1usize)
    conv_axis(tmp, est, m, m, k1v, half_even_l(ll[0usize]), 0usize)
    var sum = 0.0f64
    i = 0usize
    while i < m * m {
        sum += cnt[i] * f64(n) * est[i]
        i += 1usize
    }
    mem.reset(a, start)
    ret sum / (f64(n) * f64(n))
}

fn psi_any(a: *mem.Arena, x: []const f64, n: usize, g: f64, ra: usize, rb: usize, binned: bool) -> f64 {
    if binned { ret psi_binned(a, x, n, g, ra, rb) }
    ret psi_ab(x, n, g, ra, rb)
}

// psins (a, b) at the identity: the (a, b) derivative of the N(0, 2 I) density at the origin
fn psins2(a: usize, b: usize) -> f64 {
    let s2 = math.sqrt[f64](2.0f64)
    ret k1.dnorm_deriv(0.0f64, s2, a) * k1.dnorm_deriv(0.0f64, s2, b)
}

// gsamse(I, n, modr, nstage, psihat6) for d = 2; psi6 holds psi(6,0), psi(5,1), psi(4,2) of the sixth-order kfe when nstage is 2
fn gsamse2(n: usize, modr: usize, nstage: usize, p60: f64, p51: f64, p42: f64) -> f64 {
    var a1 = 0.0f64
    var a2 = 0.0f64
    var a3 = 0.0f64
    var k = 0usize
    while k <= modr / 2usize {
        let ra = modr - 2usize * k
        let rb = 2usize * k
        let kv = k1.dnorm_deriv(0.0f64, 1.0f64, ra) * k1.dnorm_deriv(0.0f64, 1.0f64, rb)
        var ps = 0.0f64
        if nstage == 2usize && modr == 4usize {
            // positions 1 to 7 of the sixth-order vector hold the counts (6,0) (5,1) (5,1) (4,2) (5,1) (4,2) (4,2)
            var j = 0usize
            while j < 2usize {
                var ca = ra + 2usize
                if j == 1usize { ca = ra }
                let pos = 6usize - ca
                var v = p60
                if pos == 1usize || pos == 2usize || pos == 4usize { v = p51 }
                if pos == 3usize || pos == 5usize || pos == 6usize { v = p42 }
                ps += v
                j += 1usize
            }
        } else {
            ps = psins2(ra + 2usize, rb) + psins2(ra, rb + 2usize)
        }
        a1 += kv * kv
        a2 += kv * ps
        a3 += ps * ps
        k += 1usize
    }
    let md = f64(modr)
    let b1 = (2.0f64 * md + 4.0f64) * a1
    let b2 = (md + 2.0f64 - 2.0f64) * a2
    let gamma1 = (0.0f64 - b2 + math.sqrt[f64](b2 * b2 + 4.0f64 * b1 * a3)) / (2.0f64 * b1)
    ret math.pow[f64](gamma1 * f64(n), 0.0f64 - 1.0f64 / (md + 4.0f64))
}

type PiCtx = struct { n: usize, psi: []const f64 }

// the plug-in AMISE at vech(H^(1/2)): int.var + 1/4 vec(H)' Psi vec(H), Psi from the sixteen fourth-order functionals
fn pi_obj(c: *PiCtx, v: []const f64) -> f64 {
    let h11 = v[0usize] * v[0usize] + v[1usize] * v[1usize]
    let h12 = v[1usize] * (v[0usize] + v[2usize])
    let h22 = v[1usize] * v[1usize] + v[2usize] * v[2usize]
    let det = h11 * h22 - h12 * h12
    let ivar = 1.0f64 / (math.sqrt[f64](det) * f64(c.n)) * 0.25f64 / 3.141592653589793f64
    var vh: [4]f64 = zero
    vh[0usize] = h11
    vh[1usize] = h12
    vh[2usize] = h12
    vh[3usize] = h22
    var q = 0.0f64
    var j = 0usize
    while j < 4usize {
        var i = 0usize
        while i < 4usize {
            q += vh[i] * vh[j] * c.psi[j * 4usize + i]
            i += 1usize
        }
        j += 1usize
    }
    ret ivar + 0.25f64 * q
}

fn pi_grad(c: *PiCtx, v: []const f64, g: []f64) {
    var w: [3]f64 = zero
    var j = 0usize
    while j < 3usize {
        w[0usize] = v[0usize]
        w[1usize] = v[1usize]
        w[2usize] = v[2usize]
        w[j] = v[j] + 0.001f64
        let v1 = pi_obj(c, w[0usize..3usize])
        w[j] = v[j] - 0.001f64
        let v2 = pi_obj(c, w[0usize..3usize])
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// Hpi(x, nstage, pilot = "samse", pre = "sphere", binned = FALSE) for n by 2 row-major x into h (2 by 2)
fn hpi2b(a: *mem.Arena, x: []const f64, n: usize, nstage: usize, binned: bool, h: []f64) -> err {
    var s: [4]f64 = zero
    var sinv: [4]f64 = zero
    var s12: [4]f64 = zero
    var si12: [4]f64 = zero
    cov2(x, n, s[0usize..4usize])
    sqrt2(s[0usize..4usize], s12[0usize..4usize])
    inv2(s[0usize..4usize], sinv[0usize..4usize])
    sqrt2(sinv[0usize..4usize], si12[0usize..4usize])
    let (xs, e1) = mem.alloc[f64](a, n * 2usize)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        xs[i * 2usize] = x[i * 2usize] * si12[0usize] + x[i * 2usize + 1usize] * si12[2usize]
        xs[i * 2usize + 1usize] = x[i * 2usize] * si12[1usize] + x[i * 2usize + 1usize] * si12[3usize]
        i += 1usize
    }
    var pm: [16]f64 = zero
    var psi4: [16]f64 = zero
    if nstage == 2usize {
        let g6 = gsamse2(n, 6usize, 1usize, 0.0f64, 0.0f64, 0.0f64)
        let p60 = psi_any(a, xs, n, g6, 6usize, 0usize, binned)
        let p51 = psi_any(a, xs, n, g6, 5usize, 1usize, binned)
        let p42 = psi_any(a, xs, n, g6, 4usize, 2usize, binned)
        let g4 = gsamse2(n, 4usize, 2usize, p60, p51, p42)
        var c = 0usize
        while c <= 4usize {
            pm[c] = psi_any(a, xs, n, g4, 4usize - c, c, binned)
            c += 1usize
        }
    } else {
        let g4 = gsamse2(n, 4usize, 1usize, 0.0f64, 0.0f64, 0.0f64)
        var c = 0usize
        while c <= 4usize {
            pm[c] = psi_any(a, xs, n, g4, 4usize - c, c, binned)
            c += 1usize
        }
    }
    var p = 0usize
    while p < 16usize {
        psi4[p] = pm[4usize - d4count(p)]
        p += 1usize
    }
    var hs: [4]f64 = zero
    var hn: [4]f64 = zero
    hns2(xs, n, hn[0usize..4usize])
    sqrt2(hn[0usize..4usize], hs[0usize..4usize])
    var par: [3]f64 = zero
    par[0usize] = hs[0usize]
    par[1usize] = hs[2usize]
    par[2usize] = hs[3usize]
    var ctx = PiCtx{ n: n, psi: psi4[0usize..16usize] }
    let fmin = bf.vmmin[PiCtx](a, &ctx, pi_obj, pi_grad, par[0usize..3usize], 1.4901161193847656e-08f64, 100usize)
    if fmin != fmin { ret Failed }
    var q: [4]f64 = zero
    q[0usize] = par[0usize]
    q[1usize] = par[1usize]
    q[2usize] = par[1usize]
    q[3usize] = par[2usize]
    var hh: [4]f64 = zero
    mul2(q[0usize..4usize], q[0usize..4usize], hh[0usize..4usize])
    var t1: [4]f64 = zero
    mul2(s12[0usize..4usize], hh[0usize..4usize], t1[0usize..4usize])
    mul2(t1[0usize..4usize], s12[0usize..4usize], h)
    ret ok
}

fn hpi2(a: *mem.Arena, x: []const f64, n: usize, nstage: usize, h: []f64) -> err {
    ret hpi2b(a, x, n, nstage, false, h)
}

type LsCtx = struct { x: []const f64, n: usize, hdet: f64, init: f64, trunc: f64, diag: bool }

// the unbinned LSCV(H) for H = [[h11, h12], [h12, h22]]
fn lscv2(x: []const f64, n: usize, h11: f64, h12: f64, h22: f64) -> f64 {
    let nf = f64(n)
    var term = 0usize
    var tot = 0.0f64
    var tot2 = 0.0f64
    while term < 2usize {
        var m = 1.0f64
        if term == 0usize { m = 2.0f64 }
        let a11 = m * h11
        let a12 = m * h12
        let a22 = m * h22
        let det = a11 * a22 - a12 * a12
        let i11 = a22 / det
        let i12 = 0.0f64 - a12 / det
        let i22 = a11 / det
        var s = 0.0f64
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                let dx = x[i * 2usize] - x[j * 2usize]
                let dy = x[i * 2usize + 1usize] - x[j * 2usize + 1usize]
                s += math.exp[f64](0.0f64 - 0.5f64 * (dx * dx * i11 + 2.0f64 * dx * dy * i12 + dy * dy * i22))
                j += 1usize
            }
            i += 1usize
        }
        let k = 1.0f64 / (2.0f64 * 3.141592653589793f64) / math.sqrt[f64](det)
        if term == 0usize { tot = k * s / (nf * nf) } else { tot2 = (k * s - nf * k) / (nf * (nf - 1.0f64)) }
        term += 1usize
    }
    ret tot - 2.0f64 * tot2
}

fn ls_obj(c: *LsCtx, v: []const f64) -> f64 {
    var h11 = 0.0f64
    var h12 = 0.0f64
    var h22 = 0.0f64
    if c.diag {
        h11 = v[0usize] * v[0usize]
        h22 = v[1usize] * v[1usize]
    } else {
        h11 = v[0usize] * v[0usize] + v[1usize] * v[1usize]
        h12 = v[1usize] * (v[0usize] + v[2usize])
        h22 = v[1usize] * v[1usize] + v[2usize] * v[2usize]
    }
    let det = h11 * h22 - h12 * h12
    var l = lscv2(c.x, c.n, h11, h12, h22)
    var da = det - c.hdet / c.trunc
    var db = det - c.hdet * c.trunc
    var la = math.abs[f64](l) - c.trunc * math.abs[f64](c.init)
    if da < 0.0f64 || db > 0.0f64 || la > 0.0f64 { l = c.init }
    ret l
}

// Hlscv(x, binned = FALSE) (diag false) and Hlscv.diag (diag true) for n by 2 row-major x into h (2 by 2)
fn hlscv2(a: *mem.Arena, x: []const f64, n: usize, diag: bool, h: []f64) -> err {
    var hn: [4]f64 = zero
    hns2(x, n, hn[0usize..4usize])
    var hs: [4]f64 = zero
    sqrt2(hn[0usize..4usize], hs[0usize..4usize])
    let hdet = hn[0usize] * hn[3usize] - hn[1usize] * hn[2usize]
    var ctx = LsCtx{ x: x, n: n, hdet: hdet, init: lscv2(x, n, hn[0usize], hn[1usize], hn[3usize]), trunc: 1.0e10f64, diag: diag }
    var start: [3]f64 = zero
    var out: [3]f64 = zero
    var np = 3usize
    if diag {
        np = 2usize
        start[0usize] = hs[0usize]
        start[1usize] = hs[3usize]
    } else {
        start[0usize] = hs[0usize]
        start[1usize] = hs[2usize]
        start[2usize] = hs[3usize]
    }
    let (fv, cnt, fail) = nm.nmmin[LsCtx](a, &ctx, ls_obj, start[0usize..np], 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out[0usize..np])
    if fv != fv { ret Failed }
    if diag {
        h[0usize] = out[0usize] * out[0usize]
        h[1usize] = 0.0f64
        h[2usize] = 0.0f64
        h[3usize] = out[1usize] * out[1usize]
    } else {
        h[0usize] = out[0usize] * out[0usize] + out[1usize] * out[1usize]
        h[1usize] = out[1usize] * (out[0usize] + out[2usize])
        h[2usize] = h[1usize]
        h[3usize] = out[1usize] * out[1usize] + out[2usize] * out[2usize]
    }
    ret ok
}
