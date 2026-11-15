// The break rules of R's classInt::classIntervals that need no random numbers: fixed, sd, equal,
// pretty, quantile (types 1 to 9), jenks, fisher, headtails, maximum and box, plus `find_cols`
// (the class of each value, left or right closed). Each rule answers the breaks, ascending.
//
// Not here: kmeans, hclust, bclust (they take R's clustering code and random starts) and dpih
// (KernSmooth's bandwidth), and the sampling classInt imposes past 3000 values for jenks and
// fisher: the caller samples.

use e.algo.sort
use e.math
use e.math.scale
use e.mem

error Unsupported
error SingleValue
error TooFew

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sort_up(d: []f64) {
    var ctx = 0u8
    sort.in_place_by[f64, u8](d, &ctx, cmp_up)
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (d, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (d, e) }
    var i = 0usize
    while i < x.len {
        d[i] = x[i]
        i += 1usize
    }
    sort_up(d)
    ret (d, ok)
}

fn distinct(sorted: []const f64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < sorted.len {
        if i == 0usize || sorted[i] != sorted[i - 1usize] { n += 1usize }
        i += 1usize
    }
    ret n
}

// nclass.Sturges: ceiling(log2(n) + 1).
fn nclass_sturges(n: usize) -> usize { ret usize(math.ceil[f64](math.log2[f64](f64(n)) + 1.0f64)) }

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    var m = s / f64(x.len)
    var t = 0.0f64
    i = 0usize
    while i < x.len {
        t += x[i] - m
        i += 1usize
    }
    m += t / f64(x.len)
    ret m
}

