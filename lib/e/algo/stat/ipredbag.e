// R ipred 0.9-16: bagging and error estimation over the rpart port of e.algo.stat.rpartfull. bagging (ipredbagg for a factor and for a numeric
// response) with its bootstrap draws, majority, average and weighted aggregation, out-of-bag predictions and the out-of-bag error; errorest with the
// cv, boot, 632plus and 632plus_boot estimators for the models rpart, bagging and ipredknn; ipredknn. One generator stream is shared, so the draws
// (the bootstrap rows, the folds, rpart's xval groups, the tie breaks of uwhich.max and of knn) come in the order R makes them after set.seed.
//
// Observations are 0-based rows of a column-major matrix (NaN is NA); a factor predictor carries its level codes 1 .. ncat; a class response carries
// codes 1 .. k and k > 0 selects the classification trees, k = 0 the regression trees.
//
// Not here: combined models (comb), user models and predict functions, survival bagging, list.tindx, na.action other than rpart's, and the
// formula and data.frame front ends.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.classknn as knn
use e.algo.stat.ipredpkg as ip
use e.algo.stat.rpartfull as rf
use e.math
use e.mem

error BadArg

type Data = struct {
    n: usize,
    p: usize,
    k: usize,
    ncat: []const usize,
    x: []const f64,
    y: []const f64,
}

type Bag = struct {
    d: Data,
    nbagg: usize,
    ns: usize,
    trees: []rf.View,
    bindx: []usize,
    oob: f64,
}

// model kinds: 1 rpart, 2 bagging, 3 ipredknn
type Model = struct {
    kind: usize,
    nbagg: usize,
    ctl: rf.Control,
    knnk: usize,
}

