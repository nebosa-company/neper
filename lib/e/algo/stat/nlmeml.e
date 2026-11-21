// R nlme::nlme with a user-written model function or a self-start model of e.algo.stat.nlmelist, one or two NESTED grouping levels
// (random = list(Plot = ..., Subject = ...)) and a pdMat class per level (0 pdSymm / pdLogChol, 1 pdDiag, 2 pdIdent); fixed = p ~ 1 for every parameter, ML or REML.
// Same algorithm as e.algo.stat.nlmenl (Lindstrom and Bates iterated to its fixed point: a penalized non-linear least-squares fit of the fixed effects and all random
// effects at the current relative covariances, then an ML fit of the covariances on the linearisation), with the random-effects design kept dense: the linearised
// marginal covariance is V = I + sum over groups of Z_g D_g Z_g', profiled over the residual variance and minimised by nlminb, then polished by Newton steps on
// five-point differences. A user model is a function (x, parameters, gradient out) -> value that fills the analytic gradient; its starting values are the caller's,
// a self-start model starts from the pooled nls fit. At most four model parameters and four random effects per level.
// Not here: covariates on parameters (e.algo.stat.nlmenl), crossed effects, three levels, correlation and variance structures, pdCompSymm (nlme has none either).

use e.algo.stat.gls as g
use e.algo.stat.nlmelist as nl
use e.algo.stat.nlminb as nlb
use e.algo.stat.psych as ps
use e.math
use e.mem

type M = struct { kind: i64, um: fn(f64, []const f64, []f64) -> f64, np: usize, n: usize, ng1: usize, ng2: usize, nr1: usize, nr2: usize, nb: usize, gs1: []const f64, gs2: []const f64, x: []const f64, y: []const f64, rs1: []usize, rs2: []usize, og: []usize, ig: []usize }

type Ctx = struct { a: *mem.Arena, m: M, pd1: i64, pd2: i64, t1: usize, am: []const f64, zm: []const f64, w: []const f64, cst: f64 }

fn model(c: *const M, x: f64, phi: []const f64, gr: []f64) -> f64 {
    if c.kind == 0i64 { ret c.um(x, phi, gr) }
    ret nl.ss_eval(c.kind, x, phi, gr)
}

// number of free covariance parameters of a pdMat class over q random effects
fn npd(q: usize, pd: i64) -> usize {
    if q == 0usize { ret 0usize }
    if pd == 1i64 { ret q }
    if pd == 2i64 { ret 1usize }
    ret q * (q + 1usize) / 2usize
}

fn obs_phi(c: *const M, beta: []const f64, bb: []const f64, t: usize, phi: []f64) {
    var j = 0usize
    while j < c.np {
        phi[j] = beta[j]
        j += 1usize
    }
    var r = 0usize
    while r < c.nr1 {
        phi[c.rs1[r]] += bb[c.og[t] * c.nr1 + r]
        r += 1usize
    }
    r = 0usize
    while r < c.nr2 {
        phi[c.rs2[r]] += bb[c.ng1 * c.nr1 + c.ig[t] * c.nr2 + r]
        r += 1usize
    }
}

