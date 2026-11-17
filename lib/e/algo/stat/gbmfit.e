// R gbm 2.x, the compiled boosting engine (gbm_engine.cpp, tree.cpp, node_search.cpp and the distributions) ported line for line: the in-bag selection sampling through R's
// Mersenne-Twister stream, trees grown best-first over the bagged rows with the running left/right sums of the C++ node search (so ties between equal splits fall the way gbm's do),
// the per-distribution working response, leaf refit, deviance and out-of-bag improvement, the held-out rows scored tree by tree, and the trees stored in the gbm list layout
// (pretty.gbm.tree: split variable, split code, left/right/missing node, error reduction, weight, prediction).
//
// Distributions (spec.dist): 0 gaussian, 1 bernoulli, 2 poisson, 3 adaboost, 4 laplace, 5 quantile, 6 huberized, 7 tdist, 8 coxph, 9 multinomial.
//
// Not here: categorical predictors, offsets, pairwise (see gbmrank), the loess smoother behind gbm.perf(method = "OOB").

use e.math
use e.mem
use e.algo.rand.r as rng

const UMAX: usize = 18446744073709551615usize

error NoMemory

type Spec = struct {
    dist: usize, n: usize, p: usize, ntrain: usize, nclass: usize,
    ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, bag: f64,
    alpha: f64, nu: f64, maxrank: usize, ngroups: usize,
    x: []const f64, y: []const f64, w: []const f64, misc: []const f64, mono: []const f64, off: []const f64, vclass: []const usize, catold: usize
}

// the fitted trees in the layout of R's object$trees: tree (t, k) occupies stride = 3 depth + 1 slots from (t nclass + k) stride
type Model = struct {
    nclass: usize, ntrees: usize, depth: usize, p: usize, stride: usize,
    initf: f64, f: []f64, train_err: []f64, valid_err: []f64, oobag: []f64,
    nnodes: []usize, tvar: []i64, tcode: []f64, tleft: []i64, tright: []i64, tmiss: []i64, terr: []f64, twt: []f64, tpred: []f64,
    maxk: usize, ncs: usize, cs: []i64, vclass: []usize
}

type NS = struct {
    split: bool, init_sumz: f64, init_w: f64, init_n: usize,
    best_var: usize, best_val: f64, best_imp: f64,
    bl_sumz: f64, bl_w: f64, bl_n: usize, br_sumz: f64, br_w: f64, br_n: usize, bm_sumz: f64, bm_w: f64, bm_n: usize,
    cm_sumz: f64, cm_w: f64, cm_n: usize, cl_sumz: f64, cl_w: f64, cl_n: usize, cr_sumz: f64, cr_w: f64, cr_n: usize,
    cur_imp: f64, cur_var: usize, cur_val: f64, last_x: f64, node: usize, best_classes: usize, cur_classes: usize
}

type Ctx = struct {
    sp: Spec, f: []f64, z: []f64, fadj: []f64, inbag: []u8, assign: []usize, order: []usize,
    ns: []NS, term: []usize,
    nd_pred: []f64, nd_w: []f64, nd_n: []usize, nd_isterm: []u8, nd_var: []usize, nd_split: []f64, nd_imp: []f64, nd_left: []usize, nd_right: []usize, nd_miss: []usize,
    nnode: usize, nterm: usize, totinbag: usize, ibest: usize, bestimp: f64,
    prob: []f64, stepprob: []f64, arr: []f64, w2: []f64, num: []f64, den: []f64, mx: []f64, mn: []f64,
    idx: []usize, tmp: []usize, stk: []usize, stp: []usize, sts: []usize, ids: []usize, scr: []f64,
    hm: []f64, k2n: []usize, n2k: []usize,
    maxk: usize, gsum: []f64, gw: []f64, gmean: []f64, gn: []usize, curcat: []usize, bestcat: []usize, nd_ncat: []usize, nd_cats: []usize,
    off: []f64, hasoff: bool, rg: *rng.Rng, hess: []f64, rscore: []f64, ritem: []usize, rrank: []usize, rkpos: []usize, rankw: []f64, cutoff: usize
}

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

fn af(a: *mem.Arena, n: usize, bad: *usize) -> []f64 {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[f64](a, m)
    if e != ok {
        *bad += 1usize
        var z: []f64 = zero
        ret z
    }
    var i = 0usize
    while i < m {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v
}

fn au(a: *mem.Arena, n: usize, bad: *usize) -> []usize {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[usize](a, m)
    if e != ok {
        *bad += 1usize
        var z: []usize = zero
        ret z
    }
    var i = 0usize
    while i < m {
        v[i] = 0usize
        i += 1usize
    }
    ret v
}

fn ab(a: *mem.Arena, n: usize, bad: *usize) -> []u8 {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[u8](a, m)
    if e != ok {
        *bad += 1usize
        var z: []u8 = zero
        ret z
    }
    var i = 0usize
    while i < m {
        v[i] = 0u8
        i += 1usize
    }
    ret v
}

fn ai(a: *mem.Arena, n: usize, bad: *usize) -> []i64 {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[i64](a, m)
    if e != ok {
        *bad += 1usize
        var z: []i64 = zero
        ret z
    }
    var i = 0usize
    while i < m {
        v[i] = 0i64
        i += 1usize
    }
    ret v
}

// R's sum(): a long double accumulation rounded once; here a double-double accumulation, the same to the last bit unless the exact sum sits next to a rounding boundary
fn rsum(v: []const f64, n: usize) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < n {
        let x = v[i]
        let s = hi + x
        let bb = s - hi
        let e = (hi - (s - bb)) + (x - bb)
        hi = s
        lo += e
        i += 1usize
    }
    ret hi + lo
}

// x < y with NA (NaN) first, the order of order(x, na.last = FALSE)
fn lt(x: f64, y: f64) -> bool {
    if x != x { ret y == y }
    if y != y { ret false }
    ret x < y
}

// a stable sort of idx[0..m] by key[idx[i]]
fn msort(key: []const f64, idx: []usize, tmp: []usize, m: usize) {
    var w = 1usize
    while w < m {
        var lo = 0usize
        while lo < m {
            var mid = lo + w
            if mid > m { mid = m }
            var hi = lo + 2usize * w
            if hi > m { hi = m }
            var l = lo
            var r = mid
            var o = lo
            while l < mid && r < hi {
                if lt(key[idx[r]], key[idx[l]]) {
                    tmp[o] = idx[r]
                    r += 1usize
                } else {
                    tmp[o] = idx[l]
                    l += 1usize
                }
                o += 1usize
            }
            while l < mid {
                tmp[o] = idx[l]
                l += 1usize
                o += 1usize
            }
            while r < hi {
                tmp[o] = idx[r]
                r += 1usize
                o += 1usize
            }
            lo += 2usize * w
        }
        var q = 0usize
        while q < m {
            idx[q] = tmp[q]
            q += 1usize
        }
        w = w * 2usize
    }
}

// locationm.cpp: the weighted median of v[0..m]
fn lm_median(c: *Ctx, v: []const f64, w: []const f64, m: usize) -> f64 {
    if m == 0usize { ret 0.0f64 }
    if m == 1usize { ret v[0usize] }
    var i = 0usize
    while i < m {
        c.idx[i] = i
        i += 1usize
    }
    msort(v, c.idx, c.tmp, m)
    var wsum = 0.0f64
    i = 0usize
    while i < m {
        wsum += w[i]
        i += 1usize
    }
    var mi = 0usize
    var first = true
    var cum = 0.0f64
    while cum < 0.5f64 * wsum {
        if first {
            first = false
        } else {
            mi += 1usize
        }
        cum += w[c.idx[mi]]
    }
    var nz = m
    var ii = m - 1usize
    while ii > mi {
        if w[c.idx[ii]] > 0.0f64 { nz = ii }
        ii -= 1usize
    }
    if nz == m || cum > 0.5f64 * wsum { ret v[c.idx[mi]] }
    ret 0.5f64 * (v[c.idx[mi]] + v[c.idx[nz]])
}

// locationm.cpp: the weighted alpha-quantile, the first value whose cumulative weight passes alpha times the total
fn lm_quantile(c: *Ctx, v: []const f64, w: []const f64, m: usize, alpha: f64) -> f64 {
    if m == 0usize { ret 0.0f64 }
    if m == 1usize { ret v[0usize] }
    var i = 0usize
    if alpha <= 0.0f64 {
        var lo = v[0usize]
        i = 1usize
        while i < m {
            if v[i] < lo { lo = v[i] }
            i += 1usize
        }
        ret lo
    }
    if alpha >= 1.0f64 {
        var hi = v[0usize]
        i = 1usize
        while i < m {
            if v[i] > hi { hi = v[i] }
            i += 1usize
        }
        ret hi
    }
    i = 0usize
    while i < m {
        c.idx[i] = i
        i += 1usize
    }
    msort(v, c.idx, c.tmp, m)
    var wsum = 0.0f64
    i = 0usize
    while i < m {
        wsum += w[i]
        i += 1usize
    }
    var qi = 0usize
    var first = true
    var cum = 0.0f64
    while cum <= alpha * wsum {
        if first {
            first = false
        } else {
            qi += 1usize
        }
        cum += w[c.idx[qi]]
    }
    ret v[c.idx[qi]]
}

// locationm.cpp LocationM with the t-distribution psi function (nu degrees of freedom): the iteratively reweighted location of v[0..m]
fn lm_location(c: *Ctx, v: []const f64, w: []const f64, m: usize, nu: f64) -> f64 {
    let eps = 1.0e-8f64
    var beta0 = lm_median(c, v, w, m)
    let dm = c.scr
    var i = 0usize
    while i < m {
        dm[i] = math.abs[f64](v[i] - beta0)
        i += 1usize
    }
    var scale0 = 1.4826f64 * lm_median(c, dm, w, m)
    if eps > scale0 { scale0 = eps }
    var dd = 1.0f64
    var count = 0i64
    while count < 50i64 {
        var swx = 0.0f64
        var sw = 0.0f64
        i = 0usize
        while i < m {
            var t = math.abs[f64](v[i] - beta0) / scale0
            if eps > t { t = eps }
            let wt = w[i] * (t / (nu + t * t)) / t
            swx += wt * v[i]
            sw += wt
            i += 1usize
        }
        var beta = beta0
        if sw > 0.0f64 { beta = swx / sw }
        dd = math.abs[f64](beta - beta0)
        if dd > eps { dd = dd / math.abs[f64](beta0) }
        beta0 = beta
        if dd < eps {
            count = 100i64
        } else {
            count += 1i64
        }
    }
    ret beta0
}

