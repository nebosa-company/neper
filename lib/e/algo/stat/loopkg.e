// R loo and the generalized Pareto fit of posterior: waic, Pareto-smoothed importance sampling (psis with r_eff = 1) and the leave-one-out elpd of a log-likelihood matrix, one observation's S draws at a time (ll[i * S .. (i + 1) * S]).
//
// Not here: r_eff other than 1, truncated and standard importance sampling, loo_compare, loo_model_weights and E_loo.

use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// log(sum(exp(x)))
fn logsumexp(x: []const f64) -> f64 {
    var m = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] > m { m = x[i] }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += math.exp[f64](x[i] - m)
        i += 1usize
    }
    ret m + math.log[f64](s)
}

// posterior::gpdfit(x, wip = TRUE, min_grid_pts = 30, sort_x = FALSE) for an increasing x: (k, sigma); NaN k where x has no spread
fn gpdfit(a: *mem.Arena, x: []const f64) -> (f64, f64, err) {
    let n = x.len
    let nf = f64(n)
    let m = 30usize + usize(math.floor[f64](math.sqrt[f64](nf)))
    let (th, e1) = mem.alloc[f64](a, m)
    let (lt, e2) = mem.alloc[f64](a, m)
    if e1 != ok { ret (nan(), nan(), e1) }
    if e2 != ok { ret (nan(), nan(), e2) }
    let xstar = x[usize(math.floor[f64](nf / 4.0f64 + 0.5f64)) - 1usize]
    if !(xstar > x[0usize]) { ret (nan(), nan(), ok) }
    var j = 0usize
    while j < m {
        th[j] = 1.0f64 / x[n - 1usize] + (1.0f64 - math.sqrt[f64](f64(m) / (f64(j + 1usize) - 0.5f64))) / 3.0f64 / xstar
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += dist.log1p(0.0f64 - th[j] * x[i])
            i += 1usize
        }
        let k = s / nf
        lt[j] = nf * (math.log[f64](0.0f64 - th[j] / k) - k - 1.0f64)
        j += 1usize
    }
    let lse = logsumexp(lt)
    var theta_hat = 0.0f64
    j = 0usize
    while j < m {
        theta_hat += th[j] * math.exp[f64](lt[j] - lse)
        j += 1usize
    }
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        s2 += dist.log1p(0.0f64 - theta_hat * x[i])
        i += 1usize
    }
    var k_hat = s2 / nf
    let sigma = 0.0f64 - k_hat / theta_hat
    k_hat = (k_hat * nf + 0.5f64 * 10.0f64) / (nf + 10.0f64)
    if k_hat != k_hat { ret (1.0f64 / 0.0f64, nan(), ok) }
    ret (k_hat, sigma, ok)
}

