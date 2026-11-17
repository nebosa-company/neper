// R rpart's tree growth (rpart 4.1.27 src/partition.c, bsplit.c, anova.c, gini.c, nodesplit.c) on numeric predictors with unit case weights:
// method "anova" (y numeric) and method "class" (y the class codes 1 .. k, gini, prior = class frequencies, 0/1 loss), the complexity bookkeeping
// of `partition` (a split whose complexity falls to cp times the root risk is undone), and the routing of new rows to a leaf. Nothing is cross-validated
// or pruned afterwards; rpart's `xval` only consumes one `sample` draw, which the caller makes.
//
// Not here: surrogate splits, competing splits, categorical predictors (mice hands rpart a numeric design), case weights, user priors and losses.

use e.math
use e.mem

type Rpart = struct {
    x: []const f64,
    y: []const f64,
    n: usize,
    p: usize,
    cls: bool,
    k: usize,
    minsplit: usize,
    minbucket: usize,
    alpha: f64,
    maxnode: f64,
    aprior: []f64,
    prior: []f64,
    idx: []usize,
    ord: []usize,
    nn: usize,
    svar: []usize,
    spt: []f64,
    sdir: []f64,
    lc: []usize,
    rc: []usize,
    risk: []f64,
    cplx: []f64,
    nobs: []f64,
    val: []f64,
    cnt: []f64,
    left: []f64,
    right: []f64,
}

fn impurity(p: f64) -> f64 { ret p * (1.0f64 - p) }

// the node's value and risk from the observations idx[lo..hi]: the mean and sum of squares, or the predicted class (1-based, in val) with its counts (cnt[node k ..]) and misclassification risk
fn eval_node(t: *Rpart, node: usize, lo: usize, hi: usize) {
    if !t.cls {
        var tmp = 0.0f64
        var i = lo
        while i < hi {
            tmp += t.y[t.idx[i]]
            i += 1usize
        }
        let mean = tmp / f64(hi - lo)
        var ss = 0.0f64
        i = lo
        while i < hi {
            let d = t.y[t.idx[i]] - mean
            ss += d * d
            i += 1usize
        }
        t.val[node] = mean
        t.risk[node] = ss
        ret
    }
    let k = t.k
    var c = 0usize
    while c < k {
        t.cnt[node * k + c] = 0.0f64
        c += 1usize
    }
    var i = lo
    while i < hi {
        let j = usize(t.y[t.idx[i]]) - 1usize
        t.cnt[node * k + j] += 1.0f64
        i += 1usize
    }
    var dev = 0.0f64
    var best = 0usize
    c = 0usize
    while c < k {
        var tmp = 0.0f64
        var j = 0usize
        while j < k {
            var l = 1.0f64
            if c == j { l = 0.0f64 }
            tmp += t.cnt[node * k + j] * l * t.prior[j]
            j += 1usize
        }
        if c == 0usize || tmp < dev {
            best = c
            dev = tmp
        }
        c += 1usize
    }
    t.val[node] = f64(best + 1usize)
    t.risk[node] = dev
}

// the node's observations sorted by predictor j (ties keep their order) into t.ord[0..m]
fn sort_by(t: *Rpart, lo: usize, hi: usize, j: usize) {
    let m = hi - lo
    var i = 0usize
    while i < m {
        t.ord[i] = t.idx[lo + i]
        i += 1usize
    }
    i = 1usize
    while i < m {
        let v = t.ord[i]
        var q = i
        while q > 0usize && t.x[j * t.n + t.ord[q - 1usize]] > t.x[j * t.n + v] {
            t.ord[q] = t.ord[q - 1usize]
            q -= 1usize
        }
        t.ord[q] = v
        i += 1usize
    }
}