// node.h CNode::Improvement
fn improvement(lw: f64, rw: f64, mw: f64, ls: f64, rs: f64, ms: f64) -> f64 {
    var t = 0.0f64
    var r = 0.0f64
    if mw == 0.0f64 {
        t = ls / lw - rs / rw
        r = lw * rw * t * t / (lw + rw)
    } else {
        t = ls / lw - rs / rw
        r += lw * rw * t * t
        t = ls / lw - ms / mw
        r += lw * mw * t * t
        t = rs / rw - ms / mw
        r += rw * mw * t * t
        r /= (lw + rw + mw)
    }
    ret r
}

fn ns_set(c: *Ctx, k: usize, sumz: f64, w: f64, nn: usize, node: usize) {
    c.ns[k].init_sumz = sumz
    c.ns[k].init_w = w
    c.ns[k].init_n = nn
    c.ns[k].bl_sumz = 0.0f64
    c.ns[k].bl_w = 0.0f64
    c.ns[k].bl_n = 0usize
    c.ns[k].cl_sumz = 0.0f64
    c.ns[k].cl_w = 0.0f64
    c.ns[k].cl_n = 0usize
    c.ns[k].br_sumz = sumz
    c.ns[k].br_w = w
    c.ns[k].br_n = nn
    c.ns[k].cr_sumz = 0.0f64
    c.ns[k].cr_w = w
    c.ns[k].cr_n = nn
    c.ns[k].bm_sumz = 0.0f64
    c.ns[k].bm_w = 0.0f64
    c.ns[k].bm_n = 0usize
    c.ns[k].cm_sumz = 0.0f64
    c.ns[k].cm_w = 0.0f64
    c.ns[k].cm_n = 0usize
    c.ns[k].best_imp = 0.0f64
    c.ns[k].best_var = UMAX
    c.ns[k].best_val = 0.0f64
    c.ns[k].cur_imp = 0.0f64
    c.ns[k].cur_var = UMAX
    c.ns[k].cur_val = 0.0f64 - 1.0f64 / 0.0f64
    c.ns[k].split = false
    c.ns[k].node = node
    c.ns[k].best_classes = 0usize
    c.ns[k].cur_classes = 0usize
}

fn ns_reset(c: *Ctx, k: usize, iv: usize) {
    if c.ns[k].split { ret }
    c.ns[k].cur_var = iv
    var cls = 0usize
    if c.sp.vclass.len > iv { cls = c.sp.vclass[iv] }
    c.ns[k].cur_classes = cls
    var gi = 0usize
    while gi < cls {
        c.gsum[k * c.maxk + gi] = 0.0f64
        c.gw[k * c.maxk + gi] = 0.0f64
        c.gn[k * c.maxk + gi] = 0usize
        gi += 1usize
    }
    c.ns[k].cl_sumz = 0.0f64
    c.ns[k].cl_w = 0.0f64
    c.ns[k].cl_n = 0usize
    c.ns[k].cr_sumz = c.ns[k].init_sumz
    c.ns[k].cr_w = c.ns[k].init_w
    c.ns[k].cr_n = c.ns[k].init_n
    c.ns[k].cm_sumz = 0.0f64
    c.ns[k].cm_w = 0.0f64
    c.ns[k].cm_n = 0usize
    c.ns[k].cur_imp = 0.0f64
    c.ns[k].last_x = 0.0f64 - 1.0f64 / 0.0f64
}

fn ns_incorporate(c: *Ctx, k: usize, x: f64, z: f64, w: f64, mono: f64) {
    if c.ns[k].split { ret }
    let wz = w * z
    if x != x {
        c.ns[k].cm_sumz += wz
        c.ns[k].cm_w += w
        c.ns[k].cm_n += 1usize
        c.ns[k].cr_sumz -= wz
        c.ns[k].cr_w -= w
        if c.ns[k].cr_n == 0usize {
        c.ns[k].cr_n = UMAX
    } else {
        c.ns[k].cr_n -= 1usize
    }
        ret
    }
    if c.ns[k].cur_classes > 0usize {
        let cat = usize(x)
        c.gsum[k * c.maxk + cat] += wz
        c.gw[k * c.maxk + cat] += w
        c.gn[k * c.maxk + cat] += 1usize
        ret
    }
    c.ns[k].cur_val = 0.5f64 * (c.ns[k].last_x + x)
    var ok_split = false
    if c.ns[k].last_x != x && c.ns[k].cl_n >= c.sp.minobs && c.ns[k].cr_n >= c.sp.minobs {
        if mono == 0.0f64 {
            ok_split = true
        } else if mono * (c.ns[k].cr_sumz * c.ns[k].cl_w - c.ns[k].cl_sumz * c.ns[k].cr_w) > 0.0f64 {
            ok_split = true
        }
    }
    if ok_split {
        c.ns[k].cur_imp = improvement(c.ns[k].cl_w, c.ns[k].cr_w, c.ns[k].cm_w, c.ns[k].cl_sumz, c.ns[k].cr_sumz, c.ns[k].cm_sumz)
        if c.ns[k].cur_imp > c.ns[k].best_imp {
            c.ns[k].best_var = c.ns[k].cur_var
            c.ns[k].best_val = c.ns[k].cur_val
            c.ns[k].best_classes = 0usize
            c.ns[k].bl_sumz = c.ns[k].cl_sumz
            c.ns[k].bl_w = c.ns[k].cl_w
            c.ns[k].bl_n = c.ns[k].cl_n
            c.ns[k].br_sumz = c.ns[k].cr_sumz
            c.ns[k].br_w = c.ns[k].cr_w
            c.ns[k].br_n = c.ns[k].cr_n
            c.ns[k].best_imp = c.ns[k].cur_imp
        }
    }
    c.ns[k].cl_sumz += wz
    c.ns[k].cl_w += w
    c.ns[k].cl_n += 1usize
    c.ns[k].cr_sumz -= wz
    c.ns[k].cr_w -= w
    if c.ns[k].cr_n == 0usize {
        c.ns[k].cr_n = UMAX
    } else {
        c.ns[k].cr_n -= 1usize
    }
    c.ns[k].last_x = x
}

fn ns_wrapup(c: *Ctx, k: usize) {
    if c.ns[k].cur_var == c.ns[k].best_var {
        if c.ns[k].cm_n > 0usize {
            c.ns[k].bm_sumz = c.ns[k].cm_sumz
            c.ns[k].bm_w = c.ns[k].cm_w
            c.ns[k].bm_n = c.ns[k].cm_n
        } else {
            c.ns[k].bm_sumz = c.ns[k].init_sumz
            c.ns[k].bm_w = c.ns[k].init_w
            c.ns[k].bm_n = 0usize
        }
    }
}

// R's rsort_with_index: Shell sort of x[0..m] ascending, the index carried along (not stable)
fn rsort_index(x: []f64, idx: []usize, m: usize) {
    var h = 1usize
    while h <= m / 9usize { h = 3usize * h + 1usize }
    while h > 0usize {
        var i = h
        while i < m {
            let v = x[i]
            let iv = idx[i]
            var j = i
            while j >= h && x[j - h] > v {
                x[j] = x[j - h]
                idx[j] = idx[j - h]
                j -= h
            }
            x[j] = v
            idx[j] = iv
            i += 1usize
        }
        h = h / 3usize
    }
}

fn wsub(a: usize, b: usize) -> usize {
    if a >= b { ret a - b }
    ret UMAX - (b - a) + 1usize
}

// node_search.cpp EvaluateCategoricalSplit: the categories ordered by their mean working response, every cut of that order tried
fn ns_eval_cat(c: *Ctx, k: usize) {
    if c.ns[k].split { ret }
    let cls = c.ns[k].cur_classes
    let b = k * c.maxk
    var fin = 0usize
    var i = 0usize
    while i < cls {
        c.curcat[b + i] = i
        if c.gw[b + i] != 0.0f64 {
            c.gmean[b + i] = c.gsum[b + i] / c.gw[b + i]
            fin += 1usize
        } else {
            c.gmean[b + i] = 1.0f64 / 0.0f64
        }
        i += 1usize
    }
    rsort_index(c.gmean[b..b + cls], c.curcat[b..b + cls], cls)
    i = 0usize
    while fin > 1usize && i < fin - 1usize {
        c.ns[k].cur_val = f64(i)
        let g = c.curcat[b + i]
        c.ns[k].cl_sumz += c.gsum[b + g]
        c.ns[k].cl_w += c.gw[b + g]
        c.ns[k].cl_n += c.gn[b + g]
        c.ns[k].cr_sumz -= c.gsum[b + g]
        c.ns[k].cr_w -= c.gw[b + g]
        c.ns[k].cr_n = wsub(c.ns[k].cr_n, c.gn[b + g])
        c.ns[k].cur_imp = improvement(c.ns[k].cl_w, c.ns[k].cr_w, c.ns[k].cm_w, c.ns[k].cl_sumz, c.ns[k].cr_sumz, c.ns[k].cm_sumz)
        if c.ns[k].cl_n >= c.sp.minobs && c.ns[k].cr_n >= c.sp.minobs && c.ns[k].cur_imp > c.ns[k].best_imp {
            c.ns[k].best_val = c.ns[k].cur_val
            if c.ns[k].best_var != c.ns[k].cur_var {
                c.ns[k].best_var = c.ns[k].cur_var
                c.ns[k].best_classes = cls
                var j = 0usize
                while j < cls {
                    c.bestcat[b + j] = c.curcat[b + j]
                    j += 1usize
                }
            }
            c.ns[k].bl_sumz = c.ns[k].cl_sumz
            c.ns[k].bl_w = c.ns[k].cl_w
            c.ns[k].bl_n = c.ns[k].cl_n
            c.ns[k].br_sumz = c.ns[k].cr_sumz
            c.ns[k].br_w = c.ns[k].cr_w
            c.ns[k].br_n = c.ns[k].cr_n
            c.ns[k].best_imp = c.ns[k].cur_imp
        }
        i += 1usize
    }
}

fn new_node(c: *Ctx, pred: f64, w: f64, nn: usize) -> usize {
    let k = c.nnode
    c.nnode += 1usize
    c.nd_isterm[k] = 1u8
    c.nd_pred[k] = pred
    c.nd_w[k] = w
    c.nd_n[k] = nn
    c.nd_var[k] = 0usize
    c.nd_split[k] = 0.0f64
    c.nd_imp[k] = 0.0f64
    c.nd_left[k] = UMAX
    c.nd_right[k] = UMAX
    c.nd_miss[k] = UMAX
    c.nd_ncat[k] = 0usize
    ret k
}

