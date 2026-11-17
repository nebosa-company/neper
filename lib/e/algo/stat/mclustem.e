// R mclust: the EM fits of the covariance structures the first module leaves out (VEI, VEV, EVE, VEE, VVE), written from mclust.f and mclust2.f.
//
// Layouts follow R: x is n by p, z is n by g, means are p by g and covariances are g stacked p by p matrices, all column-major.
// me_any covers every model name by sending the older structures to e.algo.stat.mclustpkg.

use e.math
use e.mem
use e.algo.stat.ica as ica
use e.algo.stat.mclustpkg as mp
use e.algo.linalg.lapack_gesdd as lapack

fn big() -> f64 { ret 1.0e308f64 }

// c = x * y for p by p column-major matrices
fn matmul(x: []const f64, y: []const f64, p: usize, c: []f64) {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            var s = 0.0f64
            var t = 0usize
            while t < p {
                s += x[t * p + i] * y[j * p + t]
                t += 1usize
            }
            c[j * p + i] = s
            i += 1usize
        }
        j += 1usize
    }
}

fn transpose_sq(m: []f64, p: usize) {
    var j = 0usize
    while j < p {
        var i = j + 1usize
        while i < p {
            let t = m[j * p + i]
            m[j * p + i] = m[i * p + j]
            m[i * p + j] = t
            i += 1usize
        }
        j += 1usize
    }
}

// the orthogonal factor u vt of the singular value decomposition of f (p by p)
fn polar(a: *mem.Arena, f: []const f64, p: usize, o: []f64) -> err {
    let start = mem.mark(a)
    let (s, e1) = mem.alloc[f64](a, p)
    let (u, e2) = mem.alloc[f64](a, p * p)
    let (vt, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let e = lapack.svd_all(a, f, p, p, s, u, vt)
    if e != ok { ret e }
    matmul(u, vt, p, o)
    mem.reset(a, start)
    ret ok
}

// the log of the geometric mean of the entries
fn geo_mean(v: []const f64, m: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < m {
        s += math.log[f64](v[j])
        j += 1usize
    }
    ret math.exp[f64](s / f64(m))
}

fn min_of(v: []const f64, m: usize) -> f64 {
    var s = v[0usize]
    var j = 1usize
    while j < m {
        if v[j] < s { s = v[j] }
        j += 1usize
    }
    ret s
}

// the E step for the covariances sigma: fills z with the memberships and returns the log likelihood (NaN when a covariance is not positive definite)
fn estep_gen(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, mu: []const f64, sigma: []const f64, pro: []const f64, z: []f64) -> f64 {
    let start = mem.mark(a)
    let (lall, e1) = mem.alloc[f64](a, g * p * p)
    let (ld, e2) = mem.alloc[f64](a, g)
    let (dv, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < g {
        if !mp.chol_lower(sigma[k * p * p..k * p * p + p * p], p, lall[k * p * p..k * p * p + p * p]) {
            mem.reset(a, start)
            ret 0.0f64 / 0.0f64
        }
        var s = 0.0f64
        var q = 0usize
        while q < p {
            s += 2.0f64 * math.log[f64](lall[k * p * p + q * p + q])
            q += 1usize
        }
        ld[k] = s
        k += 1usize
    }
    let log2pi = 1.837877066409345f64
    var hood = 0.0f64
    var i = 0usize
    while i < n {
        var tmax = 0.0f64 - 1.0e308f64
        k = 0usize
        while k < g {
            var q = 0usize
            var maha = 0.0f64
            while q < p {
                var v = x[q * n + i] - mu[k * p + q]
                var t = 0usize
                while t < q {
                    v -= lall[k * p * p + t * p + q] * dv[t]
                    t += 1usize
                }
                dv[q] = v / lall[k * p * p + q * p + q]
                maha += dv[q] * dv[q]
                q += 1usize
            }
            var lz = 0.0f64 - 1.0e308f64
            if pro[k] != 0.0f64 {
                lz = math.log[f64](pro[k]) - 0.5f64 * (f64(p) * log2pi + ld[k] + maha)
            }
            z[k * n + i] = lz
            if lz > tmax { tmax = lz }
            k += 1usize
        }
        var sum = 0.0f64
        k = 0usize
        while k < g {
            var e = 0.0f64
            if pro[k] != 0.0f64 { e = math.exp[f64](z[k * n + i] - tmax) }
            z[k * n + i] = e
            sum += e
            k += 1usize
        }
        hood += math.log[f64](sum) + tmax
        k = 0usize
        while k < g {
            z[k * n + i] = z[k * n + i] / sum
            k += 1usize
        }
        i += 1usize
    }
    mem.reset(a, start)
    ret hood
}

// the means and the weighted scatter matrices u of every group from z, dividing by sumz
fn scatter(x: []const f64, z: []const f64, n: usize, p: usize, g: usize, sumz: []const f64, mu: []f64, u: []f64) {
    var k = 0usize
    while k < g {
        var j = 0usize
        while j < p {
            var m = 0.0f64
            var i = 0usize
            while i < n {
                m += x[j * n + i] * z[k * n + i]
                i += 1usize
            }
            mu[k * p + j] = m / sumz[k]
            j += 1usize
        }
        var b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                var s = 0.0f64
                var i = 0usize
                while i < n {
                    s += z[k * n + i] * (x[c * n + i] - mu[k * p + c]) * (x[b * n + i] - mu[k * p + b])
                    i += 1usize
                }
                u[k * p * p + b * p + c] = s
                c += 1usize
            }
            b += 1usize
        }
        k += 1usize
    }
}

