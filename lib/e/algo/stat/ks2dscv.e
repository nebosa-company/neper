// R ks, two dimensions: Hscv (smoothed cross-validation with the SAMSE pilot of Chacon and Duong, sphering, unbinned SCV; the AMISE pilot Hpi is
// the binned one-stage plug-in ks asks for) by optim BFGS.
//
// Not here: the scaling pre-transformation, the other pilots, binned SCV above 500 observations, Hscv.diag.

use e.algo.stat.ks1d as k1
use e.algo.stat.ks2d as k2
use e.algo.stat.rbfgs as bf
use e.math
use e.mem

error Failed

// the number of zero digits among the six binary digits of p (zero stands for the first variable in the Kronecker indexing of ks)
fn zeros6(p: usize) -> usize {
    var c = 0usize
    var q = p
    var k = 0usize
    while k < 6usize {
        if q % 2usize == 0usize { c += 1usize }
        q = q / 2usize
        k += 1usize
    }
    ret c
}

// gamse.scv (nstage 0 or 1, Theta6 = FALSE): pilot bandwidth from Hamise (2 by 2) and psi6[a] = psi(a, 6 - a)
fn gamse_scv(n: usize, hm: []const f64, psi6: []const f64) -> f64 {
    var c11 = 0.0f64
    var p1 = 0usize
    while p1 < 2usize {
        var q1 = 0usize
        while q1 < 2usize {
            var m = 0usize
            while m < 16usize {
                var p6 = 0usize
                while p6 < 2usize {
                    var q6 = 0usize
                    while q6 < 2usize {
                        let p = p1 * 32usize + m * 2usize + p6
                        let q = q1 * 32usize + m * 2usize + q6
                        c11 += psi6[zeros6(p)] * hm[p1 * 2usize + q1] * hm[p6 * 2usize + q6] * psi6[zeros6(q)]
                        q6 += 1usize
                    }
                    p6 += 1usize
                }
                m += 1usize
            }
            q1 += 1usize
        }
        p1 += 1usize
    }
    c11 = 0.25f64 * c11
    var c12 = 0.0f64
    var i = 0usize
    while i < 2usize {
        var ip = 0usize
        while ip < 2usize {
            var j = 0usize
            while j < 2usize {
                var k = 0usize
                while k < 2usize {
                    var kp = 0usize
                    while kp < 2usize {
                        let idx = ((((ip * 2usize + j) * 2usize + kp) * 2usize + i) * 2usize + j) * 2usize + k
                        c12 += hm[i * 2usize + ip] * hm[k * 2usize + kp] * psi6[zeros6(idx)]
                        kp += 1usize
                    }
                    k += 1usize
                }
                j += 1usize
            }
            ip += 1usize
        }
        i += 1usize
    }
    let fp = 4.0f64 * 3.141592653589793f64
    c12 = 0.75f64 / fp * c12
    let tr = hm[0usize] + hm[3usize]
    let tr2 = hm[0usize] * hm[0usize] + 2.0f64 * hm[1usize] * hm[2usize] + hm[3usize] * hm[3usize]
    let c22 = 1.0f64 / 64.0f64 / (fp * fp) * (4.0f64 * tr2 + 10.0f64 * tr * tr)
    let num = 12.0f64 * c22
    let den = 0.0f64 - 4.0f64 * c12 + math.sqrt[f64](16.0f64 * c12 * c12 + 48.0f64 * c11 * c22)
    ret math.pow[f64](num / (den * f64(n)), 1.0f64 / 8.0f64)
}

type ScvCtx = struct { x: []const f64, n: usize, g2: f64 }

// Qr(x, Sigma, inc = 1) at r = 0 for Sigma = [[s11, s12], [s12, s22]]
fn q0(x: []const f64, n: usize, s11: f64, s12: f64, s22: f64) -> f64 {
    let det = s11 * s22 - s12 * s12
    let i11 = s22 / det
    let i12 = 0.0f64 - s12 / det
    let i22 = s11 / det
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
    ret s / (2.0f64 * 3.141592653589793f64) / math.sqrt[f64](det) / (f64(n) * f64(n))
}

