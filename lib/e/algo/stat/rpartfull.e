// R rpart 4.1.27 (CART trees) from the C sources: methods anova, poisson, class (gini and information) and exp (survival rescaled to a Poisson
// problem), unordered factor predictors (codes 1 .. ncat, the gray-code subset search), missing predictors (NaN) with competing and surrogate splits,
// case weights, variable costs, class priors and loss matrices, the complexity table with its cross-validation under R's `sample` folds, prune,
// predict (the pred_rpart walk), variable importance, rpart.control, the node labels, and rpart's insert_split slip (a full list of two that takes a new
// best keeps only that split, so maxcompete = 1 trees show fewer competitors).
//
// Observations carry 0-based numbers; a node owns the segment idx[lo..hi] of one permutation that is split in place (left, right, stays). Splits are
// found per predictor on a stable sort of the node's rows, which differs from rpart's quicksort only in the order equal predictors are summed.
// Child complexities, the cp list and rundown are line for line the C, including its use of a stale xtemp entry when an observation cannot descend.
//
// Not here: ordered factors (rpart turns them into csplit rows after the fact), user splitting functions, start-stop survival responses, subset and
// na.action (the caller hands over complete responses), the plotting and text helpers.

use e.algo.rand.r as rng
use e.math
use e.mem
use e.str

error BadSpec

const NONE: usize = 4294967295usize

type Pool = struct {
    cap: usize,
    nn: usize,
    scap: usize,
    ns: usize,
    nid: []i64,
    risk: []f64,
    cplx: []f64,
    wsum: []f64,
    nobs: []usize,
    resp: []f64,
    lc: []usize,
    rc: []usize,
    pstart: []usize,
    npri: []usize,
    nsur: []usize,
    lastsur: []i64,
    svar: []usize,
    simp: []f64,
    sspt: []f64,
    sdir: []i64,
    scount: []f64,
    sadj: []f64,
    scs: []i64,
}

type Control = struct {
    minsplit: f64,
    minbucket: f64,
    cp: f64,
    maxcompete: f64,
    maxsurrogate: f64,
    usesurrogate: f64,
    surrogatestyle: f64,
    maxdepth: f64,
    xval: f64,
}

type Fit = struct {
    n: usize,
    p: usize,
    ny: usize,
    x: []const f64,
    y: []const f64,
    wt: []const f64,
    ncat: []const usize,
    cost: []const f64,
    method: usize,
    nresp: usize,
    k: usize,
    maxcat: usize,
    minsplit: usize,
    minbucket: usize,
    cp: f64,
    maxpri: usize,
    maxsur: usize,
    usesur: usize,
    suragree: usize,
    maxnode: i64,
    alpha: f64,
    iscale: f64,
    ctl: Control,
    prior: []f64,
    uprior: []f64,
    aprior: []f64,
    lossa: []f64,
    freqv: []f64,
    counts: []f64,
    info: bool,
    shrink: f64,
    ealpha: f64,
    ebeta: f64,
    wpred: usize,
    ob: []usize,
    ob2: []usize,
    idx: []usize,
    tmpv: []usize,
    which: []i64,
    tempy: []i64,
    cs: []i64,
    cl: []i64,
    cr: []i64,
    lwt: []f64,
    rwt: []f64,
    gray: []i64,
    gmaxc: usize,
    gsave: i64,
    cnt: []i64,
    tsp: []i64,
    sumv: []f64,
    wtv: []f64,
    meanv: []f64,
    rate: []f64,
    death: []f64,
    ord1: []i64,
    ord2: []i64,
    ccnt: []f64,
    lcnt: []f64,
    rcnt: []f64,
    cn: usize,
    cvar: []usize,
    cimp: []f64,
    cspt: []f64,
    cdir: []i64,
    ccount: []f64,
    cadj: []f64,
    ccs: []i64,
    pl: Pool,
    ncp: usize,
    cpcp: []f64,
    cprisk: []f64,
    cpnsplit: []f64,
    cpx: []f64,
    cpxs: []f64,
    hasx: bool,
    rootrisk: f64,
    totwt: f64,
}

fn rp_finite(v: f64) -> bool { ret v - v == 0.0f64 }

fn rp_round_even(v: f64) -> f64 {
    let f = math.floor[f64](v)
    let d = v - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    let h = f / 2.0f64
    if math.floor[f64](h) == h { ret f }
    ret f + 1.0f64
}

// rpart.control: NaN stands for an argument that was not given
fn rp_control(minsplit: f64, minbucket: f64, cp: f64, maxcompete: f64, maxsurrogate: f64, usesurrogate: f64, surrogatestyle: f64, maxdepth: f64, xval: f64) -> (Control, err) {
    var c: Control = zero
    c.minsplit = 20.0f64
    c.cp = 0.01f64
    c.maxcompete = 4.0f64
    c.maxsurrogate = 5.0f64
    c.usesurrogate = 2.0f64
    c.xval = 10.0f64
    c.surrogatestyle = 0.0f64
    c.maxdepth = 30.0f64
    if minsplit == minsplit { c.minsplit = minsplit }
    if minbucket == minbucket { c.minbucket = minbucket } else { c.minbucket = rp_round_even(c.minsplit / 3.0f64) }
    if minsplit != minsplit && minbucket == minbucket { c.minsplit = minbucket * 3.0f64 }
    if cp == cp { c.cp = cp }
    if maxcompete == maxcompete { c.maxcompete = maxcompete }
    if c.maxcompete < 0.0f64 { c.maxcompete = 0.0f64 }
    if maxsurrogate == maxsurrogate { c.maxsurrogate = maxsurrogate }
    if usesurrogate == usesurrogate { c.usesurrogate = usesurrogate }
    if c.usesurrogate < 0.0f64 || c.usesurrogate > 2.0f64 { c.usesurrogate = 2.0f64 }
    if surrogatestyle == surrogatestyle { c.surrogatestyle = surrogatestyle }
    if c.surrogatestyle < 0.0f64 || c.surrogatestyle > 1.0f64 { c.surrogatestyle = 0.0f64 }
    if maxdepth == maxdepth { c.maxdepth = maxdepth }
    if c.maxdepth > 30.0f64 || c.maxdepth < 1.0f64 { ret (c, BadSpec) }
    if xval == xval { c.xval = xval }
    if c.xval < 0.0f64 { c.xval = 0.0f64 }
    ret (c, ok)
}

// the fold of every observation, 1 .. xval, as rpart draws them after set.seed(seed)
fn rp_xgroups(a: *mem.Arena, seed: i64, n: usize, xval: usize) -> ([]usize, err) {
    var g: []usize = zero
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    let (perm, e1) = rng.sample_int(a, &r, i64(n), i64(n), false)
    if e1 != ok { ret (g, e1) }
    let (out, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (g, e2) }
    var i = 0usize
    while i < n {
        out[i] = usize((perm[i] - 1i64) % i64(xval)) + 1usize
        i += 1usize
    }
    ret (out, ok)
}

// ---- the splitting functions' scratch walk (graycode.c)

fn rp_gray_init1(t: *Fit, numcat: usize, count: []const i64) {
    t.gmaxc = numcat
    var i = 0usize
    while i < numcat {
        if count[i] != 0i64 { t.gray[i] = 1i64 } else { t.gray[i] = 0i64 }
        i += 1usize
    }
    t.gsave = 0i64 - 2i64
}

fn rp_gray_init2(t: *Fit, numcat: usize, count: []const i64, val: []f64) {
    t.gmaxc = numcat
    t.gray[0usize] = 0i64
    var k = 0usize
    if count[0usize] == 0i64 { k = 1usize }
    var i = 1usize
    while i < numcat {
        if count[i] == 0i64 {
            var j = i
            while j > k {
                t.gray[j] = t.gray[j - 1usize]
                val[j] = val[j - 1usize]
                j -= 1usize
            }
            t.gray[k] = i64(i)
            k += 1usize
        } else {
            let temp = val[i]
            var j = i
            while j > k && val[j - 1usize] > temp {
                t.gray[j] = t.gray[j - 1usize]
                val[j] = val[j - 1usize]
                j -= 1usize
            }
            val[j] = temp
            t.gray[j] = i64(i)
        }
        i += 1usize
    }
    t.gsave = i64(k) - 1i64
}

fn rp_graycode(t: *Fit) -> usize {
    if t.gsave > 0i64 - 2i64 {
        t.gsave += 1i64
        if t.gsave < i64(t.gmaxc) { ret usize(t.gray[usize(t.gsave)]) }
        ret t.gmaxc
    }
    var i = 0usize
    while i + 1usize < t.gmaxc {
        if t.gray[i] == 1i64 {
            t.gray[i] = 2i64
            ret i
        }
        if t.gray[i] == 2i64 { t.gray[i] = 1i64 }
        i += 1usize
    }
    ret t.gmaxc
}

// ---- node evaluation (anovass, poissondev, ginidev) over idx[lo..hi]; the node's value goes to resp, the risk comes back

fn rp_eval(t: *Fit, node: usize, lo: usize, hi: usize) -> f64 {
    let ny = t.ny
    let base = node * t.nresp
    if t.method == 1usize {
        var temp = 0.0f64
        var twt = 0.0f64
        var i = lo
        while i < hi {
            let o = t.idx[i]
            temp += t.y[o * ny] * t.wt[o]
            twt += t.wt[o]
            i += 1usize
        }
        let mean = temp / twt
        var ss = 0.0f64
        i = lo
        while i < hi {
            let o = t.idx[i]
            let d = t.y[o * ny] - mean
            ss += d * d * t.wt[o]
            i += 1usize
        }
        t.pl.resp[base] = mean
        ret ss
    }
    if t.method == 2usize {
        var death = 0.0f64
        var time = 0.0f64
        var i = lo
        while i < hi {
            let o = t.idx[i]
            death += t.y[o * ny + 1usize] * t.wt[o]
            time += t.y[o * ny] * t.wt[o]
            i += 1usize
        }
        let lambda = (death + t.ealpha) / (time + t.ebeta)
        var dev = 0.0f64
        i = lo
        while i < hi {
            let o = t.idx[i]
            let temp = t.y[o * ny + 1usize]
            dev -= (lambda * t.y[o * ny] - temp) * t.wt[o]
            if temp > 0.0f64 { dev += (temp * math.log[f64](lambda * t.y[o * ny] / temp)) * t.wt[o] }
            i += 1usize
        }
        t.pl.resp[base] = lambda
        t.pl.resp[base + 1usize] = death
        ret 0.0f64 - 2.0f64 * dev
    }
    let k = t.k
    var c = 0usize
    while c < k {
        t.freqv[c] = 0.0f64
        c += 1usize
    }
    var temp = 0.0f64
    var i = lo
    while i < hi {
        let o = t.idx[i]
        let j = usize(t.y[o * ny]) - 1usize
        t.freqv[j] += t.wt[o]
        temp += t.wt[o] * t.prior[j]
        i += 1usize
    }
    let prob = temp
    var dev = 0.0f64
    var best = 0usize
    c = 0usize
    while c < k {
        temp = 0.0f64
        var j = 0usize
        while j < k {
            temp += t.freqv[j] * t.lossa[c * k + j] * t.prior[j]
            j += 1usize
        }
        if c == 0usize || temp < dev {
            best = c
            dev = temp
        }
        c += 1usize
    }
    t.pl.resp[base] = f64(best + 1usize)
    c = 0usize
    while c < k {
        t.pl.resp[base + 1usize + c] = t.freqv[c]
        c += 1usize
    }
    t.pl.resp[base + k + 1usize] = prob
    ret dev
}

// the error of predicting obs o with a node's value (anovapred, poissonpred, ginipred)
fn rp_error(t: *Fit, o: usize, resp0: f64) -> f64 {
    let ny = t.ny
    if t.method == 1usize {
        let d = t.y[o * ny] - resp0
        ret d * d
    }
    if t.method == 2usize {
        let y1 = t.y[o * ny + 1usize]
        let y0 = t.y[o * ny]
        if t.wpred == 1usize {
            var dev = y1 - resp0 * y0
            if y1 > 0.0f64 { dev += y1 * math.log[f64](resp0 * y0 / y1) }
            ret 0.0f64 - 2.0f64 * dev
        }
        let d = math.sqrt[f64](y1) - math.sqrt[f64](resp0 * y0)
        ret d * d
    }
    let i = usize(t.y[o * ny]) - 1usize
    let j = usize(resp0) - 1usize
    ret t.prior[i] * t.lossa[i * t.k + j]
}

