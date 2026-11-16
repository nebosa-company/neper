// R AlgDesign's optFederov core (FederovOpt.c, Wheeler): the exchange algorithm for D, A and I optimal exact designs (the Fedorov
// exchange of the worst design point for the best candidate, on the Cholesky-like triangular reduction T of the design by Givens
// rotations), nullification and random starts, augmentation, and the approximate theory design. The model matrix X is supplied
// row-major (N by k); the formula expansion of the R wrapper is the caller's.
//
// Not here: optBlock, optMonteCarlo, the balanced incomplete block search.

use e.algo.rand.r as rng
use e.math
use e.mem

type Dt = struct { d: f64, i: usize, o: usize }

type Fed = struct {
    nn: usize,
    k: usize,
    x: []f64,
    u: []f64,
    v: []f64,
    b: []f64,
    bu: []f64,
    t: []f64,
    ti: []f64,
    tip: []f64,
    w: []f64,
    maxmin: []f64,
    vec: []f64,
    d: []Dt,
    flag: []i64,
    ttrows: []i64,
    trows: []i64,
    approx: bool,
    klimit: i64,
    llimit: i64,
}

// the result of one optimisation: D, A, I, G, the iteration count, the error code, the design rows (0-based) and proportions
type Res = struct { dd: f64, aa: f64, ii: f64, gg: f64, iter: i64, errcode: i64, rows: []i64, proportions: []f64 }

fn imat(r: usize, c: usize, nc: usize) -> usize { ret c + (r * (2usize * nc - r - 1usize)) / 2usize }

