// R GeneralizedHyperbolic: the density of the generalized hyperbolic family dghyp(x, mu, delta, alpha, beta, lambda) and its special cases
// dnig (lambda = -1/2), dhyperb (lambda = 1) and dskewlap, on e.algo.stat.gslfns.bessel_knu.
//
// Not here: the distribution and quantile functions, random numbers, moments and fits.

use e.algo.stat.gslfns as gs
use e.math
use e.math.quadpack as qp
use e.algo.stat.pwr as pw
use e.algo.rand.r as rg
use e.algo.stat.splinepkg as sl
use e.mem

// log K_nu(x): the log of the trapezoid value, and for x beyond 100 (where K underflows well before the density does) the asymptotic series
// sqrt(pi / (2 x)) exp(-x) (1 + sum_k prod_{j <= k} (4 nu^2 - (2 j - 1)^2) / (j 8 x))
fn log_bessel_k(nu: f64, x: f64) -> f64 {
    if x <= 100.0f64 { ret math.log[f64](gs.bessel_knu(nu, x)) }
    var term = 1.0f64
    var sum = 1.0f64
    var j = 1.0f64
    while j < 40.0f64 {
        let f = 2.0f64 * j - 1.0f64
        term = term * (4.0f64 * nu * nu - f * f) / (j * 8.0f64 * x)
        sum += term
        if math.abs[f64](term) < 1.0e-17f64 * math.abs[f64](sum) { break }
        j += 1.0f64
    }
    ret 0.5f64 * math.log[f64](3.141592653589793238462643383279f64 / (2.0f64 * x)) - x + math.log[f64](sum)
}

// dghyp(x, param = c(mu, delta, alpha, beta, lambda)) in the (alpha, beta) parametrization, evaluated on the log scale so the tails do not underflow
fn dghyp(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let d = x - mu
    let r = math.sqrt[f64](delta * delta + d * d)
    let top = lambda * math.log[f64](gamma / delta) + log_bessel_k(lambda - 0.5f64, alpha * r) + beta * d
    let bot = 0.5f64 * math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + log_bessel_k(lambda, delta * gamma) + (0.5f64 - lambda) * math.log[f64](r / alpha)
    ret math.exp[f64](top - bot)
}

fn dnig(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret dghyp(x, mu, delta, alpha, beta, 0.0f64 - 0.5f64) }

fn dhyperb(x: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret dghyp(x, mu, delta, alpha, beta, 1.0f64) }

fn dskewlap(x: f64, mu: f64, alpha: f64, beta: f64) -> f64 {
    let ab = alpha + beta
    if x <= mu { ret math.exp[f64]((x - mu) / alpha) / ab }
    ret math.exp[f64]((mu - x) / beta) / ab
}

// ---- pghyp: R's ghypMode (a Brent maximiser of the log density over a bracket that grows by delta until the density falls below its value at mu) and pghyp
// (integrate() of the density from -Inf up to q when q is at or below the mode, from q to Inf above it, tolerance eps^0.25, 100 subdivisions; the upper tail is 1 - that)

type Gh = struct { mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64 }

fn gh_log(c: *Gh, x: f64) -> f64 { ret math.log[f64](dghyp(x, c.mu, c.delta, c.alpha, c.beta, c.lambda)) }

fn gh_dens(c: *Gh, x: f64) -> f64 { ret dghyp(x, c.mu, c.delta, c.alpha, c.beta, c.lambda) }

// R's Brent_fmin maximising the log density of c over [ax, bx] (optimize(maximum = TRUE): the negated function is minimised), tolerance eps^0.25
fn gh_fmin_max(c: *Gh, ax: f64, bx: f64) -> f64 {
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let cc = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps = math.sqrt[f64](2.220446049250313e-16f64)
    var a = ax
    var b = bx
    var v = a + cc * (b - a)
    var w = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = 0.0f64 - gh_log(c, x)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let xm = (a + b) * 0.5f64
        let tol1 = eps * math.abs[f64](x) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](x - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - x) || p >= q * (b - x) {
            if x < xm { e = b - x } else { e = a - x }
            d = cc * e
        } else {
            d = p / q
            u = x + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if x >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = x + d
        } else if d > 0.0f64 {
            u = x + tol1
        } else {
            u = x - tol1
        }
        let fu = 0.0f64 - gh_log(c, u)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = w
            w = x
            x = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || w == x {
                v = w
                fv = fw
                w = u
                fw = fu
            } else if fu <= fv || v == x || v == w {
                v = u
                fv = fu
            }
        }
    }
    ret x
}

