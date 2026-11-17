// R mclust: hcRandomPairs(data, seed) (hc with use = "RND"): random merge pairs from set.seed(seed).
//
// out receives the merge entries of the m - 1 columns (m = n or n - 1, the largest even number), column by column, one-based observation names, the smaller first.

use e.mem
use e.algo.rand.r as rng

fn hc_random_pairs(a: *mem.Arena, n: usize, seed: i64, out: []usize) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var m = n
    if n % 2usize == 1usize { m = n - 1usize }
    let (first, e1) = rng.sample_int(a, &r, i64(n), i64(m), false)
    if e1 != ok { ret e1 }
    let (ind, e2) = mem.alloc[usize](a, m)
    if e2 != ok { ret e2 }
    let half = m / 2usize
    var c = 0usize
    while c < half {
        var lo = usize(first[2usize * c])
        var hi = usize(first[2usize * c + 1usize])
        if hi < lo {
            let t = lo
            lo = hi
            hi = t
        }
        out[2usize * c] = lo
        out[2usize * c + 1usize] = hi
        ind[c] = lo
        c += 1usize
    }
    var nind = half
    var cols = half
    while cols < m - 1usize {
        let (pick, e3) = rng.sample_int(a, &r, i64(nind), 2i64, false)
        if e3 != ok { ret e3 }
        var lo = ind[usize(pick[0usize]) - 1usize]
        var hi = ind[usize(pick[1usize]) - 1usize]
        if hi < lo {
            let t = lo
            lo = hi
            hi = t
        }
        out[2usize * cols] = lo
        out[2usize * cols + 1usize] = hi
        // setdiff(ind, hi): drop hi, keep the order
        var w = 0usize
        var q = 0usize
        while q < nind {
            if ind[q] != hi {
                ind[w] = ind[q]
                w += 1usize
            }
            q += 1usize
        }
        nind = w
        cols += 1usize
    }
    ret ok
}
