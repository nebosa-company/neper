// R energy: distance covariance and correlation of two samples of points (V-statistics with doubly centred Euclidean distance matrices,
// optionally raised to a power in (0, 2)) and the two-sample energy statistic of edist and eqdist.etest.
//
// Not here: the permutation tests' p values (they use R's random permutations), the unbiased and partial distance correlations,
// the Poisson tests, the energy clustering, and the independence coefficients of the other tests.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rg
use e.algo.stat.gslfns as gs
use e.math
use e.math.dist as dist
use e.math.special as sp
use e.mem

fn dist_pow(x: []const f64, n: usize, d: usize, i: usize, j: usize, index: f64) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d {
        let v = x[i * d + k] - x[j * d + k]
        s += v * v
        k += 1usize
    }
    let r = math.sqrt[f64](s)
    if index == 1.0f64 { ret r }
    ret math.pow[f64](r, index)
}

// the doubly centred matrix A of the n points of dimension d, n by n row-major
fn centred(a: *mem.Arena, x: []const f64, n: usize, d: usize, index: f64) -> ([]f64, err) {
    let (m, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (m, e1) }
    let (rm, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (m, e2) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            let v = dist_pow(x, n, d, i, j, index)
            m[i * n + j] = v
            s += v
            j += 1usize
        }
        rm[i] = s / f64(n)
        total += s
        i += 1usize
    }
    let gm = total / (f64(n) * f64(n))
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            m[i * n + j] = m[i * n + j] - rm[i] - rm[j] + gm
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// (dCov, dCor): the distance covariance (square root of the V-statistic) and the distance correlation
fn dcov_dcor(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize, index: f64) -> (f64, f64, err) {
    let (ax, e1) = centred(a, x, n, dx, index)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (ay, e2) = centred(a, y, n, dy, index)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n * n {
        sxy += ax[i] * ay[i]
        sxx += ax[i] * ax[i]
        syy += ay[i] * ay[i]
        i += 1usize
    }
    let nn = f64(n) * f64(n)
    let vxy = sxy / nn
    let vx = sxx / nn
    let vy = syy / nn
    var dcor = 0.0f64
    if vx * vy > 0.0f64 { dcor = math.sqrt[f64](vxy / math.sqrt[f64](vx * vy)) }
    ret (math.sqrt[f64](vxy), dcor, ok)
}

// the two-sample energy statistic of edist and eqdist.etest: n1 n2 / (n1 + n2) times 2 E|X - Y| - E|X - X'| - E|Y - Y'| (V-statistic means)
fn edist_stat(x: []const f64, n1: usize, y: []const f64, n2: usize, d: usize, index: f64) -> f64 {
    var xy = 0.0f64
    var i = 0usize
    while i < n1 {
        var j = 0usize
        while j < n2 {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                let v = x[i * d + k] - y[j * d + k]
                s += v * v
                k += 1usize
            }
            xy += math.pow[f64](math.sqrt[f64](s), index)
            j += 1usize
        }
        i += 1usize
    }
    var xx = 0.0f64
    i = 0usize
    while i < n1 {
        var j = 0usize
        while j < n1 {
            xx += dist_pow(x, n1, d, i, j, index)
            j += 1usize
        }
        i += 1usize
    }
    var yy = 0.0f64
    i = 0usize
    while i < n2 {
        var j = 0usize
        while j < n2 {
            yy += dist_pow(y, n2, d, i, j, index)
            j += 1usize
        }
        i += 1usize
    }
    let e = 2.0f64 * xy / (f64(n1) * f64(n2)) - xx / (f64(n1) * f64(n1)) - yy / (f64(n2) * f64(n2))
    ret e * f64(n1) * f64(n2) / (f64(n1) + f64(n2))
}

