// R plm for unbalanced panels with individual effects: the pooling, within, between, random (swar, walhus, amemiya, nerlove) and first-difference models with their classical covariance and the variance components; the Hausman, F, Lagrange multiplier, Breusch-Godfrey and Durbin-Watson tests; and the vcovG family (vcovHC, vcovSCC) of plm 2.6.
//
// Rows are ordered by individual then period; gid is 0..N-1 and tid is the period code 0..T-1. The regressors carry no constant: every model but within adds one first, as plm does.
//
// Not here: two-way effects in the models (time effects are the periods as groups), instrumental variables inside plm (see aerpkg for ivreg); pgmm is in plmgmm.

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.carlmtest as cl
use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

const POOLING: usize = 0usize
const WITHIN: usize = 1usize
const BETWEEN: usize = 2usize
const RANDOM: usize = 3usize
const FD: usize = 4usize

const SWAR: usize = 0usize
const WALHUS: usize = 1usize
const AMEMIYA: usize = 2usize
const NERLOVE: usize = 3usize

type Panel = struct { n: usize, nid: usize, k: usize, nper: usize, gid: []usize, tid: []usize, y: []f64, x: []f64 }

type Fit = struct { kk: usize, nr: usize, dfr: usize, coef: []f64, vc: []f64, xt: []f64, yt: []f64, res: []f64, gid: []usize, tid: []usize, rss: f64, s2e: f64, s2id: f64, theta: []f64, xi: []f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zeros_u(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0usize
        i += 1usize
    }
    ret (v, ok)
}

// the panel from flat columns: id and period labels (1-based numbers) as doubles, y, and x row-major
fn make(a: *mem.Arena, n: usize, k: usize, idf: []const f64, tmf: []const f64, y: []const f64, x: []const f64) -> ([]Panel, err) {
    let (pa, e0) = mem.alloc[Panel](a, 1usize)
    if e0 != ok { ret (pa, e0) }
    let (g, e1) = zeros_u(a, n)
    let (t, e2) = zeros_u(a, n)
    let (yy, e3) = zeros(a, n)
    let (xx, e4) = zeros(a, n * k)
    if e1 != ok { ret (pa, e1) }
    if e2 != ok { ret (pa, e2) }
    if e3 != ok { ret (pa, e3) }
    if e4 != ok { ret (pa, e4) }
    var nid = 0usize
    var nper = 0usize
    var i = 0usize
    while i < n {
        g[i] = usize(idf[i]) - 1usize
        t[i] = usize(tmf[i]) - 1usize
        if g[i] + 1usize > nid { nid = g[i] + 1usize }
        if t[i] + 1usize > nper { nper = t[i] + 1usize }
        yy[i] = y[i]
        var c = 0usize
        while c < k {
            xx[i * k + c] = x[i * k + c]
            c += 1usize
        }
        i += 1usize
    }
    pa[0usize].n = n
    pa[0usize].nid = nid
    pa[0usize].k = k
    pa[0usize].nper = nper
    pa[0usize].gid = g
    pa[0usize].tid = t
    pa[0usize].y = yy
    pa[0usize].x = xx
    ret (pa, ok)
}

// observations per individual, and the means of y and x per individual
fn id_means(p: *const Panel, ti: []f64, ym: []f64, xm: []f64) {
    var i = 0usize
    while i < p.nid {
        ti[i] = 0.0f64
        ym[i] = 0.0f64
        var c0 = 0usize
        while c0 < p.k {
            xm[i * p.k + c0] = 0.0f64
            c0 += 1usize
        }
        i += 1usize
    }
    var r = 0usize
    while r < p.n {
        let g = p.gid[r]
        ti[g] += 1.0f64
        ym[g] += p.y[r]
        var c1 = 0usize
        while c1 < p.k {
            xm[g * p.k + c1] += p.x[r * p.k + c1]
            c1 += 1usize
        }
        r += 1usize
    }
    i = 0usize
    while i < p.nid {
        ym[i] = ym[i] / ti[i]
        var c2 = 0usize
        while c2 < p.k {
            xm[i * p.k + c2] = xm[i * p.k + c2] / ti[i]
            c2 += 1usize
        }
        i += 1usize
    }
}

