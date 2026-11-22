// R robustbase lmrob with method "MM" (Tukey bisquare, nonsingular subsampling): lmrob.S's fast S algorithm (lmrob.c: fast_s, subsample on the equilibrated design with its own LU,
// refine_fast_s, find_scale), then the M step (rwls) from the S estimate and scale. unif_rand draws are made in R's order. x is n by p column-major (the intercept column first when the model has one).

use e.math
use e.math.dist as dist
use e.algo.linalg.decomp as dc
use e.algo.rand.r as rng
use e.algo.stat.robustbase as rb
use e.algo.stat.robustbase_lts as lt
use e.mem

error LmrobFail

// the psi family: kind 1 = Tukey bisquare (c0 the cutoff), kind 6 = lqq with (b, c, s) = (c0, c1, c2)
type Psi = struct { kind: usize, c0: f64, c1: f64, c2: f64 }

fn lm_rho(x: f64, ps: Psi) -> f64 {
    if ps.kind == 6usize {
        let ax = lt.fabs(x)
        let k01 = ps.c0 + ps.c1
        let den = ps.c2 * ps.c1 * (3.0f64 * ps.c1 + 2.0f64 * ps.c0) + k01 * k01
        if ax <= ps.c1 { ret (3.0f64 * ps.c2 - 3.0f64) / den * x * x }
        if ax <= k01 {
            let s0 = ax - ps.c1
            ret (6.0f64 * ps.c2 - 6.0f64) / den * (x * x / 2.0f64 - ps.c2 / ps.c0 * (s0 * s0 * s0) / 6.0f64)
        }
        let s5 = ps.c2 - 1.0f64
        let s6 = -2.0f64 * k01 + ps.c0 * ps.c2
        if ax < k01 - s6 / s5 {
            let s7 = ax - k01
            ret (6.0f64 * s5) / den * (k01 * k01 / 2.0f64 - ps.c2 * ps.c0 * ps.c0 / 6.0f64 - s7 / 2.0f64 * (s6 + s7 * (s5 + s7 * s5 * s5 / 3.0f64 / s6)))
        }
        ret 1.0f64
    }
    let c = ps.c0
    if lt.fabs(x) > c { ret 1.0f64 }
    var t = x / c
    t = t * t
    ret t * (3.0f64 + t * (0.0f64 - 3.0f64 + t))
}

fn lm_wgt(x: f64, ps: Psi) -> f64 {
    if ps.kind == 6usize {
        let ax = lt.fabs(x)
        if ax <= ps.c1 { ret 1.0f64 }
        let k01 = ps.c0 + ps.c1
        if ax <= k01 {
            let s0 = ax - ps.c1
            ret 1.0f64 - ps.c2 * s0 * s0 / (2.0f64 * ax * ps.c0)
        }
        let s5 = ps.c2 - 1.0f64
        let s6 = -2.0f64 * k01 + ps.c0 * ps.c2
        if ax < k01 - s6 / s5 {
            let s7 = ax - k01
            ret 0.0f64 - (s6 / 2.0f64 + s5 * s5 / s6 * s7 * (s7 / 2.0f64 + s6 / s5)) / ax
        }
        ret 0.0f64
    }
    let c = ps.c0
    if lt.fabs(x) > c { ret 0.0f64 }
    var a = x / c
    a = (1.0f64 - a) * (1.0f64 + a)
    ret a * a
}

fn lm_psi(x: f64, ps: Psi) -> f64 {
    if ps.kind == 6usize {
        let ax = lt.fabs(x)
        if ax <= ps.c1 { ret x }
        var sg = 0.0f64
        if x > 0.0f64 { sg = 1.0f64 }
        if x < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        let k01 = ps.c0 + ps.c1
        if ax <= k01 {
            let d = ax - ps.c1
            ret sg * (ax - ps.c2 * (d * d) / ps.c0 / 2.0f64)
        }
        let s5 = ps.c2 - 1.0f64
        let s6 = -2.0f64 * k01 + ps.c0 * ps.c2
        if ax < k01 - s6 / s5 {
            var sg2 = 1.0f64
            if !(x > 0.0f64) { sg2 = 0.0f64 - 1.0f64 }
            let d = ax - k01
            ret sg2 * (0.0f64 - s6 / 2.0f64 - (s5 * s5) / s6 * ((d * d) / 2.0f64 + s6 / s5 * d))
        }
        ret 0.0f64
    }
    let c = ps.c0
    if lt.fabs(x) > c { ret 0.0f64 }
    let a = x / c
    let u = 1.0f64 - a * a
    ret x * u * u
}

