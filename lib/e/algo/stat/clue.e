// R clue, the partition measures: the Rand agreement of two partitions (1 + (sum n_ij^2 - (sum a_i^2 + sum b_j^2) / 2) / choose(n, 2) on the contingency
// table, with classes labelled 1..k) and the minimal Euclidean membership distance of two hard partitions (the membership matrices, each class of
// the first matched to a class of the second by solve_LSAP on their cross-products, then the root of the summed squared differences).
//
// Not here: the hierarchy measures, the other agreement and dissimilarity methods, consensus and membership of soft partitions.

use e.algo.graph.match as mt
use e.math
use e.mem

error Malformed

// the contingency table of the labels cx (in 1..kx) and cy (in 1..ky), kx * ky counts row-major, zeroed by the caller
fn table_counts(cx: []const usize, cy: []const usize, n: usize, kx: usize, ky: usize, t: []usize) {
    var r = 0usize
    while r < n {
        t[(cx[r] - 1usize) * ky + (cy[r] - 1usize)] += 1usize
        r += 1usize
    }
}

// clue's Rand agreement of two partitions of n objects, with k the larger class count
fn rand_agreement(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, k: usize) -> (f64, err) {
    let (t, e1) = mem.alloc[usize](a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    var sij = 0.0f64
    var sa = 0.0f64
    var sb = 0.0f64
    var i = 0usize
    while i < k {
        var rowsum = 0.0f64
        var colsum = 0.0f64
        var j = 0usize
        while j < k {
            let v = f64(t[i * k + j])
            sij += v * v
            rowsum += v
            colsum += f64(t[j * k + i])
            j += 1usize
        }
        sa += rowsum * rowsum
        sb += colsum * colsum
        i += 1usize
    }
    let nf = f64(n)
    let choose2 = nf * (nf - 1.0f64) / 2.0f64
    ret (1.0f64 + (sij - (sa + sb) / 2.0f64) / choose2, ok)
}

// clue's minimal Euclidean distance between the hard partitions cx and cy (labels 1..k): the square root of the summed squared differences of the
// membership matrices, with the classes of cy matched to those of cx by the maximal cross-product assignment
fn euclid_partition(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, k: usize) -> (f64, err) {
    let (t, e1) = mem.alloc[usize](a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    // cost = minus the cross-products C[i, j] = t[i, j]
    let (costs, e2) = mem.alloc[f64](a, k * k)
    let (asg, e3) = mem.alloc[usize](a, k)
    let (scratch, e4) = mem.alloc[f64](a, 4usize * (k + 1usize))
    let (used, e5) = mem.alloc[usize](a, 2usize * (k + 1usize))
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, Malformed) }
    z = 0usize
    while z < k * k {
        costs[z] = 0.0f64 - f64(t[z])
        z += 1usize
    }
    let (_, e6) = mt.hungarian(costs, k, asg, scratch, used)
    if e6 != ok { ret (0.0f64, e6) }
    // the squared differences of the membership matrices with cy's class asg[i] in place of class i
    var d2 = 0.0f64
    var r = 0usize
    while r < n {
        var i = 0usize
        while i < k {
            var mx = 0.0f64
            if cx[r] == i + 1usize { mx = 1.0f64 }
            var my = 0.0f64
            if cy[r] == asg[i] + 1usize { my = 1.0f64 }
            d2 += (mx - my) * (mx - my)
            i += 1usize
        }
        r += 1usize
    }
    ret (math.sqrt[f64](d2), ok)
}
