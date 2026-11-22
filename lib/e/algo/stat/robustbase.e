// R robustbase: the Rousseeuw-Croux scale estimators Qn and Sn with the package's finite-sample factors, and Huber's M-estimate of location
// with the MAD scale (huberM). Computed from all pairwise differences, which gives the same values as the package's fast algorithms.
//
// Not here: mc (the medcouple), covMcd, lmrob, scaleTau2, adjOutlyingness and the rest of the package.

use e.math
use e.algo.rand.r as rng
use e.algo.linalg.decomp as dc
use e.algo.stat.gparot as gp
use e.algo.stat.armld as ld
use e.math.dist as dist
use e.math.nmath as nmm

use e.mem

fn dnrm2_blue(x: []const f64, from: usize, count: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < count {
        let v = x[from + i]
        s += v * v
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

// dqrdc2 as R 4.6 runs it: the reference BLAS 3.12 dnrm2 (Blue) is a plain sum of squares, unlike the scaled dnrm2 in e.algo.linalg.decomp. x is n by p; pivot is 0-based.
fn dqrdc2_blue(a: *mem.Arena, x: []const f64, n: usize, p: usize, tol: f64) -> (dc.Qr, err) {
    var empty: dc.Qr = zero
    let (q, qe) = mem.alloc[f64](a, n * p + 1usize)
    let (qraux, ae) = mem.alloc[f64](a, p + 1usize)
    let (jpvt, je) = mem.alloc[usize](a, p + 1usize)
    let (w1, w1e) = mem.alloc[f64](a, p + 1usize)
    let (w2, w2e) = mem.alloc[f64](a, p + 1usize)
    if qe != ok { ret (empty, qe) }
    if ae != ok { ret (empty, ae) }
    if je != ok { ret (empty, je) }
    if w1e != ok { ret (empty, w1e) }
    if w2e != ok { ret (empty, w2e) }
    var i = 0usize
    while i < n * p {
        q[i] = x[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        jpvt[j] = j
        qraux[j] = dnrm2_blue(q, j * n, n)
        w1[j] = qraux[j]
        w2[j] = qraux[j]
        if w2[j] == 0.0f64 { w2[j] = 1.0f64 }
        j += 1usize
    }
    var lup = n
    if p < lup { lup = p }
    var k = p + 1usize
    var l = 0usize
    var stop = false
    while l < lup && !stop {
        // cycle the columns from l to p until one with a non-negligible norm is found
        while l + 1usize < k && qraux[l] < w2[l] * tol {
            let lp1 = l + 1usize
            var r = 0usize
            while r < n {
                let t = q[l * n + r]
                var c = lp1
                while c < p {
                    q[(c - 1usize) * n + r] = q[c * n + r]
                    c += 1usize
                }
                q[(p - 1usize) * n + r] = t
                r += 1usize
            }
            let ii = jpvt[l]
            let t = qraux[l]
            let tt = w1[l]
            let ttt = w2[l]
            var c = lp1
            while c < p {
                jpvt[c - 1usize] = jpvt[c]
                qraux[c - 1usize] = qraux[c]
                w1[c - 1usize] = w1[c]
                w2[c - 1usize] = w2[c]
                c += 1usize
            }
            jpvt[p - 1usize] = ii
            qraux[p - 1usize] = t
            w1[p - 1usize] = tt
            w2[p - 1usize] = ttt
            k -= 1usize
        }
        if l + 1usize == n {
            stop = true
        } else {
            // Householder transformation for column l
            var nrmxl = dnrm2_blue(q, l * n + l, n - l)
            if nrmxl != 0.0f64 {
                if q[l * n + l] != 0.0f64 {
                    if q[l * n + l] < 0.0f64 { nrmxl = 0.0f64 - math.abs[f64](nrmxl) } else { nrmxl = math.abs[f64](nrmxl) }
                }
                let inv = 1.0f64 / nrmxl
                var r = l
                while r < n {
                    q[l * n + r] = q[l * n + r] * inv
                    r += 1usize
                }
                q[l * n + l] = 1.0f64 + q[l * n + l]
                // apply to the remaining columns, updating the norms
                var c = l + 1usize
                while c < p {
                    var dot = 0.0f64
                    r = l
                    while r < n {
                        dot = dot + q[l * n + r] * q[c * n + r]
                        r += 1usize
                    }
                    let t = 0.0f64 - dot / q[l * n + l]
                    r = l
                    while r < n {
                        q[c * n + r] = q[c * n + r] + t * q[l * n + r]
                        r += 1usize
                    }
                    if qraux[c] != 0.0f64 {
                        var tt = 1.0f64 - (math.abs[f64](q[c * n + l]) / qraux[c]) * (math.abs[f64](q[c * n + l]) / qraux[c])
                        if tt < 0.0f64 { tt = 0.0f64 }
                        let t2 = tt
                        if math.abs[f64](t2) < 0.000001f64 {
                            qraux[c] = dnrm2_blue(q, c * n + l + 1usize, n - l - 1usize)
                            w1[c] = qraux[c]
                        } else {
                            qraux[c] = qraux[c] * math.sqrt[f64](t2)
                        }
                    }
                    c += 1usize
                }
                qraux[l] = q[l * n + l]
                q[l * n + l] = 0.0f64 - nrmxl
            }
            l += 1usize
        }
    }
    var rank = k - 1usize
    if n < rank { rank = n }
    ret (dc.Qr { qr: q, qraux: qraux, pivot: jpvt, rank: rank, n: n, p: p }, ok)
}

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

fn r32(x: f64) -> f64 { ret f64(f32(x)) }

// robustbase whimed_i: weighted high median of a[] (integer weights), destroying a and w
fn whimed_i(a: *mem.Arena, av: []f64, w: []i64) -> f64 {
    var n = av.len
    var w_tot = 0i64
    var i = 0usize
    while i < n {
        w_tot += w[i]
        i += 1usize
    }
    var wrest = 0i64
    while true {
        let (srt, se) = sort_copy(a, av[0usize..n])
        if se != ok { ret 0.0f64 / 0.0f64 }
        let trial = srt[n / 2usize]
        var wleft = 0i64
        var wmid = 0i64
        i = 0usize
        while i < n {
            if av[i] < trial { wleft += w[i] } else if av[i] > trial { } else { wmid += w[i] }
            i += 1usize
        }
        var kc = 0usize
        if 2i64 * (wrest + wleft) > w_tot {
            i = 0usize
            while i < n {
                if av[i] < trial {
                    av[kc] = av[i]
                    w[kc] = w[i]
                    kc += 1usize
                }
                i += 1usize
            }
        } else if 2i64 * (wrest + wleft + wmid) <= w_tot {
            i = 0usize
            while i < n {
                if av[i] > trial {
                    av[kc] = av[i]
                    w[kc] = w[i]
                    kc += 1usize
                }
                i += 1usize
            }
            wrest += wleft + wmid
        } else {
            ret trial
        }
        n = kc
    }
    ret 0.0f64
}

// robustbase qn0 for one k: the k-th smallest |x_i - x_j|, with the package's float truncation inside the search
fn qn0_k(a: *mem.Arena, x: []const f64, k: i64) -> f64 {
    let n = x.len
    let ni = i64(n)
    let (y, e0) = sort_copy(a, x)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    let (work, e1) = mem.alloc[f64](a, n)
    let (weight, e2) = mem.alloc[i64](a, n)
    let (left, e3) = mem.alloc[i64](a, n)
    let (right, e4) = mem.alloc[i64](a, n)
    let (p, e5) = mem.alloc[i64](a, n)
    let (q, e6) = mem.alloc[i64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    var odd = 0.0f64
    if n % 2usize == 1usize { odd = 1.0f64 }
    let k_l = i64(5.0f64 - 1.75f64 * odd + (0.3939f64 - 0.0067f64 * odd) * f64(ni) * f64(ni - 1i64))
    let h = ni / 2i64 + 1i64
    var nl = ni * (ni + 1i64) / 2i64
    var nr = ni * ni
    var knew = k + nl
    var found = false
    var trial = 0.0f64
    var i = 0usize
    while i < n {
        left[i] = ni - i64(i) + 1i64
        if k >= k_l || i64(i) <= h { right[i] = ni } else { right[i] = ni - (i64(i) - h) }
        i += 1usize
    }
    while !found && nr - nl > ni {
        var j = 0usize
        i = 1usize
        while i < n {
            if left[i] <= right[i] {
                weight[j] = right[i] - left[i] + 1i64
                let jh = left[i] + weight[j] / 2i64
                work[j] = r32(y[i] - y[usize(ni - jh)])
                j += 1usize
            }
            i += 1usize
        }
        trial = whimed_i(a, work[0usize..j], weight[0usize..j])
        var jj = 0i64
        var ii = ni - 1i64
        while ii >= 0i64 {
            while jj < ni && r32(y[usize(ii)] - y[usize(ni - jj - 1i64)]) < trial { jj += 1i64 }
            p[usize(ii)] = jj
            ii -= 1i64
        }
        jj = ni + 1i64
        i = 0usize
        while i < n {
            while r32(y[i] - y[usize(ni - jj + 1i64)]) > trial { jj -= 1i64 }
            q[i] = jj
            i += 1usize
        }
        var sump = 0i64
        var sumq = 0i64
        i = 0usize
        while i < n {
            sump += p[i]
            sumq += q[i] - 1i64
            i += 1usize
        }
        if knew <= sump {
            i = 0usize
            while i < n {
                right[i] = p[i]
                i += 1usize
            }
            nr = sump
        } else if knew > sumq {
            i = 0usize
            while i < n {
                left[i] = q[i]
                i += 1usize
            }
            nl = sumq
        } else {
            found = true
        }
    }
    if found { ret trial }
    let (all, e7) = mem.alloc[f64](a, n * n)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    var c = 0usize
    i = 1usize
    while i < n {
        var jj = left[i]
        while jj <= right[i] {
            all[c] = y[i] - y[usize(ni - jj)]
            c += 1usize
            jj += 1i64
        }
        i += 1usize
    }
    let (srt, e8) = sort_copy(a, all[0usize..c])
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    var kn = knew - (nl + 1i64)
    if kn > i64(c) - 1i64 { kn = i64(c) - 1i64 } else if kn < 0i64 { kn = 0i64 }
    ret srt[usize(kn)]
}

// Qn with the default constant 2.21914 and the finite-sample correction
fn qn(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    if n == 1usize { ret 0.0f64 }
    let h = n / 2usize + 1usize
    let r = 2.21914f64 * qn0_k(a, x, i64(h * (h - 1usize) / 2usize))
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

fn h_kern(av: f64, bv: f64, ai: i64, bi: i64, ab: i64, eps: f64, do_scale: bool) -> f64 {
    var lim = 4.0f64 * math.abs[f64](av + bv)
    if do_scale { lim = 2.0f64 }
    if bv > 0.0f64 || math.abs[f64](av - bv) <= eps * lim {
        let d = ab - (ai + bi)
        if d > 0i64 { ret 1.0f64 }
        if d < 0i64 { ret 0.0f64 - 1.0f64 }
        ret 0.0f64
    }
    ret (av + bv) / (av - bv)
}

// robustbase mc_C_d: one pass of the medcouple (ties at the median handled by the h kernel), the package's fast median of a table.
// Returns NaN when it does not converge within maxit
fn mc_pass(a: *mem.Arena, z: []const f64, eps1: f64, eps2: f64, maxit: i64, do_scale: bool) -> f64 {
    let n = z.len
    if n < 3usize { ret 0.0f64 }
    let ni = i64(n)
    let (x, ex) = mem.alloc[f64](a, n + 1usize)
    if ex != ok { ret 0.0f64 / 0.0f64 }
    x[0usize] = 0.0f64
    var i = 0usize
    while i < n {
        x[i + 1usize] = 0.0f64 - z[i]
        i += 1usize
    }
    let (xs, es) = sort_copy(a, x[1usize..n + 1usize])
    if es != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        x[i + 1usize] = xs[i]
        i += 1usize
    }
    var xmed = 0.0f64
    if n % 2usize == 1usize { xmed = x[n / 2usize + 1usize] } else { xmed = (x[n / 2usize] + x[n / 2usize + 1usize]) / 2.0f64 }
    var x_eps = eps1 * (eps1 + math.abs[f64](xmed))
    if math.abs[f64](x[1usize] - xmed) <= x_eps { ret 0.0f64 - 1.0f64 }
    if math.abs[f64](x[n] - xmed) <= x_eps { ret 1.0f64 }
    i = 1usize
    while i <= n {
        x[i] -= xmed
        i += 1usize
    }
    if do_scale {
        var m1 = 0.0f64 - x[1usize]
        if x[n] > m1 { m1 = x[n] }
        let xden = 0.0f64 - 2.0f64 * m1
        i = 1usize
        while i <= n {
            x[i] = x[i] / xden
            i += 1usize
        }
        xmed = xmed / xden
        x_eps = eps1 * (eps1 + math.abs[f64](xmed))
    } else {
        i = 1usize
        while i <= n {
            x[i] = 0.0f64 - x[i]
            i += 1usize
        }
    }
    var j = 1i64
    while j <= ni && x[usize(j)] >= x_eps { j += 1i64 }
    let off = j - 1i64
    var ci = 1i64
    while j <= ni && x[usize(j)] >= 0.0f64 - x_eps {
        j += 1i64
        ci += 1i64
    }
    let h1 = j - 1i64
    let h2 = ci + (ni - j)
    let (left, e1) = mem.alloc[i64](a, usize(h2) + 1usize)
    let (right, e2) = mem.alloc[i64](a, usize(h2) + 1usize)
    let (p, e3) = mem.alloc[i64](a, usize(h2) + 1usize)
    let (q, e4) = mem.alloc[i64](a, usize(h2) + 1usize)
    let (work, e5) = mem.alloc[f64](a, n)
    let (iwt, e6) = mem.alloc[i64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    var ii = 1i64
    while ii <= h2 {
        left[usize(ii)] = 1i64
        right[usize(ii)] = h1
        ii += 1i64
    }
    var nr = h1 * h2
    let knew = nr / 2i64 + 1i64
    var nl = 0i64
    var neq = 0i64
    var trial = 0.0f64 - 2.0f64
    var medc = 0.0f64
    var found = false
    var it = 0i64
    while !found && (nr - nl + neq > ni) && it < maxit {
        it += 1i64
        var jw = 0usize
        ii = 1i64
        while ii <= h2 {
            if left[usize(ii)] <= right[usize(ii)] {
                iwt[jw] = right[usize(ii)] - left[usize(ii)] + 1i64
                let k = left[usize(ii)] + iwt[jw] / 2i64
                work[jw] = h_kern(x[usize(k)], x[usize(off + ii)], k, ii, h1 + 1i64, eps2, do_scale)
                jw += 1usize
            }
            ii += 1i64
        }
        trial = whimed_i(a, work[0usize..jw], iwt[0usize..jw])
        var eps_trial = eps1 * math.abs[f64](trial)
        if do_scale { eps_trial = eps1 * (eps1 + math.abs[f64](trial)) }
        var jj = 1i64
        ii = h2
        while ii >= 1i64 {
            while jj <= h1 && h_kern(x[usize(jj)], x[usize(off + ii)], jj, ii, h1 + 1i64, eps2, do_scale) - trial > eps_trial { jj += 1i64 }
            p[usize(ii)] = jj - 1i64
            ii -= 1i64
        }
        jj = h1
        var sum_p = 0i64
        var sum_q = 0i64
        ii = 1i64
        while ii <= h2 {
            while jj >= 1i64 && trial - h_kern(x[usize(jj)], x[usize(off + ii)], jj, ii, h1 + 1i64, eps2, do_scale) > eps_trial { jj -= 1i64 }
            q[usize(ii)] = jj + 1i64
            sum_p += p[usize(ii)]
            sum_q += jj
            ii += 1i64
        }
        if knew <= sum_p {
            neq = 0i64
            ii = 1i64
            while ii <= h2 {
                right[usize(ii)] = p[usize(ii)]
                if left[usize(ii)] > right[usize(ii)] + 1i64 { neq += left[usize(ii)] - right[usize(ii)] - 1i64 }
                ii += 1i64
            }
            nr = sum_p
        } else {
            found = knew <= sum_q
            if found {
                medc = trial
            } else {
                ii = 1i64
                while ii <= h2 {
                    left[usize(ii)] = q[usize(ii)]
                    if left[usize(ii)] > right[usize(ii)] + 1i64 { neq += left[usize(ii)] - right[usize(ii)] - 1i64 }
                    ii += 1i64
                }
                nl = sum_q
            }
        }
    }
    let converged = found || (nr - nl + neq <= ni)
    if !converged { ret 0.0f64 / 0.0f64 }
    if !found {
        var c = 0usize
        ii = 1i64
        while ii <= h2 {
            if left[usize(ii)] <= right[usize(ii)] {
                var k = left[usize(ii)]
                while k <= right[usize(ii)] {
                    work[c] = 0.0f64 - h_kern(x[usize(k)], x[usize(off + ii)], k, ii, h1 + 1i64, eps2, do_scale)
                    c += 1usize
                    k += 1i64
                }
            }
            ii += 1i64
        }
        let (ws, ew) = sort_copy(a, work[0usize..c])
        if ew != ok { ret 0.0f64 / 0.0f64 }
        medc = 0.0f64 - ws[usize(knew - nl - 1i64)]
    }
    ret medc
}

// mc(x, doReflect, doScale, eps1, eps2, maxit)
fn mc_opt(a: *mem.Arena, x: []const f64, reflect: bool, do_scale: bool, eps1: f64, eps2: f64, maxit: i64) -> f64 {
    let m1 = mc_pass(a, x, eps1, eps2, maxit, do_scale)
    if !reflect { ret m1 }
    let (nx, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        nx[i] = 0.0f64 - x[i]
        i += 1usize
    }
    let m2 = mc_pass(a, nx, eps1, eps2, maxit, do_scale)
    ret (m1 - m2) / 2.0f64
}

// mc with its defaults: doReflect for n <= 100, doScale FALSE
fn mc(a: *mem.Arena, x: []const f64) -> f64 { ret mc_opt(a, x, x.len <= 100usize, false, 1.0e-14f64, 1.0e-15f64, 100i64) }

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
        // solve(qr(P, tol = 1e-12), rep(1, p)) through LINPACK dqrdc2 and dqrsl, so that the rounding matches R
        let (pc, pce) = mem.alloc[f64](a, p * p)
        if pce != ok { ret pce }
        r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                pc[c * p + r] = pm[r * p + c]
                c += 1usize
            }
            r += 1usize
        }
        let (fq, qe) = dqrdc2_blue(a, pc, p, p, 1.0e-12f64)
        if qe != ok { ret qe }
        if fq.rank == p {
            let (yv, ye) = mem.alloc[f64](a, p + 1usize)
            if ye != ok { ret ye }
            r = 0usize
            while r < p {
                yv[r] = 1.0f64
                r += 1usize
            }
            dc.qr_qty(&fq, yv)
            var jj = p
            while jj > 0usize {
                jj -= 1usize
                yv[jj] = yv[jj] / fq.qr[jj * p + jj]
                if jj > 0usize {
                    let tmp = 0.0f64 - yv[jj]
                    var q2 = 0usize
                    while q2 < jj {
                        yv[q2] = yv[q2] + tmp * fq.qr[jj * p + q2]
                        q2 += 1usize
                    }
                }
            }
            var nrm = 0.0f64
            r = 0usize
            while r < p {
                bm[i * p + fq.pivot[r]] = yv[r]
                r += 1usize
            }
            // colSums accumulates the squares in a long double
            var acc = ld.ld_zero()
            r = 0usize
            while r < p {
                let lv = ld.ld_from(yv[r])
                acc = ld.ld_add(acc, ld.ld_mul(lv, lv))
                r += 1usize
            }
            nrm = math.sqrt[f64](ld.ld_to(acc))
            r = 0usize
            while r < p {
                bm[i * p + r] = bm[i * p + r] / nrm
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
        let tmc = mc_opt(a, col[0usize..n], n <= 100usize, true, 1.0e-12f64, 1.0e-15f64, 200i64)
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

// robustbase .MCDcons for p = 1: 1 / (pgamma(qchisq(alpha, 1) / 2, 3 / 2) / alpha)
fn mcd_cons1(alpha: f64) -> f64 {
    let qa = nmm.qchisq(alpha, 1.0f64, true, false)
    ret alpha / nmm.pgamma(qa / 2.0f64, 1.5f64, 1.0f64, true, false)
}

// the finite sample factor of .MCDcnp2 (rew = false) and .MCDcnp2.rew (rew = true) for p = 1: 1 / (the interpolation between the 0.5 and 0.875 curves)
fn mcd_cnp2_1(n: f64, alpha: f64, rew: bool) -> f64 {
    var f5 = 1.0f64 - math.exp[f64](0.262024211897096f64) / math.pow[f64](n, 0.604756680630497f64)
    var f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.351584646688712f64) / math.pow[f64](n, 1.01646567502486f64)
    if rew {
        f5 = 1.0f64 - math.exp[f64](1.11098143415027f64) / math.pow[f64](n, 1.5182890270453f64)
        f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.66046776772861f64) / math.pow[f64](n, 0.88939595831888f64)
    }
    var fa = f5 + (f875 - f5) / 0.375f64 * (alpha - 0.5f64)
    if alpha > 0.875f64 { fa = f875 + (1.0f64 - f875) / 0.125f64 * (alpha - 0.875f64) }
    ret 1.0f64 / fa
}

// robustbase::covMcd for one variable (the exact univariate MCD): the h = floor(2 n2 - n + 2 (n - n2) alpha) consecutive sorted values of smallest variance give the raw center and the raw
// variance (divisor h) times the consistency factor and the small sample factor; the observations within sqrt(chi2_0.975) raw scales are reweighted (mean, variance with divisor sum w - 1),
// the variance multiplied by the factors of the reweighting when some observation is dropped. out = (raw center, raw variance, center, variance)
fn cov_mcd_1d(a: *mem.Arena, x: []const f64, alpha: f64, out: []f64) -> err {
    let n = x.len
    let (s, e0) = sort_copy(a, x)
    if e0 != ok { ret e0 }
    let n2 = (n + 2usize) / 2usize
    let h = usize(math.floor[f64](2.0f64 * f64(n2) - f64(n) + 2.0f64 * f64(n - n2) * alpha))
    var best = 1.0e308f64
    var bi = 0usize
    var i = 0usize
    while i + h <= n {
        var m = 0.0f64
        var j = 0usize
        while j < h {
            m += s[i + j]
            j += 1usize
        }
        m /= f64(h)
        var v = 0.0f64
        j = 0usize
        while j < h {
            v += (s[i + j] - m) * (s[i + j] - m)
            j += 1usize
        }
        v /= f64(h - 1usize)
        if v < best {
            best = v
            bi = i
        }
        i += 1usize
    }
    var cen = 0.0f64
    i = 0usize
    while i < h {
        cen += s[bi + i]
        i += 1usize
    }
    cen /= f64(h)
    var ss = 0.0f64
    i = 0usize
    while i < h {
        ss += (s[bi + i] - cen) * (s[bi + i] - cen)
        i += 1usize
    }
    let calpha = mcd_cons1(f64(h) / f64(n))
    let corr = mcd_cnp2_1(f64(n), alpha, false)
    let rawv = calpha * corr * ss / f64(h)
    let cm = nmm.qchisq(0.975f64, 1.0f64, true, false)
    var sw = 0.0f64
    var sx = 0.0f64
    i = 0usize
    while i < n {
        let z = (x[i] - cen) * (x[i] - cen) / rawv
        if z < cm {
            sw += 1.0f64
            sx += x[i]
        }
        i += 1usize
    }
    let mw = sx / sw
    var sv = 0.0f64
    i = 0usize
    while i < n {
        let z = (x[i] - cen) * (x[i] - cen) / rawv
        if z < cm { sv += (x[i] - mw) * (x[i] - mw) }
        i += 1usize
    }
    var cv = sv / (sw - 1.0f64)
    if sw != f64(n) { cv = cv * mcd_cons1(0.975f64) * mcd_cnp2_1(f64(n), alpha, true) }
    out[0usize] = cen
    out[1usize] = rawv
    out[2usize] = mw
    out[3usize] = cv
    ret ok
}

error McdUnsupported

// ---- covMcd for two or more variables: robustbase's FastMCD (rffastmcd.f), the unpartitioned case (n < 600), without the exact-fit branches ----

// rfcovsweep on column-major a (p by p), pivot k (0-based)
fn mcd_sweep(a: []f64, p: usize, k: usize) {
    let d = a[k * p + k]
    var j = 0usize
    while j < p {
        a[j * p + k] = a[j * p + k] / d
        j += 1usize
    }
    var i = 0usize
    while i < p {
        if i != k {
            let b = a[k * p + i]
            j = 0usize
            while j < p {
                a[j * p + i] = a[j * p + i] - b * a[j * p + k]
                j += 1usize
            }
            a[k * p + i] = 0.0f64 - b / d
        }
        i += 1usize
    }
    a[k * p + k] = 1.0f64 / d
}

// sweeps every pivot; returns the log determinant (sum of log pivots) and whether a pivot fell below eps
fn mcd_sweep_all(cinv: []f64, p: usize, eps: f64) -> (f64, bool) {
    var det = 0.0f64
    var j = 0usize
    while j < p {
        let pivot = cinv[j * p + j]
        det = det + math.log[f64](pivot)
        if pivot < eps { ret (det, false) }
        mcd_sweep(cinv, p, j)
        j += 1usize
    }
    ret (det, true)
}

// rfadmit over the listed observations then rfcovar: means and covariance (divisor cnt - 1) of dat rows idx[0..cnt] (0-based rows)
fn mcd_cov_of(dat: []const f64, n: usize, p: usize, idx: []const usize, cnt: usize, sscp: []f64, cova: []f64, means: []f64) {
    let q = p + 1usize
    var i = 0usize
    while i < q * q {
        sscp[i] = 0.0f64
        i += 1usize
    }
    var r = 0usize
    while r < cnt {
        let row = idx[r]
        sscp[0usize] = sscp[0usize] + 1.0f64
        var j = 0usize
        while j < p {
            sscp[(j + 1usize) * q] = sscp[(j + 1usize) * q] + dat[j * n + row]
            sscp[j + 1usize] = sscp[(j + 1usize) * q]
            j += 1usize
        }
        i = 0usize
        while i < p {
            j = 0usize
            while j < p {
                sscp[(j + 1usize) * q + i + 1usize] = sscp[(j + 1usize) * q + i + 1usize] + dat[i * n + row] * dat[j * n + row]
                j += 1usize
            }
            i += 1usize
        }
        r += 1usize
    }
    let fn_ = f64(cnt)
    i = 0usize
    while i < p {
        means[i] = sscp[(i + 1usize) * q]
        means[i] = means[i] / fn_
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var c = sscp[(j + 1usize) * q + i + 1usize]
            c = c - fn_ * means[i] * means[j]
            cova[j * p + i] = c / (fn_ - 1.0f64)
            j += 1usize
        }
        i += 1usize
    }
}

// rfmahad
fn mcd_mahad(dat: []const f64, n: usize, p: usize, row: usize, means: []const f64, sigma: []const f64) -> f64 {
    var t = 0.0f64
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            t = t + (dat[j * n + row] - means[j]) * (dat[k * n + row] - means[k]) * sigma[k * p + j]
            k += 1usize
        }
        j += 1usize
    }
    ret t
}