type Est = struct {
    est: f64,
    sd: f64,
    err632: f64,
    nk: usize,
    npred: usize,
    pred: []f64,
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(v: f64) -> bool { ret v != v }

fn grab(a: *mem.Arena, n: usize) -> ([]f64, err) {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[f64](a, m)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < m {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn grab_u(a: *mem.Arena, n: usize) -> ([]usize, err) {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[usize](a, m)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < m {
        v[i] = 0usize
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

// the rows `rows` of d, in that order, repeats kept
fn subset(a: *mem.Arena, d: *const Data, rows: []const usize) -> (Data, err) {
    var o: Data = zero
    let m = rows.len
    let (x, e1) = grab(a, m * d.p)
    if e1 != ok { ret (o, e1) }
    let (y, e2) = grab(a, m)
    if e2 != ok { ret (o, e2) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < d.p {
            x[j * m + i] = d.x[j * d.n + rows[i]]
            j += 1usize
        }
        y[i] = d.y[rows[i]]
        i += 1usize
    }
    o.n = m
    o.p = d.p
    o.k = d.k
    o.ncat = d.ncat
    o.x = x
    o.y = y
    ret (o, ok)
}

// bagging(), ipredbagg's front end and errorest take the complete cases (model.frame's na.omit)
fn na_omit(a: *mem.Arena, d: *const Data) -> (Data, err) {
    let (keep, e) = grab_u(a, d.n)
    if e != ok { ret (*d, e) }
    var m = 0usize
    var i = 0usize
    while i < d.n {
        var good = d.y[i] == d.y[i]
        var j = 0usize
        while j < d.p {
            if d.x[j * d.n + i] != d.x[j * d.n + i] { good = false }
            j += 1usize
        }
        if good {
            keep[m] = i
            m += 1usize
        }
        i += 1usize
    }
    let (o, eo) = subset(a, d, keep[0usize..m])
    ret (o, eo)
}

// rpart on all of d under the control; xval groups come from the shared stream the way rpart's sample() takes them
fn fit_tree(a: *mem.Arena, g: *rng.Rng, d: *const Data, ctl: rf.Control) -> (rf.View, err) {
    var v: rf.View = zero
    let n = d.n
    let (wt, e1) = grab(a, n)
    if e1 != ok { ret (v, e1) }
    let (cost, e2) = grab(a, d.p)
    if e2 != ok { ret (v, e2) }
    let (nc, e3) = grab_u(a, d.p + 1usize)
    if e3 != ok { ret (v, e3) }
    var i = 0usize
    while i < n {
        wt[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < d.p {
        cost[i] = 1.0f64
        nc[i] = d.ncat[i]
        i += 1usize
    }
    var xg: []usize = zero
    let nx = usize(ctl.xval)
    if nx > 1usize {
        let (perm, ep) = rng.sample_int(a, g, i64(n), i64(n), false)
        if ep != ok { ret (v, ep) }
        let (gg, eg) = grab_u(a, n)
        if eg != ok { ret (v, eg) }
        i = 0usize
        while i < n {
            gg[i] = usize((perm[i] - 1i64) % i64(nx)) + 1usize
            i += 1usize
        }
        xg = gg
    }
    var method = 1usize
    if d.k > 0usize { method = 3usize }
    var parms: []const f64 = zero
    let (fit, ef) = rf.rp_fit(a, d.x, n, d.p, nc, d.y, 1usize, wt, cost, method, d.k, parms, ctl, xg)
    if ef != ok { ret (v, ef) }
    var ft = fit
    let (view, ev) = rf.rp_view(a, &ft)
    ret (view, ev)
}

// the frame row each of the nn rows of xn lands in
fn tree_where(a: *mem.Arena, v: *const rf.View, xn: []const f64, nn: usize) -> ([]usize, err) {
    let (w, e) = grab_u(a, nn)
    if e != ok { ret (w, e) }
    var i = 0usize
    while i < nn {
        w[i] = rf.rp_predict_row(v, xn, nn, i)
        i += 1usize
    }
    ret (w, ok)
}

// bagging / ipredbagg: nbagg trees on bootstrap samples of ns rows (without replacement when ns < n), then the out-of-bag error when coob
fn bag_fit(a: *mem.Arena, g: *rng.Rng, d: *const Data, nbagg: usize, ns: usize, ctl: rf.Control, coob: bool) -> (Bag, err) {
    var b: Bag = zero
    if nbagg < 1usize { ret (b, BadArg) }
    if nbagg == 1usize && coob { ret (b, BadArg) }
    var replace = true
    if nbagg == 1usize || ns < d.n { replace = false }
    var nsz = ns
    if nbagg == 1usize { nsz = d.n }
    let (trees, e1) = mem.alloc[rf.View](a, nbagg)
    if e1 != ok { ret (b, e1) }
    let (bx, e2) = grab_u(a, nbagg * nsz)
    if e2 != ok { ret (b, e2) }
    var t = 0usize
    while t < nbagg {
        let (rows, er) = grab_u(a, nsz)
        if er != ok { ret (b, er) }
        if nbagg > 1usize {
            let (s, es) = rng.sample_int(a, g, i64(d.n), i64(nsz), replace)
            if es != ok { ret (b, es) }
            var i = 0usize
            while i < nsz {
                rows[i] = usize(s[i] - 1i64)
                i += 1usize
            }
        } else {
            var i = 0usize
            while i < nsz {
                rows[i] = i
                i += 1usize
            }
        }
        var i = 0usize
        while i < nsz {
            bx[t * nsz + i] = rows[i]
            i += 1usize
        }
        let (sub, esub) = subset(a, d, rows)
        if esub != ok { ret (b, esub) }
        let (v, ev) = fit_tree(a, g, &sub, ctl)
        if ev != ok { ret (b, ev) }
        trees[t] = v
        t += 1usize
    }
    b.d = *d
    b.nbagg = nbagg
    b.ns = nsz
    b.trees = trees
    b.bindx = bx
    b.oob = nan()
    if coob {
        let (pr, ep) = bag_predict(a, g, &b, d.x, d.n, true, 0usize, false)
        if ep != ok { ret (b, ep) }
        var s = 0.0f64
        var c = 0.0f64
        var i = 0usize
        while i < d.n {
            if d.k > 0usize {
                if pr[i] == pr[i] {
                    c += 1.0f64
                    if pr[i] != d.y[i] { s += 1.0f64 }
                }
            } else if pr[i] == pr[i] {
                c += 1.0f64
                s += (pr[i] - d.y[i]) * (pr[i] - d.y[i])
            }
            i += 1usize
        }
        if d.k > 0usize { b.oob = s / c } else { b.oob = math.sqrt[f64](s / c) }
    }
    ret (b, ok)
}

// uwhich.max: the position of the maximum, a tie broken by sample(length(ties), 1)
fn which_max(a: *mem.Arena, g: *rng.Rng, row: []const f64) -> (usize, err) {
    var mx = row[0usize]
    var i = 1usize
    while i < row.len {
        if row[i] > mx { mx = row[i] }
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < row.len {
        if row[i] == mx { cnt += 1usize }
        i += 1usize
    }
    var pick = 0usize
    if cnt > 1usize {
        let (s, e) = rng.sample_int(a, g, i64(cnt), 1i64, false)
        if e != ok { ret (0usize, e) }
        pick = usize(s[0usize] - 1i64)
    }
    var seen = 0usize
    i = 0usize
    while i < row.len {
        if row[i] == mx {
            if seen == pick { ret (i, ok) }
            seen += 1usize
        }
        i += 1usize
    }
    ret (0usize, ok)
}

// predict.classbagg and predict.regbagg. oob: the out-of-bag predictions of the training rows (xn is then the training matrix). agg 0 is the default
// (majority for a class response, average for a regression), 1 average of the class probabilities, 2 weighted. prob answers the nn x k matrix
// (row-major) instead of the class; a class is answered as its code.
fn bag_predict(a: *mem.Arena, g: *rng.Rng, b: *const Bag, xn: []const f64, nn: usize, oob: bool, agg: usize, prob: bool) -> ([]f64, err) {
    let k = b.d.k
    var w = 1usize
    if k > 0usize && prob { w = k }
    let (out, eo) = grab(a, nn * w)
    if eo != ok { ret (out, eo) }
    if oob && b.nbagg < 10usize { ret (out, BadArg) }
    var kk = k
    if kk == 0usize { kk = 1usize }
    let (acc, ea) = grab(a, nn * kk)
    if ea != ok { ret (out, ea) }
    let (cnt, ec) = grab(a, nn)
    if ec != ok { ret (out, ec) }
    let (inb, ei) = grab_u(a, nn)
    if ei != ok { ret (out, ei) }
    var t = 0usize
    while t < b.nbagg {
        let start = mem.mark(a)
        let v = &b.trees[t]
        let (wh, ew) = tree_where(a, v, xn, nn)
        if ew != ok { ret (out, ew) }
        var j = 0usize
        while j < nn {
            inb[j] = 0usize
            j += 1usize
        }
        if oob {
            var q = 0usize
            while q < b.ns {
                inb[b.bindx[t * b.ns + q]] = 1usize
                q += 1usize
            }
        }
        j = 0usize
        while j < nn {
            if inb[j] == 0usize {
                let row = wh[j]
                if k > 0usize && agg == 0usize {
                    acc[j * k + usize(v.fyval[row]) - 1usize] += 1.0f64
                } else if k > 0usize && agg == 1usize {
                    var c = 0usize
                    while c < k {
                        acc[j * k + c] += v.y2[row * v.y2w + 1usize + k + c]
                        c += 1usize
                    }
                    cnt[j] += 1.0f64
                } else if k == 0usize && agg != 2usize {
                    acc[j] += v.fyval[row]
                    cnt[j] += 1.0f64
                } else {
                    // weighted: the training rows of this tree's sample that share the leaf
                    var q = 0usize
                    while q < b.ns {
                        if v.wh[q] - 1usize == row {
                            let yi = b.d.y[b.bindx[t * b.ns + q]]
                            if k > 0usize { acc[j * k + usize(yi) - 1usize] += 1.0f64 } else { acc[j] += yi }
                            cnt[j] += 1.0f64
                        }
                        q += 1usize
                    }
                }
            }
            j += 1usize
        }
        mem.reset(a, start)
        t += 1usize
    }
    var j = 0usize
    while j < nn {
        if k == 0usize {
            if cnt[j] < 1.0f64 { out[j] = nan() } else { out[j] = acc[j] / cnt[j] }
        } else {
            var s = 0.0f64
            var c = 0usize
            while c < k {
                s += acc[j * k + c]
                c += 1usize
            }
            if prob {
                var den = s
                if agg == 1usize {
                    den = cnt[j]
                    if den < 1.0f64 { den = nan() }
                    if !oob { den = f64(b.nbagg) }
                }
                c = 0usize
                while c < k {
                    out[j * k + c] = acc[j * k + c] / den
                    c += 1usize
                }
            } else {
                let (wm, ew) = which_max(a, g, acc[j * k..j * k + k])
                if ew != ok { ret (out, ew) }
                out[j] = f64(wm + 1usize)
            }
        }
        j += 1usize
    }
    ret (out, ok)
}

// design matrix of ipredknn (model.matrix without the intercept, treatment contrasts), row-major, and its width
fn knn_width(d: *const Data) -> usize {
    var w = 0usize
    var j = 0usize
    while j < d.p {
        if d.ncat[j] == 0usize { w += 1usize } else { w += d.ncat[j] - 1usize }
        j += 1usize
    }
    ret w
}

fn knn_design(a: *mem.Arena, d: *const Data, xn: []const f64, nn: usize) -> ([]f64, err) {
    let w = knn_width(d)
    let (o, e) = grab(a, nn * w)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < nn {
        var at = 0usize
        var j = 0usize
        while j < d.p {
            let v = xn[j * nn + i]
            if d.ncat[j] == 0usize {
                o[i * w + at] = v
                at += 1usize
            } else {
                var l = 2usize
                while l <= d.ncat[j] {
                    if v == f64(l) { o[i * w + at] = 1.0f64 }
                    at += 1usize
                    l += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (o, ok)
}

// predict.ipredknn on a model fit to train: the class (or, with prob, the winning proportion) of each of the nn rows
fn knn_predict(a: *mem.Arena, g: *rng.Rng, train: *const Data, kn: usize, xn: []const f64, nn: usize, prob: bool) -> ([]f64, err) {
    let (tr, e1) = knn_design(a, train, train.x, train.n)
    if e1 != ok { ret (tr, e1) }
    let (te, e2) = knn_design(a, train, xn, nn)
    if e2 != ok { ret (te, e2) }
    let (cl, e3) = mem.alloc[i64](a, train.n)
    if e3 != ok { ret (tr, e3) }
    var i = 0usize
    while i < train.n {
        cl[i] = i64(train.y[i])
        i += 1usize
    }
    let (cls, pr, e4) = knn.knn(a, g, tr, cl, te, knn_width(train), train.k, kn, 0i64, false, true)
    if e4 != ok { ret (tr, e4) }
    let (out, e5) = grab(a, nn)
    if e5 != ok { ret (out, e5) }
    i = 0usize
    while i < nn {
        if prob { out[i] = pr[i] } else { out[i] = f64(cls[i]) }
        i += 1usize
    }
    ret (out, ok)
}

// fit the model to train and predict the response (class code or value) of the nn rows of xn
fn model_predict(a: *mem.Arena, g: *rng.Rng, m: *const Model, train: *const Data, xn: []const f64, nn: usize) -> ([]f64, err) {
    if m.kind == 3usize {
        let (kp, ke) = knn_predict(a, g, train, m.knnk, xn, nn, false)
        ret (kp, ke)
    }
    if m.kind == 2usize {
        let (b, e) = bag_fit(a, g, train, m.nbagg, train.n, m.ctl, false)
        if e != ok {
            var none: []f64 = zero
            ret (none, e)
        }
        let (bp, be) = bag_predict(a, g, &b, xn, nn, false, 0usize, false)
        ret (bp, be)
    }
    let (v, e) = fit_tree(a, g, train, m.ctl)
    let (out, eo) = grab(a, nn)
    if e != ok { ret (out, e) }
    if eo != ok { ret (out, eo) }
    var i = 0usize
    while i < nn {
        let row = rf.rp_predict_row(&v, xn, nn, i)
        out[i] = v.fyval[row]
        i += 1usize
    }
    ret (out, ok)
}

// R's a:b, which runs down when b < a
fn colon(from: i64, to: i64, out: []usize, ln: usize) -> usize {
    var n = 0usize
    var i = from
    var step = 1i64
    if to < from { step = 0i64 - 1i64 }
    while true {
        if i >= 1i64 && usize(i) <= ln {
            out[n] = usize(i - 1i64)
            n += 1usize
        }
        if i == to { break }
        i += step
    }
    ret n
}

// the folds of ssubset (positions into y, 0-based): consecutive blocks, or per class blocks when strat. start[i] .. start[i + 1] bound fold i in idx
fn ssubset(a: *mem.Arena, y: []const f64, kc: usize, k: usize, strat: bool, idx: []usize, start: []usize) -> err {
    let n = y.len
    var at = 0usize
    var fold = 0usize
    if !strat {
        if k > n { ret BadArg }
        let (sz, e) = grab_u(a, k)
        if e != ok { ret e }
        ip.kfoldcv(k, n, sz)
        var s = 0usize
        while fold < k {
            start[fold] = at
            var q = 0usize
            while q < sz[fold] {
                idx[at] = s + q
                at += 1usize
                q += 1usize
            }
            s += sz[fold]
            fold += 1usize
        }
        start[k] = at
        ret ok
    }
    // per class: the rows of class c in order, and the class's fold sizes
    let (nlev, e1) = grab_u(a, kc)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        nlev[usize(y[i]) - 1usize] += 1usize
        i += 1usize
    }
    let (kmat, e2) = grab_u(a, kc * k)
    if e2 != ok { ret e2 }
    var c = 0usize
    while c < kc {
        let (row, er) = grab_u(a, k)
        if er != ok { ret er }
        ip.kfoldcv(k, nlev[c], row)
        var q = 0usize
        while q < k {
            kmat[c * k + q] = row[q]
            q += 1usize
        }
        c += 1usize
    }
    let (members, e3) = grab_u(a, n + kc)
    if e3 != ok { ret e3 }
    let (mstart, e4) = grab_u(a, kc + 1usize)
    if e4 != ok { ret e4 }
    var mat = 0usize
    c = 0usize
    while c < kc {
        mstart[c] = mat
        i = 0usize
        while i < n {
            if usize(y[i]) - 1usize == c {
                members[mat] = i
                mat += 1usize
            }
            i += 1usize
        }
        c += 1usize
    }
    mstart[kc] = mat
    let (tmp, e5) = grab_u(a, 2usize + n)
    if e5 != ok { ret e5 }
    while fold < k {
        start[fold] = at
        c = 0usize
        while c < kc {
            var before = 0usize
            var q = 0usize
            while q < fold {
                before += kmat[c * k + q]
                q += 1usize
            }
            let ln = mstart[c + 1usize] - mstart[c]
            let lo = i64(before) + 1i64
            let hi = i64(before + kmat[c * k + fold])
            let cnt = colon(lo, hi, tmp, ln)
            q = 0usize
            while q < cnt {
                idx[at] = members[mstart[c] + tmp[q]]
                at += 1usize
                q += 1usize
            }
            c += 1usize
        }
        fold += 1usize
    }
    start[k] = at
    ret ok
}

fn mean_err(pred: []const f64, y: []const f64, cls: bool) -> f64 {
    var s = 0.0f64
    var c = 0.0f64
    var i = 0usize
    while i < y.len {
        if pred[i] == pred[i] {
            c += 1.0f64
            if cls {
                if pred[i] != y[i] { s += 1.0f64 }
            } else {
                s += (pred[i] - y[i]) * (pred[i] - y[i])
            }
        }
        i += 1usize
    }
    if cls { ret s / c }
    ret math.sqrt[f64](s / c)
}

// errorest(estimator = "cv"): kfold folds, random permutation first when random, stratified class folds when strat
fn est_cv(a: *mem.Arena, g: *rng.Rng, d: *const Data, m: *const Model, k: usize, strat: bool, random: bool) -> (Est, err) {
    var r: Est = zero
    let n = d.n
    let cls = d.k > 0usize
    r.nk = k
    let (my, e1) = grab_u(a, n)
    if e1 != ok { ret (r, e1) }
    var i = 0usize
    if random {
        let (s, es) = rng.sample_int(a, g, i64(n), i64(n), false)
        if es != ok { ret (r, es) }
        while i < n {
            my[i] = usize(s[i] - 1i64)
            i += 1usize
        }
    } else {
        while i < n {
            my[i] = i
            i += 1usize
        }
    }
    let (allp, e2) = grab(a, n)
    if e2 != ok { ret (r, e2) }
    let (ins, e3) = grab_u(a, n)
    if e3 != ok { ret (r, e3) }
    if cls {
        // the data is permuted; every fold predicts all n rows (and so draws for all)
        let (dp, ed) = subset(a, d, my)
        if ed != ok { ret (r, ed) }
        let (idx, e4) = grab_u(a, k * (n + 2usize * d.k + 2usize))
        if e4 != ok { ret (r, e4) }
        let (st, e5) = grab_u(a, k + 1usize)
        if e5 != ok { ret (r, e5) }
        let es2 = ssubset(a, dp.y, d.k, k, strat, idx, st)
        if es2 != ok { ret (r, es2) }
        i = 0usize
        while i < n {
            allp[i] = nan()
            i += 1usize
        }
        var f = 0usize
        while f < k {
            var q = 0usize
            while q < n {
                ins[q] = 0usize
                q += 1usize
            }
            q = st[f]
            while q < st[f + 1usize] {
                ins[idx[q]] = 1usize
                q += 1usize
            }
            var nt = 0usize
            q = 0usize
            while q < n {
                if ins[q] == 0usize { nt += 1usize }
                q += 1usize
            }
            let (rows, er) = grab_u(a, nt)
            if er != ok { ret (r, er) }
            nt = 0usize
            q = 0usize
            while q < n {
                if ins[q] == 0usize {
                    rows[nt] = q
                    nt += 1usize
                }
                q += 1usize
            }
            let (fd, ef) = subset(a, &dp, rows)
            if ef != ok { ret (r, ef) }
            let (pr, ep) = model_predict(a, g, m, &fd, dp.x, n)
            if ep != ok { ret (r, ep) }
            q = st[f]
            // R assigns allpred[tindx] in order, so a repeated index keeps its last value
            while q < st[f + 1usize] {
                allp[idx[q]] = pr[idx[q]]
                q += 1usize
            }
            f += 1usize
        }
        let (back, eb) = grab(a, n)
        if eb != ok { ret (r, eb) }
        i = 0usize
        while i < n {
            back[my[i]] = allp[i]
            i += 1usize
        }
        r.pred = back
        r.npred = n
        r.est = mean_err(back, d.y, true)
        ret (r, ok)
    }
    // regression: the data keeps its order; a fold predicts its own rows
    let (sz, e6) = grab_u(a, k)
    if e6 != ok { ret (r, e6) }
    if k > n { ret (r, BadArg) }
    ip.kfoldcv(k, n, sz)
    var s0 = 0usize
    var f = 0usize
    while f < k {
        var q = 0usize
        while q < n {
            ins[q] = 0usize
            q += 1usize
        }
        q = 0usize
        while q < sz[f] {
            ins[my[s0 + q]] = 1usize
            q += 1usize
        }
        s0 += sz[f]
        var nt = 0usize
        q = 0usize
        while q < n {
            if ins[q] == 0usize { nt += 1usize }
            q += 1usize
        }
        let (rows, er) = grab_u(a, nt)
        if er != ok { ret (r, er) }
        let (orows, eo) = grab_u(a, n - nt)
        if eo != ok { ret (r, eo) }
        var ti = 0usize
        var oi = 0usize
        q = 0usize
        while q < n {
            if ins[q] == 0usize {
                rows[ti] = q
                ti += 1usize
            } else {
                orows[oi] = q
                oi += 1usize
            }
            q += 1usize
        }
        let (fd, ef) = subset(a, d, rows)
        if ef != ok { ret (r, ef) }
        let (od, eod) = subset(a, d, orows)
        if eod != ok { ret (r, eod) }
        let (pr, ep) = model_predict(a, g, m, &fd, od.x, od.n)
        if ep != ok { ret (r, ep) }
        q = 0usize
        while q < orows.len {
            allp[orows[q]] = pr[q]
            q += 1usize
        }
        f += 1usize
    }
    r.pred = allp
    r.npred = n
    r.est = mean_err(allp, d.y, false)
    ret (r, ok)
}

// the mean of the non-missing entries of one observation's row of the bootstrap table (NaN when none)
fn row_mean(t: []const f64, nb: usize, skip: usize) -> f64 {
    var s = 0.0f64
    var c = 0.0f64
    var j = 0usize
    while j < nb {
        if j != skip && t[j] == t[j] {
            s += t[j]
            c += 1.0f64
        }
        j += 1usize
    }
    if c == 0.0f64 { ret nan() }
    ret s / c
}

fn mean_rows(t: []const f64, n: usize, nb: usize, skip: usize) -> f64 {
    var s = 0.0f64
    var c = 0.0f64
    var i = 0usize
    while i < n {
        let rm = row_mean(t[i * nb..i * nb + nb], nb, skip)
        if rm == rm {
            s += rm
            c += 1.0f64
        }
        i += 1usize
    }
    ret s / c
}

// errorest(estimator = "boot" | "632plus" | both): which 1 boot, 2 632plus, 3 both (error and sd are the boot ones, err632 the 632+ one)
fn est_boot(a: *mem.Arena, g: *rng.Rng, d: *const Data, m: *const Model, nboot: usize, which: usize) -> (Est, err) {
    var r: Est = zero
    let n = d.n
    let cls = d.k > 0usize
    if nboot <= 2usize { ret (r, BadArg) }
    if which != 1usize && !cls { ret (r, BadArg) }
    let (tab, e1) = grab(a, n * nboot)
    if e1 != ok { ret (r, e1) }
    let (bp, e2) = grab(a, n * nboot)
    if e2 != ok { ret (r, e2) }
    let (inb, e3) = grab_u(a, n)
    if e3 != ok { ret (r, e3) }
    var i = 0usize
    while i < n * nboot {
        tab[i] = nan()
        bp[i] = nan()
        i += 1usize
    }
    var b = 0usize
    while b < nboot {
        let (s, es) = rng.sample_int(a, g, i64(n), i64(n), true)
        if es != ok { ret (r, es) }
        let (rows, er) = grab_u(a, n)
        if er != ok { ret (r, er) }
        i = 0usize
        while i < n {
            rows[i] = usize(s[i] - 1i64)
            inb[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            inb[rows[i]] = 1usize
            i += 1usize
        }
        let (fd, ef) = subset(a, d, rows)
        if ef != ok { ret (r, ef) }
        var no = 0usize
        i = 0usize
        while i < n {
            if inb[i] == 0usize { no += 1usize }
            i += 1usize
        }
        let (orows, eo) = grab_u(a, no)
        if eo != ok { ret (r, eo) }
        no = 0usize
        i = 0usize
        while i < n {
            if inb[i] == 0usize {
                orows[no] = i
                no += 1usize
            }
            i += 1usize
        }
        if cls {
            // class: predict all n rows, keep the out-of-bag ones
            let (pr, ep) = model_predict(a, g, m, &fd, d.x, n)
            if ep != ok { ret (r, ep) }
            i = 0usize
            while i < no {
                let row = orows[i]
                bp[row * nboot + b] = pr[row]
                if pr[row] != d.y[row] { tab[row * nboot + b] = 1.0f64 } else { tab[row * nboot + b] = 0.0f64 }
                i += 1usize
            }
        } else {
            let (od, eod) = subset(a, d, orows)
            if eod != ok { ret (r, eod) }
            let (pr, ep) = model_predict(a, g, m, &fd, od.x, od.n)
            if ep != ok { ret (r, ep) }
            i = 0usize
            while i < no {
                let row = orows[i]
                bp[row * nboot + b] = pr[i]
                tab[row * nboot + b] = (pr[i] - d.y[row]) * (pr[i] - d.y[row])
                i += 1usize
            }
        }
        b += 1usize
    }
    r.nk = nboot
    r.pred = bp
    r.npred = n * nboot
    let one = mean_rows(tab, n, nboot, nboot)
    if !cls {
        r.est = math.sqrt[f64](one)
        r.sd = nan()
        r.err632 = nan()
        ret (r, ok)
    }
    r.est = one
    r.sd = nan()
    r.err632 = nan()
    if which >= 2usize {
        let (fp, ep) = model_predict(a, g, m, d, d.x, n)
        if ep != ok { ret (r, ep) }
        var mis = 0.0f64
        i = 0usize
        while i < n {
            if fp[i] != d.y[i] { mis += 1.0f64 }
            i += 1usize
        }
        let resub = mis / f64(n)
        let err632 = 0.368f64 * resub + 0.632f64 * one
        var gm = 0.0f64
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if d.y[i] != fp[j] { gm += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        let gamma = gm / (f64(n) * f64(n))
        var rr = (one - resub) / (gamma - resub)
        if !(one > resub && gamma > resub) { rr = 0.0f64 }
        var ep2 = one
        if gamma < one { ep2 = gamma }
        r.err632 = err632 + (ep2 - resub) * (0.368f64 * 0.632f64 * rr) / (1.0f64 - 0.368f64 * rr)
        if which == 2usize { r.est = r.err632 }
    }
    if which != 2usize {
        let (expb, ee) = grab(a, nboot)
        if ee != ok { ret (r, ee) }
        var q = 0usize
        var tot = 0.0f64
        while q < nboot {
            expb[q] = mean_rows(tab, n, nboot, q)
            tot += expb[q]
            q += 1usize
        }
        let mu = tot / f64(nboot)
        var ss = 0.0f64
        q = 0usize
        while q < nboot {
            ss += (expb[q] - mu) * (expb[q] - mu)
            q += 1usize
        }
        r.sd = math.sqrt[f64]((f64(nboot) - 1.0f64) / f64(nboot) * ss)
    }
    ret (r, ok)
}

// ---- inbagg: bagging with intermediate variables (the default workhorse.inbagg): per bag, models of the intermediates w from the predictors on the
// out-of-bag (or bag, or all) rows, then a class tree on the predictors and the predicted intermediates.

type Inb = struct {
    d: Data,
    q: usize,
    w: []const f64,
    nbagg: usize,
    ns: usize,
    wkind: usize,
    ncol: usize,
    bindx: []usize,
    coefs: []f64,
    wtrees: []rf.View,
    trees: []rf.View,
}

// the design of lm: an intercept, numeric columns, and the dummies of levels 2 .. L of each factor
fn lm_design(a: *mem.Arena, d: *const Data, xn: []const f64, nn: usize) -> ([]f64, usize, err) {
    var w = 1usize
    var j = 0usize
    while j < d.p {
        if d.ncat[j] == 0usize { w += 1usize } else { w += d.ncat[j] - 1usize }
        j += 1usize
    }
    let (o, e) = grab(a, nn * w)
    if e != ok { ret (o, w, e) }
    var i = 0usize
    while i < nn {
        o[i] = 1.0f64
        i += 1usize
    }
    var at = 1usize
    j = 0usize
    while j < d.p {
        if d.ncat[j] == 0usize {
            i = 0usize
            while i < nn {
                o[at * nn + i] = xn[j * nn + i]
                i += 1usize
            }
            at += 1usize
        } else {
            var l = 2usize
            while l <= d.ncat[j] {
                i = 0usize
                while i < nn {
                    if xn[j * nn + i] == f64(l) { o[at * nn + i] = 1.0f64 }
                    i += 1usize
                }
                at += 1usize
                l += 1usize
            }
        }
        j += 1usize
    }
    ret (o, w, ok)
}

// the intermediates of bag t predicted for the nn rows of xn, column-major nn x q
fn inb_intermed(a: *mem.Arena, m: *const Inb, t: usize, xn: []const f64, nn: usize) -> ([]f64, err) {
    let (out, e) = grab(a, nn * m.q)
    if e != ok { ret (out, e) }
    var j = 0usize
    while j < m.q {
        if m.wkind == 1usize {
            let (des, wd, ed) = lm_design(a, &m.d, xn, nn)
            if ed != ok { ret (out, ed) }
            var i = 0usize
            while i < nn {
                var s = 0.0f64
                var c = 0usize
                while c < wd {
                    let b = m.coefs[(t * m.q + j) * m.ncol + c]
                    if b == b { s += b * des[c * nn + i] }
                    c += 1usize
                }
                out[j * nn + i] = s
                i += 1usize
            }
        } else {
            let v = &m.wtrees[t * m.q + j]
            var i = 0usize
            while i < nn {
                out[j * nn + i] = v.fyval[rf.rp_predict_row(v, xn, nn, i)]
                i += 1usize
            }
        }
        j += 1usize
    }
    ret (out, ok)
}

// inbagg(y ~ w ~ x, pFUN = list(list(model = lm | rpart)), cFUN = list(model = rpart, training.set = fitted.bag | original)): wkind 1 lm, 2 rpart;
// wtrain 0 oob, 1 bag, 2 all; the final tree is y ~ w (cFUN$formula is the left formula) on the fitted.bag rows (training.set = original leaves the formula unrenamed and fails in ipred itself); nsfrac is the fraction of the rows drawn per bag
fn inb_fit(a: *mem.Arena, g: *rng.Rng, d: *const Data, w: []const f64, q: usize, nbagg: usize, nsfrac: f64, replace: bool, wkind: usize, wctl: rf.Control, wtrain: usize, cctl: rf.Control) -> (Inb, err) {
    var m: Inb = zero
    let n = d.n
    let nsz = usize(f64(n) * nsfrac)
    m.d = *d
    m.q = q
    m.w = w
    m.nbagg = nbagg
    m.ns = nsz
    m.wkind = wkind
    let (des0, wd, ed0) = lm_design(a, d, d.x, 1usize)
    if ed0 != ok { ret (m, ed0) }
    let _ = des0
    m.ncol = wd
    let (bx, e1) = grab_u(a, nbagg * nsz)
    if e1 != ok { ret (m, e1) }
    let (coefs, e2) = grab(a, nbagg * q * wd)
    if e2 != ok { ret (m, e2) }
    let (wt, e3) = mem.alloc[rf.View](a, nbagg * q + 1usize)
    if e3 != ok { ret (m, e3) }
    let (trees, e4) = mem.alloc[rf.View](a, nbagg)
    if e4 != ok { ret (m, e4) }
    m.bindx = bx
    m.coefs = coefs
    m.wtrees = wt
    m.trees = trees
    let (isin, e5) = grab_u(a, n)
    if e5 != ok { ret (m, e5) }
    var t = 0usize
    while t < nbagg {
        let (s, es) = rng.sample_int(a, g, i64(n), i64(nsz), replace)
        if es != ok { ret (m, es) }
        var i = 0usize
        while i < n {
            isin[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < nsz {
            bx[t * nsz + i] = usize(s[i] - 1i64)
            isin[bx[t * nsz + i]] = 1usize
            i += 1usize
        }
        // the rows the intermediate models are fit on
        var nf = n
        if wtrain == 1usize { nf = nsz }
        if wtrain == 0usize {
            nf = 0usize
            i = 0usize
            while i < n {
                if isin[i] == 0usize { nf += 1usize }
                i += 1usize
            }
        }
        let (frows, ef) = grab_u(a, nf)
        if ef != ok { ret (m, ef) }
        var at = 0usize
        i = 0usize
        while i < n && wtrain == 2usize {
            frows[i] = i
            i += 1usize
        }
        i = 0usize
        while i < n && wtrain == 0usize {
            if isin[i] == 0usize {
                frows[at] = i
                at += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < nsz && wtrain == 1usize {
            frows[i] = bx[t * nsz + i]
            i += 1usize
        }
        var j = 0usize
        while j < q {
            var dw = *d
            dw.y = w[j * n..j * n + n]
            dw.k = 0usize
            let (sub, esub) = subset(a, &dw, frows)
            if esub != ok { ret (m, esub) }
            if wkind == 1usize {
                let (des, wdd, edd) = lm_design(a, &sub, sub.x, sub.n)
                if edd != ok { ret (m, edd) }
                let (lf, el) = decomp.lm_fit(a, des, sub.n, wdd, sub.y, 0.0000001f64)
                if el != ok { ret (m, el) }
                var c = 0usize
                while c < wdd {
                    coefs[(t * q + j) * wd + c] = lf.coef[c]
                    c += 1usize
                }
            } else {
                let (v, ev) = fit_tree(a, g, &sub, wctl)
                if ev != ok { ret (m, ev) }
                wt[t * q + j] = v
            }
            j += 1usize
        }
        // the final tree
        let (wcols, ewn) = inb_intermed(a, &m, t, d.x, n)
        if ewn != ok { ret (m, ewn) }
        let crows = bx[t * nsz..t * nsz + nsz]
        let (nc, enc) = grab_u(a, q + 1usize)
        if enc != ok { ret (m, enc) }
        var dj: Data = zero
        dj.n = n
        dj.p = q
        dj.k = d.k
        dj.ncat = nc
        dj.x = wcols
        dj.y = d.y
        let (sj, esj) = subset(a, &dj, crows)
        if esj != ok { ret (m, esj) }
        let (tv, etv) = fit_tree(a, g, &sj, cctl)
        if etv != ok { ret (m, etv) }
        trees[t] = tv
        t += 1usize
    }
    ret (m, ok)
}

// predict.inbagg: the class code of each of the nn rows, a vote of the bags, ties broken by sample
fn inb_predict(a: *mem.Arena, g: *rng.Rng, m: *const Inb, xn: []const f64, nn: usize) -> ([]f64, err) {
    let k = m.d.k
    let (out, e) = grab(a, nn)
    if e != ok { ret (out, e) }
    let (vote, e2) = grab(a, nn * k)
    if e2 != ok { ret (out, e2) }
    var t = 0usize
    while t < m.nbagg {
        let (wn, ew) = inb_intermed(a, m, t, xn, nn)
        if ew != ok { ret (out, ew) }
        let xx = wn
        let v = &m.trees[t]
        var i = 0usize
        while i < nn {
            let row = rf.rp_predict_row(v, xx, nn, i)
            vote[i * k + usize(v.fyval[row]) - 1usize] += 1.0f64
            i += 1usize
        }
        t += 1usize
    }
    var i = 0usize
    while i < nn {
        let (wm, ewm) = which_max(a, g, vote[i * k..i * k + k])
        if ewm != ok { ret (out, ewm) }
        out[i] = f64(wm + 1usize)
        i += 1usize
    }
    ret (out, ok)
}
