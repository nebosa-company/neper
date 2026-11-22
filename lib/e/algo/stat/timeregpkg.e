// R timereg aalen: Aalen's additive hazards model with non-parametric cumulative regression functions, the least-squares increments (X'X)^-1 x_i at every event time, with an intercept; the cumulative coefficients are returned at each distinct event time (a time whose risk-set design is singular keeps the previous value, as in timereg).
//
// Also here: cox_aalen (Cox-Aalen), prop_excess (proportional excess hazard) and comp_risk (competing-risks regression, nonparametric terms), each with its resampled tests.
// Not here: constant effects (the semi-parametric aalen and comp.risk const() terms), weights, tied event times, clusters other than one per subject, left truncation, time-varying designs.

use e.algo.rand.r as rng
use e.algo.stat.gparot as gp
use e.math
use e.mem

// t, d (1 = event), x (n by p, no constant column); cum receives one row of p + 1 cumulative coefficients (intercept first) for each of up to n event times and times their event times; returns the number of rows written
fn aalen(a: *mem.Arena, t: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, cum: []f64, times: []f64) -> usize {
    let q = p + 1usize
    let (g, e1) = mem.alloc[f64](a, q * q)
    let (cur, e2) = mem.alloc[f64](a, q)
    let (xi, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var i = 0usize
    while i < q {
        cur[i] = 0.0f64
        i += 1usize
    }
    var rows = 0usize
    var done = 0usize
    // visit events in increasing time order
    let (ord, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret 0usize }
    i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && t[ord[j - 1usize]] > t[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    var pos = 0usize
    while pos < n {
        let who = ord[pos]
        if d[who] > 0.5f64 {
            let tt = t[who]
            let start = mem.mark(a)
            i = 0usize
            while i < q * q {
                g[i] = 0.0f64
                i += 1usize
            }
            var r = 0usize
            while r < n {
                if t[r] >= tt {
                    var c1 = 0usize
                    while c1 < q {
                        var v1 = 1.0f64
                        if c1 > 0usize { v1 = x[r * p + c1 - 1usize] }
                        var c2 = 0usize
                        while c2 < q {
                            var v2 = 1.0f64
                            if c2 > 0usize { v2 = x[r * p + c2 - 1usize] }
                            g[c1 * q + c2] += v1 * v2
                            c2 += 1usize
                        }
                        c1 += 1usize
                    }
                }
                r += 1usize
            }
            let (gi, ge) = gp.invert(a, g, q)
            var well = ge == ok
            if well {
                var ng = 0.0f64
                var ni = 0.0f64
                var c1 = 0usize
                while c1 < q {
                    var cg = 0.0f64
                    var ci = 0.0f64
                    var r1 = 0usize
                    while r1 < q {
                        cg += math.abs[f64](g[r1 * q + c1])
                        ci += math.abs[f64](gi[r1 * q + c1])
                        r1 += 1usize
                    }
                    if cg > ng { ng = cg }
                    if ci > ni { ni = ci }
                    c1 += 1usize
                }
                if ng * ni > 1.0e11f64 { well = false }
            }
            if well {
                xi[0usize] = 1.0f64
                i = 1usize
                while i < q {
                    xi[i] = x[who * p + i - 1usize]
                    i += 1usize
                }
                i = 0usize
                while i < q {
                    var s = 0.0f64
                    var l = 0usize
                    while l < q {
                        s += gi[i * q + l] * xi[l]
                        l += 1usize
                    }
                    cur[i] += s
                    i += 1usize
                }
            }
            i = 0usize
            while i < q {
                cum[rows * q + i] = cur[i]
                i += 1usize
            }
            times[rows] = tt
            rows += 1usize
            mem.reset(a, start)
            done += 1usize
        }
        pos += 1usize
    }
    ret rows
}

// aalen(..., n.sim = antsim, weighted.test = 0, max.time = maxt) after set.seed(seed): the martingale and robust (cluster = subject) variances of the cumulative
// coefficients and the resampled tests. out (9 * (p + 1), every statistic per column with the intercept first): observed supremum test of b = 0, of constant effect, observed Cramer-von Mises of constant effect (3 columns), their
// three p-values (3p), the 95% band quantile of the b = 0 supremum (p), the last robvar.cum row (p) and the last var.cum row (p). Times need to be distinct; at least
// q = p + 1 subjects stay at risk through every event time kept (the pseudo inverse R falls back on is not ported).
fn aalen_tests(a: *mem.Arena, t: []const f64, d: []const f64, x: []const f64, n: usize, px: usize, antsim: usize, seed: i64, maxt: f64, out: []f64) -> err {
    let q = px + 1usize
    let p = q
    var m = 0usize
    var i = 0usize
    while i < n {
        if d[i] > 0.5f64 && t[i] > 0.0f64 && t[i] <= maxt { m += 1usize }
        i += 1usize
    }
    let m1 = m + 1usize
    let (evt, e1) = mem.alloc[f64](a, m1)
    let (evp, e2) = mem.alloc[usize](a, m1)
    let (g, e3) = mem.alloc[f64](a, q * q)
    let (hat, e4) = mem.alloc[f64](a, n * p)
    let (cua, e5) = mem.alloc[f64](a, n * p)
    let (w4, e6) = mem.alloc[f64](a, n * m1 * p)
    let (cu, e7) = mem.alloc[f64](a, m1 * p)
    let (vcu, e8) = mem.alloc[f64](a, m1 * p)
    let (rob, e9) = mem.alloc[f64](a, m1 * p)
    let (dbv, e10) = mem.alloc[f64](a, q)
    let (rx, e11) = mem.alloc[f64](a, q)
    let (dl, e12) = mem.alloc[f64](a, m1 * p)
    let (tst, e13) = mem.alloc[f64](a, 3usize * p * antsim)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    evt[0usize] = 0.0f64
    var s = 1usize
    var prev = 0.0f64
    while s <= m {
        var best = 1.0e300f64
        var who = n
        i = 0usize
        while i < n {
            if d[i] > 0.5f64 && t[i] > prev && t[i] <= maxt && t[i] < best {
                best = t[i]
                who = i
            }
            i += 1usize
        }
        evt[s] = best
        evp[s] = who
        prev = best
        s += 1usize
    }
    i = 0usize
    while i < n * p {
        hat[i] = 0.0f64
        cua[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m1 * p {
        cu[i] = 0.0f64
        vcu[i] = 0.0f64
        rob[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * m1 * p {
        w4[i] = 0.0f64
        i += 1usize
    }
    s = 1usize
    while s <= m {
        let tt = evt[s]
        let start = mem.mark(a)
        i = 0usize
        while i < q * q {
            g[i] = 0.0f64
            i += 1usize
        }
        var r = 0usize
        while r < n {
            if t[r] >= tt {
                var c1 = 0usize
                while c1 < q {
                    var v1 = 1.0f64
                    if c1 > 0usize { v1 = x[r * px + c1 - 1usize] }
                    var c2 = 0usize
                    while c2 < q {
                        var v2 = 1.0f64
                        if c2 > 0usize { v2 = x[r * px + c2 - 1usize] }
                        g[c1 * q + c2] += v1 * v2
                        c2 += 1usize
                    }
                    c1 += 1usize
                }
            }
            r += 1usize
        }
        let (gi, ge) = gp.invert(a, g, q)
        if ge != ok { ret ge }
        let who = evp[s]
        i = 0usize
        while i < q {
            var sm = gi[i * q + 0usize]
            var l = 1usize
            while l < q {
                sm += gi[i * q + l] * x[who * px + l - 1usize]
                l += 1usize
            }
            dbv[i] = sm
            i += 1usize
        }
        var k = 0usize
        while k < p {
            cu[s * p + k] = cu[(s - 1usize) * p + k] + dbv[k]
            vcu[s * p + k] = vcu[(s - 1usize) * p + k] + dbv[k] * dbv[k]
            k += 1usize
        }
        r = 0usize
        while r < n {
            if t[r] >= tt {
                var ahat = dbv[0usize]
                i = 0usize
                while i < px {
                    ahat += x[r * px + i] * dbv[i + 1usize]
                    i += 1usize
                }
                i = 0usize
                while i < q {
                    var sm = gi[i * q + 0usize]
                    var l = 1usize
                    while l < q {
                        sm += gi[i * q + l] * x[r * px + l - 1usize]
                        l += 1usize
                    }
                    rx[i] = sm
                    i += 1usize
                }
                k = 0usize
                while k < p {
                    if r == who { hat[r * p + k] += rx[k] }
                    cua[r * p + k] += ahat * rx[k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        r = 0usize
        while r < n {
            k = 0usize
            while k < p {
                let df = hat[r * p + k] - cua[r * p + k]
                w4[(r * m1 + s) * p + k] = df
                rob[s * p + k] += df * df
                k += 1usize
            }
            r += 1usize
        }
        mem.reset(a, start)
        s += 1usize
    }
    let tau = evt[m] - evt[0usize]
    var k = 0usize
    while k < 3usize * p {
        out[k] = 0.0f64
        k += 1usize
    }
    s = 1usize
    while s <= m {
        let dtime = evt[s] - evt[s - 1usize]
        k = 0usize
        while k < p {
            let xij = math.abs[f64](cu[s * p + k]) / math.sqrt[f64](rob[s * p + k])
            if xij > out[k] { out[k] = xij }
            let dif = cu[s * p + k] - (evt[s] - evt[0usize]) / tau * cu[m * p + k]
            if math.abs[f64](dif) > out[p + k] { out[p + k] = math.abs[f64](dif) }
            out[2usize * p + k] += dif * dif * dtime
            k += 1usize
        }
        s += 1usize
    }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var sim = 0usize
    while sim < antsim {
        i = 0usize
        while i < m1 * p {
            dl[i] = 0.0f64
            i += 1usize
        }
        var r = 0usize
        while r < n {
            let z = rng.norm(&rg)
            i = 0usize
            while i < m1 * p {
                dl[i] += z * w4[r * m1 * p + i]
                i += 1usize
            }
            r += 1usize
        }
        k = 0usize
        while k < 3usize * p {
            tst[k * antsim + sim] = 0.0f64
            k += 1usize
        }
        s = 1usize
        while s <= m {
            let dtime = evt[s] - evt[s - 1usize]
            k = 0usize
            while k < p {
                let xi = math.abs[f64](dl[s * p + k]) / math.sqrt[f64](rob[s * p + k])
                if xi > tst[k * antsim + sim] { tst[k * antsim + sim] = xi }
                let dif = dl[s * p + k] - (evt[s] - evt[0usize]) / tau * dl[m * p + k]
                if math.abs[f64](dif) > tst[(p + k) * antsim + sim] { tst[(p + k) * antsim + sim] = math.abs[f64](dif) }
                tst[(2usize * p + k) * antsim + sim] += dif * dif * dtime
                k += 1usize
            }
            s += 1usize
        }
        sim += 1usize
    }
    k = 0usize
    while k < 3usize * p {
        var cnt = 0usize
        sim = 0usize
        while sim < antsim {
            if out[k] < tst[k * antsim + sim] { cnt += 1usize }
            sim += 1usize
        }
        out[3usize * p + k] = f64(cnt) / f64(antsim)
        k += 1usize
    }
    // percen(x, 0.95): the (round(n * 0.95) + 1)-th smallest, round half to even
    let rv = f64(antsim) * 0.95f64
    let fl = math.floor[f64](rv)
    var tag = usize(fl)
    let fr = rv - fl
    if fr > 0.5f64 || (fr == 0.5f64 && tag % 2usize == 1usize) { tag += 1usize }
    k = 0usize
    while k < p {
        var pick = 0.0f64
        sim = 0usize
        while sim < antsim {
            let v = tst[k * antsim + sim]
            var below = 0usize
            var j = 0usize
            while j < antsim {
                let u = tst[k * antsim + j]
                if u < v || (u == v && j < sim) { below += 1usize }
                j += 1usize
            }
            if below == tag { pick = v }
            sim += 1usize
        }
        out[6usize * p + k] = pick
        out[7usize * p + k] = rob[m * p + k]
        out[8usize * p + k] = vcu[m * p + k]
        k += 1usize
    }
    ret ok
}

// ---- Cox-Aalen: lambda_i(t) = Y_i(t) x_i'alpha(t) exp(z_i'beta) ----

type Pool = struct { buf: []f64, at: usize }

fn take(p: *Pool, n: usize) -> []f64 {
    let s = p.at
    p.at = s + n
    ret p.buf[s..s + n]
}

// out = inverse(m), k by k, through the arena marks so nothing stays allocated
fn inv_to(a: *mem.Arena, m: []const f64, k: usize, out: []f64) -> err {
    let start = mem.mark(a)
    let (gi, e) = gp.invert(a, m, k)
    if e != ok {
        mem.reset(a, start)
        ret e
    }
    var i = 0usize
    while i < k * k {
        out[i] = gi[i]
        i += 1usize
    }
    mem.reset(a, start)
    ret ok
}

// the risk-set sums of the Cox-Aalen model gain (w = exp(z'beta)) or lose (w = -exp(z'beta)) subject i
fn ca_add(sa: []f64, szx: []f64, szpz: []f64, szpx: []f64, x: []const f64, z: []const f64, i: usize, px: usize, pg: usize, w: f64) {
    var j = 0usize
    while j < px {
        var k = 0usize
        while k < px {
            sa[j * px + k] += x[i * px + k] * x[i * px + j] * w
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < pg {
        var k = 0usize
        while k < px {
            szx[j * px + k] += z[i * pg + j] * x[i * px + k] * w
            szpx[k * pg + j] += z[i * pg + j] * x[i * px + k] * w
            k += 1usize
        }
        k = 0usize
        while k < pg {
            szpz[j * pg + k] += z[i * pg + j] * z[i * pg + k] * w
            k += 1usize
        }
        j += 1usize
    }
}

// percen(v, 0.95): the (round(n * 0.95) + 1)-th smallest, round half to even
fn pick95(v: []const f64, n: usize) -> f64 {
    let rv = f64(n) * 0.95f64
    let fl = math.floor[f64](rv)
    var tag = usize(fl)
    let fr = rv - fl
    if fr > 0.5f64 || (fr == 0.5f64 && tag % 2usize == 1usize) { tag += 1usize }
    var pick = 0.0f64
    var sim = 0usize
    while sim < n {
        let w = v[sim]
        var below = 0usize
        var j = 0usize
        while j < n {
            if v[j] < w || (v[j] == w && j < sim) { below += 1usize }
            j += 1usize
        }
        if below == tag { pick = w }
        sim += 1usize
    }
    ret pick
}

// pval(v, obs): the share of resampled values above the observed one
fn above(v: []const f64, n: usize, obs: f64) -> f64 {
    var c = 0usize
    var i = 0usize
    while i < n {
        if obs < v[i] { c += 1usize }
        i += 1usize
    }
    ret f64(c) / f64(n)
}

// cox.aalen(Surv(t, d) ~ x-terms + prop(z-terms), max.time = maxt, n.sim = antsim, basesim = bs, beta = beta0) after set.seed(seed), right-censored data with distinct times, one cluster per
// subject, no weights, offsets, strata or tied events, at most 99 event times. x is n by px (an intercept column included as the formula gives it), z is n by pg; px = 1 is the Cox model, px > 1 needs X'X not diagonal.
// out holds the results back to back, lens their lengths: 0 cum (rows of time, then the px cumulative coefficients, row 0 first), 1 var.cum, 2 robvar.cum, 3 gamma, 4 var.gamma, 5 robvar.gamma, 6 score,
// 7 test.procProp (time then pg score processes), 8 pval.Prop, 9 conf.band, 10 obs.testBeq0, 11 obs.testBeqC, 12 pval.testBeq0, 13 pval.testBeqC (9-13 only with bs = 1), 14 D2linv, 15 loglike[2].
// lens[16] receives the number of event times.
fn cox_aalen(a: *mem.Arena, t: []const f64, d: []const f64, x: []const f64, z: []const f64, n: usize, px: usize, pg: usize, beta0: []const f64, maxt: f64, antsim: usize, seed: i64, bs: usize, nit: usize, out: []f64, lens: []usize) -> err {
    var m = 0usize
    var i = 0usize
    while i < n {
        if d[i] > 0.5f64 && t[i] > 0.0f64 && t[i] <= maxt { m += 1usize }
        i += 1usize
    }
    if m < 2usize || m > 99usize || nit < 3usize || pg > 8usize { ret mem.Full }
    let m1 = m + 1usize
    let (evt, e1) = mem.alloc[f64](a, m1)
    let (evp, e2) = mem.alloc[usize](a, m1)
    let (ord, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    evt[0usize] = 0.0f64
    var s = 1usize
    var prev = 0.0f64
    while s <= m {
        var best = 1.0e300f64
        var who = n
        i = 0usize
        while i < n {
            if d[i] > 0.5f64 && t[i] > prev && t[i] <= maxt && t[i] < best {
                best = t[i]
                who = i
            }
            i += 1usize
        }
        evt[s] = best
        evp[s] = who
        prev = best
        s += 1usize
    }
    i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && t[ord[j - 1usize]] < t[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    let q1 = px + 1usize
    let total = 10usize * pg * pg + 4usize * px * px + 12usize * pg * px + 8usize * pg + 8usize * px + n * (1usize + pg + px) + 3usize * m1 * q1 + m1 * pg + m1 * pg * pg + 2usize * m1 * px * pg + n * m1 * (pg + px) + n * m1 * (px + pg) + m1 * pg + m1 * px + m1 * pg + 2usize * antsim * (px + pg) + 4usize * antsim * px + 16usize
    let (buf, e4) = mem.alloc[f64](a, total)
    if e4 != ok { ret mem.Full }
    i = 0usize
    while i < total {
        buf[i] = 0.0f64
        i += 1usize
    }
    var pool: Pool = zero
    pool.buf = buf
    pool.at = 0usize
    let beta = take(&pool, pg)
    let u = take(&pool, pg)
    let s1 = take(&pool, pg * pg)
    let si = take(&pool, pg * pg)
    let delta = take(&pool, pg)
    let sa = take(&pool, px * px)
    let sai = take(&pool, px * px)
    let szx = take(&pool, pg * px)
    let szpz = take(&pool, pg * pg)
    let szpx = take(&pool, px * pg)
    let zpxo = take(&pool, px * pg)
    let zpzo = take(&pool, pg * pg)
    let zxai = take(&pool, pg * px)
    let da = take(&pool, px)
    let zav = take(&pool, pg)
    let dz = take(&pool, pg)
    let rr = take(&pool, n)
    let cu = take(&pool, m1 * q1)
    let vcu = take(&pool, m1 * q1)
    let rv = take(&pool, m1 * q1)
    let utt = take(&pool, m1 * pg)
    let stg = take(&pool, m1 * pg * pg)
    let cs = take(&pool, m1 * px * pg)
    let m12 = take(&pool, m1 * pg * px)
    let ct = take(&pool, px * pg)
    let m12t = take(&pool, pg * px)
    let vu = take(&pool, pg * pg)
    let tmp = take(&pool, pg * pg)
    let tmp2 = take(&pool, pg * pg)
    let w2 = take(&pool, n * pg)
    let w3 = take(&pool, n * px)
    let w2t = take(&pool, n * m1 * pg)
    let w3t = take(&pool, n * m1 * px)
    let w4t = take(&pool, n * m1 * px)
    let uti = take(&pool, n * m1 * pg)
    let varu = take(&pool, m1 * pg)
    let dlt = take(&pool, m1 * px)
    let dlt2 = take(&pool, m1 * pg)
    let tst = take(&pool, 2usize * antsim * px)
    let sut = take(&pool, antsim * pg)
    let tv = take(&pool, pg)
    let rx = take(&pool, px)
    let tobs = take(&pool, 2usize * px)
    let robv = take(&pool, pg * pg)
    var k = 0usize
    var j = 0usize
    var l = 0usize
    if px > 1usize {
        var offd = 0.0f64
        i = 0usize
        while i < n {
            j = 0usize
            while j < px {
                l = 0usize
                while l < px {
                    if j != l { offd += math.abs[f64](x[i * px + j] * x[i * px + l]) }
                    l += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        if offd == 0.0f64 { ret mem.Full }
    }
    k = 0usize
    while k < pg {
        beta[k] = beta0[k]
        k += 1usize
    }
    var llo = 0.0f64
    var it = 0usize
    while it < nit {
        let last = it == nit - 1usize
        k = 0usize
        while k < pg {
            u[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < pg * pg {
            s1[k] = 0.0f64
            szpz[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < px * px {
            sa[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < pg * px {
            szx[k] = 0.0f64
            szpx[k] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            var lp = 0.0f64
            k = 0usize
            while k < pg {
                lp += z[i * pg + k] * beta[k]
                k += 1usize
            }
            rr[i] = math.exp[f64](lp)
            i += 1usize
        }
        var s0 = 0.0f64
        var cnt = n
        while cnt > 0usize && t[ord[cnt - 1usize]] < evt[1usize] { cnt -= 1usize }
        i = 0usize
        while i < n {
            let c = ord[i]
            if t[c] >= evt[1usize] {
                ca_add(sa, szx, szpz, szpx, x, z, c, px, pg, rr[c])
                s0 += rr[c]
            }
            i += 1usize
        }
        s = 1usize
        while s <= m {
            let tt = evt[s]
            if s > 1usize {
                while cnt > 0usize && t[ord[cnt - 1usize]] < tt {
                    let c = ord[cnt - 1usize]
                    ca_add(sa, szx, szpz, szpx, x, z, c, px, pg, 0.0f64 - rr[c])
                    s0 -= rr[c]
                    cnt -= 1usize
                }
            }
            let pers = evp[s]
            if px == 1usize {
                sai[0usize] = 1.0f64 / sa[0usize]
                if math.abs[f64](sa[0usize]) < 0.000001f64 { sai[0usize] = 0.0f64 }
            } else {
                let ei = inv_to(a, sa, px, sai)
                if ei != ok { ret ei }
            }
            j = 0usize
            while j < px {
                var sm = 0.0f64
                l = 0usize
                while l < px {
                    sm += sai[j * px + l] * x[pers * px + l]
                    l += 1usize
                }
                da[j] = sm
                j += 1usize
            }
            j = 0usize
            while j < pg {
                l = 0usize
                while l < px {
                    var sm = 0.0f64
                    k = 0usize
                    while k < px {
                        sm += szx[j * px + k] * sai[k * px + l]
                        k += 1usize
                    }
                    zxai[j * px + l] = sm
                    l += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < pg {
                var sm = 0.0f64
                l = 0usize
                while l < px {
                    sm += szx[j * px + l] * da[l]
                    l += 1usize
                }
                zav[j] = sm
                dz[j] = z[pers * pg + j] - sm
                u[j] += dz[j]
                j += 1usize
            }
            if last && px > 1usize {
                k = 0usize
                while k < pg * pg {
                    zpzo[k] = 0.0f64
                    k += 1usize
                }
                k = 0usize
                while k < px * pg {
                    zpxo[k] = 0.0f64
                    k += 1usize
                }
                i = 0usize
                while i < n {
                    if t[i] >= tt {
                        var hat = 0.0f64
                        j = 0usize
                        while j < px {
                            hat += x[i * px + j] * da[j]
                            j += 1usize
                        }
                        hat = hat * rr[i]
                        j = 0usize
                        while j < px {
                            k = 0usize
                            while k < pg {
                                zpxo[j * pg + k] += hat * x[i * px + j] * z[i * pg + k]
                                k += 1usize
                            }
                            j += 1usize
                        }
                        j = 0usize
                        while j < pg {
                            k = 0usize
                            while k < pg {
                                zpzo[j * pg + k] += hat * z[i * pg + k] * z[i * pg + j]
                                k += 1usize
                            }
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
            } else {
                k = 0usize
                while k < pg * pg {
                    zpzo[k] = szpz[k] / s0
                    k += 1usize
                }
                k = 0usize
                while k < px * pg {
                    zpxo[k] = szpx[k] / s0
                    k += 1usize
                }
            }
            j = 0usize
            while j < pg {
                l = 0usize
                while l < pg {
                    var sm = 0.0f64
                    k = 0usize
                    while k < px {
                        sm += zxai[j * px + k] * zpxo[k * pg + l]
                        k += 1usize
                    }
                    s1[j * pg + l] += zpzo[j * pg + l] - sm
                    l += 1usize
                }
                j += 1usize
            }
            if last {
                k = 0usize
                while k < pg * pg {
                    stg[s * pg * pg + k] = s1[k]
                    k += 1usize
                }
                k = 0usize
                while k < pg {
                    utt[s * pg + k] = u[k]
                    k += 1usize
                }
                j = 0usize
                while j < pg {
                    l = 0usize
                    while l < pg {
                        vu[j * pg + l] += dz[j] * dz[l]
                        l += 1usize
                    }
                    j += 1usize
                }
                j = 0usize
                while j < px {
                    l = 0usize
                    while l < pg {
                        var sm = 0.0f64
                        k = 0usize
                        while k < px {
                            sm += sai[j * px + k] * zpxo[k * pg + l]
                            k += 1usize
                        }
                        ct[j * pg + l] -= sm
                        l += 1usize
                    }
                    j += 1usize
                }
                k = 0usize
                while k < px * pg {
                    cs[s * px * pg + k] = ct[k]
                    k += 1usize
                }
                j = 0usize
                while j < pg {
                    l = 0usize
                    while l < px {
                        m12t[j * px + l] += da[l] * dz[j]
                        m12[s * pg * px + j * px + l] = m12t[j * px + l]
                        l += 1usize
                    }
                    j += 1usize
                }
                cu[s * q1] = tt
                vcu[s * q1] = tt
                rv[s * q1] = tt
                k = 0usize
                while k < px {
                    cu[s * q1 + k + 1usize] = cu[(s - 1usize) * q1 + k + 1usize] + da[k]
                    vcu[s * q1 + k + 1usize] = da[k] * da[k] + vcu[(s - 1usize) * q1 + k + 1usize]
                    k += 1usize
                }
                i = 0usize
                while i < n {
                    if t[i] >= tt {
                        var hat = 0.0f64
                        j = 0usize
                        while j < px {
                            hat += x[i * px + j] * da[j]
                            j += 1usize
                        }
                        hat = hat * rr[i]
                        j = 0usize
                        while j < pg {
                            var sm = 0.0f64
                            l = 0usize
                            while l < px {
                                sm += zxai[j * px + l] * x[i * px + l]
                                l += 1usize
                            }
                            tv[j] = z[i * pg + j] - sm
                            j += 1usize
                        }
                        j = 0usize
                        while j < pg {
                            if i == pers { w2[i * pg + j] += tv[j] }
                            w2[i * pg + j] -= hat * tv[j]
                            j += 1usize
                        }
                        j = 0usize
                        while j < px {
                            var sm = 0.0f64
                            l = 0usize
                            while l < px {
                                sm += sai[j * px + l] * x[i * px + l]
                                l += 1usize
                            }
                            rx[j] = sm
                            j += 1usize
                        }
                        j = 0usize
                        while j < px {
                            if i == pers { w3[i * px + j] += rx[j] }
                            w3[i * px + j] -= hat * rx[j]
                            j += 1usize
                        }
                        llo += hat
                    }
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    j = 0usize
                    while j < pg {
                        w2t[(i * m1 + s) * pg + j] = w2[i * pg + j]
                        j += 1usize
                    }
                    j = 0usize
                    while j < px {
                        w3t[(i * m1 + s) * px + j] = w3[i * px + j]
                        j += 1usize
                    }
                    i += 1usize
                }
            }
            s += 1usize
        }
        let es = inv_to(a, s1, pg, si)
        if es != ok { ret es }
        j = 0usize
        while j < pg {
            var sm = 0.0f64
            l = 0usize
            while l < pg {
                sm += si[j * pg + l] * u[l]
                l += 1usize
            }
            delta[j] = sm
            j += 1usize
        }
        if last {
            j = 0usize
            while j < pg {
                l = 0usize
                while l < pg {
                    var sm = 0.0f64
                    k = 0usize
                    while k < pg {
                        sm += si[j * pg + k] * vu[k * pg + l]
                        k += 1usize
                    }
                    tmp[j * pg + l] = sm
                    l += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < pg {
                l = 0usize
                while l < pg {
                    var sm = 0.0f64
                    k = 0usize
                    while k < pg {
                        sm += tmp[j * pg + k] * si[k * pg + l]
                        k += 1usize
                    }
                    tmp2[j * pg + l] = sm
                    l += 1usize
                }
                j += 1usize
            }
            k = 0usize
            while k < pg * pg {
                vu[k] = tmp2[k]
                k += 1usize
            }
        } else {
            j = 0usize
            while j < pg {
                beta[j] += delta[j]
                j += 1usize
            }
        }
        var sumscore = 0.0f64
        k = 0usize
        while k < pg {
            sumscore += math.abs[f64](u[k])
            k += 1usize
        }
        if sumscore < 0.0000001f64 && it + 2usize < nit { it = nit - 2usize }
        it += 1usize
    }
    // the beta terms of the martingale variance of the cumulative coefficients
    s = 1usize
    while s <= m {
        k = 0usize
        while k < px {
            var cvc = 0.0f64
            var cov = 0.0f64
            j = 0usize
            while j < pg {
                var a1 = 0.0f64
                var a2 = 0.0f64
                l = 0usize
                while l < pg {
                    a1 += cs[s * px * pg + k * pg + l] * vu[l * pg + j]
                    a2 += cs[s * px * pg + k * pg + l] * si[l * pg + j]
                    l += 1usize
                }
                cvc += a1 * cs[s * px * pg + k * pg + j]
                cov += a2 * m12[s * pg * px + j * px + k]
                j += 1usize
            }
            vcu[s * q1 + k + 1usize] += cvc + 2.0f64 * cov
            k += 1usize
        }
        s += 1usize
    }
    // robust variance of beta
    i = 0usize
    while i < n {
        j = 0usize
        while j < pg {
            l = 0usize
            while l < pg {
                robv[j * pg + l] += w2[i * pg + j] * w2[i * pg + l]
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < pg {
        l = 0usize
        while l < pg {
            var sm = 0.0f64
            k = 0usize
            while k < pg {
                sm += robv[j * pg + k] * si[k * pg + l]
                k += 1usize
            }
            tmp[j * pg + l] = sm
            l += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < pg {
        l = 0usize
        while l < pg {
            var sm = 0.0f64
            k = 0usize
            while k < pg {
                sm += si[j * pg + k] * tmp[k * pg + l]
                k += 1usize
            }
            tmp2[j * pg + l] = sm
            l += 1usize
        }
        j += 1usize
    }
    k = 0usize
    while k < pg * pg {
        robv[k] = tmp2[k]
        k += 1usize
    }
    // robust variances of the cumulative coefficients and the cluster score processes
    s = 1usize
    while s <= m {
        i = 0usize
        while i < n {
            j = 0usize
            while j < pg {
                var sm = 0.0f64
                l = 0usize
                while l < pg {
                    sm += si[j * pg + l] * w2[i * pg + l]
                    l += 1usize
                }
                tv[j] = sm
                j += 1usize
            }
            j = 0usize
            while j < px {
                var sm = 0.0f64
                l = 0usize
                while l < pg {
                    sm += cs[s * px * pg + j * pg + l] * tv[l]
                    l += 1usize
                }
                let dx = w3t[(i * m1 + s) * px + j] + sm
                w4t[(i * m1 + s) * px + j] = dx
                rv[s * q1 + j + 1usize] += dx * dx
                j += 1usize
            }
            j = 0usize
            while j < pg {
                var sm = 0.0f64
                l = 0usize
                while l < pg {
                    sm += stg[s * pg * pg + j * pg + l] * tv[l]
                    l += 1usize
                }
                let ut = w2t[(i * m1 + s) * pg + j] - sm
                uti[(i * m1 + s) * pg + j] = ut
                varu[s * pg + j] += ut * ut
                j += 1usize
            }
            i += 1usize
        }
        s += 1usize
    }
    // observed tests and resampling
    let tau = evt[m] - evt[0usize]
    var sup: [8]f64 = zero
    k = 0usize
    while k < pg {
        sup[k] = 0.0f64
        s = 1usize
        while s <= m {
            if math.abs[f64](utt[s * pg + k]) > sup[k] { sup[k] = math.abs[f64](utt[s * pg + k]) }
            s += 1usize
        }
        k += 1usize
    }
    if bs > 0usize {
        s = 1usize
        while s <= m {
            k = 0usize
            while k < px {
                let xv = math.abs[f64](cu[s * q1 + k + 1usize]) / math.sqrt[f64](rv[s * q1 + k + 1usize])
                if xv > tobs[k] { tobs[k] = xv }
                let df = math.abs[f64](cu[s * q1 + k + 1usize] - (evt[s] - evt[0usize]) / tau * cu[m * q1 + k + 1usize])
                if df > tobs[px + k] { tobs[px + k] = df }
                k += 1usize
            }
            s += 1usize
        }
    }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let ru = rng.runif(&rg, 0.0f64, 1.0f64)
    var sim = 0usize
    while sim < antsim {
        k = 0usize
        while k < m1 * px {
            dlt[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < m1 * pg {
            dlt2[k] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            let zz = rng.norm(&rg)
            s = 0usize
            while s < m1 {
                k = 0usize
                while k < px {
                    dlt[s * px + k] += zz * w4t[(i * m1 + s) * px + k]
                    k += 1usize
                }
                k = 0usize
                while k < pg {
                    dlt2[s * pg + k] += zz * uti[(i * m1 + s) * pg + k]
                    k += 1usize
                }
                s += 1usize
            }
            i += 1usize
        }
        s = 1usize
        while s <= m {
            k = 0usize
            while k < px {
                let df = math.abs[f64](dlt[s * px + k] - (evt[s] - evt[0usize]) / tau * dlt[m * px + k])
                if df > tst[(px + k) * antsim + sim] { tst[(px + k) * antsim + sim] = df }
                let xv = math.abs[f64](dlt[s * px + k]) / math.sqrt[f64](rv[s * q1 + k + 1usize])
                if xv > tst[k * antsim + sim] { tst[k * antsim + sim] = xv }
                k += 1usize
            }
            k = 0usize
            while k < pg {
                if math.abs[f64](dlt2[s * pg + k]) > sut[k * antsim + sim] { sut[k * antsim + sim] = math.abs[f64](dlt2[s * pg + k]) }
                k += 1usize
            }
            s += 1usize
        }
        sim += 1usize
    }
    let _ = ru
    var at = 0usize
    var sec = 0usize
    while sec < 17usize {
        lens[sec] = 0usize
        sec += 1usize
    }
    sec = 0usize
    while sec < 3usize {
        k = 0usize
        while k < m1 * q1 {
            var v = cu[k]
            if sec == 1usize { v = vcu[k] }
            if sec == 2usize { v = rv[k] }
            out[at + k] = v
            k += 1usize
        }
        lens[sec] = m1 * q1
        at += m1 * q1
        sec += 1usize
    }
    k = 0usize
    while k < pg {
        out[at + k] = beta[k]
        out[at + pg + pg * pg + pg * pg + k] = u[k]
        k += 1usize
    }
    j = 0usize
    while j < pg * pg {
        out[at + pg + j] = vu[j]
        out[at + pg + pg * pg + j] = robv[j]
        j += 1usize
    }
    lens[3usize] = pg
    lens[4usize] = pg * pg
    lens[5usize] = pg * pg
    lens[6usize] = pg
    at += pg + 2usize * pg * pg + pg
    s = 0usize
    while s < m1 {
        out[at + s * (pg + 1usize)] = evt[s]
        k = 0usize
        while k < pg {
            out[at + s * (pg + 1usize) + k + 1usize] = utt[s * pg + k]
            k += 1usize
        }
        s += 1usize
    }
    lens[7usize] = m1 * (pg + 1usize)
    at += m1 * (pg + 1usize)
    k = 0usize
    while k < pg {
        out[at + k] = 0.0f64
        if antsim > 0usize { out[at + k] = above(sut[k * antsim..k * antsim + antsim], antsim, sup[k]) }
        k += 1usize
    }
    lens[8usize] = pg
    at += pg
    k = 0usize
    while k < px {
        out[at + k] = 0.0f64
        out[at + px + k] = 0.0f64
        out[at + 2usize * px + k] = 0.0f64
        out[at + 3usize * px + k] = 0.0f64
        out[at + 4usize * px + k] = 0.0f64
        if bs > 0usize && antsim > 0usize {
            out[at + k] = pick95(tst[k * antsim..k * antsim + antsim], antsim)
            out[at + px + k] = tobs[k]
            out[at + 2usize * px + k] = tobs[px + k]
            out[at + 3usize * px + k] = above(tst[k * antsim..k * antsim + antsim], antsim, tobs[k])
            out[at + 4usize * px + k] = above(tst[(px + k) * antsim..(px + k) * antsim + antsim], antsim, tobs[px + k])
        }
        k += 1usize
    }
    sec = 9usize
    while sec < 14usize {
        lens[sec] = px
        sec += 1usize
    }
    at += 5usize * px
    j = 0usize
    while j < pg * pg {
        out[at + j] = si[j]
        j += 1usize
    }
    lens[14usize] = pg * pg
    at += pg * pg
    out[at] = 0.0f64
    out[at + 1usize] = 0.0f64 - llo
    lens[15usize] = 2usize
    lens[16usize] = m
    ret ok
}

// ---- prop.excess: lambda_i(t) = Y_i(t) (x_i'alpha(t) + excess_i exp(excess_i z_i'beta) ... ), timereg's proportional excess hazard model ----

// out (ar by bc) = a (ar by ac) times b (ac by bc); out must not overlap a or b
fn mmul(a: []const f64, ar: usize, ac: usize, b: []const f64, bc: usize, out: []f64) {
    var i = 0usize
    while i < ar {
        var j = 0usize
        while j < bc {
            var s = 0.0f64
            var k = 0usize
            while k < ac {
                s += a[i * ac + k] * b[k * bc + j]
                k += 1usize
            }
            out[i * bc + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// out (ac by ar) = the transpose of a (ar by ac)
fn mtrans(a: []const f64, ar: usize, ac: usize, out: []f64) {
    var i = 0usize
    while i < ar {
        var j = 0usize
        while j < ac {
            out[j * ar + i] = a[i * ac + j]
            j += 1usize
        }
        i += 1usize
    }
}

// timereg's invert(): the inverse, or zeros when the estimated reciprocal condition number is under 1e-7 (the estimate is taken as the exact 1-norm one) or the first element is huge
fn inv_guard(a: *mem.Arena, m: []const f64, k: usize, out: []f64) {
    var i = 0usize
    while i < k * k {
        out[i] = 0.0f64
        i += 1usize
    }
    let start = mem.mark(a)
    let (gi, e) = gp.invert(a, m, k)
    if e == ok {
        var na = 0.0f64
        var ni = 0.0f64
        var c = 0usize
        while c < k {
            var s1 = 0.0f64
            var s2 = 0.0f64
            var r = 0usize
            while r < k {
                s1 += math.abs[f64](m[r * k + c])
                s2 += math.abs[f64](gi[r * k + c])
                r += 1usize
            }
            if s1 > na { na = s1 }
            if s2 > ni { ni = s2 }
            c += 1usize
        }
        if 1.0f64 / (na * ni) >= 0.0000001f64 && !(math.abs[f64](gi[0usize]) > 99999999999999.0f64) {
            i = 0usize
            while i < k * k {
                out[i] = gi[i]
                i += 1usize
            }
        }
    }
    mem.reset(a, start)
}

// (a > b) ? a : b, as the C ternary max reads it
fn cmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

// the design at event time tau: dn (n), xt, pxt, dxt (n by p + 1: X.tilde, Phi X.tilde, diag(dN) X.tilde), zm, pz, dpz (n by q: Z, Phi Z, diag(dN) Phi Z), all with the at-risk indicator
fn pe_design(t: []const f64, x: []const f64, z: []const f64, ex: []const f64, phi: []const f64, tau: f64, n: usize, p: usize, q: usize, dn: []f64, xt: []f64, pxt: []f64, dxt: []f64, zm: []f64, pz: []f64, dpz: []f64) {
    let pp = p + 1usize
    var j = 0usize
    while j < n {
        var y = 0.0f64
        var d = 0.0f64
        if t[j] >= tau { y = 1.0f64 }
        if t[j] >= tau && t[j] <= tau { d = 1.0f64 }
        dn[j] = d
        var l = 0usize
        while l < pp {
            var xv = phi[j]
            if l < p { xv = x[j * p + l] }
            xt[j * pp + l] = y * xv
            pxt[j * pp + l] = phi[j] * y * xv
            dxt[j * pp + l] = d * xv
            l += 1usize
        }
        l = 0usize
        while l < q {
            zm[j * q + l] = y * ex[j] * z[j * q + l]
            pz[j * q + l] = phi[j] * y * ex[j] * z[j * q + l]
            dpz[j * q + l] = d * phi[j] * y * ex[j] * z[j * q + l]
            l += 1usize
        }
        j += 1usize
    }
}

// the Cox-Aalen style start: prop.excess(Surv(t, d) ~ x-terms + cox(z-terms), excess = ex, tol, n.sim = antsim), beta = beta0 (coxph's fit in R) and after set.seed(seed).
// t, d, ex have n entries, x is n by p (the intercept column included), z is n by q. out holds, back to back (lens gives the lengths): 0 cum (event time, then the p + 1
// cumulative functions, one row per event), 1 var.cum (the robust variances), 2 gamma, 3 var.gamma, 4 pval (sup test), 5 score (dU/dbeta), 6 pval.HW, 7 pval.CM, 8 quant95,
// 9 quant95HW, 10 the number of Newton iterations. Event times are taken in sorted order, as R does.
fn prop_excess(a: *mem.Arena, t: []const f64, d: []const f64, x: []const f64, z: []const f64, ex: []const f64, n: usize, p: usize, q: usize, beta0: []const f64, tol: f64, alpha0: f64, antsim: usize, seed: i64, out: []f64, lens: []usize) -> err {
    let pp = p + 1usize
    var k = 0usize
    var i = 0usize
    while i < n {
        if d[i] > 0.5f64 { k += 1usize }
        i += 1usize
    }
    if k < 3usize || q > 4usize || antsim < 2usize { ret mem.Full }
    let (evt, e1) = mem.alloc[f64](a, k)
    if e1 != ok { ret mem.Full }
    var s = 0usize
    while s < k {
        // the s-th smallest event time, ties counted by position
        var best = 1.0e300f64
        i = 0usize
        while i < n {
            if d[i] > 0.5f64 {
                var rank = 0usize
                var j = 0usize
                while j < n {
                    if d[j] > 0.5f64 && (t[j] < t[i] || (t[j] == t[i] && j < i)) { rank += 1usize }
                    j += 1usize
                }
                if rank == s { best = t[i] }
            }
            i += 1usize
        }
        evt[s] = best
        s += 1usize
    }
    let nk = n * k
    let total = 60usize * n * pp + 60usize * n * q + 40usize * pp * pp + 40usize * q * q + 40usize * pp * q + 8usize * nk * pp + 8usize * nk * q + 8usize * k * pp * pp + 8usize * k * q * q + 8usize * k * pp + 8usize * antsim * pp + 8usize * antsim + 8usize * k * q + 200usize
    let (buf, e2) = mem.alloc[f64](a, total)
    if e2 != ok { ret mem.Full }
    i = 0usize
    while i < total {
        buf[i] = 0.0f64
        i += 1usize
    }
    var pool: Pool = zero
    pool.buf = buf
    pool.at = 0usize
    let phi = take(&pool, n)
    let dn = take(&pool, n)
    let xt = take(&pool, n * pp)
    let pxt = take(&pool, n * pp)
    let dxt = take(&pool, n * pp)
    let zm = take(&pool, n * q)
    let pz = take(&pool, n * q)
    let dpz = take(&pool, n * q)
    let beta = take(&pool, q)
    let betat = take(&pool, q)
    let betam = take(&pool, q)
    let ub = take(&pool, q)
    let uinp = take(&pool, q)
    let du = take(&pool, q * q)
    let du1 = take(&pool, q * q)
    let dui = take(&pool, q * q)
    let dui1 = take(&pool, q * q)
    let dscore = take(&pool, q * q)
    let opt = take(&pool, q * q)
    let optt = take(&pool, q * q)
    let m1 = take(&pool, q * q)
    let tz = take(&pool, q * n)
    let tzp = take(&pool, q * n)
    let tzpxt = take(&pool, q * pp)
    let tzpxi = take(&pool, q * pp)
    let txt = take(&pool, pp * n)
    let tdxt = take(&pool, pp * n)
    let txtxt = take(&pool, pp * pp)
    let txtxti = take(&pool, pp * pp)
    let v1 = take(&pool, pp)
    let txtdn = take(&pool, pp)
    let qdn = take(&pool, n)
    let tmp2 = take(&pool, pp * q)
    let tmp3 = take(&pool, n * q)
    let tmp5 = take(&pool, n * q)
    let tmp6 = take(&pool, n * q)
    let tmp10 = take(&pool, n * pp)
    let tmp11 = take(&pool, pp * q)
    let tmp12 = take(&pool, n * q)
    let tmp7 = take(&pool, q * q)
    let tmp13 = take(&pool, q * q)
    let tdpz = take(&pool, q * n)
    let tmpi = take(&pool, q * n)
    let tmpit = take(&pool, n * q)
    let w1 = take(&pool, n * q)
    let utm = take(&pool, nk * q)
    let ut = take(&pool, nk * q)
    let ui = take(&pool, k * q)
    let dui_i = take(&pool, k * q * q)
    let ufd = take(&pool, k)
    let psi = take(&pool, k * pp)
    let vpo = take(&pool, k * pp * pp)
    let w2t = take(&pool, nk * pp)
    let c1 = take(&pool, pp * q)
    let dc1 = take(&pool, pp * q)
    let dw2 = take(&pool, n * pp)
    let dm2m = take(&pool, n * pp)
    let tdm2m = take(&pool, pp * n)
    let c1di = take(&pool, pp * q)
    let vt7 = take(&pool, pp * pp)
    let vt = take(&pool, 8usize * pp)
    let mt = take(&pool, 8usize * q)
    let mt2 = take(&pool, 8usize * q)
    let delta = take(&pool, k * pp)
    let delta2 = take(&pool, k * q)
    let d2t = take(&pool, k)
    let tobs = take(&pool, 3usize * pp)
    let tgof = take(&pool, 2usize)
    let tsim = take(&pool, 3usize * pp * antsim)
    let gsim = take(&pool, antsim)
    let sorted = take(&pool, antsim)
    var l = 0usize
    var j = 0usize
    var c = 0usize
    var l1 = 0usize
    l = 0usize
    while l < q {
        beta[l] = beta0[l]
        betat[l] = beta0[l]
        l += 1usize
    }
    var alpha = alpha0
    var alphat = alpha0
    var del = 1000.0f64
    var delold = 10000.0f64
    var dum1 = 0.0f64
    var it = 0usize
    while del > tol && it < 50usize && dum1 < 1.0f64 {
        alpha = alphat
        if it < 2usize { alpha = 0.3f64 }
        j = 0usize
        while j < n {
            var bz = 0.0f64
            l = 0usize
            while l < q {
                bz += ex[j] * z[j * q + l] * beta[l]
                l += 1usize
            }
            phi[j] = ex[j] * math.exp[f64](bz)
            j += 1usize
        }
        l = 0usize
        while l < q {
            uinp[l] = 0.0f64
            l += 1usize
        }
        l = 0usize
        while l < q * q {
            du[l] = 0.0f64
            l += 1usize
        }
        i = 0usize
        while i < k {
            pe_design(t, x, z, ex, phi, evt[i], n, p, q, dn, xt, pxt, dxt, zm, pz, dpz)
            mtrans(zm, n, q, tz)
            mtrans(xt, n, pp, txt)
            mmul(tz, q, n, pxt, pp, tzpxt)
            mmul(txt, pp, n, xt, pp, txtxt)
            inv_guard(a, txtxt, pp, txtxti)
            mmul(txt, pp, n, dn, 1usize, txtdn)
            mmul(txtxti, pp, pp, txtdn, 1usize, v1)
            // score increment
            l = 0usize
            while l < q {
                var sc = 0.0f64
                j = 0usize
                while j < n {
                    sc += zm[j * q + l] * (phi[j] * dn[j])
                    j += 1usize
                }
                var sb = 0.0f64
                c = 0usize
                while c < pp {
                    sb += tzpxt[l * pp + c] * v1[c]
                    c += 1usize
                }
                ub[l] = sc - sb
                uinp[l] += ub[l]
                l += 1usize
            }
            // dU/dbeta
            mtrans(pz, n, q, tzp)
            mmul(xt, n, pp, v1, 1usize, qdn)
            j = 0usize
            while j < n {
                qdn[j] = dn[j] - qdn[j]
                j += 1usize
            }
            l = 0usize
            while l < pp * q {
                tmp2[l] = 0.0f64
                l += 1usize
            }
            l = 0usize
            while l < q {
                j = 0usize
                while j < n {
                    tmp2[p * q + l] += phi[j] * zm[j * q + l] * qdn[j]
                    j += 1usize
                }
                l += 1usize
            }
            j = 0usize
            while j < n * q {
                tmp3[j] = v1[p] * pz[j]
                j += 1usize
            }
            mmul(xt, n, pp, txtxti, pp, tmp10)
            mmul(txt, pp, n, tmp3, q, tmp11)
            mmul(tmp10, n, pp, tmp11, q, tmp12)
            mmul(tmp10, n, pp, tmp2, q, tmp5)
            j = 0usize
            while j < n * q {
                tmp6[j] = (tmp3[j] - tmp12[j]) + tmp5[j]
                j += 1usize
            }
            l = 0usize
            while l < q {
                l1 = 0usize
                while l1 < q {
                    var sm = 0.0f64
                    j = 0usize
                    while j < n {
                        sm += phi[j] * zm[j * q + l] * zm[j * q + l1] * qdn[j]
                        j += 1usize
                    }
                    tmp7[l * q + l1] = sm
                    l1 += 1usize
                }
                l += 1usize
            }
            mmul(tzp, q, n, tmp6, q, tmp13)
            l = 0usize
            while l < q * q {
                du[l] += tmp7[l] - tmp13[l]
                l += 1usize
            }
            mmul(tzpxt, q, pp, txtxti, pp, tzpxi)
            // the score process of every subject
            j = 0usize
            while j < n {
                c = 0usize
                while c < pp {
                    vt[c] = xt[j * pp + c] * dn[j]
                    c += 1usize
                }
                l = 0usize
                while l < q {
                    var sm = 0.0f64
                    c = 0usize
                    while c < pp {
                        sm += tzpxi[l * pp + c] * vt[c]
                        c += 1usize
                    }
                    mt[l] = pz[j * q + l] * dn[j] - sm
                    l += 1usize
                }
                l = 0usize
                while l < q {
                    if i < 1usize { w1[j * q + l] = mt[l] }
                    if i > 0usize { w1[j * q + l] += mt[l] }
                    l += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        l = 0usize
        while l < q {
            betam[l] = beta[l]
            l += 1usize
        }
        l = 0usize
        while l < q * q {
            dscore[l] = du[l]
            l += 1usize
        }
        var tau = 0.0f64
        if it < 2usize { tau = 1.0f64 }
        l = 0usize
        while l < q {
            du[l * q + l] -= tau
            l += 1usize
        }
        inv_guard(a, du, q, dui)
        l = 0usize
        while l < q * q {
            dui[l] = alpha * dui[l]
            l += 1usize
        }
        mmul(dui, q, q, uinp, 1usize, mt)
        if del < tol { dum1 = 2.0f64 }
        del = 0.0f64
        l = 0usize
        while l < q {
            del += uinp[l] * uinp[l]
            l += 1usize
        }
        del = math.sqrt[f64](del)
        l = 0usize
        while l < q {
            beta[l] = betam[l] - mt[l]
            l += 1usize
        }
        if del < tol {
            l = 0usize
            while l < q {
                beta[l] = betam[l]
                l += 1usize
            }
        }
        if delold < del && it > 2usize {
            alphat = 0.67f64 * alpha
            l = 0usize
            while l < q {
                beta[l] = betat[l]
                l += 1usize
            }
        }
        delold = del
        it += 1usize
    }
    // Psi and the robust variances at the final beta
    j = 0usize
    while j < n {
        var bz = 0.0f64
        l = 0usize
        while l < q {
            bz += ex[j] * z[j * q + l] * beta[l]
            l += 1usize
        }
        phi[j] = ex[j] * math.exp[f64](bz)
        j += 1usize
    }
    i = 0usize
    while i < k {
        pe_design(t, x, z, ex, phi, evt[i], n, p, q, dn, xt, pxt, dxt, zm, pz, dpz)
        mtrans(zm, n, q, tz)
        mtrans(xt, n, pp, txt)
        mmul(tz, q, n, pxt, pp, tzpxt)
        mmul(txt, pp, n, xt, pp, txtxt)
        inv_guard(a, txtxt, pp, txtxti)
        mmul(txt, pp, n, dn, 1usize, txtdn)
        mmul(txtxti, pp, pp, txtdn, 1usize, v1)
        c = 0usize
        while c < pp {
            var pv = 0.0f64
            if i > 0usize { pv = psi[(i - 1usize) * pp + c] }
            psi[i * pp + c] = pv + v1[c]
            c += 1usize
        }
        mmul(tzpxt, q, pp, txtxti, pp, tzpxi)
        // C1 += (v1[p] * tzpxi)'
        l = 0usize
        while l < q {
            c = 0usize
            while c < pp {
                c1[c * q + l] += v1[p] * tzpxi[l * pp + c]
                c += 1usize
            }
            l += 1usize
        }
        mmul(c1, pp, q, dui, q, c1di)
        l = 0usize
        while l < pp * pp {
            vt7[l] = 0.0f64
            l += 1usize
        }
        j = 0usize
        while j < n {
            c = 0usize
            while c < pp {
                vt[c] = xt[j * pp + c]
                c += 1usize
            }
            var dot = 0.0f64
            c = 0usize
            while c < pp {
                dot += v1[c] * vt[c]
                c += 1usize
            }
            let fac = dn[j] - dot
            c = 0usize
            while c < pp {
                vt[c] = fac * vt[c]
                c += 1usize
            }
            c = 0usize
            while c < pp {
                var sm = 0.0f64
                l = 0usize
                while l < pp {
                    sm += txtxti[c * pp + l] * vt[l]
                    l += 1usize
                }
                if i < 1usize { dw2[j * pp + c] = sm }
                if i > 0usize { dw2[j * pp + c] += sm }
                c += 1usize
            }
            c = 0usize
            while c < pp {
                var sm = 0.0f64
                l = 0usize
                while l < q {
                    sm += c1di[c * q + l] * w1[j * q + l]
                    l += 1usize
                }
                vt[c] = dw2[j * pp + c] - sm
                w2t[(j * k + i) * pp + c] = vt[c]
                c += 1usize
            }
            l = 0usize
            while l < pp {
                l1 = 0usize
                while l1 < pp {
                    vt7[l * pp + l1] += vt[l] * vt[l1]
                    l1 += 1usize
                }
                l += 1usize
            }
            j += 1usize
        }
        l = 0usize
        while l < pp * pp {
            vpo[i * pp * pp + l] = vt7[l]
            l += 1usize
        }
        i += 1usize
    }
    // the robust variance of beta, with the last step's scaled inverse
    l = 0usize
    while l < q * q {
        tmp7[l] = 0.0f64
        l += 1usize
    }
    j = 0usize
    while j < n {
        l = 0usize
        while l < q {
            l1 = 0usize
            while l1 < q {
                tmp7[l * q + l1] += w1[j * q + l] * w1[j * q + l1]
                l1 += 1usize
            }
            l += 1usize
        }
        j += 1usize
    }
    mtrans(dui, q, q, tmp13)
    mmul(dui, q, q, tmp7, q, optt)
    mmul(optt, q, q, tmp13, q, m1)
    // observed tests
    let k1 = k
    l = 0usize
    while l < pp {
        var o1 = 0.0f64
        var o2 = 0.0f64
        var o3 = 0.0f64
        i = 0usize
        while i < k1 {
            let vi = vpo[i * pp * pp + l * pp + l]
            let vk = vpo[(k1 - 1usize) * pp * pp + l * pp + l]
            let pv = psi[i * pp + l]
            o1 = cmax(o1, math.abs[f64](pv) / math.sqrt[f64](vi))
            o2 = cmax(o2, math.abs[f64](pv) * math.sqrt[f64](vk) / (vi + vk))
            o3 = o3 + pv * pv / vi
            i += 1usize
        }
        tobs[l] = o1
        tobs[pp + l] = o2
        tobs[2usize * pp + l] = o3
        l += 1usize
    }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let ru = rng.runif(&rg, 0.0f64, 1.0f64)
    let _ = ru
    var sim = 0usize
    while sim < antsim {
        l = 0usize
        while l < k * pp {
            delta[l] = 0.0f64
            l += 1usize
        }
        i = 0usize
        while i < n {
            let zz = rng.norm(&rg)
            s = 0usize
            while s < k {
                l = 0usize
                while l < pp {
                    delta[s * pp + l] += zz * w2t[(i * k + s) * pp + l]
                    l += 1usize
                }
                s += 1usize
            }
            i += 1usize
        }
        l = 0usize
        while l < pp {
            var o1 = 0.0f64
            var o2 = 0.0f64
            var o3 = 0.0f64
            i = 0usize
            while i < k1 {
                let vi = vpo[i * pp * pp + l * pp + l]
                let vk = vpo[(k1 - 1usize) * pp * pp + l * pp + l]
                let dv = delta[i * pp + l]
                o1 = cmax(o1, math.abs[f64](dv) / math.sqrt[f64](vi))
                o2 = cmax(o2, math.abs[f64](dv) * math.sqrt[f64](vk) / (vi + vk))
                o3 = o3 + dv * dv / vi
                i += 1usize
            }
            tsim[l * antsim + sim] = o1
            tsim[(pp + l) * antsim + sim] = o2
            tsim[(2usize * pp + l) * antsim + sim] = o3
            l += 1usize
        }
        sim += 1usize
    }
    // results
    var sec = 0usize
    while sec < 12usize {
        lens[sec] = 0usize
        sec += 1usize
    }
    var at = 0usize
    i = 0usize
    while i < k {
        out[at + i * (pp + 1usize)] = evt[i]
        out[at + k * (pp + 1usize) + i * (pp + 1usize)] = evt[i]
        c = 0usize
        while c < pp {
            out[at + i * (pp + 1usize) + c + 1usize] = psi[i * pp + c]
            out[at + k * (pp + 1usize) + i * (pp + 1usize) + c + 1usize] = vpo[i * pp * pp + c * pp + c]
            c += 1usize
        }
        i += 1usize
    }
    lens[0usize] = k * (pp + 1usize)
    lens[1usize] = k * (pp + 1usize)
    at += 2usize * k * (pp + 1usize)
    l = 0usize
    while l < q {
        out[at + l] = beta[l]
        l += 1usize
    }
    lens[2usize] = q
    at += q
    l = 0usize
    while l < q * q {
        out[at + l] = m1[l]
        out[at + q * q + pp + l] = dscore[l]
        l += 1usize
    }
    lens[3usize] = q * q
    lens[5usize] = q * q
    at += q * q
    // pval then score then HW, CM, quantiles
    l = 0usize
    while l < pp {
        out[at + l] = above(tsim[l * antsim..l * antsim + antsim], antsim, tobs[l])
        l += 1usize
    }
    lens[4usize] = pp
    at += pp + q * q
    l = 0usize
    while l < pp {
        out[at + l] = above(tsim[(pp + l) * antsim..(pp + l) * antsim + antsim], antsim, tobs[pp + l])
        out[at + pp + l] = above(tsim[(2usize * pp + l) * antsim..(2usize * pp + l) * antsim + antsim], antsim, tobs[2usize * pp + l])
        // quantile(sort(sims), 0.95), type 7
        var which = 0usize
        while which < 2usize {
            var base = l * antsim
            if which == 1usize { base = (pp + l) * antsim }
            sim = 0usize
            while sim < antsim {
                sorted[sim] = tsim[base + sim]
                sim += 1usize
            }
            sim = 1usize
            while sim < antsim {
                let v = sorted[sim]
                var jj = sim
                while jj > 0usize && sorted[jj - 1usize] > v {
                    sorted[jj] = sorted[jj - 1usize]
                    jj -= 1usize
                }
                sorted[jj] = v
                sim += 1usize
            }
            let idx = 1.0f64 + f64(antsim - 1usize) * 0.95f64
            let lo = math.floor[f64](idx)
            let hi = math.ceil[f64](idx)
            var qv = sorted[usize(lo) - 1usize]
            if idx > lo && sorted[usize(hi) - 1usize] != qv {
                let h = idx - lo
                qv = (1.0f64 - h) * qv + h * sorted[usize(hi) - 1usize]
            }
            out[at + 2usize * pp + which * pp + l] = qv
            which += 1usize
        }
        l += 1usize
    }
    lens[6usize] = pp
    lens[7usize] = pp
    lens[8usize] = pp
    lens[9usize] = pp
    at += 4usize * pp
    out[at] = f64(it)
    lens[10usize] = 1usize
    ret ok
}

// ---- comp.risk: competing-risks regression for the cause-specific cumulative incidence, P_1(t, x) = h(x'b(t)) by inverse-censoring-probability weighted estimating equations ----

// quantile(x, p), type 7, of an ascending x of length n
fn quant7(x: []const f64, n: usize, p: f64) -> f64 {
    let index = 1.0f64 + f64(n - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    var qs = x[usize(lo) - 1usize]
    if index > lo && x[usize(hi) - 1usize] != qs {
        let h = index - lo
        qs = (1.0f64 - h) * qs + h * x[usize(hi) - 1usize]
    }
    ret qs
}

// comp.risk(Event(t, st) ~ x-terms, cause, model, n.sim = antsim, n.times, first.time.p) with no const() terms, one cluster per subject, no weights, left truncation or time-varying
// design, Kaplan-Meier censoring weights (censoring code 0), estimator 1, conservative variance, after set.seed(seed). trans is the model code (1 additive, 2 prop, 3 logistic, 4 rcif, 5 rcif2, 6 fg,
// 7 logistic2), step the Newton step size (timereg's default: 0.5 for 2, 3, 7, else 1), tpow the time power of the constant-effect test (1 for additive, else 0). x is n by px, the intercept column included.
// out holds back to back, lens their lengths: 0 cum (time, then the px estimates, per grid time), 1 var.cum, 2 gamma2, 3 pval.testBeq0, 4 pval.testBeqC, 5 pval.testBeqC.is, 6 obs.testBeq0, 7 obs.testBeqC,
// 8 obs.testBeqC.is, 9 conf.band, 10 test.procBeqC (time, then px processes). lens[11] receives the number of grid times. A time point where the Newton iteration fails returns mem.Full.
fn comp_risk(a: *mem.Arena, t: []const f64, st: []const f64, x: []const f64, n: usize, px: usize, cause: f64, trans: usize, step: f64, nit: usize, ntm: usize, firstp: f64, antsim: usize, seed: i64, tpow: f64, out: []f64, lens: []usize) -> err {
    var m = 0usize
    var i = 0usize
    while i < n {
        if math.abs[f64](st[i]) == cause { m += 1usize }
        i += 1usize
    }
    if m < 3usize || antsim < 2usize || nit < 3usize { ret mem.Full }
    let (tc, e1) = mem.alloc[f64](a, m)
    let (gk, e2) = mem.alloc[f64](a, n)
    let (srt, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var c = 0usize
    i = 0usize
    while i < n {
        if math.abs[f64](st[i]) == cause {
            tc[c] = t[i]
            c += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let v = tc[i]
        var j = i
        while j > 0usize && tc[j - 1usize] > v {
            tc[j] = tc[j - 1usize]
            j -= 1usize
        }
        tc[j] = v
        i += 1usize
    }
    var nu = 0usize
    i = 0usize
    while i < m {
        if i == 0usize || tc[i] != tc[i - 1usize] {
            tc[nu] = tc[i]
            nu += 1usize
        }
        i += 1usize
    }
    var nt = nu
    if nu > ntm { nt = ntm }
    let (times, e4) = mem.alloc[f64](a, nt)
    if e4 != ok { ret mem.Full }
    i = 0usize
    while i < nt {
        if nu > ntm {
            var pr = firstp + f64(i) * ((1.0f64 - firstp) / f64(ntm - 1usize))
            if i == nt - 1usize { pr = 1.0f64 }
            times[i] = quant7(tc, nu, pr)
        } else {
            times[i] = tc[i]
        }
        i += 1usize
    }
    // Kaplan-Meier of the censoring times, G(T_j-)
    i = 0usize
    while i < n {
        srt[i] = t[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > v {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        var g = 1.0f64
        var u = 0usize
        while u < n {
            if (u == 0usize || srt[u] != srt[u - 1usize]) && srt[u] < t[i] {
                var dd = 0.0f64
                var rk = 0.0f64
                var l = 0usize
                while l < n {
                    if t[l] >= srt[u] { rk += 1.0f64 }
                    if t[l] == srt[u] && st[l] == 0.0f64 { dd += 1.0f64 }
                    l += 1usize
                }
                g = g * (1.0f64 - dd / rk)
            }
            u += 1usize
        }
        gk[i] = g
        i += 1usize
    }
    let q1 = px + 1usize
    let total = 3usize * n * px + 2usize * nt * q1 + n * nt * px + 40usize * px * px + 40usize * px + 3usize * antsim * px + 4usize * nt * q1 + 8usize * n + 3usize * n * px + 16usize
    let (buf, e5) = mem.alloc[f64](a, total)
    if e5 != ok { ret mem.Full }
    i = 0usize
    while i < total {
        buf[i] = 0.0f64
        i += 1usize
    }
    var pool: Pool = zero
    pool.buf = buf
    pool.at = 0usize
    let cx = take(&pool, n * px)
    let yv = take(&pool, n)
    let est = take(&pool, nt * q1)
    let vr = take(&pool, nt * q1)
    let cum_at = take(&pool, n * nt * px)
    let aa = take(&pool, px * px)
    let ai = take(&pool, px * px)
    let sc = take(&pool, px)
    let dbeta = take(&pool, px)
    let beta = take(&pool, px)
    let bet1 = take(&pool, px)
    let cuma = take(&pool, n * px)
    let dp2 = take(&pool, px)
    let vv = take(&pool, px * px)
    let ut = take(&pool, nt * q1)
    let tobs = take(&pool, 3usize * px)
    let tsim = take(&pool, 3usize * px * antsim)
    let gam = take(&pool, px)
    let cw = take(&pool, px)
    let gami = take(&pool, n * px)
    let dl = take(&pool, nt * px)
    let tm1 = take(&pool, px)
    let gt = take(&pool, px)
    let dx = take(&pool, px)
    var offd = 0.0f64
    var mind = 1.0e300f64
    var s = 0usize
    while s < nt {
        let time = times[s]
        est[s * q1] = time
        vr[s * q1] = time
        var k = 0usize
        while k < px {
            bet1[k] = 0.1f64
            beta[k] = 0.1f64
            k += 1usize
        }
        var it = 0usize
        while it < nit {
            i = 0usize
            while i < n {
                var bh = 0.0f64
                k = 0usize
                while k < px {
                    bh += x[i * px + k] * bet1[k]
                    k += 1usize
                }
                var pb = 0.0f64
                var dm = 1.0f64
                if trans == 1usize {
                    pb = 1.0f64 - math.exp[f64](0.0f64 - bh)
                    dm = 1.0f64 - pb
                }
                if trans == 2usize {
                    pb = 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](bh))
                    dm = (1.0f64 - pb) * math.exp[f64](bh)
                }
                if trans == 6usize {
                    pb = 1.0f64 - math.exp[f64](0.0f64 - bh)
                    dm = 1.0f64 - pb
                }
                if trans == 3usize {
                    pb = math.exp[f64](bh) / (1.0f64 + math.exp[f64](bh))
                    dm = math.exp[f64](bh) / math.pow[f64](1.0f64 + math.exp[f64](bh), 2.0f64)
                }
                if trans == 7usize {
                    pb = bh / (1.0f64 + bh)
                    dm = 1.0f64 / math.pow[f64](1.0f64 + bh, 2.0f64)
                }
                if trans == 4usize {
                    pb = math.exp[f64](bh)
                    dm = math.exp[f64](bh)
                }
                if trans == 5usize {
                    pb = bh
                    dm = 1.0f64
                }
                k = 0usize
                while k < px {
                    cx[i * px + k] = dm * x[i * px + k]
                    k += 1usize
                }
                var yy = 0.0f64
                if t[i] <= time && math.abs[f64](st[i]) == cause { yy = 1.0f64 }
                if st[i] < 0.0f64 { yy = 0.0f64 - yy }
                var ent = 1.0f64
                if !(time > 0.0f64) { ent = 0.0f64 }
                if gk[i] < 0.001f64 {
                    yy = yy / 0.001f64 - pb
                } else {
                    yy = (yy / gk[i] - pb) * ent
                }
                yv[i] = yy
                i += 1usize
            }
            var r = 0usize
            while r < px {
                var cc = 0usize
                while cc < px {
                    var sm = 0.0f64
                    i = 0usize
                    while i < n {
                        sm += cx[i * px + r] * cx[i * px + cc]
                        i += 1usize
                    }
                    aa[r * px + cc] = sm
                    cc += 1usize
                }
                r += 1usize
            }
            offd = 0.0f64
            mind = 1.0e300f64
            r = 0usize
            while r < px {
                if aa[r * px + r] < mind { mind = aa[r * px + r] }
                var cc = 0usize
                while cc < px {
                    if r != cc { offd += math.abs[f64](aa[r * px + cc]) }
                    cc += 1usize
                }
                r += 1usize
            }
            inv_guard(a, aa, px, ai)
            let diag = mind != 0.0f64 && !(offd > 0.0000001f64)
            if diag {
                r = 0usize
                while r < px {
                    ai[r * px + r] = 1.0f64 / aa[r * px + r]
                    r += 1usize
                }
            }
            if ai[0usize] == 0.0f64 && !diag { ret mem.Full }
            var ssum = 0.0f64
            r = 0usize
            while r < px {
                var sm = 0.0f64
                i = 0usize
                while i < n {
                    sm += cx[i * px + r] * yv[i]
                    i += 1usize
                }
                sc[r] = sm
                ssum += sm
                r += 1usize
            }
            r = 0usize
            while r < px {
                var sm = 0.0f64
                var cc = 0usize
                while cc < px {
                    sm += ai[r * px + cc] * sc[cc]
                    cc += 1usize
                }
                dbeta[r] = step * sm
                beta[r] += dbeta[r]
                r += 1usize
            }
            var sumscore = 0.0f64
            r = 0usize
            while r < px {
                sumscore += math.abs[f64](dbeta[r])
                r += 1usize
            }
            if sumscore < 0.000001f64 && it + 2usize < nit { it = nit - 2usize }
            if ssum != ssum || (sumscore > 0.5f64 && it == nit - 1usize) { ret mem.Full }
            r = 0usize
            while r < px {
                bet1[r] = beta[r]
                r += 1usize
            }
            it += 1usize
        }
        // the iid decomposition, one cluster per subject
        k = 0usize
        while k < px * px {
            vv[k] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            k = 0usize
            while k < px {
                cuma[i * px + k] = yv[i] * cx[i * px + k]
                k += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            var r = 0usize
            while r < px {
                var sm = 0.0f64
                var cc = 0usize
                while cc < px {
                    sm += ai[r * px + cc] * cuma[i * px + cc]
                    cc += 1usize
                }
                dp2[r] = sm
                cum_at[(i * nt + s) * px + r] = sm
                r += 1usize
            }
            r = 0usize
            while r < px {
                var cc = 0usize
                while cc < px {
                    vv[r * px + cc] += dp2[r] * dp2[cc]
                    cc += 1usize
                }
                r += 1usize
            }
            i += 1usize
        }
        k = 0usize
        while k < px {
            est[s * q1 + k + 1usize] = beta[k]
            vr[s * q1 + k + 1usize] = vv[k * px + k]
            k += 1usize
        }
        s += 1usize
    }
    // resampling tests, as timereg's comptestfunc
    let mtime = times[nt - 1usize]
    var k = 0usize
    while k < px {
        if math.abs[f64](tpow) < 0.000001f64 {
            s = 0usize
            while s < nt {
                if vr[s * q1 + k] > 0.0f64 {
                    let v = vr[s * q1 + k + 1usize]
                    if v > 0.0f64 {
                        cw[k] = cw[k] + 1.0f64 / v
                        gam[k] = gam[k] + est[s * q1 + k + 1usize] / v
                        i = 0usize
                        while i < n {
                            gami[i * px + k] = gami[i * px + k] + cum_at[(i * nt + s) * px + k] / v
                            i += 1usize
                        }
                    }
                }
                s += 1usize
            }
            gam[k] = gam[k] / cw[k]
            i = 0usize
            while i < n {
                gami[i * px + k] = gami[i * px + k] / cw[k]
                i += 1usize
            }
        } else {
            gam[k] = est[(nt - 1usize) * q1 + k + 1usize] / math.pow[f64](mtime, tpow)
            i = 0usize
            while i < n {
                gami[i * px + k] = cum_at[(i * nt + nt - 1usize) * px + k] / math.pow[f64](mtime, tpow)
                i += 1usize
            }
        }
        k += 1usize
    }
    ut[0usize] = times[0usize]
    s = 1usize
    while s < nt {
        let time = times[s]
        let dtime = times[s] - times[s - 1usize]
        k = 0usize
        while k < px {
            let xij = math.abs[f64](est[s * q1 + k + 1usize]) / math.sqrt[f64](vr[s * q1 + k + 1usize])
            if xij > tobs[k] { tobs[k] = xij }
            gt[k] = gam[k] * math.pow[f64](time, tpow)
            dx[k] = est[s * q1 + k + 1usize] - gt[k]
            k += 1usize
        }
        ut[s * q1] = times[s]
        k = 0usize
        while k < px {
            ut[s * q1 + k + 1usize] = dx[k]
            if math.abs[f64](dx[k]) > tobs[px + k] { tobs[px + k] = math.abs[f64](dx[k]) }
            tobs[2usize * px + k] = tobs[2usize * px + k] + dx[k] * dx[k] * dtime
            k += 1usize
        }
        s += 1usize
    }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let ru = rng.runif(&rg, 0.0f64, 1.0f64)
    let _ = ru
    var sim = 1usize
    while sim < antsim {
        k = 0usize
        while k < nt * px {
            dl[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < px {
            tm1[k] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            let zz = rng.norm(&rg)
            s = 0usize
            while s < nt {
                k = 0usize
                while k < px {
                    dl[s * px + k] += zz * cum_at[(i * nt + s) * px + k]
                    k += 1usize
                }
                s += 1usize
            }
            k = 0usize
            while k < px {
                tm1[k] += zz * gami[i * px + k]
                k += 1usize
            }
            i += 1usize
        }
        s = 1usize
        while s < nt {
            let time = times[s]
            let dtime = times[s] - times[s - 1usize]
            k = 0usize
            while k < px {
                let df = dl[s * px + k] - tm1[k] * math.pow[f64](time, tpow)
                let xv = math.abs[f64](dl[s * px + k]) / math.sqrt[f64](vr[s * q1 + k + 1usize])
                if xv > tsim[k * antsim + sim] { tsim[k * antsim + sim] = xv }
                if math.abs[f64](df) > tsim[(px + k) * antsim + sim] { tsim[(px + k) * antsim + sim] = math.abs[f64](df) }
                tsim[(2usize * px + k) * antsim + sim] = tsim[(2usize * px + k) * antsim + sim] + df * df * dtime
                k += 1usize
            }
            s += 1usize
        }
        sim += 1usize
    }
    var sec = 0usize
    while sec < 12usize {
        lens[sec] = 0usize
        sec += 1usize
    }
    var at = 0usize
    k = 0usize
    while k < nt * q1 {
        out[k] = est[k]
        out[nt * q1 + k] = vr[k]
        out[2usize * nt * q1 + 8usize * px + k] = ut[k]
        k += 1usize
    }
    lens[0usize] = nt * q1
    lens[1usize] = nt * q1
    at = 2usize * nt * q1
    k = 0usize
    while k < px {
        out[at + k] = gam[k]
        out[at + px + k] = above(tsim[k * antsim..k * antsim + antsim], antsim, tobs[k])
        out[at + 2usize * px + k] = above(tsim[(px + k) * antsim..(px + k) * antsim + antsim], antsim, tobs[px + k])
        out[at + 3usize * px + k] = above(tsim[(2usize * px + k) * antsim..(2usize * px + k) * antsim + antsim], antsim, tobs[2usize * px + k])
        out[at + 4usize * px + k] = tobs[k]
        out[at + 5usize * px + k] = tobs[px + k]
        out[at + 6usize * px + k] = tobs[2usize * px + k]
        out[at + 7usize * px + k] = pick95(tsim[k * antsim..k * antsim + antsim], antsim)
        k += 1usize
    }
    sec = 2usize
    while sec < 10usize {
        lens[sec] = px
        sec += 1usize
    }
    lens[10usize] = nt * q1
    lens[11usize] = nt
    ret ok
}
