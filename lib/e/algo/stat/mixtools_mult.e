// R mixtools multmixEM: the EM fit of a mixture of multinomials (counts n by p, row-major), value for value:
// multmix.init draws theta = matrix(runif(p * k), k, p) down the columns and then lambda, the C routine multinompost gives the
// posteriors, and the reported loglik is the log-likelihood before the last M-step, as the package's own all.loglik ends.

use e.algo.rand.r as rg
use e.algo.stat.mixtools as mt
use e.math
use e.math.nmath as nmath
use e.mem

type Mult = struct { lambda: []f64, theta: []f64, post: []f64, ll: []f64, loglik: f64, iter: usize, restarts: usize, k: usize }

// multmix.init: theta is k by p row-major. Returns k.
fn multmix_init(g: *rg.Rng, p: usize, lambda0: []const f64, theta0: []const f64, k0: usize, lambda: []f64, theta: []f64) -> usize {
    var k = k0
    var i = 0usize
    if theta0.len == 0usize {
        var c = 0usize
        while c < p {
            var r = 0usize
            while r < k {
                theta[r * p + c] = rg.runif(g, 0.0f64, 1.0f64)
                r += 1usize
            }
            c += 1usize
        }
        var r2 = 0usize
        while r2 < k {
            var s = 0.0f64
            c = 0usize
            while c < p {
                s += theta[r2 * p + c]
                c += 1usize
            }
            c = 0usize
            while c < p {
                theta[r2 * p + c] = theta[r2 * p + c] / s
                c += 1usize
            }
            r2 += 1usize
        }
    } else {
        k = theta0.len / p
        i = 0usize
        while i < theta0.len {
            theta[i] = theta0[i]
            i += 1usize
        }
    }
    if lambda0.len == 0usize {
        var s = 0.0f64
        i = 0usize
        while i < k {
            lambda[i] = rg.runif(g, 0.0f64, 1.0f64)
            s += lambda[i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            lambda[i] = lambda[i] / s
            i += 1usize
        }
    } else {
        k = lambda0.len
        i = 0usize
        while i < k {
            lambda[i] = lambda0[i]
            i += 1usize
        }
    }
    ret k
}

// C multinompost over the n by m row-major log(lambda * density) matrix; loglik starts at the constant
fn multinompost(lcd: []const f64, n: usize, m: usize, post: []f64, llconst: f64) -> f64 {
    var loglik = llconst
    var i = 0usize
    while i < n {
        var mx = lcd[i * m]
        var maxj = 0usize
        var j = 1usize
        while j < m {
            if lcd[i * m + j] > mx {
                mx = lcd[i * m + j]
                maxj = j
            }
            j += 1usize
        }
        var sum = 1.0f64
        j = 0usize
        while j < m {
            if j != maxj {
                post[i * m + j] = math.exp[f64](lcd[i * m + j] - mx)
                sum += post[i * m + j]
            }
            j += 1usize
        }
        loglik += math.log[f64](sum) + mx
        j = 0usize
        while j < m {
            if j == maxj { post[i * m + j] = 1.0f64 / sum } else { post[i * m + j] = post[i * m + j] / sum }
            j += 1usize
        }
        i += 1usize
    }
    ret loglik
}

fn mult_estep(y: []const f64, n: usize, p: usize, k: usize, lambda: []const f64, theta: []const f64, lcd: []f64, post: []f64, llconst: f64) -> f64 {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var c = 0usize
            while c < p {
                s += math.log[f64](theta[j * p + c]) * y[i * p + c]
                c += 1usize
            }
            lcd[i * k + j] = math.log[f64](lambda[j]) + s
            j += 1usize
        }
        i += 1usize
    }
    ret multinompost(lcd, n, k, post, llconst)
}

