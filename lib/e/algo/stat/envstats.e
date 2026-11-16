// R EnvStats: Rosner's generalised ESD test for outliers (rosnerTest and its critical values), the normal tolerance
// interval factors (tolIntNormK) for the one-sided content, the expectation and the Wald-Wolfowitz two-sided content
// types, and the normal prediction interval factor (predIntNormK) for one future observation or a Bonferroni set.
// The non-central t quantile is R's own bisection (qnt.c).
//
// Not here: the exact two-sided tolerance factor (a nested integral and optimiser), the exact multiple-prediction
// factor (Dunnett's multivariate t), the other estimation, interval and testing families of the package.

use e.math
use e.math.dist as dist
use e.math.nchisq as nc
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Rosner = struct { n: usize, k: usize, mean: []f64, sd: []f64, value: []f64, obs: []f64, r: []f64, lambda: []f64, outlier: []bool, nout: usize }

// the critical value lambda_{i+1} for a sample of n with i observations already removed (k = i + 1)
fn rosner_lambda(n: usize, k: usize, alpha: f64) -> f64 {
    let l = f64(k) - 1.0f64
    let p = 1.0f64 - (alpha / 2.0f64) / (f64(n) - l)
    let tc = nb.qt(p, f64(n) - l - 2.0f64, true, false)
    ret tc * (f64(n) - l - 1.0f64) / math.sqrt[f64]((f64(n) - l - 2.0f64 + tc * tc) * (f64(n) - l))
}

fn rosner_test(a: *mem.Arena, x: []const f64, k: usize, alpha: f64) -> (Rosner, err) {
    var r: Rosner = zero
    let n = x.len
    r.n = n
    r.k = k
    let (mean, e1) = mem.alloc[f64](a, k)
    let (sd, e2) = mem.alloc[f64](a, k)
    let (val, e3) = mem.alloc[f64](a, k)
    let (obs, e4) = mem.alloc[f64](a, k)
    let (rr, e5) = mem.alloc[f64](a, k)
    let (lam, e6) = mem.alloc[f64](a, k)
    let (out, e7) = mem.alloc[bool](a, k)
    let (cur, e8) = mem.alloc[f64](a, n)
    let (num, e9) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (r, mem.Full) }
    let nan = 0.0f64 / 0.0f64
    var i = 0usize
    while i < n {
        cur[i] = x[i]
        num[i] = i + 1usize
        i += 1usize
    }
    var m = n
    var stopped = false
    i = 0usize
    while i < k {
        mean[i] = nan
        sd[i] = nan
        val[i] = nan
        obs[i] = nan
        rr[i] = nan
        out[i] = false
        if !stopped {
            var s = 0.0f64
            var j = 0usize
            while j < m {
                s += cur[j]
                j += 1usize
            }
            let mu = s / f64(m)
            var ss = 0.0f64
            j = 0usize
            while j < m {
                ss += (cur[j] - mu) * (cur[j] - mu)
                j += 1usize
            }
            let sdv = math.sqrt[f64](ss / f64(m - 1usize))
            mean[i] = mu
            sd[i] = sdv
            if sdv > 0.0f64 {
                var best = 0usize
                var bz = math.abs[f64](cur[0usize] - mu) / sdv
                j = 1usize
                while j < m {
                    let z = math.abs[f64](cur[j] - mu) / sdv
                    if z > bz {
                        bz = z
                        best = j
                    }
                    j += 1usize
                }
                rr[i] = bz
                val[i] = cur[best]
                obs[i] = f64(num[best])
                j = best
                while j + 1usize < m {
                    cur[j] = cur[j + 1usize]
                    num[j] = num[j + 1usize]
                    j += 1usize
                }
                m -= 1usize
            } else {
                stopped = true
            }
        }
        lam[i] = rosner_lambda(n, i + 1usize, alpha)
        i += 1usize
    }
    var last = 0usize
    var any = false
    i = 0usize
    while i < k {
        if rr[i] == rr[i] && rr[i] > lam[i] {
            last = i
            any = true
        }
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < k {
        if any && i <= last { out[i] = true }
        if out[i] { cnt += 1usize }
        i += 1usize
    }
    r.mean = mean
    r.sd = sd
    r.value = val
    r.obs = obs
    r.r = rr
    r.lambda = lam
    r.outlier = out
    r.nout = cnt
    ret (r, ok)
}

