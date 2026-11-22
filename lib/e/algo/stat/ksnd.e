// R ks in one to four dimensions with the bandwidth matrix H (d by d, row-major) given: Hns, the exact kernel density estimate at points, the
// gridded estimate kde.grid.1d / 2d / 3d / nd (a kernel summed over its 3.7-bandwidth box in two and three dimensions, over every point otherwise),
// the binned estimate kdde.binned (linear binning and the zero-padded convolution as a direct sum), predict.kde (d-linear interpolation) and
// contourLevels(kde, cont).
//
// Not here: weights other than one, positive and unit-interval support, grid types other than linear, derivative estimates above order 0.

use e.algo.stat.classint as ci
use e.algo.stat.ks2dkde as kk
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// symmetric eigen decomposition by cyclic Jacobi: vals[d] and the eigenvectors as the columns of vecs (row-major)
fn jacobi(m: []const f64, d: usize, vals: []f64, vecs: []f64) {
    var s: [16]f64 = zero
    var i = 0usize
    while i < d * d {
        s[i] = m[i]
        vecs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < d {
        vecs[i * d + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0usize
    var done = false
    while sweep < 80usize && !done {
        var off = 0.0f64
        var p = 0usize
        while p < d {
            var q = p + 1usize
            while q < d {
                off += s[p * d + q] * s[p * d + q]
                q += 1usize
            }
            p += 1usize
        }
        if off < 1.0e-300f64 {
            done = true
        } else {
            p = 0usize
            while p < d {
                var q = p + 1usize
                while q < d {
                    let apq = s[p * d + q]
                    if math.abs[f64](apq) > 1.0e-300f64 {
                        let theta = (s[q * d + q] - s[p * d + p]) / (2.0f64 * apq)
                        var sg = 1.0f64
                        if theta < 0.0f64 { sg = 0.0f64 - 1.0f64 }
                        let t = sg / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                        let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                        let sn = t * c
                        var k = 0usize
                        while k < d {
                            let akp = s[k * d + p]
                            let akq = s[k * d + q]
                            s[k * d + p] = c * akp - sn * akq
                            s[k * d + q] = sn * akp + c * akq
                            k += 1usize
                        }
                        k = 0usize
                        while k < d {
                            let apk = s[p * d + k]
                            let aqk = s[q * d + k]
                            s[p * d + k] = c * apk - sn * aqk
                            s[q * d + k] = sn * apk + c * aqk
                            let vkp = vecs[k * d + p]
                            let vkq = vecs[k * d + q]
                            vecs[k * d + p] = c * vkp - sn * vkq
                            vecs[k * d + q] = sn * vkp + c * vkq
                            k += 1usize
                        }
                    }
                    q += 1usize
                }
                p += 1usize
            }
        }
        sweep += 1usize
    }
    i = 0usize
    while i < d {
        vals[i] = s[i * d + i]
        i += 1usize
    }
}

// the diagonal of the symmetric square root of H and the largest eigenvalue
fn sqrt_diag(h: []const f64, d: usize, sd: []f64) -> f64 {
    var vals: [4]f64 = zero
    var vecs: [16]f64 = zero
    jacobi(h, d, vals[0usize..4usize], vecs[0usize..16usize])
    var lmax = vals[0usize]
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var k = 0usize
        while k < d {
            s += vecs[j * d + k] * vecs[j * d + k] * math.sqrt[f64](vals[k])
            k += 1usize
        }
        sd[j] = s
        if vals[j] > lmax { lmax = vals[j] }
        j += 1usize
    }
    ret lmax
}

// determinant and inverse of an SPD matrix by Gauss-Jordan
fn inv_det(m: []const f64, d: usize, inv: []f64) -> f64 {
    var w: [32]f64 = zero
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            w[i * 2usize * d + j] = m[i * d + j]
            j += 1usize
        }
        w[i * 2usize * d + d + i] = 1.0f64
        i += 1usize
    }
    var det = 1.0f64
    var c = 0usize
    while c < d {
        var p = c
        var r = c + 1usize
        while r < d {
            if math.abs[f64](w[r * 2usize * d + c]) > math.abs[f64](w[p * 2usize * d + c]) { p = r }
            r += 1usize
        }
        if p != c {
            var k = 0usize
            while k < 2usize * d {
                let t = w[c * 2usize * d + k]
                w[c * 2usize * d + k] = w[p * 2usize * d + k]
                w[p * 2usize * d + k] = t
                k += 1usize
            }
            det = 0.0f64 - det
        }
        let pv = w[c * 2usize * d + c]
        det = det * pv
        var k = 0usize
        while k < 2usize * d {
            w[c * 2usize * d + k] = w[c * 2usize * d + k] / pv
            k += 1usize
        }
        r = 0usize
        while r < d {
            if r != c {
                let f = w[r * 2usize * d + c]
                k = 0usize
                while k < 2usize * d {
                    w[r * 2usize * d + k] = w[r * 2usize * d + k] - f * w[c * 2usize * d + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            inv[i * d + j] = w[i * 2usize * d + d + j]
            j += 1usize
        }
        i += 1usize
    }
    ret det
}

// var(x): the sample covariance of the n by d matrix x
fn cov_nd(x: []const f64, n: usize, d: usize, o: []f64) {
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
    j = 0usize
    while j < d {
        var k = 0usize
        while k < d {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * d + j] - mu[j]) * (x[i * d + k] - mu[k])
                i += 1usize
            }
            o[j * d + k] = s / f64(n - 1usize)
            k += 1usize
        }
        j += 1usize
    }
}