fn norm_theta(theta: []f64, k: usize, p: usize) {
    var r = 0usize
    while r < k {
        var sacc = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
        var c = 0usize
        while c < p {
            mt.acc_add(&sacc, theta[r * p + c])
            c += 1usize
        }
        let s = mt.acc_val(sacc)
        c = 0usize
        while c < p {
            theta[r * p + c] = theta[r * p + c] / s
            if theta[r * p + c] < 1.0e-100f64 { theta[r * p + c] = 1.0e-100f64 }
            c += 1usize
        }
        r += 1usize
    }
}

// multmixEM(y, lambda, theta, k, maxit, epsilon): y is n by p row-major counts; an empty lambda0 or theta0 is NULL
fn mult_mix_em(a: *mem.Arena, g: *rg.Rng, y: []const f64, n: usize, p: usize, lambda0: []const f64, theta0: []const f64, k0: usize, maxit: usize, epsilon: f64) -> (Mult, err) {
    var empty: Mult = zero
    // sum(lgamma(r + 1)) - sum(lgamma(y + 1)), each sum in long double
    var s1 = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var s2 = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var c = 0usize
        while c < p {
            rs += y[i * p + c]
            mt.acc_add(&s2, nmath.lgammafn(y[i * p + c] + 1.0f64))
            c += 1usize
        }
        mt.acc_add(&s1, nmath.lgammafn(rs + 1.0f64))
        i += 1usize
    }
    let llconst = mt.acc_val(s1) - mt.acc_val(s2)
    var k = k0
    if theta0.len > 0usize { k = theta0.len / p }
    if lambda0.len > 0usize { k = lambda0.len }
    let lambda = mt.buf(a, k)
    let theta = mt.buf(a, k * p)
    k = multmix_init(g, p, lambda0, theta0, k, lambda, theta)
    let post = mt.buf(a, n * k)
    let lcd = mt.buf(a, n * k)
    let ll = mt.buf(a, maxit + 2usize)
    var restarts = 0usize
    var must = false
    while restarts < 50usize {
        var nll = 0usize
        var iter = 0usize
        var diff = epsilon + 1.0f64
        norm_theta(theta, k, p)
        var newll = mult_estep(y, n, p, k, lambda, theta, lcd, post, llconst)
        var allzero = false
        var j = 0usize
        while j < k {
            var nz = 0usize
            i = 0usize
            while i < n {
                if post[i * k + j] == 0.0f64 { nz += 1usize }
                i += 1usize
            }
            if nz == n { allzero = true }
            j += 1usize
        }
        if allzero {
            diff = epsilon
            must = true
        }
        while iter < maxit && diff > epsilon {
            iter += 1usize
            let oldll = newll
            ll[nll] = oldll
            nll += 1usize
            var r = 0usize
            while r < k {
                var c = 0usize
                while c < p {
                    var t = 0.0f64
                    i = 0usize
                    while i < n {
                        t += post[i * k + r] * y[i * p + c]
                        i += 1usize
                    }
                    theta[r * p + c] = t
                    c += 1usize
                }
                r += 1usize
            }
            norm_theta(theta, k, p)
            mt.col_means(post, n, k, lambda)
            newll = mult_estep(y, n, p, k, lambda, theta, lcd, post, llconst)
            diff = newll - oldll
            if diff < 0.0f64 || newll != newll || newll - newll != 0.0f64 {
                must = true
                break
            }
        }
        if must {
            must = false
            restarts += 1usize
            k = multmix_init(g, p, lambda0[0usize..0usize], theta0[0usize..0usize], k, lambda, theta)
        } else {
            if p > 1usize {
                var r = 0usize
                while r < k {
                    var s = 0.0f64
                    var c = 0usize
                    while c + 1usize < p {
                        s += theta[r * p + c]
                        c += 1usize
                    }
                    theta[r * p + p - 1usize] = 1.0f64 - s
                    r += 1usize
                }
            }
            ret (Mult { lambda: lambda, theta: theta, post: post, ll: ll[0usize..nll], loglik: ll[nll - 1usize], iter: iter, restarts: restarts, k: k }, ok)
        }
    }
    ret (empty, mt.TooManyTries)
}
