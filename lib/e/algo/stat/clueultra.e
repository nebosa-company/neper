// R clue, cl_consensus of hierarchies by least squares ("euclidean", also "cophenetic") and least absolute deviation ("manhattan"): an ultrametric d minimising
// sum_b w_b |u_b - d|^2 resp. sum_b w_b |u_b - d|_1 over the lower-half vectors, by clue's sumt (a penalty for violating ultrametricity, the weight times ten until the iterate settles) with
// optim's conjugate gradients "CG" (R's cgmin as in cluegv3), the start "random shaking" x + rnorm(sd = sd(x) / sqrt(3)) of the weighted mean resp. weighted median of the ultrametrics,
// then .ultrametrify (the single linkage ultrametric, the largest one below d). The ultrametrics u_b are lower-half vectors (R's dist order: column by column, rows below the diagonal).
// R's sum() and rowSums() accumulate in a long double; cluegv3's Acc reproduces that.

use e.algo.rand.r as rr
use e.algo.stat.cluegv3 as gv
use e.math
use e.math.nmath as nm
use e.mem
use e.str
use e.io

error Malformed

type Prob = struct {
    n: usize,
    np: usize,
    kind: usize,
    bn: usize,
    wq: f64,
    x: []const f64,
    us: []const f64,
    wb: []const f64,
    rho: f64,
    dm: []f64,
    gm: []f64,
    gl: []f64,
}

