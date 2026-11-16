// The break rules of R classInt::classIntervals: fixed, sd, equal,
// pretty, quantile (types 1 to 9), jenks, fisher, headtails, maximum, box, hclust (complete linkage),
// dpih, kmeans (Hartigan-Wong with the R stream) and bclust (bagged clustering), plus `find_cols` (the class of each value, left or right closed). Each rule answers the
// breaks, ascending.
//
// Not here: the
// sampling classInt imposes past 3000 values for jenks and fisher: the caller samples.

use e.algo.rand.r as rng
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

// KernSmooth's linbin: linear binning of x onto `m` grid points from a to b, end observations truncated.
fn linbin(a: *mem.Arena, x: []const f64, lo: f64, hi: f64, m: usize) -> ([]f64, err) {
    let (g, e) = mem.alloc[f64](a, m)
    if e != ok { ret (g, e) }
    var i = 0usize
    while i < m {
        g[i] = 0.0f64
        i += 1usize
    }
    let delta = (hi - lo) / f64(m - 1usize)
    i = 0usize
    while i < x.len {
        let lxi = (x[i] - lo) / delta + 1.0f64
        let li = i64(lxi)
        let rem = lxi - f64(li)
        if li >= 1i64 && li < i64(m) {
            g[usize(li) - 1usize] += 1.0f64 - rem
            g[usize(li)] += rem
        }
        i += 1usize
    }
    ret (g, ok)
}

// bkfe on binned data: the kernel functional estimate of order `drv`, by the direct double sum the
// FFT in R evaluates.
fn bkfe(counts: []const f64, drv: usize, h: f64, lo: f64, hi: f64) -> f64 {
    let m = counts.len
    var n = 0.0f64
    var i = 0usize
    while i < m {
        n += counts[i]
        i += 1usize
    }
    let delta = (hi - lo) / f64(m - 1usize)
    let tau = f64(4usize + drv)
    var l = usize(math.floor[f64](tau * h / delta))
    if l > m { l = m }
    var total = 0.0f64
    var d = 0usize
    while d <= l {
        let arg = f64(d) * delta / h
        var kap = math.exp[f64](0.0f64 - 0.5f64 * arg * arg) / 2.5066282746310002f64 / math.pow[f64](h, f64(drv + 1usize))
        var h0 = 1.0f64
        var h1 = arg
        var hn = 1.0f64
        var k = 2usize
        while k <= drv {
            hn = arg * h1 - f64(k - 1usize) * h0
            h0 = h1
            h1 = hn
            k += 1usize
        }
        kap = hn * kap
        var s = 0.0f64
        var j = 0usize
        while j + d < m {
            s += counts[j] * counts[j + d]
            j += 1usize
        }
        if d == 0usize { total += kap * s } else { total += 2.0f64 * kap * s }
        d += 1usize
    }
    ret total / (n * n)
}

fn quantile7(s: []const f64, p: f64) -> f64 { ret quantile_r(s, p, 7u8) }

// dpih: the direct plug-in histogram bin width, scale estimate "minim", level 2, grid 401.
fn dpih(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    let n = f64(x.len)
    let mu = mean_of(x)
    let sdv = sd_of(x, mu)
    let iqr = (quantile7(s, 0.75f64) - quantile7(s, 0.25f64)) / 1.349f64
    var sc = sdv
    if iqr < sc { sc = iqr }
    if sc == 0.0f64 { ret (0.0f64, SingleValue) }
    let sa = (s[0usize] - mu) / sc
    let sb = (s[s.len - 1usize] - mu) / sc
    let (sx, xe) = mem.alloc[f64](a, x.len)
    if xe != ok { ret (0.0f64, xe) }
    var i = 0usize
    while i < x.len {
        sx[i] = (x[i] - mu) / sc
        i += 1usize
    }
    let (g, ge) = linbin(a, sx, sa, sb, 401usize)
    if ge != ok { ret (0.0f64, ge) }
    var alpha = math.pow[f64](2.0f64 / (5.0f64 * n), 1.0f64 / 7.0f64) * 1.4142135623730951f64
    let psi4 = bkfe(g, 4usize, alpha, sa, sb)
    alpha = math.pow[f64](0.7978845608028654f64 / (psi4 * n), 0.2f64)
    let psi2 = bkfe(g, 2usize, alpha, sa, sb)
    ret (sc * math.pow[f64](6.0f64 / (0.0f64 - psi2 * n), 1.0f64 / 3.0f64), ok)
}

