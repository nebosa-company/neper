// R mice's chained-equations sampler for the normal linear methods norm.nob, norm and norm.predict on numeric data
// (every other column predicts, the visit sequence the column order), value for value with R after set.seed: the
// initial draws by `sample` from the observed values (column by column, imputation by imputation), then for each
// iteration and imputation the columns in turn with the current values of the others, the regression of mice's
// estimice (its (X'X)^-1 and residuals), the chi-square and normal draws of `.norm.draw`, and the normal noise.
//
// Not here: pmm, logistic and the other methods, factors, a predictor matrix, passive imputation, post-processing, a
// near-collinearity (remove.lindep) beyond reporting it by an error.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.ica as ica
use e.math
use e.mem

error Collinear

// the inverse of the symmetric positive definite q by q matrix a (row-major) into inv by Cholesky; false when not positive definite
fn spd_inverse(a: []const f64, q: usize, inv: []f64, l: []f64) -> bool {
    var i = 0usize
    while i < q {
        var j = 0usize
        while j <= i {
            var s = a[i * q + j]
            var k = 0usize
            while k < j {
                s -= l[i * q + k] * l[j * q + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret false }
                l[i * q + i] = math.sqrt[f64](s)
            } else {
                l[i * q + j] = s / l[j * q + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    // inverse columns by forward and back substitution
    var c = 0usize
    while c < q {
        var y: [32]f64 = zero
        i = 0usize
        while i < q {
            var s = 0.0f64
            if i == c { s = 1.0f64 }
            var k = 0usize
            while k < i {
                s -= l[i * q + k] * y[k]
                k += 1usize
            }
            y[i] = s / l[i * q + i]
            i += 1usize
        }
        i = q
        while i > 0usize {
            i -= 1usize
            var s = y[i]
            var k = i + 1usize
            while k < q {
                s -= l[k * q + i] * inv[k * q + c]
                k += 1usize
            }
            inv[i * q + c] = s / l[i * q + i]
        }
        c += 1usize
    }
    ret true
}

// mice(data, m, maxit, method = "norm.nob" (0), "norm" (1) or "norm.predict" (2), seed): data is n by p column-major with NaN for missing; imp receives, for each column with missing values in order and each imputation, the imputed values of its missing rows in row order (imp must hold sum of nmis * m values)
fn mice_norm(a: *mem.Arena, data0: []const f64, n: usize, p: usize, m: usize, maxit: usize, method: usize, seed: i64, imp: []f64) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    let (data, e0) = mem.alloc[f64](a, n * p)
    let (nmis, e1) = mem.alloc[usize](a, p)
    let (off, e2) = mem.alloc[usize](a, p)
    let (x, e3) = mem.alloc[f64](a, n * p)
    let (xtx, e4) = mem.alloc[f64](a, p * p)
    let (inv, e5) = mem.alloc[f64](a, p * p)
    let (lw, e6) = mem.alloc[f64](a, p * p)
    let (xty, e7) = mem.alloc[f64](a, p)
    let (beta, e8) = mem.alloc[f64](a, p)
    let (bs, e9) = mem.alloc[f64](a, p)
    let (zz, e10) = mem.alloc[f64](a, p)
    let (yobs, e11) = mem.alloc[f64](a, n)
    let (keepf, e12) = mem.alloc[bool](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret mem.Full }
    var tot = 0usize
    var j = 0usize
    while j < p {
        nmis[j] = 0usize
        var i = 0usize
        while i < n {
            data[j * n + i] = data0[j * n + i]
            if data0[j * n + i] != data0[j * n + i] { nmis[j] += 1usize }
            i += 1usize
        }
        off[j] = tot
        if nmis[j] > 0usize && nmis[j] < n { tot += nmis[j] * m } else { nmis[j] = 0usize }
        j += 1usize
    }
    if imp.len < tot { ret mem.Full }
    // the initial draws: sample the observed values with replacement
    j = 0usize
    while j < p {
        if nmis[j] > 0usize {
            var no = 0usize
            var i = 0usize
            while i < n {
                if data0[j * n + i] == data0[j * n + i] {
                    yobs[no] = data0[j * n + i]
                    no += 1usize
                }
                i += 1usize
            }
            var im = 0usize
            while im < m {
                let (idx, es) = rng.sample_int(a, &r, i64(no), i64(nmis[j]), true)
                if es != ok { ret es }
                var q = 0usize
                while q < nmis[j] {
                    imp[off[j] + im * nmis[j] + q] = yobs[usize(idx[q]) - 1usize]
                    q += 1usize
                }
                im += 1usize
            }
        }
        j += 1usize
    }
    var k = 0usize
    while k < maxit {
        var im = 0usize
        while im < m {
            // the current imputations into the data
            j = 0usize
            while j < p {
                if nmis[j] > 0usize {
                    var q = 0usize
                    var i = 0usize
                    while i < n {
                        if data0[j * n + i] != data0[j * n + i] {
                            data[j * n + i] = imp[off[j] + im * nmis[j] + q]
                            q += 1usize
                        }
                        i += 1usize
                    }
                }
                j += 1usize
            }
            j = 0usize
            while j < p {
                if nmis[j] > 0usize {
                    // remove.lindep: a predictor stays when its variance among the observed rows exceeds 1e-4 and its correlation with y is below 0.99
                    var nobs0 = 0usize
                    var ym = 0.0f64
                    var i = 0usize
                    while i < n {
                        if data0[j * n + i] == data0[j * n + i] {
                            nobs0 += 1usize
                            ym += data0[j * n + i]
                        }
                        i += 1usize
                    }
                    ym = ym / f64(nobs0)
                    var yv = 0.0f64
                    i = 0usize
                    while i < n {
                        if data0[j * n + i] == data0[j * n + i] { yv += (data0[j * n + i] - ym) * (data0[j * n + i] - ym) }
                        i += 1usize
                    }
                    var ykeep = yv / f64(nobs0 - 1usize) >= 1.0e-4f64
                    var nkeep = 0usize
                    var jk = 0usize
                    while jk < p {
                        keepf[jk] = false
                        if jk != j && ykeep {
                            var xm = 0.0f64
                            i = 0usize
                            while i < n {
                                if data0[j * n + i] == data0[j * n + i] { xm += data[jk * n + i] }
                                i += 1usize
                            }
                            xm = xm / f64(nobs0)
                            var xv = 0.0f64
                            var xy = 0.0f64
                            i = 0usize
                            while i < n {
                                if data0[j * n + i] == data0[j * n + i] {
                                    xv += (data[jk * n + i] - xm) * (data[jk * n + i] - xm)
                                    xy += (data[jk * n + i] - xm) * (data0[j * n + i] - ym)
                                }
                                i += 1usize
                            }
                            let cr = xy / math.sqrt[f64](xv * yv)
                            if xv / f64(nobs0 - 1usize) > 1.0e-4f64 && cr < 0.99f64 {
                                keepf[jk] = true
                                nkeep += 1usize
                            }
                        }
                        jk += 1usize
                    }
                    if nkeep > 1usize {
                        // the eigenvalue condition of remove.lindep on the correlation matrix of the kept predictors
                        var ks: [8]usize = zero
                        var kq = 0usize
                        jk = 0usize
                        while jk < p {
                            if keepf[jk] {
                                ks[kq] = jk
                                kq += 1usize
                            }
                            jk += 1usize
                        }
                        let (cm, ecm) = mem.alloc[f64](a, kq * kq)
                        if ecm != ok { ret ecm }
                        var u1 = 0usize
                        while u1 < kq {
                            var u2 = 0usize
                            while u2 < kq {
                                var mu1 = 0.0f64
                                var mu2 = 0.0f64
                                i = 0usize
                                while i < n {
                                    if data0[j * n + i] == data0[j * n + i] {
                                        mu1 += data[ks[u1] * n + i]
                                        mu2 += data[ks[u2] * n + i]
                                    }
                                    i += 1usize
                                }
                                mu1 = mu1 / f64(nobs0)
                                mu2 = mu2 / f64(nobs0)
                                var s12 = 0.0f64
                                var s11 = 0.0f64
                                var s22 = 0.0f64
                                i = 0usize
                                while i < n {
                                    if data0[j * n + i] == data0[j * n + i] {
                                        s12 += (data[ks[u1] * n + i] - mu1) * (data[ks[u2] * n + i] - mu2)
                                        s11 += (data[ks[u1] * n + i] - mu1) * (data[ks[u1] * n + i] - mu1)
                                        s22 += (data[ks[u2] * n + i] - mu2) * (data[ks[u2] * n + i] - mu2)
                                    }
                                    i += 1usize
                                }
                                cm[u1 * kq + u2] = s12 / math.sqrt[f64](s11 * s22)
                                u2 += 1usize
                            }
                            u1 += 1usize
                        }
                        let (ev, evec, eee) = ica.eigen_sym(a, cm, kq)
                        if eee != ok { ret eee }
                        var emin = ev[0usize]
                        var emax = ev[0usize]
                        u1 = 1usize
                        while u1 < kq {
                            if ev[u1] < emin { emin = ev[u1] }
                            if ev[u1] > emax { emax = ev[u1] }
                            u1 += 1usize
                        }
                        if emin / emax < 1.0e-4f64 { ret Collinear }
                    }
                    // the design: an intercept and the kept columns (cd = number of columns of x1)
                    let cd = nkeep + 1usize
                    var cc = 1usize
                    i = 0usize
                    while i < n {
                        x[i] = 1.0f64
                        i += 1usize
                    }
                    var jj = 0usize
                    while jj < p {
                        if keepf[jj] {
                            i = 0usize
                            while i < n {
                                x[cc * n + i] = data[jj * n + i]
                                i += 1usize
                            }
                            cc += 1usize
                        }
                        jj += 1usize
                    }
                    // the fit on the rows observed in y
                    var s1 = 0usize
                    while s1 < cd {
                        xty[s1] = 0.0f64
                        var s2 = 0usize
                        while s2 < cd {
                            xtx[s1 * cd + s2] = 0.0f64
                            s2 += 1usize
                        }
                        s1 += 1usize
                    }
                    var nobs = 0usize
                    i = 0usize
                    while i < n {
                        if data0[j * n + i] == data0[j * n + i] {
                            nobs += 1usize
                            s1 = 0usize
                            while s1 < cd {
                                xty[s1] += x[s1 * n + i] * data0[j * n + i]
                                var s2 = 0usize
                                while s2 < cd {
                                    xtx[s1 * cd + s2] += x[s1 * n + i] * x[s2 * n + i]
                                    s2 += 1usize
                                }
                                s1 += 1usize
                            }
                        }
                        i += 1usize
                    }
                    if !spd_inverse(xtx, cd, inv, lw) { ret Collinear }
                    s1 = 0usize
                    while s1 < cd {
                        var s = 0.0f64
                        var s2 = 0usize
                        while s2 < cd {
                            s += inv[s1 * cd + s2] * xty[s2]
                            s2 += 1usize
                        }
                        beta[s1] = s
                        s1 += 1usize
                    }
                    var rss = 0.0f64
                    i = 0usize
                    while i < n {
                        if data0[j * n + i] == data0[j * n + i] {
                            var f = 0.0f64
                            s1 = 0usize
                            while s1 < cd {
                                f += x[s1 * n + i] * beta[s1]
                                s1 += 1usize
                            }
                            let rr = data0[j * n + i] - f
                            rss += rr * rr
                        }
                        i += 1usize
                    }
                    var sigma = math.sqrt[f64](rss / f64(nobs - cd - 1usize))
                    if nobs <= cd + 1usize { ret Collinear }
                    var use_beta = beta
                    if method == 1usize || method == 3usize {
                        var dfv = nobs - cd
                        if nobs <= cd { dfv = 1usize }
                        sigma = math.sqrt[f64](rss / rd.rchisq(&r, f64(dfv)))
                        // lower Cholesky factor of (X'X)^-1 times normal draws
                        var lv = lw
                        var ok2 = true
                        s1 = 0usize
                        while s1 < cd {
                            var s2 = 0usize
                            while s2 <= s1 {
                                var s = inv[s1 * cd + s2]
                                var q2 = 0usize
                                while q2 < s2 {
                                    s -= lv[s1 * cd + q2] * lv[s2 * cd + q2]
                                    q2 += 1usize
                                }
                                if s1 == s2 {
                                    if s <= 0.0f64 { ok2 = false }
                                    lv[s1 * cd + s1] = math.sqrt[f64](s)
                                } else {
                                    lv[s1 * cd + s2] = s / lv[s2 * cd + s2]
                                }
                                s2 += 1usize
                            }
                            s1 += 1usize
                        }
                        if !ok2 { ret Collinear }
                        s1 = 0usize
                        while s1 < cd {
                            zz[s1] = rng.norm(&r)
                            s1 += 1usize
                        }
                        s1 = 0usize
                        while s1 < cd {
                            var s = 0.0f64
                            var s2 = 0usize
                            while s2 <= s1 {
                                s += lv[s1 * cd + s2] * zz[s2]
                                s2 += 1usize
                            }
                            bs[s1] = beta[s1] + s * sigma
                            s1 += 1usize
                        }
                        use_beta = bs
                    }
                    if method == 3usize {
                        let nm = nmis[j]
                        let (dob, ed1) = mem.alloc[f64](a, nobs)
                        let (tmv, ed2) = mem.alloc[f64](a, nm)
                        let (yo, ed3) = mem.alloc[f64](a, nobs)
                        if ed1 != ok || ed2 != ok || ed3 != ok { ret mem.Full }
                        var qo = 0usize
                        var qm = 0usize
                        i = 0usize
                        while i < n {
                            var fb = 0.0f64
                            var fu = 0.0f64
                            s1 = 0usize
                            while s1 < cd {
                                fb += x[s1 * n + i] * beta[s1]
                                fu += x[s1 * n + i] * use_beta[s1]
                                s1 += 1usize
                            }
                            if data0[j * n + i] == data0[j * n + i] {
                                dob[qo] = fb
                                yo[qo] = data0[j * n + i]
                                qo += 1usize
                            } else {
                                tmv[qm] = fu
                                qm += 1usize
                            }
                            i += 1usize
                        }
                        let (mi, emi) = matchindex(a, &r, dob, tmv, 5usize)
                        if emi != ok { ret emi }
                        qm = 0usize
                        i = 0usize
                        while i < n {
                            if data0[j * n + i] != data0[j * n + i] {
                                let f = yo[mi[qm]]
                                imp[off[j] + im * nmis[j] + qm] = f
                                data[j * n + i] = f
                                qm += 1usize
                            }
                            i += 1usize
                        }
                    } else {
                    var q = 0usize
                    i = 0usize
                    while i < n {
                        if data0[j * n + i] != data0[j * n + i] {
                            var f = 0.0f64
                            s1 = 0usize
                            while s1 < cd {
                                f += x[s1 * n + i] * use_beta[s1]
                                s1 += 1usize
                            }
                            if method != 2usize { f += rng.norm(&r) * sigma }
                            imp[off[j] + im * nmis[j] + q] = f
                            data[j * n + i] = f
                            q += 1usize
                        }
                        i += 1usize
                    }
                    }
                }
                j += 1usize
            }
            im += 1usize
        }
        k += 1usize
    }
    ret ok
}

// mice's matchindex: the 0-based index in d of a donor drawn among the k nearest to each target (ties shuffled by a permutation of the donors, then a pre-drawn rank in 1..k per target)
fn matchindex(a: *mem.Arena, r: *rng.Rng, d: []const f64, tv: []const f64, k0: usize) -> ([]usize, err) {
    var none: []usize = zero
    let n1 = d.len
    let n0 = tv.len
    let (ish, e1) = rng.sample_int(a, r, i64(n1), i64(n1), false)
    if e1 != ok { ret (none, e1) }
    let (srt, e2) = mem.alloc[usize](a, n1)
    let (id, e3) = mem.alloc[usize](a, n1)
    let (ys, e4) = mem.alloc[f64](a, n1)
    let (idx, e5) = mem.alloc[usize](a, n0)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (none, mem.Full) }
    var i = 0usize
    while i < n1 {
        srt[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n1 {
        let ti = srt[i]
        let tvv = d[usize(ish[ti]) - 1usize]
        var j = i
        while j > 0usize && d[usize(ish[srt[j - 1usize]]) - 1usize] > tvv {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = ti
        i += 1usize
    }
    i = 0usize
    while i < n1 {
        id[i] = usize(ish[srt[i]]) - 1usize
        ys[i] = d[id[i]]
        i += 1usize
    }
    var k = k0
    if k > n1 { k = n1 }
    if k < 1usize { k = 1usize }
    let (h, e6) = rng.sample_int(a, r, i64(k), i64(n0), true)
    if e6 != ok { ret (none, e6) }
    i = 0usize
    while i < n0 {
        let val = tv[i]
        let hi = usize(h[i])
        var count = 0usize
        var lo = 0usize
        var hi2 = n1
        while lo < hi2 {
            let mid = (lo + hi2) / 2usize
            if ys[mid] < val { lo = mid + 1usize } else { hi2 = mid }
        }
        var rr = lo
        var ll = i64(lo) - 1i64
        var res = 0usize
        while count < hi && ll >= 0i64 && rr < n1 {
            if val - ys[usize(ll)] < ys[rr] - val {
                res = id[usize(ll)]
                ll -= 1i64
            } else {
                res = id[rr]
                rr += 1usize
            }
            count += 1usize
        }
        while count < hi && ll >= 0i64 {
            res = id[usize(ll)]
            ll -= 1i64
            count += 1usize
        }
        while count < hi && rr < n1 {
            res = id[rr]
            rr += 1usize
            count += 1usize
        }
        idx[i] = res
        i += 1usize
    }
    ret (idx, ok)
}
