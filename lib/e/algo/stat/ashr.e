// R ashr `ash` for the normal likelihood (df = NULL, alpha = 0) with a given mode: the grid of mixture components
// (autoselect.mixsd), the mixture proportions by mixsqp over the likelihood matrix augmented with the prior's pseudo
// observations (the package's mixSQP optimiser: eps 1e-6, 20 EM steps), then the posterior summaries of every
// observation: NegativeProb, PositiveProb, lfsr, svalue, lfdr, qvalue, PosteriorMean, PosteriorSD, and the
// log-likelihood and log likelihood ratio.
//
// kind: 0 uniform, 1 halfuniform, 2 normal, 3 +uniform, 4 -uniform. method "fdr" is pointmass with a nullbiased
// prior (nullweight on the point mass); method "shrink" is no point mass and a flat prior.
//
// Not here: other likelihoods (t, Poisson, binomial), halfnormal mixtures, mode estimation, a user-supplied grid or
// g, a grange, observations with a zero or missing standard error, the other optimisers.

use e.algo.stat.mixsqp_sqp as sq
use e.math
use e.math.dist as dist
use e.mem

type Ash = struct {
    n: usize, k: usize, loglik: f64, loglr: f64,
    pi: []f64, lo: []f64, hi: []f64, sd: []f64,
    np: []f64, pp: []f64, lfsr: []f64, svalue: []f64, lfdr: []f64, qvalue: []f64, pm: []f64, psd: []f64
}

fn lpn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, true) }

fn ldn(x: f64) -> f64 { ret dist.dnorm(x, 0.0f64, 1.0f64, true) }

fn isinf(x: f64) -> bool { ret x - x != 0.0f64 && x == x }

// ashr's logscale_sub: log(exp(lx) - exp(ly)), with lx lifted to ly when it is smaller
fn lsub(lx0: f64, ly: f64) -> f64 {
    var lx = lx0
    if lx - ly < 0.0f64 { lx = ly }
    var sc = lx
    if isinf(sc) { sc = 0.0f64 }
    ret math.log[f64](math.exp[f64](lx - sc) - math.exp[f64](ly - sc)) + sc
}