// seq(lo, hi, by = h)
fn seq_by(a: *mem.Arena, lo: f64, hi: f64, h: f64) -> ([]f64, err) {
    let cnt = usize(math.floor[f64]((hi - lo) / h + 1.0e-10f64))
    let (b, e) = mem.alloc[f64](a, cnt + 1usize)
    if e != ok { ret (b, e) }
    var i = 0usize
    while i <= cnt {
        b[i] = lo + f64(i) * h
        i += 1usize
    }
    ret (b, ok)
}

fn dpih_breaks(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (h, e) = dpih(a, x)
    if e != ok {
        var none: []f64 = zero
        ret (none, e)
    }
    let (s, se) = sorted_copy(a, x)
    if se != ok { ret (s, se) }
    let (b, be) = seq_by(a, s[0usize], s[s.len - 1usize], h)
    ret (b, be)
}

// classInt's .rbrks over the per-class (min, max) pairs, classes ordered by their centre.
fn class_breaks(a: *mem.Arena, x: []const f64, label: []const usize, k: usize) -> ([]f64, err) {
    let (cen, e1) = mem.alloc[f64](a, k)
    if e1 != ok { ret (cen, e1) }
    let (cnt, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret (cen, e2) }
    let (lo, e3) = mem.alloc[f64](a, k)
    if e3 != ok { ret (cen, e3) }
    let (hi, e4) = mem.alloc[f64](a, k)
    if e4 != ok { ret (cen, e4) }
    var c = 0usize
    while c < k {
        cen[c] = 0.0f64
        cnt[c] = 0.0f64
        lo[c] = 1.0e308f64
        hi[c] = 0.0f64 - 1.0e308f64
        c += 1usize
    }
    var i = 0usize
    while i < x.len {
        let c2 = label[i]
        cen[c2] += x[i]
        cnt[c2] += 1.0f64
        if x[i] < lo[c2] { lo[c2] = x[i] }
        if x[i] > hi[c2] { hi[c2] = x[i] }
        i += 1usize
    }
    c = 0usize
    while c < k {
        cen[c] = cen[c] / cnt[c]
        c += 1usize
    }
    // classes in order of centre (stable on ties, as order() is)
    let (ord, e5) = mem.alloc[usize](a, k)
    if e5 != ok { ret (cen, e5) }
    c = 0usize
    while c < k {
        ord[c] = c
        c += 1usize
    }
    c = 1usize
    while c < k {
        var j = c
        while j > 0usize && cen[ord[j - 1usize]] > cen[ord[j]] {
            let t = ord[j]
            ord[j] = ord[j - 1usize]
            ord[j - 1usize] = t
            j -= 1usize
        }
        c += 1usize
    }
    let (b, be) = mem.alloc[f64](a, k + 1usize)
    if be != ok { ret (b, be) }
    b[0usize] = lo[ord[0usize]]
    c = 1usize
    while c < k {
        b[c] = (hi[ord[c - 1usize]] + lo[ord[c]]) / 2.0f64
        c += 1usize
    }
    b[k] = hi[ord[k - 1usize]]
    ret (b, ok)
}