// poissoninit's shrinkage constants from the rows idx[lo..hi]
fn rp_pinit(t: *Fit, lo: usize, hi: usize) {
    var event = 0.0f64
    var time = 0.0f64
    var i = lo
    while i < hi {
        let o = t.idx[i]
        event += t.y[o * t.ny + 1usize] * t.wt[o]
        time += t.y[o * t.ny] * t.wt[o]
        i += 1usize
    }
    if t.shrink <= 0.0f64 {
        t.ealpha = 0.0f64
        t.ebeta = 0.0f64
    } else {
        t.ealpha = 1.0f64 / (t.shrink * t.shrink)
        t.ebeta = t.ealpha / (event / time)
    }
}

fn rp_impurity(t: *Fit, p: f64) -> f64 {
    if t.info {
        if p == 0.0f64 { ret 0.0f64 }
        ret 0.0f64 - p * math.log[f64](p)
    }
    ret p * (1.0f64 - p)
}

// the k rows in t.ob sorted by predictor col (stable)
fn rp_sort_ob(t: *Fit, col: usize, k: usize) {
    let xs = t.x[col * t.n..col * t.n + t.n]
    var width = 1usize
    while width < k {
        var lo = 0usize
        while lo < k {
            var mid = lo + width
            if mid > k { mid = k }
            var hi = lo + 2usize * width
            if hi > k { hi = k }
            var i = lo
            var j = mid
            var o = lo
            while i < mid && j < hi {
                if xs[t.ob[j]] < xs[t.ob[i]] {
                    t.ob2[o] = t.ob[j]
                    j += 1usize
                } else {
                    t.ob2[o] = t.ob[i]
                    i += 1usize
                }
                o += 1usize
            }
            while i < mid {
                t.ob2[o] = t.ob[i]
                i += 1usize
                o += 1usize
            }
            while j < hi {
                t.ob2[o] = t.ob[j]
                j += 1usize
                o += 1usize
            }
            lo = hi
        }
        var c = 0usize
        while c < k {
            t.ob[c] = t.ob2[c]
            c += 1usize
        }
        width = width * 2usize
    }
}

// ---- choose_split: (improve, split, direction) for predictor col over t.ob[0..k]; a categorical answer is in t.cs

fn rp_choose_anova(t: *Fit, col: usize, k: usize, nc: usize, myrisk: f64) -> (f64, f64, i64) {
    let ny = t.ny
    let xs = t.x[col * t.n..col * t.n + t.n]
    let edge = t.minbucket
    var right_wt = 0.0f64
    var right_n = k
    var right_sum = 0.0f64
    var i = 0usize
    while i < k {
        let o = t.ob[i]
        right_sum += t.y[o * ny] * t.wt[o]
        right_wt += t.wt[o]
        i += 1usize
    }
    let grand = right_sum / right_wt
    var direction = 0i64 - 1i64
    var where = 0usize
    var best = 0.0f64
    if nc == 0usize {
        var left_sum = 0.0f64
        var left_wt = 0.0f64
        var left_n = 0usize
        right_sum = 0.0f64
        i = 0usize
        while right_n > edge {
            let o = t.ob[i]
            left_wt += t.wt[o]
            right_wt -= t.wt[o]
            left_n += 1usize
            right_n -= 1usize
            let temp = (t.y[o * ny] - grand) * t.wt[o]
            left_sum += temp
            right_sum -= temp
            if xs[t.ob[i + 1usize]] != xs[o] && left_n >= edge {
                let v = left_sum * left_sum / left_wt + right_sum * right_sum / right_wt
                if v > best {
                    best = v
                    where = i
                    if left_sum < right_sum { direction = 0i64 - 1i64 } else { direction = 1i64 }
                }
            }
            i += 1usize
        }
        var split = 0.0f64
        if best > 0.0f64 { split = (xs[t.ob[where]] + xs[t.ob[where + 1usize]]) / 2.0f64 }
        ret (best / myrisk, split, direction)
    }
    i = 0usize
    while i < nc {
        t.sumv[i] = 0.0f64
        t.cnt[i] = 0i64
        t.wtv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        let o = t.ob[i]
        let j = usize(xs[o]) - 1usize
        t.cnt[j] += 1i64
        t.wtv[j] += t.wt[o]
        t.sumv[j] += (t.y[o * ny] - grand) * t.wt[o]
        i += 1usize
    }
    i = 0usize
    while i < nc {
        if t.cnt[i] > 0i64 {
            t.tsp[i] = 1i64
            t.meanv[i] = t.sumv[i] / t.wtv[i]
        } else {
            t.tsp[i] = 0i64
        }
        i += 1usize
    }
    rp_gray_init2(t, nc, t.cnt, t.meanv)
    var left_wt = 0.0f64
    var left_sum = 0.0f64
    right_sum = 0.0f64
    var left_n = 0usize
    while true {
        let j = rp_graycode(t)
        if j >= nc { break }
        t.tsp[j] = 0i64 - 1i64
        left_n += usize(t.cnt[j])
        right_n -= usize(t.cnt[j])
        left_wt += t.wtv[j]
        right_wt -= t.wtv[j]
        left_sum += t.sumv[j]
        right_sum -= t.sumv[j]
        if left_n >= edge && right_n >= edge {
            let temp = left_sum * left_sum / left_wt + right_sum * right_sum / right_wt
            if temp > best {
                best = temp
                var c = 0usize
                if (left_sum / left_wt) > (right_sum / right_wt) {
                    while c < nc {
                        t.cs[c] = 0i64 - t.tsp[c]
                        c += 1usize
                    }
                } else {
                    while c < nc {
                        t.cs[c] = t.tsp[c]
                        c += 1usize
                    }
                }
            }
        }
    }
    ret (best / myrisk, 0.0f64, 0i64)
}

