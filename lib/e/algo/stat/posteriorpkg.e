// R posterior: split-Rhat (rhat), the bulk and tail effective sample sizes (ess_bulk, ess_tail, ess_mean, ess_quantile) and the Monte Carlo standard error of the mean (mcse_mean), for a draws matrix given chain by chain (chain c occupies x[c * n .. (c + 1) * n]).
//
// Not here: mcse_quantile, mcse_sd, the other summaries, rhat_basic and summarise_draws.

use e.algo.stat.loopkg as lp
use e.algo.stat.mass as ms
use e.math.nmath_beta as nb
use e.math
use e.math.dist as dist
use e.mem

// posterior's .split_chains: every chain cut into its first floor(n / 2) draws and its last floor(n / 2); out has 2 * chains * half values, chain-major; returns half
fn split_chains(x: []const f64, nchain: usize, n: usize, out: []f64) -> usize {
    let half = n / 2usize
    var c = 0usize
    while c < nchain {
        var i = 0usize
        while i < half {
            out[(2usize * c) * half + i] = x[c * n + i]
            out[(2usize * c + 1usize) * half + i] = x[c * n + n - half + i]
            i += 1usize
        }
        c += 1usize
    }
    ret half
}

// the biased autocovariance (divided by n) at lags 0 .. n - 1: what posterior's FFT version returns for a non-constant series
fn acov(x: []const f64, out: []f64) {
    let n = x.len
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i]
        i += 1usize
    }
    m = m / f64(n)
    var k = 0usize
    while k < n {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i] - m) * (x[i + k] - m)
            i += 1usize
        }
        out[k] = s / f64(n)
        k += 1usize
    }
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

fn var_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// posterior's .rhat of nchain chains of n draws
fn rhat_plain(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let (cm, e1) = mem.alloc[f64](a, nchain)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var wsum = 0.0f64
    var c = 0usize
    while c < nchain {
        cm[c] = mean_of(x[c * n..(c + 1usize) * n])
        wsum += var_of(x[c * n..(c + 1usize) * n])
        c += 1usize
    }
    let vb = f64(n) * var_of(cm)
    let vw = wsum / f64(nchain)
    ret math.sqrt[f64]((vb / vw + f64(n) - 1.0f64) / f64(n))
}

// posterior's .ess of nchain chains of n draws
fn ess_plain(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    if n < 3usize { ret nan }
    let (am, e1) = mem.alloc[f64](a, n)
    let (ac, e2) = mem.alloc[f64](a, n)
    let (rho, e3) = mem.alloc[f64](a, n + 2usize)
    let (cm, e4) = mem.alloc[f64](a, nchain)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var k = 0usize
    while k < n {
        am[k] = 0.0f64
        rho[k] = 0.0f64
        k += 1usize
    }
    var c = 0usize
    while c < nchain {
        acov(x[c * n..(c + 1usize) * n], ac)
        // posterior's autocovariance carries var * (n - 1) / n scaling over the lag-0 term: the biased estimator, as acov
        k = 0usize
        while k < n {
            am[k] += ac[k] / f64(nchain)
            k += 1usize
        }
        cm[c] = mean_of(x[c * n..(c + 1usize) * n])
        c += 1usize
    }
    let nn = f64(n)
    let mean_var = am[0usize] * nn / (nn - 1.0f64)
    var var_plus = mean_var * (nn - 1.0f64) / nn
    if nchain > 1usize { var_plus += var_of(cm) }
    var t = 0usize
    var rho_even = 1.0f64
    rho[0usize] = rho_even
    var rho_odd = 1.0f64 - (mean_var - am[1usize]) / var_plus
    rho[1usize] = rho_odd
    while t + 5usize < n && rho_even + rho_odd > 0.0f64 {
        t += 2usize
        rho_even = 1.0f64 - (mean_var - am[t]) / var_plus
        rho_odd = 1.0f64 - (mean_var - am[t + 1usize]) / var_plus
        if rho_even + rho_odd >= 0.0f64 {
            rho[t] = rho_even
            rho[t + 1usize] = rho_odd
        }
    }
    let max_t = t
    if rho_even > 0.0f64 { rho[max_t] = rho_even }
    t = 0usize
    while max_t >= 4usize && t <= max_t - 4usize {
        t += 2usize
        if rho[t] + rho[t + 1usize] > rho[t - 2usize] + rho[t - 1usize] {
            rho[t] = (rho[t - 2usize] + rho[t - 1usize]) / 2.0f64
            rho[t + 1usize] = rho[t]
        }
    }
    var sm = 0.0f64
    k = 0usize
    while k < max_t {
        sm += rho[k]
        k += 1usize
    }
    var tau = 0.0f64 - 1.0f64 + 2.0f64 * sm + rho[max_t]
    let ess0 = f64(nchain) * nn
    let bound = 1.0f64 / math.log10[f64](ess0)
    if tau < bound { tau = bound }
    ret ess0 / tau
}

