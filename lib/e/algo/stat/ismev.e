// R ismev: the stationary generalized extreme value fit (gev.fit), the generalized Pareto fit above a threshold (gpd.fit) and the Gumbel
// fit (gum.fit), by Nelder-Mead on the package's negative log-likelihood from the package's starting values (penalty 1e6 outside the
// support), with the standard errors from the package's finite-difference Hessian (step 1e-3 on a central-difference gradient).
//
// The minimiser is tightened with restarts instead of copying R's stopping rule, so the fitted values agree with R to its optimiser
// tolerance, not bit for bit. Not here: covariates and link functions, pp.fit, rlarg.fit, return levels and profile likelihoods.

use e.math
use e.math.opt as opt
use e.mem

// kind 3 is gev.fit with location covariates: dm is the n by q design (row-major), the first q parameters are its coefficients
type Data = struct { x: []const f64, kind: usize, u: f64, dm: []const f64, q: usize }

fn nll(d: *Data, a: []const f64) -> f64 {
    let n = d.x.len
    var s = 0.0f64
    var i = 0usize
    if d.kind == 6usize {
        // gev.fit with covariates on the location, the scale and the shape: dm holds the three designs one after another (n by qm, n by qs, n by qx, row-major);
        // q packs qm + 64 qs + 4096 qx + 262144 (mulink + 2 siglink + 4 shlink), a link being 0 identity or 1 exp
        let qm = d.q % 64usize
        let qs = (d.q / 64usize) % 64usize
        let qx = (d.q / 4096usize) % 64usize
        let lk = d.q / 262144usize
        let rows = n
        var t1 = 0.0f64
        var t2 = 0.0f64
        var t3 = 0.0f64
        while i < rows {
            var mu = 0.0f64
            var sc = 0.0f64
            var xi = 0.0f64
            var j = 0usize
            while j < qm {
                mu += d.dm[i * qm + j] * a[j]
                j += 1usize
            }
            j = 0usize
            while j < qs {
                sc += d.dm[rows * qm + i * qs + j] * a[qm + j]
                j += 1usize
            }
            j = 0usize
            while j < qx {
                xi += d.dm[rows * (qm + qs) + i * qx + j] * a[qm + qs + j]
                j += 1usize
            }
            if lk % 2usize == 1usize { mu = math.exp[f64](mu) }
            if (lk / 2usize) % 2usize == 1usize { sc = math.exp[f64](sc) }
            if (lk / 4usize) % 2usize == 1usize { xi = math.exp[f64](xi) }
            if sc <= 0.0f64 { ret 1.0e6f64 }
            let y = 1.0f64 + xi * ((d.x[i] - mu) / sc)
            if y <= 0.0f64 { ret 1.0e6f64 }
            t1 += math.log[f64](sc)
            t2 += math.pow[f64](y, 0.0f64 - 1.0f64 / xi)
            t3 += math.log[f64](y) * (1.0f64 / xi + 1.0f64)
            i += 1usize
        }
        ret t1 + t2 + t3
    }
    if d.kind == 5usize {
        // pp.fit with a constant threshold u and npy observations per year (in q): mu, sigma, xi
        let mu = a[0usize]
        let sc = a[1usize]
        let xi = a[2usize]
        if sc <= 0.0f64 { ret 1.0e6f64 }
        let w = 1.0f64 + xi * (d.u - mu) / sc
        var nexc = 0usize
        while i < n {
            if d.x[i] > d.u { nexc += 1usize }
            i += 1usize
        }
        if nexc > 0usize && w < 0.0f64 { ret 1.0e6f64 }
        var l1 = 0.0f64
        var l2 = 0.0f64
        i = 0usize
        while i < n {
            let y = 1.0f64 + xi * ((d.x[i] - mu) / sc)
            if y <= 0.0f64 { ret 1.0e6f64 }
            if d.x[i] > d.u {
                l1 += math.log[f64](sc)
                l2 += math.log[f64](y) * (1.0f64 / xi + 1.0f64)
            }
            i += 1usize
        }
        ret l1 + l2 + f64(n) / f64(d.q) * math.pow[f64](w, 0.0f64 - 1.0f64 / xi)
    }
    if d.kind == 4usize {
        // rlarg.fit: the r largest order statistics of each of n rows (row-major in x, r in q)
        let r = d.q
        let rows = n / r
        let mu = a[0usize]
        let sc = a[1usize]
        let xi = a[2usize]
        if sc <= 0.0f64 { ret 1.0e6f64 }
        var tot = 0.0f64
        while i < rows {
            var mn = d.x[i * r]
            var rowsum = 0.0f64
            var j = 0usize
            while j < r {
                let v = d.x[i * r + j]
                let y = 1.0f64 + xi * (v - mu) / sc
                if y <= 0.0f64 { ret 1.0e6f64 }
                rowsum += (1.0f64 / xi + 1.0f64) * math.log[f64](y) + math.log[f64](sc)
                if v < mn { mn = v }
                j += 1usize
            }
            tot += math.pow[f64](1.0f64 + xi * (mn - mu) / sc, 0.0f64 - 1.0f64 / xi) + rowsum
            i += 1usize
        }
        ret tot
    }
    if d.kind == 3usize {
        let q = d.q
        let sc = a[q]
        let xi = a[q + 1usize]
        if sc <= 0.0f64 { ret 1.0e6f64 }
        var t1 = 0.0f64
        var t2 = 0.0f64
        while i < n {
            var mu = 0.0f64
            var j = 0usize
            while j < q {
                mu += d.dm[i * q + j] * a[j]
                j += 1usize
            }
            let y = 1.0f64 + xi * (d.x[i] - mu) / sc
            if y <= 0.0f64 { ret 1.0e6f64 }
            t1 += math.pow[f64](y, 0.0f64 - 1.0f64 / xi)
            t2 += math.log[f64](y)
            i += 1usize
        }
        ret f64(n) * math.log[f64](sc) + t1 + t2 * (1.0f64 / xi + 1.0f64)
    }
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
    var d = Data { x: x, kind: kind, u: u, dm: x[0usize..0usize], q: 0usize }
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
    let (nllh, e3) = minimise(a, &d, par)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, p)
    if e5 != ok { ret (zero, e5) }
    ret (Fit { par: par, se: se, nllh: nllh }, ok)
}

