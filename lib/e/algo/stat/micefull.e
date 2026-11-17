// R mice's chained-equations sampler for data frames with numeric and (unordered or ordered) factor columns, value for value with R after set.seed:
// the initial draws (mice.impute.sample per column and imputation in visit order), then for each iteration and imputation the visit sequence in
// order, each column through sampler.univ (the design the predictor matrix selects, factors as treatment dummies, the rows the predictors leave
// complete, remove.lindep) into the univariate method, then the post-processing bounds; passive columns are computed from the current data.
//
// Methods (the code in `meth`): 0 norm.nob, 1 norm, 2 norm.predict, 3 pmm, 4 logreg, 5 norm.boot, 6 logreg.boot, 7 mean, 8 sample, 10 cart, 11 polyreg,
// 12 polr, 15 none, and 20 for a passive column computed from columns a and b (pas[3 j] the kind: 0 a + b, 1 a * b, 2 a - b, 3 a / b, 4 a^2, then a and b).
// Factor columns hold the 1-based level code as a double (NaN missing) and `kind` the number of levels (0 for a numeric column); the levels sort
// alphabetically as R's as.factor does. The pooling of Rubin's rules over lm fits is at the end of the file.
//
// Not here: ordered factors as predictors (polynomial contrasts), pmm on a factor, the multilevel methods, formulas and blocks, `where` other than
// the missing cells, ignore, data.init, and the ridge fallback for a singular fit (the sampler stops with Collinear instead).

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.ica as ica
use e.algo.stat.micemodels as mm
use e.algo.stat.micepkg as mc
use e.algo.stat.rpartfit as rp
use e.math
use e.math.nmath_beta as nb
use e.mem

error Collinear
error NoImpute
error Unsupported

type Mi = struct {
    n: usize,
    p: usize,
    m: usize,
    d0: []const f64,
    d: []f64,
    kind: []const usize,
    meth: []const usize,
    pred: []const f64,
    lo: []const f64,
    hi: []const f64,
    pas: []const f64,
    nmis: []usize,
    off: []usize,
    imp: []f64,
    r: rng.Rng,
}

// the lower Cholesky factor of the symmetric positive definite q by q matrix c (row-major) into l; false when it is not positive definite
fn chol_lower(c: []const f64, q: usize, l: []f64) -> bool {
    var s1 = 0usize
    while s1 < q {
        var s2 = 0usize
        while s2 <= s1 {
            var s = c[s1 * q + s2]
            var k = 0usize
            while k < s2 {
                s -= l[s1 * q + k] * l[s2 * q + k]
                k += 1usize
            }
            if s1 == s2 {
                if s <= 0.0f64 { ret false }
                l[s1 * q + s1] = math.sqrt[f64](s)
            } else {
                l[s1 * q + s2] = s / l[s2 * q + s2]
            }
            s2 += 1usize
        }
        s1 += 1usize
    }
    ret true
}

// glm.fit(x, y, weights, quasibinomial()): x is n by cd column-major with the intercept, coef the coefficients and covu the unscaled covariance of the last iteration (row-major); the answer is whether it converged in 25 iterations
fn glm_logit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, cd: usize, coef: []f64, covu: []f64) -> (bool, err) {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (xtx, e2) = mem.alloc[f64](a, cd * cd)
    let (xtz, e3) = mem.alloc[f64](a, cd)
    let (lw, e4) = mem.alloc[f64](a, cd * cd)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (false, mem.Full) }
    var q = 0usize
    while q < n {
        let mu0 = (w[q] * y[q] + 0.5f64) / (w[q] + 1.0f64)
        eta[q] = math.log[f64](mu0 / (1.0f64 - mu0))
        q += 1usize
    }
    var devold = 0.0f64
    q = 0usize
    while q < n {
        devold += mc.bin_dev(y[q], mc.logit_inv(eta[q]), w[q])
        q += 1usize
    }
    var conv = false
    var iter = 0usize
    while !conv && iter < 25usize {
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
        while q < n {
            let mu = mc.logit_inv(eta[q])
            let me = mc.logit_mu_eta(eta[q])
            let wq = w[q] * me * me / (mu * (1.0f64 - mu))
            let z = eta[q] + (y[q] - mu) / me
            s1 = 0usize
            while s1 < cd {
                xtz[s1] += wq * x[s1 * n + q] * z
                var s2 = 0usize
                while s2 < cd {
                    xtx[s1 * cd + s2] += wq * x[s1 * n + q] * x[s2 * n + q]
                    s2 += 1usize
                }
                s1 += 1usize
            }
            q += 1usize
        }
        if !mc.spd_inverse(xtx, cd, covu, lw) { ret (false, Collinear) }
        s1 = 0usize
        while s1 < cd {
            var s = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                s += covu[s1 * cd + s2] * xtz[s2]
                s2 += 1usize
            }
            coef[s1] = s
            s1 += 1usize
        }
        var dev = 0.0f64
        q = 0usize
        while q < n {
            var e = 0.0f64
            s1 = 0usize
            while s1 < cd {
                e += x[s1 * n + q] * coef[s1]
                s1 += 1usize
            }
            eta[q] = e
            dev += mc.bin_dev(y[q], mc.logit_inv(e), w[q])
            q += 1usize
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            conv = true
        } else {
            devold = dev
        }
    }
    ret (conv, ok)
}

// ---- the design of one column's model

// the design columns the predictor row of column j selects, in column order: a numeric column as it is, a factor as its treatment dummies (levels 2 ..); returns the number of columns
fn mi_design(st: *Mi, j: usize, x: []f64) -> usize {
    let n = st.n
    var cd = 0usize
    var q = 0usize
    while q < st.p {
        if q != j && st.pred[j * st.p + q] != 0.0f64 {
            if st.kind[q] == 0usize {
                var i = 0usize
                while i < n {
                    x[cd * n + i] = st.d[q * n + i]
                    i += 1usize
                }
                cd += 1usize
            } else {
                var lev = 2usize
                while lev <= st.kind[q] {
                    var i = 0usize
                    while i < n {
                        let v = st.d[q * n + i]
                        if v != v {
                            x[cd * n + i] = v
                        } else if v == f64(lev) {
                            x[cd * n + i] = 1.0f64
                        } else {
                            x[cd * n + i] = 0.0f64
                        }
                        i += 1usize
                    }
                    cd += 1usize
                    lev += 1usize
                }
            }
        }
        q += 1usize
    }
    ret cd
}