// tree.cpp GetBestSplit: every terminal node's best split over every variable, the bagged rows fed in order of each variable; the node with the largest improvement (first on ties) wins
fn get_best_split(c: *Ctx, zoff: usize) {
    let nt = c.sp.ntrain
    let n = c.sp.n
    var iv = 0usize
    while iv < c.sp.p {
        var k = 0usize
        while k < c.nterm {
            ns_reset(c, k, iv)
            k += 1usize
        }
        var q = 0usize
        while q < nt {
            let ob = c.order[iv * nt + q]
            if c.inbag[ob] != 0u8 {
                ns_incorporate(c, c.assign[ob], c.sp.x[iv * n + ob], c.z[zoff + ob], c.sp.w[zoff + ob], c.sp.mono[iv])
            }
            q += 1usize
        }
        k = 0usize
        while k < c.nterm {
            if c.sp.vclass.len > iv && c.sp.vclass[iv] > 0usize { ns_eval_cat(c, k) }
            ns_wrapup(c, k)
            k += 1usize
        }
        iv += 1usize
    }
    c.ibest = 0usize
    c.bestimp = 0.0f64
    var k2 = 0usize
    while k2 < c.nterm {
        c.ns[k2].split = true
        if c.ns[k2].best_imp > c.bestimp {
            c.ibest = k2
            c.bestimp = c.ns[k2].best_imp
        }
        k2 += 1usize
    }
}

// tree.cpp grow
fn grow(c: *Ctx, zoff: usize) {
    let nt = c.sp.ntrain
    let n = c.sp.n
    var sumz = 0.0f64
    var totw = 0.0f64
    var i = 0usize
    while i < nt {
        c.assign[i] = 0usize
        if c.inbag[i] != 0u8 {
            sumz += c.sp.w[zoff + i] * c.z[zoff + i]
            totw += c.sp.w[zoff + i]
        }
        i += 1usize
    }
    c.nnode = 0usize
    let root = new_node(c, sumz / totw, totw, c.totinbag)
    c.term[0usize] = root
    c.nterm = 1usize
    ns_set(c, 0usize, sumz, totw, c.totinbag, root)
    var d = 0usize
    while d < c.sp.depth {
        get_best_split(c, zoff)
        if c.bestimp == 0.0f64 { break }
        let ib = c.ibest
        let sn = c.ns[ib].node
        let lft = new_node(c, c.ns[ib].bl_sumz / c.ns[ib].bl_w, c.ns[ib].bl_w, c.ns[ib].bl_n)
        let rgt = new_node(c, c.ns[ib].br_sumz / c.ns[ib].br_w, c.ns[ib].br_w, c.ns[ib].br_n)
        let mis = new_node(c, c.ns[ib].bm_sumz / c.ns[ib].bm_w, c.ns[ib].bm_w, c.ns[ib].bm_n)
        c.nd_isterm[sn] = 0u8
        c.nd_var[sn] = c.ns[ib].best_var
        c.nd_split[sn] = c.ns[ib].best_val
        c.nd_imp[sn] = c.ns[ib].best_imp
        if c.ns[ib].best_classes > 0usize {
            c.nd_ncat[sn] = usize(c.ns[ib].best_val) + 1usize
            var ci = 0usize
            while ci < c.nd_ncat[sn] {
                c.nd_cats[sn * c.maxk + ci] = c.bestcat[ib * c.maxk + ci]
                ci += 1usize
            }
        }
        c.nd_left[sn] = lft
        c.nd_right[sn] = rgt
        c.nd_miss[sn] = mis
        c.nterm += 2usize
        c.term[ib] = lft
        c.term[c.nterm - 2usize] = rgt
        c.term[c.nterm - 1usize] = mis
        let sv = c.nd_var[sn]
        let sval = c.nd_split[sn]
        i = 0usize
        while i < nt {
            if c.assign[i] == ib {
                let xv = c.sp.x[sv * n + i]
                if xv != xv {
                    c.assign[i] = c.nterm - 1usize
                } else if c.nd_ncat[sn] > 0usize {
                    var inleft = false
                    var ci = 0usize
                    while ci < c.nd_ncat[sn] {
                        if c.nd_cats[sn * c.maxk + ci] == usize(xv) { inleft = true }
                        ci += 1usize
                    }
                    if !inleft { c.assign[i] = c.nterm - 2usize }
                } else if !(xv < sval) {
                    c.assign[i] = c.nterm - 2usize
                }
            }
            i += 1usize
        }
        let rs = c.ns[ib].br_sumz
        let rw = c.ns[ib].br_w
        let rn = c.ns[ib].br_n
        let ms = c.ns[ib].bm_sumz
        let mw = c.ns[ib].bm_w
        let mn2 = c.ns[ib].bm_n
        let ls = c.ns[ib].bl_sumz
        let lw = c.ns[ib].bl_w
        let ln = c.ns[ib].bl_n
        ns_set(c, c.nterm - 2usize, rs, rw, rn, rgt)
        ns_set(c, c.nterm - 1usize, ms, mw, mn2, mis)
        ns_set(c, ib, ls, lw, ln, lft)
        d += 1usize
    }
}

// the distributions ---------------------------------------------------------------------------------------------------------------------------------------

fn expf(x: f64) -> f64 { ret cr_exp(x) }
fn logf(x: f64) -> f64 { ret cr_log(x) }
fn absf(x: f64) -> f64 { ret math.abs[f64](x) }

// InitF: the constant the boosting starts from
fn dist_initf(c: *Ctx) -> f64 {
    let nt = c.sp.ntrain
    let d = c.sp.dist
    var i = 0usize
    var s = 0.0f64
    var t = 0.0f64
    if d == 0usize {
        while i < nt {
            s += c.sp.w[i] * (c.sp.y[i] - c.off[i])
            t += c.sp.w[i]
            i += 1usize
        }
        ret s / t
    }
    if d == 1usize {
        if c.hasoff {
            // Newton's method for the constant that balances the offset fit
            var f0 = 0.0f64
            var step = 1.0f64
            while absf(step) > 0.0001f64 {
                var num = 0.0f64
                var den = 0.0f64
                i = 0usize
                while i < nt {
                    let pr = 1.0f64 / (1.0f64 + expf(0.0f64 - (c.off[i] + f0)))
                    num += c.sp.w[i] * (c.sp.y[i] - pr)
                    den += c.sp.w[i] * pr * (1.0f64 - pr)
                    i += 1usize
                }
                step = num / den
                f0 += step
            }
            ret f0
        }
        while i < nt {
            s += c.sp.w[i] * c.sp.y[i]
            t += c.sp.w[i]
            i += 1usize
        }
        ret logf(s / (t - s))
    }
    if d == 2usize {
        while i < nt {
            s += c.sp.w[i] * c.sp.y[i]
            t += c.sp.w[i] * expf(c.off[i])
            i += 1usize
        }
        ret logf(s / t)
    }
    if d == 3usize || d == 6usize {
        while i < nt {
            if c.sp.y[i] == 1.0f64 {
                if d == 3usize {
                    s += c.sp.w[i] * expf(0.0f64 - c.off[i])
                } else {
                    s += c.sp.w[i]
                }
            } else {
                if d == 3usize {
                    t += c.sp.w[i] * expf(c.off[i])
                } else {
                    t += c.sp.w[i]
                }
            }
            i += 1usize
        }
        if d == 6usize { ret s / t }
        ret 0.5f64 * logf(s / t)
    }
    if d == 4usize || d == 5usize || d == 7usize {
        i = 0usize
        while i < nt {
            c.arr[i] = c.sp.y[i] - c.off[i]
            i += 1usize
        }
        if d == 4usize { ret lm_median(c, c.arr, c.sp.w, nt) }
        if d == 5usize { ret lm_quantile(c, c.arr, c.sp.w, nt, c.sp.alpha) }
        ret lm_location(c, c.arr, c.sp.w, nt, c.sp.nu)
    }
    ret 0.0f64
}

// ComputeWorkingResponse: the negative gradient at the current fit for rows off..off + ntrain
fn dist_response(c: *Ctx, off: usize) {
    let nt = c.sp.ntrain
    let d = c.sp.dist
    var i = 0usize
    if d >= 10usize {
        pw_response(c)
        ret
    }
    if d == 8usize {
        var risk = 0.0f64
        while i < nt {
            if c.inbag[i] != 0u8 {
                risk += c.sp.w[i] * expf(c.f[i] + c.off[i])
                c.scr[i] = risk
            }
            i += 1usize
        }
        var tot = 0.0f64
        i = nt
        while i > 0usize {
            i -= 1usize
            if c.inbag[i] != 0u8 {
                if c.sp.misc[i] == 1.0f64 { tot += c.sp.w[i] / c.scr[i] }
                c.z[i] = c.sp.misc[i] - expf(c.f[i] + c.off[i]) * tot
            }
        }
        ret
    }
    while i < nt {
        let j = off + i
        var y = c.sp.y[j]
        var f = c.f[j]
        if d == 0usize || d == 4usize || d == 7usize {
            y = y - c.off[j]
        } else {
            f = f + c.off[j]
        }
        if d == 0usize {
            c.z[j] = y - f
        } else if d == 1usize {
            let pr = 1.0f64 / (1.0f64 + expf(0.0f64 - f))
            c.z[j] = y - pr
        } else if d == 2usize {
            c.z[j] = y - expf(f)
        } else if d == 3usize {
            c.z[j] = (2.0f64 * y - 1.0f64) * expf(0.0f64 - (2.0f64 * y - 1.0f64) * f)
        } else if d == 4usize {
            if y - f > 0.0f64 {
                c.z[j] = 1.0f64
            } else {
                c.z[j] = 0.0f64 - 1.0f64
            }
        } else if d == 5usize {
            if y > f {
                c.z[j] = c.sp.alpha
            } else {
                c.z[j] = 0.0f64 - (1.0f64 - c.sp.alpha)
            }
        } else if d == 6usize {
            let yy = 2.0f64 * y - 1.0f64
            if yy * f < 0.0f64 - 1.0f64 {
                c.z[j] = (0.0f64 - 4.0f64) * yy
            } else if 1.0f64 - yy * f < 0.0f64 {
                c.z[j] = 0.0f64
            } else {
                c.z[j] = (0.0f64 - 2.0f64) * yy * (1.0f64 - yy * f)
            }
        } else if d == 7usize {
            let u = y - f
            c.z[j] = (2.0f64 * u) / (c.sp.nu + u * u)
        } else if d == 9usize {
            c.z[j] = y - c.prob[j]
        }
        i += 1usize
    }
}

