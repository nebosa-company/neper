// Histogram gradient boosting over row-major `f64` samples (L063), after
// LightGBM and scikit-learn's `HistGradientBoosting*`: features are binned once
// into at most `max_bins` quantile bins, each tree grows leaf-wise (the leaf with
// the largest gain splits next, up to `max_leaf_nodes`) from per-feature
// gradient histograms, and a NaN is a missing value that every split routes to
// the side that gained most in training (or, for a feature with no missing
// value in training, to the child holding more samples).
//
// Squared error (a regressor) and the binary log loss (a classifier of 0/1
// labels) are supported. Splits need `min_samples_leaf` samples and
// `min_hessian` of hessian in each child and a positive gain
// `G_L^2/(H_L + l2) + G_R^2/(H_R + l2) - G^2/(H + l2)`; a leaf's value is
// `-learning_rate G / (H + l2)`. The model and its scratch live in the caller's
// arena.

use e.math
use e.mem

type Params = struct { rounds: usize, learning_rate: f64, max_leaf_nodes: usize, max_depth: usize, min_samples_leaf: usize, l2: f64, max_bins: usize, min_hessian: f64, logistic: bool }

// `feature[node] < 0` marks a leaf; trees are `stride` nodes apart.
type Model = struct { features: usize, trees: usize, stride: usize, base: f64, logistic: bool, feature: []i32, threshold: []f64, left: []u32, right: []u32, missing_left: []bool, value: []f64 }

error Invalid

fn default_params() -> Params {
    ret Params { rounds: 100usize, learning_rate: 0.1f64, max_leaf_nodes: 31usize, max_depth: 0usize, min_samples_leaf: 20usize, l2: 0.0f64, max_bins: 255usize, min_hessian: 0.001f64, logistic: false }
}

fn sigmoid(z: f64) -> f64 {
    if z >= 0.0f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z)) }
    let e = math.exp[f64](z)
    ret e / (1.0f64 + e)
}

