// Model selection and preprocessing for the ML production core (L063): k-fold
// and stratified k-fold assignment, cross-validation and grid and random
// search over caller callbacks, and a preprocessing pipeline of imputation and
// scaling steps that is fitted on a training fold and applied to the test fold
// (statistics never leak).
//
// Folds are an assignment of every row to a fold number; `fold_rows` lists a
// fold's test rows and the rest are its training rows. Estimators are
// callbacks: `evaluate(ctx, train_rows, test_rows) -> f64` fits on the first
// list and scores on the second (higher is better), so any model in `e.ml.*`
// plugs in. NaN is a missing value for the pipeline.

use e.algo.rand
use e.math

type Step = struct { kind: u8, constant: f64 }
type ParamRange = struct { low: f64, high: f64, log_scale: bool, integer: bool }

const IMPUTE_MEAN: u8 = 0u8
const IMPUTE_MEDIAN: u8 = 1u8
const IMPUTE_CONSTANT: u8 = 2u8
const STANDARDIZE: u8 = 3u8
const MIN_MAX: u8 = 4u8

error Invalid
error TooSmall

// scikit-learn's `KFold(shuffle=False)`: contiguous folds, the first `n % k`
// one row larger.
fn kfold_assign(n: usize, k: usize, fold_of: []usize) -> err {
    if k < 2usize || n < k { ret Invalid }
    if fold_of.len < n { ret TooSmall }
    let base = n / k
    let extra = n % k
    var at_row = 0usize
    var fold = 0usize
    while fold < k {
        var size = base
        if fold < extra { size += 1usize }
        var j = 0usize
        while j < size {
            fold_of[at_row] = fold
            at_row += 1usize
            j += 1usize
        }
        fold += 1usize
    }
    ret ok
}

// `KFold(shuffle=True)` with the caller's generator: the same fold sizes over a
// Fisher-Yates permutation of the rows.
fn kfold_shuffled(r: *rand.Pcg64, n: usize, k: usize, fold_of: []usize, order: []usize) -> err {
    if k < 2usize || n < k { ret Invalid }
    if fold_of.len < n || order.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    i = n
    while i > 1usize {
        i -= 1usize
        let j = usize(rand.pcg64_bounded(r, u64(i + 1usize)))
        let held = order[i]
        order[i] = order[j]
        order[j] = held
    }
    let base = n / k
    let extra = n % k
    var at_row = 0usize
    var fold = 0usize
    while fold < k {
        var size = base
        if fold < extra { size += 1usize }
        var q = 0usize
        while q < size {
            fold_of[order[at_row]] = fold
            at_row += 1usize
            q += 1usize
        }
        fold += 1usize
    }
    ret ok
}