// Hns(x, deriv.order = r)
fn hns(x: []const f64, n: usize, d: usize, r: usize, o: []f64) {
    cov_nd(x, n, d, o)
    let c = math.pow[f64](4.0f64 / (f64(n) * f64(d + 2usize * r + 2usize)), 2.0f64 / f64(d + 2usize * r + 4usize))
    var i = 0usize
    while i < d * d {
        o[i] = o[i] * c
        i += 1usize
    }
}

fn quad(hinv: []const f64, d: usize, z: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            s += z[i] * hinv[i * d + j] * z[j]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// the N(0, H) density constant (2 pi)^(-d/2) det^(-1/2)
fn norm_const(det: f64, d: usize) -> f64 {
    ret math.pow[f64](2.0f64 * 3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64) / math.sqrt[f64](det)
}

// kde(x, H, eval.points = p) at one point
fn kde_at(x: []const f64, n: usize, d: usize, hinv: []const f64, c: f64, p: []const f64) -> f64 {
    ret kde_at_w(x, n, d, hinv, c, p, 0usize)
}

// the multiplier of a kernel value for the second-derivative weights: 1 for wt 0; q - d for wt 1 (tr(H D2 kernel), q the Mahalanobis form);
// (H^-1 z)_1^2 - (H^-1)_11 for wt 2 (the first element of the Hessian of the kernel)
fn wt_factor(wt: usize, hinv: []const f64, d: usize, z: []const f64, q: f64) -> f64 {
    if wt == 1usize { ret q - f64(d) }
    // wt = 100 + j: element j of the gradient of the kernel, -(H^-1 z)_j
    if wt >= 100usize {
        let gj = wt - 100usize
        var u = 0.0f64
        var l = 0usize
        while l < d {
            u += hinv[gj * d + l] * z[l]
            l += 1usize
        }
        ret 0.0f64 - u
    }
    // wt = 10 + j * d + k: element (j, k) of the Hessian of the kernel, (H^-1 z)_j (H^-1 z)_k - (H^-1)_jk
    if wt >= 10usize {
        let rj = (wt - 10usize) / d
        let rk = (wt - 10usize) % d
        var uj = 0.0f64
        var uk = 0.0f64
        var l = 0usize
        while l < d {
            uj += hinv[rj * d + l] * z[l]
            uk += hinv[rk * d + l] * z[l]
            l += 1usize
        }
        ret uj * uk - hinv[rj * d + rk]
    }
    if wt == 2usize {
        var u = 0.0f64
        var k = 0usize
        while k < d {
            u += hinv[k] * z[k]
            k += 1usize
        }
        ret u * u - hinv[0usize]
    }
    ret 1.0f64
}

fn kde_at_w(x: []const f64, n: usize, d: usize, hinv: []const f64, c: f64, p: []const f64, wt: usize) -> f64 {
    var z: [4]f64 = zero
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            z[j] = p[j] - x[i * d + j]
            j += 1usize
        }
        let q = quad(hinv, d, z[0usize..4usize])
        var v = math.exp[f64](0.0f64 - 0.5f64 * q)
        if wt != 0usize { v = v * wt_factor(wt, hinv, d, z[0usize..4usize], q) }
        s += v
        i += 1usize
    }
    ret c * s / f64(n)
}