// R's qnt: bisection on the non-central t distribution function
fn qnt(p0: f64, df: f64, ncp: f64) -> f64 {
    let eps = 1.0e-11f64
    let accu = 1.0e-13f64
    let de = 2.220446049250313e-16f64
    if p0 > 1.0f64 - de { ret 1.0f64 / 0.0f64 }
    var pp = p0 * (1.0f64 + eps)
    if pp > 1.0f64 - de { pp = 1.0f64 - de }
    var ux = ncp
    if ux < 1.0f64 { ux = 1.0f64 }
    while ux < 1.0e300f64 && nc.pnt(ux, df, ncp, true, false) < pp { ux *= 2.0f64 }
    pp = p0 * (1.0f64 - eps)
    var lx = 0.0f64 - ncp
    if lx > 0.0f64 - 1.0f64 { lx = 0.0f64 - 1.0f64 }
    while lx > 0.0f64 - 1.0e300f64 && nc.pnt(lx, df, ncp, true, false) > pp { lx *= 2.0f64 }
    var go = true
    while go {
        let nx = 0.5f64 * (lx + ux)
        if nc.pnt(nx, df, ncp, true, false) > p0 { ux = nx } else { lx = nx }
        var mx = math.abs[f64](lx)
        if math.abs[f64](ux) > mx { mx = math.abs[f64](ux) }
        go = ux - lx > mx * accu
    }
    ret 0.5f64 * (lx + ux)
}

// tolIntNormK: kind 0 content one-sided, 1 content two-sided Wald-Wolfowitz, 2 expectation one-sided, 3 expectation two-sided
fn tol_k(n: f64, coverage: f64, conf: f64, kind: i64) -> f64 {
    let df = n - 1.0f64
    if kind == 0i64 { ret qnt(conf, df, dist.qnorm(coverage, 0.0f64, 1.0f64, true, false) * math.sqrt[f64](n)) / math.sqrt[f64](n) }
    if kind == 2i64 { ret math.sqrt[f64](1.0f64 + 1.0f64 / n) * nb.qt(coverage, df, true, false) }
    if kind == 3i64 { ret math.sqrt[f64](1.0f64 + 1.0f64 / n) * nb.qt(1.0f64 - (1.0f64 - coverage) / 2.0f64, df, true, false) }
    // the half-width r with pnorm(x + r) - pnorm(x - r) = coverage, x = 1 / sqrt(n), found by bisection
    let x = 1.0f64 / math.sqrt[f64](n)
    var lo = 0.0f64
    var hi = 10.0f64
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        let cv = dist.pnorm(x + mid, 0.0f64, 1.0f64, true, false) - dist.pnorm(x - mid, 0.0f64, 1.0f64, true, false)
        if cv < coverage { lo = mid } else { hi = mid }
        it += 1usize
    }
    let u = math.sqrt[f64](df / nm.qchisq(1.0f64 - conf, df, true, false))
    ret 0.5f64 * (lo + hi) * u
}

// predIntNormK for one future mean of n_mean observations (k = 1, exact) or k future means by Bonferroni; two_sided picks the tails
fn pred_k(n: f64, n_mean: f64, k: f64, two_sided: bool, conf: f64) -> f64 {
    var a = 1.0f64 - conf
    if k > 1.0f64 { a = a / k }
    if two_sided { a = a / 2.0f64 }
    ret nb.qt(1.0f64 - a, n - 1.0f64, true, false) * math.sqrt[f64](1.0f64 / n_mean + 1.0f64 / n)
}
