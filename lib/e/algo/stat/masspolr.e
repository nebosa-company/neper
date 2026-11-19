// R MASS polr (ordered logistic, probit, loglog, cloglog and cauchit regression): the glm.fit start of polr, polr.fit's
// objective and gradient on (beta, theta) with theta the log-spacings of the cut points, optim's BFGS (vmmin) and optimHess for
// the Hessian. x is n by pc (no intercept), y holds the 1-based level of each case, levels is the number of levels.

use e.algo.stat.massnb as nb
use e.algo.stat.rbfgs as bf
use e.math
use e.math.dist as dist
use e.mem

error BadInput

// method 0 logistic, 1 probit, 2 loglog, 3 cloglog, 4 cauchit
fn pfun(method: usize, x: f64) -> f64 {
    if method == 0usize { ret dist.plogis(x, 0.0f64, 1.0f64, true, false) }
    if method == 1usize { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }
    if method == 2usize { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - x)) }
    if method == 3usize { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](x)) }
    ret dist.pcauchy(x, 0.0f64, 1.0f64, true, false)
}

fn dfun(method: usize, x: f64) -> f64 {
    if method == 0usize { ret dist.dlogis(x, 0.0f64, 1.0f64, false) }
    if method == 1usize { ret dist.dnorm(x, 0.0f64, 1.0f64, false) }
    if method == 2usize { ret math.exp[f64](0.0f64 - x - math.exp[f64](0.0f64 - x)) }
    if method == 3usize {
        let xx = 0.0f64 - x
        ret math.exp[f64](0.0f64 - xx - math.exp[f64](0.0f64 - xx))
    }
    ret dist.dcauchy(x, 0.0f64, 1.0f64, false)
}

type PCtx = struct { x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, pc: usize, q: usize, method: usize, gamm: []f64, z1: []f64, z2: []f64, pr: []f64 }

// the linear predictor, cut points and category probabilities at beta; returns whether every probability is positive
fn setup(c: *PCtx, beta: []const f64) -> bool {
    let pc = c.pc
    let q = c.q
    c.gamm[0usize] = 0.0f64 - 1.0f64 / 0.0f64
    var cum = beta[pc]
    c.gamm[1usize] = cum
    var k = 1usize
    while k < q {
        cum += math.exp[f64](beta[pc + k])
        c.gamm[k + 1usize] = cum
        k += 1usize
    }
    c.gamm[q + 1usize] = 1.0f64 / 0.0f64
    var allpos = true
    var i = 0usize
    while i < c.n {
        var eta = c.off[i]
        if pc > 0usize {
            var s = 0.0f64
            var j = 0usize
            while j < pc {
                s += c.x[i + c.n * j] * beta[j]
                j += 1usize
            }
            eta += s
        }
        let yi = usize(c.y[i])
        var z1 = c.gamm[yi] - eta
        if z1 > 100.0f64 { z1 = 100.0f64 }
        var z2 = c.gamm[yi - 1usize] - eta
        if z2 < -100.0f64 { z2 = -100.0f64 }
        c.z1[i] = z1
        c.z2[i] = z2
        c.pr[i] = pfun(c.method, z1) - pfun(c.method, z2)
        if !(c.pr[i] > 0.0f64) { allpos = false }
        i += 1usize
    }
    ret allpos
}

fn fmin(c: *PCtx, beta: []const f64) -> f64 {
    if !setup(c, beta) { ret 1.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        s += c.wt[i] * math.log[f64](c.pr[i])
        i += 1usize
    }
    ret 0.0f64 - s
}

fn gmin(c: *PCtx, beta: []const f64, out: []f64) {
    let pc = c.pc
    let q = c.q
    let ok_ = setup(c, beta)
    var k = 0usize
    while k < pc + q {
        out[k] = 0.0f64
        k += 1usize
    }
    if !ok_ {
        k = 0usize
        while k < pc + q {
            out[k] = 0.0f64 / 0.0f64
            k += 1usize
        }
        ret
    }
    var g2: [64]f64 = zero
    var i = 0usize
    while i < c.n {
        let p1 = dfun(c.method, c.z1[i])
        let p2 = dfun(c.method, c.z2[i])
        let r = c.wt[i] / c.pr[i]
        var j = 0usize
        while j < pc {
            out[j] += c.x[i + c.n * j] * (c.wt[i] * (p1 - p2) / c.pr[i])
            j += 1usize
        }
        let yi = usize(c.y[i])
        // xx[i, k] = (k == y) p1 - (k == y - 1) p2 (k = 1..q)
        if yi <= q { g2[yi - 1usize] += 0.0f64 - (p1 * r) }
        if yi >= 2usize { g2[yi - 2usize] += p2 * r }
        i += 1usize
    }
    // t(g2) %*% jacobian(theta): column 1 is all ones, column j has exp(theta_j) from row j down
    var s0 = 0.0f64
    k = 0usize
    while k < q {
        s0 += g2[k]
        k += 1usize
    }
    out[pc] = s0
    var jj = 1usize
    while jj < q {
        var s = 0.0f64
        k = jj
        while k < q {
            s += g2[k] * math.exp[f64](beta[pc + jj])
            k += 1usize
        }
        out[pc + jj] = s
        jj += 1usize
    }
}

type Polr = struct { beta: []f64, zeta: []f64, deviance: f64, fitted: []f64, hess: []f64 }