fn pow_usize(b: usize, e: usize) -> usize {
    var r = 1usize
    var i = 0usize
    while i < e {
        r = r * b
        i += 1usize
    }
    ret r
}

// the grid for dimension j: gp[j * m ..] = seq(lo, hi, length = m)
fn make_grid(x: []const f64, n: usize, d: usize, pad: []const f64, m: usize, gp: []f64) {
    var j = 0usize
    while j < d {
        var lo = x[j]
        var hi = x[j]
        var i = 1usize
        while i < n {
            if x[i * d + j] < lo { lo = x[i * d + j] }
            if x[i * d + j] > hi { hi = x[i * d + j] }
            i += 1usize
        }
        kk.seq_len_out(lo - pad[j], hi + pad[j], m, gp[j * m..j * m + m])
        j += 1usize
    }
}

// kde.grid.1d / 2d / 3d / nd: grid (m^d cells, first variable fastest) and the grid points gp (d rows of m)
fn kde_grid(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, gp: []f64, grid: []f64) {
    var sd: [4]f64 = zero
    let _l = sqrt_diag(h, d, sd[0usize..4usize])
    var tol: [4]f64 = zero
    var j = 0usize
    while j < d {
        tol[j] = 3.7f64 * sd[j]
        j += 1usize
    }
    make_grid(x, n, d, tol[0usize..4usize], m, gp)
    kde_grid_on(a, x, n, d, h, m, gp, grid, 0usize)
}

// the same estimate on the grid already in gp (xmin and xmax given); wt as in kde_at_w
fn kde_grid_on(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, gp: []f64, grid: []f64, wt: usize) {
    var sd: [4]f64 = zero
    let _l = sqrt_diag(h, d, sd[0usize..4usize])
    var tol: [4]f64 = zero
    var j = 0usize
    while j < d {
        tol[j] = 3.7f64 * sd[j]
        j += 1usize
    }
    let total = pow_usize(m, d)
    var hinv: [16]f64 = zero
    let det = inv_det(h, d, hinv[0usize..16usize])
    let c = norm_const(det, d)
    var i = 0usize
    while i < total {
        grid[i] = 0.0f64
        i += 1usize
    }
    if d == 2usize || d == 3usize {
        var z: [4]f64 = zero
        i = 0usize
        while i < n {
            var lo: [4]usize = zero
            var hi: [4]usize = zero
            var cnt: [4]usize = zero
            j = 0usize
            while j < d {
                let xv = x[i * d + j]
                var l = kk.count_le(gp[j * m..j * m + m], xv - tol[j])
                if l == 0usize { l = 1usize }
                lo[j] = l
                hi[j] = kk.count_le(gp[j * m..j * m + m], xv + tol[j])
                cnt[j] = l
                j += 1usize
            }
            var live = true
            j = 0usize
            while j < d {
                if hi[j] < lo[j] { live = false }
                j += 1usize
            }
            while live {
                var cell = 0usize
                var stride = 1usize
                j = 0usize
                while j < d {
                    z[j] = gp[j * m + cnt[j] - 1usize] - x[i * d + j]
                    cell += (cnt[j] - 1usize) * stride
                    stride = stride * m
                    j += 1usize
                }
                let q = quad(hinv[0usize..16usize], d, z[0usize..4usize])
                var v = c * math.exp[f64](0.0f64 - 0.5f64 * q)
                if wt != 0usize { v = v * wt_factor(wt, hinv[0usize..16usize], d, z[0usize..4usize], q) }
                grid[cell] += v
                j = 0usize
                var carry = true
                while carry && j < d {
                    cnt[j] += 1usize
                    if cnt[j] > hi[j] {
                        cnt[j] = lo[j]
                        j += 1usize
                    } else {
                        carry = false
                    }
                }
                if carry { live = false }
            }
            i += 1usize
        }
        i = 0usize
        while i < total {
            grid[i] = grid[i] / f64(n)
            i += 1usize
        }
    } else {
        var p: [4]f64 = zero
        i = 0usize
        while i < total {
            var r = i
            j = 0usize
            while j < d {
                p[j] = gp[j * m + r % m]
                r = r / m
                j += 1usize
            }
            grid[i] = kde_at_w(x, n, d, hinv[0usize..16usize], c, p[0usize..4usize], wt)
            i += 1usize
        }
    }
}

