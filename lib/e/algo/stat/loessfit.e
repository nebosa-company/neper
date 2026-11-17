// R stats::loess for one numeric predictor (family gaussian, surface "interpolate"): the k-d tree of loessf.f (ehg126, ehg124: cells cut at the median until a cell holds at most
// floor(n span cell) points), the local polynomial of degree 0 to 2 fitted at every vertex of the tree by tricube-weighted least squares over the nf = floor(n span) nearest points
// (value and slope), and the cubic Hermite interpolation of ehg128 between vertices. The fitted values at the data are what loess()$fitted answers; span from enp.target is
// 1.2 tau / enp.target with tau = degree + 1 choose... (1, 2, 3 for degree 0, 1, 2).
//
// Not here: more than one predictor, robustness iterations (family "symmetric"), the hat-matrix statistics, the pseudoinverse R switches to for a singular local fit (a plain
// least-squares solution is used), weights other than the supplied ones.

use e.math
use e.mem
use e.algo.stat.gbmfit as gb

// local fit at q: the value and the slope of the weighted polynomial there
fn local_fit(a: *mem.Arena, x: []const f64, y: []const f64, rw: []const f64, n: usize, nf: usize, span: f64, degree: usize, q: f64, out: []f64) -> err {
    var bad = 0usize
    let dist = gb.af(a, n, &bad)
    let idx = gb.au(a, n, &bad)
    let tmp = gb.au(a, n, &bad)
    let kk = degree + 1usize
    let b = gb.af(a, nf * kk, &bad)
    let eta = gb.af(a, nf, &bad)
    let w = gb.af(a, nf, &bad)
    let qm = gb.af(a, nf * kk, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var i = 0usize
    while i < n {
        dist[i] = (x[i] - q) * (x[i] - q)
        idx[i] = i
        i += 1usize
    }
    gb.msort(dist, idx, tmp, n)
    var mf = 1.0f64
    if span > 1.0f64 { mf = span }
    let rho = dist[idx[nf - 1usize]] * mf
    i = 0usize
    while i < nf {
        let r = math.sqrt[f64](dist[idx[i]] / rho)
        let c = 1.0f64 - r * r * r
        w[i] = math.sqrt[f64](rw[idx[i]] * c * c * c)
        i += 1usize
    }
    i = 0usize
    while i < nf {
        let dx = x[idx[i]] - q
        var p = 1.0f64
        var j = 0usize
        while j < kk {
            b[j * nf + i] = w[i] * p
            p = p * dx
            j += 1usize
        }
        eta[i] = w[i] * y[idx[i]]
        i += 1usize
    }
    // column-scaled modified Gram-Schmidt twice, then back substitution
    let cn = gb.af(a, kk, &bad)
    let rm = gb.af(a, kk * kk, &bad)
    let qty = gb.af(a, kk, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var j = 0usize
    while j < kk {
        var s = 0.0f64
        i = 0usize
        while i < nf {
            s += b[j * nf + i] * b[j * nf + i]
            i += 1usize
        }
        s = math.sqrt[f64](s)
        if !(s > 0.0f64) { s = 1.0f64 }
        cn[j] = s
        i = 0usize
        while i < nf {
            b[j * nf + i] = b[j * nf + i] / s
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < kk {
        i = 0usize
        while i < nf {
            qm[j * nf + i] = b[j * nf + i]
            i += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            var l = 0usize
            while l < j {
                var d = 0.0f64
                i = 0usize
                while i < nf {
                    d += qm[l * nf + i] * qm[j * nf + i]
                    i += 1usize
                }
                rm[l * kk + j] += d
                i = 0usize
                while i < nf {
                    qm[j * nf + i] -= d * qm[l * nf + i]
                    i += 1usize
                }
                l += 1usize
            }
            pass += 1usize
        }
        var nr = 0.0f64
        i = 0usize
        while i < nf {
            nr += qm[j * nf + i] * qm[j * nf + i]
            i += 1usize
        }
        nr = math.sqrt[f64](nr)
        rm[j * kk + j] = nr
        i = 0usize
        while i < nf {
            if nr > 0.0f64 { qm[j * nf + i] = qm[j * nf + i] / nr }
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < kk {
        var d = 0.0f64
        i = 0usize
        while i < nf {
            d += qm[j * nf + i] * eta[i]
            i += 1usize
        }
        qty[j] = d
        j += 1usize
    }
    // R beta = Q' eta, beta in the scaled columns
    var jj = kk
    while jj > 0usize {
        jj -= 1usize
        var s = qty[jj]
        var l = jj + 1usize
        while l < kk {
            s -= rm[jj * kk + l] * qty[l]
            l += 1usize
        }
        if rm[jj * kk + jj] > 0.0f64 {
            qty[jj] = s / rm[jj * kk + jj]
        } else {
            qty[jj] = 0.0f64
        }
    }
    out[0usize] = qty[0usize] / cn[0usize]
    out[1usize] = 0.0f64
    if kk > 1usize { out[1usize] = qty[1usize] / cn[1usize] }
    ret ok
}

// the cuts of the k-d tree over the sorted values xs[0..n]: appended to cuts (count in nc)
fn kd_cuts(xs: []const f64, n: usize, fc: usize, lo_v: f64, hi_v: f64, cuts: []f64, stl: []usize, stu: []usize, stlo: []f64, sthi: []f64) -> usize {
    var nc = 0usize
    var head = 0usize
    var tail = 1usize
    var ncell = 1usize
    var nvert = 2usize
    var ncmax = n
    if ncmax < 200usize { ncmax = 200usize }
    stl[0usize] = 1usize
    stu[0usize] = n
    stlo[0usize] = lo_v
    sthi[0usize] = hi_v
    while head < tail {
        let l = stl[head]
        let u = stu[head]
        let vlo = stlo[head]
        let vhi = sthi[head]
        head += 1usize
        if u - l + 1usize <= fc { continue }
        if ncmax < ncell + 2usize || ncmax < nvert + 1usize { continue }
        var m = (l + u) / 2usize
        var offset = 0i64
        while true {
            let mo = i64(m) + offset
            if mo >= i64(u) || mo < i64(l) { break }
            if xs[usize(mo) - 1usize] == xs[usize(mo)] {
                offset = 0i64 - offset
                if offset >= 0i64 { offset += 1i64 }
            } else {
                m = usize(mo)
                break
            }
        }
        let xm = xs[m - 1usize]
        if vlo == xm || vhi == xm { continue }
        cuts[nc] = xm
        nc += 1usize
        ncell += 2usize
        nvert += 1usize
        stl[tail] = l
        stu[tail] = m
        stlo[tail] = vlo
        sthi[tail] = xm
        tail += 1usize
        stl[tail] = m + 1usize
        stu[tail] = u
        stlo[tail] = xm
        sthi[tail] = vhi
        tail += 1usize
    }
    ret nc
}

// loess(y ~ x, span, degree)$fitted for n rows (cell = 0.2 as the default control)
fn loess_fitted(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, span: f64, degree: usize, fitted: []f64) -> err {
    var bad = 0usize
    let w = gb.af(a, n, &bad)
    let idx = gb.au(a, n, &bad)
    let tmp = gb.au(a, n, &bad)
    let xs = gb.af(a, n, &bad)
    let cuts = gb.af(a, n + 2usize, &bad)
    let stl = gb.au(a, 2usize * n + 8usize, &bad)
    let stu = gb.au(a, 2usize * n + 8usize, &bad)
    let stlo = gb.af(a, 2usize * n + 8usize, &bad)
    let sthi = gb.af(a, 2usize * n + 8usize, &bad)
    let vv = gb.af(a, n + 4usize, &bad)
    let g0 = gb.af(a, n + 4usize, &bad)
    let g1 = gb.af(a, n + 4usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        idx[i] = i
        i += 1usize
    }
    gb.msort(x, idx, tmp, n)
    i = 0usize
    while i < n {
        xs[i] = x[idx[i]]
        i += 1usize
    }
    var alpha = xs[0usize]
    var beta = xs[n - 1usize]
    var mx = math.abs[f64](alpha)
    if math.abs[f64](beta) > mx { mx = math.abs[f64](beta) }
    var spread = beta - alpha
    let floor_w = 1.0e-10f64 * mx + 1.0e-30f64
    if floor_w > spread { spread = floor_w }
    let mu = 0.005f64 * spread
    alpha = alpha - mu
    beta = beta + mu
    let nf0 = math.floor[f64](f64(n) * span + 1.0e-5f64)
    var nf = usize(nf0)
    if nf > n { nf = n }
    if nf == 0usize { ret gb.NoMemory }
    let fc = usize(math.floor[f64](f64(n) * span * 0.2f64))
    let nc = kd_cuts(xs, n, fc, alpha, beta, cuts, stl, stu, stlo, sthi)
    // the cuts in order make the vertices, the bounds at either end
    var c = 0usize
    while c < nc {
        idx[c] = c
        c += 1usize
    }
    gb.msort(cuts, idx, tmp, nc)
    vv[0usize] = alpha
    c = 0usize
    while c < nc {
        vv[c + 1usize] = cuts[idx[c]]
        c += 1usize
    }
    vv[nc + 1usize] = beta
    let nv = nc + 2usize
    let o2 = gb.af(a, 2usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var v = 0usize
    while v < nv {
        let e = local_fit(a, x, y, w, n, nf, span, degree, vv[v], o2)
        if e != ok { ret e }
        g0[v] = o2[0usize]
        g1[v] = o2[1usize]
        v += 1usize
    }
    i = 0usize
    while i < n {
        // the cell holding x[i]: the cuts it lies strictly right of
        var cell = 0usize
        while cell + 1usize < nv - 1usize && x[i] > vv[cell + 1usize] { cell += 1usize }
        let wd = vv[cell + 1usize] - vv[cell]
        let h = (x[i] - vv[cell]) / wd
        let phi0 = (1.0f64 - h) * (1.0f64 - h) * (1.0f64 + 2.0f64 * h)
        let phi1 = h * h * (3.0f64 - 2.0f64 * h)
        let psi0 = h * (1.0f64 - h) * (1.0f64 - h)
        let psi1 = h * h * (h - 1.0f64)
        fitted[i] = phi0 * g0[cell] + phi1 * g0[cell + 1usize] + (psi0 * g1[cell] + psi1 * g1[cell + 1usize]) * wd
        i += 1usize
    }
    ret ok
}

// span of loess(enp.target = enp) with one predictor: 1.2 tau / enp
fn span_for_enp(enp: f64, degree: usize) -> f64 {
    var tau = 1.0f64
    if degree == 1usize { tau = 2.0f64 }
    if degree >= 2usize { tau = 3.0f64 }
    ret 1.2f64 * tau / enp
}
