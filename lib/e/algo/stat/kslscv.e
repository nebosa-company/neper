// R ks Hlscv and Hlscv.diag in d dimensions (2 to 4, unbinned): optim Nelder-Mead on the least-squares cross-validation criterion over vech of the square
// root of H (the full matrix) or over the square roots of the diagonal, started from Hns, with the truncation to the normal-scale determinant range.
//
// Not here: binned = TRUE above 1000 observations in three and four dimensions, deriv.order above 0.

use e.algo.stat.ksnd as nd
use e.algo.stat.kslocal as kl
use e.algo.stat.rnm as nm
use e.math
use e.mem

error Failed

type LsCtx = struct { x: []const f64, n: usize, d: usize, hdet: f64, init: f64, trunc: f64, diag: bool }

// the unbinned LSCV(H): the mean of N(0, 2H) at every difference minus twice the mean of N(0, H) at every difference of distinct observations
fn lscv_nd(x: []const f64, n: usize, d: usize, h: []const f64) -> f64 {
    let nf = f64(n)
    var term = 0usize
    var tot = 0.0f64
    var tot2 = 0.0f64
    while term < 2usize {
        var a: [16]f64 = zero
        var mul = 1.0f64
        if term == 0usize { mul = 2.0f64 }
        var q = 0usize
        while q < d * d {
            a[q] = mul * h[q]
            q += 1usize
        }
        var inv: [16]f64 = zero
        let det = nd.inv_det(a[0usize..16usize], d, inv[0usize..16usize])
        var z: [4]f64 = zero
        var s = 0.0f64
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var c = 0usize
                while c < d {
                    z[c] = x[i * d + c] - x[j * d + c]
                    c += 1usize
                }
                s += math.exp[f64](0.0f64 - 0.5f64 * nd.quad(inv[0usize..16usize], d, z[0usize..4usize]))
                j += 1usize
            }
            i += 1usize
        }
        let k = nd.norm_const(det, d)
        if term == 0usize {
            tot = k * s / (nf * nf)
        } else {
            tot2 = (k * s - nf * k) / (nf * (nf - 1.0f64))
        }
        term += 1usize
    }
    ret tot - 2.0f64 * tot2
}

// H from the parameters: invvech(v) %*% invvech(v), or diag(v^2)
fn make_h(v: []const f64, d: usize, diag: bool, h: []f64) {
    var i = 0usize
    while i < d * d {
        h[i] = 0.0f64
        i += 1usize
    }
    if diag {
        i = 0usize
        while i < d {
            h[i * d + i] = v[i] * v[i]
            i += 1usize
        }
        ret
    }
    var s: [16]f64 = zero
    var at = 0usize
    var c = 0usize
    while c < d {
        var r = c
        while r < d {
            s[r * d + c] = v[at]
            s[c * d + r] = v[at]
            at += 1usize
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            var t = 0.0f64
            var k = 0usize
            while k < d {
                t += s[i * d + k] * s[k * d + j]
                k += 1usize
            }
            h[i * d + j] = t
            j += 1usize
        }
        i += 1usize
    }
}

fn ls_obj(c: *LsCtx, v: []const f64) -> f64 {
    var h: [16]f64 = zero
    make_h(v, c.d, c.diag, h[0usize..16usize])
    var inv: [16]f64 = zero
    let det = nd.inv_det(h[0usize..16usize], c.d, inv[0usize..16usize])
    var l = lscv_nd(c.x, c.n, c.d, h[0usize..16usize])
    let da = det - c.hdet / c.trunc
    let db = det - c.hdet * c.trunc
    let la = math.abs[f64](l) - c.trunc * math.abs[f64](c.init)
    if da < 0.0f64 || db > 0.0f64 || la > 0.0f64 { l = c.init }
    ret l
}

// Hlscv(x, binned = FALSE) (diag false) and Hlscv.diag (diag true) for n by d row-major x into h (d by d)
fn hlscv(a: *mem.Arena, x: []const f64, n: usize, d: usize, diag: bool, h: []f64) -> err {
    var hn: [16]f64 = zero
    nd.hns(x, n, d, 0usize, hn[0usize..16usize])
    var hs: [16]f64 = zero
    kl.sqrtm(hn[0usize..16usize], d, hs[0usize..16usize])
    var inv: [16]f64 = zero
    let hdet = nd.inv_det(hn[0usize..16usize], d, inv[0usize..16usize])
    var ctx = LsCtx{ x: x, n: n, d: d, hdet: hdet, init: lscv_nd(x, n, d, hn[0usize..16usize]), trunc: 1.0e10f64, diag: diag }
    var start: [10]f64 = zero
    var out: [10]f64 = zero
    var np = 0usize
    if diag {
        np = d
        var i = 0usize
        while i < d {
            start[i] = hs[i * d + i]
            i += 1usize
        }
    } else {
        var c = 0usize
        while c < d {
            var r = c
            while r < d {
                start[np] = hs[r * d + c]
                np += 1usize
                r += 1usize
            }
            c += 1usize
        }
    }
    let (fv, cnt, fail) = nm.nmmin[LsCtx](a, &ctx, ls_obj, start[0usize..np], 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, out[0usize..np])
    if fv != fv { ret Failed }
    make_h(out[0usize..np], d, diag, h)
    ret ok
}