fn lm_sum_rho(r: []const f64, scale: f64, n: usize, p: usize, c: Psi) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s = s + lm_rho(r[i] / scale, c)
        i += 1usize
    }
    ret s / (f64(n) - f64(p))
}

fn lm_kth(a: []f64, n: usize, k0: usize) -> f64 {
    let k = k0 - 1usize
    var l = 0i64
    var lr = i64(n) - 1i64
    while l < lr {
        let ak = a[k]
        var jnc = l
        var j = lr
        while jnc <= j {
            while a[usize(jnc)] < ak { jnc += 1i64 }
            while a[usize(j)] > ak { j -= 1i64 }
            if jnc <= j {
                let w = a[usize(jnc)]
                a[usize(jnc)] = a[usize(j)]
                a[usize(j)] = w
                jnc += 1i64
                j -= 1i64
            }
        }
        if j < i64(k) { l = jnc }
        if i64(k) < jnc { lr = j }
    }
    ret a[k]
}

// MAD(res, n, 0): median of |res| times 1.4826
fn lm_mad0(a: []const f64, n: usize, b: []f64) -> f64 {
    var i = 0usize
    while i < n {
        b[i] = lt.fabs(a[i])
        i += 1usize
    }
    var m = 0.0f64
    if n % 2usize == 1usize {
        m = lm_kth(b, n, n / 2usize + 1usize)
    } else {
        let m1 = lm_kth(b, n, n / 2usize)
        let m2 = lm_kth(b, n, n / 2usize + 1usize)
        m = (m1 + m2) / 2.0f64
    }
    ret m * 1.4826f64
}

