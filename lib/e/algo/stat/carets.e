// R caret, the evaluation statistics: `confusion2` (confusionMatrix of a two-class table with the first level as the
// positive class: accuracy with its exact Clopper-Pearson interval, kappa, the no-information rate and its one-sided
// binomial p value, McNemar's p value, sensitivity, specificity, predictive values, F1, prevalence, detection rate and
// prevalence, balanced accuracy) and `post_resample` (RMSE, R squared as the squared correlation, MAE).
//
// Not here: multi-class tables, the `prevalence` argument, createDataPartition and the resampling indices,
// preProcess, varImp.

use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.rand.r as rng
use e.mem

type Conf = struct { accuracy: f64, kappa: f64, lower: f64, upper: f64, nir: f64, pvalue: f64, mcnemar: f64, sens: f64, spec: f64, ppv: f64, npv: f64, f1: f64, prevalence: f64, detection_rate: f64, detection_prevalence: f64, balanced: f64 }

// tp: predicted and actual positive; fp: predicted positive, actually negative; fnn: predicted negative, actually positive
fn confusion2(tp: f64, fp: f64, fnn: f64, tn: f64, level: f64) -> Conf {
    var c: Conf = zero
    let n = tp + fp + fnn + tn
    let x = tp + tn
    c.accuracy = x / n
    let po = c.accuracy
    let pe = ((tp + fp) * (tp + fnn) + (fnn + tn) * (fp + tn)) / (n * n)
    c.kappa = (po - pe) / (1.0f64 - pe)
    let alpha = 1.0f64 - level
    if x == 0.0f64 { c.lower = 0.0f64 } else { c.lower = nb.qbeta(alpha / 2.0f64, x, n - x + 1.0f64, true, false) }
    if x == n { c.upper = 1.0f64 } else { c.upper = nb.qbeta(1.0f64 - alpha / 2.0f64, x + 1.0f64, n - x, true, false) }
    var big = tp + fnn
    if fp + tn > big { big = fp + tn }
    c.nir = big / n
    // binom.test(x, n, p = nir, alternative = "greater"): P(X >= x)
    c.pvalue = nb.pbinom(x - 1.0f64, n, c.nir, false, false)
    let d = math.abs[f64](fp - fnn) - 1.0f64
    if fp + fnn == 0.0f64 {
        c.mcnemar = 1.0f64 / 0.0f64 - 1.0f64 / 0.0f64
    } else {
        c.mcnemar = nm.pchisq(d * d / (fp + fnn), 1.0f64, false, false)
    }
    c.sens = tp / (tp + fnn)
    c.spec = tn / (fp + tn)
    c.ppv = tp / (tp + fp)
    c.npv = tn / (fnn + tn)
    c.f1 = 2.0f64 * c.ppv * c.sens / (c.ppv + c.sens)
    c.prevalence = (tp + fnn) / n
    c.detection_rate = tp / n
    c.detection_prevalence = (tp + fp) / n
    c.balanced = (c.sens + c.spec) / 2.0f64
    ret c
}

// postResample(pred, obs): (RMSE, R squared, MAE)
fn post_resample(pred: []const f64, obs: []const f64) -> (f64, f64, f64) {
    let n = f64(pred.len)
    var mp = 0.0f64
    var mo = 0.0f64
    var i = 0usize
    while i < pred.len {
        mp += pred[i]
        mo += obs[i]
        i += 1usize
    }
    mp = mp / n
    mo = mo / n
    var se = 0.0f64
    var ae = 0.0f64
    var spp = 0.0f64
    var soo = 0.0f64
    var spo = 0.0f64
    i = 0usize
    while i < pred.len {
        let d = pred[i] - obs[i]
        se += d * d
        ae += math.abs[f64](d)
        spp += (pred[i] - mp) * (pred[i] - mp)
        soo += (obs[i] - mo) * (obs[i] - mo)
        spo += (pred[i] - mp) * (obs[i] - mo)
        i += 1usize
    }
    ret (math.sqrt[f64](se / n), spo * spo / (spp * soo), ae / n)
}

// ---- the resampling indices of caret, drawing with R's sample.int ----