// loo's do_psis_i for one observation (r_eff = 1): the smoothed log weights into lw (S values, not normalised) and the Pareto k
fn psis_i(a: *mem.Arena, lr: []const f64, lw: []f64) -> (f64, err) {
    let s = lr.len
    let sf = f64(s)
    var tail_len = usize(math.ceil[f64](math.min[f64](0.2f64 * sf, 3.0f64 * math.sqrt[f64](sf))))
    let (ord, e1) = mem.alloc[usize](a, s)
    let (srt, e2) = mem.alloc[f64](a, s)
    if e1 != ok { ret (nan(), e1) }
    if e2 != ok { ret (nan(), e2) }
    var mx = lr[0usize]
    var i = 0usize
    while i < s {
        if lr[i] > mx { mx = lr[i] }
        i += 1usize
    }
    i = 0usize
    while i < s {
        lw[i] = lr[i] - mx
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < s {
        let v = ord[i]
        var j = i
        while j > 0usize && lw[ord[j - 1usize]] > lw[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    i = 0usize
    while i < s {
        srt[i] = lw[ord[i]]
        i += 1usize
    }
    var khat = 1.0f64 / 0.0f64
    if tail_len >= 5usize {
        let first = s - tail_len
        let lo = srt[first]
        let hi = srt[s - 1usize]
        if math.abs[f64](hi - lo) >= 2.220446049250313e-16f64 / 100.0f64 {
            let cutoff = srt[first - 1usize]
            let ec = math.exp[f64](cutoff)
            let (ex, e3) = mem.alloc[f64](a, tail_len)
            if e3 != ok { ret (nan(), e3) }
            i = 0usize
            while i < tail_len {
                ex[i] = math.exp[f64](srt[first + i]) - ec
                i += 1usize
            }
            let (k, sg, ge) = gpdfit(a, ex)
            if ge != ok { ret (nan(), ge) }
            if k == k && k - k == 0.0f64 && sg > 0.0f64 {
                khat = k
                i = 0usize
                while i < tail_len {
                    let p = (f64(i + 1usize) - 0.5f64) / f64(tail_len)
                    var q = 0.0f64
                    if k == 0.0f64 {
                        q = 0.0f64 - sg * dist.log1p(0.0f64 - p)
                    } else {
                        q = sg * dist.expm1(0.0f64 - k * dist.log1p(0.0f64 - p)) / k
                    }
                    lw[ord[first + i]] = math.log[f64](q + ec)
                    i += 1usize
                }
            }
        }
    }
    i = 0usize
    while i < s {
        if lw[i] > 0.0f64 { lw[i] = 0.0f64 }
        lw[i] = lw[i] + mx
        i += 1usize
    }
    ret (khat, ok)
}


// loo(): per observation (elpd_loo, p_loo, pareto k) summed over observations into out (elpd_loo, p_loo, looic, sum of k); ll is n_obs blocks of s draws
fn loo_totals(a: *mem.Arena, ll: []const f64, s: usize, nobs: usize, out: []f64) -> err {
    let (lw, e1) = mem.alloc[f64](a, s)
    let (lr, e2) = mem.alloc[f64](a, s)
    let (t, e3) = mem.alloc[f64](a, s)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var elpd = 0.0f64
    var ploo = 0.0f64
    var ksum = 0.0f64
    var o = 0usize
    while o < nobs {
        let start = mem.mark(a)
        var i = 0usize
        while i < s {
            lr[i] = 0.0f64 - ll[o * s + i]
            i += 1usize
        }
        let (k, pe) = psis_i(a, lr, lw)
        if pe != ok { ret pe }
        let lse = logsumexp(lw)
        i = 0usize
        while i < s {
            t[i] = ll[o * s + i] + lw[i] - lse
            i += 1usize
        }
        let e_i = logsumexp(t)
        let lpd = logsumexp(ll[o * s..(o + 1usize) * s]) - math.log[f64](f64(s))
        elpd += e_i
        ploo += lpd - e_i
        ksum += k
        mem.reset(a, start)
        o += 1usize
    }
    out[0usize] = elpd
    out[1usize] = ploo
    out[2usize] = 0.0f64 - 2.0f64 * elpd
    out[3usize] = ksum
    ret ok
}

// waic(): (elpd_waic, p_waic, waic) summed over observations into out
fn waic_totals(ll: []const f64, s: usize, nobs: usize, out: []f64) {
    var elpd = 0.0f64
    var pw = 0.0f64
    var o = 0usize
    while o < nobs {
        let blk = ll[o * s..(o + 1usize) * s]
        let lpd = logsumexp(blk) - math.log[f64](f64(s))
        var m = 0.0f64
        var i = 0usize
        while i < s {
            m += blk[i]
            i += 1usize
        }
        m = m / f64(s)
        var v = 0.0f64
        i = 0usize
        while i < s {
            v += (blk[i] - m) * (blk[i] - m)
            i += 1usize
        }
        v = v / f64(s - 1usize)
        elpd += lpd - v
        pw += v
        o += 1usize
    }
    out[0usize] = elpd
    out[1usize] = pw
    out[2usize] = 0.0f64 - 2.0f64 * elpd
}