fn max2(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn min2(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

// my_etruncnorm(a, b) of the standard normal
fn etrunc(a: f64, b: f64) -> f64 {
    var alpha = a
    var beta = b
    let flip = (alpha > 0.0f64 && beta > 0.0f64) || beta > math.abs[f64](alpha)
    if flip {
        alpha = 0.0f64 - b
        beta = 0.0f64 - a
    }
    let dd = lsub(ldn(beta), ldn(alpha))
    let pd = lsub(lpn(beta), lpn(alpha))
    var sr = 0.0f64 - math.exp[f64](dd - pd)
    if isinf(pd) { sr = (alpha + beta) / 2.0f64 }
    let lower = max2(beta + 1.0f64 / beta, (alpha + beta) / 2.0f64)
    if beta < 0.0f64 && (sr < lower || sr > beta) { sr = lower }
    if flip { sr = 0.0f64 - sr }
    ret sr
}

// my_e2truncnorm(a, b) of the standard normal
fn e2trunc(a: f64, b: f64) -> f64 {
    var alpha = a
    var beta = b
    if alpha > 0.0f64 && beta > 0.0f64 {
        alpha = 0.0f64 - b
        beta = 0.0f64 - a
    }
    let pd = lsub(lpn(beta), lpn(alpha))
    let af = alpha * math.exp[f64](ldn(alpha) - pd)
    let bf = beta * math.exp[f64](ldn(beta) - pd)
    var sr = 1.0f64
    if !isinf(alpha) { sr = 1.0f64 + af }
    if !isinf(beta) { sr = sr - bf }
    if isinf(pd) { sr = (alpha + beta) * (alpha + beta) / 4.0f64 }
    let ub = min2(beta * beta + 2.0f64 * (1.0f64 + 1.0f64 / (beta * beta)), (alpha * alpha + alpha * beta + beta * beta) / 3.0f64)
    if beta < 0.0f64 && (sr < beta * beta || sr > ub) { sr = ub }
    ret sr
}

// log of the component density of x (standard error s) for component j
fn lcd(g: *const Ash, norm: bool, mode: f64, sdv: []const f64, x: f64, s: f64, j: usize) -> f64 {
    if norm {
        let sm = math.sqrt[f64](s * s + sdv[j] * sdv[j])
        ret ldn((x - mode) / sm) - math.log[f64](sm)
    }
    let aa = g.lo[j]
    let bb = g.hi[j]
    if aa == bb { ret ldn((x - bb) / s) - math.log[f64](s) }
    let pa = lpn((x - aa) / s)
    let pb = lpn((x - bb) / s)
    ret pa + math.log[f64](1.0f64 - math.exp[f64](pb - pa)) - math.log[f64](bb - aa)
}

// posterior pieces of component j for one observation: the cdf at 0, the mean and the second moment
fn comp_post(norm: bool, mode: f64, sdv: []const f64, aa: f64, bb: f64, x: f64, s: f64, j: usize) -> (f64, f64, f64) {
    if norm {
        let v = sdv[j] * sdv[j]
        let s2 = s * s
        let m1 = (s2 * mode + x * v) / (s2 + v)
        let s1 = math.sqrt[f64](s2 * v / (s2 + v))
        var cd = 0.0f64
        if s1 == 0.0f64 {
            if 0.0f64 >= m1 { cd = 1.0f64 }
        } else {
            cd = dist.pnorm(0.0f64, m1, s1, true, false)
        }
        ret (cd, m1, s1 * s1 + m1 * m1)
    }
    var cd = 1.0f64
    if aa > 0.0f64 { cd = 0.0f64 }
    if aa <= 0.0f64 && bb > 0.0f64 {
        let lna = lpn((x - aa) / s)
        let lnc = lpn(x / s)
        let lnb = lpn((x - bb) / s)
        cd = (math.exp[f64](lnc - lna) - 1.0f64) / (math.exp[f64](lnb - lna) - 1.0f64)
    }
    if aa == bb {
        cd = 0.0f64
        if aa <= 0.0f64 { cd = 1.0f64 }
    }
    if cd != cd { cd = (0.0f64 - aa) / (bb - aa) }
    let pm = x - s * etrunc((x - bb) / s, (x - aa) / s)
    let al = (aa - x) / s
    let be = (bb - x) / s
    let pm2 = x * x + 2.0f64 * x * s * etrunc(al, be) + s * s * e2trunc(al, be)
    ret (cd, pm, pm2)
}

// qval.from.lfdr: cumulative mean of the sorted values, returned in the original order (ties keep their order)
fn qval(a: *mem.Arena, v: []const f64, out: []f64) -> err {
    let n = v.len
    let (ix, e) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize && v[ix[j - 1usize]] > v[i] {
            ix[j] = ix[j - 1usize]
            j -= 1usize
        }
        ix[j] = i
        i += 1usize
    }
    var cs = 0.0f64
    i = 0usize
    while i < n {
        cs += v[ix[i]]
        out[ix[i]] = cs / f64(i + 1usize)
        i += 1usize
    }
    ret ok
}

// the fit; pointmass and nullbiased follow method "fdr" (true, true) or "shrink" (false, false)
fn ash(a: *mem.Arena, x: []const f64, s: []const f64, kind: i64, pointmass: bool, nullbiased: bool, nullweight: f64, mode: f64, mult: f64) -> (Ash, err) {
    var r: Ash = zero
    let n = x.len
    r.n = n
    var smin = s[0usize]
    var i = 1usize
    while i < n {
        if s[i] < smin { smin = s[i] }
        i += 1usize
    }
    smin = smin / 10.0f64
    var allin = true
    var mxv = 0.0f64
    i = 0usize
    while i < n {
        let bh = x[i] - mode
        let d = bh * bh - s[i] * s[i]
        if d > 0.0f64 { allin = false }
        if d > mxv { mxv = d }
        i += 1usize
    }
    var smax = 8.0f64 * smin
    if !allin { smax = 2.0f64 * math.sqrt[f64](mxv) }
    let npoint = usize(math.ceil[f64](math.log2[f64](smax / smin) / math.log2[f64](mult)))
    let ng = npoint + 1usize
    var k0 = ng
    if pointmass { k0 += 1usize }
    let (sd0, e0) = mem.alloc[f64](a, k0)
    if e0 != ok { ret (r, e0) }
    var o = 0usize
    if pointmass {
        sd0[0usize] = 0.0f64
        o = 1usize
    }
    i = 0usize
    while i < ng {
        sd0[o + i] = math.pow[f64](mult, f64(i) - f64(npoint)) * smax
        i += 1usize
    }
    var kk = k0
    var half = false
    if kind == 1i64 {
        half = true
        if pointmass { kk = 2usize * k0 - 1usize } else { kk = 2usize * k0 }
    }
    let (lo, e1) = mem.alloc[f64](a, kk)
    let (hi, e2) = mem.alloc[f64](a, kk)
    let (sdv, e3) = mem.alloc[f64](a, kk)
    let (prior, e4) = mem.alloc[f64](a, kk)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (r, mem.Full) }
    var j = 0usize
    while j < k0 {
        prior[j] = 1.0f64
        if j == 0usize && nullbiased { prior[j] = nullweight }
        sdv[j] = sd0[j]
        if kind == 0i64 {
            lo[j] = mode - sd0[j]
            hi[j] = mode + sd0[j]
        } else if kind == 3i64 {
            lo[j] = mode
            hi[j] = mode + sd0[j]
        } else if kind == 4i64 {
            lo[j] = mode - sd0[j]
            hi[j] = mode
        } else if half {
            lo[j] = mode - sd0[j]
            hi[j] = mode
        }
        j += 1usize
    }
    if half {
        var m = k0
        j = 0usize
        while j < k0 {
            if !(pointmass && j == 0usize) {
                lo[m] = mode
                hi[m] = mode + sd0[j]
                prior[m] = prior[j]
                sdv[m] = sd0[j]
                m += 1usize
            }
            j += 1usize
        }
    }
    let norm = kind == 2i64
    var g: Ash = zero
    g.lo = lo
    g.hi = hi
    let (ll, e5) = mem.alloc[f64](a, n * kk)
    let (lik, e6) = mem.alloc[f64](a, n * kk)
    let (lnorm, e7) = mem.alloc[f64](a, n)
    if e5 != ok || e6 != ok || e7 != ok { ret (r, mem.Full) }
    j = 0usize
    while j < kk {
        i = 0usize
        while i < n {
            ll[j * n + i] = lcd(&g, norm, mode, sdv, x[i], s[i], j)
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        var mx = ll[i]
        j = 1usize
        while j < kk {
            if ll[j * n + i] > mx { mx = ll[j * n + i] }
            j += 1usize
        }
        lnorm[i] = mx
        j = 0usize
        while j < kk {
            lik[j * n + i] = math.exp[f64](ll[j * n + i] - mx)
            j += 1usize
        }
        i += 1usize
    }
    let (keep, e8) = mem.alloc[usize](a, kk)
    if e8 != ok { ret (r, mem.Full) }
    var kc = 0usize
    j = 0usize
    while j < kk {
        var cm = 0.0f64
        i = 0usize
        while i < n {
            if lik[j * n + i] > cm { cm = lik[j * n + i] }
            i += 1usize
        }
        if cm > 0.0f64 || prior[j] > 1.0f64 {
            keep[kc] = j
            kc += 1usize
        }
        j += 1usize
    }
    var np_ = 0usize
    j = 0usize
    while j < kc {
        if prior[keep[j]] != 1.0f64 { np_ += 1usize }
        j += 1usize
    }
    let nr = np_ + n
    let (aa, e9) = mem.alloc[f64](a, nr * kc)
    let (w, e10) = mem.alloc[f64](a, nr)
    let (xs, e11) = mem.alloc[f64](a, kc)
    if e9 != ok || e10 != ok || e11 != ok { ret (r, mem.Full) }
    var z = 0usize
    while z < nr * kc {
        aa[z] = 0.0f64
        z += 1usize
    }
    var row = 0usize
    j = 0usize
    while j < kc {
        if prior[keep[j]] != 1.0f64 {
            aa[j * nr + row] = 1.0f64
            w[row] = prior[keep[j]] - 1.0f64
            row += 1usize
        }
        xs[j] = 1.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < kc {
            aa[j * nr + np_ + i] = lik[keep[j] * n + i]
            j += 1usize
        }
        w[np_ + i] = 1.0f64
        i += 1usize
    }
    var c = sq.sqp_default()
    c.eps = 1.0e-6f64
    c.numiter_em = 20i64
    if kc > 1usize {
        let (_, es) = sq.mixsqp_run(a, aa, w, nr, kc, xs, c, false, lnorm[0usize..0usize], lnorm[0usize..0usize])
        if es != ok { ret (r, es) }
    } else {
        xs[0usize] = 1.0f64
    }
    let (pi, e12) = mem.alloc[f64](a, kk)
    if e12 != ok { ret (r, mem.Full) }
    j = 0usize
    while j < kk {
        pi[j] = 0.0f64
        j += 1usize
    }
    var sx = 0.0f64
    j = 0usize
    while j < kc {
        sx += xs[j]
        j += 1usize
    }
    j = 0usize
    while j < kc {
        pi[keep[j]] = xs[j] / sx
        j += 1usize
    }
    // prune
    var kp = 0usize
    var sp = 0.0f64
    j = 0usize
    while j < kk {
        if pi[j] > 1.0e-10f64 {
            lo[kp] = lo[j]
            hi[kp] = hi[j]
            sdv[kp] = sdv[j]
            pi[kp] = pi[j]
            sp += pi[j]
            var t = 0usize
            while t < n {
                ll[kp * n + t] = ll[j * n + t]
                t += 1usize
            }
            kp += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < kp {
        pi[j] = pi[j] / sp
        j += 1usize
    }
    r.k = kp
    r.pi = pi[0usize..kp]
    r.lo = lo[0usize..kp]
    r.sd = sdv[0usize..kp]
    r.hi = hi[0usize..kp]
    let (np, f1) = mem.alloc[f64](a, n)
    let (pp, f2) = mem.alloc[f64](a, n)
    let (lfsr, f3) = mem.alloc[f64](a, n)
    let (sv, f4) = mem.alloc[f64](a, n)
    let (lfdr, f5) = mem.alloc[f64](a, n)
    let (qv, f6) = mem.alloc[f64](a, n)
    let (pm, f7) = mem.alloc[f64](a, n)
    let (psd, f8) = mem.alloc[f64](a, n)
    let (pr, f9) = mem.alloc[f64](a, kp)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok { ret (r, mem.Full) }
    var loglik = 0.0f64
    var nullll = 0.0f64
    i = 0usize
    while i < n {
        var off = ll[i]
        j = 1usize
        while j < kp {
            if ll[j * n + i] > off { off = ll[j * n + i] }
            j += 1usize
        }
        var t = 0.0f64
        j = 0usize
        while j < kp {
            t += pi[j] * math.exp[f64](ll[j * n + i] - off)
            j += 1usize
        }
        loglik += math.log[f64](t) + off
        nullll += ldn(x[i] / s[i]) - math.log[f64](s[i])
        // component posterior weights
        var pmx = math.log[f64](pi[0usize]) + ll[i]
        j = 1usize
        while j < kp {
            let v = math.log[f64](pi[j]) + ll[j * n + i]
            if v > pmx { pmx = v }
            j += 1usize
        }
        var tot = 0.0f64
        j = 0usize
        while j < kp {
            pr[j] = math.exp[f64](math.log[f64](pi[j]) + ll[j * n + i] - pmx)
            tot += pr[j]
            j += 1usize
        }
        var zp = 0.0f64
        var cdf = 0.0f64
        var m1 = 0.0f64
        var m2 = 0.0f64
        j = 0usize
        while j < kp {
            let wj = pr[j] / tot
            let (cd, cm, c2) = comp_post(norm, mode, sdv[0usize..kp], lo[j], hi[j], x[i], s[i], j)
            var onz = false
            if norm {
                onz = mode == 0.0f64 && sdv[j] == 0.0f64
            } else {
                onz = (lo[j] + hi[j]) / 2.0f64 == 0.0f64 && (hi[j] - lo[j]) / math.sqrt[f64](12.0f64) == 0.0f64
            }
            if onz { zp += wj }
            cdf += wj * cd
            m1 += wj * cm
            m2 += wj * c2
            j += 1usize
        }
        if zp < 0.0f64 { zp = 0.0f64 }
        var neg = cdf - zp
        if neg < 0.0f64 { neg = 0.0f64 }
        var pos = 1.0f64 - neg - zp
        if pos < 0.0f64 { pos = 0.0f64 }
        var ls = neg + zp
        if neg > 0.5f64 * (1.0f64 - zp) { ls = 1.0f64 - neg }
        if ls < 0.0f64 { ls = 0.0f64 }
        np[i] = neg
        pp[i] = pos
        lfdr[i] = zp
        lfsr[i] = ls
        pm[i] = m1
        var pv = m2 - m1 * m1
        if pv < 0.0f64 { pv = 0.0f64 }
        psd[i] = math.sqrt[f64](pv)
        i += 1usize
    }
    let q1 = qval(a, lfsr, sv)
    let q2 = qval(a, lfdr, qv)
    if q1 != ok { ret (r, q1) }
    if q2 != ok { ret (r, q2) }
    r.loglik = loglik
    r.loglr = loglik - nullll
    r.np = np
    r.pp = pp
    r.lfsr = lfsr
    r.svalue = sv
    r.lfdr = lfdr
    r.qvalue = qv
    r.pm = pm
    r.psd = psd
    ret (r, ok)
}
