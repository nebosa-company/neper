// rugarch::ugarchfit(ugarchspec(sGARCH(1,1), constant mean, "norm")): the Gaussian quasi-maximum likelihood of r_t = mu + e_t, h_t = omega + alpha e_{t-1}^2 + beta h_{t-1} with rugarch's start of the recursion, h_1 = mean(e^2) (e at the current mu), maximised by BFGS and Nelder-Mead polishing on an unconstrained parameterisation that keeps
// omega > 0, alpha, beta >= 0 and alpha + beta < 1.
//
// Not here: other variance models and orders, ARMA means, other distributions, standard errors, forecasts, simulation, bootstrap.

use e.math
use e.math.opt as opt
use e.math.nmath as nm
use e.mem
use e.algo.stat.numhess as nh

type GCtx = struct { y: []const f64, n: usize, q: []f64 }

fn th(t: f64) -> f64 { ret 2.0f64 / (1.0f64 + math.exp[f64](0.0f64 - 2.0f64 * t)) - 1.0f64 }

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

type ECtx = struct { y: []const f64, n: usize, q: []f64 }

// the eGARCH(1,1) log-likelihood: log h_t = omega + alpha z_{t-1} + gamma (|z_{t-1}| - sqrt(2 / pi)) + beta log h_{t-1} with z = e / sqrt(h) and log h_1 = log mean(e^2)
fn egarch_ll(y: []const f64, n: usize, mu: f64, om: f64, al: f64, be: f64, ga: f64) -> f64 {
    var m2 = 0.0f64
    var i = 0usize
    while i < n {
        m2 += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    var lh = math.log[f64](m2 / f64(n))
    let ez = math.sqrt[f64](2.0f64 / 3.141592653589793238462643383279f64)
    var ll = 0.0f64
    i = 0usize
    while i < n {
        let e = y[i] - mu
        ll += 0.0f64 - 0.5f64 * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + lh + e * e * math.exp[f64](0.0f64 - lh))
        let z = e * math.exp[f64](0.0f64 - lh / 2.0f64)
        lh = om + al * z + ga * (math.abs[f64](z) - ez) + be * lh
        i += 1usize
    }
    ret ll
}

// x = (mu, omega, alpha, gamma, atanh beta)
fn egarch_f(c: *ECtx, x: []const f64) -> f64 {
    ret 0.0f64 - egarch_ll(c.y, c.n, x[0usize], x[1usize], x[2usize], th(x[4usize]), x[3usize])
}