fn ghyp_mode(mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    var c: Gh = zero
    c.mu = mu
    c.delta = delta
    c.alpha = alpha
    c.beta = beta
    c.lambda = lambda
    let at_mu = gh_dens(&c, mu)
    var hi = mu + delta
    while gh_dens(&c, hi) > at_mu { hi = hi + delta }
    var lo = mu - delta
    while gh_dens(&c, lo) > at_mu { lo = lo - delta }
    ret gh_fmin_max(&c, lo, hi)
}

fn pghyp(a: *mem.Arena, q: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    var c: Gh = zero
    c.mu = mu
    c.delta = delta
    c.alpha = alpha
    c.beta = beta
    c.lambda = lambda
    let mode = ghyp_mode(mu, delta, alpha, beta, lambda)
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    if q <= mode {
        let (r, e) = qp.qagi[Gh](a, &c, gh_dens, q, 0i64 - 1i64, tol, tol, 100usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        ret r.result
    }
    let (r2, e2) = qp.qagi[Gh](a, &c, gh_dens, q, 1i64, tol, tol, 100usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret 1.0f64 - r2.result
}

fn pnig(a: *mem.Arena, q: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret pghyp(a, q, mu, delta, alpha, beta, 0.0f64 - 0.5f64) }

fn phyperb(a: *mem.Arena, q: f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 { ret pghyp(a, q, mu, delta, alpha, beta, 1.0f64) }

// ghypMean and ghypVar (the moments of the generalised hyperbolic distribution): with z = delta gamma and R(k) = K(lambda + k, z) / K(lambda, z),
// mean = mu + delta beta R(1) / gamma and variance = delta^2 (R(1) / z + (beta / gamma)^2 (R(2) - R(1)^2))
fn ghyp_mean(mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let z = delta * gamma
    ret mu + delta * beta * (gs.bessel_knu(lambda + 1.0f64, z) / gs.bessel_knu(lambda, z)) / gamma
}

fn ghyp_var(delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let z = delta * gamma
    let k0 = gs.bessel_knu(lambda, z)
    let r1 = gs.bessel_knu(lambda + 1.0f64, z) / k0
    let r2 = gs.bessel_knu(lambda + 2.0f64, z) / k0
    let bg = beta / gamma
    ret delta * delta * (r1 / z + bg * bg * (r2 - r1 * r1))
}

// ---- qghyp with R's default method "spline": pghyp on 501 equally spaced points of the density range (ghypCalcRange at density tolerance 1e-5, found with
// uniroot), an fmm spline (e.algo.stat.splinepkg) through them, and uniroot on the spline minus p over the range, tolerance eps^0.25. Probabilities outside the
// spline's range would use the integrate method in R and return NaN here.
type GhRoot = struct { g: Gh, level: f64, sp_x: []f64, sp_y: []f64, sp_b: []f64, sp_c: []f64, sp_d: []f64, n: usize, p: f64, mode: usize }

fn gh_dens_minus(c: *GhRoot, x: f64) -> f64 { ret dghyp(x, c.g.mu, c.g.delta, c.g.alpha, c.g.beta, c.g.lambda) - c.level }

fn gh_spline_minus(c: *GhRoot, x: f64) -> f64 { ret sl.spline_eval(c.n, c.sp_x, c.sp_y, c.sp_b, c.sp_c, c.sp_d, x) - c.p }

fn ghyp_range(mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, tol: f64) -> (f64, f64) {
    let mode = ghyp_mode(mu, delta, alpha, beta, lambda)
    let sd = math.sqrt[f64](ghyp_var(delta, alpha, beta, lambda))
    var c: GhRoot = zero
    c.g.mu = mu
    c.g.delta = delta
    c.g.alpha = alpha
    c.g.beta = beta
    c.g.lambda = lambda
    c.level = tol
    var hi = mode + sd
    while dghyp(hi, mu, delta, alpha, beta, lambda) > tol { hi = hi + sd }
    var lo = mode - sd
    while dghyp(lo, mu, delta, alpha, beta, lambda) > tol { lo = lo - sd }
    let tl = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let up = pw.zeroin[GhRoot](&c, gh_dens_minus, mode, hi, tl, 1000i64)
    let dn = pw.zeroin[GhRoot](&c, gh_dens_minus, lo, mode, tl, 1000i64)
    ret (dn, up)
}

fn qghyp(a: *mem.Arena, p: f64, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let (xl, xu) = ghyp_range(mu, delta, alpha, beta, lambda, 0.00001f64)
    let p_lo = pghyp(a, xl, mu, delta, alpha, beta, lambda)
    let p_hi = pghyp(a, xu, mu, delta, alpha, beta, lambda)
    if !(p > p_lo && p < p_hi) { ret 0.0f64 / 0.0f64 }
    let n = 501usize
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ys, e2) = mem.alloc[f64](a, n)
    let (bb, e3) = mem.alloc[f64](a, n)
    let (cc, e4) = mem.alloc[f64](a, n)
    let (dd, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        xs[i] = xl + (xu - xl) * f64(i) / f64(n - 1usize)
        ys[i] = pghyp(a, xs[i], mu, delta, alpha, beta, lambda)
        i += 1usize
    }
    xs[n - 1usize] = xu
    sl.fmm_spline(n, xs, ys, bb, cc, dd)
    var c: GhRoot = zero
    c.n = n
    c.sp_x = xs
    c.sp_y = ys
    c.sp_b = bb
    c.sp_c = cc
    c.sp_d = dd
    c.p = p
    ret pw.zeroin[GhRoot](&c, gh_spline_minus, xl, xu, math.pow[f64](2.220446049250313e-16f64, 0.25f64), 1000i64)
}

// ---- rgig (lambda != 1) and rghyp (lambda != 1; rnig is lambda = -1/2): the ratio-of-uniforms generator of GeneralizedHyperbolic, on R's uniform stream, with the three
// uniroot calls (tolerances as in the package) that locate the bounding rectangle
type GigG = struct { beta: f64, m: f64, lambda: f64 }

fn gig_g(c: *GigG, y: f64) -> f64 {
    ret 0.5f64 * c.beta * y * y * y - y * y * (0.5f64 * c.beta * c.m + c.lambda + 1.0f64) + y * ((c.lambda - 1.0f64) * c.m - 0.5f64 * c.beta) + 0.5f64 * c.beta * c.m
}

fn rgig(r: *rg.Rng, n: usize, chi: f64, psi: f64, lambda: f64, out: []f64) {
    let alpha = math.sqrt[f64](psi / chi)
    let beta = math.sqrt[f64](psi * chi)
    let m = (lambda - 1.0f64 + math.sqrt[f64]((lambda - 1.0f64) * (lambda - 1.0f64) + beta * beta)) / beta
    var c: GigG = zero
    c.beta = beta
    c.m = m
    c.lambda = lambda
    var upper = m
    while gig_g(&c, upper) <= 0.0f64 { upper = 2.0f64 * upper }
    let eps = 2.220446049250313e-16f64
    var tl = math.pow[f64](eps, 0.25f64)
    let alt = eps + gig_g(&c, 0.0f64) / 10.0f64
    // rgig1 (lambda = 1) runs uniroot for the lower root at its default tolerance
    if alt < tl && lambda != 1.0f64 { tl = alt }
    let ym = pw.zeroin[GigG](&c, gig_g, 0.0f64, m, tl, 1000i64)
    let yp = pw.zeroin[GigG](&c, gig_g, m, upper, pw.uniroot_tol(), 1000i64)
    let a = (yp - m) * math.pow[f64](yp / m, 0.5f64 * (lambda - 1.0f64)) * math.exp[f64](0.0f64 - 0.25f64 * beta * (yp + 1.0f64 / yp - m - 1.0f64 / m))
    let b = (ym - m) * math.pow[f64](ym / m, 0.5f64 * (lambda - 1.0f64)) * math.exp[f64](0.0f64 - 0.25f64 * beta * (ym + 1.0f64 / ym - m - 1.0f64 / m))
    let cc = 0.0f64 - 0.25f64 * beta * (m + 1.0f64 / m) + 0.5f64 * (lambda - 1.0f64) * math.log[f64](m)
    var i = 0usize
    while i < n {
        var need = true
        var yv = 0.0f64
        while need {
            let r1 = rg.unif(r)
            let r2 = rg.unif(r)
            yv = m + a * r2 / r1 + b * (1.0f64 - r2) / r1
            if yv > 0.0f64 {
                if 0.0f64 - math.log[f64](r1) >= 0.0f64 - 0.5f64 * (lambda - 1.0f64) * math.log[f64](yv) + 0.25f64 * beta * (yv + 1.0f64 / yv) + cc { need = false }
            }
        }
        out[i] = yv / alpha
        i += 1usize
    }
}

fn rghyp(r: *rg.Rng, n: usize, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, out: []f64, x: []f64) {
    rgig(r, n, delta * delta, alpha * alpha - beta * beta, lambda, x)
    var i = 0usize
    while i < n {
        let sg = math.sqrt[f64](x[i])
        out[i] = mu + beta * sg * sg + sg * rg.rnorm(r, 0.0f64, 1.0f64)
        i += 1usize
    }
}

// ---- the skew-Laplace distribution function, quantile and random numbers, and the GIG density and mean
fn pskewlap(q: f64, mu: f64, alpha: f64, beta: f64) -> f64 {
    let ab = alpha + beta
    if q < mu { ret (alpha / ab) * math.exp[f64]((q - mu) / alpha) }
    ret 1.0f64 - (beta / ab) * math.exp[f64]((mu - q) / beta)
}

fn qskewlap(p: f64, mu: f64, alpha: f64, beta: f64) -> f64 {
    let ab = alpha + beta
    if p < alpha / ab { ret alpha * math.log[f64](p * ab / alpha) + mu }
    ret mu - beta * math.log[f64](ab * (1.0f64 - p) / beta)
}

// rskewlap: n standard exponentials, then n signs drawn as sample(c(-1, 1), n, replace = TRUE, prob = c(alpha, beta) / (alpha + beta)) does it
// (R's ProbSampleReplace: the probabilities sorted in decreasing order, then the first cumulative sum at or above each uniform)
fn rskewlap(r: *rg.Rng, n: usize, mu: f64, alpha: f64, beta: f64, out: []f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = rg.rexp(r, 1.0f64)
        i += 1usize
    }
    let ab = alpha + beta
    var p0 = alpha / ab
    var p1 = beta / ab
    var first_is_minus = true
    if p1 > p0 {
        first_is_minus = false
        let t = p0
        p0 = p1
        p1 = t
    }
    i = 0usize
    while i < n {
        let u = rg.unif(r)
        var minus = first_is_minus
        if u > p0 { minus = !first_is_minus }
        var mult = beta
        if minus { mult = 0.0f64 - alpha }
        out[i] = mult * y[i] + mu
        i += 1usize
    }
}

fn dgig(x: f64, chi: f64, psi: f64, lambda: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    let omega = math.sqrt[f64](chi * psi)
    ret math.exp[f64]((lambda / 2.0f64) * math.log[f64](psi / chi) - math.log[f64](2.0f64) - log_bessel_k(lambda, omega) + (lambda - 1.0f64) * math.log[f64](x) - 0.5f64 * (chi / x + psi * x))
}

fn gig_mean(chi: f64, psi: f64, lambda: f64) -> f64 {
    let omega = math.sqrt[f64](chi * psi)
    let eta = math.sqrt[f64](chi / psi)
    ret eta * gs.bessel_knu(lambda + 1.0f64, omega) / gs.bessel_knu(lambda, omega)
}

// GIG mode, raw moments (the "normal" case: eta^k K(lambda + k, omega) / K(lambda, omega)) and variance (the second raw moment less the squared mean)
fn gig_mode(chi: f64, psi: f64, lambda: f64) -> f64 { ret (lambda - 1.0f64 + math.sqrt[f64]((lambda - 1.0f64) * (lambda - 1.0f64) + chi * psi)) / psi }

fn gig_raw_mom(order: f64, chi: f64, psi: f64, lambda: f64) -> f64 {
    let omega = math.sqrt[f64](chi * psi)
    let eta = math.sqrt[f64](chi / psi)
    ret math.pow[f64](eta, order) * gs.bessel_knu(lambda + order, omega) / gs.bessel_knu(lambda, omega)
}

fn gig_var(chi: f64, psi: f64, lambda: f64) -> f64 {
    let m1 = gig_raw_mom(1.0f64, chi, psi, lambda)
    ret gig_raw_mom(2.0f64, chi, psi, lambda) - m1 * m1
}

// ---- ghypMom: the moments of the generalised hyperbolic distribution about mu (the package's momRecursion table and Bessel ratios), converted to raw (about 0) or
// central moments by the binomial expansion of momChangeAbout; kind 0 raw, 1 central, 2 about mu
fn ghyp_mom(a: *mem.Arena, order: usize, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, kind: usize) -> f64 {
    if order == 0usize { ret 1.0f64 }
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let zeta = delta * gamma
    let nn = order + 1usize
    let (tab, e1) = mem.alloc[f64](a, nn * nn)
    let (mm, e2) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    // the recursion table a[d][l] (1-based, row d, column l), zero elsewhere
    var i = 0usize
    while i < nn * nn {
        tab[i] = 0.0f64
        i += 1usize
    }
    tab[1usize * nn + 1usize] = 1.0f64
    if order > 1usize { tab[2usize * nn + 1usize] = 1.0f64 }
    var d = 2usize
    while d <= order {
        var l = 2usize
        while l <= d {
            tab[d * nn + l] = tab[(d - 1usize) * nn + (l - 1usize)] + tab[(d - 1usize) * nn + l] * (2.0f64 * f64(l) + 1.0f64 - f64(d))
            l += 1usize
        }
        d += 1usize
    }
    let k0 = gs.bessel_knu(lambda, zeta)
    // mm[i] = the i-th moment about mu
    mm[0usize] = 1.0f64
    var o = 1usize
    while o <= order {
        var s = 0.0f64
        var l = (o + 1usize) / 2usize
        while l <= o {
            let m = 2usize * l - o
            let coeff = tab[o * nn + l]
            let ratio = gs.bessel_knu(lambda + f64(l), zeta) / k0
            s += coeff * math.pow[f64](delta, 2.0f64 * f64(l)) * math.pow[f64](beta, f64(m)) * ratio / math.pow[f64](zeta, f64(l))
            l += 1usize
        }
        mm[o] = s
        o += 1usize
    }
    if kind == 2usize { ret mm[order] }
    var about = 0.0f64
    if kind == 1usize { about = ghyp_mean(mu, delta, alpha, beta, lambda) }
    // E[(X - about)^n] = sum_j C(n, j) (mu - about)^(n - j) E[(X - mu)^j]
    var tot = 0.0f64
    var c = 1.0f64
    var j = 0usize
    while j <= order {
        tot += c * math.pow[f64](mu - about, f64(order - j)) * mm[j]
        c = c * f64(order - j) / f64(j + 1usize)
        j += 1usize
    }
    ret tot
}

fn ghyp_skew(a: *mem.Arena, mu: f64, delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    let v = ghyp_mom(a, 2usize, mu, delta, alpha, beta, lambda, 1usize)
    ret ghyp_mom(a, 3usize, mu, delta, alpha, beta, lambda, 1usize) / math.pow[f64](v, 1.5f64)
}
