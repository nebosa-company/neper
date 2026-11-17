// R statmod::gauss.quad and gauss.quad.prob: the nodes and weights of Gauss quadrature from the Jacobi matrix of the
// orthogonal polynomials, by the implicit QL method (as gausq2) tracking only the first row of the eigenvectors.
// gauss.quad kinds: 0 Legendre, 1 Chebyshev first kind, 2 Chebyshev second kind, 3 Hermite, 4 Jacobi (alpha, beta),
// 5 Laguerre (alpha). gauss.quad.prob dists: 0 uniform(l, u), 1 beta1, 2 beta2, 3 normal(mu, sigma),
// 4 beta(alpha, beta), 5 gamma(alpha, beta).
//
// Not here: the inverse Gaussian and Tweedie distributions of statmod, qresiduals, power.fisher.test.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.test as tst
use e.math
use e.math.dist as mdist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

fn sign_of(a: f64, b: f64) -> f64 {
    if b >= 0.0f64 { ret math.abs[f64](a) }
    ret 0.0f64 - math.abs[f64](a)
}

// diagonal d (n), off-diagonal e (n, last unused), first-row vector z (n); on return d holds the ascending nodes
// and z the matching first components
fn imtql(n: usize, d: []f64, e: []f64, z: []f64) -> bool {
    if n == 1usize { ret true }
    e[n - 1usize] = 0.0f64
    var l = 0usize
    while l < n {
        var iter = 0usize
        while true {
            var m = l
            while m + 1usize < n {
                let dd = math.abs[f64](d[m]) + math.abs[f64](d[m + 1usize])
                if math.abs[f64](e[m]) <= 2.220446049250313e-16f64 * dd { break }
                m += 1usize
            }
            if m == l { break }
            if iter == 60usize { ret false }
            iter += 1usize
            var g = (d[l + 1usize] - d[l]) / (2.0f64 * e[l])
            var r = math.sqrt[f64](g * g + 1.0f64)
            g = d[m] - d[l] + e[l] / (g + sign_of(r, g))
            var s = 1.0f64
            var c = 1.0f64
            var p = 0.0f64
            var i = m
            while i > l {
                i -= 1usize
                var f = s * e[i]
                let b = c * e[i]
                if math.abs[f64](f) >= math.abs[f64](g) {
                    c = g / f
                    r = math.sqrt[f64](c * c + 1.0f64)
                    e[i + 1usize] = f * r
                    s = 1.0f64 / r
                    c = c * s
                } else {
                    s = f / g
                    r = math.sqrt[f64](s * s + 1.0f64)
                    e[i + 1usize] = g * r
                    c = 1.0f64 / r
                    s = s * c
                }
                g = d[i + 1usize] - p
                r = (d[i] - g) * s + 2.0f64 * c * b
                p = s * r
                d[i + 1usize] = g + p
                g = c * r - b
                f = z[i + 1usize]
                z[i + 1usize] = s * z[i] + c * f
                z[i] = c * z[i] - s * f
            }
            d[l] = d[l] - p
            e[l] = g
            e[m] = 0.0f64
        }
        l += 1usize
    }
    var i = 0usize
    while i + 1usize < n {
        var k = i
        var j = i + 1usize
        while j < n {
            if d[j] < d[k] { k = j }
            j += 1usize
        }
        if k != i {
            let t = d[i]
            d[i] = d[k]
            d[k] = t
            let u = z[i]
            z[i] = z[k]
            z[k] = u
        }
        i += 1usize
    }
    ret true
}

fn solve(a: *mem.Arena, n: usize, av: []const f64, bv: []const f64, nodes: []f64, z: []f64) -> bool {
    var i = 0usize
    while i < n {
        nodes[i] = av[i]
        z[i] = 0.0f64
        i += 1usize
    }
    z[0usize] = 1.0f64
    let (e, er) = mem.alloc[f64](a, n)
    if er != ok { ret false }
    i = 0usize
    while i < n {
        if i + 1usize < n { e[i] = bv[i] } else { e[i] = 0.0f64 }
        i += 1usize
    }
    ret imtql(n, nodes, e, z)
}

