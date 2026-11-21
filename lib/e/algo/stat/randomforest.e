// R randomForest 4.7-1.2 (Breiman and Cutler's forests as the C and Fortran code in the package runs them) for numeric predictors: the same draws from R's
// Mersenne-Twister in the same order, so a forest grown from set.seed(s) is the forest R grows.
//
// Classification (the Fortran buildtree and findbestsplit, with their single-precision constants and tie draws) and regression (regTree.c), bootstrap or
// subsampling of rows, mtry, nodesize, maxnodes, classwt, cutoff, OOB votes, predictions and error rates, importance (permutation and node purity, with the
// standard deviations), local importance, proximity, inbag counts, predict (response, prob, votes) and the partial dependence of partialPlot.
//
// Not here: categorical predictors, test-set arguments, strata, row weights, the unsupervised mode, corr.bias, getTree, rfcv, tuneRF and the plots.
//
// predict on a classification forest draws from R's generator without saving the state (the .C call does not sync .Random.seed), so a caller keeps one Rng
// from the fit through every predict that follows, exactly as an R session does.

use e.algo.rand.r as rng
use e.algo.stat.armld as rfld
use e.math
use e.mem

error Degenerate

type Opts = struct { ntree: usize, mtry: usize, nodesize: usize, sampsize: usize, maxnodes: usize, replace: bool, importance: bool, local_imp: bool, nperm: usize, proximity: bool, oob_prox: bool, keep_inbag: bool, use_classwt: bool, corr_bias: bool }

// xtest (p by n variable fastest) and, when `labels`, ytest: class labels (1-based) in `cl` or the response in `y`; n = 0 means no test set
type TestSet = struct { x: []const f64, n: usize, labels: bool, cl: []const i64, y: []const f64 }

// Tree arrays are ntree blocks of nrnodes. Children are 0-based node indices. A classification node's class is 0-based in `pred`; regression keeps the
// node mean (plus the response mean, as the forest component does). `imp` is p by 2 column-major: regression (%IncMSE, IncNodePurity); a classification
// forest keeps its importance in `cimp`. The test-set answers: `tcls` the predicted class (1-based) or `treg` the predicted response, `tvotes` the vote
// counts (ntest by nclass), `terr` the error rate per tree (classification: nclass + 1 per tree; regression: the mse per tree) and `tprox`.
type Fit = struct {
    n: usize, mdim: usize, ntree: usize, nclass: usize, nrnodes: usize, ymean: f64, corr: bool, coef: [2]f64,
    ndbig: []i64, status: []i64, bvar: []i64, left: []i64, right: []i64, xsplit: []f64, pred: []f64,
    votes: []i64, oobn: []i64, outcl: []i64, ypred: []f64, err: []f64,
    imp: []f64, impsd: []f64, cimp: []f64, impmat: []f64, prox: []f64, inbag: []i64,
    tcls: []i64, treg: []f64, tvotes: []f64, terr: []f64, tprox: []f64
}

fn rf_f64s(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i <= n {
        s[i] = 0.0f64
        i += 1usize
    }
    ret (s, ok)
}

