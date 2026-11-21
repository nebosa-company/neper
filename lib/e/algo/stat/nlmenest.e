// R nlme::lme with nested random intercepts, random = ~ 1 | g1 / g2: two levels of intercepts (outer groups contiguous, each holding whole inner groups),
// REML or ML. V = I + s1 J(g1) + s2 J(g2) relative to sigma^2 with log-sd parameters, the profile likelihood of e.algo.stat.gls on that dense matrix, minimised
// by nlminb and polished by Newton steps on five-point differences (nlme's own optimum is only located to ~1e-6).
// Not here: random slopes at either level, more than two levels, crossed effects, correlation and variance structures, var-cov intervals.

use e.algo.stat.gls as g
use e.algo.stat.nlminb as nlb
use e.algo.stat.psych as ps
use e.math
use e.mem

type NSpec = struct { n: usize, p: usize, x: []const f64, y: []const f64, o1: []const usize, o2: []const usize, reml: bool }
type NCtx = struct { a: *mem.Arena, s: NSpec, cst: f64 }

// output of nest_fit: coef (p), sigma, logLik, AIC, BIC, sd of the level-1 intercept, sd of the level-2 intercept, se (p), level-1 BLUPs (n1), level-2 BLUPs (n2)
fn nest_len(p: usize, n1: usize, n2: usize) -> usize { ret p + 4usize + 2usize + p + n1 + n2 }

fn fill_v(s: *const NSpec, th: []const f64, v: []f64) {
    let n = s.n
    let e1 = math.exp[f64](2.0f64 * th[0usize])
    let e2 = math.exp[f64](2.0f64 * th[1usize])
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var t = 0.0f64
            if i == j { t = 1.0f64 }
            if s.o1[i] == s.o1[j] { t += e1 }
            if s.o2[i] == s.o2[j] { t += e2 }
            v[i * n + j] = t
            j += 1usize
        }
        i += 1usize
    }
}

fn ncore(a: *mem.Arena, s: *const NSpec, th: []const f64, coef: []f64, xtxi: []f64, vi: []f64) -> g.Fit {
    let n = s.n
    let p = s.p
    var bad: g.Fit = zero
    let (v, e1) = mem.alloc[f64](a, n * n)
    let (sx, e2) = mem.alloc[f64](a, n * p)
    let (xtx, e3) = mem.alloc[f64](a, p * p)
    let (xty, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret bad }
    fill_v(s, th, v)
    if !ps.invert(a, v, n, vi) { ret bad }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            var t = 0.0f64
            var k = 0usize
            while k < n {
                t += vi[i * n + k] * s.x[j * n + k]
                k += 1usize
            }
            sx[j * n + i] = t
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var t = 0.0f64
            var i = 0usize
            while i < n {
                t += s.x[j * n + i] * sx[k * n + i]
                i += 1usize
            }
            xtx[j * p + k] = t
            k += 1usize
        }
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += sx[j * n + i] * s.y[i]
            i += 1usize
        }
        xty[j] = t
        j += 1usize
    }
    if !ps.invert(a, xtx, p, xtxi) { ret bad }
    j = 0usize
    while j < p {
        var t = 0.0f64
        var k = 0usize
        while k < p {
            t += xtxi[j * p + k] * xty[k]
            k += 1usize
        }
        coef[j] = t
        j += 1usize
    }
    let (rs, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret bad }
    var i = 0usize
    while i < n {
        var t = s.y[i]
        j = 0usize
        while j < p {
            t -= s.x[j * n + i] * coef[j]
            j += 1usize
        }
        rs[i] = t
        i += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            rss += rs[i] * vi[i * n + k] * rs[k]
            k += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    let pf = f64(p)
    let ldet = ps.logdet(a, v, n)
    let two_pi = 2.0f64 * 3.141592653589793f64
    if s.reml {
        let s2 = rss / (nf - pf)
        let ll = 0.0f64 - (nf - pf) / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - 0.5f64 * ps.logdet(a, xtx, p) - (nf - pf) / 2.0f64
        ret g.Fit { sigma: math.sqrt[f64](s2), loglik: ll, good: true }
    }
    let s2 = rss / nf
    ret g.Fit { sigma: math.sqrt[f64](s2), loglik: 0.0f64 - nf / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - nf / 2.0f64, good: true }
}

fn nobj(c: *NCtx, par: []const f64) -> f64 {
    let st = mem.mark(c.a)
    let (coef, e1) = mem.alloc[f64](c.a, c.s.p)
    let (xi, e2) = mem.alloc[f64](c.a, c.s.p * c.s.p)
    let (vi, e3) = mem.alloc[f64](c.a, c.s.n * c.s.n)
    var v = 1.0e300f64
    if e1 == ok && e2 == ok && e3 == ok {
        let f = ncore(c.a, &c.s, par, coef, xi, vi)
        if f.good { v = c.cst - f.loglik }
    }
    mem.reset(c.a, st)
    ret v
}

// five-point central-difference gradient
fn ngrad(c: *NCtx, par: []const f64, gr: []f64) {
    let st = mem.mark(c.a)
    let (w, e) = mem.alloc[f64](c.a, par.len)
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
            let h = 1.0e-3f64 * (1.0f64 + ab)
            w[i] = par[i] + h
            let f1 = nobj(c, w)
            w[i] = par[i] - h
            let m1 = nobj(c, w)
            w[i] = par[i] + 2.0f64 * h
            let f2 = nobj(c, w)
            w[i] = par[i] - 2.0f64 * h
            let m2 = nobj(c, w)
            w[i] = par[i]
            gr[i] = (8.0f64 * (f1 - m1) - (f2 - m2)) / (12.0f64 * h)
            i += 1usize
        }
    }
    mem.reset(c.a, st)
}