// the U-centred Euclidean distance matrix of the n by n row-major D: A_ij = a_ij - row_i / (n - 2) - col_j / (n - 2) + total / ((n - 1)(n - 2)) for i != j,
// zero on the diagonal (Szekely and Rizzo's bias correction)
fn ucentred(a: *mem.Arena, x: []const f64, n: usize, d: usize) -> ([]f64, err) {
    let (m, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (m, e1) }
    let (rm, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (m, e2) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            m[i * n + j] = dist_pow(x, n, d, i, j, 1.0f64)
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += m[i * n + j]
            j += 1usize
        }
        rm[i] = s
        total += s
        i += 1usize
    }
    let nf = f64(n)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i == j {
                m[i * n + j] = 0.0f64
            } else {
                // the column sum of column j is rm[j] (the distances are symmetric)
                m[i * n + j] = m[i * n + j] - rm[i] / (nf - 2.0f64) - rm[j] / (nf - 2.0f64) + total / ((nf - 1.0f64) * (nf - 2.0f64))
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// the unbiased distance covariance of two U-centred matrices: sum A B / (n (n - 3))
fn dcov_u(ua: []const f64, ub: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n * n {
        s += ua[i] * ub[i]
        i += 1usize
    }
    ret s / (f64(n) * (f64(n) - 3.0f64))
}

// energy::bcdcor(x, y): the bias-corrected distance correlation, dcovU(x, y) / sqrt(dcovU(x, x) dcovU(y, y)); x and y are n by dx and n by dy
// row-major
fn bcdcor(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize) -> (f64, err) {
    let (ax, e1) = ucentred(a, x, n, dx)
    if e1 != ok { ret (0.0f64, e1) }
    let (ay, e2) = ucentred(a, y, n, dy)
    if e2 != ok { ret (0.0f64, e2) }
    let sxy = dcov_u(ax, ay, n)
    let sxx = dcov_u(ax, ax, n)
    let syy = dcov_u(ay, ay, n)
    ret (sxy / math.sqrt[f64](sxx * syy), ok)
}

// ---- the energy statistics of normality: normal.e (univariate: the sorted standardised sample) and mvnorm.e (the multivariate statistic on the whitened sample,
// through the 1F1 expectation of the standard normal distance, as energy computes it when gsl is installed); x is n by d row-major
fn normal_e(a: *mem.Arena, x: []const f64, n: usize) -> f64 {
    var mu = 0.0f64
    var i = 0usize
    while i < n {
        mu += x[i]
        i += 1usize
    }
    mu = mu / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mu) * (x[i] - mu)
        i += 1usize
    }
    let s = math.sqrt[f64](ss / f64(n - 1usize))
    let (y, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        y[i] = (x[i] - mu) / s
        i += 1usize
    }
    // insertion sort (n is small in practice)
    i = 1usize
    while i < n {
        let v = y[i]
        var j = i
        while j > 0usize && y[j - 1usize] > v {
            y[j] = y[j - 1usize]
            j -= 1usize
        }
        y[j] = v
        i += 1usize
    }
    var s1 = 0.0f64
    var sk = 0.0f64
    i = 0usize
    while i < n {
        s1 += 2.0f64 * y[i] * dist.pnorm(y[i], 0.0f64, 1.0f64, true, false) + 2.0f64 * dist.dnorm(y[i], 0.0f64, 1.0f64, false)
        sk += (f64(2usize * i) + 1.0f64 - f64(n)) * y[i]
        i += 1usize
    }
    ret 2.0f64 * (s1 - f64(n) / math.sqrt[f64](3.141592653589793238462643383279f64) - sk / f64(n))
}

