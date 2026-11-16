// Pieces of R KernSmooth and tseries: `bkde` (binned kernel density estimate, five kernels, the
// convolution summed directly where R uses an FFT), `dpik` (the direct plug-in bandwidth, level 2, normal
// kernel, scale estimate "minim"), tseries `jarque_bera` and `runs_test` (statistic and p-value).
//
// Not here: bkde2D, locpoly, dpill and the other tseries tests.

use e.algo.stat.classint as ci
use e.math
use e.math.dist as dist
use e.mem

error BadKernel

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn var_sd(x: []const f64) -> f64 {
    let m = ci.mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

// kernel 0 normal, 1 box, 2 epanech, 3 biweight, 4 triweight; bandwidth <= 0 selects the default
fn bkde(a: *mem.Arena, x: []const f64, kernel: u8, bandwidth: f64, gridsize: usize) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let n = x.len
    let nf = f64(n)
    var del0 = 0.0f64
    if kernel == 0u8 { del0 = math.pow[f64](1.0f64 / (4.0f64 * 3.141592653589793f64), 0.1f64) }
    if kernel == 1u8 { del0 = math.pow[f64](4.5f64, 0.2f64) }
    if kernel == 2u8 { del0 = math.pow[f64](15.0f64, 0.2f64) }
    if kernel == 3u8 { del0 = math.pow[f64](35.0f64, 0.2f64) }
    if kernel == 4u8 { del0 = math.pow[f64](9450.0f64 / 143.0f64, 0.2f64) }
    var h = bandwidth
    if !(bandwidth > 0.0f64) { h = del0 * math.pow[f64](243.0f64 / (35.0f64 * nf), 0.2f64) * var_sd(x) }
    var tau = 1.0f64
    if kernel == 0u8 { tau = 4.0f64 }
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let ra = lo - tau * h
    let rb = hi + tau * h
    let m = gridsize
    let (gp, ge) = mem.alloc[f64](a, m)
    if ge != ok { ret (none, none, ge) }
    let by = (rb - ra) / f64(m - 1usize)
    i = 0usize
    while i < m {
        gp[i] = ra + f64(i) * by
        i += 1usize
    }
    gp[0usize] = ra
    gp[m - 1usize] = rb
    let (gc, gce) = ci.linbin(a, x, ra, rb, m)
    if gce != ok { ret (none, none, gce) }
    let delta = (rb - ra) / (h * f64(m - 1usize))
    var l = usize(math.floor[f64](tau / delta))
    if l > m { l = m }
    let (kappa, ke) = mem.alloc[f64](a, l + 1usize)
    if ke != ok { ret (none, none, ke) }
    var tot = 0.0f64
    i = 0usize
    while i <= l {
        let u = f64(i) * delta
        var kv = 0.0f64
        if kernel == 0u8 {
            kv = math.exp[f64](0.0f64 - 0.5f64 * u * u) / 2.5066282746310002f64 / (nf * h)
        } else {
            let z = 0.5f64 * (u + 1.0f64)
            if z >= 0.0f64 && z <= 1.0f64 {
                var dens = 1.0f64
                if kernel == 2u8 { dens = 6.0f64 * z * (1.0f64 - z) }
                if kernel == 3u8 { dens = 30.0f64 * z * z * (1.0f64 - z) * (1.0f64 - z) }
                if kernel == 4u8 { dens = 140.0f64 * z * z * z * (1.0f64 - z) * (1.0f64 - z) * (1.0f64 - z) }
                kv = 0.5f64 * dens / (nf * h)
            }
        }
        kappa[i] = kv
        if i == 0usize { tot += kv } else { tot += 2.0f64 * kv }
        i += 1usize
    }
    tot = tot * (rb - ra) / f64(m - 1usize) * nf
    let (y, ye) = mem.alloc[f64](a, m)
    if ye != ok { ret (none, none, ye) }
    i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            var d = 0usize
            if j > i { d = j - i } else { d = i - j }
            if d <= l { s += kappa[d] / tot * gc[j] }
            j += 1usize
        }
        y[i] = s
        i += 1usize
    }
    ret (gp, y, ok)
}

