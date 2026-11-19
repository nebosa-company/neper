// clue::solve_LSAP and cl_membership: the linear sum assignment problem over a rectangular cost matrix, with the maximum option, and the membership matrix of a hard partition.

use e.algo.graph.match as mt
use e.mem

error Malformed

// solve_LSAP(x, maximum) for an nr by nc cost matrix with nr <= nc (row-major): the column of each row in assign (0-based) and the total cost of the matching, the cost matrix x
// for minimum and max(x) - x for maximum, as clue does. The rows are padded to a square with zero-cost dummies, which leaves the matching of the real rows optimal.
fn solve_lsap(a: *mem.Arena, x: []const f64, nr: usize, nc: usize, maximum: bool, assign: []usize) -> (f64, err) {
    if nr > nc { ret (0.0f64, Malformed) }
    let (sq, e0) = mem.alloc[f64](a, nc * nc)
    let (asg, e1) = mem.alloc[usize](a, nc)
    let (scr, e2) = mem.alloc[f64](a, 4usize * (nc + 1usize))
    let (used, e3) = mem.alloc[usize](a, 2usize * (nc + 1usize))
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, mem.Full) }
    var top = x[0usize]
    var k = 0usize
    while k < nr * nc {
        if x[k] > top { top = x[k] }
        k += 1usize
    }
    k = 0usize
    while k < nc * nc {
        sq[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < nr * nc {
        sq[k] = x[k]
        if maximum { sq[k] = top - x[k] }
        k += 1usize
    }
    let (v, e4) = mt.hungarian(sq, nc, asg, scr, used)
    if e4 != ok { ret (0.0f64, e4) }
    let _ = v
    var total = 0.0f64
    var i = 0usize
    while i < nr {
        assign[i] = asg[i]
        total += x[i * nc + asg[i]]
        i += 1usize
    }
    ret (total, ok)
}

// cl_membership of a hard partition: the n by k indicator matrix (row-major, zeroed here) of the class labels cx in 1..k
fn membership_hard(cx: []const usize, n: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < n * k {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i * k + cx[i] - 1usize] = 1.0f64
        i += 1usize
    }
}
