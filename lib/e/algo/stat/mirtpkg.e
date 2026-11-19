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
        let fp = tpl_f(t.c, t.x[0usize..m])
        t.x[i] = par[i] - h
        let fm = tpl_f(t.c, t.x[0usize..m])
        t.x[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
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
