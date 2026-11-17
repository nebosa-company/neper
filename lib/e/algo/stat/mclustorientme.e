// R mclust: me() for EEV, VEV and EVV with the orientation matrices of the last M step (what me returns in parameters$variance$orientation).
//
// The orientation comes from the memberships the last M step ran on: EEV and EVV loop the M step and E step here (no state between iterations), VEV reruns the
// EM of mclustem with the iteration count capped at one less to get them. Outputs as mclustorient.orient_params plus pro, mu and sigma of the fit.

use e.math
use e.mem
use e.algo.stat.mclustem as em
use e.algo.stat.mclustorient as mo

// z (n by g) is replaced by the final memberships; returns the log likelihood (NaN on failure), info 0 the iterations
fn me_orient(a: *mem.Arena, model: usize, x: []const f64, z: []f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, sigma: []f64, scale: []f64, shape: []f64, orient: []f64, info: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let (zp, e1) = mem.alloc[f64](a, n * g)
    let (inf, e2) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok { ret nan }
    let (zq, e9) = mem.alloc[f64](a, n * g)
    if e9 != ok { ret nan }
    var q = 0usize
    if model == 13usize {
        // run once for the iteration count, then to one iteration less for the memberships of the last M step
        let (z0, e3) = mem.alloc[f64](a, n * g)
        if e3 != ok { ret nan }
        while q < n * g {
            zp[q] = z[q]
            z0[q] = z[q]
            q += 1usize
        }
        let hood = em.me_any(a, model, false, x, z, n, p, g, pro, mu, sigma, inf)
        if hood != hood { ret hood }
        let it = usize(inf[0usize])
        info[0usize] = f64(it)
        if it >= 2usize {
            let (pro2, e4) = mem.alloc[f64](a, g)
            let (mu2, e5) = mem.alloc[f64](a, g * p)
            let (sg2, e6) = mem.alloc[f64](a, g * p * p)
            if e4 != ok || e5 != ok || e6 != ok { ret nan }
            let tol_in = math.sqrt[f64](2.220446049250313e-16f64)
            let h2 = em.me_gen(a, model, false, x, z0, n, p, g, 1.0e-5f64, tol_in, it - 1usize, 2147483647usize, 2.220446049250313e-16f64, false, pro2, mu2, sg2, inf)
            if h2 != h2 { ret nan }
            q = 0usize
            while q < n * g {
                zp[q] = z0[q]
                q += 1usize
            }
        }
        if mo.orient_from(a, model, x, zp, n, p, g, mu, sigma, scale, shape, orient) != ok { ret nan }
        ret hood
    }
    var hold = 8.0e307f64
    var iter = 0usize
    while true {
        iter += 1usize
        q = 0usize
        while q < n * g {
            zp[q] = z[q]
            zq[q] = z[q]
            q += 1usize
        }
        let mh = em.mstep_any(a, model, x, zp, n, p, g, pro, mu, sigma, inf)
        if mh != mh { ret nan }
        let hood = em.estep_gen(a, x, n, p, g, mu, sigma, pro, z)
        if hood != hood { ret hood }
        let err1 = math.abs[f64](hold - hood) / (1.0f64 + math.abs[f64](hood))
        hold = hood
        if err1 <= 1.0e-5f64 {
            info[0usize] = f64(iter)
            if mo.orient_from(a, model, x, zq, n, p, g, mu, sigma, scale, shape, orient) != ok { ret nan }
            ret hood
        }
    }
    ret nan
}
