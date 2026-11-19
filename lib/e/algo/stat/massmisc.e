// R MASS: corresp (correspondence analysis by the sign-exact SVD of R), mca (multiple correspondence analysis),
// the continued-fraction approximation behind fractions() and rational(), the numerics of truehist (breaks and bin
// heights), and hubers with the location or the scale fixed.

use e.algo.linalg.lapack_gesdd as gesdd
use e.algo.stat.classint as ci
use e.algo.stat.mass as ms
use e.algo.stat.masslqs as lq
use e.math
use e.math.dist as dist
use e.math.scale as scale
use e.mem

error BadInput

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// corresp.matrix(x, nf): x is nr by nc column-major; cor (nf), rscore (nr * nf), cscore (nc * nf) are filled.
fn corresp(a: *mem.Arena, x: []const f64, nr: usize, nc: usize, nf: usize, cor: []f64, rscore: []f64, cscore: []f64) -> err {
    var n = 0.0f64
    var i = 0usize
    while i < nr * nc {
        n += x[i]
        i += 1usize
    }
    if n == 0.0f64 { ret BadInput }
    let (dr, e1) = mem.alloc[f64](a, nr)
    let (dc, e2) = mem.alloc[f64](a, nc)
    let (m, e3) = mem.alloc[f64](a, nr * nc)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    i = 0usize
    while i < nr {
        var s = 0.0f64
        var j = 0usize
        while j < nc {
            s += x[i + nr * j] * (1.0f64 / n)
            j += 1usize
        }
        dr[i] = s
        i += 1usize
    }
    var j = 0usize
    while j < nc {
        var s = 0.0f64
        i = 0usize
        while i < nr {
            s += (1.0f64 / n) * x[i + nr * j]
            i += 1usize
        }
        dc[j] = s
        j += 1usize
    }
    i = 0usize
    while i < nr {
        if dr[i] == 0.0f64 { ret BadInput }
        i += 1usize
    }
    j = 0usize
    while j < nc {
        if dc[j] == 0.0f64 { ret BadInput }
        j += 1usize
    }
    j = 0usize
    while j < nc {
        i = 0usize
        while i < nr {
            let x1 = x[i + nr * j] / n - dr[i] * dc[j]
            m[i + nr * j] = x1 * (1.0f64 / math.sqrt[f64](dr[i])) * (1.0f64 / math.sqrt[f64](dc[j]))
            i += 1usize
        }
        j += 1usize
    }
    var k = nr
    if nc < nr { k = nc }
    let (s, e4) = mem.alloc[f64](a, k)
    let (u, e5) = mem.alloc[f64](a, nr * k)
    let (vt, e6) = mem.alloc[f64](a, k * nc)
    if e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    let se = gesdd.svd_all(a, m, nr, nc, s, u, vt)
    if se != ok { ret se }
    var f = 0usize
    while f < nf {
        cor[f] = s[f]
        i = 0usize
        while i < nr {
            rscore[i + nr * f] = u[i + nr * f] * (1.0f64 / math.sqrt[f64](dr[i]))
            i += 1usize
        }
        j = 0usize
        while j < nc {
            cscore[j + nc * f] = vt[f + k * j] * (1.0f64 / math.sqrt[f64](dc[j]))
            j += 1usize
        }
        f += 1usize
    }
    ret ok
}

// mca(df, nf): codes is the n by p column-major matrix of 0-based factor codes, levels the number of levels of each
// factor; d (nf), rs (n * nf), cs (K * nf with K the total number of levels), fs (n * nf) are filled.
fn mca(a: *mem.Arena, codes: []const f64, n: usize, p: usize, levels: []const f64, nf: usize, d: []f64, rs: []f64, cs: []f64, fs: []f64) -> err {
    var kk = 0usize
    var v = 0usize
    while v < p {
        kk += usize(levels[v])
        v += 1usize
    }
    let (g, e1) = mem.alloc[f64](a, n * kk)
    let (dc, e2) = mem.alloc[f64](a, kk)
    let (x, e3) = mem.alloc[f64](a, n * kk)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n * kk {
        g[i] = 0.0f64
        i += 1usize
    }
    var off = 0usize
    v = 0usize
    while v < p {
        i = 0usize
        while i < n {
            g[i + n * (off + usize(codes[i + n * v]))] = 1.0f64
            i += 1usize
        }
        off += usize(levels[v])
        v += 1usize
    }
    let pf = f64(p)
    var j = 0usize
    while j < kk {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += g[i + n * j]
            i += 1usize
        }
        dc[j] = s
        i = 0usize
        while i < n {
            x[i + n * j] = g[i + n * j] / math.sqrt[f64](pf * s)
            i += 1usize
        }
        j += 1usize
    }
    var k = n
    if kk < n { k = kk }
    let (s, e4) = mem.alloc[f64](a, k)
    let (u, e5) = mem.alloc[f64](a, n * k)
    let (vt, e6) = mem.alloc[f64](a, k * kk)
    if e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    let se = gesdd.svd_all(a, x, n, kk, s, u, vt)
    if se != ok { ret se }
    var f = 0usize
    while f < nf {
        let sec = f + 1usize
        d[f] = s[sec]
        i = 0usize
        while i < n {
            var t = 0.0f64
            j = 0usize
            while j < kk {
                t += x[i + n * j] * vt[sec + k * j]
                j += 1usize
            }
            rs[i + n * f] = t / pf
            fs[i + n * f] = u[i + n * sec] / (pf * s[sec])
            i += 1usize
        }
        j = 0usize
        while j < kk {
            cs[j + kk * f] = (1.0f64 / math.sqrt[f64](pf * dc[j])) * vt[sec + k * j]
            j += 1usize
        }
        f += 1usize
    }
    ret ok
}

