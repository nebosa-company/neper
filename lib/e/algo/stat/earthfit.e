// R earth: the R level of earth.fit for a numeric predictor matrix: y scaling for the forward pass, the dependent-term clean-up of ForwardPassR, the
// pruning pass (leaps backward, forward, exhaustive and seqrep for one response, earth.c's EvalSubsetsUsingXtx for several), the final lm.fit, the
// GCV, RSq and GRSq summaries, predict and model.matrix (get.bx), evimp and format.earth. Forward pass: e.algo.stat.earth; subset search:
// e.algo.stat.earthleaps; glm responses and cross-validation: e.algo.stat.earthcv.
//
// Not here: weights, wp, offset, subset, allowed, binomial pairs, factors and formulas, varmod, leverages.

use e.algo.linalg.decomp as decomp
use e.algo.stat.earth as ea
use e.algo.stat.earthleaps as lp
use e.math
use e.mem

// pmethod: 0 backward, 1 none, 2 exhaustive, 3 forward, 4 seqrep, 5 cv (the pruning of a model whose size cross-validation chose)
type Opts = struct {
    degree: i64,
    penalty: f64,
    nk: usize,
    thresh: f64,
    minspan: i64,
    endspan: i64,
    newvar: f64,
    fastk: i64,
    fastbeta: f64,
    linp: []bool,
    adjend: f64,
    autolin: bool,
    scale_y: i64,
    pmethod: usize,
    nprune: usize,
}

