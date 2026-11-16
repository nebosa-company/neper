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

// ---- classification (method "class", gini): classes are 0 .. k - 1

fn class_counts(y: []const usize, idx: []const usize, lo: usize, hi: usize, k: usize, out: []f64) {
    var c = 0usize
    while c < k {
        out[c] = 0.0f64
        c += 1usize
    }
    var i = lo
    while i < hi {
        out[y[idx[i]]] += 1.0f64
        i += 1usize
    }
}

fn gini_of(cnt: []const f64, k: usize, n: f64) -> f64 {
    var s = 0.0f64
    var c = 0usize
    while c < k {
        s += cnt[c] * cnt[c]
        c += 1usize
    }
    ret n - s / n
}

fn miscl(cnt: []const f64, k: usize, n: f64) -> f64 {
    var m = 0.0f64
    var c = 0usize
    while c < k {
        if cnt[c] > m { m = cnt[c] }
        c += 1usize
    }
    ret n - m
}

fn grow_class(a: *mem.Arena, x: []const f64, y: []const usize, n: usize, p: usize, k: usize, idx: []usize, lo: usize, hi: usize, root_err: f64, minsplit: usize, minbucket: usize, cp: f64, depth: usize, pred: []usize) -> (usize, err) {
    let m = hi - lo
    let (cnt, e0) = mem.alloc[f64](a, k)
    if e0 != ok { ret (0usize, e0) }
    class_counts(y, idx, lo, hi, k, cnt)
    var major = 0usize
    var c = 1usize
    while c < k {
        if cnt[c] > cnt[major] { major = c }
        c += 1usize
    }
    let me = miscl(cnt, k, f64(m))
    var leaf = m < minsplit || depth >= 30usize || me == 0.0f64
    var best = 0.0f64
    var bj = p
    var bthr = 0.0f64
    if !leaf {
        let (ord, e1) = mem.alloc[usize](a, m)
        if e1 != ok { ret (0usize, e1) }
        let (cl, e2) = mem.alloc[f64](a, k)
        if e2 != ok { ret (0usize, e2) }
        let (cr, e3) = mem.alloc[f64](a, k)
        if e3 != ok { ret (0usize, e3) }
        let parent_gini = gini_of(cnt, k, f64(m))
        var j = 0usize
        while j < p {
            var i = 0usize
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
            c = 0usize
            while c < k {
                cl[c] = 0.0f64
                c += 1usize
            }
            var t = 0usize
            while t + 1usize < m {
                cl[y[ord[t]]] += 1.0f64
                let nl = t + 1usize
                let nr = m - nl
                let xa = x[ord[t] * p + j]
                let xb = x[ord[t + 1usize] * p + j]
                if nl >= minbucket && nr >= minbucket && xb > xa {
                    c = 0usize
                    while c < k {
                        cr[c] = cnt[c] - cl[c]
                        c += 1usize
                    }
                    let gain = parent_gini - gini_of(cl, k, f64(nl)) - gini_of(cr, k, f64(nr))
                    if gain > best {
                        best = gain
                        bj = j
                        bthr = (xa + xb) / 2.0f64
                    }
                }
                t += 1usize
            }
            j += 1usize
        }
        if bj == p { leaf = true }
        if !leaf {
            let (lc, e4) = mem.alloc[f64](a, k)
            if e4 != ok { ret (0usize, e4) }
            let (rc, e5) = mem.alloc[f64](a, k)
            if e5 != ok { ret (0usize, e5) }
            c = 0usize
            while c < k {
                lc[c] = 0.0f64
                rc[c] = 0.0f64
                c += 1usize
            }
            var nl = 0.0f64
            var nr = 0.0f64
            var i = lo
            while i < hi {
                if x[idx[i] * p + bj] < bthr {
                    lc[y[idx[i]]] += 1.0f64
                    nl += 1.0f64
                } else {
                    rc[y[idx[i]]] += 1.0f64
                    nr += 1.0f64
                }
                i += 1usize
            }
            let drop = me - miscl(lc, k, nl) - miscl(rc, k, nr)
            if best < cp * root_err { leaf = true }
        }
    }
    if leaf {
        var i = lo
        while i < hi {
            pred[idx[i]] = major
            i += 1usize
        }
        ret (1usize, ok)
    }
    var mid = lo
    var i = lo
    while i < hi {
        if x[idx[i] * p + bj] < bthr {
            let t = idx[mid]
            idx[mid] = idx[i]
            idx[i] = t
            mid += 1usize
        }
        i += 1usize
    }
    let (l, e6) = grow_class(a, x, y, n, p, k, idx, lo, mid, root_err, minsplit, minbucket, cp, depth + 1usize, pred)
    if e6 != ok { ret (0usize, e6) }
    let (r, e7) = grow_class(a, x, y, n, p, k, idx, mid, hi, root_err, minsplit, minbucket, cp, depth + 1usize, pred)
    if e7 != ok { ret (0usize, e7) }
    ret (l + r, ok)
}

