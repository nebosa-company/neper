// R ks kde.test for two samples in three and four dimensions (H1 and H2 given, exact estimation) and rkde in any dimension from two to four.
// var.fhat is the gridded gradient estimate with Hns of order one interpolated at the mean (three dimensions, as R's kdde has no grid above three);
// in four dimensions R needs var.fhat1 and var.fhat2 given, which is the only form here.
//
// Not here: the default Hpi.kfe bandwidths above two dimensions, binned estimation.

use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.algo.stat.kslocal as kl
use e.algo.stat.ks2dtest as kt
use e.algo.stat.ksnd as nd
use e.algo.stat.mvtnorm as mv
use e.math
use e.mem

// Qr(x, y, Sigma) at r = 0: the mean of the N(0, Sigma) density over all differences x_i - y_j
fn qcross(x: []const f64, nx: usize, y: []const f64, ny: usize, d: usize, h: []const f64) -> f64 {
    var hinv: [16]f64 = zero
    let det = nd.inv_det(h, d, hinv[0usize..16usize])
    let c = nd.norm_const(det, d)
    var z: [4]f64 = zero
    var s = 0.0f64
    var j = 0usize
    while j < ny {
        var i = 0usize
        while i < nx {
            var k = 0usize
            while k < d {
                z[k] = x[i * d + k] - y[j * d + k]
                k += 1usize
            }
            s += math.exp[f64](0.0f64 - 0.5f64 * nd.quad(hinv[0usize..16usize], d, z[0usize..4usize]))
            i += 1usize
        }
        j += 1usize
    }
    ret s * c / (f64(nx) * f64(ny))
}

// var.fhat of kde.test in three dimensions: g S g' with g the gradient of kdde(x, Hns(x, deriv.order = 1)) interpolated at the mean
fn var_fhat_nd(a: *mem.Arena, x: []const f64, n: usize, d: usize) -> f64 {
    var h: [16]f64 = zero
    nd.hns(x, n, d, 1usize, h[0usize..16usize])
    let m = 51usize
    let total = nd.pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (grid, e2) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    nd.kde_grid(a, x, n, d, h[0usize..16usize], m, gp, grid)
    var mu: [4]f64 = zero
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i * d + j]
            i += 1usize
        }
        mu[j] = s / f64(n)
        j += 1usize
    }
    var g: [4]f64 = zero
    j = 0usize
    while j < d {
        nd.kde_grid_on(a, x, n, d, h[0usize..16usize], m, gp, grid, 100usize + j)
        g[j] = nd.interp_nd(gp, m, d, grid, mu[0usize..4usize])
        j += 1usize
    }
    var s: [16]f64 = zero
    nd.cov_nd(x, n, d, s[0usize..16usize])
    var v = 0.0f64
    j = 0usize
    while j < d {
        var k = 0usize
        while k < d {
            v += g[j] * s[j * d + k] * g[k]
            k += 1usize
        }
        j += 1usize
    }
    ret v
}

// kde.test(x1, x2, H1, H2) in d dimensions; v1 and v2 are var.fhat1 and var.fhat2 (NaN: the default, three dimensions only)
fn kde_test_nd(a: *mem.Arena, x1: []const f64, n1: usize, x2: []const f64, n2: usize, d: usize, h1: []const f64, h2: []const f64, v1: f64, v2: f64, out: []f64) {
    let k0 = math.pow[f64](2.0f64 * 3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64)
    let psi1 = qcross(x1, n1, x1, n1, d, h1)
    let psi2 = qcross(x2, n2, x2, n2, d, h2)
    let psi12 = qcross(x1, n1, x2, n2, d, h1)
    let psi21 = qcross(x2, n2, x1, n1, d, h2)
    var s1: [16]f64 = zero
    var s2: [16]f64 = zero
    let d1 = nd.inv_det(h1, d, s1[0usize..16usize])
    let d2 = nd.inv_det(h2, d, s2[0usize..16usize])
    let mu = (1.0f64 / f64(n1) / math.sqrt[f64](d1) + 1.0f64 / f64(n2) / math.sqrt[f64](d2)) * k0
    var w1 = v1
    var w2 = v2
    if w1 != w1 { w1 = var_fhat_nd(a, x1, n1, d) }
    if w2 != w2 { w2 = var_fhat_nd(a, x2, n2, d) }
    kt.test_parts(psi1 + psi2 - (psi12 + psi21), mu, f64(n1), f64(n2), w1, w2, out)
}

// rkde(n, kde(x, H)) in d dimensions (equal weights) under the seed: rmvnorm(n, 0, I) %*% sqrt(H) added to the sampled rows
fn rkde_nd(a: *mem.Arena, seed: i64, x: []const f64, nobs: usize, d: usize, h: []const f64, size: usize, out: []f64) -> err {
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let (w, we) = mem.alloc[f64](a, nobs)
    if we != ok { ret we }
    var i = 0usize
    while i < nobs {
        w[i] = 1.0f64
        i += 1usize
    }
    let (ind, ie) = rd.sample_prob(a, &g, nobs, size, true, w)
    if ie != ok { ret ie }
    var id: [16]f64 = zero
    var z0: [4]f64 = zero
    i = 0usize
    while i < d {
        id[i * d + i] = 1.0f64
        i += 1usize
    }
    let (z, ze) = mv.rmvnorm(a, &g, size, z0[0usize..d], id[0usize..d * d], d, 0u8)
    if ze != ok { ret ze }
    var hs: [16]f64 = zero
    kl.sqrtm(h, d, hs[0usize..16usize])
    i = 0usize
    while i < size {
        let r = usize(ind[i]) - 1usize
        var j = 0usize
        while j < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += z[i * d + k] * hs[k * d + j]
                k += 1usize
            }
            out[i * d + j] = x[r * d + j] + s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}
