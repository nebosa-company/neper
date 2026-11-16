// R robustbase: the Rousseeuw-Croux scale estimators Qn and Sn with the package's finite-sample factors, and Huber's M-estimate of location
// with the MAD scale (huberM). Computed from all pairwise differences, which gives the same values as the package's fast algorithms.
//
// Not here: mc (the medcouple), covMcd, lmrob, scaleTau2, adjOutlyingness and the rest of the package.

use e.math

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