// derivatives by the fixed effects (am, n by np) and by every random effect (zm, n by nb), both column-major, and the pseudo-response w
fn linearize(c: *const M, beta: []const f64, bb: []const f64, am: []f64, zm: []f64, w: []f64) {
    var gr: [8]f64 = zero
    var phi: [8]f64 = zero
    var i = 0usize
    while i < c.n * c.nb {
        zm[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < c.n {
        obs_phi(c, beta, bb, t, phi[0usize..8usize])
        let f = model(c, c.x[t], phi[0usize..8usize], gr[0usize..8usize])
        var wv = c.y[t] - f
        var j = 0usize
        while j < c.np {
            am[j * c.n + t] = gr[j]
            wv += gr[j] * beta[j]
            j += 1usize
        }
        var r = 0usize
        while r < c.nr1 {
            let col = c.og[t] * c.nr1 + r
            zm[col * c.n + t] = gr[c.rs1[r]]
            wv += gr[c.rs1[r]] * bb[col]
            r += 1usize
        }
        r = 0usize
        while r < c.nr2 {
            let col = c.ng1 * c.nr1 + c.ig[t] * c.nr2 + r
            zm[col * c.n + t] = gr[c.rs2[r]]
            wv += gr[c.rs2[r]] * bb[col]
            r += 1usize
        }
        w[t] = wv
        t += 1usize
    }
}

fn pobj(c: *const M, p1: []const f64, p2: []const f64, beta: []const f64, bb: []const f64) -> f64 {
    var gr: [8]f64 = zero
    var phi: [8]f64 = zero
    var s = 0.0f64
    var t = 0usize
    while t < c.n {
        obs_phi(c, beta, bb, t, phi[0usize..8usize])
        let e = c.y[t] - model(c, c.x[t], phi[0usize..8usize], gr[0usize..8usize])
        s += e * e
        t += 1usize
    }
    var k = 0usize
    while k < c.ng1 {
        var r = 0usize
        while r < c.nr1 {
            var r2 = 0usize
            while r2 < c.nr1 {
                s += bb[k * c.nr1 + r] * p1[r * c.nr1 + r2] * bb[k * c.nr1 + r2]
                r2 += 1usize
            }
            r += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < c.ng2 {
        let o = c.ng1 * c.nr1 + k * c.nr2
        var r = 0usize
        while r < c.nr2 {
            var r2 = 0usize
            while r2 < c.nr2 {
                s += bb[o + r] * p2[r * c.nr2 + r2] * bb[o + r2]
                r2 += 1usize
            }
            r += 1usize
        }
        k += 1usize
    }
    ret s
}

// Gauss-Newton with step halving on (beta, b) for the penalized problem at the relative precisions p1, p2 (inverse covariances of the two levels)
fn pnls(a: *mem.Arena, c: *const M, p1: []const f64, p2: []const f64, beta: []f64, bb: []f64) -> err {
    let np = c.np
    let nb = c.nb
    let m = np + nb
    let st = mem.mark(a)
    let (hm, e1) = mem.alloc[f64](a, m * m)
    let (hi, e2) = mem.alloc[f64](a, m * m)
    let (rhs, e3) = mem.alloc[f64](a, m)
    let (dl, e4) = mem.alloc[f64](a, m)
    let (bt, e5) = mem.alloc[f64](a, np)
    let (bbt, e6) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var gr: [8]f64 = zero
    var phi: [8]f64 = zero
    var jv: [16]f64 = zero
    var jc: [16]usize = zero
    var s0 = pobj(c, p1, p2, beta, bb)
    var it = 0usize
    while it < 200usize {
        var i = 0usize
        while i < m * m {
            hm[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < m {
            rhs[i] = 0.0f64
            i += 1usize
        }
        var t = 0usize
        while t < c.n {
            obs_phi(c, beta, bb, t, phi[0usize..8usize])
            let res = c.y[t] - model(c, c.x[t], phi[0usize..8usize], gr[0usize..8usize])
            var cnt = 0usize
            var j = 0usize
            while j < np {
                jv[cnt] = gr[j]
                jc[cnt] = j
                cnt += 1usize
                j += 1usize
            }
            var r = 0usize
            while r < c.nr1 {
                jv[cnt] = gr[c.rs1[r]]
                jc[cnt] = np + c.og[t] * c.nr1 + r
                cnt += 1usize
                r += 1usize
            }
            r = 0usize
            while r < c.nr2 {
                jv[cnt] = gr[c.rs2[r]]
                jc[cnt] = np + c.ng1 * c.nr1 + c.ig[t] * c.nr2 + r
                cnt += 1usize
                r += 1usize
            }
            var a1 = 0usize
            while a1 < cnt {
                rhs[jc[a1]] += jv[a1] * res
                var b1 = 0usize
                while b1 < cnt {
                    hm[jc[a1] * m + jc[b1]] += jv[a1] * jv[b1]
                    b1 += 1usize
                }
                a1 += 1usize
            }
            t += 1usize
        }
        var k = 0usize
        while k < c.ng1 {
            var r1 = 0usize
            while r1 < c.nr1 {
                var r2 = 0usize
                while r2 < c.nr1 {
                    let o = np + k * c.nr1
                    hm[(o + r1) * m + o + r2] += p1[r1 * c.nr1 + r2]
                    rhs[o + r1] -= p1[r1 * c.nr1 + r2] * bb[k * c.nr1 + r2]
                    r2 += 1usize
                }
                r1 += 1usize
            }
            k += 1usize
        }
        k = 0usize
        while k < c.ng2 {
            var r1 = 0usize
            while r1 < c.nr2 {
                var r2 = 0usize
                while r2 < c.nr2 {
                    let o = np + c.ng1 * c.nr1 + k * c.nr2
                    hm[(o + r1) * m + o + r2] += p2[r1 * c.nr2 + r2]
                    rhs[o + r1] -= p2[r1 * c.nr2 + r2] * bb[c.ng1 * c.nr1 + k * c.nr2 + r2]
                    r2 += 1usize
                }
                r1 += 1usize
            }
            k += 1usize
        }
        if !ps.invert(a, hm, m, hi) {
            mem.reset(a, st)
            ret g.Singular
        }
        i = 0usize
        while i < m {
            var v = 0.0f64
            var j = 0usize
            while j < m {
                v += hi[i * m + j] * rhs[j]
                j += 1usize
            }
            dl[i] = v
            i += 1usize
        }
        var hs = 1.0f64
        var s1 = s0
        var ok1 = false
        while hs >= 1.0e-12f64 {
            i = 0usize
            while i < np {
                bt[i] = beta[i] + hs * dl[i]
                i += 1usize
            }
            i = 0usize
            while i < nb {
                bbt[i] = bb[i] + hs * dl[np + i]
                i += 1usize
            }
            s1 = pobj(c, p1, p2, bt, bbt)
            if s1 == s1 && s1 <= s0 + 1.0e-15f64 * s0 {
                ok1 = true
                break
            }
            hs = hs / 2.0f64
        }
        if !ok1 { break }
        var big = 0.0f64
        var um = 0.0f64
        i = 0usize
        while i < m {
            var u = 0.0f64
            if i < np { u = bt[i] } else { u = bbt[i - np] }
            var du = hs * dl[i]
            if du < 0.0f64 { du = 0.0f64 - du }
            if du > big { big = du }
            if u < 0.0f64 { u = 0.0f64 - u }
            if u > um { um = u }
            i += 1usize
        }
        i = 0usize
        while i < np {
            beta[i] = bt[i]
            i += 1usize
        }
        i = 0usize
        while i < nb {
            bb[i] = bbt[i]
            i += 1usize
        }
        s0 = s1
        if big < 1.0e-13f64 * (1.0f64 + um) { break }
        it += 1usize
    }
    mem.reset(a, st)
    ret ok
}

// V_k = I + sum of Z D Z' over the random effects of outer group k (m by m row-major, observations t0 .. t0 + m); levels nest, so V is block diagonal over the outer groups
fn fill_vk(c: *const M, zm: []const f64, d1: []const f64, d2: []const f64, k: usize, t0: usize, m: usize, v: []f64) {
    let n = c.n
    var i = 0usize
    while i < m * m {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        v[i * m + i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var r = 0usize
            while r < c.nr1 {
                var s = 0usize
                while s < c.nr1 {
                    v[i * m + j] += zm[(k * c.nr1 + r) * n + t0 + i] * d1[r * c.nr1 + s] * zm[(k * c.nr1 + s) * n + t0 + j]
                    s += 1usize
                }
                r += 1usize
            }
            if c.ng2 > 0usize && c.ig[t0 + i] == c.ig[t0 + j] {
                let o = c.ng1 * c.nr1 + c.ig[t0 + i] * c.nr2
                r = 0usize
                while r < c.nr2 {
                    var s = 0usize
                    while s < c.nr2 {
                        v[i * m + j] += zm[(o + r) * n + t0 + i] * d2[r * c.nr2 + s] * zm[(o + s) * n + t0 + j]
                        s += 1usize
                    }
                    r += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
}

// the profile of the linearised model at covariance parameters th: rss, log det V, log det X'V^-1X, coefficients (bg) and (X'V^-1X)^-1 (xi); good is false when singular
type Prof = struct { rss: f64, ldv: f64, ldx: f64, good: bool }

fn profile(a: *mem.Arena, c: *const M, pd1: i64, pd2: i64, t1: usize, th: []const f64, am: []const f64, zm: []const f64, w: []const f64, bg: []f64, xi: []f64) -> Prof {
    let n = c.n
    let np = c.np
    let bad = Prof { rss: 0.0f64, ldv: 0.0f64, ldx: 0.0f64, good: false }
    var maxm = 0usize
    var sum2 = 0usize
    var k = 0usize
    while k < c.ng1 {
        let m = usize(c.gs1[k])
        if m > maxm { maxm = m }
        sum2 += m * m
        k += 1usize
    }
    let st = mem.mark(a)
    let (v, e1) = mem.alloc[f64](a, maxm * maxm)
    let (vib, e2) = mem.alloc[f64](a, sum2)
    let (sx, e3) = mem.alloc[f64](a, maxm * np)
    let (xtx, e4) = mem.alloc[f64](a, np * np)
    let (xty, e5) = mem.alloc[f64](a, np)
    let (d1, e6) = mem.alloc[f64](a, 64usize)
    let (d2, e7) = mem.alloc[f64](a, 64usize)
    let (vik, e8) = mem.alloc[f64](a, maxm * maxm)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret bad }
    if c.nr1 > 0usize { g.re_cov(c.nr1, th[0usize..t1], d1, pd1) }
    if c.nr2 > 0usize { g.re_cov(c.nr2, th[t1..th.len], d2, pd2) }
    var j = 0usize
    while j < np * np {
        xtx[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < np {
        xty[j] = 0.0f64
        j += 1usize
    }
    var ldv = 0.0f64
    var t0 = 0usize
    var off = 0usize
    k = 0usize
    while k < c.ng1 {
        let m = usize(c.gs1[k])
        fill_vk(c, zm, d1, d2, k, t0, m, v)
        if !ps.invert(a, v, m, vik) {
            mem.reset(a, st)
            ret bad
        }
        ldv += ps.logdet(a, v, m)
        var i = 0usize
        while i < m * m {
            vib[off + i] = vik[i]
            i += 1usize
        }
        j = 0usize
        while j < np {
            i = 0usize
            while i < m {
                var s = 0.0f64
                var l = 0usize
                while l < m {
                    s += vik[i * m + l] * am[j * n + t0 + l]
                    l += 1usize
                }
                sx[j * m + i] = s
                i += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < np {
            var l = 0usize
            while l < np {
                var s = 0.0f64
                i = 0usize
                while i < m {
                    s += am[j * n + t0 + i] * sx[l * m + i]
                    i += 1usize
                }
                xtx[j * np + l] += s
                l += 1usize
            }
            var s = 0.0f64
            i = 0usize
            while i < m {
                s += sx[j * m + i] * w[t0 + i]
                i += 1usize
            }
            xty[j] += s
            j += 1usize
        }
        off += m * m
        t0 += m
        k += 1usize
    }
    if !ps.invert(a, xtx, np, xi) {
        mem.reset(a, st)
        ret bad
    }
    j = 0usize
    while j < np {
        var s = 0.0f64
        var l = 0usize
        while l < np {
            s += xi[j * np + l] * xty[l]
            l += 1usize
        }
        bg[j] = s
        j += 1usize
    }
    var rss = 0.0f64
    t0 = 0usize
    off = 0usize
    k = 0usize
    while k < c.ng1 {
        let m = usize(c.gs1[k])
        var i = 0usize
        while i < m {
            var ri = w[t0 + i]
            j = 0usize
            while j < np {
                ri -= am[j * n + t0 + i] * bg[j]
                j += 1usize
            }
            var l = 0usize
            while l < m {
                var rl = w[t0 + l]
                j = 0usize
                while j < np {
                    rl -= am[j * n + t0 + l] * bg[j]
                    j += 1usize
                }
                rss += ri * vib[off + i * m + l] * rl
                l += 1usize
            }
            i += 1usize
        }
        off += m * m
        t0 += m
        k += 1usize
    }
    let ldx = ps.logdet(a, xtx, np)
    mem.reset(a, st)
    ret Prof { rss: rss, ldv: ldv, ldx: ldx, good: true }
}

fn obj(cx: *Ctx, par: []const f64) -> f64 {
    let st = mem.mark(cx.a)
    let (bg, e1) = mem.alloc[f64](cx.a, cx.m.np)
    let (xi, e2) = mem.alloc[f64](cx.a, cx.m.np * cx.m.np)
    var v = 1.0e300f64
    if e1 == ok && e2 == ok {
        let f = profile(cx.a, &cx.m, cx.pd1, cx.pd2, cx.t1, par, cx.am, cx.zm, cx.w, bg, xi)
        if f.good && f.rss > 0.0f64 { v = 0.0f64 - (cx.cst - f64(cx.m.n) / 2.0f64 * math.log[f64](f.rss) - f.ldv / 2.0f64) }
    }
    mem.reset(cx.a, st)
    ret v
}

// five-point central-difference gradient
fn grad(cx: *Ctx, par: []const f64, gr: []f64) {
    let st = mem.mark(cx.a)
    let (w, e) = mem.alloc[f64](cx.a, par.len)
    if e == ok {
        var i = 0usize
        while i < par.len {
            w[i] = par[i]
            i += 1usize
        }
        i = 0usize
        while i < par.len {
            var ab = par[i]
            if ab < 0.0f64 { ab = 0.0f64 - ab }
            // five-point differences at h and h / 2, Richardson-extrapolated to remove the h^4 term
            let h = 6.0e-3f64 * (1.0f64 + ab)
            var gs: [2]f64 = zero
            var s = 0usize
            while s < 2usize {
                var hh = h
                if s == 1usize { hh = h / 2.0f64 }
                w[i] = par[i] + hh
                let f1 = obj(cx, w)
                w[i] = par[i] - hh
                let m1 = obj(cx, w)
                w[i] = par[i] + 2.0f64 * hh
                let f2 = obj(cx, w)
                w[i] = par[i] - 2.0f64 * hh
                let m2 = obj(cx, w)
                w[i] = par[i]
                gs[s] = (8.0f64 * (f1 - m1) - (f2 - m2)) / (12.0f64 * hh)
                s += 1usize
            }
            gr[i] = (64.0f64 * gs[1usize] - gs[0usize]) / 63.0f64
            i += 1usize
        }
    }
    mem.reset(cx.a, st)
}

// Newton steps with the Hessian from central differences of grad; a step that does not lower the objective ends the polish
fn polish(a: *mem.Arena, cx: *Ctx, pv: []f64) {
    let np = pv.len
    let st = mem.mark(a)
    let (gr, e1) = mem.alloc[f64](a, np)
    let (gp, e2) = mem.alloc[f64](a, np)
    let (gm, e3) = mem.alloc[f64](a, np)
    let (hs, e4) = mem.alloc[f64](a, np * np)
    let (hi, e5) = mem.alloc[f64](a, np * np)
    let (pn, e6) = mem.alloc[f64](a, np)
    if e1 == ok && e2 == ok && e3 == ok && e4 == ok && e5 == ok && e6 == ok {
        var it = 0usize
        while it < 25usize {
            grad(cx, pv, gr)
            var j = 0usize
            while j < np {
                var ab = pv[j]
                if ab < 0.0f64 { ab = 0.0f64 - ab }
                let h = 1.0e-4f64 * (1.0f64 + ab)
                let pj = pv[j]
                pv[j] = pj + h
                grad(cx, pv, gp)
                pv[j] = pj - h
                grad(cx, pv, gm)
                pv[j] = pj
                var i = 0usize
                while i < np {
                    hs[i * np + j] = (gp[i] - gm[i]) / (2.0f64 * h)
                    i += 1usize
                }
                j += 1usize
            }
            var i = 0usize
            while i < np {
                j = 0usize
                while j < i {
                    let mv = (hs[i * np + j] + hs[j * np + i]) / 2.0f64
                    hs[i * np + j] = mv
                    hs[j * np + i] = mv
                    j += 1usize
                }
                i += 1usize
            }
            if !ps.invert(a, hs, np, hi) { break }
            var big = 0.0f64
            i = 0usize
            while i < np {
                var sv = 0.0f64
                j = 0usize
                while j < np {
                    sv += hi[i * np + j] * gr[j]
                    j += 1usize
                }
                pn[i] = pv[i] - sv
                if sv < 0.0f64 { sv = 0.0f64 - sv }
                if sv > big { big = sv }
                i += 1usize
            }
            if obj(cx, pn) > obj(cx, pv) + 1.0e-13f64 { break }
            i = 0usize
            while i < np {
                pv[i] = pn[i]
                i += 1usize
            }
            if big < 1.0e-10f64 { break }
            it += 1usize
        }
    }
    mem.reset(a, st)
}

fn nlme_multi_len(np: usize, nr1: usize, nr2: usize) -> usize {
    ret np + 4usize + nr1 + nr2 + pairs(nr1) + pairs(nr2) + np
}

fn pairs(q: usize) -> usize {
    if q < 2usize { ret 0usize }
    ret q * (q - 1usize) / 2usize
}

fn inv_cov(a: *mem.Arena, q: usize, th: []const f64, pd: i64, d: []f64, pm: []f64) -> bool {
    if q == 0usize { ret true }
    g.re_cov(q, th, d, pd)
    var tmp: [16]f64 = zero
    var i = 0usize
    while i < q * q {
        tmp[i] = d[i]
        i += 1usize
    }
    ret ps.invert(a, tmp[0usize..16usize], q, pm)
}

// kind 0: user model um with np parameters and starting values start; kind > 0: self-start model (np = its parameter count), pooled nls start.
// gs1 / gs2: sizes of the contiguous outer / inner groups (inner groups nest in the outer ones; gs2 empty for one level); rset1 / rset2: 1-based parameter
// indices carrying random effects at each level (rset2 empty for one level); pd1 / pd2: pdMat classes.
// out (nlme_multi_len): fixed effects (np), sigma, logLik, AIC, BIC, random-effect sds of level 1 then level 2, correlations of level 1 then level 2 (lower triangle by
// columns), standard errors of the fixed effects (np)
fn nlme_multi(a: *mem.Arena, kind: i64, um: fn(f64, []const f64, []f64) -> f64, np: usize, n: usize, gs1: []const f64, gs2: []const f64, x: []const f64, y: []const f64, rset1: []const f64, pd1: i64, rset2: []const f64, pd2: i64, reml: bool, start: []const f64, out: []f64) -> err {
    let ng1 = gs1.len
    let ng2 = gs2.len
    let nr1 = rset1.len
    let nr2 = rset2.len
    let nb = ng1 * nr1 + ng2 * nr2
    let t1 = npd(nr1, pd1)
    let t2 = npd(nr2, pd2)
    let (rs1, e0) = mem.alloc[usize](a, nr1 + 1usize)
    let (rs2, e1) = mem.alloc[usize](a, nr2 + 1usize)
    let (og, e2) = mem.alloc[usize](a, n)
    let (ig, e3) = mem.alloc[usize](a, n)
    let (beta, e4) = mem.alloc[f64](a, np)
    let (bb, e5) = mem.alloc[f64](a, nb)
    let (am, e6) = mem.alloc[f64](a, n * np)
    let (zm, e7) = mem.alloc[f64](a, n * nb)
    let (w, e8) = mem.alloc[f64](a, n)
    let (pv, e9) = mem.alloc[f64](a, t1 + t2 + 1usize)
    let (pold, e10) = mem.alloc[f64](a, t1 + t2 + 1usize)
    let (bold, e11) = mem.alloc[f64](a, np + nb)
    let (bg, e12) = mem.alloc[f64](a, np)
    let (xi, e13) = mem.alloc[f64](a, np * np)
    let (d1, e14) = mem.alloc[f64](a, 64usize)
    let (d2, e15) = mem.alloc[f64](a, 64usize)
    let (p1, e16) = mem.alloc[f64](a, 64usize)
    let (p2, e17) = mem.alloc[f64](a, 64usize)
    let (nfit, e18) = mem.alloc[f64](a, 2usize * np + 5usize + 16usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e0 }
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret e9 }
    var i = 0usize
    while i < nr1 {
        rs1[i] = usize(rset1[i]) - 1usize
        i += 1usize
    }
    i = 0usize
    while i < nr2 {
        rs2[i] = usize(rset2[i]) - 1usize
        i += 1usize
    }
    var t = 0usize
    i = 0usize
    while i < ng1 {
        let m = usize(gs1[i])
        var k = 0usize
        while k < m {
            og[t + k] = i
            k += 1usize
        }
        t += m
        i += 1usize
    }
    t = 0usize
    i = 0usize
    while i < ng2 {
        let m = usize(gs2[i])
        var k = 0usize
        while k < m {
            ig[t + k] = i
            k += 1usize
        }
        t += m
        i += 1usize
    }
    i = 0usize
    while i < nb {
        bb[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < t1 + t2 + 1usize {
        pv[i] = 0.0f64
        i += 1usize
    }
    if kind == 0i64 {
        i = 0usize
        while i < np {
            beta[i] = start[i]
            i += 1usize
        }
    } else {
        let ne = nl.nls_fit(a, kind, n, x, y, nfit)
        if ne != ok { ret ne }
        i = 0usize
        while i < np {
            if !(nfit[i] - nfit[i] == 0.0f64) { ret g.Singular }
            beta[i] = nfit[i]
            i += 1usize
        }
    }
    var cm = M { kind: kind, um: um, np: np, n: n, ng1: ng1, ng2: ng2, nr1: nr1, nr2: nr2, nb: nb, gs1: gs1, gs2: gs2, x: x, y: y, rs1: rs1, rs2: rs2, og: og, ig: ig }
    let nobs0 = f64(n)
    let cst = nobs0 * (math.log[f64](nobs0) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    var ctl: [6]f64 = zero
    ctl[0usize] = 400.0f64
    ctl[1usize] = 150.0f64
    ctl[2usize] = 0.0f64
    ctl[3usize] = 1.0e-12f64
    ctl[4usize] = 1.0e-9f64
    ctl[5usize] = 1.0e-12f64
    var conv = false
    var lastch = 1.0f64
    var it = 0usize
    while it < 600usize && !conv {
        let st = mem.mark(a)
        linearize(&cm, beta, bb, am, zm, w)
        var cx = Ctx { a: a, m: cm, pd1: pd1, pd2: pd2, t1: t1, am: am, zm: zm, w: w, cst: cst }
        i = 0usize
        while i < t1 + t2 {
            pold[i] = pv[i]
            i += 1usize
        }
        let r = nlb.nlminb[Ctx](a, &cx, obj, grad, true, pv[0usize..t1 + t2], ctl[0usize..6usize])
        if r.iterations == 0usize && r.fevals == 0usize {
            mem.reset(a, st)
            ret g.Singular
        }
        if lastch < 1.0e-3f64 { polish(a, &cx, pv[0usize..t1 + t2]) }
        if !inv_cov(a, nr1, pv[0usize..t1], pd1, d1, p1) || !inv_cov(a, nr2, pv[t1..t1 + t2], pd2, d2, p2) {
            mem.reset(a, st)
            ret g.Singular
        }
        i = 0usize
        while i < np {
            bold[i] = beta[i]
            i += 1usize
        }
        i = 0usize
        while i < nb {
            bold[np + i] = bb[i]
            i += 1usize
        }
        let pe = pnls(a, &cm, p1, p2, beta, bb)
        if pe != ok {
            mem.reset(a, st)
            ret pe
        }
        var ch = 0.0f64
        i = 0usize
        while i < np + nb + t1 + t2 {
            var nv = 0.0f64
            var ov = 0.0f64
            if i < np + nb {
                if i < np { nv = beta[i] } else { nv = bb[i - np] }
                ov = bold[i]
            } else {
                nv = pv[i - np - nb]
                ov = pold[i - np - nb]
            }
            var dv = nv - ov
            if dv < 0.0f64 { dv = 0.0f64 - dv }
            var sc = nv
            if sc < 0.0f64 { sc = 0.0f64 - sc }
            if sc < 1.0f64 { sc = 1.0f64 }
            if dv / sc > ch { ch = dv / sc }
            i += 1usize
        }
        lastch = ch
        if ch < 2.0e-11f64 { conv = true }
        mem.reset(a, st)
        it += 1usize
    }
    if !conv { ret g.Singular }
    linearize(&cm, beta, bb, am, zm, w)
    let f = profile(a, &cm, pd1, pd2, t1, pv[0usize..t1 + t2], am, zm, w, bg, xi)
    if !f.good { ret g.Singular }
    if !inv_cov(a, nr1, pv[0usize..t1], pd1, d1, p1) || !inv_cov(a, nr2, pv[t1..t1 + t2], pd2, d2, p2) { ret g.Singular }
    var nobs = nobs0
    var val = 0.0f64 - nobs0 / 2.0f64 * math.log[f64](f.rss) - f.ldv / 2.0f64
    if reml {
        val = val + f64(np) / 2.0f64 * math.log[f64](f.rss) - 0.5f64 * f.ldx
        nobs = nobs0 - f64(np)
    }
    let sigma = math.sqrt[f64](f.rss / nobs)
    let ll = val + nobs * (math.log[f64](nobs) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    let npar = f64(np + t1 + t2 + 1usize)
    i = 0usize
    while i < np {
        out[i] = beta[i]
        i += 1usize
    }
    out[np] = sigma
    out[np + 1usize] = ll
    out[np + 2usize] = 0.0f64 - 2.0f64 * ll + 2.0f64 * npar
    out[np + 3usize] = 0.0f64 - 2.0f64 * ll + npar * math.log[f64](nobs)
    var o = np + 4usize
    i = 0usize
    while i < nr1 {
        out[o + i] = sigma * math.sqrt[f64](d1[i * nr1 + i])
        i += 1usize
    }
    o += nr1
    i = 0usize
    while i < nr2 {
        out[o + i] = sigma * math.sqrt[f64](d2[i * nr2 + i])
        i += 1usize
    }
    o += nr2
    var l = 0usize
    while l < nr1 {
        var k = l + 1usize
        while k < nr1 {
            out[o] = d1[k * nr1 + l] / math.sqrt[f64](d1[k * nr1 + k] * d1[l * nr1 + l])
            o += 1usize
            k += 1usize
        }
        l += 1usize
    }
    l = 0usize
    while l < nr2 {
        var k = l + 1usize
        while k < nr2 {
            out[o] = d2[k * nr2 + l] / math.sqrt[f64](d2[k * nr2 + k] * d2[l * nr2 + l])
            o += 1usize
            k += 1usize
        }
        l += 1usize
    }
    i = 0usize
    while i < np {
        out[o + i] = sigma * math.sqrt[f64](xi[i * np + i])
        i += 1usize
    }
    ret ok
}