fn fabs_(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// Rotates the row `vec` into the triangular T (weight -1 removes it); tvec is scratch
fn rotate(vec: []const f64, tvec: []f64, m: []f64, nterms: usize, ncols: usize, weight0: f64, n: f64) {
    var weight = weight0
    let dn = math.sqrt[f64](n)
    var i = 0usize
    while i < ncols {
        tvec[i] = vec[i] / dn
        i += 1usize
    }
    i = 0usize
    while i < nterms {
        let x = tvec[i]
        if x == 0.0f64 {
            i += 1usize
            continue
        }
        var kidx = imat(i, i, ncols)
        let d = m[kidx]
        let dp = d + weight * x * x
        if fabs_(dp) < 1.0e-50f64 {
            i += 1usize
            continue
        }
        m[kidx] = dp
        let c = d / dp
        let s = weight * x / dp
        var skip = false
        if d == 0.0f64 {
            skip = true
            weight = 0.0f64
        } else {
            weight = weight * c
        }
        kidx += 1usize
        var j = i + 1usize
        while j < ncols {
            let r = m[kidx]
            m[kidx] = s * tvec[j] + c * r
            tvec[j] = tvec[j] - x * r
            j += 1usize
            kidx += 1usize
        }
        if skip { break }
        i += 1usize
    }
}

fn backsolve_t(m: []f64, nc: usize, scaled: bool) {
    if scaled {
        var col = nc - 1usize
        while col > 0usize {
            m[imat(col, col, nc)] = 1.0f64 / m[imat(col, col, nc)]
            var j = col
            while j > 0usize {
                j -= 1usize
                let l = imat(j, col, nc)
                var kk = imat(j, j + 1usize, nc)
                m[l] = m[l] * (0.0f64 - m[imat(col, col, nc)])
                var i = 1usize
                while i < col - j {
                    m[l] = m[l] - m[imat(i + j, col, nc)] * m[kk]
                    kk += 1usize
                    i += 1usize
                }
                m[l] = m[l] / m[imat(j, j, nc)]
            }
            col -= 1usize
        }
        m[0usize] = 1.0f64 / m[0usize]
    } else {
        var col = nc - 1usize
        while col > 0usize {
            var j = col
            while j > 0usize {
                j -= 1usize
                let l = imat(j, col, nc)
                var kk = imat(j, j + 1usize, nc)
                m[l] = m[l] * (0.0f64 - 1.0f64)
                var i = 1usize
                while i < col - j {
                    m[l] = m[l] - m[imat(i + j, col, nc)] * m[kk]
                    kk += 1usize
                    i += 1usize
                }
            }
            col -= 1usize
        }
        var i = 0usize
        while i < nc {
            m[imat(i, i, nc)] = 1.0f64 / m[imat(i, i, nc)]
            i += 1usize
        }
    }
}

fn get_range(mx: []f64, mn: []f64, px: []const f64, k: usize) {
    var i = 0usize
    while i < k {
        if px[i] > mx[i] { mx[i] = px[i] }
        if px[i] < mn[i] { mn[i] = px[i] }
        i += 1usize
    }
}

// reduceDesign: the rows (design indices) of X reduced to T; returns the log determinant, singular set when a pivot is too small
fn reduce_design(f: *Fed, rows: []const i64, nrows: usize, scale: bool) -> (f64, bool) {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var i = 0usize
    while i < k {
        f.maxmin[i] = 0.0f64 - 1.0e16f64
        f.maxmin[k + i] = 1.0e16f64
        i += 1usize
    }
    i = 0usize
    while i < kk {
        f.t[i] = 0.0f64
        i += 1usize
    }
    var norm = 1.0f64
    if scale { norm = f64(nrows) }
    i = 0usize
    while i < nrows {
        let px = f.x[usize(rows[i]) * k..usize(rows[i]) * k + k]
        get_range(f.maxmin[0usize..k], f.maxmin[k..2usize * k], px, k)
        rotate(px, f.vec, f.t, k, k, 1.0f64, norm)
        i += 1usize
    }
    var nrm = 2.0f64
    if scale { nrm = 2.0f64 * math.sqrt[f64](f64(nrows)) }
    var logdet = 0.0f64
    i = 0usize
    while i < k {
        let r = (f.maxmin[i] + f.maxmin[k + i]) / nrm
        let t = f.t[imat(i, i, k)]
        if t <= 0.0f64 || t < r * 1.0e-16f64 { ret (0.0f64, true) }
        logdet += math.log[f64](t)
        i += 1usize
    }
    ret (logdet, false)
}

fn get_next_row(f: *Fed) -> (f64, i64) {
    let k = f.k
    var scale = 0.0f64 - 1.0f64
    var newrow = 0i64 - 1i64
    var i = 0usize
    while i < f.nn {
        if f.flag[i] == 0i64 {
            var ssq = 0.0f64
            var j = 0usize
            while j < k {
                let vv = f.v[i * k + j]
                ssq += vv * vv
                j += 1usize
            }
            if ssq > scale {
                newrow = i64(i)
                scale = ssq
            }
        }
        i += 1usize
    }
    ret (scale, newrow)
}

// orthogonalise V against the row `vec` (a copy of a row of V) with squared length scale
fn orthog(f: *Fed, vec: []const f64, scale: f64) {
    let k = f.k
    var i = 0usize
    while i < f.nn {
        if f.flag[i] == 0i64 {
            var cross = 0.0f64
            var j = 0usize
            while j < k {
                cross += f.v[i * k + j] * vec[j]
                j += 1usize
            }
            let beta = cross / scale
            j = 0usize
            while j < k {
                f.v[i * k + j] = f.v[i * k + j] - beta * vec[j]
                j += 1usize
            }
        }
        i += 1usize
    }
}

fn nullify(f: *Fed, augment: usize, rows: []i64, tmp: []f64) -> bool {
    let k = f.k
    var i = 0usize
    while i < f.nn * k {
        f.v[i] = f.x[i]
        i += 1usize
    }
    if augment > 0usize {
        i = 0usize
        while i < augment {
            var scale = 0.0f64
            var j = 0usize
            while j < k {
                tmp[j] = f.v[usize(rows[i]) * k + j]
                scale += tmp[j] * tmp[j]
                j += 1usize
            }
            orthog(f, tmp, scale)
            i += 1usize
        }
    }
    var tolerance = 1.0e-8f64
    i = 0usize
    while i < k - augment {
        let (scale, newrow) = get_next_row(f)
        if scale < tolerance || newrow == 0i64 - 1i64 { ret false }
        if i == 0usize { tolerance = scale * 1.0e-8f64 }
        rows[i + augment] = newrow
        f.flag[usize(newrow)] = 1i64
        if i != k - 1usize {
            var j = 0usize
            while j < k {
                tmp[j] = f.v[usize(newrow) * k + j]
                j += 1usize
            }
            orthog(f, tmp, scale)
        }
        i += 1usize
    }
    ret true
}

// Ti (the inverse of the scaled T) and Tip (its transpose, packed by rows of Ti'); the log determinant and singular flag
fn make_ti_tip(f: *Fed, norm: f64) -> (f64, bool) {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var singular = false
    var logdet = 0.0f64
    var i = 0usize
    while i < kk {
        f.ti[i] = f.t[i]
        i += 1usize
    }
    var pt = 0usize
    i = 0usize
    while i < k {
        var r = f.maxmin[i] - f.maxmin[k + i]
        r = 1.0e-16f64 * r * r / norm
        if f.ti[pt] > r { logdet += math.log[f64](f.ti[pt]) } else { singular = true }
        let d = math.sqrt[f64](f.ti[pt])
        f.ti[pt] = d
        pt += 1usize
        var j = i + 1usize
        while j < k {
            f.ti[pt] = f.ti[pt] * d
            pt += 1usize
            j += 1usize
        }
        i += 1usize
    }
    backsolve_t(f.ti, k, true)
    var g = 0usize
    var jj = 0usize
    while jj < k {
        var ii = 0usize
        while ii <= jj {
            f.tip[g] = f.ti[imat(ii, jj, k)]
            g += 1usize
            ii += 1usize
        }
        jj += 1usize
    }
    ret (logdet, singular)
}

// returns the criterion value; acrit and icrit through the Fed scratch fields (acrit_ and icrit_ in the result tuple)
fn evaluate_criteria(f: *Fed, criterion: i64, evaluate_i: bool, logdet: f64) -> (f64, f64, f64) {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var t = 0.0f64
    var i = 0usize
    while i < kk {
        t += f.ti[i] * f.ti[i]
        i += 1usize
    }
    let acrit = t / f64(k)
    var icrit = 0.0f64
    if criterion == 2i64 || evaluate_i {
        i = 0usize
        while i < k {
            var q = 0usize
            while q < kk {
                f.w[q] = 0.0f64
                q += 1usize
            }
            var pt0 = (i * (i + 1usize)) / 2usize
            var pt = pt0 + i
            var j = i
            while j < k {
                var pw = 0usize
                var g = 0usize
                while g <= j {
                    f.w[pw] += f.tip[pt0] * f.tip[pt]
                    pw += 1usize
                    pt0 += 1usize
                    g += 1usize
                }
                pt = pt0 + i
                j += 1usize
            }
            var tt = 0.0f64
            j = 0usize
            while j < i {
                tt += f.b[imat(j, i, k)] * f.w[j]
                j += 1usize
            }
            var pb = imat(i, i, k)
            j = i
            while j < k {
                tt += f.b[pb] * f.w[j]
                pb += 1usize
                j += 1usize
            }
            icrit += tt
            i += 1usize
        }
    }
    var crit = 0.0f64
    if criterion == 0i64 { crit = logdet }
    if criterion == 1i64 { crit = acrit }
    if criterion == 2i64 { crit = icrit }
    ret (crit, acrit, icrit)
}

// C = A B for the packed upper triangle A (a by a), B' (b columns of length a) and C' likewise
fn matmult(am: []const f64, bm: []const f64, cm: []f64, a: usize, b: usize) {
    var i = 0usize
    while i < a * b {
        cm[i] = 0.0f64
        i += 1usize
    }
    var pb = 0usize
    var pc = 0usize
    i = 0usize
    while i < b {
        var pa = 0usize
        var j = 0usize
        while j < a {
            var pbj = pb + j
            var s = 0.0f64
            var k = j
            while k < a {
                s += am[pa] * bm[pbj]
                pa += 1usize
                pbj += 1usize
                k += 1usize
            }
            cm[pc] = s
            pc += 1usize
            j += 1usize
        }
        pb += a
        i += 1usize
    }
    pb = 0usize
    pc = 0usize
    i = 0usize
    while i < b {
        var pa = 0usize
        var pbj = pb
        var j = 0usize
        while j + 1usize < a {
            pa += 1usize
            var k = j + 1usize
            while k < a {
                cm[pc + k] += am[pa] * bm[pbj]
                pa += 1usize
                k += 1usize
            }
            pbj += 1usize
            j += 1usize
        }
        pb += a
        pc += a
        i += 1usize
    }
}

// the shell sort of dShellSort: by d ascending (by_d) or by index ascending
fn dcompare(a: Dt, b: Dt, by_d: bool) -> i64 {
    if by_d {
        let dd = a.d - b.d
        if dd < 0.0f64 { ret 0i64 - 1i64 }
        if dd == 0.0f64 { ret 0i64 }
        ret 1i64
    }
    if a.i < b.i { ret 0i64 - 1i64 }
    if a.i == b.i { ret 0i64 }
    ret 1i64
}

fn dshell_sort(d: []Dt, n: usize, by_d: bool) {
    var gap = n / 2usize
    while gap > 0usize {
        var i = gap
        while i < n {
            var j = i
            while j >= gap {
                let jj = j - gap
                if dcompare(d[jj], d[jj + gap], by_d) <= 0i64 { break }
                let tmp = d[jj]
                d[jj] = d[jj + gap]
                d[jj + gap] = tmp
                j = jj
            }
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// makeBXd: V = X Ti, U = X Ti Ti', the d values (row sums of squares of V), BU = G U for I, and the sorted order
fn make_bxd(f: *Fed, criterion: i64) -> (f64, usize) {
    let k = f.k
    var i = 0usize
    while i < f.nn {
        var q = 0usize
        var sumsq = 0.0f64
        var j = 0usize
        while j < k {
            var sum = 0.0f64
            var l = 0usize
            while l <= j {
                sum += f.x[i * k + l] * f.tip[q]
                q += 1usize
                l += 1usize
            }
            sumsq += sum * sum
            f.v[i * k + j] = sum
            j += 1usize
        }
        f.d[i].i = i
        f.d[i].d = sumsq
        if criterion != 0i64 {
            var qq = 0usize
            j = 0usize
            while j < k {
                var sum = 0.0f64
                var l = j
                while l < k {
                    sum += f.v[i * k + l] * f.ti[qq]
                    qq += 1usize
                    l += 1usize
                }
                f.u[i * k + j] = sum
                j += 1usize
            }
        }
        i += 1usize
    }
    if criterion == 2i64 { matmult(f.b, f.u, f.bu, k, f.nn) }
    dshell_sort(f.d, f.nn, true)
    let maxd = f.d[f.nn - 1usize].d
    let maxdi = f.d[f.nn - 1usize].i
    var g = 0usize
    i = 0usize
    while i < f.nn {
        if !f.approx && f.flag[f.d[i].i] != 0i64 {
            f.d[i].o = g
            g += 1usize
        } else {
            f.d[i].o = i
        }
        i += 1usize
    }
    dshell_sort(f.d, f.nn, false)
    ret (maxd, maxdi)
}

fn linear_criterion_a(bu: []const f64, criterion: i64, u: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    if criterion == 1i64 {
        while i < k {
            s += u[i] * u[i]
            i += 1usize
        }
    } else {
        while i < k {
            s += bu[i] * u[i]
            i += 1usize
        }
    }
    ret s
}

fn linear_criterion(f: *Fed, criterion: i64, i: usize, j: usize, di: f64, dj: f64, dij: f64, dn: f64) -> f64 {
    let k = f.k
    var si = 0.0f64
    var sji = 0.0f64
    var sij = 0.0f64
    var sj = 0.0f64
    var ss = 0.0f64
    var l = 0usize
    if criterion == 1i64 {
        while l < k {
            let ui = f.u[i * k + l]
            let uj = f.u[j * k + l]
            si += ui * ui
            sji += ui * uj
            sj += uj * uj
            l += 1usize
        }
        ss = 2.0f64 * sji
    } else {
        while l < k {
            let bi = f.bu[i * k + l]
            let bj = f.bu[j * k + l]
            si += bi * f.u[i * k + l]
            sji += bj * f.u[i * k + l]
            sij += bi * f.u[j * k + l]
            sj += bj * f.u[j * k + l]
            l += 1usize
        }
        ss = sji + sij
    }
    ret (sj * (dn - di) + ss * dij - si * (dn + dj)) / (dn * dn)
}

// findDelta: the best exchange (xold in the design, xnew outside), its gain, and failure
fn find_delta(f: *Fed, criterion: i64, n: usize, trows: []const i64) -> (f64, i64, i64, bool) {
    let k = f.k
    let dn = f64(n)
    var extreme = 1.0e-14f64
    var xi = 0i64 - 1i64
    var xj = 0i64 - 1i64
    var i = 0usize
    while i < n {
        let ri = usize(trows[i])
        if f.flag[ri] == 2i64 || i64(f.d[ri].o) > f.klimit {
            i += 1usize
            continue
        }
        let di = f.d[ri].d
        var j = 0usize
        while j < f.nn {
            if f.flag[j] != 0i64 || i64(f.d[j].o) < f.llimit {
                j += 1usize
                continue
            }
            let dj = f.d[j].d
            var dij = 0.0f64
            var l = 0usize
            while l < k {
                dij += f.v[ri * k + l] * f.v[j * k + l]
                l += 1usize
            }
            let delta_t = (dn * dj - (di * dj - dij * dij) - dn * di) / (dn * dn)
            var delta = delta_t
            if criterion != 0i64 { delta = linear_criterion(f, criterion, ri, j, di, dj, dij, dn) / (1.0f64 + delta_t) }
            if delta > extreme {
                extreme = delta
                xi = i64(ri)
                xj = i64(j)
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (extreme, xi, xj, xi == 0i64 - 1i64 || xj == 0i64 - 1i64)
}

// findDeltaAlpha: the best point and step of the approximate theory
fn find_delta_alpha(f: *Fed, criterion: i64, maxd: f64, maxdi: usize, acrit: f64, icrit: f64) -> (f64, f64, i64, bool) {
    let k = f.k
    var best_delta = 1.0e-14f64
    var best_alpha = 0.0f64
    var xi = 0i64 - 1i64
    var crit = f64(k)
    if criterion == 1i64 { crit = acrit }
    if criterion == 2i64 { crit = icrit }
    if criterion == 0i64 {
        best_delta = maxd
        best_alpha = (best_delta - crit) / ((best_delta - 1.0f64) * f64(k))
        best_delta = best_delta - crit
        xi = i64(maxdi)
    } else {
        var i = 0usize
        while i < f.nn {
            let delta0 = linear_criterion_a(f.bu[i * k..i * k + k], criterion, f.u[i * k..i * k + k], k)
            let alpha = (delta0 - crit) / (1.2f64 * delta0 * (f.d[i].d - 1.0f64))
            let delta = delta0 - crit
            if delta > best_delta {
                best_alpha = alpha
                best_delta = delta
                xi = i64(i)
            }
            i += 1usize
        }
    }
    ret (best_delta, best_alpha, xi, xi == 0i64 - 1i64)
}

fn update_a(f: *Fed, xnew: usize, proportions: []f64, alpha: f64) {
    let k = f.k
    let beta = 1.0f64 - alpha
    var pt = 0usize
    var i = 0usize
    while i < k {
        f.t[pt] = f.t[pt] * beta
        pt += k - i
        i += 1usize
    }
    rotate(f.x[xnew * k..xnew * k + k], f.vec, f.t, k, k, alpha, 1.0f64)
    i = 0usize
    while i < f.nn {
        proportions[i] = proportions[i] * beta
        i += 1usize
    }
    proportions[xnew] = proportions[xnew] + alpha
}

fn update(f: *Fed, xold: usize, xnew: usize, trows: []i64, n: usize) {
    let k = f.k
    rotate(f.x[xnew * k..xnew * k + k], f.vec, f.t, k, k, 1.0f64, f64(n))
    rotate(f.x[xold * k..xold * k + k], f.vec, f.t, k, k, 0.0f64 - 1.0f64, f64(n))
    f.flag[xold] = 0i64
    f.flag[xnew] = 1i64
    var i = 0usize
    while i < n {
        if i64(xold) == trows[i] {
            trows[i] = i64(xnew)
            break
        }
        i += 1usize
    }
}

fn fill_in_b(f: *Fed) {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var i = 0usize
    while i < kk {
        f.b[i] = 0.0f64
        i += 1usize
    }
    var l = 0usize
    while l < f.nn {
        var pb = 0usize
        var i1 = 0usize
        while i1 < k {
            var j = i1
            while j < k {
                f.b[pb] += f.x[l * k + i1] * f.x[l * k + j] / f64(f.nn)
                pb += 1usize
                j += 1usize
            }
            i1 += 1usize
        }
        l += 1usize
    }
}

fn permute(g: *rng.Rng, a: []i64, n: usize) {
    var i = 1usize
    while i < n {
        let j = usize(f64(1usize + i) * rng.unif(g))
        let tmp = a[j]
        a[j] = a[i]
        a[i] = tmp
        i += 1usize
    }
}

// filloutDesign: adds rows to a nullification start until n is reached, by the largest variance
fn fillout_design(f: *Fed, rows: []i64, ka: usize, n: usize) -> bool {
    let k = f.k
    let (ld0, singular0) = reduce_design(f, rows, ka, false)
    if singular0 { ret true }
    let (ld1, singular1) = make_ti_tip(f, 1.0f64)
    if singular1 { ret true }
    var i = ka
    while i < n {
        var newrow = 0i64 - 1i64
        var delta = 0.0f64 - 1.0f64
        var j = 0usize
        while j < f.nn {
            if f.ttrows[j] == 0i64 {
                var sumsq = 0.0f64
                var pt = 0usize
                var l = 0usize
                while l < k {
                    var d = 0.0f64
                    var m = 0usize
                    while m <= l {
                        d += f.x[j * k + m] * f.tip[pt]
                        pt += 1usize
                        m += 1usize
                    }
                    sumsq += d * d
                    l += 1usize
                }
                if sumsq > delta {
                    delta = sumsq
                    newrow = i64(j)
                }
            }
            j += 1usize
        }
        if newrow == 0i64 - 1i64 { ret true }
        f.ttrows[usize(newrow)] = 1i64
        rows[i] = newrow
        if i != n - 1usize {
            rotate(f.x[usize(newrow) * k..usize(newrow) * k + k], f.vec, f.t, k, k, 1.0f64, 1.0f64)
            let (ld2, singular2) = make_ti_tip(f, 1.0f64)
            if singular2 { ret true }
        }
        i += 1usize
    }
    ret false
}

// optFederov's FederovOptimize on the row-major model matrix x (nn by k). rows is the in/out design (length nn at least);
// proportions (nn) is used when approx
fn fedorov(a: *mem.Arena, g: *rng.Rng, x: []const f64, nn: usize, k: usize, random_start: bool, nullify_mode: i64, criterion: i64, evaluate_i: bool,
           space_b: []const f64, do_space: bool, augment: usize, approx: bool, n_in: usize, max_iteration0: i64, n_repeats0: i64, dfrac: f64, cfrac: f64,
           rows: []i64, proportions: []f64) -> (Res, err) {
    var res: Res = zero
    let kk = k * (k + 1usize) / 2usize
    var f: Fed = zero
    f.nn = nn
    f.k = k
    f.approx = approx
    let (xx, e1) = mem.alloc[f64](a, nn * k)
    let (v, e2) = mem.alloc[f64](a, nn * k)
    let (u, e3) = mem.alloc[f64](a, nn * k)
    let (bu, e4) = mem.alloc[f64](a, nn * k)
    let (b, e5) = mem.alloc[f64](a, kk)
    let (t, e6) = mem.alloc[f64](a, kk)
    let (ti, e7) = mem.alloc[f64](a, kk)
    let (tip, e8) = mem.alloc[f64](a, kk)
    let (w, e9) = mem.alloc[f64](a, kk)
    let (mm, e10) = mem.alloc[f64](a, 2usize * k)
    let (vec, e11) = mem.alloc[f64](a, k)
    let (d, e12) = mem.alloc[Dt](a, nn)
    let (flag, e13) = mem.alloc[i64](a, nn)
    let (ttrows, e14) = mem.alloc[i64](a, nn)
    let (trows, e15) = mem.alloc[i64](a, nn)
    let (tmp, e16) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (res, e1) }
    var q = 0usize
    while q < nn * k {
        xx[q] = x[q]
        v[q] = 0.0f64
        u[q] = 0.0f64
        bu[q] = 0.0f64
        q += 1usize
    }
    f.x = xx
    f.v = v
    f.u = u
    f.bu = bu
    f.b = b
    f.t = t
    f.ti = ti
    f.tip = tip
    f.w = w
    f.maxmin = mm
    f.vec = vec
    f.d = d
    f.flag = flag
    f.ttrows = ttrows
    f.trows = trows
    var n = n_in
    var n_repeats = n_repeats0
    if approx || nullify_mode == 1i64 { n_repeats = 1i64 }
    if do_space {
        q = 0usize
        while q < kk {
            f.b[q] = space_b[q]
            q += 1usize
        }
    }
    if !do_space && (criterion == 2i64 || evaluate_i) { fill_in_b(&f) }
    f.klimit = i64(dfrac * f64(n))
    f.llimit = i64((1.0f64 - cfrac) * f64(nn - 1usize))
    var max_iteration = max_iteration0
    if max_iteration == 0i64 { max_iteration = 100i64 }
    var nullify_ = nullify_mode
    if approx {
        n = k
        nullify_ = 1i64
    }
    var best_crit = 1.0e8f64
    if criterion == 0i64 { best_crit = 0.0f64 - 1.0e8f64 }
    var count_singular = 0i64
    var iter = 0i64
    var n_repeat_counts = n_repeats
    var err_code = 0i64
    var again = true
    while again {
        var first_pass = true
        q = 0usize
        while q < nn {
            f.flag[q] = 0i64
            q += 1usize
        }
        var i = 0usize
        if augment > 0usize {
            while i < augment {
                f.flag[usize(rows[i])] = 2i64
                i += 1usize
            }
        }
        var broke = false
        if nullify_ != 0i64 {
            if augment < k {
                if !nullify(&f, augment, rows, tmp) {
                    res.errcode = 13i64
                    ret (res, ok)
                }
            }
            i = 0usize
            while i < nn {
                f.ttrows[i] = f.flag[i]
                i += 1usize
            }
            var ka = k
            if augment > k { ka = augment }
            if n > ka {
                if nullify_ == 1i64 {
                    let sing = fillout_design(&f, rows, ka, n)
                    if sing {
                        count_singular += 1i64
                        broke = true
                    } else {
                        i = 0usize
                        while i < n {
                            f.trows[i] = rows[i]
                            i += 1usize
                        }
                    }
                } else {
                    var j = 0usize
                    i = 0usize
                    while i < nn {
                        if f.flag[i] == 0i64 {
                            f.ttrows[j] = i64(i)
                            j += 1usize
                        }
                        i += 1usize
                    }
                    permute(g, f.ttrows, nn - k)
                    j = 0usize
                    var l = 0usize
                    i = 0usize
                    while i < nn {
                        if f.flag[i] != 0i64 {
                            f.trows[j] = rows[j]
                            j += 1usize
                        } else {
                            f.trows[l] = f.ttrows[l]
                            l += 1usize
                        }
                        i += 1usize
                    }
                }
            } else {
                i = 0usize
                while i < n {
                    f.trows[i] = rows[i]
                    i += 1usize
                }
            }
        } else if random_start {
            i = 0usize
            while i < nn {
                f.trows[i] = i64(i)
                i += 1usize
            }
            permute(g, f.trows, nn)
        } else {
            if augment != 0usize {
                i = 0usize
                while i < augment {
                    f.trows[i] = rows[i]
                    i += 1usize
                }
                if augment < n {
                    var j = augment
                    i = 0usize
                    while i < nn {
                        if f.flag[i] == 0i64 {
                            f.trows[j] = i64(i)
                            j += 1usize
                        }
                        i += 1usize
                    }
                    permute(g, f.trows[augment..nn], nn - augment)
                }
            } else {
                i = 0usize
                while i < n {
                    f.trows[i] = rows[i]
                    i += 1usize
                }
            }
        }
        if !broke {
            i = 0usize
            while i < n {
                if f.flag[usize(f.trows[i])] == 0i64 { f.flag[usize(f.trows[i])] = 1i64 }
                i += 1usize
            }
            let (logdet0, singular0) = reduce_design(&f, f.trows, n, true)
            var logdet = logdet0
            var singular = singular0
            if approx {
                q = 0usize
                while q < nn {
                    proportions[q] = 0.0f64
                    q += 1usize
                }
                let pf = 1.0f64 / f64(k)
                i = 0usize
                while i < k {
                    proportions[usize(rows[i])] = pf
                    i += 1usize
                }
            }
            var restart = true
            while restart {
                restart = false
                if singular {
                    count_singular += 1i64
                } else {
                    var norm = f64(n)
                    if approx { norm = 1.0f64 }
                    let (ld, sg) = make_ti_tip(&f, norm)
                    logdet = ld
                    if sg {
                        count_singular += 1i64
                    } else {
                        let (crit0, acrit0, icrit0) = evaluate_criteria(&f, criterion, evaluate_i, logdet)
                        var crit = crit0
                        var acrit = acrit0
                        var icrit = icrit0
                        let (maxd0, maxdi0) = make_bxd(&f, criterion)
                        var maxd = maxd0
                        var maxdi = maxdi0
                        var miter = 0i64
                        var sing_exit = false
                        var go = true
                        while go {
                            if approx {
                                let (delta, alpha, xnew, failure) = find_delta_alpha(&f, criterion, maxd, maxdi, acrit, icrit)
                                var lim = 1.0e-3f64
                                if crit > 0.0f64 { lim = crit * 1.0e-3f64 }
                                if failure || delta < lim || miter > max_iteration { break }
                                update_a(&f, usize(xnew), proportions, alpha)
                                f.flag[usize(xnew)] = 0i64
                            } else {
                                let (delta, xold, xnew, failure) = find_delta(&f, criterion, n, f.trows)
                                if failure || delta < crit * 1.0e-3f64 || miter > max_iteration { break }
                                update(&f, usize(xold), usize(xnew), f.trows, n)
                            }
                            let (ld2, sg2) = make_ti_tip(&f, norm)
                            logdet = ld2
                            if sg2 {
                                sing_exit = true
                                break
                            }
                            let (c2, a2, i2) = evaluate_criteria(&f, criterion, evaluate_i, logdet)
                            crit = c2
                            acrit = a2
                            icrit = i2
                            let (m2, mi2) = make_bxd(&f, criterion)
                            maxd = m2
                            maxdi = mi2
                            miter += 1i64
                        }
                        if sing_exit {
                            count_singular += 1i64
                        } else {
                            if miter > iter { iter = miter }
                            var better = crit > best_crit
                            if criterion != 0i64 { better = crit < best_crit }
                            if better {
                                best_crit = crit
                                if !approx {
                                    i = 0usize
                                    while i < n {
                                        rows[i] = f.trows[i]
                                        i += 1usize
                                    }
                                }
                                res.dd = math.exp[f64](logdet / f64(k))
                                res.aa = acrit
                                res.gg = f64(k) / maxd
                                if criterion == 2i64 || evaluate_i { res.ii = icrit }
                            }
                            if approx && first_pass {
                                first_pass = false
                                var np = 0usize
                                var nd = 0usize
                                i = 0usize
                                while i < nn {
                                    if proportions[i] > 0.0f64 { np += 1usize }
                                    if f.flag[i] > 0i64 { nd += 1usize }
                                    i += 1usize
                                }
                                n = np - nd
                                if n >= k {
                                    i = 0usize
                                    while i < nn {
                                        if f.flag[i] > 0i64 { proportions[i] = 0.0f64 }
                                        i += 1usize
                                    }
                                    i = 0usize
                                    while i < nn {
                                        f.flag[i] = 0i64
                                        i += 1usize
                                    }
                                    var j = 0usize
                                    i = 0usize
                                    while i < nn {
                                        if proportions[i] > 0.0f64 {
                                            f.trows[j] = i64(i)
                                            j += 1usize
                                            proportions[i] = 1.0f64 / f64(n)
                                        }
                                        i += 1usize
                                    }
                                    let (ld3, s3) = reduce_design(&f, f.trows, n, true)
                                    singular = s3
                                    restart = true
                                }
                            }
                        }
                    }
                }
            }
        }
        if broke {
            again = false
        } else if !random_start && nullify_ != 2i64 {
            again = false
        } else {
            n_repeat_counts -= 1i64
            if n_repeat_counts == 0i64 { again = false }
        }
    }
    if random_start || nullify_ == 2i64 {
        if count_singular == n_repeats { err_code = 12i64 }
    } else {
        if count_singular > 0i64 { err_code = 12i64 }
    }
    res.iter = iter
    res.errcode = err_code
    res.rows = rows
    res.proportions = proportions
    ret (res, ok)
}
