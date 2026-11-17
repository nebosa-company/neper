// R gbm, the gaussian loss with no subsampling (bag.fraction = 1, train.fraction = 1): gradient boosting of regression trees grown best-first to `depth` splits, each leaf predicting the mean residual,
// the fit moved by `shrinkage` times it. The answer is the fit at the training rows.
//
// Not here: the other distributions, bagging (needs the R generator), train.fraction, weights, missing values, factors, relative.influence, predict on new data.

use e.mem

// the best split of the rows in leaf l: writes (variable, position in that variable's order, improvement) to out; improvement 0 when no split leaves minobs rows on each side
fn best_split(x: []const f64, r: []const f64, order: []const usize, leafof: []const usize, n: usize, p: usize, l: usize, minobs: usize, out: []f64) {
    var total = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < n {
        if leafof[i] == l {
            total += r[i]
            cnt += 1usize
        }
        i += 1usize
    }
    out[0usize] = 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64
    var j = 0usize
    while j < p {
        var sl = 0.0f64
        var nl = 0usize
        var q = 0usize
        while q < n {
            let row = order[j * n + q]
            if leafof[row] == l {
                sl += r[row]
                nl += 1usize
                var q2 = q + 1usize
                while q2 < n && leafof[order[j * n + q2]] != l { q2 += 1usize }
                if q2 < n && x[j * n + order[j * n + q2]] > x[j * n + row] {
                    let nr = cnt - nl
                    if nl >= minobs && nr >= minobs {
                        let ml = sl / f64(nl)
                        let mr = (total - sl) / f64(nr)
                        let imp = f64(nl) * f64(nr) / f64(nl + nr) * (ml - mr) * (ml - mr)
                        if imp > out[2usize] {
                            out[0usize] = f64(j)
                            out[1usize] = f64(q)
                            out[2usize] = imp
                        }
                    }
                }
            }
            q += 1usize
        }
        j += 1usize
    }
}

// x is n by p column-major; fitted receives the boosted fit at the training rows after ntrees trees
fn gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    let (order, e1) = mem.alloc[usize](a, n * p)
    let (r, e2) = mem.alloc[f64](a, n)
    let (leafof, e3) = mem.alloc[usize](a, n)
    let (cand, e4) = mem.alloc[f64](a, 3usize)
    let (lsum, e5) = mem.alloc[f64](a, depth + 1usize)
    let (lcnt, e6) = mem.alloc[f64](a, depth + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            order[j * n + i] = i
            i += 1usize
        }
        i = 1usize
        while i < n {
            let key = order[j * n + i]
            var k = i
            while k > 0usize && x[j * n + order[j * n + k - 1usize]] > x[j * n + key] {
                order[j * n + k] = order[j * n + k - 1usize]
                k -= 1usize
            }
            order[j * n + k] = key
            i += 1usize
        }
        j += 1usize
    }
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += y[i]
        i += 1usize
    }
    m = m / f64(n)
    i = 0usize
    while i < n {
        fitted[i] = m
        i += 1usize
    }
    var t = 0usize
    while t < ntrees {
        i = 0usize
        while i < n {
            r[i] = y[i] - fitted[i]
            leafof[i] = 0usize
            i += 1usize
        }
        var nleaf = 1usize
        var s = 0usize
        while s < depth {
            var bl = 0usize
            var bimp = 0.0f64
            var bv = 0usize
            var bq = 0usize
            var l = 0usize
            while l < nleaf {
                best_split(x, r, order, leafof, n, p, l, minobs, cand)
                if cand[2usize] > bimp {
                    bimp = cand[2usize]
                    bl = l
                    bv = usize(cand[0usize])
                    bq = usize(cand[1usize])
                }
                l += 1usize
            }
            if bimp <= 0.0f64 { break }
            let thr = x[bv * n + order[bv * n + bq]]
            i = 0usize
            while i < n {
                if leafof[i] == bl && x[bv * n + i] > thr { leafof[i] = nleaf }
                i += 1usize
            }
            nleaf += 1usize
            s += 1usize
        }
        var l = 0usize
        while l < nleaf {
            lsum[l] = 0.0f64
            lcnt[l] = 0.0f64
            l += 1usize
        }
        i = 0usize
        while i < n {
            lsum[leafof[i]] += r[i]
            lcnt[leafof[i]] += 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            fitted[i] += shrinkage * lsum[leafof[i]] / lcnt[leafof[i]]
            i += 1usize
        }
        t += 1usize
    }
    ret ok
}