// rffindq: the k-th smallest of aw[0..ncas] (k is 1-based), partially ordering aw and index (0-based observation numbers) in place
fn mcd_findq(aw: []f64, ncas: usize, k: usize, index: []usize) -> f64 {
    var j = 0usize
    while j < ncas {
        index[j] = j
        j += 1usize
    }
    var l = 1i64
    var lr = i64(ncas)
    let ki = i64(k)
    while l < lr {
        let ax = aw[usize(ki - 1i64)]
        var jnc = l
        var jj = lr
        while jnc <= jj {
            while aw[usize(jnc - 1i64)] < ax { jnc += 1i64 }
            while aw[usize(jj - 1i64)] > ax { jj -= 1i64 }
            if jnc <= jj {
                let t = index[usize(jnc - 1i64)]
                index[usize(jnc - 1i64)] = index[usize(jj - 1i64)]
                index[usize(jj - 1i64)] = t
                let wa = aw[usize(jnc - 1i64)]
                aw[usize(jnc - 1i64)] = aw[usize(jj - 1i64)]
                aw[usize(jj - 1i64)] = wa
                jnc += 1i64
                jj -= 1i64
            }
        }
        if jj < ki { l = jnc }
        if ki < jnc { lr = jj }
    }
    ret aw[usize(ki - 1i64)]
}