type EFit = struct {
    n: usize,
    p: usize,
    nr: usize,
    nt: usize,
    dirs: []i64,
    cuts: []f64,
    termcond: i64,
    nk: usize,
    penalty: f64,
    thresh: f64,
    pmethod: usize,
    nall: usize,
    rss_sub: []f64,
    gcv_sub: []f64,
    prune: []usize,
    nsel: usize,
    sel: []usize,
    bx: []f64,
    coef: []f64,
    fitted: []f64,
    resid: []f64,
    rss: f64,
    rsq: f64,
    gcv: f64,
    grsq: f64,
    rss_resp: []f64,
    rsq_resp: []f64,
    gcv_resp: []f64,
    grsq_resp: []f64,
    tss_resp: []f64,
    bxf: []f64,
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn two_sum(x: f64, y: f64) -> (f64, f64) {
    let s = x + y
    let bb = s - x
    let e = (x - (s - bb)) + (y - bb)
    ret (s, e)
}

// a sum that rounds as R's long double accumulation does, to the last place
fn ld_sum(x: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < x.len {
        let (s, e) = two_sum(hi, x[i])
        hi = s
        lo += e
        i += 1usize
    }
    ret hi + lo
}

fn opts_default(a: *mem.Arena, p: usize, degree: i64) -> (Opts, err) {
    var o: Opts = zero
    let (linp, e) = mem.alloc[bool](a, p + 1usize)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < p + 1usize {
        linp[i] = false
        i += 1usize
    }
    o.degree = degree
    o.penalty = 2.0f64
    if degree > 1i64 { o.penalty = 3.0f64 }
    var k = 2usize * p
    if k < 20usize { k = 20usize }
    if k > 200usize { k = 200usize }
    o.nk = k + 1usize
    o.thresh = 0.001f64
    o.minspan = 0i64
    o.endspan = 0i64
    o.newvar = 0.0f64
    o.fastk = 20i64
    o.fastbeta = 1.0f64
    o.linp = linp
    o.adjend = 2.0f64
    o.autolin = true
    o.scale_y = 0i64 - 1i64
    o.pmethod = 0usize
    o.nprune = 0usize
    ret (o, ok)
}

// the first column's mean and sd as scale() computes them; false when a column is constant (earth then does not scale)
fn scaled_y(a: *mem.Arena, y: []const f64, n: usize, nr: usize) -> ([]f64, bool, err) {
    let (ys, e) = mem.alloc[f64](a, n * nr + 1usize)
    let (tmp, e2) = mem.alloc[f64](a, n + 1usize)
    if e != ok || e2 != ok { ret (ys, false, mem.Exhausted) }
    var r = 0usize
    while r < nr {
        let m = ld_sum(y[r * n..r * n + n]) / f64(n)
        var i = 0usize
        while i < n {
            ys[r * n + i] = y[r * n + i] - m
            tmp[i] = ys[r * n + i] * ys[r * n + i]
            i += 1usize
        }
        var dn = f64(n) - 1.0f64
        if dn < 1.0f64 { dn = 1.0f64 }
        let sd = math.sqrt[f64](ld_sum(tmp[0usize..n]) / dn)
        if sd == 0.0f64 { ret (ys, false, ok) }
        i = 0usize
        while i < n {
            ys[r * n + i] = ys[r * n + i] / sd
            i += 1usize
        }
        r += 1usize
    }
    ret (ys, true, ok)
}

// ---- least squares on a set of columns

type Reg = struct { rank: usize, pivot: []usize, rss: f64, betas: []f64, diags: []f64 }

// dqrdc2 and dqrsl on the m columns xu (n rows): betas (m by nr, in pivot order), the residual sum of squares over every response, diag(solve(crossprod(x)))
fn regress(a: *mem.Arena, xu: []const f64, y: []const f64, n: usize, nr: usize, m: usize, want_diag: bool) -> (Reg, err) {
    var g: Reg = zero
    let (f, qe) = decomp.qr(a, xu, n, m, 1.0e-8f64)
    if qe != ok { ret (g, qe) }
    let (betas, e1) = mem.alloc[f64](a, m * nr + 1usize)
    let (diags, e2) = mem.alloc[f64](a, m + 1usize)
    let (qty, e3) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (g, mem.Exhausted) }
    let k = f.rank
    var rss = 0.0f64
    var r = 0usize
    while r < nr {
        var i = 0usize
        while i < n {
            qty[i] = y[r * n + i]
            i += 1usize
        }
        decomp.qr_qty(&f, qty[0usize..n])
        // betas: dqrsl's column oriented back substitution
        i = 0usize
        while i < k {
            betas[r * m + i] = qty[i]
            i += 1usize
        }
        var jj = 1usize
        while jj <= k {
            let j = k - jj
            betas[r * m + j] = betas[r * m + j] / f.qr[j * n + j]
            if j != 0usize {
                let t = 0.0f64 - betas[r * m + j]
                i = 0usize
                while i < j {
                    betas[r * m + i] = betas[r * m + i] + t * f.qr[j * n + i]
                    i += 1usize
                }
            }
            jj += 1usize
        }
        // residuals: Q [0; qty[k..n]]
        i = 0usize
        while i < n {
            if i < k { qty[i] = 0.0f64 }
            i += 1usize
        }
        decomp.qr_qy(&f, qty[0usize..n])
        i = 0usize
        while i < n {
            rss += qty[i] * qty[i]
            i += 1usize
        }
        r += 1usize
    }
    if want_diag && k == m {
        // CalcDiags: inverse of the triangular R column by column (dtrsl job 1), then the row sums of squares
        let (bi, e4) = mem.alloc[f64](a, m * m + 1usize)
        if e4 != ok { ret (g, mem.Exhausted) }
        var c = 0usize
        while c < m {
            var i = 0usize
            while i < m {
                bi[c * m + i] = 0.0f64
                i += 1usize
            }
            bi[c * m + c] = 1.0f64
            bi[c * m + m - 1usize] = bi[c * m + m - 1usize] / f.qr[(m - 1usize) * n + (m - 1usize)]
            var jq = 2usize
            while jq <= m {
                let j = m - jq
                let t = 0.0f64 - bi[c * m + j + 1usize]
                i = 0usize
                while i <= j {
                    bi[c * m + i] = bi[c * m + i] + t * f.qr[(j + 1usize) * n + i]
                    i += 1usize
                }
                bi[c * m + j] = bi[c * m + j] / f.qr[j * n + j]
                jq += 1usize
            }
            c += 1usize
        }
        var i2 = 0usize
        while i2 < m {
            var sm = 0.0f64
            var kk = i2
            while kk < m {
                sm += bi[kk * m + i2] * bi[kk * m + i2]
                kk += 1usize
            }
            diags[i2] = sm
            i2 += 1usize
        }
    }
    g.rank = k
    g.pivot = f.pivot
    g.rss = rss
    g.betas = betas
    g.diags = diags
    ret (g, ok)
}

fn copy_cols(a: *mem.Arena, x: []const f64, n: usize, cols: []const usize, m: usize) -> ([]f64, err) {
    let (xu, e) = mem.alloc[f64](a, n * m + 1usize)
    if e != ok { ret (xu, e) }
    var c = 0usize
    while c < m {
        var i = 0usize
        while i < n {
            xu[c * n + i] = x[cols[c] * n + i]
            i += 1usize
        }
        c += 1usize
    }
    ret (xu, ok)
}

