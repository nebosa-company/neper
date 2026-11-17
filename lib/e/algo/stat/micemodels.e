// The classification fits behind R mice's polyreg and polr, step for step as R runs them so that the discrete draws agree:
//   nnet::multinom (nnet 7.3-20: the softmax or entropy network without hidden units, weights as case weights, zero start, the free weights through
//   optim's BFGS `vmmin` with nnet's abstol 1e-4 and reltol 1e-8, at most 100 iterations) and
//   MASS::polr (logistic: glm.fit start values, the log-spaced cut points, optim BFGS with the analytic gradient).
// Designs are column-major with the intercept as the first column of the multinom design; polr's design has none.
//
// Not here: multinom's offsets and weight decay, polr's other links, Hessians.

use e.algo.stat.rbfgs as bf
use e.math
use e.mem

error Singular

type NnCtx = struct {
    x: []const f64,
    y: []const usize,
    w: []const f64,
    n: usize,
    r: usize,
    k: usize,
    wts: []f64,
    free: []usize,
    slopes: []f64,
    outs: []f64,
}

// the weighted deviation of one pattern's output and its slopes; the network is the bias and the r inputs connected to each of the k outputs (one output with a logistic unit for two classes)
fn nn_pattern(c: *NnCtx, i: usize, grad: bool) -> f64 {
    let r = c.r
    let n = c.n
    var total = 0.0f64
    if c.k == 2usize {
        var sum = 0.0f64
        sum += 1.0f64 * c.wts[0usize]
        var q = 0usize
        while q < r {
            sum += c.x[q * n + i] * c.wts[1usize + q]
            q += 1usize
        }
        var out = 0.0f64
        if sum < 0.0f64 - 15.0f64 {
            out = 0.0f64
        } else if sum > 15.0f64 {
            out = 1.0f64
        } else {
            out = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - sum))
        }
        let t = f64(c.y[i])
        var e = 0.0f64
        if t > 0.0f64 { e -= t * math.log[f64]((out + 1.0e-80f64) / t) }
        if t < 1.0f64 { e -= (1.0f64 - t) * math.log[f64]((1.0f64 - out + 1.0e-80f64) / (1.0f64 - t)) }
        total = c.w[i] * e
        if grad {
            let dif = out - t
            c.slopes[0usize] += c.w[i] * dif * 1.0f64
            q = 0usize
            while q < r {
                c.slopes[1usize + q] += c.w[i] * dif * c.x[q * n + i]
                q += 1usize
            }
        }
        ret total
    }
    let k = c.k
    var o = 0usize
    while o < k {
        var sum = 0.0f64
        sum += 1.0f64 * c.wts[o * (r + 1usize)]
        var q = 0usize
        while q < r {
            sum += c.x[q * n + i] * c.wts[o * (r + 1usize) + 1usize + q]
            q += 1usize
        }
        c.outs[o] = sum
        o += 1usize
    }
    var mx = c.outs[0usize]
    o = 1usize
    while o < k {
        if c.outs[o] > mx { mx = c.outs[o] }
        o += 1usize
    }
    var sm = 0.0f64
    o = 0usize
    while o < k {
        c.outs[k + o] = math.exp[f64](c.outs[o] - mx)
        sm += c.outs[k + o]
        o += 1usize
    }
    o = 0usize
    while o < k {
        c.outs[k + o] = c.outs[k + o] / sm
        o += 1usize
    }
    let cl = c.y[i]
    if c.outs[k + cl] > 0.0f64 {
        total -= c.w[i] * 1.0f64 * math.log[f64](c.outs[k + cl])
    } else {
        total += c.w[i] * 1000.0f64
    }
    if grad {
        o = 0usize
        while o < k {
            var goal = 0.0f64
            if o == cl { goal = 1.0f64 }
            let dif = 1.0f64 * c.outs[k + o] - goal
            c.slopes[o * (r + 1usize)] += c.w[i] * dif * 1.0f64
            var q = 0usize
            while q < r {
                c.slopes[o * (r + 1usize) + 1usize + q] += c.w[i] * dif * c.x[q * n + i]
                q += 1usize
            }
            o += 1usize
        }
    }
    ret total
}