// the best split point of one predictor (rpart's anova or gini splitting function) on t.ord[0..m]: (improvement, split point, direction), improvement 0 when none
fn best_split(t: *Rpart, m: usize, j: usize, myrisk: f64) -> (f64, f64, f64) {
    let xo = t.x[j * t.n..j * t.n + t.n]
    let edge = t.minbucket
    var where = 0usize
    var direction = 0.0f64 - 1.0f64
    if !t.cls {
        var right_sum = 0.0f64
        var right_wt = 0.0f64
        var right_n = m
        var i = 0usize
        while i < m {
            right_sum += t.y[t.ord[i]]
            right_wt += 1.0f64
            i += 1usize
        }
        let grand = right_sum / right_wt
        var left_sum = 0.0f64
        var left_wt = 0.0f64
        var left_n = 0usize
        right_sum = 0.0f64
        var best = 0.0f64
        i = 0usize
        while right_n > edge {
            left_wt += 1.0f64
            right_wt -= 1.0f64
            left_n += 1usize
            right_n -= 1usize
            let tmp = t.y[t.ord[i]] - grand
            left_sum += tmp
            right_sum -= tmp
            if xo[t.ord[i + 1usize]] != xo[t.ord[i]] && left_n >= edge {
                let v = left_sum * left_sum / left_wt + right_sum * right_sum / right_wt
                if v > best {
                    best = v
                    where = i
                    if left_sum < right_sum { direction = 0.0f64 - 1.0f64 } else { direction = 1.0f64 }
                }
            }
            i += 1usize
        }
        var split = 0.0f64
        if best > 0.0f64 { split = (xo[t.ord[where]] + xo[t.ord[where + 1usize]]) / 2.0f64 }
        ret (best / myrisk, split, direction)
    }
    let k = t.k
    var lcount: [64]f64 = zero
    var rcount: [64]f64 = zero
    var lwt = 0.0f64
    var rwt = 0.0f64
    var rtot = 0usize
    var ltot = 0usize
    var i = 0usize
    while i < m {
        let j2 = usize(t.y[t.ord[i]]) - 1usize
        rwt += t.aprior[j2]
        rcount[j2] += 1.0f64
        rtot += 1usize
        i += 1usize
    }
    var total_ss = 0.0f64
    var c = 0usize
    while c < k {
        let tmp = t.aprior[c] * rcount[c] / rwt
        total_ss += rwt * impurity(tmp)
        c += 1usize
    }
    var best = total_ss
    i = 0usize
    while rtot > edge {
        let j2 = usize(t.y[t.ord[i]]) - 1usize
        rwt -= t.aprior[j2]
        lwt += t.aprior[j2]
        rtot -= 1usize
        ltot += 1usize
        rcount[j2] -= 1.0f64
        lcount[j2] += 1.0f64
        if ltot >= edge && xo[t.ord[i + 1usize]] != xo[t.ord[i]] {
            var tmp = 0.0f64
            var lmean = 0.0f64
            var rmean = 0.0f64
            var cc = 0usize
            while cc < k {
                var pp = t.aprior[cc] * lcount[cc] / lwt
                tmp += lwt * impurity(pp)
                lmean += pp * f64(cc)
                pp = t.aprior[cc] * rcount[cc] / rwt
                tmp += rwt * impurity(pp)
                rmean += pp * f64(cc)
                cc += 1usize
            }
            if tmp < best {
                best = tmp
                where = i
                if lmean < rmean { direction = 0.0f64 - 1.0f64 } else { direction = 1.0f64 }
            }
        }
        i += 1usize
    }
    var improve = total_ss - best
    var split = 0.0f64
    if improve > 0.0f64 { split = (xo[t.ord[where]] + xo[t.ord[where + 1usize]]) / 2.0f64 }
    ret (improve, split, direction)
}

