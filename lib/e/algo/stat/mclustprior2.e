// R mclust: the conjugate-prior M step (msXXp) and EM (meXXp of mclust.f) for EEI, VEI, EVI, VVI, EEV and VEV.
//
// The standalone M step and the EM step of mclust differ in the Fortran (the EEI, EVI and EEV denominators, EEV standalone drops the shrinkage), so as_me picks the version.
// EVE, VEE, VVE and EVV have no prior in mclust. pscale is the scalar in [0] for EEI, VEI, EVI, VVI and the p by p matrix for EEV and VEV.
// st (g + p) holds the scale and shape of VEI and VEV, warm started from one EM iteration to the next.

use e.math
use e.mem
use e.algo.stat.ica as ica
use e.algo.stat.mclustem as em

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

// true when the model has a prior version handled here
fn handles(model: usize) -> bool {
    ret model == 4usize || model == 5usize || model == 6usize || model == 7usize || model == 12usize || model == 13usize
}

fn pos_min(v: []const f64, m: usize) -> bool {
    var j = 0usize
    while j < m {
        if !(v[j] > 0.0f64) { ret false }
        j += 1usize
    }
    ret true
}

// the M step from z; first starts the VEI and VEV scale and shape afresh. Returns false when it breaks down.
fn mstep2(a: *mem.Arena, model: usize, as_me: bool, first: bool, x: []const f64, z: []const f64, n: usize, p: usize, g: usize, shrk0: f64, pmu: []const f64, pscale: []const f64, pdof: f64, pro: []f64, mu: []f64, sigma: []f64, st: []f64) -> bool {
    let (sumz, e1) = mem.alloc[f64](a, g)
    let (u, e2) = mem.alloc[f64](a, g * p * p)
    let (ev, e3) = mem.alloc[f64](a, g * p)
    let (evec, e4) = mem.alloc[f64](a, g * p * p)
    let (w, e5) = mem.alloc[f64](a, p + g)
    let (shp, e6) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret false }
    var shrk = shrk0
    if shrk < 0.0f64 { shrk = 0.0f64 }
    if model == 12usize && !as_me { shrk = 0.0f64 }
    let nn = f64(n)
    let pp = f64(p)
    let gg = f64(g)
    var extra = 0.0f64
    if shrk > 0.0f64 { extra = 1.0f64 }
    var k = 0usize
    var j = 0usize
    var tz = 0.0f64
    while k < g {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += z[k * n + i]
            i += 1usize
        }
        if !(s > 0.0f64) { ret false }
        sumz[k] = s
        pro[k] = s / nn
        tz += s
        k += 1usize
    }
    em.scatter(x, z, n, p, g, sumz, mu, u)
    // the shrinkage term about the unshrunk mean, then the prior scale
    k = 0usize
    while k < g {
        let ck = sumz[k] * shrk / (sumz[k] + shrk)
        var b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                u[k * p * p + c * p + b] = u[k * p * p + c * p + b] + ck * (pmu[b] - mu[k * p + b]) * (pmu[c] - mu[k * p + c])
                if model == 12usize || model == 13usize {
                    u[k * p * p + c * p + b] = u[k * p * p + c * p + b] + pscale[c * p + b]
                }
                c += 1usize
            }
            if model != 12usize && model != 13usize { u[k * p * p + b * p + b] = u[k * p * p + b * p + b] + pscale[0usize] }
            b += 1usize
        }
        if model != 4usize {
            j = 0usize
            while j < p {
                mu[k * p + j] = (sumz[k] * mu[k * p + j] + shrk * pmu[j]) / (sumz[k] + shrk)
                j += 1usize
            }
        }
        k += 1usize
    }
    k = 0usize
    while k < g * p * p {
        sigma[k] = 0.0f64
        k += 1usize
    }
    let pq = p * p
    if model == 4usize {
        var term = pdof + tz + 2.0f64
        if shrk > 0.0f64 { term += gg }
        if as_me { term = pdof + nn + 1.0f64 + extra }
        j = 0usize
        while j < p {
            var s = 0.0f64 - (gg - 1.0f64) * pscale[0usize]
            k = 0usize
            while k < g {
                s += u[k * pq + j * p + j]
                k += 1usize
            }
            if !(s > 0.0f64) { ret false }
            k = 0usize
            while k < g {
                sigma[k * pq + j * p + j] = s / term
                k += 1usize
            }
            j += 1usize
        }
    } else if model == 7usize {
        k = 0usize
        while k < g {
            j = 0usize
            while j < p {
                let d = u[k * pq + j * p + j]
                if !(d > 0.0f64) { ret false }
                sigma[k * pq + j * p + j] = d / (sumz[k] + pdof + 2.0f64 + extra)
                j += 1usize
            }
            k += 1usize
        }
    } else if model == 6usize {
        var term = pdof + tz + 2.0f64
        if shrk > 0.0f64 { term += gg }
        if as_me { term = pdof + nn + 1.0f64 + extra }
        var gs = 0.0f64
        k = 0usize
        while k < g {
            j = 0usize
            while j < p {
                w[j] = u[k * pq + j * p + j]
                j += 1usize
            }
            if !pos_min(w, p) { ret false }
            let gk = em.geo_mean(w, p)
            ev[k] = gk
            gs += gk
            k += 1usize
        }
        k = 0usize
        while k < g {
            j = 0usize
            while j < p {
                sigma[k * pq + j * p + j] = u[k * pq + j * p + j] / ev[k] * gs / term
                j += 1usize
            }
            k += 1usize
        }
    } else if model == 5usize {
        // VEI: scale (g) and shape (p) by alternating, warm started
        if first {
            k = 0usize
            while k < g + p {
                st[k] = 1.0f64
                k += 1usize
            }
        }
        var tmp = pdof + 2.0f64 + extra
        var inner = 0usize
        var again = true
        while again {
            if !pos_min(st[g..g + p], p) { ret false }
            inner += 1usize
            k = 0usize
            while k < g {
                w[p + k] = st[k]
                var s = 0.0f64
                j = 0usize
                while j < p {
                    s += u[k * pq + j * p + j] / st[g + j]
                    j += 1usize
                }
                st[k] = s / (sumz[k] * pp + tmp)
                k += 1usize
            }
            if !pos_min(st, g) { ret false }
            j = 0usize
            while j < p {
                w[j] = st[g + j]
                var s = 0.0f64
                k = 0usize
                while k < g {
                    s += u[k * pq + j * p + j] / st[k]
                    k += 1usize
                }
                st[g + j] = s
                j += 1usize
            }
            if !pos_min(st[g..g + p], p) { ret false }
            let gm = em.geo_mean(st[g..g + p], p)
            j = 0usize
            while j < p {
                st[g + j] = st[g + j] / gm
                j += 1usize
            }
            var erv = 0.0f64
            k = 0usize
            while k < g {
                let d = math.abs[f64](w[p + k] - st[k]) / (1.0f64 + st[k])
                if d > erv { erv = d }
                k += 1usize
            }
            j = 0usize
            while j < p {
                let d = math.abs[f64](w[j] - st[g + j]) / (1.0f64 + st[g + j])
                if d > erv { erv = d }
                j += 1usize
            }
            again = erv > 1.4901161193847656e-8f64 && inner <= 2147483647usize
        }
        k = 0usize
        while k < g {
            j = 0usize
            while j < p {
                sigma[k * pq + j * p + j] = st[k] * st[g + j]
                j += 1usize
            }
            k += 1usize
        }
    } else {
        // EEV and VEV: eigenvalues and eigenvectors of every scatter matrix
        k = 0usize
        while k < g {
            let (vals, vecs, ee) = ica.eigen_sym(a, u[k * pq..k * pq + pq], p)
            if ee != ok { ret false }
            j = 0usize
            while j < p {
                ev[k * p + j] = vals[j]
                var q = 0usize
                while q < p {
                    evec[k * pq + j * p + q] = vecs[q * p + j]
                    q += 1usize
                }
                j += 1usize
            }
            k += 1usize
        }
        j = 0usize
        while j < p {
            var s = 0.0f64
            k = 0usize
            while k < g {
                s += ev[k * p + j]
                k += 1usize
            }
            shp[j] = s
            j += 1usize
        }
        if !pos_min(shp, p) { ret false }
        if model == 12usize {
            var term = pdof + pp + 1.0f64 + tz
            if as_me { term = pdof + pp + 1.0f64 + extra + nn }
            k = 0usize
            while k < g {
                var b = 0usize
                while b < p {
                    var c = 0usize
                    while c < p {
                        var s = 0.0f64
                        j = 0usize
                        while j < p {
                            s += evec[k * pq + j * p + b] * shp[j] * evec[k * pq + j * p + c]
                            j += 1usize
                        }
                        sigma[k * pq + c * p + b] = s / term
                        c += 1usize
                    }
                    b += 1usize
                }
                k += 1usize
            }
        } else {
            if first {
                let gm = em.geo_mean(shp, p)
                k = 0usize
                while k < g {
                    st[k] = gm / sumz[k]
                    k += 1usize
                }
                j = 0usize
                while j < p {
                    st[g + j] = shp[j] / gm
                    j += 1usize
                }
            }
            var inner = 0usize
            var again = true
            while again {
                j = 0usize
                while j < p {
                    w[j] = st[g + j]
                    shp[j] = 0.0f64
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    w[p + k] = st[k]
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += ev[k * p + j] / w[j]
                        j += 1usize
                    }
                    st[k] = s / (sumz[k] * pp)
                    if !(st[k] > 0.0f64) { ret false }
                    j = 0usize
                    while j < p {
                        shp[j] = shp[j] + ev[k * p + j] / st[k]
                        j += 1usize
                    }
                    k += 1usize
                }
                inner += 1usize
                if !pos_min(shp, p) { ret false }
                let gm = em.geo_mean(shp, p)
                j = 0usize
                while j < p {
                    st[g + j] = shp[j] / gm
                    j += 1usize
                }
                var erv = 0.0f64
                j = 0usize
                while j < p {
                    let d = math.abs[f64](w[j] - st[g + j]) / (1.0f64 + st[g + j])
                    if d > erv { erv = d }
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    let d = math.abs[f64](st[k] - w[p + k]) / (1.0f64 + st[k])
                    if d > erv { erv = d }
                    k += 1usize
                }
                again = erv >= 1.4901161193847656e-8f64 && inner < 2147483647usize
            }
            k = 0usize
            while k < g {
                var b = 0usize
                while b < p {
                    var c = 0usize
                    while c < p {
                        var s = 0.0f64
                        j = 0usize
                        while j < p {
                            s += evec[k * pq + j * p + b] * st[g + j] * evec[k * pq + j * p + c]
                            j += 1usize
                        }
                        sigma[k * pq + c * p + b] = st[k] * s
                        c += 1usize
                    }
                    b += 1usize
                }
                k += 1usize
            }
        }
    }
    ret true
}

