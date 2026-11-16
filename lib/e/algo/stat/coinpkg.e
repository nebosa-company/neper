// R coin asymptotic conditional tests: the two-sample tests with linear scores (wilcox_test, normal_test, median_test, oneway_test), the K-sample Kruskal-Wallis chi-square and Spearman's test. The statistic is the standardised group sum of scores under the permutation distribution, the group being the first level.
//
// Not here: the exact and Monte Carlo distributions, strata, maxT tests, the scale tests (Ansari, Mood, Fligner), Savage scores and the general independence_test with arbitrary transformations.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

// average ranks of x into r
fn avg_rank(a: *mem.Arena, x: []const f64, r: []f64) -> err {
    let n = x.len
    let (ord, e) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && x[ord[j - 1usize]] > x[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && x[ord[j + 1usize]] == x[ord[i]] { j += 1usize }
        let rv = (f64(i + 1usize) + f64(j + 1usize)) / 2.0f64
        var q = i
        while q <= j {
            r[ord[q]] = rv
            q += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

// scores: 0 average ranks, 1 normal scores qnorm(rank / (N + 1)), 2 median (1 above the median), 3 the values themselves
fn scores(a: *mem.Arena, y: []const f64, kind: usize, s: []f64) -> err {
    let n = y.len
    if kind == 3usize {
        var i = 0usize
        while i < n {
            s[i] = y[i]
            i += 1usize
        }
        ret ok
    }
    let e = avg_rank(a, y, s)
    if e != ok { ret e }
    if kind == 1usize {
        var i = 0usize
        while i < n {
            s[i] = dist.qnorm(s[i] / (f64(n) + 1.0f64), 0.0f64, 1.0f64, true, false)
            i += 1usize
        }
    }
    if kind == 2usize {
        let (srt, e2) = mem.alloc[f64](a, n)
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            srt[i] = y[i]
            i += 1usize
        }
        i = 1usize
        while i < n {
            let t = srt[i]
            var j = i
            while j > 0usize && srt[j - 1usize] > t {
                srt[j] = srt[j - 1usize]
                j -= 1usize
            }
            srt[j] = t
            i += 1usize
        }
        var med = srt[n / 2usize]
        if n % 2usize == 0usize { med = (srt[n / 2usize - 1usize] + srt[n / 2usize]) / 2.0f64 }
        i = 0usize
        while i < n {
            if y[i] > med { s[i] = 1.0f64 } else { s[i] = 0.0f64 }
            i += 1usize
        }
    }
    ret ok
}

// two-sample: z statistic and two-sided asymptotic p of the first group (g == 0) against the rest
fn two_sample(a: *mem.Arena, y: []const f64, g: []const f64, kind: usize) -> (f64, f64) {
    let n = y.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    if scores(a, y, kind, s) != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    var t = 0.0f64
    var tot = 0.0f64
    var sq = 0.0f64
    var n1 = 0.0f64
    var i = 0usize
    while i < n {
        tot += s[i]
        sq += s[i] * s[i]
        if g[i] < 0.5f64 {
            t += s[i]
            n1 += 1.0f64
        }
        i += 1usize
    }
    let nf = f64(n)
    let ev = n1 / nf * tot
    let vr = n1 * (nf - n1) / (nf * (nf - 1.0f64)) * (sq - tot * tot / nf)
    let z = (t - ev) / math.sqrt[f64](vr)
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false))
}

// K-sample Kruskal-Wallis with rank scores: the chi-square statistic and its asymptotic p on K - 1 degrees of freedom
fn kruskal(a: *mem.Arena, y: []const f64, g: []const f64, k: usize) -> (f64, f64) {
    let n = y.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    if avg_rank(a, y, s) != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += s[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (s[i] - mean) * (s[i] - mean)
        i += 1usize
    }
    var q = 0.0f64
    var gi = 0usize
    while gi < k {
        var cnt = 0.0f64
        var sm = 0.0f64
        i = 0usize
        while i < n {
            if usize(g[i]) == gi {
                cnt += 1.0f64
                sm += s[i]
            }
            i += 1usize
        }
        q += cnt * (sm / cnt - mean) * (sm / cnt - mean)
        gi += 1usize
    }
    let stat = (f64(n) - 1.0f64) * q / ss
    ret (stat, nm.pchisq(stat, f64(k - 1usize), false, false))
}

// Spearman's test: z = r sqrt(N - 1) and its two-sided asymptotic p
fn spearman(a: *mem.Arena, x: []const f64, y: []const f64) -> (f64, f64) {
    let n = x.len
    let (rx, e1) = mem.alloc[f64](a, n)
    let (ry, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    if avg_rank(a, x, rx) != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    if avg_rank(a, y, ry) != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    let m = (f64(n) + 1.0f64) / 2.0f64
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        sxy += (rx[i] - m) * (ry[i] - m)
        sxx += (rx[i] - m) * (rx[i] - m)
        syy += (ry[i] - m) * (ry[i] - m)
        i += 1usize
    }
    let z = sxy / math.sqrt[f64](sxx * syy) * math.sqrt[f64](f64(n) - 1.0f64)
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false))
}