// ---- pruning

type Prune = struct { nall: usize, rss: []f64, gcv: []f64, terms: []usize, sel: []usize, nsel: usize, pmethod: usize }

// EvalSubsetsUsingXtx: drop, one at a time, the term whose removal raises the RSS least; rss[k] and terms[k + j * nt] (1-based term numbers, 0 padded) for the model of k + 1 terms
fn eval_xtx(a: *mem.Arena, bx: []const f64, y: []const f64, n: usize, nr: usize, nt: usize, rss: []f64, terms: []usize) -> err {
    let (work, e1) = mem.alloc[bool](a, nt + 1usize)
    let (cols, e2) = mem.alloc[usize](a, nt + 1usize)
    if e1 != ok || e2 != ok { ret mem.Exhausted }
    var t = 0usize
    while t < nt {
        work[t] = true
        t += 1usize
    }
    var nused = nt
    while nused >= 1usize {
        let mark = mem.mark(a)
        var m = 0usize
        t = 0usize
        while t < nt {
            if work[t] {
                cols[m] = t
                m += 1usize
            }
            t += 1usize
        }
        let (xu, e3) = copy_cols(a, bx, n, cols, m)
        if e3 != ok { ret e3 }
        let (g, e4) = regress(a, xu, y, n, nr, m, true)
        if e4 != ok { ret e4 }
        if g.rank != nused { ret ea.EarthFailed }
        rss[nused - 1usize] = g.rss
        var q = 0usize
        t = 0usize
        while t < nt {
            terms[nused - 1usize + t * nt] = 0usize
            t += 1usize
        }
        t = 0usize
        while t < nt {
            if work[t] {
                terms[nused - 1usize + q * nt] = t + 1usize
                q += 1usize
            }
            t += 1usize
        }
        var idel = nt
        if nused > 1usize {
            var it1 = 0usize
            var mind = 1.0f64 / 0.0f64
            t = 0usize
            while t < nt {
                if work[t] {
                    var dr = 0.0f64
                    var r = 0usize
                    while r < nr {
                        dr += (g.betas[it1 + r * m] * g.betas[it1 + r * m]) / g.diags[it1]
                        r += 1usize
                    }
                    if t > 0usize && dr < mind {
                        mind = dr
                        idel = t
                    }
                    it1 += 1usize
                }
                t += 1usize
            }
            if idel == nt { ret ea.EarthFailed }
            work[idel] = false
        }
        mem.reset(a, mark)
        if nused == 1usize { break }
        nused -= 1usize
    }
    ret ok
}

