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
use e.algo.stat.ica as ica
use e.algo.linalg.decomp as decomp
use e.algo.stat.bayesmpkg as bz
use e.algo.stat.fdrtool as fd
use e.algo.stat.mass as ms

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

fn pp_var(v: []const f64) -> f64 {
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
    ret (t + comp) / f64(v.len - 1usize)
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

// BoxCoxTrans(y): the lambda of MASS::boxcox on the grid seq(-2, 2, 1/10) for y ~ 1, the first maximiser; NaN when y has a non-positive value or fewer than three distinct values
fn box_cox_lambda(a: *mem.Arena, y: []const f64) -> f64 {
    let n = y.len
    var uniq = 0usize
    var i = 0usize
    while i < n {
        if y[i] <= 0.0f64 { ret 0.0f64 / 0.0f64 }
        var seen = false
        var j = 0usize
        while j < i {
            if y[j] == y[i] { seen = true }
            j += 1usize
        }
        if !seen { uniq += 1usize }
        i += 1usize
    }
    if uniq < 3usize { ret 0.0f64 / 0.0f64 }
    let (ones, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        ones[i] = 1.0f64
        i += 1usize
    }
    var best = 0.0f64 - 1.0e300f64
    var lam = 0.0f64
    var g = 0usize
    while g <= 40usize {
        let l = 0.0f64 - 2.0f64 + f64(g) * 0.1f64
        let (ll, e2) = ms.boxcox_loglik(a, y, ones, 1usize, l)
        if e2 == ok && ll > best {
            best = ll
            lam = l
        }
        g += 1usize
    }
    ret lam
}

// predict(BoxCoxTrans, x) with fudge 0.2: log inside the fudge of 0, the identity inside the fudge of 1, else (x^lambda - 1) / lambda; NaN lambda leaves x unchanged
fn box_cox_apply(x: f64, lambda: f64) -> f64 {
    if lambda != lambda { ret x }
    if lambda < 0.2f64 && lambda > 0.0f64 - 0.2f64 { ret math.log[f64](x) }
    if lambda < 1.2f64 && lambda > 0.8f64 { ret x }
    ret (math.pow[f64](x, lambda) - 1.0f64) / lambda
}

// ---- preProcess YeoJohnson: recipes::estimate_yj as caret calls it (optimize of the profile log likelihood over (-3, 3), tol 1e-4, at least three distinct values) and the transform ----

fn yj_value(x: f64, lambda: f64) -> f64 {
    if x >= 0.0f64 {
        if math.abs[f64](lambda) < 0.001f64 { ret math.log[f64](x + 1.0f64) }
        ret (math.pow[f64](x + 1.0f64, lambda) - 1.0f64) / lambda
    }
    if math.abs[f64](lambda - 2.0f64) < 0.001f64 { ret 0.0f64 - math.log[f64](0.0f64 - x + 1.0f64) }
    ret 0.0f64 - (math.pow[f64](0.0f64 - x + 1.0f64, 2.0f64 - lambda) - 1.0f64) / (2.0f64 - lambda)
}

type Yj = struct { dat: []const f64, tmp: []f64, cst: f64 }

fn yj_negll(c: *Yj, lam: f64) -> f64 {
    let n = c.dat.len
    var i = 0usize
    while i < n {
        c.tmp[i] = yj_value(c.dat[i], lam)
        i += 1usize
    }
    let vt = pp_var(c.tmp[0usize..n]) * f64(n - 1usize) / f64(n)
    ret 0.0f64 - (0.0f64 - 0.5f64 * f64(n) * math.log[f64](vt) + (lam - 1.0f64) * c.cst)
}

// the lambda recipes::estimate_yj finds for the sample dat, NaN when it has fewer than three distinct values or lands within 0.001 of a limit
fn yeo_johnson_lambda(a: *mem.Arena, dat: []const f64) -> f64 {
    let n = dat.len
    var uniq = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < i {
            if dat[j] == dat[i] { seen = true }
            j += 1usize
        }
        if !seen { uniq += 1usize }
        i += 1usize
    }
    if uniq < 3usize { ret 0.0f64 / 0.0f64 }
    let (tmp, e) = mem.alloc[f64](a, n)
    let (cs, e2) = mem.alloc[f64](a, n)
    if e != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        var sg = 0.0f64
        if dat[i] > 0.0f64 { sg = 1.0f64 } else if dat[i] < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        cs[i] = sg * math.log[f64](math.abs[f64](dat[i]) + 1.0f64)
        i += 1usize
    }
    var ctx = Yj{ dat: dat, tmp: tmp, cst: pp_sum(cs) }
    let lam = fd.brent_min_tol[Yj](&ctx, yj_negll, 0.0f64 - 3.0f64, 3.0f64, 1.0e-4f64)
    if math.abs[f64](0.0f64 - 3.0f64 - lam) <= 0.001f64 || math.abs[f64](3.0f64 - lam) <= 0.001f64 { ret 0.0f64 / 0.0f64 }
    ret lam
}