// createResample(y, times = 1): one bootstrap sample of the n positions, sorted (1-based)
fn create_resample(a: *mem.Arena, r: *rng.Rng, n: usize, out: []i64) -> err {
    let (s, e) = rng.sample_int(a, r, i64(n), i64(n), true)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        out[i] = s[i]
        i += 1usize
    }
    var j = 1usize
    while j < n {
        let key = out[j]
        var q = j
        while q > 0usize && out[q - 1usize] > key {
            out[q] = out[q - 1usize]
            q -= 1usize
        }
        out[q] = key
        j += 1usize
    }
    ret ok
}

// createFolds(y, k, list = FALSE) for a factor y given as class codes 0.. in the order of its levels: the fold (1-based) of every observation
fn create_folds(a: *mem.Arena, r: *rng.Rng, cls: []const i64, k: usize, fold: []i64) -> err {
    let n = cls.len
    var i = 0usize
    if k >= n {
        while i < n {
            fold[i] = i64(i + 1usize)
            i += 1usize
        }
        ret ok
    }
    var m = 0i64
    while i < n {
        if cls[i] + 1i64 > m { m = cls[i] + 1i64 }
        fold[i] = 0i64
        i += 1usize
    }
    var c = 0i64
    while c < m {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if cls[i] == c { cnt += 1usize }
            i += 1usize
        }
        if cnt > 0usize {
            let minr = cnt / k
            let (seqv, e1) = mem.alloc[i64](a, cnt)
            if e1 != ok { ret e1 }
            if minr > 0usize {
                let spares = cnt % k
                var q = 0usize
                while q < minr * k {
                    seqv[q] = i64(q % k + 1usize)
                    q += 1usize
                }
                if spares > 0usize {
                    let (sp, e2) = rng.sample_int(a, r, i64(k), i64(spares), false)
                    if e2 != ok { ret e2 }
                    var t = 0usize
                    while t < spares {
                        seqv[minr * k + t] = sp[t]
                        t += 1usize
                    }
                }
                let (perm, e3) = rng.sample_int(a, r, i64(cnt), i64(cnt), false)
                if e3 != ok { ret e3 }
                var at = 0usize
                i = 0usize
                while i < n {
                    if cls[i] == c {
                        fold[i] = seqv[usize(perm[at] - 1i64)]
                        at += 1usize
                    }
                    i += 1usize
                }
            } else {
                let (sp, e4) = rng.sample_int(a, r, i64(k), i64(cnt), false)
                if e4 != ok { ret e4 }
                var at = 0usize
                i = 0usize
                while i < n {
                    if cls[i] == c {
                        fold[i] = sp[at]
                        at += 1usize
                    }
                    i += 1usize
                }
            }
        }
        c += 1i64
    }
    ret ok
}

// groupKFold(group, k): each group (a code 0.. in order of first appearance, m groups) goes to one of k folds drawn with replacement; the test fold of every observation (1-based)
fn group_kfold(a: *mem.Arena, r: *rng.Rng, grp: []const i64, m: usize, k: usize, fold: []i64) -> err {
    let (gf, e) = rng.sample_int(a, r, i64(k), i64(m), true)
    if e != ok { ret e }
    var i = 0usize
    while i < grp.len {
        fold[i] = gf[usize(grp[i])]
        i += 1usize
    }
    ret ok
}

// createTimeSlices(y, initialWindow, horizon, fixedWindow, skip): the number of slices, and for slice s (0-based) the 1-based training start and stop and test start and stop in out[4 s ..]
fn create_time_slices(n: usize, initial: usize, horizon: usize, fixed: bool, skip: usize, out: []i64) -> usize {
    var cnt = 0usize
    var stop = initial
    while stop + horizon <= n {
        var start = 1usize
        if fixed { start = stop - initial + 1usize }
        out[4usize * cnt] = i64(start)
        out[4usize * cnt + 1usize] = i64(stop)
        out[4usize * cnt + 2usize] = i64(stop + 1usize)
        out[4usize * cnt + 3usize] = i64(stop + horizon)
        cnt += 1usize
        stop += skip + 1usize
    }
    ret cnt
}