// Deviance over len rows from index off
fn dist_dev(c: *Ctx, off: usize, len: usize) -> f64 {
    let d = c.sp.dist
    if d >= 10usize { ret pw_dev(c, off, len) }
    var dl = 0.0f64
    var dw = 0.0f64
    var i = off
    if d == 9usize {
        let mr = c.sp.n
        let nc = c.sp.nclass
        let rs = off % mr
        let icls = off / mr
        if icls != nc - 1usize { ret 0.0f64 }
        var ii = rs
        while ii < rs + len {
            var cs = 0.0f64
            var kk = 0usize
            while kk < nc {
                cs += expf(c.f[ii + kk * mr] + c.off[ii + kk * mr])
                kk += 1usize
            }
            if !(cs > 0.0f64) { cs = 1.0e-8f64 }
            kk = 0usize
            while kk < nc {
                let ix = ii + kk * mr
                if c.sp.y[ix] == 1.0f64 { dl += (0.0f64 - c.sp.w[ix]) * (c.f[ix] + c.off[ix] - logf(cs)) }
                kk += 1usize
            }
            dw += c.sp.w[ii]
            ii += 1usize
        }
        ret dl / dw
    }
    if d == 8usize {
        var tr = 0.0f64
        while i < off + len {
            let f = c.f[i] + c.off[i]
            tr += c.sp.w[i] * expf(f)
            if c.sp.misc[i] == 1.0f64 {
                dl += c.sp.w[i] * (f - logf(tr))
                dw += c.sp.w[i]
            }
            i += 1usize
        }
        ret (0.0f64 - 2.0f64) * dl / dw
    }
    while i < off + len {
        var y = c.sp.y[i]
        var f = c.f[i]
        if d == 0usize || d == 4usize || d == 7usize {
            y = y - c.off[i]
        } else {
            f = f + c.off[i]
        }
        let w = c.sp.w[i]
        if d == 0usize {
            dl += w * (y - f) * (y - f)
        } else if d == 1usize {
            dl += w * (y * f - logf(1.0f64 + expf(f)))
        } else if d == 2usize {
            dl += w * (y * f - expf(f))
        } else if d == 3usize {
            dl += w * expf(0.0f64 - (2.0f64 * y - 1.0f64) * f)
        } else if d == 4usize {
            dl += w * absf(y - f)
        } else if d == 5usize {
            if y > f {
                dl += w * c.sp.alpha * (y - f)
            } else {
                dl += w * (1.0f64 - c.sp.alpha) * (f - y)
            }
        } else if d == 6usize {
            let yy = 2.0f64 * y - 1.0f64
            if yy * f < 0.0f64 - 1.0f64 {
                dl += (0.0f64 - w) * 4.0f64 * yy * f
            } else if 1.0f64 - yy * f < 0.0f64 {
                dl += 0.0f64
            } else {
                dl += w * (1.0f64 - yy * f) * (1.0f64 - yy * f)
            }
        } else if d == 7usize {
            let u = y - f
            dl += w * logf(c.sp.nu + u * u)
        }
        dw += w
        i += 1usize
    }
    if d == 1usize || d == 2usize { ret (0.0f64 - 2.0f64) * dl / dw }
    ret dl / dw
}

// BagImprovement: the drop in loss over the rows left out of the bag when the tree is added with step dstep (fadj holds the unscaled leaf values)
fn dist_bagimp(c: *Ctx, dstep: f64) -> f64 {
    let d = c.sp.dist
    if d >= 10usize { ret pw_bagimp(c, dstep) }
    let nt = c.sp.ntrain
    var ret_v = 0.0f64
    var dw = 0.0f64
    var i = 0usize
    if d == 9usize {
        let mr = c.sp.n
        let nc = c.sp.nclass
        var ii = 0usize
        while ii < mr {
            var cs = 0.0f64
            var kk = 0usize
            while kk < nc {
                let ix = ii + kk * mr
                var df = c.f[ix] + c.off[ix]
                if kk == nc - 1usize { df += dstep * c.fadj[ix] }
                c.stepprob[ix] = c.sp.w[ix] * expf(df)
                cs += c.sp.w[ix] * expf(df)
                kk += 1usize
            }
            if !(cs > 0.0f64) { cs = 1.0e-8f64 }
            kk = 0usize
            while kk < nc {
                c.stepprob[ii + kk * mr] /= cs
                kk += 1usize
            }
            ii += 1usize
        }
        ii = 0usize
        while ii < nt {
            if c.inbag[ii] == 0u8 {
                var kk = 0usize
                while kk < nc {
                    let ix = ii + kk * mr
                    ret_v += c.sp.w[ix] * c.sp.y[ix] * (logf(c.stepprob[ix]) - logf(c.prob[ix]))
                    dw += c.sp.w[ix] * c.sp.y[ix]
                    kk += 1usize
                }
            }
            ii += 1usize
        }
        ret ret_v / dw
    }
    if d == 8usize {
        var dnum = 0.0f64
        var dden = 0.0f64
        while i < nt {
            if c.inbag[i] == 0u8 {
                let f = c.f[i] + c.off[i]
                dnum += c.sp.w[i] * expf(f + dstep * c.fadj[i])
                dden += c.sp.w[i] * expf(f)
                if c.sp.misc[i] == 1.0f64 {
                    ret_v += c.sp.w[i] * (dstep * c.fadj[i] - logf(dnum) + logf(dden))
                    dw += c.sp.w[i]
                }
            }
            i += 1usize
        }
        ret ret_v / dw
    }
    while i < nt {
        if c.inbag[i] == 0u8 {
            let y = c.sp.y[i]
            let f = c.f[i] + c.off[i]
            let w = c.sp.w[i]
            let fa = c.fadj[i]
            if d == 0usize {
                ret_v += w * dstep * fa * (2.0f64 * (y - f) - dstep * fa)
            } else if d == 1usize {
                if y == 1.0f64 { ret_v += w * dstep * fa }
                ret_v += w * (logf(1.0f64 + expf(f)) - logf(1.0f64 + expf(f + dstep * fa)))
            } else if d == 2usize {
                ret_v += w * (y * dstep * fa - expf(f + dstep * fa) + expf(f))
            } else if d == 3usize {
                ret_v += w * (expf(0.0f64 - (2.0f64 * y - 1.0f64) * f) - expf(0.0f64 - (2.0f64 * y - 1.0f64) * (f + dstep * fa)))
            } else if d == 4usize {
                ret_v += w * (absf(y - f) - absf(y - f - dstep * fa))
            } else if d == 5usize {
                if y > f {
                    ret_v += w * c.sp.alpha * (y - f)
                } else {
                    ret_v += w * (1.0f64 - c.sp.alpha) * (f - y)
                }
                if y > f + dstep * fa {
                    ret_v -= w * c.sp.alpha * (y - f - dstep * fa)
                } else {
                    ret_v -= w * (1.0f64 - c.sp.alpha) * (f + dstep * fa - y)
                }
            } else if d == 6usize {
                let yy = 2.0f64 * y - 1.0f64
                if yy * f < 0.0f64 - 1.0f64 {
                    ret_v += w * ((0.0f64 - 4.0f64) * yy * f - (0.0f64 - 4.0f64) * yy * (f + dstep * fa))
                } else if 1.0f64 - yy * f < 0.0f64 {
                    ret_v += 0.0f64
                } else {
                    ret_v += w * ((1.0f64 - yy * f) * (1.0f64 - yy * f) - (1.0f64 - yy * (f + dstep * fa)) * (1.0f64 - yy * (f + dstep * fa)))
                }
            } else if d == 7usize {
                let du = y - f
                let dv = y - f - dstep * fa
                ret_v += w * (logf(c.sp.nu + du * du) - logf(c.sp.nu + dv * dv))
            }
            dw += w
        }
        i += 1usize
    }
    ret ret_v / dw
}

