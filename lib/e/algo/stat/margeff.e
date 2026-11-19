// R marginaleffects for a generalised linear model fitted with the identity (gaussian), logit (binomial) or log (Poisson) link, from the fitted coefficients and their covariance: `avg_predictions` (the mean fitted response), `avg_slopes` (the average marginal effect of a variable,
// mean of beta_j mu'(eta)) and `avg_comparisons` of a 0 / 1 variable (the mean of mu(eta with the variable at 1) - mu(eta with it at 0)), each with the delta-method standard error sqrt(J V J') from the analytic Jacobian
// (marginaleffects differentiates numerically, so its estimates carry a difference error of about 1e-9).
//
// Not here: other families and links, comparisons for factors and other contrasts, predictions at a grid or for a new data frame, conditional effects, hypotheses.

use e.math
use e.math.dist as dist
use e.mem

// the inverse link and its first two derivatives at eta: link 0 identity, 1 logit, 2 log, 3 probit, 4 cloglog, 5 inverse, 6 sqrt
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
    } else if link == 3usize {
        let d = dist.dnorm(eta, 0.0f64, 1.0f64, false)
        out[0usize] = dist.pnorm(eta, 0.0f64, 1.0f64, true, false)
        out[1usize] = d
        out[2usize] = 0.0f64 - eta * d
    } else if link == 4usize {
        let ee = math.exp[f64](eta)
        let d = ee * math.exp[f64](0.0f64 - ee)
        out[0usize] = 1.0f64 - math.exp[f64](0.0f64 - ee)
        out[1usize] = d
        out[2usize] = d * (1.0f64 - ee)
    } else if link == 5usize {
        out[0usize] = 1.0f64 / eta
        out[1usize] = 0.0f64 - 1.0f64 / (eta * eta)
        out[2usize] = 2.0f64 / (eta * eta * eta)
    } else if link == 6usize {
        out[0usize] = eta * eta
        out[1usize] = 2.0f64 * eta
        out[2usize] = 2.0f64
    } else {
        let m = math.exp[f64](eta)
        out[0usize] = m
        out[1usize] = m
        out[2usize] = m
    }
}

// x is n by p column-major (an intercept column included), beta and vcov (p by p, column-major) from the fit. kind 0: the slope of column j, or the average prediction when j >= p; kind 1: the average comparison of the 0 / 1 column j; kind 2: the average comparison of column j raised by one unit.
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
        } else if kind == 2usize {
            // a unit increase of column j (avg_comparisons(variables = list(v = 1)))
            mu_d(link, eta + beta[j], m1)
            est += (m1[0usize] - m0[0usize]) / nf
            k = 0usize
            while k < p {
                var x1 = x[k * n + i]
                if k == j { x1 += 1.0f64 }
                jac[k] += (m1[1usize] * x1 - m0[1usize] * x[k * n + i]) / nf
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

// predictions(model, newdata) of a glm for one new row x (p values, intercept first): the response mu(eta) and its delta-method standard error mu'(eta) sqrt(x' V x); beta and vcov (p by p, column-major) from the fit; out = (estimate, standard error)
fn glm_pred(link: usize, x: []const f64, beta: []const f64, vcov: []const f64, p: usize, out: []f64) {
    var eta = 0.0f64
    var i = 0usize
    while i < p {
        eta += x[i] * beta[i]
        i += 1usize
    }
    var d: [3]f64 = zero
    mu_d(link, eta, d[0usize..3usize])
    var q = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            q += x[i] * vcov[j * p + i] * x[j]
            j += 1usize
        }
        i += 1usize
    }
    out[0usize] = d[0usize]
    out[1usize] = math.abs[f64](d[1usize]) * math.sqrt[f64](q)
}

// hypotheses(model, "r'b = q") of a glm: the estimate r'b - q, its standard error sqrt(r' V r), the z statistic and the two-sided normal p-value; beta and vcov (p by p, column-major) from the fit, out = (estimate, se, z, p)
fn lin_hypothesis(beta: []const f64, vcov: []const f64, r: []const f64, q: f64, p: usize, out: []f64) {
    var e = 0.0f64 - q
    var v = 0.0f64
    var i = 0usize
    while i < p {
        e += r[i] * beta[i]
        var j = 0usize
        while j < p {
            v += r[i] * vcov[j * p + i] * r[j]
            j += 1usize
        }
        i += 1usize
    }
    let se = math.sqrt[f64](v)
    out[0usize] = e
    out[1usize] = se
    out[2usize] = e / se
    out[3usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](e / se), 0.0f64, 1.0f64, true, false)
}