fn mcd_sort_usize(v: []usize, cnt: usize) {
    var i = 1usize
    while i < cnt {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
}

type McdWork = struct {
    n: usize,
    p: usize,
    dat: []f64,
    nhalf: usize,
    eps: f64,
    sscp: []f64,
    cova1: []f64,
    cinv1: []f64,
    means: []f64,
    ndist: []f64,
    index2: []usize,
    temp: []usize,
    det: f64,
    object: f64,
    medi2: f64,
    cova2: []f64,
    cinv2: []f64,
    bmeans: []f64,
    best: []usize
}

// the concentration steps (label 9555 of rffastmcd): returns McdUnsupported when a covariance becomes singular
fn mcd_steps(m: *McdWork, g: *rng.Rng, kstep: usize, fin: bool, it: usize) -> err {
    let n = m.n
    let p = m.p
    var deti = 0.0f64 - 1.0e300f64
    var detimin1 = deti
    var step = 1usize
    while step <= kstep {
        var r = 0usize
        while r < m.nhalf {
            m.temp[r] = m.index2[r]
            r += 1usize
        }
        mcd_sort_usize(m.temp, m.nhalf)
        mcd_cov_of(m.dat, n, p, m.temp, m.nhalf, m.sscp, m.cova1, m.means)
        r = 0usize
        while r < p * p {
            m.cinv1[r] = m.cova1[r]
            r += 1usize
        }
        let (dt, okk) = mcd_sweep_all(m.cinv1, p, m.eps)
        m.det = dt
        if !okk { ret McdUnsupported }
        if step >= 2usize && m.det == detimin1 { ret ok }
        detimin1 = deti
        deti = m.det
        r = 0usize
        while r < n {
            m.ndist[r] = mcd_mahad(m.dat, n, p, r, m.means, m.cinv1)
            r += 1usize
        }
        let _ = mcd_findq(m.ndist, n, m.nhalf, m.index2)
        if fin && ((it == 1usize && step == 1usize) || m.det < m.object) {
            m.medi2 = mcd_findq(m.ndist, n, n / 2usize, m.temp)
            m.object = m.det
            r = 0usize
            while r < m.nhalf {
                m.best[r] = m.index2[r] + 1usize
                r += 1usize
            }
            r = 0usize
            while r < p * p {
                m.cova2[r] = m.cova1[r]
                m.cinv2[r] = m.cinv1[r]
                r += 1usize
            }
            r = 0usize
            while r < p {
                m.bmeans[r] = m.means[r]
                r += 1usize
            }
        }
        step += 1usize
    }
    let _ = g
    ret ok
}

// FastMCD for p >= 2 on x (n rows of p, row-major), h = number of observations kept, nsamp random starts (0 = all subsets).
// out = raw center (p), raw covariance as initcov (p*p row-major, before the consistency factor), log determinant, medi2 / chi2_0.5 (the factor ltsReg uses)
fn fastmcd_raw(a: *mem.Arena, g: *rng.Rng, x: []const f64, n: usize, p: usize, h: usize, nsamp: usize, out: []f64) -> err {
    let nsel = p + 1usize
    if n >= 600usize || h >= n { ret McdUnsupported }
    var eps = 1.0e-12f64
    if p >= 5usize { eps = 1.0e-14f64 }
    if p > 8usize { eps = 1.0e-16f64 }
    let (dat, e0) = mem.alloc[f64](a, n * p)
    let (sscp, e1) = mem.alloc[f64](a, (p + 1usize) * (p + 1usize))
    let (cova1, e2) = mem.alloc[f64](a, p * p)
    let (cinv1, e3) = mem.alloc[f64](a, p * p)
    let (means, e4) = mem.alloc[f64](a, p)
    let (ndist, e5) = mem.alloc[f64](a, n)
    let (index2, e6) = mem.alloc[usize](a, n)
    let (temp, e7) = mem.alloc[usize](a, n)
    let (cova2, e8) = mem.alloc[f64](a, p * p)
    let (cinv2, e9) = mem.alloc[f64](a, p * p)
    let (bmeans, e10) = mem.alloc[f64](a, p)
    let (best, e11) = mem.alloc[usize](a, n)
    let (index1, e12) = mem.alloc[i64](a, n + 1usize)
    let (am, e13) = mem.alloc[f64](a, n)
    let (med, e14) = mem.alloc[f64](a, p)
    let (mad, e15) = mem.alloc[f64](a, p)
    let (cst, e16) = mem.alloc[f64](a, 10usize * p * p)
    let (mst, e17) = mem.alloc[f64](a, 10usize * p)
    let (mdet, e18) = mem.alloc[f64](a, 10usize)
    let (idx0, e19) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret e0 }
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret e10 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            dat[j * n + i] = x[i * p + j]
            j += 1usize
        }
        idx0[i] = i
        i += 1usize
    }
    // the classical estimate must be regular
    mcd_cov_of(dat, n, p, idx0, n, sscp, cova1, means)
    var jc = 0usize
    while jc < p {
        let q = p + 1usize
        let s2 = sscp[(jc + 1usize) * q + jc + 1usize]
        let mj = sscp[(jc + 1usize) * q]
        let f = (s2 - mj * mj / f64(n)) / (f64(n) - 1.0f64)
        if !(f > 0.0f64) { ret McdUnsupported }
        jc += 1usize
    }
    i = 0usize
    while i < p * p {
        cinv1[i] = cova1[i]
        i += 1usize
    }
    let (d0, ok0) = mcd_sweep_all(cinv1, p, eps)
    let _ = d0
    if !ok0 { ret McdUnsupported }
    // standardise each column by its median and the h-th smallest absolute deviation
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            am[i] = dat[j * n + i]
            i += 1usize
        }
        let (srt, se) = sort_copy(a, am)
        if se != ok { ret se }
        if n % 2usize == 0usize { med[j] = (srt[n / 2usize - 1usize] + srt[n / 2usize]) / 2.0f64 } else { med[j] = srt[(n + 1usize) / 2usize - 1usize] }
        i = 0usize
        while i < n {
            ndist[i] = math.abs[f64](dat[j * n + i] - med[j])
            i += 1usize
        }
        let (srt2, se2) = sort_copy(a, ndist)
        if se2 != ok { ret se2 }
        mad[j] = srt2[h - 1usize]
        if mad[j] - 0.0f64 < eps { ret McdUnsupported }
        i = 0usize
        while i < n {
            dat[j * n + i] = (dat[j * n + i] - med[j]) / mad[j]
            i += 1usize
        }
        j += 1usize
    }
    var m = McdWork { n: n, p: p, dat: dat, nhalf: h, eps: eps, sscp: sscp, cova1: cova1, cinv1: cinv1, means: means, ndist: ndist, index2: index2, temp: temp, det: 0.0f64, object: 1.0e26f64, medi2: 0.0f64, cova2: cova2, cinv2: cinv2, bmeans: bmeans, best: best }
    // phase 1: random (or all) elemental starts, two concentration steps each, the ten best kept
    var nrep = nsamp
    var allsub = false
    var comb = 1.0f64
    j = 1usize
    while j <= nsel {
        comb = comb * ((f64(n) - f64(j) + 1.0f64) / (f64(nsel) - f64(j) + 1.0f64))
        j += 1usize
    }
    var lowrep = 0usize
    if nsel == 1usize { lowrep = 500usize }
    if nsel == 2usize { lowrep = 50usize }
    if nsel == 3usize { lowrep = 22usize }
    if nsel == 4usize { lowrep = 17usize }
    if nsel == 5usize { lowrep = 15usize }
    if nsel == 6usize { lowrep = 14usize }
    if nsamp == 0usize || n <= lowrep {
        allsub = true
        if comb > 2147483647.0f64 { comb = 2147483647.0f64 }
        nrep = usize(comb + 0.5f64)
    }
    i = 0usize
    while i < 10usize {
        mdet[i] = 1.0e26f64
        mst[i * p] = 1234567.0f64
        i += 1usize
    }
    var gen = 0usize
    while gen < nsel {
        index1[gen + 1usize] = i64(gen) + 1i64
        gen += 1usize
    }
    index1[nsel] = i64(nsel) - 1i64
    var rep = 1usize
    while rep <= nrep {
        var pnsel = nsel
        if allsub {
            // rfgenpn
            var kk = nsel
            index1[kk] = index1[kk] + 1i64
            while !(kk == 1usize || index1[kk] <= i64(n) - i64(nsel - kk)) {
                kk -= 1usize
                index1[kk] = index1[kk] + 1i64
                var ii = kk + 1usize
                while ii <= nsel {
                    index1[ii] = index1[ii - 1usize] + 1i64
                    ii += 1usize
                }
            }
        } else {
            // rfrangen
            var di = 1usize
            while di <= nsel {
                var again = true
                var num = 0i64
                while again {
                    num = i64(rng.unif(g) * f64(n)) + 1i64
                    again = false
                    var dj = 1usize
                    while dj < di {
                        if index1[dj] == num { again = true }
                        dj += 1usize
                    }
                }
                index1[di] = num
                di += 1usize
            }
        }
        var started = false
        while !started {
            var r = 0usize
            while r < pnsel {
                temp[r] = usize(index1[r + 1usize] - 1i64)
                r += 1usize
            }
            mcd_cov_of(dat, n, p, temp, pnsel, sscp, cova1, means)
            r = 0usize
            while r < p * p {
                cinv1[r] = cova1[r]
                r += 1usize
            }
            let (dt, okk) = mcd_sweep_all(cinv1, p, eps)
            m.det = dt
            if okk {
                started = true
            } else {
                // singular: extend the subsample by one random observation (prdraw)
                var s1 = 1usize
                while s1 < pnsel {
                    let v = index1[s1 + 1usize]
                    var s2 = s1
                    while s2 > 0usize && index1[s2] > v {
                        index1[s2 + 1usize] = index1[s2]
                        s2 -= 1usize
                    }
                    index1[s2 + 1usize] = v
                    s1 += 1usize
                }
                let jndex = i64(pnsel)
                let nrand = i64(rng.unif(g) * f64(i64(n) - jndex)) + 1i64
                let jn = jndex + 1i64
                index1[usize(jn)] = nrand + jn - 1i64
                var pi = 1i64
                var placed = false
                while pi <= jn - 1i64 && !placed {
                    if index1[usize(pi)] > nrand + pi - 1i64 {
                        var pj = jn
                        while pj >= pi + 1i64 {
                            index1[usize(pj)] = index1[usize(pj - 1i64)]
                            pj -= 1i64
                        }
                        index1[usize(pi)] = nrand + pi - 1i64
                        placed = true
                    }
                    pi += 1i64
                }
                pnsel += 1usize
                if pnsel >= n { ret McdUnsupported }
            }
        }
        var r = 0usize
        while r < n {
            ndist[r] = mcd_mahad(dat, n, p, r, means, cinv1)
            r += 1usize
        }
        let _ = mcd_findq(ndist, n, h, index2)
        let se = mcd_steps(&m, g, 2usize, false, rep)
        if se != ok { ret se }
        // store the ten best by determinant
        var slot = 0usize
        var stored = false
        while slot < 10usize && !stored {
            if m.det <= mdet[slot] {
                var insert = false
                var dup = false
                if m.det != mdet[slot] {
                    insert = true
                } else {
                    var kk = slot
                    while kk < 10usize && !insert {
                        if m.det == mdet[kk] {
                            var c1 = 0usize
                            while c1 < p && !insert {
                                if m.means[c1] != mst[kk * p + c1] { insert = true }
                                c1 += 1usize
                            }
                            c1 = 0usize
                            while c1 < p * p && !insert {
                                if m.cova1[c1] != cst[kk * p * p + c1] { insert = true }
                                c1 += 1usize
                            }
                        }
                        kk += 1usize
                    }
                    if !insert { dup = true }
                }
                if insert {
                    var kk = 9usize
                    while kk > slot {
                        var c2 = 0usize
                        while c2 < p * p {
                            cst[kk * p * p + c2] = cst[(kk - 1usize) * p * p + c2]
                            c2 += 1usize
                        }
                        c2 = 0usize
                        while c2 < p {
                            mst[kk * p + c2] = mst[(kk - 1usize) * p + c2]
                            c2 += 1usize
                        }
                        mdet[kk] = mdet[kk - 1usize]
                        kk -= 1usize
                    }
                    var c3 = 0usize
                    while c3 < p * p {
                        cst[slot * p * p + c3] = m.cova1[c3]
                        c3 += 1usize
                    }
                    c3 = 0usize
                    while c3 < p {
                        mst[slot * p + c3] = m.means[c3]
                        c3 += 1usize
                    }
                    mdet[slot] = m.det
                    stored = true
                }
                if dup { stored = true }
            }
            slot += 1usize
        }
        rep += 1usize
    }
    // phase 3: the stored estimates, up to 100 concentration steps each
    var kfin = 100usize
    if n * p > 100000usize { kfin = 1usize }
    m.object = 1.0e26f64
    var fi = 1usize
    var more = true
    while fi <= 10usize && more {
        if mst[(fi - 1usize) * p] == 1234567.0f64 {
            more = false
        } else {
            var r = 0usize
            while r < p {
                means[r] = mst[(fi - 1usize) * p + r]
                r += 1usize
            }
            r = 0usize
            while r < p * p {
                cova1[r] = cst[(fi - 1usize) * p * p + r]
                cinv1[r] = cova1[r]
                r += 1usize
            }
            let (dt, okk) = mcd_sweep_all(cinv1, p, eps)
            if !okk { ret McdUnsupported }
            m.det = dt
            r = 0usize
            while r < n {
                ndist[r] = mcd_mahad(dat, n, p, r, means, cinv1)
                r += 1usize
            }
            let _ = mcd_findq(ndist, n, h, index2)
            let se = mcd_steps(&m, g, kfin, true, fi)
            if se != ok { ret se }
            fi += 1usize
        }
    }
    j = 0usize
    while j < p {
        out[j] = bmeans[j] * mad[j] + med[j]
        j += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            out[p + i * p + j] = cova2[j * p + i] * mad[i] * mad[j]
            j += 1usize
        }
        i += 1usize
    }
    var ldet = m.object
    j = 0usize
    while j < p {
        ldet = ldet + 2.0f64 * math.log[f64](mad[j])
        j += 1usize
    }
    out[p + p * p] = ldet
    out[p + p * p + 1usize] = m.medi2 / nmm.qchisq(0.5f64, f64(p), true, false)
    ret ok
}