fn rp_choose_poisson(t: *Fit, col: usize, k: usize, nc: usize, myrisk: f64) -> (f64, f64, i64) {
    let ny = t.ny
    let xs = t.x[col * t.n..col * t.n + t.n]
    let edge = t.minbucket
    var right_d = 0.0f64
    var right_time = 0.0f64
    var right_n = k
    var i = 0usize
    while i < k {
        let o = t.ob[i]
        right_d += t.y[o * ny + 1usize] * t.wt[o]
        right_time += t.y[o * ny] * t.wt[o]
        i += 1usize
    }
    var lambda2 = right_d / right_time
    if lambda2 == 0.0f64 { ret (0.0f64, 0.0f64, 0i64) }
    let dev = right_d * math.log[f64](lambda2)
    var direction = 0i64 - 1i64
    var best = dev
    if nc == 0usize {
        var left_time = 0.0f64
        var left_d = 0.0f64
        var where = 0i64 - 1i64
        i = 0usize
        while i + edge < k {
            let o = t.ob[i]
            left_d += t.y[o * ny + 1usize] * t.wt[o]
            right_d -= t.y[o * ny + 1usize] * t.wt[o]
            left_time += t.y[o * ny] * t.wt[o]
            right_time -= t.y[o * ny] * t.wt[o]
            if xs[t.ob[i + 1usize]] != xs[o] && (1usize + i) >= edge {
                let lambda1 = left_d / left_time
                lambda2 = right_d / right_time
                var temp = 0.0f64
                if lambda1 > 0.0f64 { temp += left_d * math.log[f64](lambda1) }
                if lambda2 > 0.0f64 { temp += right_d * math.log[f64](lambda2) }
                if temp > best {
                    best = temp
                    where = i64(i)
                    if lambda1 < lambda2 { direction = 0i64 - 1i64 } else { direction = 1i64 }
                }
            }
            i += 1usize
        }
        var split = 0.0f64
        if where >= 0i64 { split = (xs[t.ob[usize(where)]] + xs[t.ob[usize(where) + 1usize]]) / 2.0f64 }
        ret (0.0f64 - 2.0f64 * (dev - best), split, direction)
    }
    i = 0usize
    while i < nc {
        t.wtv[i] = 0.0f64
        t.death[i] = 0.0f64
        t.cnt[i] = 0i64
        i += 1usize
    }
    i = 0usize
    while i < k {
        let o = t.ob[i]
        let j = usize(xs[o] - 1.0f64)
        t.cnt[j] += 1i64
        t.death[j] += t.y[o * ny + 1usize] * t.wt[o]
        t.wtv[j] += t.y[o * ny] * t.wt[o]
        i += 1usize
    }
    var ncat = 0usize
    i = 0usize
    while i < nc {
        t.ord1[i] = 0i64
        if t.cnt[i] > 0i64 {
            ncat += 1usize
            t.rate[i] = t.death[i] / t.wtv[i]
            var j = i
            while j > 0usize {
                j -= 1usize
                if t.cnt[j] > 0i64 {
                    if t.rate[i] > t.rate[j] { t.ord1[j] += 1i64 } else { t.ord1[i] += 1i64 }
                }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < nc {
        if t.cnt[i] > 0i64 { t.ord2[usize(t.ord1[i])] = i64(i) }
        i += 1usize
    }
    var left_n = 0usize
    var left_d = 0.0f64
    var left_time = 0.0f64
    var where = 0usize
    i = 0usize
    while i + 1usize < ncat {
        let j = usize(t.ord2[i])
        left_n += usize(t.cnt[j])
        right_n -= usize(t.cnt[j])
        left_time += t.wtv[j]
        right_time -= t.wtv[j]
        left_d += t.death[j]
        right_d -= t.death[j]
        if left_n >= edge && right_n >= edge {
            let lambda1 = left_d / left_time
            lambda2 = right_d / right_time
            var temp = 0.0f64
            if lambda1 > 0.0f64 { temp += left_d * math.log[f64](lambda1) }
            if lambda2 > 0.0f64 { temp += right_d * math.log[f64](lambda2) }
            if temp > best {
                best = temp
                where = i
                if lambda1 < lambda2 { direction = 0i64 - 1i64 } else { direction = 1i64 }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < nc {
        t.cs[i] = 0i64
        i += 1usize
    }
    i = 0usize
    while i <= where {
        t.cs[usize(t.ord2[i])] = direction
        i += 1usize
    }
    while i < ncat {
        t.cs[usize(t.ord2[i])] = 0i64 - direction
        i += 1usize
    }
    ret (0.0f64 - 2.0f64 * (dev - best), 0.0f64, 0i64)
}

fn rp_choose_gini(t: *Fit, col: usize, k: usize, nc: usize, myrisk: f64) -> (f64, f64, i64) {
    let ny = t.ny
    let nk = t.k
    let xs = t.x[col * t.n..col * t.n + t.n]
    let edge = t.minbucket
    var c = 0usize
    while c < nk {
        t.lcnt[c] = 0.0f64
        t.rcnt[c] = 0.0f64
        c += 1usize
    }
    var lwt = 0.0f64
    var rwt = 0.0f64
    var rtot = 0usize
    var ltot = 0usize
    var i = 0usize
    while i < k {
        let o = t.ob[i]
        let j = usize(t.y[o * ny]) - 1usize
        rwt += t.aprior[j] * t.wt[o]
        t.rcnt[j] += t.wt[o]
        rtot += 1usize
        i += 1usize
    }
    var total_ss = 0.0f64
    c = 0usize
    while c < nk {
        let temp = t.aprior[c] * t.rcnt[c] / rwt
        total_ss += rwt * rp_impurity(t, temp)
        c += 1usize
    }
    var best = total_ss
    var direction = 0i64 - 1i64
    var where = 0usize
    if nc == 0usize {
        i = 0usize
        while rtot > edge {
            let o = t.ob[i]
            let j = usize(t.y[o * ny]) - 1usize
            rwt -= t.aprior[j] * t.wt[o]
            lwt += t.aprior[j] * t.wt[o]
            rtot -= 1usize
            ltot += 1usize
            t.rcnt[j] -= t.wt[o]
            t.lcnt[j] += t.wt[o]
            if ltot >= edge && xs[t.ob[i + 1usize]] != xs[o] {
                var temp = 0.0f64
                var lmean = 0.0f64
                var rmean = 0.0f64
                var jj = 0usize
                while jj < nk {
                    var pp = t.aprior[jj] * t.lcnt[jj] / lwt
                    temp += lwt * rp_impurity(t, pp)
                    lmean += pp * f64(jj)
                    pp = t.aprior[jj] * t.rcnt[jj] / rwt
                    temp += rwt * rp_impurity(t, pp)
                    rmean += pp * f64(jj)
                    jj += 1usize
                }
                if temp < best {
                    best = temp
                    where = i
                    if lmean < rmean { direction = 0i64 - 1i64 } else { direction = 1i64 }
                }
            }
            i += 1usize
        }
        let improve = total_ss - best
        var split = 0.0f64
        if improve > 0.0f64 { split = (xs[t.ob[where]] + xs[t.ob[where + 1usize]]) / 2.0f64 }
        ret (improve, split, direction)
    }
    i = 0usize
    while i < nc {
        t.wtv[i] = 0.0f64
        t.cnt[i] = 0i64
        c = 0usize
        while c < nk {
            t.ccnt[c * t.maxcat + i] = 0.0f64
            c += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        let o = t.ob[i]
        let j = usize(t.y[o * ny]) - 1usize
        let kk = usize(xs[o]) - 1usize
        t.wtv[kk] += t.aprior[j] * t.wt[o]
        t.cnt[kk] += 1i64
        t.ccnt[j * t.maxcat + kk] += t.wt[o]
        i += 1usize
    }
    i = 0usize
    while i < nc {
        if t.wtv[i] == 0.0f64 {
            t.tsp[i] = 0i64
        } else {
            t.rate[i] = t.ccnt[i] / t.wtv[i]
            t.tsp[i] = 1i64
        }
        i += 1usize
    }
    if nk == 2usize { rp_gray_init2(t, nc, t.cnt, t.rate) } else { rp_gray_init1(t, nc, t.cnt) }
    while true {
        let ii = rp_graycode(t)
        if ii >= nc { break }
        if t.tsp[ii] == 0i64 - 1i64 {
            t.tsp[ii] = 1i64
            rwt += t.wtv[ii]
            lwt -= t.wtv[ii]
            rtot += usize(t.cnt[ii])
            ltot -= usize(t.cnt[ii])
            c = 0usize
            while c < nk {
                t.rcnt[c] += t.ccnt[c * t.maxcat + ii]
                t.lcnt[c] -= t.ccnt[c * t.maxcat + ii]
                c += 1usize
            }
        } else {
            t.tsp[ii] = 0i64 - 1i64
            rwt -= t.wtv[ii]
            lwt += t.wtv[ii]
            rtot -= usize(t.cnt[ii])
            ltot += usize(t.cnt[ii])
            c = 0usize
            while c < nk {
                t.rcnt[c] -= t.ccnt[c * t.maxcat + ii]
                t.lcnt[c] += t.ccnt[c * t.maxcat + ii]
                c += 1usize
            }
        }
        if ltot >= edge && rtot >= edge {
            var temp = 0.0f64
            var lmean = 0.0f64
            var rmean = 0.0f64
            var jj = 0usize
            while jj < nk {
                var pp = t.aprior[jj] * t.lcnt[jj] / lwt
                temp += lwt * rp_impurity(t, pp)
                lmean += pp * f64(jj)
                pp = t.aprior[jj] * t.rcnt[jj] / rwt
                temp += rwt * rp_impurity(t, pp)
                rmean += pp * f64(jj)
                jj += 1usize
            }
            if temp < best {
                best = temp
                c = 0usize
                if lmean < rmean {
                    while c < nc {
                        t.cs[c] = t.tsp[c]
                        c += 1usize
                    }
                } else {
                    while c < nc {
                        t.cs[c] = 0i64 - t.tsp[c]
                        c += 1usize
                    }
                }
            }
        }
    }
    ret (total_ss - best, 0.0f64, 0i64)
}

// ---- the candidate list of insert_split.c (kept sorted by improvement, best first)

fn rp_cand_shift(t: *Fit, from: usize, to: usize) {
    var i = to
    while i > from {
        t.cvar[i] = t.cvar[i - 1usize]
        t.cimp[i] = t.cimp[i - 1usize]
        t.cspt[i] = t.cspt[i - 1usize]
        t.cdir[i] = t.cdir[i - 1usize]
        t.ccount[i] = t.ccount[i - 1usize]
        t.cadj[i] = t.cadj[i - 1usize]
        var c = 0usize
        while c < t.maxcat {
            t.ccs[i * t.maxcat + c] = t.ccs[(i - 1usize) * t.maxcat + c]
            c += 1usize
        }
        i -= 1usize
    }
}

// the slot the new split takes, or NONE when it is not good enough
fn rp_cand_slot(t: *Fit, improve: f64, max: usize) -> usize {
    let nl = t.cn
    if nl == 0usize {
        t.cn = 1usize
        ret 0usize
    }
    if max < 2usize {
        if improve <= t.cimp[0usize] { ret NONE }
        ret 0usize
    }
    var pos = nl
    var i = 0usize
    while i < nl {
        if improve > t.cimp[i] {
            pos = i
            break
        }
        i += 1usize
    }
    if nl == max {
        if pos == nl { ret NONE }
        // insert_split.c relinks wrongly when a full list of two takes a new best: the list is left holding that one split
        if nl == 2usize && pos == 0usize {
            t.cn = 1usize
            ret 0usize
        }
        rp_cand_shift(t, pos, nl - 1usize)
    } else {
        rp_cand_shift(t, pos, nl)
        t.cn = nl + 1usize
    }
    ret pos
}

// ---- bsplit: the best split of each predictor into the candidate list; returns the count

fn rp_bsplit(t: *Fit, node: usize, lo: usize, hi: usize) -> usize {
    t.cn = 0usize
    let myrisk = t.pl.risk[node]
    var v = 0usize
    while v < t.p {
        let nc = t.ncat[v]
        let xs = t.x[v * t.n..v * t.n + t.n]
        var k = 0usize
        var i = lo
        while i < hi {
            let o = t.idx[i]
            if rp_finite(xs[o]) && t.wt[o] > 0.0f64 {
                t.ob[k] = o
                k += 1usize
            }
            i += 1usize
        }
        if nc == 0usize && k > 0usize { rp_sort_ob(t, v, k) }
        if k == 0usize || (nc == 0usize && xs[t.ob[0usize]] == xs[t.ob[k - 1usize]]) {
            v += 1usize
            continue
        }
        var improve = 0.0f64
        var split = 0.0f64
        var dir = 0i64
        if t.method == 1usize {
            let (im, sp, dr) = rp_choose_anova(t, v, k, nc, myrisk)
            improve = im
            split = sp
            dir = dr
        } else if t.method == 2usize {
            let (im, sp, dr) = rp_choose_poisson(t, v, k, nc, myrisk)
            improve = im
            split = sp
            dir = dr
        } else {
            let (im, sp, dr) = rp_choose_gini(t, v, k, nc, myrisk)
            improve = im
            split = sp
            dir = dr
        }
        if improve > t.iscale { t.iscale = improve }
        if improve > t.iscale * 1.0e-10f64 {
            improve = improve / t.cost[v]
            let slot = rp_cand_slot(t, improve, t.maxpri)
            if slot != NONE {
                t.cvar[slot] = v
                t.cimp[slot] = improve
                t.cspt[slot] = split
                t.ccount[slot] = f64(k)
                t.cadj[slot] = 0.0f64
                if nc == 0usize {
                    t.cdir[slot] = dir
                } else {
                    var c = 0usize
                    while c < nc {
                        t.ccs[slot * t.maxcat + c] = t.cs[c]
                        c += 1usize
                    }
                }
            }
        }
        v += 1usize
    }
    ret t.cn
}

// copies the candidate list into the pool after the splits already there; returns the first index
fn rp_cand_store(t: *Fit) -> usize {
    let first = t.pl.ns
    var i = 0usize
    while i < t.cn {
        let s = t.pl.ns
        t.pl.svar[s] = t.cvar[i]
        t.pl.simp[s] = t.cimp[i]
        t.pl.sspt[s] = t.cspt[i]
        t.pl.sdir[s] = t.cdir[i]
        t.pl.scount[s] = t.ccount[i]
        t.pl.sadj[s] = t.cadj[i]
        var c = 0usize
        while c < t.maxcat {
            t.pl.scs[s * t.maxcat + c] = t.ccs[i * t.maxcat + c]
            c += 1usize
        }
        t.pl.ns += 1usize
        i += 1usize
    }
    ret first
}

// ---- surrogate.c and choose_surg.c

// (agreement, adjusted agreement, split, direction) of predictor col against the primary coded in t.tempy
fn rp_choose_surg(t: *Fit, col: usize, lo: usize, hi: usize, nc: usize, tleft: f64, tright: f64) -> (f64, f64, f64, i64) {
    let xs = t.x[col * t.n..col * t.n + t.n]
    var k = 0usize
    var i = lo
    while i < hi {
        let o = t.idx[i]
        if rp_finite(xs[o]) {
            t.ob[k] = o
            k += 1usize
        }
        i += 1usize
    }
    var agree = 0.0f64
    var majority = 0.0f64
    var total_wt = 0.0f64
    var success = false
    var split = 0.0f64
    var dir = 0i64 - 1i64
    if nc == 0usize {
        if k > 1usize { rp_sort_ob(t, col, k) }
        var lastx = 0.0f64
        var ll = 0i64
        var rl = 0i64
        var llwt = 0.0f64
        var rlwt = 0.0f64
        i = k
        while i > 0usize {
            i -= 1usize
            let o = t.ob[i]
            lastx = xs[o]
            let yy = t.tempy[o]
            if yy == 0i64 - 1i64 {
                if t.wt[o] > 0.0f64 { ll += 1i64 }
                llwt += t.wt[o]
            } else if yy == 1i64 {
                if t.wt[o] > 0.0f64 { rl += 1i64 }
                rlwt += t.wt[o]
            }
        }
        if llwt > rlwt { agree = llwt } else { agree = rlwt }
        majority = agree
        total_wt = llwt + rlwt
        var lr = 0i64
        var rr = 0i64
        var lrwt = 0.0f64
        var rrwt = 0.0f64
        dir = 0i64 - 1i64
        split = lastx
        i = 0usize
        while ll + rl >= 2i64 && i < k {
            let o = t.ob[i]
            if lr + rr >= 2i64 && xs[o] != lastx {
                if llwt + rrwt > agree {
                    success = true
                    agree = llwt + rrwt
                    dir = 1i64
                    split = (xs[o] + lastx) / 2.0f64
                } else if lrwt + rlwt > agree {
                    success = true
                    agree = lrwt + rlwt
                    dir = 0i64 - 1i64
                    split = (xs[o] + lastx) / 2.0f64
                }
            }
            let yy = t.tempy[o]
            if yy == 0i64 - 1i64 {
                if t.wt[o] > 0.0f64 {
                    ll -= 1i64
                    lr += 1i64
                }
                llwt -= t.wt[o]
                lrwt += t.wt[o]
            } else if yy == 1i64 {
                if t.wt[o] > 0.0f64 {
                    rl -= 1i64
                    rr += 1i64
                }
                rlwt -= t.wt[o]
                rrwt += t.wt[o]
            }
            lastx = xs[o]
            i += 1usize
        }
    } else {
        var lcount = 0i64
        var rcount = 0i64
        var c = 0usize
        while c < nc {
            t.cl[c] = 0i64
            t.cr[c] = 0i64
            t.lwt[c] = 0.0f64
            t.rwt[c] = 0.0f64
            c += 1usize
        }
        i = 0usize
        while i < k {
            let o = t.ob[i]
            let kk = usize(xs[o]) - 1usize
            let yy = t.tempy[o]
            if yy == 0i64 - 1i64 {
                if t.wt[o] > 0.0f64 { t.cl[kk] += 1i64 }
                t.lwt[kk] += t.wt[o]
            } else if yy == 1i64 {
                if t.wt[o] > 0.0f64 { t.cr[kk] += 1i64 }
                t.rwt[kk] += t.wt[o]
            }
            i += 1usize
        }
        var llwt = 0.0f64
        var rrwt = 0.0f64
        c = 0usize
        while c < nc {
            llwt += t.lwt[c]
            rrwt += t.rwt[c]
            c += 1usize
        }
        var defdir = 1i64
        if llwt > rrwt {
            defdir = 0i64 - 1i64
            majority = llwt
        } else {
            majority = rrwt
        }
        total_wt = llwt + rrwt
        agree = 0.0f64
        c = 0usize
        while c < nc {
            if t.cl[c] == 0i64 && t.cr[c] == 0i64 {
                t.cs[c] = 0i64
            } else if t.lwt[c] < t.rwt[c] || (t.lwt[c] == t.rwt[c] && defdir == 1i64) {
                agree += t.rwt[c]
                t.cs[c] = 1i64
                lcount += t.cl[c]
                rcount += t.cr[c]
            } else {
                agree += t.lwt[c]
                t.cs[c] = 0i64 - 1i64
                lcount += t.cr[c]
                rcount += t.cl[c]
            }
            c += 1usize
        }
        success = lcount > 1i64 && rcount > 1i64
    }
    if !success { ret (0.0f64, 0.0f64, split, dir) }
    if t.suragree == 0usize {
        total_wt = tleft + tright
        if tleft > tright { majority = tleft } else { majority = tright }
    }
    let agreement = agree / total_wt
    majority = majority / total_wt
    let adj = (agreement - majority) / (1.0f64 - majority)
    ret (agreement, adj, split, dir)
}

fn rp_surrogate(t: *Fit, node: usize, lo: usize, hi: usize) {
    let p0 = t.pl.pstart[node]
    let pvar = t.pl.svar[p0]
    let xp = t.x[pvar * t.n..pvar * t.n + t.n]
    var i = lo
    while i < hi {
        let o = t.idx[i]
        if !rp_finite(xp[o]) {
            t.tempy[o] = 0i64
        } else if t.ncat[pvar] == 0usize {
            var d = t.pl.sdir[p0]
            if !(xp[o] < t.pl.sspt[p0]) { d = 0i64 - d }
            t.tempy[o] = d
        } else {
            t.tempy[o] = t.pl.scs[p0 * t.maxcat + usize(xp[o]) - 1usize]
        }
        i += 1usize
    }
    var lcount = 0.0f64
    var rcount = 0.0f64
    i = lo
    while i < hi {
        let o = t.idx[i]
        if t.tempy[o] == 0i64 - 1i64 {
            lcount += t.wt[o]
        } else if t.tempy[o] == 1i64 {
            rcount += t.wt[o]
        }
        i += 1usize
    }
    if lcount < rcount {
        t.pl.lastsur[node] = 1i64
    } else if lcount > rcount {
        t.pl.lastsur[node] = 0i64 - 1i64
    } else {
        t.pl.lastsur[node] = 0i64
    }
    t.cn = 0usize
    var v = 0usize
    while v < t.p {
        if v == pvar {
            v += 1usize
            continue
        }
        let nc = t.ncat[v]
        let (improve, adj, split, dir) = rp_choose_surg(t, v, lo, hi, nc, lcount, rcount)
        if adj <= 1.0e-10f64 {
            v += 1usize
            continue
        }
        let slot = rp_cand_slot(t, improve, t.maxsur)
        if slot != NONE {
            t.cvar[slot] = v
            t.cimp[slot] = improve
            t.cspt[slot] = split
            t.ccount[slot] = 0.0f64
            t.cadj[slot] = adj
            if nc == 0usize {
                t.cdir[slot] = dir
            } else {
                var c = 0usize
                while c < nc {
                    t.ccs[slot * t.maxcat + c] = t.cs[c]
                    c += 1usize
                }
            }
        }
        v += 1usize
    }
    t.pl.nsur[node] = t.cn
    let _ = rp_cand_store(t)
}

// ---- nodesplit.c: assigns the node's observations to its two children and regroups idx[lo..hi] as left, right, stays
fn rp_nodesplit(t: *Fit, node: usize, nodenum: i64, lo: usize, hi: usize) -> (usize, usize) {
    let leftson = 2i64 * nodenum
    let rightson = leftson + 1i64
    let p0 = t.pl.pstart[node]
    let pvar = t.pl.svar[p0]
    let xp = t.x[pvar * t.n..pvar * t.n + t.n]
    var someleft = 0usize
    var i = lo
    while i < hi {
        let j = t.idx[i]
        let v = xp[j]
        if !rp_finite(v) {
            someleft += 1usize
        } else if t.ncat[pvar] > 0usize {
            let d = t.pl.scs[p0 * t.maxcat + usize(v) - 1usize]
            if d == 0i64 - 1i64 {
                t.which[j] = leftson
            } else if d == 1i64 {
                t.which[j] = rightson
            }
        } else {
            var d = t.pl.sdir[p0]
            if !(v < t.pl.sspt[p0]) { d = 0i64 - d }
            if d == 0i64 - 1i64 { t.which[j] = leftson } else { t.which[j] = rightson }
        }
        i += 1usize
    }
    let npri = t.pl.npri[node]
    let nsur = t.pl.nsur[node]
    if someleft > 0usize && t.usesur > 0usize {
        i = lo
        while i < hi {
            let j = t.idx[i]
            if rp_finite(xp[j]) {
                i += 1usize
                continue
            }
            var s = 0usize
            while s < nsur {
                let si = p0 + npri + s
                let sv = t.pl.svar[si]
                let xv = t.x[sv * t.n + j]
                if !rp_finite(xv) {
                    s += 1usize
                    continue
                }
                if t.ncat[sv] > 0usize {
                    let d = t.pl.scs[si * t.maxcat + usize(xv) - 1usize]
                    if d != 0i64 {
                        t.pl.scount[si] += 1.0f64
                        if d == 0i64 - 1i64 { t.which[j] = leftson } else { t.which[j] = rightson }
                        someleft -= 1usize
                        break
                    }
                } else {
                    t.pl.scount[si] += 1.0f64
                    var d = t.pl.sdir[si]
                    if !(xv < t.pl.sspt[si]) { d = 0i64 - d }
                    if d == 0i64 - 1i64 { t.which[j] = leftson } else { t.which[j] = rightson }
                    someleft -= 1usize
                    break
                }
                s += 1usize
            }
            i += 1usize
        }
    }
    if someleft > 0usize && t.usesur == 2usize {
        let ls = t.pl.lastsur[node]
        if ls != 0i64 {
            var side = rightson
            if ls < 0i64 { side = leftson }
            i = lo
            while i < hi {
                let j = t.idx[i]
                if !rp_finite(xp[j]) && t.which[j] == nodenum { t.which[j] = side }
                i += 1usize
            }
        }
    }
    var nleft = 0usize
    var nright = 0usize
    i = lo
    while i < hi {
        let j = t.idx[i]
        if t.which[j] == leftson { nleft += 1usize } else if t.which[j] == rightson { nright += 1usize }
        i += 1usize
    }
    var i1 = lo
    var i2 = lo + nleft
    var i3 = i2 + nright
    i = lo
    while i < hi {
        let j = t.idx[i]
        if t.which[j] == leftson {
            t.idx[i1] = j
            i1 += 1usize
        } else if t.which[j] == rightson {
            t.tmpv[i2] = j
            i2 += 1usize
        } else {
            t.tmpv[i3] = j
            i3 += 1usize
        }
        i += 1usize
    }
    i = lo + nleft
    while i < hi {
        t.idx[i] = t.tmpv[i]
        i += 1usize
    }
    ret (nleft, nright)
}

fn rp_new_node(t: *Fit) -> usize {
    let i = t.pl.nn
    t.pl.nn += 1usize
    t.pl.lc[i] = NONE
    t.pl.rc[i] = NONE
    t.pl.npri[i] = 0usize
    t.pl.nsur[i] = 0usize
    t.pl.cplx[i] = 0.0f64
    t.pl.risk[i] = 0.0f64
    t.pl.pstart[i] = 0usize
    t.pl.lastsur[i] = 0i64
    ret i
}

fn rp_make_leaf(t: *Fit, node: usize) {
    t.pl.cplx[node] = t.alpha
    t.pl.lc[node] = NONE
    t.pl.rc[node] = NONE
    t.pl.npri[node] = 0usize
    t.pl.nsur[node] = 0usize
}

// partition.c: grows the node and returns (the number of splits kept below it, the risk of the kept subtree)
fn rp_partition(t: *Fit, node: usize, nodenum: i64, lo: usize, hi: usize) -> (usize, f64) {
    let n = hi - lo
    var tempcp = 0.0f64
    t.pl.nid[node] = nodenum
    if nodenum > 1i64 {
        var twt = 0.0f64
        var i = lo
        while i < hi {
            twt += t.wt[t.idx[i]]
            i += 1usize
        }
        t.pl.risk[node] = rp_eval(t, node, lo, hi)
        t.pl.nobs[node] = n
        t.pl.wsum[node] = twt
        tempcp = t.pl.risk[node]
        if tempcp > t.pl.cplx[node] { tempcp = t.pl.cplx[node] }
    } else {
        tempcp = t.pl.risk[node]
    }
    if n < t.minsplit || tempcp <= t.alpha || nodenum > t.maxnode || t.pl.nn + 2usize > t.pl.cap {
        rp_make_leaf(t, node)
        ret (0usize, t.pl.risk[node])
    }
    let nprim = rp_bsplit(t, node, lo, hi)
    if nprim == 0usize || t.pl.ns + nprim + t.maxsur > t.pl.scap {
        rp_make_leaf(t, node)
        ret (0usize, t.pl.risk[node])
    }
    t.pl.pstart[node] = rp_cand_store(t)
    t.pl.npri[node] = nprim
    t.pl.nsur[node] = 0usize
    if t.maxsur > 0usize { rp_surrogate(t, node, lo, hi) }
    let (nleft, nright) = rp_nodesplit(t, node, nodenum, lo, hi)
    let ln = rp_new_node(t)
    t.pl.lc[node] = ln
    t.pl.cplx[ln] = tempcp - t.alpha
    let (ls0, lr0) = rp_partition(t, ln, 2i64 * nodenum, lo, lo + nleft)
    var left_split = ls0
    var left_risk = lr0
    tempcp = (t.pl.risk[node] - left_risk) / f64(left_split + 1usize)
    let tempcp2 = t.pl.risk[node] - t.pl.risk[ln]
    if tempcp < tempcp2 { tempcp = tempcp2 }
    if tempcp > t.pl.cplx[node] { tempcp = t.pl.cplx[node] }
    let rn = rp_new_node(t)
    t.pl.rc[node] = rn
    t.pl.cplx[rn] = tempcp - t.alpha
    let (rs0, rr0) = rp_partition(t, rn, 1i64 + 2i64 * nodenum, lo + nleft, lo + nleft + nright)
    var right_split = rs0
    var right_risk = rr0
    tempcp = (t.pl.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
    if t.pl.cplx[rn] > t.pl.cplx[ln] {
        if tempcp > t.pl.cplx[ln] {
            left_risk = t.pl.risk[ln]
            left_split = 0usize
            tempcp = (t.pl.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
            if tempcp > t.pl.cplx[rn] {
                right_risk = t.pl.risk[rn]
                right_split = 0usize
            }
        }
    } else if tempcp > t.pl.cplx[rn] {
        right_split = 0usize
        right_risk = t.pl.risk[rn]
        tempcp = (t.pl.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
        if tempcp > t.pl.cplx[ln] {
            left_risk = t.pl.risk[ln]
            left_split = 0usize
        }
    }
    t.pl.cplx[node] = (t.pl.risk[node] - (left_risk + right_risk)) / f64(left_split + right_split + 1usize)
    if t.pl.cplx[node] <= t.alpha {
        t.pl.lc[node] = NONE
        t.pl.rc[node] = NONE
        t.pl.npri[node] = 0usize
        t.pl.nsur[node] = 0usize
        var i = lo
        while i < hi {
            t.which[t.idx[i]] = nodenum
            i += 1usize
        }
        ret (0usize, t.pl.risk[node])
    }
    ret (left_split + right_split + 1usize, left_risk + right_risk)
}

// ---- the cp list (make_cp_list.c, make_cp_table.c, fix_cp.c)

fn rp_cp_list(t: *Fit, node: usize, parent: f64) {
    if t.pl.cplx[node] > parent { t.pl.cplx[node] = parent }
    var me_cp = t.pl.cplx[node]
    if me_cp < t.alpha { me_cp = t.alpha }
    if t.pl.lc[node] != NONE {
        rp_cp_list(t, t.pl.lc[node], me_cp)
        rp_cp_list(t, t.pl.rc[node], me_cp)
    }
    if me_cp < parent {
        var after = 0usize
        var i = 0usize
        while i < t.ncp {
            if me_cp == t.cpcp[i] { ret }
            if me_cp > t.cpcp[i] { break }
            after = i + 1usize
            i += 1usize
        }
        var j = t.ncp
        while j > after {
            t.cpcp[j] = t.cpcp[j - 1usize]
            j -= 1usize
        }
        t.cpcp[after] = me_cp
        t.ncp += 1usize
    }
}

fn rp_cp_table(t: *Fit, node: usize, parent: f64, nsplit: f64) -> i64 {
    var at = 0i64
    if t.pl.lc[node] != NONE {
        let dummy = rp_cp_table(t, t.pl.lc[node], t.pl.cplx[node], 0.0f64)
        let _ = dummy
        at = rp_cp_table(t, t.pl.rc[node], t.pl.cplx[node], nsplit + 1.0f64)
    } else {
        at = i64(t.ncp) - 1i64
    }
    while at >= 0i64 && t.cpcp[usize(at)] < parent {
        t.cprisk[usize(at)] += t.pl.risk[node]
        t.cpnsplit[usize(at)] += nsplit
        at -= 1i64
    }
    ret at
}

fn rp_fix_cp(t: *Fit, node: usize, parent: f64) {
    if t.pl.cplx[node] > parent { t.pl.cplx[node] = parent }
    if t.pl.lc[node] != NONE {
        rp_fix_cp(t, t.pl.lc[node], t.pl.cplx[node])
        rp_fix_cp(t, t.pl.rc[node], t.pl.cplx[node])
    }
}

// ---- branch.c and rundown.c: the child an observation takes, NONE when it cannot decide
fn rp_branch(t: *Fit, node: usize, o: usize) -> usize {
    if t.pl.lc[node] == NONE { ret NONE }
    let p0 = t.pl.pstart[node]
    var dir = 0i64
    var done = false
    let v = t.pl.svar[p0]
    let xv = t.x[v * t.n + o]
    if rp_finite(xv) {
        if t.ncat[v] == 0usize {
            dir = t.pl.sdir[p0]
            if !(xv < t.pl.sspt[p0]) { dir = 0i64 - dir }
            done = true
        } else {
            dir = t.pl.scs[p0 * t.maxcat + usize(xv) - 1usize]
            if dir != 0i64 { done = true }
        }
    }
    if !done {
        if t.usesur == 0usize { ret NONE }
        let np = t.pl.npri[node]
        var s = 0usize
        while s < t.pl.nsur[node] && !done {
            let si = p0 + np + s
            let sv = t.pl.svar[si]
            let sx = t.x[sv * t.n + o]
            if rp_finite(sx) {
                if t.ncat[sv] == 0usize {
                    dir = t.pl.sdir[si]
                    if !(sx < t.pl.sspt[si]) { dir = 0i64 - dir }
                    done = true
                } else {
                    dir = t.pl.scs[si * t.maxcat + usize(sx) - 1usize]
                    if dir != 0i64 { done = true }
                }
            }
            s += 1usize
        }
        if !done {
            if t.usesur < 2usize { ret NONE }
            dir = t.pl.lastsur[node]
        }
    }
    if dir == 0i64 - 1i64 { ret t.pl.lc[node] }
    ret t.pl.rc[node]
}

// an observation that cannot descend (a missing value with no surrogate to use) leaves the rest of xtemp as the previous observation left it, as rpart does
fn rp_rundown(t: *Fit, o: usize, cp: []const f64, xtemp: []f64) {
    var node = 0usize
    var otree = 0usize
    var i = 0usize
    while i < t.ncp {
        while cp[i] < t.pl.cplx[node] {
            let nx = rp_branch(t, node, o)
            if nx == NONE { ret }
            node = nx
            otree = nx
        }
        xtemp[i] = rp_error(t, o, t.pl.resp[node * t.nresp])
        i += 1usize
    }
    let _ = otree
}

// ---- the pool and the fit

fn rp_pool(a: *mem.Arena, cap: usize, scap: usize, nresp: usize, maxcat: usize) -> (Pool, err) {
    var q: Pool = zero
    q.cap = cap
    q.scap = scap
    let sc = scap * (maxcat + 1usize)
    let (nid, e1) = mem.alloc[i64](a, cap)
    let (risk, e2) = mem.alloc[f64](a, cap)
    let (cplx, e3) = mem.alloc[f64](a, cap)
    let (wsum, e4) = mem.alloc[f64](a, cap)
    let (nobs, e5) = mem.alloc[usize](a, cap)
    let (resp, e6) = mem.alloc[f64](a, cap * nresp)
    let (lc, e7) = mem.alloc[usize](a, cap)
    let (rc, e8) = mem.alloc[usize](a, cap)
    let (pstart, e9) = mem.alloc[usize](a, cap)
    let (npri, e10) = mem.alloc[usize](a, cap)
    let (nsur, e11) = mem.alloc[usize](a, cap)
    let (lastsur, e12) = mem.alloc[i64](a, cap)
    let (svar, e13) = mem.alloc[usize](a, scap)
    let (simp, e14) = mem.alloc[f64](a, scap)
    let (sspt, e15) = mem.alloc[f64](a, scap)
    let (sdir, e16) = mem.alloc[i64](a, scap)
    let (scount, e17) = mem.alloc[f64](a, scap)
    let (sadj, e18) = mem.alloc[f64](a, scap)
    let (scs, e19) = mem.alloc[i64](a, sc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (q, mem.Full) }
    if e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret (q, mem.Full) }
    q.nid = nid
    q.risk = risk
    q.cplx = cplx
    q.wsum = wsum
    q.nobs = nobs
    q.resp = resp
    q.lc = lc
    q.rc = rc
    q.pstart = pstart
    q.npri = npri
    q.nsur = nsur
    q.lastsur = lastsur
    q.svar = svar
    q.simp = simp
    q.sspt = sspt
    q.sdir = sdir
    q.scount = scount
    q.sadj = sadj
    q.scs = scs
    ret (q, ok)
}

// survival times rescaled to a Poisson problem (rpart.exp): y holds (time, status) rows; the answer holds (rescaled time, status) rows
fn rp_exp_y(a: *mem.Arena, y: []const f64, n: usize) -> ([]f64, err) {
    var none: []f64 = zero
    let (newy, e0) = mem.alloc[f64](a, n * 2usize)
    let (dt, e1) = mem.alloc[f64](a, n + 1usize)
    let (itable, e2) = mem.alloc[f64](a, n + 3usize)
    let (cumhaz, e3) = mem.alloc[f64](a, n + 3usize)
    let (pyears, e4) = mem.alloc[f64](a, n + 3usize)
    let (deaths, e5) = mem.alloc[f64](a, n + 3usize)
    let (cntg, e6) = mem.alloc[f64](a, n + 3usize)
    let (index, e7) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (none, mem.Full) }
    var m = 0usize
    var tmax = 0.0f64
    var i = 0usize
    while i < n {
        if y[i * 2usize] > tmax { tmax = y[i * 2usize] }
        if y[i * 2usize + 1usize] == 1.0f64 {
            let tv = y[i * 2usize]
            var q = m
            while q > 0usize && dt[q - 1usize] > tv {
                dt[q] = dt[q - 1usize]
                q -= 1usize
            }
            dt[q] = tv
            m += 1usize
        }
        i += 1usize
    }
    if m == 0usize { ret (none, BadSpec) }
    var u = 0usize
    i = 0usize
    while i < m {
        if i == 0usize || dt[i] != dt[i - 1usize] {
            dt[u] = dt[i]
            u += 1usize
        }
        i += 1usize
    }
    m = u
    // rpartexp2: drop death times closer than eps * the interquartile range to the last one kept
    let eps = 2.220446049250313e-16f64
    let delta = eps * (dt[(3usize * m) / 4usize] - dt[m / 4usize])
    var lasty = dt[0usize]
    var kept = 1usize
    i = 1usize
    while i < m {
        if dt[i] - lasty > delta {
            dt[kept] = dt[i]
            kept += 1usize
            lasty = dt[i]
        }
        i += 1usize
    }
    m = kept
    itable[0usize] = 0.0f64
    i = 0usize
    while i + 1usize < m {
        itable[i + 1usize] = dt[i]
        i += 1usize
    }
    itable[m] = tmax
    let ng = m
    i = 0usize
    while i < ng {
        pyears[i] = 0.0f64
        deaths[i] = 0.0f64
        cntg[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let tv = y[i * 2usize]
        var g = 0usize
        while g + 1usize < ng && tv > itable[g + 1usize] { g += 1usize }
        index[i] = g
        cntg[g] += 1.0f64
        pyears[g] += tv - itable[g]
        deaths[g] += y[i * 2usize + 1usize]
        i += 1usize
    }
    var above = 0.0f64
    var g = ng
    while g > 0usize {
        g -= 1usize
        pyears[g] += (itable[g + 1usize] - itable[g]) * above
        above += cntg[g]
    }
    cumhaz[0usize] = 0.0f64
    g = 0usize
    while g < ng {
        cumhaz[g + 1usize] = cumhaz[g] + (deaths[g] / pyears[g]) * (itable[g + 1usize] - itable[g])
        g += 1usize
    }
    i = 0usize
    while i < n {
        let tv = y[i * 2usize]
        let gg = index[i]
        newy[i * 2usize] = cumhaz[gg] + (tv - itable[gg]) * ((cumhaz[gg + 1usize] - cumhaz[gg]) / (itable[gg + 1usize] - itable[gg]))
        if tv == itable[gg + 1usize] { newy[i * 2usize] = cumhaz[gg + 1usize] }
        newy[i * 2usize + 1usize] = y[i * 2usize + 1usize]
        i += 1usize
    }
    ret (newy, ok)
}

fn rp_xval(a: *mem.Arena, t: *Fit, xg: []const usize, nx: usize) -> err {
    let mk = mem.mark(a)
    let n = t.n
    let (xpool, ep) = rp_pool(a, t.pl.cap, t.pl.scap, t.nresp, t.maxcat)
    let (cp, e1) = mem.alloc[f64](a, t.ncp + 1usize)
    let (xtemp, e2) = mem.alloc[f64](a, t.ncp + 1usize)
    let (savew, e3) = mem.alloc[i64](a, n)
    let (leftout, e4) = mem.alloc[usize](a, n)
    if ep != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < t.ncp {
        xtemp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        savew[i] = t.which[i]
        i += 1usize
    }
    let alphasave = t.alpha
    cp[0usize] = 10.0f64 * t.cpcp[0usize]
    i = 1usize
    while i < t.ncp {
        cp[i] = math.sqrt[f64](t.cpcp[i - 1usize] * t.cpcp[i])
        i += 1usize
    }
    var total_wt = 0.0f64
    i = 0usize
    while i < n {
        total_wt += t.wt[i]
        i += 1usize
    }
    var old_wt = total_wt
    let saved = t.pl
    t.pl = xpool
    var g = 0usize
    while g < nx {
        var k = 0usize
        var nl = 0usize
        var temp = 0.0f64
        i = 0usize
        while i < n {
            t.which[i] = 1i64
            if xg[i] == g + 1usize {
                leftout[nl] = i
                nl += 1usize
            } else {
                t.idx[k] = i
                temp += t.wt[i]
                k += 1usize
            }
            i += 1usize
        }
        var j = 0usize
        while j < t.ncp {
            cp[j] = cp[j] * (temp / old_wt)
            j += 1usize
        }
        t.alpha = t.alpha * (temp / old_wt)
        old_wt = temp
        t.pl.nn = 1usize
        t.pl.ns = 0usize
        t.pl.nid[0usize] = 1i64
        t.pl.lc[0usize] = NONE
        t.pl.rc[0usize] = NONE
        t.pl.npri[0usize] = 0usize
        t.pl.nsur[0usize] = 0usize
        t.pl.nobs[0usize] = k
        if t.method == 2usize { rp_pinit(t, 0usize, k) }
        t.pl.risk[0usize] = rp_eval(t, 0usize, 0usize, k)
        t.pl.cplx[0usize] = t.pl.risk[0usize]
        let (s0, r0) = rp_partition(t, 0usize, 1i64, 0usize, k)
        let _ = s0
        let _ = r0
        rp_fix_cp(t, 0usize, t.pl.cplx[0usize])
        i = 0usize
        while i < nl {
            let o = leftout[i]
            rp_rundown(t, o, cp, xtemp)
            j = 0usize
            while j < t.ncp {
                t.cpx[j] += xtemp[j] * t.wt[o]
                t.cpxs[j] += xtemp[j] * xtemp[j] * t.wt[o]
                j += 1usize
            }
            i += 1usize
        }
        g += 1usize
    }
    i = 0usize
    while i < t.ncp {
        t.cpxs[i] = math.sqrt[f64](t.cpxs[i] - t.cpx[i] * t.cpx[i] / total_wt)
        i += 1usize
    }
    t.pl = saved
    t.alpha = alphasave
    i = 0usize
    while i < n {
        t.which[i] = savew[i]
        i += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

// rpart() for numeric y (anova), (time, events) rows (poisson), (time, status) rows (exp), or class codes 1 .. k (class). x is n by p, column-major, NaN
// missing, factors as codes 1 .. ncat[j]. parms: class prior (k), loss (k*k, column-major), split (1 gini, 2 information); poisson and exp shrink, method (1 deviance,
// 2 sqrt); a NaN entry, or an empty parms, takes rpart's default. xg: the fold of each row, empty for none.
fn rp_fit(a: *mem.Arena, x: []const f64, n: usize, p: usize, ncat: []const usize, y0: []const f64, ny0: usize, wt: []const f64, cost: []const f64, method0: usize, k: usize, parms: []const f64, ctl: Control, xg: []const usize) -> (Fit, err) {
    var t: Fit = zero
    t.n = n
    t.p = p
    t.x = x
    t.wt = wt
    t.ncat = ncat
    t.cost = cost
    t.ctl = ctl
    t.k = k
    t.y = y0
    t.ny = ny0
    t.method = method0
    if method0 == 4usize {
        let (ey, ee) = rp_exp_y(a, y0, n)
        if ee != ok { ret (t, ee) }
        t.y = ey
        t.ny = 2usize
        t.method = 2usize
    }
    var maxcat = 0usize
    var v = 0usize
    while v < p {
        if ncat[v] > maxcat { maxcat = ncat[v] }
        v += 1usize
    }
    t.maxcat = maxcat
    t.minsplit = usize(ctl.minsplit)
    t.minbucket = usize(ctl.minbucket)
    t.cp = ctl.cp
    t.maxpri = usize(ctl.maxcompete) + 1usize
    t.maxsur = usize(ctl.maxsurrogate)
    t.usesur = usize(ctl.usesurrogate)
    t.suragree = usize(ctl.surrogatestyle)
    var mn = 1i64
    var d = 0usize
    while d < usize(ctl.maxdepth) {
        mn = mn * 2i64
        d += 1usize
    }
    t.maxnode = mn - 1i64
    var kk = k
    if t.method != 3usize { kk = 1usize }
    t.nresp = 1usize
    if t.method == 2usize { t.nresp = 2usize }
    if t.method == 3usize { t.nresp = k + 2usize }
    let cap = 2usize * n + 8usize
    let m = t.maxpri + t.maxsur + 2usize
    let scap = (n + 4usize) * (t.maxpri + t.maxsur) + 8usize
    let (pool, ep) = rp_pool(a, cap, scap, t.nresp, maxcat)
    let (ob, a1) = mem.alloc[usize](a, n + 2usize)
    let (ob2, a2) = mem.alloc[usize](a, n + 2usize)
    let (idx, a3) = mem.alloc[usize](a, n + 2usize)
    let (tmpv, a4) = mem.alloc[usize](a, n + 2usize)
    let (which, a5) = mem.alloc[i64](a, n + 2usize)
    let (tempy, a6) = mem.alloc[i64](a, n + 2usize)
    let mc = maxcat + 2usize
    let (cs, b1) = mem.alloc[i64](a, mc)
    let (cl, b2) = mem.alloc[i64](a, mc)
    let (cr, b3) = mem.alloc[i64](a, mc)
    let (lwt, b4) = mem.alloc[f64](a, mc)
    let (rwt, b5) = mem.alloc[f64](a, mc)
    let (gray, b6) = mem.alloc[i64](a, mc)
    let (cnt, b7) = mem.alloc[i64](a, mc)
    let (tsp, b8) = mem.alloc[i64](a, mc)
    let (sumv, b9) = mem.alloc[f64](a, mc)
    let (wtv, b10) = mem.alloc[f64](a, mc)
    let (meanv, b11) = mem.alloc[f64](a, mc)
    let (rate, b12) = mem.alloc[f64](a, mc)
    let (death, b13) = mem.alloc[f64](a, mc)
    let (ord1, b14) = mem.alloc[i64](a, mc)
    let (ord2, b15) = mem.alloc[i64](a, mc)
    let (ccnt, b16) = mem.alloc[f64](a, kk * mc)
    let (lcnt, b17) = mem.alloc[f64](a, kk + 1usize)
    let (rcnt, b18) = mem.alloc[f64](a, kk + 1usize)
    let (cvar, c1) = mem.alloc[usize](a, m)
    let (cimp, c2) = mem.alloc[f64](a, m)
    let (cspt, c3) = mem.alloc[f64](a, m)
    let (cdir, c4) = mem.alloc[i64](a, m)
    let (ccount, c5) = mem.alloc[f64](a, m)
    let (cadj, c6) = mem.alloc[f64](a, m)
    let (ccs, c7) = mem.alloc[i64](a, m * mc)
    let (prior, d1) = mem.alloc[f64](a, kk + 1usize)
    let (uprior, d2) = mem.alloc[f64](a, kk + 1usize)
    let (aprior, d3) = mem.alloc[f64](a, kk + 1usize)
    let (lossa, d4) = mem.alloc[f64](a, kk * kk + 1usize)
    let (freqv, d5) = mem.alloc[f64](a, kk + 1usize)
    let (counts, d6) = mem.alloc[f64](a, kk + 1usize)
    let (cpcp, f1) = mem.alloc[f64](a, cap + 2usize)
    let (cprisk, f2) = mem.alloc[f64](a, cap + 2usize)
    let (cpnsplit, f3) = mem.alloc[f64](a, cap + 2usize)
    let (cpx, f4) = mem.alloc[f64](a, cap + 2usize)
    let (cpxs, f5) = mem.alloc[f64](a, cap + 2usize)
    if ep != ok || a1 != ok || a2 != ok || a3 != ok || a4 != ok || a5 != ok || a6 != ok { ret (t, mem.Full) }
    if b1 != ok || b2 != ok || b3 != ok || b4 != ok || b5 != ok || b6 != ok || b7 != ok || b8 != ok || b9 != ok { ret (t, mem.Full) }
    if b10 != ok || b11 != ok || b12 != ok || b13 != ok || b14 != ok || b15 != ok || b16 != ok || b17 != ok || b18 != ok { ret (t, mem.Full) }
    if c1 != ok || c2 != ok || c3 != ok || c4 != ok || c5 != ok || c6 != ok || c7 != ok { ret (t, mem.Full) }
    if d1 != ok || d2 != ok || d3 != ok || d4 != ok || d5 != ok || d6 != ok { ret (t, mem.Full) }
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok { ret (t, mem.Full) }
    t.pl = pool
    t.ob = ob
    t.ob2 = ob2
    t.idx = idx
    t.tmpv = tmpv
    t.which = which
    t.tempy = tempy
    t.cs = cs
    t.cl = cl
    t.cr = cr
    t.lwt = lwt
    t.rwt = rwt
    t.gray = gray
    t.cnt = cnt
    t.tsp = tsp
    t.sumv = sumv
    t.wtv = wtv
    t.meanv = meanv
    t.rate = rate
    t.death = death
    t.ord1 = ord1
    t.ord2 = ord2
    t.ccnt = ccnt
    t.lcnt = lcnt
    t.rcnt = rcnt
    t.cvar = cvar
    t.cimp = cimp
    t.cspt = cspt
    t.cdir = cdir
    t.ccount = ccount
    t.cadj = cadj
    t.ccs = ccs
    t.prior = prior
    t.uprior = uprior
    t.aprior = aprior
    t.lossa = lossa
    t.freqv = freqv
    t.counts = counts
    t.cpcp = cpcp
    t.cprisk = cprisk
    t.cpnsplit = cpnsplit
    t.cpx = cpx
    t.cpxs = cpxs
    var i = 0usize
    while i < n {
        idx[i] = i
        which[i] = 1i64
        i += 1usize
    }
    i = 0usize
    while i < cap + 2usize {
        cpcp[i] = 0.0f64
        cprisk[i] = 0.0f64
        cpnsplit[i] = 0.0f64
        cpx[i] = 0.0f64
        cpxs[i] = 0.0f64
        i += 1usize
    }
    var twt = 0.0f64
    i = 0usize
    while i < n {
        twt += wt[i]
        i += 1usize
    }
    t.totwt = twt
    if t.method == 2usize {
        t.shrink = 1.0f64
        t.wpred = 1usize
        if parms.len >= 2usize {
            if parms[1usize] == parms[1usize] { t.wpred = usize(parms[1usize]) }
            t.shrink = f64(2usize - t.wpred)
            if parms[0usize] == parms[0usize] { t.shrink = parms[0usize] }
        }
        rp_pinit(&t, 0usize, n)
    }
    if t.method == 3usize {
        var c = 0usize
        while c < k {
            counts[c] = 0.0f64
            c += 1usize
        }
        i = 0usize
        while i < n {
            counts[usize(t.y[i * t.ny]) - 1usize] += wt[i]
            i += 1usize
        }
        var tot = 0.0f64
        c = 0usize
        while c < k {
            tot += counts[c]
            c += 1usize
        }
        if parms.len >= k && parms[0usize] == parms[0usize] {
            c = 0usize
            while c < k {
                uprior[c] = parms[c]
                c += 1usize
            }
        } else {
            c = 0usize
            while c < k {
                uprior[c] = counts[c] / tot
                c += 1usize
            }
        }
        var lossgiven = false
        if parms.len >= k + k * k && parms[k] == parms[k] { lossgiven = true }
        c = 0usize
        while c < k {
            var j = 0usize
            while j < k {
                var lv = 1.0f64
                if c == j { lv = 0.0f64 }
                if lossgiven { lv = parms[k + c + j * k] }
                lossa[c + j * k] = lv
                j += 1usize
            }
            c += 1usize
        }
        t.info = false
        if parms.len > k + k * k && parms[k + k * k] == 2.0f64 { t.info = true }
        c = 0usize
        while c < k {
            freqv[c] = counts[c] / tot
            c += 1usize
        }
        var temp = 0.0f64
        c = 0usize
        while c < k {
            prior[c] = uprior[c]
            aprior[c] = 0.0f64
            var j = 0usize
            while j < k {
                let kix = k * j + c
                temp += lossa[kix] * prior[c]
                aprior[c] += lossa[kix] * prior[c]
                j += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < k {
            if freqv[c] > 0.0f64 {
                prior[c] = prior[c] / freqv[c]
                aprior[c] = aprior[c] / (temp * freqv[c])
            }
            c += 1usize
        }
    }
    t.pl.nn = 1usize
    t.pl.ns = 0usize
    t.pl.nid[0usize] = 1i64
    t.pl.lc[0usize] = NONE
    t.pl.rc[0usize] = NONE
    t.pl.npri[0usize] = 0usize
    t.pl.nsur[0usize] = 0usize
    t.pl.nobs[0usize] = n
    t.pl.wsum[0usize] = twt
    t.pl.risk[0usize] = rp_eval(&t, 0usize, 0usize, n)
    t.pl.cplx[0usize] = t.pl.risk[0usize]
    t.alpha = t.cp * t.pl.risk[0usize]
    t.rootrisk = t.pl.risk[0usize]
    let (sp0, rk0) = rp_partition(&t, 0usize, 1i64, 0usize, n)
    let _ = sp0
    let _ = rk0
    t.ncp = 1usize
    t.cpcp[0usize] = t.pl.cplx[0usize]
    t.cprisk[0usize] = t.pl.risk[0usize]
    t.cpnsplit[0usize] = 0.0f64
    var nx = usize(ctl.xval)
    if xg.len == 0usize { nx = 0usize }
    t.hasx = nx > 1usize
    if t.pl.lc[0usize] != NONE {
        rp_cp_list(&t, 0usize, t.pl.cplx[0usize])
        let tail = rp_cp_table(&t, 0usize, t.pl.cplx[0usize], 0.0f64)
        let _ = tail
        if nx > 1usize {
            let ex = rp_xval(a, &t, xg, nx)
            if ex != ok { ret (t, ex) }
        }
    }
    ret (t, ok)
}

// ---- the fitted object as R holds it: frame, splits, csplit, where, cptable, variable importance

type View = struct {
    method: usize,
    p: usize,
    k: usize,
    maxcat: usize,
    usesur: usize,
    nfr: usize,
    nsp: usize,
    ncs: usize,
    id: []i64,
    fn_: []usize,
    fwt: []f64,
    fdev: []f64,
    fyval: []f64,
    fcplx: []f64,
    fncomp: []usize,
    fnsur: []usize,
    fvar: []usize,
    fidx: []usize,
    y2w: usize,
    y2: []f64,
    sp_var: []usize,
    sp_count: []f64,
    sp_ncat: []i64,
    sp_imp: []f64,
    sp_index: []f64,
    sp_adj: []f64,
    cs: []i64,
    wh: []usize,
    nobs: usize,
    ncp: usize,
    hasx: bool,
    cp_cp: []f64,
    cp_nsplit: []f64,
    cp_rel: []f64,
    cp_x: []f64,
    cp_xs: []f64,
    nimp: usize,
    imp_var: []usize,
    imp_val: []f64,
}

fn rp_leaf(t: *Fit, node: usize) -> bool { ret t.pl.lc[node] == NONE || t.pl.cplx[node] <= t.alpha }

fn rp_count(t: *Fit, node: usize) -> (usize, usize, usize) {
    if rp_leaf(t, node) { ret (1usize, 0usize, 0usize) }
    var ns = t.pl.npri[node] + t.pl.nsur[node]
    var nc = 0usize
    let p0 = t.pl.pstart[node]
    var s = 0usize
    while s < ns {
        if t.ncat[t.pl.svar[p0 + s]] > 0usize { nc += 1usize }
        s += 1usize
    }
    let (n1, s1, c1) = rp_count(t, t.pl.lc[node])
    let (n2, s2, c2) = rp_count(t, t.pl.rc[node])
    ret (1usize + n1 + n2, ns + s1 + s2, nc + c1 + c2)
}

// per-row quantities of the frame, one preorder pass; v.nobs, v.nsp and v.ncs are the running counters here
fn rp_fill(t: *Fit, v: *View, node: usize, id: i64, scale: f64) {
    let r = v.nfr
    v.nfr += 1usize
    v.id[r] = id
    v.fn_[r] = t.pl.nobs[node]
    v.fwt[r] = t.pl.wsum[node]
    v.fdev[r] = t.pl.risk[node]
    v.fyval[r] = t.pl.resp[node * t.nresp]
    v.fcplx[r] = t.pl.cplx[node] * scale
    var c = 0usize
    if t.method == 3usize {
        let k = t.k
        let base = node * t.nresp
        c = 0usize
        while c <= k {
            v.y2[r * v.y2w + c] = t.pl.resp[base + c]
            c += 1usize
        }
        var sm = 0.0f64
        c = 0usize
        while c < k {
            var tot = t.counts[c]
            if tot < 1.0f64 { tot = 1.0f64 }
            v.y2[r * v.y2w + 1usize + k + c] = t.pl.resp[base + 1usize + c] * (t.uprior[c] / tot)
            sm += v.y2[r * v.y2w + 1usize + k + c]
            c += 1usize
        }
        c = 0usize
        while c < k {
            v.y2[r * v.y2w + 1usize + k + c] = v.y2[r * v.y2w + 1usize + k + c] / sm
            c += 1usize
        }
        v.y2[r * v.y2w + 2usize * k + 1usize] = t.pl.resp[base + k + 1usize] / t.totwt
    } else if t.method == 2usize {
        v.y2[r * v.y2w] = t.pl.resp[node * 2usize]
        v.y2[r * v.y2w + 1usize] = t.pl.resp[node * 2usize + 1usize]
    }
    if rp_leaf(t, node) {
        v.fvar[r] = 0usize
        v.fidx[r] = 0usize
        v.fncomp[r] = 0usize
        v.fnsur[r] = 0usize
        ret
    }
    let p0 = t.pl.pstart[node]
    let np = t.pl.npri[node]
    let nsr = t.pl.nsur[node]
    v.fvar[r] = t.pl.svar[p0] + 1usize
    v.fidx[r] = v.nsp + 1usize
    v.fncomp[r] = np - 1usize
    v.fnsur[r] = nsr
    var s = 0usize
    while s < np + nsr {
        let si = p0 + s
        let sv = t.pl.svar[si]
        let row = v.nsp
        v.sp_var[row] = sv + 1usize
        v.sp_count[row] = t.pl.scount[si]
        v.sp_imp[row] = t.pl.simp[si]
        v.sp_adj[row] = 0.0f64
        if s >= np { v.sp_adj[row] = t.pl.sadj[si] }
        if t.ncat[sv] == 0usize {
            v.sp_ncat[row] = t.pl.sdir[si]
            v.sp_index[row] = t.pl.sspt[si]
        } else {
            v.sp_ncat[row] = i64(t.ncat[sv])
            v.sp_index[row] = f64(v.ncs + 1usize)
            var q = 0usize
            while q < t.maxcat {
                v.cs[v.ncs * t.maxcat + q] = 0i64
                if q < t.ncat[sv] { v.cs[v.ncs * t.maxcat + q] = t.pl.scs[si * t.maxcat + q] }
                q += 1usize
            }
            v.ncs += 1usize
        }
        v.nsp += 1usize
        s += 1usize
    }
    rp_fill(t, v, t.pl.lc[node], 2i64 * id, scale)
    rp_fill(t, v, t.pl.rc[node], 2i64 * id + 1i64, scale)
}

// variable importance (importance.R): the improvement of each primary split (times the node deviance for anova), plus adj times that for its surrogates
fn rp_importance(a: *mem.Arena, v: *View) -> err {
    let (acc, e1) = mem.alloc[f64](a, v.p + 1usize)
    let (used, e2) = mem.alloc[bool](a, v.p + 1usize)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i <= v.p {
        acc[i] = 0.0f64
        used[i] = false
        i += 1usize
    }
    var r = 0usize
    while r < v.nfr {
        if v.fvar[r] != 0usize {
            let s0 = v.fidx[r] - 1usize
            var sc = v.sp_imp[s0]
            if v.method == 1usize { sc = sc * v.fdev[r] }
            acc[v.fvar[r] - 1usize] += sc
            used[v.fvar[r] - 1usize] = true
            var q = 0usize
            while q < v.fnsur[r] {
                let si = s0 + 1usize + v.fncomp[r] + q
                acc[v.sp_var[si] - 1usize] += sc * v.sp_adj[si]
                used[v.sp_var[si] - 1usize] = true
                q += 1usize
            }
        }
        r += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < v.p {
        if used[i] { m += 1usize }
        i += 1usize
    }
    let (iv, e3) = mem.alloc[usize](a, m + 1usize)
    let (ival, e4) = mem.alloc[f64](a, m + 1usize)
    if e3 != ok || e4 != ok { ret mem.Full }
    var c = 0usize
    i = 0usize
    while i < v.p {
        if used[i] {
            // insertion into descending order; equal values keep the variable order
            var q = c
            while q > 0usize && ival[q - 1usize] < acc[i] {
                ival[q] = ival[q - 1usize]
                iv[q] = iv[q - 1usize]
                q -= 1usize
            }
            ival[q] = acc[i]
            iv[q] = i + 1usize
            c += 1usize
        }
        i += 1usize
    }
    v.nimp = m
    v.imp_var = iv
    v.imp_val = ival
    ret ok
}

fn rp_view(a: *mem.Arena, t: *Fit) -> (View, err) {
    var v: View = zero
    v.method = t.method
    v.p = t.p
    v.k = 0usize
    if t.method == 3usize { v.k = t.k }
    v.maxcat = t.maxcat
    v.usesur = t.usesur
    v.nobs = t.n
    let (nf, ns, nc) = rp_count(t, 0usize)
    var w = 0usize
    if t.method == 3usize { w = 2usize * t.k + 2usize }
    if t.method == 2usize { w = 2usize }
    v.y2w = w
    let (id, e1) = mem.alloc[i64](a, nf)
    let (fnn, e2) = mem.alloc[usize](a, nf)
    let (fwt, e3) = mem.alloc[f64](a, nf)
    let (fdev, e4) = mem.alloc[f64](a, nf)
    let (fyval, e5) = mem.alloc[f64](a, nf)
    let (fcplx, e6) = mem.alloc[f64](a, nf)
    let (fncomp, e7) = mem.alloc[usize](a, nf)
    let (fnsur, e8) = mem.alloc[usize](a, nf)
    let (fvar, e9) = mem.alloc[usize](a, nf)
    let (fidx, e10) = mem.alloc[usize](a, nf)
    let (y2, e11) = mem.alloc[f64](a, nf * w + 1usize)
    let (spv, e12) = mem.alloc[usize](a, ns + 1usize)
    let (spc, e13) = mem.alloc[f64](a, ns + 1usize)
    let (spn, e14) = mem.alloc[i64](a, ns + 1usize)
    let (spi, e15) = mem.alloc[f64](a, ns + 1usize)
    let (spx, e16) = mem.alloc[f64](a, ns + 1usize)
    let (spa, e17) = mem.alloc[f64](a, ns + 1usize)
    let (cs, e18) = mem.alloc[i64](a, nc * t.maxcat + 1usize)
    let (wh, e19) = mem.alloc[usize](a, t.n)
    let (c1, e20) = mem.alloc[f64](a, t.ncp)
    let (c2, e21) = mem.alloc[f64](a, t.ncp)
    let (c3, e22) = mem.alloc[f64](a, t.ncp)
    let (c4, e23) = mem.alloc[f64](a, t.ncp)
    let (c5, e24) = mem.alloc[f64](a, t.ncp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (v, mem.Full) }
    if e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok { ret (v, mem.Full) }
    v.id = id
    v.fn_ = fnn
    v.fwt = fwt
    v.fdev = fdev
    v.fyval = fyval
    v.fcplx = fcplx
    v.fncomp = fncomp
    v.fnsur = fnsur
    v.fvar = fvar
    v.fidx = fidx
    v.y2 = y2
    v.sp_var = spv
    v.sp_count = spc
    v.sp_ncat = spn
    v.sp_imp = spi
    v.sp_index = spx
    v.sp_adj = spa
    v.cs = cs
    v.wh = wh
    v.nfr = 0usize
    v.nsp = 0usize
    v.ncs = 0usize
    rp_fill(t, &v, 0usize, 1i64, 1.0f64 / t.pl.risk[0usize])
    v.nfr = nf
    v.nsp = ns
    v.ncs = nc
    var i = 0usize
    while i < t.n {
        var kid = t.which[i]
        var row = nf
        while row >= nf {
            var r = 0usize
            row = nf
            while r < nf {
                if v.id[r] == kid { row = r }
                r += 1usize
            }
            if row >= nf { kid = kid / 2i64 }
        }
        wh[i] = row + 1usize
        i += 1usize
    }
    v.ncp = t.ncp
    v.hasx = t.hasx
    let sc = 1.0f64 / t.pl.risk[0usize]
    i = 0usize
    while i < t.ncp {
        c1[i] = t.cpcp[i] * sc
        c2[i] = t.cpnsplit[i]
        c3[i] = t.cprisk[i] * sc
        c4[i] = t.cpx[i] * sc
        c5[i] = t.cpxs[i] * sc
        i += 1usize
    }
    v.cp_cp = c1
    v.cp_nsplit = c2
    v.cp_rel = c3
    v.cp_x = c4
    v.cp_xs = c5
    v.nimp = 0usize
    if ns > 0usize {
        let ei = rp_importance(a, &v)
        if ei != ok { ret (v, ei) }
    }
    ret (v, ok)
}

// prune.rpart: the subtree whose nodes complexity (scaled by the root risk) is above cp
fn rp_prune(a: *mem.Arena, v0: *const View, cp: f64) -> (View, err) {
    var v: View = zero
    let nf = v0.nfr
    let (tossed, e1) = mem.alloc[bool](a, nf)
    let (newleaf, e2) = mem.alloc[bool](a, nf)
    let (keep, e3) = mem.alloc[bool](a, nf)
    if e1 != ok || e2 != ok || e3 != ok { ret (v, mem.Full) }
    var any = false
    var r = 0usize
    while r < nf {
        tossed[r] = v0.fcplx[r] <= cp && v0.fvar[r] != 0usize
        if tossed[r] { any = true }
        r += 1usize
    }
    if !any { ret (*v0, ok) }
    // a row is tossed when it or an ancestor is in the first set
    var q = 0usize
    r = 0usize
    while r < nf {
        var hit = tossed[r]
        var anc = v0.id[r]
        while !hit && anc > 1i64 {
            anc = anc / 2i64
            q = 0usize
            while q < nf {
                if v0.id[q] == anc && v0.fcplx[q] <= cp && v0.fvar[q] != 0usize { hit = true }
                q += 1usize
            }
        }
        keep[r] = !hit
        r += 1usize
    }
    // the rows that become leaves: in the first set with a parent that is not tossed
    var nk = 0usize
    r = 0usize
    while r < nf {
        newleaf[r] = false
        if !keep[r] && tossed[r] {
            // a tossed row whose parent is not tossed becomes a leaf; one under a tossed parent goes
            let par = v0.id[r] / 2i64
            var parent_removed = false
            q = 0usize
            while q < nf {
                if v0.id[q] == par && !keep[q] { parent_removed = true }
                q += 1usize
            }
            if !parent_removed { newleaf[r] = true }
        }
        if keep[r] || newleaf[r] { nk += 1usize }
        r += 1usize
    }
    var nsp = 0usize
    var ncs = 0usize
    r = 0usize
    while r < nf {
        if keep[r] && v0.fvar[r] != 0usize {
            let cnt = 1usize + v0.fncomp[r] + v0.fnsur[r]
            nsp += cnt
            var s = 0usize
            while s < cnt {
                if v0.sp_ncat[v0.fidx[r] - 1usize + s] > 1i64 { ncs += 1usize }
                s += 1usize
            }
        }
        r += 1usize
    }
    v.method = v0.method
    v.p = v0.p
    v.k = v0.k
    v.maxcat = v0.maxcat
    v.usesur = v0.usesur
    v.nobs = v0.nobs
    v.y2w = v0.y2w
    let (id, f1) = mem.alloc[i64](a, nk)
    let (fnn, f2) = mem.alloc[usize](a, nk)
    let (fwt, f3) = mem.alloc[f64](a, nk)
    let (fdev, f4) = mem.alloc[f64](a, nk)
    let (fyval, f5) = mem.alloc[f64](a, nk)
    let (fcplx, f6) = mem.alloc[f64](a, nk)
    let (fncomp, f7) = mem.alloc[usize](a, nk)
    let (fnsur, f8) = mem.alloc[usize](a, nk)
    let (fvar, f9) = mem.alloc[usize](a, nk)
    let (fidx, f10) = mem.alloc[usize](a, nk)
    let (y2, f11) = mem.alloc[f64](a, nk * v0.y2w + 1usize)
    let (spv, g1) = mem.alloc[usize](a, nsp + 1usize)
    let (spc, g2) = mem.alloc[f64](a, nsp + 1usize)
    let (spn, g3) = mem.alloc[i64](a, nsp + 1usize)
    let (spi, g4) = mem.alloc[f64](a, nsp + 1usize)
    let (spx, g5) = mem.alloc[f64](a, nsp + 1usize)
    let (spa, g6) = mem.alloc[f64](a, nsp + 1usize)
    let (cs, g7) = mem.alloc[i64](a, ncs * v0.maxcat + 1usize)
    let (wh, g8) = mem.alloc[usize](a, v0.nobs)
    let (newrow, g9) = mem.alloc[usize](a, nf)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok || f11 != ok { ret (v, mem.Full) }
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok { ret (v, mem.Full) }
    var o = 0usize
    var sp = 0usize
    var cr = 0usize
    r = 0usize
    while r < nf {
        newrow[r] = nf
        if keep[r] || newleaf[r] {
            newrow[r] = o
            id[o] = v0.id[r]
            fnn[o] = v0.fn_[r]
            fwt[o] = v0.fwt[r]
            fdev[o] = v0.fdev[r]
            fyval[o] = v0.fyval[r]
            fcplx[o] = v0.fcplx[r]
            var c = 0usize
            while c < v0.y2w {
                y2[o * v0.y2w + c] = v0.y2[r * v0.y2w + c]
                c += 1usize
            }
            if keep[r] && v0.fvar[r] != 0usize {
                fvar[o] = v0.fvar[r]
                fncomp[o] = v0.fncomp[r]
                fnsur[o] = v0.fnsur[r]
                fidx[o] = sp + 1usize
                let cnt = 1usize + v0.fncomp[r] + v0.fnsur[r]
                var s = 0usize
                while s < cnt {
                    let src = v0.fidx[r] - 1usize + s
                    spv[sp] = v0.sp_var[src]
                    spc[sp] = v0.sp_count[src]
                    spn[sp] = v0.sp_ncat[src]
                    spi[sp] = v0.sp_imp[src]
                    spx[sp] = v0.sp_index[src]
                    spa[sp] = v0.sp_adj[src]
                    if v0.sp_ncat[src] > 1i64 {
                        let old = usize(v0.sp_index[src]) - 1usize
                        var q2 = 0usize
                        while q2 < v0.maxcat {
                            cs[cr * v0.maxcat + q2] = v0.cs[old * v0.maxcat + q2]
                            q2 += 1usize
                        }
                        spx[sp] = f64(cr + 1usize)
                        cr += 1usize
                    }
                    sp += 1usize
                    s += 1usize
                }
            } else {
                fvar[o] = 0usize
                fncomp[o] = 0usize
                fnsur[o] = 0usize
                fidx[o] = 0usize
            }
            o += 1usize
        }
        r += 1usize
    }
    v.nfr = nk
    v.nsp = nsp
    v.ncs = ncs
    v.id = id
    v.fn_ = fnn
    v.fwt = fwt
    v.fdev = fdev
    v.fyval = fyval
    v.fcplx = fcplx
    v.fncomp = fncomp
    v.fnsur = fnsur
    v.fvar = fvar
    v.fidx = fidx
    v.y2 = y2
    v.sp_var = spv
    v.sp_count = spc
    v.sp_ncat = spn
    v.sp_imp = spi
    v.sp_index = spx
    v.sp_adj = spa
    v.cs = cs
    var i = 0usize
    while i < v0.nobs {
        var kid = v0.id[v0.wh[i] - 1usize]
        var row = nk
        while row >= nk {
            row = nk
            r = 0usize
            while r < nf {
                if v0.id[r] == kid && newrow[r] < nk { row = newrow[r] }
                r += 1usize
            }
            if row >= nk { kid = kid / 2i64 }
        }
        wh[i] = row + 1usize
        i += 1usize
    }
    v.wh = wh
    // the cp table: rows whose cp is at least the new cp, then one row at cp
    let (c1, h1) = mem.alloc[f64](a, v0.ncp)
    let (c2, h2) = mem.alloc[f64](a, v0.ncp)
    let (c3, h3) = mem.alloc[f64](a, v0.ncp)
    let (c4, h4) = mem.alloc[f64](a, v0.ncp)
    let (c5, h5) = mem.alloc[f64](a, v0.ncp)
    if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok { ret (v, mem.Full) }
    var m = 0usize
    var seen_cp = false
    i = 0usize
    while i < v0.ncp {
        var tcp = v0.cp_cp[i]
        if tcp < cp { tcp = cp }
        var first = true
        if tcp == cp && seen_cp { first = false }
        if tcp == cp { seen_cp = true }
        // match(unique(temp), temp): later rows equal to an earlier temp are dropped
        var j = 0usize
        while j < i {
            var tj = v0.cp_cp[j]
            if tj < cp { tj = cp }
            if tj == tcp { first = false }
            j += 1usize
        }
        if first {
            c1[m] = tcp
            c2[m] = v0.cp_nsplit[i]
            c3[m] = v0.cp_rel[i]
            c4[m] = v0.cp_x[i]
            c5[m] = v0.cp_xs[i]
            m += 1usize
        }
        i += 1usize
    }
    c1[m - 1usize] = cp
    v.ncp = m
    v.hasx = v0.hasx
    v.cp_cp = c1
    v.cp_nsplit = c2
    v.cp_rel = c3
    v.cp_x = c4
    v.cp_xs = c5
    v.nimp = 0usize
    if nsp > 0usize {
        let ei = rp_importance(a, &v)
        if ei != ok { ret (v, ei) }
    }
    ret (v, ok)
}

// pred_rpart: the frame row (0-based) each of the nn rows of xn (nn by p, column-major, NaN missing) ends in
fn rp_find_row(v: *const View, id: i64) -> usize {
    var r = 0usize
    while r < v.nfr {
        if v.id[r] == id { ret r }
        r += 1usize
    }
    ret NONE
}

fn rp_predict_row(v: *const View, xn: []const f64, nn: usize, i: usize) -> usize {
    var node = 1i64
    while true {
        let npos = rp_find_row(v, node)
        if v.fvar[npos] == 0usize { ret npos }
        var moved = false
        let s0 = v.fidx[npos] - 1usize
        let var0 = v.sp_var[s0] - 1usize
        let xv = xn[var0 * nn + i]
        if rp_finite(xv) {
            let nc = v.sp_ncat[s0]
            var dir = 0i64
            if nc >= 2i64 {
                dir = v.cs[(usize(v.sp_index[s0]) - 1usize) * v.maxcat + usize(xv) - 1usize]
            } else if xv < v.sp_index[s0] {
                dir = nc
            } else {
                dir = 0i64 - nc
            }
            if dir != 0i64 {
                if dir == 0i64 - 1i64 { node = 2i64 * node } else { node = 2i64 * node + 1i64 }
                moved = true
            }
        }
        if !moved && v.usesur > 0usize {
            var j = 0usize
            while j < v.fnsur[npos] && !moved {
                let si = s0 + 1usize + v.fncomp[npos] + j
                let sv = v.sp_var[si] - 1usize
                let sx = xn[sv * nn + i]
                if rp_finite(sx) {
                    let nc = v.sp_ncat[si]
                    var dir = 0i64
                    if nc >= 2i64 {
                        dir = v.cs[(usize(v.sp_index[si]) - 1usize) * v.maxcat + usize(sx) - 1usize]
                    } else if sx < v.sp_index[si] {
                        dir = nc
                    } else {
                        dir = 0i64 - nc
                    }
                    if dir != 0i64 {
                        if dir == 0i64 - 1i64 { node = 2i64 * node } else { node = 2i64 * node + 1i64 }
                        moved = true
                    }
                }
                j += 1usize
            }
        }
        if !moved && v.usesur > 1usize {
            let lr = rp_find_row(v, 2i64 * node)
            let rr = rp_find_row(v, 2i64 * node + 1i64)
            if v.fn_[lr] != v.fn_[rr] {
                if v.fn_[lr] > v.fn_[rr] { node = 2i64 * node } else { node = 2i64 * node + 1i64 }
                moved = true
            }
        }
        if !moved { ret npos }
    }
    ret NONE
}

// ---- labels.rpart: sprintf("%.<digits>g"), then the node labels of a view

fn rp_pow10(k: i64) -> f64 {
    var r = 1.0f64
    var i = 0i64
    if k >= 0i64 {
        while i < k {
            r = r * 10.0f64
            i += 1i64
        }
        ret r
    }
    while i > k {
        r = r / 10.0f64
        i -= 1i64
    }
    ret r
}

fn rp_fmt_g(b: *str.Builder, x: f64, digits: usize) -> err {
    if x == 0.0f64 { ret str.push(b, "0") }
    var neg = false
    var ax = x
    if ax < 0.0f64 {
        neg = true
        ax = 0.0f64 - ax
    }
    let pd = i64(digits)
    var e10 = i64(math.floor[f64](math.log10[f64](ax)))
    var m = math.floor[f64](ax / rp_pow10(e10 - pd + 1i64) + 0.5f64)
    if m >= rp_pow10(pd) {
        e10 += 1i64
        m = math.floor[f64](ax / rp_pow10(e10 - pd + 1i64) + 0.5f64)
    }
    if m < rp_pow10(pd - 1i64) {
        e10 -= 1i64
        m = math.floor[f64](ax / rp_pow10(e10 - pd + 1i64) + 0.5f64)
    }
    var ds: [24]u8 = zero
    var q = 0usize
    var rest = m
    while q < digits {
        let d = rest - math.floor[f64](rest / 10.0f64) * 10.0f64
        ds[digits - 1usize - q] = 48u8 + u8(usize(d))
        rest = math.floor[f64](rest / 10.0f64)
        q += 1usize
    }
    var last = digits
    while last > 1usize && ds[last - 1usize] == 48u8 { last -= 1usize }
    if neg { let _ = str.push_byte(b, 45u8) }
    if e10 >= pd || e10 < 0i64 - 4i64 {
        let _ = str.push_byte(b, ds[0usize])
        if last > 1usize {
            let _ = str.push_byte(b, 46u8)
            q = 1usize
            while q < last {
                let _ = str.push_byte(b, ds[q])
                q += 1usize
            }
        }
        let _ = str.push_byte(b, 101u8)
        var ex = e10
        if ex < 0i64 {
            let _ = str.push_byte(b, 45u8)
            ex = 0i64 - ex
        } else {
            let _ = str.push_byte(b, 43u8)
        }
        if ex < 10i64 { let _ = str.push_byte(b, 48u8) }
        ret str.push_usize(b, usize(ex))
    }
    if e10 >= 0i64 {
        let ip = usize(e10) + 1usize
        q = 0usize
        while q < ip {
            if q < digits { let _ = str.push_byte(b, ds[q]) } else { let _ = str.push_byte(b, 48u8) }
            q += 1usize
        }
        if last > ip {
            let _ = str.push_byte(b, 46u8)
            q = ip
            while q < last {
                let _ = str.push_byte(b, ds[q])
                q += 1usize
            }
        }
        ret ok
    }
    let _ = str.push(b, "0.")
    var z = 0i64 - e10 - 1i64
    while z > 0i64 {
        let _ = str.push_byte(b, 48u8)
        z -= 1i64
    }
    q = 0usize
    while q < last {
        let _ = str.push_byte(b, ds[q])
        q += 1usize
    }
    ret ok
}

fn rp_level_letter(j: usize) -> u8 {
    if j < 26usize { ret 97u8 + u8(j) }
    ret 65u8 + u8(j - 26usize)
}

// "root", then each other row's label (variable, comparison, cut or levels) joined by "|"; the variables are named x1, x2, ... and the levels a, b, ...
fn rp_labels(a: *mem.Arena, v: *const View, digits: usize) -> (str, err) {
    let (ib, eb) = str.builder(a, 64usize + v.nfr * 48usize)
    if eb != ok { ret ("", eb) }
    var b = ib
    let _ = str.push(&b, "root")
    var r = 1usize
    while r < v.nfr {
        let _ = str.push(&b, "|")
        let pr = rp_find_row(v, v.id[r] / 2i64)
        let s0 = v.fidx[pr] - 1usize
        let _ = str.push(&b, "x")
        let _ = str.push_usize(&b, v.sp_var[s0])
        let isleft = v.id[r] % 2i64 == 0i64
        let nc = v.sp_ncat[s0]
        if nc < 2i64 {
            // direction -1: x < cut goes left
            var lt = isleft
            if nc > 0i64 { lt = !isleft }
            if lt { let _ = str.push(&b, "< ") } else { let _ = str.push(&b, ">=") }
            let _ = rp_fmt_g(&b, v.sp_index[s0], digits)
        } else {
            let _ = str.push(&b, "=")
            let row = usize(v.sp_index[s0]) - 1usize
            var want = 1i64
            if isleft { want = 0i64 - 1i64 }
            var q = 0usize
            while q < usize(nc) {
                if v.cs[row * v.maxcat + q] == want { let _ = str.push_byte(&b, rp_level_letter(q)) }
                q += 1usize
            }
        }
        r += 1usize
    }
    ret (str.done(&b), ok)
}
