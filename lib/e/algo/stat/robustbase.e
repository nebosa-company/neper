// R robustbase: the Rousseeuw-Croux scale estimators Qn and Sn with the package's finite-sample factors, and Huber's M-estimate of location
// with the MAD scale (huberM). Computed from all pairwise differences, which gives the same values as the package's fast algorithms.
//
// Not here: mc (the medcouple), covMcd, lmrob, scaleTau2, adjOutlyingness and the rest of the package.

use e.math
use e.math.dist as dist

use e.mem

fn sort_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    // heap-free insertion sort is quadratic; the differences array can be large, so use a shell sort
    var gap = s.len / 2usize
    while gap > 0usize {
        i = gap
        while i < s.len {
            let t = s[i]
            var j = i
            while j >= gap && s[j - gap] > t {
                s[j] = s[j - gap]
                j -= gap
            }
            s[j] = t
            i += 1usize
        }
        gap = gap / 2usize
    }
    ret (s, ok)
}

fn qn_finite_c(n: f64) -> f64 {
    var v = 0.0f64
    if n - 2.0f64 * math.floor[f64](n / 2.0f64) == 1.0f64 {
        v = 1.60188f64 + (0.0f64 - 2.1284f64 - 5.172f64 / n) / n
    } else {
        v = 3.67561f64 + (1.9654f64 + (6.987f64 - 77.0f64 / n) / n) / n
    }
    ret v / n + 1.0f64
}

fn qn_small(n: usize) -> f64 {
    if n == 2usize { ret 0.399356f64 }
    if n == 3usize { ret 0.99365f64 }
    if n == 4usize { ret 0.51321f64 }
    if n == 5usize { ret 0.84401f64 }
    if n == 6usize { ret 0.6122f64 }
    if n == 7usize { ret 0.85877f64 }
    if n == 8usize { ret 0.66993f64 }
    if n == 9usize { ret 0.87344f64 }
    if n == 10usize { ret 0.72014f64 }
    if n == 11usize { ret 0.88906f64 }
    ret 0.75743f64
}

// Qn with the default constant 2.21914 and the finite-sample correction
fn qn(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    if n == 1usize { ret 0.0f64 }
    let m = n * (n - 1usize) / 2usize
    let (d, e) = mem.alloc[f64](a, m)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var c = 0usize
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            d[c] = math.abs[f64](x[i] - x[j])
            c += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let (s, e2) = sort_copy(a, d)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let h = n / 2usize + 1usize
    let k = h * (h - 1usize) / 2usize
    let r = 2.21914f64 * s[k - 1usize]
    if n <= 12usize { ret r * qn_small(n) }
    ret r / qn_finite_c(f64(n))
}

fn sn_small(n: usize) -> f64 {
    if n == 2usize { ret 0.743f64 }
    if n == 3usize { ret 1.851f64 }
    if n == 4usize { ret 0.954f64 }
    if n == 5usize { ret 1.351f64 }
    if n == 6usize { ret 0.993f64 }
    if n == 7usize { ret 1.198f64 }
    if n == 8usize { ret 1.005f64 }
    ret 1.131f64
}

// Sn with the default constant 1.1926 and the finite-sample correction: the low median over i of the high median over j of |x_i - x_j|
fn sn(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    if n == 1usize { ret 0.0f64 }
    let (row, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (ai, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            row[j] = math.abs[f64](x[i] - x[j])
            j += 1usize
        }
        let (s, e3) = sort_copy(a, row)
        if e3 != ok { ret 0.0f64 / 0.0f64 }
        ai[i] = s[n / 2usize]
        i += 1usize
    }
    let (s2, e4) = sort_copy(a, ai)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let r = 1.1926f64 * s2[(n + 1usize) / 2usize - 1usize]
    if n <= 9usize { ret sn_small(n) * r }
    if n % 2usize == 1usize { ret f64(n) / (f64(n) - 0.9f64) * r }
    ret r
}

fn median_sorted(s: []const f64) -> f64 {
    let n = s.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// huberM(x, k, tol): the location from the median start and the MAD scale (constant 1.4826); (mu, s, iterations)
fn huber_m(a: *mem.Arena, x: []const f64, k: f64, tol: f64) -> (f64, f64, usize) {
    let n = x.len
    let (s, e) = sort_copy(a, x)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0usize) }
    var mu = median_sorted(s)
    let (dev, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0usize) }
    var i = 0usize
    while i < n {
        dev[i] = math.abs[f64](x[i] - mu)
        i += 1usize
    }
    let (ds, e3) = sort_copy(a, dev)
    if e3 != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0usize) }
    let sc = 1.4826f64 * median_sorted(ds)
    var it = 0usize
    if sc <= 0.0f64 { ret (mu, sc, it) }
    var go = true
    while go {
        it += 1usize
        var sum = 0.0f64
        i = 0usize
        while i < n {
            var y = x[i]
            if y < mu - k * sc { y = mu - k * sc }
            if y > mu + k * sc { y = mu + k * sc }
            sum += y
            i += 1usize
        }
        let mu1 = sum / f64(n)
        if math.abs[f64](mu - mu1) < tol * sc {
            go = false
        } else {
            mu = mu1
        }
    }
    ret (mu, sc, it)
}

