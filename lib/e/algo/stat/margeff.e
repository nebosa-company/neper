// R marginaleffects for a generalised linear model fitted with the identity (gaussian), logit (binomial) or log (Poisson) link, from the fitted coefficients and their covariance: `avg_predictions` (the mean fitted response), `avg_slopes` (the average marginal effect of a variable,
// mean of beta_j mu'(eta)) and `avg_comparisons` of a 0 / 1 variable (the mean of mu(eta with the variable at 1) - mu(eta with it at 0)), each with the delta-method standard error sqrt(J V J') from the analytic Jacobian
// (marginaleffects differentiates numerically, so its estimates carry a difference error of about 1e-9).
//
// Not here: other families and links, comparisons for factors and other contrasts, predictions at a grid or for a new data frame, conditional effects, hypotheses.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.math.nmath as nm
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
fn glm_avg_rows(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, r0: usize, r1: usize, out: []f64) {
    let nf = f64(r1 - r0)
    let (jac, je) = mem.alloc[f64](a, p)
    let (m0, me) = mem.alloc[f64](a, 3usize)
    let (m1, me1) = mem.alloc[f64](a, 3usize)
    if je != ok || me != ok || me1 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    var h = 1.0f64
    if kind == 0usize && j < p {
        // marginaleffects steps a slope variable by 1e-4 of its range
        var lo = x[j * n]
        var hi = x[j * n]
        var r = 1usize
        while r < n {
            let v = x[j * n + r]
            if v < lo { lo = v }
            if v > hi { hi = v }
            r += 1usize
        }
        h = 1.0e-4f64 * (hi - lo)
        if h == 0.0f64 { h = 1.0e-4f64 }
    }
    var est = 0.0f64
    var k = 0usize
    while k < p {
        jac[k] = 0.0f64
        k += 1usize
    }
    var i = r0
    while i < r1 {
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
            // marginaleffects: central difference of the response with the column moved by -+ h / 2, and the analytic Jacobian of that difference
            let eh = eta + beta[j] * (h / 2.0f64)
            let el = eta - beta[j] * (h / 2.0f64)
            mu_d(link, eh, m1)
            mu_d(link, el, m0)
            est += (m1[0usize] - m0[0usize]) / h / nf
            k = 0usize
            while k < p {
                var xh = x[k * n + i]
                var xl = x[k * n + i]
                if k == j {
                    xh += h / 2.0f64
                    xl -= h / 2.0f64
                }
                jac[k] += (m1[1usize] * xh - m0[1usize] * xl) / h / nf
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
fn lin_value(beta: []const f64, r: []const f64, q: f64, p: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < p {
        s += r[i] * beta[i]
        i += 1usize
    }
    ret s - q
}

fn lin_hypothesis(beta: []const f64, vcov: []const f64, r: []const f64, q: f64, p: usize, out: []f64) {
    let e = lin_value(beta, r, q, p)
    // marginaleffects differentiates the hypothesis numerically: forward step max(|b| sqrt(eps), 1e-10) per coefficient
    var bp: [64]f64 = zero
    var jac: [64]f64 = zero
    var i = 0usize
    while i < p {
        bp[i] = beta[i]
        i += 1usize
    }
    let root_eps = math.sqrt[f64](2.220446049250313e-16f64)
    i = 0usize
    while i < p {
        var s = math.abs[f64](beta[i]) * root_eps
        if s < 1.0e-10f64 { s = 1.0e-10f64 }
        bp[i] = beta[i] + s
        jac[i] = r[i] * ((bp[i] - beta[i]) / s)
        bp[i] = beta[i]
        i += 1usize
    }
    var v = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            v += jac[i] * vcov[j * p + i] * jac[j]
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

// avg_comparisons of a 0 / 1 column j with comparison = "ratio" (kind 0: mean mu1 / mean mu0), "lnratio" (kind 1: its log) or "lift" (kind 2: the ratio less one); the standard error by the delta method on the two means; out = (estimate, standard error)
fn glm_avg_ratio_rows(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, r0: usize, r1: usize, out: []f64) {
    let nf = f64(r1 - r0)
    let (ja, e1) = mem.alloc[f64](a, p)
    let (jb, e2) = mem.alloc[f64](a, p)
    let (m1, e3) = mem.alloc[f64](a, 3usize)
    let (m0, e4) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    var k = 0usize
    while k < p {
        ja[k] = 0.0f64
        jb[k] = 0.0f64
        k += 1usize
    }
    var ma = 0.0f64
    var mb = 0.0f64
    var i = r0
    while i < r1 {
        var eta = 0.0f64
        k = 0usize
        while k < p {
            eta += x[k * n + i] * beta[k]
            k += 1usize
        }
        mu_d(link, eta + beta[j] * (1.0f64 - x[j * n + i]), m1)
        mu_d(link, eta - beta[j] * x[j * n + i], m0)
        ma += m1[0usize] / nf
        mb += m0[0usize] / nf
        k = 0usize
        while k < p {
            var x1 = x[k * n + i]
            var x0 = x[k * n + i]
            if k == j {
                x1 = 1.0f64
                x0 = 0.0f64
            }
            ja[k] += m1[1usize] * x1 / nf
            jb[k] += m0[1usize] * x0 / nf
            k += 1usize
        }
        i += 1usize
    }
    let r = ma / mb
    var est = r
    if kind == 1usize { est = math.log[f64](r) }
    if kind == 2usize { est = r - 1.0f64 }
    var v = 0.0f64
    var u = 0usize
    while u < p {
        var gu = ja[u] / mb - ma * jb[u] / (mb * mb)
        if kind == 1usize { gu = ja[u] / ma - jb[u] / mb }
        var w = 0usize
        while w < p {
            var gw = ja[w] / mb - ma * jb[w] / (mb * mb)
            if kind == 1usize { gw = ja[w] / ma - jb[w] / mb }
            v += gu * vcov[w * p + u] * gw
            w += 1usize
        }
        u += 1usize
    }
    out[0usize] = est
    out[1usize] = math.sqrt[f64](v)
}

fn glm_avg(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, out: []f64) {
    glm_avg_rows(a, link, kind, x, beta, vcov, n, p, j, 0usize, n, out)
}

fn glm_avg_ratio(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, out: []f64) {
    glm_avg_ratio_rows(a, link, kind, x, beta, vcov, n, p, j, 0usize, n, out)
}

// slopes() and comparisons() for one observation (row of x): the estimate and delta-method standard error of glm_avg with the average taken over that row alone (the slope step still comes from the whole column); glm_row_ratio gives the row's own ratio, log ratio or lift
fn glm_row(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, row: usize, out: []f64) {
    glm_avg_rows(a, link, kind, x, beta, vcov, n, p, j, row, row + 1usize, out)
}

fn glm_row_ratio(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, row: usize, out: []f64) {
    glm_avg_ratio_rows(a, link, kind, x, beta, vcov, n, p, j, row, row + 1usize, out)
}

// avg_comparisons() of any contrast: hi and lo give, per model-matrix column, the value that column takes in the "high" and "low" counterfactual (1.0e300 leaves the column as observed), which covers a factor level against another level and a continuous variable moved between two values (a dummy column set, the rest of that factor's dummies zeroed). kind 0 mean difference, 1 ratio of means, 2 its log, 3 its lift; the standard error by the delta method from the analytic Jacobian marginaleffects uses; out = (estimate, standard error)
fn glm_contrast(a: *mem.Arena, link: usize, kind: usize, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, hi: []const f64, lo: []const f64, out: []f64) {
    let nf = f64(n)
    let (ja, e1) = mem.alloc[f64](a, p)
    let (jb, e2) = mem.alloc[f64](a, p)
    let (m1, e3) = mem.alloc[f64](a, 3usize)
    let (m0, e4) = mem.alloc[f64](a, 3usize)
    let (xh, e5) = mem.alloc[f64](a, p)
    let (xl, e6) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    var k = 0usize
    while k < p {
        ja[k] = 0.0f64
        jb[k] = 0.0f64
        k += 1usize
    }
    var ma = 0.0f64
    var mb = 0.0f64
    var i = 0usize
    while i < n {
        var eh = 0.0f64
        var el = 0.0f64
        k = 0usize
        while k < p {
            xh[k] = x[k * n + i]
            xl[k] = x[k * n + i]
            if hi[k] < 1.0e299f64 { xh[k] = hi[k] }
            if lo[k] < 1.0e299f64 { xl[k] = lo[k] }
            eh += xh[k] * beta[k]
            el += xl[k] * beta[k]
            k += 1usize
        }
        mu_d(link, eh, m1)
        mu_d(link, el, m0)
        ma += m1[0usize] / nf
        mb += m0[0usize] / nf
        k = 0usize
        while k < p {
            ja[k] += m1[1usize] * xh[k] / nf
            jb[k] += m0[1usize] * xl[k] / nf
            k += 1usize
        }
        i += 1usize
    }
    var est = ma - mb
    if kind == 1usize { est = ma / mb }
    if kind == 2usize { est = math.log[f64](ma / mb) }
    if kind == 3usize { est = ma / mb - 1.0f64 }
    var v = 0.0f64
    var u = 0usize
    while u < p {
        var gu = ja[u] - jb[u]
        if kind == 1usize || kind == 3usize { gu = ja[u] / mb - ma * jb[u] / (mb * mb) }
        if kind == 2usize { gu = ja[u] / ma - jb[u] / mb }
        var w = 0usize
        while w < p {
            var gw = ja[w] - jb[w]
            if kind == 1usize || kind == 3usize { gw = ja[w] / mb - ma * jb[w] / (mb * mb) }
            if kind == 2usize { gw = ja[w] / ma - jb[w] / mb }
            v += gu * vcov[w * p + u] * gw
            w += 1usize
        }
        u += 1usize
    }
    out[0usize] = est
    out[1usize] = math.sqrt[f64](v)
}

// One row of a predicted-margin table (ggeffects predict_response, effects Effect) for a glm: x is the model-matrix row of the margin (the focal term at its value, the other terms at their mean or reference), beta and vcov (p by p, column-major) from the fit.
// df is the residual degrees of freedom for a family that estimates its dispersion (the interval then uses the t quantile) or 0 for binomial and Poisson (the normal quantile); level is the interval level.
// out = (response mu(eta), standard error on the link scale, standard error on the response scale mu'(eta) se, interval lower, interval upper), the interval formed on the link scale and mapped through the inverse link
fn glm_margin(link: usize, x: []const f64, beta: []const f64, vcov: []const f64, p: usize, df: f64, level: f64, out: []f64) {
    var eta = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < p {
        eta += x[i] * beta[i]
        var j = 0usize
        while j < p {
            q += x[i] * vcov[j * p + i] * x[j]
            j += 1usize
        }
        i += 1usize
    }
    let se = math.sqrt[f64](q)
    var crit = dist.qnorm(0.5f64 + level / 2.0f64, 0.0f64, 1.0f64, true, false)
    if df > 0.0f64 { crit = nb.qt(0.5f64 + level / 2.0f64, df, true, false) }
    var d: [3]f64 = zero
    mu_d(link, eta, d[0usize..3usize])
    out[0usize] = d[0usize]
    out[1usize] = se
    out[2usize] = math.abs[f64](d[1usize]) * se
    var lo: [3]f64 = zero
    var hi: [3]f64 = zero
    mu_d(link, eta - crit * se, lo[0usize..3usize])
    mu_d(link, eta + crit * se, hi[0usize..3usize])
    out[3usize] = lo[0usize]
    out[4usize] = hi[0usize]
}

// ---- counterfactual model matrices: slopes, comparisons and predictions of any model, factors and interactions included, by group ----

// the coding of a factor of nl levels: kind 0 treatment (contr.treatment), 1 sum (contr.sum), 2 Helmert (contr.helmert); the value of column c (0 .. nl - 2) at level l (0 .. nl - 1)
fn contr_value(kind: usize, nl: usize, l: usize, c: usize) -> f64 {
    if kind == 0usize {
        if l == c + 1usize { ret 1.0f64 }
        ret 0.0f64
    }
    if kind == 1usize {
        if l == c { ret 1.0f64 }
        if l == nl - 1usize { ret -1.0f64 }
        ret 0.0f64
    }
    if l <= c { ret -1.0f64 }
    if l == c + 1usize { ret f64(c + 1usize) }
    ret 0.0f64
}

// the model.matrix of one of the designs below, n by the returned width, column-major in out; f holds the level (0 based) of a factor with nf levels, x and w are numeric
// model 0: ~ x + w; 1: ~ f + x; 2: ~ f * x; 3: ~ x + I(x^2) + f; 4: ~ x * w + f. Callers rebuild it with a variable moved to get a counterfactual matrix
fn mm_design(model: usize, coding: usize, nf: usize, f: []const f64, x: []const f64, w: []const f64, n: usize, out: []f64) -> usize {
    var c = 1usize
    var i = 0usize
    while i < n {
        out[i] = 1.0f64
        i += 1usize
    }
    if model == 0usize || model == 3usize || model == 4usize {
        i = 0usize
        while i < n {
            out[c * n + i] = x[i]
            i += 1usize
        }
        c += 1usize
    }
    if model == 0usize || model == 4usize {
        i = 0usize
        while i < n {
            out[c * n + i] = w[i]
            i += 1usize
        }
        c += 1usize
    }
    if model == 3usize {
        i = 0usize
        while i < n {
            out[c * n + i] = x[i] * x[i]
            i += 1usize
        }
        c += 1usize
    }
    if model == 4usize {
        i = 0usize
        while i < n {
            out[c * n + i] = x[i] * w[i]
            i += 1usize
        }
        c += 1usize
    }
    if model >= 1usize {
        var k = 0usize
        while k + 1usize < nf {
            i = 0usize
            while i < n {
                out[c * n + i] = contr_value(coding, nf, usize(f[i]), k)
                i += 1usize
            }
            c += 1usize
            k += 1usize
        }
    }
    if model == 1usize || model == 2usize {
        i = 0usize
        while i < n {
            out[c * n + i] = x[i]
            i += 1usize
        }
        c += 1usize
    }
    if model == 2usize {
        var k = 0usize
        while k + 1usize < nf {
            i = 0usize
            while i < n {
                out[c * n + i] = contr_value(coding, nf, usize(f[i]), k) * x[i]
                i += 1usize
            }
            c += 1usize
            k += 1usize
        }
    }
    ret c
}

// the average over the rows with a nonzero mask (all rows when mask is empty) of a counterfactual pair: xh and xl are n by p column-major model matrices with the variable at its high and low value.
// kind 0: mean (mu(xh b) - mu(xl b)) / div (div is the step of a slope, else 1); 1: ratio of the means; 2: its log; 3: the ratio less one; 4: the mean prediction at xh (avg_predictions, xl unused).
// out = (estimate, delta-method standard error); jac (p long) gets the gradient of the estimate
fn glm_pair(a: *mem.Arena, link: usize, kind: usize, xh: []const f64, xl: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, mask: []const f64, div: f64, jac: []f64, out: []f64) {
    let (ja, e1) = mem.alloc[f64](a, p)
    let (jb, e2) = mem.alloc[f64](a, p)
    let (m1, e3) = mem.alloc[f64](a, 3usize)
    let (m0, e4) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    var nf = 0.0f64
    var i = 0usize
    while i < n {
        if mask.len == 0usize || mask[i] != 0.0f64 { nf += 1.0f64 }
        i += 1usize
    }
    var k = 0usize
    while k < p {
        ja[k] = 0.0f64
        jb[k] = 0.0f64
        k += 1usize
    }
    var ma = 0.0f64
    var mb = 0.0f64
    i = 0usize
    while i < n {
        if mask.len == 0usize || mask[i] != 0.0f64 {
            var eh = 0.0f64
            var el = 0.0f64
            k = 0usize
            while k < p {
                eh += xh[k * n + i] * beta[k]
                el += xl[k * n + i] * beta[k]
                k += 1usize
            }
            mu_d(link, eh, m1)
            mu_d(link, el, m0)
            ma += m1[0usize] / nf
            mb += m0[0usize] / nf
            k = 0usize
            while k < p {
                ja[k] += m1[1usize] * xh[k * n + i] / nf
                jb[k] += m0[1usize] * xl[k * n + i] / nf
                k += 1usize
            }
        }
        i += 1usize
    }
    var est = ma
    if kind == 0usize { est = (ma - mb) / div }
    if kind == 1usize { est = ma / mb }
    if kind == 2usize { est = math.log[f64](ma / mb) }
    if kind == 3usize { est = ma / mb - 1.0f64 }
    k = 0usize
    while k < p {
        var g = ja[k]
        if kind == 0usize { g = (ja[k] - jb[k]) / div }
        if kind == 1usize || kind == 3usize { g = ja[k] / mb - ma * jb[k] / (mb * mb) }
        if kind == 2usize { g = ja[k] / ma - jb[k] / mb }
        jac[k] = g
        k += 1usize
    }
    var v = 0.0f64
    var u = 0usize
    while u < p {
        var w = 0usize
        while w < p {
            v += jac[u] * vcov[w * p + u] * jac[w]
            w += 1usize
        }
        u += 1usize
    }
    out[0usize] = est
    out[1usize] = math.sqrt[f64](v)
}

// the weights of row `row` of hypothesis = ~pairwise (kind 0: b2 - b1, b3 - b1, b3 - b2, b4 - b1, ...), ~revpairwise (1: the opposite signs), ~sequential (2: b2 - b1, b3 - b2, ...) or ~reference (3: b2 - b1, b3 - b1, ...) over m estimates, in r (m long); answers false past the last row
fn hyp_weights(kind: usize, m: usize, row: usize, r: []f64) -> bool {
    var i = 0usize
    while i < m {
        r[i] = 0.0f64
        i += 1usize
    }
    var lo = 0usize
    var hi = 0usize
    var found = false
    if kind == 2usize {
        if row + 1usize < m {
            lo = row
            hi = row + 1usize
            found = true
        }
    } else if kind == 3usize {
        if row + 1usize < m {
            lo = 0usize
            hi = row + 1usize
            found = true
        }
    } else {
        // pairwise runs through the later level of each pair last-first (b - a, c - a, d - a, c - b, ...), revpairwise through the earlier level (a - b, a - c, b - c, a - d, ...)
        var cnt = 0usize
        var u = 0usize
        while u < m {
            var v = 0usize
            while v < m {
                var s = u
                var t = v
                var ok3 = false
                if kind == 0usize {
                    s = u
                    t = v
                    ok3 = v > u
                } else {
                    s = v
                    t = u
                    ok3 = v < u
                }
                if ok3 {
                    if cnt == row {
                        lo = s
                        hi = t
                        found = true
                    }
                    cnt += 1usize
                }
                v += 1usize
            }
            u += 1usize
        }
    }
    if !found { ret false }
    if kind == 1usize {
        r[lo] = 1.0f64
        r[hi] = -1.0f64
    } else {
        r[lo] = -1.0f64
        r[hi] = 1.0f64
    }
    ret true
}

// hypotheses() over m estimates (estimates est, gradients jacs m by p row-major from glm_pair): the weighted sum r'est - q with its delta-method standard error, z statistic and two-sided normal p-value
fn hyp_est(est: []const f64, jacs: []const f64, r: []const f64, q: f64, vcov: []const f64, p: usize, m: usize, out: []f64) {
    var e = 0.0f64 - q
    var g: [64]f64 = zero
    var i = 0usize
    while i < m {
        e += r[i] * est[i]
        var k = 0usize
        while k < p {
            g[k] += r[i] * jacs[i * p + k]
            k += 1usize
        }
        i += 1usize
    }
    var v = 0.0f64
    var u = 0usize
    while u < p {
        var w = 0usize
        while w < p {
            v += g[u] * vcov[w * p + u] * g[w]
            w += 1usize
        }
        u += 1usize
    }
    let se = math.sqrt[f64](v)
    out[0usize] = e
    out[1usize] = se
    out[2usize] = e / se
    out[3usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](e / se), 0.0f64, 1.0f64, true, false)
}

// hypotheses(joint = ): the Wald statistic of R b = r0 over q rows (rr q by p row-major, q at most 16): (Rb - r0)' (R V R')^-1 (Rb - r0);
// out = (chi-square, q, its p-value, F = chi-square / q, p-value of F at df residual degrees of freedom, 0 when df is 0)
fn lin_joint(a: *mem.Arena, beta: []const f64, vcov: []const f64, rr: []const f64, r0: []const f64, p: usize, q: usize, df: f64, out: []f64) {
    let (m, e1) = mem.alloc[f64](a, q * q)
    let (d, e2) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok {
        out[0usize] = 0.0f64 / 0.0f64
        ret
    }
    var d0: [16]f64 = zero
    var i = 0usize
    while i < q {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += rr[i * p + k] * beta[k]
            k += 1usize
        }
        d[i] = s - r0[i]
        d0[i] = d[i]
        var j = 0usize
        while j < q {
            var t = 0.0f64
            k = 0usize
            while k < p {
                var l = 0usize
                while l < p {
                    t += rr[i * p + k] * vcov[l * p + k] * rr[j * p + l]
                    l += 1usize
                }
                k += 1usize
            }
            m[i * q + j] = t
            j += 1usize
        }
        i += 1usize
    }
    // Gaussian elimination with partial pivoting solves m y = d; row swaps do not change y
    var c = 0usize
    while c < q {
        var piv = c
        var r = c + 1usize
        while r < q {
            if math.abs[f64](m[r * q + c]) > math.abs[f64](m[piv * q + c]) { piv = r }
            r += 1usize
        }
        if piv != c {
            var j = 0usize
            while j < q {
                let t = m[c * q + j]
                m[c * q + j] = m[piv * q + j]
                m[piv * q + j] = t
                j += 1usize
            }
            let t2 = d[c]
            d[c] = d[piv]
            d[piv] = t2
        }
        r = c + 1usize
        while r < q {
            let fct = m[r * q + c] / m[c * q + c]
            var j = c
            while j < q {
                m[r * q + j] -= fct * m[c * q + j]
                j += 1usize
            }
            d[r] -= fct * d[c]
            r += 1usize
        }
        c += 1usize
    }
    var sol: [16]f64 = zero
    var ii = q
    while ii > 0usize {
        ii -= 1usize
        var s = d[ii]
        var j = ii + 1usize
        while j < q {
            s -= m[ii * q + j] * sol[j]
            j += 1usize
        }
        sol[ii] = s / m[ii * q + ii]
    }
    var stat = 0.0f64
    i = 0usize
    while i < q {
        stat += d0[i] * sol[i]
        i += 1usize
    }
    out[0usize] = stat
    out[1usize] = f64(q)
    out[2usize] = nm.pchisq(stat, f64(q), false, false)
    out[3usize] = stat / f64(q)
    out[4usize] = 0.0f64
    if df > 0.0f64 { out[4usize] = nb.pf(stat / f64(q), f64(q), df, false, false) }
}
