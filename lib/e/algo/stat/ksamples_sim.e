// R kSamples, the permutation side: the exact and simulated p-values of ad.test and qn.test and of contingency2xt, the null distributions
// behind them (dist = TRUE), the normal scores of qn.test(test = "NS") and the combined tests over several data sets.
//
// The simulated p-values come out of R's own stream: kSamples' randPerm (a Fisher-Yates cut at the first sample, one runif(0, 1) per
// swap) and contingency2xtSim (one rhyper per column), so a stream seeded like set.seed gives the package's counts exactly. qn.test
// averages the tied scores with rank(ties.method = "random"), which draws one runif per observation before any simulation; that
// draw is reproduced.
//
// Method codes: 0 asymptotic, 1 simulated, 2 exact. Test codes of qn.test: 0 KW, 1 vdW, 2 NS.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.ksamples as ks
use e.math
use e.math.dist as mdist
use e.math.nmath as nm
use e.math.special as special
use e.mem

// an empty slice that can still be assigned slices of mutable memory
fn kx_empty(a: *mem.Arena) -> []f64 {
    let (e, er) = mem.alloc[f64](a, 1usize)
    ret e[0usize..0usize]
}

// C's round(): halves away from zero
fn kx_cround(v: f64) -> f64 {
    if v >= 0.0f64 { ret math.floor[f64](v + 0.5f64) }
    ret 0.0f64 - math.floor[f64](0.5f64 - v)
}

// R's round(x, digits) for a few digits
fn kx_round(x: f64, digits: i64) -> f64 {
    var p = 1.0f64
    var i = 0i64
    while i < digits {
        p = p * 10.0f64
        i += 1i64
    }
    ret kx_cround(x * p) / p
}

// R's signif(x, digits) (fprec): scale by a power of ten, round to even, scale back
fn kx_signif(x: f64, digits: i64) -> f64 {
    if x == 0.0f64 || x != x { ret x }
    var ax = x
    var sgn = 1.0f64
    if x < 0.0f64 {
        ax = 0.0f64 - x
        sgn = 0.0f64 - 1.0f64
    }
    let e10 = digits - 1i64 - i64(math.floor[f64](math.log10[f64](ax)))
    var ae = e10
    if e10 < 0i64 { ae = 0i64 - e10 }
    var p10 = 1.0f64
    var i = 0i64
    while i < ae {
        p10 = p10 * 10.0f64
        i += 1i64
    }
    if e10 > 0i64 { ret sgn * (math.round[f64](ax * p10) / p10) }
    ret sgn * (math.round[f64](ax / p10) * p10)
}

// R's mean: a second pass corrects the first
fn kx_mean(v: []const f64) -> f64 {
    let n = f64(v.len)
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    s = s / n
    var t = 0.0f64
    i = 0usize
    while i < v.len {
        t += v[i] - s
        i += 1usize
    }
    ret s + t / n
}

// the number of assignments of the pooled observations to the first k - 1 samples, as the package multiplies it
fn kx_ncomb(sizes: []const usize) -> f64 {
    var nc = 1.0f64
    var np = 0usize
    var i = 0usize
    while i < sizes.len {
        np += sizes[i]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < sizes.len {
        nc = nc * special.choose(f64(np), f64(sizes[i]))
        np -= sizes[i]
        i += 1usize
    }
    ret nc
}

// ---- normal scores: SuppDists normOrder (Royston's AS 177.3) ----

fn kx_correc(i: i64, n: i64) -> f64 {
    if i * n == 4i64 { ret 1.9e-5f64 }
    if i < 1i64 || i > 7i64 { ret 0.0f64 }
    if i != 4i64 && n > 20i64 { ret 0.0f64 }
    if i == 4i64 && n > 40i64 { ret 0.0f64 }
    let an0 = f64(n)
    let an = 1.0f64 / (an0 * an0)
    var c1 = 0.0f64
    var c2 = 0.0f64
    var c3 = 0.0f64
    if i == 1i64 {
        c1 = 9.5f64
        c2 = 0.0f64 - 6195.0f64
        c3 = 93380.0f64
    }
    if i == 2i64 {
        c1 = 28.7f64
        c2 = 0.0f64 - 9569.0f64
        c3 = 175160.0f64
    }
    if i == 3i64 {
        c1 = 1.9f64
        c2 = 0.0f64 - 6728.0f64
        c3 = 410400.0f64
    }
    if i == 4i64 {
        c1 = 0.0f64
        c2 = 0.0f64 - 17614.0f64
        c3 = 2157600.0f64
    }
    if i == 5i64 {
        c1 = 0.0f64 - 7.0f64
        c2 = 0.0f64 - 8278.0f64
        c3 = 2.376e6f64
    }
    if i == 6i64 {
        c1 = 0.0f64 - 6.2f64
        c2 = 0.0f64 - 3570.0f64
        c3 = 2.065e6f64
    }
    if i == 7i64 {
        c1 = 0.0f64 - 1.6f64
        c2 = 1075.0f64
        c3 = 2.065e6f64
    }
    ret (c1 + an * (c2 + an * c3)) * 1.0e-6f64
}

fn kx_eps(i: usize) -> f64 {
    if i == 0usize { ret 0.419885f64 }
    if i == 1usize { ret 0.450536f64 }
    if i == 2usize { ret 0.456936f64 }
    ret 0.468488f64
}

fn kx_dl1(i: usize) -> f64 {
    if i == 0usize { ret 0.112063f64 }
    if i == 1usize { ret 0.12177f64 }
    if i == 2usize { ret 0.239299f64 }
    ret 0.215159f64
}

fn kx_dl2(i: usize) -> f64 {
    if i == 0usize { ret 0.080122f64 }
    if i == 1usize { ret 0.111348f64 }
    if i == 2usize { ret 0.0f64 - 0.211867f64 }
    ret 0.0f64 - 0.115049f64
}

fn kx_gam(i: usize) -> f64 {
    if i == 0usize { ret 0.474798f64 }
    if i == 1usize { ret 0.469051f64 }
    if i == 2usize { ret 0.208597f64 }
    ret 0.259784f64
}

fn kx_lam(i: usize) -> f64 {
    if i == 0usize { ret 0.282765f64 }
    if i == 1usize { ret 0.304856f64 }
    if i == 2usize { ret 0.407708f64 }
    ret 0.414093f64
}

// the expected values of the normal order statistics of a sample of n, smallest first (SuppDists::normOrder)
fn kx_norm_order(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (out, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (out, e0) }
    let m = n / 2usize
    let (s, e1) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok { ret (out, e1) }
    s[0usize] = 0.5641896f64
    if n > 2usize {
        let an = f64(n)
        var k = 3usize
        if m < k { k = m }
        var i = 0usize
        while i < k {
            let ai = f64(i + 1usize)
            let e1v = (ai - kx_eps(i)) / (an + kx_gam(i))
            let e2v = math.pow[f64](e1v, kx_lam(i))
            s[i] = e1v + e2v * (kx_dl1(i) + e2v * kx_dl2(i)) / an - kx_correc(i64(i + 1usize), i64(n))
            i += 1usize
        }
        if m > k {
            i = 3usize
            while i < m {
                let ai = f64(i + 1usize)
                let e1v = (ai - kx_eps(3usize)) / (an + kx_gam(3usize))
                let e2v = math.pow[f64](e1v, kx_lam(3usize) + (0.0f64 - 0.283833f64) / (ai + (0.0f64 - 0.106136f64)))
                s[i] = e1v + e2v * (kx_dl1(3usize) + e2v * kx_dl2(3usize)) / an - kx_correc(i64(i + 1usize), i64(n))
                i += 1usize
            }
        }
        i = 0usize
        while i < m {
            s[i] = 0.0f64 - mdist.qnorm(s[i], 0.0f64, 1.0f64, true, false)
            i += 1usize
        }
    }
    var i = 0usize
    while i < m {
        out[i] = 0.0f64 - s[i]
        out[n - 1usize - i] = s[i]
        i += 1usize
    }
    if n % 2usize == 1usize { out[m] = 0.0f64 }
    ret (out, ok)
}

// the scores 1:n, qnorm((1:n) / (n + 1)) or the normal scores, by test code 0, 1, 2
fn kx_scores(a: *mem.Arena, n: usize, test: usize) -> ([]f64, err) {
    if test == 2usize {
        let (ns, en) = kx_norm_order(a, n)
        ret (ns, en)
    }
    let (sc, e) = mem.alloc[f64](a, n)
    if e != ok { ret (sc, e) }
    var i = 0usize
    while i < n {
        if test == 0usize { sc[i] = f64(i + 1usize) } else { sc[i] = mdist.qnorm(f64(i + 1usize) / (f64(n) + 1.0f64), 0.0f64, 1.0f64, true, false) }
        i += 1usize
    }
    ret (sc, ok)
}

// qn.test's ave.score: tied observations take the mean of the scores of the positions they cover
fn kx_ave_score(a: *mem.Arena, x: []const f64, sc: []const f64) -> ([]f64, err) {
    let n = x.len
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var below = 0usize
        var equal = 0usize
        var j = 0usize
        while j < n {
            if x[j] < x[i] { below += 1usize }
            if x[j] == x[i] { equal += 1usize }
            j += 1usize
        }
        out[i] = kx_mean(sc[below..below + equal])
        i += 1usize
    }
    ret (out, ok)
}

