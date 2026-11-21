// R nlme::nlme: non-linear mixed-effects models with the self-start models of e.algo.stat.nlmelist (SSlogis, SSasymp, SSmicmen, SSfpl,
// SSgompertz), one grouping level, every parameter fixed ~ 1 with random effects on a subset of them (full log-Cholesky covariance), method "ML".
//
// nlme's alternating algorithm (Lindstrom and Bates): a penalized non-linear least-squares fit of the fixed effects and all random effects at the
// current relative covariance D (Gauss-Newton with step halving on the stacked system), then an ML fit of D on the linearisation at that fit, which is the
// lme profile objective of e.algo.stat.gls over the pseudo-response w = y - f + A beta + B b with A, B the derivatives of the model by the fixed and the
// random effects. R stops its iteration at its own pnlsTol (1e-3 by default), so its estimates sit ~1e-4 from the fixed point where the two steps
// reproduce each other; this module iterates to that fixed point (relative change below 3e-9; the D optimum is located to ~1e-9). Starting values are
// the pooled nls fit of the same self-start model, random effects start at zero.
// Not here: method "REML" (nlme's REML estimates differ from this linearisation's), covariates on the parameters, user-written model functions,
// nested random effects, correlation and variance structures.

use e.algo.stat.gls as g
use e.algo.stat.nlmelist as nl
use e.algo.stat.nlminb as nlb
use e.algo.stat.psych as ps
use e.math
use e.mem

type Lin = struct { kind: i64, n: usize, np: usize, ng: usize, nr: usize, gs: []const f64, x: []const f64, y: []const f64, rs: []usize }

fn nlme_len(np: usize, nr: usize, ng: usize) -> usize {
    ret np + 4usize + nr + nr * (nr - 1usize) / 2usize + np + ng * nr
}

// derivatives by the fixed effects (am, n by np column-major) and the random effects (bz, n by nr) and the pseudo-response w at (beta, bb)
fn linearize(c: *Lin, beta: []const f64, bb: []const f64, am: []f64, bz: []f64, w: []f64) {
    var gr: [4]f64 = zero
    var phi: [4]f64 = zero
    var t = 0usize
    var gi = 0usize
    while gi < c.ng {
        let m = usize(c.gs[gi])
        var k = 0usize
        while k < m {
            var j = 0usize
            while j < c.np {
                phi[j] = beta[j]
                j += 1usize
            }
            var r = 0usize
            while r < c.nr {
                phi[c.rs[r]] += bb[gi * c.nr + r]
                r += 1usize
            }
            let f = nl.ss_eval(c.kind, c.x[t], phi[0usize..4usize], gr[0usize..4usize])
            var wv = c.y[t] - f
            j = 0usize
            while j < c.np {
                am[j * c.n + t] = gr[j]
                wv += gr[j] * beta[j]
                j += 1usize
            }
            r = 0usize
            while r < c.nr {
                bz[r * c.n + t] = gr[c.rs[r]]
                wv += gr[c.rs[r]] * bb[gi * c.nr + r]
                r += 1usize
            }
            w[t] = wv
            t += 1usize
            k += 1usize
        }
        gi += 1usize
    }
}

// penalized residual sum of squares: sum (y - f)^2 + sum_g b_g' pm b_g
fn pobj(c: *Lin, pm: []const f64, beta: []const f64, bb: []const f64) -> f64 {
    var gr: [4]f64 = zero
    var phi: [4]f64 = zero
    var s = 0.0f64
    var t = 0usize
    var gi = 0usize
    while gi < c.ng {
        let m = usize(c.gs[gi])
        var k = 0usize
        while k < m {
            var j = 0usize
            while j < c.np {
                phi[j] = beta[j]
                j += 1usize
            }
            var r = 0usize
            while r < c.nr {
                phi[c.rs[r]] += bb[gi * c.nr + r]
                r += 1usize
            }
            let f = nl.ss_eval(c.kind, c.x[t], phi[0usize..4usize], gr[0usize..4usize])
            let e = c.y[t] - f
            s += e * e
            t += 1usize
            k += 1usize
        }
        var r = 0usize
        while r < c.nr {
            var r2 = 0usize
            while r2 < c.nr {
                s += bb[gi * c.nr + r] * pm[r * c.nr + r2] * bb[gi * c.nr + r2]
                r2 += 1usize
            }
            r += 1usize
        }
        gi += 1usize
    }
    ret s
}

