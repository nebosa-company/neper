// `e.ml.tree`: a depth-two regression tree and a depth-three classifier
// split where scikit-learn splits (up to its random tie) and predict the same, a random forest of
// bootstrap trees with one random feature per split classifies three
// clusters, gradient boosting drives the training error of a step-like
// target down with the rounds, and the argument checks answer. Each check
// exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.tree
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: a regression tree on eight points.
    var x1: [8]f64 = zero
    var y1: [8]f64 = zero
    y1[0usize] = 1.0f64
    y1[1usize] = 1.5f64
    y1[2usize] = 1.2f64
    y1[3usize] = 5.0f64
    y1[4usize] = 5.5f64
    y1[5usize] = 5.1f64
    y1[6usize] = 9.0f64
    y1[7usize] = 9.4f64
    var i = 0usize
    while i < 8usize {
        x1[i] = f64(i + 1usize)
        i += 1usize
    }
    let (t1, t1_error) = tree.cart(a, x1[..], y1[..], 8usize, 1usize, 0usize, 2usize, 1usize)
    if t1_error != ok || t1.count != 7usize || t1.nodes[0usize].feature != 0usize || !near(t1.nodes[0usize].threshold, 3.5f64, 0.000001f64) { os.exit(1i32) }
    var q: [2]f64 = zero
    q[0usize] = 2.5f64
    if !near(tree.predict(&t1, q[..]), 1.35f64, 0.000001f64) { os.exit(1i32) }
    q[0usize] = 4.5f64
    if !near(tree.predict(&t1, q[..]), 5.2f64, 0.000001f64) { os.exit(1i32) }
    q[0usize] = 7.5f64
    if !near(tree.predict(&t1, q[..]), 9.2f64, 0.000001f64) { os.exit(1i32) }
    let (stump, stump_error) = tree.cart(a, x1[..], y1[..], 8usize, 1usize, 0usize, 0usize, 1usize)
    if stump_error != ok || stump.count != 1usize || !near(tree.predict(&stump, q[..]), 4.7125f64, 0.000001f64) { os.exit(1i32) }
    let (_, invalid) = tree.cart(a, x1[..], y1[..], 8usize, 1usize, 0usize, 2usize, 0usize)
    if invalid != tree.Invalid { os.exit(1i32) }
    let (_, room) = tree.cart(a, x1[..], y1[..3usize], 8usize, 1usize, 0usize, 2usize, 1usize)
    if room != tree.TooSmall { os.exit(1i32) }

    // 2: a classifier on three groups of four.
    var x2: [24]f64 = zero
    x2[2usize] = 1.0f64
    x2[5usize] = 1.0f64
    x2[6usize] = 1.0f64
    x2[7usize] = 1.0f64
    x2[8usize] = 2.0f64
    x2[9usize] = 2.0f64
    x2[10usize] = 3.0f64
    x2[11usize] = 2.0f64
    x2[12usize] = 2.0f64
    x2[13usize] = 3.0f64
    x2[14usize] = 3.0f64
    x2[15usize] = 3.0f64
    x2[17usize] = 3.0f64
    x2[18usize] = 1.0f64
    x2[19usize] = 3.0f64
    x2[21usize] = 2.0f64
    x2[22usize] = 1.0f64
    x2[23usize] = 2.0f64
    var y2: [12]f64 = zero
    i = 4usize
    while i < 12usize {
        y2[i] = 1.0f64
        if i >= 8usize { y2[i] = 2.0f64 }
        i += 1usize
    }
    let (t2, t2_error) = tree.cart(a, x2[..], y2[..], 12usize, 2usize, 3usize, 3usize, 1usize)
    // Either feature splits class 0 off at 1.5 with the same gain; scikit-learn breaks the tie at random.
    if t2_error != ok || t2.count != 5usize || t2.nodes[0usize].feature > 1usize || !near(t2.nodes[0usize].threshold, 1.5f64, 0.000001f64) { os.exit(2i32) }
    q[0usize] = 0.5f64
    q[1usize] = 0.5f64
    if tree.predict(&t2, q[..]) != 0.0f64 { os.exit(2i32) }
    q[0usize] = 2.5f64
    q[1usize] = 2.5f64
    if tree.predict(&t2, q[..]) != 1.0f64 { os.exit(2i32) }
    q[0usize] = 0.5f64
    q[1usize] = 2.5f64
    if tree.predict(&t2, q[..]) != 2.0f64 { os.exit(2i32) }

    // 3: a random forest on the same groups, one random feature per split.
    var r = rand.pcg64(9u64, 1u64)
    let (forest, forest_error) = tree.random_forest(a, x2[..], y2[..], 12usize, 2usize, 3usize, 25usize, 1usize, 4usize, 1usize, &r)
    if forest_error != ok || forest.count != 25usize { os.exit(3i32) }
    var bins: [3]usize = zero
    var wrong = 0usize
    i = 0usize
    while i < 12usize {
        let (vote, vote_error) = tree.forest_predict(&forest, x2[2usize * i..2usize * i + 2usize], bins[..])
        if vote_error != ok { os.exit(3i32) }
        if vote != y2[i] { wrong += 1usize }
        i += 1usize
    }
    if wrong != 0usize { os.exit(3i32) }
    let (_, vote_room) = tree.forest_predict(&forest, x2[..2usize], bins[..2usize])
    if vote_room != tree.TooSmall { os.exit(3i32) }
    let (_, forest_invalid) = tree.random_forest(a, x2[..], y2[..], 12usize, 2usize, 3usize, 0usize, 1usize, 4usize, 1usize, &r)
    if forest_invalid != tree.Invalid { os.exit(3i32) }
    // A regression forest averages.
    let (rf, rf_error) = tree.random_forest(a, x1[..], y1[..], 8usize, 1usize, 0usize, 10usize, 1usize, 3usize, 1usize, &r)
    if rf_error != ok { os.exit(3i32) }
    q[0usize] = 7.5f64
    let (mean, mean_error) = tree.forest_predict(&rf, q[..], bins[..])
    if mean_error != ok || mean < 8.5f64 || mean > 9.5f64 { os.exit(3i32) }

    // 4: gradient boosting.
    var residuals: [8]f64 = zero
    let (boost, boost_error) = tree.gradient_boost(a, x1[..], y1[..], 8usize, 1usize, 30usize, 0.3f64, 1usize, 1usize, residuals[..])
    if boost_error != ok || boost.count != 30usize || !near(boost.base, 4.7125f64, 0.000001f64) { os.exit(4i32) }
    var total = 0.0f64
    i = 0usize
    while i < 8usize {
        let d = tree.boost_predict(&boost, x1[i..i + 1usize]) - y1[i]
        total += d * d
        i += 1usize
    }
    if total > 0.5f64 { os.exit(4i32) }
    let (short, short_error) = tree.gradient_boost(a, x1[..], y1[..], 8usize, 1usize, 3usize, 0.3f64, 1usize, 1usize, residuals[..])
    if short_error != ok { os.exit(4i32) }
    var short_total = 0.0f64
    i = 0usize
    while i < 8usize {
        let d = tree.boost_predict(&short, x1[i..i + 1usize]) - y1[i]
        short_total += d * d
        i += 1usize
    }
    if short_total <= total { os.exit(4i32) }
    let (_, boost_room) = tree.gradient_boost(a, x1[..], y1[..], 8usize, 1usize, 3usize, 0.3f64, 1usize, 1usize, residuals[..4usize])
    if boost_room != tree.TooSmall { os.exit(4i32) }

    try io.print("ml tree ok\n")
    ret ok
}