// one node: returns the number of splits kept below it and its subtree risk
fn partition(t: *Rpart, node: usize, nodenum: f64, lo: usize, hi: usize, root_risk: f64) -> (usize, f64) {
    let n = hi - lo
    var tempcp = 0.0f64
    if nodenum > 1.0f64 {
        eval_node(t, node, lo, hi)
        t.nobs[node] = f64(n)
        tempcp = t.risk[node]
        if tempcp > t.cplx[node] { tempcp = t.cplx[node] }
    } else {
        tempcp = t.risk[node]
    }
    if n < t.minsplit || tempcp <= t.alpha || nodenum > t.maxnode {
        t.cplx[node] = t.alpha
        t.lc[node] = t.n + t.n + 5usize
        ret (0usize, t.risk[node])
    }
    // bsplit: the best predictor, the first among equals
    var bimp = 0.0f64
    var bsp = 0.0f64
    var bdir = 0.0f64
    var bvar = t.p
    var iscale = 0.0f64
    var j = 0usize
    while j < t.p {
        sort_by(t, lo, hi, j)
        let skip = t.x[j * t.n + t.ord[0usize]] == t.x[j * t.n + t.ord[n - 1usize]]
        if !skip {
            let (imp, sp, dr) = best_split(t, n, j, t.risk[node])
            if imp > iscale { iscale = imp }
            if imp > iscale * 1.0e-10f64 {
                if bvar == t.p || imp > bimp {
                    bimp = imp
                    bsp = sp
                    bdir = dr
                    bvar = j
                }
            }
        }
        j += 1usize
    }
    if bvar == t.p {
        t.cplx[node] = t.alpha
        t.lc[node] = t.n + t.n + 5usize
        ret (0usize, t.risk[node])
    }
    t.svar[node] = bvar
    t.spt[node] = bsp
    t.sdir[node] = bdir
    // nodesplit: the observations that go left come first
    var mid = lo
    var i = lo
    while i < hi {
        var goes_left = false
        if t.x[bvar * t.n + t.idx[i]] < bsp {
            goes_left = bdir < 0.0f64
        } else {
            goes_left = bdir > 0.0f64
        }
        if goes_left {
            let tmp = t.idx[mid]
            t.idx[mid] = t.idx[i]
            t.idx[i] = tmp
            mid += 1usize
        }
        i += 1usize
    }
    let ln = t.nn
    t.nn += 2usize
    let rn = ln + 1usize
    t.lc[node] = ln
    t.rc[node] = rn
    t.cplx[ln] = tempcp - t.alpha
    let (left_split0, left_risk0) = partition(t, ln, 2.0f64 * nodenum, lo, mid, root_risk)
    var left_split = left_split0
    var left_risk = left_risk0
    var t2 = (t.risk[node] - left_risk) / f64(left_split + 1usize)
    let t3 = t.risk[node] - t.risk[ln]
    if t2 < t3 { t2 = t3 }
    if t2 > t.cplx[node] { t2 = t.cplx[node] }
    t.cplx[rn] = t2 - t.alpha
    let (right_split0, right_risk0) = partition(t, rn, 1.0f64 + 2.0f64 * nodenum, mid, hi, root_risk)
    var right_split = right_split0
    var right_risk = right_risk0
    var cp = (t.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
    if t.cplx[rn] > t.cplx[ln] {
        if cp > t.cplx[ln] {
            left_risk = t.risk[ln]
            left_split = 0usize
            cp = (t.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
            if cp > t.cplx[rn] {
                right_risk = t.risk[rn]
                right_split = 0usize
            }
        }
    } else if cp > t.cplx[rn] {
        right_split = 0usize
        right_risk = t.risk[rn]
        cp = (t.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
        if cp > t.cplx[ln] {
            left_risk = t.risk[ln]
            left_split = 0usize
        }
    }
    t.cplx[node] = (t.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
    if t.cplx[node] <= t.alpha {
        t.lc[node] = t.n + t.n + 5usize
        ret (0usize, t.risk[node])
    }
    ret (left_split + right_split + 1usize, left_risk + right_risk)
}

// grows the tree on x (n by p, column-major) and y (the response, or class codes 1..k as doubles); cls selects gini classification
fn rpart_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, cls: bool, k: usize, minsplit: usize, minbucket: usize, cp: f64) -> (Rpart, err) {
    var t: Rpart = zero
    let cap = 2usize * n + 4usize
    let (idx, e1) = mem.alloc[usize](a, n)
    let (ord, e2) = mem.alloc[usize](a, n)
    let (svar, e3) = mem.alloc[usize](a, cap)
    let (spt, e4) = mem.alloc[f64](a, cap)
    let (sdir, e5) = mem.alloc[f64](a, cap)
    let (lc, e6) = mem.alloc[usize](a, cap)
    let (rc, e7) = mem.alloc[usize](a, cap)
    let (risk, e8) = mem.alloc[f64](a, cap)
    let (cplx, e9) = mem.alloc[f64](a, cap)
    let (nobs, e10) = mem.alloc[f64](a, cap)
    let (val, e11) = mem.alloc[f64](a, cap)
    let (cnt, e12) = mem.alloc[f64](a, cap * (k + 1usize))
    let (prior, e13) = mem.alloc[f64](a, k + 1usize)
    let (aprior, e14) = mem.alloc[f64](a, k + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (t, mem.Full) }
    if k > 60usize { ret (t, mem.Full) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 0usize
    while i < cap {
        lc[i] = n + n + 5usize
        rc[i] = n + n + 5usize
        i += 1usize
    }
    t.x = x
    t.y = y
    t.n = n
    t.p = p
    t.cls = cls
    t.k = k
    t.minsplit = minsplit
    t.minbucket = minbucket
    t.idx = idx
    t.ord = ord
    t.svar = svar
    t.spt = spt
    t.sdir = sdir
    t.lc = lc
    t.rc = rc
    t.risk = risk
    t.cplx = cplx
    t.nobs = nobs
    t.val = val
    t.cnt = cnt
    t.prior = prior
    t.aprior = aprior
    t.nn = 1usize
    t.maxnode = 1073741823.0f64
    if cls {
        // gini.c giniinit: prior = class frequency, altered prior pi_i / n_i from the 0/1 loss
        var freq: [64]f64 = zero
        var pri: [64]f64 = zero
        i = 0usize
        while i < n {
            freq[usize(y[i]) - 1usize] += 1.0f64
            i += 1usize
        }
        var tot = 0.0f64
        var c = 0usize
        while c < k {
            tot += freq[c]
            c += 1usize
        }
        c = 0usize
        while c < k {
            pri[c] = freq[c] / tot
            freq[c] = freq[c] / tot
            c += 1usize
        }
        var temp = 0.0f64
        c = 0usize
        while c < k {
            prior[c] = pri[c]
            aprior[c] = 0.0f64
            var j = 0usize
            while j < k {
                var l = 1.0f64
                if c == j { l = 0.0f64 }
                temp += l * prior[c]
                aprior[c] += l * prior[c]
                j += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < k {
            if freq[c] > 0.0f64 {
                prior[c] = prior[c] / freq[c]
                aprior[c] = aprior[c] / (temp * freq[c])
            }
            c += 1usize
        }
    }
    eval_node(&t, 0usize, 0usize, n)
    t.nobs[0usize] = f64(n)
    t.cplx[0usize] = t.risk[0usize]
    t.alpha = cp * t.risk[0usize]
    let (sp, rk) = partition(&t, 0usize, 1.0f64, 0usize, n, t.risk[0usize])
    let _ = sp
    let _ = rk
    ret (t, ok)
}

// the leaf (node index) that row i of the n2 by p matrix xm (column-major) reaches
fn rpart_leaf(t: *const Rpart, xm: []const f64, n2: usize, i: usize) -> usize {
    var node = 0usize
    while t.lc[node] < t.n + t.n + 5usize {
        let v = xm[t.svar[node] * n2 + i]
        var left = false
        if v < t.spt[node] { left = t.sdir[node] < 0.0f64 } else { left = t.sdir[node] > 0.0f64 }
        if left { node = t.lc[node] } else { node = t.rc[node] }
    }
    ret node
}

// the class probabilities of a leaf as rpart's predict gives them: counts times prior over the data count, normalised (out has k values)
fn rpart_leaf_probs(t: *const Rpart, node: usize, out: []f64) {
    let k = t.k
    var s = 0.0f64
    var c = 0usize
    while c < k {
        var tot = 0.0f64
        var i = 0usize
        while i < t.n {
            if usize(t.y[i]) - 1usize == c { tot += 1.0f64 }
            i += 1usize
        }
        if tot < 1.0f64 { tot = 1.0f64 }
        // prior (the class frequency) over its count; the stored altered prior is one when both agree
        out[c] = t.cnt[node * k + c] * (tot / f64(t.n) / tot)
        s += out[c]
        c += 1usize
    }
    c = 0usize
    while c < k {
        out[c] = out[c] / s
        c += 1usize
    }
}