// Shell sort in place.
fn sort_values(values: []f64) {
    var gap = values.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < values.len {
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
}

// The bin thresholds of one sorted, NaN-free column into `out` (at most
// `max_bins - 1`): midpoints between neighbouring distinct values when there are
// at most `max_bins` of them, else NumPy's "averaged_inverted_cdf" percentiles
// at `100 k / max_bins` (what scikit-learn bins by), duplicates collapsed.
// Answers how many.
fn bin_thresholds(sorted: []const f64, max_bins: usize, out: []f64) -> usize {
    let m = sorted.len
    if m == 0usize { ret 0usize }
    var distinct = 1usize
    var i = 1usize
    while i < m {
        if sorted[i] != sorted[i - 1usize] { distinct += 1usize }
        i += 1usize
    }
    var count = 0usize
    if distinct <= max_bins {
        i = 1usize
        while i < m {
            if sorted[i] != sorted[i - 1usize] {
                out[count] = (sorted[i - 1usize] + sorted[i]) * 0.5f64
                count += 1usize
            }
            i += 1usize
        }
        ret count
    }
    // NumPy's "averaged_inverted_cdf" percentile at 100 k / max_bins: the order
    // statistic at ceil(m q), or the mean of that and the one below it when m q is
    // an integer. Equal neighbours collapse to one threshold.
    let step = 100.0f64 / f64(max_bins)
    var k = 1usize
    while k < max_bins {
        let quantile = f64(k) * step / 100.0f64
        var virtual_index = f64(m) * quantile - 1.0f64
        if virtual_index < 0.0f64 { virtual_index = 0.0f64 }
        let previous_index = math.floor[f64](virtual_index)
        let gamma = virtual_index - previous_index
        let lower = usize(previous_index)
        var upper = lower + 1usize
        if upper > m - 1usize { upper = m - 1usize }
        var v = sorted[upper]
        if gamma == 0.0f64 { v = sorted[lower] + (sorted[upper] - sorted[lower]) * 0.5f64 }
        if count == 0usize || v != out[count - 1usize] {
            out[count] = v
            count += 1usize
        }
        k += 1usize
    }
    ret count
}

// Number of thresholds strictly below `x`: the bin of `x` (a value equal to a
// threshold goes left).
fn bin_of(thresholds: []const f64, x: f64) -> usize {
    var lo = 0usize
    var hi = thresholds.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if thresholds[mid] < x { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

// Fit `p.rounds` trees to `y` over `n` rows of `d` features (NaN = missing).
// Classification labels are 0 and 1. The model's arrays come from `a`.
fn fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, p: Params) -> (Model, err) {
    var m: Model = zero
    if n < 2usize || d == 0usize || p.rounds == 0usize || p.max_leaf_nodes < 2usize || p.max_bins < 2usize || p.max_bins > 255usize { ret (m, Invalid) }
    if !(p.learning_rate > 0.0f64) || p.min_samples_leaf == 0usize || p.l2 < 0.0f64 { ret (m, Invalid) }
    if x.len < n * d || y.len < n { ret (m, Invalid) }
    let bins_per = p.max_bins
    // Thresholds per feature.
    let (thr, te) = mem.alloc[f64](a, d * bins_per)
    if te != ok { ret (m, te) }
    let (thr_count, tce) = mem.alloc[usize](a, d)
    if tce != ok { ret (m, tce) }
    let (has_missing, hme) = mem.alloc[bool](a, d)
    if hme != ok { ret (m, hme) }
    let (col, ce) = mem.alloc[f64](a, n)
    if ce != ok { ret (m, ce) }
    let (binned, be) = mem.alloc[u16](a, n * d)
    if be != ok { ret (m, be) }
    var f = 0usize
    while f < d {
        var c = 0usize
        var miss_any = false
        var i = 0usize
        while i < n {
            let v = x[i * d + f]
            if v == v {
                col[c] = v
                c += 1usize
            } else {
                miss_any = true
            }
            i += 1usize
        }
        has_missing[f] = miss_any
        sort_values(col[..c])
        thr_count[f] = bin_thresholds(col[..c], p.max_bins, thr[f * bins_per..f * bins_per + bins_per])
        i = 0usize
        while i < n {
            let v = x[i * d + f]
            if v == v {
                binned[i * d + f] = u16(bin_of(thr[f * bins_per..f * bins_per + thr_count[f]], v))
            } else {
                binned[i * d + f] = 65535u16
            }
            i += 1usize
        }
        f += 1usize
    }
    // Tree storage.
    let stride = 2usize * p.max_leaf_nodes
    let total_nodes = p.rounds * stride
    let (feature, fe) = mem.alloc[i32](a, total_nodes)
    if fe != ok { ret (m, fe) }
    let (threshold, the) = mem.alloc[f64](a, total_nodes)
    if the != ok { ret (m, the) }
    let (left, le) = mem.alloc[u32](a, total_nodes)
    if le != ok { ret (m, le) }
    let (right, re) = mem.alloc[u32](a, total_nodes)
    if re != ok { ret (m, re) }
    let (missing_left, mle) = mem.alloc[bool](a, total_nodes)
    if mle != ok { ret (m, mle) }
    let (value, ve) = mem.alloc[f64](a, total_nodes)
    if ve != ok { ret (m, ve) }
    // Per-sample state.
    let (raw, rawe) = mem.alloc[f64](a, n)
    if rawe != ok { ret (m, rawe) }
    let (grad, ge) = mem.alloc[f64](a, n)
    if ge != ok { ret (m, ge) }
    let (hess, hee) = mem.alloc[f64](a, n)
    if hee != ok { ret (m, hee) }
    let (rows, rowe) = mem.alloc[usize](a, n)
    if rowe != ok { ret (m, rowe) }
    // Per-node state during growth.
    let cap = stride
    let (node_lo, e1) = mem.alloc[usize](a, cap)
    if e1 != ok { ret (m, e1) }
    let (node_hi, e2) = mem.alloc[usize](a, cap)
    if e2 != ok { ret (m, e2) }
    let (node_g, e3) = mem.alloc[f64](a, cap)
    if e3 != ok { ret (m, e3) }
    let (node_h, e4) = mem.alloc[f64](a, cap)
    if e4 != ok { ret (m, e4) }
    let (node_depth, e5) = mem.alloc[usize](a, cap)
    if e5 != ok { ret (m, e5) }
    let (best_gain, e6) = mem.alloc[f64](a, cap)
    if e6 != ok { ret (m, e6) }
    let (best_feature, e7) = mem.alloc[usize](a, cap)
    if e7 != ok { ret (m, e7) }
    let (best_bin, e8) = mem.alloc[usize](a, cap)
    if e8 != ok { ret (m, e8) }
    let (best_missing_left, e9) = mem.alloc[bool](a, cap)
    if e9 != ok { ret (m, e9) }
    let (open, e10) = mem.alloc[bool](a, cap)
    if e10 != ok { ret (m, e10) }
    let (hist_g, e11) = mem.alloc[f64](a, bins_per + 1usize)
    if e11 != ok { ret (m, e11) }
    let (hist_h, e12) = mem.alloc[f64](a, bins_per + 1usize)
    if e12 != ok { ret (m, e12) }
    let (hist_c, e13) = mem.alloc[usize](a, bins_per + 1usize)
    if e13 != ok { ret (m, e13) }
    // Baseline.
    var mean_y = 0.0f64
    var i0 = 0usize
    while i0 < n {
        mean_y += y[i0]
        i0 += 1usize
    }
    mean_y = mean_y / f64(n)
    var base = mean_y
    if p.logistic {
        if !(mean_y > 0.0f64 && mean_y < 1.0f64) { ret (m, Invalid) }
        base = math.log[f64](mean_y / (1.0f64 - mean_y))
    }
    i0 = 0usize
    while i0 < n {
        raw[i0] = base
        i0 += 1usize
    }
    var tree = 0usize
    while tree < p.rounds {
        // Gradients and hessians of the loss at the current raw predictions.
        var i = 0usize
        while i < n {
            if p.logistic {
                let pr = sigmoid(raw[i])
                grad[i] = pr - y[i]
                hess[i] = pr * (1.0f64 - pr)
            } else {
                grad[i] = raw[i] - y[i]
                hess[i] = 1.0f64
            }
            rows[i] = i
            i += 1usize
        }
        let at = tree * stride
        var nodes = 1usize
        var leaves = 1usize
        node_lo[0usize] = 0usize
        node_hi[0usize] = n
        node_depth[0usize] = 0usize
        var sg = 0.0f64
        var sh = 0.0f64
        i = 0usize
        while i < n {
            sg += grad[i]
            sh += hess[i]
            i += 1usize
        }
        node_g[0usize] = sg
        node_h[0usize] = sh
        feature[at] = 0i32 - 1i32
        left[at] = 0u32
        right[at] = 0u32
        missing_left[at] = false
        open[0usize] = true
        best_gain[0usize] = 0.0f64
        find_split(binned, d, rows, node_lo[0usize], node_hi[0usize], grad, hess, thr_count, has_missing, bins_per, p, 0usize, node_g, node_h, node_depth, best_gain, best_feature, best_bin, best_missing_left, hist_g, hist_h, hist_c)
        while leaves < p.max_leaf_nodes {
            // The open node with the largest positive gain.
            var pick = cap
            var top = 0.0f64
            var q = 0usize
            while q < nodes {
                if open[q] && best_gain[q] > top {
                    top = best_gain[q]
                    pick = q
                }
                q += 1usize
            }
            if pick == cap { break }
            // Partition the node's rows by the split.
            let lo = node_lo[pick]
            let hi = node_hi[pick]
            let sf = best_feature[pick]
            let sb = best_bin[pick]
            var write = lo
            var r = lo
            while r < hi {
                let row = rows[r]
                let b = usize(binned[row * d + sf])
                var goes_left = false
                if binned[row * d + sf] == 65535u16 { goes_left = best_missing_left[pick] } else { goes_left = b <= sb }
                if goes_left {
                    let swap = rows[write]
                    rows[write] = row
                    rows[r] = swap
                    write += 1usize
                }
                r += 1usize
            }
            let lc = nodes
            let rc = nodes + 1usize
            nodes += 2usize
            leaves += 1usize
            node_lo[lc] = lo
            node_hi[lc] = write
            node_lo[rc] = write
            node_hi[rc] = hi
            node_depth[lc] = node_depth[pick] + 1usize
            node_depth[rc] = node_depth[pick] + 1usize
            var lg = 0.0f64
            var lh = 0.0f64
            r = lo
            while r < write {
                lg += grad[rows[r]]
                lh += hess[rows[r]]
                r += 1usize
            }
            node_g[lc] = lg
            node_h[lc] = lh
            node_g[rc] = node_g[pick] - lg
            node_h[rc] = node_h[pick] - lh
            open[pick] = false
            feature[at + pick] = i32(sf)
            threshold[at + pick] = 1.0e300f64
            if sb < thr_count[sf] { threshold[at + pick] = thr[sf * bins_per + sb] }
            missing_left[at + pick] = best_missing_left[pick]
            left[at + pick] = u32(lc)
            right[at + pick] = u32(rc)
            feature[at + lc] = 0i32 - 1i32
            feature[at + rc] = 0i32 - 1i32
            open[lc] = true
            open[rc] = true
            best_gain[lc] = 0.0f64
            best_gain[rc] = 0.0f64
            find_split(binned, d, rows, node_lo[lc], node_hi[lc], grad, hess, thr_count, has_missing, bins_per, p, lc, node_g, node_h, node_depth, best_gain, best_feature, best_bin, best_missing_left, hist_g, hist_h, hist_c)
            find_split(binned, d, rows, node_lo[rc], node_hi[rc], grad, hess, thr_count, has_missing, bins_per, p, rc, node_g, node_h, node_depth, best_gain, best_feature, best_bin, best_missing_left, hist_g, hist_h, hist_c)
        }
        // Leaf values and the raw predictions.
        var q2 = 0usize
        while q2 < nodes {
            if feature[at + q2] < 0i32 {
                let v = 0.0f64 - p.learning_rate * node_g[q2] / (node_h[q2] + p.l2)
                value[at + q2] = v
                var r = node_lo[q2]
                while r < node_hi[q2] {
                    raw[rows[r]] += v
                    r += 1usize
                }
            }
            q2 += 1usize
        }
        tree += 1usize
    }
    m = Model { features: d, trees: p.rounds, stride: stride, base: base, logistic: p.logistic, feature: feature, threshold: threshold, left: left, right: right, missing_left: missing_left, value: value }
    ret (m, ok)
}

// The best split of node `node` over its rows `rows[lo..hi]`, written into the
// `best_*` arrays; `best_gain[node]` stays 0 when the node cannot split.
fn find_split(binned: []const u16, d: usize, rows: []const usize, lo: usize, hi: usize, grad: []const f64, hess: []const f64, thr_count: []const usize, has_missing: []const bool, bins_per: usize, p: Params, node: usize, node_g: []const f64, node_h: []const f64, node_depth: []const usize, best_gain: []f64, best_feature: []usize, best_bin: []usize, best_missing_left: []bool, hist_g: []f64, hist_h: []f64, hist_c: []usize) {
    best_gain[node] = 0.0f64
    let count = hi - lo
    if count < 2usize * p.min_samples_leaf { ret }
    if p.max_depth > 0usize && node_depth[node] >= p.max_depth { ret }
    let total_g = node_g[node]
    let total_h = node_h[node]
    let parent = total_g * total_g / (total_h + p.l2)
    var f = 0usize
    while f < d {
        let nb = thr_count[f] + 1usize
        var b = 0usize
        while b < nb {
            hist_g[b] = 0.0f64
            hist_h[b] = 0.0f64
            hist_c[b] = 0usize
            b += 1usize
        }
        var mg = 0.0f64
        var mh = 0.0f64
        var mc = 0usize
        var r = lo
        while r < hi {
            let row = rows[r]
            let bin = binned[row * d + f]
            if bin == 65535u16 {
                mg += grad[row]
                mh += hess[row]
                mc += 1usize
            } else {
                hist_g[usize(bin)] += grad[row]
                hist_h[usize(bin)] += hess[row]
                hist_c[usize(bin)] += 1usize
            }
            r += 1usize
        }
        // Left-to-right scan: missing values go right. With missing values in the
        // training data the last observed bin may go wholly left as well.
        var s = 0usize
        var last = nb - 1usize
        if has_missing[f] { last = nb }
        var lg = 0.0f64
        var lh = 0.0f64
        var lc = 0usize
        while s < last {
            lg += hist_g[s]
            lh += hist_h[s]
            lc += hist_c[s]
            let rg = total_g - lg
            let rh = total_h - lh
            let rc = count - lc
            if lc >= p.min_samples_leaf && rc >= p.min_samples_leaf && lh >= p.min_hessian && rh >= p.min_hessian {
                let gain = lg * lg / (lh + p.l2) + rg * rg / (rh + p.l2) - parent
                if gain > best_gain[node] {
                    best_gain[node] = gain
                    best_feature[node] = f
                    best_bin[node] = s
                    // No missing value in training: unseen ones follow the larger child.
                    best_missing_left[node] = !has_missing[f] && lc > rc
                }
            }
            s += 1usize
        }
        // Right-to-left scan (missing values go left), only for a feature that had
        // missing values in training; a tie with the left-to-right best keeps it, and
        // among equal right-to-left gains the highest bin wins.
        if has_missing[f] && nb >= 2usize {
            var rg = 0.0f64
            var rh = 0.0f64
            var rc = 0usize
            var bin_index = nb - 1usize
            while bin_index > 0usize {
                bin_index -= 1usize
                rg += hist_g[bin_index + 1usize]
                rh += hist_h[bin_index + 1usize]
                rc += hist_c[bin_index + 1usize]
                let lg2 = total_g - rg
                let lh2 = total_h - rh
                let lc2 = count - rc
                if lc2 >= p.min_samples_leaf && rc >= p.min_samples_leaf && lh2 >= p.min_hessian && rh >= p.min_hessian {
                    let gain = lg2 * lg2 / (lh2 + p.l2) + rg * rg / (rh + p.l2) - parent
                    if gain > best_gain[node] {
                        best_gain[node] = gain
                        best_feature[node] = f
                        best_bin[node] = bin_index
                        best_missing_left[node] = true
                    }
                }
            }
        }
        f += 1usize
    }
}

// The raw prediction of `row` (the log-odds for a classifier).
fn predict_raw(m: *const Model, row: []const f64) -> f64 {
    var sum = m.base
    var t = 0usize
    while t < m.trees {
        let at = t * m.stride
        var node = 0usize
        while m.feature[at + node] >= 0i32 {
            let v = row[usize(m.feature[at + node])]
            var go_left = false
            if v != v { go_left = m.missing_left[at + node] } else { go_left = v <= m.threshold[at + node] }
            if go_left { node = usize(m.left[at + node]) } else { node = usize(m.right[at + node]) }
        }
        sum += m.value[at + node]
        t += 1usize
    }
    ret sum
}

// The prediction: the regression value, or the probability of class 1.
fn predict(m: *const Model, row: []const f64) -> f64 {
    let raw = predict_raw(m, row)
    if m.logistic { ret sigmoid(raw) }
    ret raw
}