// remove.lindep (eps 1e-4, maxcor 0.99) on the design x (n by cd) for the observed rows ro of the response y: keep[c] says whether column c stays; Collinear when the correlation matrix of the kept columns is near singular (R would log an event and drop a column)
fn mi_lindep(a: *mem.Arena, x: []const f64, cd: usize, n: usize, y: []const f64, ro: []const usize, keep: []bool) -> err {
    var c = 0usize
    while c < cd {
        keep[c] = false
        c += 1usize
    }
    let no = ro.len
    if no < 2usize { ret ok }
    let nof = f64(no)
    var ym = 0.0f64
    var t = 0usize
    while t < no {
        ym += y[ro[t]]
        t += 1usize
    }
    ym = ym / nof
    var yv = 0.0f64
    t = 0usize
    while t < no {
        yv += (y[ro[t]] - ym) * (y[ro[t]] - ym)
        t += 1usize
    }
    if yv / (nof - 1.0f64) < 1.0e-4f64 { ret ok }
    var nk = 0usize
    c = 0usize
    while c < cd {
        var xm = 0.0f64
        t = 0usize
        while t < no {
            xm += x[c * n + ro[t]]
            t += 1usize
        }
        xm = xm / nof
        var xv = 0.0f64
        var xy = 0.0f64
        t = 0usize
        while t < no {
            xv += (x[c * n + ro[t]] - xm) * (x[c * n + ro[t]] - xm)
            xy += (x[c * n + ro[t]] - xm) * (y[ro[t]] - ym)
            t += 1usize
        }
        let cr = xy / math.sqrt[f64](xv * yv)
        if xv / (nof - 1.0f64) > 1.0e-4f64 && cr < 0.99f64 {
            keep[c] = true
            nk += 1usize
        }
        c += 1usize
    }
    if nk > 1usize {
        let (ks, eks) = mem.alloc[usize](a, nk)
        let (cm, ecm) = mem.alloc[f64](a, nk * nk)
        if eks != ok || ecm != ok { ret mem.Full }
        var kq = 0usize
        c = 0usize
        while c < cd {
            if keep[c] {
                ks[kq] = c
                kq += 1usize
            }
            c += 1usize
        }
        var u1 = 0usize
        while u1 < kq {
            var u2 = 0usize
            while u2 < kq {
                var mu1 = 0.0f64
                var mu2 = 0.0f64
                t = 0usize
                while t < no {
                    mu1 += x[ks[u1] * n + ro[t]]
                    mu2 += x[ks[u2] * n + ro[t]]
                    t += 1usize
                }
                mu1 = mu1 / nof
                mu2 = mu2 / nof
                var s12 = 0.0f64
                var s11 = 0.0f64
                var s22 = 0.0f64
                t = 0usize
                while t < no {
                    s12 += (x[ks[u1] * n + ro[t]] - mu1) * (x[ks[u2] * n + ro[t]] - mu2)
                    s11 += (x[ks[u1] * n + ro[t]] - mu1) * (x[ks[u1] * n + ro[t]] - mu1)
                    s22 += (x[ks[u2] * n + ro[t]] - mu2) * (x[ks[u2] * n + ro[t]] - mu2)
                    t += 1usize
                }
                cm[u1 * kq + u2] = s12 / math.sqrt[f64](s11 * s22)
                u2 += 1usize
            }
            u1 += 1usize
        }
        let (ev, evec, eee) = ica.eigen_sym(a, cm, kq)
        if eee != ok { ret eee }
        let _ = evec
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
    ret ok
}

// ---- mice's augment (the 2 p k rows near the data that keep a categorical fit finite) for the rows ro of the n by nk design xk and the codes y

type Aug = struct { na: usize, xa: []f64, ya: []f64, wa: []f64 }

// the observed rows followed by the augmentation rows (none when there are no predictors, exactly one row is not observed, or aug is false); the class codes are the codes in y
fn mi_augment(a: *mem.Arena, xk: []const f64, nk: usize, n: usize, y: []const f64, ro: []const usize, aug: bool) -> (Aug, err) {
    var g: Aug = zero
    let no = ro.len
    // the distinct codes over all the rows of y
    let (uc, eu) = mem.alloc[f64](a, n + 1usize)
    if eu != ok { ret (g, eu) }
    var k = 0usize
    var i = 0usize
    while i < n {
        if y[i] == y[i] {
            var seen = false
            var q = 0usize
            while q < k {
                if uc[q] == y[i] { seen = true }
                q += 1usize
            }
            if !seen {
                uc[k] = y[i]
                k += 1usize
            }
        }
        i += 1usize
    }
    // sort the codes ascending
    i = 1usize
    while i < k {
        let t = uc[i]
        var q = i
        while q > 0usize && uc[q - 1usize] > t {
            uc[q] = uc[q - 1usize]
            q -= 1usize
        }
        uc[q] = t
        i += 1usize
    }
    var nr = 0usize
    if aug && nk > 0usize && n - no != 1usize { nr = 2usize * nk * k }
    let na = no + nr
    let (xa, e1) = mem.alloc[f64](a, na * nk + 1usize)
    let (ya, e2) = mem.alloc[f64](a, na + 1usize)
    let (wa, e3) = mem.alloc[f64](a, na + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (g, mem.Full) }
    var t = 0usize
    while t < no {
        var c = 0usize
        while c < nk {
            xa[c * na + t] = xk[c * n + ro[t]]
            c += 1usize
        }
        ya[t] = y[ro[t]]
        wa[t] = 1.0f64
        t += 1usize
    }
    let blen = 2usize * k + nr
    var c = 0usize
    while c < nk {
        // mean, sd, min and max of the column over its non-missing rows
        var cnt = 0usize
        var s = 0.0f64
        var mn = 0.0f64
        var mx = 0.0f64
        i = 0usize
        while i < n {
            let v = xk[c * n + i]
            if v == v {
                if cnt == 0usize {
                    mn = v
                    mx = v
                }
                if v < mn { mn = v }
                if v > mx { mx = v }
                s += v
                cnt += 1usize
            }
            i += 1usize
        }
        let mean = s / f64(cnt)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            let v = xk[c * n + i]
            if v == v { ss += (v - mean) * (v - mean) }
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / f64(cnt - 1usize))
        var rr = 0usize
        while rr < nr {
            let pos = (c * nr + rr) % blen
            var b = 0.0f64
            if pos < 2usize * k {
                if pos % 2usize == 0usize { b = 0.5f64 } else { b = 0.0f64 - 0.5f64 }
            }
            var dv = mean + b * sd
            if mn > dv { dv = mn }
            if mx < dv { dv = mx }
            xa[c * na + no + rr] = dv
            rr += 1usize
        }
        c += 1usize
    }
    var rr = 0usize
    while rr < nr {
        ya[no + rr] = uc[(rr % (2usize * k)) / 2usize]
        wa[no + rr] = f64(nk + 1usize) / f64(nr)
        rr += 1usize
    }
    g.na = na
    g.xa = xa
    g.ya = ya
    g.wa = wa
    ret (g, ok)
}