// scikit-learn's `StratifiedKFold(shuffle=False)`: `classes` labels in
// `0..classes`; every class is spread over the folds in proportion, the order
// of rows within a class kept. `scratch.len >= classes * k`.
fn stratified_assign(labels: []const usize, n: usize, classes: usize, k: usize, fold_of: []usize, scratch: []usize) -> err {
    if k < 2usize || n < k || classes == 0usize { ret Invalid }
    if labels.len < n || fold_of.len < n || scratch.len < classes * k { ret TooSmall }
    // allocation[fold][class] = count of class in the sorted labels at positions fold, fold + k, ...
    // Sorted labels are a run of each class in class order: position p holds the class whose run covers p.
    var run_start: [64]usize = zero
    if classes > 64usize { ret TooSmall }
    var totals: [64]usize = zero
    var i = 0usize
    while i < n {
        if labels[i] >= classes { ret Invalid }
        totals[labels[i]] += 1usize
        i += 1usize
    }
    // scikit-learn orders the classes by first appearance in the labels.
    var seen_order: [64]usize = zero
    var seen = 0usize
    i = 0usize
    while i < n {
        var known = false
        var q = 0usize
        while q < seen {
            if seen_order[q] == labels[i] { known = true }
            q += 1usize
        }
        if !known {
            seen_order[seen] = labels[i]
            seen += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    var acc = 0usize
    while c < seen {
        run_start[seen_order[c]] = acc
        acc += totals[seen_order[c]]
        c += 1usize
    }
    var fold = 0usize
    while fold < k {
        c = 0usize
        while c < classes {
            // Positions p = fold + k t in [run_start, run_start + total).
            let start = run_start[c]
            let end = start + totals[c]
            var below_end = 0usize
            if end > fold { below_end = (end - fold + k - 1usize) / k }
            var below_start = 0usize
            if start > fold { below_start = (start - fold + k - 1usize) / k }
            let count = below_end - below_start
            scratch[fold * classes + c] = count
            c += 1usize
        }
        fold += 1usize
    }
    // Rows of each class take fold ids repeated by their allocation, in row order.
    c = 0usize
    while c < classes {
        var cursor_fold = 0usize
        var left_in_fold = scratch[c]
        i = 0usize
        while i < n {
            if labels[i] == c {
                while left_in_fold == 0usize && cursor_fold + 1usize < k {
                    cursor_fold += 1usize
                    left_in_fold = scratch[cursor_fold * classes + c]
                }
                fold_of[i] = cursor_fold
                if left_in_fold > 0usize { left_in_fold -= 1usize }
            }
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// Fill `rows` with the rows whose fold is `fold` (the test rows) and answer
// their count, and `train` with the others, answering that count too.
fn split_fold(fold_of: []const usize, n: usize, fold: usize, train: []usize, test: []usize) -> (usize, usize) {
    var nt = 0usize
    var nr = 0usize
    var i = 0usize
    while i < n {
        if fold_of[i] == fold {
            test[nt] = i
            nt += 1usize
        } else {
            train[nr] = i
            nr += 1usize
        }
        i += 1usize
    }
    ret (nr, nt)
}

// Cross-validate: `evaluate(ctx, train_rows, test_rows)` for every fold; the
// scores go to `scores` (one per fold) and the mean is answered.
// `train.len` and `test.len` must be at least `n`.
fn cross_validate[Ctx: type](ctx: *Ctx, n: usize, folds: usize, fold_of: []const usize, train: []usize, test: []usize, evaluate: fn(*Ctx, []const usize, []const usize) -> f64, scores: []f64) -> (f64, err) {
    if folds < 2usize || scores.len < folds || train.len < n || test.len < n { ret (0.0f64, TooSmall) }
    var total = 0.0f64
    var fold = 0usize
    while fold < folds {
        let (nr, nt) = split_fold(fold_of, n, fold, train, test)
        if nr == 0usize || nt == 0usize { ret (0.0f64, Invalid) }
        let s = evaluate(ctx, train[..nr], test[..nt])
        scores[fold] = s
        total += s
        fold += 1usize
    }
    ret (total / f64(folds), ok)
}

// Grid search over `points` candidates: `evaluate(ctx, point, train, test)`
// scored by cross-validation; `means[point]` receives the mean score and the
// best (the first among equals) is answered. `fold_scores` wants `folds` floats.
fn grid_search[Ctx: type](ctx: *Ctx, points: usize, n: usize, folds: usize, fold_of: []const usize, train: []usize, test: []usize, evaluate: fn(*Ctx, usize, []const usize, []const usize) -> f64, means: []f64) -> (usize, err) {
    if points == 0usize || means.len < points || folds < 2usize || train.len < n || test.len < n { ret (0usize, TooSmall) }
    var best = 0usize
    var point = 0usize
    while point < points {
        var total = 0.0f64
        var fold = 0usize
        while fold < folds {
            let (nr, nt) = split_fold(fold_of, n, fold, train, test)
            if nr == 0usize || nt == 0usize { ret (0usize, Invalid) }
            total += evaluate(ctx, point, train[..nr], test[..nt])
            fold += 1usize
        }
        means[point] = total / f64(folds)
        if means[point] > means[best] { best = point }
        point += 1usize
    }
    ret (best, ok)
}

// One uniform draw of a parameter from its range (log-uniform on the log
// scale, rounded for an integer parameter).
fn draw_parameter(r: *rand.Pcg64, spec: ParamRange) -> f64 {
    let u = rand.pcg64_f64(r)
    var v = spec.low + u * (spec.high - spec.low)
    if spec.log_scale {
        v = math.exp[f64](math.log[f64](spec.low) + u * (math.log[f64](spec.high) - math.log[f64](spec.low)))
    }
    if spec.integer { v = math.floor[f64](v + 0.5f64) }
    ret v
}

// Random search: `draws` parameter vectors sampled from `ranges`; the vector
// goes to `candidate`, `evaluate(ctx, candidate, train, test)` is averaged over
// the folds, and the best mean score is answered with its vector left in
// `best_params` (`ranges.len` floats). `means` receives one score per draw.
fn random_search[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, ranges: []const ParamRange, draws: usize, n: usize, folds: usize, fold_of: []const usize, train: []usize, test: []usize, evaluate: fn(*Ctx, []const f64, []const usize, []const usize) -> f64, candidate: []f64, best_params: []f64, means: []f64) -> (f64, err) {
    if draws == 0usize || means.len < draws || candidate.len < ranges.len || best_params.len < ranges.len || folds < 2usize || train.len < n || test.len < n { ret (0.0f64, TooSmall) }
    var best_score = 0.0f64 - 1.0e300f64
    var d = 0usize
    while d < draws {
        var k = 0usize
        while k < ranges.len {
            candidate[k] = draw_parameter(r, ranges[k])
            k += 1usize
        }
        var total = 0.0f64
        var fold = 0usize
        while fold < folds {
            let (nr, nt) = split_fold(fold_of, n, fold, train, test)
            if nr == 0usize || nt == 0usize { ret (0.0f64, Invalid) }
            total += evaluate(ctx, candidate[..ranges.len], train[..nr], test[..nt])
            fold += 1usize
        }
        means[d] = total / f64(folds)
        if means[d] > best_score {
            best_score = means[d]
            k = 0usize
            while k < ranges.len {
                best_params[k] = candidate[k]
                k += 1usize
            }
        }
        d += 1usize
    }
    ret (best_score, ok)
}

// --- the preprocessing pipeline --------------------------------------------------------------------------------

fn nan_median(values: []f64) -> f64 {
    let m = values.len
    var gap = m / 2usize
    while gap > 0usize {
        var i = gap
        while i < m {
            let held = values[i]
            var j = i
            while j >= gap && values[j - gap] > held {
                values[j] = values[j - gap]
                j -= gap
            }
            values[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
    if m == 0usize { ret 0.0f64 / 0.0f64 }
    if m % 2usize == 1usize { ret values[m / 2usize] }
    ret 0.5f64 * (values[m / 2usize - 1usize] + values[m / 2usize])
}

// Fit the steps in order on `rows` of `x` (`n` x `d`), each step seeing the
// previous steps' output. `params` receives two numbers per step and feature
// (fill value or centre, then divisor); `work` wants `n * d + n` floats.
// Constant columns scale by 1, as scikit-learn does.
fn pipeline_fit(steps: []const Step, x: []const f64, n: usize, d: usize, rows: []const usize, params: []f64, work: []f64) -> err {
    let m = rows.len
    if m == 0usize || d == 0usize || params.len < 2usize * d * steps.len || work.len < m * d + m || x.len < n * d { ret TooSmall }
    var data = work[..m * d]
    var column = work[m * d..m * d + m]
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < d {
            data[i * d + j] = x[rows[i] * d + j]
            j += 1usize
        }
        i += 1usize
    }
    var s = 0usize
    while s < steps.len {
        let kind = steps[s].kind
        var j = 0usize
        while j < d {
            var count = 0usize
            var sum = 0.0f64
            var lo = 1.0e300f64
            var hi = 0.0f64 - 1.0e300f64
            i = 0usize
            while i < m {
                let v = data[i * d + j]
                if v == v {
                    column[count] = v
                    count += 1usize
                    sum += v
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
                i += 1usize
            }
            var centre = 0.0f64
            var scale = 1.0f64
            if kind == IMPUTE_MEAN {
                if count > 0usize { centre = sum / f64(count) }
            } else if kind == IMPUTE_MEDIAN {
                if count > 0usize { centre = nan_median(column[..count]) }
            } else if kind == IMPUTE_CONSTANT {
                centre = steps[s].constant
            } else if kind == STANDARDIZE {
                if count > 0usize {
                    centre = sum / f64(count)
                    var ss = 0.0f64
                    var q = 0usize
                    while q < count {
                        ss += (column[q] - centre) * (column[q] - centre)
                        q += 1usize
                    }
                    let sd = math.sqrt[f64](ss / f64(count))
                    if sd > 0.0f64 { scale = sd }
                }
            } else if kind == MIN_MAX {
                if count > 0usize {
                    centre = lo
                    if hi - lo > 0.0f64 { scale = hi - lo }
                }
            } else {
                ret Invalid
            }
            params[(s * d + j) * 2usize] = centre
            params[(s * d + j) * 2usize + 1usize] = scale
            // Apply to the fit data for the next step.
            i = 0usize
            while i < m {
                data[i * d + j] = apply_step(kind, data[i * d + j], centre, scale)
                i += 1usize
            }
            j += 1usize
        }
        s += 1usize
    }
    ret ok
}

fn apply_step(kind: u8, v: f64, centre: f64, scale: f64) -> f64 {
    if kind == IMPUTE_MEAN || kind == IMPUTE_MEDIAN || kind == IMPUTE_CONSTANT {
        if v != v { ret centre }
        ret v
    }
    ret (v - centre) / scale
}

// Transform `rows` of `x` through the fitted pipeline into `out` (`rows.len`
// x `d`, row-major).
fn pipeline_transform(steps: []const Step, params: []const f64, x: []const f64, d: usize, rows: []const usize, out: []f64) -> err {
    if out.len < rows.len * d || params.len < 2usize * d * steps.len { ret TooSmall }
    var i = 0usize
    while i < rows.len {
        var j = 0usize
        while j < d {
            var v = x[rows[i] * d + j]
            var s = 0usize
            while s < steps.len {
                v = apply_step(steps[s].kind, v, params[(s * d + j) * 2usize], params[(s * d + j) * 2usize + 1usize])
                s += 1usize
            }
            out[i * d + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}
