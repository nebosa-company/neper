// R ks kroc(x1, x2, h1 = , hy = ) in one dimension and kroc(x1, x2, H1 = , hy = ) in two: the upper-tail kernel cdf of x1 (kcde, a cumulative sum of the
// gridded density, binned by default above one observation in 1-d and above 500 in 2-d), the probit of the cdf at x1 and x2, the lower-tail cdfs of the two
// transformed samples with bandwidth hy, the ROC curve as one against the other smoothed by smooth.spline(spar = 0.5) and its summary indices.
//
// Not here: the default bandwidths of hpi.kcde and Hpi.kcde, three dimensions, positive support, weights, eval.points.

use e.algo.stat.ks2dkde as kk
use e.algo.stat.kssmooth as sm
use e.algo.stat.ksnd as nd
use e.math
use e.math.dist as dist
use e.mem

error Failed

// cdf estimate on the grid in gp from the gridded density in est (m^d cells): the cumulative sum of kcde, normalised by its maximum
fn cdf_1d(est: []f64, gp: []const f64, upper: bool) {
    let m = est.len
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += est[i]
        i += 1usize
    }
    var cs = 0.0f64
    var mx = 0.0f64
    i = 0usize
    while i < m {
        cs += est[i]
        var dv = 0.0f64
        if upper {
            var d1 = math.abs[f64](gp[1usize] - gp[0usize])
            if i > 0usize { d1 = math.abs[f64](gp[i] - gp[i - 1usize]) }
            dv = d1 * (s - cs)
        } else {
            if i > 0usize { dv = math.abs[f64](gp[i] - gp[i - 1usize]) * cs }
        }
        est[i] = dv
        if i == 0usize || dv > mx { mx = dv }
        i += 1usize
    }
    i = 0usize
    while i < m {
        est[i] = est[i] / mx
        i += 1usize
    }
}

// the 2-d upper-tail cdf, with the matrix operations of kcde read as written (apply over rows, recycling down columns)
fn cdf_2d_upper(a: *mem.Arena, est: []f64, gx: []const f64, gy: []const f64) -> err {
    let m = gx.len
    let (t1, e1) = mem.alloc[f64](a, m * m)
    let (rs, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret e1 }
    let d1 = math.abs[f64](gx[1usize] - gx[0usize])
    let d2 = math.abs[f64](gy[1usize] - gy[0usize])
    var i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += est[i + m * j]
            j += 1usize
        }
        rs[i] = s
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var cs = 0.0f64
            var k = 0usize
            while k <= i {
                cs += est[j + m * k]
                k += 1usize
            }
            var dv = d1
            if i > 0usize { dv = math.abs[f64](gx[i] - gx[i - 1usize]) }
            t1[i + m * j] = (rs[j] - cs) * dv
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            s += t1[i + m * j]
            j += 1usize
        }
        rs[i] = s
        i += 1usize
    }
    var mx = 0.0f64
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var cs = 0.0f64
            var k = 0usize
            while k <= i {
                cs += t1[j + m * k]
                k += 1usize
            }
            var dv = d2
            if i > 0usize { dv = math.abs[f64](gy[i] - gy[i - 1usize]) }
            let v = (rs[j] - cs) * dv
            est[i + m * j] = v
            if (i == 0usize && j == 0usize) || v > mx { mx = v }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m * m {
        est[i] = est[i] / mx
        i += 1usize
    }
    ret ok
}

fn probit_filter(a: *mem.Arena, x: []const f64, n: usize, d: usize, gp: []const f64, m: usize, grid: []const f64, out: []f64) -> usize {
    var kept = 0usize
    var i = 0usize
    while i < n {
        let v = nd.interp_nd(gp, m, d, grid, x[i * d..i * d + d])
        if v > 0.0f64 {
            out[kept] = dist.qnorm(v, 0.0f64, 1.0f64, true, false)
            kept += 1usize
        }
        i += 1usize
    }
    ret kept
}

