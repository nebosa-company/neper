// R mclust: the orientation matrices of the M step of EEV, VEV and EVV with the sign convention of the compiled package.
//
// mclust gets them from dgesvd('N', 'O') (lapack_gesvd): of the triangular factor of the Givens rotations of the weighted rows sqrt(z) (x - mu) for EEV and VEV (observation order),
// of the scatter matrix sum w w' for EVV. The columns of orient[,,k] are the right singular vectors; the variance parameters are read off the M step covariances in that basis.

use e.math
use e.mem
use e.algo.linalg.lapack_gesvd as gsv
use e.algo.stat.mclustem as em
use e.algo.stat.mclustpkg as mp

// mstep of the model (12 EEV, 13 VEV, 14 EVV) from z: pro (g), mu (p by g, mu[k p + j]), and the sim parameters
// scale (g), shape (p g), orient (g stacked p by p) laid out the way mclustsim.sim_draw reads them
fn orient_params(a: *mem.Arena, model: usize, x: []const f64, z: []const f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, scale: []f64, shape: []f64, orient: []f64) -> err {
    let pq = p * p
    let (zz, e1) = mem.alloc[f64](a, n * g)
    let (sigma, e2) = mem.alloc[f64](a, g * pq)
    let (inf, e3) = mem.alloc[f64](a, 4usize)
    let (r, e4) = mem.alloc[f64](a, pq)
    let (w, e5) = mem.alloc[f64](a, p)
    let (sv, e6) = mem.alloc[f64](a, p)
    let (vt, e7) = mem.alloc[f64](a, pq)
    let (ev, e8) = mem.alloc[f64](a, g * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var q = 0usize
    while q < n * g {
        zz[q] = z[q]
        q += 1usize
    }
    let mh = em.mstep_any(a, model, x, zz, n, p, g, pro, mu, sigma, inf)
    if mh != mh { ret mem.Full }
    ret orient_from(a, model, x, z, n, p, g, mu, sigma, scale, shape, orient)
}

// the orientation and sim parameters for the covariances sigma and means mu of an M step taken from z
fn orient_from(a: *mem.Arena, model: usize, x: []const f64, z: []const f64, n: usize, p: usize, g: usize, mu: []const f64, sigma: []const f64, scale: []f64, shape: []f64, orient: []f64) -> err {
    let pq = p * p
    let (r, e4) = mem.alloc[f64](a, pq)
    let (w, e5) = mem.alloc[f64](a, p)
    let (sv, e6) = mem.alloc[f64](a, p)
    let (vt, e7) = mem.alloc[f64](a, pq)
    let (ev, e8) = mem.alloc[f64](a, g * p)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var q = 0usize
    var k = 0usize
    while k < g {
        q = 0usize
        while q < pq {
            r[q] = 0.0f64
            q += 1usize
        }
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < p {
                w[j] = (x[j * n + i] - mu[k * p + j]) * math.sqrt[f64](z[k * n + i])
                j += 1usize
            }
            if model == 14usize {
                // dger: the scatter matrix
                var b = 0usize
                while b < p {
                    var c = 0usize
                    while c < p {
                        r[c * p + b] = r[c * p + b] + w[b] * w[c]
                        c += 1usize
                    }
                    b += 1usize
                }
            } else {
                j = 0usize
                while j + 1usize < p {
                    let (c, sn, rr) = mp.rotg_classic(r[j * p + j], w[j])
                    r[j * p + j] = rr
                    var t = j + 1usize
                    while t < p {
                        let xv = r[t * p + j]
                        let yv = w[t]
                        r[t * p + j] = c * xv + sn * yv
                        w[t] = c * yv - sn * xv
                        t += 1usize
                    }
                    j += 1usize
                }
                let (c2, s2, r2) = mp.rotg_classic(r[(p - 1usize) * p + (p - 1usize)], w[p - 1usize])
                r[(p - 1usize) * p + (p - 1usize)] = r2
            }
            i += 1usize
        }
        if gsv.gesvd_no(a, r, p, sv, vt) != ok { ret mem.Full }
        // orientation[,,k] = t(vt): column j is the j-th right singular vector (row j of vt)
        var b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                orient[k * pq + c * p + b] = vt[b * p + c]
                c += 1usize
            }
            b += 1usize
        }
        // the variance along every direction: v' Sigma_k v
        var j = 0usize
        while j < p {
            var s = 0.0f64
            b = 0usize
            while b < p {
                var c = 0usize
                while c < p {
                    s += orient[k * pq + j * p + b] * sigma[k * pq + c * p + b] * orient[k * pq + j * p + c]
                    c += 1usize
                }
                b += 1usize
            }
            ev[k * p + j] = s
            j += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < g {
        scale[k] = 1.0f64
        k += 1usize
    }
    var j = 0usize
    while j < p {
        shape[j] = ev[j]
        j += 1usize
    }
    if model == 14usize {
        k = 0usize
        while k < g {
            j = 0usize
            while j < p {
                shape[k * p + j] = ev[k * p + j]
                j += 1usize
            }
            k += 1usize
        }
    }
    if model == 13usize {
        k = 0usize
        while k < g {
            scale[k] = ev[k * p]
            k += 1usize
        }
        j = 0usize
        while j < p {
            shape[j] = ev[j] / ev[0usize]
            j += 1usize
        }
    }
    ret ok
}