// Gauss-Newton on (beta, b) for the penalized problem at the relative precision pm = D^-1, from the current beta and bb
fn pnls(a: *mem.Arena, c: *Lin, pm: []const f64, beta: []f64, bb: []f64) -> err {
    let np = c.np
    let nr = c.nr
    let m = np + c.ng * nr
    let st = mem.mark(a)
    let (hm, e1) = mem.alloc[f64](a, m * m)
    let (hi, e2) = mem.alloc[f64](a, m * m)
    let (rhs, e3) = mem.alloc[f64](a, m)
    let (dl, e4) = mem.alloc[f64](a, m)
    let (bt, e5) = mem.alloc[f64](a, np)
    let (bbt, e6) = mem.alloc[f64](a, c.ng * nr)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var gr: [4]f64 = zero
    var phi: [4]f64 = zero
    var jv: [8]f64 = zero
    var jc: [8]usize = zero
    var s0 = pobj(c, pm, beta, bb)
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
        var gi = 0usize
        while gi < c.ng {
            let ms = usize(c.gs[gi])
            var k = 0usize
            while k < ms {
                var j = 0usize
                while j < np {
                    phi[j] = beta[j]
                    j += 1usize
                }
                var r = 0usize
                while r < nr {
                    phi[c.rs[r]] += bb[gi * nr + r]
                    r += 1usize
                }
                let f = nl.ss_eval(c.kind, c.x[t], phi[0usize..4usize], gr[0usize..4usize])
                let res = c.y[t] - f
                j = 0usize
                while j < np {
                    jv[j] = gr[j]
                    jc[j] = j
                    j += 1usize
                }
                r = 0usize
                while r < nr {
                    jv[np + r] = gr[c.rs[r]]
                    jc[np + r] = np + gi * nr + r
                    r += 1usize
                }
                var a1 = 0usize
                while a1 < np + nr {
                    rhs[jc[a1]] += jv[a1] * res
                    var b1 = 0usize
                    while b1 < np + nr {
                        hm[jc[a1] * m + jc[b1]] += jv[a1] * jv[b1]
                        b1 += 1usize
                    }
                    a1 += 1usize
                }
                t += 1usize
                k += 1usize
            }
            var r1 = 0usize
            while r1 < nr {
                var r2 = 0usize
                while r2 < nr {
                    hm[(np + gi * nr + r1) * m + np + gi * nr + r2] += pm[r1 * nr + r2]
                    rhs[np + gi * nr + r1] -= pm[r1 * nr + r2] * bb[gi * nr + r2]
                    r2 += 1usize
                }
                r1 += 1usize
            }
            gi += 1usize
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
            while i < c.ng * nr {
                bbt[i] = bb[i] + hs * dl[np + i]
                i += 1usize
            }
            s1 = pobj(c, pm, bt, bbt)
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
        while i < c.ng * nr {
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

// kind: 1 SSlogis, 2 SSasymp, 3 SSmicmen, 4 SSfpl, 5 SSgompertz; gs group sizes (contiguous groups); rset 1-based parameter indices of the random effects.
// out: fixed effects (np), sigma, logLik, AIC, BIC, random-effect sds (nr), their correlations (lower triangle by columns), standard errors of the
// fixed effects (np), random effects (group-major)
fn nlme_fit(a: *mem.Arena, kind: i64, n: usize, gs: []const f64, x: []const f64, y: []const f64, rset: []const f64, reml: bool, out: []f64) -> err {
    let np = nl.ss_np(kind)
    let ng = gs.len
    let nr = rset.len
    let nrp = nr * (nr + 1usize) / 2usize
    let (rs, e0) = mem.alloc[usize](a, nr)
    let (beta, e1) = mem.alloc[f64](a, np)
    let (bb, e2) = mem.alloc[f64](a, ng * nr)
    let (am, e3) = mem.alloc[f64](a, n * np)
    let (bz, e4) = mem.alloc[f64](a, n * nr)
    let (w, e5) = mem.alloc[f64](a, n)
    let (pv, e6) = mem.alloc[f64](a, nrp + 1usize)
    let (pold, e7) = mem.alloc[f64](a, nrp + 1usize)
    let (nfit, e8) = mem.alloc[f64](a, nl.nls_len(kind))
    let (cf, e9) = mem.alloc[f64](a, np)
    let (xi, e10) = mem.alloc[f64](a, np * np)
    let (tz, e11) = mem.alloc[f64](a, n)
    let (dm, e12) = mem.alloc[f64](a, nr * nr + 1usize)
    let (pm, e13) = mem.alloc[f64](a, nr * nr + 1usize)
    let (bold, e14) = mem.alloc[f64](a, np + ng * nr)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e0 }
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret e8 }
    var i = 0usize
    while i < nr {
        rs[i] = usize(rset[i]) - 1usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        tz[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * nr {
        bb[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nrp {
        pv[i] = 0.0f64
        i += 1usize
    }
    let ne = nl.nls_fit(a, kind, n, x, y, nfit)
    if ne != ok { ret ne }
    i = 0usize
    while i < np {
        beta[i] = nfit[i]
        i += 1usize
    }
    var c = Lin { kind: kind, n: n, np: np, ng: ng, nr: nr, gs: gs, x: x, y: y, rs: rs }
    let nobs = f64(n)
    let cst = nobs * (math.log[f64](nobs) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    var ctl: [6]f64 = zero
    ctl[0usize] = 400.0f64
    ctl[1usize] = 150.0f64
    ctl[2usize] = 0.0f64
    ctl[3usize] = 1.0e-12f64
    ctl[4usize] = 1.0e-9f64
    ctl[5usize] = 1.0e-12f64
    var dd: [64]f64 = zero
    var conv = false
    var it = 0usize
    while it < 100usize && !conv {
        let st = mem.mark(a)
        linearize(&c, beta, bb, am, bz, w)
        let sp = g.Spec { n: n, p: np, x: am, y: w, t: tz, gs: gs, ng: ng, ck: 0i64, nv: 0usize, vk: tz[0usize..0usize], vn: tz[0usize..0usize], vc: tz[0usize..0usize], reml: false, q: nr, z: bz, pd: 0i64 }
        var cx = g.Ctx { a: a, s: sp, cst: cst }
        i = 0usize
        while i < nrp {
            pold[i] = pv[i]
            i += 1usize
        }
        let r = nlb.nlminb[g.Ctx](a, &cx, g.obj, nl.lme_grad, true, pv[0usize..nrp], ctl[0usize..6usize])
        if r.iterations == 0usize && r.fevals == 0usize {
            mem.reset(a, st)
            ret g.Singular
        }
        if it > 0usize { nl.lme_polish(a, &cx, pv[0usize..nrp]) }
        g.re_cov(nr, pv[0usize..nrp], dd[0usize..64usize], 0i64)
        i = 0usize
        while i < nr * nr {
            dm[i] = dd[i]
            i += 1usize
        }
        if !ps.invert(a, dm, nr, pm) {
            mem.reset(a, st)
            ret g.Singular
        }
        i = 0usize
        while i < np {
            bold[i] = beta[i]
            i += 1usize
        }
        i = 0usize
        while i < ng * nr {
            bold[np + i] = bb[i]
            i += 1usize
        }
        let pe = pnls(a, &c, pm, beta, bb)
        if pe != ok {
            mem.reset(a, st)
            ret pe
        }
        var ch = 0.0f64
        i = 0usize
        while i < np + ng * nr + nrp {
            var nv = 0.0f64
            var ov = 0.0f64
            if i < np {
                nv = beta[i]
                ov = bold[i]
            } else {
                if i < np + ng * nr {
                    nv = bb[i - np]
                    ov = bold[i]
                } else {
                    nv = pv[i - np - ng * nr]
                    ov = pold[i - np - ng * nr]
                }
            }
            var dv = nv - ov
            if dv < 0.0f64 { dv = 0.0f64 - dv }
            var sc = nv
            if sc < 0.0f64 { sc = 0.0f64 - sc }
            if sc < 1.0f64 { sc = 1.0f64 }
            if dv / sc > ch { ch = dv / sc }
            i += 1usize
        }
        if ch < 3.0e-9f64 { conv = true }
        mem.reset(a, st)
        it += 1usize
    }
    if !conv { ret g.Singular }
    linearize(&c, beta, bb, am, bz, w)
    let sp = g.Spec { n: n, p: np, x: am, y: w, t: tz, gs: gs, ng: ng, ck: 0i64, nv: 0usize, vk: tz[0usize..0usize], vn: tz[0usize..0usize], vc: tz[0usize..0usize], reml: reml, q: nr, z: bz, pd: 0i64 }
    let f = g.core(a, &sp, pv[0usize..nrp], cf, xi)
    if !f.good { ret g.Singular }
    g.re_cov(nr, pv[0usize..nrp], dd[0usize..64usize], 0i64)
    i = 0usize
    while i < np {
        out[i] = beta[i]
        i += 1usize
    }
    out[np] = f.sigma
    out[np + 1usize] = f.loglik
    let npar = f64(np + nrp + 1usize)
    // nlme's PNLS step estimates beta, b and D by ML whatever the method; REML only changes sigma, logLik and the standard errors afterwards
    var nrem = 0.0f64
    if reml { nrem = f64(np) }
    out[np + 2usize] = 0.0f64 - 2.0f64 * f.loglik + 2.0f64 * npar
    out[np + 3usize] = 0.0f64 - 2.0f64 * f.loglik + npar * math.log[f64](nobs - nrem)
    var o = np + 4usize
    var k = 0usize
    while k < nr {
        out[o + k] = f.sigma * math.sqrt[f64](dd[k * nr + k])
        k += 1usize
    }
    o += nr
    var l = 0usize
    while l < nr {
        k = l + 1usize
        while k < nr {
            out[o] = dd[k * nr + l] / math.sqrt[f64](dd[k * nr + k] * dd[l * nr + l])
            o += 1usize
            k += 1usize
        }
        l += 1usize
    }
    i = 0usize
    while i < np {
        out[o + i] = f.sigma * math.sqrt[f64](xi[i * np + i])
        i += 1usize
    }
    o += np
    i = 0usize
    while i < ng * nr {
        out[o + i] = bb[i]
        i += 1usize
    }
    ret ok
}