// Nelder-Mead from par, restarted until the value stops moving; par holds the minimiser on return, the value is returned
fn minimise(a: *mem.Arena, d: *Data, par: []f64) -> (f64, err) {
    let p = par.len
    let (scr, e2) = mem.alloc[f64](a, (p + 1usize) * (p + 1usize) + 4usize * p)
    if e2 != ok { ret (0.0f64, e2) }
    var round = 0usize
    var last = 1.0e30f64
    var res = opt.Result { value: 0.0f64, iterations: 0u32, converged: false }
    while round < 40usize {
        let (r, e3) = opt.nelder_mead[Data](d, nll, par, 0.1f64 * (1.0f64 + math.abs[f64](par[0usize])), 1.0e-15f64, 20000u32, scr)
        if e3 != ok { ret (0.0f64, e3) }
        res = r
        if math.abs[f64](last - r.value) < 1.0e-14f64 * (1.0f64 + math.abs[f64](r.value)) && round > 2usize { break }
        last = r.value
        round += 1usize
    }
    ret (res.value, ok)
}

// gev.fit(x, ydat = z, mul = 1): the location is b0 + b1 z (the design of the n by q matrix dm, row-major), with the scale and the shape;
// the start is the stationary moment fit with the slope coefficients at zero. Standard errors as in fit.
fn fit_mul(a: *mem.Arena, x: []const f64, dm: []const f64, q: usize) -> (Fit, err) {
    var d = Data { x: x, kind: 3usize, u: 0.0f64, dm: dm, q: q }
    let p = q + 2usize
    let (m, v) = mean_var(x)
    let in2 = math.sqrt[f64](6.0f64 * v) / 3.141592653589793f64
    let (par, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (zero, e1) }
    var j = 0usize
    while j < p {
        par[j] = 0.0f64
        j += 1usize
    }
    par[0usize] = m - 0.57722f64 * in2
    par[q] = in2
    par[q + 1usize] = 0.1f64
    let (nllh, e3) = minimise(a, &d, par)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, p)
    if e5 != ok { ret (zero, e5) }
    ret (Fit { par: par, se: se, nllh: nllh }, ok)
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

// rlarg.fit(x, r) with no covariates: x is rows by r row-major (the r largest values of each block, descending); the start is the stationary moment fit of the
// first column, then Nelder-Mead and the numerical Hessian as in fit
fn fit_rlarg(a: *mem.Arena, x: []const f64, rows: usize, r: usize) -> (Fit, err) {
    let (c1, e0) = mem.alloc[f64](a, rows)
    if e0 != ok { ret (zero, e0) }
    var i = 0usize
    while i < rows {
        c1[i] = x[i * r]
        i += 1usize
    }
    let (m, v) = mean_var(c1)
    let in2 = math.sqrt[f64](6.0f64 * v) / 3.141592653589793f64
    let (par, e1) = mem.alloc[f64](a, 3usize)
    if e1 != ok { ret (zero, e1) }
    par[0usize] = m - 0.57722f64 * in2
    par[1usize] = in2
    par[2usize] = 0.1f64
    var d = Data { x: x, kind: 4usize, u: 0.0f64, dm: x[0usize..0usize], q: r }
    let (nllh, e3) = minimise(a, &d, par)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, 3usize)
    if e5 != ok { ret (zero, e5) }
    ret (Fit { par: par, se: se, nllh: nllh }, ok)
}

