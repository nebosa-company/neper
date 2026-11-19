// rugarch::ugarchfit(ugarchspec(sGARCH(1,1), constant mean, "norm")): the Gaussian quasi-maximum likelihood of r_t = mu + e_t, h_t = omega + alpha e_{t-1}^2 + beta h_{t-1} with rugarch's start of the recursion, h_1 = mean(e^2) (e at the current mu), maximised by BFGS and Nelder-Mead polishing on an unconstrained parameterisation that keeps
// omega > 0, alpha, beta >= 0 and alpha + beta < 1.
//
// Not here: other variance models and orders, ARMA means, other distributions, standard errors, forecasts, simulation, bootstrap.

use e.math
use e.math.opt as opt
use e.math.nmath as nm
use e.mem

type GCtx = struct { y: []const f64, n: usize, q: []f64 }

fn lg(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

// the log-likelihood at the natural parameters
fn garch_ll(y: []const f64, n: usize, mu: f64, om: f64, al: f64, be: f64) -> f64 {
    var m2 = 0.0f64
    var i = 0usize
    while i < n {
        m2 += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    m2 = m2 / f64(n)
    var h = m2
    var ll = 0.0f64
    i = 0usize
    while i < n {
        let e = y[i] - mu
        ll += 0.0f64 - 0.5f64 * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + math.log[f64](h) + e * e / h)
        h = om + al * e * e + be * h
        i += 1usize
    }
    ret ll
}

// the natural parameters of the unconstrained x = (mu, log omega, logit of alpha + beta, logit of alpha / (alpha + beta))
fn garch_nat(x: []const f64, o: []f64) {
    o[0usize] = x[0usize]
    o[1usize] = math.exp[f64](x[1usize])
    let s = lg(x[2usize])
    let w = lg(x[3usize])
    o[2usize] = s * w
    o[3usize] = s * (1.0f64 - w)
}

fn garch_f(c: *GCtx, x: []const f64) -> f64 {
    var nat: [4]f64 = zero
    garch_nat(x, nat[0usize..4usize])
    ret 0.0f64 - garch_ll(c.y, c.n, nat[0usize], nat[1usize], nat[2usize], nat[3usize])
}

fn garch_g(c: *GCtx, x: []const f64, g: []f64) {
    var i = 0usize
    while i < 4usize {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = garch_f(c, c.q[0usize..4usize])
        c.q[i] = x[i] - h
        let fm = garch_f(c, c.q[0usize..4usize])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// the fit to the series y: out = mu, omega, alpha1, beta1, the log-likelihood; false when the optimiser fails
fn garch11(a: *mem.Arena, y: []const f64, n: usize, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, 4usize)
    let (scr, e2) = mem.alloc[f64](a, 128usize)
    if e1 != ok || e2 != ok { ret false }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += y[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (y[i] - mean) * (y[i] - mean)
        i += 1usize
    }
    v = v / f64(n)
    var x: [4]f64 = zero
    x[0usize] = mean
    x[1usize] = math.log[f64](v * 0.05f64)
    x[2usize] = math.log[f64](0.9f64 / 0.1f64)
    x[3usize] = math.log[f64](0.1f64 / 0.8f64 * 1.0f64)
    var c = GCtx { y: y, n: n, q: qq }
    var round = 0usize
    while round < 4usize {
        let (r, e3) = opt.bfgs[GCtx](&c, garch_f, garch_g, x[0usize..4usize], 1.0e-12f64, 400u32, scr)
        if e3 != ok { ret false }
        round += 1usize
    }
    var pol = 0usize
    while pol < 3usize {
        let (r2, e4) = opt.nelder_mead[GCtx](&c, garch_f, x[0usize..4usize], 0.05f64, 1.0e-16f64, 3000u32, scr)
        if e4 != ok { ret false }
        let (r3, e5) = opt.bfgs[GCtx](&c, garch_f, garch_g, x[0usize..4usize], 1.0e-12f64, 400u32, scr)
        if e5 != ok { ret false }
        pol += 1usize
    }
    var nat: [4]f64 = zero
    garch_nat(x[0usize..4usize], nat[0usize..4usize])
    out[0usize] = nat[0usize]
    out[1usize] = nat[1usize]
    out[2usize] = nat[2usize]
    out[3usize] = nat[3usize]
    out[4usize] = garch_ll(y, n, nat[0usize], nat[1usize], nat[2usize], nat[3usize])
    ret true
}

type JCtx = struct { y: []const f64, n: usize, q: []f64 }

// the gjrGARCH(1,1) log-likelihood: h_t = omega + (alpha + gamma [e_{t-1} < 0]) e_{t-1}^2 + beta h_{t-1}, h_1 = mean(e^2)
fn gjr_ll(y: []const f64, n: usize, mu: f64, om: f64, al: f64, be: f64, ga: f64) -> f64 {
    var m2 = 0.0f64
    var i = 0usize
    while i < n {
        m2 += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    var h = m2 / f64(n)
    var ll = 0.0f64
    i = 0usize
    while i < n {
        let e = y[i] - mu
        ll += 0.0f64 - 0.5f64 * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + math.log[f64](h) + e * e / h)
        var a2 = al
        if e < 0.0f64 { a2 = al + ga }
        h = om + a2 * e * e + be * h
        i += 1usize
    }
    ret ll
}

// x = (mu, log omega, log alpha, log beta, gamma); infeasible points (alpha + gamma < 0, or persistence alpha + beta + gamma / 2 at least 1) cost a large constant
fn gjr_f(c: *JCtx, x: []const f64) -> f64 {
    let al = math.exp[f64](x[2usize])
    let be = math.exp[f64](x[3usize])
    let ga = x[4usize]
    if al + ga < 0.0f64 || al + be + ga / 2.0f64 >= 0.9999f64 { ret 1.0e8f64 }
    ret 0.0f64 - gjr_ll(c.y, c.n, x[0usize], math.exp[f64](x[1usize]), al, be, ga)
}

fn gjr_g(c: *JCtx, x: []const f64, g: []f64) {
    var i = 0usize
    while i < 5usize {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = gjr_f(c, c.q[0usize..5usize])
        c.q[i] = x[i] - h
        let fm = gjr_f(c, c.q[0usize..5usize])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// ugarchfit of sGARCH replaced by gjrGARCH(1,1), constant mean, normal: out = mu, omega, alpha1, beta1, gamma1, the log-likelihood
fn gjrgarch11(a: *mem.Arena, y: []const f64, n: usize, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, 5usize)
    let (scr, e2) = mem.alloc[f64](a, 160usize)
    if e1 != ok || e2 != ok { ret false }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += y[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (y[i] - mean) * (y[i] - mean)
        i += 1usize
    }
    v = v / f64(n)
    var x: [5]f64 = zero
    x[0usize] = mean
    x[1usize] = math.log[f64](v * 0.05f64)
    x[2usize] = math.log[f64](0.05f64)
    x[3usize] = math.log[f64](0.8f64)
    x[4usize] = 0.05f64
    var c = JCtx { y: y, n: n, q: qq }
    var round = 0usize
    while round < 3usize {
        let (r2, e4) = opt.nelder_mead[JCtx](&c, gjr_f, x[0usize..5usize], 0.05f64, 1.0e-16f64, 3000u32, scr)
        if e4 != ok { ret false }
        let (r3, e5) = opt.bfgs[JCtx](&c, gjr_f, gjr_g, x[0usize..5usize], 1.0e-12f64, 400u32, scr)
        if e5 != ok { ret false }
        round += 1usize
    }
    out[0usize] = x[0usize]
    out[1usize] = math.exp[f64](x[1usize])
    out[2usize] = math.exp[f64](x[2usize])
    out[3usize] = math.exp[f64](x[3usize])
    out[4usize] = x[4usize]
    out[5usize] = gjr_ll(y, n, x[0usize], out[1usize], out[2usize], out[3usize], out[4usize])
    ret true
}

// the sGARCH(1,1) log-likelihood with standardised Student t innovations of shape nu > 2 (rugarch's "std"), h_1 = mean(e^2)
fn garch_t_ll(y: []const f64, n: usize, mu: f64, om: f64, al: f64, be: f64, nu: f64) -> f64 {
    var m2 = 0.0f64
    var i = 0usize
    while i < n {
        m2 += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    var h = m2 / f64(n)
    let k = nm.lgammafn((nu + 1.0f64) / 2.0f64) - nm.lgammafn(nu / 2.0f64) - 0.5f64 * math.log[f64](3.141592653589793238462643383279f64 * (nu - 2.0f64))
    var ll = 0.0f64
    i = 0usize
    while i < n {
        let e = y[i] - mu
        ll += k - 0.5f64 * math.log[f64](h) - (nu + 1.0f64) / 2.0f64 * math.log[f64](1.0f64 + e * e / (h * (nu - 2.0f64)))
        h = om + al * e * e + be * h
        i += 1usize
    }
    ret ll
}

fn garch_t_f(c: *GCtx, x: []const f64) -> f64 {
    var nat: [4]f64 = zero
    garch_nat(x[0usize..4usize], nat[0usize..4usize])
    ret 0.0f64 - garch_t_ll(c.y, c.n, nat[0usize], nat[1usize], nat[2usize], nat[3usize], 2.0f64 + math.exp[f64](x[4usize]))
}

fn garch_t_g(c: *GCtx, x: []const f64, g: []f64) {
    var i = 0usize
    while i < 5usize {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = garch_t_f(c, c.q[0usize..5usize])
        c.q[i] = x[i] - h
        let fm = garch_t_f(c, c.q[0usize..5usize])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// the sGARCH(1,1) fit with t innovations: out = mu, omega, alpha1, beta1, shape, the log-likelihood
fn garch11_t(a: *mem.Arena, y: []const f64, n: usize, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, 5usize)
    let (scr, e2) = mem.alloc[f64](a, 160usize)
    if e1 != ok || e2 != ok { ret false }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += y[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (y[i] - mean) * (y[i] - mean)
        i += 1usize
    }
    v = v / f64(n)
    var x: [5]f64 = zero
    x[0usize] = mean
    x[1usize] = math.log[f64](v * 0.05f64)
    x[2usize] = math.log[f64](0.9f64 / 0.1f64)
    x[3usize] = math.log[f64](0.1f64 / 0.8f64)
    x[4usize] = math.log[f64](4.0f64)
    var c = GCtx { y: y, n: n, q: qq }
    var round = 0usize
    while round < 3usize {
        let (r2, e4) = opt.nelder_mead[GCtx](&c, garch_t_f, x[0usize..5usize], 0.05f64, 1.0e-16f64, 3000u32, scr)
        if e4 != ok { ret false }
        let (r3, e5) = opt.bfgs[GCtx](&c, garch_t_f, garch_t_g, x[0usize..5usize], 1.0e-12f64, 400u32, scr)
        if e5 != ok { ret false }
        round += 1usize
    }
    var nat: [4]f64 = zero
    garch_nat(x[0usize..5usize], nat[0usize..4usize])
    out[0usize] = nat[0usize]
    out[1usize] = nat[1usize]
    out[2usize] = nat[2usize]
    out[3usize] = nat[3usize]
    out[4usize] = 2.0f64 + math.exp[f64](x[4usize])
    out[5usize] = garch_t_ll(y, n, nat[0usize], nat[1usize], nat[2usize], nat[3usize], out[4usize])
    ret true
}