// OLS of yt on xt (nr by kk): coef, the inverse of xt'xt into xi, residuals into res; returns the residual sum of squares, NaN when singular
fn ols_core(a: *mem.Arena, xt: []const f64, yt: []const f64, nr: usize, kk: usize, coef: []f64, xi: []f64, res: []f64) -> f64 {
    let (g, e1) = zeros(a, kk * kk)
    let (rv, e2) = zeros(a, kk)
    if e1 != ok || e2 != ok { ret nan() }
    var t = 0usize
    while t < nr {
        var i = 0usize
        while i < kk {
            rv[i] += xt[t * kk + i] * yt[t]
            var j = 0usize
            while j < kk {
                g[i * kk + j] += xt[t * kk + i] * xt[t * kk + j]
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    let (inv, ie) = gp.invert(a, g, kk)
    if ie != ok { ret nan() }
    var i2 = 0usize
    while i2 < kk {
        var s = 0.0f64
        var j2 = 0usize
        while j2 < kk {
            xi[i2 * kk + j2] = inv[i2 * kk + j2]
            s += inv[i2 * kk + j2] * rv[j2]
            j2 += 1usize
        }
        coef[i2] = s
        i2 += 1usize
    }
    var rss = 0.0f64
    t = 0usize
    while t < nr {
        var f = 0.0f64
        var i3 = 0usize
        while i3 < kk {
            f += xt[t * kk + i3] * coef[i3]
            i3 += 1usize
        }
        res[t] = yt[t] - f
        rss += res[t] * res[t]
        t += 1usize
    }
    ret rss
}

// tr(A B) for m by m matrices
fn trace_prod(x: []const f64, y: []const f64, m: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            s += x[i * m + j] * y[j * m + i]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// the random-effects variance components for individual effects: sg = (sigma2 idiosyncratic, sigma2 individual), theta per individual
fn ercomp(a: *mem.Arena, p: *const Panel, method: usize, sg: []f64, theta: []f64) -> err {
    let n = p.n
    let nid = p.nid
    let k = p.k
    let kb = k + 1usize
    let of = f64(n)
    let nf = f64(nid)
    let kf = f64(k)
    let (ti, e1) = zeros(a, nid)
    let (ym, e2) = zeros(a, nid)
    let (xm, e3) = zeros(a, nid * k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    id_means(p, ti, ym, xm)
    let balanced = nid * p.nper == n
    // within fit
    let (xd, e4) = zeros(a, n * k)
    let (yd, e5) = zeros(a, n)
    let (bw, e6) = zeros(a, k)
    let (xiw, e7) = zeros(a, k * k)
    let (rw, e8) = zeros(a, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var r = 0usize
    while r < n {
        let g = p.gid[r]
        yd[r] = p.y[r] - ym[g]
        var c = 0usize
        while c < k {
            xd[r * k + c] = p.x[r * k + c] - xm[g * k + c]
            c += 1usize
        }
        r += 1usize
    }
    let rss_w = ols_core(a, xd, yd, n, k, bw, xiw, rw)
    if rss_w != rss_w { ret gp.Singular }
    var s2n = 0.0f64
    var s2h = 0.0f64
    var q1 = 0.0f64
    var q2 = 0.0f64
    var m11 = 0.0f64
    var m12 = 0.0f64
    var m21 = 0.0f64
    var m22 = 0.0f64
    if method == NERLOVE {
        s2n = rss_w / of
        var sw = 0.0f64
        let (fe, e9) = zeros(a, nid)
        if e9 != ok { ret e9 }
        var i = 0usize
        while i < nid {
            var f = ym[i]
            var c2 = 0usize
            while c2 < k {
                f -= xm[i * k + c2] * bw[c2]
                c2 += 1usize
            }
            fe[i] = f
            sw += ti[i] * f
            i += 1usize
        }
        let fm = sw / of
        var s = 0.0f64
        i = 0usize
        while i < nid {
            s += (fe[i] - fm) * (fe[i] - fm) * ti[i] / of
            i += 1usize
        }
        s2h = s * nf / (nf - 1.0f64)
        if balanced {
            s = 0.0f64
            i = 0usize
            while i < nid {
                s += (fe[i] - fm) * (fe[i] - fm)
                i += 1usize
            }
            s2h = s / (nf - 1.0f64)
        }
    } else {
        // the pooled and between regressions on z = (1, x)
        let (zz, e10) = zeros(a, kb * kb)
        let (zb, e11) = zeros(a, kb * kb)
        let (zs, e12) = zeros(a, kb * kb)
        let (zr, e13) = zeros(a, kb)
        let (zm, e14) = zeros(a, nid * kb)
        if e10 != ok { ret e10 }
        if e11 != ok { ret e11 }
        if e12 != ok { ret e12 }
        if e13 != ok { ret e13 }
        if e14 != ok { ret e14 }
        var i = 0usize
        while i < nid {
            zm[i * kb] = 1.0f64
            var c3 = 0usize
            while c3 < k {
                zm[i * kb + 1usize + c3] = xm[i * k + c3]
                c3 += 1usize
            }
            var u = 0usize
            while u < kb {
                var v = 0usize
                while v < kb {
                    zb[u * kb + v] += ti[i] * zm[i * kb + u] * zm[i * kb + v]
                    zs[u * kb + v] += ti[i] * ti[i] * zm[i * kb + u] * zm[i * kb + v]
                    v += 1usize
                }
                u += 1usize
            }
            i += 1usize
        }
        r = 0usize
        while r < n {
            let g = p.gid[r]
            var u2 = 0usize
            while u2 < kb {
                var zu = 1.0f64
                if u2 > 0usize { zu = p.x[r * k + u2 - 1usize] }
                zr[u2] += zu * p.y[r]
                var v2 = 0usize
                while v2 < kb {
                    var zv = 1.0f64
                    if v2 > 0usize { zv = p.x[r * k + v2 - 1usize] }
                    zz[u2 * kb + v2] += zu * zv
                    v2 += 1usize
                }
                u2 += 1usize
            }
            r += 1usize
        }
        let (zzi, e15) = gp.invert(a, zz, kb)
        if e15 != ok { ret e15 }
        if method == SWAR {
            // unweighted between regression on the individual means
            let (xb, e16) = zeros(a, nid * kb)
            let (yb, e17) = zeros(a, nid)
            let (bb, e18) = zeros(a, kb)
            let (xib, e19) = zeros(a, kb * kb)
            let (rb, e20) = zeros(a, nid)
            if e16 != ok { ret e16 }
            if e17 != ok { ret e17 }
            if e18 != ok { ret e18 }
            if e19 != ok { ret e19 }
            if e20 != ok { ret e20 }
            // plm regresses the expanded individual means, which weights each individual by Ti
            i = 0usize
            while i < nid {
                yb[i] = ym[i] * math.sqrt[f64](ti[i])
                var c4 = 0usize
                while c4 < kb {
                    xb[i * kb + c4] = zm[i * kb + c4] * math.sqrt[f64](ti[i])
                    c4 += 1usize
                }
                i += 1usize
            }
            let rss_b = ols_core(a, xb, yb, nid, kb, bb, xib, rb)
            if rss_b != rss_b { ret gp.Singular }
            q1 = rss_w
            i = 0usize
            while i < nid {
                q2 += rb[i] * rb[i]
                i += 1usize
            }
            let (zbi, e21) = gp.invert(a, zb, kb)
            if e21 != ok { ret e21 }
            let (pm, e22) = gp.matmul(a, zbi, zs, kb, kb, kb)
            if e22 != ok { ret e22 }
            var trc = 0.0f64
            i = 0usize
            while i < kb {
                trc += pm[i * kb + i]
                i += 1usize
            }
            m11 = of - nf - kf
            m21 = nf - kf - 1.0f64
            m22 = of - trc
        }
        if method == WALHUS {
            let (bp, e23) = zeros(a, kb)
            let (ep, e24) = zeros(a, n)
            if e23 != ok { ret e23 }
            if e24 != ok { ret e24 }
            // pooled residuals
            var u3 = 0usize
            while u3 < kb {
                var sb = 0.0f64
                var v3 = 0usize
                while v3 < kb {
                    sb += zzi[u3 * kb + v3] * zr[v3]
                    v3 += 1usize
                }
                bp[u3] = sb
                u3 += 1usize
            }
            let (em, e25) = zeros(a, nid)
            if e25 != ok { ret e25 }
            r = 0usize
            while r < n {
                var f2 = p.y[r] - bp[0usize]
                var c5 = 0usize
                while c5 < k {
                    f2 -= p.x[r * k + c5] * bp[1usize + c5]
                    c5 += 1usize
                }
                ep[r] = f2
                em[p.gid[r]] += f2 / ti[p.gid[r]]
                r += 1usize
            }
            r = 0usize
            while r < n {
                let d = ep[r] - em[p.gid[r]]
                q1 += d * d
                r += 1usize
            }
            i = 0usize
            while i < nid {
                q2 += ti[i] * em[i] * em[i]
                i += 1usize
            }
            if balanced {
                m11 = of - nf
                m21 = nf
                m22 = of
            } else {
                // CPZW is the pooled cross product less its between part
                let (zw, e26) = zeros(a, kb * kb)
                if e26 != ok { ret e26 }
                var u4 = 0usize
                while u4 < kb * kb {
                    zw[u4] = zz[u4] - zb[u4]
                    u4 += 1usize
                }
                let (pw, e27) = gp.matmul(a, zzi, zw, kb, kb, kb)
                let (ps, e28) = gp.matmul(a, zzi, zs, kb, kb, kb)
                let (pbm, e29) = gp.matmul(a, zzi, zb, kb, kb, kb)
                if e27 != ok { ret e27 }
                if e28 != ok { ret e28 }
                if e29 != ok { ret e29 }
                m11 = of - nf - trace_of(pw, kb)
                m12 = trace_prod(pw, ps, kb)
                m21 = nf - trace_of(pbm, kb)
                m22 = of - 2.0f64 * trace_of(ps, kb) + trace_prod(pbm, ps, kb)
            }
        }
        if method == AMEMIYA {
            q1 = rss_w
            let (em2, e30) = zeros(a, nid)
            if e30 != ok { ret e30 }
            r = 0usize
            while r < n {
                var f3 = p.y[r]
                var c6 = 0usize
                while c6 < k {
                    f3 -= p.x[r * k + c6] * bw[c6]
                    c6 += 1usize
                }
                em2[p.gid[r]] += f3 / ti[p.gid[r]]
                r += 1usize
            }
            // plm takes the within model's residuals with the overall mean put back, so they average to zero
            var gm = 0.0f64
            i = 0usize
            while i < nid {
                gm += ti[i] * em2[i] / of
                i += 1usize
            }
            i = 0usize
            while i < nid {
                q2 += ti[i] * (em2[i] - gm) * (em2[i] - gm)
                i += 1usize
            }
            if balanced {
                m11 = of - nf
                m21 = nf
                m22 = of
            } else {
                // trace of (Xw'Xw)^-1 times the between cross product of the centred means
                let (mu, e31) = zeros(a, k)
                let (cb, e32) = zeros(a, k * k)
                if e31 != ok { ret e31 }
                if e32 != ok { ret e32 }
                i = 0usize
                while i < nid {
                    var c7 = 0usize
                    while c7 < k {
                        mu[c7] += ti[i] * xm[i * k + c7] / of
                        c7 += 1usize
                    }
                    i += 1usize
                }
                i = 0usize
                while i < nid {
                    var u5 = 0usize
                    while u5 < k {
                        var v5 = 0usize
                        while v5 < k {
                            cb[u5 * k + v5] += ti[i] * (xm[i * k + u5] - mu[u5]) * (xm[i * k + v5] - mu[v5])
                            v5 += 1usize
                        }
                        u5 += 1usize
                    }
                    i += 1usize
                }
                var s2t = 0.0f64
                i = 0usize
                while i < nid {
                    s2t += ti[i] * ti[i]
                    i += 1usize
                }
                m11 = of - nf - kf
                m21 = nf - 1.0f64 + trace_prod(xiw, cb, k)
                m22 = of - s2t / of
            }
        }
        // solve the 2 by 2 system [m11 m12; m21 m22] sigma = (q1, q2)
        let det = m11 * m22 - m12 * m21
        s2n = (q1 * m22 - m12 * q2) / det
        s2h = (m11 * q2 - m21 * q1) / det
        if s2n < 0.0f64 { s2n = 0.0f64 }
        if s2h < 0.0f64 { s2h = 0.0f64 }
    }
    sg[0usize] = s2n
    sg[1usize] = s2h
    var i5 = 0usize
    while i5 < nid {
        theta[i5] = 1.0f64 - 1.0f64 / math.sqrt[f64](1.0f64 + ti[i5] * s2h / s2n)
        i5 += 1usize
    }
    ret ok
}

// the trace of an m by m matrix
fn trace_of(x: []const f64, m: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += x[i * m + i]
        i += 1usize
    }
    ret s
}

// fills f for the model (POOLING, WITHIN, BETWEEN, RANDOM, FD); method matters for RANDOM only
fn fit_model(a: *mem.Arena, p: *const Panel, model: usize, method: usize, f: *Fit) -> err {
    let n = p.n
    let k = p.k
    let nid = p.nid
    var kk = k + 1usize
    var nr = n
    if model == WITHIN { kk = k }
    if model == BETWEEN { nr = nid }
    var nfd = 0usize
    if model == FD {
        var r0 = 1usize
        while r0 < n {
            if p.gid[r0] == p.gid[r0 - 1usize] && p.tid[r0] == p.tid[r0 - 1usize] + 1usize { nfd += 1usize }
            r0 += 1usize
        }
        nr = nfd
    }
    let (xt, e1) = zeros(a, nr * kk)
    let (yt, e2) = zeros(a, nr)
    let (co, e3) = zeros(a, kk)
    let (xi, e4) = zeros(a, kk * kk)
    let (rs, e5) = zeros(a, nr)
    let (gi, e6) = zeros_u(a, nr)
    let (ti2, e7) = zeros_u(a, nr)
    let (th, e8) = zeros(a, nid)
    let (ti, e9) = zeros(a, nid)
    let (ym, e10) = zeros(a, nid)
    let (xm, e11) = zeros(a, nid * k)
    let (vc, e12) = zeros(a, kk * kk)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    id_means(p, ti, ym, xm)
    let (sg, e13) = zeros(a, 2usize)
    if e13 != ok { ret e13 }
    var dfr = nr - kk
    if model == POOLING {
        var r = 0usize
        while r < n {
            xt[r * kk] = 1.0f64
            var c = 0usize
            while c < k {
                xt[r * kk + 1usize + c] = p.x[r * k + c]
                c += 1usize
            }
            yt[r] = p.y[r]
            gi[r] = p.gid[r]
            ti2[r] = p.tid[r]
            r += 1usize
        }
    }
    if model == WITHIN {
        dfr = n - nid - k
        var r = 0usize
        while r < n {
            let g = p.gid[r]
            var c = 0usize
            while c < k {
                xt[r * kk + c] = p.x[r * k + c] - xm[g * k + c]
                c += 1usize
            }
            yt[r] = p.y[r] - ym[g]
            gi[r] = g
            ti2[r] = p.tid[r]
            r += 1usize
        }
    }
    if model == BETWEEN {
        var i = 0usize
        while i < nid {
            xt[i * kk] = 1.0f64
            var c = 0usize
            while c < k {
                xt[i * kk + 1usize + c] = xm[i * k + c]
                c += 1usize
            }
            yt[i] = ym[i]
            gi[i] = i
            i += 1usize
        }
    }
    if model == RANDOM {
        let ec = ercomp(a, p, method, sg, th)
        if ec != ok { ret ec }
        var r = 0usize
        while r < n {
            let g = p.gid[r]
            xt[r * kk] = 1.0f64 - th[g]
            var c = 0usize
            while c < k {
                xt[r * kk + 1usize + c] = p.x[r * k + c] - th[g] * xm[g * k + c]
                c += 1usize
            }
            yt[r] = p.y[r] - th[g] * ym[g]
            gi[r] = g
            ti2[r] = p.tid[r]
            r += 1usize
        }
    }
    if model == FD {
        var w = 0usize
        var r = 1usize
        while r < n {
            if p.gid[r] == p.gid[r - 1usize] && p.tid[r] == p.tid[r - 1usize] + 1usize {
                xt[w * kk] = 1.0f64
                var c = 0usize
                while c < k {
                    xt[w * kk + 1usize + c] = p.x[r * k + c] - p.x[(r - 1usize) * k + c]
                    c += 1usize
                }
                yt[w] = p.y[r] - p.y[r - 1usize]
                gi[w] = p.gid[r]
                ti2[w] = p.tid[r]
                w += 1usize
            }
            r += 1usize
        }
    }
    let rss = ols_core(a, xt, yt, nr, kk, co, xi, rs)
    if rss != rss { ret gp.Singular }
    let s2 = rss / f64(dfr)
    var u = 0usize
    while u < kk * kk {
        vc[u] = s2 * xi[u]
        u += 1usize
    }
    f.kk = kk
    f.nr = nr
    f.dfr = dfr
    f.coef = co
    f.vc = vc
    f.xi = xi
    f.xt = xt
    f.yt = yt
    f.res = rs
    f.gid = gi
    f.tid = ti2
    f.rss = rss
    f.s2e = s2
    f.s2id = 0.0f64
    f.theta = th
    if model == RANDOM {
        f.s2e = sg[0usize]
        f.s2id = sg[1usize]
    }
    ret ok
}

// the Hausman statistic of the within against the random model, out = (statistic, degrees of freedom)
fn phtest(a: *mem.Arena, p: *const Panel, method: usize, out: []f64) -> err {
    let k = p.k
    let (fw, e0) = mem.alloc[Fit](a, 2usize)
    if e0 != ok { ret e0 }
    let e1 = fit_model(a, p, WITHIN, 0usize, &fw[0usize])
    if e1 != ok { ret e1 }
    let e2 = fit_model(a, p, RANDOM, method, &fw[1usize])
    if e2 != ok { ret e2 }
    let (db, e3) = zeros(a, k)
    let (dv, e4) = zeros(a, k * k)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < k {
        db[i] = fw[0usize].coef[i] - fw[1usize].coef[i + 1usize]
        var j = 0usize
        while j < k {
            dv[i * k + j] = fw[0usize].vc[i * k + j] - fw[1usize].vc[(i + 1usize) * fw[1usize].kk + j + 1usize]
            j += 1usize
        }
        i += 1usize
    }
    let (di, e5) = gp.invert(a, dv, k)
    if e5 != ok { ret e5 }
    var s = 0.0f64
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            s += db[i] * di[i * k + j] * db[j]
            j += 1usize
        }
        i += 1usize
    }
    out[0usize] = math.abs[f64](s)
    out[1usize] = f64(k)
    ret ok
}

// the F statistic of the individual effects (within against pooling), out = (F, df1, df2)
fn pftest(a: *mem.Arena, p: *const Panel, out: []f64) -> err {
    let (fw, e0) = mem.alloc[Fit](a, 2usize)
    if e0 != ok { ret e0 }
    let e1 = fit_model(a, p, WITHIN, 0usize, &fw[0usize])
    if e1 != ok { ret e1 }
    let e2 = fit_model(a, p, POOLING, 0usize, &fw[1usize])
    if e2 != ok { ret e2 }
    let df1 = f64(fw[1usize].dfr - fw[0usize].dfr)
    let df2 = f64(fw[0usize].dfr)
    out[0usize] = (fw[1usize].rss - fw[0usize].rss) / fw[0usize].rss / df1 * df2
    out[1usize] = df1
    out[2usize] = df2
    ret ok
}

// the Lagrange multiplier statistics of plmtest on the pooled residuals: out = (LM1 individual, LM2 time, M11, M22)
fn plm_lm(a: *mem.Arena, p: *const Panel, out: []f64) -> err {
    let (fw, e0) = mem.alloc[Fit](a, 1usize)
    if e0 != ok { ret e0 }
    let e1 = fit_model(a, p, POOLING, 0usize, &fw[0usize])
    if e1 != ok { ret e1 }
    let (si, e2) = zeros(a, p.nid)
    let (st, e3) = zeros(a, p.nper)
    let (ci, e4) = zeros(a, p.nid)
    let (ct, e5) = zeros(a, p.nper)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var r = 0usize
    while r < p.n {
        si[p.gid[r]] += fw[0usize].res[r]
        st[p.tid[r]] += fw[0usize].res[r]
        ci[p.gid[r]] += 1.0f64
        ct[p.tid[r]] += 1.0f64
        r += 1usize
    }
    var a1 = 0.0f64
    var a2 = 0.0f64
    var m11 = 0.0f64
    var m22 = 0.0f64
    var i = 0usize
    while i < p.nid {
        a1 += si[i] * si[i]
        m11 += ci[i] * ci[i]
        i += 1usize
    }
    i = 0usize
    while i < p.nper {
        a2 += st[i] * st[i]
        m22 += ct[i] * ct[i]
        i += 1usize
    }
    let of = f64(p.n)
    a1 = a1 / fw[0usize].rss - 1.0f64
    a2 = a2 / fw[0usize].rss - 1.0f64
    out[0usize] = of / math.sqrt[f64](2.0f64 * (m11 - of)) * a1
    out[1usize] = of / math.sqrt[f64](2.0f64 * (m22 - of)) * a2
    out[2usize] = m11
    out[3usize] = m22
    ret ok
}

// the Breusch-Godfrey statistic of y on x (nr by kk, the constant already in x) with lags 1..order of the residuals, zero filled; out = (LM, df)
fn bgtest(a: *mem.Arena, x: []const f64, y: []const f64, nr: usize, kk: usize, order: usize, out: []f64) -> err {
    let (co, e1) = zeros(a, kk)
    let (xi, e2) = zeros(a, kk * kk)
    let (rs, e3) = zeros(a, nr)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    let rss = ols_core(a, x, y, nr, kk, co, xi, rs)
    if rss != rss { ret gp.Singular }
    let k2 = kk + order
    let (xz, e4) = zeros(a, nr * k2)
    let (c2, e5) = zeros(a, k2)
    let (xi2, e6) = zeros(a, k2 * k2)
    let (r2, e7) = zeros(a, nr)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var t = 0usize
    while t < nr {
        var c = 0usize
        while c < kk {
            xz[t * k2 + c] = x[t * kk + c]
            c += 1usize
        }
        var l = 1usize
        while l <= order {
            if t >= l { xz[t * k2 + kk + l - 1usize] = rs[t - l] }
            l += 1usize
        }
        t += 1usize
    }
    let rss2 = ols_core(a, xz, rs, nr, k2, c2, xi2, r2)
    if rss2 != rss2 { ret gp.Singular }
    var fit2 = 0.0f64
    t = 0usize
    while t < nr {
        let d = rs[t] - r2[t]
        fit2 += d * d
        t += 1usize
    }
    out[0usize] = f64(nr) * fit2 / rss
    out[1usize] = f64(order)
    ret ok
}

// the model's own transformed regression (all columns kept) through bgtest; the pbgtest of plm
fn pbgtest(a: *mem.Arena, p: *const Panel, model: usize, method: usize, order: usize, out: []f64) -> err {
    let (fw, e0) = mem.alloc[Fit](a, 1usize)
    if e0 != ok { ret e0 }
    let e1 = fit_model(a, p, model, method, &fw[0usize])
    if e1 != ok { ret e1 }
    ret bgtest(a, fw[0usize].xt, fw[0usize].yt, fw[0usize].nr, fw[0usize].kk, order, out)
}

// the Durbin-Watson statistic of the model's transformed regression residuals (stacked, boundaries ignored as in plm)
fn pdwtest(a: *mem.Arena, p: *const Panel, model: usize, method: usize) -> f64 {
    let (fw, e0) = mem.alloc[Fit](a, 1usize)
    if e0 != ok { ret nan() }
    if fit_model(a, p, model, method, &fw[0usize]) != ok { ret nan() }
    var num = 0.0f64
    var t = 1usize
    while t < fw[0usize].nr {
        let d = fw[0usize].res[t] - fw[0usize].res[t - 1usize]
        num += d * d
        t += 1usize
    }
    ret num / fw[0usize].rss
}

// lmtest's pan.f (Farebrother AS 153, Clint Cummins' 1996 revision) for c = 0: a[0] is x, a[1..m] the eigenvalues; n terms. Returns P(sum a_i u_i^2 < x sum u_i^2)
fn pan(a: []const f64, m: i64, n: i64) -> f64 {
    let x = a[0usize]
    var h = 1i64
    var kk = 1i64
    var ie = m
    if a[1usize] > a[usize(m)] {
        h = m
        kk = 0i64 - 1i64
        ie = 1i64
    }
    var nu = h
    var found = false
    while true {
        if a[usize(nu)] >= x {
            found = true
            break
        }
        if nu == ie { break }
        nu += kk
    }
    if !found { ret 1.0f64 }
    if nu == h { ret 0.0f64 }
    if kk == 1i64 { nu -= 1i64 }
    h = m - nu
    let y0 = h - nu
    var d = 0i64 - 2i64
    var j1 = m - 2i64
    var j2 = m - 1i64
    var j3 = m + 1i64
    var j4 = m
    if y0 >= 0i64 {
        d = 2i64
        h = nu
        kk = 0i64 - kk
        j1 = 0i64
        j2 = 2i64
        j3 = 3i64
        j4 = 1i64
    } else {
        nu += 1i64
    }
    let pin = 2.0f64 * math.atan[f64](1.0f64) / f64(n)
    var sum = 0.5f64 * f64(kk + 1i64)
    var sgn = f64(kk) / f64(n)
    let n2 = n + n - 1i64
    var l1 = h - 2i64 * (h / 2i64)
    while l1 >= 0i64 {
        var l2 = j2
        while (d > 0i64 && l2 <= nu) || (d < 0i64 && l2 >= nu) {
            let s1 = a[usize(j4)]
            let pr = a[usize(l2)]
            let u = 0.5f64 * (s1 + pr)
            let v = 0.5f64 * (s1 - pr)
            var acc = 0.0f64
            var i = 1i64
            while i <= n2 {
                let y = u - v * math.cos[f64](f64(i) * pin)
                let num = y - x
                var prod = 1.0f64
                var q = 1i64
                while q <= j1 {
                    prod = prod * num / (y - a[usize(q)])
                    q += 1i64
                }
                q = j3
                while q <= m {
                    prod = prod * num / (y - a[usize(q)])
                    q += 1i64
                }
                acc += math.sqrt[f64](math.abs[f64](prod))
                i += 2i64
            }
            sgn = 0.0f64 - sgn
            sum += sgn * acc
            j1 += d
            j3 += d
            j4 += d
            l2 += d
        }
        if d == 2i64 {
            j3 -= 1i64
        } else {
            j1 += 1i64
        }
        j2 = 0i64
        nu = 0i64
        l1 -= 1i64
    }
    ret sum
}

// the p value of lmtest::dwtest (alternative greater) on the model's transformed regression: pan with the n - kk leading eigenvalues of M A for n < 100, else the normal approximation
fn pdwtest_p(a: *mem.Arena, p: *const Panel, model: usize, method: usize) -> f64 {
    let (fw, e0) = mem.alloc[Fit](a, 1usize)
    if e0 != ok { ret nan() }
    if fit_model(a, p, model, method, &fw[0usize]) != ok { ret nan() }
    let f = &fw[0usize]
    let n = f.nr
    let kk = f.kk
    let dw = pdwtest(a, p, model, method)
    if n >= 100usize {
        let (_d, pv) = cl.dw_approx(a, f.xt, f.yt, n, kk, 0usize)
        ret pv
    }
    let (mm, e1) = zeros(a, n * n)
    let (am, e2) = zeros(a, n * n)
    let (b, e3) = zeros(a, n * n)
    let (w, e4) = zeros(a, n)
    let (z, e5) = zeros(a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan() }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var q1 = 0usize
            while q1 < kk {
                var q2 = 0usize
                while q2 < kk {
                    s += f.xt[i * kk + q1] * f.xi[q1 * kk + q2] * f.xt[j * kk + q2]
                    q2 += 1usize
                }
                q1 += 1usize
            }
            mm[i * n + j] = 0.0f64 - s
            if i == j { mm[i * n + j] += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    // A M with A the tridiagonal (1, 2 .. 2, 1; -1 beside)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 2.0f64 * mm[i * n + j]
            if i == 0usize || i == n - 1usize { s = mm[i * n + j] }
            if i > 0usize { s -= mm[(i - 1usize) * n + j] }
            if i + 1usize < n { s -= mm[(i + 1usize) * n + j] }
            am[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += mm[i * n + l] * am[l * n + j]
                l += 1usize
            }
            b[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            let sv = 0.5f64 * (b[i * n + j] + b[j * n + i])
            b[i * n + j] = sv
            b[j * n + i] = sv
            j += 1usize
        }
        i += 1usize
    }
    if sy.dsyevr_all(a, b, n, w, z) != ok { ret nan() }
    let (av, e6) = zeros(a, n + 1usize)
    if e6 != ok { ret nan() }
    av[0usize] = dw
    var m = 0usize
    i = 0usize
    while i < n - kk {
        let ev = w[n - 1usize - i]
        if ev > 1.0e-10f64 {
            m += 1usize
            av[m] = ev
        }
        i += 1usize
    }
    if m == 0usize { ret nan() }
    let pv = pan(av, i64(m), 15i64)
    if pv != pv || pv > 1.0f64 || pv < 0.0f64 {
        let (_d, pa) = cl.dw_approx(a, f.xt, f.yt, n, kk, 0usize)
        ret pa
    }
    ret pv
}

// the cluster-robust covariance of plm's vcovG into out (kk by kk). typ: 0 HC0, 1 sss, 2 HC1, 3 HC2, 4 HC3, 5 HC4; clus: 0 group, 1 time; inner: 0 cluster, 1 white, 2 diagavg; lag is the order l
fn vcov_g(a: *mem.Arena, f: *const Fit, typ: usize, clus: usize, lag: usize, inner: usize, out: []f64) -> err {
    let nr = f.nr
    let kk = f.kk
    // cluster code per row, compressed to 0..nc-1 in ascending order of the code, and the other index as label
    var big = 0usize
    var r = 0usize
    while r < nr {
        var cc = f.gid[r]
        if clus == 1usize { cc = f.tid[r] }
        if cc + 1usize > big { big = cc + 1usize }
        r += 1usize
    }
    let (cnt, e1) = zeros_u(a, big)
    if e1 != ok { ret e1 }
    r = 0usize
    while r < nr {
        var cc = f.gid[r]
        if clus == 1usize { cc = f.tid[r] }
        cnt[cc] += 1usize
        r += 1usize
    }
    var nc = 0usize
    let (rank, e2) = zeros_u(a, big)
    if e2 != ok { ret e2 }
    var q = 0usize
    while q < big {
        if cnt[q] > 0usize {
            rank[q] = nc
            nc += 1usize
        }
        q += 1usize
    }
    // rows of each cluster, in row order
    let (start, e3) = zeros_u(a, nc + 1usize)
    let (rows, e4) = zeros_u(a, nr)
    let (fillp, e5) = zeros_u(a, nc)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    q = 0usize
    var acc = 0usize
    while q < big {
        if cnt[q] > 0usize {
            start[rank[q]] = acc
            acc += cnt[q]
        }
        q += 1usize
    }
    start[nc] = nr
    r = 0usize
    while r < nr {
        var cc = f.gid[r]
        if clus == 1usize { cc = f.tid[r] }
        let ci = rank[cc]
        rows[start[ci] + fillp[ci]] = r
        fillp[ci] += 1usize
        r += 1usize
    }
    // the adjusted residuals
    let (uh, e6) = zeros(a, nr)
    if e6 != ok { ret e6 }
    let nt = f64(nr)
    let kf = f64(kk)
    var gg = nt
    if inner == 0usize { gg = f64(nc) }
    var hat: []f64 = uh
    if typ >= 3usize {
        let (xx, e7) = zeros(a, kk * kk)
        if e7 != ok { ret e7 }
        r = 0usize
        while r < nr {
            var u = 0usize
            while u < kk {
                var v = 0usize
                while v < kk {
                    xx[u * kk + v] += f.xt[r * kk + u] * f.xt[r * kk + v]
                    v += 1usize
                }
                u += 1usize
            }
            r += 1usize
        }
        let (xxi, e8) = gp.invert(a, xx, kk)
        if e8 != ok { ret e8 }
        let (h, e9) = zeros(a, nr)
        if e9 != ok { ret e9 }
        r = 0usize
        while r < nr {
            var s = 0.0f64
            var u2 = 0usize
            while u2 < kk {
                var v2 = 0usize
                while v2 < kk {
                    s += f.xt[r * kk + u2] * xxi[u2 * kk + v2] * f.xt[r * kk + v2]
                    v2 += 1usize
                }
                u2 += 1usize
            }
            h[r] = s
            r += 1usize
        }
        hat = h
    }
    var hsum = 0.0f64
    r = 0usize
    while r < nr {
        hsum += hat[r]
        r += 1usize
    }
    let hround = math.floor[f64](hsum + 0.5f64)
    r = 0usize
    while r < nr {
        var w = 1.0f64
        if typ == 1usize { w = math.sqrt[f64](gg / (gg - 1.0f64) * ((nt - 1.0f64) / (nt - kf))) }
        if typ == 2usize { w = math.sqrt[f64](nt / (nt - kf)) }
        if typ == 3usize { w = 1.0f64 / math.sqrt[f64](1.0f64 - hat[r]) }
        if typ == 4usize { w = 1.0f64 / (1.0f64 - hat[r]) }
        if typ == 5usize {
            var ex = nt * hat[r] / hround
            if ex > 4.0f64 { ex = 4.0f64 }
            w = 1.0f64 / math.pow[f64](math.sqrt[f64](1.0f64 - hat[r]), ex)
        }
        uh[r] = f.res[r] * w
        r += 1usize
    }
    // the sum over clusters of X_i' E(u_i, u_{i-l}) X_{i-l}
    let (sl, e10) = zeros(a, kk * kk)
    let (sa, e11) = zeros(a, kk)
    let (sb, e12) = zeros(a, kk)
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    var ci2 = lag
    while ci2 < nc {
        let cj = ci2 - lag
        if inner == 0usize {
            var c = 0usize
            while c < kk {
                sa[c] = 0.0f64
                sb[c] = 0.0f64
                c += 1usize
            }
            var ra = start[ci2]
            while ra < start[ci2 + 1usize] {
                let row = rows[ra]
                var c1 = 0usize
                while c1 < kk {
                    sa[c1] += f.xt[row * kk + c1] * uh[row]
                    c1 += 1usize
                }
                ra += 1usize
            }
            var rb = start[cj]
            while rb < start[cj + 1usize] {
                let row = rows[rb]
                var c2 = 0usize
                while c2 < kk {
                    sb[c2] += f.xt[row * kk + c2] * uh[row]
                    c2 += 1usize
                }
                rb += 1usize
            }
            var u3 = 0usize
            while u3 < kk {
                var v3 = 0usize
                while v3 < kk {
                    sl[u3 * kk + v3] += sa[u3] * sb[v3]
                    v3 += 1usize
                }
                u3 += 1usize
            }
        } else {
            // matched pairs: the same label (the other index) in both clusters
            var msum = 0.0f64
            var mcnt = 0.0f64
            if inner == 2usize {
                var ra2 = start[ci2]
                while ra2 < start[ci2 + 1usize] {
                    let ro = rows[ra2]
                    var rb2 = start[cj]
                    while rb2 < start[cj + 1usize] {
                        let rp = rows[rb2]
                        var la = f.tid[ro]
                        var lb = f.tid[rp]
                        if clus == 1usize {
                            la = f.gid[ro]
                            lb = f.gid[rp]
                        }
                        if la == lb {
                            msum += uh[ro] * uh[rp]
                            mcnt += 1.0f64
                        }
                        rb2 += 1usize
                    }
                    ra2 += 1usize
                }
            }
            var ra3 = start[ci2]
            while ra3 < start[ci2 + 1usize] {
                let ro = rows[ra3]
                var rb3 = start[cj]
                while rb3 < start[cj + 1usize] {
                    let rp = rows[rb3]
                    var la = f.tid[ro]
                    var lb = f.tid[rp]
                    if clus == 1usize {
                        la = f.gid[ro]
                        lb = f.gid[rp]
                    }
                    if la == lb {
                        var e = uh[ro] * uh[rp]
                        if inner == 2usize { e = msum / mcnt }
                        var u4 = 0usize
                        while u4 < kk {
                            var v4 = 0usize
                            while v4 < kk {
                                sl[u4 * kk + v4] += f.xt[ro * kk + u4] * e * f.xt[rp * kk + v4]
                                v4 += 1usize
                            }
                            u4 += 1usize
                        }
                    }
                    rb3 += 1usize
                }
                ra3 += 1usize
            }
        }
        ci2 += 1usize
    }
    let (xx2, e13) = zeros(a, kk * kk)
    if e13 != ok { ret e13 }
    r = 0usize
    while r < nr {
        var u5 = 0usize
        while u5 < kk {
            var v5 = 0usize
            while v5 < kk {
                xx2[u5 * kk + v5] += f.xt[r * kk + u5] * f.xt[r * kk + v5]
                v5 += 1usize
            }
            u5 += 1usize
        }
        r += 1usize
    }
    let (pane, e14) = gp.invert(a, xx2, kk)
    if e14 != ok { ret e14 }
    let (m1, e15) = gp.matmul(a, pane, sl, kk, kk, kk)
    if e15 != ok { ret e15 }
    let (m2, e16) = gp.matmul(a, m1, pane, kk, kk, kk)
    if e16 != ok { ret e16 }
    var z = 0usize
    while z < kk * kk {
        out[z] = m2[z]
        z += 1usize
    }
    ret ok
}

// vcovSCC: the Newey-West weighted sum of the time-clustered lagged covariances; maxlag is the caller's choice (plm: floor(max Ti ^ 1/4))
fn vcov_scc(a: *mem.Arena, f: *const Fit, typ: usize, inner: usize, maxlag: usize, out: []f64) -> err {
    let kk = f.kk
    let e0 = vcov_g(a, f, typ, 1usize, 0usize, inner, out)
    if e0 != ok { ret e0 }
    let (vl, e1) = zeros(a, kk * kk)
    if e1 != ok { ret e1 }
    var j = 1usize
    while j <= maxlag {
        let e2 = vcov_g(a, f, typ, 1usize, j, inner, vl)
        if e2 != ok { ret e2 }
        let w = 1.0f64 - f64(j) / f64(maxlag + 1usize)
        var u = 0usize
        while u < kk {
            var v = 0usize
            while v < kk {
                out[u * kk + v] += w * (vl[u * kk + v] + vl[v * kk + u])
                v += 1usize
            }
            u += 1usize
        }
        j += 1usize
    }
    ret ok
}

// plmtest on the pooled model: effect 0 individual, 1 time, 2 twoways; type 0 honda, 1 bp, 2 kw, 3 ghm (twoways only). out = (statistic, p value)
fn plmtest(a: *mem.Arena, p: *const Panel, effect: usize, ty: usize, out: []f64) -> err {
    let (lm, e0) = zeros(a, 4usize)
    if e0 != ok { ret e0 }
    let e1 = plm_lm(a, p, lm)
    if e1 != ok { ret e1 }
    let of = f64(p.n)
    let l1 = lm[0usize]
    let l2 = lm[1usize]
    var stat = 0.0f64
    var pv = 0.0f64
    if effect != 2usize {
        var l = l1
        if effect == 1usize { l = l2 }
        stat = l
        if ty == 1usize {
            stat = l * l
            pv = nm.pchisq(stat, 1.0f64, false, false)
        } else {
            pv = dist.pnorm(stat, 0.0f64, 1.0f64, false, false)
        }
    } else {
        if ty == 0usize {
            stat = (l1 + l2) / math.sqrt[f64](2.0f64)
            pv = dist.pnorm(stat, 0.0f64, 1.0f64, false, false)
        }
        if ty == 1usize {
            stat = l1 * l1 + l2 * l2
            pv = nm.pchisq(stat, 2.0f64, false, false)
        }
        if ty == 2usize {
            let den = math.sqrt[f64](lm[2usize] + lm[3usize] - 2.0f64 * of)
            stat = math.sqrt[f64](lm[2usize] - of) / den * l1 + math.sqrt[f64](lm[3usize] - of) / den * l2
            pv = dist.pnorm(stat, 0.0f64, 1.0f64, false, false)
        }
        if ty == 3usize {
            var m1 = l1
            var m2 = l2
            if m1 < 0.0f64 { m1 = 0.0f64 }
            if m2 < 0.0f64 { m2 = 0.0f64 }
            stat = m1 * m1 + m2 * m2
            pv = 0.5f64 * nm.pchisq(stat, 1.0f64, false, false) + 0.25f64 * nm.pchisq(stat, 2.0f64, false, false)
        }
    }
    out[0usize] = stat
    out[1usize] = pv
    ret ok
}

// plm's default vcovSCC lag: floor(max Ti ^ 1/4)
fn default_maxlag(p: *const Panel) -> usize {
    var best = 0usize
    var i = 0usize
    while i < p.nid {
        var cnt = 0usize
        var r = 0usize
        while r < p.n {
            if p.gid[r] == i { cnt += 1usize }
            r += 1usize
        }
        if cnt > best { best = cnt }
        i += 1usize
    }
    ret usize(math.floor[f64](math.pow[f64](f64(best), 0.25f64)))
}