fn gauss_quad(a: *mem.Arena, n: usize, kind: u8, alpha: f64, beta: f64, nodes: []f64, w: []f64) -> bool {
    let (av, e1) = mem.alloc[f64](a, n)
    let (bv, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var lnmu = 0.0f64
    var i = 1usize
    while i <= n {
        av[i - 1usize] = 0.0f64
        bv[i - 1usize] = 0.0f64
        i += 1usize
    }
    let pi = 3.141592653589793f64
    if kind == 0u8 {
        lnmu = math.log[f64](2.0f64)
        i = 1usize
        while i < n {
            bv[i - 1usize] = f64(i) / math.sqrt[f64](4.0f64 * f64(i) * f64(i) - 1.0f64)
            i += 1usize
        }
    } else if kind == 1u8 || kind == 2u8 {
        if kind == 1u8 { lnmu = math.log[f64](pi) } else { lnmu = math.log[f64](pi / 2.0f64) }
        i = 1usize
        while i < n {
            bv[i - 1usize] = 0.5f64
            i += 1usize
        }
        if kind == 1u8 && n > 1usize { bv[0usize] = math.sqrt[f64](0.5f64) }
    } else if kind == 3u8 {
        lnmu = math.log[f64](pi) / 2.0f64
        i = 1usize
        while i < n {
            bv[i - 1usize] = math.sqrt[f64](f64(i) / 2.0f64)
            i += 1usize
        }
    } else if kind == 4u8 {
        let ab = alpha + beta
        lnmu = (ab + 1.0f64) * math.log[f64](2.0f64) + nm.lgammafn(alpha + 1.0f64) + nm.lgammafn(beta + 1.0f64) - nm.lgammafn(ab + 2.0f64)
        av[0usize] = (beta - alpha) / (ab + 2.0f64)
        i = 2usize
        while i <= n {
            let abi = ab + 2.0f64 * f64(i)
            av[i - 1usize] = (beta * beta - alpha * alpha) / (abi - 2.0f64) / abi
            i += 1usize
        }
        if n > 1usize { bv[0usize] = math.sqrt[f64](4.0f64 * (alpha + 1.0f64) * (beta + 1.0f64) / ((ab + 2.0f64) * (ab + 2.0f64)) / (ab + 3.0f64)) }
        i = 2usize
        while i < n {
            let abi = ab + 2.0f64 * f64(i)
            bv[i - 1usize] = math.sqrt[f64](4.0f64 * f64(i) * (f64(i) + alpha) * (f64(i) + beta) * (f64(i) + ab) / (abi * abi - 1.0f64) / (abi * abi))
            i += 1usize
        }
    } else {
        lnmu = nm.lgammafn(alpha + 1.0f64)
        i = 1usize
        while i <= n {
            av[i - 1usize] = 2.0f64 * f64(i) - 1.0f64 + alpha
            i += 1usize
        }
        i = 1usize
        while i < n {
            bv[i - 1usize] = math.sqrt[f64](f64(i) * (f64(i) + alpha))
            i += 1usize
        }
    }
    if !solve(a, n, av, bv, nodes, z) { ret false }
    i = 0usize
    while i < n {
        w[i] = math.exp[f64](lnmu + 2.0f64 * math.log[f64](math.abs[f64](z[i])))
        i += 1usize
    }
    ret true
}

fn gauss_quad_prob(a: *mem.Arena, n: usize, dist: u8, l: f64, u: f64, mu: f64, sigma: f64, alpha: f64, beta: f64, nodes: []f64, w: []f64) -> bool {
    if n == 1usize {
        w[0usize] = 1.0f64
        if dist == 0u8 {
            nodes[0usize] = (l + u) / 2.0f64
        } else if dist == 3u8 {
            nodes[0usize] = mu
        } else if dist == 5u8 {
            nodes[0usize] = alpha * beta
        } else if dist == 1u8 || dist == 2u8 {
            nodes[0usize] = 0.5f64
        } else {
            nodes[0usize] = alpha / (alpha + beta)
        }
        ret true
    }
    var d = dist
    if d == 4u8 && alpha == 0.5f64 && beta == 0.5f64 { d = 1u8 }
    if d == 4u8 && alpha == 1.5f64 && beta == 1.5f64 { d = 2u8 }
    let (av, e1) = mem.alloc[f64](a, n)
    let (bv, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var i = 1usize
    while i <= n {
        av[i - 1usize] = 0.0f64
        bv[i - 1usize] = 0.0f64
        i += 1usize
    }
    if d == 0u8 {
        i = 1usize
        while i < n {
            bv[i - 1usize] = f64(i) / math.sqrt[f64](4.0f64 * f64(i) * f64(i) - 1.0f64)
            i += 1usize
        }
    } else if d == 1u8 || d == 2u8 {
        i = 1usize
        while i < n {
            bv[i - 1usize] = 0.5f64
            i += 1usize
        }
        if d == 1u8 { bv[0usize] = math.sqrt[f64](0.5f64) }
    } else if d == 3u8 {
        i = 1usize
        while i < n {
            bv[i - 1usize] = math.sqrt[f64](f64(i) / 2.0f64)
            i += 1usize
        }
    } else if d == 4u8 {
        let ab = alpha + beta
        av[0usize] = (alpha - beta) / ab
        i = 2usize
        while i <= n {
            let abi = ab - 2.0f64 + 2.0f64 * f64(i)
            av[i - 1usize] = ((alpha - 1.0f64) * (alpha - 1.0f64) - (beta - 1.0f64) * (beta - 1.0f64)) / (abi - 2.0f64) / abi
            i += 1usize
        }
        bv[0usize] = math.sqrt[f64](4.0f64 * alpha * beta / (ab * ab) / (ab + 1.0f64))
        i = 2usize
        while i < n {
            let abi = ab - 2.0f64 + 2.0f64 * f64(i)
            bv[i - 1usize] = math.sqrt[f64](4.0f64 * f64(i) * (f64(i) + alpha - 1.0f64) * (f64(i) + beta - 1.0f64) * (f64(i) + ab - 2.0f64) / (abi * abi - 1.0f64) / (abi * abi))
            i += 1usize
        }
    } else {
        i = 1usize
        while i <= n {
            av[i - 1usize] = 2.0f64 * f64(i) + alpha - 2.0f64
            i += 1usize
        }
        i = 1usize
        while i < n {
            bv[i - 1usize] = math.sqrt[f64](f64(i) * (f64(i) + alpha - 1.0f64))
            i += 1usize
        }
    }
    if !solve(a, n, av, bv, nodes, z) { ret false }
    i = 0usize
    while i < n {
        w[i] = z[i] * z[i]
        if d == 0u8 {
            nodes[i] = l + (u - l) * (nodes[i] + 1.0f64) / 2.0f64
        } else if d == 1u8 || d == 2u8 || d == 4u8 {
            nodes[i] = (nodes[i] + 1.0f64) / 2.0f64
        } else if d == 3u8 {
            nodes[i] = mu + math.sqrt[f64](2.0f64) * sigma * nodes[i]
        } else {
            nodes[i] = beta * nodes[i]
        }
        i += 1usize
    }
    ret true
}

// ---- the inverse Gaussian distribution of statmod (regular parameters: finite positive mean and dispersion) ----

// dinvgauss(x, mean, dispersion, log = FALSE)
fn dinvgauss(x0: f64, mean: f64, disp0: f64, lg: bool) -> f64 {
    let x = x0 / mean
    let disp = disp0 * mean
    let d = (0.0f64 - math.log[f64](disp) - math.log[f64](2.0f64 * 3.141592653589793f64) - 3.0f64 * math.log[f64](x) - (x - 1.0f64) * (x - 1.0f64) / disp / x) / 2.0f64 - math.log[f64](mean)
    if lg { ret d }
    ret math.exp[f64](d)
}

// pinvgauss(q, mean, dispersion, lower.tail, log.p): the package's log-scale formula, with its large-q upper-tail asymptote
fn pinvgauss(q0: f64, mean: f64, disp0: f64, lower: bool, lg: bool) -> f64 {
    let q = q0 / mean
    let dispersion = disp0 * mean
    let pq = math.sqrt[f64](dispersion * q)
    let a = mdist.pnorm((q - 1.0f64) / pq, 0.0f64, 1.0f64, lower, true)
    var b = 2.0f64 / dispersion + mdist.pnorm(0.0f64 - (q + 1.0f64) / pq, 0.0f64, 1.0f64, true, true)
    if lower { b = math.exp[f64](b - a) } else { b = 0.0f64 - math.exp[f64](b - a) }
    var logp = a + mdist.log1p(b)
    if !lower && q > 1.0e6f64 && q / 2.0f64 / dispersion > 5.0e5f64 {
        logp = 1.0f64 / dispersion - 0.5f64 * math.log[f64](3.141592653589793f64) - math.log[f64](2.0f64 * dispersion) - 1.5f64 * mdist.log1p(q / 2.0f64 / dispersion) - q / 2.0f64 / dispersion
    }
    if lg { ret logp }
    ret math.exp[f64](logp)
}

// rinvgauss(n, mean, dispersion) after set.seed: n standard normals, then n uniforms (the two stages are vectorised in R, so all the normals come first)
fn rinvgauss(a: *mem.Arena, n: usize, mean: f64, disp: f64, seed: i64, out: []f64) -> err {
    let (ys, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var i = 0usize
    while i < n {
        let z = rng.norm(&rg)
        ys[i] = z * z
        i += 1usize
    }
    var anybig = false
    i = 0usize
    while i < n {
        if ys[i] * disp * mean > 5.0e5f64 { anybig = true }
        i += 1usize
    }
    i = 0usize
    while i < n {
        let yphi = ys[i] * disp * mean
        var x1 = 0.0f64
        if anybig {
            if yphi > 5.0e5f64 { x1 = 1.0f64 / yphi } else { x1 = 1.0f64 + yphi / 2.0f64 * (1.0f64 - math.sqrt[f64](1.0f64 + 4.0f64 / yphi)) }
        } else {
            x1 = 1.0f64 + yphi / 2.0f64 * (1.0f64 - math.sqrt[f64](1.0f64 + 4.0f64 / yphi))
        }
        let u = rng.unif(&rg)
        if u < 1.0f64 / (1.0f64 + x1) { out[i] = mean * x1 } else { out[i] = mean * (1.0f64 / x1) }
        i += 1usize
    }
    ret ok
}

// ---- statmod::permp: the permutation p-value that counts the observed permutation (Phipson and Smyth 2010) ----

// choose(n, k) for integers, as R computes it: the running product for k under 30 (rounded), else the rounded exponential of the log
fn choose_r(n: f64, k0: f64) -> f64 {
    var k = k0
    if k > n - k { k = n - k }
    if k < 0.5f64 { ret 1.0f64 }
    if k < 30.0f64 {
        var r = n
        var j = 2.0f64
        while j <= k {
            r = r * ((n - j + 1.0f64) / j)
            j += 1.0f64
        }
        ret math.round[f64](r)
    }
    ret math.round[f64](math.exp[f64](nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64)))
}

// permp(x, nperm, n1, n2, total.nperm, method, twosided) for one x: method 0 auto (exact up to 10000 possible permutations), 1 exact, 2 approximate; total0 <= 0 means NULL
fn permp(a: *mem.Arena, x: f64, nperm: f64, n1: f64, n2: f64, total0: f64, method0: usize, twosided: bool) -> f64 {
    var total = total0
    if total <= 0.0f64 {
        total = choose_r(n1 + n2, n1)
        if n1 == n2 && twosided { total = total / 2.0f64 }
    }
    var method = method0
    if method == 0usize {
        if total > 10000.0f64 { method = 2usize } else { method = 1usize }
    }
    if method == 1usize {
        var s = 0.0f64
        var i = 1.0f64
        while i <= total {
            s += nb.pbinom(x, nperm, i / total, true, false)
            i += 1.0f64
        }
        ret s / total
    }
    let (nodes, e1) = mem.alloc[f64](a, 128usize)
    let (w, e2) = mem.alloc[f64](a, 128usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    if !gauss_quad_prob(a, 128usize, 0u8, 0.0f64, 0.5f64 / total, 0.0f64, 1.0f64, 1.0f64, 1.0f64, nodes, w) { ret 0.0f64 / 0.0f64 }
    var cs = 0.0f64
    var k = 0usize
    while k < 128usize {
        cs += w[k] * nb.pbinom(x, nperm, nodes[k], true, false)
        k += 1usize
    }
    let integral = 0.5f64 / total * cs
    ret (x + 1.0f64) / (nperm + 1.0f64) - integral
}

// statmod::power.fisher.test (two-sided) after set.seed: nsim binomial counts for each group (all of the first group's, then the second's), Fisher's exact test on each 2 by 2 table, the share of p values under alpha
fn power_fisher_test(a: *mem.Arena, p1: f64, p2: f64, n1: f64, n2: f64, alpha: f64, nsim: usize, seed: i64) -> f64 {
    ret power_fisher_alt(a, p1, p2, n1, n2, alpha, nsim, seed, 0usize)
}

// the same with alternative = "two.sided" (0), "greater" (1) or "less" (2): the one-sided p values are the hypergeometric tails of the first cell
fn power_fisher_alt(a: *mem.Arena, p1: f64, p2: f64, n1: f64, n2: f64, alpha: f64, nsim: usize, seed: i64, alt: usize) -> f64 {
    let (y1, e1) = mem.alloc[f64](a, nsim)
    let (y2, e2) = mem.alloc[f64](a, nsim)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var i = 0usize
    while i < nsim {
        y1[i] = rd.rbinom(&rg, n1, p1)
        i += 1usize
    }
    i = 0usize
    while i < nsim {
        y2[i] = rd.rbinom(&rg, n2, p2)
        i += 1usize
    }
    var hit = 0.0f64
    i = 0usize
    while i < nsim {
        var pv = 0.0f64
        if alt == 0usize {
            pv = tst.fisher_exact(u64(y1[i]), u64(n1 - y1[i]), u64(y2[i]), u64(n2 - y2[i])).p_value
        } else if alt == 1usize {
            pv = nb.phyper(y1[i] - 1.0f64, n1, n2, y1[i] + y2[i], false, false)
        } else {
            pv = nb.phyper(y1[i], n1, n2, y1[i] + y2[i], true, false)
        }
        if pv < alpha { hit += 1.0f64 }
        i += 1usize
    }
    ret hit / f64(nsim)
}

// qinvgauss(p, mean, dispersion, lower.tail, log.p) of statmod: the start from the mode or a tail approximation, then the package's Newton steps on the log scale until the step is under 1e-14 relative
fn qinvgauss(p0: f64, mean: f64, disp: f64, lower: bool, lg: bool) -> f64 {
    var logp = p0
    if !lg {
        if p0 < 0.0f64 || p0 > 1.0f64 { ret 0.0f64 / 0.0f64 }
        logp = math.log[f64](p0)
    }
    let p = math.exp[f64](logp)
    let inf = 1.0f64 / 0.0f64
    var left = logp == 0.0f64 - inf
    var right = logp == 0.0f64
    if !lower {
        left = logp == 0.0f64
        right = logp == 0.0f64 - inf
    }
    if left { ret 0.0f64 }
    if right { ret inf }
    let phi = disp * mean
    if phi < 1.0e-8f64 { ret nm.qgamma(logp, 1.0f64 / phi, phi * mean, lower, true) }
    let kappa = 1.5f64 * phi
    var x = math.sqrt[f64](1.0f64 + kappa * kappa) - kappa
    if kappa > 1000.0f64 {
        let k1 = 1.0f64 / 2.0f64 / kappa
        x = k1 * (1.0f64 - k1 * k1)
    }
    var smallleft = logp < 0.0f64 - 11.51f64
    var smallright = logp > 0.0f64 - 1.0e-5f64
    if !lower {
        smallleft = logp > 0.0f64 - 1.0e-5f64
        smallright = logp < 0.0f64 - 11.51f64
    }
    if smallleft {
        let qn = mdist.qnorm(logp, 0.0f64, 1.0f64, lower, true)
        x = 1.0f64 / phi / (qn * qn)
    }
    if smallright {
        let alpha = 1.0f64 / phi
        let qg = nm.qgamma(logp, alpha, 1.0f64 / alpha, lower, true)
        if qg > x { x = qg }
    }
    var dx = invgauss_step(x, p, logp, phi, lower)
    if dx != dx { dx = 0.0f64 }
    var sdx = 0.0f64
    if dx > 0.0f64 { sdx = 1.0f64 } else if dx < 0.0f64 { sdx = 0.0f64 - 1.0f64 }
    if lower { x = x + dx } else { x = x - dx }
    var more = math.abs[f64](dx) > 1.0e-14f64
    var iter = 0usize
    while more {
        iter += 1usize
        if iter > 200usize { break }
        dx = invgauss_step(x, p, logp, phi, lower)
        if dx != dx || dx * sdx < 0.0f64 { dx = 0.0f64 }
        if lower { x = x + dx } else { x = x - dx }
        var den = x
        if den < 1.0f64 { den = 1.0f64 }
        more = math.abs[f64](dx) / den > 1.0e-14f64
    }
    ret x * mean
}

fn invgauss_step(x: f64, p: f64, logp: f64, phi: f64, lower: bool) -> f64 {
    let logf = pinvgauss(x, 1.0f64, phi, lower, true)
    let dlogp = logp - logf
    var dp = 0.0f64
    if math.abs[f64](dlogp) < 1.0e-5f64 {
        dp = math.exp[f64](logp + mdist.log1p(0.0f64 - dlogp / 2.0f64)) * dlogp
    } else {
        dp = p - math.exp[f64](logf)
    }
    ret dp / dinvgauss(x, 1.0f64, phi, false)
}

// ---- qresiduals (Dunn and Smyth) of statmod for the fitted values mu of a glm: the randomised ones draw runif(min = a, max = b) in observation order ----

// family 0 binomial (y the proportions, w the prior weights n), 1 Poisson, 2 gamma (dispersion given), 3 inverse Gaussian (dispersion given), 4 negative binomial (theta in disp)
fn qresiduals(r: *rng.Rng, family: usize, y: []const f64, mu: []const f64, w: []const f64, disp: f64, out: []f64) {
    let n = y.len
    var i = 0usize
    while i < n {
        if family == 0usize {
            let cnt = w[i] * y[i]
            let lo = nb.pbinom(cnt - 1.0f64, w[i], mu[i], true, false)
            let hi = nb.pbinom(cnt, w[i], mu[i], true, false)
            let u = lo + (hi - lo) * rng.unif(r)
            out[i] = mdist.qnorm(u, 0.0f64, 1.0f64, true, false)
        } else if family == 1usize {
            let lo = nm.ppois(y[i] - 1.0f64, mu[i], true, false)
            let hi = nm.ppois(y[i], mu[i], true, false)
            let u = lo + (hi - lo) * rng.unif(r)
            out[i] = mdist.qnorm(u, 0.0f64, 1.0f64, true, false)
        } else if family == 2usize {
            let lp = nm.pgamma(w[i] * y[i] / mu[i] / disp, w[i] / disp, 1.0f64, true, true)
            out[i] = mdist.qnorm(lp, 0.0f64, 1.0f64, true, true)
        } else if family == 3usize {
            if y[i] > mu[i] {
                out[i] = mdist.qnorm(pinvgauss(y[i], mu[i], disp, false, true), 0.0f64, 1.0f64, false, true)
            } else if y[i] < mu[i] {
                out[i] = mdist.qnorm(pinvgauss(y[i], mu[i], disp, true, true), 0.0f64, 1.0f64, true, true)
            } else {
                out[i] = y[i]
            }
        } else {
            let p = disp / (mu[i] + disp)
            var lo = 0.0f64
            var yy = y[i]
            if yy < 1.0f64 { yy = 1.0f64 }
            if y[i] > 0.0f64 { lo = nb.pbeta(p, disp, yy, true, false) }
            let hi = nb.pbeta(p, disp, y[i] + 1.0f64, true, false)
            let u = lo + (hi - lo) * rng.unif(r)
            out[i] = mdist.qnorm(u, 0.0f64, 1.0f64, true, false)
        }
        i += 1usize
    }
}

// statmod::tweedie(var.power = p, link.power = lambda): the unit deviance 2 wt (y theta - kappa) with y1 = y + 0.1 [y = 0], theta = log(y1 / mu) for p = 1 or (y1^(1 - p) - mu^(1 - p)) / (1 - p),
// kappa = log(y1 / mu) for p = 2 or (y^(2 - p) - mu^(2 - p)) / (2 - p); the variance mu^p; the power link mu^lambda (log for lambda = 0), its inverse and the derivative of the inverse
fn tweedie_dev_resid(y: f64, mu: f64, wt: f64, p: f64) -> f64 {
    var y1 = y
    if y == 0.0f64 { y1 = y + 0.1f64 }
    var theta = 0.0f64
    if p == 1.0f64 { theta = math.log[f64](y1 / mu) } else { theta = (math.pow[f64](y1, 1.0f64 - p) - math.pow[f64](mu, 1.0f64 - p)) / (1.0f64 - p) }
    var kappa = 0.0f64
    if p == 2.0f64 { kappa = math.log[f64](y1 / mu) } else { kappa = (math.pow[f64](y, 2.0f64 - p) - math.pow[f64](mu, 2.0f64 - p)) / (2.0f64 - p) }
    ret 2.0f64 * wt * (y * theta - kappa)
}

fn tweedie_variance(mu: f64, p: f64) -> f64 { ret math.pow[f64](mu, p) }

fn tweedie_linkfun(mu: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.log[f64](mu) }
    ret math.pow[f64](mu, lambda)
}

fn tweedie_linkinv(eta: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 {
        var v = math.exp[f64](eta)
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    ret math.pow[f64](eta, 1.0f64 / lambda)
}

fn tweedie_mu_eta(eta: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 {
        var v = math.exp[f64](eta)
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    ret (1.0f64 / lambda) * math.pow[f64](eta, 1.0f64 / lambda - 1.0f64)
}

// tweedie::dtweedie for 1 < p < 2 (the compound Poisson-gamma form): with lambda = mu^(2 - p) / (phi (2 - p)), a = (2 - p) / (p - 1) and tau = phi (p - 1) mu^(p - 1), the density is
// sum_j Poisson(j; lambda) Gamma(y; j a, scale tau) for y > 0 and exp(-lambda) at 0; kind 0 the density, 1 the distribution function (the atom at 0 plus the gamma distribution functions)
fn tweedie_pg(y: f64, p: f64, mu: f64, phi: f64, kind: usize) -> f64 {
    let lam = math.pow[f64](mu, 2.0f64 - p) / (phi * (2.0f64 - p))
    let a = (2.0f64 - p) / (p - 1.0f64)
    let tau = phi * (p - 1.0f64) * math.pow[f64](mu, p - 1.0f64)
    if y == 0.0f64 { ret math.exp[f64](0.0f64 - lam) }
    var lo = 1.0f64
    let lj = lam - 40.0f64 * math.sqrt[f64](lam) - 10.0f64
    if lj > lo { lo = math.floor[f64](lj) }
    let hj = lam + 40.0f64 * math.sqrt[f64](lam) + 40.0f64
    var s = 0.0f64
    var j = lo
    while j <= hj {
        let lw = 0.0f64 - lam + j * math.log[f64](lam) - nm.lgammafn(j + 1.0f64)
        if kind == 0usize {
            s += math.exp[f64](lw + nm.dgamma(y, j * a, tau, true))
        } else {
            s += math.exp[f64](lw) * nm.pgamma(y, j * a, tau, true, false)
        }
        j += 1.0f64
    }
    if kind == 1usize { s += math.exp[f64](0.0f64 - lam) }
    ret s
}

// tweedie::rtweedie for 1 < p < 2: all n Poisson counts N ~ Poisson(lambda) first, then for each the gamma draw of shape N (2 - p) / (p - 1) and scale phi (p - 1) mu^(p - 1), zero (without a draw) when N = 0
fn rtweedie_pg(r: *rng.Rng, n: usize, p: f64, mu: f64, phi: f64, out: []f64) -> err {
    let lam = math.pow[f64](mu, 2.0f64 - p) / (phi * (2.0f64 - p))
    let a = (2.0f64 - p) / (p - 1.0f64)
    let gam = phi * (p - 1.0f64) * math.pow[f64](mu, p - 1.0f64)
    var i = 0usize
    while i < n {
        out[i] = rd.rpois(r, lam)
        i += 1usize
    }
    i = 0usize
    while i < n {
        let k = out[i]
        if k > 0.0f64 { out[i] = rd.rgamma(r, k * a, gam) } else { out[i] = 0.0f64 }
        i += 1usize
    }
    ret ok
}
