// R's boot for the ordinary nonparametric bootstrap with an index statistic (stype "i"): the index
// array of `boot` (sample.int filled by column), the replicates of the mean, median, standard
// deviation and variance, and `boot.ci` of type norm, basic, perc and bca (the empirical influence
// values by regression on the resampling counts when R >= n, else by the jackknife).
//
// Not here: parametric, balanced and antithetic resampling, strata, tsboot, censboot, studentized
// intervals, abc.ci and jack.after.boot.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.rand.rdist as rdist
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

// tsboot(sim = "fixed" or "geom", l, endcorr): blocks of the series from the stream of boot's ts.array; sim 0 fixed blocks of length l, 1 geometric
// lengths with mean l (always with the end correction); n.sim = n. t[r] the statistic of the r-th resample.
fn tsboot(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize, l: usize, sim: u8, endcorr: bool) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let nsim = n
    var endpt = n
    if !endcorr && sim == 0u8 { endpt = n - l + 1usize }
    // block lengths: nrep rows by nn columns (column-major), or the single vector for the fixed rule
    var nn = 0usize
    var lens: []usize = zero
    if sim == 1u8 {
        let (lt, lte) = mem.alloc[usize](a, nrep * (nsim + 1usize))
        let (tot, tote) = mem.alloc[usize](a, nrep)
        if lte != ok { ret (none, lte) }
        if tote != ok { ret (none, tote) }
        var r = 0usize
        while r < nrep {
            tot[r] = 0usize
            r += 1usize
        }
        var more = true
        while more {
            r = 0usize
            while r < nrep {
                var tmp = 1usize + usize(rdist.rgeom(g, 1.0f64 / f64(l)))
                let room = nsim - tot[r]
                if tmp > room { tmp = room }
                lt[nn * nrep + r] = tmp
                tot[r] += tmp
                r += 1usize
            }
            nn += 1usize
            more = false
            r = 0usize
            while r < nrep {
                if tot[r] < nsim { more = true }
                r += 1usize
            }
        }
        lens = lt
    } else {
        nn = (nsim + l - 1usize) / l
        let (lt, lte) = mem.alloc[usize](a, nn)
        if lte != ok { ret (none, lte) }
        var c = 0usize
        while c + 1usize < nn {
            lt[c] = l
            c += 1usize
        }
        lt[nn - 1usize] = 1usize + (nsim - 1usize) % l
        lens = lt
    }
    let (st, se) = rng.sample_int(a, g, i64(endpt), i64(nn * nrep), true)
    if se != ok { ret (none, se) }
    let (t, te) = mem.alloc[f64](a, nrep)
    let (buf, be) = mem.alloc[f64](a, nsim)
    if te != ok || be != ok { ret (none, te) }
    var r = 0usize
    while r < nrep {
        var at = 0usize
        var c = 0usize
        while c < nn && at < nsim {
            var len = lens[c]
            if sim == 1u8 { len = lens[c * nrep + r] }
            let s = usize(st[c * nrep + r])
            var q = 0usize
            while q < len && at < nsim {
                buf[at] = x[(s - 1usize + q) % n]
                at += 1usize
                q += 1usize
            }
            c += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    var noidx: []i64 = zero
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: noidx, n: n, r: nrep }, ok)
}

// boot.ci(type = "stud") of the mean with the variance statistic var(d[i]) / n: from the bootstrap of the mean (kind 0) with its index array
fn stud_mean_ci(a: *mem.Arena, b: *const Boot, x: []const f64, conf: f64) -> (f64, f64, err) {
    let n = b.n
    let nf = f64(n)
    let (z, ze) = mem.alloc[f64](a, b.r)
    let (buf, be) = mem.alloc[f64](a, n)
    if ze != ok { ret (0.0f64, 0.0f64, ze) }
    if be != ok { ret (0.0f64, 0.0f64, be) }
    var r = 0usize
    while r < b.r {
        var j = 0usize
        while j < n {
            buf[j] = x[usize(b.idx[r * n + j]) - 1usize]
            j += 1usize
        }
        let v = var_of(buf) / nf
        z[r] = (b.t[r] - b.t0) / math.sqrt[f64](v)
        r += 1usize
    }
    let v0 = var_of(x) / nf
    let (qh, e1) = norm_inter(a, z, (1.0f64 + conf) / 2.0f64)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (ql, e2) = norm_inter(a, z, (1.0f64 - conf) / 2.0f64)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    ret (b.t0 - math.sqrt[f64](v0) * qh, b.t0 - math.sqrt[f64](v0) * ql, ok)
}

