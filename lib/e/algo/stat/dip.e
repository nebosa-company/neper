// R diptest::dip, the Hartigan dip statistic (Algorithm AS 217, with the 1994 and 2003 fixes) for a sorted sample:
// the greatest convex minorant and least concave majorant are walked from the current modal interval until it
// stops shrinking. Answers the dip and the 1-based modal interval [low, high], so the modes are x[low] and
// x[high].
//
// Also `dip_p`, the table-interpolated p value of dip.test. Not here: the simulated p value.

use e.algo.rand.r as rr
use e.algo.sort
use e.algo.stat.dip_table as tb
use e.math
use e.mem

type Dip = struct { dip: f64, low: usize, high: usize }

fn dip(a: *mem.Arena, xs: []const f64, min_is_0: bool) -> (Dip, err) {
    let n = xs.len
    var res: Dip = zero
    let (mn, e1) = mem.alloc[usize](a, n + 2usize)
    let (mj, e2) = mem.alloc[usize](a, n + 2usize)
    let (gcm, e3) = mem.alloc[usize](a, n + 2usize)
    let (lcm, e4) = mem.alloc[usize](a, n + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (res, e1) }
    // x[k] is xs[k - 1]
    var low = 1usize
    var high = n
    var d_ip = 1.0f64
    if min_is_0 { d_ip = 0.0f64 }
    if n < 2usize || xs[n - 1usize] == xs[0usize] {
        res.dip = d_ip / f64(2usize * n)
        res.low = low
        res.high = high
        ret (res, ok)
    }
    mn[1usize] = 1usize
    var j = 2usize
    while j <= n {
        mn[j] = j - 1usize
        var go = true
        while go {
            let mnj = mn[j]
            let mnmnj = mn[mnj]
            if mnj == 1usize || (xs[j - 1usize] - xs[mnj - 1usize]) * (f64(mnj) - f64(mnmnj)) < (xs[mnj - 1usize] - xs[mnmnj - 1usize]) * (f64(j) - f64(mnj)) {
                go = false
            } else {
                mn[j] = mnmnj
            }
        }
        j += 1usize
    }
    mj[n] = n
    var k = n - 1usize
    while k >= 1usize {
        mj[k] = k + 1usize
        var go = true
        while go {
            let mjk = mj[k]
            let mjmjk = mj[mjk]
            if mjk == n || (xs[k - 1usize] - xs[mjk - 1usize]) * (f64(mjk) - f64(mjmjk)) < (xs[mjk - 1usize] - xs[mjmjk - 1usize]) * (f64(k) - f64(mjk)) {
                go = false
            } else {
                mj[k] = mjmjk
            }
        }
        k -= 1usize
    }
    var again = true
    while again {
        gcm[1usize] = high
        var i = 1usize
        while gcm[i] > low {
            gcm[i + 1usize] = mn[gcm[i]]
            i += 1usize
        }
        var ig = i
        let l_gcm = i
        var ix = ig - 1usize
        lcm[1usize] = low
        i = 1usize
        while lcm[i] < high {
            lcm[i + 1usize] = mj[lcm[i]]
            i += 1usize
        }
        var ih = i
        let l_lcm = i
        var iv = 2usize
        var d = 0.0f64
        if l_gcm != 2usize || l_lcm != 2usize {
            var more = true
            while more {
                let gcmix = gcm[ix]
                let lcmiv = lcm[iv]
                if gcmix > lcmiv {
                    let gcmi1 = gcm[ix + 1usize]
                    let dx = (f64(lcmiv) - f64(gcmi1) + 1.0f64) - (xs[lcmiv - 1usize] - xs[gcmi1 - 1usize]) * (f64(gcmix) - f64(gcmi1)) / (xs[gcmix - 1usize] - xs[gcmi1 - 1usize])
                    iv += 1usize
                    if dx >= d {
                        d = dx
                        ig = ix + 1usize
                        ih = iv - 1usize
                    }
                } else {
                    let lcmiv1 = lcm[iv - 1usize]
                    let dx = (xs[gcmix - 1usize] - xs[lcmiv1 - 1usize]) * (f64(lcmiv) - f64(lcmiv1)) / (xs[lcmiv - 1usize] - xs[lcmiv1 - 1usize]) - (f64(gcmix) - f64(lcmiv1) - 1.0f64)
                    ix -= 1usize
                    if dx >= d {
                        d = dx
                        ig = ix + 1usize
                        ih = iv
                    }
                }
                if ix < 1usize { ix = 1usize }
                if iv > l_lcm { iv = l_lcm }
                if gcm[ix] == lcm[iv] { more = false }
            }
        } else {
            d = 1.0f64
            if min_is_0 { d = 0.0f64 }
        }
        if d < d_ip { break }
        var dip_l = 0.0f64
        j = ig
        while j < l_gcm {
            var max_t = 1.0f64
            let jb = gcm[j + 1usize]
            let je = gcm[j]
            if je - jb > 1usize && xs[je - 1usize] != xs[jb - 1usize] {
                let c = (f64(je) - f64(jb)) / (xs[je - 1usize] - xs[jb - 1usize])
                var jj = jb
                while jj <= je {
                    let t = (f64(jj) - f64(jb) + 1.0f64) - (xs[jj - 1usize] - xs[jb - 1usize]) * c
                    if max_t < t { max_t = t }
                    jj += 1usize
                }
            }
            if dip_l < max_t { dip_l = max_t }
            j += 1usize
        }
        var dip_u = 0.0f64
        j = ih
        while j < l_lcm {
            var max_t = 1.0f64
            let jb = lcm[j]
            let je = lcm[j + 1usize]
            if je - jb > 1usize && xs[je - 1usize] != xs[jb - 1usize] {
                let c = (f64(je) - f64(jb)) / (xs[je - 1usize] - xs[jb - 1usize])
                var jj = jb
                while jj <= je {
                    let t = (xs[jj - 1usize] - xs[jb - 1usize]) * c - (f64(jj) - f64(jb) - 1.0f64)
                    if max_t < t { max_t = t }
                    jj += 1usize
                }
            }
            if dip_u < max_t { dip_u = max_t }
            j += 1usize
        }
        var dipnew = dip_l
        if dip_u > dip_l { dipnew = dip_u }
        if d_ip < dipnew { d_ip = dipnew }
        if low == gcm[ig] && high == lcm[ih] {
            again = false
        } else {
            low = gcm[ig]
            high = lcm[ih]
        }
    }
    res.dip = d_ip / f64(2usize * n)
    res.low = low
    res.high = high
    ret (res, ok)
}