fn mcd_cons(p: f64, alpha: f64) -> f64 {
    let qa = nmm.qchisq(alpha, p, true, false)
    ret alpha / nmm.pgamma(qa / 2.0f64, p / 2.0f64 + 1.0f64, 1.0f64, true, false)
}

// fp(alpha, n) of .MCDcnp2 / .MCDcnp2.rew for p >= 2 (the tabulated simulated values for alpha = 0.5 at tiny n are not here)
fn mcd_cnp2_p(pp: f64, n: f64, alpha: f64, rew: bool) -> f64 {
    var f5 = 0.0f64
    var f875 = 0.0f64
    if pp == 2.0f64 {
        if rew {
            f5 = 1.0f64 - math.exp[f64](3.11101712909049f64) / math.pow[f64](n, 1.91401056721863f64)
            f875 = 1.0f64 - math.exp[f64](0.79473550581058f64) / math.pow[f64](n, 1.10081930350091f64)
        } else {
            f5 = 1.0f64 - math.exp[f64](0.673292623522027f64) / math.pow[f64](n, 0.691365864961895f64)
            f875 = 1.0f64 - math.exp[f64](0.446537815635445f64) / math.pow[f64](n, 1.06690782995919f64)
        }
    } else {
        var a500 = 0.0f64 - 1.42764571687802f64
        var a500b = 0.0f64 - 1.06141115981725f64
        var b500 = 1.26263336932151f64
        var b500b = 1.28907991440387f64
        var a875 = 0.0f64 - 0.455179464070565f64
        var a875b = 0.0f64 - 0.294241208320834f64
        var b875 = 1.11192541278794f64
        var b875b = 1.09649329149811f64
        if rew {
            a500 = 0.0f64 - 1.02842572724793f64
            a500b = 0.0f64 - 0.26800273450853f64
            b500 = 1.67659883081926f64
            b500b = 1.35968562893582f64
            a875 = 0.0f64 - 0.544482443573914f64
            a875b = 0.0f64 - 0.343791072183285f64
            b875 = 1.25994483222292f64
            b875b = 1.25159004257133f64
        }
        let l2 = math.log[f64](2.0f64 * pp * pp)
        let l3 = math.log[f64](3.0f64 * pp * pp)
        // solve [1 -l2; 1 -l3] c = y for each of the two curves
        let y5a = math.log[f64](0.0f64 - a500 / math.pow[f64](pp, b500))
        let y5b = math.log[f64](0.0f64 - a500b / math.pow[f64](pp, b500b))
        let y8a = math.log[f64](0.0f64 - a875 / math.pow[f64](pp, b875))
        let y8b = math.log[f64](0.0f64 - a875b / math.pow[f64](pp, b875b))
        let c25 = (y5b - y5a) / (l2 - l3)
        let c15 = y5a + l2 * c25
        let c28 = (y8b - y8a) / (l2 - l3)
        let c18 = y8a + l2 * c28
        f5 = 1.0f64 - math.exp[f64](c15) / math.pow[f64](n, c25)
        f875 = 1.0f64 - math.exp[f64](c18) / math.pow[f64](n, c28)
    }
    var fa = f5 + (f875 - f5) / 0.375f64 * (alpha - 0.5f64)
    if alpha > 0.875f64 { fa = f875 + (1.0f64 - f875) / 0.125f64 * (alpha - 0.875f64) }
    ret 1.0f64 / fa
}