// pp.fit(x, threshold, npy) with a constant threshold and no covariates: the point-process model of the exceedances of u, npy observations per year.
// The start is ismev's (the moment fit of the exceedances moved to the rate scale, shape 1e-8 in the location start, then 0.1).
fn fit_pp(a: *mem.Arena, x: []const f64, u: f64, npy: usize) -> (Fit, err) {
    var nex = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] > u { nex += 1usize }
        i += 1usize
    }
    let (ex, e0) = mem.alloc[f64](a, nex)
    if e0 != ok { ret (zero, e0) }
    nex = 0usize
    i = 0usize
    while i < x.len {
        if x[i] > u {
            ex[nex] = x[i]
            nex += 1usize
        }
        i += 1usize
    }
    let lrate = f64(nex) / f64(x.len)
    let (m, v) = mean_var(ex)
    var in2 = math.sqrt[f64](6.0f64 * v) / 3.141592653589793f64
    let in3 = 0.00000001f64
    in2 = math.exp[f64](math.log[f64](in2) + in3 * math.log[f64](lrate))
    let in1 = u - (in2 / in3) * (math.pow[f64](lrate, 0.0f64 - in3) - 1.0f64)
    let (par, e1) = mem.alloc[f64](a, 3usize)
    if e1 != ok { ret (zero, e1) }
    par[0usize] = in1
    par[1usize] = in2
    par[2usize] = 0.1f64
    var d = Data { x: x, kind: 5usize, u: u, dm: x[0usize..0usize], q: npy }
    let (nllh, e3) = minimise(a, &d, par)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, 3usize)
    if e5 != ok { ret (zero, e5) }
    let _ = m
    ret (Fit { par: par, se: se, nllh: nllh }, ok)
}

// the profile likelihoods behind gev.prof and gpd.prof: ismev plots them, so the values are the minima of the profile negative log-likelihood at each
// return level of a grid, each search started from the previous solution
type Prof = struct { x: []const f64, xp: f64, p: f64, m: f64, la: f64, u: f64 }

fn gev_plik(d: *Prof, a: []const f64) -> f64 {
    let n = d.x.len
    var i = 0usize
    var s1 = 0.0f64
    var s2 = 0.0f64
    if math.abs[f64](a[1usize]) < 0.000001f64 {
        let mu = d.xp + a[0usize] * math.log[f64](0.0f64 - math.log[f64](1.0f64 - d.p))
        if a[0usize] <= 0.0f64 { ret 1.0e6f64 }
        while i < n {
            let y = (d.x[i] - mu) / a[0usize]
            s1 += math.exp[f64](0.0f64 - y)
            s2 += y
            i += 1usize
        }
        ret f64(n) * math.log[f64](a[0usize]) + s1 + s2
    }
    let mu = d.xp - a[0usize] / a[1usize] * (math.pow[f64](0.0f64 - math.log[f64](1.0f64 - d.p), 0.0f64 - a[1usize]) - 1.0f64)
    if a[0usize] <= 0.0f64 { ret 1.0e6f64 }
    while i < n {
        let y = 1.0f64 + a[1usize] * ((d.x[i] - mu) / a[0usize])
        if y <= 0.0f64 { ret 1.0e6f64 }
        s1 += math.pow[f64](y, 0.0f64 - 1.0f64 / a[1usize])
        s2 += math.log[f64](y)
        i += 1usize
    }
    ret f64(n) * math.log[f64](a[0usize]) + s1 + s2 * (1.0f64 / a[1usize] + 1.0f64)
}

fn gpd_plik(d: *Prof, a: []const f64) -> f64 {
    let n = d.x.len
    let xi = a[0usize]
    let sc = (xi * (d.xp - d.u)) / (math.pow[f64](d.m * d.la, xi) - 1.0f64)
    var i = 0usize
    if math.abs[f64](xi) < 0.0001f64 {
        var t = 0.0f64
        while i < n {
            t += d.x[i] - d.u
            i += 1usize
        }
        ret f64(n) * math.log[f64](sc) + t / sc
    }
    var ls = 0.0f64
    while i < n {
        let y = 1.0f64 + xi * ((d.x[i] - d.u) / sc)
        if y <= 0.0f64 || sc <= 0.0f64 { ret 1.0e6f64 }
        ls += math.log[f64](y)
        i += 1usize
    }
    ret f64(n) * math.log[f64](sc) + ls * (1.0f64 / xi + 1.0f64)
}

