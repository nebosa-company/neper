// R earth (Milborrow): multivariate adaptive regression splines on a numeric predictor matrix. The forward pass is earth.c's ForwardPass step for step
// (Friedman's fast MARS queue with ageing, the orthogonalised basis and the covariance updates of FindKnot, minspan and endspan, linpreds, the new variable
// penalty, the termination codes), the pruning pass is leaps' AS274 bakwrd (one response) or earth.c's EvalSubsetsUsingXtx (several responses), and the
// final fit is lm.fit through LINPACK dqrdc2 and dqrsl.
//
// Not here: weights, wp, offset, subset, the allowed function, binomial pairs, factors and formulas, varmod, plots; the beta cache of the forward pass is
// left out (it caches values the search recomputes identically, so the answers do not change); ties in a predictor are ordered by row index where earth
// leaves them to the C library's qsort.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

error EarthFailed

type QE = struct { par: i64, nt: i64, rd: f64, ar: f64 }

type Fw = struct {
    n: usize,
    p: usize,
    nr: usize,
    nk: usize,
    x: []const f64,
    y: []const f64,
    xo: []usize,
    bx: []f64,
    bxo: []f64,
    bxoct: []f64,
    bxom: []f64,
    dirs: []i64,
    cuts: []f64,
    ndeg: []i64,
    nuses: []i64,
    full: []bool,
    ymean: []f64,
    xbx: []f64,
    covsx: []f64,
    covcol: []f64,
    ycbo: []f64,
    ybxs: []f64,
    q: []QE,
    sq: []QE,
    nq: usize,
    iq: usize,
    maxdeg: i64,
    penalty: f64,
    thresh: f64,
    minspan: i64,
    endspan: i64,
    newvarpen: f64,
    fastk: i64,
    fastbeta: f64,
    linp: []const bool,
    adjend: f64,
    autolin: bool,
    // the answers of the search for one term
    b_case: i64,
    b_pred: i64,
    b_parent: i64,
    b_rd_term: f64,
    b_rd_parent: f64,
    b_new: bool,
    b_lin: bool,
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn sqr(x: f64) -> f64 { ret x * x }

fn min_bx_sos() -> f64 { ret 0.01f64 }

fn maybe_zero(x: f64) -> f64 {
    if x > 0.0f64 - 1.0e-10f64 && x < 1.0e-10f64 { ret 0.0f64 }
    ret x
}

fn fill_f(x: []f64, v: f64) {
    var i = 0usize
    while i < x.len {
        x[i] = v
        i += 1usize
    }
}

fn mean_of(x: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i] / f64(n)
        i += 1usize
    }
    ret m
}

fn sum_sq(x: []const f64, mean: f64, n: usize) -> f64 {
    var ss = 0.0f64
    var i = 0usize
    while i < n {
        ss += sqr(x[i] - mean)
        i += 1usize
    }
    ret ss
}

// earth's GCV: nterms counts the intercept; penalty -1 makes terms and knots free
fn get_gcv(nterms: i64, n: usize, rss: f64, penalty: f64) -> f64 {
    var cost = 0.0f64
    if penalty != 0.0f64 - 1.0f64 {
        let nknots = (f64(nterms) - 1.0f64) / 2.0f64
        cost = (f64(nterms) + penalty * nknots) / f64(n)
    }
    if cost >= 1.0f64 { ret inf() }
    ret rss / (f64(n) * sqr(1.0f64 - cost))
}

// R's get.gcv, which uses a penalty below zero to mean free terms
fn r_gcv(nterms: i64, n: usize, rss: f64, penalty: f64) -> f64 {
    var nparams = f64(nterms) + penalty * ((f64(nterms) - 1.0f64) / 2.0f64)
    if penalty < 0.0f64 { nparams = 0.0f64 }
    if nparams >= f64(n) { ret inf() }
    ret rss / (f64(n) * sqr(1.0f64 - nparams / f64(n)))
}

