// R marginaleffects for a generalised linear model fitted with the identity (gaussian), logit (binomial) or log (Poisson) link, from the fitted coefficients and their covariance: `avg_predictions` (the mean fitted response), `avg_slopes` (the average marginal effect of a variable,
// mean of beta_j mu'(eta)) and `avg_comparisons` of a 0 / 1 variable (the mean of mu(eta with the variable at 1) - mu(eta with it at 0)), each with the delta-method standard error sqrt(J V J') from the analytic Jacobian
// (marginaleffects differentiates numerically, so its estimates carry a difference error of about 1e-9).
//
// Not here: other families and links, comparisons for factors and other contrasts, predictions at a grid or for a new data frame, conditional effects, hypotheses.

use e.math
use e.mem

// the inverse link and its first two derivatives at eta: link 0 identity, 1 logit, 2 log
fn mu_d(link: usize, eta: f64, out: []f64) {
    if link == 0usize {
        out[0usize] = eta
        out[1usize] = 1.0f64
        out[2usize] = 0.0f64
    } else if link == 1usize {
        let p = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        out[0usize] = p
        out[1usize] = p * (1.0f64 - p)
        out[2usize] = p * (1.0f64 - p) * (1.0f64 - 2.0f64 * p)
    } else {
        let m = math.exp[f64](eta)
        out[0usize] = m
        out[1usize] = m
        out[2usize] = m
    }
}

// x is n by p column-major (an intercept column included), beta and vcov (p by p, column-major) from the fit. kind 0: the slope of column j, or the average prediction when j >= p; kind 1: the average comparison of the 0 / 1 column j.
// out = (estimate, standard error)
fn glm_avg(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, out: []f64) {
    let nf = f64(n)
    let (jac, je) = mem.alloc[f64](a, p)
    let (m0, me) = mem.alloc[f64](a, 3usize)
    let (m1, me1) = mem.alloc[f64](a, 3usize)
    if je != ok || me != ok || me1 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    var est = 0.0f64
    var k = 0usize
    while k < p {
        jac[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        k = 0usize
        while k < p {
            eta += x[k * n + i] * beta[k]
            k += 1usize
        }
        mu_d(link, eta, m0)
        if kind == 1usize {
            // the linear predictor with column j at 1 and at 0
            let e1 = eta + beta[j] * (1.0f64 - x[j * n + i])
            let e0 = eta - beta[j] * x[j * n + i]
            mu_d(link, e1, m1)
            mu_d(link, e0, m0)
            est += (m1[0usize] - m0[0usize]) / nf
            k = 0usize
            while k < p {
                var x1 = x[k * n + i]
                var x0 = x[k * n + i]
                if k == j {
                    x1 = 1.0f64
                    x0 = 0.0f64
                }
                jac[k] += (m1[1usize] * x1 - m0[1usize] * x0) / nf
                k += 1usize
            }
        } else if j >= p {
            est += m0[0usize] / nf
            k = 0usize
            while k < p {
                jac[k] += m0[1usize] * x[k * n + i] / nf
                k += 1usize
            }
        } else {
            est += beta[j] * m0[1usize] / nf
            k = 0usize
            while k < p {
                var d = beta[j] * m0[2usize] * x[k * n + i]
                if k == j { d += m0[1usize] }
                jac[k] += d / nf
                k += 1usize
            }
        }
        i += 1usize
    }
    var v = 0.0f64
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            v += jac[a1] * vcov[b1 * p + a1] * jac[b1]
            b1 += 1usize
        }
        a1 += 1usize
    }
    out[0usize] = est
    out[1usize] = math.sqrt[f64](v)
}