// pruning.pass: nprune_arg 0 means no limit
fn prune_pass(a: *mem.Arena, bx: []const f64, y: []const f64, n: usize, nr: usize, nt: usize, pmethod_in: usize, penalty: f64, nprune_arg: usize) -> (Prune, err) {
    var out: Prune = zero
    var pmethod = pmethod_in
    var nprune = nprune_arg
    if nprune == 0usize || pmethod == 5usize { nprune = nt }
    if nprune > nt { nprune = nt }
    var nall = nt
    if pmethod == 2usize { nall = nprune }
    let (rss, e1) = mem.alloc[f64](a, nt + 1usize)
    let (terms, e2) = mem.alloc[usize](a, nt * nt + 1usize)
    if e1 != ok || e2 != ok { ret (out, mem.Exhausted) }
    var z = 0usize
    while z < nt * nt {
        terms[z] = 0usize
        z += 1usize
    }
    if pmethod == 2usize {
        // preprocess.exhaustive: an ill conditioned bx falls back to backward elimination
        let (sv, es) = decomp.svd(a, bx, n, nt)
        if es != ok { ret (out, es) }
        let cond = sv.d[sv.k - 1usize] / sv.d[0usize]
        if cond != cond || cond < 1.0e-10f64 { pmethod = 0usize }
    }
    var use_xtx = false
    if nr > 1usize {
        use_xtx = true
        if pmethod != 0usize && pmethod != 1usize { ret (out, ea.EarthFailed) }
    } else if nt <= 2usize {
        use_xtx = true
        if pmethod != 0usize && pmethod != 1usize { pmethod = 0usize }
    }
    var nsub = 0usize
    if use_xtx {
        let e3 = eval_xtx(a, bx, y, n, nr, nt, rss, terms)
        if e3 != ok { ret (out, e3) }
        nsub = nprune
        if pmethod != 2usize { nsub = nt }
    } else {
        var method = 0usize
        if pmethod == 3usize { method = 1usize }
        if pmethod == 2usize { method = 2usize }
        if pmethod == 4usize { method = 3usize }
        let (sb, e4) = lp.leaps_search(a, bx, y, n, nt, nall, method)
        if e4 != ok { ret (out, e4) }
        nsub = sb.nvmax
        var k = 1usize
        while k <= nsub {
            rss[k - 1usize] = sb.ress[k]
            var j = 1usize
            while j <= k {
                terms[k - 1usize + (j - 1usize) * nt] = sb.lopt[k * (k - 1usize) / 2usize + j]
                j += 1usize
            }
            k += 1usize
        }
    }
    if nprune > nsub { nprune = nsub }
    if nall > nsub { nall = nsub }
    // the first nall rows and columns of the subset table
    let (tt, e5) = mem.alloc[usize](a, nall * nall + 1usize)
    let (gcv, e6) = mem.alloc[f64](a, nall + 1usize)
    let (sel, e7) = mem.alloc[usize](a, nall + 1usize)
    if e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Exhausted) }
    var rr = 0usize
    while rr < nall {
        var cc = 0usize
        while cc < nall {
            tt[rr + cc * nall] = terms[rr + cc * nt]
            cc += 1usize
        }
        gcv[rr] = ea.r_gcv(i64(rr + 1usize), n, rss[rr], penalty)
        rr += 1usize
    }
    // selected.terms
    var nsel = nprune
    var row = nprune - 1usize
    if pmethod == 5usize {
        row = nprune_arg - 1usize
    } else if pmethod != 1usize {
        var best = 0usize
        var bv = gcv[0usize]
        var k2 = 1usize
        while k2 < nprune {
            if gcv[k2] < bv {
                bv = gcv[k2]
                best = k2
            }
            k2 += 1usize
        }
        row = best
    }
    if pmethod == 1usize {
        var q = 0usize
        while q < nprune {
            sel[q] = q
            q += 1usize
        }
    } else {
        nsel = 0usize
        var q = 0usize
        while q < nall {
            let v = tt[row + q * nall]
            if v != 0usize {
                sel[nsel] = v - 1usize
                nsel += 1usize
            }
            q += 1usize
        }
    }
    out.nall = nall
    out.rss = rss
    out.gcv = gcv
    out.terms = tt
    out.sel = sel
    out.nsel = nsel
    out.pmethod = pmethod
    ret (out, ok)
}

// ---- the forward pass and its clean-up

type Fwd = struct { nt: usize, dirs: []i64, cuts: []f64, bx: []f64, termcond: i64 }

// earth.fit's forward.pass with the ForwardPassR clean-up: unused terms and terms that are linear combinations of the others are dropped
fn forward_terms(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, o: *const Opts) -> (Fwd, err) {
    var out: Fwd = zero
    var ys = y
    var scale = o.scale_y == 1i64
    if o.scale_y < 0i64 && nr == 1usize { scale = true }
    if scale {
        let (s2, good, es) = scaled_y(a, y, n, nr)
        if es != ok { ret (out, es) }
        if good { ys = s2 }
    }
    let (fw, e1) = ea.forward_pass(a, x, ys, n, p, nr, o.degree, o.penalty, o.nk, o.thresh, o.minspan, o.endspan, o.fastk, o.fastbeta, o.newvar, o.linp, o.adjend, o.autolin)
    if e1 != ok { ret (out, e1) }
    let nk = fw.nk
    let (cols, e2) = mem.alloc[usize](a, nk + 1usize)
    if e2 != ok { ret (out, e2) }
    var m = 0usize
    var t = 0usize
    while t < nk {
        if fw.keep[t] {
            cols[m] = t
            m += 1usize
        }
        t += 1usize
    }
    let (xu, e3) = copy_cols(a, fw.bx, n, cols, m)
    if e3 != ok { ret (out, e3) }
    let (f, e4) = decomp.qr(a, xu, n, m, 1.0e-8f64)
    if e4 != ok { ret (out, e4) }
    var q = f.rank
    while q < m {
        fw.keep[cols[f.pivot[q]]] = false
        q += 1usize
    }
    var nt = 0usize
    t = 0usize
    while t < nk {
        if fw.keep[t] { nt += 1usize }
        t += 1usize
    }
    let (bx, e5) = mem.alloc[f64](a, n * nt + 1usize)
    let (dirs, e6) = mem.alloc[i64](a, nt * p + 1usize)
    let (cuts, e7) = mem.alloc[f64](a, nt * p + 1usize)
    if e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Exhausted) }
    var c = 0usize
    t = 0usize
    while t < nk {
        if fw.keep[t] {
            var i = 0usize
            while i < n {
                bx[c * n + i] = fw.bx[t * n + i]
                i += 1usize
            }
            var j = 0usize
            while j < p {
                dirs[c + j * nt] = fw.dirs[t + j * nk]
                cuts[c + j * nt] = fw.cuts[t + j * nk]
                j += 1usize
            }
            c += 1usize
        }
        t += 1usize
    }
    out.nt = nt
    out.dirs = dirs
    out.cuts = cuts
    out.bx = bx
    out.termcond = fw.termcond
    ret (out, ok)
}

