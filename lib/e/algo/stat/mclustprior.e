// R mclust: defaultPrior and the conjugate-prior M step and EM (msXXp / meXXp of mclust.f) for E, V, EII, VII, EEE and VVV.
//
// Not here: the prior versions of EEI, VEI, EVI, VVI, EEV and VEV (mclust has no prior for EVE, VEE, VVE and EVV either).
// pscale is a scalar for E, V, EII (not used by mclust there) and VII, the p by p matrix for EEE and VVV.

use e.math
use e.mem
use e.algo.stat.mclustem as em

// defaultPrior(data, G, modelName): shrinkage 0.01, mean = column means, dof and scale as mclust computes them; pscale (p * p) gets the scalar in [0] or the matrix
fn default_prior(x: []const f64, n: usize, p: usize, g: usize, model: usize, pmu: []f64, pscale: []f64) -> f64 {
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[j * n + i]
            i += 1usize
        }
        pmu[j] = m / f64(n)
        j += 1usize
    }
    // covariance (divisor n - 1)
    var b = 0usize
    while b < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[b * n + i] - pmu[b]) * (x[c * n + i] - pmu[c])
                i += 1usize
            }
            pscale[c * p + b] = s / f64(n - 1usize)
            c += 1usize
        }
        b += 1usize
    }
    let gg = f64(g)
    if model == 0usize || model == 1usize {
        pscale[0usize] = pscale[0usize] / (gg * gg)
        ret 3.0f64
    }
    let fac = math.pow[f64](1.0f64 / gg, 2.0f64 / f64(p))
    if model == 2usize || model == 3usize {
        var tr = 0.0f64
        j = 0usize
        while j < p {
            tr += pscale[j * p + j]
            j += 1usize
        }
        pscale[0usize] = fac * tr / f64(p)
        ret f64(p) + 2.0f64
    }
    // full matrix: fac * var(data), or its diagonal when n <= p
    b = 0usize
    while b < p {
        var c = 0usize
        while c < p {
            if n > p || b == c { pscale[c * p + b] = fac * pscale[c * p + b] } else { pscale[c * p + b] = 0.0f64 }
            c += 1usize
        }
        b += 1usize
    }
    ret f64(p) + 2.0f64
}

// the M step with the prior (shrk, pmu, pscale, pdof) from z: pro (g), mu (p by g), sigma (g stacked p by p)
fn mstep_prior(a: *mem.Arena, model: usize, x: []const f64, z: []const f64, n: usize, p: usize, g: usize, shrk: f64, pmu: []const f64, pscale: []const f64, pdof: f64, pro: []f64, mu: []f64, sigma: []f64) -> err {
    let (sumz, e1) = mem.alloc[f64](a, g)
    let (u, e2) = mem.alloc[f64](a, g * p * p)
    let (acc, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var k = 0usize
    while k < g {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += z[k * n + i]
            i += 1usize
        }
        sumz[k] = s
        pro[k] = s / f64(n)
        k += 1usize
    }
    em.scatter(x, z, n, p, g, sumz, mu, u)
    var corr = 0.0f64
    if shrk > 0.0f64 { corr = 1.0f64 }
    let nn = f64(n)
    let pp = f64(p)
    let gg = f64(g)
    var tz = 0.0f64
    k = 0usize
    while k < g {
        tz += sumz[k]
        k += 1usize
    }
    // the group term c_k d d' is added to u (about the unshrunk mean); for EII the scatter is about the shrunk mean
    var b = 0usize
    var c = 0usize
    var q = 0usize
    while q < p * p {
        acc[q] = 0.0f64
        q += 1usize
    }
    var eii = 0.0f64
    k = 0usize
    while k < g {
        let ck = sumz[k] * shrk / (sumz[k] + shrk)
        b = 0usize
        while b < p {
            c = 0usize
            while c < p {
                let dd = (mu[k * p + b] - pmu[b]) * (mu[k * p + c] - pmu[c])
                u[k * p * p + c * p + b] = u[k * p * p + c * p + b] + ck * dd
                acc[c * p + b] += u[k * p * p + c * p + b]
                c += 1usize
            }
            b += 1usize
        }
        if model == 2usize {
            // EII: the scatter about the shrunk mean plus the shrinkage term, the scale is not used
            var tr = 0.0f64
            var j = 0usize
            while j < p {
                let ms = (sumz[k] * mu[k * p + j] + shrk * pmu[j]) / (sumz[k] + shrk)
                var i = 0usize
                while i < n {
                    let df = x[j * n + i] - ms
                    tr += z[k * n + i] * df * df
                    i += 1usize
                }
                let d2 = mu[k * p + j] - pmu[j]
                tr += ck * d2 * d2
                j += 1usize
            }
            eii += tr
        }
        // shrink the mean
        var j = 0usize
        while j < p {
            mu[k * p + j] = (sumz[k] * mu[k * p + j] + shrk * pmu[j]) / (sumz[k] + shrk)
            j += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < g {
        var den = 1.0f64
        b = 0usize
        while b < p * p {
            sigma[k * p * p + b] = 0.0f64
            b += 1usize
        }
        if model == 0usize {
            den = pdof + nn + 2.0f64 + corr * gg
            sigma[k] = (pscale[0usize] + acc[0usize]) / den
        } else if model == 1usize {
            den = pdof + sumz[k] + 2.0f64 + corr
            sigma[k] = (pscale[0usize] + u[k * p * p]) / den
        } else if model == 2usize {
            den = pdof + tz * pp + 2.0f64 + corr * gg * pp
            var j = 0usize
            while j < p {
                sigma[k * p * p + j * p + j] = eii / den
                j += 1usize
            }
        } else if model == 3usize {
            den = pdof + sumz[k] * pp + 2.0f64 + corr * pp
            var tr = pscale[0usize]
            var j = 0usize
            while j < p {
                tr += u[k * p * p + j * p + j]
                j += 1usize
            }
            j = 0usize
            while j < p {
                sigma[k * p * p + j * p + j] = tr / den
                j += 1usize
            }
        } else if model == 8usize {
            den = pdof + nn + pp + 1.0f64 + corr * gg
            b = 0usize
            while b < p * p {
                sigma[k * p * p + b] = (pscale[b] + acc[b]) / den
                b += 1usize
            }
        } else {
            den = pdof + sumz[k] + pp + 1.0f64 + corr
            b = 0usize
            while b < p * p {
                sigma[k * p * p + b] = (pscale[b] + u[k * p * p + b]) / den
                b += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// me(data, modelName, z, prior): EM with the prior M step; returns the log likelihood of the data (NaN on failure), info 0 the iterations
fn me_prior(a: *mem.Arena, model: usize, x: []const f64, z: []f64, n: usize, p: usize, g: usize, shrk: f64, pmu: []const f64, pscale: []const f64, pdof: f64, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    var hold = 8.0e307f64
    var iter = 0usize
    while true {
        iter += 1usize
        let it0 = mem.mark(a)
        if mstep_prior(a, model, x, z, n, p, g, shrk, pmu, pscale, pdof, pro, mu, sigma) != ok { ret 0.0f64 / 0.0f64 }
        let hood = em.estep_gen(a, x, n, p, g, mu, sigma, pro, z)
        mem.reset(a, it0)
        if hood != hood { ret hood }
        let err1 = math.abs[f64](hold - hood) / (1.0f64 + math.abs[f64](hood))
        hold = hood
        if err1 <= 1.0e-5f64 {
            info[0usize] = f64(iter)
            ret hood
        }
    }
    ret 0.0f64
}
