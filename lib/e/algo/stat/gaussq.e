// R statmod::gauss.quad and gauss.quad.prob: the nodes and weights of Gauss quadrature from the Jacobi matrix of the
// orthogonal polynomials, by the implicit QL method (as gausq2) tracking only the first row of the eigenvectors.
// gauss.quad kinds: 0 Legendre, 1 Chebyshev first kind, 2 Chebyshev second kind, 3 Hermite, 4 Jacobi (alpha, beta),
// 5 Laguerre (alpha). gauss.quad.prob dists: 0 uniform(l, u), 1 beta1, 2 beta2, 3 normal(mu, sigma),
// 4 beta(alpha, beta), 5 gamma(alpha, beta).
//
// Not here: the inverse Gaussian and Tweedie distributions of statmod, qresiduals, power.fisher.test.

use e.math
use e.math.nmath as nm
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
