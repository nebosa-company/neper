// R survey: the means, totals and ratios of a stratified cluster sample with their Taylor-linearisation standard errors (svymean, svytotal, svyratio), with or without a finite-population correction given as the number of PSUs in each stratum.
//
// Not here: replicate-weight designs, calibration, svyglm, quantiles, domains, multistage variance with several ids, lonely PSUs.

use e.math
use e.mem

// the linearised variance of the total of z over a design: strata[i] in 0 .. nh, psu[i] in 0 .. np (unique across strata), fpc[h] the PSU population of stratum h (0 for none)
fn lin_var(a: *mem.Arena, z: []const f64, strata: []const f64, psu: []const f64, fpc: []const f64, nh: usize, np: usize) -> f64 {
    let (tot, e1) = mem.alloc[f64](a, np)
    let (sh, e2) = mem.alloc[usize](a, np)
    let (cnt, e3) = mem.alloc[f64](a, nh)
    let (sm, e4) = mem.alloc[f64](a, nh)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < np {
        tot[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nh {
        cnt[i] = 0.0f64
        sm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < z.len {
        tot[usize(psu[i])] += z[i]
        sh[usize(psu[i])] = usize(strata[i])
        i += 1usize
    }
    i = 0usize
    while i < np {
        cnt[sh[i]] += 1.0f64
        sm[sh[i]] += tot[i]
        i += 1usize
    }
    var v = 0.0f64
    var h = 0usize
    while h < nh {
        let nhf = cnt[h]
        let mean = sm[h] / nhf
        var ss = 0.0f64
        i = 0usize
        while i < np {
            if sh[i] == h { ss += (tot[i] - mean) * (tot[i] - mean) }
            i += 1usize
        }
        var f = 1.0f64
        if fpc[h] > 0.0f64 { f = 1.0f64 - nhf / fpc[h] }
        v += f * nhf / (nhf - 1.0f64) * ss
        h += 1usize
    }
    ret v
}

// out: mean, se(mean), total, se(total), ratio y / x, se(ratio)
fn estimates(a: *mem.Arena, y: []const f64, x: []const f64, w: []const f64, strata: []const f64, psu: []const f64, fpc: []const f64, nh: usize, np: usize, out: []f64) -> err {
    let n = y.len
    let (z, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var sw = 0.0f64
    var swy = 0.0f64
    var swx = 0.0f64
    var i = 0usize
    while i < n {
        sw += w[i]
        swy += w[i] * y[i]
        swx += w[i] * x[i]
        i += 1usize
    }
    let mean = swy / sw
    i = 0usize
    while i < n {
        z[i] = w[i] * (y[i] - mean) / sw
        i += 1usize
    }
    out[0usize] = mean
    out[1usize] = math.sqrt[f64](lin_var(a, z, strata, psu, fpc, nh, np))
    i = 0usize
    while i < n {
        z[i] = w[i] * y[i]
        i += 1usize
    }
    out[2usize] = swy
    out[3usize] = math.sqrt[f64](lin_var(a, z, strata, psu, fpc, nh, np))
    let r = swy / swx
    i = 0usize
    while i < n {
        z[i] = w[i] * (y[i] - r * x[i]) / swx
        i += 1usize
    }
    out[4usize] = r
    out[5usize] = math.sqrt[f64](lin_var(a, z, strata, psu, fpc, nh, np))
    ret ok
}
