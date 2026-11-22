// R ks kde.test for two samples: the statistic of Duong, Goria, Hall and Cuevas with bandwidth matrices H1 and H2 given (two dimensions, unbinned, the variance
// of the density estimate at the mean from the gridded gradient estimate with Hns of order one) and in one dimension with the bandwidths and variances given.
//
// Not here: binned estimation (above 500 observations in two dimensions, any in one with binned = TRUE), kde.local.test (see kslocal).

use e.algo.stat.ks2d as k2
use e.algo.stat.ks1d as k1
use e.algo.stat.ks2dkde as kk
use e.algo.stat.kspi as kp
use e.math
use e.math.dist as dist
use e.mem

// Qr(x, y, Sigma) at r = 0 with inc = 1: the mean of the N(0, Sigma) density over all differences x_i - y_j (2 dimensions)
fn qcross2(x: []const f64, nx: usize, y: []const f64, ny: usize, h: []const f64) -> f64 {
    let det = h[0usize] * h[3usize] - h[1usize] * h[2usize]
    let i11 = h[3usize] / det
    let i12 = 0.0f64 - h[1usize] / det
    let i22 = h[0usize] / det
    var s = 0.0f64
    var j = 0usize
    while j < ny {
        var i = 0usize
        while i < nx {
            let dx = x[i * 2usize] - y[j * 2usize]
            let dy = x[i * 2usize + 1usize] - y[j * 2usize + 1usize]
            s += math.exp[f64](0.0f64 - 0.5f64 * (dx * dx * i11 + 2.0f64 * dx * dy * i12 + dy * dy * i22))
            i += 1usize
        }
        j += 1usize
    }
    ret s / (2.0f64 * 3.141592653589793f64 * math.sqrt[f64](det)) / (f64(nx) * f64(ny))
}

// var.fhat of kde.test: the gradient of kdde(x, Hns(x, deriv.order = 1)) on the 151 by 151 grid, interpolated at the mean, as g S g'
fn var_fhat2(a: *mem.Arena, x: []const f64, n: usize) -> f64 {
    let m = 151usize
    var s: [4]f64 = zero
    k2.cov2(x, n, s[0usize..4usize])
    let c = math.pow[f64](4.0f64 / (f64(n) * 6.0f64), 2.0f64 / 8.0f64)
    var h: [4]f64 = zero
    var i = 0usize
    while i < 4usize {
        h[i] = s[i] * c
        i += 1usize
    }
    let (gx, e1) = mem.alloc[f64](a, m)
    let (gy, e2) = mem.alloc[f64](a, m)
    let (f1, e3) = mem.alloc[f64](a, m * m)
    let (f2, e4) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var hs: [4]f64 = zero
    k2.sqrt2(h[0usize..4usize], hs[0usize..4usize])
    let tx = 3.7f64 * hs[0usize]
    let ty = 3.7f64 * hs[3usize]
    var x0 = x[0usize]
    var x1 = x[0usize]
    var y0 = x[1usize]
    var y1 = x[1usize]
    i = 1usize
    while i < n {
        if x[i * 2usize] < x0 { x0 = x[i * 2usize] }
        if x[i * 2usize] > x1 { x1 = x[i * 2usize] }
        if x[i * 2usize + 1usize] < y0 { y0 = x[i * 2usize + 1usize] }
        if x[i * 2usize + 1usize] > y1 { y1 = x[i * 2usize + 1usize] }
        i += 1usize
    }
    kk.seq_len_out(x0 - tx, x1 + tx, m, gx)
    kk.seq_len_out(y0 - ty, y1 + ty, m, gy)
    i = 0usize
    while i < m * m {
        f1[i] = 0.0f64
        f2[i] = 0.0f64
        i += 1usize
    }
    let det = h[0usize] * h[3usize] - h[1usize] * h[2usize]
    let i11 = h[3usize] / det
    let i12 = 0.0f64 - h[1usize] / det
    let i22 = h[0usize] / det
    let kc = 1.0f64 / (2.0f64 * 3.141592653589793f64 * math.sqrt[f64](det))
    i = 0usize
    while i < n {
        let px = x[i * 2usize]
        let py = x[i * 2usize + 1usize]
        var ax = kk.count_le(gx, px - tx)
        if ax == 0usize { ax = 1usize }
        let bx = kk.count_le(gx, px + tx)
        var ay = kk.count_le(gy, py - ty)
        if ay == 0usize { ay = 1usize }
        let by = kk.count_le(gy, py + ty)
        var jy = ay
        while jy <= by {
            var jx = ax
            while jx <= bx {
                let dx = gx[jx - 1usize] - px
                let dy = gy[jy - 1usize] - py
                let phi = kc * math.exp[f64](0.0f64 - 0.5f64 * (dx * dx * i11 + 2.0f64 * dx * dy * i12 + dy * dy * i22))
                f1[(jy - 1usize) * m + jx - 1usize] += 0.0f64 - (i11 * dx + i12 * dy) * phi
                f2[(jy - 1usize) * m + jx - 1usize] += 0.0f64 - (i12 * dx + i22 * dy) * phi
                jx += 1usize
            }
            jy += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m * m {
        f1[i] = f1[i] / f64(n)
        f2[i] = f2[i] / f64(n)
        i += 1usize
    }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < n {
        mx += x[i * 2usize]
        my += x[i * 2usize + 1usize]
        i += 1usize
    }
    mx = mx / f64(n)
    my = my / f64(n)
    let g1 = kk.interp2d(gx, gy, f1, mx, my)
    let g2 = kk.interp2d(gx, gy, f2, mx, my)
    ret g1 * (s[0usize] * g1 + s[1usize] * g2) + g2 * (s[2usize] * g1 + s[3usize] * g2)
}

// the statistic from the five parts: element 0 Tstat, 1 zstat, 2 pvalue, 3 var, 4 var.fhat1, 5 mean
fn test_parts(t: f64, mu: f64, n1: f64, n2: f64, v1: f64, v2: f64, out: []f64) {
    let vt = 3.0f64 * (n1 * v1 + n2 * v2) / (n1 + n2) * (1.0f64 / n1 + 1.0f64 / n2)
    let z = (t - mu) / math.sqrt[f64](vt)
    var p = 1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false)
    if p == 0.0f64 { p = dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false) }
    out[0usize] = t
    out[1usize] = z
    out[2usize] = p
    out[3usize] = vt
    out[4usize] = v1
    out[5usize] = mu
}