fn egarch_g(c: *ECtx, x: []const f64, g: []f64) {
    var i = 0usize
    while i < 5usize {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = egarch_f(c, c.q[0usize..5usize])
        c.q[i] = x[i] - h
        let fm = egarch_f(c, c.q[0usize..5usize])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// the eGARCH(1,1) fit with a constant mean and normal innovations: out = mu, omega, alpha1, beta1, gamma1, the log-likelihood
fn egarch11(a: *mem.Arena, y: []const f64, n: usize, out: []f64) -> bool {
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
    var x: [5]f64 = zero
    x[0usize] = mean
    x[1usize] = 0.0f64 - 0.1f64
    x[2usize] = 0.0f64
    x[3usize] = 0.1f64
    x[4usize] = 1.0f64
    var c = ECtx { y: y, n: n, q: qq }
    var round = 0usize
    while round < 3usize {
        let (r2, e4) = opt.nelder_mead[ECtx](&c, egarch_f, x[0usize..5usize], 0.1f64, 1.0e-16f64, 3000u32, scr)
        if e4 != ok { ret false }
        let (r3, e5) = opt.bfgs[ECtx](&c, egarch_f, egarch_g, x[0usize..5usize], 1.0e-12f64, 400u32, scr)
        if e5 != ok { ret false }
        round += 1usize
    }
    out[0usize] = x[0usize]
    out[1usize] = x[1usize]
    out[2usize] = x[2usize]
    out[3usize] = th(x[4usize])
    out[4usize] = x[3usize]
    out[5usize] = egarch_ll(y, n, x[0usize], x[1usize], x[2usize], out[3usize], x[3usize])
    ret true
}

// the IGARCH(1,1) fit (alpha + beta = 1) with a constant mean and normal innovations, x = (mu, log omega, logit alpha), the same recursion start: out = mu, omega, alpha1, beta1, the log-likelihood
fn igarch_f(c: *GCtx, x: []const f64) -> f64 {
    let al = lg(x[2usize])
    ret 0.0f64 - garch_ll(c.y, c.n, x[0usize], math.exp[f64](x[1usize]), al, 1.0f64 - al)
}

fn igarch_g(c: *GCtx, x: []const f64, g: []f64) {
    var i = 0usize
    while i < 3usize {
        c.q[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        let h = 1.0e-6f64
        c.q[i] = x[i] + h
        let fp = igarch_f(c, c.q[0usize..3usize])
        c.q[i] = x[i] - h
        let fm = igarch_f(c, c.q[0usize..3usize])
        c.q[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

fn igarch11(a: *mem.Arena, y: []const f64, n: usize, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, 4usize)
    let (scr, e2) = mem.alloc[f64](a, 96usize)
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
    var x: [3]f64 = zero
    x[0usize] = mean
    x[1usize] = math.log[f64](v * 0.02f64)
    x[2usize] = math.log[f64](0.1f64 / 0.9f64)
    var c = GCtx { y: y, n: n, q: qq }
    var round = 0usize
    while round < 3usize {
        let (r2, e4) = opt.nelder_mead[GCtx](&c, igarch_f, x[0usize..3usize], 0.1f64, 1.0e-16f64, 3000u32, scr)
        if e4 != ok { ret false }
        let (r3, e5) = opt.bfgs[GCtx](&c, igarch_f, igarch_g, x[0usize..3usize], 1.0e-12f64, 400u32, scr)
        if e5 != ok { ret false }
        round += 1usize
    }
    let al = lg(x[2usize])
    out[0usize] = x[0usize]
    out[1usize] = math.exp[f64](x[1usize])
    out[2usize] = al
    out[3usize] = 1.0f64 - al
    out[4usize] = garch_ll(y, n, x[0usize], out[1usize], al, 1.0f64 - al)
    ret true
}

type GSeCtx = struct { y: []const f64, n: usize }

fn garch_nat_f(c: *GSeCtx, x: []const f64) -> f64 { ret 0.0f64 - garch_ll(c.y, c.n, x[0usize], x[1usize], x[2usize], x[3usize]) }

// the standard errors of the sGARCH(1,1) fit at est = (mu, omega, alpha1, beta1): the inverse of the Hessian of minus the log-likelihood on the natural parameters, as rugarch's vcov(fit)
fn garch11_se(a: *mem.Arena, y: []const f64, n: usize, est: []const f64, out: []f64) -> bool {
    var c = GSeCtx { y: y, n: n }
    ret nh.hessian_se[GSeCtx](a, &c, garch_nat_f, est, 4usize, out)
}

type GSe5Ctx = struct { y: []const f64, n: usize, model: usize }

// minus the log-likelihood of model 1 gjrGARCH, 2 eGARCH or 3 Student t sGARCH on the natural parameters x = (mu, omega, alpha, beta, gamma or shape)
fn garch5_f(c: *GSe5Ctx, x: []const f64) -> f64 {
    if c.model == 1usize { ret 0.0f64 - gjr_ll(c.y, c.n, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if c.model == 2usize { ret 0.0f64 - egarch_ll(c.y, c.n, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    ret 0.0f64 - garch_t_ll(c.y, c.n, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize])
}

// the standard errors of the gjrGARCH (model 1), eGARCH (2) or Student t (3) fits at est, the five natural parameters in the order the fit functions return them
fn garch5_se(a: *mem.Arena, y: []const f64, n: usize, model: usize, est: []const f64, out: []f64) -> bool {
    var c = GSe5Ctx { y: y, n: n, model: model }
    ret nh.hessian_se[GSe5Ctx](a, &c, garch5_f, est, 5usize, out)
}

type PqCtx = struct { y: []const f64, n: usize, p: usize, q: usize, h: []f64, e2: []f64, qq: []f64 }

// the log-likelihood of sGARCH(P, Q), h_t = omega + sum_i alpha_i e_{t-i}^2 + sum_j beta_j h_{t-j}, with the first max(P, Q) conditional variances set to mean(e^2) as rugarch does (checked at its own coefficients for (2, 1) and (1, 2)); par = mu, omega, alpha_1 .. alpha_P, beta_1 .. beta_Q
fn pq_ll(c: *PqCtx, par: []const f64) -> f64 {
    let n = c.n
    var m2 = 0.0f64
    var i = 0usize
    while i < n {
        let e = c.y[i] - par[0usize]
        c.e2[i] = e * e
        m2 += e * e
        i += 1usize
    }
    m2 = m2 / f64(n)
    var start = c.p
    if c.q > start { start = c.q }
    var ll = 0.0f64
    i = 0usize
    while i < n {
        var hv = m2
        if i >= start {
            hv = par[1usize]
            var a1 = 0usize
            while a1 < c.p {
                hv += par[2usize + a1] * c.e2[i - 1usize - a1]
                a1 += 1usize
            }
            var b1 = 0usize
            while b1 < c.q {
                hv += par[2usize + c.p + b1] * c.h[i - 1usize - b1]
                b1 += 1usize
            }
        }
        c.h[i] = hv
        ll += 0.0f64 - 0.5f64 * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + math.log[f64](hv) + c.e2[i] / hv)
        i += 1usize
    }
    ret ll
}

// minus the log-likelihood at x = (mu, log omega, log alpha_i, log beta_j); persistence at or above one costs a large constant
fn pq_f(c: *PqCtx, x: []const f64) -> f64 {
    let m = 2usize + c.p + c.q
    var par: [8]f64 = zero
    par[0usize] = x[0usize]
    var k = 1usize
    var pers = 0.0f64
    while k < m {
        par[k] = math.exp[f64](x[k])
        if k >= 2usize { pers += par[k] }
        k += 1usize
    }
    if pers >= 0.9999f64 { ret 1.0e8f64 }
    ret 0.0f64 - pq_ll(c, par[0usize..m])
}

fn pq_g(c: *PqCtx, x: []const f64, g: []f64) {
    let m = 2usize + c.p + c.q
    var i = 0usize
    while i < m {
        c.qq[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        let h = 1.0e-6f64
        c.qq[i] = x[i] + h
        let fp = pq_f(c, c.qq[0usize..m])
        c.qq[i] = x[i] - h
        let fm = pq_f(c, c.qq[0usize..m])
        c.qq[i] = x[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// the sGARCH(P, Q) fit (P and Q at most 3) with a constant mean and normal innovations: out = mu, omega, alpha_1 .. alpha_P, beta_1 .. beta_Q, the log-likelihood
fn sgarch_pq(a: *mem.Arena, y: []const f64, n: usize, p: usize, q: usize, out: []f64) -> bool {
    let m = 2usize + p + q
    let (hh, e1) = mem.alloc[f64](a, n)
    let (e2a, e2) = mem.alloc[f64](a, n)
    let (qq, e3) = mem.alloc[f64](a, m)
    let (scr, e4) = mem.alloc[f64](a, 256usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret false }
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
    var x: [8]f64 = zero
    x[0usize] = mean
    x[1usize] = math.log[f64](v * 0.05f64)
    var k = 0usize
    while k < p {
        x[2usize + k] = math.log[f64](0.1f64 / f64(p))
        k += 1usize
    }
    k = 0usize
    while k < q {
        x[2usize + p + k] = math.log[f64](0.7f64 / f64(q))
        k += 1usize
    }
    var c = PqCtx { y: y, n: n, p: p, q: q, h: hh, e2: e2a, qq: qq }
    var round = 0usize
    while round < 3usize {
        let (r2, e5) = opt.nelder_mead[PqCtx](&c, pq_f, x[0usize..m], 0.05f64, 1.0e-16f64, 4000u32, scr)
        if e5 != ok { ret false }
        let (r3, e6) = opt.bfgs[PqCtx](&c, pq_f, pq_g, x[0usize..m], 1.0e-12f64, 400u32, scr)
        if e6 != ok { ret false }
        round += 1usize
    }
    out[0usize] = x[0usize]
    k = 1usize
    while k < m {
        out[k] = math.exp[f64](x[k])
        k += 1usize
    }
    out[m] = 0.0f64 - pq_f(&c, x[0usize..m])
    ret true
}