// me(data, modelName, z) for VEI (5), VEV (13), EVE (9), VEE (10) and VVE (11), codes from the package table; no noise component and no prior.
// z is replaced by the final memberships; pro (g), mu (p by g), sigma (g stacked p by p) hold the fit. info: 0 iterations, 1 final error, 2 the largest inner iteration count, 3 the last inner error.
// Returns the log likelihood, NaN when the fit breaks down.
fn me_gen(a: *mem.Arena, model: usize, eqpro: bool, x: []const f64, z: []f64, n: usize, p: usize, g: usize, tol_out: f64, tol_in: f64, itmax_out: usize, itmax_in: usize, eps: f64, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let (sumz, e1) = mem.alloc[f64](a, g)
    let (u, e2) = mem.alloc[f64](a, g * p * p)
    let (scale, e3) = mem.alloc[f64](a, g)
    let (shape, e4) = mem.alloc[f64](a, p * g)
    let (om, e5) = mem.alloc[f64](a, p * p)
    let (t1, e6) = mem.alloc[f64](a, p * p)
    let (t2, e7) = mem.alloc[f64](a, p * p)
    let (t3, e8) = mem.alloc[f64](a, p * p)
    let (omega, e9) = mem.alloc[f64](a, g)
    let (ev, e10) = mem.alloc[f64](a, p * g)
    let (evec, e11) = mem.alloc[f64](a, g * p * p)
    let (w, e12) = mem.alloc[f64](a, p + g)
    let (shp, e13) = mem.alloc[f64](a, p)
    let (cm, e14) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret nan }
    let rteps = math.sqrt[f64](eps)
    let nn = f64(n)
    let pp = f64(p)
    let gg = f64(g)
    let fam2 = model == 9usize || model == 10usize || model == 11usize
    var hold = big() / 2.0f64
    var iter = 0usize
    var inmax = 0usize
    var errin = big()
    var errv = big()
    var hood = 0.0f64
    var j = 0usize
    var k = 0usize
    j = 0usize
    while j < p * g {
        shape[j] = 1.0f64
        j += 1usize
    }
    j = 0usize
    while j < g {
        scale[j] = 1.0f64
        j += 1usize
    }
    j = 0usize
    while j < p * p {
        om[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        om[j * p + j] = 1.0f64
        shp[j] = 1.0f64
        j += 1usize
    }
    var eqscale = 1.0f64
    while true {
        iter += 1usize
        let it0 = mem.mark(a)
        k = 0usize
        while k < g {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += z[k * n + i]
                i += 1usize
            }
            sumz[k] = s
            pro[k] = s / nn
            if eqpro { pro[k] = 1.0f64 / gg }
            if fam2 && eqpro { sumz[k] = nn / gg }
            k += 1usize
        }
        scatter(x, z, n, p, g, sumz, mu, u)
        var inner = 0usize
        if model == 5usize {
            // VEI: scale and shape, warm started from the previous iteration
            k = 0usize
            while k < g {
                if sumz[k] <= rteps { ret nan }
                k += 1usize
            }
            var again = itmax_in > 0usize
            while again {
                if min_of(shp, p) <= eps { ret nan }
                inner += 1usize
                k = 0usize
                while k < g {
                    w[p + k] = scale[k]
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += u[k * p * p + j * p + j] / shp[j]
                        j += 1usize
                    }
                    scale[k] = s / (pp * sumz[k])
                    k += 1usize
                }
                if min_of(scale, g) <= eps { ret nan }
                j = 0usize
                while j < p {
                    w[j] = shp[j]
                    var s = 0.0f64
                    k = 0usize
                    while k < g {
                        s += u[k * p * p + j * p + j] / scale[k]
                        k += 1usize
                    }
                    shp[j] = s
                    j += 1usize
                }
                if min_of(shp, p) <= eps { ret nan }
                let gm = geo_mean(shp, p)
                if gm <= eps { ret nan }
                j = 0usize
                while j < p {
                    shp[j] = shp[j] / gm
                    j += 1usize
                }
                errin = 0.0f64
                k = 0usize
                while k < g {
                    let d = math.abs[f64](w[p + k] - scale[k]) / (1.0f64 + scale[k])
                    if d > errin { errin = d }
                    k += 1usize
                }
                j = 0usize
                while j < p {
                    let d = math.abs[f64](w[j] - shp[j]) / (1.0f64 + shp[j])
                    if d > errin { errin = d }
                    j += 1usize
                }
                again = errin > tol_in && inner <= itmax_in
            }
            k = 0usize
            while k < g {
                var b = 0usize
                while b < p {
                    var c = 0usize
                    while c < p {
                        sigma[k * p * p + b * p + c] = 0.0f64
                        c += 1usize
                    }
                    sigma[k * p * p + b * p + b] = scale[k] * shp[b]
                    b += 1usize
                }
                k += 1usize
            }
        } else if model == 13usize {
            // VEV: eigenvalues and eigenvectors of every scatter matrix, then scale and shape
            k = 0usize
            while k < g {
                if sumz[k] < rteps { ret nan }
                let (vals, vecs, ee) = ica.eigen_sym(a, u[k * p * p..k * p * p + p * p], p)
                if ee != ok { ret nan }
                j = 0usize
                while j < p {
                    ev[k * p + j] = vals[j]
                    var q = 0usize
                    while q < p {
                        evec[k * p * p + j * p + q] = vecs[q * p + j]
                        q += 1usize
                    }
                    j += 1usize
                }
                k += 1usize
            }
            if iter == 1usize {
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
                if min_of(shp, p) <= 0.0f64 { ret nan }
                let gm = geo_mean(shp, p)
                var tsum = 0.0f64
                k = 0usize
                while k < g {
                    tsum += sumz[k]
                    k += 1usize
                }
                k = 0usize
                while k < g {
                    scale[k] = gm / nn
                    k += 1usize
                }
                if gm <= eps { ret nan }
                j = 0usize
                while j < p {
                    shp[j] = shp[j] / gm
                    j += 1usize
                }
            }
            errin = 0.0f64
            var again = itmax_in > 0usize
            while again {
                j = 0usize
                while j < p {
                    w[j] = shp[j]
                    shp[j] = 0.0f64
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    w[p + k] = scale[k]
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        s += ev[k * p + j] / w[j]
                        j += 1usize
                    }
                    scale[k] = s / (sumz[k] * pp)
                    if scale[k] <= eps { ret nan }
                    j = 0usize
                    while j < p {
                        shp[j] = shp[j] + ev[k * p + j] / scale[k]
                        j += 1usize
                    }
                    k += 1usize
                }
                inner += 1usize
                if min_of(shp, p) <= 0.0f64 { ret nan }
                let gm = geo_mean(shp, p)
                if gm <= eps { ret nan }
                j = 0usize
                while j < p {
                    shp[j] = shp[j] / gm
                    j += 1usize
                }
                errin = 0.0f64
                j = 0usize
                while j < p {
                    let d = math.abs[f64](w[j] - shp[j]) / (1.0f64 + shp[j])
                    if d > errin { errin = d }
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    let d = math.abs[f64](scale[k] - w[p + k]) / (1.0f64 + scale[k])
                    if d > errin { errin = d }
                    k += 1usize
                }
                again = errin >= tol_in && inner < itmax_in
            }
            // the E step of the Fortran divides by the square root of the shape; shape and scale must clear rteps
            if min_of(shp, p) <= eps || min_of(scale, g) <= eps { ret nan }
            if min_of(shp, p) <= 0.0f64 { ret nan }
            k = 0usize
            while k < g {
                var b = 0usize
                while b < p {
                    var c = 0usize
                    while c < p {
                        var s = 0.0f64
                        j = 0usize
                        while j < p {
                            s += evec[k * p * p + j * p + b] * shp[j] * evec[k * p * p + j * p + c]
                            j += 1usize
                        }
                        sigma[k * p * p + c * p + b] = scale[k] * s
                        c += 1usize
                    }
                    b += 1usize
                }
                k += 1usize
            }
        } else if model == 10usize {
            // VEE: scale per group and one common shape matrix C, scale reset to one every iteration
            k = 0usize
            while k < g {
                let (vals, vecs, ee) = ica.eigen_sym(a, u[k * p * p..k * p * p + p * p], p)
                if ee != ok { ret nan }
                if min_of(vals, p) <= 0.0f64 { ret nan }
                k += 1usize
            }
            k = 0usize
            while k < g {
                scale[k] = 1.0f64
                k += 1usize
            }
            var trgtprev = big() / 2.0f64
            var again = true
            var tmp3 = 1.0f64
            while again {
                inner += 1usize
                let m0 = mem.mark(a)
                j = 0usize
                while j < p * p {
                    cm[j] = 0.0f64
                    k = 0usize
                    while k < g {
                        cm[j] += u[k * p * p + j] / scale[k]
                        k += 1usize
                    }
                    j += 1usize
                }
                let (vals, vecs, ee) = ica.eigen_sym(a, cm, p)
                if ee != ok { ret nan }
                var lsum = 0.0f64
                j = 0usize
                while j < p {
                    lsum += math.log[f64](vals[j])
                    j += 1usize
                }
                tmp3 = math.pow[f64](math.exp[f64](lsum), 1.0f64 / pp)
                j = 0usize
                while j < p * p {
                    cm[j] = cm[j] / tmp3
                    j += 1usize
                }
                // inverse of C from its Cholesky factor
                if !mp.chol_lower(cm, p, t1) { ret nan }
                // C = L L'; invert by solving L Y = I then L' X = Y
                var cc = 0usize
                while cc < p {
                    var q = 0usize
                    while q < p {
                        var v = 0.0f64
                        if q == cc { v = 1.0f64 }
                        var t = 0usize
                        while t < q {
                            v -= t1[t * p + q] * t2[cc * p + t]
                            t += 1usize
                        }
                        t2[cc * p + q] = v / t1[q * p + q]
                        q += 1usize
                    }
                    q = p
                    while q > 0usize {
                        q -= 1usize
                        var v = t2[cc * p + q]
                        var t = q + 1usize
                        while t < p {
                            v -= t1[q * p + t] * t3[cc * p + t]
                            t += 1usize
                        }
                        t3[cc * p + q] = v / t1[q * p + q]
                    }
                    cc += 1usize
                }
                k = 0usize
                var ssum = 0.0f64
                var lw = 0.0f64
                while k < g {
                    var s = 0.0f64
                    j = 0usize
                    while j < p {
                        var i2 = 0usize
                        while i2 < p {
                            s += u[k * p * p + i2 * p + j] * t3[j * p + i2]
                            i2 += 1usize
                        }
                        j += 1usize
                    }
                    scale[k] = s / (pp * sumz[k])
                    ssum += sumz[k]
                    lw += math.log[f64](scale[k]) * sumz[k]
                    k += 1usize
                }
                let trgt = ssum * pp + pp * lw
                errin = math.abs[f64](trgt - trgtprev) / (1.0f64 + math.abs[f64](trgt))
                trgtprev = trgt
                again = errin > tol_in && inner < itmax_in
                if !again {
                    j = 0usize
                    while j < p {
                        shp[j] = vals[j] / tmp3
                        j += 1usize
                    }
                }
                mem.reset(a, m0)
            }
            if min_of(shp, p) <= rteps || min_of(scale, g) <= rteps { ret nan }
            k = 0usize
            while k < g {
                j = 0usize
                while j < p * p {
                    sigma[k * p * p + j] = scale[k] * cm[j]
                    j += 1usize
                }
                k += 1usize
            }
        } else {
            // EVE (9) and VVE (11): common orientation through the MM steps of Browne and McNicholas, shape per group
            k = 0usize
            while k < g {
                let (vals, vecs, ee) = ica.eigen_sym(a, u[k * p * p..k * p * p + p * p], p)
                if ee != ok { ret nan }
                if min_of(vals, p) < rteps { ret nan }
                omega[k] = vals[0usize]
                k += 1usize
            }
            var trgtprev = big() / 2.0f64
            var trgt = 0.0f64
            var again = true
            while again {
                inner += 1usize
                // MM 1
                j = 0usize
                while j < p * p {
                    t3[j] = 0.0f64
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    var r = 0usize
                    while r < p {
                        var c = 0usize
                        while c < p {
                            t1[c * p + r] = om[c * p + r] / shape[k * p + r]
                            c += 1usize
                        }
                        r += 1usize
                    }
                    matmul(t1, u[k * p * p..k * p * p + p * p], p, t2)
                    j = 0usize
                    while j < p * p {
                        t3[j] += t2[j] - omega[k] * t1[j]
                        j += 1usize
                    }
                    k += 1usize
                }
                if polar(a, t3, p, om) != ok { ret nan }
                transpose_sq(om, p)
                // MM 2
                j = 0usize
                while j < p * p {
                    t3[j] = 0.0f64
                    j += 1usize
                }
                k = 0usize
                while k < g {
                    matmul(u[k * p * p..k * p * p + p * p], om, p, t1)
                    var mx = 0.0f64
                    j = 0usize
                    while j < p {
                        let r = 1.0f64 / shape[k * p + j]
                        if r > mx { mx = r }
                        j += 1usize
                    }
                    var c = 0usize
                    while c < p {
                        var r = 0usize
                        while r < p {
                            t2[c * p + r] = t1[c * p + r] / shape[k * p + c]
                            r += 1usize
                        }
                        c += 1usize
                    }
                    j = 0usize
                    while j < p * p {
                        t3[j] += t2[j] - mx * t1[j]
                        j += 1usize
                    }
                    k += 1usize
                }
                if polar(a, t3, p, om) != ok { ret nan }
                transpose_sq(om, p)
                // shape and the target function
                trgt = 0.0f64
                k = 0usize
                while k < g {
                    matmul(om, u[k * p * p..k * p * p + p * p], p, t1)
                    j = 0usize
                    while j < p {
                        var s = 0.0f64
                        var c = 0usize
                        while c < p {
                            s += t1[c * p + j] * om[c * p + j]
                            c += 1usize
                        }
                        shape[k * p + j] = s
                        j += 1usize
                    }
                    if model == 9usize {
                        let gm = geo_mean(shape[k * p..k * p + p], p)
                        j = 0usize
                        while j < p {
                            shape[k * p + j] = shape[k * p + j] / gm
                            j += 1usize
                        }
                        if min_of(shape[k * p..k * p + p], p) < rteps { ret nan }
                    } else {
                        j = 0usize
                        while j < p {
                            shape[k * p + j] = shape[k * p + j] / sumz[k]
                            j += 1usize
                        }
                        let gm = geo_mean(shape[k * p..k * p + p], p)
                        scale[k] = gm
                        j = 0usize
                        while j < p {
                            shape[k * p + j] = shape[k * p + j] / gm
                            j += 1usize
                        }
                        if min_of(shape[k * p..k * p + p], p) < rteps || gm < rteps { ret nan }
                    }
                    j = 0usize
                    while j < p {
                        var s = 0.0f64
                        var c = 0usize
                        while c < p {
                            s += t1[c * p + j] * om[c * p + j]
                            c += 1usize
                        }
                        trgt += s / shape[k * p + j]
                        j += 1usize
                    }
                    k += 1usize
                }
                errin = math.abs[f64](trgt - trgtprev) / (1.0f64 + math.abs[f64](trgt))
                trgtprev = trgt
                again = errin > tol_in && inner < itmax_in
            }
            if model == 9usize {
                var ssum = 0.0f64
                k = 0usize
                while k < g {
                    ssum += sumz[k]
                    k += 1usize
                }
                eqscale = trgt / (ssum * pp)
                k = 0usize
                while k < g {
                    scale[k] = eqscale
                    k += 1usize
                }
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
                            s += om[b * p + j] * shape[k * p + j] * om[c * p + j]
                            j += 1usize
                        }
                        sigma[k * p * p + c * p + b] = scale[k] * s
                        c += 1usize
                    }
                    b += 1usize
                }
                k += 1usize
            }
        }
        if inner > inmax { inmax = inner }
        hood = estep_gen(a, x, n, p, g, mu, sigma, pro, z)
        if hood != hood { ret nan }
        errv = math.abs[f64](hood - hold) / (1.0f64 + math.abs[f64](hood))
        hold = hood
        if fam2 {
            k = 0usize
            while k < g {
                if sumz[k] < rteps { ret 0.0f64 - 1.0e308f64 }
                k += 1usize
            }
        }
        mem.reset(a, it0)
        if errv <= tol_out || iter >= itmax_out {
            info[0usize] = f64(iter)
            info[1usize] = errv
            info[2usize] = f64(inmax)
            info[3usize] = errin
            ret hood
        }
    }
    ret hood
}

