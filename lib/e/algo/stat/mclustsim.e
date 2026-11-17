// R mclust: sim(modelName, parameters, n, seed) for the 16 covariance models, drawing from R's own streams (set.seed, sample with prob, rnorm).
//
// Layouts follow R: means are d by G, orientation is d by d (by G when it differs between groups), column-major.

use e.math
use e.mem
use e.algo.rand.r as rng

// revsort of R (sort.c): a heap sort into descending order that carries the permutation ib alongside; the same ties come out as in R
fn revsort(a: []f64, ib: []usize, n: usize) {
    if n <= 1usize { ret }
    var l = n / 2usize + 1usize
    var ir = n
    var ra = 0.0f64
    var ii = 0usize
    while true {
        if l > 1usize {
            l -= 1usize
            ra = a[l - 1usize]
            ii = ib[l - 1usize]
        } else {
            ra = a[ir - 1usize]
            ii = ib[ir - 1usize]
            a[ir - 1usize] = a[0usize]
            ib[ir - 1usize] = ib[0usize]
            ir -= 1usize
            if ir == 1usize {
                a[0usize] = ra
                ib[0usize] = ii
                ret
            }
        }
        var i = l
        var j = l * 2usize
        while j <= ir {
            if j < ir && a[j - 1usize] > a[j] { j += 1usize }
            if ra > a[j - 1usize] {
                a[i - 1usize] = a[j - 1usize]
                ib[i - 1usize] = ib[j - 1usize]
                i = j
                j += i
            } else {
                j = ir + 1usize
            }
        }
        a[i - 1usize] = ra
        ib[i - 1usize] = ii
    }
}

// sample(1:g, size = n, replace = TRUE, prob = pro): ProbSampleReplace, 1-based answers
fn sample_prob(a: *mem.Arena, r: *rng.Rng, pro: []const f64, g: usize, n: usize, out: []usize) -> err {
    let (p, e1) = mem.alloc[f64](a, g)
    let (perm, e2) = mem.alloc[usize](a, g)
    if e1 != ok || e2 != ok { ret mem.Full }
    var s = 0.0f64
    var k = 0usize
    while k < g {
        s += pro[k]
        k += 1usize
    }
    k = 0usize
    while k < g {
        p[k] = pro[k] / s
        perm[k] = k + 1usize
        k += 1usize
    }
    revsort(p, perm, g)
    k = 1usize
    while k < g {
        p[k] = p[k] + p[k - 1usize]
        k += 1usize
    }
    var i = 0usize
    while i < n {
        let ru = rng.unif(r)
        var j = 0usize
        while j + 1usize < g && ru > p[j] { j += 1usize }
        out[i] = perm[j]
        i += 1usize
    }
    ret ok
}

// the draws of sim(): model index (E 0, V 1, EII 2, VII 3, EEI 4, VEI 5, EVI 6, VVI 7, EEE 8, EVE 9, VEE 10, VVE 11, EEV 12, VEV 13, EVV 14, VVV 15), d variables, g groups, n draws.
// scale, shape, orient and sigma are the variance components the model uses (sigma: sigmasq for E, V, EII and VII, the d by d matrix for EEE, g stacked matrices for VVV).
// grp receives the 1-based group labels (n) and x the draws (n by d, column-major).
fn sim_model(a: *mem.Arena, model: usize, d: usize, g: usize, n: usize, seed: i64, pro: []const f64, mu: []const f64, scale: []const f64, shape: []const f64, orient: []const f64, sigma: []const f64, grp: []f64, x: []f64) -> err {
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    let (cl, e1) = mem.alloc[usize](a, n)
    let (cnt, e2) = mem.alloc[usize](a, g)
    let (z, e3) = mem.alloc[f64](a, n * d)
    let (cf, e4) = mem.alloc[f64](a, d * d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let se = sample_prob(a, &r, pro, g, n, cl)
    if se != ok { ret se }
    var k = 0usize
    while k < g {
        cnt[k] = 0usize
        k += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[cl[i] - 1usize] += 1usize
        grp[i] = f64(cl[i])
        i += 1usize
    }
    k = 0usize
    while k < g {
        let m = cnt[k]
        // the chol factor of the group, cf[i][j] in column-major d by d
        var q = 0usize
        while q < d * d {
            cf[q] = 0.0f64
            q += 1usize
        }
        if model == 0usize || model == 1usize {
            var s2 = sigma[0usize]
            if model == 1usize { s2 = sigma[k] }
            cf[0usize] = math.sqrt[f64](s2)
        } else if model == 2usize || model == 3usize {
            var s2 = sigma[0usize]
            if model == 3usize { s2 = sigma[k] }
            q = 0usize
            while q < d {
                cf[q * d + q] = math.sqrt[f64](s2)
                q += 1usize
            }
        } else if model >= 4usize && model <= 7usize {
            // diagonal: EEI scale and shape (d), VEI scale (g) and shape (d), EVI scale and shape (d by g), VVI scale (g) and shape (d by g)
            q = 0usize
            while q < d {
                var sc = scale[0usize]
                if model == 5usize || model == 7usize { sc = scale[k] }
                var sh = shape[q]
                if model == 6usize || model == 7usize { sh = shape[k * d + q] }
                cf[q * d + q] = math.sqrt[f64](sc * sh)
                q += 1usize
            }
        } else if model == 8usize || model == 15usize {
            // upper Cholesky factor R of the covariance: R'R = Sigma
            var off = 0usize
            if model == 15usize { off = k * d * d }
            var j = 0usize
            while j < d {
                var s = sigma[off + j * d + j]
                var t = 0usize
                while t < j {
                    s -= cf[j * d + t] * cf[j * d + t]
                    t += 1usize
                }
                let rjj = math.sqrt[f64](s)
                cf[j * d + j] = rjj
                var c = j + 1usize
                while c < d {
                    var v = sigma[off + c * d + j]
                    t = 0usize
                    while t < j {
                        v -= cf[j * d + t] * cf[c * d + t]
                        t += 1usize
                    }
                    cf[c * d + j] = v / rjj
                    c += 1usize
                }
                j += 1usize
            }
        } else {
            // t(orientation) * sss: cf[i][j] = sss_i * O[j][i]
            var off = 0usize
            if model == 12usize || model == 13usize || model == 14usize { off = k * d * d }
            var ii = 0usize
            while ii < d {
                var sc = scale[0usize]
                if model == 10usize || model == 11usize || model == 13usize { sc = scale[k] }
                var sh = shape[ii]
                if model == 9usize || model == 11usize || model == 14usize { sh = shape[k * d + ii] }
                let sss = math.sqrt[f64](sc) * math.sqrt[f64](sh)
                var j = 0usize
                while j < d {
                    cf[j * d + ii] = sss * orient[off + ii * d + j]
                    j += 1usize
                }
                ii += 1usize
            }
        }
        // draws matrix(rnorm(m d), m, d) in column-major order
        q = 0usize
        while q < m * d {
            z[q] = rng.norm(&r)
            q += 1usize
        }
        var row = 0usize
        i = 0usize
        while i < n {
            if cl[i] == k + 1usize {
                var j = 0usize
                while j < d {
                    var s = 0.0f64
                    var t = 0usize
                    while t < d {
                        s += z[t * m + row] * cf[j * d + t]
                        t += 1usize
                    }
                    x[j * n + i] = s + mu[k * d + j]
                    j += 1usize
                }
                row += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    ret ok
}