// a sum rounded once from a compensated accumulation, standing in for R's long double sum
fn lsum(v: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < v.len {
        let xv = v[i]
        let t = hi + xv
        var e = 0.0f64
        if math.abs[f64](hi) >= math.abs[f64](xv) { e = (hi - t) + xv } else { e = (xv - t) + hi }
        hi = t
        lo += e
        i += 1usize
    }
    ret hi + lo
}

// the weighted statistic of abc.ci: weighted mean (kind 0) or the weighted variance sum w (d - m)^2 (kind 1); R's sums are long double
fn wstat(a: *mem.Arena, kind: u8, x: []const f64, w: []const f64) -> f64 {
    let (buf, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        buf[i] = x[i] * w[i]
        i += 1usize
    }
    let sdw = lsum(buf)
    let sw = lsum(w)
    let m = sdw / sw
    if kind == 0u8 { ret m }
    i = 0usize
    while i < x.len {
        buf[i] = w[i] * ((x[i] - m) * (x[i] - m))
        i += 1usize
    }
    ret lsum(buf) / sw
}

// abc.ci(data, statistic, conf) for one stratum: the approximate bootstrap confidence limits, (lower, upper)
fn abc_ci(a: *mem.Arena, x: []const f64, kind: u8, conf: f64) -> (f64, f64, err) {
    let n = x.len
    let nf = f64(n)
    let eps = 0.001f64 / nf
    let (w0, e0) = mem.alloc[f64](a, n)
    let (w, e1) = mem.alloc[f64](a, n)
    let (ll, e2) = mem.alloc[f64](a, n)
    let (l2, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, e0) }
    var i = 0usize
    while i < n {
        w0[i] = 1.0f64 / nf
        i += 1usize
    }
    // the weights are rescaled to sum to one, as w / (w %*% mat), the original ones too (their sum is not exactly one)
    var s0 = 0.0f64
    i = 0usize
    while i < n {
        s0 += w0[i]
        i += 1usize
    }
    let (w0n, e0n) = mem.alloc[f64](a, n)
    if e0n != ok { ret (0.0f64, 0.0f64, e0n) }
    i = 0usize
    while i < n {
        w0n[i] = w0[i] / s0
        i += 1usize
    }
    let t0 = wstat(a, kind, x, w0n)
    i = 0usize
    while i < n {
        var j = 0usize
        var s1 = 0.0f64
        while j < n {
            w[j] = (1.0f64 - eps) * w0[j]
            if j == i { w[j] = w[j] + eps }
            s1 += w[j]
            j += 1usize
        }
        j = 0usize
        while j < n {
            w[j] = w[j] / s1
            j += 1usize
        }
        let t1 = wstat(a, kind, x, w)
        var s2 = 0.0f64
        j = 0usize
        while j < n {
            w[j] = (1.0f64 + eps) * w0[j]
            if j == i { w[j] = w[j] - eps }
            s2 += w[j]
            j += 1usize
        }
        j = 0usize
        while j < n {
            w[j] = w[j] / s2
            j += 1usize
        }
        let t2 = wstat(a, kind, x, w)
        ll[i] = (t1 - t2) / (2.0f64 * eps)
        l2[i] = (t1 - 2.0f64 * t0 + t2) / (eps * eps)
        i += 1usize
    }
    let (sq, sqe) = mem.alloc[f64](a, n)
    let (cb, cbe) = mem.alloc[f64](a, n)
    if sqe != ok || cbe != ok { ret (0.0f64, 0.0f64, sqe) }
    i = 0usize
    while i < n {
        sq[i] = ll[i] * ll[i]
        cb[i] = math.pow[f64](ll[i], 3.0f64)
        i += 1usize
    }
    let temp1 = lsum(sq)
    let cube = lsum(cb)
    let sl2 = lsum(l2)
    let sigmahat = math.sqrt[f64](temp1) / nf
    let ahat = cube / (6.0f64 * math.pow[f64](temp1, 1.5f64))
    let bhat = sl2 / (2.0f64 * nf * nf)
    let (w3, e4) = mem.alloc[f64](a, n)
    let (w4, e5) = mem.alloc[f64](a, n)
    if e4 != ok || e5 != ok { ret (0.0f64, 0.0f64, e4) }
    var s3 = 0.0f64
    var s4 = 0.0f64
    i = 0usize
    while i < n {
        let dh = ll[i] / (nf * nf * sigmahat)
        w3[i] = w0[i] + eps * dh
        w4[i] = w0[i] - eps * dh
        s3 += w3[i]
        s4 += w4[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        w3[i] = w3[i] / s3
        w4[i] = w4[i] / s4
        i += 1usize
    }
    let chat = (wstat(a, kind, x, w3) - 2.0f64 * t0 + wstat(a, kind, x, w4)) / (2.0f64 * eps * eps * sigmahat)
    let bprime = ahat - (bhat / sigmahat - chat)
    var out2: [2]f64 = zero
    var k = 0usize
    while k < 2usize {
        var alpha = (1.0f64 - conf) / 2.0f64
        if k == 1usize { alpha = (1.0f64 + conf) / 2.0f64 }
        let za = qn(alpha)
        let la = (bprime + za) / ((1.0f64 - ahat * (bprime + za)) * (1.0f64 - ahat * (bprime + za)))
        var sf = 0.0f64
        i = 0usize
        while i < n {
            let dh = ll[i] / (nf * nf * sigmahat)
            w[i] = w0[i] + la * dh
            sf += w[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            w[i] = w[i] / sf
            i += 1usize
        }
        out2[k] = wstat(a, kind, x, w)
        k += 1usize
    }
    ret (out2[0usize], out2[1usize], ok)
}

// boot(sim = "antithetic", L): the first R %/% 2 resamples are ordinary; the next R %/% 2 replace each observation by the one whose
// influence value L has the reverse rank; an odd R adds one more ordinary resample. L must have no ties here (R breaks ties at random).
fn boot_antithetic(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize, lv: []const f64) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let r1 = nrep / 2usize
    let (draw, de) = rng.sample_int(a, g, i64(n), i64(r1 * n), true)
    if de != ok { ret (none, de) }
    let (rank, ke) = mem.alloc[usize](a, n)
    let (rev, re) = mem.alloc[usize](a, n)
    if ke != ok || re != ok { ret (none, ke) }
    var i = 0usize
    while i < n {
        var below = 0usize
        var j = 0usize
        while j < n {
            if lv[j] < lv[i] { below += 1usize }
            j += 1usize
        }
        rank[i] = below + 1usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if rank[j] == n + 1usize - rank[i] { rev[i] = j + 1usize }
            j += 1usize
        }
        i += 1usize
    }
    var extra = 0usize
    if nrep != 2usize * r1 { extra = 1usize }
    let (idx, ie) = mem.alloc[i64](a, nrep * n)
    let (t, te) = mem.alloc[f64](a, nrep)
    let (buf, be) = mem.alloc[f64](a, n)
    if ie != ok || te != ok || be != ok { ret (none, ie) }
    var r = 0usize
    while r < r1 {
        var j = 0usize
        while j < n {
            // the first block, then the antithetic block with the observation replaced by its reverse
            let k = draw[j * r1 + r]
            idx[r * n + j] = k
            idx[(r1 + r) * n + j] = i64(rev[usize(k) - 1usize])
            j += 1usize
        }
        r += 1usize
    }
    if extra == 1usize {
        let (d2, e2) = rng.sample_int(a, g, i64(n), i64(n), true)
        if e2 != ok { ret (none, e2) }
        var j = 0usize
        while j < n {
            idx[2usize * r1 * n + j] = d2[j]
            j += 1usize
        }
    }
    r = 0usize
    while r < nrep {
        var j = 0usize
        while j < n {
            buf[j] = x[usize(idx[r * n + j]) - 1usize]
            j += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: idx, n: n, r: nrep }, ok)
}