// dip.test's interpolated p value for a sample of n values with dip d: the table of simulated quantiles is
// interpolated in sqrt(n) and then in the probabilities (approx with rule = 2, ties averaged)
fn dip_p(n: usize, d: f64) -> f64 {
    if n <= 3usize { ret 1.0f64 }
    let tab = tb.dip_table()
    let sizes = tb.dip_sizes()
    let probs = tb.dip_probs()
    var i_n = 20usize
    var n0 = sizes[20usize]
    var n1 = n0
    var i2 = 20usize
    var f = 0.0f64
    let nf = f64(n)
    if nf < n0 {
        i_n = 0usize
        var k = 0usize
        while k < 21usize {
            if sizes[k] <= nf { i_n = k }
            k += 1usize
        }
        i2 = i_n + 1usize
        n0 = sizes[i_n]
        n1 = sizes[i2]
        f = (nf - n0) / (n1 - n0)
    }
    var xs: [26]f64 = zero
    var ys: [26]f64 = zero
    var m = 0usize
    var j = 0usize
    var cnt = 0.0f64
    while j < 26usize {
        let y0 = math.sqrt[f64](n0) * tab[i_n * 26usize + j]
        let y1 = math.sqrt[f64](n1) * tab[i2 * 26usize + j]
        let x = y0 + f * (y1 - y0)
        if m > 0usize && xs[m - 1usize] == x {
            ys[m - 1usize] = (ys[m - 1usize] * cnt + probs[j]) / (cnt + 1.0f64)
            cnt += 1.0f64
        } else {
            xs[m] = x
            ys[m] = probs[j]
            cnt = 1.0f64
            m += 1usize
        }
        j += 1usize
    }
    let v = math.sqrt[f64](nf) * d
    var p = 0.0f64
    if v <= xs[0usize] {
        p = ys[0usize]
    } else if v >= xs[m - 1usize] {
        p = ys[m - 1usize]
    } else {
        var lo = 0usize
        var hi = m - 1usize
        while lo + 1usize < hi {
            let mid = (lo + hi) / 2usize
            if v < xs[mid] { hi = mid } else { lo = mid }
        }
        if v == xs[hi] {
            p = ys[hi]
        } else if v == xs[lo] {
            p = ys[lo]
        } else {
            p = ys[lo] + (ys[hi] - ys[lo]) * ((v - xs[lo]) / (xs[hi] - xs[lo]))
        }
    }
    ret 1.0f64 - p
}

fn cmp_f64(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// dip.test(x, simulate.p.value = TRUE, B): the share of B uniform samples of size n whose dip reaches d, drawing
// from the R generator `g` (seed it with set.seed's value first)
fn dip_sim_p(a: *mem.Arena, g: *rr.Rng, n: usize, d: f64, reps: usize) -> (f64, err) {
    let (u, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64, e) }
    var hits = 0usize
    var b = 0usize
    while b < reps {
        var i = 0usize
        while i < n {
            u[i] = rr.runif(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        var ctx = 0u8
        sort.in_place_by[f64, u8](u, &ctx, cmp_f64)
        let (r, de) = dip(a, u, false)
        if de != ok { ret (0.0f64, de) }
        if d <= r.dip { hits += 1usize }
        b += 1usize
    }
    ret (f64(hits) / f64(reps), ok)
}