// dpik(x): level 2, normal kernel, scale estimate minim
fn dpik(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let n = f64(x.len)
    let (s, se) = ci.sorted_copy(a, x)
    if se != ok { ret (0.0f64, se) }
    let mu = ci.mean_of(x)
    let sdv = var_sd(x)
    let iqr = (ci.quantile7(s, 0.75f64) - ci.quantile7(s, 0.25f64)) / 1.349f64
    var sc = sdv
    if iqr < sc { sc = iqr }
    if sc == 0.0f64 { ret (0.0f64, BadKernel) }
    let sa = (s[0usize] - mu) / sc
    let sb = (s[s.len - 1usize] - mu) / sc
    let (sx, xe) = mem.alloc[f64](a, x.len)
    if xe != ok { ret (0.0f64, xe) }
    var i = 0usize
    while i < x.len {
        sx[i] = (x[i] - mu) / sc
        i += 1usize
    }
    let (g, ge) = ci.linbin(a, sx, sa, sb, 401usize)
    if ge != ok { ret (0.0f64, ge) }
    let sqrt2 = math.sqrt[f64](2.0f64)
    var alpha = math.pow[f64](2.0f64 * math.pow[f64](sqrt2, 9.0f64) / (7.0f64 * n), 1.0f64 / 9.0f64)
    let psi6 = ci.bkfe(g, 6usize, alpha, sa, sb)
    alpha = math.pow[f64](0.0f64 - 3.0f64 * math.sqrt[f64](2.0f64 / 3.141592653589793f64) / (psi6 * n), 1.0f64 / 7.0f64)
    let psi4 = ci.bkfe(g, 4usize, alpha, sa, sb)
    let del0 = 1.0f64 / math.pow[f64](4.0f64 * 3.141592653589793f64, 0.1f64)
    ret (sc * del0 * math.pow[f64](1.0f64 / (psi4 * n), 0.2f64), ok)
}

// Jarque-Bera: the statistic and its chi-squared (2 df) p-value
fn jarque_bera(x: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    var m1 = 0.0f64
    var i = 0usize
    while i < x.len {
        m1 += x[i]
        i += 1usize
    }
    m1 = m1 / n
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    i = 0usize
    while i < x.len {
        let d = x[i] - m1
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        i += 1usize
    }
    m2 = m2 / n
    m3 = m3 / n
    m4 = m4 / n
    let b1 = (m3 / math.pow[f64](m2, 1.5f64)) * (m3 / math.pow[f64](m2, 1.5f64))
    let b2 = m4 / (m2 * m2)
    let stat = n * b1 / 6.0f64 + n * (b2 - 3.0f64) * (b2 - 3.0f64) / 24.0f64
    ret (stat, 1.0f64 - (1.0f64 - math.exp[f64](0.0f64 - stat / 2.0f64)))
}

// runs.test on a 0/1 sequence (level 0 first): the standard normal statistic and the two-sided p-value
fn runs_test(x: []const i64) -> (f64, f64) {
    let n = x.len
    var r = 1.0f64
    var i = 1usize
    while i < n {
        if x[i] != x[i - 1usize] { r += 1.0f64 }
        i += 1usize
    }
    var n1 = 0.0f64
    var n2 = 0.0f64
    i = 0usize
    while i < n {
        if x[i] == 0i64 { n1 += 1.0f64 } else { n2 += 1.0f64 }
        i += 1usize
    }
    let m = 1.0f64 + 2.0f64 * n1 * n2 / (n1 + n2)
    let s = math.sqrt[f64](2.0f64 * n1 * n2 * (2.0f64 * n1 * n2 - n1 - n2) / ((n1 + n2) * (n1 + n2) * (n1 + n2 - 1.0f64)))
    let stat = (r - m) / s
    var az = stat
    if az < 0.0f64 { az = 0.0f64 - az }
    ret (stat, 2.0f64 * dist.pnorm(0.0f64 - az, 0.0f64, 1.0f64, true, false))
}
