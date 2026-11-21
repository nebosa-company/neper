// R MCMCpack::MCMCoprobit with mcmc.method "Cowles" (R's default): the ordered probit Gibbs sampler with the Cowles (1996) Metropolis step for the cut points,
// on the Scythe Mersenne-Twister stream. The start values come from MASS::polr as in R (masspolr.e), the tuning is the scalar tune.
//
// The "AC" method is in e.algo.stat.mcmcpackac; beta.start is taken as given (R 4.6 accepts only a scalar one, recycled).

use e.algo.stat.masspolr as mp
use e.algo.stat.mcmcpackdraw as md
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.math.dist as dist
use e.mem

// Scythe's two-sided rtnorm_combo
fn rtnorm_combo(g: *ms.Sc, mean: f64, variance: f64, below: f64, above: f64) -> f64 {
    let sd = math.sqrt[f64](variance)
    let za = (above - mean) / sd
    let zb = (below - mean) / sd
    if (za > 0.5f64 && -1.0f64 * zb > 0.5f64) || (za > 2.0f64 && zb < 0.25f64) || (-1.0f64 * zb > 2.0f64 && za > -0.25f64) {
        var x = ms.sc_rnorm(g, mean, sd)
        while x > above || x < below { x = ms.sc_rnorm(g, mean, sd) }
        ret x
    }
    ret md.rtnorm(g, mean, variance, below, above)
}

fn pn(x: f64, mean: f64, sd: f64) -> f64 { ret dist.pnorm((x - mean) / sd, 0.0f64, 1.0f64, true, false) }

// R's start values from polr: gamma (ncat + 1 entries) and beta (k)
fn oprobit_start(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, k: usize, ncat: usize, gamma: []f64, beta: []f64) -> err {
    let pc = k - 1usize
    let (xp, ea) = mem.alloc[f64](a, n * pc + 1usize)
    let (wt, eb) = mem.alloc[f64](a, n)
    let (off, ec) = mem.alloc[f64](a, n)
    if ea != ok { ret ea }
    if eb != ok { ret eb }
    if ec != ok { ret ec }
    var t = 0usize
    while t < n {
        wt[t] = 1.0f64
        off[t] = 0.0f64
        var j = 0usize
        while j < pc {
            xp[j * n + t] = x[t * k + j + 1usize]
            j += 1usize
        }
        t += 1usize
    }
    let (fit, ep) = mp.polr(a, xp[0usize..n * pc], n, pc, y, ncat, wt, off, 0usize, false, xp[0usize..0usize], false)
    if ep != ok { ret ep }
    gamma[0usize] = -300.0f64
    gamma[1usize] = 0.0f64
    var s = 2usize
    while s < ncat {
        gamma[s] = (fit.zeta[s - 1usize] - fit.zeta[0usize]) * 0.588f64
        s += 1usize
    }
    gamma[ncat] = 300.0f64
    beta[0usize] = -0.588f64 * fit.zeta[0usize]
    var j = 1usize
    while j < k {
        beta[j] = 0.588f64 * fit.beta[j - 1usize]
        j += 1usize
    }
    ret ok
}

// y holds levels 1..ncat; x is n by k row-major with an intercept first; bb0 is the k by k prior precision.
// out is nstore rows of (beta[k], gamma[2..ncat-1])
fn oprobit_cowles_polr(a: *mem.Arena, g: *ms.Sc, y: []const f64, x: []const f64, n: usize, k: usize, ncat: usize, tune: f64, b0: []const f64, bb0: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let (gamma0, e1) = mem.alloc[f64](a, ncat + 1usize)
    let (beta0, e2) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let es = oprobit_start(a, y, x, n, k, ncat, gamma0, beta0)
    if es != ok { ret es }
    ret oprobit_cowles(a, g, y, x, n, k, ncat, tune, gamma0, beta0, b0, bb0, burnin, mcmc, thin, out)
}

