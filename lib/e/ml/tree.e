// Decision trees over row-major `f64` samples in the caller's arena: `cart`
// grows a binary tree by the best threshold split (Gini impurity for class
// labels, squared error for targets) down to `max_depth` or `min_samples`;
// `random_forest` grows trees on bootstrap samples with a random feature
// subset per split and votes or averages; `gradient_boost` fits regression
// trees to the residuals of the running prediction with a learning rate.
// Every split is exhaustive over the samples at the node.

use e.algo.rand
use e.mem

type Node = struct { feature: usize, threshold: f64, left: u32, right: u32, value: f64 }
type Tree = struct { nodes: []Node, count: usize, classes: usize }
type Forest = struct { trees: []Tree, count: usize, classes: usize }
type Boost = struct { trees: []Tree, count: usize, base: f64, rate: f64 }
error TooSmall
error Invalid

const LEAF: u32 = 4294967295u32

// The impurity of the samples `rows[..count]`: Gini over `classes` labels, or
// the squared error about the mean when `classes == 0`. `bins.len >= classes`.
fn impurity(x: []const f64, y: []const f64, rows: []const usize, count: usize, classes: usize, bins: []usize) -> f64 {
    if count == 0usize { ret 0.0f64 }
    if classes == 0usize {
        var mean = 0.0f64
        var i = 0usize
        while i < count {
            mean += y[rows[i]]
            i += 1usize
        }
        mean = mean / f64(count)
        var sum = 0.0f64
        i = 0usize
        while i < count {
            let t = y[rows[i]] - mean
            sum += t * t
            i += 1usize
        }
        ret sum
    }
    var c = 0usize
    while c < classes {
        bins[c] = 0usize
        c += 1usize
    }
    var i = 0usize
    while i < count {
        bins[usize(y[rows[i]])] += 1usize
        i += 1usize
    }
    var gini = 1.0f64
    c = 0usize
    while c < classes {
        let p = f64(bins[c]) / f64(count)
        gini -= p * p
        c += 1usize
    }
    ret gini * f64(count)
}

// The leaf value: the majority class or the mean.
fn leaf_value(y: []const f64, rows: []const usize, count: usize, classes: usize, bins: []usize) -> f64 {
    if classes == 0usize {
        var mean = 0.0f64
        var i = 0usize
        while i < count {
            mean += y[rows[i]]
            i += 1usize
        }
        if count > 0usize { ret mean / f64(count) }
        ret 0.0f64
    }
    var c = 0usize
    while c < classes {
        bins[c] = 0usize
        c += 1usize
    }
    var i = 0usize
    while i < count {
        bins[usize(y[rows[i]])] += 1usize
        i += 1usize
    }
    var best = 0usize
    c = 1usize
    while c < classes {
        if bins[c] > bins[best] { best = c }
        c += 1usize
    }
    ret f64(best)
}

// Partition `rows[..count]` by `feature <= threshold`; answers the left count.
fn partition(x: []const f64, d: usize, rows: []usize, count: usize, feature: usize, threshold: f64) -> usize {
    var left = 0usize
    var i = 0usize
    while i < count {
        if x[rows[i] * d + feature] <= threshold {
            let t = rows[left]
            rows[left] = rows[i]
            rows[i] = t
            left += 1usize
        }
        i += 1usize
    }
    ret left
}

// The best split of `rows[..count]` over the features `features[..feature_count]`
// (every value between two distinct sorted values is a candidate threshold):
// the feature, threshold and impurity gain, `gain == 0` when nothing helps.
fn best_split(x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, classes: usize, features: []const usize, feature_count: usize, bins: []usize, order: []usize) -> (usize, f64, f64) {
    let parent = impurity(x, y, rows, count, classes, bins)
    var best_feature = d
    var best_threshold = 0.0f64
    var best_gain = 0.0f64
    var f = 0usize
    while f < feature_count {
        let feature = features[f]
        // Sort the rows by this feature (insertion sort into `order`).
        var i = 0usize
        while i < count {
            var k = i
            while k > 0usize && x[order[k - 1usize] * d + feature] > x[rows[i] * d + feature] {
                order[k] = order[k - 1usize]
                k -= 1usize
            }
            order[k] = rows[i]
            i += 1usize
        }
        i = 1usize
        while i < count {
            let a = x[order[i - 1usize] * d + feature]
            let b = x[order[i] * d + feature]
            if a < b {
                let threshold = 0.5f64 * (a + b)
                let left = impurity(x, y, order, i, classes, bins)
                let right = impurity(x, y, order[i..], count - i, classes, bins)
                let gain = parent - left - right
                if gain > best_gain + 1.0e-12f64 {
                    best_gain = gain
                    best_feature = feature
                    best_threshold = threshold
                }
            }
            i += 1usize
        }
        f += 1usize
    }
    ret (best_feature, best_threshold, best_gain)
}