// robustbase::covMcd(x, alpha, nsamp) for p >= 2 and n < 600: out = raw center (p), raw cov (p*p), center (p), cov (p*p), crit = log det (1), the weights-based count (1)
fn cov_mcd(a: *mem.Arena, g: *rng.Rng, x: []const f64, n: usize, p: usize, alpha: f64, nsamp: usize, out: []f64) -> err {
    let n2 = (n + p + 1usize) / 2usize
    let h = usize(math.floor[f64](2.0f64 * f64(n2) - f64(n) + 2.0f64 * f64(n - n2) * alpha))
    let (raw, e0) = mem.alloc[f64](a, p + p * p + 2usize)
    if e0 != ok { ret e0 }
    let fe = fastmcd_raw(a, g, x, n, p, h, nsamp, raw)
    if fe != ok { ret fe }
    let calpha = mcd_cons(f64(p), f64(h) / f64(n))
    let corr = mcd_cnp2_p(f64(p), f64(n), alpha, false)
    var i = 0usize
    while i < p {
        out[i] = raw[i]
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        out[p + i] = calpha * corr * raw[p + i]
        i += 1usize
    }
    // raw Mahalanobis distances against the scaled raw covariance
    let (inv, ie) = gp.invert(a, out[p..p + p * p], p)
    if ie != ok { ret ie }
    let cut = nmm.qchisq(0.975f64, f64(p), true, false)
    let (wts, we) = mem.alloc[f64](a, n)
    if we != ok { ret we }
    var sw = 0.0f64
    var r = 0usize
    while r < n {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                t = t + (x[r * p + j] - out[j]) * inv[j * p + k] * (x[r * p + k] - out[k])
                k += 1usize
            }
            j += 1usize
        }
        wts[r] = 0.0f64
        if t < cut { wts[r] = 1.0f64 }
        sw += wts[r]
        r += 1usize
    }
    if sw < 2.0f64 { ret McdUnsupported }
    let cen = out[p + p * p..p + p * p + p]
    i = 0usize
    while i < p {
        cen[i] = 0.0f64
        r = 0usize
        while r < n {
            cen[i] = cen[i] + wts[r] * x[r * p + i]
            r += 1usize
        }
        cen[i] = cen[i] / sw
        i += 1usize
    }
    let cv = out[2usize * p + p * p..2usize * p + 2usize * p * p]
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            r = 0usize
            while r < n {
                s = s + wts[r] * (x[r * p + i] - cen[i]) * (x[r * p + j] - cen[j])
                r += 1usize
            }
            cv[i * p + j] = s / (sw - 1.0f64)
            j += 1usize
        }
        i += 1usize
    }
    if sw != f64(n) {
        let f = mcd_cons(f64(p), 0.975f64) * mcd_cnp2_p(f64(p), f64(n), alpha, true)
        i = 0usize
        while i < p * p {
            cv[i] = cv[i] * f
            i += 1usize
        }
    }
    out[2usize * p + 2usize * p * p] = raw[p + p * p]
    out[2usize * p + 2usize * p * p + 1usize] = raw[p + p * p + 1usize]
    ret ok
}