fn mvnorm_e(a: *mem.Arena, x: []const f64, n: usize, d: usize) -> f64 {
    if d == 1usize { ret normal_e(a, x, n) }
    let (mu, e1) = mem.alloc[f64](a, d)
    let (cov, e2) = mem.alloc[f64](a, d * d)
    let (w, e3) = mem.alloc[f64](a, d)
    let (z, e4) = mem.alloc[f64](a, d * d)
    let (y, e5) = mem.alloc[f64](a, n * d)
    let (t, e6) = mem.alloc[f64](a, d * d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i * d + j]
            i += 1usize
        }
        mu[j] = s / f64(n)
        j += 1usize
    }
    var r = 0usize
    while r < d {
        var c = 0usize
        while c < d {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * d + r] - mu[r]) * (x[i * d + c] - mu[c])
                i += 1usize
            }
            cov[r * d + c] = s / f64(n - 1usize)
            c += 1usize
        }
        r += 1usize
    }
    let ee = sy.dsyevr_all(a, cov, d, w, z)
    if ee != ok { ret 0.0f64 / 0.0f64 }
    // P D P' with D = diag(1 / sqrt(lambda)); the eigenvectors are the columns of z (column-major)
    r = 0usize
    while r < d {
        var c = 0usize
        while c < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += z[k * d + r] * (1.0f64 / math.sqrt[f64](w[k])) * z[k * d + c]
                k += 1usize
            }
            t[r * d + c] = s
            c += 1usize
        }
        r += 1usize
    }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += (x[i * d + k] - mu[k]) * t[k * d + c]
                k += 1usize
            }
            y[i * d + c] = s
            c += 1usize
        }
        i += 1usize
    }
    let dd = f64(d)
    let cst = math.exp[f64](sp.lgamma((dd + 1.0f64) / 2.0f64) - sp.lgamma(dd / 2.0f64))
    let mean2 = 2.0f64 * cst
    var m1 = 0.0f64
    i = 0usize
    while i < n {
        var ysq = 0.0f64
        var c = 0usize
        while c < d {
            ysq += y[i * d + c] * y[i * d + c]
            c += 1usize
        }
        m1 += gs.hyperg_1f1(0.0f64 - 0.5f64, dd / 2.0f64, 0.0f64 - ysq / 2.0f64)
        i += 1usize
    }
    let mean1 = math.sqrt[f64](2.0f64) * cst * m1 / f64(n)
    var sd = 0.0f64
    i = 0usize
    while i < n {
        var k = 0usize
        while k < i {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                let df = y[i * d + c] - y[k * d + c]
                s += df * df
                c += 1usize
            }
            sd += math.sqrt[f64](s)
            k += 1usize
        }
        i += 1usize
    }
    let mean3 = 2.0f64 * sd / (f64(n) * f64(n))
    ret f64(n) * (2.0f64 * mean1 - mean2 - mean3)
}

// energy::pdcor(x, y, z): the partial distance correlation, the cosine of the U-centred matrices of x and y after projecting out the U-centred matrix of z
fn pdcor(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, n: usize, dx: usize, dy: usize, dz: usize) -> (f64, err) {
    let (cx, e1) = ucentred(a, x, n, dx)
    if e1 != ok { ret (0.0f64, e1) }
    let (cy, e2) = ucentred(a, y, n, dy)
    if e2 != ok { ret (0.0f64, e2) }
    let (cz, e3) = ucentred(a, z, n, dz)
    if e3 != ok { ret (0.0f64, e3) }
    let nn = n * n
    var xz = 0.0f64
    var yz = 0.0f64
    var zz = 0.0f64
    var i = 0usize
    while i < nn {
        xz += cx[i] * cz[i]
        yz += cy[i] * cz[i]
        zz += cz[i] * cz[i]
        i += 1usize
    }
    let bx = xz / zz
    let by = yz / zz
    var pxy = 0.0f64
    var pxx = 0.0f64
    var pyy = 0.0f64
    i = 0usize
    while i < nn {
        let ux = cx[i] - bx * cz[i]
        let uy = cy[i] - by * cz[i]
        pxy += ux * uy
        pxx += ux * ux
        pyy += uy * uy
        i += 1usize
    }
    ret (pxy / math.sqrt[f64](pxx * pyy), ok)
}

// energy::dcov.test(x, y, R = reps): the statistic n dCov^2 and the permutation p value (1 + #(replicates >= statistic)) / (1 + reps). The C routine keeps one index
// vector across replicates and shuffles it in place (j = floor(m unif), m decreasing, swapping J[j] with J[m]) before each, drawing n - 1 uniforms per replicate; the
// rows of y are taken in that order. x and y are n by dx and n by dy row-major.
fn dcov_test(a: *mem.Arena, r: *rg.Rng, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize, reps: usize) -> (f64, f64, err) {
    let (s, p, e) = perm_test(a, r, x, y, n, dx, dy, reps, false)
    ret (s, p, e)
}

