// R mcmc::metrop: the random-walk Metropolis sampler, batch means of the states taken every nspac proposals (blen per batch), proposals current + scale * rnorm, an uphill move accepted without drawing a uniform and a downhill one by `u < exp(delta)` with u drawn only then, as the package's C code does. The log unnormalised density is one of a fixed set (no user functions here).
//
// Not here: user-supplied densities and output functions, morph, temper, initseq and the other samplers of the package.

use e.algo.rand.r as rng
use e.math
use e.mem

// target 0 standard normal, 1 -x^2/2 - x^4/10 per sum, 2 Laplace
fn lud(id: usize, x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if id == 0usize { s += 0.0f64 - 0.5f64 * x[i] * x[i] }
        if id == 1usize { s += 0.0f64 - 0.5f64 * x[i] * x[i] - 0.1f64 * x[i] * x[i] * x[i] * x[i] }
        if id == 2usize { s += 0.0f64 - math.abs[f64](x[i]) }
        i += 1usize
    }
    ret s
}

// metrop(lud, initial, nbatch, blen, nspac, scale): batch (nbatch by d, row-major), the acceptance rate of each batch and the final state
fn metrop(a: *mem.Arena, g: *rng.Rng, id: usize, initial: []const f64, nbatch: usize, blen: usize, nspac: usize, scale: []const f64, batch: []f64, accb: []f64, fin: []f64) -> err {
    let d = initial.len
    let (cur, e1) = mem.alloc[f64](a, d)
    let (prop, e2) = mem.alloc[f64](a, d)
    let (sum, e3) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < d {
        cur[i] = initial[i]
        i += 1usize
    }
    var lc = lud(id, cur)
    var ib = 0usize
    while ib < nbatch {
        i = 0usize
        while i < d {
            sum[i] = 0.0f64
            i += 1usize
        }
        var nacc = 0usize
        var jb = 0usize
        while jb < blen {
            var is = 0usize
            while is < nspac {
                i = 0usize
                while i < d {
                    prop[i] = cur[i] + scale[i] * rng.rnorm(g, 0.0f64, 1.0f64)
                    i += 1usize
                }
                let lp = lud(id, prop)
                var accept = false
                if lp >= lc { accept = true } else {
                    let u = rng.unif(g)
                    if u < math.exp[f64](lp - lc) { accept = true }
                }
                if accept {
                    i = 0usize
                    while i < d {
                        cur[i] = prop[i]
                        i += 1usize
                    }
                    lc = lp
                    nacc += 1usize
                }
                is += 1usize
            }
            i = 0usize
            while i < d {
                sum[i] += cur[i]
                i += 1usize
            }
            jb += 1usize
        }
        i = 0usize
        while i < d {
            batch[ib * d + i] = sum[i] / f64(blen)
            i += 1usize
        }
        accb[ib] = f64(nacc) / f64(blen * nspac)
        ib += 1usize
    }
    i = 0usize
    while i < d {
        fin[i] = cur[i]
        i += 1usize
    }
    ret ok
}
