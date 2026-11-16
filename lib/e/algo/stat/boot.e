// R's boot for the ordinary nonparametric bootstrap with an index statistic (stype "i"): the index
// array of `boot` (sample.int filled by column), the replicates of the mean, median, standard
// deviation and variance, and `boot.ci` of type norm, basic, perc and bca (the empirical influence
// values by regression on the resampling counts when R >= n, else by the jackknife).
//
// Not here: parametric, balanced and antithetic resampling, strata, tsboot, censboot, studentized
// intervals, abc.ci and jack.after.boot.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.sort
use e.math
use e.math.dist as dist
use e.mem

error NotFinite
error NotFiniteA
error RegFail

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sort_up(d: []f64) {
    var ctx = 0u8
    sort.in_place_by[f64, u8](d, &ctx, cmp_up)
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    var m = s / f64(x.len)
    var t = 0.0f64
    i = 0usize
    while i < x.len {
        t += x[i] - m
        i += 1usize
    }
    ret m + t / f64(x.len)
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

// statistic of a sample: 0 mean, 1 median, 2 sd, 3 var
fn stat_of(a: *mem.Arena, kind: u8, x: []const f64) -> f64 {
    if kind == 0u8 { ret mean_of(x) }
    if kind == 2u8 { ret math.sqrt[f64](var_of(x)) }
    if kind == 3u8 { ret var_of(x) }
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    sort_up(s)
    let n = x.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

type Boot = struct { t0: f64, t: []f64, idx: []i64, n: usize, r: usize }

// boot(data, statistic, R): the replicates and the 1-based index array (R x n, row-major)
fn boot(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let (draw, de) = rng.sample_int(a, g, i64(n), i64(n * nrep), true)
    if de != ok { ret (none, de) }
    let (idx, ie) = mem.alloc[i64](a, n * nrep)
    if ie != ok { ret (none, ie) }
    let (t, te) = mem.alloc[f64](a, nrep)
    if te != ok { ret (none, te) }
    let (buf, be) = mem.alloc[f64](a, n)
    if be != ok { ret (none, be) }
    var r = 0usize
    while r < nrep {
        var j = 0usize
        while j < n {
            idx[r * n + j] = draw[j * nrep + r]
            buf[j] = x[usize(draw[j * nrep + r]) - 1usize]
            j += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: idx, n: n, r: nrep }, ok)
}

// boot's norm.inter: interpolation on the normal quantile scale between order statistics
fn norm_inter(a: *mem.Arena, t: []const f64, alpha: f64) -> (f64, err) {
    var cnt = 0usize
    var i = 0usize
    while i < t.len {
        if t[i] == t[i] && t[i] - t[i] == 0.0f64 { cnt += 1usize }
        i += 1usize
    }
    let (s, e) = mem.alloc[f64](a, cnt)
    if e != ok { ret (0.0f64, e) }
    var k = 0usize
    i = 0usize
    while i < t.len {
        if t[i] == t[i] && t[i] - t[i] == 0.0f64 {
            s[k] = t[i]
            k += 1usize
        }
        i += 1usize
    }
    sort_up(s)
    let rr = f64(cnt)
    let rk = (rr + 1.0f64) * alpha
    let kk = math.floor[f64](rk)
    if kk == rk && kk >= 1.0f64 && kk <= rr { ret (s[usize(kk) - 1usize], ok) }
    if kk == 0.0f64 { ret (s[0usize], ok) }
    if kk == rr { ret (s[cnt - 1usize], ok) }
    let t1 = dist.qnorm(alpha, 0.0f64, 1.0f64, true, false)
    let t2 = dist.qnorm(kk / (rr + 1.0f64), 0.0f64, 1.0f64, true, false)
    let t3 = dist.qnorm((kk + 1.0f64) / (rr + 1.0f64), 0.0f64, 1.0f64, true, false)
    let tk = s[usize(kk) - 1usize]
    let tk1 = s[usize(kk)]
    ret (tk + (t1 - t2) / (t3 - t2) * (tk1 - tk), ok)
}

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// the bounds of a confidence interval of kind 0 norm, 1 basic, 2 perc, 3 bca
fn boot_ci(a: *mem.Arena, b: *const Boot, x: []const f64, kind: u8, qkind: u8, conf: f64) -> (f64, f64, err) {
    let t = b.t
    if kind == 0u8 {
        var m = 0.0f64
        var cnt = 0usize
        var i = 0usize
        while i < t.len {
            m += t[i]
            cnt += 1usize
            i += 1usize
        }
        m = mean_of(t)
        let v = var_of(t)
        let bias = m - b.t0
        let merr = math.sqrt[f64](v) * qn((1.0f64 + conf) / 2.0f64)
        ret (b.t0 - bias - merr, b.t0 - bias + merr, ok)
    }
    let a1 = (1.0f64 - conf) / 2.0f64
    let a2 = (1.0f64 + conf) / 2.0f64
    if kind == 1u8 {
        let (hi, e1) = norm_inter(a, t, a2)
        if e1 != ok { ret (0.0f64, 0.0f64, e1) }
        let (lo, e2) = norm_inter(a, t, a1)
        if e2 != ok { ret (0.0f64, 0.0f64, e2) }
        ret (2.0f64 * b.t0 - hi, 2.0f64 * b.t0 - lo, ok)
    }
    if kind == 2u8 {
        let (lo, e1) = norm_inter(a, t, a1)
        if e1 != ok { ret (0.0f64, 0.0f64, e1) }
        let (hi, e2) = norm_inter(a, t, a2)
        if e2 != ok { ret (0.0f64, 0.0f64, e2) }
        ret (lo, hi, ok)
    }
    // bca
    var below = 0usize
    var i = 0usize
    while i < t.len {
        if t[i] < b.t0 { below += 1usize }
        i += 1usize
    }
    let w = qn(f64(below) / f64(t.len))
    if !(w - w == 0.0f64) { ret (0.0f64, 0.0f64, NotFinite) }
    let n = b.n
    let (l, le) = mem.alloc[f64](a, n)
    if le != ok { ret (0.0f64, 0.0f64, le) }
    if b.r < n {
        // jackknife: (n - 1) * (t0 - statistic without observation i)
        let (sub, se) = mem.alloc[f64](a, n - 1usize)
        if se != ok { ret (0.0f64, 0.0f64, se) }
        i = 0usize
        while i < n {
            var k = 0usize
            var j = 0usize
            while j < n {
                if j != i {
                    sub[k] = x[j]
                    k += 1usize
                }
                j += 1usize
            }
            l[i] = f64(n - 1usize) * (b.t0 - stat_of(a, qkind, sub))
            i += 1usize
        }
    } else {
        // regression of t on the resampling counts of observations 2..n (with an intercept)
        let p = n
        let (xm, xe) = mem.alloc[f64](a, b.r * p)
        if xe != ok { ret (0.0f64, 0.0f64, xe) }
        var r = 0usize
        while r < b.r * p {
            xm[r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < b.r {
            xm[r] = 1.0f64
            r += 1usize
        }
        r = 0usize
        while r < b.r {
            var j = 0usize
            while j < n {
                let ix = usize(b.idx[r * n + j]) - 1usize
                if ix >= 1usize { xm[ix * b.r + r] += 1.0f64 / f64(n) }
                j += 1usize
            }
            r += 1usize
        }
        let (fit, fe) = decomp.lm_fit(a, xm, b.r, p, t, 1.0e-7f64)
        if fe != ok { ret (0.0f64, 0.0f64, fe) }
        l[0usize] = 0.0f64
        var j = 1usize
        while j < n {
            l[j] = fit.coef[j]
            j += 1usize
        }
        var ml = 0.0f64
        j = 0usize
        while j < n {
            ml += l[j]
            j += 1usize
        }
        ml = ml / f64(n)
        j = 0usize
        while j < n {
            l[j] -= ml
            j += 1usize
        }
    }
    var s2 = 0.0f64
    var s3 = 0.0f64
    i = 0usize
    while i < n {
        s2 += l[i] * l[i]
        s3 += l[i] * l[i] * l[i]
        i += 1usize
    }
    let acc = s3 / (6.0f64 * math.pow[f64](s2, 1.5f64))
    if !(acc - acc == 0.0f64) { ret (0.0f64, 0.0f64, NotFiniteA) }
    let z1 = qn(a1)
    let z2 = qn(a2)
    let aa1 = dist.pnorm(w + (w + z1) / (1.0f64 - acc * (w + z1)), 0.0f64, 1.0f64, true, false)
    let aa2 = dist.pnorm(w + (w + z2) / (1.0f64 - acc * (w + z2)), 0.0f64, 1.0f64, true, false)
    let (lo, e1) = norm_inter(a, t, aa1)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (hi, e2) = norm_inter(a, t, aa2)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    ret (lo, hi, ok)
}

// boot(sim = "balanced"): every observation appears exactly R times overall; the index array is the permutation
// sample(rep(1:n, R)) cut into R rows of n
fn boot_balanced(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let (perm, pe) = rng.sample_int(a, g, i64(n * nrep), i64(n * nrep), false)
    if pe != ok { ret (none, pe) }
    let (idx, ie) = mem.alloc[i64](a, n * nrep)
    let (t, te) = mem.alloc[f64](a, nrep)
    let (buf, be) = mem.alloc[f64](a, n)
    if ie != ok || te != ok || be != ok { ret (none, ie) }
    var r = 0usize
    while r < nrep {
        var j = 0usize
        while j < n {
            let k = (perm[r * n + j] - 1i64) % i64(n) + 1i64
            idx[r * n + j] = k
            buf[j] = x[usize(k) - 1usize]
            j += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: idx, n: n, r: nrep }, ok)
}

// boot(sim = "parametric", ran.gen = function(d, p) rnorm(n, p[1], p[2]), mle = c(mu, sd)); there is no index array
fn boot_parametric_norm(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize, mu: f64, sd: f64) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let (t, te) = mem.alloc[f64](a, nrep)
    let (buf, be) = mem.alloc[f64](a, n)
    let (ix, xe) = mem.alloc[i64](a, 1usize)
    if te != ok || be != ok || xe != ok { ret (none, te) }
    var r = 0usize
    while r < nrep {
        var j = 0usize
        while j < n {
            buf[j] = rng.rnorm(g, mu, sd)
            j += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: ix[0usize..0usize], n: n, r: nrep }, ok)
}