fn absf(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn negpart(x: f64) -> f64 {
    if x < 0.0f64 { ret x }
    ret 0.0f64
}

// the symmetric matrix of a lower-half vector, row-major, into p.dm
fn sqm(p: *Prob, d: []const f64) {
    let n = p.n
    var q = 0usize
    var c = 0usize
    while c < n {
        p.dm[c * n + c] = 0.0f64
        var r = c + 1usize
        while r < n {
            p.dm[r * n + c] = d[q]
            p.dm[c * n + r] = d[q]
            q += 1usize
            r += 1usize
        }
        c += 1usize
    }
}

// deviation_from_ultrametricity: the sum of squared (or the largest absolute) deviations over the triples
fn nonult(p: *Prob, d: []const f64, mx: bool) -> f64 {
    sqm(p, d)
    let n = p.n
    var s = 0.0f64
    var i = 0usize
    while i + 2usize < n {
        var j = i + 1usize
        while j + 1usize < n {
            let aa = p.dm[i * n + j]
            var k = j + 1usize
            while k < n {
                let bb = p.dm[i * n + k]
                let cc = p.dm[j * n + k]
                var delta = 0.0f64
                if aa <= bb && aa <= cc {
                    delta = cc - bb
                } else {
                    if bb <= cc {
                        delta = aa - cc
                    } else {
                        delta = bb - aa
                    }
                }
                if mx {
                    if absf(delta) > s { s = absf(delta) }
                } else {
                    s += delta * delta
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn pval(p: *Prob, d: []const f64) -> f64 {
    let v = nonult(p, d, false)
    var acc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var q = 0usize
    while q < p.np {
        let t = negpart(d[q])
        gv.acc_add(&acc, t * t)
        q += 1usize
    }
    ret v + gv.acc_val(&acc)
}

fn lval(p: *Prob, d: []const f64) -> f64 {
    var acc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var q = 0usize
    if p.kind == 0usize {
        while q < p.np {
            let t = p.x[q] - d[q]
            gv.acc_add(&acc, p.wq * (t * t))
            q += 1usize
        }
        ret gv.acc_val(&acc)
    }
    var b = 0usize
    while b < p.bn {
        var inner = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
        q = 0usize
        while q < p.np {
            gv.acc_add(&inner, absf(p.us[b * p.np + q] - d[q]))
            q += 1usize
        }
        gv.acc_add(&acc, p.wb[b] * gv.acc_val(&inner))
        b += 1usize
    }
    ret gv.acc_val(&acc)
}

fn phi(p: *Prob, d: []const f64) -> f64 { ret lval(p, d) + p.rho * pval(p, d) }

fn gphi(p: *Prob, d: []const f64, g: []f64) {
    let n = p.n
    let np = p.np
    var q = 0usize
    if p.kind == 0usize {
        while q < np {
            p.gl[q] = 2.0f64 * p.wq * (d[q] - p.x[q])
            q += 1usize
        }
    } else {
        while q < np {
            var acc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
            var b = 0usize
            while b < p.bn {
                let t = d[q] - p.us[b * np + q]
                var sg = 0.0f64
                if t > 0.0f64 { sg = 1.0f64 }
                if t < 0.0f64 { sg = 0.0f64 - 1.0f64 }
                gv.acc_add(&acc, sg * p.wb[b])
                b += 1usize
            }
            p.gl[q] = gv.acc_val(&acc)
            q += 1usize
        }
    }
    sqm(p, d)
    var i = 0usize
    while i < n * n {
        p.gm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i + 2usize < n {
        var j = i + 1usize
        while j + 1usize < n {
            let aa = p.dm[i * n + j]
            var k = j + 1usize
            while k < n {
                let bb = p.dm[i * n + k]
                let cc = p.dm[j * n + k]
                if aa <= bb && aa <= cc {
                    let delta = 2.0f64 * (bb - cc)
                    p.gm[i * n + k] += delta
                    p.gm[j * n + k] -= delta
                } else {
                    if bb <= cc {
                        let delta = 2.0f64 * (cc - aa)
                        p.gm[j * n + k] += delta
                        p.gm[i * n + j] -= delta
                    } else {
                        let delta = 2.0f64 * (aa - bb)
                        p.gm[i * n + j] += delta
                        p.gm[i * n + k] -= delta
                    }
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    var nacc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    q = 0usize
    while q < np {
        gv.acc_add(&nacc, negpart(d[q]))
        q += 1usize
    }
    let sneg = 2.0f64 * gv.acc_val(&nacc)
    q = 0usize
    var c = 0usize
    while c < n {
        var r = c + 1usize
        while r < n {
            g[q] = p.gl[q] + p.rho * (p.gm[c * n + r] + sneg)
            q += 1usize
            r += 1usize
        }
        c += 1usize
    }
}

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// optim(x, fn, gr, method = "CG") with the defaults, as cluegv3.cgmin
fn cgmin(a: *mem.Arena, p: *Prob, x: []f64) -> err {
    let n = p.np
    let (bvec, e0) = mem.alloc[f64](a, n)
    let (c, e1) = mem.alloc[f64](a, n)
    let (g, e2) = mem.alloc[f64](a, n)
    let (t, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let intol = 1.4901161193847656e-8f64
    let maxit = 100usize
    let stepredn = 0.2f64
    let acctol = 0.0001f64
    let reltest = 10.0f64
    let setstep = 1.7f64
    var i = 0usize
    while i < n {
        bvec[i] = x[i]
        i += 1usize
    }
    let tol = intol * f64(n) * math.sqrt[f64](intol)
    var f = phi(p, bvec)
    if !finite(f) { ret Malformed }
    var fmin = f
    var gradcount = 0usize
    var cycle = 0usize
    var count = 0usize
    var g1 = 0.0f64
    var steplength = 1.0f64
    var again = true
    while again {
        i = 0usize
        while i < n {
            t[i] = 0.0f64
            c[i] = 0.0f64
            i += 1usize
        }
        cycle = 0usize
        var oldstep = 1.0f64
        count = 0usize
        var inner = true
        while inner {
            cycle += 1usize
            gradcount += 1usize
            if gradcount > maxit { ret ok }
            gphi(p, bvec, g)
            g1 = 0.0f64
            var g2 = 0.0f64
            i = 0usize
            while i < n {
                x[i] = bvec[i]
                g1 += g[i] * g[i]
                g2 += c[i] * c[i]
                c[i] = g[i]
                i += 1usize
            }
            if g1 > tol {
                var g3 = 1.0f64
                if g2 > 0.0f64 { g3 = g1 / g2 }
                var gradproj = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = t[i] * g3 - g[i]
                    gradproj += t[i] * g[i]
                    i += 1usize
                }
                steplength = oldstep
                var accpoint = false
                var search = true
                while search {
                    count = 0usize
                    i = 0usize
                    while i < n {
                        bvec[i] = x[i] + steplength * t[i]
                        if reltest + x[i] == reltest + bvec[i] { count += 1usize }
                        i += 1usize
                    }
                    if count < n {
                        f = phi(p, bvec)
                        accpoint = finite(f) && f <= fmin + gradproj * steplength * acctol
                        if !accpoint {
                            steplength = steplength * stepredn
                        } else {
                            fmin = f
                        }
                    }
                    if count == n || accpoint { search = false }
                }
                if count < n {
                    var newstep = 2.0f64 * (f - fmin - gradproj * steplength)
                    if newstep > 0.0f64 {
                        newstep = 0.0f64 - gradproj * steplength * steplength / newstep
                        i = 0usize
                        while i < n {
                            bvec[i] = x[i] + newstep * t[i]
                            i += 1usize
                        }
                        fmin = f
                        f = phi(p, bvec)
                        if f < fmin {
                            fmin = f
                        } else {
                            i = 0usize
                            while i < n {
                                bvec[i] = x[i] + steplength * t[i]
                                i += 1usize
                            }
                        }
                    }
                }
            }
            oldstep = setstep * steplength
            if oldstep > 1.0f64 { oldstep = 1.0f64 }
            if !(count != n && g1 > tol && cycle != n) { inner = false }
        }
        if !(cycle != 1usize || (count != n && g1 > tol)) { again = false }
    }
    ret ok
}

// clue's sumt from one start: x holds the start and receives the minimiser; the answer is the penalised value at the stopping point
fn sumt_run(a: *mem.Arena, p: *Prob, x: []f64) -> (f64, err) {
    let n = p.np
    let (xold, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (0.0f64, mem.Full) }
    let eps = 1.4901161193847656e-8f64
    var l0 = lval(p, x)
    if l0 < 0.00001f64 { l0 = 0.00001f64 }
    var p0 = pval(p, x)
    if p0 < 0.00001f64 { p0 = 0.00001f64 }
    p.rho = l0 / p0
    var go = true
    while go {
        var i = 0usize
        while i < n {
            xold[i] = x[i]
            i += 1usize
        }
        let e = cgmin(a, p, x)
        if e != ok { ret (0.0f64, e) }
        var md = 0.0f64
        i = 0usize
        while i < n {
            let d = absf(xold[i] - x[i])
            if d > md { md = d }
            i += 1usize
        }
        if md < eps { go = false } else { p.rho = 10.0f64 * p.rho }
    }
    ret (phi(p, x), ok)
}

// cluegv3.acc_add for an addend held as xh + xl (a long double): one rounding of the whole sum
fn acc_add_ld(s: *gv.Acc, xh: f64, xl: f64) {
    let t = s.hi + xh
    let bb = t - s.hi
    let er = (s.hi - (t - bb)) + (xh - bb)
    let lo0 = (s.lo + xl) + er
    let h2 = t + lo0
    let l2 = lo0 - (h2 - t)
    if h2 == 0.0f64 || l2 == 0.0f64 {
        s.hi = h2
        s.lo = l2
        ret
    }
    let (_, ex) = nm.frexp(h2)
    let q = nm.ldexp(1.0f64, ex - 64i64)
    let kq = l2 / q
    var fl = math.floor[f64](kq)
    let fr = kq - fl
    if fr > 0.5f64 { fl += 1.0f64 }
    if fr == 0.5f64 {
        let half = math.floor[f64](fl / 2.0f64) * 2.0f64
        if half != fl { fl += 1.0f64 }
    }
    s.hi = h2
    s.lo = fl * q
}

// (hi + lo) / d as a long double
fn ldiv(s: *const gv.Acc, d: f64) -> gv.Acc {
    let q = s.hi / d
    let rem = math.fma[f64](0.0f64 - q, d, s.hi) + s.lo
    var r = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    gv.acc_add(&r, q)
    gv.acc_add(&r, rem / d)
    ret r
}

// sd(x) / sqrt(3)
fn shake_sd(x: []const f64) -> f64 {
    let n = x.len
    var acc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < n {
        gv.acc_add(&acc, x[i])
        i += 1usize
    }
    // R's MEAN: tmp = sum / n, then tmp += sum(x - tmp) / n, all long double
    var tmp = ldiv(&acc, f64(n))
    var a2 = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    i = 0usize
    while i < n {
        var df = gv.Acc { hi: x[i], lo: 0.0f64 }
        acc_add_ld(&df, 0.0f64 - tmp.hi, 0.0f64 - tmp.lo)
        acc_add_ld(&a2, df.hi, df.lo)
        i += 1usize
    }
    let corr = ldiv(&a2, f64(n))
    acc_add_ld(&tmp, corr.hi, corr.lo)
    let mean = gv.acc_val(&tmp)
    // R's cov: sum += (x - xm) * (x - xm) with every operand and product a long double (64-bit mantissa)
    var a3 = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    i = 0usize
    while i < n {
        let s = x[i] - mean
        let bb = s - x[i]
        let e = (x[i] - (s - bb)) + (0.0f64 - mean - bb)
        let ph = s * s
        let pl = math.fma[f64](s, s, 0.0f64 - ph) + 2.0f64 * s * e
        var pr = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
        gv.acc_add(&pr, ph)
        gv.acc_add(&pr, pl)
        acc_add_ld(&a3, pr.hi, pr.lo)
        i += 1usize
    }
    // (hi + lo) / (n - 1) rounded once, as R's long double quotient
    let dn = f64(n - 1usize)
    let q = a3.hi / dn
    let rem = math.fma[f64](0.0f64 - q, dn, a3.hi) + a3.lo
    let vr = q + rem / dn
    ret math.sqrt[f64](vr) / math.sqrt[f64](3.0f64)
}

// weighted_median(v, w) for w summing to one: the first minimiser of x (cumsum(w) - 0.5) - cumsum(w x) over the sorted values
fn wmedian(a: *mem.Arena, v: []const f64, w: []const f64) -> (f64, err) {
    let m = v.len
    let (ord, e0) = mem.alloc[usize](a, m)
    if e0 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < m {
        ord[i] = i
        i += 1usize
    }
    // stable insertion sort by value
    i = 1usize
    while i < m {
        let key = ord[i]
        var j = i
        while j > 0usize && v[ord[j - 1usize]] > v[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var ws = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    i = 0usize
    while i < m {
        gv.acc_add(&ws, w[i])
        i += 1usize
    }
    let wsum = gv.acc_val(&ws)
    var c1 = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var c2 = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var best = 0.0f64
    var bestv = 0.0f64
    i = 0usize
    while i < m {
        let xv = v[ord[i]]
        let wv = w[ord[i]] / wsum
        gv.acc_add(&c1, wv)
        gv.acc_add(&c2, wv * xv)
        let val = xv * (gv.acc_val(&c1) - 0.5f64) - gv.acc_val(&c2)
        if i == 0usize || val < bestv {
            bestv = val
            best = xv
        }
        i += 1usize
    }
    ret (best, ok)
}

// the single linkage ultrametric of the lower-half vector d (n by n row-major into out): the smallest largest step over the paths between two objects
fn ultrametrify(a: *mem.Arena, d: []const f64, n: usize, out: []f64) {
    var q = 0usize
    var c = 0usize
    while c < n {
        out[c * n + c] = 0.0f64
        var r = c + 1usize
        while r < n {
            out[r * n + c] = d[q]
            out[c * n + r] = d[q]
            q += 1usize
            r += 1usize
        }
        c += 1usize
    }
    var k = 0usize
    while k < n {
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                var via = out[i * n + k]
                if out[k * n + j] > via { via = out[k * n + j] }
                if via < out[i * n + j] { out[i * n + j] = via }
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
}

// cl_consensus(trees, method = "euclidean" (kind 0) or "manhattan" (kind 1), weights = w, control = list(nruns = nruns)) after set.seed: us are the bn ultrametrics as lower-half
// vectors, out receives the consensus ultrametric (n by n, row-major); the answer is its objective value (the meta objval)
fn consensus_ultra(a: *mem.Arena, g: *rr.Rng, us: []const f64, w: []const f64, bn: usize, n: usize, kind: usize, nruns: usize, stage: usize, out: []f64) -> (f64, err) {
    let np = n * (n - 1usize) / 2usize
    let (dm, e0) = mem.alloc[f64](a, n * n)
    let (gm, e1) = mem.alloc[f64](a, n * n)
    let (gl, e2) = mem.alloc[f64](a, np)
    let (wb, e3) = mem.alloc[f64](a, bn)
    let (xm, e4) = mem.alloc[f64](a, np)
    let (x, e5) = mem.alloc[f64](a, np)
    let (best, e6) = mem.alloc[f64](a, np)
    let (col, e7) = mem.alloc[f64](a, bn)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, mem.Full) }
    var wacc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
    var b = 0usize
    while b < bn {
        gv.acc_add(&wacc, w[b])
        b += 1usize
    }
    let wsum = gv.acc_val(&wacc)
    b = 0usize
    while b < bn {
        wb[b] = w[b] / wsum
        b += 1usize
    }
    var p = Prob { n: n, np: np, kind: kind, bn: bn, wq: 1.0f64 / f64(np), x: xm, us: us, wb: wb, rho: 1.0f64, dm: dm, gm: gm, gl: gl }
    var q = 0usize
    if kind == 0usize {
        // the weighted mean of the ultrametrics
        while q < np {
            var acc = gv.Acc { hi: 0.0f64, lo: 0.0f64 }
            b = 0usize
            while b < bn {
                gv.acc_add(&acc, us[b * np + q] * wb[b])
                b += 1usize
            }
            xm[q] = gv.acc_val(&acc)
            q += 1usize
        }
        // ls_fit_ultrametric returns an ultrametric argument as it is
        if nonult(&p, xm, true) == 0.0f64 {
            ultrametrify(a, xm, n, out)
            ret (0.0f64, ok)
        }
    } else {
        while q < np {
            b = 0usize
            while b < bn {
                col[b] = us[b * np + q]
                b += 1usize
            }
            let (mv, em) = wmedian(a, col, wb)
            if em != ok { ret (0.0f64, em) }
            xm[q] = mv
            q += 1usize
        }
    }
    let sdv = shake_sd(xm)
    if stage == 1usize {
        q = 0usize
        while q < np {
            out[q] = xm[q]
            q += 1usize
        }
        out[np] = sdv
        ret (0.0f64, ok)
    }
    // R draws every start before the first run (replicate)
    let (starts, e8) = mem.alloc[f64](a, nruns * np)
    if e8 != ok { ret (0.0f64, mem.Full) }
    var run = 0usize
    while run < nruns {
        q = 0usize
        while q < np {
            starts[run * np + q] = xm[q] + rr.rnorm(g, 0.0f64, sdv)
            q += 1usize
        }
        run += 1usize
    }
    if stage == 100usize {
        q = 0usize
        while q < np {
            x[q] = starts[q]
            q += 1usize
        }
        var l0 = lval(&p, x)
        if l0 < 0.00001f64 { l0 = 0.00001f64 }
        var p0 = pval(&p, x)
        if p0 < 0.00001f64 { p0 = 0.00001f64 }
        p.rho = l0 / p0
        gphi(&p, x, best)
        q = 0usize
        while q < np {
            out[q] = best[q]
            q += 1usize
        }
        out[np] = phi(&p, x)
        out[np + 1usize] = p.rho
        out[np + 2usize] = lval(&p, x)
        out[np + 3usize] = pval(&p, x)
        ret (0.0f64, ok)
    }
    if stage >= 2usize {
        q = 0usize
        while q < np {
            x[q] = starts[q]
            q += 1usize
        }
        var l0 = lval(&p, x)
        if l0 < 0.00001f64 { l0 = 0.00001f64 }
        var p0 = pval(&p, x)
        if p0 < 0.00001f64 { p0 = 0.00001f64 }
        p.rho = l0 / p0
        var calls = 1usize
        while calls < stage {
            let (xo, ex) = mem.alloc[f64](a, np)
            if ex != ok { ret (0.0f64, ex) }
            q = 0usize
            while q < np {
                xo[q] = x[q]
                q += 1usize
            }
            let ec = cgmin(a, &p, x)
            if ec != ok { ret (0.0f64, ec) }
            var mxd = 0.0f64
            q = 0usize
            while q < np {
                if absf(xo[q] - x[q]) > mxd { mxd = absf(xo[q] - x[q]) }
                q += 1usize
            }
            if mxd < 1.4901161193847656e-8f64 { calls = stage } else { p.rho = 10.0f64 * p.rho }
            calls += 1usize
        }
        q = 0usize
        while q < np {
            out[q] = x[q]
            q += 1usize
        }
        ret (0.0f64, ok)
    }
    var vbest = 0.0f64
    run = 0usize
    while run < nruns {
        q = 0usize
        while q < np {
            x[q] = starts[run * np + q]
            q += 1usize
        }
        let (v, e) = sumt_run(a, &p, x)
        if e != ok { ret (0.0f64, e) }
        if run == 0usize || v < vbest {
            vbest = v
            q = 0usize
            while q < np {
                best[q] = x[q]
                q += 1usize
            }
        }
        run += 1usize
    }
    ultrametrify(a, best, n, out)
    // the objective at the ultrametric, as a lower-half vector
    q = 0usize
    var c = 0usize
    while c < n {
        var r = c + 1usize
        while r < n {
            x[q] = out[r * n + c]
            q += 1usize
            r += 1usize
        }
        c += 1usize
    }
    p.rho = 0.0f64
    ret (lval(&p, x), ok)
}