// energy::dcor.test: the same permutation test on the distance correlation itself (the statistic is dCor, compared as dCor)
fn dcor_test(a: *mem.Arena, r: *rg.Rng, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize, reps: usize) -> (f64, f64, err) {
    let (s, p, e) = perm_test(a, r, x, y, n, dx, dy, reps, true)
    ret (s, p, e)
}

fn perm_test(a: *mem.Arena, r: *rg.Rng, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize, reps: usize, use_cor: bool) -> (f64, f64, err) {
    let (d0, c0, e0) = dcov_dcor(a, x, y, n, dx, dy, 1.0f64)
    if e0 != ok { ret (0.0f64, 0.0f64, e0) }
    var stat = f64(n) * d0 * d0
    if use_cor { stat = c0 }
    let (jj, e1) = mem.alloc[usize](a, n)
    let (yp, e2) = mem.alloc[f64](a, n * dy)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        jj[i] = i
        i += 1usize
    }
    var k = 0usize
    var rep = 0usize
    while rep < reps {
        var m = n
        i = 0usize
        while i + 1usize < n {
            let j = usize(math.floor[f64](f64(m) * rg.unif(r)))
            m -= 1usize
            let t = jj[j]
            jj[j] = jj[m]
            jj[m] = t
            i += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < dy {
                yp[i * dy + c] = y[jj[i] * dy + c]
                c += 1usize
            }
            i += 1usize
        }
        let (dv, cv, ev) = dcov_dcor(a, x, yp, n, dx, dy, 1.0f64)
        if ev != ok { ret (0.0f64, 0.0f64, ev) }
        var v = f64(n) * dv * dv
        if use_cor { v = cv }
        if v >= stat { k += 1usize }
        rep += 1usize
    }
    ret (stat, f64(1usize + k) / f64(1usize + reps), ok)
}