// z_scale on the whole array: qnorm((rank - 3/8) / (S - 2 * 3/8 + 1)) with average ranks over ties
fn z_scale(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let s = x.len
    let (ord, e) = mem.alloc[usize](a, s)
    if e != ok { ret e }
    var i = 0usize
    while i < s {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < s {
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
    while i < s {
        var j = i
        while j + 1usize < s && x[ord[j + 1usize]] == x[ord[i]] { j += 1usize }
        let r = (f64(i + 1usize) + f64(j + 1usize)) / 2.0f64
        let z = dist.qnorm((r - 0.375f64) / (f64(s) - 0.75f64 + 1.0f64), 0.0f64, 1.0f64, true, false)
        var q = i
        while q <= j {
            out[ord[q]] = z
            q += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

fn median_of(a: *mem.Arena, x: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
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
    ret ms.quant7(s, 0.5f64)
}

// ess_bulk(x): the ESS of the rank-normalised split chains
fn ess_bulk(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let (sp, e1) = mem.alloc[f64](a, nchain * n)
    let (z, e2) = mem.alloc[f64](a, nchain * n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let half = split_chains(x, nchain, n, sp)
    if z_scale(a, sp[0usize..2usize * nchain * half], z) != ok { ret 0.0f64 / 0.0f64 }
    ret ess_plain(a, z, 2usize * nchain, half)
}

// ess_mean(x): the ESS of the split chains as they are
fn ess_mean(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let (sp, e1) = mem.alloc[f64](a, nchain * n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let half = split_chains(x, nchain, n, sp)
    ret ess_plain(a, sp, 2usize * nchain, half)
}

// ess_quantile(x, prob): the ESS of the split indicator of x <= quantile(x, prob)
fn ess_quantile(a: *mem.Arena, x: []const f64, nchain: usize, n: usize, prob0: f64) -> f64 {
    var prob = prob0
    let len = nchain * n
    if prob == 1.0f64 { prob = (f64(len) - 0.5f64) / f64(len) }
    let (s, e0) = mem.alloc[f64](a, len)
    let (ind, e1) = mem.alloc[f64](a, len)
    let (sp, e2) = mem.alloc[f64](a, len)
    if e0 != ok || e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    let q = ms.quant7(s, prob)
    i = 0usize
    while i < len {
        if x[i] <= q { ind[i] = 1.0f64 } else { ind[i] = 0.0f64 }
        i += 1usize
    }
    let half = split_chains(ind, nchain, n, sp)
    ret ess_plain(a, sp, 2usize * nchain, half)
}

// ess_tail(x): the smaller of the 5% and 95% quantile ESS
fn ess_tail(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let lo = ess_quantile(a, x, nchain, n, 0.05f64)
    let hi = ess_quantile(a, x, nchain, n, 0.95f64)
    if hi < lo { ret hi }
    ret lo
}

// rhat(x): the larger of the split Rhat of the rank-normalised draws and of the rank-normalised folded draws
fn rhat(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let len = nchain * n
    let (sp, e1) = mem.alloc[f64](a, len)
    let (z, e2) = mem.alloc[f64](a, len)
    let (fo, e3) = mem.alloc[f64](a, len)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    let half = split_chains(x, nchain, n, sp)
    if z_scale(a, sp[0usize..2usize * nchain * half], z) != ok { ret 0.0f64 / 0.0f64 }
    let bulk = rhat_plain(a, z, 2usize * nchain, half)
    let med = median_of(a, x)
    var i = 0usize
    while i < len {
        fo[i] = math.abs[f64](x[i] - med)
        i += 1usize
    }
    let half2 = split_chains(fo, nchain, n, sp)
    if z_scale(a, sp[0usize..2usize * nchain * half2], z) != ok { ret 0.0f64 / 0.0f64 }
    let tail = rhat_plain(a, z, 2usize * nchain, half2)
    if tail > bulk { ret tail }
    ret bulk
}

// mcse_mean(x) = sd(x) / sqrt(ess_mean(x)) over all draws
fn mcse_mean(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    ret math.sqrt[f64](var_of(x[0usize..nchain * n])) / math.sqrt[f64](ess_mean(a, x, nchain, n))
}

// a sorted copy of x (insertion sort)
fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
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

// rhat_basic(x, split): the plain Rhat of the (split) chains
fn rhat_basic(a: *mem.Arena, x: []const f64, nchain: usize, n: usize, split: bool) -> f64 {
    if !split { ret rhat_plain(a, x, nchain, n) }
    let (sp, e1) = mem.alloc[f64](a, nchain * n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let half = split_chains(x, nchain, n, sp)
    ret rhat_plain(a, sp, 2usize * nchain, half)
}

// ess_sd(x): the ESS of the split squared deviations from the overall mean
fn ess_sd(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let len = nchain * n
    let (d, e1) = mem.alloc[f64](a, len)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let m = mean_of(x[0usize..len])
    var i = 0usize
    while i < len {
        d[i] = (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret ess_mean(a, d, nchain, n)
}

// mcse_sd(x)
fn mcse_sd(a: *mem.Arena, x: []const f64, nchain: usize, n: usize) -> f64 {
    let len = nchain * n
    let (d, e1) = mem.alloc[f64](a, len)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let m = mean_of(x[0usize..len])
    var i = 0usize
    var ev = 0.0f64
    var m4 = 0.0f64
    while i < len {
        let c = x[i] - m
        d[i] = c * c
        ev += c * c
        m4 += c * c * c * c
        i += 1usize
    }
    ev = ev / f64(len)
    m4 = m4 / f64(len)
    let ess = ess_mean(a, d, nchain, n)
    let varvar = (m4 - ev * ev) / ess
    ret math.sqrt[f64](varvar / ev / 4.0f64)
}

// mcse_quantile(x, prob)
fn mcse_quantile(a: *mem.Arena, x: []const f64, nchain: usize, n: usize, prob: f64) -> f64 {
    let len = nchain * n
    let ess = ess_quantile(a, x, nchain, n, prob)
    let a1 = nb.qbeta(0.1586553f64, ess * prob + 1.0f64, ess * (1.0f64 - prob) + 1.0f64, true, false)
    let a2 = nb.qbeta(0.8413447f64, ess * prob + 1.0f64, ess * (1.0f64 - prob) + 1.0f64, true, false)
    let (s, e) = sorted_copy(a, x[0usize..len])
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i1 = usize(math.floor[f64](a1 * f64(len)))
    if i1 < 1usize { i1 = 1usize }
    var i2 = usize(math.ceil[f64](a2 * f64(len)))
    if i2 > len { i2 = len }
    ret (s[i2 - 1usize] - s[i1 - 1usize]) / 2.0f64
}

// stats::mad: 1.4826 median(|x - median(x)|)
fn mad_of(a: *mem.Arena, x: []const f64) -> f64 {
    let med = median_of(a, x)
    let (d, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        d[i] = math.abs[f64](x[i] - med)
        i += 1usize
    }
    ret 1.4826f64 * median_of(a, d)
}

// quantile(x, prob) type 7
fn quantile_of(a: *mem.Arena, x: []const f64, prob: f64) -> f64 {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret ms.quant7(s, prob)
}

// summarise_draws(x) into out: mean, median, sd, mad, q5, q95, rhat, ess_bulk, ess_tail
fn summarise(a: *mem.Arena, x: []const f64, nchain: usize, n: usize, out: []f64) {
    let all = x[0usize..nchain * n]
    out[0usize] = mean_of(all)
    out[1usize] = median_of(a, all)
    out[2usize] = math.sqrt[f64](var_of(all))
    out[3usize] = mad_of(a, all)
    out[4usize] = quantile_of(a, all, 0.05f64)
    out[5usize] = quantile_of(a, all, 0.95f64)
    out[6usize] = rhat(a, x, nchain, n)
    out[7usize] = ess_bulk(a, x, nchain, n)
    out[8usize] = ess_tail(a, x, nchain, n)
}

// one tail of posterior:::ps_tail on x in place (tail 1 = right, 2 = left): the Pareto k, NaN where no fit was made
fn ps_tail(a: *mem.Arena, x: []f64, ndt: usize, left: bool) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    let s = x.len
    let (y, e0) = mem.alloc[f64](a, s)
    let (ord, e1) = mem.alloc[usize](a, s)
    if e0 != ok { ret (nan, e0) }
    if e1 != ok { ret (nan, e1) }
    var i = 0usize
    while i < s {
        if left { y[i] = 0.0f64 - x[i] } else { y[i] = x[i] }
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < s {
        let v = ord[i]
        var j = i
        while j > 0usize && y[ord[j - 1usize]] > y[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    let first = s - ndt
    let lo = y[ord[first]]
    let hi = y[ord[s - 1usize]]
    if math.abs[f64](hi - lo) < 2.220446049250313e-16f64 { ret (nan, ok) }
    var cutoff = y[ord[first - 1usize]]
    if cutoff == lo { cutoff = cutoff - 2.220446049250313e-16f64 }
    let (ex, e2) = mem.alloc[f64](a, ndt)
    if e2 != ok { ret (nan, e2) }
    i = 0usize
    while i < ndt {
        ex[i] = y[ord[first + i]] - cutoff
        i += 1usize
    }
    let (k, sg, ge) = lp.gpdfit(a, ex)
    if ge != ok { ret (nan, ge) }
    if k == k && k - k == 0.0f64 && sg > 0.0f64 {
        i = 0usize
        while i < ndt {
            let p = (f64(i + 1usize) - 0.5f64) / f64(ndt)
            var q = 0.0f64
            if k == 0.0f64 { q = cutoff - sg * dist.log1p(0.0f64 - p) } else { q = cutoff + sg * dist.expm1(0.0f64 - k * dist.log1p(0.0f64 - p)) / k }
            if q > hi { q = hi }
            y[ord[first + i]] = q
            i += 1usize
        }
    }
    i = 0usize
    while i < s {
        if left { x[i] = 0.0f64 - y[i] } else { x[i] = y[i] }
        i += 1usize
    }
    ret (k, ok)
}

// pareto_smooth(x, tail, r_eff, return_k, extra_diags) of one vector (tail 0 both, 1 right, 2 left; r_eff <= 0 for the default ess_tail(x) / S): the smoothed draws into out and (khat, min_ss, khat_threshold, convergence_rate); NaN khat where no fit was made
fn pareto_smooth(a: *mem.Arena, x: []const f64, tail: usize, r_eff0: f64, out: []f64) -> (f64, f64, f64, f64, err) {
    let nan = 0.0f64 / 0.0f64
    let s = x.len
    let sf = f64(s)
    var i = 0usize
    while i < s {
        out[i] = x[i]
        i += 1usize
    }
    var r_eff = r_eff0
    if !(r_eff > 0.0f64) { r_eff = ess_tail(a, x, 1usize, s) / sf }
    var ndt0 = math.floor[f64](sf / 5.0f64)
    if sf * r_eff > 225.0f64 { ndt0 = math.floor[f64](3.0f64 * math.sqrt[f64](sf / r_eff)) }
    var ndt = usize(ndt0)
    if ndt < 5usize { ndt = 5usize }
    if ndt >= s { ret (nan, nan, nan, nan, ok) }
    if tail == 0usize && f64(ndt) > sf / 2.0f64 { ndt = usize(math.floor[f64](sf / 2.0f64)) }
    var k = nan
    if tail == 0usize {
        let (k1, e1) = ps_tail(a, out, ndt, true)
        if e1 != ok { ret (nan, nan, nan, nan, e1) }
        let (k2, e2) = ps_tail(a, out, ndt, false)
        if e2 != ok { ret (nan, nan, nan, nan, e2) }
        k = k2
        if k1 == k1 && (k2 != k2 || k1 > k2) { k = k1 }
    } else {
        let (k1, e1) = ps_tail(a, out, ndt, tail == 2usize)
        if e1 != ok { ret (nan, nan, nan, nan, e1) }
        k = k1
    }
    if k != k { ret (nan, nan, nan, nan, ok) }
    var min_ss = 1.0f64 / 0.0f64
    if k < 1.0f64 {
        var kp = k
        if kp < 0.0f64 { kp = 0.0f64 }
        min_ss = math.pow[f64](10.0f64, 1.0f64 / (1.0f64 - kp))
    }
    let thr = 1.0f64 - 1.0f64 / math.log10[f64](sf)
    var rate = 0.0f64
    if k < 0.0f64 {
        rate = 1.0f64
    } else if k > 1.0f64 {
        rate = 0.0f64
    } else if k == 0.5f64 {
        rate = 1.0f64 - 1.0f64 / math.log[f64](sf)
    } else {
        let p2 = math.pow[f64](sf, 2.0f64 * k)
        rate = (2.0f64 * (k - 1.0f64) * math.pow[f64](sf, 2.0f64 * k + 1.0f64) + (1.0f64 - 2.0f64 * k) * p2 + sf * sf) / ((sf - 1.0f64) * (sf - p2))
        if rate < 0.0f64 { rate = 0.0f64 }
    }
    ret (k, min_ss, thr, rate, ok)
}