// kde.test(x1, x2, H1, H2) in two dimensions
fn kde_test2(a: *mem.Arena, x1: []const f64, n1: usize, x2: []const f64, n2: usize, h1: []const f64, h2: []const f64, out: []f64) {
    let k0 = 1.0f64 / (2.0f64 * 3.141592653589793f64)
    let psi1 = qcross2(x1, n1, x1, n1, h1)
    let psi2 = qcross2(x2, n2, x2, n2, h2)
    let psi12 = qcross2(x1, n1, x2, n2, h1)
    let psi21 = qcross2(x2, n2, x1, n1, h2)
    let d1 = h1[0usize] * h1[3usize] - h1[1usize] * h1[2usize]
    let d2 = h2[0usize] * h2[3usize] - h2[1usize] * h2[2usize]
    let mu = (1.0f64 / f64(n1) / math.sqrt[f64](d1) + 1.0f64 / f64(n2) / math.sqrt[f64](d2)) * k0
    let v1 = var_fhat2(a, x1, n1)
    let v2 = var_fhat2(a, x2, n2)
    test_parts(psi1 + psi2 - (psi12 + psi21), mu, f64(n1), f64(n2), v1, v2, out)
}

// kde.test(x1, x2, h1 =, h2 =, var.fhat1 =, var.fhat2 =) in one dimension
fn kde_test1(x1: []const f64, x2: []const f64, h1: f64, h2: f64, v1: f64, v2: f64, out: []f64) {
    let n1 = f64(x1.len)
    let n2 = f64(x2.len)
    let psi1 = q1(x1, x1, h1)
    let psi2 = q1(x2, x2, h2)
    let psi12 = q1(x1, x2, h1)
    let psi21 = q1(x2, x1, h2)
    let mu = (1.0f64 / (n1 * h1) + 1.0f64 / (n2 * h2)) * 0.3989422804014327f64
    test_parts(psi1 + psi2 - (psi12 + psi21), mu, n1, n2, v1, v2, out)
}

// hpi.kfe(x, nstage = 2, binned = FALSE): the bias-annihilating plug-in bandwidth of the kernel functional estimator
fn hpi_kfe1(x: []const f64) -> f64 {
    let n = f64(x.len)
    let sd = math.sqrt[f64](k1.var_of(x))
    let kr0 = 0.3989422804014327f64
    let psi4 = k1.psins_1d(4usize, sd)
    let g2 = math.pow[f64](2.0f64 * kr0 / (psi4 * n), 1.0f64 / 5.0f64)
    let psi2 = k1.kfe_1d_direct(x, g2, 2usize, true)
    ret math.pow[f64](kr0 / (0.0f64 - psi2 * n), 1.0f64 / 3.0f64)
}

