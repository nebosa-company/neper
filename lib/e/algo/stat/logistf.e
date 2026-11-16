// R logistf: Firth's penalized logistic regression. The coefficients maximise l(b) + 0.5 log |X' W X|; the covariance is the inverse
// information at the estimate, the penalized log-likelihoods of the full and the intercept-only model are reported, and the profile
// penalized-likelihood-ratio p value of each coefficient comes from the fit with that coefficient fixed at zero.
//
// Not here: the profile-likelihood confidence limits, FLIC and FLAC, weights, offsets, pl convergence histories and predict.

use e.math
use e.math.nmath as nm
use e.mem

// x is n by p row-major with the intercept column included
type Fit = struct { beta: []f64, cov: []f64, pll: f64, iter: usize }

fn expit(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

// invert a p by p matrix in place into out; returns the log determinant (of the input) as the second answer
fn invert(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> (f64, err) {
    let (w, e) = mem.alloc[f64](a, p * 2usize * p)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            w[i * 2usize * p + j] = m[i * p + j]
            w[i * 2usize * p + p + j] = 0.0f64
            j += 1usize
        }
        w[i * 2usize * p + p + i] = 1.0f64
        i += 1usize
    }
    var logdet = 0.0f64
    var c = 0usize
    while c < p {
        var piv = c
        var k = c + 1usize
        while k < p {
            if math.abs[f64](w[k * 2usize * p + c]) > math.abs[f64](w[piv * 2usize * p + c]) { piv = k }
            k += 1usize
        }
        var j = 0usize
        while j < 2usize * p {
            let t = w[c * 2usize * p + j]
            w[c * 2usize * p + j] = w[piv * 2usize * p + j]
            w[piv * 2usize * p + j] = t
            j += 1usize
        }
        let d = w[c * 2usize * p + c]
        logdet += math.log[f64](math.abs[f64](d))
        j = 0usize
        while j < 2usize * p {
            w[c * 2usize * p + j] = w[c * 2usize * p + j] / d
            j += 1usize
        }
        k = 0usize
        while k < p {
            if k != c {
                let f = w[k * 2usize * p + c]
                j = 0usize
                while j < 2usize * p {
                    w[k * 2usize * p + j] -= f * w[c * 2usize * p + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            out[i * p + j] = w[i * 2usize * p + p + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (logdet, ok)
}

// penalized log-likelihood at beta, with the information matrix and its inverse and the hat diagonal written out
fn pen_ll(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, beta: []const f64, info: []f64, cov: []f64, h: []f64) -> (f64, err) {
    var ll = 0.0f64
    var i = 0usize
    var q = 0usize
    while q < p * p {
        info[q] = 0.0f64
        q += 1usize
    }
    let (pi, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (0.0f64, e0) }
    while i < n {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += x[i * p + j] * beta[j]
            j += 1usize
        }
        let pr = expit(t)
        pi[i] = pr
        if y[i] > 0.5f64 { ll += math.log[f64](pr) } else { ll += math.log[f64](1.0f64 - pr) }
        let w = pr * (1.0f64 - pr)
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                info[j * p + k] += w * x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let (logdet, e1) = invert(a, info, p, cov)
    if e1 != ok { ret (0.0f64, e1) }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                s += x[i * p + j] * cov[j * p + k] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        h[i] = pi[i] * (1.0f64 - pi[i]) * s
        i += 1usize
    }
    ret (ll + 0.5f64 * logdet, ok)
}

// fixed: the index of a coefficient held at zero (p when none); the fit moves the others by Newton steps with step halving
fn firth(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, fixed: usize) -> (Fit, err) {
    let (f, e) = firth_sub(a, x, y, n, p, fixed, p)
    ret (f, e)
}

// only the first nfree coefficients move (the null model keeps the intercept alone, the penalty still uses every column)
fn firth_sub(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, fixed: usize, nfree: usize) -> (Fit, err) {
    let (beta, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (zero, e1) }
    let (info, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret (zero, e2) }
    let (cov, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret (zero, e3) }
    let (h, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret (zero, e4) }
    let (trial, e5) = mem.alloc[f64](a, p)
    if e5 != ok { ret (zero, e5) }
    let (u, e6) = mem.alloc[f64](a, p)
    if e6 != ok { ret (zero, e6) }
    let (step, e7) = mem.alloc[f64](a, p)
    if e7 != ok { ret (zero, e7) }
    let (info2, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret (zero, e8) }
    let (h2, e9) = mem.alloc[f64](a, n)
    if e9 != ok { ret (zero, e9) }
    var i = 0usize
    while i < p {
        beta[i] = 0.0f64
        i += 1usize
    }
    var iter = 0usize
    var (pll, e0) = pen_ll(a, x, y, n, p, beta, info, cov, h)
    if e0 != ok { ret (zero, e0) }
    while iter < 200usize {
        // the penalized score U* = X' (y - pi + h (0.5 - pi))
        i = 0usize
        while i < p {
            u[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            var t = 0.0f64
            var j = 0usize
            while j < p {
                t += x[i * p + j] * beta[j]
                j += 1usize
            }
            let pr = expit(t)
            let r = y[i] - pr + h[i] * (0.5f64 - pr)
            j = 0usize
            while j < p {
                u[j] += x[i * p + j] * r
                j += 1usize
            }
            i += 1usize
        }
        // the step on the free coefficients: solve the information restricted to them
        var nf = 0usize
        let (idx, e10) = mem.alloc[usize](a, p)
        if e10 != ok { ret (zero, e10) }
        i = 0usize
        while i < p {
            if i != fixed && i < nfree {
                idx[nf] = i
                nf += 1usize
            }
            i += 1usize
        }
        let (sub, e11) = mem.alloc[f64](a, nf * nf)
        if e11 != ok { ret (zero, e11) }
        let (sinv, e12) = mem.alloc[f64](a, nf * nf)
        if e12 != ok { ret (zero, e12) }
        i = 0usize
        while i < nf {
            var j = 0usize
            while j < nf {
                sub[i * nf + j] = info[idx[i] * p + idx[j]]
                j += 1usize
            }
            i += 1usize
        }
        let (ld, e13) = invert(a, sub, nf, sinv)
        if e13 != ok { ret (zero, e13) }
        i = 0usize
        while i < p {
            step[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < nf {
            var s = 0.0f64
            var j = 0usize
            while j < nf {
                s += sinv[i * nf + j] * u[idx[j]]
                j += 1usize
            }
            step[idx[i]] = s
            i += 1usize
        }
        var scale = 1.0f64
        var ok_step = false
        var tries = 0usize
        var new_pll = pll
        while tries < 30usize && !ok_step {
            i = 0usize
            while i < p {
                trial[i] = beta[i] + scale * step[i]
                i += 1usize
            }
            let (np, e14) = pen_ll(a, x, y, n, p, trial, info2, cov, h2)
            if e14 != ok { ret (zero, e14) }
            if np >= pll - 1.0e-12f64 {
                ok_step = true
                new_pll = np
            } else {
                scale = scale / 2.0f64
            }
            tries += 1usize
        }
        if !ok_step { break }
        var maxd = 0.0f64
        i = 0usize
        while i < p {
            let dd = math.abs[f64](scale * step[i])
            if dd > maxd { maxd = dd }
            beta[i] = trial[i]
            i += 1usize
        }
        let (np2, e15) = pen_ll(a, x, y, n, p, beta, info, cov, h)
        if e15 != ok { ret (zero, e15) }
        pll = np2
        iter += 1usize
        if maxd < 1.0e-11f64 { break }
    }
    // the package reports the covariance as the inverse of X' diag(w (1 + h)) X at the estimate
    let (pp, e16) = mem.alloc[f64](a, p * p)
    if e16 != ok { ret (zero, e16) }
    i = 0usize
    while i < p * p {
        pp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += x[i * p + j] * beta[j]
            j += 1usize
        }
        let pr = expit(t)
        let w = pr * (1.0f64 - pr) * (1.0f64 + h[i])
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                pp[j * p + k] += w * x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let (ldd, e17) = invert(a, pp, p, cov)
    if e17 != ok { ret (zero, e17) }
    ret (Fit { beta: beta, cov: cov, pll: pll, iter: iter }, ok)
}

// the "null" penalized log-likelihood: only the intercept moves, the penalty keeps the full design
fn null_pll(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, err) {
    let (f, e2) = firth_sub(a, x, y, n, p, p, 1usize)
    if e2 != ok { ret (0.0f64, e2) }
    ret (f.pll, ok)
}

// the profile penalized-likelihood-ratio p value for coefficient k
fn prof_p(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, full: f64, k: usize) -> (f64, err) {
    let (f, e) = firth(a, x, y, n, p, k)
    if e != ok { ret (0.0f64, e) }
    var stat = 2.0f64 * (full - f.pll)
    if stat < 0.0f64 { stat = 0.0f64 }
    ret (nm.pchisq(stat, 1.0f64, false, false), ok)
}