fn scv_obj(c: *ScvCtx, v: []const f64) -> f64 {
    let h11 = v[0usize] * v[0usize] + v[1usize] * v[1usize]
    let h12 = v[1usize] * (v[0usize] + v[2usize])
    let h22 = v[1usize] * v[1usize] + v[2usize] * v[2usize]
    let g = c.g2
    let s1 = q0(c.x, c.n, 2.0f64 * h11 + 2.0f64 * g, 2.0f64 * h12, 2.0f64 * h22 + 2.0f64 * g)
    let s2 = q0(c.x, c.n, h11 + 2.0f64 * g, h12, h22 + 2.0f64 * g)
    let s3 = q0(c.x, c.n, 2.0f64 * g, 0.0f64, 2.0f64 * g)
    var bias2 = s1 - 2.0f64 * s2 + s3
    if bias2 < 0.0f64 { bias2 = 0.0f64 }
    let det = h11 * h22 - h12 * h12
    ret 1.0f64 / (math.sqrt[f64](det) * f64(c.n)) * 0.25f64 / 3.141592653589793f64 + bias2
}

fn scv_grad(c: *ScvCtx, v: []const f64, g: []f64) {
    var w: [3]f64 = zero
    var j = 0usize
    while j < 3usize {
        w[0usize] = v[0usize]
        w[1usize] = v[1usize]
        w[2usize] = v[2usize]
        w[j] = v[j] + 0.001f64
        let v1 = scv_obj(c, w[0usize..3usize])
        w[j] = v[j] - 0.001f64
        let v2 = scv_obj(c, w[0usize..3usize])
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// Hscv(x, nstage, pilot = "samse", pre = "sphere", binned = FALSE) for n by 2 row-major x into h (2 by 2)
fn hscv2(a: *mem.Arena, x: []const f64, n: usize, nstage: usize, h: []f64) -> err {
    var s: [4]f64 = zero
    var sinv: [4]f64 = zero
    var s12: [4]f64 = zero
    var si12: [4]f64 = zero
    k2.cov2(x, n, s[0usize..4usize])
    k2.sqrt2(s[0usize..4usize], s12[0usize..4usize])
    k2.inv2(s[0usize..4usize], sinv[0usize..4usize])
    k2.sqrt2(sinv[0usize..4usize], si12[0usize..4usize])
    let (xs, e1) = mem.alloc[f64](a, n * 2usize)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        xs[i * 2usize] = x[i * 2usize] * si12[0usize] + x[i * 2usize + 1usize] * si12[2usize]
        xs[i * 2usize + 1usize] = x[i * 2usize] * si12[1usize] + x[i * 2usize + 1usize] * si12[3usize]
        i += 1usize
    }
    var ham: [4]f64 = zero
    let e2 = k2.hpi2b(a, xs, n, 1usize, true, ham[0usize..4usize])
    if e2 != ok { ret e2 }
    var p6: [7]f64 = zero
    var q = 0usize
    if nstage == 1usize {
        while q <= 6usize {
            p6[q] = k2.psins2(q, 6usize - q)
            q += 1usize
        }
    } else {
        let g6 = k2.gsamse2(n, 6usize, 1usize, 0.0f64, 0.0f64, 0.0f64)
        while q <= 6usize {
            p6[q] = k2.psi_ab(xs, n, g6, q, 6usize - q)
            q += 1usize
        }
    }
    let gs = gamse_scv(n, ham[0usize..4usize], p6[0usize..7usize])
    var hn: [4]f64 = zero
    var hs: [4]f64 = zero
    k2.hns2(xs, n, hn[0usize..4usize])
    k2.sqrt2(hn[0usize..4usize], hs[0usize..4usize])
    var par: [3]f64 = zero
    par[0usize] = hs[0usize]
    par[1usize] = hs[2usize]
    par[2usize] = hs[3usize]
    var ctx = ScvCtx{ x: xs, n: n, g2: gs * gs }
    let fmin = bf.vmmin[ScvCtx](a, &ctx, scv_obj, scv_grad, par[0usize..3usize], 1.4901161193847656e-08f64, 100usize)
    if fmin != fmin { ret Failed }
    var qm: [4]f64 = zero
    qm[0usize] = par[0usize]
    qm[1usize] = par[1usize]
    qm[2usize] = par[1usize]
    qm[3usize] = par[2usize]
    var hh: [4]f64 = zero
    k2.mul2(qm[0usize..4usize], qm[0usize..4usize], hh[0usize..4usize])
    var t1: [4]f64 = zero
    k2.mul2(s12[0usize..4usize], hh[0usize..4usize], t1[0usize..4usize])
    k2.mul2(t1[0usize..4usize], s12[0usize..4usize], h)
    ret ok
}
