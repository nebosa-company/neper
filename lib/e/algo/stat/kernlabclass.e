// R kernlab ksvm around the SMO solvers of kernlabsvm: one-against-one multi-class C-svc and nu-svc (pair order (1,2), (1,3), ..., voting with
// which.max ties to the first class), class weights, ksvm's default scaled = TRUE (R's scale() of the columns, and of a regression target), the
// probability models (Platt's sigmoid fitted on 3-fold cross-validated decision values drawn from R's stream, and the regression model, the mean
// absolute residual of 3-fold predictions) and the couplers minpair, pkpd and vote of couplers.R. Data are row-major, n by nf.
//
// Not here: the automatic sigma of an rbf kernel (sigest),
// class weights together with prob.model (kernlab itself stops there for more than two classes), kernel-matrix and string input.

use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.kernlabmmd as km
use e.algo.stat.kernlabqp as qp
use e.algo.stat.kernlabsvm as ks
use e.math
use e.mem

error Fail

// R's scale(): center = colMeans, scale = sqrt(sum(v^2) / (n - 1)) of the centred column. Writes x in place and the two vectors.
fn scale_cols(a: *mem.Arena, x: []f64, n: usize, nf: usize, center: []f64, sc: []f64) -> err {
    let (col, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var j = 0usize
    while j < nf {
        var i = 0usize
        while i < n {
            col[i] = x[i * nf + j]
            i += 1usize
        }
        center[j] = ld.colmean_ld(col[0usize..n])
        i = 0usize
        while i < n {
            col[i] = (x[i * nf + j] - center[j]) * (x[i * nf + j] - center[j])
            i += 1usize
        }
        sc[j] = math.sqrt[f64](ld.sum_ld(col[0usize..n]) / f64(n - 1usize))
        i = 0usize
        while i < n {
            x[i * nf + j] = (x[i * nf + j] - center[j]) / sc[j]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// x (nt by nf) scaled by a stored centre and scale
fn apply_scale(x: []f64, nt: usize, nf: usize, center: []const f64, sc: []const f64) {
    var i = 0usize
    while i < nt {
        var j = 0usize
        while j < nf {
            x[i * nf + j] = (x[i * nf + j] - center[j]) / sc[j]
            j += 1usize
        }
        i += 1usize
    }
}

// the decision values of one fitted problem on xnew: sum_j coef[j] k(new, x_j) - b, over the support vectors in index order
fn decide(a: *mem.Arena, par: *const ks.Param, x: []const f64, n: usize, nf: usize, coef: []const f64, b: f64, xnew: []const f64, nt: usize, out: []f64) -> err {
    let (xall, e1) = mem.alloc[f64](a, (n + nt) * nf)
    let (xsq, e2) = mem.alloc[f64](a, n + nt)
    if e1 != ok || e2 != ok { ret Fail }
    var i = 0usize
    while i < n * nf {
        xall[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < nt * nf {
        xall[n * nf + i] = xnew[i]
        i += 1usize
    }
    let (sqb, e3) = mem.alloc[f64](a, nf)
    if e3 != ok { ret Fail }
    i = 0usize
    while i < n + nt {
        var k = 0usize
        while k < nf {
            sqb[k] = xall[i * nf + k] * xall[i * nf + k]
            k += 1usize
        }
        xsq[i] = ld.sum_ld(sqb[0usize..nf])
        i += 1usize
    }
    var t = 0usize
    while t < nt {
        var d = 0.0f64 - b
        var j = 0usize
        while j < n {
            if coef[j] != 0.0f64 {
                if par.ktype == 7usize {
                    // kernelMult.anovakernel with a y matrix raises each term to the degree before summing (kernlab's kernels.R), unlike kernelMatrix
                    var kv = 0.0f64
                    var k = 0usize
                    while k < nf {
                        let df = xall[(n + t) * nf + k] - xall[j * nf + k]
                        let ev = math.exp[f64](0.0f64 - par.gamma * (df * df))
                        if par.degree == 2i64 {
                            kv += ev * ev
                        } else {
                            kv += math.pow[f64](ev, f64(par.degree))
                        }
                        k += 1usize
                    }
                    d += coef[j] * kv
                } else {
                    if par.ktype == 2usize || par.ktype == 5usize {
                        // kernelMult.rbfkernel and .laplacekernel: the squared distance as 2 x.y - |y|^2 - |x|^2 (the Laplace one rounded to nine places)
                        var dot = 0.0f64
                        var k = 0usize
                        while k < nf {
                            dot += xall[(n + t) * nf + k] * xall[j * nf + k]
                            k += 1usize
                        }
                        let nd = (2.0f64 * dot - xsq[j]) - xsq[n + t]
                        if par.ktype == 2usize {
                            d += coef[j] * math.exp[f64](par.gamma * nd)
                        } else {
                            d += coef[j] * math.exp[f64](0.0f64 - par.gamma * math.sqrt[f64](0.0f64 - km.round9(nd)))
                        }
                    } else {
                        d += coef[j] * ks.kval(par, xall, nf, xsq, n + t, j)
                    }
                }
            }
            j += 1usize
        }
        out[t] = d
        t += 1usize
    }
    ret ok
}

fn with_c(par: *const ks.Param, cp: f64, cn: f64) -> ks.Param {
    ret ks.Param { ktype: par.ktype, svm: par.svm, c: par.c, nu: par.nu, p: par.p, gamma: par.gamma, degree: par.degree, coef0: par.coef0, tol: par.tol, shrinking: par.shrinking, cp: cp, cn: cn }
}

// one-against-one fit. cls: class of each row, 0 .. kc - 1. coef (npair by n, 0 off the support vectors), bout and obj (npair). wts: class weights (kc values) or empty.
fn fit_class(a: *mem.Arena, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, par: *const ks.Param, wts: []const f64, coef: []f64, bout: []f64, obj: []f64) -> err {
    var p = 0usize
    var i = 0usize
    while i < kc * (kc - 1usize) / 2usize * n {
        coef[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i + 1usize < kc {
        var j = i + 1usize
        while j < kc {
            let start = mem.mark(a)
            let (idx, e1) = mem.alloc[usize](a, n)
            if e1 != ok { ret Fail }
            var m = 0usize
            var li = 0usize
            var r = 0usize
            while r < n {
                if cls[r] == i {
                    idx[m] = r
                    m += 1usize
                    li += 1usize
                }
                r += 1usize
            }
            r = 0usize
            while r < n {
                if cls[r] == j {
                    idx[m] = r
                    m += 1usize
                }
                r += 1usize
            }
            let (xs, e2) = mem.alloc[f64](a, m * nf)
            let (yd, e3) = mem.alloc[f64](a, m)
            let (out, e4) = mem.alloc[f64](a, m)
            if e2 != ok || e3 != ok || e4 != ok { ret Fail }
            var q = 0usize
            while q < m {
                var k = 0usize
                while k < nf {
                    xs[q * nf + k] = x[idx[q] * nf + k]
                    k += 1usize
                }
                yd[q] = 1.0f64
                if q < li { yd[q] = 0.0f64 - 1.0f64 }
                q += 1usize
            }
            var cp = par.c
            var cn = par.c
            if wts.len > 0usize {
                cp = par.c * wts[j]
                cn = par.c * wts[i]
            }
            let pp = with_c(par, cp, cn)
            let (rho, ob, e5) = ks.smo_optim(a, xs, m, nf, yd, &pp, out)
            if e5 != ok { ret e5 }
            q = 0usize
            while q < m {
                var v = out[q]
                if par.svm == 0usize { v = out[q] * yd[q] }
                coef[p * n + idx[q]] = v
                q += 1usize
            }
            bout[p] = rho
            obj[p] = ob
            mem.reset(a, start)
            p += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Platt's sigmoid by .probPlatt: ab = [A, B] for decision values deci and labels yres (+1 or -1)
fn platt(a: *mem.Arena, deci: []const f64, yres: []const f64, m: usize, ab: []f64) -> err {
    let (t, e1) = mem.alloc[f64](a, m)
    let (pv, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret Fail }
    var prior1 = 0.0f64
    var i = 0usize
    while i < m {
        if yres[i] >= 0.0f64 { prior1 += 1.0f64 }
        i += 1usize
    }
    let prior0 = f64(m) - prior1
    let hi = (prior1 + 1.0f64) / (prior1 + 2.0f64)
    let lo = 1.0f64 / (prior0 + 2.0f64)
    i = 0usize
    while i < m {
        t[i] = lo
        if yres[i] >= 0.0f64 { t[i] = hi }
        i += 1usize
    }
    var ca = 0.0f64
    var cb = math.log[f64]((prior0 + 1.0f64) / (prior1 + 1.0f64))
    let sigma = 1.0e-3f64
    let eps = 1.0e-5f64
    let minstep = 1.0e-10f64
    var fval = fvalue(deci, t, m, ca, cb)
    var it = 0usize
    while it < 100usize {
        var h11 = sigma
        var h22 = sigma
        var h21 = 0.0f64
        var g1 = 0.0f64
        var g2 = 0.0f64
        i = 0usize
        while i < m {
            let f = deci[i] * ca + cb
            var pp = 0.0f64
            var qq = 0.0f64
            if f >= 0.0f64 {
                pp = math.exp[f64](0.0f64 - f) / (1.0f64 + math.exp[f64](0.0f64 - f))
                qq = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - f))
            } else {
                pp = 1.0f64 / (1.0f64 + math.exp[f64](f))
                qq = math.exp[f64](f) / (1.0f64 + math.exp[f64](f))
            }
            pv[i] = pp
            let d2 = pp * qq
            h11 += d2 * (deci[i] * deci[i])
            h22 += d2
            h21 += deci[i] * d2
            let d1 = t[i] - pp
            g1 += deci[i] * d1
            g2 += d1
            i += 1usize
        }
        var a1 = g1
        if a1 < 0.0f64 { a1 = 0.0f64 - a1 }
        var a2 = g2
        if a2 < 0.0f64 { a2 = 0.0f64 - a2 }
        if a1 < eps && a2 < eps { break }
        let det = h11 * h22 - h21 * h21
        let da = 0.0f64 - (h22 * g1 - h21 * g2) / det
        let db = 0.0f64 - (0.0f64 - h21 * g1 + h11 * g2) / det
        let gd = g1 * da + g2 * db
        var step = 1.0f64
        while step >= minstep {
            let na = ca + step * da
            let nb = cb + step * db
            let nf2 = fvalue(deci, t, m, na, nb)
            if nf2 < fval + 0.0001f64 * step * gd {
                ca = na
                cb = nb
                fval = nf2
                break
            }
            step = step / 2.0f64
        }
        if step < minstep { ret Fail }
        it += 1usize
    }
    ab[0usize] = ca
    ab[1usize] = cb
    ret ok
}

fn fvalue(deci: []const f64, t: []const f64, m: usize, ca: f64, cb: f64) -> f64 {
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < m {
        let f = deci[i] * ca + cb
        if f >= 0.0f64 {
            s1 += t[i] * f + math.log[f64](1.0f64 + math.exp[f64](0.0f64 - f))
        } else {
            s2 += (t[i] - 1.0f64) * f + math.log[f64](1.0f64 + math.exp[f64](f))
        }
        i += 1usize
    }
    ret s1 + s2
}

// .SigmoidPredict
fn sigmoid(deci: f64, ca: f64, cb: f64) -> f64 {
    let f = deci * ca + cb
    if f >= 0.0f64 { ret math.exp[f64](0.0f64 - f) / (1.0f64 + math.exp[f64](0.0f64 - f)) }
    ret 1.0f64 / (1.0f64 + math.exp[f64](f))
}

// the three folds of split(vec, 1:3): fold k holds vec[e] for e mod 3 == k; train = the other two folds in index order, test = fold k
fn fold_lists(vec: []const usize, m: usize, k: usize, train: []usize, test: []usize) -> (usize, usize) {
    var nt = 0usize
    var ne = 0usize
    var g = 0usize
    while g < 3usize {
        var e = 0usize
        while e < m {
            if e % 3usize == g {
                if g == k {
                    test[nt] = vec[e]
                    nt += 1usize
                } else {
                    train[ne] = vec[e]
                    ne += 1usize
                }
            }
            e += 1usize
        }
        g += 1usize
    }
    ret (ne, nt)
}

// ksvm's prob.model for classification: ab (2 per pair) = A, B of each pair. R draws sample(1:li, li) and sample((li + 1):(li + lj), lj) per pair, then fits and predicts folds 1 to 3
fn prob_class(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, par: *const ks.Param, ab: []f64) -> err {
    var p = 0usize
    var i = 0usize
    while i + 1usize < kc {
        var j = i + 1usize
        while j < kc {
            let start = mem.mark(a)
            let (idx, e1) = mem.alloc[usize](a, n)
            if e1 != ok { ret Fail }
            var m = 0usize
            var li = 0usize
            var r = 0usize
            while r < n {
                if cls[r] == i {
                    idx[m] = r
                    m += 1usize
                    li += 1usize
                }
                r += 1usize
            }
            r = 0usize
            while r < n {
                if cls[r] == j {
                    idx[m] = r
                    m += 1usize
                }
                r += 1usize
            }
            let lj = m - li
            let (s1, f1) = rr.sample_int(a, g, i64(li), i64(li), false)
            let (s2, f2) = rr.sample_int(a, g, i64(lj), i64(lj), false)
            if f1 != ok || f2 != ok { ret Fail }
            let (vec, e2) = mem.alloc[usize](a, m)
            let (xc, e3) = mem.alloc[f64](a, m * nf)
            let (tr, e4) = mem.alloc[usize](a, m)
            let (te, e5) = mem.alloc[usize](a, m)
            let (pres, e6) = mem.alloc[f64](a, m)
            let (yres, e7) = mem.alloc[f64](a, m)
            if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Fail }
            var q = 0usize
            while q < li {
                vec[q] = usize(s1[q]) - 1usize
                q += 1usize
            }
            while q < m {
                vec[q] = li + usize(s2[q - li]) - 1usize
                q += 1usize
            }
            q = 0usize
            while q < m {
                var k = 0usize
                while k < nf {
                    xc[q * nf + k] = x[idx[q] * nf + k]
                    k += 1usize
                }
                q += 1usize
            }
            var filled = 0usize
            var fold = 0usize
            while fold < 3usize {
                let st2 = mem.mark(a)
                let (ne, nt) = fold_lists(vec, m, fold, tr, te)
                let (xt, f3) = mem.alloc[f64](a, ne * nf)
                let (cl2, f4) = mem.alloc[usize](a, ne)
                let (xv, f5) = mem.alloc[f64](a, nt * nf)
                let (cf, f6) = mem.alloc[f64](a, ne)
                let (bb, f7) = mem.alloc[f64](a, 1usize)
                let (ob, f8) = mem.alloc[f64](a, 1usize)
                let (dv, f9) = mem.alloc[f64](a, nt)
                if f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok { ret Fail }
                q = 0usize
                while q < ne {
                    var k = 0usize
                    while k < nf {
                        xt[q * nf + k] = xc[tr[q] * nf + k]
                        k += 1usize
                    }
                    cl2[q] = 0usize
                    if tr[q] >= li { cl2[q] = 1usize }
                    q += 1usize
                }
                q = 0usize
                while q < nt {
                    var k = 0usize
                    while k < nf {
                        xv[q * nf + k] = xc[te[q] * nf + k]
                        k += 1usize
                    }
                    q += 1usize
                }
                let none: []const f64 = zero
                let fe = fit_class(a, xt, ne, nf, cl2, 2usize, par, none, cf, bb, ob)
                if fe != ok { ret fe }
                let de = decide(a, par, xt, ne, nf, cf, bb[0usize], xv, nt, dv)
                if de != ok { ret de }
                q = 0usize
                while q < nt {
                    pres[filled + q] = dv[q]
                    yres[filled + q] = 1.0f64
                    if te[q] < li { yres[filled + q] = 0.0f64 - 1.0f64 }
                    q += 1usize
                }
                filled += nt
                mem.reset(a, st2)
                fold += 1usize
            }
            let pe = platt(a, pres, yres, m, ab[2usize * p..2usize * p + 2usize])
            if pe != ok { ret pe }
            mem.reset(a, start)
            p += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ksvm's regression prob.model: the mean absolute residual of the 3-fold predictions (rescaled by the target's scale when ys is set), zeroing those beyond 5 sd
fn prob_reg(a: *mem.Arena, g: *rr.Rng, x: []const f64, n: usize, nf: usize, y: []const f64, par: *const ks.Param, has_ys: bool, ysc: f64, ycen: f64) -> (f64, err) {
    let (vec0, f0) = rr.sample_int(a, g, i64(n), i64(n), false)
    let (vec, e1) = mem.alloc[usize](a, n)
    let (tr, e2) = mem.alloc[usize](a, n)
    let (te, e3) = mem.alloc[usize](a, n)
    let (pres, e4) = mem.alloc[f64](a, n)
    if f0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, Fail) }
    var q = 0usize
    while q < n {
        vec[q] = usize(vec0[q]) - 1usize
        q += 1usize
    }
    var filled = 0usize
    var fold = 0usize
    while fold < 3usize {
        let st = mem.mark(a)
        let (ne, nt) = fold_lists(vec, n, fold, tr, te)
        let (xt, f3) = mem.alloc[f64](a, ne * nf)
        let (yt, f4) = mem.alloc[f64](a, ne)
        let (xv, f5) = mem.alloc[f64](a, nt * nf)
        let (cf, f6) = mem.alloc[f64](a, ne)
        let (dv, f7) = mem.alloc[f64](a, nt)
        if f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok { ret (0.0f64, Fail) }
        q = 0usize
        while q < ne {
            var k = 0usize
            while k < nf {
                xt[q * nf + k] = x[tr[q] * nf + k]
                k += 1usize
            }
            yt[q] = y[tr[q]]
            q += 1usize
        }
        q = 0usize
        while q < nt {
            var k = 0usize
            while k < nf {
                xv[q * nf + k] = x[te[q] * nf + k]
                k += 1usize
            }
            q += 1usize
        }
        let (rho, ob, se) = ks.smo_optim(a, xt, ne, nf, yt, par, cf)
        if se != ok { ret (0.0f64, se) }
        let de = decide(a, par, xt, ne, nf, cf, rho, xv, nt, dv)
        if de != ok { ret (0.0f64, de) }
        q = 0usize
        while q < nt {
            var v = dv[q]
            if has_ys { v = dv[q] * ysc + ycen }
            pres[filled + q] = v
            q += 1usize
        }
        filled += nt
        mem.reset(a, st)
        fold += 1usize
    }
    let mean = ld.sum_ld(pres[0usize..n]) / f64(n)
    let (dev, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret (0.0f64, Fail) }
    q = 0usize
    while q < n {
        dev[q] = (pres[q] - mean) * (pres[q] - mean)
        q += 1usize
    }
    let sd = math.sqrt[f64](ld.sum_ld(dev[0usize..n]) / f64(n - 1usize))
    q = 0usize
    while q < n {
        var v = pres[q]
        if v < 0.0f64 { v = 0.0f64 - v }
        if v > 5.0f64 * sd { v = 0.0f64 }
        dev[q] = v
        q += 1usize
    }
    ret (ld.sum_ld(dev[0usize..n]) / f64(n), ok)
}

// the class with most votes for one test row from its pairwise decisions (dec: npair values in pair order), votes (kc) filled; the first maximum wins
fn vote_row(dec: []const f64, kc: usize, votes: []f64) -> usize {
    var i = 0usize
    while i < kc {
        votes[i] = 0.0f64
        i += 1usize
    }
    var p = 0usize
    i = 0usize
    while i + 1usize < kc {
        var j = i + 1usize
        while j < kc {
            if dec[p] < 0.0f64 { votes[i] += 1.0f64 }
            if dec[p] > 0.0f64 { votes[j] += 1.0f64 }
            p += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var best = 0usize
    i = 1usize
    while i < kc {
        if votes[i] > votes[best] { best = i }
        i += 1usize
    }
    ret best
}

// couple(): probin holds the pairwise probabilities 1 - sigmoid in pair order; which 0 minpair, 1 pkpd, 2 vote. out gets kc probabilities
fn couple(a: *mem.Arena, probin: []const f64, kc: usize, which: usize, out: []f64) -> err {
    let (pm, e1) = mem.alloc[f64](a, kc * kc)
    if e1 != ok { ret Fail }
    var i = 0usize
    while i < kc * kc {
        pm[i] = 0.0f64
        i += 1usize
    }
    if which == 2usize {
        var p = 0usize
        i = 0usize
        while i < kc {
            out[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i + 1usize < kc {
            var j = i + 1usize
            while j < kc {
                // R indexes probin by the class numbers i and j; an index past the last pair is NA and changes nothing
                if i < probin.len && probin[i] >= 0.5f64 { out[i] += 1.0f64 }
                if j < probin.len && probin[j] < 0.5f64 { out[j] += 1.0f64 }
                p += 1usize
                j += 1usize
            }
            i += 1usize
        }
        var s = 0.0f64
        i = 0usize
        while i < kc {
            s += out[i]
            i += 1usize
        }
        i = 0usize
        while i < kc {
            out[i] = out[i] / s
            i += 1usize
        }
        ret ok
    }
    // probim[upper.tri] <- probin and probim[lower.tri] <- 1 - probin fill by column
    var k = 0usize
    var c = 0usize
    while c < kc {
        var r = 0usize
        while r < c {
            pm[r * kc + c] = probin[k]
            k += 1usize
            r += 1usize
        }
        c += 1usize
    }
    k = 0usize
    c = 0usize
    while c < kc {
        var r = c + 1usize
        while r < kc {
            pm[r * kc + c] = 1.0f64 - probin[k]
            k += 1usize
            r += 1usize
        }
        c += 1usize
    }
    if which == 1usize {
        i = 0usize
        while i < kc * kc {
            if pm[i] == 0.0f64 { pm[i] = 1.0e-300f64 }
            i += 1usize
        }
        var s = 0.0f64
        i = 0usize
        while i < kc {
            var rs = 0.0f64
            var j = 0usize
            while j < kc {
                if i != j { rs += 1.0f64 / pm[i * kc + j] }
                j += 1usize
            }
            out[i] = 1.0f64 / (rs - f64(kc - 2usize))
            s += out[i]
            i += 1usize
        }
        i = 0usize
        while i < kc {
            out[i] = out[i] / s
            i += 1usize
        }
        ret ok
    }
    let t = kc + 1usize
    let (sq, e2) = mem.alloc[f64](a, t * t)
    let (rhs, e3) = mem.alloc[f64](a, t)
    let (sol, e4) = mem.alloc[f64](a, t)
    if e2 != ok || e3 != ok || e4 != ok { ret Fail }
    i = 0usize
    while i < t * t {
        sq[i] = 0.0f64
        i += 1usize
    }
    c = 0usize
    while c < kc {
        var s = 0.0f64
        var r = 0usize
        while r < kc {
            s += pm[r * kc + c] * pm[r * kc + c]
            r += 1usize
        }
        sq[c * t + c] = s
        sq[kc * t + c] = 1.0f64
        sq[c * t + kc] = 1.0f64
        c += 1usize
    }
    k = 0usize
    c = 0usize
    while c < kc {
        var r = 0usize
        while r < c {
            sq[r * t + c] = 0.0f64 - probin[k] * (1.0f64 - probin[k])
            k += 1usize
            r += 1usize
        }
        c += 1usize
    }
    k = 0usize
    c = 0usize
    while c < kc {
        var r = c + 1usize
        while r < kc {
            sq[r * t + c] = 0.0f64 - probin[k] * (1.0f64 - probin[k])
            k += 1usize
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < t {
        rhs[i] = 0.0f64
        i += 1usize
    }
    rhs[kc] = 1.0f64
    let se = qp.solve_ap(a, sq, rhs, sol, t)
    if se != ok { ret se }
    var s = 0.0f64
    i = 0usize
    while i < kc {
        s += sol[i]
        i += 1usize
    }
    i = 0usize
    while i < kc {
        out[i] = sol[i] / s
        i += 1usize
    }
    ret ok
}