fn cox_invert(h: []f64, m: usize) {
    if m == 0usize { ret }
    if m == 1usize {
        h[0usize] = 1.0f64 / h[0usize]
        ret
    }
    var i = 1usize
    while i < m {
        h[i] /= h[0usize]
        i += 1usize
    }
    i = 1usize
    while i < m {
        var j = i
        while j < m {
            var sum = 0.0f64
            var k = 0usize
            while k < i {
                sum += h[j * m + k] * h[k * m + i]
                k += 1usize
            }
            h[j * m + i] -= sum
            j += 1usize
        }
        if i == m - 1usize {
            i += 1usize
            continue
        }
        j = i + 1usize
        while j < m {
            var sum = 0.0f64
            var k = 0usize
            while k < i {
                sum += h[i * m + k] * h[k * m + j]
                k += 1usize
            }
            h[i * m + j] = (h[i * m + j] - sum) / h[i * m + i]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = i
        while j < m {
            var x = 1.0f64
            if i != j {
                x = 0.0f64
                var k = i
                while k < j {
                    x -= h[j * m + k] * h[k * m + i]
                    k += 1usize
                }
            }
            h[j * m + i] = x / h[j * m + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = i
        while j < m {
            if i != j {
                var sum = 0.0f64
                var k = i
                while k < j {
                    var f = 1.0f64
                    if i != k { f = h[i * m + k] }
                    sum += h[k * m + j] * f
                    k += 1usize
                }
                h[i * m + j] = 0.0f64 - sum
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var sum = 0.0f64
            var k = j
            if i > j { k = i }
            while k < m {
                var f = 1.0f64
                if j != k { f = h[j * m + k] }
                sum += f * h[k * m + i]
                k += 1usize
            }
            h[j * m + i] = sum
            j += 1usize
        }
        i += 1usize
    }
}

// FitBestConstant: each terminal node's prediction from the bagged rows that landed in it
fn dist_fitconst(c: *Ctx, zoff: usize) {
    let d = c.sp.dist
    let nt = c.sp.ntrain
    let nterm = c.nterm
    var i = 0usize
    var k = 0usize
    if d == 0usize { ret }
    if d >= 10usize {
        pw_fitconst(c)
        ret
    }
    if d == 4usize || d == 5usize || d == 7usize {
        k = 0usize
        while k < nterm {
            let nd = c.term[k]
            if c.nd_n[nd] >= c.sp.minobs {
                var m = 0usize
                i = 0usize
                while i < nt {
                    if c.inbag[i] != 0u8 && c.assign[i] == k {
                        c.arr[m] = c.sp.y[i] - c.off[i] - c.f[i]
                        c.w2[m] = c.sp.w[i]
                        m += 1usize
                    }
                    i += 1usize
                }
                if d == 4usize {
                    c.nd_pred[nd] = lm_median(c, c.arr, c.w2, m)
                } else if d == 5usize {
                    c.nd_pred[nd] = lm_quantile(c, c.arr, c.w2, m, c.sp.alpha)
                } else {
                    c.nd_pred[nd] = lm_location(c, c.arr, c.w2, m, c.sp.nu)
                }
            }
            k += 1usize
        }
        ret
    }
    if d == 9usize {
        k = 0usize
        while k < nterm {
            let nd = c.term[k]
            if c.nd_n[nd] >= c.sp.minobs {
                var dnum = 0.0f64
                var dden = 0.0f64
                i = 0usize
                while i < nt {
                    if c.inbag[i] != 0u8 && c.assign[i] == k {
                        let ix = i + zoff
                        dnum += c.sp.w[ix] * c.z[ix]
                        dden += c.sp.w[ix] * absf(c.z[ix]) * (1.0f64 - absf(c.z[ix]))
                    }
                    i += 1usize
                }
                if !(dden > 0.0f64) { dden = 1.0e-8f64 }
                c.nd_pred[nd] = dnum / dden
            }
            k += 1usize
        }
        ret
    }
    if d == 8usize {
        fitconst_cox(c)
        ret
    }
    k = 0usize
    while k < nterm {
        c.num[k] = 0.0f64
        c.den[k] = 0.0f64
        c.mx[k] = 0.0f64 - 1.0f64 / 0.0f64
        c.mn[k] = 1.0f64 / 0.0f64
        k += 1usize
    }
    i = 0usize
    while i < nt {
        let a = c.assign[i]
        let y = c.sp.y[i]
        let w = c.sp.w[i]
        let f = c.f[i] + c.off[i]
        if c.inbag[i] != 0u8 {
            if d == 1usize {
                c.num[a] += w * c.z[i]
                c.den[a] += w * (y - c.z[i]) * (1.0f64 - y + c.z[i])
            } else if d == 2usize {
                c.num[a] += w * y
                c.den[a] += w * expf(f)
            } else if d == 3usize {
                let yy = 2.0f64 * y - 1.0f64
                c.num[a] += w * yy * expf(0.0f64 - yy * f)
                c.den[a] += w * expf(0.0f64 - yy * f)
            } else if d == 6usize {
                let yy = 2.0f64 * y - 1.0f64
                if yy * f < 0.0f64 - 1.0f64 {
                    c.num[a] += w * 4.0f64 * yy
                    c.den[a] += (0.0f64 - w) * 4.0f64 * yy * f
                } else if 1.0f64 - yy * f < 0.0f64 {
                    c.num[a] += 0.0f64
                    c.den[a] += 0.0f64
                } else {
                    c.num[a] += w * 2.0f64 * yy * (1.0f64 - yy * f)
                    c.den[a] += w * (1.0f64 - yy * f) * (1.0f64 - yy * f)
                }
            }
        }
        if d == 2usize {
            if c.f[i] > c.mx[a] { c.mx[a] = c.f[i] }
            if c.f[i] < c.mn[a] { c.mn[a] = c.f[i] }
        }
        i += 1usize
    }
    k = 0usize
    while k < nterm {
        let nd = c.term[k]
        if d == 2usize {
            if c.num[k] == 0.0f64 {
                c.nd_pred[nd] = 0.0f64 - 1.0f64
            } else if c.den[k] == 0.0f64 {
                c.nd_pred[nd] = 0.0f64
            } else {
                c.nd_pred[nd] = logf(c.num[k] / c.den[k])
            }
            if 19.0f64 - c.mx[k] < c.nd_pred[nd] { c.nd_pred[nd] = 19.0f64 - c.mx[k] }
            if c.nd_pred[nd] < 0.0f64 - 19.0f64 - c.mn[k] { c.nd_pred[nd] = 0.0f64 - 19.0f64 - c.mn[k] }
        } else {
            if c.den[k] == 0.0f64 {
                c.nd_pred[nd] = 0.0f64
            } else {
                c.nd_pred[nd] = c.num[k] / c.den[k]
            }
        }
        k += 1usize
    }
}

// coxph.cpp FitBestConstant: one Newton step on the partial likelihood over the nodes that hold at least minobs rows, the last of them held at zero
fn fitconst_cox(c: *Ctx) {
    let nt = c.sp.ntrain
    let nterm = c.nterm
    var kk = 0usize
    var i = 0usize
    var k = 0usize
    while i < nterm {
        c.n2k[i] = 0usize
        if c.nd_n[c.term[i]] >= c.sp.minobs {
            c.k2n[kk] = i
            c.n2k[i] = kk
            kk += 1usize
        }
        i += 1usize
    }
    if kk == 0usize { ret }
    let m = kk - 1usize
    i = 0usize
    while i < kk {
        c.num[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m * m + 1usize {
        c.hm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m + 1usize {
        c.den[i] = 0.0f64
        i += 1usize
    }
    var risk = 0.0f64
    i = 0usize
    while i < nt {
        if c.inbag[i] != 0u8 && c.nd_n[c.term[c.assign[i]]] >= c.sp.minobs {
            let f = c.f[i] + c.off[i]
            c.num[c.n2k[c.assign[i]]] += c.sp.w[i] * expf(f)
            risk += c.sp.w[i] * expf(f)
            if c.sp.misc[i] == 1.0f64 {
                k = 0usize
                while k < m {
                    var eq = 0.0f64
                    if c.assign[i] == c.k2n[k] { eq = 1.0f64 }
                    c.den[k] += c.sp.w[i] * (eq - c.num[k] / risk)
                    c.hm[k * m + k] = c.hm[k * m + k] - c.sp.w[i] * c.num[k] / risk * (1.0f64 - c.num[k] / risk)
                    var q = 0usize
                    while q < k {
                        let t = c.hm[k * m + q] + c.sp.w[i] * c.num[k] / risk * c.num[q] / risk
                        c.hm[k * m + q] = t
                        c.hm[q * m + k] = t
                        q += 1usize
                    }
                    k += 1usize
                }
            }
        }
        i += 1usize
    }
    cox_invert(c.hm, m)
    k = 0usize
    while k < nterm {
        c.nd_pred[c.term[k]] = 0.0f64
        k += 1usize
    }
    var q = 0usize
    while q < m {
        k = 0usize
        while k < m {
            let t = c.hm[k * m + q]
            if !(t - t == 0.0f64) {
                c.nd_pred[c.term[c.k2n[k]]] = 0.0f64
                break
            } else {
                c.nd_pred[c.term[c.k2n[k]]] -= t * c.den[q]
            }
            k += 1usize
        }
        q += 1usize
    }
}

// multinomial UpdateParams: the class probabilities from the current fit
fn update_params(c: *Ctx) {
    let mr = c.sp.n
    let nc = c.sp.nclass
    var ii = 0usize
    while ii < mr {
        var cs = 0.0f64
        var kk = 0usize
        while kk < nc {
            let ix = ii + kk * mr
            c.prob[ix] = c.sp.w[ix] * expf(c.f[ix] + c.off[ix])
            cs += c.sp.w[ix] * expf(c.f[ix] + c.off[ix])
            kk += 1usize
        }
        if !(cs > 0.0f64) { cs = 1.0e-8f64 }
        kk = 0usize
        while kk < nc {
            c.prob[ii + kk * mr] /= cs
            kk += 1usize
        }
        ii += 1usize
    }
}

// tree.cpp Adjust and TransferTreeToRList: the unreached missing branches take the weighted mean of their siblings, then the tree is written out depth first (node, left, right, missing)
fn transfer(c: *Ctx, m: *Model, ti: usize, shrink: f64) {
    let base = ti * m.stride
    var j = c.nnode
    while j > 0usize {
        j -= 1usize
        if c.nd_isterm[j] == 0u8 {
            let l = c.nd_left[j]
            let r = c.nd_right[j]
            let ms = c.nd_miss[j]
            var pr = 0.0f64
            if c.nd_isterm[ms] == 1u8 && c.nd_n[ms] < c.sp.minobs {
                pr = (c.nd_w[l] * c.nd_pred[l] + c.nd_w[r] * c.nd_pred[r]) / (c.nd_w[l] + c.nd_w[r])
                c.nd_pred[ms] = pr
            } else {
                pr = (c.nd_w[l] * c.nd_pred[l] + c.nd_w[r] * c.nd_pred[r] + c.nd_w[ms] * c.nd_pred[ms]) / (c.nd_w[l] + c.nd_w[r] + c.nd_w[ms])
            }
            c.nd_pred[j] = pr
        }
    }
    var sp = 1usize
    c.stk[0usize] = 0usize
    c.stp[0usize] = UMAX
    c.sts[0usize] = 0usize
    var id = 0usize
    while sp > 0usize {
        sp -= 1usize
        let nd = c.stk[sp]
        let par = c.stp[sp]
        let slot = c.sts[sp]
        let at = base + id
        if par != UMAX {
            if slot == 1usize { m.tleft[base + par] = i64(id) }
            if slot == 2usize { m.tright[base + par] = i64(id) }
            if slot == 3usize { m.tmiss[base + par] = i64(id) }
        }
        if c.nd_isterm[nd] == 1u8 {
            m.tvar[at] = 0i64 - 1i64
            m.tcode[at] = shrink * c.nd_pred[nd]
            m.tleft[at] = 0i64 - 1i64
            m.tright[at] = 0i64 - 1i64
            m.tmiss[at] = 0i64 - 1i64
            m.terr[at] = 0.0f64
            m.twt[at] = c.nd_w[nd]
            m.tpred[at] = shrink * c.nd_pred[nd]
        } else {
            m.tvar[at] = i64(c.nd_var[nd])
            m.tcode[at] = c.nd_split[nd]
            if c.nd_ncat[nd] > 0usize {
                m.tcode[at] = f64(m.ncs + c.sp.catold)
                let lv = c.sp.vclass[c.nd_var[nd]]
                var li = 0usize
                while li < lv {
                    m.cs[m.ncs * m.maxk + li] = 1i64
                    li += 1usize
                }
                li = 0usize
                while li < c.nd_ncat[nd] {
                    m.cs[m.ncs * m.maxk + c.nd_cats[nd * c.maxk + li]] = 0i64 - 1i64
                    li += 1usize
                }
                m.ncs += 1usize
            }
            m.terr[at] = c.nd_imp[nd]
            m.twt[at] = c.nd_w[nd]
            m.tpred[at] = shrink * c.nd_pred[nd]
            c.stk[sp] = c.nd_miss[nd]
            c.stp[sp] = id
            c.sts[sp] = 3usize
            sp += 1usize
            c.stk[sp] = c.nd_right[nd]
            c.stp[sp] = id
            c.sts[sp] = 2usize
            sp += 1usize
            c.stk[sp] = c.nd_left[nd]
            c.stp[sp] = id
            c.sts[sp] = 1usize
            sp += 1usize
        }
        id += 1usize
    }
    m.nnodes[ti] = id
}

// the value the grown tree gives row i of x
fn tree_value(c: *Ctx, i: usize) -> f64 {
    var nd = 0usize
    while c.nd_isterm[nd] == 0u8 {
        let xv = c.sp.x[c.nd_var[nd] * c.sp.n + i]
        if xv != xv {
            nd = c.nd_miss[nd]
        } else if c.nd_ncat[nd] > 0usize {
            var inleft = false
            var ci = 0usize
            while ci < c.nd_ncat[nd] {
                if c.nd_cats[nd * c.maxk + ci] == usize(xv) { inleft = true }
                ci += 1usize
            }
            if inleft {
                nd = c.nd_left[nd]
            } else {
                nd = c.nd_right[nd]
            }
        } else if xv < c.nd_split[nd] {
            nd = c.nd_left[nd]
        } else {
            nd = c.nd_right[nd]
        }
    }
    ret c.nd_pred[nd]
}

// gbm_engine.cpp CGBM::iterate: one tree for class k; res receives the training deviance, the held-out deviance and the out-of-bag improvement
fn iterate(c: *Ctx, rg: *rng.Rng, m: *Model, ti: usize, shrink: f64, k: usize, res: []f64) {
    let nt = c.sp.ntrain
    let n = c.sp.n
    let off = k * n
    res[0usize] = 0.0f64
    res[1usize] = 0.0f64
    res[2usize] = 0.0f64
    if k == 0usize && c.sp.dist >= 10usize {
        pw_sample(c, rg)
    } else if k == 0usize {
        var bagged = 0usize
        var i = 0usize
        while i < nt {
            if rng.unif(rg) * f64(nt - i) < f64(c.totinbag - bagged) {
                c.inbag[i] = 1u8
                bagged += 1usize
            } else {
                c.inbag[i] = 0u8
            }
            i += 1usize
        }
    }
    dist_response(c, off)
    grow(c, off)
    dist_fitconst(c, off)
    transfer(c, m, ti, shrink)
    var i = 0usize
    while i < nt {
        c.fadj[off + i] = c.nd_pred[c.term[c.assign[i]]]
        i += 1usize
    }
    if k == c.sp.nclass - 1usize {
        res[2usize] = dist_bagimp(c, shrink)
    }
    i = 0usize
    while i < nt {
        c.f[off + i] += shrink * c.fadj[off + i]
        i += 1usize
    }
    res[0usize] = dist_dev(c, off, nt)
    i = nt
    while i < n {
        c.fadj[off + i] = tree_value(c, i) * shrink
        c.f[off + i] += c.fadj[off + i]
        i += 1usize
    }
    res[1usize] = dist_dev(c, off + nt, n - nt)
}

// gbm_fit: boosting for spec.ntrees trees; fold, when not empty, is the fit to continue from (gbm.more), otherwise the fit starts at the constant initf
fn fit(a: *mem.Arena, sp: *const Spec, rg: *rng.Rng, fold: []const f64) -> (Model, err) {
    let s = *sp
    let n = s.n
    let nt = s.ntrain
    let nc = s.nclass
    let dp = s.depth
    let stride = 3usize * dp + 1usize
    var maxk = 1usize
    var vq = 0usize
    while vq < s.vclass.len {
        if s.vclass[vq] > maxk { maxk = s.vclass[vq] }
        vq += 1usize
    }
    let nterm = 2usize * dp + 1usize
    var bad = 0usize
    var pwork = 1usize
    if s.dist == 9usize { pwork = n * nc }
    var nsv: []NS = zero
    let (nsx, nse) = mem.alloc[NS](a, nterm)
    if nse != ok { bad += 1usize } else { nsv = nsx }
    var c = Ctx{ sp: s, f: af(a, n * nc, &bad), z: af(a, n * nc, &bad), fadj: af(a, n * nc, &bad), inbag: ab(a, nt, &bad), assign: au(a, nt, &bad), order: au(a, nt * s.p, &bad),
        ns: nsv, term: au(a, nterm, &bad),
        nd_pred: af(a, stride, &bad), nd_w: af(a, stride, &bad), nd_n: au(a, stride, &bad), nd_isterm: ab(a, stride, &bad), nd_var: au(a, stride, &bad), nd_split: af(a, stride, &bad), nd_imp: af(a, stride, &bad), nd_left: au(a, stride, &bad), nd_right: au(a, stride, &bad), nd_miss: au(a, stride, &bad),
        nnode: 0usize, nterm: 0usize, totinbag: 0usize, ibest: 0usize, bestimp: 0.0f64,
        prob: af(a, pwork, &bad), stepprob: af(a, pwork, &bad), arr: af(a, n, &bad), w2: af(a, n, &bad), num: af(a, nterm + 1usize, &bad), den: af(a, nterm + 1usize, &bad), mx: af(a, nterm + 1usize, &bad), mn: af(a, nterm + 1usize, &bad),
        idx: au(a, n, &bad), tmp: au(a, n, &bad), stk: au(a, stride + 3usize, &bad), stp: au(a, stride + 3usize, &bad), sts: au(a, stride + 3usize, &bad), ids: au(a, nterm + 1usize, &bad), scr: af(a, n, &bad),
        hm: af(a, nterm * nterm + 1usize, &bad), k2n: au(a, nterm + 1usize, &bad), n2k: au(a, nterm + 1usize, &bad),
        maxk: maxk, gsum: af(a, nterm * maxk, &bad), gw: af(a, nterm * maxk, &bad), gmean: af(a, nterm * maxk, &bad), gn: au(a, nterm * maxk, &bad), curcat: au(a, nterm * maxk, &bad), bestcat: au(a, nterm * maxk, &bad), nd_ncat: au(a, stride, &bad), nd_cats: au(a, stride * maxk, &bad),
        off: af(a, n * nc, &bad), hasoff: false, rg: rg, hess: af(a, n, &bad), rscore: af(a, n, &bad), ritem: au(a, n, &bad), rrank: au(a, n, &bad), rkpos: au(a, n + 1usize, &bad), rankw: af(a, n + 2usize, &bad), cutoff: 0usize }
    let tot = s.ntrees * nc
    var m = Model{ nclass: nc, ntrees: s.ntrees, depth: dp, p: s.p, stride: stride, initf: 0.0f64, f: c.f, train_err: af(a, s.ntrees, &bad), valid_err: af(a, s.ntrees, &bad), oobag: af(a, s.ntrees, &bad),
        nnodes: au(a, tot, &bad), tvar: ai(a, tot * stride, &bad), tcode: af(a, tot * stride, &bad), tleft: ai(a, tot * stride, &bad), tright: ai(a, tot * stride, &bad), tmiss: ai(a, tot * stride, &bad), terr: af(a, tot * stride, &bad), twt: af(a, tot * stride, &bad), tpred: af(a, tot * stride, &bad),
        maxk: maxk, ncs: 0usize, cs: ai(a, (tot * dp + 1usize) * maxk, &bad), vclass: au(a, s.p, &bad) }
    var res = af(a, 3usize, &bad)
    var vi = 0usize
    while vi < s.vclass.len && vi < s.p {
        m.vclass[vi] = s.vclass[vi]
        vi += 1usize
    }
    if bad != 0usize || dp < 1usize { ret (m, NoMemory) }
    c.totinbag = usize(s.bag * f64(nt))
    if s.off.len == n * nc {
        var oi = 0usize
        while oi < n * nc {
            c.off[oi] = s.off[oi]
            if s.off[oi] != 0.0f64 { c.hasoff = true }
            oi += 1usize
        }
    }
    if s.dist >= 10usize {
        var maxitems = 0usize
        var start = 0usize
        while start < n {
            let e = pw_end(&c, start, n)
            if e - start > maxitems { maxitems = e - start }
            start = e
        }
        c.cutoff = maxitems
        if s.maxrank > 0usize { c.cutoff = s.maxrank }
        var top = maxitems
        if c.cutoff < top { top = c.cutoff }
        var r = 1usize
        while r <= top {
            c.rankw[r] = logf(2.0f64) / logf(f64(r + 1usize))
            r += 1usize
        }
        var ng = 0usize
        start = 0usize
        while start < nt {
            ng += 1usize
            start = pw_end(&c, start, nt)
        }
        c.sp.ngroups = ng
    }
    var j = 0usize
    while j < s.p {
        var q = 0usize
        while q < nt {
            c.idx[q] = q
            q += 1usize
        }
        msort(s.x[j * n..j * n + nt], c.idx, c.tmp, nt)
        q = 0usize
        while q < nt {
            c.order[j * nt + q] = c.idx[q]
            q += 1usize
        }
        j += 1usize
    }
    m.initf = dist_initf(&c)
    var i = 0usize
    while i < n * nc {
        if fold.len > 0usize {
            c.f[i] = fold[i]
        } else {
            c.f[i] = m.initf
        }
        i += 1usize
    }
    var t = 0usize
    while t < s.ntrees {
        if s.dist == 9usize { update_params(&c) }
        var kc = 0usize
        while kc < nc {
            iterate(&c, rg, &m, t * nc + kc, s.shrinkage, kc, res)
            m.train_err[t] += res[0usize]
            m.valid_err[t] += res[1usize]
            m.oobag[t] += res[2usize]
            kc += 1usize
        }
        t += 1usize
    }
    ret (m, ok)
}

// gbm_pred: the fit on the link scale at nn rows of xnew (nn by p, column-major) with the first use_trees trees; class k of row r lands at r + k nn
fn predict_link(m: *const Model, xnew: []const f64, nn: usize, use_trees: usize, out: []f64) {
    let nc = m.nclass
    var i = 0usize
    while i < nn * nc {
        out[i] = m.initf
        i += 1usize
    }
    var t = 0usize
    while t < use_trees {
        var k = 0usize
        while k < nc {
            let base = (t * nc + k) * m.stride
            var r = 0usize
            while r < nn {
                var nd = 0usize
                while m.tvar[base + nd] != 0i64 - 1i64 {
                    let xv = xnew[usize(m.tvar[base + nd]) * nn + r]
                    if xv != xv {
                        nd = usize(m.tmiss[base + nd])
                    } else if m.vclass[usize(m.tvar[base + nd])] > 0usize {
                        let ind = m.cs[usize(m.tcode[base + nd]) * m.maxk + usize(xv)]
                        if ind == 0i64 - 1i64 {
                            nd = usize(m.tleft[base + nd])
                        } else if ind == 1i64 {
                            nd = usize(m.tright[base + nd])
                        } else {
                            nd = usize(m.tmiss[base + nd])
                        }
                    } else if xv < m.tcode[base + nd] {
                        nd = usize(m.tleft[base + nd])
                    } else {
                        nd = usize(m.tright[base + nd])
                    }
                }
                out[k * nn + r] += m.tcode[base + nd]
                r += 1usize
            }
            k += 1usize
        }
        t += 1usize
    }
}

// relative.influence (unscaled): per variable the sum over the first use_trees trees of the per-tree sum of split improvements; scr holds stride + use_trees * nclass values
fn rel_inf(m: *const Model, use_trees: usize, out: []f64, scr: []f64) {
    let nc = m.nclass
    var v = 0usize
    while v < m.p {
        var nts = 0usize
        var t = 0usize
        while t < use_trees * nc {
            let base = t * m.stride
            var cnt = 0usize
            var q = 0usize
            while q < m.nnodes[t] {
                if m.tvar[base + q] == i64(v) {
                    scr[cnt] = m.terr[base + q]
                    cnt += 1usize
                }
                q += 1usize
            }
            if cnt > 0usize {
                scr[m.stride + nts] = rsum(scr[0usize..cnt], cnt)
                nts += 1usize
            }
            t += 1usize
        }
        out[v] = rsum(scr[m.stride..m.stride + nts], nts)
        v += 1usize
    }
}

// gbm_plot (the partial dependence behind plot.gbm): for each of the rows of x (rows by nv, column-major, the variables named by which) the fit with the other variables averaged out
// by the training weight of the branches at splits on them; class k of row r lands at k rows + r. scr holds 2 stride + 2 values.
fn plot_values(m: *const Model, nv: usize, which: []const usize, x: []const f64, rows: usize, use_trees: usize, out: []f64, scr: []f64) {
    let nc = m.nclass
    var i = 0usize
    while i < rows * nc {
        out[i] = m.initf
        i += 1usize
    }
    let wst = m.stride + 1usize
    var t = 0usize
    while t < use_trees {
        var k = 0usize
        while k < nc {
            let base = (t * nc + k) * m.stride
            var r = 0usize
            while r < rows {
                scr[0usize] = 0.0f64
                scr[wst] = 1.0f64
                var cnt = 1usize
                while cnt > 0usize {
                    cnt -= 1usize
                    let nd = usize(scr[cnt])
                    if m.tvar[base + nd] == 0i64 - 1i64 {
                        out[k * rows + r] += scr[wst + cnt] * m.tcode[base + nd]
                    } else {
                        var pv = nv
                        var q = 0usize
                        while pv == nv && q < nv {
                            if i64(which[q]) == m.tvar[base + nd] { pv = q }
                            q += 1usize
                        }
                        if pv != nv {
                            let xv = x[pv * rows + r]
                            if xv != xv {
                                scr[cnt] = f64(m.tmiss[base + nd])
                            } else if m.vclass[usize(m.tvar[base + nd])] > 0usize {
                                let ind = m.cs[usize(m.tcode[base + nd]) * m.maxk + usize(xv)]
                                if ind == 0i64 - 1i64 {
                                    scr[cnt] = f64(m.tleft[base + nd])
                                } else if ind == 1i64 {
                                    scr[cnt] = f64(m.tright[base + nd])
                                } else {
                                    scr[cnt] = f64(m.tmiss[base + nd])
                                }
                            } else if xv < m.tcode[base + nd] {
                                scr[cnt] = f64(m.tleft[base + nd])
                            } else {
                                scr[cnt] = f64(m.tright[base + nd])
                            }
                            cnt += 1usize
                        } else {
                            let lc = usize(m.tleft[base + nd])
                            let rc = usize(m.tright[base + nd])
                            scr[cnt] = f64(rc)
                            let cur = scr[wst + cnt]
                            scr[wst + cnt] = cur * m.twt[base + rc] / (m.twt[base + lc] + m.twt[base + rc])
                            cnt += 1usize
                            scr[cnt] = f64(lc)
                            scr[wst + cnt] = cur - scr[wst + cnt - 1usize]
                            cnt += 1usize
                        }
                    }
                }
                r += 1usize
            }
            k += 1usize
        }
        t += 1usize
    }
}

// pairwise (LambdaMART, pairwise.cpp) ----------------------------------------------------------------------------------------------------------------------
// dist 10 conc, 11 ndcg, 12 map, 13 mrr; the rows are grouped (spec.misc holds the group code, contiguous) with non-increasing labels inside a group

fn pw_end(c: *Ctx, start: usize, limit: usize) -> usize {
    var e = start + 1usize
    while e < limit && c.sp.misc[e] == c.sp.misc[start] { e += 1usize }
    ret e
}

// CRanker::SetGroupScores and Rank over the m scores f[at..at + m], a little noise breaking ties: rank of item i (1-based) lands in rrank[i], item of rank r in ritem[r - 1]
fn rk_setscores(c: *Ctx, at: usize, m: usize) {
    var i = 0usize
    while i < m {
        c.rscore[i] = c.f[at + i] + c.off[at + i] + 1.0e-10f64 * (rng.unif(c.rg) - 0.5f64)
        i += 1usize
    }
}

fn rk_rank(c: *Ctx, m: usize) {
    var i = 0usize
    while i < m {
        let key = i
        var j = i
        while j > 0usize && c.rscore[c.ritem[j - 1usize]] < c.rscore[key] {
            c.ritem[j] = c.ritem[j - 1usize]
            j -= 1usize
        }
        c.ritem[j] = key
        i += 1usize
    }
    i = 0usize
    while i < m {
        c.rrank[c.ritem[i]] = i + 1usize
        i += 1usize
    }
}

fn pw_anypairs(c: *Ctx, at: usize, m: usize) -> bool {
    ret m >= 2usize && c.sp.y[at] > 0.0f64 && c.sp.y[at + m - 1usize] != c.sp.y[at]
}

fn pw_paircount(c: *Ctx, at: usize, m: usize) -> f64 {
    if !pw_anypairs(c, at, m) { ret 0.0f64 }
    var cur = c.sp.y[at]
    var lend = 0usize
    var pairs = 0usize
    var j = 1usize
    while j < m {
        if c.sp.y[at + j] != cur {
            lend = j
            cur = c.sp.y[at + j]
        }
        pairs += lend
        j += 1usize
    }
    ret f64(pairs)
}

fn pw_maxmeasure(c: *Ctx, at: usize, m: usize) -> f64 {
    if c.sp.dist == 10usize { ret pw_paircount(c, at, m) }
    if c.sp.dist == 11usize {
        if !pw_anypairs(c, at, m) { ret 0.0f64 }
        var score = 0.0f64
        var i = 0usize
        while i < m && c.sp.y[at + i] > 0.0f64 {
            score += c.sp.y[at + i] * c.rankw[i + 1usize]
            i += 1usize
        }
        ret score
    }
    if pw_anypairs(c, at, m) { ret 1.0f64 }
    ret 0.0f64
}

fn pw_toprankpos(c: *Ctx, at: usize, m: usize, top: *usize, npos: *usize) {
    *top = m + 1usize
    var p = 0usize
    while p < m {
        if c.sp.y[at + p] <= 0.0f64 {
            *npos = p
            ret
        }
        if c.rrank[p] < *top { *top = c.rrank[p] }
        p += 1usize
    }
    *npos = p
}

// the ranks of the positive items, sorted ascending, in rkpos[0..npos]
fn pw_sortrankpos(c: *Ctx, at: usize, m: usize) -> usize {
    var p = 0usize
    while p < m {
        if c.sp.y[at + p] <= 0.0f64 { break }
        c.rkpos[p] = c.rrank[p]
        p += 1usize
    }
    var i = 1usize
    while i < p {
        let key = c.rkpos[i]
        var j = i
        while j > 0usize && c.rkpos[j - 1usize] > key {
            c.rkpos[j] = c.rkpos[j - 1usize]
            j -= 1usize
        }
        c.rkpos[j] = key
        i += 1usize
    }
    ret p
}

fn pw_measure(c: *Ctx, at: usize, m: usize) -> f64 {
    let d = c.sp.dist
    if d == 10usize {
        var cur = c.sp.y[at]
        var lend = 0usize
        var good = 0usize
        var j = 1usize
        while j < m {
            if c.sp.y[at + j] != cur {
                lend = j
                cur = c.sp.y[at + j]
            }
            var i = 0usize
            while i < lend {
                if c.rrank[i] < c.rrank[j] { good += 1usize }
                i += 1usize
            }
            j += 1usize
        }
        ret f64(good)
    }
    if d == 11usize {
        var score = 0.0f64
        var i = 0usize
        while i < m {
            score += c.sp.y[at + i] * c.rankw[c.rrank[i]]
            i += 1usize
        }
        ret score
    }
    if d == 13usize {
        var top = 0usize
        var npos = 0usize
        pw_toprankpos(c, at, m, &top, &npos)
        var nitems = m
        if c.cutoff < nitems { nitems = c.cutoff }
        if top >= nitems + 1usize { ret 0.0f64 }
        ret 1.0f64 / f64(top)
    }
    let npos = pw_sortrankpos(c, at, m)
    if npos == 0usize { ret 0.0f64 }
    var prec = 0.0f64
    var j = 0usize
    while j < npos {
        prec += f64(j + 1usize) / f64(c.rkpos[j])
        j += 1usize
    }
    ret prec / f64(npos)
}

// the first index of rkpos[0..npos] holding a value greater than v
fn pw_upper(c: *Ctx, npos: usize, v: usize) -> usize {
    var i = 0usize
    while i < npos && c.rkpos[i] <= v { i += 1usize }
    ret i
}

fn pw_swapcost(c: *Ctx, at: usize, m: usize, ib: usize, iw: usize) -> f64 {
    let d = c.sp.dist
    if d == 11usize {
        ret (c.rankw[c.rrank[ib]] - c.rankw[c.rrank[iw]]) * (c.sp.y[at + ib] - c.sp.y[at + iw])
    }
    if d == 10usize {
        let rb = c.rrank[ib]
        let rw = c.rrank[iw]
        var upper = 0usize
        var lower = 0usize
        var yu = 0.0f64
        var yl = 0.0f64
        var diff = 0i64
        if rb > rw {
            upper = rw
            lower = rb
            yu = c.sp.y[at + iw]
            yl = c.sp.y[at + ib]
            diff = 1i64
        } else {
            upper = rb
            lower = rw
            yu = c.sp.y[at + ib]
            yl = c.sp.y[at + iw]
            diff = 0i64 - 1i64
        }
        var r = upper + 1usize
        while r < lower {
            let yi = c.sp.y[at + c.ritem[r - 1usize]]
            var ds = yi - yl
            if ds != 0.0f64 {
                if ds < 0.0f64 {
                    diff += 1i64
                } else {
                    diff -= 1i64
                }
            }
            ds = yi - yu
            if ds != 0.0f64 {
                if ds < 0.0f64 {
                    diff -= 1i64
                } else {
                    diff += 1i64
                }
            }
            r += 1usize
        }
        ret f64(diff)
    }
    if d == 13usize {
        var top = 0usize
        var npos = 0usize
        pw_toprankpos(c, at, m, &top, &npos)
        if top >= m + 1usize || npos >= m { ret 0.0f64 }
        let rp = c.rrank[ib]
        let rn = c.rrank[iw]
        var cur = 0.0f64
        if !(top > c.cutoff) { cur = 1.0f64 / f64(top) }
        var mneg = 0.0f64
        if !(rn > c.cutoff) { mneg = 1.0f64 / f64(rn) }
        if rn < top || rp == top { ret mneg - cur }
        ret 0.0f64
    }
    let npos = pw_sortrankpos(c, at, m)
    if npos == 0usize { ret 0.0f64 }
    let irp = c.rrank[ib]
    let irn = c.rrank[iw]
    let nnb = pw_upper(c, npos, irp)
    let nan2 = pw_upper(c, npos, irn)
    var low = 0i64
    var high = 0i64
    let before = f64(nnb) / f64(irp)
    var sign = 0.0f64
    var after = 0.0f64
    if irn > irp {
        sign = 0.0f64 - 1.0f64
        low = i64(nnb)
        high = i64(nan2) - 1i64
        after = f64(nan2) / f64(irn)
    } else {
        sign = 1.0f64
        low = i64(nan2)
        high = i64(nnb) - 2i64
        after = f64(nan2 + 1usize) / f64(irn)
    }
    var dd = after - before
    var j = low
    while j <= high {
        dd += sign / f64(c.rkpos[usize(j)])
        j += 1i64
    }
    ret dd / f64(npos)
}

// ComputeLambdas for the group of m items at row index at
fn pw_lambdas(c: *Ctx, at: usize, m: usize) {
    if c.sp.w[at] <= 0.0f64 { ret }
    let dmax = pw_maxmeasure(c, at, m)
    if dmax <= 0.0f64 { ret }
    rk_setscores(c, at, m)
    rk_rank(c, m)
    var cur = c.sp.y[at]
    var lstart = 0usize
    var pairs = 0usize
    var j = 1usize
    while j < m {
        if c.sp.y[at + j] != cur {
            lstart = j
            cur = c.sp.y[at + j]
        }
        var i = 0usize
        while i < lstart {
            let sc = absf(pw_swapcost(c, at, m, i, j))
            if sc > 0.0f64 {
                pairs += 1usize
                let rho = 1.0f64 / (1.0f64 + expf((c.f[at + i] + c.off[at + i]) - (c.f[at + j] + c.off[at + j])))
                let lam = sc * rho
                c.z[at + i] += lam
                c.z[at + j] -= lam
                let der = lam * (1.0f64 - rho)
                c.hess[at + i] += der
                c.hess[at + j] += der
            }
            i += 1usize
        }
        j += 1usize
    }
    if pairs > 0usize {
        let qn = 1.0f64 / (dmax * f64(pairs))
        j = 0usize
        while j < m {
            c.z[at + j] *= qn
            c.hess[at + j] *= qn
            j += 1usize
        }
    }
}

fn pw_response(c: *Ctx) {
    let nt = c.sp.ntrain
    var start = 0usize
    while start < nt {
        let e = pw_end(c, start, nt)
        var i = start
        while i < e {
            c.z[i] = 0.0f64
            c.hess[i] = 0.0f64
            i += 1usize
        }
        if c.inbag[start] != 0u8 { pw_lambdas(c, start, e - start) }
        start = e
    }
}

fn pw_dev(c: *Ctx, off: usize, len: usize) -> f64 {
    if len == 0usize { ret 0.0f64 }
    var dl = 0.0f64
    var dw = 0.0f64
    var start = off
    let cend = off + len
    while start < cend {
        let e = pw_end(c, start, cend)
        let m = e - start
        let dmax = pw_maxmeasure(c, start, m)
        if dmax > 0.0f64 {
            rk_setscores(c, start, m)
            rk_rank(c, m)
            dl += c.sp.w[start] * pw_measure(c, start, m) / dmax
            dw += c.sp.w[start]
        }
        start = e
    }
    ret 1.0f64 - dl / dw
}

fn pw_bagimp(c: *Ctx, dstep: f64) -> f64 {
    let nt = c.sp.ntrain
    if nt == 0usize { ret 0.0f64 }
    var dl = 0.0f64
    var dw = 0.0f64
    var start = 0usize
    while start < nt {
        let e = pw_end(c, start, nt)
        let m = e - start
        if c.inbag[start] == 0u8 {
            let dmax = pw_maxmeasure(c, start, m)
            if dmax > 0.0f64 {
                rk_setscores(c, start, m)
                rk_rank(c, m)
                let old = pw_measure(c, start, m)
                var i = 0usize
                while i < m {
                    c.rscore[i] += c.fadj[start + i] * dstep
                    i += 1usize
                }
                let wi = c.sp.w[start]
                rk_rank(c, m)
                let nw = pw_measure(c, start, m)
                dl += wi * (nw - old) / dmax
                dw += wi
            }
        }
        start = e
    }
    ret dl / dw
}

fn pw_fitconst(c: *Ctx) {
    let nt = c.sp.ntrain
    var k = 0usize
    while k < c.nterm {
        c.num[k] = 0.0f64
        c.den[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < nt {
        if c.inbag[i] != 0u8 {
            c.num[c.assign[i]] += c.sp.w[i] * c.z[i]
            c.den[c.assign[i]] += c.sp.w[i] * c.hess[i]
        }
        i += 1usize
    }
    k = 0usize
    while k < c.nterm {
        if c.den[k] <= 0.0f64 {
            c.nd_pred[c.term[k]] = 0.0f64
        } else {
            c.nd_pred[c.term[k]] = c.num[k] / c.den[k]
        }
        k += 1usize
    }
}

// iterate's group sampling: whole groups drawn into the bag, a group at a time, until the bagged share of the groups is reached
fn pw_sample(c: *Ctx, rg: *rng.Rng) {
    let nt = c.sp.ntrain
    var last = 0.0f64 - 1.0f64
    var chosen = false
    var nbag = 0usize
    var nseen = 0usize
    var tot = usize(c.sp.bag * f64(c.sp.ngroups))
    if tot == 0usize { tot = 1usize }
    var i = 0usize
    while i < nt {
        let g = c.sp.misc[i]
        if g != last {
            if nbag >= tot { break }
            chosen = rng.unif(rg) * f64(c.sp.ngroups - nseen) < f64(tot - nbag)
            if chosen { nbag += 1usize }
            last = g
            nseen += 1usize
        }
        if chosen {
            c.inbag[i] = 1u8
        } else {
            c.inbag[i] = 0u8
        }
        i += 1usize
    }
    while i < nt {
        c.inbag[i] = 0u8
        i += 1usize
    }
}

// exp and log correctly rounded to the last bit (R's come from the C runtime, which is within a hair of that; Neper's own differ in the last bit for one argument in ten, enough to
// reorder exactly tied splits). Double-double arithmetic: the argument reduced by ln 2 in three pieces, the Taylor series summed to 106 bits, the result rounded once.

fn two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b
    let bb = s - a
    let e = (a - (s - bb)) + (b - bb)
    ret (s, e)
}

fn split_hi(a: f64) -> f64 {
    let t = 134217729.0f64 * a
    ret t - (t - a)
}

fn two_prod(a: f64, b: f64) -> (f64, f64) {
    let p = a * b
    let ah = split_hi(a)
    let al = a - ah
    let bh = split_hi(b)
    let bl = b - bh
    let e = ((ah * bh - p) + ah * bl + al * bh) + al * bl
    ret (p, e)
}

fn dd_mul(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let (p, e0) = two_prod(ah, bh)
    let e = e0 + (ah * bl + al * bh)
    let (s, t) = two_sum(p, e)
    ret (s, t)
}

fn dd_div_d(ah: f64, al: f64, d: f64) -> (f64, f64) {
    let q1 = ah / d
    let (p, pe) = two_prod(q1, d)
    let r = ((ah - p) - pe) + al
    let q2 = r / d
    let (s, t) = two_sum(q1, q2)
    ret (s, t)
}

// exp of x (|x| below 709) as a double-double times 2^k, written into hi, lo and k
fn exp_dd(x: f64, k: *i64, hi: *f64, lo: *f64) {
    let kf = math.floor[f64](x * 1.4426950408889634f64 + 0.5f64)
    let (r1a, r2a) = two_sum(x, 0.0f64 - kf * 0.6931471803691238f64)
    let (pp, pe) = two_prod(kf, 1.9082149292705877e-10f64)
    let (r1, e2) = two_sum(r1a, 0.0f64 - pp)
    let r2 = (r2a + e2) - pe - kf * 1.1612227229362532e-26f64
    let (rh, rl) = two_sum(r1, r2)
    var th = 1.0f64
    var tl = 0.0f64
    var n = 24i64
    while n >= 1i64 {
        let (mh, ml) = dd_mul(th, tl, rh, rl)
        let (dh, dl) = dd_div_d(mh, ml, f64(n))
        let (sh, sl) = two_sum(dh, 1.0f64)
        let (uh, ul) = two_sum(sh, dl + sl)
        th = uh
        tl = ul
        n -= 1i64
    }
    *k = i64(kf)
    *hi = th
    *lo = tl
}

fn cr_exp(x: f64) -> f64 {
    if x != x { ret x }
    if x > 709.0f64 || x < 0.0f64 - 708.0f64 { ret math.exp[f64](x) }
    var k = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    exp_dd(x, &k, &hi, &lo)
    ret (hi + lo) * math.power_of_two(k)
}

fn cr_log(x: f64) -> f64 {
    if !(x > 1.0e-290f64) || x > 1.0e290f64 { ret math.log[f64](x) }
    let y0 = math.log[f64](x)
    var k = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    exp_dd(y0, &k, &hi, &lo)
    let sc = math.power_of_two(k)
    let e0h = hi * sc
    let e0l = lo * sc
    let t = ((x - e0h) - e0l) / e0h
    ret y0 + t
}