// var.fhat of kde.test.1d: the first-derivative kdde(x, h = hns(x, deriv.order = 1)) (binned on 401 points over the data and 4.7 bandwidths, the default in one
// dimension) interpolated at the mean, squared and scaled by the variance
fn var_fhat1(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let nf = f64(n)
    let sd = math.sqrt[f64](k1.var_of(x))
    let h = math.pow[f64](4.0f64 / (nf * 5.0f64), 1.0f64 / 7.0f64) * sd
    let m = 401usize
    var lo = x[0usize]
    var hi = x[0usize]
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    lo = lo - 4.7f64 * h
    hi = hi + 4.7f64 * h
    let delta = (hi - lo) / f64(m - 1usize)
    let (counts, e1) = mem.alloc[f64](a, m)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < m {
        counts[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let pos = (x[i] - lo) / delta
        let fl = math.floor[f64](pos)
        let ix = usize(fl)
        counts[ix] += 1.0f64 - (pos - fl)
        counts[ix + 1usize] += pos - fl
        i += 1usize
    }
    var l = usize(math.ceil[f64](5.0f64 * h / delta))
    if l > m - 1usize { l = m - 1usize }
    let nn = 2usize * l - 1usize
    var rd = l
    if (l - 1usize) % 2usize == 0usize { rd = l - 1usize }
    let lp = rd + 1usize
    let (ke, e2) = mem.alloc[f64](a, nn)
    let (est, e3) = mem.alloc[f64](a, m)
    if e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < nn {
        ke[k] = k1.dnorm_deriv(delta * (f64(k) - f64(l - 1usize)), h, 1usize) / nf
        k += 1usize
    }
    var t = 1usize
    while t <= m {
        var s = 0.0f64
        var j = 1usize
        while j <= nn {
            let c = i64(nn + t + 1usize) - i64(j) - i64(lp)
            if c >= 1i64 && c <= i64(m) { s += ke[j - 1usize] * counts[usize(c) - 1usize] }
            j += 1usize
        }
        est[t - 1usize] = s
        t += 1usize
    }
    // predict.kdde: linear interpolation of the gridded derivative at the mean
    let pos = (mean - lo) / delta
    let fl = math.floor[f64](pos)
    let ix = usize(fl)
    let f = pos - fl
    let v = est[ix] * (1.0f64 - f) + est[ix + 1usize] * f
    ret v * v * sd * sd
}

// kde.test(x1, x2) in one dimension with every default (hpi.kfe bandwidths, the default var.fhat)
fn kde_test1_default(a: *mem.Arena, x1: []const f64, x2: []const f64, out: []f64, bw: []f64) {
    let h1 = hpi_kfe1(x1)
    let h2 = hpi_kfe1(x2)
    bw[0usize] = h1
    bw[1usize] = h2
    kde_test1(x1, x2, h1, h2, var_fhat1(a, x1), var_fhat1(a, x2), out)
}

// kde.test(x1, x2) in two dimensions with the Hpi.kfe bandwidths
fn kde_test2_default(a: *mem.Arena, x1: []const f64, n1: usize, x2: []const f64, n2: usize, out: []f64, bw: []f64) -> err {
    var h1: [16]f64 = zero
    var h2: [16]f64 = zero
    let e1 = kp.hpi_kfe(a, x1, n1, 2usize, 2usize, h1[0usize..16usize])
    if e1 != ok { ret e1 }
    let e2 = kp.hpi_kfe(a, x2, n2, 2usize, 2usize, h2[0usize..16usize])
    if e2 != ok { ret e2 }
    bw[0usize] = h1[0usize]
    bw[1usize] = h2[3usize]
    kde_test2(a, x1, n1, x2, n2, h1[0usize..4usize], h2[0usize..4usize], out)
    ret ok
}

fn q1(x: []const f64, y: []const f64, g: f64) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < y.len {
        var i = 0usize
        while i < x.len {
            let d = (x[i] - y[j]) / g
            s += math.exp[f64](0.0f64 - 0.5f64 * d * d)
            i += 1usize
        }
        j += 1usize
    }
    ret s / 2.5066282746310002f64 / g / (f64(x.len) * f64(y.len))
}
