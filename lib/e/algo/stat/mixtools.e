// R mixtools: normalmixEM for a univariate normal mixture from given starting values: the EM iteration of the package (its default constraints select the ECM variant, which refreshes the posteriors and the weights after the means move), including that the variance
// update uses the squared deviations from the previous means, the log-likelihood and the stopping rule (an increase of at most epsilon, or maxit).
//
// Not here: the random starting values, the constrained and fast variants, restarts for collapsing variances, the multivariate and regression
// mixtures, the bootstrap and the semiparametric EM.

use e.math
use e.mem

type Fit = struct { loglik: f64, iter: usize }

fn phi(x: f64, mu: f64, sd: f64) -> f64 {
    let z = (x - mu) / sd
    ret math.exp[f64](0.0f64 - 0.5f64 * z * z) / (sd * math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64))
}

// posterior probabilities into post (n by k row-major), squared deviations into res, and the log-likelihood
fn posterior(x: []const f64, lambda: []const f64, mu: []const f64, sd: []const f64, post: []f64, res: []f64) -> f64 {
    let n = x.len
    let k = lambda.len
    var ll = 0.0f64
    var i = 0usize
    while i < n {
        var tot = 0.0f64
        var j = 0usize
        while j < k {
            let d = x[i] - mu[j]
            res[i * k + j] = d * d
            let v = lambda[j] * phi(x[i], mu[j], sd[j])
            post[i * k + j] = v
            tot += v
            j += 1usize
        }
        j = 0usize
        while j < k {
            post[i * k + j] = post[i * k + j] / tot
            j += 1usize
        }
        ll += math.log[f64](tot)
        i += 1usize
    }
    ret ll
}

// lambda, mu and sd hold the starting values and receive the estimates
fn normal_mix_em(a: *mem.Arena, x: []const f64, lambda: []f64, mu: []f64, sd: []f64, epsilon: f64, maxit: usize) -> (Fit, err) {
    let n = x.len
    let k = lambda.len
    let (post, e1) = mem.alloc[f64](a, n * k)
    if e1 != ok { ret (zero, e1) }
    let (res, e2) = mem.alloc[f64](a, n * k)
    if e2 != ok { ret (zero, e2) }
    var ll = posterior(x, lambda, mu, sd, post, res)
    var diff = epsilon + 1.0f64
    var iter = 0usize
    while diff > epsilon && iter < maxit {
        var j = 0usize
        while j < k {
            var sp = 0.0f64
            var sx = 0.0f64
            var i = 0usize
            while i < n {
                sp += post[i * k + j]
                sx += post[i * k + j] * x[i]
                i += 1usize
            }
            lambda[j] = sp / f64(n)
            mu[j] = sx / (f64(n) * lambda[j])
            j += 1usize
        }
        // the default constraints make the package run the ECM variant: posteriors again at the new means, then lambda again
        let _ = posterior(x, lambda, mu, sd, post, res)
        j = 0usize
        while j < k {
            var sp = 0.0f64
            var i = 0usize
            while i < n {
                sp += post[i * k + j]
                i += 1usize
            }
            lambda[j] = sp / f64(n)
            j += 1usize
        }
        j = 0usize
        while j < k {
            var sr = 0.0f64
            var i = 0usize
            while i < n {
                sr += post[i * k + j] * res[i * k + j]
                i += 1usize
            }
            sd[j] = math.sqrt[f64](sr / (f64(n) * lambda[j]))
            j += 1usize
        }
        let nll = posterior(x, lambda, mu, sd, post, res)
        diff = nll - ll
        ll = nll
        iter += 1usize
    }
    ret (Fit { loglik: ll, iter: iter }, ok)
}