// .rat(x, cycles, max.denominator): the numerator and denominator of the continued-fraction approximation of x
fn rat(x: f64, cycles: usize, maxden: f64) -> (f64, f64) {
    if x - x != 0.0f64 { ret (x, 1.0f64) }
    var bs: [64]f64 = zero
    var as_: [64]f64 = zero
    bs[0usize] = math.floor[f64](x)
    as_[0usize] = 1.0f64
    var r = x - bs[0usize]
    var len = 0usize
    var cols = 1usize
    var go = r > 1.0f64 / maxden
    while go {
        len += 1usize
        if len > cycles {
            go = false
        } else {
            as_[cols] = 1.0f64
            r = 1.0f64 / r
            bs[cols] = math.floor[f64](r)
            r = r - bs[cols]
            cols += 1usize
            go = r > 1.0f64 / maxden
        }
    }
    var pq1n = 1.0f64
    var pq1d = 0.0f64
    var pqn = bs[0usize]
    var pqd = 1.0f64
    var l = 1usize
    while l < cols {
        let pq0n = pq1n
        let pq0d = pq1d
        pq1n = pqn
        pq1d = pqd
        pqn = bs[l] * pq1n + as_[l] * pq0n
        pqd = bs[l] * pq1d + as_[l] * pq0d
        l += 1usize
    }
    ret (pqn, pqd)
}

// truehist's breaks and heights: mode 0 nbins = nclass.scott, 1 nclass.FD, 2 nbins given; h > 0 gives the bin width,
// x0 is the origin (NaN for -h / 1000). Returns (number of breaks); breaks gets nb values, est nb - 1 (prob = TRUE).
fn truehist(a: *mem.Arena, data: []const f64, mode: usize, nbins_in: f64, h_in: f64, x0_in: f64, breaks: []f64, est: []f64) -> (usize, err) {
    let n = data.len
    let (s, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0usize, e1) }
    var i = 0usize
    while i < n {
        s[i] = data[i]
        i += 1usize
    }
    lq.sortf(s)
    let lo = s[0usize]
    let hi = s[n - 1usize]
    var h = h_in
    if h <= 0.0f64 {
        var nb = nbins_in
        if mode == 0usize {
            var m = 0.0f64
            i = 0usize
            while i < n {
                m += data[i]
                i += 1usize
            }
            m /= f64(n)
            var v = 0.0f64
            i = 0usize
            while i < n {
                v += (data[i] - m) * (data[i] - m)
                i += 1usize
            }
            v /= f64(n - 1usize)
            let hh = 3.5f64 * math.sqrt[f64](v) * math.pow[f64](f64(n), 0.0f64 - 1.0f64 / 3.0f64)
            nb = 1.0f64
            if hh > 0.0f64 { nb = math.ceil[f64]((hi - lo) / hh) }
            if nb < 1.0f64 { nb = 1.0f64 }
        } else if mode == 1usize {
            let (sg, e2) = mem.alloc[f64](a, n)
            if e2 != ok { ret (0usize, e2) }
            i = 0usize
            while i < n {
                sg[i] = signif5(data[i])
                i += 1usize
            }
            lq.sortf(sg)
            var hh = 2.0f64 * (ci.quantile_r(sg, 0.75f64, 7u8) - ci.quantile_r(sg, 0.25f64, 7u8))
            var al = 0.25f64
            while hh == 0.0f64 && al / 2.0f64 >= 1.0f64 / 512.0f64 {
                al = al / 2.0f64
                hh = (ci.quantile_r(sg, 1.0f64 - al, 7u8) - ci.quantile_r(sg, al, 7u8)) / (1.0f64 - 2.0f64 * al)
            }
            if hh == 0.0f64 {
                var m = 0.0f64
                i = 0usize
                while i < n {
                    m += data[i]
                    i += 1usize
                }
                m /= f64(n)
                var v = 0.0f64
                i = 0usize
                while i < n {
                    v += (data[i] - m) * (data[i] - m)
                    i += 1usize
                }
                hh = 3.5f64 * math.sqrt[f64](v / f64(n - 1usize))
            }
            nb = 1.0f64
            if hh > 0.0f64 { nb = math.ceil[f64]((hi - lo) / hh * math.pow[f64](f64(n), 1.0f64 / 3.0f64)) }
        }
        let (pb, pe) = scale.pretty(a, lo, hi, i64(nb))
        if pe != ok { ret (0usize, pe) }
        h = pb[1usize] - pb[0usize]
    }
    var x0 = x0_in
    if x0 != x0 { x0 = 0.0f64 - h / 1000.0f64 }
    let first = math.floor[f64]((lo - x0) / h)
    let last = math.ceil[f64]((hi - x0) / h)
    let nbk = usize(last - first) + 1usize
    var k = 0usize
    while k < nbk {
        breaks[k] = x0 + h * (first + f64(k))
        k += 1usize
    }
    k = 0usize
    while k + 1usize < nbk {
        est[k] = 0.0f64
        k += 1usize
    }
    // cut(data, breaks, include.lowest = TRUE): (b[k], b[k + 1]] and the first bin closed on the left
    i = 0usize
    while i < n {
        var kk = 0usize
        while kk + 1usize < nbk {
            let hit = (data[i] > breaks[kk] && data[i] <= breaks[kk + 1usize]) || (kk == 0usize && data[i] == breaks[0usize])
            if hit {
                est[kk] += 1.0f64
                kk = nbk
            } else { kk += 1usize }
        }
        i += 1usize
    }
    k = 0usize
    while k + 1usize < nbk {
        est[k] = est[k] / ((breaks[k + 1usize] - breaks[k]) * f64(n))
        k += 1usize
    }
    ret (nbk, ok)
}

