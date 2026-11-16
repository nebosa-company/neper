// R leaps::regsubsets with nbest = 1: the best subset of each size by residual sum of squares, by exhaustive search,
// forward selection or backward elimination, and the summary statistics (rsq, adjusted r squared, Mallows Cp, BIC) as
// summary.regsubsets defines them, all with an intercept.
//
// Not here: seqrep, nbest > 1, force.in and force.out, weights, the branch-and-bound of the package (an exhaustive
// enumeration returns the same subsets; it is exponential in the number of variables).

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

// the residual sum of squares of y on an intercept and the columns of x selected by `mask` (bit j = column j)
fn subset_rss(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, mask: u32) -> f64 {
    var k = 0usize
    var j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 { k += 1usize }
        j += 1usize
    }
    let (d, e1) = mem.alloc[f64](a, n * (k + 1usize))
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    var c = 1usize
    j = 0usize
    while j < p {
        if (mask >> u32(j)) & 1u32 == 1u32 {
            i = 0usize
            while i < n {
                d[c * n + i] = x[j * n + i]
                i += 1usize
            }
            c += 1usize
        }
        j += 1usize
    }
    let (fit, fe) = decomp.lm_fit(a, d, n, k + 1usize, y, 1.0e-11f64)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret s
}

fn popcount(m: u32) -> usize {
    var c = 0usize
    var t = m
    while t > 0u32 {
        c += usize(t & 1u32)
        t = t >> 1u32
    }
    ret c
}

// method 0 exhaustive, 1 forward, 2 backward; masks[k - 1] and rss[k - 1] receive the best subset of k variables
fn regsubsets(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nvmax: usize, method: u8, masks: []u32, rss: []f64) {
    let total = u32(1usize << p)
    if method == 0u8 {
        var k = 1usize
        while k <= nvmax {
            var best = 1.0e300f64
            var bm = 0u32
            var m = 1u32
            while m < total {
                if popcount(m) == k {
                    let r = subset_rss(a, x, y, n, p, m)
                    if r < best {
                        best = r
                        bm = m
                    }
                }
                m += 1u32
            }
            masks[k - 1usize] = bm
            rss[k - 1usize] = best
            k += 1usize
        }
        ret
    }
    if method == 1u8 {
        var cur = 0u32
        var k = 1usize
        while k <= nvmax {
            var best = 1.0e300f64
            var bm = cur
            var j = 0usize
            while j < p {
                if (cur >> u32(j)) & 1u32 == 0u32 {
                    let cand = cur | (1u32 << u32(j))
                    let r = subset_rss(a, x, y, n, p, cand)
                    if r < best {
                        best = r
                        bm = cand
                    }
                }
                j += 1usize
            }
            cur = bm
            masks[k - 1usize] = cur
            rss[k - 1usize] = best
            k += 1usize
        }
        ret
    }
    // backward: start from all variables and drop the one whose removal costs the least
    var cur = total - 1u32
    var k = p
    while k >= 1usize {
        if k <= nvmax {
            masks[k - 1usize] = cur
            rss[k - 1usize] = subset_rss(a, x, y, n, p, cur)
        }
        if k == 1usize { break }
        var best = 1.0e300f64
        var bm = cur
        var j = 0usize
        while j < p {
            if (cur >> u32(j)) & 1u32 == 1u32 {
                let cand = cur & ~(1u32 << u32(j))
                let r = subset_rss(a, x, y, n, p, cand)
                if r < best {
                    best = r
                    bm = cand
                }
            }
            j += 1usize
        }
        cur = bm
        k -= 1usize
    }
}

// summary.regsubsets for a model of k variables with residual sum of squares rss: (rsq, adjr2, cp, bic);
// nullrss the centred total sum of squares and fullrss the residual sum of squares of the model with all p variables
fn summarise(n: usize, p: usize, k: usize, rss: f64, nullrss: f64, fullrss: f64) -> (f64, f64, f64, f64) {
    let n1 = f64(n - 1usize)
    let i = f64(k + 1usize)
    let vr = rss / nullrss
    let sigma2 = fullrss / (n1 + 1.0f64 - f64(p + 1usize))
    let adj = 1.0f64 - vr * n1 / (n1 + 1.0f64 - i)
    let cp = rss / sigma2 - (n1 + 1.0f64 - 2.0f64 * i)
    let bic = (n1 + 1.0f64) * math.log[f64](vr) + i * math.log[f64](n1 + 1.0f64)
    ret (1.0f64 - vr, adj, cp, bic)
}