// censboot(sim = "ordinary") with one stratum: the cases drawn as boot does, then taken in sorted order before the statistic is formed
fn censboot_ordinary(a: *mem.Arena, g: *rng.Rng, x: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = x.len
    let (draw, de) = rng.sample_int(a, g, i64(n), i64(n * nrep), true)
    if de != ok { ret (none, de) }
    let (idx, ie) = mem.alloc[i64](a, n * nrep)
    let (t, te) = mem.alloc[f64](a, nrep)
    let (buf, be) = mem.alloc[f64](a, n)
    let (key, ke) = mem.alloc[f64](a, n)
    if ie != ok || te != ok || be != ok || ke != ok { ret (none, ie) }
    var r = 0usize
    while r < nrep {
        var j = 0usize
        while j < n {
            key[j] = f64(draw[j * nrep + r])
            j += 1usize
        }
        sort_up(key)
        j = 0usize
        while j < n {
            idx[r * n + j] = i64(key[j])
            buf[j] = x[usize(key[j]) - 1usize]
            j += 1usize
        }
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    ret (Boot { t0: stat_of(a, kind, x), t: t, idx: idx, n: n, r: nrep }, ok)
}

// censboot(sim = "weird") with one stratum, F.surv = survfit(Surv(time, status) ~ 1): each replicate redraws the number of deaths at every distinct time as rbinom(n.risk, n.event / n.risk) (repeating until there is a death), adds the censored cases, and applies the statistic to the sorted times
fn censboot_weird(a: *mem.Arena, g: *rng.Rng, time: []const f64, status: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = time.len
    let (ut, e1) = mem.alloc[f64](a, n)
    let (risk, e2) = mem.alloc[f64](a, n)
    let (ev, e3) = mem.alloc[f64](a, n)
    let (nev, e4) = mem.alloc[f64](a, n)
    let (buf, e5) = mem.alloc[f64](a, 2usize * n)
    let (t, e6) = mem.alloc[f64](a, nrep)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (none, e1) }
    var i = 0usize
    while i < n {
        buf[i] = time[i]
        i += 1usize
    }
    sort_up(buf[0usize..n])
    var m = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || buf[i] != buf[i - 1usize] {
            ut[m] = buf[i]
            m += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < m {
        var rk = 0.0f64
        var d = 0.0f64
        i = 0usize
        while i < n {
            if time[i] >= ut[j] { rk += 1.0f64 }
            if time[i] == ut[j] && status[i] > 0.5f64 { d += 1.0f64 }
            i += 1usize
        }
        risk[j] = rk
        ev[j] = d
        j += 1usize
    }
    var r = 0usize
    while r < nrep {
        var total = 0.0f64
        while total == 0.0f64 {
            j = 0usize
            while j < m {
                nev[j] = rdist.rbinom(g, risk[j], ev[j] / risk[j])
                total += nev[j]
                j += 1usize
            }
            if total != 0.0f64 { break }
        }
        var cnt = 0usize
        j = 0usize
        while j < m {
            var q = 0usize
            while q < usize(nev[j]) {
                buf[cnt] = ut[j]
                cnt += 1usize
                q += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < n {
            if status[i] < 0.5f64 {
                buf[cnt] = time[i]
                cnt += 1usize
            }
            i += 1usize
        }
        sort_up(buf[0usize..cnt])
        t[r] = stat_of(a, kind, buf[0usize..cnt])
        r += 1usize
    }
    let (idx, ie) = mem.alloc[i64](a, 1usize)
    if ie != ok { ret (none, ie) }
    ret (Boot { t0: stat_of(a, kind, time), t: t, idx: idx, n: n, r: nrep }, ok)
}

// the Kaplan-Meier curve of (time, event): distinct times into ut, S(t) into sv; a final point (Inf, 0) is appended when S stays above 0; returns the number of points
fn km_curve(time: []const f64, event: []const f64, ut: []f64, sv: []f64) -> usize {
    let n = time.len
    var m = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < m {
            if ut[j] == time[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ut[m] = time[i]
            m += 1usize
        }
        i += 1usize
    }
    sort_up(ut[0usize..m])
    var s = 1.0f64
    var k = 0usize
    while k < m {
        var rk = 0.0f64
        var d = 0.0f64
        i = 0usize
        while i < n {
            if time[i] >= ut[k] { rk += 1.0f64 }
            if time[i] == ut[k] && event[i] > 0.5f64 { d += 1.0f64 }
            i += 1usize
        }
        s = s * ((rk - d) / rk)
        sv[k] = s
        k += 1usize
    }
    if sv[m - 1usize] > 0.0f64 {
        ut[m] = 1.0f64 / 0.0f64
        sv[m] = 0.0f64
        m += 1usize
    }
    ret m
}

// censboot(sim = "cond", cox = NULL) with one stratum: failure times from the KM of (time, status), censoring times from the KM of the censoring distribution given the case's own time, as cens.resamp draws them
fn censboot_cond(a: *mem.Arena, g: *rng.Rng, time: []const f64, status: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = time.len
    let (cev, e0) = mem.alloc[f64](a, n)
    let (fu, e1) = mem.alloc[f64](a, n + 1usize)
    let (fs, e2) = mem.alloc[f64](a, n + 1usize)
    let (gu, e3) = mem.alloc[f64](a, n + 1usize)
    let (gs, e4) = mem.alloc[f64](a, n + 1usize)
    let (pf, e5) = mem.alloc[f64](a, n + 1usize)
    let (pg, e6) = mem.alloc[f64](a, n + 1usize)
    let (y0, e7) = mem.alloc[f64](a, n * nrep)
    let (c0, e8) = mem.alloc[f64](a, n * nrep)
    let (buf, e9) = mem.alloc[f64](a, n)
    let (t, e10) = mem.alloc[f64](a, nrep)
    let (pri, e11) = mem.alloc[f64](a, n + 1usize)
    let (ti, e12) = mem.alloc[f64](a, n + 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (none, e0) }
    var i = 0usize
    while i < n {
        if status[i] > 0.5f64 { cev[i] = 0.0f64 } else { cev[i] = 1.0f64 }
        i += 1usize
    }
    let mf = km_curve(time, status, fu, fs)
    let mg = km_curve(time, cev, gu, gs)
    i = 0usize
    while i < mf {
        var prev = 1.0f64
        if i > 0usize { prev = fs[i - 1usize] }
        pf[i] = prev - fs[i]
        i += 1usize
    }
    i = 0usize
    while i < mg {
        var prev = 1.0f64
        if i > 0usize { prev = gs[i - 1usize] }
        pg[i] = prev - gs[i]
        i += 1usize
    }
    // y0: matrix(bsample(time, n * R, prob), R, n), column-major
    let (dy, dye) = rdist.sample_prob(a, g, mf, n * nrep, true, pf[0usize..mf])
    if dye != ok { ret (none, dye) }
    i = 0usize
    while i < n * nrep {
        y0[i] = fu[usize(dy[i]) - 1usize]
        i += 1usize
    }
    // c0: per case, nrep draws among the censoring times beyond its own time
    i = 0usize
    while i < n {
        if status[i] < 0.5f64 {
            var r = 0usize
            while r < nrep {
                c0[r + nrep * i] = time[i]
                r += 1usize
            }
        } else {
            var cnt = 0usize
            var q = 0usize
            while q < mg {
                if gu[q] > time[i] {
                    ti[cnt] = gu[q]
                    pri[cnt] = pg[q]
                    cnt += 1usize
                }
                q += 1usize
            }
            if cnt == 1usize {
                var r = 0usize
                while r < nrep {
                    c0[r + nrep * i] = ti[0usize]
                    r += 1usize
                }
            } else {
                let (dc, dce) = rdist.sample_prob(a, g, cnt, nrep, true, pri[0usize..cnt])
                if dce != ok { ret (none, dce) }
                var r = 0usize
                while r < nrep {
                    c0[r + nrep * i] = ti[usize(dc[r]) - 1usize]
                    r += 1usize
                }
            }
        }
        i += 1usize
    }
    // both infinite: the largest failure time
    var maxf = 0.0f64
    i = 0usize
    while i < n {
        if status[i] > 0.5f64 && time[i] > maxf { maxf = time[i] }
        i += 1usize
    }
    var r = 0usize
    while r < nrep {
        i = 0usize
        while i < n {
            var yy = y0[r + nrep * i]
            let cc = c0[r + nrep * i]
            let inf = 1.0f64 / 0.0f64
            if yy == inf && cc == inf { yy = maxf }
            if yy < cc { buf[i] = yy } else { buf[i] = cc }
            i += 1usize
        }
        sort_up(buf)
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    let (idx, ie) = mem.alloc[i64](a, 1usize)
    if ie != ok { ret (none, ie) }
    ret (Boot { t0: stat_of(a, kind, time), t: t, idx: idx, n: n, r: nrep }, ok)
}

// censboot(sim = "model") with one stratum and a Cox fit: failure times from the conditional distribution 1 - F0(t)^exp(eta_i) of each case (F0 the baseline survival ft, fs), censoring times from the censoring survival gt, gs; the draws follow cens.resamp (gety2 per column, then getc1 in one call)
fn censboot_model(a: *mem.Arena, g: *rng.Rng, time: []const f64, status: []const f64, eta: []const f64, ft: []const f64, fs: []const f64, gt: []const f64, gs: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = time.len
    let inf = 1.0f64 / 0.0f64
    var mf = ft.len
    var mg = gt.len
    let (xt, e1) = mem.alloc[f64](a, mf + 1usize)
    let (xs, e2) = mem.alloc[f64](a, mf + 1usize)
    let (ct, e3) = mem.alloc[f64](a, mg + 1usize)
    let (cs, e4) = mem.alloc[f64](a, mg + 1usize)
    let (pf, e5) = mem.alloc[f64](a, mf + 2usize)
    let (pg, e6) = mem.alloc[f64](a, mg + 1usize)
    let (y0, e7) = mem.alloc[f64](a, n * nrep)
    let (c0, e8) = mem.alloc[f64](a, n * nrep)
    let (buf, e9) = mem.alloc[f64](a, n)
    let (t, e10) = mem.alloc[f64](a, nrep)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (none, e1) }
    var i = 0usize
    while i < mf {
        xt[i] = ft[i]
        xs[i] = fs[i]
        i += 1usize
    }
    if xs[mf - 1usize] > 0.0f64 {
        xt[mf] = inf
        xs[mf] = 0.0f64
        mf += 1usize
    }
    i = 0usize
    while i < mg {
        ct[i] = gt[i]
        cs[i] = gs[i]
        i += 1usize
    }
    if cs[mg - 1usize] > 0.0f64 {
        ct[mg] = inf
        cs[mg] = 0.0f64
        mg += 1usize
    }
    // y0 column by column: probabilities diff(c(0, 1 - F0^exp(eta)))
    i = 0usize
    while i < n {
        let ex = math.exp[f64](eta[i])
        var prev = 0.0f64
        var j = 0usize
        while j < mf {
            let cur = 1.0f64 - math.pow[f64](xs[j], ex)
            pf[j] = cur - prev
            prev = cur
            j += 1usize
        }
        let (d, de) = rdist.sample_prob(a, g, mf, nrep, true, pf[0usize..mf])
        if de != ok { ret (none, de) }
        var r = 0usize
        while r < nrep {
            y0[r + nrep * i] = xt[usize(d[r]) - 1usize]
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < mg {
        var prev = 1.0f64
        if i > 0usize { prev = cs[i - 1usize] }
        pg[i] = prev - cs[i]
        i += 1usize
    }
    let (dc, dce) = rdist.sample_prob(a, g, mg, n * nrep, true, pg[0usize..mg])
    if dce != ok { ret (none, dce) }
    i = 0usize
    while i < n * nrep {
        c0[i] = ct[usize(dc[i]) - 1usize]
        i += 1usize
    }
    var maxf = 0.0f64
    i = 0usize
    while i < n {
        if status[i] > 0.5f64 && time[i] > maxf { maxf = time[i] }
        i += 1usize
    }
    var r = 0usize
    while r < nrep {
        i = 0usize
        while i < n {
            var yy = y0[r + nrep * i]
            let cc = c0[r + nrep * i]
            if yy == inf && cc == inf { yy = maxf }
            if yy < cc { buf[i] = yy } else { buf[i] = cc }
            i += 1usize
        }
        sort_up(buf)
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    let (idx, ie) = mem.alloc[i64](a, 1usize)
    if ie != ok { ret (none, ie) }
    ret (Boot { t0: stat_of(a, kind, time), t: t, idx: idx, n: n, r: nrep }, ok)
}
// censboot(sim = "cond") with a Cox fit: failure times as in model (gety2), each censoring time drawn beyond the case's own time (getc2), the two matrices filled in R's order
fn censboot_condcox(a: *mem.Arena, g: *rng.Rng, time: []const f64, status: []const f64, eta: []const f64, ft: []const f64, fs: []const f64, gt: []const f64, gs: []const f64, kind: u8, nrep: usize) -> (Boot, err) {
    var none: Boot = zero
    let n = time.len
    let inf = 1.0f64 / 0.0f64
    var mf = ft.len
    var mg = gt.len
    let (xt, e1) = mem.alloc[f64](a, mf + 1usize)
    let (xs, e2) = mem.alloc[f64](a, mf + 1usize)
    let (ct, e3) = mem.alloc[f64](a, mg + 1usize)
    let (cs, e4) = mem.alloc[f64](a, mg + 1usize)
    let (pf, e5) = mem.alloc[f64](a, mf + 2usize)
    let (pg, e6) = mem.alloc[f64](a, mg + 1usize)
    let (y0, e7) = mem.alloc[f64](a, n * nrep)
    let (c0, e8) = mem.alloc[f64](a, n * nrep)
    let (buf, e9) = mem.alloc[f64](a, n)
    let (t, e10) = mem.alloc[f64](a, nrep)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (none, e1) }
    var i = 0usize
    while i < mf {
        xt[i] = ft[i]
        xs[i] = fs[i]
        i += 1usize
    }
    if xs[mf - 1usize] > 0.0f64 {
        xt[mf] = inf
        xs[mf] = 0.0f64
        mf += 1usize
    }
    i = 0usize
    while i < mg {
        ct[i] = gt[i]
        cs[i] = gs[i]
        i += 1usize
    }
    if cs[mg - 1usize] > 0.0f64 {
        ct[mg] = inf
        cs[mg] = 0.0f64
        mg += 1usize
    }
    // y0 column by column: probabilities diff(c(0, 1 - F0^exp(eta)))
    i = 0usize
    while i < n {
        let ex = math.exp[f64](eta[i])
        var prev = 0.0f64
        var j = 0usize
        while j < mf {
            let cur = 1.0f64 - math.pow[f64](xs[j], ex)
            pf[j] = cur - prev
            prev = cur
            j += 1usize
        }
        let (d, de) = rdist.sample_prob(a, g, mf, nrep, true, pf[0usize..mf])
        if de != ok { ret (none, de) }
        var r = 0usize
        while r < nrep {
            y0[r + nrep * i] = xt[usize(d[r]) - 1usize]
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < mg {
        var prev = 1.0f64
        if i > 0usize { prev = cs[i - 1usize] }
        pg[i] = prev - cs[i]
        i += 1usize
    }
    let (ti, e11) = mem.alloc[f64](a, mg + 1usize)
    let (pri, e12) = mem.alloc[f64](a, mg + 1usize)
    if e11 != ok || e12 != ok { ret (none, e11) }
    i = 0usize
    while i < n {
        if status[i] < 0.5f64 {
            var r = 0usize
            while r < nrep {
                c0[r + nrep * i] = time[i]
                r += 1usize
            }
        } else {
            var cnt = 0usize
            var q = 0usize
            while q < mg {
                if ct[q] > time[i] {
                    ti[cnt] = ct[q]
                    pri[cnt] = pg[q]
                    cnt += 1usize
                }
                q += 1usize
            }
            if cnt == 1usize {
                var r = 0usize
                while r < nrep {
                    c0[r + nrep * i] = ti[0usize]
                    r += 1usize
                }
            } else {
                let (dc, dce) = rdist.sample_prob(a, g, cnt, nrep, true, pri[0usize..cnt])
                if dce != ok { ret (none, dce) }
                var r = 0usize
                while r < nrep {
                    c0[r + nrep * i] = ti[usize(dc[r]) - 1usize]
                    r += 1usize
                }
            }
        }
        i += 1usize
    }
    var maxf = 0.0f64
    i = 0usize
    while i < n {
        if status[i] > 0.5f64 && time[i] > maxf { maxf = time[i] }
        i += 1usize
    }
    var r = 0usize
    while r < nrep {
        i = 0usize
        while i < n {
            var yy = y0[r + nrep * i]
            let cc = c0[r + nrep * i]
            if yy == inf && cc == inf { yy = maxf }
            if yy < cc { buf[i] = yy } else { buf[i] = cc }
            i += 1usize
        }
        sort_up(buf)
        t[r] = stat_of(a, kind, buf)
        r += 1usize
    }
    let (idx, ie) = mem.alloc[i64](a, 1usize)
    if ie != ok { ret (none, ie) }
    ret (Boot { t0: stat_of(a, kind, time), t: t, idx: idx, n: n, r: nrep }, ok)
}

// empinf(type = "inf", stype = "w") for one stratum: out[i] = (stat(data, w_i) - stat(data, 1/n)) / (eps / n) with weight eps / n moved onto case i; kind as in wstat
fn empinf_inf(a: *mem.Arena, x: []const f64, kind: u8, eps0: f64, out: []f64) -> err {
    let n = x.len
    let (w, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let eps = eps0 / f64(n)
    var i = 0usize
    while i < n {
        w[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    let tobs = wstat(a, kind, x, w)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            w[j] = (1.0f64 - eps) * (1.0f64 / f64(n))
            j += 1usize
        }
        w[i] = w[i] + eps
        out[i] = (wstat(a, kind, x, w) - tobs) / eps
        i += 1usize
    }
    ret ok
}

// empinf(type = "jack") for one stratum: stype "w" (wsel true, weighted statistic of kind 0 or 1 with case i given weight 0) or stype "i" (stat_of kind on the data without case i); out[i] = (n - 1) (tobs - stat_without_i)
fn empinf_jack(a: *mem.Arena, x: []const f64, kind: u8, wsel: bool, out: []f64) -> err {
    let n = x.len
    let (w, e1) = mem.alloc[f64](a, n)
    let (buf, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    var tobs = 0.0f64
    if wsel {
        while i < n {
            w[i] = 1.0f64 / f64(n)
            i += 1usize
        }
        tobs = wstat(a, kind, x, w)
    } else {
        tobs = stat_of(a, kind, x)
    }
    i = 0usize
    while i < n {
        var other = 0.0f64
        if wsel {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                w[j] = 1.0f64 / f64(n)
                if j == i { w[j] = 0.0f64 }
                s += w[j]
                j += 1usize
            }
            j = 0usize
            while j < n {
                w[j] = w[j] / s
                j += 1usize
            }
            other = wstat(a, kind, x, w)
        } else {
            var m = 0usize
            var j = 0usize
            while j < n {
                if j != i {
                    buf[m] = x[j]
                    m += 1usize
                }
                j += 1usize
            }
            other = stat_of(a, kind, buf[0usize..m])
        }
        out[i] = f64(n - 1usize) * (tobs - other)
        i += 1usize
    }
    ret ok
}

// empinf(type = "reg") for one stratum: the least-squares slopes of the bootstrap statistics on the resampling frequencies divided by n (case 1 left out), centred to mean zero
fn empinf_reg(a: *mem.Arena, b: *const Boot, out: []f64) -> err {
    let n = b.n
    let nr = b.r
    let p = n
    let (xm, e1) = mem.alloc[f64](a, nr * p)
    let (ata, e2) = mem.alloc[f64](a, p * (p + 1usize))
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var r = 0usize
    while r < nr {
        xm[r * p] = 1.0f64
        var j = 1usize
        while j < p {
            xm[r * p + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < n {
            let c = usize(b.idx[r * n + j]) - 1usize
            if c > 0usize { xm[r * p + c] += 1.0f64 / f64(n) }
            j += 1usize
        }
        r += 1usize
    }
    let wd = p + 1usize
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            r = 0usize
            while r < nr {
                s += xm[r * p + i] * xm[r * p + j]
                r += 1usize
            }
            ata[i * wd + j] = s
            j += 1usize
        }
        var s2 = 0.0f64
        r = 0usize
        while r < nr {
            s2 += xm[r * p + i] * b.t[r]
            r += 1usize
        }
        ata[i * wd + p] = s2
        i += 1usize
    }
    var col = 0usize
    while col < p {
        var piv = col
        var rr = col + 1usize
        while rr < p {
            if math.abs[f64](ata[rr * wd + col]) > math.abs[f64](ata[piv * wd + col]) { piv = rr }
            rr += 1usize
        }
        var cc = 0usize
        while cc < wd {
            let t = ata[col * wd + cc]
            ata[col * wd + cc] = ata[piv * wd + cc]
            ata[piv * wd + cc] = t
            cc += 1usize
        }
        rr = 0usize
        while rr < p {
            if rr != col {
                let fct = ata[rr * wd + col] / ata[col * wd + col]
                cc = col
                while cc < wd {
                    ata[rr * wd + cc] -= fct * ata[col * wd + cc]
                    cc += 1usize
                }
            }
            rr += 1usize
        }
        col += 1usize
    }
    out[0usize] = 0.0f64
    var m = 0.0f64
    i = 1usize
    while i < p {
        out[i] = ata[i * wd + p] / ata[i * wd + i]
        m += out[i]
        i += 1usize
    }
    m = m / f64(n)
    i = 0usize
    while i < n {
        out[i] = out[i] - m
        i += 1usize
    }
    ret ok
}

// empinf(type = "pos") for one stratum: positive jackknife, case i given double weight (stype "w") or appended once more (stype "i"); out[i] = (n + 1) (stat - tobs)
fn empinf_pos(a: *mem.Arena, x: []const f64, kind: u8, wsel: bool, out: []f64) -> err {
    let n = x.len
    let (w, e1) = mem.alloc[f64](a, n)
    let (buf, e2) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    var tobs = 0.0f64
    if wsel {
        while i < n {
            w[i] = 1.0f64 / f64(n)
            i += 1usize
        }
        tobs = wstat(a, kind, x, w)
    } else {
        tobs = stat_of(a, kind, x)
    }
    i = 0usize
    while i < n {
        var other = 0.0f64
        if wsel {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                w[j] = 1.0f64 / f64(n)
                if j == i { w[j] = 2.0f64 * w[j] }
                s += w[j]
                j += 1usize
            }
            j = 0usize
            while j < n {
                w[j] = w[j] / s
                j += 1usize
            }
            other = wstat(a, kind, x, w)
        } else {
            var j = 0usize
            while j < n {
                buf[j] = x[j]
                j += 1usize
            }
            buf[n] = x[i]
            other = stat_of(a, kind, buf[0usize..n + 1usize])
        }
        out[i] = f64(n + 1usize) * (other - tobs)
        i += 1usize
    }
    ret ok
}