// Grow the subtree over `rows[..count]` into `t`, answering its node index.
fn grow(t: *Tree, x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, depth: usize, max_depth: usize, min_samples: usize, features: []usize, feature_count: usize, subset: usize, r: *rand.Pcg64, bins: []usize, order: []usize) -> (u32, err) {
    if t.count >= t.nodes.len { ret (LEAF, TooSmall) }
    let node = t.count
    t.count += 1usize
    t.nodes[node] = Node { feature: d, threshold: 0.0f64, left: LEAF, right: LEAF, value: leaf_value(y, rows, count, t.classes, bins) }
    if depth >= max_depth || count < 2usize * min_samples { ret (u32(node), ok) }
    // The candidate features: all, or a random subset of `subset` without replacement.
    var chosen = feature_count
    if subset < feature_count {
        var i = 0usize
        while i < subset {
            let j = i + usize(rand.pcg64_bounded(r, u64(feature_count - i)))
            let tmp = features[i]
            features[i] = features[j]
            features[j] = tmp
            i += 1usize
        }
        chosen = subset
    }
    let (feature, threshold, gain) = best_split(x, y, d, rows, count, t.classes, features, chosen, bins, order)
    if gain <= 0.0f64 { ret (u32(node), ok) }
    let left_count = partition(x, d, rows, count, feature, threshold)
    if left_count < min_samples || count - left_count < min_samples { ret (u32(node), ok) }
    let (left, left_error) = grow(t, x, y, d, rows, left_count, depth + 1usize, max_depth, min_samples, features, feature_count, subset, r, bins, order)
    if left_error != ok { ret (LEAF, left_error) }
    let (right, right_error) = grow(t, x, y, d, rows[left_count..], count - left_count, depth + 1usize, max_depth, min_samples, features, feature_count, subset, r, bins, order)
    if right_error != ok { ret (LEAF, right_error) }
    t.nodes[node].feature = feature
    t.nodes[node].threshold = threshold
    t.nodes[node].left = left
    t.nodes[node].right = right
    ret (u32(node), ok)
}

