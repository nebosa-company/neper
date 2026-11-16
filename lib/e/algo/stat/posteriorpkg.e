// R posterior: split-Rhat (rhat), the bulk and tail effective sample sizes (ess_bulk, ess_tail, ess_mean, ess_quantile) and the Monte Carlo standard error of the mean (mcse_mean), for a draws matrix given chain by chain (chain c occupies x[c * n .. (c + 1) * n]).
//
// Not here: mcse_quantile, mcse_sd, the other summaries, rhat_basic and summarise_draws.

use e.algo.stat.mass as ms
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
