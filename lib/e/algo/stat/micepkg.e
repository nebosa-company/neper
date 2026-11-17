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
fn mice_norm(a: *mem.Arena, data0: []const f64, n: usize, p: usize, m: usize, maxit: usize, method: usize, seed: i64, imp: []f64, pred: []const f64, visit: []const f64) -> err {
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
    var v0 = 0usize
    var nv0 = p
    if visit.len > 0usize { nv0 = visit.len }
    while v0 < nv0 {
        j = v0
        if visit.len > 0usize { j = usize(visit[v0]) }
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
        v0 += 1usize
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
            var vi = 0usize
            var nv = p
            if visit.len > 0usize { nv = visit.len }
            while vi < nv {
                j = vi
                if visit.len > 0usize { j = usize(visit[vi]) }
                if nmis[j] > 0usize {
                    var mj = method
                    if (method == 4usize || method == 6usize) && j > 0usize { mj = 0usize }
                    if method == 7usize || method == 8usize {
                        // mice.impute.mean (the observed mean) and mice.impute.sample (a draw with replacement of the observed values)
                        let (yo, eyo) = mem.alloc[f64](a, n)
                        if eyo != ok { ret eyo }
                        var no = 0usize
                        var sm = 0.0f64
                        var i0 = 0usize
                        while i0 < n {
                            if data0[j * n + i0] == data0[j * n + i0] {
                                yo[no] = data0[j * n + i0]
                                sm += yo[no]
                                no += 1usize
                            }
                            i0 += 1usize
                        }
                        var sidx: []i64 = zero
                        if method == 8usize {
                            let (ix, eix) = rng.sample_int(a, &r, i64(no), i64(nmis[j]), true)
                            if eix != ok { ret eix }
                            sidx = ix
                        }
                        var q0 = 0usize
                        i0 = 0usize
                        while i0 < n {
                            if data0[j * n + i0] != data0[j * n + i0] {
                                var f0 = sm / f64(no)
                                if method == 8usize { f0 = yo[usize(sidx[q0]) - 1usize] }
                                imp[off[j] + im * nmis[j] + q0] = f0
                                data[j * n + i0] = f0
                                q0 += 1usize
                            }
                            i0 += 1usize
                        }
                        vi += 1usize
                        continue
                    }
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
                        if jk != j && ykeep && (pred.len == 0usize || pred[j * p + jk] != 0.0f64) {
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
                    if mj == 4usize || mj == 6usize {
                        let (ob, eob) = mem.alloc[f64](a, nmis[j] + 1usize)
                        if eob != ok { ret eob }
                        let le = logreg_draw(a, &r, x[0usize..cd * n], cd, n, data0[j * n..j * n + n], ob, mj == 6usize)
                        if le != ok { ret le }
                        var qb = 0usize
                        i = 0usize
                        while i < n {
                            if data0[j * n + i] != data0[j * n + i] {
                                imp[off[j] + im * nmis[j] + qb] = ob[qb]
                                data[j * n + i] = ob[qb]
                                qb += 1usize
                            }
                            i += 1usize
                        }
                    } else {
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
                    let (cnt, ecn) = mem.alloc[f64](a, n)
                    if ecn != ok { ret ecn }
                    i = 0usize
                    while i < n {
                        cnt[i] = 1.0f64
                        i += 1usize
                    }
                    if mj == 5usize {
                        var no1 = 0usize
                        i = 0usize
                        while i < n {
                            cnt[i] = 0.0f64
                            if data0[j * n + i] == data0[j * n + i] { no1 += 1usize }
                            i += 1usize
                        }
                        let (bi, ebi) = rng.sample_int(a, &r, i64(no1), i64(no1), true)
                        if ebi != ok { ret ebi }
                        var qb2 = 0usize
                        var ord = 0usize
                        // the h-th observed row (1-based) gets one count per time it was drawn
                        while qb2 < no1 {
                            var rowi = 0usize
                            ord = 0usize
                            while rowi < n {
                                if data0[j * n + rowi] == data0[j * n + rowi] {
                                    ord += 1usize
                                    if ord == usize(bi[qb2]) { cnt[rowi] += 1.0f64 }
                                }
                                rowi += 1usize
                            }
                            qb2 += 1usize
                        }
                    }
                    i = 0usize
                    while i < n {
                        if data0[j * n + i] == data0[j * n + i] {
                            nobs += usize(cnt[i])
                            s1 = 0usize
                            while s1 < cd {
                                xty[s1] += cnt[i] * x[s1 * n + i] * data0[j * n + i]
                                var s2 = 0usize
                                while s2 < cd {
                                    xtx[s1 * cd + s2] += cnt[i] * x[s1 * n + i] * x[s2 * n + i]
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
                            rss += cnt[i] * rr * rr
                        }
                        i += 1usize
                    }
                    var sigma = math.sqrt[f64](rss / f64(nobs - cd - 1usize))
                    if nobs <= cd + 1usize { ret Collinear }
                    var use_beta = beta
                    if mj == 1usize || mj == 3usize {
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
                    if mj == 3usize {
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
                            if mj != 2usize { f += rng.norm(&r) * sigma }
                            imp[off[j] + im * nmis[j] + q] = f
                            data[j * n + i] = f
                            q += 1usize
                        }
                        i += 1usize
                    }
                    }
                    }
                }
                vi += 1usize
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

// mice.impute.logreg: x is n by cd column-major with the intercept in column 0 and the kept predictors after it, y the 0/1 column with NaN for the missing; the n_mis imputed 0/1 values go to out in row order. The design is augmented as mice's `augment` does (4 p rows near the data means), glm.fit's iteratively reweighted fit of the logit with weights, the coefficient draw through the lower Cholesky factor of the unscaled covariance, then uniform draws against the fitted probabilities.
fn logreg_draw(a: *mem.Arena, r: *rng.Rng, x: []const f64, cd: usize, n: usize, y: []const f64, out: []f64, boot: bool) -> err {
    let p = cd - 1usize
    var nr = 4usize * p
    if boot { nr = 0usize }
    let na = n + nr
    let (xa, e1) = mem.alloc[f64](a, na * cd)
    let (ya, e2) = mem.alloc[f64](a, na)
    let (wa, e3) = mem.alloc[f64](a, na)
    let (mean, e4) = mem.alloc[f64](a, p)
    let (sd, e5) = mem.alloc[f64](a, p)
    let (mn, e6) = mem.alloc[f64](a, p)
    let (mx, e7) = mem.alloc[f64](a, p)
    let (ro, e8) = mem.alloc[usize](a, na)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var c = 0usize
    while c < p {
        var s = 0.0f64
        var i = 0usize
        mn[c] = x[(c + 1usize) * n]
        mx[c] = x[(c + 1usize) * n]
        while i < n {
            let v = x[(c + 1usize) * n + i]
            s += v
            if v < mn[c] { mn[c] = v }
            if v > mx[c] { mx[c] = v }
            i += 1usize
        }
        mean[c] = s / f64(n)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            let v = x[(c + 1usize) * n + i] - mean[c]
            ss += v * v
            i += 1usize
        }
        sd[c] = math.sqrt[f64](ss / f64(n - 1usize))
        c += 1usize
    }
    // the rows: the data, then the augmentation
    var i = 0usize
    while i < n {
        var cc = 0usize
        while cc < cd {
            xa[cc * na + i] = x[cc * n + i]
            cc += 1usize
        }
        ya[i] = y[i]
        wa[i] = 1.0f64
        i += 1usize
    }
    if boot {
        var no1 = 0usize
        i = 0usize
        while i < n {
            if y[i] == y[i] { no1 += 1usize }
            i += 1usize
        }
        let (bi, ebi) = rng.sample_int(a, r, i64(no1), i64(no1), true)
        if ebi != ok { ret ebi }
        let (obi, eob2) = mem.alloc[usize](a, no1)
        if eob2 != ok { ret eob2 }
        var qo = 0usize
        i = 0usize
        while i < n {
            if y[i] == y[i] {
                obi[qo] = i
                qo += 1usize
            }
            i += 1usize
        }
        qo = 0usize
        i = 0usize
        while i < n {
            if y[i] == y[i] {
                let src = obi[usize(bi[qo]) - 1usize]
                var cc2 = 0usize
                while cc2 < cd {
                    xa[cc2 * na + i] = x[cc2 * n + src]
                    cc2 += 1usize
                }
                ya[i] = y[src]
                qo += 1usize
            }
            i += 1usize
        }
    }
    let blen = 4usize + nr
    var rr = 0usize
    while rr < nr {
        xa[rr + n] = 1.0f64
        c = 0usize
        while c < p {
            let pos = (c * nr + rr) % blen
            var b = 0.0f64
            if pos == 0usize || pos == 2usize { b = 0.5f64 }
            if pos == 1usize || pos == 3usize { b = 0.0f64 - 0.5f64 }
            var dv = mean[c] + b * sd[c]
            if mn[c] > dv { dv = mn[c] }
            if mx[c] < dv { dv = mx[c] }
            xa[(c + 1usize) * na + n + rr] = dv
            c += 1usize
        }
        // e: the codes 1, 1, 2, 2 repeated, i.e. the class 0, 0, 1, 1
        var cls = 0.0f64
        if rr % 4usize >= 2usize { cls = 1.0f64 }
        ya[n + rr] = cls
        wa[n + rr] = f64(p + 1usize) / f64(nr)
        rr += 1usize
    }
    // the rows used: the observed y and all augmentation rows
    var no = 0usize
    i = 0usize
    while i < na {
        if ya[i] == ya[i] {
            ro[no] = i
            no += 1usize
        }
        i += 1usize
    }
    let (eta, e9) = mem.alloc[f64](a, no)
    let (xtx, e10) = mem.alloc[f64](a, cd * cd)
    let (xtz, e11) = mem.alloc[f64](a, cd)
    let (inv, e12) = mem.alloc[f64](a, cd * cd)
    let (lw, e13) = mem.alloc[f64](a, cd * cd)
    let (coef, e14) = mem.alloc[f64](a, cd)
    let (covu, e15) = mem.alloc[f64](a, cd * cd)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok { ret mem.Full }
    // start: mustart = (w y + 0.5) / (w + 1)
    var q = 0usize
    while q < no {
        let k = ro[q]
        let mu0 = (wa[k] * ya[k] + 0.5f64) / (wa[k] + 1.0f64)
        eta[q] = math.log[f64](mu0 / (1.0f64 - mu0))
        q += 1usize
    }
    var devold = 0.0f64
    q = 0usize
    while q < no {
        let k = ro[q]
        let mu = logit_inv(eta[q])
        devold += bin_dev(ya[k], mu, wa[k])
        q += 1usize
    }
    var iter = 0usize
    var go = true
    while go && iter < 25usize {
        iter += 1usize
        var s1 = 0usize
        while s1 < cd {
            xtz[s1] = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                xtx[s1 * cd + s2] = 0.0f64
                s2 += 1usize
            }
            s1 += 1usize
        }
        q = 0usize
        while q < no {
            let k = ro[q]
            let mu = logit_inv(eta[q])
            let me = logit_mu_eta(eta[q])
            let wq = wa[k] * me * me / (mu * (1.0f64 - mu))
            let z = eta[q] + (ya[k] - mu) / me
            s1 = 0usize
            while s1 < cd {
                xtz[s1] += wq * xa[s1 * na + k] * z
                var s2 = 0usize
                while s2 < cd {
                    xtx[s1 * cd + s2] += wq * xa[s1 * na + k] * xa[s2 * na + k]
                    s2 += 1usize
                }
                s1 += 1usize
            }
            q += 1usize
        }
        if !spd_inverse(xtx, cd, inv, lw) { ret Collinear }
        s1 = 0usize
        while s1 < cd {
            var s = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                s += inv[s1 * cd + s2] * xtz[s2]
                s2 += 1usize
            }
            coef[s1] = s
            covu[s1 * cd + 0usize] = inv[s1 * cd + 0usize]
            s1 += 1usize
        }
        s1 = 0usize
        while s1 < cd * cd {
            covu[s1] = inv[s1]
            s1 += 1usize
        }
        var dev = 0.0f64
        q = 0usize
        while q < no {
            let k = ro[q]
            var e = 0.0f64
            s1 = 0usize
            while s1 < cd {
                e += xa[s1 * na + k] * coef[s1]
                s1 += 1usize
            }
            eta[q] = e
            let mu = logit_inv(e)
            dev += bin_dev(ya[k], mu, wa[k])
            q += 1usize
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            go = false
        } else {
            devold = dev
        }
    }
    // lower Cholesky factor of the unscaled covariance, normal draws, then the uniforms
    var lv = lw
    var s1 = 0usize
    while !boot && s1 < cd {
        var s2 = 0usize
        while s2 <= s1 {
            var s = covu[s1 * cd + s2]
            var q2 = 0usize
            while q2 < s2 {
                s -= lv[s1 * cd + q2] * lv[s2 * cd + q2]
                q2 += 1usize
            }
            if s1 == s2 {
                if s <= 0.0f64 { ret Collinear }
                lv[s1 * cd + s1] = math.sqrt[f64](s)
            } else {
                lv[s1 * cd + s2] = s / lv[s2 * cd + s2]
            }
            s2 += 1usize
        }
        s1 += 1usize
    }
    let (zz, e16) = mem.alloc[f64](a, cd)
    let (bs, e17) = mem.alloc[f64](a, cd)
    if e16 != ok || e17 != ok { ret mem.Full }
    s1 = 0usize
    while s1 < cd {
        zz[s1] = 0.0f64
        if !boot { zz[s1] = rng.norm(r) }
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
        bs[s1] = coef[s1] + s
        s1 += 1usize
    }
    var qm = 0usize
    i = 0usize
    while i < n {
        if y[i] != y[i] {
            var e = 0.0f64
            s1 = 0usize
            while s1 < cd {
                e += x[s1 * n + i] * bs[s1]
                s1 += 1usize
            }
            let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e))
            out[qm] = 0.0f64
            if rng.unif(r) <= pr { out[qm] = 1.0f64 }
            qm += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn bin_dev(y: f64, mu: f64, w: f64) -> f64 {
    var t1 = 0.0f64
    if y > 0.0f64 { t1 = y * math.log[f64](y / mu) }
    var t2 = 0.0f64
    if y < 1.0f64 { t2 = (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
    ret 2.0f64 * w * (t1 + t2)
}

// mice::pool.scalar (Rubin 1987): out receives qbar, ubar, b, t, df, r and fmi for the m estimates q with variances u, a complete-data df of n - k (n infinite when not finite)
fn pool_scalar(q: []const f64, u: []const f64, n: f64, k: f64, out: []f64) {
    let m = q.len
    let mf = f64(m)
    var qb = 0.0f64
    var ub = 0.0f64
    var i = 0usize
    while i < m {
        qb += q[i]
        ub += u[i]
        i += 1usize
    }
    qb = qb / mf
    ub = ub / mf
    var b = 0.0f64
    i = 0usize
    while i < m {
        b += (q[i] - qb) * (q[i] - qb)
        i += 1usize
    }
    b = b / (mf - 1.0f64)
    let r = (1.0f64 + 1.0f64 / mf) * b / ub
    let t = ub + (mf + 1.0f64) * b / mf
    let lambda = (1.0f64 + 1.0f64 / mf) * b / t
    let dfold = (mf - 1.0f64) / (lambda * lambda)
    var df = dfold
    let dfcom = n - k
    if dfcom - dfcom == 0.0f64 {
        let tmp = (1.0f64 - lambda) * (1.0f64 + dfcom) * dfcom
        df = (mf - 1.0f64) * tmp / ((dfcom + 3.0f64) * (mf - 1.0f64) + lambda * lambda * tmp)
    }
    out[0usize] = qb
    out[1usize] = ub
    out[2usize] = b
    out[3usize] = t
    out[4usize] = df
    out[5usize] = r
    out[6usize] = (r + 2.0f64 / (df + 3.0f64)) / (r + 1.0f64)
}

// R's logit family: the linear predictor is clamped at +-30 (linkinv at DBL_EPSILON and its reciprocal, mu.eta at DBL_EPSILON)
fn logit_inv(eta: f64) -> f64 {
    var tmp = 0.0f64
    if eta < 0.0f64 - 30.0f64 {
        tmp = 2.220446049250313e-16f64
    } else if eta > 30.0f64 {
        tmp = 1.0f64 / 2.220446049250313e-16f64
    } else {
        tmp = math.exp[f64](eta)
    }
    ret tmp / (1.0f64 + tmp)
}

fn logit_mu_eta(eta: f64) -> f64 {
    if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret 2.220446049250313e-16f64 }
    let e = math.exp[f64](eta)
    ret e / ((1.0f64 + e) * (1.0f64 + e))
}