// mstep(data, modelName, z, prior) for the models handled here
fn mstep_prior2(a: *mem.Arena, model: usize, x: []const f64, z: []const f64, n: usize, p: usize, g: usize, shrk: f64, pmu: []const f64, pscale: []const f64, pdof: f64, pro: []f64, mu: []f64, sigma: []f64) -> err {
    let (st, e1) = mem.alloc[f64](a, g + p)
    if e1 != ok { ret mem.Full }
    if !mstep2(a, model, false, true, x, z, n, p, g, shrk, pmu, pscale, pdof, pro, mu, sigma, st) { ret mem.Full }
    ret ok
}

// me(data, modelName, z, prior): EM with the prior M step; the log likelihood (NaN on failure), info 0 the iterations
fn me_prior2(a: *mem.Arena, model: usize, x: []const f64, z: []f64, n: usize, p: usize, g: usize, shrk: f64, pmu: []const f64, pscale: []const f64, pdof: f64, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    let (st, e1) = mem.alloc[f64](a, g + p)
    if e1 != ok { ret nanv() }
    var hold = 8.0e307f64
    var iter = 0usize
    while true {
        iter += 1usize
        let it0 = mem.mark(a)
        if !mstep2(a, model, true, iter == 1usize, x, z, n, p, g, shrk, pmu, pscale, pdof, pro, mu, sigma, st) { ret nanv() }
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
    ret nanv()
}
