// R xgboost with objective reg:squarederror and tree_method exact: gradient-boosted regression trees grown by the exact greedy algorithm (split gain with lambda, gamma and min_child_weight, bottom-up pruning by gamma, learning rate eta, base score the mean of y), no sampling.
//
// Not here: other objectives, the approx and hist methods, sampling and column subsampling, monotone and interaction constraints, missing values, DART and linear boosters.

use e.math
use e.mem

// a node of the flat tree arrays: feat[i] < 0 is a leaf with value val[i]; otherwise rows with x[feat] < val[i] go to left[i], the others to right[i]
fn grow(a: *mem.Arena, x: []const f64, g: []const f64, n: usize, p: usize, rows: []usize, depth: usize, max_depth: usize, lambda: f64, gamma: f64, mcw: f64, eta: f64, feat: []i64, val: []f64, left: []usize, right: []usize, count: *usize, loss: []f64) -> usize {
    let me = *count
    *count = *count + 1usize
    var gs = 0.0f64
    var hs = 0.0f64
    var i = 0usize
    while i < rows.len {
        gs += g[rows[i]]
        hs += 1.0f64
        i += 1usize
    }
    feat[me] = 0i64 - 1i64
    val[me] = 0.0f64 - gs / (hs + lambda) * eta
    loss[me] = 0.0f64
    if depth >= max_depth || rows.len < 2usize { ret me }
    var best = 0.0f64
    var bf = p
    var bt = 0.0f64
    let (ord, e1) = mem.alloc[usize](a, rows.len)
    if e1 != ok { ret me }
    var f = 0usize
    while f < p {
        i = 0usize
        while i < rows.len {
            ord[i] = rows[i]
            i += 1usize
        }
        i = 1usize
        while i < rows.len {
            let v = ord[i]
            var j = i
            while j > 0usize && x[ord[j - 1usize] * p + f] > x[v * p + f] {
                ord[j] = ord[j - 1usize]
                j -= 1usize
            }
            ord[j] = v
            i += 1usize
        }
        var gl = 0.0f64
        var hl = 0.0f64
        i = 0usize
        while i + 1usize < rows.len {
            gl += g[ord[i]]
            hl += 1.0f64
            let a0 = x[ord[i] * p + f]
            let b0 = x[ord[i + 1usize] * p + f]
            if b0 > a0 {
                let hr = hs - hl
                if hl >= mcw && hr >= mcw {
                    let gr = gs - gl
                    let gain = 0.5f64 * (gl * gl / (hl + lambda) + gr * gr / (hr + lambda) - gs * gs / (hs + lambda))
                    if gain > best + 1.0e-6f64 || (bf == p && gain > 1.0e-6f64) {
                        best = gain
                        bf = f
                        bt = (a0 + b0) / 2.0f64
                    }
                }
            }
            i += 1usize
        }
        f += 1usize
    }
    if bf == p { ret me }
    let (lr, e2) = mem.alloc[usize](a, rows.len)
    let (rr, e3) = mem.alloc[usize](a, rows.len)
    if e2 != ok || e3 != ok { ret me }
    var nl = 0usize
    var nr = 0usize
    i = 0usize
    while i < rows.len {
        if x[rows[i] * p + bf] < bt {
            lr[nl] = rows[i]
            nl += 1usize
        } else {
            rr[nr] = rows[i]
            nr += 1usize
        }
        i += 1usize
    }
    feat[me] = i64(bf)
    val[me] = bt
    loss[me] = best
    left[me] = grow(a, x, g, n, p, lr[0usize..nl], depth + 1usize, max_depth, lambda, gamma, mcw, eta, feat, val, left, right, count, loss)
    right[me] = grow(a, x, g, n, p, rr[0usize..nr], depth + 1usize, max_depth, lambda, gamma, mcw, eta, feat, val, left, right, count, loss)
    // prune a split whose children are both leaves and whose gain, xgboost counting it without the one half, is below gamma
    if feat[left[me]] < 0i64 && feat[right[me]] < 0i64 && 2.0f64 * best < gamma {
        feat[me] = 0i64 - 1i64
        val[me] = 0.0f64 - gs / (hs + lambda) * eta
    }
    ret me
}

// fit and predict on the training rows: pred receives the boosted predictions
fn boost(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nrounds: usize, eta: f64, max_depth: usize, lambda: f64, gamma: f64, mcw: f64, pred: []f64) -> err {
    let cap = 2usize * (1usize << (max_depth + 1usize))
    var base = 0.0f64
    var i = 0usize
    while i < n {
        base += y[i] / f64(n)
        i += 1usize
    }
    i = 0usize
    while i < n {
        pred[i] = base
        i += 1usize
    }
    let (g, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    var round = 0usize
    while round < nrounds {
        let start = mem.mark(a)
        let (feat, e1) = mem.alloc[i64](a, cap)
        let (val, e2) = mem.alloc[f64](a, cap)
        let (lf, e3) = mem.alloc[usize](a, cap)
        let (rt, e4) = mem.alloc[usize](a, cap)
        let (loss, e5) = mem.alloc[f64](a, cap)
        let (rows, e6) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
        i = 0usize
        while i < n {
            g[i] = pred[i] - y[i]
            rows[i] = i
            i += 1usize
        }
        var count = 0usize
        let root = grow(a, x, g, n, p, rows, 0usize, max_depth, lambda, gamma, mcw, eta, feat, val, lf, rt, &count, loss)
        i = 0usize
        while i < n {
            var node = root
            while feat[node] >= 0i64 {
                if x[i * p + usize(feat[node])] < val[node] { node = lf[node] } else { node = rt[node] }
            }
            pred[i] += val[node]
            i += 1usize
        }
        mem.reset(a, start)
        round += 1usize
    }
    ret ok
}
