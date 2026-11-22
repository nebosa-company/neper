// R klaR: NaiveBayes with Gaussian class-conditional densities (usekernel = FALSE) and its predict: priors are the class frequencies, each
// variable has a per-class mean and (n - 1) standard deviation, a density of exactly 0 is replaced by threshold, and the posterior is the
// normalised exp of log prior plus the summed log densities.
//
// The mixed fit (nb_fit_mixed) adds factor predictors: a factor column is given as 0-based level codes and
// its table is klaR's LaplaceEst(table(grouping, var), f = 0), the count of the class and level divided by
// the class count, which predict reads as a probability and thresholds when it is 0.
//
// Not here: kernel densities, logical predictors, the Laplace smoothing fL, rda, woe, stepclass, greedy.wilks and the plots.

use e.math
use e.math.dist as dist
use e.mem

// x is n by p row-major; is_factor[c] marks a column of 0-based level codes and maxlev bounds their count;
// fprob is p by k by maxlev (a factor column's class-conditional level probabilities, row-major by column,
// class, level); mean and sd are k by p, prior k
fn nb_fit_mixed(x: []const f64, n: usize, p: usize, labels: []const usize, k: usize, is_factor: []const bool, maxlev: usize, prior: []f64, mean: []f64, sd: []f64, fprob: []f64) {
    var cnt: [16]f64 = zero
    var j = 0usize
    while j < k {
        cnt[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < k * p {
        mean[j] = 0.0f64
        sd[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p * k * maxlev {
        fprob[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        let cls = labels[i] - 1usize
        cnt[cls] += 1.0f64
        var c = 0usize
        while c < p {
            if is_factor[c] {
                let lev = usize(x[i * p + c])
                if lev < maxlev { fprob[c * k * maxlev + cls * maxlev + lev] += 1.0f64 }
            } else {
                mean[cls * p + c] += x[i * p + c]
            }
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        prior[j] = cnt[j] / f64(n)
        j += 1usize
    }
    j = 0usize
    while j < k {
        var c = 0usize
        while c < p {
            if !is_factor[c] { mean[j * p + c] = mean[j * p + c] / cnt[j] }
            c += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        let cls = labels[i] - 1usize
        var c = 0usize
        while c < p {
            if !is_factor[c] {
                let d = x[i * p + c] - mean[cls * p + c]
                sd[cls * p + c] += d * d
            }
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        var c = 0usize
        while c < p {
            if !is_factor[c] { sd[j * p + c] = math.sqrt[f64](sd[j * p + c] / (cnt[j] - 1.0f64)) }
            c += 1usize
        }
        j += 1usize
    }
    // LaplaceEst(table(grouping, var), f = 0): each class-and-level count over its class count
    var c = 0usize
    while c < p {
        if is_factor[c] {
            var cls = 0usize
            while cls < k {
                if cnt[cls] > 0.0f64 {
                    var lev = 0usize
                    while lev < maxlev {
                        fprob[c * k * maxlev + cls * maxlev + lev] = fprob[c * k * maxlev + cls * maxlev + lev] / cnt[cls]
                        lev += 1usize
                    }
                }
                cls += 1usize
            }
        }
        c += 1usize
    }
}

// klaR::woe for one factor variable (0-based level codes) against a binary target (labels 1 and 2): each
// level's weight of evidence is the log of its share of class 1 over its share of class 2, every empty
// class-and-level cell is raised to zeroadj first, and the last value of out is the information value, the
// sum over levels of the share difference times the woe. out holds nlev + 1 values; the caller supplies a
// 2 by nlev scratch in counts (row 0 for class 1, row 1 for class 2).
fn woe_counts(codes: []const usize, n: usize, labels: []const usize, nlev: usize, zeroadj: f64, counts: []f64, out: []f64) -> err {
    if counts.len < nlev * 2usize || out.len < nlev + 1usize { ret mem.Full }
    var lev = 0usize
    while lev < nlev * 2usize {
        counts[lev] = 0.0f64
        lev += 1usize
    }
    var i = 0usize
    while i < n {
        let cls = labels[i]
        if cls >= 1usize && cls <= 2usize && codes[i] < nlev {
            counts[(cls - 1usize) * nlev + codes[i]] += 1.0f64
        }
        i += 1usize
    }
    // klaR raises every empty cell to zeroadj before the class totals are taken
    lev = 0usize
    while lev < nlev * 2usize {
        if counts[lev] == 0.0f64 { counts[lev] = zeroadj }
        lev += 1usize
    }
    var fy0 = 0.0f64
    var fy1 = 0.0f64
    lev = 0usize
    while lev < nlev {
        fy0 += counts[lev]
        fy1 += counts[nlev + lev]
        lev += 1usize
    }
    var iv = 0.0f64
    lev = 0usize
    while lev < nlev {
        let r0 = counts[lev] / fy0
        let r1 = counts[nlev + lev] / fy1
        let s = math.log[f64](r0 / r1)
        out[lev] = s
        iv += (r0 - r1) * s
        lev += 1usize
    }
    out[nlev] = iv
    ret ok
}

// the posterior of one observation over the k classes into post, and the predicted class (1-based), with
// numeric columns read through mean and sd and factor columns through fprob
fn nb_predict_mixed(row: []const f64, p: usize, k: usize, prior: []const f64, mean: []const f64, sd: []const f64, fprob: []const f64, is_factor: []const bool, maxlev: usize, threshold: f64, post: []f64) -> usize {
    var best = 0usize
    var j = 0usize
    while j < k {
        var l = math.log[f64](prior[j])
        var c = 0usize
        while c < p {
            var d = 0.0f64
            if is_factor[c] {
                let lev = usize(row[c])
                if lev < maxlev { d = fprob[c * k * maxlev + j * maxlev + lev] }
            } else {
                d = dist.dnorm(row[c], mean[j * p + c], sd[j * p + c], false)
            }
            if d == 0.0f64 { d = threshold }
            l += math.log[f64](d)
            c += 1usize
        }
        post[j] = l
        if j == 0usize || l > post[best] { best = j }
        j += 1usize
    }
    var tot = 0.0f64
    j = 0usize
    while j < k {
        post[j] = math.exp[f64](post[j])
        tot += post[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        post[j] = post[j] / tot
        j += 1usize
    }
    ret best + 1usize
}

// x is n by p row-major, labels 1..k; mean and sd are k by p, prior k
fn nb_fit(x: []const f64, n: usize, p: usize, labels: []const usize, k: usize, prior: []f64, mean: []f64, sd: []f64) {
    var cnt: [16]f64 = zero
    var j = 0usize
    while j < k {
        cnt[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < k * p {
        mean[j] = 0.0f64
        sd[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[labels[i] - 1usize] += 1.0f64
        var c = 0usize
        while c < p {
            mean[(labels[i] - 1usize) * p + c] += x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        prior[j] = cnt[j] / f64(n)
        var c = 0usize
        while c < p {
            mean[j * p + c] = mean[j * p + c] / cnt[j]
            c += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            let d = x[i * p + c] - mean[(labels[i] - 1usize) * p + c]
            sd[(labels[i] - 1usize) * p + c] += d * d
            c += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        var c = 0usize
        while c < p {
            sd[j * p + c] = math.sqrt[f64](sd[j * p + c] / (cnt[j] - 1.0f64))
            c += 1usize
        }
        j += 1usize
    }
}

// the posterior of one observation (p values) over the k classes into post, and the predicted class (1-based)
fn nb_predict(row: []const f64, p: usize, k: usize, prior: []const f64, mean: []const f64, sd: []const f64, threshold: f64, post: []f64) -> usize {
    var best = 0usize
    var j = 0usize
    while j < k {
        var l = math.log[f64](prior[j])
        var c = 0usize
        while c < p {
            var d = dist.dnorm(row[c], mean[j * p + c], sd[j * p + c], false)
            if d == 0.0f64 { d = threshold }
            l += math.log[f64](d)
            c += 1usize
        }
        post[j] = l
        if j == 0usize || l > post[best] { best = j }
        j += 1usize
    }
    var tot = 0.0f64
    j = 0usize
    while j < k {
        post[j] = math.exp[f64](post[j])
        tot += post[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        post[j] = post[j] / tot
        j += 1usize
    }
    ret best + 1usize
}
