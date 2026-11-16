// R kSamples: the Anderson-Darling k-sample statistic of Scholz and Stephens, both versions ad.test reports (version 1 with every tie counted as one block,
// version 2 with the mid-rank adjustment), and the standardised T.AD = (AD - (k - 1)) / sigma_N.
//
// Not here: the asymptotic, exact and simulated p-values, qn.test, contingency2xt and the distribution functions behind them.

use e.math
use e.mem

fn sorted_pool(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// the scale sigma_N of the statistic's null distribution
fn sigma_n(sizes: []const usize) -> f64 {
    let k = f64(sizes.len)
    var nn = 0usize
    var hh = 0.0f64
    var i = 0usize
    while i < sizes.len {
        nn += sizes[i]
        hh += 1.0f64 / f64(sizes[i])
        i += 1usize
    }
    let n = f64(nn)
    var h = 0.0f64
    i = 1usize
    while i < nn {
        h += 1.0f64 / f64(i)
        i += 1usize
    }
    var g = 0.0f64
    i = 1usize
    while i + 1usize < nn {
        var j = i + 1usize
        while j < nn {
            g += 1.0f64 / (f64(nn - i) * f64(j))
            j += 1usize
        }
        i += 1usize
    }
    let a = (4.0f64 * g - 6.0f64) * (k - 1.0f64) + (10.0f64 - 6.0f64 * g) * hh
    let b = (2.0f64 * g - 4.0f64) * k * k + 8.0f64 * h * k + (2.0f64 * g - 14.0f64 * h - 4.0f64) * hh - 8.0f64 * h + 4.0f64 * g - 6.0f64
    let c = (6.0f64 * h + 2.0f64 * g - 2.0f64) * k * k + (4.0f64 * h - 4.0f64 * g + 6.0f64) * k + (2.0f64 * h - 6.0f64) * hh + 4.0f64 * h
    let d = (2.0f64 * h + 6.0f64) * k * k - 4.0f64 * h * k
    ret math.sqrt[f64]((a * n * n * n + b * n * n + c * n + d) / ((n - 1.0f64) * (n - 2.0f64) * (n - 3.0f64)))
}

// ad.test over k samples stored back to back in x with their sizes: version 1 or 2; part 0 the AD statistic, 1 the standardised T.AD
fn ad_test(a: *mem.Arena, x: []const f64, sizes: []const usize, version: usize, part: usize) -> f64 {
    let k = sizes.len
    let nn = x.len
    let n = f64(nn)
    let (z, e) = sorted_pool(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var total = 0.0f64
    var si = 0usize
    var off = 0usize
    while si < k {
        let ni = f64(sizes[si])
        var sub = 0.0f64
        var lo = 0usize
        // walk the distinct pooled values; B counts the pooled values up to and including this block
        while lo < nn {
            var hi = lo
            while hi < nn && z[hi] == z[lo] { hi += 1usize }
            let l = f64(hi - lo)
            let b = f64(hi)
            var fi = 0.0f64
            var le = 0.0f64
            var q = 0usize
            while q < sizes[si] {
                let v = x[off + q]
                if v == z[lo] { fi += 1.0f64 }
                if v <= z[lo] { le += 1.0f64 }
                q += 1usize
            }
            if version == 1usize {
                if hi < nn {
                    let d = n * le - ni * b
                    sub += l * d * d / (b * (n - b))
                }
            } else {
                let ba = b - l / 2.0f64
                let m = le - fi / 2.0f64
                let d = n * m - ni * ba
                sub += l * d * d / (ba * (n - ba) - n * l / 4.0f64)
            }
            lo = hi
        }
        total += sub / ni
        off += sizes[si]
        si += 1usize
    }
    var ad = 0.0f64
    if version == 1usize { ad = total / n } else { ad = (n - 1.0f64) / (n * n) * total }
    if part == 0usize { ret ad }
    ret (ad - f64(k - 1usize)) / sigma_n(sizes)
}