// me(data, modelName, z) for any model of the package table index (E 0, V 1, EII 2, VII 3, EEI 4, VEI 5, EVI 6, VVI 7, EEE 8, EVE 9, VEE 10, VVE 11, EEV 12, VEV 13, EVV 14, VVV 15); the same outputs as me_gen
fn me_any(a: *mem.Arena, model: usize, eqpro: bool, x: []const f64, z: []f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    let tol_in = math.sqrt[f64](2.220446049250313e-16f64)
    let imax = 2147483647usize
    if model == 5usize || model == 9usize || model == 10usize || model == 11usize || model == 13usize {
        ret me_gen(a, model, eqpro, x, z, n, p, g, 1.0e-5f64, tol_in, imax, imax, 2.220446049250313e-16f64, pro, mu, sigma, info)
    }
    var code = 0usize
    if model == 3usize || model == 1usize { code = 1usize }
    if model == 4usize { code = 2usize }
    if model == 7usize { code = 3usize }
    if model == 8usize { code = 4usize }
    if model == 15usize { code = 5usize }
    if model == 6usize { code = 6usize }
    if model == 14usize { code = 7usize }
    if model == 12usize { code = 8usize }
    let (mg, e1) = mem.alloc[f64](a, g * p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let h = mp.me_em(a, code, eqpro, x, z, n, p, g, pro, mg, sigma, info)
    var k = 0usize
    while k < g {
        var j = 0usize
        while j < p {
            mu[k * p + j] = mg[j * g + k]
            j += 1usize
        }
        k += 1usize
    }
    ret h
}
