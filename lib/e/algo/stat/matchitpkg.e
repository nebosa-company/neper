// R MatchIt method = "nearest" without replacement on a logistic propensity score (distance = "glm"): treated units in decreasing score order each take the nearest unmatched control, ratio passes, matched units weight 1, unmatched controls 0 (without replacement MatchIt does not rescale).
//
// Not here: matching with replacement, calipers, exact and mahalanobis distances, subclassification, full and optimal matching, genetic matching, balance summaries.

use e.algo.stat.rmspkg as rm
use e.math
use e.mem

// t is 0/1, x is n by p without a constant; w receives the matching weights, ps the fitted propensity scores
fn nearest(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, ratio: usize, w: []f64, ps: []f64) -> err {
    let (out, e1) = mem.alloc[f64](a, 2usize * (p + 1usize) + 8usize)
    let (ord, e2) = mem.alloc[usize](a, n)
    let (used, e3) = mem.alloc[bool](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    let r = rm.lrm(a, x, t, n, p, out)
    if r != ok { ret r }
    var i = 0usize
    while i < n {
        var eta = out[0usize]
        var j = 0usize
        while j < p {
            eta += out[1usize + j] * x[i * p + j]
            j += 1usize
        }
        ps[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        w[i] = 0.0f64
        used[i] = false
        i += 1usize
    }
    var nt = 0usize
    i = 0usize
    while i < n {
        if t[i] > 0.5f64 {
            ord[nt] = i
            nt += 1usize
            w[i] = 1.0f64
        }
        i += 1usize
    }
    // decreasing score, ties by row
    i = 1usize
    while i < nt {
        let v = ord[i]
        var j = i
        while j > 0usize && ps[ord[j - 1usize]] < ps[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    var pass = 0usize
    while pass < ratio {
        i = 0usize
        while i < nt {
            let ti = ord[i]
            var best = n
            var bd = 1.0e300f64
            var c = 0usize
            while c < n {
                if t[c] < 0.5f64 && !used[c] {
                    let d = math.abs[f64](ps[c] - ps[ti])
                    if d < bd {
                        bd = d
                        best = c
                    }
                }
                c += 1usize
            }
            if best < n {
                used[best] = true
                w[best] = 1.0f64
            }
            i += 1usize
        }
        pass += 1usize
    }
    ret ok
}