// res = y - X beta (dgemv column by column)
fn lm_res(x: []const f64, y: []const f64, n: usize, p: usize, beta: []const f64, res: []f64) {
    var i = 0usize
    while i < n {
        res[i] = y[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        let t = 0.0f64 - beta[j]
        if beta[j] != 0.0f64 {
            i = 0usize
            while i < n {
                res[i] = res[i] + t * x[j * n + i]
                i += 1usize
            }
        }
        j += 1usize
    }
}

fn lm_weights(r: []const f64, s: f64, n: usize, c: Psi, w: []f64) {
    var i = 0usize
    while i < n {
        var z = 0.0f64
        if r[i] != 0.0f64 { z = r[i] / s }
        w[i] = lm_wgt(z, c)
        i += 1usize
    }
}

fn lm_find_scale(r: []const f64, b: f64, c: Psi, init: f64, n: usize, p: usize, maxit: usize, tol: f64) -> f64 {
    if init <= 0.0f64 { ret 0.0f64 }
    var scale = init
    var ini = init
    var it = 0usize
    while it < maxit {
        scale = scale * math.sqrt[f64](lm_sum_rho(r, scale, n, p, c) / b)
        if lt.fabs(scale - ini) <= tol * ini { ret scale }
        ini = scale
        it += 1usize
    }
    ret scale
}

fn lm_find_max(a: []const f64, n: usize) -> usize {
    var k = 0usize
    if n > 1usize {
        var tt = a[0usize]
        var i = 1usize
        while i < n {
            if tt < a[i] {
                tt = a[i]
                k = i
            }
            i += 1usize
        }
    }
    ret k
}

// refine_fast_s: kk steps (convcheck false) or up to kk steps until convergence (convcheck true). Returns (steps or -zeroes, converged, scale); res holds the residuals of the last fit, beta_ref the fit.
fn lm_refine(a: *mem.Arena, x: []const f64, y: []const f64, sy: f64, n: usize, p: usize, res: []f64, beta_cand: []const f64, beta_ref: []f64, convcheck: bool, kk: usize, rel_tol: f64, zero_tol: f64, bb: f64, c: Psi, initial_scale: f64) -> (i64, bool, f64, err) {
    var conv = convcheck
    lm_res(x, y, n, p, beta_cand, res)
    let (wk, e0) = mem.alloc[f64](a, n)
    let (wts, e1) = mem.alloc[f64](a, n)
    let (bj, e2) = mem.alloc[f64](a, p)
    let (rs, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (0i64, false, 0.0f64, e0) }
    var isc = initial_scale
    if isc < 0.0f64 { isc = lm_mad0(res, n, wk) }
    let s0z = sy * zero_tol
    var zeroes = 0i64
    var j = 0usize
    while j < n {
        if lt.fabs(res[j]) <= s0z { zeroes += 1i64 }
        j += 1usize
    }
    if isc <= 0.0f64 || f64(zeroes) > f64(n) / 2.0f64 {
        j = 0usize
        while j < p {
            beta_ref[j] = beta_cand[j]
            j += 1usize
        }
        ret (0i64 - zeroes, conv, 0.0f64, ok)
    }
    var s0 = isc
    j = 0usize
    while j < p {
        bj[j] = beta_cand[j]
        j += 1usize
    }
    var converged = false
    var iS = 0usize
    while iS < kk {
        s0 = s0 * math.sqrt[f64](lm_sum_rho(res, s0, n, p, c) / bb)
        lm_weights(res, s0, n, c, wts)
        let start = mem.mark(a)
        let fe = lt.wls_fit(a, x, y, wts, n, p, beta_ref, rs)
        mem.reset(a, start)
        if fe != ok { ret (0i64, false, 0.0f64, fe) }
        if conv {
            var del = 0.0f64
            j = 0usize
            while j < p {
                del = del + (bj[j] - beta_ref[j]) * (bj[j] - beta_ref[j])
                j += 1usize
            }
            del = math.sqrt[f64](del)
            let nrm = rb.dnrm2_blue(bj, 0usize, p)
            var mx = rel_tol
            if nrm > mx { mx = nrm }
            converged = del <= rel_tol * mx
            if converged { break }
        }
        lm_res(x, y, n, p, beta_ref, res)
        j = 0usize
        while j < p {
            bj[j] = beta_ref[j]
            j += 1usize
        }
        iS += 1usize
    }
    if conv && !converged { conv = false }
    ret (i64(iS), conv, s0, ok)
}

// dgeequ + dlaqge: Xe gets the equilibrated design, dr and dcol the factors; returns (rowequ, colequ, info) with info > 0 when the equilibration is skipped
fn lm_equil(x: []const f64, n: usize, p: usize, xe: []f64, dr: []f64, dcol: []f64) -> (bool, bool, i64) {
    let smlnum = 2.2250738585072014e-308f64
    let bignum = 1.0f64 / smlnum
    var i = 0usize
    while i < n * p {
        xe[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        dr[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            let v = lt.fabs(x[j * n + i])
            if v > dr[i] { dr[i] = v }
            i += 1usize
        }
        j += 1usize
    }
    var rcmin = bignum
    var rcmax = 0.0f64
    i = 0usize
    while i < n {
        if dr[i] > rcmax { rcmax = dr[i] }
        if dr[i] < rcmin { rcmin = dr[i] }
        i += 1usize
    }
    let amax = rcmax
    if rcmin == 0.0f64 {
        i = 0usize
        while i < n {
            if dr[i] == 0.0f64 { ret (false, false, i64(i) + 1i64) }
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        var t = dr[i]
        if t < smlnum { t = smlnum }
        if t > bignum { t = bignum }
        dr[i] = 1.0f64 / t
        i += 1usize
    }
    var rm = rcmin
    if rm < smlnum { rm = smlnum }
    var rx = rcmax
    if rx > bignum { rx = bignum }
    let rowcnd = rm / rx
    j = 0usize
    while j < p {
        dcol[j] = 0.0f64
        i = 0usize
        while i < n {
            let v = lt.fabs(x[j * n + i]) * dr[i]
            if v > dcol[j] { dcol[j] = v }
            i += 1usize
        }
        j += 1usize
    }
    var cmin = bignum
    var cmax = 0.0f64
    j = 0usize
    while j < p {
        if dcol[j] > cmax { cmax = dcol[j] }
        if dcol[j] < cmin { cmin = dcol[j] }
        j += 1usize
    }
    if cmin == 0.0f64 {
        j = 0usize
        while j < p {
            if dcol[j] == 0.0f64 { ret (false, false, i64(n) + i64(j) + 1i64) }
            j += 1usize
        }
    }
    j = 0usize
    while j < p {
        var t = dcol[j]
        if t < smlnum { t = smlnum }
        if t > bignum { t = bignum }
        dcol[j] = 1.0f64 / t
        j += 1usize
    }
    var cm = cmin
    if cm < smlnum { cm = smlnum }
    var cx = cmax
    if cx > bignum { cx = bignum }
    let colcnd = cm / cx
    let small = smlnum / 2.220446049250313e-16f64
    let large = 1.0f64 / small
    var rowequ = false
    var colequ = false
    if rowcnd >= 0.1f64 && amax >= small && amax <= large {
        if colcnd < 0.1f64 {
            colequ = true
            j = 0usize
            while j < p {
                i = 0usize
                while i < n {
                    xe[j * n + i] = dcol[j] * xe[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
        }
    } else {
        if colcnd >= 0.1f64 {
            rowequ = true
            j = 0usize
            while j < p {
                i = 0usize
                while i < n {
                    xe[j * n + i] = dr[i] * xe[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
        } else {
            rowequ = true
            colequ = true
            j = 0usize
            while j < p {
                let cj = dcol[j]
                i = 0usize
                while i < n {
                    xe[j * n + i] = cj * dr[i] * xe[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
        }
    }
    ret (rowequ, colequ, 0i64)
}

// subsample() with sample = TRUE, solve = TRUE; returns 0 on success, 1 when no nonsingular subsample exists, 2 for too many singular resamples (simple subsampling)
fn lm_subsample(g: *rng.Rng, xe: []const f64, y: []const f64, n: usize, m: usize, beta: []f64, indsp: []i64, idc: []i64, idr: []i64, lu: []f64, v: []f64, pivot: []i64, dr: []const f64, dcol: []const f64, rowequ: bool, colequ: bool, mts: usize, ss: bool, tol_inv: f64) -> i64 {
    var i = 0usize
    var attempt = 0usize
    var restart = true
    while restart {
        restart = false
        // sample_noreplace(ind_space, n, n, idc)
        var k = 0usize
        while k < n {
            idc[k] = i64(k)
            k += 1usize
        }
        var nn = n
        k = 0usize
        while k < n {
            let jj = usize(f64(nn) * rng.unif(g))
            indsp[k] = idc[jj]
            nn -= 1usize
            idc[jj] = idc[nn]
            k += 1usize
        }
        k = 0usize
        while k < m {
            idr[k] = i64(k)
            k += 1usize
        }
        var j = 0usize
        while j < m && !restart {
            var sing = true
            while sing && !restart {
                if i + j == n { ret 1i64 }
                idc[j] = indsp[i + j]
                if j == 0usize {
                    k = 0usize
                    while k < m {
                        v[k] = xe[usize(idr[k]) * n + usize(idc[0usize])]
                        k += 1usize
                    }
                } else {
                    k = 0usize
                    while k < j {
                        lu[j * m + k] = xe[usize(idr[k]) * n + usize(idc[j])]
                        k += 1usize
                    }
                    // z = solve(unit lower L[0:j,0:j], U[0:j, j]) (dtrsv L N U)
                    var jj = 0usize
                    while jj < j {
                        if lu[j * m + jj] != 0.0f64 {
                            let tmp = lu[j * m + jj]
                            var ii = jj + 1usize
                            while ii < j {
                                lu[j * m + ii] = lu[j * m + ii] - tmp * lu[jj * m + ii]
                                ii += 1usize
                            }
                        }
                        jj += 1usize
                    }
                    k = j
                    while k < m {
                        v[k] = xe[usize(idr[k]) * n + usize(idc[j])]
                        var l = 0usize
                        while l < j {
                            v[k] = v[k] - lu[l * m + k] * lu[j * m + l]
                            l += 1usize
                        }
                        k += 1usize
                    }
                }
                if j + 1usize < m {
                    var tmpd = lt.fabs(v[j])
                    var mu = j
                    k = j + 1usize
                    while k < m {
                        if tmpd < lt.fabs(v[k]) {
                            mu = k
                            tmpd = lt.fabs(v[k])
                        }
                        k += 1usize
                    }
                    if tmpd >= tol_inv {
                        pivot[j] = i64(mu)
                        let t1 = v[j]
                        v[j] = v[mu]
                        v[mu] = t1
                        let ti = idr[j]
                        idr[j] = idr[mu]
                        idr[mu] = ti
                        k = j + 1usize
                        while k < m {
                            lu[j * m + k] = v[k] / v[j]
                            k += 1usize
                        }
                        if j > 0usize {
                            k = 0usize
                            while k < j {
                                let t2 = lu[k * m + j]
                                lu[k * m + j] = lu[k * m + mu]
                                lu[k * m + mu] = t2
                                k += 1usize
                            }
                        }
                    }
                }
                if lt.fabs(v[j]) < tol_inv {
                    if !ss {
                        attempt += 1usize
                        if attempt >= mts { ret 2i64 }
                        restart = true
                    } else {
                        i += 1usize
                    }
                } else {
                    sing = false
                    lu[j * m + j] = v[j]
                }
            }
            j += 1usize
        }
    }
    // solve for the candidate: U' L' beta = y[subsample]
    var k = 0usize
    while k < m {
        beta[k] = y[usize(idc[k])]
        k += 1usize
    }
    if rowequ {
        k = 0usize
        while k < m {
            beta[k] = beta[k] * dr[usize(idc[k])]
            k += 1usize
        }
    }
    // dtrsv U T N
    var jt = 0usize
    while jt < m {
        var temp = beta[jt]
        var it2 = 0usize
        while it2 < jt {
            temp = temp - lu[jt * m + it2] * beta[it2]
            it2 += 1usize
        }
        temp = temp / lu[jt * m + jt]
        beta[jt] = temp
        jt += 1usize
    }
    // dtrsv L T U
    var jl = m
    while jl > 0usize {
        jl -= 1usize
        var temp = beta[jl]
        var il = m
        while il > jl + 1usize {
            il -= 1usize
            temp = temp - lu[jl * m + il] * beta[il]
        }
        beta[jl] = temp
    }
    if colequ {
        k = 0usize
        while k < m {
            beta[k] = beta[k] * dcol[usize(idr[k])]
            k += 1usize
        }
    }
    if m >= 2usize {
        var kk = m - 1usize
        while kk > 0usize {
            kk -= 1usize
            let pk = usize(pivot[kk])
            let tmp = beta[kk]
            beta[kk] = beta[pk]
            beta[pk] = tmp
        }
    }
    ret 0i64
}

// lmrob.S: fills bbeta (p) and returns (scale, converged); scale -1 for a singular subsample failure
fn lm_fast_s(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, p: usize, nres: usize, c: Psi, bb: f64, best_r: usize, kmax: usize, kfast: usize, rel_tol: f64, inv_tol: f64, scale_tol: f64, zero_tol: f64, maxit_scale: usize, mts: usize, bbeta: []f64) -> (f64, bool, err) {
    var sy = 0.0f64
    var i = 0usize
    while i < n {
        sy = sy + lt.fabs(y[i])
        i += 1usize
    }
    sy = sy / f64(n)
    let infsc = sy * 1.0e20f64
    let (xe, e0) = mem.alloc[f64](a, n * p)
    let (dr, e1) = mem.alloc[f64](a, n)
    let (dcol, e2) = mem.alloc[f64](a, p)
    let (indsp, e3) = mem.alloc[i64](a, n)
    let (idc, e4) = mem.alloc[i64](a, n)
    let (idr, e5) = mem.alloc[i64](a, p)
    let (lu, e6) = mem.alloc[f64](a, p * p)
    let (v, e7) = mem.alloc[f64](a, p)
    let (pivot, e8) = mem.alloc[i64](a, p)
    let (res, e9) = mem.alloc[f64](a, n)
    let (bcand, e10) = mem.alloc[f64](a, p)
    let (bref, e11) = mem.alloc[f64](a, p)
    let (bscales, e12) = mem.alloc[f64](a, best_r)
    let (bbetas, e13) = mem.alloc[f64](a, best_r * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, false, e0) }
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (0.0f64, false, e7) }
    let (rowequ, colequ, info) = lm_equil(x, n, p, xe, dr, dcol)
    if info > i64(n) { ret (0.0f64, false, LmrobFail) }
    i = 0usize
    while i < best_r {
        bscales[i] = infsc
        i += 1usize
    }
    var pos_worst = 0usize
    var worst_sc = infsc
    i = 0usize
    while i < nres {
        let start = mem.mark(a)
        let st = lm_subsample(g, xe, y, n, p, bcand, indsp, idc, idr, lu, v, pivot, dr, dcol, rowequ, colequ, mts, true, inv_tol)
        if st != 0i64 { ret (0.0f64 - 1.0f64, false, ok) }
        let (ik, cv, sc0, re) = lm_refine(a, x, y, sy, n, p, res, bcand, bref, false, kfast, rel_tol, zero_tol, bb, c, 0.0f64 - 1.0f64)
        if re != ok { ret (0.0f64, false, re) }
        var sc = sc0
        if lt.fabs(sc) == 0.0f64 {
            var j = 0usize
            while j < p {
                bbeta[j] = bcand[j]
                j += 1usize
            }
            ret (sc, true, ok)
        }
        if lm_sum_rho(res, worst_sc, n, p, c) < bb {
            sc = lm_find_scale(res, bb, c, sc, n, p, maxit_scale, scale_tol)
            bscales[pos_worst] = sc
            var j = 0usize
            while j < p {
                bbetas[pos_worst * p + j] = bref[j]
                j += 1usize
            }
            pos_worst = lm_find_max(bscales, best_r)
            worst_sc = bscales[pos_worst]
        }
        mem.reset(a, start)
        i += 1usize
    }
    var best_sc = infsc
    var allconv = true
    i = 0usize
    while i < best_r {
        let start = mem.mark(a)
        let (it_k, cv, aux, re) = lm_refine(a, x, y, sy, n, p, res, bbetas[i * p..i * p + p], bref, true, kmax, rel_tol, zero_tol, bb, c, bscales[i])
        if re != ok { ret (0.0f64, false, re) }
        if aux < best_sc {
            best_sc = aux
            var j = 0usize
            while j < p {
                bbeta[j] = bref[j]
                j += 1usize
            }
        }
        if !cv { allconv = false }
        mem.reset(a, start)
        i += 1usize
    }
    ret (best_sc, allconv, ok)
}

// rwls: the M step from beta0 with the scale fixed; returns (converged, iterations)
fn lm_rwls(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, est: []f64, beta0: []const f64, resid: []f64, scale: f64, eps: f64, maxit: usize, c: Psi) -> (bool, usize, err) {
    let (wts, e0) = mem.alloc[f64](a, n)
    let (b0, e1) = mem.alloc[f64](a, p)
    let (rs, e2) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (false, 0usize, e0) }
    var j = 0usize
    while j < p {
        b0[j] = beta0[j]
        j += 1usize
    }
    lm_res(x, y, n, p, b0, resid)
    var converged = false
    var iterations = 0usize
    while !converged {
        iterations += 1usize
        if iterations >= maxit { break }
        lm_weights(resid, scale, n, c, wts)
        let start = mem.mark(a)
        let fe = lt.wls_fit(a, x, y, wts, n, p, est, rs)
        mem.reset(a, start)
        if fe != ok { ret (false, iterations, fe) }
        lm_res(x, y, n, p, est, resid)
        var d = 0.0f64
        var nr = 0.0f64
        j = 0usize
        while j < p {
            d = d + lt.fabs(b0[j] - est[j])
            nr = nr + lt.fabs(est[j])
            j += 1usize
        }
        var mx = eps
        if nr > mx { mx = nr }
        converged = d <= eps * mx
        j = 0usize
        while j < p {
            b0[j] = est[j]
            j += 1usize
        }
    }
    ret (converged, iterations, ok)
}

// R's zeroin (R_zeroin2) on [ax, bx] for a function that is linear in its argument: f(x) = ca - x * cb (the caller supplies the two sums); tol as uniroot's default
fn lm_zeroin(ca: f64, cb: f64, ax: f64, bx: f64, tol: f64) -> f64 {
    var a = ax
    var b = bx
    var fa = ca - a * cb
    var fb = ca - b * cb
    var c = a
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    let eps = 2.220446049250313e-16f64
    var maxit = 1001usize
    while maxit > 0usize {
        maxit -= 1usize
        let prev_step = b - a
        if lt.fabs(fc) < lt.fabs(fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * lt.fabs(b) + tol / 2.0f64
        var new_step = (c - b) / 2.0f64
        if lt.fabs(new_step) <= tol_act || fb == 0.0f64 { ret b }
        if lt.fabs(prev_step) >= tol_act && lt.fabs(fa) > lt.fabs(fb) {
            let cbv = c - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cbv * t1
                qq = 1.0f64 - t1
            } else {
                qq = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cbv * qq * (qq - t1) - (b - a) * (t1 - 1.0f64))
                qq = (qq - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 {
                qq = 0.0f64 - qq
            } else {
                pp = 0.0f64 - pp
            }
            if pp < (0.75f64 * cbv * qq - lt.fabs(tol_act * qq) / 2.0f64) && pp < lt.fabs(prev_step * qq / 2.0f64) { new_step = pp / qq }
        }
        if lt.fabs(new_step) < tol_act {
            if new_step > 0.0f64 {
                new_step = tol_act
            } else {
                new_step = 0.0f64 - tol_act
            }
        }
        a = b
        fa = fb
        b = b + new_step
        fb = ca - b * cb
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

// ghq(10) with modify = TRUE: nodes and weights * exp(node^2), by Newton on the orthonormal Hermite recurrence
fn lm_ghq10(nodes: []f64, wts: []f64) {
    let n = 10usize
    let pim4 = 0.7511255444649425f64
    var i = 0usize
    var z = 0.0f64
    var z1 = 0.0f64
    var pp = 0.0f64
    while i < 5usize {
        if i == 0usize {
            z = math.sqrt[f64](2.0f64 * f64(n) + 1.0f64) - 1.85575f64 * math.pow[f64](2.0f64 * f64(n) + 1.0f64, 0.0f64 - 1.0f64 / 6.0f64)
        } else if i == 1usize {
            z = z - 1.14f64 * math.pow[f64](f64(n), 0.426f64) / z
        } else if i == 2usize {
            z = 1.86f64 * z - 0.86f64 * nodes[0usize]
        } else if i == 3usize {
            z = 1.91f64 * z - 0.91f64 * nodes[1usize]
        } else {
            z = 2.0f64 * z - nodes[2usize]
        }
        var its = 0usize
        var done = false
        while its < 100usize && !done {
            var p1 = pim4
            var p2 = 0.0f64
            var j = 1usize
            while j <= n {
                let p3 = p2
                p2 = p1
                p1 = z * math.sqrt[f64](2.0f64 / f64(j)) * p2 - math.sqrt[f64](f64(j - 1usize) / f64(j)) * p3
                j += 1usize
            }
            pp = math.sqrt[f64](2.0f64 * f64(n)) * p2
            z1 = z
            z = z1 - p1 / pp
            if lt.fabs(z - z1) <= 1.0e-15f64 { done = true }
            its += 1usize
        }
        nodes[i] = z
        nodes[n - 1usize - i] = 0.0f64 - z
        let w = 2.0f64 / (pp * pp)
        wts[i] = w
        wts[n - 1usize - i] = w
        i += 1usize
    }
    i = 0usize
    while i < n {
        wts[i] = wts[i] * math.exp[f64](nodes[i] * nodes[i])
        i += 1usize
    }
}

fn lm_hat(a: *mem.Arena, x: []const f64, w: []const f64, n: usize, p: usize, h: []f64) -> err {
    let (xw, e0) = mem.alloc[f64](a, n * p)
    let (ev, e1) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            xw[j * n + i] = x[j * n + i] * math.sqrt[f64](w[i])
            i += 1usize
        }
        j += 1usize
    }
    let (q, qe) = rb.dqrdc2_blue(a, xw, n, p, 1.0e-7f64)
    if qe != ok { ret qe }
    var i = 0usize
    while i < n {
        h[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            ev[i] = 0.0f64
            i += 1usize
        }
        ev[j] = 1.0f64
        dc.qr_qy(&q, ev)
        i = 0usize
        while i < n {
            h[i] = h[i] + ev[i] * ev[i]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        if h[i] > 1.0f64 { h[i] = 1.0f64 }
        i += 1usize
    }
    ret ok
}

// lmrob(method = "MM", psi = "bisquare") or lmrob(method = "SMDM", psi = "lqq") with the default control (nResample 500, best.r.s 2, k.fast.s 1, k.max 200, refine.tol 1e-7, rel.tol 1e-7,
// scale.tol 1e-10, solve.tol 1e-7, zero.tol 1e-10, mts 1000, max.it 50, numpoints 10). The lqq constants are the package's tabulated ones for the default tuning.
// out = S coefficients (p), S scale, final coefficients (p), final scale, last M iterations, S converged, last M converged, final residuals (n), final robustness weights (n),
//       then for SMDM only: kappa, D scale, D converged, first M coefficients (p)
fn lmrob_fit(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, p: usize, nres: usize, smdm: bool, out: []f64) -> err {
    var chi = Psi { kind: 1usize, c0: 1.54764f64, c1: 0.0f64, c2: 0.0f64 }
    var psi = Psi { kind: 1usize, c0: 4.685061f64, c1: 0.0f64, c2: 0.0f64 }
    if smdm {
        chi = Psi { kind: 6usize, c0: 0.4015457f64, c1: 0.2676971f64, c2: 1.5f64 }
        psi = Psi { kind: 6usize, c0: 1.4734061f64, c1: 0.9822707f64, c2: 1.5f64 }
    }
    let (bs, e0) = mem.alloc[f64](a, p)
    if e0 != ok { ret e0 }
    let (sc, sconv, fe) = lm_fast_s(a, g, x, y, n, p, nres, chi, 0.5f64, 2usize, 200usize, 1usize, 1.0e-7f64, 1.0e-7f64, 1.0e-10f64, 1.0e-10f64, 200usize, 1000usize, bs)
    if fe != ok { ret fe }
    if sc <= 0.0f64 { ret LmrobFail }
    var j = 0usize
    while j < p {
        out[j] = bs[j]
        j += 1usize
    }
    out[p] = sc
    let bm = out[p + 1usize..2usize * p + 1usize]
    let rs = out[2usize * p + 5usize..2usize * p + 5usize + n]
    let (cv, it, me) = lm_rwls(a, x, y, n, p, bm, bs, rs, sc, 1.0e-7f64, 50usize, psi)
    if me != ok { ret me }
    out[2usize * p + 1usize] = sc
    out[2usize * p + 2usize] = f64(it)
    out[2usize * p + 3usize] = 0.0f64
    if sconv { out[2usize * p + 3usize] = 1.0f64 }
    out[2usize * p + 4usize] = 0.0f64
    if cv { out[2usize * p + 4usize] = 1.0f64 }
    var final_scale = sc
    let base = 2usize * p + 5usize + 2usize * n
    if smdm {
        let (wr, e1) = mem.alloc[f64](a, n)
        let (hh, e2) = mem.alloc[f64](a, n)
        let (nodes, e3) = mem.alloc[f64](a, 10usize)
        let (gw, e4) = mem.alloc[f64](a, 10usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
        var i = 0usize
        while i < n {
            wr[i] = lm_wgt(rs[i] / sc, psi)
            i += 1usize
        }
        let he = lm_hat(a, x, wr, n, p, hh)
        if he != ok { ret he }
        // kappa: the root of E[psi(r) r - kappa wgt(r)] by 10-point Gauss-Hermite, uniroot on c(0.1, 1)
        lm_ghq10(nodes, gw)
        var ca = 0.0f64
        var cb = 0.0f64
        i = 0usize
        while i < 10usize {
            let dn = dist.dnorm(nodes[i], 0.0f64, 1.0f64, false)
            ca = ca + gw[i] * (lm_psi(nodes[i], psi) * nodes[i]) * dn
            cb = cb + gw[i] * lm_wgt(nodes[i], psi) * dn
            i += 1usize
        }
        let kappa = lm_zeroin(ca, cb, 0.1f64, 1.0f64, 1.220703125e-4f64)
        // tau (the fast approximation) and the D scale
        let tfact = 0.94736359f64
        let tcorr = 0.0f64 - 0.08594805f64
        let (tau, e5) = mem.alloc[f64](a, n)
        if e5 != ok { ret e5 }
        var s1 = 0.0f64
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            tau[i] = math.sqrt[f64](1.0f64 - tfact * hh[i]) * (tcorr * hh[i] + 1.0f64)
            s1 = s1 + wr[i] * rs[i] * rs[i]
            s2 = s2 + tau[i] * tau[i] * wr[i]
            i += 1usize
        }
        var ds = math.sqrt[f64](s1 / kappa / s2)
        var dconv = false
        var k = 0usize
        while k < 200usize && !dconv {
            let scale = ds
            var t1 = 0.0f64
            var t2 = 0.0f64
            i = 0usize
            while i < n {
                let w = lm_wgt(rs[i] / tau[i] / scale, psi)
                t1 = t1 + rs[i] * rs[i] * w
                t2 = t2 + w * tau[i] * tau[i]
                i += 1usize
            }
            ds = math.sqrt[f64](t1 / t2 / kappa)
            var mx = 1.0e-7f64
            if scale > mx { mx = scale }
            if lt.fabs(scale - ds) < 1.0e-7f64 * mx { dconv = true }
            k += 1usize
        }
        out[base] = kappa
        out[base + 1usize] = ds
        out[base + 2usize] = 0.0f64
        if dconv { out[base + 2usize] = 1.0f64 }
        j = 0usize
        while j < p {
            out[base + 3usize + j] = bm[j]
            j += 1usize
        }
        if !dconv { ret LmrobFail }
        // the final M step from the first M estimate with the D scale
        let (b0, e6) = mem.alloc[f64](a, p)
        if e6 != ok { ret e6 }
        j = 0usize
        while j < p {
            b0[j] = bm[j]
            j += 1usize
        }
        let (cv2, it2, me2) = lm_rwls(a, x, y, n, p, bm, b0, rs, ds, 1.0e-7f64, 50usize, psi)
        if me2 != ok { ret me2 }
        out[2usize * p + 1usize] = ds
        out[2usize * p + 2usize] = f64(it2)
        out[2usize * p + 4usize] = 0.0f64
        if cv2 { out[2usize * p + 4usize] = 1.0f64 }
        final_scale = ds
    }
    var i2 = 0usize
    while i2 < n {
        out[2usize * p + 5usize + n + i2] = lm_wgt(rs[i2] / final_scale, psi)
        i2 += 1usize
    }
    ret ok
}