// ---- the univariate methods; each fills vals (one value per row of wo, in row order)

// least squares of yo on the intercept and the kept predictors of the rows ro (xo is no by cd column-major with the intercept first): beta, the inverse of X'X (row-major) and the residual sum of squares
fn mi_ols(a: *mem.Arena, xo: []const f64, yo: []const f64, no: usize, cd: usize, beta: []f64, inv: []f64) -> (f64, err) {
    let (xtx, e1) = mem.alloc[f64](a, cd * cd)
    let (xty, e2) = mem.alloc[f64](a, cd)
    let (lw, e3) = mem.alloc[f64](a, cd * cd)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, mem.Full) }
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
    var i = 0usize
    while i < no {
        s1 = 0usize
        while s1 < cd {
            xty[s1] += xo[s1 * no + i] * yo[i]
            var s2 = 0usize
            while s2 < cd {
                xtx[s1 * cd + s2] += xo[s1 * no + i] * xo[s2 * no + i]
                s2 += 1usize
            }
            s1 += 1usize
        }
        i += 1usize
    }
    if !mc.spd_inverse(xtx, cd, inv, lw) { ret (0.0f64, Collinear) }
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
    while i < no {
        var f = 0.0f64
        s1 = 0usize
        while s1 < cd {
            f += xo[s1 * no + i] * beta[s1]
            s1 += 1usize
        }
        let rr = yo[i] - f
        rss += rr * rr
        i += 1usize
    }
    ret (rss, ok)
}

