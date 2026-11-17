// R marginaleffects for a logistic regression, from the fitted coefficients and their covariance: `avg_predictions` (the mean fitted probability) and `avg_slopes` (the average marginal effect of a variable, mean of beta_j p (1 - p)), each with the delta-method standard error
// sqrt(J V J') from the analytic Jacobian (marginaleffects differentiates numerically, so its estimates carry a difference error of about 1e-9).
//
// Not here: comparisons for factors, other families and links, predictions at a grid or for a new data frame, conditional effects, hypotheses.

use e.math
use e.mem

fn logistic(eta: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta)) }

// x is n by p column-major (an intercept column included), beta and vcov (p by p, column-major) from the fit; j the slope variable (1-based column of x), or p = pass j >= p for the average prediction.
// out = (estimate, standard error)
fn logit_avg(a: *mem.Arena, x: []const f64, beta: []const f64, vcov: []const f64, n: usize, p: usize, j: usize, out: []f64) {
    let nf = f64(n)
    var jac_est = 0.0f64
    var est = 0.0f64
    var k = 0usize
    let (jac, je) = mem.alloc[f64](a, p)
    if je != ok {
        out[0usize] = 0.0f64 / 0.0f64
        out[1usize] = 0.0f64 / 0.0f64
        ret
    }
    k = 0usize
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
        let pr = logistic(eta)
        let w = pr * (1.0f64 - pr)
        if j >= p {
            est += pr / nf
            k = 0usize
            while k < p {
                jac[k] += w * x[k * n + i] / nf
                k += 1usize
            }
        } else {
            est += beta[j] * w / nf
            k = 0usize
            while k < p {
                var d = beta[j] * w * (1.0f64 - 2.0f64 * pr) * x[k * n + i]
                if k == j { d += w }
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