// ---- the model matrix

// get.bx: basis functions of the terms `which` (0-based rows of dirs) at the m rows of x
fn get_bx(a: *mem.Arena, x: []const f64, m: usize, p: usize, dirs: []const i64, cuts: []const f64, nt: usize, which: []const usize, nw: usize) -> ([]f64, err) {
    let (bx, e) = mem.alloc[f64](a, m * nw + 1usize)
    if e != ok { ret (bx, e) }
    var c = 0usize
    while c < nw {
        let t = which[c]
        var i = 0usize
        while i < m {
            var temp1 = 1.0f64
            var j = 0usize
            while j < p {
                let dir = dirs[t + j * nt]
                if dir == 2i64 {
                    temp1 = temp1 * x[i + j * m]
                } else if dir == 1i64 || dir == 0i64 - 1i64 {
                    let temp2 = f64(dir) * (x[i + j * m] - cuts[t + j * nt])
                    var gate = 0.0f64
                    if temp2 > 0.0f64 { gate = 1.0f64 }
                    temp1 = temp1 * temp2 * gate
                }
                j += 1usize
            }
            bx[c * m + i] = temp1
            i += 1usize
        }
        c += 1usize
    }
    ret (bx, ok)
}

// predict.earth(type = "earth") at the m rows of x: bx %*% coefficients
fn predict_rows(a: *mem.Arena, f: *const EFit, x: []const f64, m: usize, out: []f64) -> err {
    let (bx, e) = get_bx(a, x, m, f.p, f.dirs, f.cuts, f.nt, f.sel, f.nsel)
    if e != ok { ret e }
    var r = 0usize
    while r < f.nr {
        var i = 0usize
        while i < m {
            var s = 0.0f64
            var k = 0usize
            while k < f.nsel {
                s += bx[k * m + i] * f.coef[k + r * f.nsel]
                k += 1usize
            }
            out[i + r * m] = s
            i += 1usize
        }
        r += 1usize
    }
    ret ok
}

// ---- earth.fit

fn sos_centered(y: []const f64, n: usize) -> f64 {
    let mu = ld_sum(y[0usize..n]) / f64(n)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    ret s
}