// norm (2), norm.nob (3), norm.predict (4), norm.boot (5) and pmm (1)
fn mi_norm(a: *mem.Arena, st: *Mi, mth: usize, xk: []const f64, nk: usize, y: []const f64, ro: []const usize, wo: []const usize, vals: []f64) -> err {
    let n = st.n
    let no = ro.len
    let nw = wo.len
    let cd = nk + 1usize
    let (xo, e1) = mem.alloc[f64](a, no * cd)
    let (yo, e2) = mem.alloc[f64](a, no)
    let (xw, e3) = mem.alloc[f64](a, nw * cd)
    let (beta, e4) = mem.alloc[f64](a, cd)
    let (inv, e5) = mem.alloc[f64](a, cd * cd)
    let (bs, e6) = mem.alloc[f64](a, cd)
    let (zz, e7) = mem.alloc[f64](a, cd)
    let (lv, e8) = mem.alloc[f64](a, cd * cd)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var sidx: []i64 = zero
    if mth == 5usize {
        let (s, es) = rng.sample_int(a, &st.r, i64(no), i64(no), true)
        if es != ok { ret es }
        sidx = s
    }
    var t = 0usize
    while t < no {
        var src = ro[t]
        if mth == 5usize { src = ro[usize(sidx[t]) - 1usize] }
        xo[t] = 1.0f64
        var c = 0usize
        while c < nk {
            xo[(c + 1usize) * no + t] = xk[c * n + src]
            c += 1usize
        }
        yo[t] = y[src]
        t += 1usize
    }
    t = 0usize
    while t < nw {
        xw[t] = 1.0f64
        var c = 0usize
        while c < nk {
            xw[(c + 1usize) * nw + t] = xk[c * n + wo[t]]
            c += 1usize
        }
        t += 1usize
    }
    let (rss, eo) = mi_ols(a, xo, yo, no, cd, beta, inv)
    if eo != ok { ret eo }
    if no <= cd + 1usize && mth != 3usize && mth != 1usize { ret Collinear }
    var sigma = math.sqrt[f64](rss / f64(no - cd - 1usize))
    var use_beta = beta
    if mth == 3usize || mth == 1usize {
        var dfv = no - cd
        if no <= cd { dfv = 1usize }
        sigma = math.sqrt[f64](rss / rd.rchisq(&st.r, f64(dfv)))
        if !chol_lower(inv, cd, lv) { ret Collinear }
        var s1 = 0usize
        while s1 < cd {
            zz[s1] = rng.norm(&st.r)
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
    if mth == 3usize {
        let (dob, ed1) = mem.alloc[f64](a, no)
        let (tmv, ed2) = mem.alloc[f64](a, nw)
        if ed1 != ok || ed2 != ok { ret mem.Full }
        t = 0usize
        while t < no {
            var f = 0.0f64
            var c = 0usize
            while c < cd {
                f += xo[c * no + t] * beta[c]
                c += 1usize
            }
            dob[t] = f
            t += 1usize
        }
        t = 0usize
        while t < nw {
            var f = 0.0f64
            var c = 0usize
            while c < cd {
                f += xw[c * nw + t] * use_beta[c]
                c += 1usize
            }
            tmv[t] = f
            t += 1usize
        }
        let (mi, emi) = mc.matchindex(a, &st.r, dob, tmv, 5usize)
        if emi != ok { ret emi }
        t = 0usize
        while t < nw {
            vals[t] = yo[mi[t]]
            t += 1usize
        }
        ret ok
    }
    t = 0usize
    while t < nw {
        var f = 0.0f64
        var c = 0usize
        while c < cd {
            f += xw[c * nw + t] * use_beta[c]
            c += 1usize
        }
        vals[t] = f
        t += 1usize
    }
    if mth != 2usize {
        t = 0usize
        while t < nw {
            vals[t] += rng.norm(&st.r) * sigma
            t += 1usize
        }
    }
    ret ok
}

// logreg (boot false) and logreg.boot (boot true) for a two-level factor (codes 1 and 2)
fn mi_logreg(a: *mem.Arena, st: *Mi, boot: bool, xk: []const f64, nk: usize, y: []const f64, ro: []const usize, wo: []const usize, vals: []f64) -> err {
    let n = st.n
    let cd = nk + 1usize
    let nw = wo.len
    var xa: []f64 = zero
    var ya: []f64 = zero
    var wa: []f64 = zero
    var na = 0usize
    var ymin = 1.0f64
    var ro2 = ro
    if boot {
        let no = ro.len
        let (s, es) = rng.sample_int(a, &st.r, i64(no), i64(no), true)
        if es != ok { ret es }
        let (rb, erb) = mem.alloc[usize](a, no)
        if erb != ok { ret erb }
        var t = 0usize
        while t < no {
            rb[t] = ro[usize(s[t]) - 1usize]
            t += 1usize
        }
        ro2 = rb
    }
    let (g, eg) = mi_augment(a, xk, nk, n, y, ro2, !boot)
    if eg != ok { ret eg }
    na = g.na
    xa = g.xa
    ya = g.ya
    wa = g.wa
    var t = 0usize
    while t < na {
        if t == 0usize || ya[t] < ymin { ymin = ya[t] }
        t += 1usize
    }
    // a response that is not the lowest present level is a success
    let (xi, e1) = mem.alloc[f64](a, na * cd)
    let (y01, e2) = mem.alloc[f64](a, na)
    let (coef, e3) = mem.alloc[f64](a, cd)
    let (covu, e4) = mem.alloc[f64](a, cd * cd)
    let (lv, e5) = mem.alloc[f64](a, cd * cd)
    let (bs, e6) = mem.alloc[f64](a, cd)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    t = 0usize
    while t < na {
        xi[t] = 1.0f64
        var c = 0usize
        while c < nk {
            xi[(c + 1usize) * na + t] = xa[c * na + t]
            c += 1usize
        }
        y01[t] = 0.0f64
        if ya[t] > ymin { y01[t] = 1.0f64 }
        t += 1usize
    }
    let (conv, ef) = glm_logit(a, xi, y01, wa, na, cd, coef, covu)
    if ef != ok { ret ef }
    let _ = conv
    var c = 0usize
    while c < cd {
        bs[c] = coef[c]
        c += 1usize
    }
    if !boot {
        if !chol_lower(covu, cd, lv) { ret Collinear }
        var zz: [32]f64 = zero
        c = 0usize
        while c < cd {
            zz[c] = rng.norm(&st.r)
            c += 1usize
        }
        c = 0usize
        while c < cd {
            var s = 0.0f64
            var k = 0usize
            while k <= c {
                s += lv[c * cd + k] * zz[k]
                k += 1usize
            }
            bs[c] = coef[c] + s
            c += 1usize
        }
    }
    t = 0usize
    while t < nw {
        var e = 0.0f64
        e += 1.0f64 * bs[0usize]
        c = 0usize
        while c < nk {
            e += xk[c * n + wo[t]] * bs[c + 1usize]
            c += 1usize
        }
        let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e))
        vals[t] = 1.0f64
        if rng.unif(&st.r) <= pr { vals[t] = 2.0f64 }
        t += 1usize
    }
    ret ok
}

// the draw of a level from class probabilities: 1 + the number of cumulative sums below the uniform
fn mi_pick(pr: []const f64, k: usize, u: f64) -> usize {
    var cum = 0.0f64
    var cnt = 0usize
    var c = 0usize
    while c < k {
        cum += pr[c]
        if u > cum { cnt += 1usize }
        c += 1usize
    }
    ret cnt
}