// gamma0 (ncat + 1 entries, -300 first and 300 last) and beta0 are the start values
fn oprobit_cowles(a: *mem.Arena, g: *ms.Sc, y: []const f64, x: []const f64, n: usize, k: usize, ncat: usize, tune: f64, gamma0: []const f64, beta0: []const f64, b0: []const f64, bb0: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let nstore = mcmc / thin
    let width = k + ncat - 2usize
    let (gamma, e1) = mem.alloc[f64](a, ncat + 1usize)
    let (gp, e2) = mem.alloc[f64](a, ncat + 1usize)
    let (beta, e3) = mem.alloc[f64](a, k)
    let (m1, e4) = mem.alloc[f64](a, k * k)
    let (bn_var, e5) = mem.alloc[f64](a, k * k)
    let (cc, e6) = mem.alloc[f64](a, k * k)
    let (zv, e7) = mem.alloc[f64](a, n)
    let (xb, e8) = mem.alloc[f64](a, n)
    let (rhs, e9) = mem.alloc[f64](a, k)
    let (zz, e10) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var s = 0usize
    while s <= ncat {
        gamma[s] = gamma0[s]
        s += 1usize
    }
    var j = 0usize
    while j < k {
        beta[j] = beta0[j]
        j += 1usize
    }
    s = 0usize
    var t = 0usize
    while s <= ncat {
        gp[s] = gamma[s]
        s += 1usize
    }
    // posterior precision of beta
    var i = 0usize
    while i < k {
        j = 0usize
        while j < k {
            var sm = 0.0f64
            t = 0usize
            while t < n {
                sm += x[t * k + i] * x[t * k + j]
                t += 1usize
            }
            m1[i * k + j] = bb0[i * k + j] + sm
            j += 1usize
        }
        i += 1usize
    }
    var ld = 0.0f64
    if ms.inv_pd(a, m1, k, bn_var, &ld) != ok { ret ms.NotPd }
    if !ms.chol(bn_var, k, cc) { ret ms.NotPd }
    let tv = tune * tune
    var count = 0usize
    var iter = 0usize
    t = 0usize
    while t < n {
        var e = 0.0f64
        i = 0usize
        while i < k {
            e += x[t * k + i] * beta[i]
            i += 1usize
        }
        xb[t] = e
        t += 1usize
    }
    while iter < burnin + mcmc {
        // Cowles step (on X beta as of the previous refresh, which is one draw stale, as in R's C++) for the cut points
        i = 2usize
        while i < ncat {
            if i == ncat - 1usize { gp[i] = md.rtbnorm_combo(g, gamma[i], tv, gp[i - 1usize]) } else { gp[i] = rtnorm_combo(g, gamma[i], tv, gp[i - 1usize], gamma[i + 1usize]) }
            i += 1usize
        }
        var llr = 0.0f64
        t = 0usize
        while t < n {
            let yi = usize(y[t])
            if yi == ncat {
                llr = llr + math.log[f64](1.0f64 - pn(gp[yi - 1usize] - xb[t], 0.0f64, 1.0f64)) - math.log[f64](1.0f64 - pn(gamma[yi - 1usize] - xb[t], 0.0f64, 1.0f64))
            } else {
                if yi == 1usize {
                    llr = llr + math.log[f64](pn(gp[yi] - xb[t], 0.0f64, 1.0f64)) - math.log[f64](pn(gamma[yi] - xb[t], 0.0f64, 1.0f64))
                } else {
                    llr = llr + math.log[f64](pn(gp[yi] - xb[t], 0.0f64, 1.0f64) - pn(gp[yi - 1usize] - xb[t], 0.0f64, 1.0f64)) - math.log[f64](pn(gamma[yi] - xb[t], 0.0f64, 1.0f64) - pn(gamma[yi - 1usize] - xb[t], 0.0f64, 1.0f64))
                }
            }
            t += 1usize
        }
        var lgr = 0.0f64
        j = 2usize
        while j < ncat {
            lgr = lgr + math.log[f64](pn(gamma[j + 1usize], gamma[j], tune) - pn(gp[j - 1usize], gamma[j], tune)) - math.log[f64](pn(gp[j + 1usize], gp[j], tune) - pn(gamma[j - 1usize], gp[j], tune))
            j += 1usize
        }
        if ms.sc_unif(g) <= math.exp[f64](llr + lgr) {
            s = 0usize
            while s <= ncat {
                gamma[s] = gp[s]
                s += 1usize
            }
        }
        // latent data and beta
        t = 0usize
        while t < n {
            var e = 0.0f64
            i = 0usize
            while i < k {
                e += x[t * k + i] * beta[i]
                i += 1usize
            }
            xb[t] = e
            t += 1usize
        }
        t = 0usize
        while t < n {
            let yi = usize(y[t])
            zv[t] = rtnorm_combo(g, xb[t], 1.0f64, gamma[yi - 1usize], gamma[yi])
            t += 1usize
        }
        i = 0usize
        while i < k {
            var sm = 0.0f64
            j = 0usize
            while j < k {
                sm += bb0[i * k + j] * b0[j]
                j += 1usize
            }
            t = 0usize
            while t < n {
                sm += x[t * k + i] * zv[t]
                t += 1usize
            }
            rhs[i] = sm
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sm = 0.0f64
            j = 0usize
            while j < k {
                sm += bn_var[i * k + j] * rhs[j]
                j += 1usize
            }
            m1[i] = sm
            zz[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sm = m1[i]
            j = 0usize
            while j <= i {
                sm += cc[i * k + j] * zz[j]
                j += 1usize
            }
            beta[i] = sm
            i += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            j = 0usize
            while j < k {
                out[count * width + j] = beta[j]
                j += 1usize
            }
            j = 2usize
            while j < ncat {
                out[count * width + k + j - 2usize] = gamma[j]
                j += 1usize
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}