// kdde.binned at r = 0: bin counts (linear binning on m^d cells over the data and 3.7 bandwidths), then the kernel summed over the cells within L
fn kde_binned(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, gp: []f64, grid: []f64) -> err {
    var pad: [4]f64 = zero
    var j = 0usize
    while j < d {
        pad[j] = 3.7f64 * math.sqrt[f64](h[j * d + j])
        j += 1usize
    }
    make_grid(x, n, d, pad[0usize..4usize], m, gp)
    ret kde_binned_on(a, x, n, d, h, m, gp, grid)
}

// the same on the grid already in gp (xmin and xmax given; every observation inside)
fn kde_binned_on(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, gp: []f64, grid: []f64) -> err {
    var sd: [4]f64 = zero
    let lmax = sqrt_diag(h, d, sd[0usize..4usize])
    var dg: [4]f64 = zero
    var j = 0usize
    let total = pow_usize(m, d)
    let (counts, e1) = mem.alloc[f64](a, total)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < total {
        counts[i] = 0.0f64
        grid[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < d {
        dg[j] = (gp[j * m + m - 1usize] - gp[j * m]) / f64(m - 1usize)
        j += 1usize
    }
    i = 0usize
    while i < n {
        var ix: [4]usize = zero
        var fx: [4]f64 = zero
        j = 0usize
        while j < d {
            let pos = (x[i * d + j] - gp[j * m]) / dg[j]
            let fl = math.floor[f64](pos)
            ix[j] = usize(fl)
            fx[j] = pos - fl
            j += 1usize
        }
        var corner = 0usize
        while corner < pow_usize(2usize, d) {
            var wgt = 1.0f64
            var cell = 0usize
            var stride = 1usize
            j = 0usize
            while j < d {
                let bit = (corner / pow_usize(2usize, j)) % 2usize
                if bit == 1usize {
                    wgt = wgt * fx[j]
                } else {
                    wgt = wgt * (1.0f64 - fx[j])
                }
                cell += (ix[j] + bit) * stride
                stride = stride * m
                j += 1usize
            }
            counts[cell] += wgt
            corner += 1usize
        }
        i += 1usize
    }
    var hinv: [16]f64 = zero
    let det = inv_det(h, d, hinv[0usize..16usize])
    let c = norm_const(det, d)
    var ll: [4]usize = zero
    var nn: [4]usize = zero
    var ktot = 1usize
    j = 0usize
    while j < d {
        var l = usize(math.ceil[f64](4.0f64 * math.sqrt[f64](lmax) / dg[j]))
        if l > m - 1usize { l = m - 1usize }
        ll[j] = l
        nn[j] = 2usize * l - 1usize
        ktot = ktot * nn[j]
        j += 1usize
    }
    let (kern, e2) = mem.alloc[f64](a, ktot)
    if e2 != ok { ret e2 }
    var z: [4]f64 = zero
    i = 0usize
    while i < ktot {
        var r = i
        j = 0usize
        while j < d {
            let o = r % nn[j]
            r = r / nn[j]
            z[j] = dg[j] * (f64(o) - f64(ll[j] - 1usize))
            j += 1usize
        }
        kern[i] = c * math.exp[f64](0.0f64 - 0.5f64 * quad(hinv[0usize..16usize], d, z[0usize..4usize])) / f64(n)
        i += 1usize
    }
    var cell = 0usize
    while cell < total {
        let cv = counts[cell]
        if cv != 0.0f64 {
            var mi: [4]usize = zero
            var r = cell
            j = 0usize
            while j < d {
                mi[j] = r % m
                r = r / m
                j += 1usize
            }
            var k = 0usize
            while k < ktot {
                var rk = k
                var tcell = 0usize
                var stride = 1usize
                var inside = true
                j = 0usize
                while j < d {
                    let o = rk % nn[j]
                    rk = rk / nn[j]
                    var tgt = i64(mi[j]) + i64(o) - i64(ll[j] - 1usize)
                    // symconv.nd centres the kernel at round(N / 2) + 1, and R rounds half to even: an even L shifts the result one cell
                    if ll[j] % 2usize == 0usize { tgt += 1i64 }
                    if tgt < 0i64 || tgt >= i64(m) { inside = false }
                    if inside { tcell += usize(tgt) * stride }
                    stride = stride * m
                    j += 1usize
                }
                if inside { grid[tcell] += cv * kern[k] }
                k += 1usize
            }
        }
        cell += 1usize
    }
    ret ok
}

// predict.kde: d-linear interpolation of the gridded estimate at p (zero outside the grid)
fn interp_nd(gp: []const f64, m: usize, d: usize, grid: []const f64, p: []const f64) -> f64 {
    var ix: [4]usize = zero
    var fx: [4]f64 = zero
    var j = 0usize
    while j < d {
        let dl = (gp[j * m + m - 1usize] - gp[j * m]) / f64(m - 1usize)
        let pos = (p[j] - gp[j * m]) / dl
        let fl = math.floor[f64](pos)
        if fl < 0.0f64 || fl > f64(m - 2usize) { ret 0.0f64 }
        ix[j] = usize(fl)
        fx[j] = pos - fl
        j += 1usize
    }
    var s = 0.0f64
    var corner = 0usize
    while corner < pow_usize(2usize, d) {
        var wgt = 1.0f64
        var cell = 0usize
        var stride = 1usize
        j = 0usize
        while j < d {
            let bit = (corner / pow_usize(2usize, j)) % 2usize
            if bit == 1usize {
                wgt = wgt * fx[j]
            } else {
                wgt = wgt * (1.0f64 - fx[j])
            }
            cell += (ix[j] + bit) * stride
            stride = stride * m
            j += 1usize
        }
        s += grid[cell] * wgt
        corner += 1usize
    }
    ret s
}

// contourLevels(kde, cont = c, approx = TRUE): the (100 - c) / 100 type 7 quantile of the gridded estimate at the data; binned selects kdde.binned
fn kde_contour(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, binned: bool, cont: f64) -> f64 {
    let total = pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (grid, e2) = mem.alloc[f64](a, total)
    let (dv, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret nan() }
    if binned {
        if kde_binned(a, x, n, d, h, m, gp, grid) != ok { ret nan() }
    } else {
        kde_grid(a, x, n, d, h, m, gp, grid)
    }
    var i = 0usize
    while i < n {
        dv[i] = interp_nd(gp, m, d, grid, x[i * d..i * d + d])
        i += 1usize
    }
    let (s, se) = ci.sorted_copy(a, dv)
    if se != ok { ret nan() }
    ret ci.quantile7(s, (100.0f64 - cont) / 100.0f64)
}

// ksupp(kde, cont = c, convex.hull = FALSE): out[0] the number of grid cells with an estimate above the contour level, out[1 + j] the sum of their coordinate j
fn kde_supp(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, binned: bool, cont: f64, out: []f64) -> err {
    let total = pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (grid, e2) = mem.alloc[f64](a, total)
    let (dv, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    if binned {
        let be = kde_binned(a, x, n, d, h, m, gp, grid)
        if be != ok { ret be }
    } else {
        kde_grid(a, x, n, d, h, m, gp, grid)
    }
    var i = 0usize
    while i < n {
        dv[i] = interp_nd(gp, m, d, grid, x[i * d..i * d + d])
        i += 1usize
    }
    let (s, se) = ci.sorted_copy(a, dv)
    if se != ok { ret se }
    let level = ci.quantile7(s, (100.0f64 - cont) / 100.0f64)
    var j = 0usize
    while j <= d {
        out[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < total {
        if grid[i] > level {
            out[0usize] += 1.0f64
            var r = i
            j = 0usize
            while j < d {
                out[1usize + j] += gp[j * m + r % m]
                r = r / m
                j += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}
