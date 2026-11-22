// R ks, two dimensions, the diagonal selectors with the default SAMSE pilot and the scaling pre-transformation: Hpi.diag (the closed form for d = 2, r = 0)
// and Hscv.diag (optim Nelder-Mead on the SCV criterion over the diagonal). The pre-scaled data have the correlation matrix as covariance, so the
// normal-scale functionals of gsamse are the correlated ones (Isserlis moments of kspi); everything else is the sphered code of ks2d and ks2dscv.
//
// Not here: binned estimation above 500 observations, the other pilots.

use e.algo.stat.ks2d as k2
use e.algo.stat.ks2dscv as sc
use e.algo.stat.ks1d as k1
use e.algo.stat.kspi as kp
use e.algo.stat.rnm as nm
use e.math
use e.mem

error Failed

// psins(r = c(a, b), Sigma): the partial derivative (a, b) of the N(0, 2 Sigma) density at zero; c = (2 Sigma)^-1 as 2 by 2 and k0 the density constant
fn psins_s(a: usize, b: usize, c: []const f64, k0: f64) -> f64 {
    var idx: [8]usize = zero
    var i = 0usize
    while i < b {
        idx[a + i] = 1usize
        i += 1usize
    }
    ret kp.psins_at(idx[0usize..8usize], a + b, c, 2usize, k0)
}

// gsamse2 with the normal-scale functionals of the given Sigma
fn gsamse2s(n: usize, modr: usize, nstage: usize, p60: f64, p51: f64, p42: f64, c: []const f64, k0: f64) -> f64 {
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
            ps = psins_s(ra + 2usize, rb, c, k0) + psins_s(ra, rb + 2usize, c, k0)
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

// the scaled data xs = x diag(1/sd), its correlation matrix as (2 Sigma)^-1 and the constant of the N(0, 2 Sigma) density, and the standard deviations
fn scale_pre(x: []const f64, n: usize, xs: []f64, sd: []f64, c: []f64) -> f64 {
    var s: [4]f64 = zero
    k2.cov2(x, n, s[0usize..4usize])
    sd[0usize] = math.sqrt[f64](s[0usize])
    sd[1usize] = math.sqrt[f64](s[3usize])
    var i = 0usize
    while i < n {
        xs[i * 2usize] = x[i * 2usize] / sd[0usize]
        xs[i * 2usize + 1usize] = x[i * 2usize + 1usize] / sd[1usize]
        i += 1usize
    }
    var ss: [4]f64 = zero
    k2.cov2(xs, n, ss[0usize..4usize])
    var s2: [4]f64 = zero
    var q = 0usize
    while q < 4usize {
        s2[q] = 2.0f64 * ss[q]
        q += 1usize
    }
    let det = s2[0usize] * s2[3usize] - s2[1usize] * s2[2usize]
    c[0usize] = s2[3usize] / det
    c[1usize] = 0.0f64 - s2[1usize] / det
    c[2usize] = 0.0f64 - s2[2usize] / det
    c[3usize] = s2[0usize] / det
    ret 1.0f64 / (2.0f64 * 3.141592653589793f64 * math.sqrt[f64](det))
}

// the fourth-order functionals psi(4 - c, c), c = 0..4, of psifun1 / psifun2 with the SAMSE pilot on the scaled data
fn psi4_scaled(a: *mem.Arena, xs: []const f64, n: usize, nstage: usize, c: []const f64, k0: f64, pm: []f64) {
    var g4 = 0.0f64
    if nstage == 2usize {
        let g6 = gsamse2s(n, 6usize, 1usize, 0.0f64, 0.0f64, 0.0f64, c, k0)
        let p60 = k2.psi_any(a, xs, n, g6, 6usize, 0usize, false)
        let p51 = k2.psi_any(a, xs, n, g6, 5usize, 1usize, false)
        let p42 = k2.psi_any(a, xs, n, g6, 4usize, 2usize, false)
        g4 = gsamse2s(n, 4usize, 2usize, p60, p51, p42, c, k0)
    } else {
        g4 = gsamse2s(n, 4usize, 1usize, 0.0f64, 0.0f64, 0.0f64, c, k0)
    }
    var q = 0usize
    while q <= 4usize {
        pm[q] = k2.psi_any(a, xs, n, g4, 4usize - q, q, false)
        q += 1usize
    }
}

// Hpi.diag(x, nstage, pre = "scale") for d = 2 with the SAMSE pilot: the closed form in psi(4,0), psi(2,2), psi(0,4)
fn hpi_diag(a: *mem.Arena, x: []const f64, n: usize, nstage: usize, h: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * 2usize)
    if e1 != ok { ret e1 }
    var sd: [2]f64 = zero
    var c: [4]f64 = zero
    let k0 = scale_pre(x, n, xs, sd[0usize..2usize], c[0usize..4usize])
    var pm: [5]f64 = zero
    psi4_scaled(a, xs, n, nstage, c[0usize..4usize], k0, pm[0usize..5usize])
    let rk = 1.0f64 / (4.0f64 * 3.141592653589793f64)
    let p40 = pm[0usize]
    let p22 = pm[2usize]
    let p04 = pm[4usize]
    let h1 = math.pow[f64](math.pow[f64](p04, 0.75f64) * rk / (math.pow[f64](p40, 0.75f64) * (math.sqrt[f64](p40 * p04) + p22) * f64(n)), 1.0f64 / 6.0f64)
    let h2 = math.pow[f64](p40 / p04, 0.25f64) * h1
    h[0usize] = sd[0usize] * sd[0usize] * h1 * h1
    h[1usize] = 0.0f64
    h[2usize] = 0.0f64
    h[3usize] = sd[1usize] * sd[1usize] * h2 * h2
    ret ok
}

