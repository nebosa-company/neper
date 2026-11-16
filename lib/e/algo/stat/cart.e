// R rpart (method "anova", xval = 0): a regression tree on numeric predictors grown the way rpart.control's defaults do: a node with fewer than minsplit
// observations is a leaf, a split must leave at least minbucket observations on each side and be placed at the midpoint between consecutive distinct values,
// the best split is the one with the largest reduction of the sum of squares, and a split is made only when that reduction is at least cp times the root's sum
// of squares. Observations go left when x < the threshold.
//
// Not here: classification, Poisson and survival trees, surrogate and competing splits, categorical predictors, cross-validation and pruning.

use e.mem

type Tree = struct { nleaf: usize, fitted: []f64 }

// the node holds the observation indices idx[lo..hi]; fitted values go to the output
fn grow(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, idx: []usize, lo: usize, hi: usize, root_ss: f64, minsplit: usize, minbucket: usize, cp: f64, depth: usize, fitted: []f64) -> (usize, err) {
    let m = hi - lo
    var s = 0.0f64
    var i = lo
    while i < hi {
        s += y[idx[i]]
        i += 1usize
    }
    let mean = s / f64(m)
    var ss = 0.0f64
    i = lo
    while i < hi {
        ss += (y[idx[i]] - mean) * (y[idx[i]] - mean)
        i += 1usize
    }
    var leaf = m < minsplit || depth >= 30usize
    var best = 0.0f64
    var bj = p
    var bthr = 0.0f64
    if !leaf {
        let (ord, e1) = mem.alloc[usize](a, m)
        if e1 != ok { ret (0usize, e1) }
        var j = 0usize
        while j < p {
            // the node's observations ordered by predictor j
            i = 0usize
            while i < m {
                ord[i] = idx[lo + i]
                i += 1usize
            }
            i = 1usize
            while i < m {
                let t = ord[i]
                var q = i
                while q > 0usize && x[ord[q - 1usize] * p + j] > x[t * p + j] {
                    ord[q] = ord[q - 1usize]
                    q -= 1usize
                }
                ord[q] = t
                i += 1usize
            }
            var sl = 0.0f64
            var k = 0usize
            while k + 1usize < m {
                sl += y[ord[k]]
                let nl = k + 1usize
                let nr = m - nl
                let xa = x[ord[k] * p + j]
                let xb = x[ord[k + 1usize] * p + j]
                if nl >= minbucket && nr >= minbucket && xb > xa {
                    let sr = s - sl
                    let gain = sl * sl / f64(nl) + sr * sr / f64(nr) - s * s / f64(m)
                    if gain > best {
                        best = gain
                        bj = j
                        bthr = (xa + xb) / 2.0f64
                    }
                }
                k += 1usize
            }
            j += 1usize
        }
        if bj == p || best < cp * root_ss { leaf = true }
    }
    if leaf {
        i = lo
        while i < hi {
            fitted[idx[i]] = mean
            i += 1usize
        }
        ret (1usize, ok)
    }
    // partition: left (x < thr) first
    var mid = lo
    i = lo
    while i < hi {
        if x[idx[i] * p + bj] < bthr {
            let t = idx[mid]
            idx[mid] = idx[i]
            idx[i] = t
            mid += 1usize
        }
        i += 1usize
    }
    let (l, e2) = grow(a, x, y, n, p, idx, lo, mid, root_ss, minsplit, minbucket, cp, depth + 1usize, fitted)
    if e2 != ok { ret (0usize, e2) }
    let (r, e3) = grow(a, x, y, n, p, idx, mid, hi, root_ss, minsplit, minbucket, cp, depth + 1usize, fitted)
    if e3 != ok { ret (0usize, e3) }
    ret (l + r, ok)
}

fn rpart_anova(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, minsplit: usize, minbucket: usize, cp: f64) -> (Tree, err) {
    var t: Tree = zero
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (t, e1) }
    let (fitted, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (t, e2) }
    var i = 0usize
    var s = 0.0f64
    while i < n {
        idx[i] = i
        s += y[i]
        i += 1usize
    }
    let mean = s / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (y[i] - mean) * (y[i] - mean)
        i += 1usize
    }
    let (nl, e3) = grow(a, x, y, n, p, idx, 0usize, n, ss, minsplit, minbucket, cp, 0usize, fitted)
    if e3 != ok { ret (t, e3) }
    t.nleaf = nl
    t.fitted = fitted
    ret (t, ok)
}
