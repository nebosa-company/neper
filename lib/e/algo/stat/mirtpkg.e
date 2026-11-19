// mirt::mirt(data, 1, itemtype = "2PL"): the two-parameter logistic item response model P(y_ij = 1 | theta) = logistic(a_j theta + d_j) with theta ~ N(0, 1) integrated on mirt's quadrature (61 equally spaced points on [-6, 6], weights
// proportional to the normal density); mirt maximises it by EM, here the same marginal log-likelihood is maximised directly by BFGS on a central-difference gradient from a = 1, d = 0.
//
// Not here: other item types (Rasch, 3PL, graded, nominal), several factors, a free latent variance, missing responses, standard errors, scores, fit statistics, differential item functioning.

use e.math
use e.math.opt as opt
use e.mem

type TplCtx = struct { y: []const f64, cnt: []const f64, n: usize, j: usize, q: []const f64, w: []const f64, nq: usize, lp: []f64, lq: []f64, g: []f64 }

fn tpl_f(c: *TplCtx, par: []const f64) -> f64 {
    let nq = c.nq
    let j = c.j
    var k = 0usize
    while k < nq {
        var jj = 0usize
        while jj < j {
            let e = par[2usize * jj] * c.q[k] + par[2usize * jj + 1usize]
            // log P = -log(1 + exp(-e)), log (1 - P) = -log(1 + exp(e)), each computed stably
            var lpv = 0.0f64
            var lqv = 0.0f64
            if e >= 0.0f64 {
                lpv = 0.0f64 - math.log[f64](1.0f64 + math.exp[f64](0.0f64 - e))
                lqv = 0.0f64 - e - math.log[f64](1.0f64 + math.exp[f64](0.0f64 - e))
            } else {
                lpv = e - math.log[f64](1.0f64 + math.exp[f64](e))
                lqv = 0.0f64 - math.log[f64](1.0f64 + math.exp[f64](e))
            }
            c.lp[k * j + jj] = lpv
            c.lq[k * j + jj] = lqv
            jj += 1usize
        }
        k += 1usize
    }
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        if c.cnt[i] == 0.0f64 {
            i += 1usize
            continue
        }
        var mx = 0.0f64 - 1.0e300f64
        k = 0usize
        while k < nq {
            var s = math.log[f64](c.w[k])
            var jj = 0usize
            while jj < j {
                if c.y[i * j + jj] > 0.5f64 { s += c.lp[k * j + jj] } else { s += c.lq[k * j + jj] }
                jj += 1usize
            }
            c.g[k] = s
            if s > mx { mx = s }
            k += 1usize
        }
        var tot = 0.0f64
        k = 0usize
        while k < nq {
            tot += math.exp[f64](c.g[k] - mx)
            k += 1usize
        }
        ll += c.cnt[i] * (mx + math.log[f64](tot))
        i += 1usize
    }
    ret 0.0f64 - ll
}

type TplGrad = struct { c: *TplCtx, x: []f64 }