// polyreg (mth 11) and polr (12, falling back on multinom as mice does) for a factor with the codes in y
fn mi_poly(a: *mem.Arena, st: *Mi, mth: usize, xk: []const f64, nk: usize, y: []const f64, ro: []const usize, wo: []const usize, vals: []f64) -> err {
    let n = st.n
    let nw = wo.len
    let (g, eg) = mi_augment(a, xk, nk, n, y, ro, true)
    if eg != ok { ret eg }
    let na = g.na
    // the dense levels: the distinct codes of the fitted rows in ascending order
    let (uc, eu) = mem.alloc[f64](a, na + 1usize)
    if eu != ok { ret eu }
    var k = 0usize
    var t = 0usize
    while t < na {
        var seen = false
        var q = 0usize
        while q < k {
            if uc[q] == g.ya[t] { seen = true }
            q += 1usize
        }
        if !seen {
            uc[k] = g.ya[t]
            k += 1usize
        }
        t += 1usize
    }
    t = 1usize
    while t < k {
        let v = uc[t]
        var q = t
        while q > 0usize && uc[q - 1usize] > v {
            uc[q] = uc[q - 1usize]
            q -= 1usize
        }
        uc[q] = v
        t += 1usize
    }
    let (cls, ec) = mem.alloc[usize](a, na)
    let (cnt, ecn) = mem.alloc[usize](a, k)
    let (xm, exm) = mem.alloc[f64](a, nw * (nk + 1usize))
    let (pr, epr) = mem.alloc[f64](a, k)
    if ec != ok || ecn != ok || exm != ok || epr != ok { ret mem.Full }
    t = 0usize
    while t < k {
        cnt[t] = 0usize
        t += 1usize
    }
    t = 0usize
    while t < na {
        var q = 0usize
        while q < k {
            if uc[q] == g.ya[t] { cls[t] = q }
            q += 1usize
        }
        cnt[cls[t]] += 1usize
        t += 1usize
    }
    t = 0usize
    while t < nw {
        xm[t] = 1.0f64
        var c = 0usize
        while c < nk {
            xm[(c + 1usize) * nw + t] = xk[c * n + wo[t]]
            c += 1usize
        }
        t += 1usize
    }
    var un: []f64 = zero
    if mth == 11usize {
        // polyreg draws its uniforms before the fit
        let (u0, eu0) = mem.alloc[f64](a, nw)
        if eu0 != ok { ret eu0 }
        t = 0usize
        while t < nw {
            u0[t] = rng.unif(&st.r)
            t += 1usize
        }
        un = u0
        var q = 0usize
        while q < k {
            if cnt[q] == na {
                t = 0usize
                while t < nw {
                    vals[t] = uc[q]
                    t += 1usize
                }
                ret ok
            }
            q += 1usize
        }
    }
    var polr_done = false
    if mth == 12usize && k >= 3usize {
        let (par, ep) = mem.alloc[f64](a, nk + k)
        if ep != ok { ret ep }
        let fe = mm.polr_fit(a, g.xa, cls, g.wa, na, nk, k, par)
        if fe == ok {
            polr_done = true
            let (u1, eu1) = mem.alloc[f64](a, nw)
            if eu1 != ok { ret eu1 }
            let (po, epo) = mem.alloc[f64](a, nw * k)
            if epo != ok { ret epo }
            t = 0usize
            while t < nw {
                // polr_probs reads row t of an nw by nk design
                mm.polr_probs(par, xm[nw..nw + nw * nk], nw, nk, k, t, pr)
                var c = 0usize
                while c < k {
                    po[t * k + c] = pr[c]
                    c += 1usize
                }
                t += 1usize
            }
            t = 0usize
            while t < nw {
                u1[t] = rng.unif(&st.r)
                t += 1usize
            }
            t = 0usize
            while t < nw {
                let idx = mi_pick(po[t * k..t * k + k], k, u1[t])
                if idx >= k { vals[t] = 0.0f64 / 0.0f64 } else { vals[t] = uc[idx] }
                t += 1usize
            }
        }
    }
    if mth == 12usize && !polr_done {
        // multinom fallback: the same fit, the uniforms after it
        let (xi, exi) = mem.alloc[f64](a, na * (nk + 1usize))
        if exi != ok { ret exi }
        t = 0usize
        while t < na {
            xi[t] = 1.0f64
            var c = 0usize
            while c < nk {
                xi[(c + 1usize) * na + t] = g.xa[c * na + t]
                c += 1usize
            }
            t += 1usize
        }
        var nwt = nk + 2usize
        if k > 2usize { nwt = k * (nk + 2usize) }
        let (wts, ew) = mem.alloc[f64](a, nwt)
        if ew != ok { ret ew }
        let fe = mm.multinom_fit(a, xi, cls, g.wa, na, nk + 1usize, k, wts)
        if fe != ok { ret fe }
        let (u1, eu1) = mem.alloc[f64](a, nw)
        if eu1 != ok { ret eu1 }
        t = 0usize
        while t < nw {
            u1[t] = rng.unif(&st.r)
            t += 1usize
        }
        t = 0usize
        while t < nw {
            mm.multinom_probs(wts, xm, nw, nk + 1usize, k, t, pr)
            let idx = mi_pick(pr, k, u1[t])
            if idx >= k { vals[t] = 0.0f64 / 0.0f64 } else { vals[t] = uc[idx] }
            t += 1usize
        }
        ret ok
    }
    if mth == 11usize {
        let (xi, exi) = mem.alloc[f64](a, na * (nk + 1usize))
        if exi != ok { ret exi }
        t = 0usize
        while t < na {
            xi[t] = 1.0f64
            var c = 0usize
            while c < nk {
                xi[(c + 1usize) * na + t] = g.xa[c * na + t]
                c += 1usize
            }
            t += 1usize
        }
        var nwt = nk + 2usize
        if k > 2usize { nwt = k * (nk + 2usize) }
        let (wts, ew) = mem.alloc[f64](a, nwt)
        if ew != ok { ret ew }
        let fe = mm.multinom_fit(a, xi, cls, g.wa, na, nk + 1usize, k, wts)
        if fe != ok { ret fe }
        t = 0usize
        while t < nw {
            mm.multinom_probs(wts, xm, nw, nk + 1usize, k, t, pr)
            let idx = mi_pick(pr, k, un[t])
            if idx >= k { vals[t] = 0.0f64 / 0.0f64 } else { vals[t] = uc[idx] }
            t += 1usize
        }
    }
    ret ok
}

