// R tseries: `bds.test` (the Brock-Dechert-Scheinkman statistic for embedding dimensions 2 to m and each eps, the counting
// of LeBaron's bit grid done as the pair counts it equals) and `tsbootstrap` (the stationary and the block resampling of
// boot.c on R's stream, with the bootstrap of a statistic of the series: replicates, bias and standard error).
//
// Not here: the other tseries tests and portfolio.optim.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.olsfit as ols
use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn ipow(x: f64, m: usize) -> f64 {
    var y = 1.0f64
    var j = 0usize
    while j < m {
        y *= x
        j += 1usize
    }
    ret y
}

// the normalised statistic of cstat(c, cm, k, m, n)
fn cstat(c: f64, cm: f64, k: f64, m: usize, n: usize) -> f64 {
    var sigma = 0.0f64
    var j = 1usize
    while j + 1usize <= m {
        sigma += 2.0f64 * ipow(k, m - j) * ipow(c, 2usize * j)
        j += 1usize
    }
    let mm = f64(m)
    sigma += ipow(k, m) + (mm - 1.0f64) * (mm - 1.0f64) * ipow(c, 2usize * m) - mm * mm * k * ipow(c, 2usize * m - 2usize)
    sigma *= 4.0f64
    let std = math.sqrt[f64](sigma / f64(n))
    ret (cm - ipow(c, m)) / std
}

// bds.test(x, m, eps): stat[(d - 2)] for d = 2 .. m, one eps
fn bds_stat(a: *mem.Arena, x: []const f64, m: usize, eps: f64, out: []f64) -> err {
    let n = x.len
    let nobs = n - (m - 1usize)
    let nd = f64(nobs)
    // the close pairs among the first nobs points in the first dimension: d_i the number of neighbours
    let (dcount, e1) = mem.alloc[f64](a, nobs)
    if e1 != ok { ret e1 }
    var sum_d = 0.0f64
    var sum_d2 = 0.0f64
    var i = 0usize
    while i < nobs {
        var cnt = 0.0f64
        var j = 0usize
        while j < nobs {
            if j != i {
                var df = x[i] - x[j]
                if df < 0.0f64 { df = 0.0f64 - df }
                if df <= eps { cnt += 1.0f64 }
            }
            j += 1usize
        }
        sum_d += cnt
        sum_d2 += cnt * cnt
        i += 1usize
    }
    let k = (sum_d2 - sum_d) / (nd * (nd - 1.0f64) * (nd - 2.0f64))
    let c1 = sum_d / (nd * (nd - 1.0f64))
    var d = 2usize
    while d <= m {
        var count = 0.0f64
        i = 0usize
        while i < nobs {
            var j = i + 1usize
            while j < nobs {
                var close = true
                var t = 0usize
                while t < d && close {
                    var df = x[i + t] - x[j + t]
                    if df < 0.0f64 { df = 0.0f64 - df }
                    if df > eps { close = false }
                    t += 1usize
                }
                if close { count += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        let cd = 2.0f64 * count / (nd * (nd - 1.0f64))
        out[d - 2usize] = cstat(c1, cd, k, d, nobs)
        d += 1usize
    }
    ret ok
}

fn wrap(i: i64, n: i64) -> i64 {
    if i < 1i64 { ret i % n + n }
    if i > n { ret (i - 1i64) % n + 1i64 }
    ret i
}

fn disuni(g: *rng.Rng, n: i64) -> i64 { ret i64(rng.unif(g) * f64(n) + 1.0f64) }

fn geodev(g: *rng.Rng, p: f64) -> i64 {
    let b = (0.0f64 - 1.0f64) / math.log[f64](1.0f64 - p)
    let y = rng.exp_unit(g)
    ret i64(b * y)
}

// boot.sample(x, b, type): type 0 the stationary bootstrap with the geometric parameter b, 1 the blockwise bootstrap of length b
fn boot_sample(g: *rng.Rng, x: []const f64, b: f64, qtype: u8, out: []f64) {
    let n = i64(x.len)
    var i = 1i64
    if qtype == 0u8 {
        while i <= n {
            let bi = disuni(g, n)
            let l = geodev(g, b)
            var j = 0i64
            while j < l && i <= n {
                out[usize(i - 1i64)] = x[usize(wrap(bi + j, n) - 1i64)]
                i += 1i64
                j += 1i64
            }
        }
    } else {
        let l = i64(b)
        while i <= n {
            let bi = disuni(g, n - l + 1i64)
            var j = 0i64
            while j < l && i <= n {
                out[usize(i - 1i64)] = x[usize(bi + j - 1i64)]
                i += 1i64
                j += 1i64
            }
        }
    }
}

// ---- the neural network tests: terasvirta.test and white.test (x is n by nin column-major, y has n values)

fn scaled(a: *mem.Arena, v: []const f64, n: usize, cols: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, n * cols)
    if e != ok { ret (o, e) }
    var c = 0usize
    while c < cols {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += v[c * n + i]
            i += 1usize
        }
        m = m / f64(n)
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += (v[c * n + i] - m) * (v[c * n + i] - m)
            i += 1usize
        }
        let sd = math.sqrt[f64](s / f64(n - 1usize))
        i = 0usize
        while i < n {
            o[c * n + i] = (v[c * n + i] - m) / sd
            i += 1usize
        }
        c += 1usize
    }
    ret (o, ok)
}