// Hscv.diag(x, nstage, pre = "scale") for d = 2 with the SAMSE pilot
fn hscv_diag(a: *mem.Arena, x: []const f64, n: usize, nstage: usize, h: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * 2usize)
    if e1 != ok { ret e1 }
    var sd: [2]f64 = zero
    var c: [4]f64 = zero
    let k0 = scale_pre(x, n, xs, sd[0usize..2usize], c[0usize..4usize])
    var ham: [4]f64 = zero
    let e2 = k2.hpi2b(a, xs, n, 1usize, false, ham[0usize..4usize])
    if e2 != ok { ret e2 }
    var p6: [7]f64 = zero
    var q = 0usize
    if nstage == 1usize {
        while q <= 6usize {
            p6[q] = psins_s(q, 6usize - q, c[0usize..4usize], k0)
            q += 1usize
        }
    } else {
        let g6 = gsamse2s(n, 6usize, 1usize, 0.0f64, 0.0f64, 0.0f64, c[0usize..4usize], k0)
        while q <= 6usize {
            p6[q] = k2.psi_ab(xs, n, g6, q, 6usize - q)
            q += 1usize
        }
    }
    let gs = sc.gamse_scv(n, ham[0usize..4usize], p6[0usize..7usize])
    var par: [2]f64 = zero
    let np = kp.start_par(xs, n, 2usize, true, par[0usize..2usize])
    var s3: [16]f64 = zero
    s3[0usize] = 2.0f64 * gs * gs
    s3[3usize] = 2.0f64 * gs * gs
    var ctx = kp.ScvCtx{ arena: a, x: xs, n: n, d: 2usize, diag: true, g2: gs * gs, scv3: kp.q_all(a, xs, n, 2usize, s3[0usize..16usize]) }
    var out: [2]f64 = zero
    let (fv, cnt, fail) = nm.nmmin[kp.ScvCtx](a, &ctx, kp.scv_obj, par[0usize..np], 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out[0usize..np])
    if fv != fv { ret Failed }
    h[0usize] = sd[0usize] * sd[0usize] * out[0usize] * out[0usize]
    h[1usize] = 0.0f64
    h[2usize] = 0.0f64
    h[3usize] = sd[1usize] * sd[1usize] * out[1usize] * out[1usize]
    ret ok
}
