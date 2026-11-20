// R MCMCpack::MCMCirt1d: the one-dimensional item response (ideal point) model by Gibbs sampling, on the Scythe Mersenne-Twister stream
// (data augmentation Z, item parameters eta = (alpha, beta), subject abilities theta with equality and sign constraints).
//
// Not here: the start values R derives from the data (the caller hands them over), and the other IRT samplers.

use e.algo.stat.mcmcpackdraw as md
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.mem

// x is J by K row-major with 1, 0 or anything else for missing; eq[j] is -999 when theta[j] is free, ineq[j] > 0 or < 0 is a sign constraint.
// out is nsamp rows of (theta[J], then (alpha, beta) per item) when both stores are asked for
fn irt1d(a: *mem.Arena, g: *ms.Sc, x: []const f64, jn: usize, kn: usize, theta0: []const f64, alpha0: []const f64, beta0: []const f64, t0: f64, tt0: f64, ab0: []const f64, abb0: []const f64, eq: []const f64, ineq: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64) -> err {
    let (theta, e1) = mem.alloc[f64](a, jn)
    let (eta, e2) = mem.alloc[f64](a, kn * 2usize)
    let (z, e3) = mem.alloc[f64](a, jn * kn)
    let (tpt, e4) = mem.alloc[f64](a, 4usize)
    let (pv, e5) = mem.alloc[f64](a, 4usize)
    let (pc, e6) = mem.alloc[f64](a, 4usize)
    let (abab, e7) = mem.alloc[f64](a, 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var j = 0usize
    while j < jn {
        theta[j] = theta0[j]
        j += 1usize
    }
    var k = 0usize
    while k < kn {
        eta[k * 2usize] = alpha0[k]
        eta[k * 2usize + 1usize] = beta0[k]
        k += 1usize
    }
    abab[0usize] = abb0[0usize] * ab0[0usize] + abb0[1usize] * ab0[1usize]
    abab[1usize] = abb0[2usize] * ab0[0usize] + abb0[3usize] * ab0[1usize]
    let t0tt = tt0 * t0
    var ld = 0.0f64
    var count = 0usize
    var iter = 0usize
    let width = jn + 2usize * kn
    while iter < burnin + mcmc {
        // latent utilities
        j = 0usize
        while j < jn {
            k = 0usize
            while k < kn {
                let zm = -eta[k * 2usize] + theta[j] * eta[k * 2usize + 1usize]
                let xv = x[j * kn + k]
                if xv == 1.0f64 { z[j * kn + k] = md.rtbnorm_combo(g, zm, 1.0f64, 0.0f64) } else {
                    if xv == 0.0f64 { z[j * kn + k] = md.rtanorm_combo(g, zm, 1.0f64, 0.0f64) } else { z[j * kn + k] = ms.sc_rnorm(g, zm, 1.0f64) }
                }
                k += 1usize
            }
            j += 1usize
        }
        // item parameters
        var s1 = 0.0f64
        var s2 = 0.0f64
        j = 0usize
        while j < jn {
            s1 -= theta[j]
            s2 += math.pow[f64](theta[j], 2.0f64)
            j += 1usize
        }
        tpt[0usize] = f64(jn) + abb0[0usize]
        tpt[1usize] = s1 + abb0[1usize]
        tpt[2usize] = s1 + abb0[2usize]
        tpt[3usize] = s2 + abb0[3usize]
        if ms.inv_pd(a, tpt, 2usize, pv, &ld) != ok { ret ms.NotPd }
        if !ms.chol(pv, 2usize, pc) { ret ms.NotPd }
        k = 0usize
        while k < kn {
            var tz0 = 0.0f64
            var tz1 = 0.0f64
            j = 0usize
            while j < jn {
                tz0 -= z[j * kn + k]
                tz1 += z[j * kn + k] * theta[j]
                j += 1usize
            }
            let r0 = tz0 + abab[0usize]
            let r1 = tz1 + abab[1usize]
            let m0 = pv[0usize] * r0 + pv[1usize] * r1
            let m1 = pv[2usize] * r0 + pv[3usize] * r1
            let n0 = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            let n1 = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            eta[k * 2usize] = pc[0usize] * n0 + pc[1usize] * n1 + m0
            eta[k * 2usize + 1usize] = pc[2usize] * n0 + pc[3usize] * n1 + m1
            k += 1usize
        }
        // abilities
        var tv = tt0
        k = 0usize
        while k < kn {
            tv += math.pow[f64](eta[k * 2usize + 1usize], 2.0f64)
            k += 1usize
        }
        tv = 1.0f64 / tv
        let tsd = math.sqrt[f64](tv)
        j = 0usize
        while j < jn {
            if eq[j] == -999.0f64 {
                var bz = 0.0f64
                k = 0usize
                while k < kn {
                    bz += eta[k * 2usize + 1usize] * (z[j * kn + k] + eta[k * 2usize])
                    k += 1usize
                }
                let tm = tv * (t0tt + bz)
                if ineq[j] == 0.0f64 { theta[j] = tm + ms.sc_rnorm(g, 0.0f64, tsd) } else {
                    if ineq[j] > 0.0f64 { theta[j] = md.rtbnorm_combo(g, tm, tv, 0.0f64) } else { theta[j] = md.rtanorm_combo(g, tm, tv, 0.0f64) }
                }
            } else {
                theta[j] = eq[j]
            }
            j += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            j = 0usize
            while j < jn {
                out[count * width + j] = theta[j]
                j += 1usize
            }
            k = 0usize
            while k < 2usize * kn {
                out[count * width + jn + k] = eta[k]
                k += 1usize
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}