// cart: rpart's tree on the observed rows (anova for a numeric y, class for a factor) with minbucket 5, cp 1e-4 (minsplit 15), then a donor drawn from the leaf (anova) or a level drawn with the leaf's probabilities (class)
fn mi_cart(a: *mem.Arena, st: *Mi, isfac: bool, xk: []const f64, nk0: usize, y: []const f64, ro: []const usize, wo: []const usize, vals: []f64) -> err {
    let n = st.n
    let no = ro.len
    let nw = wo.len
    var nk = nk0
    if nk == 0usize { nk = 1usize }
    let (xo, e1) = mem.alloc[f64](a, no * nk)
    let (xw, e2) = mem.alloc[f64](a, nw * nk)
    let (yo, e3) = mem.alloc[f64](a, no)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var t = 0usize
    while t < no {
        var c = 0usize
        while c < nk {
            xo[c * no + t] = 1.0f64
            if nk0 > 0usize { xo[c * no + t] = xk[c * n + ro[t]] }
            c += 1usize
        }
        yo[t] = y[ro[t]]
        t += 1usize
    }
    t = 0usize
    while t < nw {
        var c = 0usize
        while c < nk {
            xw[c * nw + t] = 1.0f64
            if nk0 > 0usize { xw[c * nw + t] = xk[c * n + wo[t]] }
            c += 1usize
        }
        t += 1usize
    }
    var kc = 0usize
    let (uc, eu) = mem.alloc[f64](a, no + 1usize)
    if eu != ok { ret eu }
    var ycode = yo
    if isfac {
        t = 0usize
        while t < no {
            var seen = false
            var q = 0usize
            while q < kc {
                if uc[q] == yo[t] { seen = true }
                q += 1usize
            }
            if !seen {
                uc[kc] = yo[t]
                kc += 1usize
            }
            t += 1usize
        }
        t = 1usize
        while t < kc {
            let v = uc[t]
            var q = t
            while q > 0usize && uc[q - 1usize] > v {
                uc[q] = uc[q - 1usize]
                q -= 1usize
            }
            uc[q] = v
            t += 1usize
        }
        if kc == 1usize {
            // a level holds every observation: it is the answer with no draws
            t = 0usize
            while t < nw {
                vals[t] = uc[0usize]
                t += 1usize
            }
            ret ok
        }
        let (yc, eyc) = mem.alloc[f64](a, no)
        if eyc != ok { ret eyc }
        t = 0usize
        while t < no {
            var q = 0usize
            while q < kc {
                if uc[q] == yo[t] { yc[t] = f64(q + 1usize) }
                q += 1usize
            }
            t += 1usize
        }
        ycode = yc
    }
    // rpart's xval groups: one permutation draw
    let (gp, eg) = rng.sample_int(a, &st.r, i64(no), i64(no), false)
    if eg != ok { ret eg }
    let _ = gp
    let (tree, et) = rp.rpart_fit(a, xo, ycode, no, nk, isfac, kc, 15usize, 5usize, 1.0e-4f64)
    if et != ok { ret et }
    let (lf, el) = mem.alloc[usize](a, no)
    if el != ok { ret el }
    t = 0usize
    while t < no {
        lf[t] = rp.rpart_leaf(&tree, xo, no, t)
        t += 1usize
    }
    let (pr, ep) = mem.alloc[f64](a, kc + 1usize)
    if ep != ok { ret ep }
    t = 0usize
    while t < nw {
        let leaf = rp.rpart_leaf(&tree, xw, nw, t)
        if isfac {
            rp.rpart_leaf_probs(&tree, leaf, pr)
            let (pk, epk) = rd.sample_prob(a, &st.r, kc, 1usize, false, pr[0usize..kc])
            if epk != ok { ret epk }
            vals[t] = uc[usize(pk[0usize]) - 1usize]
        } else {
            var nd = 0usize
            var q = 0usize
            while q < no {
                if lf[q] == leaf { nd += 1usize }
                q += 1usize
            }
            let (dn, ed) = mem.alloc[f64](a, nd)
            if ed != ok { ret ed }
            nd = 0usize
            q = 0usize
            while q < no {
                if lf[q] == leaf {
                    dn[nd] = yo[q]
                    nd += 1usize
                }
                q += 1usize
            }
            // R's sample(x, 1) on a single value x >= 1 draws from 1:x
            var ln = nd
            var one = false
            if nd == 1usize && dn[0usize] >= 1.0f64 {
                ln = usize(dn[0usize])
                one = true
            }
            let (pk, epk) = rng.sample_int(a, &st.r, i64(ln), 1i64, false)
            if epk != ok { ret epk }
            if one { vals[t] = f64(pk[0usize]) } else { vals[t] = dn[usize(pk[0usize]) - 1usize] }
        }
        t += 1usize
    }
    ret ok
}