fn get_rsq(rss: f64, tss: f64) -> f64 {
    let r = 1.0f64 - rss / tss
    if r > 0.0f64 - 1.0e-5f64 && r < 1.0e-5f64 { ret 0.0f64 }
    ret r
}

// ---- the fast MARS queue

fn q_less(a: QE, b: QE) -> bool {
    // CompareQ: larger RssDelta first, then smaller parent
    let d = b.rd - a.rd
    if d < 0.0f64 { ret true }
    if d > 0.0f64 { ret false }
    ret a.par < b.par
}

fn aged_less(a: QE, b: QE) -> bool {
    let d = a.ar - b.ar
    if d < 0.0f64 { ret true }
    if d > 0.0f64 { ret false }
    let d2 = b.rd - a.rd
    if d2 < 0.0f64 { ret true }
    if d2 > 0.0f64 { ret false }
    ret a.par < b.par
}

fn q_add(f: *Fw, iterm: usize, nterms: i64, rd: f64, sort: bool) {
    f.q[f.nq].nt = nterms
    var m = f.q[iterm].rd
    if rd > m { m = rd }
    f.q[f.nq].rd = m
    f.nq += 1usize
    if sort {
        var i = 0usize
        while i < f.nq {
            f.sq[i] = f.q[i]
            i += 1usize
        }
        // insertion sort: the comparison is a total order, so any sort gives the same sequence
        i = 1usize
        while i < f.nq {
            let t = f.sq[i]
            var j = i
            while j > 0usize && q_less(t, f.sq[j - 1usize]) {
                f.sq[j] = f.sq[j - 1usize]
                j -= 1usize
            }
            f.sq[j] = t
            i += 1usize
        }
        if f.fastbeta > 0.0f64 {
            i = 0usize
            while i < f.nq {
                f.sq[i].ar = f64(i) + f.fastbeta * f64(nterms - f.sq[i].nt)
                i += 1usize
            }
            i = 1usize
            while i < f.nq {
                let t = f.sq[i]
                var j = i
                while j > 0usize && aged_less(t, f.sq[j - 1usize]) {
                    f.sq[j] = f.sq[j - 1usize]
                    j -= 1usize
                }
                f.sq[j] = t
                i += 1usize
            }
        }
    }
}

fn next_parent(f: *Fw) -> i64 {
    var lim = f.nq
    if f.fastk < i64(lim) { lim = usize(f.fastk) }
    if f.iq < lim {
        let r = f.sq[f.iq].par
        f.iq += 1usize
        ret r
    }
    ret 0i64 - 1i64
}

// ---- orthogonalised basis

// bx column `col` (a slice of n values) orthogonalised against the used earlier columns; GoodCol is false when its sum of squares is not above 0.01
fn init_bxorth_col(f: *Fw, col: []const f64, nterms: usize, cache_term: i64) -> bool {
    let n = f.n
    let nk = f.nk
    var good = true
    var i = 0usize
    if nterms == 0usize {
        let len = 1.0f64 / math.sqrt[f64](f64(n))
        while i < n {
            f.bxo[i] = len
            i += 1usize
        }
        f.bxom[0usize] = len
    } else if nterms == 1usize {
        let ym = mean_of(col, n)
        while i < n {
            f.bxo[n + i] = col[i] - ym
            i += 1usize
        }
    } else {
        // OrthogResiduals: modified Gram-Schmidt against the used columns
        i = 0usize
        while i < n {
            f.bxo[nterms * n + i] = col[i]
            i += 1usize
        }
        var t = 0usize
        while t < nterms {
            if f.full[t] {
                var xty = 0.0f64
                i = 0usize
                while i < n {
                    xty += f.bxo[t * n + i] * f.bxo[nterms * n + i]
                    i += 1usize
                }
                let nb = 0.0f64 - xty
                i = 0usize
                while i < n {
                    f.bxo[nterms * n + i] = f.bxo[nterms * n + i] + nb * f.bxo[t * n + i]
                    i += 1usize
                }
            }
            t += 1usize
        }
    }
    if nterms > 0usize {
        let off = nterms * n
        let ss = sum_sq(f.bxo[off..off + n], 0.0f64, n)
        if ss <= min_bx_sos() { good = false }
        var lim = 0.0f64
        if cache_term >= 0i64 { lim = min_bx_sos() }
        if ss > lim {
            f.bxom[nterms] = mean_of(f.bxo[off..off + n], n)
            let len = math.sqrt[f64](ss)
            i = 0usize
            while i < n {
                f.bxo[off + i] = f.bxo[off + i] / len
                i += 1usize
            }
        } else {
            f.bxom[nterms] = 0.0f64
            i = 0usize
            while i < n {
                f.bxo[off + i] = 0.0f64
                i += 1usize
            }
        }
    }
    i = 0usize
    while i < n {
        f.bxoct[nterms + i * nk] = f.bxo[nterms * n + i] - f.bxom[nterms]
        i += 1usize
    }
    ret good
}