// createDataPartition(y, times = 1, p, groups): a stratified draw of ceiling(p n_g) of the n_g observations of each stratum (a class, or for a numeric y the quantile bin of
// cut(y, unique(quantile(y, seq(0, 1, length.out = groups))), include.lowest = TRUE)); `cls` holds the class codes in level order when `numeric` is false, else the values;
// mask[i] is 1 when observation i is selected
fn create_data_partition(a: *mem.Arena, r: *rng.Rng, y: []const f64, numeric: bool, p: f64, groups0: usize, mask: []i64) -> err {
    let n = y.len
    var groups = groups0
    if groups < 2usize { groups = 2usize }
    let (code, e0) = mem.alloc[i64](a, n)
    if e0 != ok { ret e0 }
    var i = 0usize
    var m = 0i64
    if numeric {
        let (xs, e1) = mem.alloc[f64](a, n)
        let (br, e2) = mem.alloc[f64](a, groups)
        if e1 != ok || e2 != ok { ret mem.Full }
        i = 0usize
        while i < n {
            xs[i] = y[i]
            i += 1usize
        }
        i = 1usize
        while i < n {
            let key = xs[i]
            var j = i
            while j > 0usize && xs[j - 1usize] > key {
                xs[j] = xs[j - 1usize]
                j -= 1usize
            }
            xs[j] = key
            i += 1usize
        }
        var nbr = 0usize
        let by = 1.0f64 / f64(groups - 1usize)
        var q = 0usize
        while q < groups {
            var pr = f64(q) * by
            if q == groups - 1usize { pr = 1.0f64 }
            let index = 1.0f64 + f64(n - 1usize) * pr
            let lo = math.floor[f64](index)
            let hi = math.ceil[f64](index)
            var v = xs[usize(lo) - 1usize]
            let xh = xs[usize(hi) - 1usize]
            if index > lo && xh != v {
                let h = index - lo
                v = (1.0f64 - h) * v + h * xh
            }
            if nbr == 0usize || v != br[nbr - 1usize] {
                br[nbr] = v
                nbr += 1usize
            }
            q += 1usize
        }
        i = 0usize
        while i < n {
            var b = 0usize
            while b + 2usize < nbr && y[i] > br[b + 1usize] { b += 1usize }
            code[i] = i64(b)
            i += 1usize
        }
        m = i64(nbr)
    } else {
        i = 0usize
        while i < n {
            code[i] = i64(y[i])
            if code[i] + 1i64 > m { m = code[i] + 1i64 }
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        mask[i] = 0i64
        i += 1usize
    }
    var c = 0i64
    while c < m {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if code[i] == c { cnt += 1usize }
            i += 1usize
        }
        if cnt == 1usize {
            i = 0usize
            while i < n {
                if code[i] == c { mask[i] = 1i64 }
                i += 1usize
            }
        } else if cnt > 1usize {
            let num = usize(math.ceil[f64](f64(cnt) * p))
            let (sp, e3) = rng.sample_int(a, r, i64(cnt), i64(num), false)
            if e3 != ok { ret e3 }
            let (pos, e4) = mem.alloc[usize](a, cnt)
            if e4 != ok { ret e4 }
            var at = 0usize
            i = 0usize
            while i < n {
                if code[i] == c {
                    pos[at] = i
                    at += 1usize
                }
                i += 1usize
            }
            var t = 0usize
            while t < num {
                mask[pos[usize(sp[t] - 1i64)]] = 1i64
                t += 1usize
            }
        }
        c += 1i64
    }
    ret ok
}

// ---- preProcess: center, scale and range, per column of the n by p column-major matrix x ----

fn pp_sum(v: []const f64) -> f64 {
    var total = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let t = total + v[i]
        if math.abs[f64](total) >= math.abs[f64](v[i]) { comp += (total - t) + v[i] } else { comp += (v[i] - t) + total }
        total = t
        i += 1usize
    }
    ret total + comp
}

// R's mean(): the sum over n, refined by the mean of the residuals
fn pp_mean(v: []const f64) -> f64 {
    let n = f64(v.len)
    let m = pp_sum(v) / n
    var t = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let d = v[i] - m
        let u = t + d
        if math.abs[f64](t) >= math.abs[f64](d) { comp += (t - u) + d } else { comp += (d - u) + t }
        t = u
        i += 1usize
    }
    ret m + (t + comp) / n
}

fn pp_sd(v: []const f64) -> f64 {
    let m = pp_mean(v)
    var t = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let d = (v[i] - m) * (v[i] - m)
        let u = t + d
        if math.abs[f64](t) >= math.abs[f64](d) { comp += (t - u) + d } else { comp += (d - u) + t }
        t = u
        i += 1usize
    }
    ret math.sqrt[f64]((t + comp) / f64(v.len - 1usize))
}