// varImp(lm): the absolute t value of each coefficient but the intercept, for the n by p column-major design x (the intercept first) and the response y; out[0 .. p - 1] for columns 1 .. p
fn var_imp_lm(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, out: []f64) -> err {
    let (f, fe) = decomp.lm_fit(a, x, n, p, y, 1.0e-7f64)
    if fe != ok { ret fe }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.residuals[i] * f.residuals[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (u, e2) = mem.alloc[f64](a, p * p)
    let (ui, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sv = 0.0f64
            i = 0usize
            while i < n {
                sv += x[c * n + i] * x[c2 * n + i]
                i += 1usize
            }
            xtx[c2 * p + c] = sv
            c2 += 1usize
        }
        c += 1usize
    }
    if !bz.chol_upper(xtx, p, u) { ret mem.Full }
    bz.inv_upper(u, p, ui)
    c = 1usize
    while c < p {
        // (X'X)^-1 [c, c] = sum over r of ui[r, c]^2
        var d = 0.0f64
        var r = 0usize
        while r < p {
            d += ui[r * p + c] * ui[r * p + c]
            r += 1usize
        }
        out[c - 1usize] = math.abs[f64](f.coef[c] / math.sqrt[f64](s2 * d))
        c += 1usize
    }
    ret ok
}

// preProcess(method = "pca", thresh): the columns of x (n by p, column-major) standardised and projected on the leading principal components of their correlation matrix, the number of components
// being the first whose cumulative variance share reaches thresh (at least two, all of them when none does); sdev (p values) and scores (n by k, column-major, each column up to sign) are filled and k returned
fn pre_process_pca(a: *mem.Arena, x: []const f64, n: usize, p: usize, thresh: f64, sdev: []f64, scores: []f64) -> usize {
    let (z, e1) = mem.alloc[f64](a, n * p)
    let (cm, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret 0usize }
    pre_process_cs(x, n, p, true, true, z)
    var c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += z[c * n + i] * z[c2 * n + i]
                i += 1usize
            }
            cm[c2 * p + c] = s / f64(n - 1usize)
            c2 += 1usize
        }
        c += 1usize
    }
    let (ev, vecs, ee) = ica.eigen_sym(a, cm, p)
    if ee != ok { ret 0usize }
    var tot = 0.0f64
    c = 0usize
    while c < p {
        sdev[c] = math.sqrt[f64](ev[c])
        tot += ev[c]
        c += 1usize
    }
    var k = p
    var cum = 0.0f64
    var found = false
    c = 0usize
    while c < p && !found {
        cum += ev[c] / tot
        if cum >= thresh {
            k = c + 1usize
            found = true
        }
        c += 1usize
    }
    if found && k < 2usize { k = 2usize }
    c = 0usize
    while c < k {
        var i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                s += z[j * n + i] * vecs[j * p + c]
                j += 1usize
            }
            scores[c * n + i] = s
            i += 1usize
        }
        c += 1usize
    }
    ret k
}

// confusionMatrix(prevalence = prev): the predictive values re-derived from the sensitivity and specificity at the given prevalence (Bayes' rule); the other statistics, the precision and the F1 keep their observed values. out = (ppv, npv, prevalence)
fn with_prevalence(sens: f64, spec: f64, prev: f64, out: []f64) {
    out[0usize] = sens * prev / (sens * prev + (1.0f64 - spec) * (1.0f64 - prev))
    out[1usize] = spec * (1.0f64 - prev) / ((1.0f64 - sens) * prev + spec * (1.0f64 - prev))
    out[2usize] = prev
}

