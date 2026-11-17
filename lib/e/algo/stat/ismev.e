// R ismev: the stationary generalized extreme value fit (gev.fit), the generalized Pareto fit above a threshold (gpd.fit) and the Gumbel
// fit (gum.fit), by Nelder-Mead on the package's negative log-likelihood from the package's starting values (penalty 1e6 outside the
// support), with the standard errors from the package's finite-difference Hessian (step 1e-3 on a central-difference gradient).
//
// The minimiser is tightened with restarts instead of copying R's stopping rule, so the fitted values agree with R to its optimiser
// tolerance, not bit for bit. Not here: covariates and link functions, pp.fit, rlarg.fit, return levels and profile likelihoods.

use e.math
use e.math.opt as opt
use e.mem

type Data = struct { x: []const f64, kind: usize, u: f64 }

fn nll(d: *Data, a: []const f64) -> f64 {
    let n = d.x.len
    var s = 0.0f64
    var i = 0usize
    if d.kind == 0usize {
        let mu = a[0usize]
        let sc = a[1usize]
        let xi = a[2usize]
        if sc <= 0.0f64 { ret 1.0e6f64 }
        var t1 = 0.0f64
        var t2 = 0.0f64
        while i < n {
            let y = 1.0f64 + xi * (d.x[i] - mu) / sc
            if y <= 0.0f64 { ret 1.0e6f64 }
            t1 += math.pow[f64](y, 0.0f64 - 1.0f64 / xi)
            t2 += math.log[f64](y)
            i += 1usize
        }
        ret f64(n) * math.log[f64](sc) + t1 + t2 * (1.0f64 / xi + 1.0f64)
    }
    if d.kind == 1usize {
        let sc = a[0usize]
        let xi = a[1usize]
        if sc <= 0.0f64 { ret 1.0e6f64 }
        var t2 = 0.0f64
        while i < n {
            let y = 1.0f64 + xi * (d.x[i] - d.u) / sc
            if y <= 0.0f64 { ret 1.0e6f64 }
            t2 += math.log[f64](y)
            i += 1usize
        }
        ret f64(n) * math.log[f64](sc) + t2 * (1.0f64 / xi + 1.0f64)
    }
    let mu = a[0usize]
    let sc = a[1usize]
    if sc <= 0.0f64 { ret 1.0e6f64 }
    while i < n {
        let y = (d.x[i] - mu) / sc
        s += math.log[f64](sc) + y + math.exp[f64](0.0f64 - y)
        i += 1usize
    }
    ret s
}

fn grad(d: *Data, a: []f64, g: []f64) {
    var j = 0usize
    while j < a.len {
        let keep = a[j]
        a[j] = keep + 1.0e-3f64
        let f1 = nll(d, a)
        a[j] = keep - 1.0e-3f64
        let f2 = nll(d, a)
        a[j] = keep
        g[j] = (f1 - f2) / 2.0e-3f64
        j += 1usize
    }
}