fn tpl_g(t: *TplGrad, par: []const f64, g: []f64) {
    let c = t.c
    let nq = c.nq
    let j = c.j
    // tpl_f at par fills lp and lq, which the gradient reuses: d(ll)/d(a_j) = sum over patterns of count times the posterior mean of (y - P) q, and of (y - P) for d_j
    let fv = tpl_f(c, par)
    var jj = 0usize
    while jj < 2usize * j {
        g[jj] = 0.0f64
        jj += 1usize
    }
    var i = 0usize
    while i < c.n {
        if c.cnt[i] == 0.0f64 {
            i += 1usize
            continue
        }
        var mx = 0.0f64 - 1.0e300f64
        var k = 0usize
        while k < nq {
            var s = math.log[f64](c.w[k])
            jj = 0usize
            while jj < j {
                if c.y[i * j + jj] > 0.5f64 { s += c.lp[k * j + jj] } else { s += c.lq[k * j + jj] }
                jj += 1usize
            }
            c.g[k] = s
            if s > mx { mx = s }
            k += 1usize
        }
        var tot = 0.0f64
        k = 0usize
        while k < nq {
            c.g[k] = math.exp[f64](c.g[k] - mx)
            tot += c.g[k]
            k += 1usize
        }
        k = 0usize
        while k < nq {
            let r = c.cnt[i] * c.g[k] / tot
            jj = 0usize
            while jj < j {
                let pk = math.exp[f64](c.lp[k * j + jj])
                let res = c.y[i * j + jj] - pk
                g[2usize * jj] += 0.0f64 - r * res * c.q[k]
                g[2usize * jj + 1usize] += 0.0f64 - r * res
                jj += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
}

fn tpl_fw(t: *TplGrad, par: []const f64) -> f64 { ret tpl_f(t.c, par) }

// the fit to the n by j 0/1 response matrix y (row-major): out = a_1, d_1, a_2, d_2, ..., then the log-likelihood
fn tpl(a: *mem.Arena, y: []const f64, n: usize, j: usize, out: []f64) -> bool {
    let nq = 61usize
    let m = 2usize * j
    let (q, e1) = mem.alloc[f64](a, nq)
    let (w, e2) = mem.alloc[f64](a, nq)
    let (lp, e3) = mem.alloc[f64](a, nq * j)
    let (lq, e4) = mem.alloc[f64](a, nq * j)
    let (gg, e5) = mem.alloc[f64](a, nq)
    let (par, e6) = mem.alloc[f64](a, m)
    let (xx, e7) = mem.alloc[f64](a, m)
    let (scr, e8) = mem.alloc[f64](a, m * m + 6usize * m + 16usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret false }
    var sw = 0.0f64
    var k = 0usize
    while k < nq {
        q[k] = 0.0f64 - 6.0f64 + 12.0f64 * f64(k) / 60.0f64
        w[k] = math.exp[f64](0.0f64 - q[k] * q[k] / 2.0f64)
        sw += w[k]
        k += 1usize
    }
    k = 0usize
    while k < nq {
        w[k] = w[k] / sw
        k += 1usize
    }
    var jj = 0usize
    while jj < j {
        par[2usize * jj] = 1.0f64
        par[2usize * jj + 1usize] = 0.0f64
        jj += 1usize
    }
    let (cnt, e10) = mem.alloc[f64](a, n)
    if e10 != ok { ret false }
    var pi = 0usize
    while pi < n {
        cnt[pi] = 1.0f64
        var qi = 0usize
        while qi < pi {
            if cnt[qi] > 0.0f64 {
                var same = true
                var jx = 0usize
                while jx < j {
                    if y[qi * j + jx] != y[pi * j + jx] { same = false }
                    jx += 1usize
                }
                if same {
                    cnt[qi] += 1.0f64
                    cnt[pi] = 0.0f64
                    break
                }
            }
            qi += 1usize
        }
        pi += 1usize
    }
    var c = TplCtx { y: y, cnt: cnt, n: n, j: j, q: q, w: w, nq: nq, lp: lp, lq: lq, g: gg }
    var t = TplGrad { c: &c, x: xx }
    var round = 0usize
    while round < 2usize {
        let (r, e9) = opt.bfgs[TplGrad](&t, tpl_fw, tpl_g, par, 1.0e-9f64, 120u32, scr)
        if e9 != ok { ret false }
        round += 1usize
    }
    k = 0usize
    while k < m {
        out[k] = par[k]
        k += 1usize
    }
    out[m] = 0.0f64 - tpl_f(&c, par)
    ret true
}

type RasCtx = struct { c: *TplCtx, full: []f64 }

// the Rasch model as a 2PL with every slope the latent standard deviation s = exp(par[j]) (theta = s q on the standard normal quadrature) and the intercepts par[0 .. j - 1]
fn ras_f(r: *RasCtx, par: []const f64) -> f64 {
    let j = r.c.j
    let s = math.exp[f64](par[j])
    var jj = 0usize
    while jj < j {
        r.full[2usize * jj] = s
        r.full[2usize * jj + 1usize] = par[jj]
        jj += 1usize
    }
    ret tpl_f(r.c, r.full[0usize..2usize * j])
}

type RasGrad = struct { r: *RasCtx, x: []f64 }

fn ras_fw(t: *RasGrad, par: []const f64) -> f64 { ret ras_f(t.r, par) }

fn ras_g(t: *RasGrad, par: []const f64, g: []f64) {
    let r = t.r
    let j = r.c.j
    let s = math.exp[f64](par[j])
    var jj = 0usize
    while jj < j {
        r.full[2usize * jj] = s
        r.full[2usize * jj + 1usize] = par[jj]
        jj += 1usize
    }
    // the 2PL analytic gradient at (s, d): the intercepts directly, log s through every slope (d s / d log s = s)
    var tg = TplGrad { c: r.c, x: t.x }
    var gf: [64]f64 = zero
    tpl_g(&tg, r.full[0usize..2usize * j], gf[0usize..2usize * j])
    g[j] = 0.0f64
    jj = 0usize
    while jj < j {
        g[jj] = gf[2usize * jj + 1usize]
        g[j] += gf[2usize * jj] * s
        jj += 1usize
    }
}

// mirt(data, 1, itemtype = "Rasch"): unit slopes, free intercepts and a free latent variance; out = d_1 .. d_j, the latent variance, the log-likelihood
fn rasch(a: *mem.Arena, y: []const f64, n: usize, j: usize, out: []f64) -> bool {
    let nq = 61usize
    let m = j + 1usize
    let (q, e1) = mem.alloc[f64](a, nq)
    let (w, e2) = mem.alloc[f64](a, nq)
    let (lp, e3) = mem.alloc[f64](a, nq * j)
    let (lq, e4) = mem.alloc[f64](a, nq * j)
    let (gg, e5) = mem.alloc[f64](a, nq)
    let (par, e6) = mem.alloc[f64](a, m)
    let (xx, e7) = mem.alloc[f64](a, m)
    let (scr, e8) = mem.alloc[f64](a, m * m + 6usize * m + 16usize)
    let (cnt, e10) = mem.alloc[f64](a, n)
    let (full, e11) = mem.alloc[f64](a, 2usize * j)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e10 != ok || e11 != ok { ret false }
    var sw = 0.0f64
    var k = 0usize
    while k < nq {
        q[k] = 0.0f64 - 6.0f64 + 12.0f64 * f64(k) / 60.0f64
        w[k] = math.exp[f64](0.0f64 - q[k] * q[k] / 2.0f64)
        sw += w[k]
        k += 1usize
    }
    k = 0usize
    while k < nq {
        w[k] = w[k] / sw
        k += 1usize
    }
    var pi = 0usize
    while pi < n {
        cnt[pi] = 1.0f64
        var qi = 0usize
        while qi < pi {
            if cnt[qi] > 0.0f64 {
                var same = true
                var jx = 0usize
                while jx < j {
                    if y[qi * j + jx] != y[pi * j + jx] { same = false }
                    jx += 1usize
                }
                if same {
                    cnt[qi] += 1.0f64
                    cnt[pi] = 0.0f64
                    break
                }
            }
            qi += 1usize
        }
        pi += 1usize
    }
    var jj = 0usize
    while jj < j {
        par[jj] = 0.0f64
        jj += 1usize
    }
    par[j] = 0.0f64
    var c = TplCtx { y: y, cnt: cnt, n: n, j: j, q: q, w: w, nq: nq, lp: lp, lq: lq, g: gg }
    var r = RasCtx { c: &c, full: full }
    var t = RasGrad { r: &r, x: xx }
    var round = 0usize
    while round < 2usize {
        let (rr, e9) = opt.bfgs[RasGrad](&t, ras_fw, ras_g, par, 1.0e-9f64, 120u32, scr)
        if e9 != ok { ret false }
        round += 1usize
    }
    k = 0usize
    while k < j {
        out[k] = par[k]
        k += 1usize
    }
    out[j] = math.exp[f64](2.0f64 * par[j])
    out[j + 1usize] = 0.0f64 - ras_f(&r, par)
    ret true
}

type GrCtx = struct { y: []const f64, n: usize, j: usize, kc: usize, q: []const f64, w: []const f64, nq: usize, lt: []f64, g: []f64 }

fn lgst(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

// minus the marginal log-likelihood of the graded response model: item i has slope par[i (kc)], first intercept par[i kc + 1] and each further intercept the previous one less exp(par), so that P(y >= c | theta) = logistic(a theta + d_c)
// decreases in c; lt receives log P(y = c | theta_k) for every item, quadrature point and category
fn gr_f(c: *GrCtx, par: []const f64) -> f64 {
    let kc = c.kc
    let j = c.j
    var it = 0usize
    while it < j {
        let base = it * kc
        var k = 0usize
        while k < c.nq {
            var prev = 1.0f64
            var d = 0.0f64
            var cat = 0usize
            while cat < kc {
                var nxt = 0.0f64
                if cat + 1usize < kc {
                    if cat == 0usize { d = par[base + 1usize] } else { d = d - math.exp[f64](par[base + 1usize + cat]) }
                    nxt = lgst(par[base] * c.q[k] + d)
                }
                var pr = prev - nxt
                if pr < 1.0e-300f64 { pr = 1.0e-300f64 }
                c.lt[(it * c.nq + k) * kc + cat] = math.log[f64](pr)
                prev = nxt
                cat += 1usize
            }
            k += 1usize
        }
        it += 1usize
    }
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var mx = 0.0f64 - 1.0e300f64
        var k = 0usize
        while k < c.nq {
            var s = math.log[f64](c.w[k])
            var jj = 0usize
            while jj < j {
                s += c.lt[(jj * c.nq + k) * kc + usize(c.y[i * j + jj])]
                jj += 1usize
            }
            c.g[k] = s
            if s > mx { mx = s }
            k += 1usize
        }
        var tot = 0.0f64
        k = 0usize
        while k < c.nq {
            tot += math.exp[f64](c.g[k] - mx)
            k += 1usize
        }
        ll += mx + math.log[f64](tot)
        i += 1usize
    }
    ret 0.0f64 - ll
}

type GrGrad = struct { c: *GrCtx, x: []f64 }

fn gr_fw(t: *GrGrad, par: []const f64) -> f64 { ret gr_f(t.c, par) }

fn gr_g(t: *GrGrad, par: []const f64, g: []f64) {
    let m = par.len
    var i = 0usize
    while i < m {
        t.x[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        let h = 1.0e-6f64
        t.x[i] = par[i] + h
        let fp = gr_f(t.c, t.x[0usize..m])
        t.x[i] = par[i] - h
        let fm = gr_f(t.c, t.x[0usize..m])
        t.x[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// mirt(data, 1, itemtype = "graded") for responses coded 0 .. kc - 1 on every item: out = per item the slope and the kc - 1 intercepts (decreasing), then the log-likelihood
fn graded(a: *mem.Arena, y: []const f64, n: usize, j: usize, kc: usize, out: []f64) -> bool {
    let nq = 61usize
    let m = j * kc
    let (q, e1) = mem.alloc[f64](a, nq)
    let (w, e2) = mem.alloc[f64](a, nq)
    let (lt, e3) = mem.alloc[f64](a, j * nq * kc)
    let (gg, e5) = mem.alloc[f64](a, nq)
    let (par, e6) = mem.alloc[f64](a, m)
    let (xx, e7) = mem.alloc[f64](a, m)
    let (scr, e8) = mem.alloc[f64](a, m * m + 6usize * m + 16usize)
    if e1 != ok || e2 != ok || e3 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret false }
    var sw = 0.0f64
    var k = 0usize
    while k < nq {
        q[k] = 0.0f64 - 6.0f64 + 12.0f64 * f64(k) / 60.0f64
        w[k] = math.exp[f64](0.0f64 - q[k] * q[k] / 2.0f64)
        sw += w[k]
        k += 1usize
    }
    k = 0usize
    while k < nq {
        w[k] = w[k] / sw
        k += 1usize
    }
    var it = 0usize
    while it < j {
        par[it * kc] = 1.0f64
        par[it * kc + 1usize] = 1.0f64
        var cat = 2usize
        while cat < kc {
            par[it * kc + cat] = 0.0f64
            cat += 1usize
        }
        it += 1usize
    }
    var c = GrCtx { y: y, n: n, j: j, kc: kc, q: q, w: w, nq: nq, lt: lt, g: gg }
    var t = GrGrad { c: &c, x: xx }
    var round = 0usize
    while round < 2usize {
        let (r, e9) = opt.bfgs[GrGrad](&t, gr_fw, gr_g, par, 1.0e-9f64, 150u32, scr)
        if e9 != ok { ret false }
        round += 1usize
    }
    it = 0usize
    while it < j {
        out[it * kc] = par[it * kc]
        var d = 0.0f64
        var cat = 1usize
        while cat < kc {
            if cat == 1usize { d = par[it * kc + 1usize] } else { d = d - math.exp[f64](par[it * kc + cat]) }
            out[it * kc + cat] = d
            cat += 1usize
        }
        it += 1usize
    }
    out[m] = 0.0f64 - gr_f(&c, par)
    ret true
}