// preProcess(x, method = c("center", "scale")) then predict: center subtracts the column mean, scale divides by the column standard deviation (after centering when both)
fn pre_process_cs(x: []const f64, n: usize, p: usize, center: bool, scale: bool, out: []f64) {
    var c = 0usize
    while c < p {
        let col = x[c * n..c * n + n]
        let m = pp_mean(col)
        let sd = pp_sd(col)
        var i = 0usize
        while i < n {
            var v = col[i]
            if center { v = v - m }
            if scale { v = v / sd }
            out[c * n + i] = v
            i += 1usize
        }
        c += 1usize
    }
}

// preProcess(x, method = "range", rangeBounds = c(lo, hi))
fn pre_process_range(x: []const f64, n: usize, p: usize, lo: f64, hi: f64, out: []f64) {
    var c = 0usize
    while c < p {
        var mn = x[c * n]
        var mx = x[c * n]
        var i = 1usize
        while i < n {
            if x[c * n + i] < mn { mn = x[c * n + i] }
            if x[c * n + i] > mx { mx = x[c * n + i] }
            i += 1usize
        }
        i = 0usize
        while i < n {
            out[c * n + i] = (x[c * n + i] - mn) / (mx - mn) * (hi - lo) + lo
            i += 1usize
        }
        c += 1usize
    }
}

// confusionMatrix of a k-class table (rows the prediction, columns the reference; x[col * k + row]): out[0..7] are Accuracy, Kappa, AccuracyLower, AccuracyUpper, AccuracyNull, AccuracyPValue, McnemarPValue (Bowker's test),
// then for each class eleven values: Sensitivity, Specificity, Pos Pred Value, Neg Pred Value, Precision, Recall, F1, Prevalence, Detection Rate, Detection Prevalence, Balanced Accuracy
fn confusion_multi(x: []const f64, k: usize, out: []f64) {
    var n = 0.0f64
    var diag = 0.0f64
    var i = 0usize
    while i < k * k {
        n += x[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        diag += x[i * k + i]
        i += 1usize
    }
    var pe = 0.0f64
    var big = 0.0f64
    i = 0usize
    while i < k {
        var rs = 0.0f64
        var cs = 0.0f64
        var j = 0usize
        while j < k {
            rs += x[j * k + i]
            cs += x[i * k + j]
            j += 1usize
        }
        pe += rs * cs / (n * n)
        if cs > big { big = cs }
        i += 1usize
    }
    let po = diag / n
    out[0usize] = po
    out[1usize] = (po - pe) / (1.0f64 - pe)
    if diag == 0.0f64 { out[2usize] = 0.0f64 } else { out[2usize] = nb.qbeta(0.025f64, diag, n - diag + 1.0f64, true, false) }
    if diag == n { out[3usize] = 1.0f64 } else { out[3usize] = nb.qbeta(0.975f64, diag + 1.0f64, n - diag, true, false) }
    out[4usize] = big / n
    out[5usize] = nb.pbinom(diag - 1.0f64, n, big / n, false, false)
    var st = 0.0f64
    i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            let u = x[j * k + i]
            let l = x[i * k + j]
            st += (u - l) * (u - l) / (u + l)
            j += 1usize
        }
        i += 1usize
    }
    out[6usize] = nm.pchisq(st, f64(k * (k - 1usize) / 2usize), false, false)
    var c = 0usize
    while c < k {
        let tp = x[c * k + c]
        var rowp = 0.0f64
        var colp = 0.0f64
        var tn = 0.0f64
        var negref = 0.0f64
        i = 0usize
        while i < k {
            rowp += x[i * k + c]
            colp += x[c * k + i]
            if i != c {
                var j = 0usize
                while j < k {
                    if j != c { tn += x[j * k + i] }
                    j += 1usize
                }
            }
            i += 1usize
        }
        negref = n - colp
        let sens = tp / colp
        let spec = tn / negref
        let ppv = tp / rowp
        let rest = n - rowp
        let npv = tn / rest
        let o = 7usize + c * 11usize
        out[o] = sens
        out[o + 1usize] = spec
        out[o + 2usize] = ppv
        out[o + 3usize] = npv
        out[o + 4usize] = ppv
        out[o + 5usize] = sens
        out[o + 6usize] = 2.0f64 * ppv * sens / (ppv + sens)
        out[o + 7usize] = colp / n
        out[o + 8usize] = tp / n
        out[o + 9usize] = rowp / n
        out[o + 10usize] = (sens + spec) / 2.0f64
        c += 1usize
    }
}
