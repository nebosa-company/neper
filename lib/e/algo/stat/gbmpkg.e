// R gbm, the gaussian, bernoulli, poisson, adaboost and laplace losses with no subsampling (bag.fraction = 1, train.fraction = 1): gradient boosting of regression trees grown best-first to `depth` splits, each leaf predicting the mean residual,
// the fit moved by `shrinkage` times it. The answer is the fit at the training rows.
//
// Not here: the other distributions (quantile, huberized, coxph, pairwise, multinomial), bagging (needs the R generator), train.fraction, weights, missing values, factors, relative.influence, predict on new data.

use e.math
use e.mem

// the alpha-quantile of v (sorted in place) with equal weights: the first value whose cumulative count reaches alpha times the total; a count that reaches it exactly takes the mean with the next value (the median of the laplace loss)
fn wquant(v: []f64, alpha: f64) -> f64 {
    let k = v.len
    var i = 1usize
    while i < k {
        let key = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > key {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = key
        i += 1usize
    }
    let cutoff = alpha * f64(k)
    var c = 0usize
    while c < k && f64(c + 1usize) < cutoff { c += 1usize }
    if f64(c + 1usize) == cutoff && c + 1usize < k { ret (v[c] + v[c + 1usize]) / 2.0f64 }
    ret v[c]
}

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
fn boost(a: *mem.Arena, loss: usize, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, alpha: f64, fitted: []f64) -> err {
    let (order, e1) = mem.alloc[usize](a, n * p)
    let (r, e2) = mem.alloc[f64](a, n)
    let (leafof, e3) = mem.alloc[usize](a, n)
    let (cand, e4) = mem.alloc[f64](a, 3usize)
    let (lsum, e5) = mem.alloc[f64](a, depth + 1usize)
    let (lcnt, e6) = mem.alloc[f64](a, depth + 1usize)
    let (lden, e7) = mem.alloc[f64](a, depth + 1usize)
    let (tmp, e8) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
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
    if loss == 1usize { m = math.log[f64](m / (1.0f64 - m)) }
    if loss == 2usize { m = math.log[f64](m) }
    if loss == 3usize { m = 0.5f64 * math.log[f64](m / (1.0f64 - m)) }
    if loss >= 4usize {
        i = 0usize
        while i < n {
            tmp[i] = y[i]
            i += 1usize
        }
        var al0 = alpha
        if loss == 4usize { al0 = 0.5f64 }
        m = wquant(tmp[0usize..n], al0)
    }
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
            if loss == 1usize { r[i] = y[i] - 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - fitted[i])) }
            if loss == 2usize { r[i] = y[i] - math.exp[f64](fitted[i]) }
            if loss >= 4usize {
                var al = alpha
                if loss == 4usize { al = 0.5f64 }
                if y[i] > fitted[i] {
                    r[i] = al
                    if loss == 4usize { r[i] = 1.0f64 }
                } else {
                    r[i] = al - 1.0f64
                    if loss == 4usize { r[i] = 0.0f64 - 1.0f64 }
                }
            }
            if loss == 3usize { r[i] = (2.0f64 * y[i] - 1.0f64) * math.exp[f64](0.0f64 - (2.0f64 * y[i] - 1.0f64) * fitted[i]) }
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
            lden[l] = 0.0f64
            l += 1usize
        }
        i = 0usize
        while i < n {
            lcnt[leafof[i]] += 1.0f64
            if loss == 0usize {
                lsum[leafof[i]] += r[i]
            } else if loss == 1usize {
                let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - fitted[i]))
                lsum[leafof[i]] += r[i]
                lden[leafof[i]] += pr * (1.0f64 - pr)
            } else if loss == 3usize {
                let ex = math.exp[f64](0.0f64 - (2.0f64 * y[i] - 1.0f64) * fitted[i])
                lsum[leafof[i]] += (2.0f64 * y[i] - 1.0f64) * ex
                lden[leafof[i]] += ex
            } else {
                lsum[leafof[i]] += y[i]
                lden[leafof[i]] += math.exp[f64](fitted[i])
            }
            i += 1usize
        }
        if loss >= 4usize {
            l = 0usize
            while l < nleaf {
                var k = 0usize
                i = 0usize
                while i < n {
                    if leafof[i] == l {
                        tmp[k] = y[i] - fitted[i]
                        k += 1usize
                    }
                    i += 1usize
                }
                var al = alpha
                if loss == 4usize { al = 0.5f64 }
                lsum[l] = wquant(tmp[0usize..k], al)
                l += 1usize
            }
        }
        i = 0usize
        while i < n {
            let lf = leafof[i]
            if loss == 0usize { fitted[i] += shrinkage * lsum[lf] / lcnt[lf] }
            if loss == 1usize || loss == 3usize { fitted[i] += shrinkage * lsum[lf] / lden[lf] }
            if loss == 2usize { fitted[i] += shrinkage * math.log[f64](lsum[lf] / lden[lf]) }
            if loss >= 4usize { fitted[i] += shrinkage * lsum[lf] }
            i += 1usize
        }
        t += 1usize
    }
    ret ok
}

fn gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    ret boost(a, 0usize, x, y, n, p, ntrees, shrinkage, depth, minobs, 0.5f64, fitted)
}

// distribution "bernoulli" (y in {0, 1}; fitted is on the log-odds scale): the tree fits y - p, each leaf moves by the Newton step sum(y - p) / sum(p (1 - p))
fn bernoulli(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    ret boost(a, 1usize, x, y, n, p, ntrees, shrinkage, depth, minobs, 0.5f64, fitted)
}

// distribution "poisson" (fitted is on the log scale): the tree fits y - exp(F), each leaf moves by log(sum y / sum exp(F))
fn poisson(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    ret boost(a, 2usize, x, y, n, p, ntrees, shrinkage, depth, minobs, 0.5f64, fitted)
}

// distribution "adaboost" (y in {0, 1}; fitted is the half log-odds scale): the tree fits (2y - 1) exp(-(2y - 1) F), each leaf moves by sum((2y - 1) exp(-(2y - 1) F)) / sum(exp(-(2y - 1) F)), the start is half the log odds
fn adaboost(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    ret boost(a, 3usize, x, y, n, p, ntrees, shrinkage, depth, minobs, 0.5f64, fitted)
}

// distribution "laplace": the tree fits the sign of y - F, each leaf moves by the median of its residuals, the start is the median of y
fn laplace(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, fitted: []f64) -> err {
    ret boost(a, 4usize, x, y, n, p, ntrees, shrinkage, depth, minobs, 0.5f64, fitted)
}