// caret preProcess(method = "knnImpute", k) then predict: the columns are centred and scaled with the mean and sd of their observed values (NaN marks a missing value); a row with missing values takes, for each missing column, the mean over its k
// nearest complete rows (Euclidean distance on the columns the row has, ties by row order) of that column in the scaled data; out is the n by p scaled and imputed matrix, column-major
fn knn_impute(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, out: []f64) -> err {
    let (mu, e1) = mem.alloc[f64](a, p)
    let (sd, e2) = mem.alloc[f64](a, p)
    let (cc, e3) = mem.alloc[bool](a, n)
    let (dd, e4) = mem.alloc[f64](a, n)
    let (ix, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var c = 0.0f64
        var i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] {
                s += x[j * n + i]
                c += 1.0f64
            }
            i += 1usize
        }
        mu[j] = s / c
        var v = 0.0f64
        i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] { v += (x[j * n + i] - mu[j]) * (x[j * n + i] - mu[j]) }
            i += 1usize
        }
        sd[j] = math.sqrt[f64](v / (c - 1.0f64))
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var full = true
        j = 0usize
        while j < p {
            out[j * n + i] = (x[j * n + i] - mu[j]) / sd[j]
            if x[j * n + i] != x[j * n + i] { full = false }
            j += 1usize
        }
        cc[i] = full
        i += 1usize
    }
    i = 0usize
    while i < n {
        if !cc[i] {
            var q = 0usize
            while q < n {
                dd[q] = 1.0e300f64
                ix[q] = q
                if cc[q] {
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        if x[j * n + i] == x[j * n + i] {
                            let d = out[j * n + q] - out[j * n + i]
                            s += d * d
                        }
                        j += 1usize
                    }
                    dd[q] = s
                }
                q += 1usize
            }
            // the k smallest distances, a stable selection by (distance, row)
            var t = 0usize
            while t < k {
                var best = n
                q = 0usize
                while q < n {
                    if dd[q] < 1.0e299f64 && (best == n || dd[q] < dd[best]) { best = q }
                    q += 1usize
                }
                if best == n { break }
                ix[t] = best
                dd[best] = 1.0e300f64
                t += 1usize
            }
            j = 0usize
            while j < p {
                if x[j * n + i] != x[j * n + i] {
                    var s = 0.0f64
                    var u = 0usize
                    while u < t {
                        s += out[j * n + ix[u]]
                        u += 1usize
                    }
                    out[j * n + i] = s / f64(t)
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// varImp(glm(family = binomial)): the absolute z value of each coefficient but the intercept, from glm.fit's iteratively reweighted least squares on the n by p column-major design x (intercept first) and the 0 / 1 response y: the start mu = (y + 0.5) / 2,
// the working response and weights from the current linear predictor, the stop when the relative change of the deviance falls below 1e-8 (at most 25 iterations), and the covariance (X' W X)^-1 taken with the weights of the last iteration, as summary.glm reports it;
// out[0 .. p - 2] for columns 1 .. p - 1
fn var_imp_logit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (xtwx, e2) = mem.alloc[f64](a, p * p)
    let (u, e3) = mem.alloc[f64](a, p * p)
    let (iu, e4) = mem.alloc[f64](a, p * p)
    let (g, e5) = mem.alloc[f64](a, p)
    let (eta, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        let mu0 = (y[i] + 0.5f64) / 2.0f64
        eta[i] = math.log[f64](mu0 / (1.0f64 - mu0))
        i += 1usize
    }
    var devold = 0.0f64
    var it = 0usize
    while it < 25usize {
        var j = 0usize
        while j < p {
            g[j] = 0.0f64
            var k = 0usize
            while k < p {
                xtwx[k * p + j] = 0.0f64
                k += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < n {
            let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
            let w = mu * (1.0f64 - mu)
            let z = eta[i] + (y[i] - mu) / w
            j = 0usize
            while j < p {
                g[j] += w * x[j * n + i] * z
                var k = 0usize
                while k < p {
                    xtwx[k * p + j] += w * x[j * n + i] * x[k * n + i]
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        if !bz.chol_upper(xtwx, p, u) { ret mem.Full }
        bz.inv_upper(u, p, iu)
        j = 0usize
        while j < p {
            var t = 0.0f64
            var q = j
            while q < p {
                var s2 = 0.0f64
                var r = 0usize
                while r <= q {
                    s2 += iu[q * p + r] * g[r]
                    r += 1usize
                }
                t += iu[q * p + j] * s2
                q += 1usize
            }
            beta[j] = t
            j += 1usize
        }
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var e = 0.0f64
            j = 0usize
            while j < p {
                e += x[j * n + i] * beta[j]
                j += 1usize
            }
            eta[i] = e
            let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e))
            var d = 0.0f64
            if y[i] > 0.0f64 { d += y[i] * math.log[f64](y[i] / mu) }
            if y[i] < 1.0f64 { d += (1.0f64 - y[i]) * math.log[f64]((1.0f64 - y[i]) / (1.0f64 - mu)) }
            dev += 2.0f64 * d
            i += 1usize
        }
        it += 1usize
        if it > 1usize && math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 { break }
        devold = dev
    }
    var j = 1usize
    while j < p {
        var v = 0.0f64
        var q = j
        while q < p {
            v += iu[q * p + j] * iu[q * p + j]
            q += 1usize
        }
        out[j - 1usize] = math.abs[f64](beta[j] / math.sqrt[f64](v))
        j += 1usize
    }
    ret ok
}

// C's %.{p}g of v into buf (returns the length): the digits of v rounded to p significant digits, fixed notation when the decimal exponent is in -4 .. p - 1, else d.ddde+XX, trailing zeros dropped
fn fmt_g(v: f64, p: usize, buf: []u8) -> usize {
    var n = 0usize
    if v == 0.0f64 {
        buf[0usize] = 48u8
        ret 1usize
    }
    var av = v
    if v < 0.0f64 {
        buf[0usize] = 45u8
        n = 1usize
        av = 0.0f64 - v
    }
    var x = i64(math.floor[f64](math.log10[f64](av)))
    var m = math.floor[f64](av / math.pow[f64](10.0f64, f64(x - i64(p) + 1i64)) + 0.5f64)
    if m >= math.pow[f64](10.0f64, f64(p)) {
        m = math.floor[f64](m / 10.0f64 + 0.5f64)
        x += 1i64
    }
    if m < math.pow[f64](10.0f64, f64(p) - 1.0f64) {
        x -= 1i64
        m = math.floor[f64](av / math.pow[f64](10.0f64, f64(x - i64(p) + 1i64)) + 0.5f64)
    }
    var dg: [20]u8 = zero
    var q = 0usize
    var mi = u64(m)
    while q < p {
        dg[p - 1usize - q] = u8(48u64 + mi % 10u64)
        mi = mi / 10u64
        q += 1usize
    }
    var nd = p
    while nd > 1usize && dg[nd - 1usize] == 48u8 { nd -= 1usize }
    if x >= -4i64 && x < i64(p) {
        if x >= 0i64 {
            var i = 0usize
            while i <= usize(x) {
                var ch = 48u8
                if i < p { ch = dg[i] }
                buf[n] = ch
                n += 1usize
                i += 1usize
            }
            if nd > usize(x) + 1usize {
                buf[n] = 46u8
                n += 1usize
                i = usize(x) + 1usize
                while i < nd {
                    buf[n] = dg[i]
                    n += 1usize
                    i += 1usize
                }
            }
        } else {
            buf[n] = 48u8
            buf[n + 1usize] = 46u8
            n += 2usize
            var z = 0i64
            while z < 0i64 - x - 1i64 {
                buf[n] = 48u8
                n += 1usize
                z += 1i64
            }
            var i2 = 0usize
            while i2 < nd {
                buf[n] = dg[i2]
                n += 1usize
                i2 += 1usize
            }
        }
        ret n
    }
    buf[n] = dg[0usize]
    n += 1usize
    if nd > 1usize {
        buf[n] = 46u8
        n += 1usize
        var i3 = 1usize
        while i3 < nd {
            buf[n] = dg[i3]
            n += 1usize
            i3 += 1usize
        }
    }
    buf[n] = 101u8
    n += 1usize
    var ex = x
    if ex < 0i64 {
        buf[n] = 45u8
        ex = 0i64 - ex
    } else {
        buf[n] = 43u8
    }
    n += 1usize
    var eu = u64(ex)
    if eu >= 100u64 {
        buf[n] = u8(48u64 + eu / 100u64)
        n += 1usize
    }
    buf[n] = u8(48u64 + (eu / 10u64) % 10u64)
    buf[n + 1usize] = u8(48u64 + eu % 10u64)
    n += 2usize
    ret n
}

// createFolds(y, k, list = FALSE) for a numeric y: the quantile cuts (floor(n / k) clamped to 2 .. 5 of them, type-7 quantiles, duplicates dropped), cut's interval labels ordered as strings (byte order, which is the order R sorts them in here), then the factor routine
fn create_folds_numeric(a: *mem.Arena, r: *rng.Rng, y: []const f64, k: usize, fold: []i64) -> err {
    let n = y.len
    var cuts = n / k
    if cuts < 2usize { cuts = 2usize }
    if cuts > 5usize { cuts = 5usize }
    let (s, e0) = mem.alloc[f64](a, n)
    let (br, e1) = mem.alloc[f64](a, cuts)
    let (cls, e2) = mem.alloc[i64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        s[i] = y[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    var nbr = 0usize
    var qi = 0usize
    while qi < cuts {
        let h = (f64(n) - 1.0f64) * f64(qi) / f64(cuts - 1usize)
        let lo = math.floor[f64](h)
        let hi = math.ceil[f64](h)
        var v = s[usize(lo)]
        if hi > lo { v = v + (h - lo) * (s[usize(hi)] - v) }
        if nbr == 0usize || v != br[nbr - 1usize] {
            br[nbr] = v
            nbr += 1usize
        }
        qi += 1usize
    }
    // the intervals (b[j-1], b[j]], the first including its lower end; labels from formatC(digits = dig) widened until the breaks are distinct
    let ni = nbr - 1usize
    var labs: [5][64]u8 = zero
    var lens: [5]usize = zero
    var dig = 3usize
    var ok2 = false
    while !ok2 && dig <= 12usize {
        var cb: [6][32]u8 = zero
        var cl: [6]usize = zero
        var j = 0usize
        while j < nbr {
            cl[j] = fmt_g(br[j], dig, cb[j][0usize..32usize])
            j += 1usize
        }
        ok2 = true
        j = 1usize
        while j < nbr {
            var same = cl[j] == cl[j - 1usize]
            if same {
                var q2 = 0usize
                while q2 < cl[j] {
                    if cb[j][q2] != cb[j - 1usize][q2] { same = false }
                    q2 += 1usize
                }
            }
            if same { ok2 = false }
            j += 1usize
        }
        if ok2 {
            j = 0usize
            while j < ni {
                var m = 0usize
                if j == 0usize { labs[j][0usize] = 91u8 } else { labs[j][0usize] = 40u8 }
                m = 1usize
                var q3 = 0usize
                while q3 < cl[j] {
                    labs[j][m] = cb[j][q3]
                    m += 1usize
                    q3 += 1usize
                }
                labs[j][m] = 44u8
                m += 1usize
                q3 = 0usize
                while q3 < cl[j + 1usize] {
                    labs[j][m] = cb[j + 1usize][q3]
                    m += 1usize
                    q3 += 1usize
                }
                labs[j][m] = 93u8
                m += 1usize
                lens[j] = m
                j += 1usize
            }
        } else {
            dig += 1usize
        }
    }
    // rank of each interval's label in byte order
    var rank: [5]i64 = zero
    var j2 = 0usize
    while j2 < ni {
        var rk = 0i64
        var j3 = 0usize
        while j3 < ni {
            if j3 != j2 {
                var less = false
                var decided = false
                var q4 = 0usize
                while !decided && q4 < lens[j3] && q4 < lens[j2] {
                    if labs[j3][q4] != labs[j2][q4] {
                        less = labs[j3][q4] < labs[j2][q4]
                        decided = true
                    }
                    q4 += 1usize
                }
                if !decided { less = lens[j3] < lens[j2] }
                if less { rk += 1i64 }
            }
            j3 += 1usize
        }
        rank[j2] = rk
        j2 += 1usize
    }
    i = 0usize
    while i < n {
        var iv = 0usize
        var j4 = 1usize
        while j4 < ni {
            if y[i] > br[j4] { iv = j4 }
            j4 += 1usize
        }
        cls[i] = rank[iv]
        i += 1usize
    }
    ret create_folds(a, r, cls, k, fold)
}