// style "hclust": complete linkage on the Euclidean distances, cut into k clusters.
fn hclust_breaks(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let n = x.len
    let (d, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (d, e1) }
    let (label, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (d, e2) }
    let (live, e3) = mem.alloc[bool](a, n)
    if e3 != ok { ret (d, e3) }
    var i = 0usize
    while i < n {
        label[i] = i
        live[i] = true
        var j = 0usize
        while j < n {
            var t = x[i] - x[j]
            if t < 0.0f64 { t = 0.0f64 - t }
            d[i * n + j] = t
            j += 1usize
        }
        i += 1usize
    }
    var clusters = n
    while clusters > k {
        var best = 1.0e308f64
        var bi = 0usize
        var bj = 0usize
        i = 0usize
        while i < n {
            if live[i] {
                var j = i + 1usize
                while j < n {
                    if live[j] && d[i * n + j] < best {
                        best = d[i * n + j]
                        bi = i
                        bj = j
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        var m = 0usize
        while m < n {
            if live[m] && m != bi && m != bj {
                var v = d[bi * n + m]
                if d[bj * n + m] > v { v = d[bj * n + m] }
                d[bi * n + m] = v
                d[m * n + bi] = v
            }
            m += 1usize
        }
        live[bj] = false
        m = 0usize
        while m < n {
            if label[m] == bj { label[m] = bi }
            m += 1usize
        }
        clusters -= 1usize
    }
    // relabel to 0..k-1
    let (map, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret (d, e4) }
    var next = 0usize
    i = 0usize
    while i < n {
        map[i] = n
        i += 1usize
    }
    i = 0usize
    while i < n {
        if map[label[i]] == n {
            map[label[i]] = next
            next += 1usize
        }
        label[i] = map[label[i]]
        i += 1usize
    }
    let (cb, ce) = class_breaks(a, x, label, k)
    ret (cb, ce)
}

// --- kmeans (Hartigan and Wong, AS 136) on one variable, 1-based arrays as the Fortran has them.

fn sq(x: f64) -> f64 { ret x * x }

// the optimal-transfer stage; answers the new INDX
fn optra(a: []const f64, m: i64, c: []f64, k: i64, ic1: []i64, ic2: []i64, nc: []i64, an1: []f64, an2: []f64, ncp: []i64, d: []f64, itran: []i64, live: []i64, indx0: i64) -> i64 {
    var indx = indx0
    let big = 1.0e30f64
    var l = 1i64
    while l <= k {
        if itran[usize(l)] == 1i64 { live[usize(l)] = m + 1i64 }
        l += 1i64
    }
    var i = 1i64
    while i <= m {
        indx += 1i64
        let ui = usize(i)
        let l1 = ic1[ui]
        var l2 = ic2[ui]
        let ll = l2
        if nc[usize(l1)] != 1i64 {
            if ncp[usize(l1)] != 0i64 { d[ui] = sq(a[ui] - c[usize(l1)]) * an1[usize(l1)] }
            var r2 = sq(a[ui] - c[usize(l2)]) * an2[usize(l2)]
            l = 1i64
            while l <= k {
                let skip = (i >= live[usize(l1)] && i >= live[usize(l)]) || l == l1 || l == ll
                if !skip {
                    let rr = r2 / an2[usize(l)]
                    let dc = sq(a[ui] - c[usize(l)])
                    if !(dc >= rr) {
                        r2 = dc * an2[usize(l)]
                        l2 = l
                    }
                }
                l += 1i64
            }
            if r2 >= d[ui] {
                ic2[ui] = l2
            } else {
                indx = 0i64
                live[usize(l1)] = m + i
                live[usize(l2)] = m + i
                ncp[usize(l1)] = i
                ncp[usize(l2)] = i
                let al1 = f64(nc[usize(l1)])
                let alw = al1 - 1.0f64
                let al2 = f64(nc[usize(l2)])
                let alt = al2 + 1.0f64
                c[usize(l1)] = (c[usize(l1)] * al1 - a[ui]) / alw
                c[usize(l2)] = (c[usize(l2)] * al2 + a[ui]) / alt
                nc[usize(l1)] -= 1i64
                nc[usize(l2)] += 1i64
                an2[usize(l1)] = alw / al1
                an1[usize(l1)] = big
                if alw > 1.0f64 { an1[usize(l1)] = alw / (alw - 1.0f64) }
                an1[usize(l2)] = alt / al2
                an2[usize(l2)] = alt / (alt + 1.0f64)
                ic1[ui] = l2
                ic2[ui] = l1
            }
        }
        if indx == m { ret indx }
        i += 1i64
    }
    l = 1i64
    while l <= k {
        itran[usize(l)] = 0i64
        live[usize(l)] -= m
        l += 1i64
    }
    ret indx
}

// the quick-transfer stage; answers (INDX, whether the step limit was kept)
fn qtran(a: []const f64, m: i64, c: []f64, ic1: []i64, ic2: []i64, nc: []i64, an1: []f64, an2: []f64, ncp: []i64, d: []f64, itran: []i64, indx0: i64, imax: i64) -> (i64, bool) {
    var indx = indx0
    let big = 1.0e30f64
    var icoun = 0i64
    var istep = 0i64
    while true {
        var i = 1i64
        while i <= m {
            icoun += 1i64
            istep += 1i64
            if istep >= imax { ret (indx, false) }
            let ui = usize(i)
            let l1 = ic1[ui]
            let l2 = ic2[ui]
            if nc[usize(l1)] != 1i64 {
                if istep <= ncp[usize(l1)] { d[ui] = sq(a[ui] - c[usize(l1)]) * an1[usize(l1)] }
                if istep < ncp[usize(l1)] || istep < ncp[usize(l2)] {
                    let r2 = d[ui] / an2[usize(l2)]
                    let dd = sq(a[ui] - c[usize(l2)])
                    if !(dd >= r2) {
                        icoun = 0i64
                        indx = 0i64
                        itran[usize(l1)] = 1i64
                        itran[usize(l2)] = 1i64
                        ncp[usize(l1)] = istep + m
                        ncp[usize(l2)] = istep + m
                        let al1 = f64(nc[usize(l1)])
                        let alw = al1 - 1.0f64
                        let al2 = f64(nc[usize(l2)])
                        let alt = al2 + 1.0f64
                        c[usize(l1)] = (c[usize(l1)] * al1 - a[ui]) / alw
                        c[usize(l2)] = (c[usize(l2)] * al2 + a[ui]) / alt
                        nc[usize(l1)] -= 1i64
                        nc[usize(l2)] += 1i64
                        an2[usize(l1)] = alw / al1
                        an1[usize(l1)] = big
                        if alw > 1.0f64 { an1[usize(l1)] = alw / (alw - 1.0f64) }
                        an1[usize(l2)] = alt / al2
                        an2[usize(l2)] = alt / (alt + 1.0f64)
                        ic1[ui] = l2
                        ic2[ui] = l1
                    }
                }
            }
            if icoun == m { ret (indx, true) }
            i += 1i64
        }
    }
    ret (indx, true)
}

// kmeans(x, k) with the defaults of R (Hartigan-Wong, nstart 1, iter.max 10): centres from sample.int,
// then from unique(x) when two coincide. Answers the class breaks of classInt style "kmeans".
fn kmeans_labels(a: *mem.Arena, r: *rng.Rng, x: []const f64, kk: usize) -> ([]usize, err) {
    let m = x.len
    var none: []usize = zero
    let (pick, pe) = rng.sample_int(a, r, i64(m), i64(kk), false)
    if pe != ok { ret (none, pe) }
    let (cen, ce) = mem.alloc[f64](a, kk + 1usize)
    if ce != ok { ret (none, ce) }
    var i = 0usize
    var dup = false
    while i < kk {
        cen[i + 1usize] = x[usize(pick[i]) - 1usize]
        var j = 0usize
        while j < i {
            if cen[j + 1usize] == cen[i + 1usize] { dup = true }
            j += 1usize
        }
        i += 1usize
    }
    if dup {
        let (u, ue) = mem.alloc[f64](a, m)
        if ue != ok { ret (none, ue) }
        var nu = 0usize
        i = 0usize
        while i < m {
            var seen = false
            var j = 0usize
            while j < nu {
                if u[j] == x[i] { seen = true }
                j += 1usize
            }
            if !seen {
                u[nu] = x[i]
                nu += 1usize
            }
            i += 1usize
        }
        let (pick2, pe2) = rng.sample_int(a, r, i64(nu), i64(kk), false)
        if pe2 != ok { ret (none, pe2) }
        i = 0usize
        while i < kk {
            cen[i + 1usize] = u[usize(pick2[i]) - 1usize]
            i += 1usize
        }
        i = 0usize
        while i < kk {
            var j = 0usize
            while j < i {
                if cen[j + 1usize] == cen[i + 1usize] { ret (none, Unsupported) }
                j += 1usize
            }
            i += 1usize
        }
    }
    let mi = i64(m)
    let k = i64(kk)
    let (av, e1) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok { ret (none, e1) }
    i = 0usize
    while i < m {
        av[i + 1usize] = x[i]
        i += 1usize
    }
    let (ic1, e2) = mem.alloc[i64](a, m + 1usize)
    if e2 != ok { ret (none, e2) }
    let (ic2, e3) = mem.alloc[i64](a, m + 1usize)
    if e3 != ok { ret (none, e3) }
    let (d, e4) = mem.alloc[f64](a, m + 1usize)
    if e4 != ok { ret (none, e4) }
    let (nc, e5) = mem.alloc[i64](a, kk + 1usize)
    if e5 != ok { ret (none, e5) }
    let (ncp, e6) = mem.alloc[i64](a, kk + 1usize)
    if e6 != ok { ret (none, e6) }
    let (itran, e7) = mem.alloc[i64](a, kk + 1usize)
    if e7 != ok { ret (none, e7) }
    let (live, e8) = mem.alloc[i64](a, kk + 1usize)
    if e8 != ok { ret (none, e8) }
    let (an1, e9) = mem.alloc[f64](a, kk + 1usize)
    if e9 != ok { ret (none, e9) }
    let (an2, e10) = mem.alloc[f64](a, kk + 1usize)
    if e10 != ok { ret (none, e10) }
    var p = 1i64
    while p <= mi {
        let up = usize(p)
        ic1[up] = 1i64
        ic2[up] = 2i64
        var dt1 = sq(av[up] - cen[1usize])
        var dt2 = sq(av[up] - cen[2usize])
        if dt1 > dt2 {
            ic1[up] = 2i64
            ic2[up] = 1i64
            let t = dt1
            dt1 = dt2
            dt2 = t
        }
        var l = 3i64
        while l <= k {
            let db = sq(av[up] - cen[usize(l)])
            if !(db >= dt2) {
                if db >= dt1 {
                    dt2 = db
                    ic2[up] = l
                } else {
                    dt2 = dt1
                    ic2[up] = ic1[up]
                    dt1 = db
                    ic1[up] = l
                }
            }
            l += 1i64
        }
        p += 1i64
    }
    var l = 1i64
    while l <= k {
        nc[usize(l)] = 0i64
        cen[usize(l)] = 0.0f64
        l += 1i64
    }
    p = 1i64
    while p <= mi {
        let lc = ic1[usize(p)]
        nc[usize(lc)] += 1i64
        cen[usize(lc)] += av[usize(p)]
        p += 1i64
    }
    l = 1i64
    while l <= k {
        if nc[usize(l)] == 0i64 { ret (none, Unsupported) }
        let aa = f64(nc[usize(l)])
        cen[usize(l)] = cen[usize(l)] / aa
        an2[usize(l)] = aa / (aa + 1.0f64)
        an1[usize(l)] = 1.0e30f64
        if aa > 1.0f64 { an1[usize(l)] = aa / (aa - 1.0f64) }
        itran[usize(l)] = 1i64
        ncp[usize(l)] = 0i64 - 1i64
        l += 1i64
    }
    var indx = 0i64
    var ij = 1i64
    var done = false
    while ij <= 10i64 && !done {
        indx = optra(av, mi, cen, k, ic1, ic2, nc, an1, an2, ncp, d, itran, live, indx)
        if indx == mi {
            done = true
        } else {
            let (ix, kept) = qtran(av, mi, cen, ic1, ic2, nc, an1, an2, ncp, d, itran, indx, 50i64 * mi)
            indx = ix
            if !kept || kk == 2usize {
                done = true
            } else {
                l = 1i64
                while l <= k {
                    ncp[usize(l)] = 0i64
                    l += 1i64
                }
                ij += 1i64
            }
        }
    }
    let (label, e11) = mem.alloc[usize](a, m)
    if e11 != ok { ret (none, e11) }
    i = 0usize
    while i < m {
        label[i] = usize(ic1[i + 1usize]) - 1usize
        i += 1usize
    }
    ret (label, ok)
}

fn kmeans_breaks(a: *mem.Arena, r: *rng.Rng, x: []const f64, kk: usize) -> ([]f64, err) {
    let (label, le) = kmeans_labels(a, r, x, kk)
    if le != ok {
        var none: []f64 = zero
        ret (none, le)
    }
    let (cb, cbe) = class_breaks(a, x, label, kk)
    ret (cb, cbe)
}


// style "bclust" (e1071::bclust(x, centers = k) with iter.base = 10 committee members of 20 k-means centres, each on a
// bootstrap resample, average-linkage hclust of all centres, cutree to k, every observation to the cluster of its
// nearest committee centre); n is the number of classes
fn bclust_breaks(a: *mem.Arena, r: *rng.Rng, x: []const f64, k: usize) -> ([]f64, err) {
    var none: []f64 = zero
    let m = x.len
    let nb = 20usize
    let (allc, e0) = mem.alloc[f64](a, 10usize * nb)
    let (x1, e1) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok { ret (none, e0) }
    var total = 0usize
    var member = 0usize
    while member < 10usize {
        let (draw, de) = rng.sample_int(a, r, i64(m), i64(m), true)
        if de != ok { ret (none, de) }
        var i = 0usize
        while i < m {
            x1[i] = x[usize(draw[i]) - 1usize]
            i += 1usize
        }
        var tries = 0usize
        var got = false
        while tries < 20usize && !got {
            let (lab, le) = kmeans_labels(a, r, x1, nb)
            if le == ok {
                var c = 0usize
                while c < nb {
                    var s = 0.0f64
                    var cnt = 0.0f64
                    i = 0usize
                    while i < m {
                        if lab[i] == c {
                            s += x1[i]
                            cnt += 1.0f64
                        }
                        i += 1usize
                    }
                    allc[total + c] = s / cnt
                    c += 1usize
                }
                total += nb
                got = true
            }
            tries += 1usize
        }
        if !got { ret (none, Unsupported) }
        member += 1usize
    }
    // average linkage on the 1-d distances between the committee centres
    let nc = total
    let (d, e2) = mem.alloc[f64](a, nc * nc)
    let (size, e3) = mem.alloc[f64](a, nc)
    let (live, e4) = mem.alloc[bool](a, nc)
    let (grp, e5) = mem.alloc[usize](a, nc)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (none, e2) }
    var i = 0usize
    while i < nc {
        size[i] = 1.0f64
        live[i] = true
        grp[i] = i
        var j = 0usize
        while j < nc {
            var t = allc[i] - allc[j]
            if t < 0.0f64 { t = 0.0f64 - t }
            d[i * nc + j] = t
            j += 1usize
        }
        i += 1usize
    }
    var clusters = nc
    while clusters > k {
        var best = 1.0e308f64
        var bi = 0usize
        var bj = 0usize
        i = 0usize
        while i < nc {
            if live[i] {
                var j = i + 1usize
                while j < nc {
                    if live[j] && d[i * nc + j] < best {
                        best = d[i * nc + j]
                        bi = i
                        bj = j
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        var q = 0usize
        while q < nc {
            if live[q] && q != bi && q != bj {
                let v = (size[bi] * d[bi * nc + q] + size[bj] * d[bj * nc + q]) / (size[bi] + size[bj])
                d[bi * nc + q] = v
                d[q * nc + bi] = v
            }
            q += 1usize
        }
        size[bi] += size[bj]
        live[bj] = false
        q = 0usize
        while q < nc {
            if grp[q] == bj { grp[q] = bi }
            q += 1usize
        }
        clusters -= 1usize
    }
    // label every observation by the cluster of its nearest committee centre
    let (label, e6) = mem.alloc[usize](a, m)
    let (rank, e7) = mem.alloc[usize](a, nc)
    if e6 != ok || e7 != ok { ret (none, e6) }
    var next = 0usize
    i = 0usize
    while i < nc {
        rank[i] = nc
        i += 1usize
    }
    i = 0usize
    while i < nc {
        if rank[grp[i]] == nc {
            rank[grp[i]] = next
            next += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        var bestd = 1.0e308f64
        var bc = 0usize
        var c = 0usize
        while c < nc {
            var t = x[i] - allc[c]
            if t < 0.0f64 { t = 0.0f64 - t }
            if t < bestd {
                bestd = t
                bc = c
            }
            c += 1usize
        }
        label[i] = rank[grp[bc]]
        i += 1usize
    }
    // classes that no observation falls in vanish (tapply over the observed levels)
    let (used, e8) = mem.alloc[usize](a, k)
    if e8 != ok { ret (none, e8) }
    i = 0usize
    while i < k {
        used[i] = k
        i += 1usize
    }
    i = 0usize
    while i < m {
        used[label[i]] = 0usize
        i += 1usize
    }
    var nk = 0usize
    i = 0usize
    while i < k {
        if used[i] == 0usize {
            used[i] = nk
            nk += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        label[i] = used[label[i]]
        i += 1usize
    }
    let (cb, cbe) = class_breaks(a, x, label, nk)
    ret (cb, cbe)
}