// ---- terms already in the model

fn new_form(f: *Fw, ipred: usize, iterm: usize, nterms: usize) -> bool {
    var isnew = true
    var i = 1usize
    while i < nterms {
        if f.full[i] {
            isnew = false
            if f.dirs[i + ipred * f.nk] == 0i64 { ret true }
            var j = 0usize
            while j < f.p {
                if j != ipred {
                    let a = f.dirs[i + j * f.nk] != 0i64
                    let b = f.dirs[iterm + j * f.nk] != 0i64
                    if a != b { ret true }
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret isnew
}

fn get_cut(f: *Fw, i: usize, ipred: usize) -> f64 {
    ret f.x[f.xo[i + ipred * f.n] + ipred * f.n]
}

// ---- spans

fn get_endspan(f: *Fw, ndeg: i64) -> i64 {
    var es = 1i64
    if f.endspan > 0i64 {
        es = f.endspan
    } else {
        es = i64(7.32193f64 + math.log[f64](f64(f.p)) / 0.69315f64)
    }
    if ndeg >= 2i64 { es += i64(f.adjend * f64(es) + 0.5f64) }
    let cap = i64(f.n) / 2i64 - 1i64
    if es > cap { es = cap }
    if es < 1i64 { es = 1i64 }
    ret es
}

fn get_nused(f: *Fw, iparent: usize) -> i64 {
    var c = 0i64
    var i = 0usize
    while i < f.n {
        if f.bx[i + iparent * f.n] > 0.0f64 { c += 1i64 }
        i += 1usize
    }
    ret c
}

// (minspan, endspan, startspan) of a parent whose child would have degree ndeg
fn get_span_params(f: *Fw, ndeg: i64, iparent: usize) -> (i64, i64, i64) {
    let es = get_endspan(f, ndeg)
    var start = 0i64
    var minsp = 0i64
    if f.minspan < 0i64 {
        minsp = i64(math.ceil[f64](f64(f.n) / (1.0f64 - f64(f.minspan))))
        start = minsp
        while start < es { start += minsp }
        start -= 1i64
        if start < 1i64 { start = 1i64 }
    } else {
        if f.minspan > 0i64 {
            minsp = f.minspan
        } else {
            let nused = get_nused(f, iparent)
            minsp = i64((2.9702f64 + math.log[f64](f64(i64(f.p) * nused))) / 1.7329f64)
        }
        if minsp < 1i64 { minsp = 1i64 }
        var avail = i64(f.n) - 2i64 * es
        if avail < 0i64 { avail = 0i64 }
        start = avail / 2i64
        if avail > minsp {
            let nd = avail / minsp
            if avail == nd * minsp {
                start = minsp / 2i64
            } else {
                start = (avail - nd * minsp) / 2i64
            }
        }
        start = es + start
        if start < 1i64 { start = 1i64 }
    }
    ret (minsp, es, start)
}

// ---- the knot search

// FindKnot: scan the cases of predictor ipred downwards for the knot with the largest RSS decrease for a hinge on parent iparent
fn find_knot(f: *Fw, best_case: *i64, best_rd: *f64, inew: usize, iparent: usize, ipred: usize, rd_lin: f64, max_legal: f64, nstart: i64, nmin: i64, nend: i64, new_adj: f64) {
    let n = f.n
    let nk = f.nk
    var tol = 1.0e-5f64
    if inew < 15usize { tol = 0.01f64 }
    var ir = 0usize
    while ir < f.nr {
        f.ycbo[inew + ir * nk] = 0.0f64
        ir += 1usize
    }
    var z = 0usize
    while z <= inew {
        f.covcol[z] = 0.0f64
        f.covsx[z] = 0.0f64
        z += 1usize
    }
    ir = 0usize
    while ir < f.nr {
        f.ybxs[ir] = 0.0f64
        ir += 1usize
    }
    var bx_sum = 0.0f64
    var bx_sq_sum = 0.0f64
    var bx_sqx_sum = 0.0f64
    var bxx_sum = 0.0f64
    var st = 0.0f64
    var ispan = nstart
    var i = i64(n) - 2i64
    while i >= nend {
        let ix0 = f.xo[usize(i) + ipred * n]
        let x0 = f.x[ix0 + ipred * n]
        let ix1 = f.xo[usize(i) + 1usize + ipred * n]
        let x1 = f.x[ix1 + ipred * n]
        let bx1 = f.bx[ix1 + iparent * n]
        let bx_sq = sqr(bx1)
        let xdelta = x1 - x0
        var it = 0usize
        while it < inew {
            f.covsx[it] = f.covsx[it] + bx1 * f.bxoct[it + ix1 * nk]
            f.covcol[it] = f.covcol[it] + xdelta * f.covsx[it]
            it += 1usize
        }
        bx_sum += bx1
        bx_sq_sum += bx_sq
        bxx_sum += bx1 * x1
        bx_sqx_sum += bx_sq * x1
        let su = st
        st = bxx_sum - bx_sum * x0
        f.covcol[inew] += xdelta * (2.0f64 * bx_sqx_sum - bx_sq_sum * (x0 + x1)) + (sqr(su) - sqr(st)) / f64(n)
        ir = 0usize
        while ir < f.nr {
            f.ybxs[ir] += (f.y[ix1 + ir * n] - f.ymean[ir]) * bx1
            f.ycbo[inew + ir * nk] += xdelta * f.ybxs[ir]
            ir += 1usize
        }
        var trig = false
        if bx1 > 0.0f64 && f.covcol[inew] > 0.0f64 {
            ispan -= 1i64
            if ispan == 0i64 { trig = true }
        }
        if trig {
            ispan = nmin
            var rd = 0.0f64
            ir = 0usize
            while ir < f.nr {
                var t1 = f.ycbo[inew + ir * nk]
                var dot1 = 0.0f64
                it = 0usize
                while it < inew {
                    dot1 += f.ycbo[it + ir * nk] * f.covcol[it]
                    it += 1usize
                }
                t1 = t1 - dot1
                var dot2 = 0.0f64
                it = 0usize
                while it < inew {
                    dot2 += f.covcol[it] * f.covcol[it]
                    it += 1usize
                }
                let t2 = f.covcol[inew] - dot2
                if t2 / f.covcol[inew] > tol { rd += sqr(t1) / t2 }
                ir += 1usize
            }
            rd = new_adj * (rd_lin + rd)
            if rd > *best_rd && rd < max_legal {
                *best_case = i
                *best_rd = rd
            }
        }
        i -= 1i64
    }
}

// the candidate term with predictor ipred entering linearly: its orthogonal column goes at nterms; returns the RSS decrease and whether the column is acceptable
fn add_candidate_linear(f: *Fw, ipred: usize, iparent: usize, nterms: usize, rd_lin: *f64, is_new: *bool) {
    let n = f.n
    let nk = f.nk
    var i = 0usize
    while i < n {
        f.xbx[i] = f.x[i + ipred * n] * f.bx[i + iparent * n]
        i += 1usize
    }
    *is_new = init_bxorth_col(f, f.xbx, nterms, i64(iparent))
    var z = 0usize
    while z + 1usize < nterms {
        f.covcol[z] = 0.0f64
        z += 1usize
    }
    f.covcol[nterms] = 1.0f64
    var ir = 0usize
    while ir < f.nr {
        f.ycbo[nterms + ir * nk] = 0.0f64
        i = 0usize
        while i < n {
            f.ycbo[nterms + ir * nk] += (f.y[i + ir * n] - f.ymean[ir]) * f.bxo[nterms * n + i]
            i += 1usize
        }
        ir += 1usize
    }
    var rd = 0.0f64
    ir = 0usize
    while ir < f.nr {
        var ybo = 0.0f64
        i = 0usize
        while i < n {
            ybo += f.y[i + ir * n] * f.bxo[nterms * n + i]
            i += 1usize
        }
        rd += sqr(ybo)
        ir += 1usize
    }
    *rd_lin = rd
}

// FindPredGivenParent: the best predictor and knot for parent iparent
fn find_pred_given_parent(f: *Fw, iparent: usize, nterms: usize, max_legal: f64, minsp: i64, endsp: i64, startsp: i64) {
    var updated = false
    var ipred = 0usize
    while ipred < f.p {
        if f.dirs[iparent + ipred * f.nk] == 0i64 {
            var pen = 0.0f64
            if f.nuses[ipred] == 0i64 { pen = f.newvarpen }
            let new_adj = 1.0f64 / (1.0f64 + pen)
            var rd_lin = 0.0f64
            var rd_lin_unadj = 0.0f64
            var is_new = new_form(f, ipred, iparent, nterms)
            if is_new {
                add_candidate_linear(f, ipred, iparent, nterms, &rd_lin_unadj, &is_new)
                rd_lin = new_adj * rd_lin_unadj
                if rd_lin > f.b_rd_parent { f.b_rd_parent = rd_lin }
                if rd_lin > f.b_rd_term {
                    updated = true
                    f.b_rd_term = rd_lin
                    f.b_lin = true
                    f.b_case = 0i64
                    f.b_pred = i64(ipred)
                    f.b_parent = i64(iparent)
                }
            }
            var rd_pair = rd_lin
            if !f.linp[ipred] {
                var ibest = 0i64 - 1i64
                var inew = nterms
                if is_new { inew = nterms + 1usize }
                find_knot(f, &ibest, &rd_pair, inew, iparent, ipred, rd_lin_unadj, max_legal, startsp, minsp, endsp, new_adj)
                if rd_pair > f.b_rd_parent { f.b_rd_parent = rd_pair }
                if rd_pair > f.b_rd_term {
                    updated = true
                    f.b_rd_term = rd_pair
                    f.b_lin = false
                    f.b_case = ibest
                    f.b_pred = i64(ipred)
                    f.b_parent = i64(iparent)
                    f.b_new = is_new
                }
            }
        }
        ipred += 1usize
    }
    if updated && f.newvarpen != 0.0f64 && f.nuses[usize(f.b_pred)] == 0i64 {
        f.b_rd_term = f.b_rd_term * (1.0f64 + f.newvarpen)
    }
}

// FindTerm: the best new term over the parents that FastK lets through
fn find_term(f: *Fw, nterms: usize, max_legal: f64) {
    let n = f.n
    let nk = f.nk
    f.b_case = 0i64 - 1i64
    f.b_rd_term = 0.0f64
    f.b_lin = false
    f.b_new = false
    var ir = 0usize
    while ir < f.nr {
        var it = 0usize
        while it < nterms {
            f.ycbo[it + ir * nk] = 0.0f64
            var i = 0usize
            while i < n {
                f.ycbo[it + ir * nk] += (f.y[i + ir * n] - f.ymean[ir]) * f.bxo[it * n + i]
                i += 1usize
            }
            it += 1usize
        }
        ir += 1usize
    }
    f.iq = 0usize
    while true {
        let ip = next_parent(f)
        if ip < 0i64 { break }
        let iparent = usize(ip)
        f.b_rd_parent = 0.0f64 - 1.0f64
        if f.ndeg[iparent] < f.maxdeg {
            let (minsp, endsp, startsp) = get_span_params(f, f.ndeg[iparent] + 1i64, iparent)
            find_pred_given_parent(f, iparent, nterms, max_legal, minsp, endsp, startsp)
            f.q[iparent].nt = i64(nterms)
            f.q[iparent].rd = f.b_rd_parent
        }
    }
}

// ---- adding a term pair

fn add_term_pair(f: *Fw, nterms: usize, iparent: usize, icase: usize, ipred: usize, lin_best: bool) {
    let n = f.n
    let nk = f.nk
    let nt1 = nterms + 1usize
    var j = 0usize
    while j < f.p {
        f.dirs[nterms + j * nk] = f.dirs[iparent + j * nk]
        f.dirs[nt1 + j * nk] = f.dirs[iparent + j * nk]
        f.cuts[nterms + j * nk] = f.cuts[iparent + j * nk]
        f.cuts[nt1 + j * nk] = f.cuts[iparent + j * nk]
        j += 1usize
    }
    f.ndeg[nterms] = f.ndeg[iparent] + 1i64
    f.ndeg[nt1] = f.ndeg[iparent] + 1i64
    var de = 1i64
    if f.linp[ipred] || lin_best { de = 2i64 }
    f.dirs[nterms + ipred * nk] = de
    f.dirs[nt1 + ipred * nk] = 0i64 - 1i64
    let best_cut = get_cut(f, icase, ipred)
    f.cuts[nterms + ipred * nk] = best_cut
    f.cuts[nt1 + ipred * nk] = best_cut
    var i = 0usize
    if de == 2i64 {
        while i < n {
            f.bx[nterms * n + i] = f.bx[iparent * n + i] * f.x[i + ipred * n]
            i += 1usize
        }
    } else {
        while i < n {
            let io = f.xo[i + ipred * n]
            let xi = f.x[io + ipred * n]
            if i > icase {
                f.bx[nterms * n + io] = f.bx[iparent * n + io] * (xi - best_cut)
            } else {
                f.bx[nt1 * n + io] = f.bx[iparent * n + io] * (best_cut - xi)
            }
            i += 1usize
        }
    }
    f.nuses[ipred] += 1i64
    f.full[nterms] = true
    let _g1 = init_bxorth_col(f, f.bx[nterms * n..nterms * n + n], nterms, 0i64 - 1i64)
    if !lin_best && f.b_new { f.full[nt1] = true }
    if f.full[nt1] {
        let _g2 = init_bxorth_col(f, f.bx[nt1 * n..nt1 * n + n], nt1, 0i64 - 1i64)
    }
    if !f.full[nt1] {
        f.ndeg[nt1] = 101i64
        i = 0usize
        while i < n {
            f.bxo[nt1 * n + i] = 0.0f64
            i += 1usize
        }
        f.bxom[nt1] = 0.0f64
        i = 0usize
        while i < n {
            f.bxoct[nt1 + i * nk] = 0.0f64
            i += 1usize
        }
    }
}

// the order of each predictor's cases, ascending; equal values keep their row order
fn sort_order(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> ([]usize, err) {
    let (xo, e) = mem.alloc[usize](a, n * p + 1usize)
    if e != ok { ret (xo, e) }
    var c = 0usize
    while c < p {
        var i = 0usize
        while i < n {
            let t = i
            var j = i
            while j > 0usize && x[t + c * n] < x[xo[c * n + j - 1usize] + c * n] {
                xo[c * n + j] = xo[c * n + j - 1usize]
                j -= 1usize
            }
            xo[c * n + j] = t
            i += 1usize
        }
        c += 1usize
    }
    ret (xo, ok)
}

type Forward = struct {
    nterms: usize,
    termcond: i64,
    keep: []bool,
    bx: []f64,
    dirs: []i64,
    cuts: []f64,
    nk: usize,
}

// earth.c ForwardPass on the already scaled y: x is n by p, y is n by nr, both column major. Returns the terms the pass kept (nterms rows of dirs and cuts, bx columns)
fn forward_pass(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, maxdeg: i64, penalty: f64, nk_in: usize, thresh: f64, minspan: i64, endspan: i64, fast_k: i64, fast_beta: f64, newvar_pen: f64, linp: []const bool, adj_end: f64, auto_lin: bool) -> (Forward, err) {
    var out: Forward = zero
    var f: Fw = zero
    let nk = nk_in
    f.n = n
    f.p = p
    f.nr = nr
    f.nk = nk
    f.x = x
    f.y = y
    f.maxdeg = maxdeg
    f.penalty = penalty
    f.thresh = thresh
    f.minspan = minspan
    f.endspan = endspan
    f.newvarpen = newvar_pen
    f.fastbeta = fast_beta
    f.linp = linp
    f.adjend = adj_end
    f.autolin = auto_lin
    var fk = fast_k
    if fk <= 0i64 { fk = 10001i64 }
    if fk < 3i64 { fk = 3i64 }
    f.fastk = fk
    let (xo, e0) = sort_order(a, x, n, p)
    if e0 != ok { ret (out, e0) }
    f.xo = xo
    let (bx, e1) = mem.alloc[f64](a, n * nk + 1usize)
    let (bxo, e2) = mem.alloc[f64](a, n * nk + 1usize)
    let (bxoct, e3) = mem.alloc[f64](a, n * nk + 1usize)
    let (bxom, e4) = mem.alloc[f64](a, nk + 1usize)
    let (dirs, e5) = mem.alloc[i64](a, nk * p + 1usize)
    let (cuts, e6) = mem.alloc[f64](a, nk * p + 1usize)
    let (ndeg, e7) = mem.alloc[i64](a, nk + 1usize)
    let (nuses, e8) = mem.alloc[i64](a, p + 1usize)
    let (full, e9) = mem.alloc[bool](a, nk + 1usize)
    let (ymean, e10) = mem.alloc[f64](a, nr + 1usize)
    let (xbx, e11) = mem.alloc[f64](a, n + 1usize)
    let (covsx, e12) = mem.alloc[f64](a, nk + 1usize)
    let (covcol, e13) = mem.alloc[f64](a, nk + 1usize)
    let (ycbo, e14) = mem.alloc[f64](a, nk * nr + 1usize)
    let (ybxs, e15) = mem.alloc[f64](a, nr + 1usize)
    let (q, e16) = mem.alloc[QE](a, nk + 1usize)
    let (sq, e17) = mem.alloc[QE](a, nk + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (out, mem.Exhausted) }
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret (out, mem.Exhausted) }
    f.bx = bx
    f.bxo = bxo
    f.bxoct = bxoct
    f.bxom = bxom
    f.dirs = dirs
    f.cuts = cuts
    f.ndeg = ndeg
    f.nuses = nuses
    f.full = full
    f.ymean = ymean
    f.xbx = xbx
    f.covsx = covsx
    f.covcol = covcol
    f.ycbo = ycbo
    f.ybxs = ybxs
    f.q = q
    f.sq = sq
    fill_f(bx, 0.0f64)
    fill_f(bxo, 0.0f64)
    fill_f(bxoct, 0.0f64)
    fill_f(bxom, 0.0f64)
    fill_f(cuts, 0.0f64)
    fill_f(covsx, 0.0f64)
    fill_f(covcol, 0.0f64)
    fill_f(ycbo, 0.0f64)
    var z = 0usize
    while z < nk * p {
        dirs[z] = 0i64
        z += 1usize
    }
    z = 0usize
    while z < nk {
        ndeg[z] = 0i64
        full[z] = false
        var qe0: QE = zero
        qe0.par = i64(z)
        qe0.nt = 0i64 - 99i64
        qe0.rd = 0.0f64 - 1.0f64
        qe0.ar = 0.0f64 - 1.0f64
        q[z] = qe0
        sq[z] = q[z]
        z += 1usize
    }
    z = 0usize
    while z < p {
        nuses[z] = 0i64
        z += 1usize
    }
    z = 0usize
    while z < n {
        bx[z] = 1.0f64
        z += 1usize
    }
    let _g = init_bxorth_col(&f, f.bx[0usize..n], 0usize, 0i64 - 1i64)
    f.full[0usize] = true
    var ir = 0usize
    var rss_null = 0.0f64
    while ir < nr {
        ymean[ir] = mean_of(y[ir * n..ir * n + n], n)
        let ssn = sum_sq(y[ir * n..ir * n + n], ymean[ir], n)
        rss_null += ssn
        var lim = 1.0e-8f64 * f64(n)
        if rss_null < lim { rss_null = lim }
        ir += 1usize
    }
    var rss = rss_null
    var rd_all = rss_null
    var rsq = 0.0f64
    var rsq_delta = 0.0f64
    var nused = 1i64
    var gcv = 0.0f64
    let gcv_null = get_gcv(nused, n, rss_null, penalty)
    f.nq = 0usize
    q_add(&f, 0usize, 1i64, rss_null, true)
    var nterms = 1usize
    var ibest_case = 0i64 - 1i64
    if nk >= 3usize {
        while true {
            if rss <= 0.0f64 { ret (out, EarthFailed) }
            var max_legal = 1.01f64 * rss
            if 10.0f64 * rd_all < max_legal { max_legal = 10.0f64 * rd_all }
            find_term(&f, nterms, max_legal)
            rd_all = f.b_rd_term
            ibest_case = f.b_case
            if f.b_case < 0i64 { f.b_lin = false }
            var lin_best = f.b_lin
            if !auto_lin && f.b_pred >= 0i64 && !linp[usize(f.b_pred)] { lin_best = false }
            if ibest_case >= 0i64 {
                add_term_pair(&f, nterms, usize(f.b_parent), usize(ibest_case), usize(f.b_pred), lin_best)
            }
            let is_pair = ibest_case > 0i64 && f.b_new
            nused += 1i64
            if is_pair { nused += 1i64 }
            rss -= rd_all
            rss = maybe_zero(rss)
            gcv = get_gcv(nused, n, rss, penalty)
            let old_rsq = rsq
            rsq = 1.0f64 - rss / rss_null
            rsq_delta = maybe_zero(rsq - old_rsq)
            if ibest_case < 0i64 {
                f.full[nterms] = false
                f.full[nterms + 1usize] = false
                break
            }
            if thresh != 0.0f64 && rsq_delta < thresh {
                f.full[nterms] = false
                f.full[nterms + 1usize] = false
                break
            }
            let grsq = 1.0f64 - gcv / gcv_null
            if thresh != 0.0f64 && grsq < 0.0f64 - 10.0f64 {
                f.full[nterms] = false
                f.full[nterms + 1usize] = false
                break
            }
            if !lin_best && f.b_new {
                q_add(&f, nterms, i64(nterms), inf(), false)
                q_add(&f, nterms + 1usize, i64(nterms), inf(), true)
            } else {
                q_add(&f, nterms, i64(nterms), inf(), true)
            }
            nterms += 2usize
            if rsq >= 1.0f64 - thresh { break }
            if nterms + 1usize >= nk { break }
        }
    }
    // ForwardEpilog
    var term_cond = 7i64
    let grsq_e = 1.0f64 - gcv / gcv_null
    if nk < 3usize {
        term_cond = 1i64
    } else if thresh != 0.0f64 && grsq_e < 0.0f64 - 10.0f64 {
        term_cond = 3i64
        if grsq_e < 0.0f64 - 1000.0f64 { term_cond = 2i64 }
    } else if thresh != 0.0f64 && rsq_delta < thresh {
        term_cond = 4i64
    } else if rsq >= 1.0f64 - thresh {
        term_cond = 5i64
    } else if ibest_case < 0i64 {
        term_cond = 6i64
    }
    out.nterms = nterms
    out.termcond = term_cond
    out.keep = f.full
    out.bx = f.bx
    out.dirs = f.dirs
    out.cuts = f.cuts
    out.nk = nk
    ret (out, ok)
}