// polr(y ~ x, weights, offset, method, start): start (pc + q) is read when use_start. Hessian only when want_hess.
fn polr(a: *mem.Arena, x: []const f64, n: usize, pc: usize, y: []const f64, levels: usize, wt: []const f64, offset: []const f64, method: usize, use_start: bool, start_in: []const f64, want_hess: bool) -> (Polr, err) {
    var out: Polr = zero
    let q = levels - 1usize
    if q > 60usize { ret (out, BadInput) }
    let np = pc + q
    let (s0, e1) = mem.alloc[f64](a, np)
    let (gamm, e2) = mem.alloc[f64](a, q + 2usize)
    let (z1, e3) = mem.alloc[f64](a, n)
    let (z2, e4) = mem.alloc[f64](a, n)
    let (pr, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (out, mem.Full) }
    var start = start_in
    if !use_start {
        let q1 = levels / 2usize
        let (xx, e6) = mem.alloc[f64](a, n * (pc + 1usize))
        let (y1, e7) = mem.alloc[f64](a, n)
        if e6 != ok || e7 != ok { ret (out, mem.Full) }
        var i = 0usize
        while i < n {
            xx[i] = 1.0f64
            y1[i] = 0.0f64
            if usize(y[i]) > q1 { y1[i] = 1.0f64 }
            i += 1usize
        }
        i = 0usize
        while i < n * pc {
            xx[n + i] = x[i]
            i += 1usize
        }
        var link = 3usize
        if method == 4usize { link = 5usize } else if method != 0usize { link = 4usize }
        let (none, e8) = mem.alloc[f64](a, n)
        if e8 != ok { ret (out, mem.Full) }
        let (fit, fe) = nb.glm_fit(a, xx, n, pc + 1usize, y1, wt, offset, false, none, 2usize, 0.0f64, link, 1.0e-8f64, 25usize, true)
        if fe != ok { ret (out, fe) }
        if !fit.conv { ret (out, BadInput) }
        let (st, e9) = mem.alloc[f64](a, np)
        if e9 != ok { ret (out, mem.Full) }
        var j = 0usize
        while j < pc {
            st[j] = fit.coef[j + 1usize]
            j += 1usize
        }
        let qf = f64(q)
        var k = 0usize
        var sq1 = 0.0f64
        while k < q {
            let pk = f64(k + 1usize) / (qf + 1.0f64)
            var sp = math.log[f64](pk / (1.0f64 - pk))
            if method != 0usize { sp = sp / 1.7f64 }
            st[pc + k] = sp
            if k + 1usize == q1 { sq1 = sp }
            k += 1usize
        }
        k = 0usize
        while k < q {
            st[pc + k] = 0.0f64 - fit.coef[0usize] + st[pc + k] - sq1
            k += 1usize
        }
        start = st
    }
    var j = 0usize
    while j < pc {
        s0[j] = start[j]
        j += 1usize
    }
    s0[pc] = start[pc]
    var k = 1usize
    while k < q {
        s0[pc + k] = math.log[f64](start[pc + k] - start[pc + k - 1usize])
        k += 1usize
    }
    var c = PCtx { x: x, y: y, wt: wt, off: offset, n: n, pc: pc, q: q, method: method, gamm: gamm, z1: z1, z2: z2, pr: pr }
    let fv = bf.vmmin[PCtx](a, &c, fmin, gmin, s0, 1.4901161193847656e-08f64, 100usize)
    let (beta, e10) = mem.alloc[f64](a, pc + 1usize)
    let (zeta, e11) = mem.alloc[f64](a, q)
    let (fitted, e12) = mem.alloc[f64](a, n * levels)
    let (hs, e13) = mem.alloc[f64](a, np * np)
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (out, mem.Full) }
    j = 0usize
    while j < pc {
        beta[j] = s0[j]
        j += 1usize
    }
    var cum = s0[pc]
    zeta[0usize] = cum
    k = 1usize
    while k < q {
        cum += math.exp[f64](s0[pc + k])
        zeta[k] = cum
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var eta = offset[i]
        j = 0usize
        while j < pc {
            eta += x[i + n * j] * beta[j]
            j += 1usize
        }
        var prev = 0.0f64
        k = 0usize
        while k < q {
            let cp = pfun(method, zeta[k] - eta)
            fitted[i + n * k] = cp - prev
            prev = cp
            k += 1usize
        }
        fitted[i + n * q] = 1.0f64 - prev
        i += 1usize
    }
    if want_hess {
        let (g1, e14) = mem.alloc[f64](a, np)
        let (g2, e15) = mem.alloc[f64](a, np)
        let (bb, e16) = mem.alloc[f64](a, np)
        if e14 != ok || e15 != ok || e16 != ok { ret (out, mem.Full) }
        var r = 0usize
        while r < np {
            let eps = 0.001f64
            j = 0usize
            while j < np {
                bb[j] = s0[j]
                j += 1usize
            }
            bb[r] = s0[r] + eps
            gmin(&c, bb, g1)
            bb[r] = s0[r] - eps
            gmin(&c, bb, g2)
            var m = 0usize
            while m < np {
                hs[r * np + m] = (g1[m] - g2[m]) / (2.0f64 * eps)
                m += 1usize
            }
            r += 1usize
        }
        r = 0usize
        while r < np {
            var m = r + 1usize
            while m < np {
                let o = 0.5f64 * (hs[r * np + m] + hs[m * np + r])
                hs[r * np + m] = o
                hs[m * np + r] = o
                m += 1usize
            }
            r += 1usize
        }
    }
    out = Polr { beta: beta[0usize..pc], zeta: zeta, deviance: 2.0f64 * fv, fitted: fitted, hess: hs }
    ret (out, ok)
}
