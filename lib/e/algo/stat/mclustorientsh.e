// R mclust: me() for EVE, VEE and VVE with the shared orientation matrix of parameters$variance$orientation, and the sim parameters read off it.
//
// EVE and VVE keep the orientation of the MM steps of the Fortran (polar factors, sign free) in the state of the EM, mclustem copies it out through info[4..];
// VEE takes it from svd(C) of the common shape matrix C = Sigma_k / det(Sigma_k)^(1/p) at the R level (La.svd), shape = its singular values.
// Outputs follow mclustsim.sim_draw: orient (p by p, columns the directions), scale (g) and shape (p g for EVE and VVE, p for VEE).

use e.math
use e.mem
use e.algo.linalg.lapack_gesdd as lapack
use e.algo.stat.mclustem as em
use e.algo.stat.mclustpkg as mp

// z (n by g) is replaced by the final memberships; returns the log likelihood (NaN on failure), info 0 the iterations
fn me_shared(a: *mem.Arena, model: usize, x: []const f64, z: []f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, sigma: []f64, scale: []f64, shape: []f64, orient: []f64, info: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let pq = p * p
    let (inf, e1) = mem.alloc[f64](a, 4usize + pq)
    let (sv, e2) = mem.alloc[f64](a, p)
    let (u, e3) = mem.alloc[f64](a, pq)
    let (vt, e4) = mem.alloc[f64](a, pq)
    let (cm, e5) = mem.alloc[f64](a, pq)
    let (l, e6) = mem.alloc[f64](a, pq)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan }
    let hood = em.me_any(a, model, false, x, z, n, p, g, pro, mu, sigma, inf)
    if hood != hood { ret hood }
    info[0usize] = inf[0usize]
    var k = 0usize
    var j = 0usize
    if model == 10usize {
        k = 0usize
        while k < g {
            if !mp.chol_lower(sigma[k * pq..k * pq + pq], p, l) { ret nan }
            var ld = 0.0f64
            j = 0usize
            while j < p {
                ld += 2.0f64 * math.log[f64](l[j * p + j])
                j += 1usize
            }
            scale[k] = math.exp[f64](ld / f64(p))
            k += 1usize
        }
        j = 0usize
        while j < pq {
            cm[j] = sigma[j] / scale[0usize]
            j += 1usize
        }
        if lapack.svd_all(a, cm, p, p, sv, u, vt) != ok { ret nan }
        j = 0usize
        while j < p {
            shape[j] = sv[j]
            var r = 0usize
            while r < p {
                orient[j * p + r] = vt[r * p + j]
                r += 1usize
            }
            j += 1usize
        }
        ret hood
    }
    // EVE, VVE: orientation = t(om)
    var c = 0usize
    while c < p {
        var r = 0usize
        while r < p {
            orient[c * p + r] = inf[4usize + r * p + c]
            r += 1usize
        }
        c += 1usize
    }
    k = 0usize
    while k < g {
        scale[k] = 1.0f64
        j = 0usize
        while j < p {
            var s = 0.0f64
            var b = 0usize
            while b < p {
                var d = 0usize
                while d < p {
                    s += orient[j * p + b] * sigma[k * pq + d * p + b] * orient[j * p + d]
                    d += 1usize
                }
                b += 1usize
            }
            shape[k * p + j] = s
            j += 1usize
        }
        k += 1usize
    }
    ret hood
}
