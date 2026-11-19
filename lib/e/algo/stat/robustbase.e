// R robustbase: the Rousseeuw-Croux scale estimators Qn and Sn with the package's finite-sample factors, and Huber's M-estimate of location
// with the MAD scale (huberM). Computed from all pairwise differences, which gives the same values as the package's fast algorithms.
//
// Not here: mc (the medcouple), covMcd, lmrob, scaleTau2, adjOutlyingness and the rest of the package.

use e.math
use e.algo.rand.r as rng
use e.algo.stat.gparot as gp
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
                } else if s[j] == med && s[i] == med {
                    // two observations at the median: the sign of i + j - 1 - n over the sorted positions (Brys et al.)
                    let pos = i + j + 1usize
                    var kv = 0.0f64
                    if pos < n { kv = 0.0f64 - 1.0f64 }
                    if pos > n { kv = 1.0f64 }
                    h[cnt] = kv
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

fn quantile7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let h = f64(n - 1usize) * p
    let lo = math.floor[f64](h)
    let i = usize(lo)
    if i + 1usize >= n { ret s[n - 1usize] }
    ret s[i] + (h - lo) * (s[i + 1usize] - s[i])
}

// robustbase::adjOutlyingness(x) with the defaults (ndir directions from p-subsets of the rows drawn by sample.int and sorted, B = solve(P, 1) normalized, medcouple adjusted fences
// with clower 4, cupper 3, coef 1.5, quantile type 7); x is n by p row-major, out gets the n adjusted outlyingnesses. Needs n <= 100 for the reflected medcouple the package uses then.
fn adj_outlyingness(a: *mem.Arena, g: *rng.Rng, x: []const f64, n: usize, p: usize, ndir: usize, out: []f64) -> err {
    let (bm, e0) = mem.alloc[f64](a, p * ndir)
    let (pm, e1) = mem.alloc[f64](a, p * p)
    let (yy, e2) = mem.alloc[f64](a, ndir * n)
    let (col, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret e0 }
    var i = 0usize
    var guard = 0usize
    while i < ndir && guard < 100usize * ndir {
        guard += 1usize
        let start = mem.mark(a)
        let (idx, se) = rng.sample_int(a, g, i64(n), i64(p), false)
        if se != ok { ret se }
        var q = 1usize
        while q < p {
            let v = idx[q]
            var j = q
            while j > 0usize && idx[j - 1usize] > v {
                idx[j] = idx[j - 1usize]
                j -= 1usize
            }
            idx[j] = v
            q += 1usize
        }
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                pm[r * p + c] = x[usize(idx[r] - 1i64) * p + c]
                c += 1usize
            }
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, pm, p)
        if ie == ok {
            var nrm = 0.0f64
            r = 0usize
            while r < p {
                var s = 0.0f64
                var c = 0usize
                while c < p {
                    s += inv[r * p + c]
                    c += 1usize
                }
                bm[i * p + r] = s
                nrm += s * s
                r += 1usize
            }
            nrm = math.sqrt[f64](nrm)
            r = 0usize
            while r < p {
                bm[i * p + r] /= nrm
                r += 1usize
            }
            i += 1usize
        }
        mem.reset(a, start)
    }
    if i < ndir { ret mem.Full }
    var d = 0usize
    while d < ndir {
        var t = 0usize
        while t < n {
            var s = 0.0f64
            var c = 0usize
            while c < p {
                s += x[t * p + c] * bm[d * p + c]
                c += 1usize
            }
            yy[d * n + t] = s
            t += 1usize
        }
        let (srt, ee) = sort_copy(a, yy[d * n..d * n + n])
        if ee != ok { ret ee }
        let med = median_sorted(srt)
        t = 0usize
        while t < n {
            yy[d * n + t] -= med
            t += 1usize
        }
        d += 1usize
    }
    let (yup, e4) = mem.alloc[f64](a, ndir)
    let (ylo, e5) = mem.alloc[f64](a, ndir)
    if e4 != ok || e5 != ok { ret e4 }
    d = 0usize
    while d < ndir {
        let start = mem.mark(a)
        var t = 0usize
        while t < n {
            col[t] = yy[d * n + t]
            t += 1usize
        }
        let tmc = mc(a, col[0usize..n])
        let (srt, ee) = sort_copy(a, col[0usize..n])
        if ee != ok { ret ee }
        let q1 = quantile7(srt, 0.25f64)
        let q3 = quantile7(srt, 0.75f64)
        let iqr = q3 - q1
        var cu = 0.0f64 - tmc * 4.0f64
        var cl = 0.0f64 - tmc * 3.0f64
        var ew = 3.0f64 * tmc
        var lw = 0.0f64 - 4.0f64 * tmc
        if tmc >= 0.0f64 {
            cu = 3.0f64 * tmc
            cl = 0.0f64 - 4.0f64 * tmc
            ew = cu
            lw = cl
        } else {
            ew = 4.0f64 * tmc
            lw = 0.0f64 - 3.0f64 * tmc
        }
        let tup = q3 + 1.5f64 * (iqr * math.exp[f64](ew))
        let tlo = q1 - 1.5f64 * (iqr * math.exp[f64](lw))
        var mxu = 0.0f64 - 1.0e308f64 * 10.0f64
        var mnl = 1.0e308f64 * 10.0f64
        t = 0usize
        while t < n {
            let v = yy[d * n + t]
            if v < tup && v > mxu { mxu = v }
            if v > tlo && v < mnl { mnl = v }
            t += 1usize
        }
        yup[d] = mxu
        ylo[d] = 0.0f64 - mnl
        mem.reset(a, start)
        d += 1usize
    }
    var t = 0usize
    while t < n {
        var best = 0.0f64 - 1.0e308f64
        d = 0usize
        while d < ndir {
            let y = yy[d * n + t]
            var v = 0.0f64
            if y != 0.0f64 {
                var dd = ylo[d]
                if y > 0.0f64 { dd = yup[d] }
                v = math.abs[f64](y) / dd
            }
            if v == v && v < 1.0e308f64 && v > best { best = v }
            d += 1usize
        }
        out[t] = best
        t += 1usize
    }
    ret ok
}