fn rf_i64s(a: *mem.Arena, n: usize) -> ([]i64, err) {
    let (s, e) = mem.alloc[i64](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i <= n {
        s[i] = 0i64
        i += 1usize
    }
    ret (s, ok)
}

fn ux(i: i64) -> usize { ret usize(i) }

// R's mean(): the long double sum and its refinement pass, as in armld
fn rf_mean(v: []const f64) -> f64 { ret rfld.mean_ld(v) }

// R's R_qsort_I (Singleton's quicksort carrying an index vector), positions 0-based and inclusive: the order of equal keys is the one R leaves
fn rf_qsort_i(v: []f64, ix: []i64, lo: i64, hi: i64) {
    var il: [40]i64 = zero
    var iu: [40]i64 = zero
    var i = lo
    var j = hi
    let ii = i
    var m = 1i64
    var rr = 0.375f64
    var vt = 0.0f64
    var vtt = 0.0f64
    var it = 0i64
    var tt = 0i64
    var k = 0i64
    var l = 0i64
    var ij = 0i64
    var st = 10i64
    while true {
        if st == 10i64 {
            if i < j {
                if rr < 0.5898437f64 {
                    rr += 0.0390625f64
                } else {
                    rr -= 0.21875f64
                }
                st = 20i64
            } else {
                st = 80i64
            }
            continue
        }
        if st == 20i64 {
            k = i
            ij = i + i64(f64(j - i) * rr)
            it = ix[ux(ij)]
            vt = v[ux(ij)]
            if v[ux(i)] > vt {
                ix[ux(ij)] = ix[ux(i)]
                ix[ux(i)] = it
                it = ix[ux(ij)]
                v[ux(ij)] = v[ux(i)]
                v[ux(i)] = vt
                vt = v[ux(ij)]
            }
            l = j
            if v[ux(j)] < vt {
                ix[ux(ij)] = ix[ux(j)]
                ix[ux(j)] = it
                it = ix[ux(ij)]
                v[ux(ij)] = v[ux(j)]
                v[ux(j)] = vt
                vt = v[ux(ij)]
                if v[ux(i)] > vt {
                    ix[ux(ij)] = ix[ux(i)]
                    ix[ux(i)] = it
                    it = ix[ux(ij)]
                    v[ux(ij)] = v[ux(i)]
                    v[ux(i)] = vt
                    vt = v[ux(ij)]
                }
            }
            var going = true
            while going {
                l -= 1i64
                while v[ux(l)] > vt { l -= 1i64 }
                tt = ix[ux(l)]
                vtt = v[ux(l)]
                k += 1i64
                while v[ux(k)] < vt { k += 1i64 }
                if k > l {
                    going = false
                } else {
                    ix[ux(l)] = ix[ux(k)]
                    ix[ux(k)] = tt
                    v[ux(l)] = v[ux(k)]
                    v[ux(k)] = vtt
                }
            }
            m += 1i64
            if l - i <= j - k {
                il[ux(m)] = k
                iu[ux(m)] = j
                j = l
            } else {
                il[ux(m)] = i
                iu[ux(m)] = l
                i = k
            }
            st = 30i64
            continue
        }
        if st == 80i64 {
            if m == 1i64 { ret }
            i = il[ux(m)]
            j = iu[ux(m)]
            m -= 1i64
            st = 30i64
            continue
        }
        if st == 30i64 {
            if j - i > 10i64 {
                st = 20i64
                continue
            }
            if i == ii {
                st = 10i64
                continue
            }
            i -= 1i64
            st = 100i64
            continue
        }
        // st == 100: insertion sort of the short segment
        var scanning = true
        var finished = false
        while scanning {
            i += 1i64
            if i == j {
                finished = true
                scanning = false
            } else {
                it = ix[ux(i + 1i64)]
                vt = v[ux(i + 1i64)]
                if !(vt >= v[ux(i)]) { scanning = false }
            }
        }
        if finished {
            st = 80i64
            continue
        }
        k = i
        var shifting = true
        while shifting {
            ix[ux(k + 1i64)] = ix[ux(k)]
            v[ux(k + 1i64)] = v[ux(k)]
            k -= 1i64
            if !(vt < v[ux(k)]) { shifting = false }
        }
        ix[ux(k + 1i64)] = it
        v[ux(k + 1i64)] = vt
    }
}

// the rows a tree is grown from: sampleDataRows without weights
fn rf_sample_rows(g: *rng.Rng, pop: i64, size: i64, replace: bool, out: []i64, work: []i64) {
    var i = 0i64
    if replace {
        while i < size {
            out[ux(i)] = i64(rng.unif(g) * f64(pop))
            i += 1i64
        }
        ret
    }
    while i < pop {
        work[ux(i)] = i
        i += 1i64
    }
    var last = pop - 1i64
    i = 0i64
    while i < size {
        let cs = i64(rng.unif(g) * f64(last + 1i64))
        let kk = work[ux(cs)]
        work[ux(cs)] = work[ux(last)]
        work[ux(last)] = kk
        last -= 1i64
        out[ux(i)] = kk
        i += 1i64
    }
}

// permuteOOB: the out-of-bag values of variable m shuffled in place
fn rf_permute_oob(g: *rng.Rng, m: i64, x: []f64, inbag: []i64, ns: i64, mdim: i64, tp: []f64) {
    var noob = 0i64
    var i = 0i64
    while i < ns {
        if inbag[ux(i)] == 0i64 {
            tp[ux(noob)] = x[ux(m + i * mdim)]
            noob += 1i64
        }
        i += 1i64
    }
    var last = noob
    i = 0i64
    while i < noob {
        let kk = i64(f64(last) * rng.unif(g))
        let tmp = tp[ux(last - 1i64)]
        tp[ux(last - 1i64)] = tp[ux(kk)]
        tp[ux(kk)] = tmp
        last -= 1i64
        i += 1i64
    }
    noob = 0i64
    i = 0i64
    while i < ns {
        if inbag[ux(i)] == 0i64 {
            x[ux(m + i * mdim)] = tp[ux(noob)]
            noob += 1i64
        }
        i += 1i64
    }
}

// computeProximity
fn rf_proximity(prox: []f64, oobprox: bool, node: []i64, inbag: []i64, oobpair: []i64, n: i64) {
    var i = 0i64
    while i < n {
        var j = i + 1i64
        while j < n {
            if oobprox {
                if !(inbag[ux(i)] > 0i64 || inbag[ux(j)] > 0i64) {
                    oobpair[ux(j * n + i)] += 1i64
                    oobpair[ux(i * n + j)] += 1i64
                    if node[ux(i)] == node[ux(j)] {
                        prox[ux(j * n + i)] += 1.0f64
                        prox[ux(i * n + j)] += 1.0f64
                    }
                }
            } else {
                if node[ux(i)] == node[ux(j)] {
                    prox[ux(j * n + i)] += 1.0f64
                    prox[ux(i * n + j)] += 1.0f64
                }
            }
            j += 1i64
        }
        i += 1i64
    }
}

// ---------------------------------------------------------------- regression

type RW = struct { rows: []i64, nodestart: []i64, npts: []i64, ut: []f64, xt: []f64, vv: []f64, yl: []f64, vars: []i64, ncase: []i64 }

// regTree.c findBestSplit for numeric predictors; the answer is (var + 1 or -1, decsplit, split value, last left position)
fn rf_reg_findbest(g: *rng.Rng, w: *RW, x: []const f64, y: []const f64, mdim: i64, ns: i64, ndstart: i64, ndend: i64, mtry: i64, sumnode: f64, nodecount: i64) -> (i64, f64, f64, i64) {
    var bestvar = -1i64
    var best_all = 0.0f64
    var value_at_best = 0.0f64
    var best_split = 0.0f64
    var i = 0i64
    while i < mdim {
        w.vars[ux(i)] = i
        i += 1i64
    }
    var last = mdim - 1i64
    var tie_var = 1i64
    i = 0i64
    while i < mtry {
        var best_within = 0.0f64
        var j = i64(rng.unif(g) * f64(last + 1i64))
        let kv = w.vars[ux(j)]
        w.vars[ux(j)] = w.vars[ux(last)]
        w.vars[ux(last)] = kv
        last -= 1i64
        j = ndstart
        while j <= ndend {
            w.xt[ux(j)] = x[ux(kv + (w.rows[ux(j)] - 1i64) * mdim)]
            w.yl[ux(j)] = y[ux(w.rows[ux(j)] - 1i64)]
            w.vv[ux(j)] = w.xt[ux(j)]
            j += 1i64
        }
        j = 1i64
        while j <= ns {
            w.ncase[ux(j - 1i64)] = j
            j += 1i64
        }
        rf_qsort_i(w.vv, w.ncase, ndstart, ndend)
        if !(w.vv[ux(ndstart)] >= w.vv[ux(ndend)]) {
            let crit_parent = sumnode * sumnode / f64(nodecount)
            var suml = 0.0f64
            var sumr = sumnode
            var npopl = 0i64
            var npopr = nodecount
            var tie_val = 1i64
            j = ndstart
            while j <= ndend - 1i64 {
                let d = w.yl[ux(w.ncase[ux(j)] - 1i64)]
                suml += d
                sumr -= d
                npopl += 1i64
                npopr -= 1i64
                if w.vv[ux(j)] < w.vv[ux(j + 1i64)] {
                    let crit = (suml * suml / f64(npopl)) + (sumr * sumr / f64(npopr)) - crit_parent
                    if crit > best_within {
                        value_at_best = (w.vv[ux(j)] + w.vv[ux(j + 1i64)]) / 2.0f64
                        best_within = crit
                        tie_val = 1i64
                    }
                    if crit == best_within {
                        tie_val += 1i64
                        if rng.unif(g) < 1.0f64 / f64(tie_val) {
                            value_at_best = (w.vv[ux(j)] + w.vv[ux(j + 1i64)]) / 2.0f64
                            best_within = crit
                        }
                    }
                }
                j += 1i64
            }
            if best_within > best_all {
                best_split = value_at_best
                bestvar = kv + 1i64
                best_all = best_within
                j = ndstart
                while j <= ndend {
                    w.ut[ux(j)] = w.xt[ux(j)]
                    j += 1i64
                }
                tie_var = 1i64
            }
            if best_within == best_all {
                tie_var += 1i64
                if rng.unif(g) < 1.0f64 / f64(tie_var) {
                    best_split = value_at_best
                    bestvar = kv + 1i64
                    best_all = best_within
                    j = ndstart
                    while j <= ndend {
                        w.ut[ux(j)] = w.xt[ux(j)]
                        j += 1i64
                    }
                }
            }
        }
        i += 1i64
    }
    var ndendl = 0i64
    if bestvar != -1i64 {
        var nl = ndstart
        var j = ndstart
        while j <= ndend {
            if w.ut[ux(j)] <= best_split {
                nl += 1i64
                w.ncase[ux(nl - 1i64)] = w.rows[ux(j)]
            }
            j += 1i64
        }
        ndendl = math.max[i64](nl - 1i64, ndstart)
        var nr = ndendl + 1i64
        j = ndstart
        while j <= ndend {
            if w.ut[ux(j)] > best_split {
                if nr >= ns { break }
                nr += 1i64
                w.ncase[ux(nr - 1i64)] = w.rows[ux(j)]
            }
            j += 1i64
        }
        if ndendl >= ndend { ndendl = ndend - 1i64 }
        j = ndstart
        while j <= ndend {
            w.rows[ux(j)] = w.ncase[ux(j)]
            j += 1i64
        }
    }
    ret (bestvar, best_all, best_split, ndendl)
}

// regTree: one tree on the bootstrap sample (xb, yb); the tree size is returned
fn rf_reg_tree(g: *rng.Rng, w: *RW, xb: []const f64, yb: []const f64, mdim: i64, ns: i64, ld: []i64, rd: []i64, split: []f64, nmean: []f64, nstat: []i64, nnodes: i64, nthsize: i64, mtry: i64, bvar: []i64, tgini: []f64, vused: []i64) -> i64 {
    var i = 0i64
    while i < nnodes {
        nstat[ux(i)] = 0i64
        w.nodestart[ux(i)] = 0i64
        w.npts[ux(i)] = 0i64
        nmean[ux(i)] = 0.0f64
        i += 1i64
    }
    i = 1i64
    while i <= ns {
        w.rows[ux(i - 1i64)] = i
        i += 1i64
    }
    var cur = 0i64
    w.npts[0usize] = ns
    nstat[0usize] = -2i64
    var node_mean = 0.0f64
    i = 0i64
    while i < ns {
        let label = yb[ux(w.rows[ux(i)] - 1i64)]
        node_mean = (f64(i) * node_mean + label) / f64(i + 1i64)
        i += 1i64
    }
    nmean[0usize] = node_mean
    var k = -1i64
    while true {
        k += 1i64
        if k >= nnodes - 2i64 { break }
        if k > cur || cur >= nnodes - 2i64 { break }
        if nstat[ux(k)] != -2i64 { continue }
        let ndstart = w.nodestart[ux(k)]
        let ndend = ndstart + w.npts[ux(k)] - 1i64
        let count = w.npts[ux(k)]
        let sumnode = f64(count) * nmean[ux(k)]
        let (msplit, decsplit, ubest, ndendl) = rf_reg_findbest(g, w, xb, yb, mdim, ns, ndstart, ndend, mtry, sumnode, count)
        if msplit == -1i64 {
            nstat[ux(k)] = -1i64
            continue
        }
        bvar[ux(k)] = msplit - 1i64
        vused[ux(msplit - 1i64)] = 1i64
        split[ux(k)] = ubest
        tgini[ux(msplit - 1i64)] += decsplit
        nstat[ux(k)] = -3i64
        w.npts[ux(cur + 1i64)] = ndendl - ndstart + 1i64
        w.npts[ux(cur + 2i64)] = ndend - ndendl
        w.nodestart[ux(cur + 1i64)] = ndstart
        w.nodestart[ux(cur + 2i64)] = ndendl + 1i64
        node_mean = 0.0f64
        var j = ndstart
        while j <= ndendl {
            let label = yb[ux(w.rows[ux(j)] - 1i64)]
            let mm = j - ndstart
            node_mean = (f64(mm) * node_mean + label) / f64(mm + 1i64)
            j += 1i64
        }
        nmean[ux(cur + 1i64)] = node_mean
        nstat[ux(cur + 1i64)] = -2i64
        if w.npts[ux(cur + 1i64)] <= nthsize { nstat[ux(cur + 1i64)] = -1i64 }
        node_mean = 0.0f64
        j = ndendl + 1i64
        while j <= ndend {
            let label = yb[ux(w.rows[ux(j)] - 1i64)]
            let mm = j - (ndendl + 1i64)
            node_mean = (f64(mm) * node_mean + label) / f64(mm + 1i64)
            j += 1i64
        }
        nmean[ux(cur + 2i64)] = node_mean
        nstat[ux(cur + 2i64)] = -2i64
        if w.npts[ux(cur + 2i64)] <= nthsize { nstat[ux(cur + 2i64)] = -1i64 }
        ld[ux(k)] = cur + 1i64
        rd[ux(k)] = cur + 2i64
        cur += 2i64
    }
    var tsize = nnodes
    k = nnodes - 1i64
    while k >= 0i64 {
        if nstat[ux(k)] == 0i64 { tsize -= 1i64 }
        if nstat[ux(k)] == -2i64 { nstat[ux(k)] = -1i64 }
        k -= 1i64
    }
    ret tsize
}

// predictRegTree / predictClassTree for numeric predictors: the terminal node of every row (0-based)
fn rf_walk(x: []const f64, n: i64, mdim: i64, ld: []const i64, rd: []const i64, nstat: []const i64, split: []const f64, bvar: []const i64, node: []i64) {
    var i = 0i64
    while i < n {
        var k = 0i64
        while nstat[ux(k)] != -1i64 {
            let m = bvar[ux(k)]
            if x[ux(m + i * mdim)] <= split[ux(k)] {
                k = ld[ux(k)]
            } else {
                k = rd[ux(k)]
            }
        }
        node[ux(i)] = k
        i += 1i64
    }
}

// simpleLinReg: y on x over the cases that have a prediction; the coefficients go to coef and the mean squared residual is returned
fn rf_linreg(x: []const f64, y: []const f64, n: i64, haspred: []const i64, coef: []f64) -> f64 {
    var nout = 0i64
    var sxx = 0.0f64
    var sxy = 0.0f64
    var xbar = 0.0f64
    var ybar = 0.0f64
    var i = 0i64
    while i < n {
        if haspred[ux(i)] != 0i64 {
            nout += 1i64
            xbar += x[ux(i)]
            ybar += y[ux(i)]
        }
        i += 1i64
    }
    xbar /= f64(nout)
    ybar /= f64(nout)
    i = 0i64
    while i < n {
        if haspred[ux(i)] != 0i64 {
            let dx = x[ux(i)] - xbar
            let dy = y[ux(i)] - ybar
            sxx += dx * dx
            sxy += dx * dy
        }
        i += 1i64
    }
    coef[1usize] = sxy / sxx
    coef[0usize] = ybar - coef[1usize] * xbar
    var mse = 0.0f64
    i = 0i64
    while i < n {
        if haspred[ux(i)] != 0i64 {
            let py = coef[0usize] + coef[1usize] * x[ux(i)]
            let dy = y[ux(i)] - py
            mse += dy * dy
        }
        i += 1i64
    }
    ret mse / f64(nout)
}

// regRF: the regression forest. `y` is the raw response; x is p by n (variable fastest), copied because importance permutes it.
fn rf_fit_reg(a: *mem.Arena, g: *rng.Rng, x0: []const f64, y0: []const f64, n: usize, p: usize, o: *const Opts, ts: *const TestSet) -> (Fit, err) {
    var f: Fit = zero
    let nts = ts.n
    let ns = i64(n)
    let mdim = i64(p)
    let ntree = o.ntree
    let sampsize = i64(o.sampsize)
    var nrn = 2i64 * sampsize + 1i64
    if o.maxnodes > 0usize {
        let mn = 2i64 * i64(o.maxnodes) - 1i64
        nrn = math.min[i64](nrn, math.max[i64](mn, 1i64))
    }
    let nrnu = ux(nrn)
    f.n = n
    f.mdim = p
    f.ntree = ntree
    f.nclass = 0usize
    f.nrnodes = nrnu
    f.ymean = rf_mean(y0)
    let (y, e0) = rf_f64s(a, n)
    let (x, e1) = rf_f64s(a, n * p)
    if e0 != ok { ret (f, e0) }
    if e1 != ok { ret (f, e1) }
    var i = 0usize
    while i < n {
        y[i] = y0[i] - f.ymean
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        x[i] = x0[i]
        i += 1usize
    }
    let (ndbig, e2) = rf_i64s(a, ntree)
    let (status, e3) = rf_i64s(a, ntree * nrnu)
    let (bvar, e4) = rf_i64s(a, ntree * nrnu)
    let (left, e5) = rf_i64s(a, ntree * nrnu)
    let (right, e6) = rf_i64s(a, ntree * nrnu)
    let (xsplit, e7) = rf_f64s(a, ntree * nrnu)
    let (pred, e8) = rf_f64s(a, ntree * nrnu)
    let (oobn, e9) = rf_i64s(a, n)
    let (ypred, e10) = rf_f64s(a, n)
    let (mse, e11) = rf_f64s(a, ntree)
    let (imp, e12) = rf_f64s(a, 2usize * p)
    let (impsd, e13) = rf_f64s(a, p)
    var nim = 1usize
    if o.local_imp { nim = n * p }
    let (impmat, e14) = rf_f64s(a, nim)
    var npx = 1usize
    if o.proximity { npx = n * n }
    let (prox, e15) = rf_f64s(a, npx)
    let (oobpair, e16) = rf_i64s(a, npx)
    var nib = 1usize
    if o.keep_inbag { nib = n * ntree }
    let (inbag, e17) = rf_i64s(a, nib)
    let (ytree, t1) = rf_f64s(a, nts)
    let (nodexts, t2) = rf_i64s(a, nts)
    let (ytp, t3) = rf_f64s(a, nts)
    let (coef, t6) = rf_f64s(a, 2usize)
    if t6 != ok { ret (f, mem.Exhausted) }
    let (msets, t4) = rf_f64s(a, ntree)
    var npt = 1usize
    if o.proximity && nts > 0usize { npt = nts * (nts + n) }
    let (proxts, t5) = rf_f64s(a, npt)
    if t1 != ok || t2 != ok || t3 != ok || t4 != ok || t5 != ok { ret (f, mem.Exhausted) }
    if e2 != ok { ret (f, e2) }
    if e3 != ok { ret (f, e3) }
    if e4 != ok { ret (f, e4) }
    if e5 != ok { ret (f, e5) }
    if e6 != ok { ret (f, e6) }
    if e7 != ok { ret (f, e7) }
    if e8 != ok { ret (f, e8) }
    if e9 != ok { ret (f, e9) }
    if e10 != ok { ret (f, e10) }
    if e11 != ok { ret (f, e11) }
    if e12 != ok { ret (f, e12) }
    if e13 != ok { ret (f, e13) }
    if e14 != ok { ret (f, e14) }
    if e15 != ok { ret (f, e15) }
    if e16 != ok { ret (f, e16) }
    if e17 != ok { ret (f, e17) }
    let (yb, f1) = rf_f64s(a, o.sampsize)
    let (xb, f2) = rf_f64s(a, o.sampsize * p)
    let (ytr, f3) = rf_f64s(a, n)
    let (xtmp, f4) = rf_f64s(a, n)
    let (resoob, f5) = rf_f64s(a, n)
    let (inb, f6) = rf_i64s(a, n)
    let (nodex, f7) = rf_i64s(a, n)
    let (vused, f8) = rf_i64s(a, p)
    let (sidx, f9) = rf_i64s(a, o.sampsize)
    let (work, f10) = rf_i64s(a, n)
    let (tp, f11) = rf_f64s(a, n)
    let (tgini, f12) = rf_f64s(a, p)
    var w: RW = zero
    let (w1, h1) = rf_i64s(a, o.sampsize)
    let (w2, h2) = rf_i64s(a, nrnu)
    let (w3, h3) = rf_i64s(a, nrnu)
    let (w4, h4) = rf_f64s(a, o.sampsize)
    let (w5, h5) = rf_f64s(a, o.sampsize)
    let (w6, h6) = rf_f64s(a, o.sampsize)
    let (w7, h7) = rf_f64s(a, o.sampsize)
    let (w8, h8) = rf_i64s(a, p)
    let (w9, h9) = rf_i64s(a, o.sampsize)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok || f11 != ok || f12 != ok { ret (f, mem.Exhausted) }
    if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok || h8 != ok || h9 != ok { ret (f, mem.Exhausted) }
    w.rows = w1
    w.nodestart = w2
    w.npts = w3
    w.ut = w4
    w.xt = w5
    w.vv = w6
    w.yl = w7
    w.vars = w8
    w.ncase = w9
    var j = 0i64
    let ntr = i64(ntree)
    let nperm = i64(o.nperm)
    while j < ntr {
        let idx = j * nrn
        var q = 0i64
        while q < ns {
            inb[ux(q)] = 0i64
            q += 1i64
        }
        q = 0i64
        while q < mdim {
            vused[ux(q)] = 0i64
            q += 1i64
        }
        rf_sample_rows(g, ns, sampsize, o.replace, sidx, work)
        q = 0i64
        while q < sampsize {
            let kk = sidx[ux(q)]
            inb[ux(kk)] += 1i64
            yb[ux(q)] = y[ux(kk)]
            var m = 0i64
            while m < mdim {
                xb[ux(m + q * mdim)] = x[ux(m + kk * mdim)]
                m += 1i64
            }
            q += 1i64
        }
        if o.keep_inbag {
            q = 0i64
            while q < ns {
                inbag[ux(j * ns + q)] = inb[ux(q)]
                q += 1i64
            }
        }
        let tsize = rf_reg_tree(g, &w, xb, yb, mdim, sampsize, left[ux(idx)..ux(idx + nrn)], right[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], pred[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], nrn, i64(o.nodesize), i64(o.mtry), bvar[ux(idx)..ux(idx + nrn)], tgini, vused)
        ndbig[ux(j)] = tsize
        rf_walk(x, ns, mdim, left[ux(idx)..ux(idx + nrn)], right[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodex)
        q = 0i64
        while q < ns {
            ytr[ux(q)] = pred[ux(idx + nodex[ux(q)])]
            q += 1i64
        }
        var errb = 0.0f64
        var ooberr = 0.0f64
        var jout = 0i64
        var noob = 0i64
        q = 0i64
        while q < ns {
            if inb[ux(q)] == 0i64 {
                oobn[ux(q)] += 1i64
                noob += 1i64
                ypred[ux(q)] = (f64(oobn[ux(q)] - 1i64) * ypred[ux(q)] + ytr[ux(q)]) / f64(oobn[ux(q)])
                resoob[ux(q)] = ytr[ux(q)] - y[ux(q)]
                ooberr += resoob[ux(q)] * resoob[ux(q)]
            }
            if oobn[ux(q)] != 0i64 {
                jout += 1i64
                errb += (y[ux(q)] - ypred[ux(q)]) * (y[ux(q)] - ypred[ux(q)])
            }
            q += 1i64
        }
        errb /= f64(jout)
        if o.corr_bias { errb = rf_linreg(ypred, y, ns, oobn, coef) }
        var errts = 0.0f64
        if nts > 0usize {
            rf_walk(ts.x, i64(nts), mdim, left[ux(idx)..ux(idx + nrn)], right[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodexts)
            q = 0i64
            while q < i64(nts) {
                ytree[ux(q)] = pred[ux(idx + nodexts[ux(q)])]
                ytp[ux(q)] = (f64(j) * ytp[ux(q)] + ytree[ux(q)]) / f64(j + 1i64)
                q += 1i64
            }
            if ts.labels {
                q = 0i64
                while q < i64(nts) {
                    var resid = 0.0f64
                    if o.corr_bias {
                        resid = (ts.y[ux(q)] - f.ymean) - (coef[0usize] + coef[1usize] * ytp[ux(q)])
                    } else {
                        resid = (ts.y[ux(q)] - f.ymean) - ytp[ux(q)]
                    }
                    errts += resid * resid
                    q += 1i64
                }
                errts /= f64(nts)
            }
        }
        mse[ux(j)] = errb
        if ts.labels { msets[ux(j)] = errts }
        if o.proximity {
            rf_proximity(prox, o.oob_prox, nodex, inb, oobpair, ns)
            if nts > 0usize {
                rf_proximity(proxts, false, nodexts, inb, oobpair, i64(nts))
                var tn = 0i64
                while tn < i64(nts) {
                    var tk = 0i64
                    while tk < ns {
                        if nodexts[ux(tn)] == nodex[ux(tk)] { proxts[ux(tn + i64(nts) * (tk + i64(nts)))] += 1.0f64 }
                        tk += 1i64
                    }
                    tn += 1i64
                }
            }
        }
        if o.importance {
            var mr = 0i64
            while mr < mdim {
                if vused[ux(mr)] != 0i64 {
                    q = 0i64
                    while q < ns {
                        xtmp[ux(q)] = x[ux(mr + q * mdim)]
                        q += 1i64
                    }
                    var ooberrperm = 0.0f64
                    var kp = 0i64
                    while kp < nperm {
                        rf_permute_oob(g, mr, x, inb, ns, mdim, tp)
                        rf_walk(x, ns, mdim, left[ux(idx)..ux(idx + nrn)], right[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodex)
                        q = 0i64
                        while q < ns {
                            ytr[ux(q)] = pred[ux(idx + nodex[ux(q)])]
                            q += 1i64
                        }
                        q = 0i64
                        while q < ns {
                            if inb[ux(q)] == 0i64 {
                                let rv = ytr[ux(q)] - y[ux(q)]
                                ooberrperm += rv * rv
                                if o.local_imp {
                                    impmat[ux(mr + q * mdim)] += (rv * rv - resoob[ux(q)] * resoob[ux(q)]) / f64(nperm)
                                }
                            }
                            q += 1i64
                        }
                        kp += 1i64
                    }
                    let delta = (ooberrperm / f64(nperm) - ooberr) / f64(noob)
                    imp[ux(mr)] += delta
                    impsd[ux(mr)] += delta * delta
                    q = 0i64
                    while q < ns {
                        x[ux(mr + q * mdim)] = xtmp[ux(q)]
                        q += 1i64
                    }
                }
                mr += 1i64
            }
        }
        j += 1i64
    }
    if o.proximity {
        var q = 0i64
        while q < ns {
            var kk = q + 1i64
            while kk < ns {
                var den = f64(ntr)
                if o.oob_prox {
                    if oobpair[ux(ns * kk + q)] > 0i64 {
                        den = f64(oobpair[ux(ns * kk + q)])
                    } else {
                        den = 1.0f64
                    }
                }
                prox[ux(ns * kk + q)] /= den
                prox[ux(ns * q + kk)] = prox[ux(ns * kk + q)]
                kk += 1i64
            }
            prox[ux(ns * q + q)] = 1.0f64
            q += 1i64
        }
        if nts > 0usize {
            q = 0i64
            while q < i64(nts) * (i64(nts) + ns) {
                proxts[ux(q)] /= f64(ntr)
                q += 1i64
            }
        }
    }
    if o.corr_bias {
        i = 0usize
        while i < n {
            if oobn[i] != 0i64 { ypred[i] = coef[0usize] + coef[1usize] * ypred[i] }
            i += 1usize
        }
        i = 0usize
        while i < nts {
            ytp[i] = coef[0usize] + coef[1usize] * ytp[i]
            i += 1usize
        }
    }
    i = 0usize
    while i < nts {
        ytp[i] += f.ymean
        i += 1usize
    }
    f.corr = o.corr_bias
    f.coef[0usize] = coef[0usize]
    f.coef[1usize] = coef[1usize]
    f.treg = ytp
    f.terr = msets
    f.tprox = proxts
    var m = 0i64
    while m < mdim {
        if o.importance {
            imp[ux(m)] = imp[ux(m)] / f64(ntr)
            impsd[ux(m)] = math.sqrt[f64](((impsd[ux(m)] / f64(ntr)) - (imp[ux(m)] * imp[ux(m)])) / f64(ntr))
            if o.local_imp {
                var q = 0i64
                while q < ns {
                    impmat[ux(m + q * mdim)] /= f64(oobn[ux(q)])
                    q += 1i64
                }
            }
        }
        imp[ux(mdim + m)] = tgini[ux(m)] / f64(ntr)
        m += 1i64
    }
    // the forest component stores the node means with the response mean added back
    j = 0i64
    while j < ntr * nrn {
        pred[ux(j)] += f.ymean
        j += 1i64
    }
    i = 0usize
    while i < n {
        ypred[i] += f.ymean
        i += 1usize
    }
    f.ndbig = ndbig
    f.status = status
    f.bvar = bvar
    f.left = left
    f.right = right
    f.xsplit = xsplit
    f.pred = pred
    f.oobn = oobn
    f.ypred = ypred
    f.err = mse
    f.imp = imp
    f.impsd = impsd
    f.impmat = impmat
    f.prox = prox
    f.inbag = inbag
    ret (f, ok)
}

// predict.randomForest for a regression forest: the mean of the trees' answers (ntest rows, variable fastest), through the bias correction when the
// forest has one
fn rf_predict_reg(a: *mem.Arena, f: *const Fit, xnew: []const f64, ntest: usize, out: []f64) -> err {
    let (junk, e1) = rf_f64s(a, 1usize)
    let (jn, e2) = rf_i64s(a, 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    ret rf_predict_reg_full(a, f, xnew, ntest, out, junk, false, jn, false, junk, false)
}

// ... with the proximity of the rows (ntest by ntest), the terminal node of every row and tree (1-based, ntest by ntree) and every tree's answer (ntest by ntree)
fn rf_predict_reg_full(a: *mem.Arena, f: *const Fit, xnew: []const f64, ntest: usize, out: []f64, prox: []f64, doprox: bool, nodes: []i64, keepnodes: bool, allpred: []f64, keepall: bool) -> err {
    let (node, e) = rf_i64s(a, ntest)
    if e != ok { ret e }
    let nrn = i64(f.nrnodes)
    var i = 0usize
    while i < ntest {
        out[i] = 0.0f64
        i += 1usize
    }
    if doprox {
        i = 0usize
        while i < ntest * ntest {
            prox[i] = 0.0f64
            i += 1usize
        }
    }
    let (junk, e3) = rf_i64s(a, 1usize)
    if e3 != ok { ret e3 }
    var t = 0i64
    while t < i64(f.ntree) {
        let idx = ux(t * nrn)
        let end = ux(t * nrn + nrn)
        rf_walk(xnew, i64(ntest), i64(f.mdim), f.left[idx..end], f.right[idx..end], f.status[idx..end], f.xsplit[idx..end], f.bvar[idx..end], node)
        i = 0usize
        while i < ntest {
            out[i] += f.pred[idx + usize(node[i])]
            if keepall { allpred[i + usize(t) * ntest] = f.pred[idx + usize(node[i])] }
            if keepnodes { nodes[i + usize(t) * ntest] = node[i] + 1i64 }
            i += 1usize
        }
        if doprox { rf_proximity(prox, false, node, junk, junk, i64(ntest)) }
        t += 1i64
    }
    i = 0usize
    while i < ntest {
        out[i] = out[i] / f64(f.ntree)
        i += 1usize
    }
    if doprox {
        i = 0usize
        while i < ntest {
            var j = i + 1usize
            while j < ntest {
                prox[i + j * ntest] /= f64(f.ntree)
                prox[j + i * ntest] = prox[i + j * ntest]
                j += 1usize
            }
            prox[i + i * ntest] = 1.0f64
            i += 1usize
        }
    }
    if f.corr {
        i = 0usize
        while i < ntest {
            out[i] = f.coef[0usize] + f.coef[1usize] * out[i]
            i += 1usize
        }
    }
    ret ok
}

// ------------------------------------------------------------ classification

type CW = struct {
    mdim: i64, ns: i64, nclass: i64, nrn: i64,
    a: []i64, b: []i64, ta: []i64, idmove: []i64, ncase: []i64, mind: []i64, cls: []i64, vused: []i64,
    win: []f64, wr: []f64, wl: []f64, tpop: []f64, classpop: []f64, tgini: []f64,
    nodestart: []i64, nodepop: []i64, bsplit: []i64, bnext: []i64
}

// the Fortran findbestsplit for numeric predictors: (jstat, variable, position, decrease)
fn rf_findbest(g: *rng.Rng, w: *CW, ndstart: i64, ndend: i64, mtry: i64) -> (i64, i64, i64, f64) {
    let nclass = w.nclass
    let mdim = w.mdim
    var pno = 0.0f64
    var pdo = 0.0f64
    var j = 0i64
    while j < nclass {
        pno += w.tpop[ux(j)] * w.tpop[ux(j)]
        pdo += w.tpop[ux(j)]
        j += 1i64
    }
    let crit0 = pno / pdo
    var critmax = f64(-1.0e25f32)
    var msplit = -1i64
    var best = 0i64
    j = 0i64
    while j < mdim {
        w.mind[ux(j)] = j
        j += 1i64
    }
    var nn = mdim
    var mt = 0i64
    while mt < mtry {
        let jj = i64(f64(nn) * rng.unif(g))
        let mvar = w.mind[ux(jj)]
        w.mind[ux(jj)] = w.mind[ux(nn - 1i64)]
        w.mind[ux(nn - 1i64)] = mvar
        nn -= 1i64
        var rrn = pno
        var rrd = pdo
        var rln = 0.0f64
        var rld = 0.0f64
        j = 0i64
        while j < nclass {
            w.wl[ux(j)] = 0.0f64
            w.wr[ux(j)] = w.tpop[ux(j)]
            j += 1i64
        }
        var ntie = 1i64
        var nsp = ndstart
        while nsp < ndend {
            let nc = w.a[ux(mvar + nsp * mdim)]
            let u = w.win[ux(nc)]
            let kc = w.cls[ux(nc)]
            rln = rln + u * (2.0f64 * w.wl[ux(kc)] + u)
            rrn = rrn + u * (-2.0f64 * w.wr[ux(kc)] + u)
            rld = rld + u
            rrd = rrd - u
            w.wl[ux(kc)] = w.wl[ux(kc)] + u
            w.wr[ux(kc)] = w.wr[ux(kc)] - u
            let nxt = w.a[ux(mvar + (nsp + 1i64) * mdim)]
            if w.b[ux(mvar + nc * mdim)] < w.b[ux(mvar + nxt * mdim)] {
                if math.min[f64](rrd, rld) > f64(1.0e-5f32) {
                    let crit = (rln / rld) + (rrn / rrd)
                    if crit > critmax {
                        best = nsp
                        critmax = crit
                        msplit = mvar
                        ntie = 1i64
                    }
                    if crit == critmax {
                        ntie += 1i64
                        if rng.unif(g) < f64(1.0f32 / f32(ntie)) {
                            best = nsp
                            critmax = crit
                            msplit = mvar
                        }
                    }
                }
            }
            nsp += 1i64
        }
        mt += 1i64
    }
    var jstat = 0i64
    if critmax < f64(-1.0e10f32) || msplit == -1i64 { jstat = -1i64 }
    ret (jstat, msplit, best, critmax - crit0)
}

// buildtree + movedata: the tree size (nodes used); nuse is the number of distinct in-bag rows
fn rf_buildtree(g: *rng.Rng, w: *CW, nuse: i64, ndsize: i64, mtry: i64, status: []i64, bvar: []i64, tleft: []i64, nodeclass: []i64) -> i64 {
    let nrn = w.nrn
    let nclass = w.nclass
    let mdim = w.mdim
    var i = 0i64
    while i < nrn {
        status[ux(i)] = 0i64
        w.nodestart[ux(i)] = 0i64
        w.nodepop[ux(i)] = 0i64
        i += 1i64
    }
    i = 0i64
    while i < nclass * nrn {
        w.classpop[ux(i)] = 0.0f64
        i += 1i64
    }
    i = 0i64
    while i < nclass {
        w.classpop[ux(i)] = w.tpop[ux(i)]
        i += 1i64
    }
    var ncur = 1i64
    w.nodestart[0usize] = 0i64
    w.nodepop[0usize] = nuse
    status[0usize] = 2i64
    var kb = 0i64
    while kb < nrn {
        if kb >= ncur { break }
        if status[ux(kb)] != 2i64 {
            kb += 1i64
            continue
        }
        let ndstart = w.nodestart[ux(kb)]
        let ndend = ndstart + w.nodepop[ux(kb)] - 1i64
        i = 0i64
        while i < nclass {
            w.tpop[ux(i)] = w.classpop[ux(i + kb * nclass)]
            i += 1i64
        }
        let (jstat, msplit, best, dec0) = rf_findbest(g, w, ndstart, ndend, mtry)
        if jstat == -1i64 {
            status[ux(kb)] = -1i64
            kb += 1i64
            continue
        }
        var decsplit = dec0
        bvar[ux(kb)] = msplit
        w.vused[ux(msplit)] = 1i64
        if decsplit < 0.0f64 { decsplit = 0.0f64 }
        w.tgini[ux(msplit)] += decsplit
        w.bsplit[ux(kb)] = w.a[ux(msplit + best * mdim)]
        w.bnext[ux(kb)] = w.a[ux(msplit + (best + 1i64) * mdim)]
        // movedata
        i = ndstart
        while i <= best {
            w.idmove[ux(w.a[ux(msplit + i * mdim)])] = 1i64
            i += 1i64
        }
        i = best + 1i64
        while i <= ndend {
            w.idmove[ux(w.a[ux(msplit + i * mdim)])] = 0i64
            i += 1i64
        }
        let ndendl = best
        var msh = 0i64
        while msh < mdim {
            var kk = ndstart
            i = ndstart
            while i <= ndend {
                let ih = w.a[ux(msh + i * mdim)]
                if w.idmove[ux(ih)] == 1i64 {
                    w.ta[ux(kk)] = ih
                    kk += 1i64
                }
                i += 1i64
            }
            i = ndstart
            while i <= ndend {
                let ih = w.a[ux(msh + i * mdim)]
                if w.idmove[ux(ih)] == 0i64 {
                    w.ta[ux(kk)] = ih
                    kk += 1i64
                }
                i += 1i64
            }
            i = ndstart
            while i <= ndend {
                w.a[ux(msh + i * mdim)] = w.ta[ux(i)]
                i += 1i64
            }
            msh += 1i64
        }
        i = ndstart
        while i <= ndend {
            w.ncase[ux(i)] = w.a[ux(msplit + i * mdim)]
            i += 1i64
        }
        w.nodepop[ux(ncur)] = ndendl - ndstart + 1i64
        w.nodepop[ux(ncur + 1i64)] = ndend - ndendl
        w.nodestart[ux(ncur)] = ndstart
        w.nodestart[ux(ncur + 1i64)] = ndendl + 1i64
        i = ndstart
        while i <= ndendl {
            let nc = w.ncase[ux(i)]
            let jc = w.cls[ux(nc)]
            w.classpop[ux(jc + ncur * nclass)] = w.classpop[ux(jc + ncur * nclass)] + w.win[ux(nc)]
            i += 1i64
        }
        i = ndendl + 1i64
        while i <= ndend {
            let nc = w.ncase[ux(i)]
            let jc = w.cls[ux(nc)]
            w.classpop[ux(jc + (ncur + 1i64) * nclass)] = w.classpop[ux(jc + (ncur + 1i64) * nclass)] + w.win[ux(nc)]
            i += 1i64
        }
        status[ux(ncur)] = 2i64
        status[ux(ncur + 1i64)] = 2i64
        if w.nodepop[ux(ncur)] <= ndsize { status[ux(ncur)] = -1i64 }
        if w.nodepop[ux(ncur + 1i64)] <= ndsize { status[ux(ncur + 1i64)] = -1i64 }
        var popt1 = 0.0f64
        var popt2 = 0.0f64
        i = 0i64
        while i < nclass {
            popt1 = popt1 + w.classpop[ux(i + ncur * nclass)]
            popt2 = popt2 + w.classpop[ux(i + (ncur + 1i64) * nclass)]
            i += 1i64
        }
        i = 0i64
        while i < nclass {
            if w.classpop[ux(i + ncur * nclass)] == popt1 { status[ux(ncur)] = -1i64 }
            if w.classpop[ux(i + (ncur + 1i64) * nclass)] == popt2 { status[ux(ncur + 1i64)] = -1i64 }
            i += 1i64
        }
        tleft[ux(kb)] = ncur
        status[ux(kb)] = 1i64
        ncur += 2i64
        if ncur >= nrn { break }
        kb += 1i64
    }
    var ndbig = nrn
    var k = nrn - 1i64
    while k >= 0i64 {
        if status[ux(k)] == 0i64 { ndbig -= 1i64 }
        if status[ux(k)] == 2i64 { status[ux(k)] = -1i64 }
        k -= 1i64
    }
    var kn = 0i64
    while kn < ndbig {
        if status[ux(kn)] == -1i64 {
            var pp = 0.0f64
            var ntie = 1i64
            var jc = 0i64
            while jc < nclass {
                let cp = w.classpop[ux(jc + kn * nclass)]
                if cp > pp {
                    nodeclass[ux(kn)] = jc
                    pp = cp
                    ntie = 1i64
                }
                if cp == pp {
                    ntie += 1i64
                    if rng.unif(g) < f64(1.0f32 / f32(ntie)) {
                        nodeclass[ux(kn)] = jc
                        pp = cp
                    }
                }
                jc += 1i64
            }
        }
        kn += 1i64
    }
    ret ndbig
}

// oob(): the OOB class of every case seen so far and the error rates for this tree (errtr: overall, then by class)
fn rf_oob(g: *rng.Rng, ns: i64, nclass: i64, cls: []const i64, counttr: []const i64, out: []const i64, errtr: []f64, jest: []i64, cutoff: []const f64, noobcl: []i64) {
    var i = 0i64
    while i <= nclass {
        errtr[ux(i)] = 0.0f64
        i += 1i64
    }
    i = 0i64
    while i < nclass {
        noobcl[ux(i)] = 0i64
        i += 1i64
    }
    var noob = 0i64
    var n = 0i64
    while n < ns {
        if out[ux(n)] != 0i64 {
            noob += 1i64
            noobcl[ux(cls[ux(n)])] += 1i64
            var smaxtr = 0.0f64
            var ntie = 1i64
            var j = 0i64
            while j < nclass {
                let qq = (f64(counttr[ux(j + n * nclass)]) / f64(out[ux(n)])) / cutoff[ux(j)]
                if qq > smaxtr {
                    smaxtr = qq
                    jest[ux(n)] = j + 1i64
                    ntie = 1i64
                }
                if qq == smaxtr {
                    ntie += 1i64
                    if rng.unif(g) < 1.0f64 / f64(ntie) {
                        smaxtr = qq
                        jest[ux(n)] = j + 1i64
                    }
                }
                j += 1i64
            }
            if jest[ux(n)] != cls[ux(n)] + 1i64 {
                errtr[ux(cls[ux(n)] + 1i64)] += 1.0f64
                errtr[0usize] += 1.0f64
            }
        }
        n += 1i64
    }
    errtr[0usize] /= f64(noob)
    i = 1i64
    while i <= nclass {
        errtr[ux(i)] /= f64(noobcl[ux(i - 1i64)])
        i += 1i64
    }
}

// TestSetError: the test-set votes after tree nvote, the predicted classes (1-based) with R's tie draws, and the error rates when the labels are known
fn rf_test_error(g: *rng.Rng, countts: []f64, jts: []const i64, clts: []const i64, jet: []i64, ntest: i64, nclass: i64, nvote: i64, errts: []f64, labelts: bool, nclts: []const i64, cutoff: []const f64) {
    var n = 0i64
    while n < ntest {
        countts[ux(jts[ux(n)] + n * nclass)] += 1.0f64
        n += 1i64
    }
    n = 0i64
    while n < ntest {
        var cmax = 0.0f64
        var ntie = 1i64
        var j = 0i64
        while j < nclass {
            let crit = (countts[ux(j + n * nclass)] / f64(nvote)) / cutoff[ux(j)]
            if crit > cmax {
                jet[ux(n)] = j + 1i64
                cmax = crit
                ntie = 1i64
            }
            if crit == cmax {
                ntie += 1i64
                if rng.unif(g) < 1.0f64 / f64(ntie) {
                    jet[ux(n)] = j + 1i64
                    cmax = crit
                }
            }
            j += 1i64
        }
        n += 1i64
    }
    if labelts {
        var i = 0i64
        while i <= nclass {
            errts[ux(i)] = 0.0f64
            i += 1i64
        }
        n = 0i64
        while n < ntest {
            if jet[ux(n)] != clts[ux(n)] {
                errts[0usize] += 1.0f64
                errts[ux(clts[ux(n)])] += 1.0f64
            }
            n += 1i64
        }
        errts[0usize] /= f64(ntest)
        i = 1i64
        while i <= nclass {
            errts[ux(i)] /= f64(nclts[ux(i - 1i64)])
            i += 1i64
        }
    }
}

// classRF: the classification forest. `cl` holds 1-based class labels; x is p by n (variable fastest). `classwt` and `cutoff` have nclass entries
// (classwt is read only when o.use_classwt). The OOB votes are counts; the importance matrix `cimp` is p by (nclass + 2) column-major:
// per-class decrease, MeanDecreaseAccuracy, MeanDecreaseGini; `impsd` is p by (nclass + 1).
fn rf_fit_class(a: *mem.Arena, g: *rng.Rng, x0: []const f64, cl: []const i64, nclass: usize, n: usize, p: usize, classwt_in: []const f64, cutoff: []const f64, o: *const Opts, ts: *const TestSet) -> (Fit, err) {
    var f: Fit = zero
    let nts = ts.n
    let ns = i64(n)
    let mdim = i64(p)
    let nc = i64(nclass)
    let ntree = o.ntree
    let sampsize = i64(o.sampsize)
    var nrn = 2i64 * sampsize + 1i64
    if o.maxnodes > 0usize {
        let mn = 2i64 * i64(o.maxnodes) - 1i64
        nrn = math.min[i64](nrn, math.max[i64](mn, 1i64))
    }
    let nrnu = ux(nrn)
    f.n = n
    f.mdim = p
    f.ntree = ntree
    f.nclass = nclass
    f.nrnodes = nrnu
    let (x, e1) = rf_f64s(a, n * p)
    let (cls, e2) = rf_i64s(a, n)
    let (classwt, e3) = rf_f64s(a, nclass)
    let (freq, e4) = rf_i64s(a, nclass)
    if e1 != ok { ret (f, e1) }
    if e2 != ok { ret (f, e2) }
    if e3 != ok { ret (f, e3) }
    if e4 != ok { ret (f, e4) }
    var i = 0usize
    while i < n * p {
        x[i] = x0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        cls[i] = cl[i] - 1i64
        freq[usize(cls[i])] += 1i64
        i += 1usize
    }
    // normClassWt
    if o.use_classwt {
        var sumwt = 0.0f64
        i = 0usize
        while i < nclass {
            sumwt += classwt_in[i]
            i += 1usize
        }
        i = 0usize
        while i < nclass {
            classwt[i] = classwt_in[i] / sumwt
            i += 1usize
        }
    } else {
        i = 0usize
        while i < nclass {
            classwt[i] = f64(freq[i]) / f64(n)
            i += 1usize
        }
    }
    i = 0usize
    while i < nclass {
        if freq[i] != 0i64 {
            classwt[i] = classwt[i] * f64(n) / f64(freq[i])
        } else {
            classwt[i] = 0.0f64
        }
        i += 1usize
    }
    let (ndbig, g1) = rf_i64s(a, ntree)
    let (status, g2) = rf_i64s(a, ntree * nrnu)
    let (bvar, g3) = rf_i64s(a, ntree * nrnu)
    let (left, g4) = rf_i64s(a, ntree * nrnu)
    let (xsplit, g5) = rf_f64s(a, ntree * nrnu)
    let (pred, g6) = rf_f64s(a, ntree * nrnu)
    let (nodeclass, g7) = rf_i64s(a, ntree * nrnu)
    let (counttr, g8) = rf_i64s(a, n * nclass)
    let (outn, g9) = rf_i64s(a, n)
    let (outcl, g10) = rf_i64s(a, n)
    let (errtr, g11) = rf_f64s(a, (nclass + 1usize) * ntree)
    let (cimp, g12) = rf_f64s(a, (nclass + 2usize) * p)
    let (impsd, g13) = rf_f64s(a, (nclass + 1usize) * p)
    var nim = 1usize
    if o.local_imp { nim = n * p }
    let (impmat, g14) = rf_f64s(a, nim)
    var npx = 1usize
    if o.proximity { npx = n * n }
    let (prox, g15) = rf_f64s(a, npx)
    let (oobpair, g16) = rf_i64s(a, npx)
    var nib = 1usize
    if o.keep_inbag { nib = n * ntree }
    let (inbag, g17) = rf_i64s(a, nib)
    let (countts, t1) = rf_f64s(a, nts * nclass)
    let (outclts, t2) = rf_i64s(a, nts)
    let (jts, t3) = rf_i64s(a, nts)
    let (nodexts, t4) = rf_i64s(a, nts)
    let (errts, t5) = rf_f64s(a, (nclass + 1usize) * ntree)
    let (nclts, t6) = rf_i64s(a, nclass)
    var npt = 1usize
    if o.proximity && nts > 0usize { npt = nts * (nts + n) }
    let (proxts, t7) = rf_f64s(a, npt)
    if t1 != ok || t2 != ok || t3 != ok || t4 != ok || t5 != ok || t6 != ok || t7 != ok { ret (f, mem.Exhausted) }
    if ts.labels {
        i = 0usize
        while i < nts {
            nclts[usize(ts.cl[i] - 1i64)] += 1i64
            i += 1usize
        }
    }
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok || g10 != ok || g11 != ok || g12 != ok || g13 != ok || g14 != ok || g15 != ok || g16 != ok || g17 != ok { ret (f, mem.Exhausted) }
    // scratch
    var w: CW = zero
    w.mdim = mdim
    w.ns = ns
    w.nclass = nc
    w.nrn = nrn
    let (at, h1) = rf_i64s(a, n * p)
    let (wa, h2) = rf_i64s(a, n * p)
    let (wb, h3) = rf_i64s(a, n * p)
    let (wta, h4) = rf_i64s(a, n)
    let (wid, h5) = rf_i64s(a, n)
    let (wnc, h6) = rf_i64s(a, n)
    let (wmind, h7) = rf_i64s(a, p)
    let (wvu, h8) = rf_i64s(a, p)
    let (wwin, h9) = rf_f64s(a, n)
    let (wwr, h10) = rf_f64s(a, nclass)
    let (wwl, h11) = rf_f64s(a, nclass)
    let (wtp, h12) = rf_f64s(a, nclass)
    let (wcp, h13) = rf_f64s(a, nclass * nrnu)
    let (wtg, h14) = rf_f64s(a, p)
    let (wns, h15) = rf_i64s(a, nrnu)
    let (wnp, h16) = rf_i64s(a, nrnu)
    let (wbs, h17) = rf_i64s(a, nrnu)
    let (wbn, h18) = rf_i64s(a, nrnu)
    let (jin, h19) = rf_i64s(a, n)
    let (sidx, h20) = rf_i64s(a, n)
    let (work, h21) = rf_i64s(a, n)
    let (jtr, h22) = rf_i64s(a, n)
    let (jvr, h23) = rf_i64s(a, n)
    let (nodex, h24) = rf_i64s(a, n)
    let (tx, h25) = rf_f64s(a, n)
    let (tp, h26) = rf_f64s(a, n)
    let (nout, h27) = rf_i64s(a, nclass)
    let (nright, h28) = rf_i64s(a, nclass)
    let (nrightimp, h29) = rf_i64s(a, nclass)
    let (noobcl, h30) = rf_i64s(a, nclass)
    let (sv, h31) = rf_f64s(a, n)
    let (si, h32) = rf_i64s(a, n)
    if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok || h8 != ok || h9 != ok || h10 != ok || h11 != ok || h12 != ok || h13 != ok || h14 != ok || h15 != ok || h16 != ok { ret (f, mem.Exhausted) }
    if h17 != ok || h18 != ok || h19 != ok || h20 != ok || h21 != ok || h22 != ok || h23 != ok || h24 != ok || h25 != ok || h26 != ok || h27 != ok || h28 != ok || h29 != ok || h30 != ok || h31 != ok || h32 != ok { ret (f, mem.Exhausted) }
    w.a = wa
    w.b = wb
    w.ta = wta
    w.idmove = wid
    w.ncase = wnc
    w.mind = wmind
    w.cls = cls
    w.vused = wvu
    w.win = wwin
    w.wr = wwr
    w.wl = wwl
    w.tpop = wtp
    w.classpop = wcp
    w.tgini = wtg
    w.nodestart = wns
    w.nodepop = wnp
    w.bsplit = wbs
    w.bnext = wbn
    // makeA: the cases of each variable in ascending order, and the rank of the distinct values
    var v = 0i64
    while v < mdim {
        var q = 0i64
        while q < ns {
            sv[ux(q)] = x[ux(v + q * mdim)]
            si[ux(q)] = q
            q += 1i64
        }
        rf_qsort_i(sv, si, 0i64, ns - 1i64)
        q = 0i64
        while q < ns - 1i64 {
            let n1 = si[ux(q)]
            let n2 = si[ux(q + 1i64)]
            at[ux(v + q * mdim)] = n1
            if q == 0i64 { w.b[ux(v + n1 * mdim)] = 1i64 }
            if sv[ux(q)] < sv[ux(q + 1i64)] {
                w.b[ux(v + n2 * mdim)] = w.b[ux(v + n1 * mdim)] + 1i64
            } else {
                w.b[ux(v + n2 * mdim)] = w.b[ux(v + n1 * mdim)]
            }
            q += 1i64
        }
        at[ux(v + (ns - 1i64) * mdim)] = si[ux(ns - 1i64)]
        v += 1i64
    }
    var j = 0i64
    let ntr = i64(ntree)
    var idx = 0i64
    var idn = 0i64
    while j < ntr {
        var guard = 0i64
        var nuse = 0i64
        var ndb = 1i64
        while ndb == 1i64 {
            guard += 1i64
            if guard > 100000i64 { ret (f, Degenerate) }
            var q = 0i64
            while q < nrn {
                status[ux(idx + q)] = 0i64
                left[ux(idx + q)] = 0i64
                xsplit[ux(idx + q)] = 0.0f64
                nodeclass[ux(idx + q)] = 0i64
                q += 1i64
            }
            q = 0i64
            while q < mdim {
                w.vused[ux(q)] = 0i64
                q += 1i64
            }
            var ntry = 0i64
            var nempty = 0i64
            var more = true
            while more {
                nempty = 0i64
                q = 0i64
                while q < ns {
                    jin[ux(q)] = 0i64
                    w.win[ux(q)] = 0.0f64
                    q += 1i64
                }
                q = 0i64
                while q < nc {
                    w.tpop[ux(q)] = 0.0f64
                    q += 1i64
                }
                rf_sample_rows(g, ns, sampsize, o.replace, sidx, work)
                q = 0i64
                while q < sampsize {
                    let kk = sidx[ux(q)]
                    w.tpop[ux(cls[ux(kk)])] += classwt[ux(cls[ux(kk)])]
                    w.win[ux(kk)] += classwt[ux(cls[ux(kk)])]
                    jin[ux(kk)] += 1i64
                    q += 1i64
                }
                q = 0i64
                while q < nc {
                    if w.tpop[ux(q)] == 0.0f64 { nempty += 1i64 }
                    q += 1i64
                }
                ntry += 1i64
                more = nc - nempty < 2i64 && ntry <= 30i64
            }
            if nc - nempty < 2i64 { ret (f, Degenerate) }
            if o.keep_inbag {
                q = 0i64
                while q < ns {
                    inbag[ux(idn + q)] = jin[ux(q)]
                    q += 1i64
                }
            }
            // modA: the in-bag cases of every variable's ordering
            nuse = 0i64
            q = 0i64
            while q < ns {
                if jin[ux(q)] != 0i64 { nuse += 1i64 }
                q += 1i64
            }
            var vv = 0i64
            while vv < mdim {
                var nt = 0i64
                q = 0i64
                while q < ns {
                    let c = at[ux(vv + q * mdim)]
                    if jin[ux(c)] != 0i64 {
                        w.a[ux(vv + nt * mdim)] = c
                        nt += 1i64
                    }
                    q += 1i64
                }
                vv += 1i64
            }
            ndb = rf_buildtree(g, &w, nuse, i64(o.nodesize), i64(o.mtry), status[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], left[ux(idx)..ux(idx + nrn)], nodeclass[ux(idx)..ux(idx + nrn)])
        }
        ndbig[ux(j)] = ndb
        // Xtranslate
        var t = 0i64
        while t < ndb {
            if status[ux(idx + t)] == 1i64 {
                let m = bvar[ux(idx + t)]
                xsplit[ux(idx + t)] = 0.5f64 * (x[ux(m + w.bsplit[ux(t)] * mdim)] + x[ux(m + w.bnext[ux(t)] * mdim)])
            }
            t += 1i64
        }
        if nts > 0usize {
            rf_walk_class(ts.x, i64(nts), mdim, left[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodeclass[ux(idx)..ux(idx + nrn)], jts, nodexts)
            rf_test_error(g, countts, jts, ts.cl, outclts, i64(nts), nc, j + 1i64, errts[ux(j * (nc + 1i64))..ux((j + 1i64) * (nc + 1i64))], ts.labels, nclts, cutoff)
        }
        // out-of-bag votes
        rf_walk_class(x, ns, mdim, left[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodeclass[ux(idx)..ux(idx + nrn)], jtr, nodex)
        rf_zero_i(nout, nc)
        var noutall = 0i64
        var n1 = 0i64
        while n1 < ns {
            if jin[ux(n1)] == 0i64 {
                counttr[ux(n1 * nc + jtr[ux(n1)])] += 1i64
                outn[ux(n1)] += 1i64
                nout[ux(cls[ux(n1)])] += 1i64
                noutall += 1i64
            }
            n1 += 1i64
        }
        rf_oob(g, ns, nc, cls, counttr, outn, errtr[ux(j * (nc + 1i64))..ux((j + 1i64) * (nc + 1i64))], outcl, cutoff, noobcl)
        if o.proximity {
            rf_proximity(prox, o.oob_prox, nodex, jin, oobpair, ns)
            if nts > 0usize {
                rf_proximity(proxts, false, nodexts, jin, oobpair, i64(nts))
                var tn = 0i64
                while tn < i64(nts) {
                    var tk = 0i64
                    while tk < ns {
                        if nodexts[ux(tn)] == nodex[ux(tk)] { proxts[ux(tn + i64(nts) * (tk + i64(nts)))] += 1.0f64 }
                        tk += 1i64
                    }
                    tn += 1i64
                }
            }
        }
        if o.importance {
            var nrightall = 0i64
            rf_zero_i(nright, nc)
            n1 = 0i64
            while n1 < ns {
                if jin[ux(n1)] == 0i64 && jtr[ux(n1)] == cls[ux(n1)] {
                    nright[ux(cls[ux(n1)])] += 1i64
                    nrightall += 1i64
                }
                n1 += 1i64
            }
            var m = 0i64
            while m < mdim {
                if w.vused[ux(m)] != 0i64 {
                    var nrightimpall = 0i64
                    rf_zero_i(nrightimp, nc)
                    n1 = 0i64
                    while n1 < ns {
                        tx[ux(n1)] = x[ux(m + n1 * mdim)]
                        n1 += 1i64
                    }
                    rf_permute_oob(g, m, x, jin, ns, mdim, tp)
                    rf_walk_class(x, ns, mdim, left[ux(idx)..ux(idx + nrn)], status[ux(idx)..ux(idx + nrn)], xsplit[ux(idx)..ux(idx + nrn)], bvar[ux(idx)..ux(idx + nrn)], nodeclass[ux(idx)..ux(idx + nrn)], jvr, nodex)
                    n1 = 0i64
                    while n1 < ns {
                        x[ux(m + n1 * mdim)] = tx[ux(n1)]
                        if jin[ux(n1)] == 0i64 {
                            if jvr[ux(n1)] == cls[ux(n1)] {
                                nrightimp[ux(cls[ux(n1)])] += 1i64
                                nrightimpall += 1i64
                            }
                            if o.local_imp && jvr[ux(n1)] != jtr[ux(n1)] {
                                if cls[ux(n1)] == jvr[ux(n1)] {
                                    impmat[ux(m + n1 * mdim)] -= 1.0f64
                                } else {
                                    impmat[ux(m + n1 * mdim)] += 1.0f64
                                }
                            }
                        }
                        n1 += 1i64
                    }
                    var kc = 0i64
                    while kc < nc {
                        if nout[ux(kc)] > 0i64 {
                            let delta = f64(nright[ux(kc)] - nrightimp[ux(kc)]) / f64(nout[ux(kc)])
                            cimp[ux(m + kc * mdim)] += delta
                            impsd[ux(m + kc * mdim)] += delta * delta
                        }
                        kc += 1i64
                    }
                    if noutall > 0i64 {
                        let delta = f64(nrightall - nrightimpall) / f64(noutall)
                        cimp[ux(m + nc * mdim)] += delta
                        impsd[ux(m + nc * mdim)] += delta * delta
                    }
                }
                m += 1i64
            }
        }
        idx += nrn
        if o.keep_inbag { idn += ns }
        j += 1i64
    }
    var m = 0i64
    while m < mdim {
        w.tgini[ux(m)] /= f64(ntr)
        m += 1i64
    }
    m = 0i64
    while m < mdim {
        if o.importance {
            if o.local_imp {
                var q = 0i64
                while q < ns {
                    impmat[ux(m + q * mdim)] /= f64(outn[ux(q)])
                    q += 1i64
                }
            }
            var kc = 0i64
            while kc < nc {
                let av = cimp[ux(m + kc * mdim)] / f64(ntr)
                impsd[ux(m + kc * mdim)] = math.sqrt[f64](((impsd[ux(m + kc * mdim)] / f64(ntr)) - av * av) / f64(ntr))
                cimp[ux(m + kc * mdim)] = av
                kc += 1i64
            }
            let av2 = cimp[ux(m + nc * mdim)] / f64(ntr)
            impsd[ux(m + nc * mdim)] = math.sqrt[f64](((impsd[ux(m + nc * mdim)] / f64(ntr)) - av2 * av2) / f64(ntr))
            cimp[ux(m + nc * mdim)] = av2
            cimp[ux(m + (nc + 1i64) * mdim)] = w.tgini[ux(m)]
        } else {
            cimp[ux(m + (nc + 1i64) * mdim)] = w.tgini[ux(m)]
        }
        m += 1i64
    }
    if o.proximity {
        var q = 0i64
        while q < ns {
            var kk = q + 1i64
            while kk < ns {
                var den = f64(ntr)
                if o.oob_prox {
                    if oobpair[ux(ns * kk + q)] > 0i64 {
                        den = f64(oobpair[ux(ns * kk + q)])
                    } else {
                        den = 1.0f64
                    }
                }
                prox[ux(ns * kk + q)] /= den
                prox[ux(ns * q + kk)] = prox[ux(ns * kk + q)]
                kk += 1i64
            }
            prox[ux(ns * q + q)] = 1.0f64
            q += 1i64
        }
        if nts > 0usize {
            q = 0i64
            while q < i64(nts) {
                var kk = 0i64
                while kk < i64(nts) + ns {
                    proxts[ux(i64(nts) * kk + q)] /= f64(ntr)
                    kk += 1i64
                }
                proxts[ux(i64(nts) * q + q)] = 1.0f64
                q += 1i64
            }
        }
    }
    f.tcls = outclts
    f.tvotes = countts
    f.terr = errts
    f.tprox = proxts
    // the forest keeps the class (0-based) of a node in `pred`
    var z = 0i64
    while z < ntr * nrn {
        pred[ux(z)] = f64(nodeclass[ux(z)])
        z += 1i64
    }
    f.ndbig = ndbig
    f.status = status
    f.bvar = bvar
    f.left = left
    f.xsplit = xsplit
    f.pred = pred
    f.votes = counttr
    f.oobn = outn
    f.outcl = outcl
    f.err = errtr
    f.cimp = cimp
    f.impsd = impsd
    f.impmat = impmat
    f.prox = prox
    f.inbag = inbag
    ret (f, ok)
}

fn rf_zero_i(s: []i64, n: i64) {
    var i = 0i64
    while i < n {
        s[ux(i)] = 0i64
        i += 1i64
    }
}

// the terminal node of every row, and its class (classification trees: the right child is the node after the left)
fn rf_walk_class(x: []const f64, n: i64, mdim: i64, ld: []const i64, nstat: []const i64, split: []const f64, bvar: []const i64, nodeclass: []const i64, jts: []i64, node: []i64) {
    var i = 0i64
    while i < n {
        var k = 0i64
        while nstat[ux(k)] != -1i64 {
            let m = bvar[ux(k)]
            if x[ux(m + i * mdim)] <= split[ux(k)] {
                k = ld[ux(k)]
            } else {
                k = ld[ux(k)] + 1i64
            }
        }
        jts[ux(i)] = nodeclass[ux(k)]
        node[ux(i)] = k
        i += 1i64
    }
}

// classForest: vote counts (ntest by nclass, class fastest) and the predicted class (1-based) of every row, with R's tie draws from `g`
fn rf_predict_class(a: *mem.Arena, g: *rng.Rng, f: *const Fit, xnew: []const f64, ntest: usize, cutoff: []const f64, counts: []f64, jet: []i64) -> err {
    let (junk, e1) = rf_f64s(a, 1usize)
    let (jn, e2) = rf_i64s(a, 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    ret rf_predict_class_full(a, g, f, xnew, ntest, cutoff, counts, jet, junk, false, jn, false, jn, false)
}

// ... with the proximity of the rows, the terminal node (1-based) and the class (1-based) of every row and tree (both ntest by ntree)
fn rf_predict_class_full(a: *mem.Arena, g: *rng.Rng, f: *const Fit, xnew: []const f64, ntest: usize, cutoff: []const f64, counts: []f64, jet: []i64, prox: []f64, doprox: bool, nodes: []i64, keepnodes: bool, allpred: []i64, keepall: bool) -> err {
    let (jts, e1) = rf_i64s(a, ntest)
    let (node, e2) = rf_i64s(a, ntest)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let nrn = i64(f.nrnodes)
    let nc = i64(f.nclass)
    var i = 0usize
    while i < ntest * f.nclass {
        counts[i] = 0.0f64
        i += 1usize
    }
    if doprox {
        i = 0usize
        while i < ntest * ntest {
            prox[i] = 0.0f64
            i += 1usize
        }
    }
    let (nodecls, e3) = rf_i64s(a, f.ntree * f.nrnodes)
    if e3 != ok { ret e3 }
    var q = 0usize
    while q < f.ntree * f.nrnodes {
        nodecls[q] = i64(f.pred[q])
        q += 1usize
    }
    var t = 0i64
    while t < i64(f.ntree) {
        let lo = ux(t * nrn)
        let hi = ux(t * nrn + nrn)
        rf_walk_class(xnew, i64(ntest), i64(f.mdim), f.left[lo..hi], f.status[lo..hi], f.xsplit[lo..hi], f.bvar[lo..hi], nodecls[lo..hi], jts, node)
        i = 0usize
        while i < ntest {
            counts[usize(jts[i]) + i * f.nclass] += 1.0f64
            if keepall { allpred[i + usize(t) * ntest] = jts[i] + 1i64 }
            if keepnodes { nodes[i + usize(t) * ntest] = node[i] + 1i64 }
            i += 1usize
        }
        if doprox { rf_proximity(prox, false, node, jts, jts, i64(ntest)) }
        t += 1i64
    }
    i = 0usize
    while i < ntest {
        var cmax = 0.0f64
        var ntie = 1i64
        var jc = 0i64
        while jc < nc {
            let crit = (counts[usize(jc) + i * f.nclass] / f64(f.ntree)) / cutoff[usize(jc)]
            if crit > cmax {
                jet[i] = jc + 1i64
                cmax = crit
                ntie = 1i64
            }
            if crit == cmax {
                ntie += 1i64
                if rng.unif(g) < 1.0f64 / f64(ntie) { jet[i] = jc + 1i64 }
            }
            jc += 1i64
        }
        i += 1usize
    }
    if doprox {
        i = 0usize
        while i < ntest {
            var j = i + 1usize
            while j < ntest {
                prox[i + j * ntest] /= f64(f.ntree)
                prox[j + i * ntest] = prox[i + j * ntest]
                j += 1usize
            }
            prox[i + i * ntest] = 1.0f64
            i += 1usize
        }
    }
    ret ok
}

// seq(min(x), max(x), length = npt) as seq.default builds it
fn rf_grid(xmin: f64, xmax: f64, npt: usize, out: []f64) {
    out[0usize] = xmin
    if npt < 2usize { ret }
    out[npt - 1usize] = xmax
    let by = (xmax - xmin) / f64(npt - 1usize)
    var i = 1usize
    while i + 1usize < npt {
        out[i] = xmin + f64(i) * by
        i += 1usize
    }
}

// partialPlot of a classification forest: the grid xpt over the range of variable `v` of xdata and the partial dependence ypt of class `focus` (0-based)
fn rf_partial_class(a: *mem.Arena, g: *rng.Rng, f: *const Fit, xdata: []const f64, n: usize, v: usize, focus: usize, npt: usize, cutoff: []const f64, xpt: []f64, ypt: []f64) -> err {
    let p = f.mdim
    let kk = f.nclass
    let (xd, e1) = rf_f64s(a, n * p)
    let (counts, e2) = rf_f64s(a, n * kk)
    let (jet, e3) = rf_i64s(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n * p {
        xd[i] = xdata[i]
        i += 1usize
    }
    var lo = xdata[v]
    var hi = xdata[v]
    i = 1usize
    while i < n {
        if xdata[v + i * p] < lo { lo = xdata[v + i * p] }
        if xdata[v + i * p] > hi { hi = xdata[v + i * p] }
        i += 1usize
    }
    rf_grid(lo, hi, npt, xpt)
    let eps = 2.220446049250313e-16f64
    var q = 0usize
    while q < npt {
        i = 0usize
        while i < n {
            xd[v + i * p] = xpt[q]
            i += 1usize
        }
        let e4 = rf_predict_class(a, g, f, xd, n, cutoff, counts, jet)
        if e4 != ok { ret e4 }
        var total = 0.0f64
        i = 0usize
        while i < n {
            var pf = counts[focus + i * kk] / f64(f.ntree)
            if pf == 0.0f64 { pf = eps }
            var rm = 0.0f64
            var c = 0usize
            while c < kk {
                var pv = counts[c + i * kk] / f64(f.ntree)
                if pv == 0.0f64 { pv = eps }
                rm += math.log[f64](pv)
                c += 1usize
            }
            total += math.log[f64](pf) - rm / f64(kk)
            i += 1usize
        }
        ypt[q] = total / f64(n)
        q += 1usize
    }
    ret ok
}

// partialPlot of a regression forest
fn rf_partial_reg(a: *mem.Arena, f: *const Fit, xdata: []const f64, n: usize, v: usize, npt: usize, xpt: []f64, ypt: []f64) -> err {
    let p = f.mdim
    let (xd, e1) = rf_f64s(a, n * p)
    let (pr, e2) = rf_f64s(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n * p {
        xd[i] = xdata[i]
        i += 1usize
    }
    var lo = xdata[v]
    var hi = xdata[v]
    i = 1usize
    while i < n {
        if xdata[v + i * p] < lo { lo = xdata[v + i * p] }
        if xdata[v + i * p] > hi { hi = xdata[v + i * p] }
        i += 1usize
    }
    rf_grid(lo, hi, npt, xpt)
    var q = 0usize
    while q < npt {
        i = 0usize
        while i < n {
            xd[v + i * p] = xpt[q]
            i += 1usize
        }
        let e3 = rf_predict_reg(a, f, xd, n, pr)
        if e3 != ok { ret e3 }
        var total = 0.0f64
        i = 0usize
        while i < n {
            total += pr[i]
            i += 1usize
        }
        ypt[q] = total / f64(n)
        q += 1usize
    }
    ret ok
}