// A tree over `rows` (sample indices, permuted in place) with `classes` labels
// in `y` (`0` for regression); `subset` features are drawn per split when
// smaller than `d`. At most `2 * count` nodes are allocated.
fn grow_tree(a: *mem.Arena, x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, classes: usize, max_depth: usize, min_samples: usize, subset: usize, r: *rand.Pcg64) -> (Tree, err) {
    let (nodes, nodes_error) = mem.alloc[Node](a, 2usize * count + 1usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (bins, bins_error) = mem.alloc[usize](a, classes + 1usize)
    if bins_error != ok { ret (zero, bins_error) }
    let (order, order_error) = mem.alloc[usize](a, count)
    if order_error != ok { ret (zero, order_error) }
    let (features, features_error) = mem.alloc[usize](a, d)
    if features_error != ok { ret (zero, features_error) }
    var f = 0usize
    while f < d {
        features[f] = f
        f += 1usize
    }
    var t = Tree { nodes: nodes, count: 0usize, classes: classes }
    let (_, grow_error) = grow(&t, x, y, d, rows, count, 0usize, max_depth, min_samples, features, d, subset, r, bins, order)
    if grow_error != ok { ret (zero, grow_error) }
    ret (t, ok)
}

// CART on all `n` samples; `classes` labels in `y` (`0` for regression).
fn cart(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, classes: usize, max_depth: usize, min_samples: usize) -> (Tree, err) {
    if x.len < n * d || y.len < n { ret (zero, TooSmall) }
    if n == 0usize || d == 0usize || min_samples == 0usize { ret (zero, Invalid) }
    let (rows, rows_error) = mem.alloc[usize](a, n)
    if rows_error != ok { ret (zero, rows_error) }
    var i = 0usize
    while i < n {
        rows[i] = i
        i += 1usize
    }
    var r = rand.pcg64(0u64, 0u64)
    let (t, tree_error) = grow_tree(a, x, y, d, rows, n, classes, max_depth, min_samples, d, &r)
    ret (t, tree_error)
}

// The tree's answer for `sample` (a class index or a value).
fn predict(t: *const Tree, sample: []const f64) -> f64 {
    var node = 0usize
    while t.nodes[node].left != LEAF {
        if sample[t.nodes[node].feature] <= t.nodes[node].threshold {
            node = usize(t.nodes[node].left)
        } else {
            node = usize(t.nodes[node].right)
        }
    }
    ret t.nodes[node].value
}

// A forest of `trees` trees, each on a bootstrap sample of the rows with
// `subset` random features per split.
fn random_forest(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, classes: usize, trees: usize, subset: usize, max_depth: usize, min_samples: usize, r: *rand.Pcg64) -> (Forest, err) {
    if x.len < n * d || y.len < n { ret (zero, TooSmall) }
    if n == 0usize || d == 0usize || trees == 0usize || subset == 0usize || min_samples == 0usize { ret (zero, Invalid) }
    let (list, list_error) = mem.alloc[Tree](a, trees)
    if list_error != ok { ret (zero, list_error) }
    let (rows, rows_error) = mem.alloc[usize](a, n)
    if rows_error != ok { ret (zero, rows_error) }
    var k = 0usize
    while k < trees {
        var i = 0usize
        while i < n {
            rows[i] = usize(rand.pcg64_bounded(r, u64(n)))
            i += 1usize
        }
        let (t, tree_error) = grow_tree(a, x, y, d, rows, n, classes, max_depth, min_samples, subset, r)
        if tree_error != ok { ret (zero, tree_error) }
        list[k] = t
        k += 1usize
    }
    ret (Forest { trees: list, count: trees, classes: classes }, ok)
}

// The forest's vote (`bins.len >= classes`) or mean.
fn forest_predict(f: *const Forest, sample: []const f64, bins: []usize) -> (f64, err) {
    if f.classes == 0usize {
        var sum = 0.0f64
        var k = 0usize
        while k < f.count {
            sum += predict(&f.trees[k], sample)
            k += 1usize
        }
        ret (sum / f64(f.count), ok)
    }
    if bins.len < f.classes { ret (0.0f64, TooSmall) }
    var c = 0usize
    while c < f.classes {
        bins[c] = 0usize
        c += 1usize
    }
    var k = 0usize
    while k < f.count {
        bins[usize(predict(&f.trees[k], sample))] += 1usize
        k += 1usize
    }
    var best = 0usize
    c = 1usize
    while c < f.classes {
        if bins[c] > bins[best] { best = c }
        c += 1usize
    }
    ret (f64(best), ok)
}

// Gradient boosting for regression with squared loss: from the mean, each of
// `rounds` trees fits the residuals and joins with weight `rate`;
// `residuals.len >= n` is caller scratch.
fn gradient_boost(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, rounds: usize, rate: f64, max_depth: usize, min_samples: usize, residuals: []f64) -> (Boost, err) {
    if x.len < n * d || y.len < n || residuals.len < n { ret (zero, TooSmall) }
    if n == 0usize || d == 0usize || rounds == 0usize || min_samples == 0usize { ret (zero, Invalid) }
    let (list, list_error) = mem.alloc[Tree](a, rounds)
    if list_error != ok { ret (zero, list_error) }
    let (rows, rows_error) = mem.alloc[usize](a, n)
    if rows_error != ok { ret (zero, rows_error) }
    var base = 0.0f64
    var i = 0usize
    while i < n {
        base += y[i]
        i += 1usize
    }
    base = base / f64(n)
    i = 0usize
    while i < n {
        residuals[i] = y[i] - base
        i += 1usize
    }
    var r = rand.pcg64(0u64, 0u64)
    var k = 0usize
    while k < rounds {
        i = 0usize
        while i < n {
            rows[i] = i
            i += 1usize
        }
        let (t, tree_error) = grow_tree(a, x, residuals, d, rows, n, 0usize, max_depth, min_samples, d, &r)
        if tree_error != ok { ret (zero, tree_error) }
        list[k] = t
        i = 0usize
        while i < n {
            residuals[i] -= rate * predict(&t, x[i * d..(i + 1usize) * d])
            i += 1usize
        }
        k += 1usize
    }
    ret (Boost { trees: list, count: rounds, base: base, rate: rate }, ok)
}

fn boost_predict(b: *const Boost, sample: []const f64) -> f64 {
    var sum = b.base
    var k = 0usize
    while k < b.count {
        sum += b.rate * predict(&b.trees[k], sample)
        k += 1usize
    }
    ret sum
}