fn fit_selected(a: *mem.Arena, f: *EFit, y: []const f64, pr: *Prune) -> err {
    let n = f.n
    let nr = f.nr
    let nsel = f.nsel
    let (bxs, e1) = mem.alloc[f64](a, n * nsel + 1usize)
    let (coef, e2) = mem.alloc[f64](a, nsel * nr + 1usize)
    let (fitted, e3) = mem.alloc[f64](a, n * nr + 1usize)
    let (resid, e4) = mem.alloc[f64](a, n * nr + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Exhausted }
    var c = 0usize
    while c < nsel {
        var i = 0usize
        while i < n {
            bxs[c * n + i] = f.bxf[f.sel[c] * n + i]
            i += 1usize
        }
        c += 1usize
    }
    var r = 0usize
    while r < nr {
        let (lf, e5) = decomp.lm_fit(a, bxs, n, nsel, y[r * n..r * n + n], 1.0e-7f64)
        if e5 != ok { ret e5 }
        if lf.rank != nsel { ret ea.EarthFailed }
        var i = 0usize
        while i < nsel {
            coef[i + r * nsel] = lf.coef[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            resid[i + r * n] = lf.residuals[i]
            fitted[i + r * n] = y[r * n + i] - lf.residuals[i]
            i += 1usize
        }
        r += 1usize
    }
    f.bx = bxs
    f.coef = coef
    f.fitted = fitted
    f.resid = resid
    // summaries: subset statistics below 1e-10 are zero
    var k = 0usize
    while k < pr.nall {
        if pr.rss[k] < 1.0e-10f64 { pr.rss[k] = 0.0f64 }
        if pr.gcv[k] < 1.0e-10f64 { pr.gcv[k] = 0.0f64 }
        k += 1usize
    }
    f.rss_sub = pr.rss
    f.gcv_sub = pr.gcv
    f.rss = pr.rss[nsel - 1usize]
    f.rsq = ea.get_rsq(f.rss, pr.rss[0usize])
    f.gcv = pr.gcv[nsel - 1usize]
    f.grsq = ea.get_rsq(f.gcv, pr.gcv[0usize])
    let (rr, e6) = mem.alloc[f64](a, nr + 1usize)
    let (rq, e7) = mem.alloc[f64](a, nr + 1usize)
    let (gr, e8) = mem.alloc[f64](a, nr + 1usize)
    let (gq, e9) = mem.alloc[f64](a, nr + 1usize)
    let (ts, e10) = mem.alloc[f64](a, nr + 1usize)
    let (tmp, e11) = mem.alloc[f64](a, n + 1usize)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Exhausted }
    r = 0usize
    while r < nr {
        var rs = 0.0f64
        var i = 0usize
        while i < n {
            tmp[i] = f.resid[i + r * n] * f.resid[i + r * n]
            i += 1usize
        }
        rs = ld_sum(tmp[0usize..n])
        let tss = sos_centered(y[r * n..r * n + n], n)
        rr[r] = rs
        ts[r] = tss
        rq[r] = ea.get_rsq(rs, tss)
        gr[r] = ea.r_gcv(i64(nsel), n, rs, f.penalty)
        let gnull = ea.r_gcv(1i64, n, tss, f.penalty)
        gq[r] = ea.get_rsq(gr[r], gnull)
        r += 1usize
    }
    f.rss_resp = rr
    f.rsq_resp = rq
    f.gcv_resp = gr
    f.grsq_resp = gq
    f.tss_resp = ts
    ret ok
}

// the pruning pass and the final fit on forward-pass terms; also what update.earth(Object = ...) runs with a different pmethod, nprune or penalty
fn prune_and_fit(a: *mem.Arena, y: []const f64, n: usize, p: usize, nr: usize, fw: *const Fwd, nk: usize, thresh: f64, penalty: f64, pmethod: usize, nprune: usize) -> (EFit, err) {
    var f: EFit = zero
    let (pr, e1) = prune_pass(a, fw.bx, y, n, nr, fw.nt, pmethod, penalty, nprune)
    if e1 != ok { ret (f, e1) }
    f.n = n
    f.p = p
    f.nr = nr
    f.nt = fw.nt
    f.dirs = fw.dirs
    f.cuts = fw.cuts
    f.termcond = fw.termcond
    f.nk = nk
    f.penalty = penalty
    f.thresh = thresh
    f.pmethod = pr.pmethod
    f.nall = pr.nall
    f.prune = pr.terms
    f.nsel = pr.nsel
    f.sel = pr.sel
    f.bxf = fw.bx
    var pw = pr
    let e2 = fit_selected(a, &f, y, &pw)
    ret (f, e2)
}

fn earth_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, o: *const Opts) -> (EFit, err) {
    var empty: EFit = zero
    let (fw, e1) = forward_terms(a, x, y, n, p, nr, o)
    if e1 != ok { ret (empty, e1) }
    let (f, e2) = prune_and_fit(a, y, n, p, nr, &fw, o.nk, o.thresh, o.penalty, o.pmethod, o.nprune)
    ret (f, e2)
}

// earth_fit that also answers the forward pass terms, for the pruning that update.earth(Object = ) repeats
fn earth_fit_fwd(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, o: *const Opts) -> (EFit, Fwd, err) {
    var empty: EFit = zero
    var nofw: Fwd = zero
    let (fw, e1) = forward_terms(a, x, y, n, p, nr, o)
    if e1 != ok { ret (empty, nofw, e1) }
    let (f, e2) = prune_and_fit(a, y, n, p, nr, &fw, o.nk, o.thresh, o.penalty, o.pmethod, o.nprune)
    ret (f, fw, e2)
}