// signif(x, 5)
fn signif5(x: f64) -> f64 {
    if x == 0.0f64 { ret 0.0f64 }
    let e = math.floor[f64](math.log10[f64](math.abs[f64](x)))
    let p = 4.0f64 - e
    let sc = math.pow[f64](10.0f64, math.abs[f64](p))
    if p >= 0.0f64 { ret math.round[f64](x * sc) / sc }
    ret math.round[f64](x / sc) * sc
}

// hubers(y, k, mu, s, initmu, tol): mu_given / s_given NaN when missing; initmu NaN for median(y)
fn hubers_full(a: *mem.Arena, y: []const f64, k: f64, mu_given: f64, s_given: f64, initmu: f64, tol: f64) -> (f64, f64) {
    let n = f64(y.len)
    let mmu = mu_given != mu_given
    let ms_ = s_given != s_given
    var mu0 = mu_given
    var mu1 = mu_given
    var n1 = n
    if mmu {
        mu0 = initmu
        if mu0 != mu0 { mu0 = ms.median_of(a, y) }
        n1 = n - 1.0f64
    }
    var s0 = s_given
    var s1 = s_given
    if ms_ {
        s0 = ms.mad(a, y)
        if s0 == 0.0f64 { ret (mu0, 0.0f64) }
    }
    let th = 2.0f64 * dist.pnorm(k, 0.0f64, 1.0f64, true, false) - 1.0f64
    let beta = th + k * k * (1.0f64 - th) - 2.0f64 * k * dist.dnorm(k, 0.0f64, 1.0f64, false)
    var it = 0usize
    var done = false
    while it < 30usize && !done {
        var sum = 0.0f64
        var i = 0usize
        while i < y.len {
            sum += ms.clamp(y[i], mu0 - k * s0, mu0 + k * s0)
            i += 1usize
        }
        if mmu { mu1 = sum / n }
        if ms_ {
            var ss = 0.0f64
            i = 0usize
            while i < y.len {
                let yy = ms.clamp(y[i], mu0 - k * s0, mu0 + k * s0)
                ss += (yy - mu1) * (yy - mu1)
                i += 1usize
            }
            s1 = math.sqrt[f64](ss / n1 / beta)
        }
        if math.abs[f64](mu0 - mu1) < tol * s0 && math.abs[f64](s0 - s1) < tol * s0 {
            done = true
        } else {
            mu0 = mu1
            s0 = s1
            it += 1usize
        }
    }
    ret (mu0, s0)
}