// regress u on the columns of cols (n by p, plus an intercept) and answer the residual sum of squares
fn rss_of(a: *mem.Arena, cols: []const f64, n: usize, p: usize, u: []const f64) -> (f64, err) {
    let (d, e) = mem.alloc[f64](a, n * (p + 1usize))
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        d[n + i] = cols[i]
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, n, p + 1usize, u)
    if oe != ok { ret (0.0f64, oe) }
    ret (o.rss, ok)
}

// answers (statistic, df1, df2) for type Chisq (df2 is 0) or F
fn nn_finish(ssr0: f64, ssr: f64, n: usize, nin: usize, mdf: usize, ftype: bool) -> (f64, f64, f64) {
    let t = f64(n)
    if !ftype { ret (t * math.log[f64](ssr0 / ssr), f64(mdf), 0.0f64) }
    let d2 = t - f64(mdf) - f64(nin)
    ret (((ssr0 - ssr) / f64(mdf)) / (ssr / d2), f64(mdf), d2)
}

// terasvirta.test(x, y, type, scale)
fn terasvirta(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, nin: usize, ftype: bool, scale: bool) -> (f64, f64, f64, err) {
    var x = x0
    var y = y0
    if scale {
        let (xs, e1) = scaled(a, x0, n, nin)
        let (ys, e2) = scaled(a, y0, n, 1usize)
        if e1 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
        if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
        x = xs
        y = ys
    }
    let (r0, re0) = olsres(a, x, n, nin, y)
    if re0 != ok { ret (0.0f64, 0.0f64, 0.0f64, re0) }
    let ssr0 = r0.rss
    // the squares and the cubes of the regressors
    var m = 0usize
    var i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            m += 1usize
            var k = j
            while k < nin {
                m += 1usize
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let p = nin + m
    let (cols, ce) = mem.alloc[f64](a, n * p)
    if ce != ok { ret (0.0f64, 0.0f64, 0.0f64, ce) }
    var c = 0usize
    while c < nin * n {
        cols[c] = x[c]
        c += 1usize
    }
    var at = nin
    i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            var t = 0usize
            while t < n {
                cols[at * n + t] = x[i * n + t] * x[j * n + t]
                t += 1usize
            }
            at += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            var k = j
            while k < nin {
                var t = 0usize
                while t < n {
                    cols[at * n + t] = x[i * n + t] * x[j * n + t] * x[k * n + t]
                    t += 1usize
                }
                at += 1usize
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let (ssr, e2) = rss_of(a, cols, n, p, r0.resid)
    if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
    // m counts the squares and the cubes: nin (nin + 1) / 2 + nin (nin + 1) (nin + 2) / 6
    let (st, d1, d2) = nn_finish(ssr0, ssr, n, nin, nin * (nin + 1usize) / 2usize + nin * (nin + 1usize) * (nin + 2usize) / 6usize, ftype)
    ret (st, d1, d2, ok)
}

fn olsres(a: *mem.Arena, x: []const f64, n: usize, nin: usize, y: []const f64) -> (ols.Ols, err) {
    let (d, e) = mem.alloc[f64](a, n * (nin + 1usize))
    var none: ols.Ols = zero
    if e != ok { ret (none, e) }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * nin {
        d[n + i] = x[i]
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, n, nin + 1usize, y)
    ret (o, oe)
}

// white.test(x, y, qstar, q, range, type, scale): the random weights are runif on R's stream
fn white(a: *mem.Arena, g: *rng.Rng, x0: []const f64, y0: []const f64, n: usize, nin: usize, qstar: usize, q: usize, range: f64, ftype: bool, scale: bool) -> (f64, f64, f64, err) {
    var x = x0
    var y = y0
    if scale {
        let (xs, e1) = scaled(a, x0, n, nin)
        let (ys, e2) = scaled(a, y0, n, 1usize)
        if e1 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
        if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
        x = xs
        y = ys
    }
    let (r0, re0) = olsres(a, x, n, nin, y)
    if re0 != ok { ret (0.0f64, 0.0f64, 0.0f64, re0) }
    let ssr0 = r0.rss
    let mx = range / 2.0f64
    let (gam, ge) = mem.alloc[f64](a, (nin + 1usize) * q)
    if ge != ok { ret (0.0f64, 0.0f64, 0.0f64, ge) }
    var i = 0usize
    while i < (nin + 1usize) * q {
        gam[i] = 0.0f64 - mx + (2.0f64 * mx) * rng.unif(g)
        i += 1usize
    }
    let (ph, pe) = mem.alloc[f64](a, n * q)
    if pe != ok { ret (0.0f64, 0.0f64, 0.0f64, pe) }
    var c = 0usize
    while c < q {
        i = 0usize
        while i < n {
            var s = gam[c * (nin + 1usize)]
            var j = 0usize
            while j < nin {
                s += x[j * n + i] * gam[c * (nin + 1usize) + j + 1usize]
                j += 1usize
            }
            ph[c * n + i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s))
            i += 1usize
        }
        c += 1usize
    }
    // prcomp(phantom, scale. = TRUE): the centred, unit-variance columns and their right singular vectors
    let (z, ze) = scaled(a, ph, n, q)
    if ze != ok { ret (0.0f64, 0.0f64, 0.0f64, ze) }
    let (sv, se) = decomp.svd(a, z, n, q)
    if se != ok { ret (0.0f64, 0.0f64, 0.0f64, se) }
    let (pcs, pce) = mem.alloc[f64](a, n * qstar)
    if pce != ok { ret (0.0f64, 0.0f64, 0.0f64, pce) }
    var j = 0usize
    while j < qstar {
        i = 0usize
        while i < n {
            pcs[j * n + i] = sv.u[(j + 1usize) * n + i] * sv.d[j + 1usize]
            i += 1usize
        }
        j += 1usize
    }
    // u ~ x + phantomstar
    let p = nin + qstar
    let (cols, cke) = mem.alloc[f64](a, n * p)
    if cke != ok { ret (0.0f64, 0.0f64, 0.0f64, cke) }
    i = 0usize
    while i < n * nin {
        cols[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n * qstar {
        cols[n * nin + i] = pcs[i]
        i += 1usize
    }
    let (ssr, e3) = rss_of(a, cols, n, p, r0.resid)
    if e3 != ok { ret (0.0f64, 0.0f64, 0.0f64, e3) }
    let t = f64(n)
    if !ftype { ret (t * math.log[f64](ssr0 / ssr), f64(qstar), 0.0f64, ok) }
    let d2 = t - f64(qstar) - f64(nin)
    ret (((ssr0 - ssr) / f64(qstar)) / (ssr / d2), f64(qstar), d2, ok)
}

// ---- portfolio.optim: solve.QP for min 1/2 w' D w subject to A' w >= b (the first meq rows of A' are equalities), by the dual
// method of Goldfarb and Idnani. D is k by k row-major (positive definite), A is k by q row-major (a column per constraint).
// Answers false when the constraints cannot be met.

fn mat_inverse(a: *mem.Arena, x: []const f64, k: usize, out: []f64) -> bool {
    let (w, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret false }
    var i = 0usize
    while i < k * k {
        w[i] = x[i]
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        out[i * k + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var pv = c
        var best = math.abs[f64](w[c * k + c])
        var r = c + 1usize
        while r < k {
            if math.abs[f64](w[r * k + c]) > best {
                best = math.abs[f64](w[r * k + c])
                pv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if pv != c {
            var j = 0usize
            while j < k {
                let t = w[c * k + j]
                w[c * k + j] = w[pv * k + j]
                w[pv * k + j] = t
                let t2 = out[c * k + j]
                out[c * k + j] = out[pv * k + j]
                out[pv * k + j] = t2
                j += 1usize
            }
        }
        let d = w[c * k + c]
        var j = 0usize
        while j < k {
            w[c * k + j] = w[c * k + j] / d
            out[c * k + j] = out[c * k + j] / d
            j += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = w[r * k + c]
                j = 0usize
                while j < k {
                    w[r * k + j] -= f * w[c * k + j]
                    out[r * k + j] -= f * out[c * k + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret true
}

// a_j' x - b_j for constraint j
fn con_slack(amat: []const f64, k: usize, q: usize, bvec: []const f64, j: usize, x: []const f64) -> f64 {
    var s = 0.0f64 - bvec[j]
    var i = 0usize
    while i < k {
        s += amat[i * q + j] * x[i]
        i += 1usize
    }
    ret s
}

fn solve_qp(a: *mem.Arena, dmat: []const f64, k: usize, amat: []const f64, q: usize, bvec: []const f64, meq: usize, sol: []f64) -> bool {
    let (dinv, e1) = mem.alloc[f64](a, k * k)
    let (act, e2) = mem.alloc[usize](a, q + 1usize)
    let (asg, e3) = mem.alloc[f64](a, q + 1usize)
    let (u, e4) = mem.alloc[f64](a, q + 1usize)
    let (isact, e5) = mem.alloc[bool](a, q)
    let (np, e6) = mem.alloc[f64](a, k)
    let (dnp, e7) = mem.alloc[f64](a, k)
    let (zv, e8) = mem.alloc[f64](a, k)
    let (nm, e9) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret false }
    if !mat_inverse(a, dmat, k, dinv) { ret false }
    var i = 0usize
    while i < k {
        sol[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < q {
        isact[j] = false
        var s = 0.0f64
        i = 0usize
        while i < k {
            s += amat[i * q + j] * amat[i * q + j]
            i += 1usize
        }
        nm[j] = math.sqrt[f64](s)
        j += 1usize
    }
    var na = 0usize
    var outer = 0usize
    while outer < 2000usize {
        outer += 1usize
        // the most violated constraint, equalities first
        var p = q
        var worst = 0.0f64
        var sign = 1.0f64
        j = 0usize
        while j < q {
            if !isact[j] {
                let s = con_slack(amat, k, q, bvec, j, sol) / nm[j]
                if j < meq {
                    if s < 0.0f64 - 1.0e-12f64 || s > 1.0e-12f64 {
                        p = j
                        sign = 1.0f64
                        if s > 0.0f64 { sign = 0.0f64 - 1.0f64 }
                        j = q
                    }
                } else if s < worst - 1.0e-12f64 {
                    worst = s
                    p = j
                    sign = 1.0f64
                }
            }
            if j < q { j += 1usize }
        }
        if p == q { ret true }
        var up = 0.0f64
        var inner = 0usize
        var added = false
        while !added && inner < 2000usize {
            inner += 1usize
            i = 0usize
            while i < k {
                np[i] = sign * amat[i * q + p]
                i += 1usize
            }
            i = 0usize
            while i < k {
                var s = 0.0f64
                var c = 0usize
                while c < k {
                    s += dinv[i * k + c] * np[c]
                    c += 1usize
                }
                dnp[i] = s
                zv[i] = s
                i += 1usize
            }
            let (r, re) = mem.alloc[f64](a, na + 1usize)
            if re != ok { ret false }
            if na > 0usize {
                // M = N' D^-1 N and N' D^-1 np with N the signed active normals
                let (mm, me) = mem.alloc[f64](a, na * na)
                let (mi, mie) = mem.alloc[f64](a, na * na)
                let (rhs, rhe) = mem.alloc[f64](a, na)
                let (dn, dne) = mem.alloc[f64](a, k * na)
                if me != ok || mie != ok || rhe != ok || dne != ok { ret false }
                var ai = 0usize
                while ai < na {
                    i = 0usize
                    while i < k {
                        var s = 0.0f64
                        var c = 0usize
                        while c < k {
                            s += dinv[i * k + c] * asg[ai] * amat[c * q + act[ai]]
                            c += 1usize
                        }
                        dn[i * na + ai] = s
                        i += 1usize
                    }
                    ai += 1usize
                }
                ai = 0usize
                while ai < na {
                    var aj = 0usize
                    while aj < na {
                        var s = 0.0f64
                        i = 0usize
                        while i < k {
                            s += asg[ai] * amat[i * q + act[ai]] * dn[i * na + aj]
                            i += 1usize
                        }
                        mm[ai * na + aj] = s
                        aj += 1usize
                    }
                    var s2 = 0.0f64
                    i = 0usize
                    while i < k {
                        s2 += asg[ai] * amat[i * q + act[ai]] * dnp[i]
                        i += 1usize
                    }
                    rhs[ai] = s2
                    ai += 1usize
                }
                if !mat_inverse(a, mm, na, mi) { ret false }
                ai = 0usize
                while ai < na {
                    var s = 0.0f64
                    var aj = 0usize
                    while aj < na {
                        s += mi[ai * na + aj] * rhs[aj]
                        aj += 1usize
                    }
                    r[ai] = s
                    ai += 1usize
                }
                i = 0usize
                while i < k {
                    var s = dnp[i]
                    ai = 0usize
                    while ai < na {
                        s -= dn[i * na + ai] * r[ai]
                        ai += 1usize
                    }
                    zv[i] = s
                    i += 1usize
                }
            }
            var t1 = 1.0e300f64
            var drop = na
            var ai = 0usize
            while ai < na {
                if act[ai] >= meq && r[ai] > 1.0e-14f64 {
                    let ratio = u[ai] / r[ai]
                    if ratio < t1 {
                        t1 = ratio
                        drop = ai
                    }
                }
                ai += 1usize
            }
            var zn = 0.0f64
            i = 0usize
            while i < k {
                zn += zv[i] * np[i]
                i += 1usize
            }
            var sp = 0.0f64
            i = 0usize
            while i < k {
                sp += np[i] * sol[i]
                i += 1usize
            }
            sp = sp - sign * bvec[p]
            var t2 = 1.0e300f64
            var zz = 0.0f64
            i = 0usize
            while i < k {
                zz += zv[i] * zv[i]
                i += 1usize
            }
            let zfull = zz > 1.0e-24f64
            if zfull && zn > 0.0f64 { t2 = 0.0f64 - sp / zn }
            var t = t2
            if t1 < t { t = t1 }
            if t >= 1.0e299f64 { ret false }
            if zfull {
                i = 0usize
                while i < k {
                    sol[i] += t * zv[i]
                    i += 1usize
                }
            }
            ai = 0usize
            while ai < na {
                u[ai] = u[ai] - t * r[ai]
                ai += 1usize
            }
            up += t
            if zfull && t2 <= t1 {
                act[na] = p
                asg[na] = sign
                u[na] = up
                isact[p] = true
                na += 1usize
                added = true
            } else {
                // the multiplier of the constraint at `drop` is zero: remove it and go on
                var m = drop
                isact[act[m]] = false
                while m + 1usize < na {
                    act[m] = act[m + 1usize]
                    asg[m] = asg[m + 1usize]
                    u[m] = u[m + 1usize]
                    m += 1usize
                }
                na -= 1usize
            }
        }
        if !added { ret false }
    }
    ret false
}

// portfolio.optim.default(x, pm, riskless, shorts, rf, reslow, reshigh): the weights; x is n by k column-major; reslow and reshigh are
// given (both, with 1e100 standing for none) when has_res
fn portfolio_optim(a: *mem.Arena, x: []const f64, n: usize, k: usize, pm: f64, riskless: bool, shorts: bool, rf: f64, has_res: bool, reslow: []const f64, reshigh: []const f64, w: []f64) -> bool {
    // covariance and means
    let (mu, e1) = mem.alloc[f64](a, k)
    let (cv, e2) = mem.alloc[f64](a, k * k)
    if e1 != ok || e2 != ok { ret false }
    var j = 0usize
    while j < k {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[j * n + i]
            i += 1usize
        }
        mu[j] = s / f64(n)
        j += 1usize
    }
    j = 0usize
    while j < k {
        var l = 0usize
        while l < k {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[j * n + i] - mu[j]) * (x[l * n + i] - mu[l])
                i += 1usize
            }
            cv[j * k + l] = s / f64(n - 1usize)
            l += 1usize
        }
        j += 1usize
    }
    // the constraint columns in R's order
    var q = 0usize
    var meq = 1usize
    if !riskless { meq = 2usize }
    q = meq
    if !(shorts && riskless) {
        if !(riskless && shorts) {
            if !shorts { q += k }
        }
    }
    if has_res { q += 2usize * k }
    let (am, e3) = mem.alloc[f64](a, k * q)
    let (bv, e4) = mem.alloc[f64](a, q)
    if e3 != ok || e4 != ok { ret false }
    var c = 0usize
    var i = 0usize
    if riskless {
        i = 0usize
        while i < k {
            am[i * q] = mu[i] - rf
            i += 1usize
        }
        bv[0usize] = pm - rf
        c = 1usize
    } else {
        i = 0usize
        while i < k {
            am[i * q] = 1.0f64
            am[i * q + 1usize] = mu[i]
            i += 1usize
        }
        bv[0usize] = 1.0f64
        bv[1usize] = pm
        c = 2usize
    }
    if !shorts {
        j = 0usize
        while j < k {
            i = 0usize
            while i < k {
                am[i * q + c] = 0.0f64
                i += 1usize
            }
            am[j * q + c] = 1.0f64
            bv[c] = 0.0f64
            c += 1usize
            j += 1usize
        }
    }
    if has_res {
        j = 0usize
        while j < k {
            i = 0usize
            while i < k {
                am[i * q + c] = 0.0f64
                i += 1usize
            }
            am[j * q + c] = 1.0f64
            bv[c] = reslow[j]
            c += 1usize
            j += 1usize
        }
        j = 0usize
        while j < k {
            i = 0usize
            while i < k {
                am[i * q + c] = 0.0f64
                i += 1usize
            }
            am[j * q + c] = 0.0f64 - 1.0f64
            bv[c] = 0.0f64 - reshigh[j]
            c += 1usize
            j += 1usize
        }
    }
    ret solve_qp(a, cv, k, am, q, bv, meq, w)
}