fn nn_f(c: *NnCtx, b: []const f64) -> f64 {
    var q = 0usize
    while q < b.len {
        c.wts[c.free[q]] = b[q]
        q += 1usize
    }
    var tot = 0.0f64
    var i = 0usize
    while i < c.n {
        tot += nn_pattern(c, i, false)
        i += 1usize
    }
    ret tot + 0.0f64
}

fn nn_g(c: *NnCtx, b: []const f64, g: []f64) {
    var q = 0usize
    while q < b.len {
        c.wts[c.free[q]] = b[q]
        q += 1usize
    }
    q = 0usize
    while q < c.slopes.len {
        c.slopes[q] = 0.0f64
        q += 1usize
    }
    var i = 0usize
    while i < c.n {
        let _ = nn_pattern(c, i, true)
        i += 1usize
    }
    q = 0usize
    while q < b.len {
        g[q] = c.slopes[c.free[q]]
        q += 1usize
    }
}

// nnet::multinom(maxit = 100) on the design x (n by r, the intercept included), classes y in 0 .. k - 1 with case weights w. wts receives the network weights: for two classes the bias (fixed at zero) and the r weights, for k classes k blocks of the bias and r weights, the first block fixed at zero
fn multinom_fit(a: *mem.Arena, x: []const f64, y: []const usize, w: []const f64, n: usize, r: usize, k: usize, wts: []f64) -> err {
    var nw = r + 1usize
    var nfree = r
    if k > 2usize {
        nw = k * (r + 1usize)
        nfree = (k - 1usize) * r
    }
    let (free, e1) = mem.alloc[usize](a, nfree)
    let (slopes, e2) = mem.alloc[f64](a, nw)
    let (outs, e3) = mem.alloc[f64](a, 2usize * k)
    let (b, e4) = mem.alloc[f64](a, nfree)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var q = 0usize
    while q < nw {
        wts[q] = 0.0f64
        q += 1usize
    }
    var fi = 0usize
    if k == 2usize {
        q = 0usize
        while q < r {
            free[fi] = 1usize + q
            fi += 1usize
            q += 1usize
        }
    } else {
        var o = 1usize
        while o < k {
            q = 0usize
            while q < r {
                free[fi] = o * (r + 1usize) + 1usize + q
                fi += 1usize
                q += 1usize
            }
            o += 1usize
        }
    }
    q = 0usize
    while q < nfree {
        b[q] = 0.0f64
        q += 1usize
    }
    var c: NnCtx = zero
    c.x = x
    c.y = y
    c.w = w
    c.n = n
    c.r = r
    c.k = k
    c.wts = wts
    c.free = free
    c.slopes = slopes
    c.outs = outs
    let fmin = bf.vmmin_abs[NnCtx](a, &c, nn_f, nn_g, b, 1.0e-8f64, 100usize, 1.0e-4f64)
    if fmin != fmin { ret Singular }
    q = 0usize
    while q < nfree {
        wts[free[q]] = b[q]
        q += 1usize
    }
    ret ok
}

// the class probabilities (k values) of the row i of the m by r design xm under the weights multinom_fit returned
fn multinom_probs(wts: []const f64, xm: []const f64, m: usize, r: usize, k: usize, i: usize, out: []f64) {
    if k == 2usize {
        var sum = 0.0f64
        sum += 1.0f64 * wts[0usize]
        var q = 0usize
        while q < r {
            sum += xm[q * m + i] * wts[1usize + q]
            q += 1usize
        }
        var p1 = 0.0f64
        if sum < 0.0f64 - 15.0f64 {
            p1 = 0.0f64
        } else if sum > 15.0f64 {
            p1 = 1.0f64
        } else {
            p1 = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - sum))
        }
        out[0usize] = 1.0f64 - p1
        out[1usize] = p1
        ret
    }
    var o = 0usize
    var mx = 0.0f64
    while o < k {
        var sum = 0.0f64
        sum += 1.0f64 * wts[o * (r + 1usize)]
        var q = 0usize
        while q < r {
            sum += xm[q * m + i] * wts[o * (r + 1usize) + 1usize + q]
            q += 1usize
        }
        out[o] = sum
        if o == 0usize || sum > mx { mx = sum }
        o += 1usize
    }
    var sm = 0.0f64
    o = 0usize
    while o < k {
        out[o] = math.exp[f64](out[o] - mx)
        sm += out[o]
        o += 1usize
    }
    o = 0usize
    while o < k {
        out[o] = out[o] / sm
        o += 1usize
    }
}