// kroc: res[0..401] the ROC estimate at seq(0, 1, length = 401); idx = (auc, youden, LR minus, LR plus)
fn kroc(a: *mem.Arena, x1: []const f64, n1: usize, x2: []const f64, n2: usize, d: usize, hx: []const f64, hy: f64, res: []f64, idx: []f64) -> err {
    var m = 401usize
    if d == 2usize { m = 151usize }
    var binned = n1 > 1usize
    if d == 2usize { binned = n1 > 500usize }
    let total = nd.pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (grid, e2) = mem.alloc[f64](a, total)
    let (y1, e3) = mem.alloc[f64](a, n1)
    let (y2, e4) = mem.alloc[f64](a, n2)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    if binned {
        let be = nd.kde_binned(a, x1, n1, d, hx, m, gp, grid)
        if be != ok { ret be }
    } else {
        nd.kde_grid(a, x1, n1, d, hx, m, gp, grid)
    }
    if d == 1usize {
        cdf_1d(grid, gp, true)
    } else {
        let ce = cdf_2d_upper(a, grid, gp[0usize..m], gp[m..2usize * m])
        if ce != ok { ret ce }
    }
    let k1 = probit_filter(a, x1, n1, d, gp, m, grid, y1)
    let k2 = probit_filter(a, x2, n2, d, gp, m, grid, y2)
    if k1 == 0usize || k2 == 0usize { ret Failed }
    var lo = y1[0usize]
    var hi = y1[0usize]
    var i = 0usize
    while i < k1 {
        if y1[i] < lo { lo = y1[i] }
        if y1[i] > hi { hi = y1[i] }
        i += 1usize
    }
    i = 0usize
    while i < k2 {
        if y2[i] < lo { lo = y2[i] }
        if y2[i] > hi { hi = y2[i] }
        i += 1usize
    }
    lo = lo - 3.7f64 * hy
    hi = hi + 3.7f64 * hy
    let my = 401usize
    let (gy, e5) = mem.alloc[f64](a, my)
    let (c1, e6) = mem.alloc[f64](a, my)
    let (c2, e7) = mem.alloc[f64](a, my)
    if e5 != ok || e6 != ok || e7 != ok { ret e5 }
    kk.seq_len_out(lo, hi, my, gy)
    var hv: [1]f64 = zero
    hv[0usize] = hy * hy
    let b1 = nd.kde_binned_on(a, y1[0usize..k1], k1, 1usize, hv[0usize..1usize], my, gy, c1)
    if b1 != ok { ret b1 }
    let b2 = nd.kde_binned_on(a, y2[0usize..k2], k2, 1usize, hv[0usize..1usize], my, gy, c2)
    if b2 != ok { ret b2 }
    cdf_1d(c1, gy, false)
    cdf_1d(c2, gy, false)
    let (xo, e8) = mem.alloc[f64](a, my)
    if e8 != ok { ret e8 }
    kk.seq_len_out(0.0f64, 1.0f64, my, xo)
    let se = sm.smooth_spline(a, c1, c2, 0.5f64, xo, res)
    if se != ok { ret se }
    if res[0usize] != 0.0f64 { res[0usize] = 0.0f64 }
    if res[my - 1usize] != 1.0f64 { res[my - 1usize] = 1.0f64 }
    i = 0usize
    while i < my {
        if res[i] > 1.0f64 { res[i] = 1.0f64 }
        if res[i] < 0.0f64 { res[i] = 0.0f64 }
        i += 1usize
    }
    var auc = 0.0f64
    i = 0usize
    while i + 1usize < my {
        let dx = math.abs[f64](xo[i + 1usize] - xo[i])
        auc += math.abs[f64](res[i] - res[i + 1usize]) * dx / 2.0f64 + res[i] * dx
        i += 1usize
    }
    var best = res[0usize] - xo[0usize]
    var bi = 0usize
    i = 1usize
    while i < my {
        let v = res[i] - xo[i]
        if v > best {
            best = v
            bi = i
        }
        i += 1usize
    }
    idx[0usize] = auc
    idx[1usize] = best
    if best > 0.001f64 {
        idx[2usize] = (1.0f64 - res[bi]) / (1.0f64 - xo[bi])
        idx[3usize] = res[bi] / xo[bi]
    } else {
        idx[2usize] = 1.0f64
        idx[3usize] = 1.0f64
    }
    ret ok
}