fn erho(b: f64) -> f64 {
    ret 2.0f64 * ((1.0f64 - b * b) * dist.pnorm(b, 0.0f64, 1.0f64, true, false) - b * dist.dnorm(b, 0.0f64, 1.0f64, false) + b * b) - 1.0f64
}

// scaleTau2(x, c1 = 4.5, c2 = 3, consistency = TRUE, iter = 1): the tau scale and (with mu_too) the location, from mu0 = median and sigma0 = the raw median absolute deviation
fn scale_tau2(a: *mem.Arena, x: []const f64, c1: f64, c2: f64) -> (f64, f64) {
    let n = x.len
    let (s, e) = sort_copy(a, x)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let mu0 = median_sorted(s)
    let (dev, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    var i = 0usize
    while i < n {
        dev[i] = math.abs[f64](x[i] - mu0)
        i += 1usize
    }
    let (ds, e3) = sort_copy(a, dev)
    if e3 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let sig0 = median_sorted(ds)
    if sig0 <= 0.0f64 { ret (mu0, 0.0f64) }
    let nes2 = f64(n) * erho(c2 * dist.qnorm(0.75f64, 0.0f64, 1.0f64, true, false))
    var sw = 0.0f64
    var sxw = 0.0f64
    i = 0usize
    while i < n {
        let u = dev[i] / (sig0 * c1)
        var w = 1.0f64 - u * u
        if w < 0.0f64 { w = 0.0f64 }
        w = w * w
        sw += w
        sxw += x[i] * w
        i += 1usize
    }
    let mu = sxw / sw
    var rs = 0.0f64
    i = 0usize
    while i < n {
        var r = (x[i] - mu) / sig0
        r = r * r
        if r > c2 * c2 { r = c2 * c2 }
        rs += r
        i += 1usize
    }
    ret (mu, sig0 * math.sqrt[f64](rs / nes2))
}

// mc: the medcouple, the median of ((x_j - med) - (med - x_i)) / (x_j - x_i) over x_i <= med <= x_j, for samples without ties at the median
// (an observation exactly at the median pairs with itself and is skipped here); doReflect makes the package average the estimate with the reflected one,
// which is the same number when there are no ties
fn mc(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let (s, e) = sort_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let med = median_sorted(s)
    let (h, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var cnt = 0usize
    var i = 0usize
    while i < n {
        if s[i] <= med {
            var j = 0usize
            while j < n {
                if s[j] >= med && s[j] > s[i] {
                    h[cnt] = ((s[j] - med) - (med - s[i])) / (s[j] - s[i])
                    cnt += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    let (hs, e3) = sort_copy(a, h[0usize..cnt])
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    ret median_sorted(hs)
}

// Tukey's five numbers
fn fivenum_sorted(s: []const f64, out: []f64) {
    let n = f64(s.len)
    let n4 = math.floor[f64]((n + 3.0f64) / 2.0f64) / 2.0f64
    out[0usize] = s[0usize]
    out[4usize] = s[s.len - 1usize]
    let d1 = n4
    let d2 = (n + 1.0f64) / 2.0f64
    let d3 = n + 1.0f64 - n4
    out[1usize] = 0.5f64 * (s[usize(math.floor[f64](d1)) - 1usize] + s[usize(math.ceil[f64](d1)) - 1usize])
    out[2usize] = 0.5f64 * (s[usize(math.floor[f64](d2)) - 1usize] + s[usize(math.ceil[f64](d2)) - 1usize])
    out[3usize] = 0.5f64 * (s[usize(math.floor[f64](d3)) - 1usize] + s[usize(math.ceil[f64](d3)) - 1usize])
}

// robustbase adjboxStats for a sample without ties in its medcouple: out = (five numbers with the whiskers moved to the extreme non-outlying values, notch lower, notch upper,
// fence lower, fence upper, number of outliers)
fn adjbox_stats(a: *mem.Arena, x: []const f64, coef: f64, ca: f64, cb: f64, out: []f64) {
    let (s, e) = sort_copy(a, x)
    if e != ok { ret }
    var st: [5]f64 = zero
    fivenum_sorted(s, st[0usize..5usize])
    let iqr = st[3usize] - st[1usize]
    let medc = mc(a, x)
    var f0 = st[1usize] - coef * math.exp[f64](ca * medc) * iqr
    var f1 = st[3usize] + coef * math.exp[f64](cb * medc) * iqr
    if medc < 0.0f64 {
        f0 = st[1usize] - coef * math.exp[f64](0.0f64 - cb * medc) * iqr
        f1 = st[3usize] + coef * math.exp[f64](0.0f64 - ca * medc) * iqr
    }
    var nout = 0usize
    var lo = 1.0e300f64
    var hi = -1.0e300f64
    var i = 0usize
    while i < x.len {
        if x[i] < f0 || f1 < x[i] {
            nout += 1usize
        } else {
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
        }
        i += 1usize
    }
    if nout > 0usize {
        st[0usize] = lo
        st[4usize] = hi
    }
    let half = 1.58f64 * iqr / math.sqrt[f64](f64(x.len))
    out[0usize] = st[0usize]
    out[1usize] = st[1usize]
    out[2usize] = st[2usize]
    out[3usize] = st[3usize]
    out[4usize] = st[4usize]
    out[5usize] = st[2usize] - half
    out[6usize] = st[2usize] + half
    out[7usize] = f0
    out[8usize] = f1
    out[9usize] = f64(nout)
}