// glm.fit(x, y, weights, family = binomial()) for a 0/1 response: x is n by cd column-major with the intercept; returns the coefficients and whether the fit converged
fn glm_binomial(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, cd: usize, coef: []f64) -> err {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (xtx, e2) = mem.alloc[f64](a, cd * cd)
    let (xtz, e3) = mem.alloc[f64](a, cd)
    let (inv, e4) = mem.alloc[f64](a, cd * cd)
    let (lw, e5) = mem.alloc[f64](a, cd * cd)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    var devold = 0.0f64
    while i < n {
        let mu = (w[i] * y[i] + 0.5f64) / (w[i] + 1.0f64)
        eta[i] = math.log[f64](mu / (1.0f64 - mu))
        var d0 = 0.0f64
        if y[i] > 0.0f64 { d0 += y[i] * math.log[f64](y[i] / mu) }
        if y[i] < 1.0f64 { d0 += (1.0f64 - y[i]) * math.log[f64]((1.0f64 - y[i]) / (1.0f64 - mu)) }
        devold += 2.0f64 * w[i] * d0
        i += 1usize
    }
    var iter = 0usize
    var go = true
    while go && iter < 25usize {
        iter += 1usize
        var s1 = 0usize
        while s1 < cd {
            xtz[s1] = 0.0f64
            var s2 = 0usize
            while s2 < cd {
                xtx[s1 * cd + s2] = 0.0f64
                s2 += 1usize
            }
            s1 += 1usize
        }
        i = 0usize
        while i < n {
            let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
            let me = mu * (1.0f64 - mu)
            let wq = w[i] * me * me / (mu * (1.0f64 - mu))
            let z = eta[i] + (y[i] - mu) / me
            s1 = 0usize
            while s1 < cd {
                xtz[s1] += wq * x[s1 * n + i] * z
                var s2 = 0usize
                while s2 < cd {
                    xtx[s1 * cd + s2] += wq * x[s1 * n + i] * x[s2 * n + i]
                    s2 += 1usize
                }
                s1 += 1usize
            }
            i += 1usize
        }
        if !spd_solve(xtx, xtz, cd, coef, inv, lw) { ret Singular }
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var e = 0.0f64
            s1 = 0usize
            while s1 < cd {
                e += x[s1 * n + i] * coef[s1]
                s1 += 1usize
            }
            eta[i] = e
            let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e))
            var d1 = 0.0f64
            if y[i] > 0.0f64 { d1 += y[i] * math.log[f64](y[i] / mu) }
            if y[i] < 1.0f64 { d1 += (1.0f64 - y[i]) * math.log[f64]((1.0f64 - y[i]) / (1.0f64 - mu)) }
            dev += 2.0f64 * w[i] * d1
            i += 1usize
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            go = false
        } else {
            devold = dev
        }
    }
    ret ok
}