// Newton steps with the Hessian from central differences of ngrad; a step that does not lower the objective ends the polish
fn npolish(a: *mem.Arena, c: *NCtx, pv: []f64) {
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
        while it < 12usize {
            ngrad(c, pv, gr)
            var j = 0usize
            while j < np {
                var ab = pv[j]
                if ab < 0.0f64 { ab = 0.0f64 - ab }
                let h = 1.0e-4f64 * (1.0f64 + ab)
                let pj = pv[j]
                pv[j] = pj + h
                ngrad(c, pv, gp)
                pv[j] = pj - h
                ngrad(c, pv, gm)
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
                    let m = (hs[i * np + j] + hs[j * np + i]) / 2.0f64
                    hs[i * np + j] = m
                    hs[j * np + i] = m
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
            if nobj(c, pn) > nobj(c, pv) + 1.0e-13f64 { break }
            i = 0usize
            while i < np {
                pv[i] = pn[i]
                i += 1usize
            }
            if big < 1.0e-7f64 { break }
            it += 1usize
        }
    }
    mem.reset(a, st)
}

// g1s: sizes (observations) of the outer groups, g2s: sizes of the inner groups in data order; x is n by p column-major
fn nest_fit(a: *mem.Arena, reml: bool, n: usize, p: usize, g1s: []const f64, g2s: []const f64, y: []const f64, x: []const f64, out: []f64) -> err {
    let n1 = g1s.len
    let n2 = g2s.len
    let (o1, e1) = mem.alloc[usize](a, n)
    let (o2, e2) = mem.alloc[usize](a, n)
    let (coef, e3) = mem.alloc[f64](a, p)
    let (xi, e4) = mem.alloc[f64](a, p * p)
    let (vi, e5) = mem.alloc[f64](a, n * n)
    let (th, e6) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var t = 0usize
    var i = 0usize
    while i < n1 {
        let m = usize(g1s[i])
        var k = 0usize
        while k < m {
            o1[t + k] = i
            k += 1usize
        }
        t += m
        i += 1usize
    }
    t = 0usize
    i = 0usize
    while i < n2 {
        let m = usize(g2s[i])
        var k = 0usize
        while k < m {
            o2[t + k] = i
            k += 1usize
        }
        t += m
        i += 1usize
    }
    th[0usize] = 0.0f64
    th[1usize] = 0.0f64
    let nobs = f64(n) - f64(p) * g.if_reml(reml)
    let cst = nobs * (math.log[f64](nobs) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    let sp = NSpec { n: n, p: p, x: x, y: y, o1: o1, o2: o2, reml: reml }
    var c = NCtx { a: a, s: sp, cst: cst }
    var ctl: [6]f64 = zero
    ctl[0usize] = 400.0f64
    ctl[1usize] = 150.0f64
    ctl[2usize] = 0.0f64
    ctl[3usize] = 1.0e-12f64
    ctl[4usize] = 1.0e-9f64
    ctl[5usize] = 1.0e-12f64
    let r = nlb.nlminb[NCtx](a, &c, nobj, ngrad, true, th[0usize..2usize], ctl[0usize..6usize])
    if r.iterations == 0usize && r.fevals == 0usize { ret g.Singular }
    npolish(a, &c, th[0usize..2usize])
    let f = ncore(a, &sp, th[0usize..2usize], coef, xi, vi)
    if !f.good { ret g.Singular }
    var j = 0usize
    while j < p {
        out[j] = coef[j]
        j += 1usize
    }
    out[p] = f.sigma
    out[p + 1usize] = f.loglik
    let npar = f64(p + 3usize)
    out[p + 2usize] = 0.0f64 - 2.0f64 * f.loglik + 2.0f64 * npar
    out[p + 3usize] = 0.0f64 - 2.0f64 * f.loglik + npar * math.log[f64](nobs)
    out[p + 4usize] = f.sigma * math.exp[f64](th[0usize])
    out[p + 5usize] = f.sigma * math.exp[f64](th[1usize])
    j = 0usize
    while j < p {
        out[p + 6usize + j] = f.sigma * math.sqrt[f64](xi[j * p + j])
        j += 1usize
    }
    // BLUPs: s_k sum over the group of (V^-1 (y - X beta)), s_k the relative variance of the level
    let bo = 2usize * p + 6usize
    i = 0usize
    while i < n1 + n2 {
        out[bo + i] = 0.0f64
        i += 1usize
    }
    let e1v = math.exp[f64](2.0f64 * th[0usize])
    let e2v = math.exp[f64](2.0f64 * th[1usize])
    i = 0usize
    while i < n {
        var res = 0.0f64
        var k = 0usize
        while k < n {
            var rk = y[k]
            j = 0usize
            while j < p {
                rk -= x[j * n + k] * coef[j]
                j += 1usize
            }
            res += vi[i * n + k] * rk
            k += 1usize
        }
        out[bo + o1[i]] += e1v * res
        out[bo + n1 + o2[i]] += e2v * res
        i += 1usize
    }
    ret ok
}