// the number of leaves; pred receives the majority class of each observation's leaf
fn rpart_class(a: *mem.Arena, x: []const f64, y: []const usize, n: usize, p: usize, k: usize, minsplit: usize, minbucket: usize, cp: f64, pred: []usize) -> (usize, err) {
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0usize, e1) }
    let (cnt, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret (0usize, e2) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    class_counts(y, idx, 0usize, n, k, cnt)
    let root = miscl(cnt, k, f64(n))
    let (nl, e3) = grow_class(a, x, y, n, p, k, idx, 0usize, n, root, minsplit, minbucket, cp, 0usize, pred)
    ret (nl, e3)
}

// ---- classification by growth and cost-complexity pruning: the tree is grown over every admissible gini split and pruned bottom-up by cp

// returns (leaves, risk of the pruned subtree in misclassified counts); preds are written for every observation of the node
fn grow_prune(a: *mem.Arena, x: []const f64, y: []const usize, n: usize, p: usize, k: usize, idx: []usize, lo: usize, hi: usize, root_err: f64, minsplit: usize, minbucket: usize, cp: f64, depth: usize, pred: []usize) -> (usize, f64, err) {
    let m = hi - lo
    let (cnt, e0) = mem.alloc[f64](a, k)
    if e0 != ok { ret (0usize, 0.0f64, e0) }
    class_counts(y, idx, lo, hi, k, cnt)
    var major = 0usize
    var c = 1usize
    while c < k {
        if cnt[c] > cnt[major] { major = c }
        c += 1usize
    }
    let me = miscl(cnt, k, f64(m))
    var leaf = m < minsplit || depth >= 30usize || me == 0.0f64
    var best = 0.0f64
    var bj = p
    var bthr = 0.0f64
    if !leaf {
        let (ord, e1) = mem.alloc[usize](a, m)
        if e1 != ok { ret (0usize, 0.0f64, e1) }
        let (cl, e2) = mem.alloc[f64](a, k)
        if e2 != ok { ret (0usize, 0.0f64, e2) }
        let (cr, e3) = mem.alloc[f64](a, k)
        if e3 != ok { ret (0usize, 0.0f64, e3) }
        let parent_gini = gini_of(cnt, k, f64(m))
        var j = 0usize
        while j < p {
            var i = 0usize
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
            c = 0usize
            while c < k {
                cl[c] = 0.0f64
                c += 1usize
            }
            var t = 0usize
            while t + 1usize < m {
                cl[y[ord[t]]] += 1.0f64
                let nl = t + 1usize
                let nr = m - nl
                let xa = x[ord[t] * p + j]
                let xb = x[ord[t + 1usize] * p + j]
                if nl >= minbucket && nr >= minbucket && xb > xa {
                    c = 0usize
                    while c < k {
                        cr[c] = cnt[c] - cl[c]
                        c += 1usize
                    }
                    let gain = parent_gini - gini_of(cl, k, f64(nl)) - gini_of(cr, k, f64(nr))
                    if gain > best {
                        best = gain
                        bj = j
                        bthr = (xa + xb) / 2.0f64
                    }
                }
                t += 1usize
            }
            j += 1usize
        }
        if bj == p { leaf = true }
    }
    if leaf {
        var i = lo
        while i < hi {
            pred[idx[i]] = major
            i += 1usize
        }
        ret (1usize, me, ok)
    }
    var mid = lo
    var i = lo
    while i < hi {
        if x[idx[i] * p + bj] < bthr {
            let t = idx[mid]
            idx[mid] = idx[i]
            idx[i] = t
            mid += 1usize
        }
        i += 1usize
    }
    let (ll, lr, e6) = grow_prune(a, x, y, n, p, k, idx, lo, mid, root_err, minsplit, minbucket, cp, depth + 1usize, pred)
    if e6 != ok { ret (0usize, 0.0f64, e6) }
    let (rl, rr, e7) = grow_prune(a, x, y, n, p, k, idx, mid, hi, root_err, minsplit, minbucket, cp, depth + 1usize, pred)
    if e7 != ok { ret (0usize, 0.0f64, e7) }
    let leaves = ll + rl
    let sub = lr + rr
    // collapse when the subtree buys less than cp * root risk per added leaf
    let alpha = (me - sub) / f64(leaves - 1usize)
    if alpha < cp * root_err {
        i = lo
        while i < hi {
            pred[idx[i]] = major
            i += 1usize
        }
        ret (1usize, me, ok)
    }
    ret (leaves, sub, ok)
}

fn rpart_class_pruned(a: *mem.Arena, x: []const f64, y: []const usize, n: usize, p: usize, k: usize, minsplit: usize, minbucket: usize, cp: f64, pred: []usize) -> (usize, err) {
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0usize, e1) }
    let (cnt, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret (0usize, e2) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    class_counts(y, idx, 0usize, n, k, cnt)
    let root = miscl(cnt, k, f64(n))
    let (nl, r, e3) = grow_prune(a, x, y, n, p, k, idx, 0usize, n, root, minsplit, minbucket, cp, 0usize, pred)
    ret (nl, e3)
}
