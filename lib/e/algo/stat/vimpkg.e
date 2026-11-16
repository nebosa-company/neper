// R VIM::kNN for one numeric variable: each missing value takes the median (or mean) of the k nearest rows that have it, by Gower distance on the other columns (absolute difference over the column range, averaged). Columns are row-major, the other columns complete.
//
// Not here: missing values in the distance columns (VIM imputes those first and reuses them), factors, ordered and mixed variables, weights, donor conditions, random-forest distances.

use e.math
use e.mem

// x is n by p row-major; column v has NaN where missing; the filled column goes into out (n values)
fn knn_impute(a: *mem.Arena, x: []const f64, n: usize, p: usize, v: usize, k: usize, use_mean: bool, out: []f64) -> err {
    let (rg, e1) = mem.alloc[f64](a, p)
    let (dist, e2) = mem.alloc[f64](a, n)
    let (cand, e3) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var c = 0usize
    while c < p {
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        var i = 0usize
        while i < n {
            let t = x[i * p + c]
            if t == t {
                if t < lo { lo = t }
                if t > hi { hi = t }
            }
            i += 1usize
        }
        rg[c] = hi - lo
        c += 1usize
    }
    var i = 0usize
    while i < n {
        out[i] = x[i * p + v]
        i += 1usize
    }
    i = 0usize
    while i < n {
        if x[i * p + v] != x[i * p + v] {
            var m = 0usize
            var j = 0usize
            while j < n {
                if x[j * p + v] == x[j * p + v] {
                    var s = 0.0f64
                    c = 0usize
                    while c < p {
                        if c != v { s += math.abs[f64](x[i * p + c] - x[j * p + c]) / rg[c] }
                        c += 1usize
                    }
                    dist[j] = s / f64(p - 1usize)
                    // insertion into cand ordered by (distance, index)
                    var q = m
                    while q > 0usize && dist[cand[q - 1usize]] > dist[j] {
                        cand[q] = cand[q - 1usize]
                        q -= 1usize
                    }
                    cand[q] = j
                    m += 1usize
                }
                j += 1usize
            }
            var kk = k
            if m < kk { kk = m }
            var s = 0.0f64
            if use_mean {
                var q = 0usize
                while q < kk {
                    s += x[cand[q] * p + v]
                    q += 1usize
                }
                out[i] = s / f64(kk)
            } else {
                // the median of the kk donor values
                var q = 0usize
                while q < kk {
                    var r = q
                    while r > 0usize && x[cand[r - 1usize] * p + v] > x[cand[r] * p + v] {
                        let t = cand[r]
                        cand[r] = cand[r - 1usize]
                        cand[r - 1usize] = t
                        r -= 1usize
                    }
                    q += 1usize
                }
                if kk % 2usize == 1usize {
                    out[i] = x[cand[kk / 2usize] * p + v]
                } else {
                    out[i] = (x[cand[kk / 2usize - 1usize] * p + v] + x[cand[kk / 2usize] * p + v]) / 2.0f64
                }
            }
        }
        i += 1usize
    }
    ret ok
}