// ---- the statistics, in the order of the package's C code ----

fn kx_lower_bound(z: []const f64, v: f64) -> usize {
    var lo = 0usize
    var hi = z.len
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if z[mid] < v { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

// adkTestStat: out[0] version 1, out[1] version 2
fn kx_adstat(xc: []const f64, ns: []const usize, zstar: []const f64, fij: []f64, lvec: []f64, out: []f64) {
    let k = ns.len
    let l = zstar.len
    var i = 0usize
    while i < k * l {
        fij[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < l {
        lvec[i] = 0.0f64
        i += 1usize
    }
    var off = 0usize
    var nsum = 0usize
    i = 0usize
    while i < k {
        var q = 0usize
        while q < ns[i] {
            let j = kx_lower_bound(zstar, xc[off + q])
            fij[i * l + j] += 1.0f64
            lvec[j] += 1.0f64
            q += 1usize
        }
        off += ns[i]
        nsum += ns[i]
        i += 1usize
    }
    let dn = f64(nsum)
    var s0 = 0.0f64
    var s1 = 0.0f64
    i = 0usize
    while i < k {
        let ni = f64(ns[i])
        var mij = 0.0f64
        var inner = 0.0f64
        var ainner = 0.0f64
        var bj = 0.0f64
        var j = 0usize
        while j < l {
            let f = fij[i * l + j]
            mij += f
            let maij = mij - f / 2.0f64
            bj += lvec[j]
            let baj = bj - lvec[j] / 2.0f64
            if j + 1usize < l {
                let tmp = dn * mij - ni * bj
                inner = inner + lvec[j] * tmp * tmp / (bj * (dn - bj))
            }
            let tmp2 = dn * maij - ni * baj
            ainner = ainner + lvec[j] * tmp2 * tmp2 / (baj * (dn - baj) - dn * lvec[j] / 4.0f64)
            j += 1usize
        }
        s0 = s0 + inner / ni
        s1 = s1 + ainner / ni
        i += 1usize
    }
    out[0usize] = s0 / dn
    out[1usize] = (dn - 1.0f64) * s1 / (dn * dn)
}

// QNTestStat on the averaged scores laid out sample by sample
fn kx_qnstat(rx: []const f64, ns: []const usize, out: []f64) {
    var q = 0.0f64
    var istart = 0usize
    var i = 0usize
    while i < ns.len {
        var ri = 0.0f64
        let iend = istart + ns[i]
        var j = istart
        while j < iend {
            ri += rx[j]
            j += 1usize
        }
        q += ri * ri / f64(ns[i])
        istart = iend
        i += 1usize
    }
    out[0usize] = kx_cround(1.0e8f64 * q) / 1.0e8f64
}

// SteelTestStat: the largest (alt 1), smallest (alt -1) or largest absolute (alt 0) standardised Wilcoxon count of the control, the first
// sample, against each other sample; rx holds the midranks sample by sample
fn kx_steelstat(rx: []const f64, ns: []const usize, mu: []const f64, tau: []const f64, alt: i64, out: []f64) {
    var istart = ns[0usize]
    var i = 1usize
    while i < ns.len {
        let iend = istart + ns[i]
        var ri = 0.0f64
        var j = istart
        while j < iend {
            var m = 0usize
            while m < ns[0usize] {
                if rx[m] <= rx[j] {
                    if rx[m] == rx[j] { ri += 0.5f64 } else { ri += 1.0f64 }
                }
                m += 1usize
            }
            j += 1usize
        }
        ri = (ri - mu[i - 1usize]) / tau[i - 1usize]
        if alt == 1i64 {
            if i == 1usize { out[0usize] = ri } else {
                if ri > out[0usize] { out[0usize] = ri }
            }
        }
        if alt == 0i64 - 1i64 {
            if i == 1usize { out[0usize] = ri } else {
                if ri < out[0usize] { out[0usize] = ri }
            }
        }
        if alt == 0i64 {
            if ri < 0.0f64 { ri = 0.0f64 - ri }
            if i == 1usize { out[0usize] = ri } else {
                if ri > out[0usize] { out[0usize] = ri }
            }
        }
        istart = iend
        i += 1usize
    }
}

// JTTestStat: the Jonckheere-Terpstra count over all ordered pairs of samples
fn kx_jtstat(rx: []const f64, ns: []const usize, out: []f64) {
    var mstart = 0usize
    out[0usize] = 0.0f64
    var i = 0usize
    while i + 1usize < ns.len {
        let mend = mstart + ns[i]
        var nstart = mend
        var j = i + 1usize
        while j < ns.len {
            let nend = nstart + ns[j]
            var n = nstart
            while n < nend {
                var m = mstart
                while m < mend {
                    if rx[m] <= rx[n] {
                        if rx[m] == rx[n] { out[0usize] += 0.5f64 } else { out[0usize] += 1.0f64 }
                    }
                    m += 1usize
                }
                n += 1usize
            }
            nstart = nend
            j += 1usize
        }
        mstart = mend
        i += 1usize
    }
}

// ---- exactcomb: every split of the pooled observations into the samples, in Knuth's Chase order ----

type ExCtx = struct {
    kind: usize, k: usize, nsum: usize, ns: []const usize, xvec: []const f64, ivec: []usize,
    dimst: usize, teststat: []const f64, pval: []f64, smat: []f64, gets: bool, ncomb: usize, count: usize,
    xc: []f64, tc: []f64, arena: *mem.Arena, zstar: []const f64, fij: []f64, lvec: []f64, alt: i64, mu: []const f64, tau: []const f64
}

fn kx_eval(c: *ExCtx, out: []f64) {
    if c.kind == 0usize {
        kx_adstat(c.xc, c.ns, c.zstar, c.fij, c.lvec, out)
        ret
    }
    if c.kind == 2usize {
        kx_steelstat(c.xc, c.ns, c.mu, c.tau, c.alt, out)
        ret
    }
    if c.kind == 3usize {
        kx_jtstat(c.xc, c.ns, out)
        ret
    }
    kx_qnstat(c.xc, c.ns, out)
}

// the context for kind 0 (AD over the values xvec with the distinct sorted zstar) or 1 (the QN statistic over averaged scores)
fn kx_ctx(a: *mem.Arena, kind: usize, xvec: []const f64, ns: []const usize, zstar: []const f64) -> (ExCtx, err) {
    var nsum = 0usize
    var i = 0usize
    while i < ns.len {
        nsum += ns[i]
        i += 1usize
    }
    let dimst = 1usize + (1usize - 1usize)
    var dm = dimst
    if kind == 0usize { dm = 2usize }
    let (ivec, e1) = mem.alloc[usize](a, nsum)
    let (xc, e2) = mem.alloc[f64](a, nsum)
    let (tc, e3) = mem.alloc[f64](a, 2usize)
    let (fij, e4) = mem.alloc[f64](a, ns.len * zstar.len + 1usize)
    let (lvec, e5) = mem.alloc[f64](a, zstar.len + 1usize)
    let (pv, e6) = mem.alloc[f64](a, 2usize)
    var e = ok
    if e1 != ok { e = e1 }
    if e2 != ok { e = e2 }
    if e3 != ok { e = e3 }
    if e4 != ok { e = e4 }
    if e5 != ok { e = e5 }
    if e6 != ok { e = e6 }
    let c = ExCtx{ kind: kind, k: ns.len, nsum: nsum, ns: ns, xvec: xvec, ivec: ivec, dimst: dm, teststat: tc, pval: pv, smat: tc, gets: false, ncomb: 1usize, count: 0usize, xc: xc, tc: tc, arena: a, zstar: zstar, fij: fij, lvec: lvec, alt: 1i64, mu: tc, tau: tc }
    ret (c, e)
}

fn kx_exactcomb(c: *ExCtx, now: usize, position: []const usize, m: usize) {
    if now + 1usize == c.k {
        var i = 0usize
        while i < m {
            c.ivec[position[i]] = now
            i += 1usize
        }
        var pt = 0usize
        i = 0usize
        while i < c.k {
            var j = 0usize
            while j < c.nsum {
                if c.ivec[j] == i {
                    c.xc[pt] = c.xvec[j]
                    pt += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        kx_eval(c, c.tc)
        var j = 0usize
        while j < c.dimst {
            if c.gets { c.smat[c.count + c.ncomb * j] = c.tc[j] }
            if c.tc[j] >= c.teststat[j] { c.pval[j] = c.pval[j] + 1.0f64 }
            j += 1usize
        }
        c.count += 1usize
        ret
    }
    let start = mem.mark(c.arena)
    let s = m - c.ns[now]
    let (av, e1) = mem.alloc[usize](c.arena, m + 1usize)
    let (w, e2) = mem.alloc[usize](c.arena, m + 2usize)
    let (np, e3) = mem.alloc[usize](c.arena, s + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret }
    var j = 0usize
    while j < s {
        av[j] = 0usize
        w[j] = 1usize
        j += 1usize
    }
    j = s
    while j < m {
        av[j] = 1usize
        w[j] = 1usize
        j += 1usize
    }
    w[m] = 1usize
    var r = s
    if s == 0usize { r = c.ns[now] }
    j = r
    var going = true
    while going {
        var ti = 0usize
        var i = 0usize
        while i < m {
            if av[i] == 1usize {
                c.ivec[position[i]] = now
            } else {
                np[ti] = position[i]
                ti += 1usize
            }
            i += 1usize
        }
        kx_exactcomb(c, now + 1usize, np[0usize..s], s)
        j = r
        while w[j] == 0usize {
            w[j] = 1usize
            j += 1usize
        }
        if j == m {
            going = false
        } else {
            w[j] = 0usize
            if av[j] == 1usize {
                if j % 2usize == 0usize && av[j - 2usize] == 0usize {
                    av[j - 2usize] = 1usize
                    av[j] = 0usize
                    if r == j {
                        if j - 2usize > 1usize { r = j - 2usize } else { r = 1usize }
                    } else {
                        if r == j - 2usize { r = j - 1usize }
                    }
                } else {
                    av[j - 1usize] = 1usize
                    av[j] = 0usize
                    if r == j && j > 1usize {
                        r = j - 1usize
                    } else {
                        if r == j - 1usize { r = j }
                    }
                }
            } else {
                if j % 2usize == 1usize && j >= 2usize && av[j - 1usize] == 0usize {
                    av[j] = 1usize
                    av[j - 2usize] = 0usize
                    if r == j - 2usize {
                        r = j
                    } else {
                        if r == j - 1usize { r = j - 2usize }
                    }
                } else {
                    av[j] = 1usize
                    av[j - 1usize] = 0usize
                    if r == j && j > 1usize {
                        r = j - 1usize
                    } else {
                        if r == j - 1usize { r = j }
                    }
                }
            }
        }
    }
    mem.reset(c.arena, start)
}

// visits every split; pval counts the splits whose statistic reaches the observed one
fn kx_run_exact(c: *ExCtx) -> err {
    let (position, e) = mem.alloc[usize](c.arena, c.nsum)
    if e != ok { ret e }
    var i = 0usize
    while i < c.nsum {
        position[i] = i
        i += 1usize
    }
    kx_exactcomb(c, 0usize, position, c.nsum)
    ret ok
}

// randPerm: swaps positions nsum - 1 down to ns[0] with one uniform each
fn kx_rand_perm(g: *rng.Rng, rc: []f64, nsum: usize, n0: usize) {
    var j = nsum
    while j > n0 {
        var randy = rng.runif(g, 0.0f64, 1.0f64)
        while 1.0f64 <= randy { randy = rng.runif(g, 0.0f64, 1.0f64) }
        let index = usize(math.floor[f64](randy * f64(j)))
        let t = rc[j - 1usize]
        rc[j - 1usize] = rc[index]
        rc[index] = t
        j -= 1usize
    }
}

// ---- ad.test ----

type AdOut = struct {
    ad1: f64, ad2: f64, t1: f64, t2: f64, a1: f64, a2: f64, p1: f64, p2: f64,
    r1: f64, r2: f64, sig: f64, nties: usize, method: usize, nsim: usize, d1: []f64, d2: []f64
}

// ad.test over the samples stored back to back in x. method 0 asymptotic, 1 simulated, 2 exact; dist asks for the null distributions;
// the stream g supplies the simulation (the caller seeds it the way set.seed does). r1 and r2 are the statistics as ad.test prints them (5 and 3 digits).
fn kx_ad_test(a: *mem.Arena, g: *rng.Rng, x: []const f64, sizes: []const usize, method0: usize, dist0: bool, nsim0: usize) -> (AdOut, err) {
    let k = sizes.len
    let n = x.len
    let (zs, es) = ks.sorted_pool(a, x)
    if es != ok { ret (AdOut{ ad1: 0.0f64, ad2: 0.0f64, t1: 0.0f64, t2: 0.0f64, a1: 0.0f64, a2: 0.0f64, p1: 0.0f64, p2: 0.0f64, r1: 0.0f64, r2: 0.0f64, sig: 0.0f64, nties: 0usize, method: 0usize, nsim: 0usize, d1: kx_empty(a), d2: kx_empty(a) }, es) }
    var zl = 0usize
    var i = 0usize
    while i < n {
        if i == 0usize || zs[i] != zs[i - 1usize] {
            zs[zl] = zs[i]
            zl += 1usize
        }
        i += 1usize
    }
    let zstar = zs[0usize..zl]
    var method = method0
    var dist = dist0
    var nsim = nsim0
    if dist && nsim > 100000000usize { nsim = 100000000usize }
    let ncomb = kx_ncomb(sizes)
    if method == 2usize && f64(nsim) < ncomb { method = 1usize }
    if method == 0usize {
        nsim = 1usize
        dist = false
    }
    var nrow = 0usize
    if method == 2usize && dist { nrow = usize(ncomb) }
    if method == 1usize && dist { nrow = nsim }
    var pv0 = 0.0f64
    var pv1 = 0.0f64
    var d1 = kx_empty(a)
    var d2 = kx_empty(a)
    let (cx, ec) = kx_ctx(a, 0usize, x, sizes, zstar)
    var c = cx
    var res = AdOut{ ad1: 0.0f64, ad2: 0.0f64, t1: 0.0f64, t2: 0.0f64, a1: 0.0f64, a2: 0.0f64, p1: 0.0f64, p2: 0.0f64, r1: 0.0f64, r2: 0.0f64, sig: 0.0f64, nties: n - zl, method: method, nsim: nsim, d1: d1, d2: d2 }
    if ec != ok { ret (res, ec) }
    var obs0 = 0.0f64
    var obs1 = 0.0f64
    kx_adstat(x, sizes, zstar, c.fij, c.lvec, c.tc)
    obs0 = c.tc[0usize]
    obs1 = c.tc[1usize]
    if method != 0usize {
        var ob = c.pval
        ob[0usize] = 0.0f64
        ob[1usize] = 0.0f64
        let (ov, eo) = mem.alloc[f64](a, 2usize)
        if eo != ok { ret (res, eo) }
        ov[0usize] = obs0
        ov[1usize] = obs1
        c.teststat = ov
        if dist {
            let (m1, e7) = mem.alloc[f64](a, nrow + 1usize)
            let (m2, e8) = mem.alloc[f64](a, nrow + 1usize)
            if e7 != ok || e8 != ok { ret (res, e7) }
            d1 = m1[0usize..nrow]
            d2 = m2[0usize..nrow]
        }
        if method == 2usize {
            c.ncomb = usize(ncomb)
            if dist {
                let (sm, e9) = mem.alloc[f64](a, 2usize * c.ncomb + 1usize)
                if e9 != ok { ret (res, e9) }
                c.smat = sm
                c.gets = true
            }
            let er = kx_run_exact(&c)
            if er != ok { ret (res, er) }
            pv0 = c.pval[0usize] / ncomb
            pv1 = c.pval[1usize] / ncomb
            if dist {
                var q = 0usize
                while q < c.ncomb {
                    d1[q] = kx_round(c.smat[q], 8i64)
                    d2[q] = kx_round(c.smat[q + c.ncomb], 8i64)
                    q += 1usize
                }
            }
        } else {
            let (rc, er2) = mem.alloc[f64](a, n)
            if er2 != ok { ret (res, er2) }
            var is = 0usize
            var h0 = 0.0f64
            var h1 = 0.0f64
            while is < nsim {
                var q = 0usize
                while q < n {
                    rc[q] = x[q]
                    q += 1usize
                }
                kx_rand_perm(g, rc, n, sizes[0usize])
                kx_adstat(rc, sizes, zstar, c.fij, c.lvec, c.tc)
                if dist {
                    d1[is] = kx_round(c.tc[0usize], 8i64)
                    d2[is] = kx_round(c.tc[1usize], 8i64)
                }
                if c.tc[0usize] >= obs0 { h0 += 1.0f64 }
                if c.tc[1usize] >= obs1 { h1 += 1.0f64 }
                is += 1usize
            }
            pv0 = h0 / f64(nsim)
            pv1 = h1 / f64(nsim)
        }
    }
    let kk = f64(k)
    let nn = f64(n)
    var sig = 0.0f64
    var t1 = 0.0f64 / 0.0f64
    var t2 = 0.0f64 / 0.0f64
    var a1 = 1.0f64
    var a2 = 1.0f64
    if n > 3usize {
        sig = ks.sigma_n(sizes)
        t1 = (obs0 - (kk - 1.0f64)) / sig
        t2 = (obs1 - (kk - 1.0f64)) / sig
        a1 = ks.ad_pval(a, t1, kk - 1.0f64, 1usize)
        a2 = ks.ad_pval(a, t2, kk - 1.0f64, 2usize)
    }
    if n == 3usize && k == 2usize {
        sig = 0.3535534f64
        t1 = (obs0 - (kk - 1.0f64)) / sig
        t2 = (obs1 - (kk - 1.0f64)) / sig
        a1 = ks.ad_pval(a, t1, kk - 1.0f64, 1usize)
        a2 = ks.ad_pval(a, t2, kk - 1.0f64, 2usize)
    }
    res = AdOut{ ad1: obs0, ad2: obs1, t1: t1, t2: t2, a1: a1, a2: a2, p1: pv0, p2: pv1, r1: kx_signif(obs0, 5i64), r2: kx_signif(obs1, 3i64), sig: sig, nties: n - zl, method: method, nsim: nsim, d1: d1, d2: d2 }
    ret (res, ok)
}

// ---- qn.test ----

type QnOut = struct { stat: f64, asym: f64, p: f64, nties: usize, method: usize, nsim: usize, dist: []f64 }

// qn.test(test = KW, vdW or NS) over the samples stored back to back in x. The stream g supplies rank(ties.method = "random") first
// (one runif per observation) and then the simulation.
fn kx_qn_test(a: *mem.Arena, g: *rng.Rng, x: []const f64, sizes: []const usize, test: usize, method0: usize, dist0: bool, nsim0: usize) -> (QnOut, err) {
    let k = sizes.len
    let n = x.len
    var res = QnOut{ stat: 0.0f64, asym: 0.0f64, p: 0.0f64, nties: 0usize, method: method0, nsim: nsim0, dist: kx_empty(a) }
    let (sc, e1) = kx_scores(a, n, test)
    if e1 != ok { ret (res, e1) }
    var u = 0usize
    while u < n {
        let _ = rng.runif(g, 0.0f64, 1.0f64)
        u += 1usize
    }
    let (rx, e2) = kx_ave_score(a, x, sc)
    if e2 != ok { ret (res, e2) }
    let smean = kx_mean(rx)
    var ss = 0.0f64
    var i = 0usize
    while i < n {
        ss += (rx[i] - smean) * (rx[i] - smean)
        i += 1usize
    }
    let svar = ss / f64(n - 1usize)
    let (zs, e3) = ks.sorted_pool(a, rx)
    if e3 != ok { ret (res, e3) }
    var zl = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || zs[i] != zs[i - 1usize] { zl += 1usize }
        i += 1usize
    }
    var method = method0
    var dist = dist0
    var nsim = nsim0
    if dist && nsim > 100000000usize { nsim = 100000000usize }
    let ncomb = kx_ncomb(sizes)
    if method == 2usize && f64(nsim) < ncomb { method = 1usize }
    if method == 0usize {
        nsim = 1usize
        dist = false
    }
    var nrow = 0usize
    if method == 2usize && dist { nrow = usize(ncomb) }
    if method == 1usize && dist { nrow = nsim }
    let (cx, ec) = kx_ctx(a, 1usize, rx, sizes, kx_empty(a))
    if ec != ok { ret (res, ec) }
    var c = cx
    kx_qnstat(rx, sizes, c.tc)
    let obs = c.tc[0usize]
    var pv = 0.0f64
    var dv = kx_empty(a)
    if method != 0usize {
        let (ov, eo) = mem.alloc[f64](a, 2usize)
        if eo != ok { ret (res, eo) }
        ov[0usize] = obs
        c.teststat = ov
        c.pval[0usize] = 0.0f64
        let (m1, e7) = mem.alloc[f64](a, nrow + 1usize)
        if e7 != ok { ret (res, e7) }
        dv = m1[0usize..nrow]
        if method == 2usize {
            c.ncomb = usize(ncomb)
            if dist {
                let (sm, e9) = mem.alloc[f64](a, c.ncomb + 1usize)
                if e9 != ok { ret (res, e9) }
                c.smat = sm
                c.gets = true
            }
            let er = kx_run_exact(&c)
            if er != ok { ret (res, er) }
            pv = c.pval[0usize] / ncomb
            if dist {
                var q = 0usize
                while q < c.ncomb {
                    dv[q] = kx_round((c.smat[q] - f64(n) * smean * smean) / svar, 8i64)
                    q += 1usize
                }
            }
        } else {
            let (rc, er2) = mem.alloc[f64](a, n)
            if er2 != ok { ret (res, er2) }
            var is = 0usize
            var h = 0.0f64
            while is < nsim {
                var q = 0usize
                while q < n {
                    rc[q] = rx[q]
                    q += 1usize
                }
                kx_rand_perm(g, rc, n, sizes[0usize])
                kx_qnstat(rc, sizes, c.tc)
                if c.tc[0usize] >= obs { h += 1.0f64 }
                if dist { dv[is] = kx_round((c.tc[0usize] - f64(n) * smean * smean) / svar, 8i64) }
                is += 1usize
            }
            pv = h / f64(nsim)
        }
    }
    let stat = (obs - f64(n) * smean * smean) / svar
    let asym = 1.0f64 - nm.pchisq(stat, f64(k - 1usize), true, false)
    ret (QnOut{ stat: stat, asym: asym, p: pv, nties: n - zl, method: method, nsim: nsim, dist: dv }, ok)
}

// ---- contingency2xt ----

type C2Out = struct { kw: f64, asym: f64, p: f64, method: usize, nsim: usize, vals: []f64, probs: []f64 }

type C2Walk = struct { d: []const f64, t: usize, m: f64, obs: f64, cc: f64, pval: f64, cur: []f64, vals: []f64, probs: []f64, cnt: usize, gets: bool }

fn kx_c2_walk(c: *C2Walk, pos: usize, rem: f64) {
    if pos + 1usize == c.t {
        if rem > c.d[pos] { ret }
        c.cur[pos] = rem
        var delta = 0.0f64
        var pr = 1.0f64
        var i = 0usize
        while i < c.t {
            delta = delta + c.cur[i] * c.cur[i] / c.d[i]
            pr = pr * special.choose(c.d[i], c.cur[i])
            i += 1usize
        }
        pr = pr / c.cc
        if delta >= c.obs { c.pval += pr }
        if c.gets {
            c.vals[c.cnt] = delta
            c.probs[c.cnt] = pr
            c.cnt += 1usize
        }
        ret
    }
    var v = 0.0f64
    while v <= c.d[pos] && v <= rem {
        c.cur[pos] = v
        kx_c2_walk(c, pos + 1usize, rem - v)
        v += 1.0f64
    }
}

// shell sort of the values with their probabilities riding along
fn kx_sort2(v: []f64, p: []f64) {
    var gap = v.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < v.len {
            let tv = v[i]
            let tp = p[i]
            var j = i
            while j >= gap && v[j - gap] > tv {
                v[j] = v[j - gap]
                p[j] = p[j - gap]
                j -= gap
            }
            v[j] = tv
            p[j] = tp
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// contingency2xt(Avec, Bvec, method, dist, tab0, Nsim); vals and probs are the null distribution when dist (a table of KW values and
// probabilities, or with tab0 false and a simulated null every simulated value and no probabilities)
fn kx_contingency(a: *mem.Arena, g: *rng.Rng, avec: []const f64, bvec: []const f64, method0: usize, dist: bool, tab0: bool, nsim0: usize) -> (C2Out, err) {
    let t = avec.len
    var m = 0.0f64
    var nb0 = 0.0f64
    var i = 0usize
    while i < t {
        m += avec[i]
        nb0 += bvec[i]
        i += 1usize
    }
    let nn = m + nb0
    let (d, e1) = mem.alloc[f64](a, t)
    let (cur, e2) = mem.alloc[f64](a, t)
    let res = C2Out{ kw: 0.0f64, asym: 0.0f64, p: 0.0f64, method: method0, nsim: nsim0, vals: kx_empty(a), probs: kx_empty(a) }
    if e1 != ok { ret (res, e1) }
    if e2 != ok { ret (res, e2) }
    var s = 0.0f64
    var dobs = 0.0f64
    i = 0usize
    while i < t {
        d[i] = avec[i] + bvec[i]
        s += avec[i] * avec[i] / d[i]
        dobs = dobs + avec[i] * avec[i] / d[i]
        i += 1usize
    }
    let scale = nn * (nn - 1.0f64) / (m * nb0)
    let kw0 = scale * (s - m * m / nn)
    let asym = 1.0f64 - nm.pchisq(kw0, f64(t - 1usize), true, false)
    var method = method0
    var nsim = nsim0
    if method == 0usize { ret (C2Out{ kw: kw0, asym: asym, p: 0.0f64, method: 0usize, nsim: nsim, vals: kx_empty(a), probs: kx_empty(a) }, ok) }
    if dist && nsim > 100000000usize { nsim = 100000000usize }
    let ncomb = special.choose(m + f64(t) - 1.0f64, f64(t) - 1.0f64)
    let kwo = kx_round(scale * (dobs - m * m / nn), 6i64)
    var pv = 0.0f64
    var vals = kx_empty(a)
    var probs = kx_empty(a)
    if f64(nsim) >= ncomb && method == 2usize {
        let cap = usize(ncomb) + 1usize
        let (vv, e3) = mem.alloc[f64](a, cap)
        let (pp, e4) = mem.alloc[f64](a, cap)
        if e3 != ok { ret (res, e3) }
        if e4 != ok { ret (res, e4) }
        var w = C2Walk{ d: d, t: t, m: m, obs: dobs, cc: special.choose(nn, m), pval: 0.0f64, cur: cur, vals: vv, probs: pp, cnt: 0usize, gets: dist }
        kx_c2_walk(&w, 0usize, m)
        pv = w.pval
        if dist {
            var q = 0usize
            while q < w.cnt {
                vv[q] = kx_round(scale * (vv[q] - m * m / nn), 6i64)
                q += 1usize
            }
            kx_sort2(vv[0usize..w.cnt], pp[0usize..w.cnt])
            var u = 0usize
            q = 0usize
            while q < w.cnt {
                if u > 0usize && vv[u - 1usize] == vv[q] {
                    pp[u - 1usize] += pp[q]
                } else {
                    vv[u] = vv[q]
                    pp[u] = pp[q]
                    u += 1usize
                }
                q += 1usize
            }
            vals = vv[0usize..u]
            probs = pp[0usize..u]
        }
    } else {
        method = 1usize
        if nsim < 100usize { nsim = 100usize }
        let (sv, e5) = mem.alloc[f64](a, nsim)
        if e5 != ok { ret (res, e5) }
        var h = 0.0f64
        var is = 0usize
        while is < nsim {
            var nb = nn
            var kk = m
            var delta = 0.0f64
            var sum = 0.0f64
            var j = 0usize
            while j + 1usize < t {
                nb = nb - d[j]
                let av = math.trunc[f64](rd.rhyper(g, d[j], nb, kk))
                delta = delta + av * av / d[j]
                sum = sum + av
                kk = kk - av
                j += 1usize
            }
            let al = m - sum
            delta = delta + al * al / d[t - 1usize]
            if delta >= dobs { h += 1.0f64 }
            sv[is] = delta
            is += 1usize
        }
        pv = h / f64(nsim)
        if dist {
            var q = 0usize
            while q < nsim {
                sv[q] = scale * (kx_round(sv[q], 6i64) - m * m / nn)
                q += 1usize
            }
            if tab0 {
                let (pz, e6) = mem.alloc[f64](a, nsim)
                if e6 != ok { ret (res, e6) }
                var z = sv
                q = 0usize
                while q < nsim {
                    pz[q] = 1.0f64
                    q += 1usize
                }
                kx_sort2(z, pz)
                var u = 0usize
                q = 0usize
                while q < nsim {
                    if u > 0usize && z[u - 1usize] == z[q] {
                        pz[u - 1usize] += 1.0f64
                    } else {
                        z[u] = z[q]
                        pz[u] = pz[q]
                        u += 1usize
                    }
                    q += 1usize
                }
                q = 0usize
                while q < u {
                    pz[q] = pz[q] / f64(nsim)
                    q += 1usize
                }
                vals = z[0usize..u]
                probs = pz[0usize..u]
            } else {
                vals = sv
            }
        }
    }
    ret (C2Out{ kw: kwo, asym: asym, p: pv, method: method, nsim: nsim, vals: vals, probs: probs }, ok)
}

// ---- the combined tests: several data sets, their statistics added and their null distributions summed or convolved ----

// all sums x1[i] + x2[j], index j + i * n2 (the package's convvec)
fn kx_convvec(a: *mem.Arena, x1: []const f64, x2: []const f64) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, x1.len * x2.len + 1usize)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x1.len {
        var j = 0usize
        while j < x2.len {
            out[j + i * x2.len] = x1[i] + x2[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..x1.len * x2.len], ok)
}

// the distribution of the sum of two independent tables: the support sums rounded to eight decimals, the probabilities multiplied
fn kx_conv(a: *mem.Arena, x1: []const f64, p1: []const f64, x2: []const f64, p2: []const f64) -> ([]f64, []f64, err) {
    let cap = x1.len * x2.len + 1usize
    let (xs, e1) = mem.alloc[f64](a, cap)
    let (ps, e2) = mem.alloc[f64](a, cap)
    if e1 != ok { ret (xs, ps, e1) }
    if e2 != ok { ret (xs, ps, e2) }
    var lt = 0usize
    var i = 0usize
    while i < x1.len {
        var j = 0usize
        while j < x2.len {
            let xn = kx_cround(1.0e8f64 * (x1[i] + x2[j])) / 1.0e8f64
            let pn = p1[i] * p2[j]
            // the first index whose value is at least xn
            var lo = 0usize
            var hi = lt
            while lo < hi {
                let mid = (lo + hi) / 2usize
                if xs[mid] < xn { lo = mid + 1usize } else { hi = mid }
            }
            if lo < lt && xs[lo] == xn {
                ps[lo] += pn
            } else {
                var q = lt
                while q > lo {
                    xs[q] = xs[q - 1usize]
                    ps[q] = ps[q - 1usize]
                    q -= 1usize
                }
                xs[lo] = xn
                ps[lo] = pn
                lt += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (xs[0usize..lt], ps[0usize..lt], ok)
}

type AdComb = struct { ad1: f64, t1: f64, a1: f64, p1: f64, ad2: f64, t2: f64, a2: f64, p2: f64, mu: f64, sig: f64, method: usize, nsim: usize, d1: []f64, d2: []f64 }

// ad.test.combined: xs holds every observation set by set and sample by sample, sizes every sample size, setk the samples per set.
// The statistics are the printed ones (the sums use ad.test's rounded AD values, as the package does).
fn kx_ad_combined(a: *mem.Arena, g: *rng.Rng, xs: []const f64, sizes: []const usize, setk: []const usize, method0: usize, nsim0: usize) -> (AdComb, err) {
    var nsim = nsim0
    if nsim > 10000000usize { nsim = 10000000usize }
    var res = AdComb{ ad1: 0.0f64, t1: 0.0f64, a1: 0.0f64, p1: 0.0f64, ad2: 0.0f64, t2: 0.0f64, a2: 0.0f64, p2: 0.0f64, mu: 0.0f64, sig: 0.0f64, method: method0, nsim: nsim, d1: kx_empty(a), d2: kx_empty(a) }
    var ncomb = 1.0f64
    var so = 0usize
    var s = 0usize
    while s < setk.len {
        ncomb = ncomb * kx_ncomb(sizes[so..so + setk[s]])
        so += setk[s]
        s += 1usize
    }
    var method = method0
    if f64(nsim) < ncomb && method == 2usize { method = 1usize }
    let dist0 = method != 0usize
    var xo = 0usize
    so = 0usize
    var ad1 = 0.0f64
    var ad2 = 0.0f64
    var sigsum = 0.0f64
    var muc = 0.0f64
    var d1 = kx_empty(a)
    var d2 = kx_empty(a)
    s = 0usize
    while s < setk.len {
        let ss = sizes[so..so + setk[s]]
        var tot = 0usize
        var q = 0usize
        while q < ss.len {
            tot += ss[q]
            q += 1usize
        }
        let (r, e) = kx_ad_test(a, g, xs[xo..xo + tot], ss, method, dist0, nsim)
        if e != ok { ret (res, e) }
        if dist0 {
            if s == 0usize {
                d1 = r.d1
                d2 = r.d2
            } else {
                if method == 1usize {
                    var z = 0usize
                    while z < d1.len {
                        d1[z] = d1[z] + r.d1[z]
                        d2[z] = d2[z] + r.d2[z]
                        z += 1usize
                    }
                } else {
                    let (c1, ea) = kx_convvec(a, d1, r.d1)
                    let (c2, eb) = kx_convvec(a, d2, r.d2)
                    if ea != ok { ret (res, ea) }
                    if eb != ok { ret (res, eb) }
                    d1 = c1
                    d2 = c2
                }
            }
        }
        ad1 = ad1 + r.r1
        ad2 = ad2 + r.r2
        let sg = kx_round(r.sig, 5i64)
        sigsum = sigsum + sg * sg
        muc = muc + f64(setk[s] - 1usize)
        xo += tot
        so += setk[s]
        s += 1usize
    }
    var pd1 = 0.0f64
    var pd2 = 0.0f64
    if dist0 {
        var c1 = 0.0f64
        var c2 = 0.0f64
        var z = 0usize
        while z < d1.len {
            if d1[z] >= ad1 { c1 += 1.0f64 }
            if d2[z] >= ad2 { c2 += 1.0f64 }
            z += 1usize
        }
        pd1 = c1 / f64(d1.len)
        pd2 = c2 / f64(d1.len)
    }
    let sigc = math.sqrt[f64](sigsum)
    var t1 = 0.0f64 / 0.0f64
    var t2 = 0.0f64 / 0.0f64
    var a1 = 1.0f64
    var a2 = 1.0f64
    if sigc > 0.0f64 {
        t1 = (ad1 - muc) / sigc
        t2 = (ad2 - muc) / sigc
        a1 = ks.ad_pval(a, t1, muc, 1usize)
        a2 = ks.ad_pval(a, t2, muc, 2usize)
    }
    ret (AdComb{ ad1: kx_signif(ad1, 7i64), t1: kx_signif(t1, 7i64), a1: kx_round(a1, 7i64), p1: kx_round(pd1, 7i64), ad2: kx_signif(ad2, 7i64), t2: kx_signif(t2, 7i64), a2: kx_round(a2, 7i64), p2: kx_round(pd2, 7i64), mu: muc, sig: kx_round(sigc, 5i64), method: method, nsim: nsim, d1: d1, d2: d2 }, ok)
}

type QnComb = struct { stat: f64, asym: f64, p: f64, method: usize, nsim: usize, dist: []f64 }

// qn.test.combined over the same layout
fn kx_qn_combined(a: *mem.Arena, g: *rng.Rng, xs: []const f64, sizes: []const usize, setk: []const usize, test: usize, method0: usize, nsim: usize) -> (QnComb, err) {
    var res = QnComb{ stat: 0.0f64, asym: 0.0f64, p: 0.0f64, method: method0, nsim: nsim, dist: kx_empty(a) }
    var ncomb = 1.0f64
    var so = 0usize
    var s = 0usize
    while s < setk.len {
        ncomb = ncomb * kx_ncomb(sizes[so..so + setk[s]])
        so += setk[s]
        s += 1usize
    }
    var method = method0
    if f64(nsim) < ncomb && method == 2usize { method = 1usize }
    let dist0 = method != 0usize
    var xo = 0usize
    so = 0usize
    var obs = 0.0f64
    var mu = 0.0f64
    var d = kx_empty(a)
    s = 0usize
    while s < setk.len {
        let ss = sizes[so..so + setk[s]]
        var tot = 0usize
        var q = 0usize
        while q < ss.len {
            tot += ss[q]
            q += 1usize
        }
        let (r, e) = kx_qn_test(a, g, xs[xo..xo + tot], ss, test, method, dist0, nsim)
        if e != ok { ret (res, e) }
        if dist0 {
            if s == 0usize {
                d = r.dist
            } else {
                if method == 1usize {
                    var z = 0usize
                    while z < d.len {
                        d[z] = d[z] + r.dist[z]
                        z += 1usize
                    }
                } else {
                    let (c1, ea) = kx_convvec(a, d, r.dist)
                    if ea != ok { ret (res, ea) }
                    d = c1
                }
            }
        }
        obs = obs + r.stat
        mu = mu + f64(setk[s] - 1usize)
        xo += tot
        so += setk[s]
        s += 1usize
    }
    var pv = 0.0f64
    if dist0 {
        var c1 = 0.0f64
        var z = 0usize
        while z < d.len {
            if d[z] >= obs { c1 += 1.0f64 }
            z += 1usize
        }
        pv = c1 / f64(d.len)
    }
    ret (QnComb{ stat: obs, asym: 1.0f64 - nm.pchisq(obs, mu, true, false), p: pv, method: method, nsim: nsim, dist: d }, ok)
}

type C2Comb = struct { kw: f64, asym: f64, p: f64, method: usize, nsim: usize, vals: []f64, probs: []f64 }

// contingency2xt.comb: avec and bvec hold the count vectors of every table back to back, tvec their lengths
fn kx_c2_combined(a: *mem.Arena, g: *rng.Rng, avec: []const f64, bvec: []const f64, tvec: []const usize, method0: usize, dist: bool, nsim: usize) -> (C2Comb, err) {
    var res = C2Comb{ kw: 0.0f64, asym: 0.0f64, p: 0.0f64, method: method0, nsim: nsim, vals: kx_empty(a), probs: kx_empty(a) }
    var ncomb = 1.0f64
    var at = 0usize
    var s = 0usize
    var ttot = 0usize
    while s < tvec.len {
        var m = 0.0f64
        var q = 0usize
        while q < tvec[s] {
            m += avec[at + q]
            q += 1usize
        }
        ncomb = ncomb * special.choose(m + f64(tvec[s]) - 1.0f64, m)
        at += tvec[s]
        ttot += tvec[s]
        s += 1usize
    }
    var method = method0
    if f64(nsim) < ncomb && method == 2usize { method = 1usize }
    var kwobs = 0.0f64
    var vals = kx_empty(a)
    var probs = kx_empty(a)
    at = 0usize
    s = 0usize
    while s < tvec.len {
        let (r, e) = kx_contingency(a, g, avec[at..at + tvec[s]], bvec[at..at + tvec[s]], method, method != 0usize, method == 2usize, nsim)
        if e != ok { ret (res, e) }
        if method == 1usize {
            if s == 0usize {
                vals = r.vals
            } else {
                var z = 0usize
                while z < vals.len {
                    vals[z] = vals[z] + r.vals[z]
                    z += 1usize
                }
            }
        }
        if method == 2usize {
            if s == 0usize {
                vals = r.vals
                probs = r.probs
            } else {
                let (cx, cp, ec) = kx_conv(a, vals, probs, r.vals, r.probs)
                if ec != ok { ret (res, ec) }
                vals = cx
                probs = cp
            }
        }
        kwobs = kwobs + r.kw
        at += tvec[s]
        s += 1usize
    }
    var pv = 0.0f64
    if method == 1usize {
        var c1 = 0.0f64
        var z = 0usize
        while z < vals.len {
            if vals[z] >= kwobs { c1 += 1.0f64 }
            z += 1usize
        }
        pv = c1 / f64(nsim)
    }
    if method == 2usize {
        var z = 0usize
        while z < vals.len {
            if vals[z] >= kwobs { pv += probs[z] }
            z += 1usize
        }
    }
    let asym = 1.0f64 - nm.pchisq(kwobs, f64(ttot - tvec.len), true, false)
    if method == 1usize {
        // table(round(null.dist, 6)): the distinct values in order with their shares
        let nv = vals.len
        let (pz, e6) = mem.alloc[f64](a, nv + 1usize)
        if e6 != ok { ret (res, e6) }
        var z = 0usize
        while z < nv {
            vals[z] = kx_round(vals[z], 6i64)
            pz[z] = 1.0f64
            z += 1usize
        }
        kx_sort2(vals, pz)
        var u = 0usize
        z = 0usize
        while z < nv {
            if u > 0usize && vals[u - 1usize] == vals[z] {
                pz[u - 1usize] += 1.0f64
            } else {
                vals[u] = vals[z]
                pz[u] = pz[z]
                u += 1usize
            }
            z += 1usize
        }
        z = 0usize
        while z < u {
            pz[z] = pz[z] / f64(nsim)
            z += 1usize
        }
        vals = vals[0usize..u]
        probs = pz[0usize..u]
    }
    ret (C2Comb{ kw: kwobs, asym: asym, p: pv, method: method, nsim: nsim, vals: vals, probs: probs }, ok)
}