// H[i * p + j] as optimhess: central differences of the numerical gradient, then symmetrised
fn hessian(a0: *mem.Arena, d: *Data, par: []const f64) -> ([]f64, err) {
    let p = par.len
    let (h, e) = mem.alloc[f64](a0, p * p)
    if e != ok { ret (h, e) }
    let (a, e2) = mem.alloc[f64](a0, p)
    if e2 != ok { ret (h, e2) }
    let (g1, e3) = mem.alloc[f64](a0, p)
    if e3 != ok { ret (h, e3) }
    let (g2, e4) = mem.alloc[f64](a0, p)
    if e4 != ok { ret (h, e4) }
    var i = 0usize
    while i < p {
        var k = 0usize
        while k < p {
            a[k] = par[k]
            k += 1usize
        }
        a[i] = par[i] + 1.0e-3f64
        grad(d, a, g1)
        a[i] = par[i] - 1.0e-3f64
        grad(d, a, g2)
        var j = 0usize
        while j < p {
            h[i * p + j] = (g1[j] - g2[j]) / 2.0e-3f64
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = i + 1usize
        while j < p {
            let m = 0.5f64 * (h[i * p + j] + h[j * p + i])
            h[i * p + j] = m
            h[j * p + i] = m
            j += 1usize
        }
        i += 1usize
    }
    ret (h, ok)
}

// the standard errors: the square roots of the diagonal of the inverse Hessian (Gauss-Jordan)
fn std_errors(a: *mem.Arena, h: []const f64, p: usize) -> ([]f64, err) {
    let (m, e) = mem.alloc[f64](a, p * 2usize * p)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            m[i * 2usize * p + j] = h[i * p + j]
            m[i * 2usize * p + p + j] = 0.0f64
            j += 1usize
        }
        m[i * 2usize * p + p + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var piv = c
        var k = c + 1usize
        while k < p {
            if math.abs[f64](m[k * 2usize * p + c]) > math.abs[f64](m[piv * 2usize * p + c]) { piv = k }
            k += 1usize
        }
        var j = 0usize
        while j < 2usize * p {
            let t = m[c * 2usize * p + j]
            m[c * 2usize * p + j] = m[piv * 2usize * p + j]
            m[piv * 2usize * p + j] = t
            j += 1usize
        }
        let d = m[c * 2usize * p + c]
        j = 0usize
        while j < 2usize * p {
            m[c * 2usize * p + j] = m[c * 2usize * p + j] / d
            j += 1usize
        }
        k = 0usize
        while k < p {
            if k != c {
                let f = m[k * 2usize * p + c]
                j = 0usize
                while j < 2usize * p {
                    m[k * 2usize * p + j] -= f * m[c * 2usize * p + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
        c += 1usize
    }
    let (se, e2) = mem.alloc[f64](a, p)
    if e2 != ok { ret (se, e2) }
    i = 0usize
    while i < p {
        se[i] = math.sqrt[f64](m[i * 2usize * p + p + i])
        i += 1usize
    }
    ret (se, ok)
}

fn mean_var(x: []const f64) -> (f64, f64) {
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / f64(x.len)
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret (m, v / (f64(x.len) - 1.0f64))
}

type Fit = struct { par: []f64, se: []f64, nllh: f64 }

// kind 0 gev.fit, 1 gpd.fit (the exceedances of u), 2 gum.fit
fn fit(a: *mem.Arena, x: []const f64, kind: usize, u: f64) -> (Fit, err) {
    var d = Data { x: x, kind: kind, u: u }
    var xs = x
    if kind == 1usize {
        var cnt = 0usize
        var i = 0usize
        while i < x.len {
            if x[i] > u { cnt += 1usize }
            i += 1usize
        }
        let (ex, e0) = mem.alloc[f64](a, cnt)
        if e0 != ok { ret (zero, e0) }
        cnt = 0usize
        i = 0usize
        while i < x.len {
            if x[i] > u {
                ex[cnt] = x[i]
                cnt += 1usize
            }
            i += 1usize
        }
        xs = ex
        d.x = ex
    }
    let (m, v) = mean_var(xs)
    let in2 = math.sqrt[f64](6.0f64 * v) / 3.141592653589793f64
    let in1 = m - 0.57722f64 * in2
    var p = 3usize
    if kind == 1usize { p = 2usize }
    if kind == 2usize { p = 2usize }
    let (par, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (zero, e1) }
    if kind == 0usize {
        par[0usize] = in1
        par[1usize] = in2
        par[2usize] = 0.1f64
    }
    if kind == 1usize {
        par[0usize] = in2
        par[1usize] = 0.1f64
    }
    if kind == 2usize {
        par[0usize] = in1
        par[1usize] = in2
    }
    let (scr, e2) = mem.alloc[f64](a, (p + 1usize) * (p + 1usize) + 4usize * p)
    if e2 != ok { ret (zero, e2) }
    var round = 0usize
    var last = 1.0e30f64
    var res = opt.Result { value: 0.0f64, iterations: 0u32, converged: false }
    while round < 40usize {
        let (r, e3) = opt.nelder_mead[Data](&d, nll, par, 0.1f64 * (1.0f64 + math.abs[f64](par[0usize])), 1.0e-15f64, 20000u32, scr)
        if e3 != ok { ret (zero, e3) }
        res = r
        if math.abs[f64](last - r.value) < 1.0e-14f64 * (1.0f64 + math.abs[f64](r.value)) && round > 2usize { break }
        last = r.value
        round += 1usize
    }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, p)
    if e5 != ok { ret (zero, e5) }
    ret (Fit { par: par, se: se, nllh: res.value }, ok)
}

// ---- the closed-form helpers ismev exports: the GEV quantile, distribution function and density, the GPD quantile, distribution function and density, the return-level gradients ----

// gevq(a = (mu, sigma, xi), p): mu + sigma ((-log(1 - p))^-xi - 1) / xi, the Gumbel quantile at xi = 0
fn gevq(mu: f64, sg: f64, xi: f64, p: f64) -> f64 {
    if xi != 0.0f64 { ret mu + sg * (math.pow[f64](0.0f64 - math.log[f64](1.0f64 - p), 0.0f64 - xi) - 1.0f64) / xi }
    ret mu - sg * math.log[f64](0.0f64 - math.log[f64](1.0f64 - p))
}

fn gevf(mu: f64, sg: f64, xi: f64, z: f64) -> f64 {
    if xi != 0.0f64 { ret math.exp[f64](0.0f64 - math.pow[f64](1.0f64 + xi * (z - mu) / sg, 0.0f64 - 1.0f64 / xi)) }
    ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - (z - mu) / sg))
}

fn gev_dens(mu: f64, sg: f64, xi: f64, z: f64) -> f64 {
    if xi != 0.0f64 {
        let t = 1.0f64 + xi * (z - mu) / sg
        ret math.exp[f64](0.0f64 - math.pow[f64](t, 0.0f64 - 1.0f64 / xi)) * math.pow[f64](t, 0.0f64 - 1.0f64 / xi - 1.0f64) / sg
    }
    let y = (z - mu) / sg
    ret math.exp[f64](0.0f64 - y) * math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - y)) / sg
}