fn sd_of(x: []const f64, m: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

// seq(min, max, length.out = n + 1)
fn equal(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let lo = s[0usize]
    let hi = s[s.len - 1usize]
    let (b, be) = mem.alloc[f64](a, n + 1usize)
    if be != ok { ret (b, be) }
    let by = (hi - lo) / f64(n)
    var i = 1usize
    b[0usize] = lo
    while i < n {
        b[i] = lo + f64(i) * by
        i += 1usize
    }
    b[n] = hi
    ret (b, ok)
}

// c(pretty(x, n))
fn pretty_breaks(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let (p, pe) = scale.pretty(a, s[0usize], s[s.len - 1usize], i64(n))
    ret (p, pe)
}

// pretty(scale(x), n) mapped back; the ends that are not finite become the range of x.
fn sd_breaks(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let m = mean_of(x)
    let sd = sd_of(x, m)
    let (z, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (z, e) }
    var i = 0usize
    var lo = 1.0e300f64
    var hi = 0.0f64 - 1.0e300f64
    while i < x.len {
        z[i] = (x[i] - m) / sd
        if z[i] < lo { lo = z[i] }
        if z[i] > hi { hi = z[i] }
        i += 1usize
    }
    let (p, pe) = scale.pretty(a, lo, hi, i64(n))
    if pe != ok { ret (p, pe) }
    i = 0usize
    while i < p.len {
        p[i] = p[i] * sd + m
        i += 1usize
    }
    ret (p, ok)
}

// R's quantile(x, p, type) for one probability on an ascending sample.
fn quantile_r(s: []const f64, p: f64, qtype: u8) -> f64 {
    let n = s.len
    let nf = f64(n)
    if qtype == 7u8 {
        var mx = nf - 1.0f64
        if mx < 0.0f64 { mx = 0.0f64 }
        let index = 1.0f64 + mx * p
        let lo = math.floor[f64](index)
        let hi = math.ceil[f64](index)
        let q = s[usize(lo) - 1usize]
        let xh = s[usize(hi) - 1usize]
        if index > lo && xh != q {
            let h = index - lo
            ret (1.0f64 - h) * q + h * xh
        }
        ret q
    }
    let fuzz = 4.0f64 * eps()
    var j = 0.0f64
    var h = 0.0f64
    if qtype <= 3u8 {
        var nppm = nf * p
        if qtype == 3u8 { nppm = nf * p - 0.5f64 }
        j = math.floor[f64](nppm * (1.0f64 + fuzz))
        if qtype == 1u8 {
            if nppm > j { h = 1.0f64 }
        } else if qtype == 2u8 {
            if nppm > j { h = 1.0f64 } else { h = 0.5f64 }
        } else {
            let odd = (i64(j) % 2i64 + 2i64) % 2i64 == 1i64
            if nppm != j || odd { h = 1.0f64 }
        }
    } else {
        var aa = 0.0f64
        var bb = 1.0f64
        if qtype == 5u8 {
            aa = 0.5f64
            bb = 0.5f64
        } else if qtype == 6u8 {
            aa = 0.0f64
            bb = 0.0f64
        } else if qtype == 8u8 {
            aa = 1.0f64 / 3.0f64
            bb = 1.0f64 / 3.0f64
        } else if qtype == 9u8 {
            aa = 0.375f64
            bb = 0.375f64
        }
        let nppm = aa + p * (nf + 1.0f64 - aa - bb)
        j = math.floor[f64](nppm * (1.0f64 + fuzz))
        h = nppm - j
        if math.abs[f64](h) < fuzz { h = 0.0f64 }
    }
    // x padded as c(x[1], x[1], x, x[n], x[n]); x[j + 2] is s[j - 1]
    let k = i64(j)
    let lo = padded(s, k)
    let hi = padded(s, k + 1i64)
    var qs = lo
    if h == 1.0f64 { qs = hi }
    if h > 0.0f64 && h < 1.0f64 && lo != hi { qs = (1.0f64 - h) * lo + h * hi }
    ret qs
}

// element j (1-based) of x padded with two copies of each end
fn padded(s: []const f64, j: i64) -> f64 {
    if j < 1i64 { ret s[0usize] }
    if j > i64(s.len) { ret s[s.len - 1usize] }
    ret s[usize(j) - 1usize]
}

// Types 1 to 9 are R's; type 7 is the default. Type 4 is a = 0, b = 1, and so on as quantile() says.
fn quantile_breaks(a: *mem.Arena, x: []const f64, n: usize, qtype: u8) -> ([]f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let (b, be) = mem.alloc[f64](a, n + 1usize)
    if be != ok { ret (b, be) }
    var i = 0usize
    while i <= n {
        var pr = f64(i) * (1.0f64 / f64(n))
        if i == n { pr = 1.0f64 }
        b[i] = quantile_r(s, pr, qtype)
        i += 1usize
    }
    ret (b, ok)
}

// brks of style "jenks": R's own loops over the sorted values, classes closed on the right.
fn jenks(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (d, e) = sorted_copy(a, x)
    if e != ok { ret (d, e) }
    let m = d.len
    let (mat1, e1) = mem.alloc[f64](a, m * k)
    if e1 != ok { ret (d, e1) }
    let (mat2, e2) = mem.alloc[f64](a, m * k)
    if e2 != ok { ret (d, e2) }
    var i = 0usize
    while i < m * k {
        mat1[i] = 1.0f64
        mat2[i] = 0.0f64
        i += 1usize
    }
    var l = 1usize
    while l < m {
        var j = 0usize
        while j < k {
            mat2[l * k + j] = 1.7976931348623157e308f64
            j += 1usize
        }
        l += 1usize
    }
    var v = 0.0f64
    l = 2usize
    while l <= m {
        var s1 = 0.0f64
        var s2 = 0.0f64
        var w = 0.0f64
        var mm = 1usize
        while mm <= l {
            let i3 = l - mm + 1usize
            let val = d[i3 - 1usize]
            s2 += val * val
            s1 += val
            w += 1.0f64
            v = s2 - (s1 * s1) / w
            let i4 = i3 - 1usize
            if i4 != 0usize {
                var j = 2usize
                while j <= k {
                    if mat2[(l - 1usize) * k + (j - 1usize)] >= v + mat2[(i4 - 1usize) * k + (j - 2usize)] {
                        mat1[(l - 1usize) * k + (j - 1usize)] = f64(i3)
                        mat2[(l - 1usize) * k + (j - 1usize)] = v + mat2[(i4 - 1usize) * k + (j - 2usize)]
                    }
                    j += 1usize
                }
            }
            mm += 1usize
        }
        mat1[(l - 1usize) * k] = 1.0f64
        mat2[(l - 1usize) * k] = v
        l += 1usize
    }
    let (kc, ke) = mem.alloc[usize](a, k)
    if ke != ok { ret (d, ke) }
    kc[k - 1usize] = m
    var kk = m
    var j = k
    while j >= 2usize {
        let id = usize(mat1[(kk - 1usize) * k + (j - 1usize)]) - 1usize
        kc[j - 2usize] = id
        kk = id
        j -= 1usize
    }
    let (b, be) = mem.alloc[f64](a, k + 1usize)
    if be != ok { ret (b, be) }
    b[0usize] = d[0usize]
    i = 0usize
    while i < k {
        b[i + 1usize] = d[kc[i] - 1usize]
        i += 1usize
    }
    ret (b, ok)
}

// Fisher's exact partition of the sorted values into k contiguous classes of least within-class
// sum of squares; the breaks are the class ends, with a midpoint between the classes.
fn fisher(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (d, e) = sorted_copy(a, x)
    if e != ok { ret (d, e) }
    let m = d.len
    let (c1, e1) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok { ret (d, e1) }
    let (c2, e2) = mem.alloc[f64](a, m + 1usize)
    if e2 != ok { ret (d, e2) }
    var i = 0usize
    c1[0usize] = 0.0f64
    c2[0usize] = 0.0f64
    while i < m {
        c1[i + 1usize] = c1[i] + d[i]
        c2[i + 1usize] = c2[i] + d[i] * d[i]
        i += 1usize
    }
    let (cost, e3) = mem.alloc[f64](a, (k + 1usize) * (m + 1usize))
    if e3 != ok { ret (d, e3) }
    let (cut, e4) = mem.alloc[usize](a, (k + 1usize) * (m + 1usize))
    if e4 != ok { ret (d, e4) }
    i = 0usize
    while i < (k + 1usize) * (m + 1usize) {
        cost[i] = 1.0e308f64
        cut[i] = 0usize
        i += 1usize
    }
    cost[0usize] = 0.0f64
    var q = 1usize
    while q <= k {
        var n = q
        while n <= m {
            var best = 1.0e308f64
            var at = q - 1usize
            var s = q - 1usize
            while s < n {
                let prev = cost[(q - 1usize) * (m + 1usize) + s]
                if prev < 1.0e308f64 {
                    let w = f64(n - s)
                    let sum = c1[n] - c1[s]
                    let ss = (c2[n] - c2[s]) - sum * sum / w
                    let t = prev + ss
                    if t < best {
                        best = t
                        at = s
                    }
                }
                s += 1usize
            }
            cost[q * (m + 1usize) + n] = best
            cut[q * (m + 1usize) + n] = at
            n += 1usize
        }
        q += 1usize
    }
    let (b, be) = mem.alloc[f64](a, k + 1usize)
    if be != ok { ret (b, be) }
    var end = m
    q = k
    b[k] = d[m - 1usize]
    while q >= 1usize {
        let s = cut[q * (m + 1usize) + end]
        if q > 1usize {
            b[q - 1usize] = (d[s - 1usize] + d[s]) / 2.0f64
        } else {
            b[0usize] = d[0usize]
        }
        end = s
        q -= 1usize
    }
    ret (b, ok)
}

fn headtails(a: *mem.Arena, x: []const f64, thr0: f64) -> ([]f64, err) {
    var thr = thr0
    if thr > 1.0f64 { thr = 1.0f64 }
    if thr < 0.0f64 { thr = 0.0f64 }
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let (out, oe) = mem.alloc[f64](a, 102usize)
    if oe != ok { ret (out, oe) }
    var nb = 0usize
    out[nb] = s[0usize]
    nb += 1usize
    var head = s
    var iter = 0usize
    while iter < 100usize {
        let mu = mean_of(head)
        out[nb] = mu
        nb += 1usize
        let ntot = head.len
        var first = 0usize
        while first < head.len && !(head[first] > mu) { first += 1usize }
        head = head[first..head.len]
        let prop = f64(head.len) / f64(ntot)
        if !(prop <= thr && head.len > 1usize) { break }
        iter += 1usize
    }
    out[nb] = s[s.len - 1usize]
    nb += 1usize
    sort_up(out[0usize..nb])
    var u = 0usize
    var i = 0usize
    while i < nb {
        if u == 0usize || out[i] != out[u - 1usize] {
            out[u] = out[i]
            u += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..u], ok)
}

fn maximum(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let m = s.len - 1usize
    let (diffs, de) = mem.alloc[f64](a, m)
    if de != ok { ret (s, de) }
    let (sd, se) = mem.alloc[f64](a, m)
    if se != ok { ret (s, se) }
    var i = 0usize
    while i < m {
        diffs[i] = s[i + 1usize] - s[i]
        sd[i] = diffs[i]
        i += 1usize
    }
    sort_up(sd)
    // the n - 1 largest differences, every position whose difference is one of those values
    let (b, be) = mem.alloc[f64](a, n + m + 1usize)
    if be != ok { ret (s, be) }
    var nb = 0usize
    b[nb] = s[0usize]
    nb += 1usize
    i = 0usize
    while i < m {
        var hit = false
        var t = 0usize
        while t < n - 1usize {
            if diffs[i] == sd[m - 1usize - t] { hit = true }
            t += 1usize
        }
        if hit {
            b[nb] = (s[i + 1usize] + s[i]) / 2.0f64
            nb += 1usize
        }
        i += 1usize
    }
    b[nb] = s[s.len - 1usize]
    nb += 1usize
    ret (b[0usize..nb], ok)
}

// style "box": seven breaks from the five-number summary and the fences; legacy keeps finite
// outer breaks at the floor and ceiling of the extremes.
fn box(a: *mem.Arena, x: []const f64, iqr_mult: f64, qtype: u8, legacy: bool) -> ([]f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (s, e) }
    let (bb, be) = mem.alloc[f64](a, 7usize)
    if be != ok { ret (bb, be) }
    var q: [5]f64 = zero
    var i = 0usize
    while i < 5usize {
        q[i] = quantile_r(s, f64(i) / 4.0f64, qtype)
        i += 1usize
    }
    let iqr = iqr_mult * (q[3usize] - q[1usize])
    let up = q[3usize] + iqr
    let lo = q[1usize] - iqr
    let inf = 1.0f64 / 0.0f64
    if lo < q[0usize] {
        if legacy {
            bb[0usize] = lo
            bb[1usize] = math.floor[f64](q[0usize])
        } else {
            bb[0usize] = 0.0f64 - inf
            bb[1usize] = lo
        }
    } else {
        bb[1usize] = lo
        bb[0usize] = q[0usize]
    }
    if up > q[4usize] {
        if legacy {
            bb[6usize] = up
            bb[5usize] = math.ceil[f64](q[4usize])
        } else {
            bb[6usize] = inf
            bb[5usize] = up
        }
    } else {
        bb[5usize] = up
        bb[6usize] = q[4usize]
    }
    bb[2usize] = q[1usize]
    bb[3usize] = q[2usize]
    bb[4usize] = q[3usize]
    ret (bb, ok)
}

// findCols: the 0-based class of x for ascending breaks, `left` closed on the left (the last class
// also closes on the right) or on the right (the first also closes on the left); -1 outside.
fn find_cols(brks: []const f64, x: f64, left: bool) -> i64 {
    let nb = brks.len
    if x != x { ret 0i64 - 1i64 }
    if left {
        if x < brks[0usize] || x > brks[nb - 1usize] { ret 0i64 - 1i64 }
        var i = nb - 1usize
        while i >= 1usize {
            if x >= brks[i - 1usize] && (x < brks[i] || (i == nb - 1usize && x == brks[i])) { ret i64(i) - 1i64 }
            i -= 1usize
        }
        ret 0i64 - 1i64
    }
    if x < brks[0usize] || x > brks[nb - 1usize] { ret 0i64 - 1i64 }
    var i = 1usize
    while i < nb {
        if x <= brks[i] && (x > brks[i - 1usize] || (i == 1usize && x == brks[0usize])) { ret i64(i) - 1i64 }
        i += 1usize
    }
    ret 0i64 - 1i64
}