// the imputations of column j for chain im (sampler.univ): out holds one value per originally missing row in row order
fn mi_univ(a: *mem.Arena, st: *Mi, j: usize, out: []f64) -> err {
    let n = st.n
    var cap = 1usize
    var q = 0usize
    while q < st.p {
        if q != j && st.pred[j * st.p + q] != 0.0f64 {
            if st.kind[q] == 0usize { cap += 1usize } else { cap += st.kind[q] }
        }
        q += 1usize
    }
    let (xall, e1) = mem.alloc[f64](a, n * cap)
    let (ryv, e2) = mem.alloc[bool](a, n)
    let (wyv, e3) = mem.alloc[bool](a, n)
    let (keep, e4) = mem.alloc[bool](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let cd = mi_design(st, j, xall)
    var nro = 0usize
    var nwo = 0usize
    var i = 0usize
    while i < n {
        var xok = true
        var c = 0usize
        while c < cd {
            let v = xall[c * n + i]
            if v != v { xok = false }
            c += 1usize
        }
        let obs = st.d0[j * n + i] == st.d0[j * n + i]
        ryv[i] = xok && obs && st.d[j * n + i] == st.d[j * n + i]
        wyv[i] = xok && !obs
        if ryv[i] { nro += 1usize }
        if wyv[i] { nwo += 1usize }
        i += 1usize
    }
    if nwo == 0usize { ret NoImpute }
    let (ro, e5) = mem.alloc[usize](a, nro)
    let (wo, e6) = mem.alloc[usize](a, nwo)
    let (vals, e7) = mem.alloc[f64](a, nwo)
    if e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var k1 = 0usize
    var k2 = 0usize
    i = 0usize
    while i < n {
        if ryv[i] {
            ro[k1] = i
            k1 += 1usize
        }
        if wyv[i] {
            wo[k2] = i
            k2 += 1usize
        }
        i += 1usize
    }
    let y = st.d[j * n..j * n + n]
    let le = mi_lindep(a, xall, cd, n, y, ro, keep)
    if le != ok { ret le }
    var nk = 0usize
    var c = 0usize
    while c < cd {
        if keep[c] { nk += 1usize }
        c += 1usize
    }
    let (xk, e8) = mem.alloc[f64](a, n * (nk + 1usize))
    if e8 != ok { ret mem.Full }
    var cc = 0usize
    c = 0usize
    while c < cd {
        if keep[c] {
            i = 0usize
            while i < n {
                xk[cc * n + i] = xall[c * n + i]
                i += 1usize
            }
            cc += 1usize
        }
        c += 1usize
    }
    let mth = st.meth[j]
    var fe: err = ok
    if mth <= 3usize || mth == 5usize {
        fe = mi_norm(a, st, mth, xk, nk, y, ro, wo, vals)
    } else if mth == 7usize {
        var s = 0.0f64
        var t = 0usize
        while t < nro {
            s += y[ro[t]]
            t += 1usize
        }
        t = 0usize
        while t < nwo {
            vals[t] = s / f64(nro)
            t += 1usize
        }
    } else if mth == 8usize {
        let (yy, eyy) = mem.alloc[f64](a, nro + 1usize)
        if eyy != ok { ret eyy }
        var t = 0usize
        while t < nro {
            yy[t] = y[ro[t]]
            t += 1usize
        }
        var len = nro
        if nro == 1usize {
            yy[1usize] = yy[0usize]
            len = 2usize
        }
        let (ix, eix) = rng.sample_int(a, &st.r, i64(len), i64(nwo), true)
        if eix != ok { ret eix }
        t = 0usize
        while t < nwo {
            vals[t] = yy[usize(ix[t]) - 1usize]
            t += 1usize
        }
    } else if mth == 10usize {
        fe = mi_cart(a, st, st.kind[j] > 0usize, xk, nk, y, ro, wo, vals)
    } else if mth == 4usize || mth == 6usize {
        fe = mi_logreg(a, st, mth == 6usize, xk, nk, y, ro, wo, vals)
    } else if mth == 11usize || mth == 12usize {
        fe = mi_poly(a, st, mth, xk, nk, y, ro, wo, vals)
    } else {
        ret Unsupported
    }
    if fe != ok { ret fe }
    // back to one value per originally missing row
    var qm = 0usize
    var qw = 0usize
    i = 0usize
    while i < n {
        if !(st.d0[j * n + i] == st.d0[j * n + i]) {
            if wyv[i] {
                out[qm] = vals[qw]
                qw += 1usize
            } else {
                out[qm] = 0.0f64 / 0.0f64
            }
            qm += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the passive formula of column j on row i of the current data: pas[3 j] the kind (0 a + b, 1 a * b, 2 a - b, 3 a / b, 4 a^2), pas[3 j + 1] and pas[3 j + 2] the columns a and b
fn mi_passive(st: *Mi, j: usize, i: usize) -> f64 {
    let n = st.n
    let k = usize(st.pas[3usize * j])
    let av = st.d[usize(st.pas[3usize * j + 1usize]) * n + i]
    let bv = st.d[usize(st.pas[3usize * j + 2usize]) * n + i]
    if k == 0usize { ret av + bv }
    if k == 1usize { ret av * bv }
    if k == 2usize { ret av - bv }
    if k == 3usize { ret av / bv }
    ret av * av
}

// mice(data, m, maxit, method, predictorMatrix, visitSequence, post, seed), the number of imputed values first in the answer: d0 is n by p column-major with NaN for missing; imp receives, for each visited column with missing values in column order and each imputation, the imputed values of its missing rows in row order; comp (n * p * m, or empty) receives complete(imp, i) for each imputation
fn mice_run(a: *mem.Arena, d0: []const f64, n: usize, p: usize, m: usize, maxit: usize, kind: []const usize, meth: []const usize, pred: []const f64, lo: []const f64, hi: []const f64, pas: []const f64, visit: []const usize, seed: i64, imp: []f64, comp: []f64) -> (usize, err) {
    let (d, e0) = mem.alloc[f64](a, n * p)
    let (nmis, e1) = mem.alloc[usize](a, p)
    let (off, e2) = mem.alloc[usize](a, p)
    let (vis, e3) = mem.alloc[usize](a, p + visit.len)
    let (meff, e4) = mem.alloc[usize](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, mem.Full) }
    var st = Mi { n: n, p: p, m: m, d0: d0, d: d, kind: kind, meth: meff, pred: pred, lo: lo, hi: hi, pas: pas, nmis: nmis, off: off, imp: imp, r: zero }
    rng.seed(&st.r, seed)
    var j = 0usize
    while j < p {
        nmis[j] = 0usize
        var i = 0usize
        while i < n {
            d[j * n + i] = d0[j * n + i]
            if d0[j * n + i] != d0[j * n + i] { nmis[j] += 1usize }
            i += 1usize
        }
        meff[j] = meth[j]
        if nmis[j] == 0usize || nmis[j] == n || meth[j] == 15usize { meff[j] = 15usize }
        j += 1usize
    }
    // the visit sequence: as given, or the active columns and then the passive ones
    var nv = 0usize
    if visit.len > 0usize {
        var h = 0usize
        while h < visit.len {
            vis[nv] = visit[h]
            nv += 1usize
            h += 1usize
        }
    } else {
        j = 0usize
        while j < p {
            if meth[j] < 20usize {
                vis[nv] = j
                nv += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < p {
            if meth[j] >= 20usize {
                vis[nv] = j
                nv += 1usize
            }
            j += 1usize
        }
    }
    var tot = 0usize
    j = 0usize
    while j < p {
        var seen = false
        var h = 0usize
        while h < nv {
            if vis[h] == j { seen = true }
            h += 1usize
        }
        off[j] = tot
        if seen && meff[j] != 15usize {
            tot += nmis[j] * m
        } else {
            meff[j] = 15usize
        }
        j += 1usize
    }
    if imp.len < tot { ret (0usize, mem.Full) }
    // the initial draws
    var h = 0usize
    while h < nv {
        j = vis[h]
        if meff[j] != 15usize {
            var im = 0usize
            while im < m {
                let (yy, eyy) = mem.alloc[f64](a, n + 1usize)
                if eyy != ok { ret (0usize, eyy) }
                var no = 0usize
                var i = 0usize
                while i < n {
                    if d0[j * n + i] == d0[j * n + i] {
                        yy[no] = d0[j * n + i]
                        no += 1usize
                    }
                    i += 1usize
                }
                var len = no
                if no == 1usize {
                    yy[1usize] = yy[0usize]
                    len = 2usize
                }
                let (ix, eix) = rng.sample_int(a, &st.r, i64(len), i64(nmis[j]), true)
                if eix != ok { ret (0usize, eix) }
                var q = 0usize
                while q < nmis[j] {
                    imp[off[j] + im * nmis[j] + q] = yy[usize(ix[q]) - 1usize]
                    q += 1usize
                }
                im += 1usize
            }
        }
        h += 1usize
    }
    var k = 0usize
    while k < maxit {
        var im = 0usize
        while im < m {
            // the chain's current imputations into the data
            h = 0usize
            while h < nv {
                j = vis[h]
                if meff[j] != 15usize {
                    var q = 0usize
                    var i = 0usize
                    while i < n {
                        if d0[j * n + i] != d0[j * n + i] {
                            d[j * n + i] = imp[off[j] + im * nmis[j] + q]
                            q += 1usize
                        }
                        i += 1usize
                    }
                }
                h += 1usize
            }
            h = 0usize
            while h < nv {
                j = vis[h]
                if meff[j] != 15usize {
                    var q = 0usize
                    var i = 0usize
                    if meff[j] >= 20usize {
                        while i < n {
                            if d0[j * n + i] != d0[j * n + i] {
                                let v = mi_passive(&st, j, i)
                                imp[off[j] + im * nmis[j] + q] = v
                                d[j * n + i] = v
                                q += 1usize
                            }
                            i += 1usize
                        }
                    } else {
                        let (out, eo) = mem.alloc[f64](a, nmis[j])
                        if eo != ok { ret (0usize, eo) }
                        let ue = mi_univ(a, &st, j, out)
                        if ue != ok { ret (0usize, ue) }
                        q = 0usize
                        while q < nmis[j] {
                            var v = out[q]
                            if v < lo[j] { v = lo[j] }
                            if v > hi[j] { v = hi[j] }
                            imp[off[j] + im * nmis[j] + q] = v
                            q += 1usize
                        }
                        q = 0usize
                        i = 0usize
                        while i < n {
                            if d0[j * n + i] != d0[j * n + i] {
                                d[j * n + i] = imp[off[j] + im * nmis[j] + q]
                                q += 1usize
                            }
                            i += 1usize
                        }
                    }
                }
                h += 1usize
            }
            im += 1usize
        }
        k += 1usize
    }
    if comp.len >= n * p * m {
        var im = 0usize
        while im < m {
            j = 0usize
            while j < p {
                var q = 0usize
                var i = 0usize
                while i < n {
                    var v = d0[j * n + i]
                    if v != v && meff[j] != 15usize {
                        v = imp[off[j] + im * nmis[j] + q]
                        q += 1usize
                    }
                    comp[im * n * p + j * n + i] = v
                    i += 1usize
                }
                j += 1usize
            }
            im += 1usize
        }
    }
    ret (tot, ok)
}

// ---- pooling (mice::pool on lm fits): the m completed data sets (comp, n by p column-major each) are fitted by y ~ the numeric columns xcols; out[c * 13 ..] receives, for the intercept and each predictor in order: estimate, ubar, b, t, df, riv, lambda, fmi, std.error, statistic, p.value, conf.low and conf.high (Rubin's rules, Barnard-Rubin df with the complete-data df n - ncoef)

fn pool_lm(a: *mem.Arena, comp: []const f64, n: usize, p: usize, m: usize, ycol: usize, xcols: []const usize, out: []f64) -> err {
    let cd = xcols.len + 1usize
    let (xo, e1) = mem.alloc[f64](a, n * cd)
    let (yo, e2) = mem.alloc[f64](a, n)
    let (beta, e3) = mem.alloc[f64](a, cd)
    let (inv, e4) = mem.alloc[f64](a, cd * cd)
    let (est, e5) = mem.alloc[f64](a, m * cd)
    let (var_, e6) = mem.alloc[f64](a, m * cd)
    let (q1, e7) = mem.alloc[f64](a, m)
    let (u1, e8) = mem.alloc[f64](a, m)
    let (po, e9) = mem.alloc[f64](a, 7usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var im = 0usize
    while im < m {
        var i = 0usize
        while i < n {
            xo[i] = 1.0f64
            var c = 0usize
            while c < cd - 1usize {
                xo[(c + 1usize) * n + i] = comp[im * n * p + xcols[c] * n + i]
                c += 1usize
            }
            yo[i] = comp[im * n * p + ycol * n + i]
            i += 1usize
        }
        let (rss, eo) = mi_ols(a, xo, yo, n, cd, beta, inv)
        if eo != ok { ret eo }
        let s2 = rss / f64(n - cd)
        var c = 0usize
        while c < cd {
            est[im * cd + c] = beta[c]
            var_[im * cd + c] = s2 * inv[c * cd + c]
            c += 1usize
        }
        im += 1usize
    }
    var c = 0usize
    while c < cd {
        im = 0usize
        while im < m {
            q1[im] = est[im * cd + c]
            u1[im] = var_[im * cd + c]
            im += 1usize
        }
        mc.pool_scalar(q1, u1, f64(n), f64(cd), po)
        // pool_scalar: qbar ubar b t df r fmi
        let base = c * 13usize
        out[base] = po[0usize]
        out[base + 1usize] = po[1usize]
        out[base + 2usize] = po[2usize]
        out[base + 3usize] = po[3usize]
        out[base + 4usize] = po[4usize]
        out[base + 5usize] = po[5usize]
        let lambda = (1.0f64 + 1.0f64 / f64(m)) * po[2usize] / po[3usize]
        out[base + 6usize] = lambda
        out[base + 7usize] = po[6usize]
        let se = math.sqrt[f64](po[3usize])
        out[base + 8usize] = se
        let stat = po[0usize] / se
        out[base + 9usize] = stat
        var dfp = po[4usize]
        if dfp < 0.001f64 { dfp = 0.001f64 }
        out[base + 10usize] = 2.0f64 * nb.pt(math.abs[f64](stat), dfp, false, false)
        let tq = nb.qt(0.975f64, dfp, true, false)
        out[base + 11usize] = po[0usize] - tq * se
        out[base + 12usize] = po[0usize] + tq * se
        c += 1usize
    }
    ret ok
}