// gpdq(a = (sigma, xi), u, p): u + sigma (p^-xi - 1) / xi; gpdf and gpd.dens likewise
fn gpdq(sg: f64, xi: f64, u: f64, p: f64) -> f64 { ret u + sg * (math.pow[f64](p, 0.0f64 - xi) - 1.0f64) / xi }

fn gpdf(sg: f64, xi: f64, u: f64, z: f64) -> f64 { ret 1.0f64 - math.pow[f64](1.0f64 + xi * (z - u) / sg, 0.0f64 - 1.0f64 / xi) }

fn gpd_dens(sg: f64, xi: f64, u: f64, z: f64) -> f64 { ret math.pow[f64](1.0f64 + xi * (z - u) / sg, 0.0f64 - 1.0f64 / xi - 1.0f64) / sg }

// gpdq2(a, u, la, m): the m-observation return level u + sigma ((m la)^xi - 1) / xi
fn gpdq2(sg: f64, xi: f64, u: f64, la: f64, m: f64) -> f64 { ret u + sg * (math.pow[f64](m * la, xi) - 1.0f64) / xi }

// gev.rl.gradient(a, p)[k]: the gradient of the GEV return level with respect to (mu, sigma, xi)
fn gev_rl_gradient(sg: f64, xi: f64, p: f64, k: usize) -> f64 {
    if k == 0usize { ret 1.0f64 }
    let yp = 0.0f64 - math.log[f64](1.0f64 - p)
    let ypx = math.pow[f64](yp, 0.0f64 - xi)
    if k == 1usize { ret 0.0f64 - (1.0f64 - ypx) / xi }
    ret sg / (xi * xi) * (1.0f64 - ypx) - sg / xi * ypx * math.log[f64](yp)
}

// gpd.rl.gradient(a = (la, sigma, xi), m)[k]
fn gpd_rl_gradient(la: f64, sg: f64, xi: f64, m: f64, k: usize) -> f64 {
    if xi == 0.0f64 {
        if k == 0usize { ret sg / la }
        if k == 1usize { ret math.log[f64](m * la) }
        ret 0.0f64
    }
    let t = math.pow[f64](m * la, xi)
    if k == 0usize { ret sg * math.pow[f64](m, xi) * math.pow[f64](la, xi - 1.0f64) }
    if k == 1usize { ret (t - 1.0f64) / xi }
    ret 0.0f64 - sg / (xi * xi) * (t - 1.0f64) + sg / xi * t * math.log[f64](m * la)
}