// Nelder-Mead on the profile objective, restarted until the value stops moving
fn min_prof(a: *mem.Arena, d: *Prof, f: fn(*Prof, []const f64) -> f64, par: []f64) -> (f64, err) {
    let p = par.len
    let (scr, e2) = mem.alloc[f64](a, (p + 1usize) * (p + 1usize) + 4usize * p)
    if e2 != ok { ret (0.0f64, e2) }
    var round = 0usize
    var last = 1.0e30f64
    var val = 0.0f64
    while round < 40usize {
        let (r, e3) = opt.nelder_mead[Prof](d, f, par, 0.1f64 * (1.0f64 + math.abs[f64](par[0usize])), 1.0e-15f64, 20000u32, scr)
        if e3 != ok { ret (0.0f64, e3) }
        val = r.value
        if math.abs[f64](last - r.value) < 1.0e-14f64 * (1.0f64 + math.abs[f64](r.value)) && round > 2usize { break }
        last = r.value
        round += 1usize
    }
    ret (val, ok)
}

// gev.prof: the profile negative log-likelihood at nint return levels of the m-block return level from xlow to xup, out has nint entries
fn gev_profile(a: *mem.Arena, x: []const f64, m: f64, xlow: f64, xup: f64, nint: usize, out: []f64) -> err {
    let (f, e0) = fit(a, x, 0usize, 0.0f64)
    if e0 != ok { ret e0 }
    var d = Prof { x: x, xp: 0.0f64, p: 1.0f64 / m, m: m, la: 0.0f64, u: 0.0f64 }
    let (sol, e1) = mem.alloc[f64](a, 2usize)
    if e1 != ok { ret e1 }
    sol[0usize] = f.par[1usize]
    sol[1usize] = f.par[2usize]
    var i = 0usize
    while i < nint {
        d.xp = xlow + (xup - xlow) * f64(i) / f64(nint - 1usize)
        let (v, e2) = min_prof(a, &d, gev_plik, sol)
        if e2 != ok { ret e2 }
        out[i] = v
        i += 1usize
    }
    ret ok
}

// gpd.prof: the profile at nint return levels of the m-year level (npy observations a year), the threshold u and the exceedance rate la of gpd.fit
fn gpd_profile(a: *mem.Arena, x: []const f64, u: f64, m: f64, npy: f64, xlow: f64, xup: f64, nint: usize, out: []f64) -> err {
    let (f, e0) = fit(a, x, 1usize, u)
    if e0 != ok { ret e0 }
    var cnt = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] > u { cnt += 1usize }
        i += 1usize
    }
    let (ex, e1) = mem.alloc[f64](a, cnt)
    if e1 != ok { ret e1 }
    cnt = 0usize
    i = 0usize
    while i < x.len {
        if x[i] > u {
            ex[cnt] = x[i]
            cnt += 1usize
        }
        i += 1usize
    }
    var d = Prof { x: ex, xp: 0.0f64, p: 0.0f64, m: m * npy, la: f64(cnt) / f64(x.len), u: u }
    let (sol, e2) = mem.alloc[f64](a, 1usize)
    if e2 != ok { ret e2 }
    sol[0usize] = f.par[1usize]
    i = 0usize
    while i < nint {
        d.xp = xlow + (xup - xlow) * f64(i) / f64(nint - 1usize)
        let (v, e3) = min_prof(a, &d, gpd_plik, sol)
        if e3 != ok { ret e3 }
        out[i] = v
        i += 1usize
    }
    ret ok
}

// gev.fit(x, ydat, mul, sigl, shl, mulink, siglink, shlink): dm holds the designs of the location, scale and shape (intercept first) one after another
// (n by qm, n by qs, n by qx, row-major); links 0 identity, 1 exp. ismev's start: the moment fit for the three intercepts (not passed through the links),
// 0.1 for the shape intercept, zero for every slope.
fn fit_cov(a: *mem.Arena, x: []const f64, dm: []const f64, qm: usize, qs: usize, qx: usize, mulink: usize, siglink: usize, shlink: usize) -> (Fit, err) {
    let p = qm + qs + qx
    var d = Data { x: x, kind: 6usize, u: 0.0f64, dm: dm, q: qm + 64usize * qs + 4096usize * qx + 262144usize * (mulink + 2usize * siglink + 4usize * shlink) }
    let (m, v) = mean_var(x)
    let in2 = math.sqrt[f64](6.0f64 * v) / 3.141592653589793f64
    let (par, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (zero, e1) }
    var j = 0usize
    while j < p {
        par[j] = 0.0f64
        j += 1usize
    }
    par[0usize] = m - 0.57722f64 * in2
    par[qm] = in2
    par[qm + qs] = 0.1f64
    let (nllh, e3) = minimise(a, &d, par)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = hessian(a, &d, par)
    if e4 != ok { ret (zero, e4) }
    let (se, e5) = std_errors(a, h, p)
    if e5 != ok { ret (zero, e5) }
    ret (Fit { par: par, se: se, nllh: nllh }, ok)
}