// energy::eqdist.etest(x, sizes = c(n1, n2), R = reps): the two-sample E statistic and its permutation p value; the pooled rows are shuffled by the same
// in-place index shuffle as dcov.test and the first n1 go to the first sample
fn eqdist_etest(a: *mem.Arena, r: *rg.Rng, x: []const f64, n1: usize, n2: usize, d: usize, reps: usize) -> (f64, f64, err) {
    let n = n1 + n2
    let stat = edist_stat(x[0usize..n1 * d], n1, x[n1 * d..n * d], n2, d, 1.0f64)
    let (jj, e1) = mem.alloc[usize](a, n)
    let (pa, e2) = mem.alloc[f64](a, n1 * d)
    let (pb, e3) = mem.alloc[f64](a, n2 * d)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        jj[i] = i
        i += 1usize
    }
    var k = 0usize
    var rep = 0usize
    while rep < reps {
        var m = n
        i = 0usize
        while i + 1usize < n {
            let j = usize(math.floor[f64](f64(m) * rg.unif(r)))
            m -= 1usize
            let t = jj[j]
            jj[j] = jj[m]
            jj[m] = t
            i += 1usize
        }
        i = 0usize
        while i < n1 {
            var c = 0usize
            while c < d {
                pa[i * d + c] = x[jj[i] * d + c]
                c += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n2 {
            var c = 0usize
            while c < d {
                pb[i * d + c] = x[jj[n1 + i] * d + c]
                c += 1usize
            }
            i += 1usize
        }
        let v = edist_stat(pa, n1, pb, n2, d, 1.0f64)
        if v >= stat { k += 1usize }
        rep += 1usize
    }
    ret (stat, f64(1usize + k) / f64(1usize + reps), ok)
}

// the K-sample E-statistic: the sum over sample pairs of the two-sample statistic, the samples being consecutive blocks of x (n rows of d) of the given sizes
fn ksample_stat(x: []const f64, sizes: []const usize, d: usize, index: f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    var offi = 0usize
    while i < sizes.len {
        var j = i + 1usize
        var offj = offi + sizes[i]
        while j < sizes.len {
            total += edist_stat(x[offi * d..(offi + sizes[i]) * d], sizes[i], x[offj * d..(offj + sizes[j]) * d], sizes[j], d, index)
            offj += sizes[j]
            j += 1usize
        }
        offi += sizes[i]
        i += 1usize
    }
    ret total
}

// eqdist.etest(x, sizes, R) for any number of samples (the original method): the statistic and the permutation p value, the permutation being R's cumulative shuffle of the index vector
fn eqdist_ketest(a: *mem.Arena, r: *rg.Rng, x: []const f64, sizes: []const usize, d: usize, reps: usize) -> (f64, f64, err) {
    var n = 0usize
    var i = 0usize
    while i < sizes.len {
        n += sizes[i]
        i += 1usize
    }
    let stat = ksample_stat(x, sizes, d, 1.0f64)
    let (jj, e1) = mem.alloc[usize](a, n)
    let (px, e2) = mem.alloc[f64](a, n * d)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    i = 0usize
    while i < n {
        jj[i] = i
        i += 1usize
    }
    var k = 0usize
    var rep = 0usize
    while rep < reps {
        var m = n
        i = 0usize
        while i + 1usize < n {
            let j = usize(math.floor[f64](f64(m) * rg.unif(r)))
            m -= 1usize
            let t = jj[j]
            jj[j] = jj[m]
            jj[m] = t
            i += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < d {
                px[i * d + c] = x[jj[i] * d + c]
                c += 1usize
            }
            i += 1usize
        }
        if ksample_stat(px, sizes, d, 1.0f64) >= stat { k += 1usize }
        rep += 1usize
    }
    ret (stat, f64(1usize + k) / f64(1usize + reps), ok)
}

// disco(x, factors = g, index, R) for one factor: dst is the n by n row-major distance matrix already raised to the index, grp the 0-based level of each row (k levels);
// out receives (between, within, statistic, p value), the p value by boot's permutation of the factor (R draws of sample.int(n) under the generator) and strict exceedance, NaN when R is 0
fn disco_parts(dst: []const f64, n: usize, grp: []const usize, perm: []const usize, k: usize, out: []f64) {
    var total = 0.0f64
    var i = 0usize
    while i < n * n {
        total += dst[i]
        i += 1usize
    }
    total = total / (2.0f64 * f64(n))
    var w = 0.0f64
    var l = 0usize
    while l < k {
        var cnt = 0usize
        var g = 0.0f64
        i = 0usize
        while i < n {
            if grp[perm[i]] == l {
                cnt += 1usize
                var j = 0usize
                while j < n {
                    if grp[perm[j]] == l { g += dst[i * n + j] }
                    j += 1usize
                }
            }
            i += 1usize
        }
        w += g / (2.0f64 * f64(cnt))
        l += 1usize
    }
    out[0usize] = total - w
    out[1usize] = w
    out[2usize] = ((total - w) / f64(k - 1usize)) / (w / f64(n - k))
}

fn disco(a: *mem.Arena, r: *rg.Rng, dst: []const f64, n: usize, grp: []const usize, k: usize, reps: usize, out: []f64) -> err {
    let (id, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        id[i] = i
        i += 1usize
    }
    disco_parts(dst, n, grp, id, k, out)
    let t0 = out[2usize]
    out[3usize] = 0.0f64 / 0.0f64
    if reps == 0usize { ret ok }
    var cnt = 0usize
    let (tmp, e2) = mem.alloc[f64](a, 3usize)
    if e2 != ok { ret e2 }
    var rep = 0usize
    while rep < reps {
        let (pm, pe) = rg.sample_int(a, r, i64(n), i64(n), false)
        if pe != ok { ret pe }
        let (pu, e3) = mem.alloc[usize](a, n)
        if e3 != ok { ret e3 }
        i = 0usize
        while i < n {
            pu[i] = usize(pm[i] - 1i64)
            i += 1usize
        }
        disco_parts(dst, n, grp, pu, k, tmp)
        if tmp[2usize] > t0 { cnt += 1usize }
        rep += 1usize
    }
    out[3usize] = f64(cnt + 1usize) / f64(reps + 1usize)
    ret ok
}