// solves the symmetric positive definite system a x = b (a is q by q row-major) by Cholesky; false when it is not positive definite
fn spd_solve(a: []const f64, b: []const f64, q: usize, x: []f64, tmp: []f64, l: []f64) -> bool {
    var i = 0usize
    while i < q {
        var j = 0usize
        while j <= i {
            var s = a[i * q + j]
            var k = 0usize
            while k < j {
                s -= l[i * q + k] * l[j * q + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret false }
                l[i * q + i] = math.sqrt[f64](s)
            } else {
                l[i * q + j] = s / l[j * q + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < q {
        var s = b[i]
        var k = 0usize
        while k < i {
            s -= l[i * q + k] * tmp[k]
            k += 1usize
        }
        tmp[i] = s / l[i * q + i]
        i += 1usize
    }
    i = q
    while i > 0usize {
        i -= 1usize
        var s = tmp[i]
        var k = i + 1usize
        while k < q {
            s -= l[k * q + i] * x[k]
            k += 1usize
        }
        x[i] = s / l[i * q + i]
    }
    ret true
}

type PolrCtx = struct {
    x: []const f64,
    y: []const usize,
    w: []const f64,
    n: usize,
    pc: usize,
    q: usize,
    eta: []f64,
    z1: []f64,
    z2: []f64,
    pr: []f64,
    gam: []f64,
}

fn plogis(z: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z)) }

fn dlogis(z: f64) -> f64 {
    let e = math.exp[f64](0.0f64 - math.abs[f64](z))
    let f = 1.0f64 + e
    ret e / (f * f)
}

// the cut points and the linear predictors of a parameter vector (the pc coefficients, then the first cut and the logs of the spacings); false when some probability is not positive
fn polr_setup(c: *PolrCtx, b: []const f64) -> bool {
    let q = c.q
    let pc = c.pc
    // gam[1 .. q] are the cumulative cuts, gam[0] = -Inf and gam[q + 1] = Inf
    c.gam[0usize] = 0.0f64 - 1.0f64 / 0.0f64
    var s = b[pc]
    c.gam[1usize] = s
    var j = 1usize
    while j < q {
        s += math.exp[f64](b[pc + j])
        c.gam[1usize + j] = s
        j += 1usize
    }
    c.gam[q + 1usize] = 1.0f64 / 0.0f64
    var all = true
    var i = 0usize
    while i < c.n {
        var e = 0.0f64
        var k = 0usize
        while k < pc {
            e += c.x[k * c.n + i] * b[k]
            k += 1usize
        }
        c.eta[i] = 0.0f64 + e
        let yi = c.y[i] + 1usize
        var u = c.gam[yi] - c.eta[i]
        if u > 100.0f64 { u = 100.0f64 }
        var l = c.gam[yi - 1usize] - c.eta[i]
        if l < 0.0f64 - 100.0f64 { l = 0.0f64 - 100.0f64 }
        c.z1[i] = u
        c.z2[i] = l
        c.pr[i] = plogis(u) - plogis(l)
        if !(c.pr[i] > 0.0f64) { all = false }
        i += 1usize
    }
    ret all
}

fn polr_f(c: *PolrCtx, b: []const f64) -> f64 {
    if !polr_setup(c, b) { ret 1.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        s += c.w[i] * math.log[f64](c.pr[i])
        i += 1usize
    }
    ret 0.0f64 - s
}

fn polr_g(c: *PolrCtx, b: []const f64, g: []f64) {
    let q = c.q
    let pc = c.pc
    let n = c.n
    if !polr_setup(c, b) {
        var t = 0usize
        while t < pc + q {
            g[t] = 0.0f64 / 0.0f64
            t += 1usize
        }
        ret
    }
    var k = 0usize
    while k < pc {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            let p1 = dlogis(c.z1[i])
            let p2 = dlogis(c.z2[i])
            s += c.x[k * n + i] * (c.w[i] * (p1 - p2) / c.pr[i])
            i += 1usize
        }
        g[k] = s
        k += 1usize
    }
    // g2[cl] = - sum_i xx[i, cl] w_i / pr_i with xx[i, cl] = [cl == y_i] p1_i - [cl == y_i - 1] p2_i (cl 1-based)
    var g2: [32]f64 = zero
    var i = 0usize
    while i < n {
        let yi = c.y[i] + 1usize
        let p1 = dlogis(c.z1[i])
        let p2 = dlogis(c.z2[i])
        var cl = 1usize
        while cl <= q {
            var xx = 0.0f64
            if cl == yi { xx += p1 }
            if cl + 1usize == yi { xx -= p2 }
            g2[cl - 1usize] += xx * (c.w[i] / c.pr[i])
            cl += 1usize
        }
        i += 1usize
    }
    var cl = 0usize
    while cl < q {
        g2[cl] = 0.0f64 - g2[cl]
        cl += 1usize
    }
    // jacobian: column 1 is ones, column j (j >= 2) holds exp(theta_j) in rows j .. q
    var j = 0usize
    while j < q {
        var s = 0.0f64
        if j == 0usize {
            var r = 0usize
            while r < q {
                s += g2[r]
                r += 1usize
            }
        } else {
            let et = math.exp[f64](b[pc + j])
            var r = j
            while r < q {
                s += g2[r] * et
                r += 1usize
            }
        }
        g[pc + j] = s
        j += 1usize
    }
}

// MASS::polr(method = "logistic") on the design x (n by pc, no intercept), classes y in 0 .. nl - 1 (nl >= 3) and weights w: par receives the pc coefficients and the nl - 1 cut points zeta
fn polr_fit(a: *mem.Arena, x: []const f64, y: []const usize, w: []const f64, n: usize, pc: usize, nl: usize, par: []f64) -> err {
    let q = nl - 1usize
    let (xi, e1) = mem.alloc[f64](a, n * (pc + 1usize))
    let (y1, e2) = mem.alloc[f64](a, n)
    let (coef, e3) = mem.alloc[f64](a, pc + 1usize)
    let (b, e4) = mem.alloc[f64](a, pc + q)
    let (eta, e5) = mem.alloc[f64](a, n)
    let (z1, e6) = mem.alloc[f64](a, n)
    let (z2, e7) = mem.alloc[f64](a, n)
    let (pr, e8) = mem.alloc[f64](a, n)
    let (gam, e9) = mem.alloc[f64](a, q + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    if q > 32usize { ret mem.Full }
    var i = 0usize
    while i < n {
        xi[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < pc {
        i = 0usize
        while i < n {
            xi[(k + 1usize) * n + i] = x[k * n + i]
            i += 1usize
        }
        k += 1usize
    }
    let q1 = nl / 2usize
    i = 0usize
    while i < n {
        y1[i] = 0.0f64
        if y[i] + 1usize > q1 { y1[i] = 1.0f64 }
        i += 1usize
    }
    let ge = glm_binomial(a, xi, y1, w, n, pc + 1usize, coef)
    if ge != ok { ret ge }
    // start: the coefficients, then gamma_j = -intercept + spacing_j - spacing_q1, spacing_j = logit(j / (q + 1))
    var sp: [32]f64 = zero
    var j = 0usize
    while j < q {
        let pj = f64(j + 1usize) / f64(q + 1usize)
        sp[j] = math.log[f64](pj / (1.0f64 - pj))
        j += 1usize
    }
    k = 0usize
    while k < pc {
        b[k] = coef[k + 1usize]
        k += 1usize
    }
    var prev = 0.0f64
    j = 0usize
    while j < q {
        let g = 0.0f64 - coef[0usize] + sp[j] - sp[q1 - 1usize]
        if j == 0usize {
            b[pc] = g
        } else {
            b[pc + j] = math.log[f64](g - prev)
        }
        prev = g
        j += 1usize
    }
    var c: PolrCtx = zero
    c.x = x
    c.y = y
    c.w = w
    c.n = n
    c.pc = pc
    c.q = q
    c.eta = eta
    c.z1 = z1
    c.z2 = z2
    c.pr = pr
    c.gam = gam
    let fmin = bf.vmmin[PolrCtx](a, &c, polr_f, polr_g, b, 1.4901161193847656e-08f64, 100usize)
    if fmin != fmin { ret Singular }
    k = 0usize
    while k < pc {
        par[k] = b[k]
        k += 1usize
    }
    var s = b[pc]
    par[pc] = s
    j = 1usize
    while j < q {
        s += math.exp[f64](b[pc + j])
        par[pc + j] = s
        j += 1usize
    }
    ret ok
}

// class probabilities (nl values) of row i of the m by pc design xm under polr_fit's parameters
fn polr_probs(par: []const f64, xm: []const f64, m: usize, pc: usize, nl: usize, i: usize, out: []f64) {
    let q = nl - 1usize
    var e = 0.0f64
    var k = 0usize
    while k < pc {
        e += xm[k * m + i] * par[k]
        k += 1usize
    }
    var prev = 0.0f64
    var j = 0usize
    while j < q {
        let cum = plogis(par[pc + j] - e)
        out[j] = cum - prev
        prev = cum
        j += 1usize
    }
    out[q] = 1.0f64 - prev
}
