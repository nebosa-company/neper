// R compositions beyond e.algo.stat.compositions: the rcomp (real-space) geometry (cdt, norm, minus, scalar multiple, mean, variance, distance and
// the isometric coordinates of the closed data), ilr bases from signary matrices and balances (balanceBase / balance, gsi.buildilrBase, the
// "balanced" ilrBase), zeroreplace with given detection limits, the normal location tests (acompNormalLocation.test: one sample, several samples
// with equal and with different variances, chi-squared or Monte Carlo p value from the seeded generator), Gauss.test, and the energy test of
// normality of the ilr coordinates (acompNormalGOF.test = energy::mvnorm.etest, the Monte Carlo p value from the seeded generator).
//
// Data are n by D row-major. Not here: robust estimates, missing values (NA) in acomp data, the "optimal" and principal balance bases, balance
// expressions as formulas (pass the positive and negative parts as index masks) and the plots.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rng
use e.algo.stat.compositions as cm
use e.algo.stat.hoslem_rsf as hr
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.text.prettyunits as pu

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// ---- rcomp ----

// cdt of an rcomp: the closed data minus the neutral composition 1 / D
fn rcomp_cdt(x: []const f64, n: usize, d: usize, out: []f64) {
    cm.clo(x, n, d, out)
    var i = 0usize
    while i < n * d {
        out[i] = out[i] - 1.0f64 / f64(d)
        i += 1usize
    }
}

// norm(rcomp): the Euclidean norm of cdt
fn rcomp_norm(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    rcomp_cdt(x, n, d, c)
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += c[i * d + j] * c[i * d + j]
            j += 1usize
        }
        out[i] = math.sqrt[f64](s)
        i += 1usize
    }
    ret ok
}

// x - y of two rcomp objects: the difference of the closed data (not closed again)
fn rcomp_minus(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (cy, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    cm.clo(x, n, d, out)
    cm.clo(y, n, d, cy)
    var i = 0usize
    while i < n * d {
        out[i] = out[i] - cy[i]
        i += 1usize
    }
    ret ok
}

// p * x of an rcomp: the closed data times p
fn rcomp_times(x: []const f64, p: f64, n: usize, d: usize, out: []f64) {
    cm.clo(x, n, d, out)
    var i = 0usize
    while i < n * d {
        out[i] = out[i] * p
        i += 1usize
    }
}

// mean(rcomp): the column means of the closed data
fn rcomp_mean(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    cm.clo(x, n, d, c)
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += c[i * d + j]
            i += 1usize
        }
        out[j] = s / f64(n)
        j += 1usize
    }
    ret ok
}

// var(rcomp): the covariance matrix (n - 1) of the closed data, D by D
fn rcomp_var(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    let (m, e2) = mem.alloc[f64](a, d)
    if e != ok || e2 != ok { ret e }
    cm.clo(x, n, d, c)
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += c[i * d + j]
            i += 1usize
        }
        m[j] = s / f64(n)
        j += 1usize
    }
    j = 0usize
    while j < d {
        var k = 0usize
        while k < d {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (c[i * d + j] - m[j]) * (c[i * d + k] - m[k])
                i += 1usize
            }
            out[j * d + k] = s / f64(n - 1usize)
            k += 1usize
        }
        j += 1usize
    }
    ret ok
}

// dist(rcomp): the Euclidean distances between the rows of the closed data, lower triangle by columns (R's dist order), n (n - 1) / 2 values
fn rcomp_dist(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    cm.clo(x, n, d, c)
    var k = 0usize
    var j = 0usize
    while j + 1usize < n {
        var i = j + 1usize
        while i < n {
            var s = 0.0f64
            var q = 0usize
            while q < d {
                s += (c[i * d + q] - c[j * d + q]) * (c[i * d + q] - c[j * d + q])
                q += 1usize
            }
            out[k] = math.sqrt[f64](s)
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// idt of an rcomp: cdt %*% V with the default ilr basis, n by (D - 1)
fn rcomp_idt(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    rcomp_cdt(x, n, d, c)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j + 1usize < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += c[i * d + k] * cm.ilr_v(k, j)
                k += 1usize
            }
            out[i * (d - 1usize) + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ---- bases and balances ----

// gsi.buildilrBase(W): the D by nc signary matrix W (row-major, entries 1, -1, 0) as an orthonormal ilr base, v row-major D by nc
fn signary_base(w: []const f64, d: usize, nc: usize, v: []f64) {
    var j = 0usize
    while j < nc {
        var npos = 0.0f64
        var nneg = 0.0f64
        var i = 0usize
        while i < d {
            if w[i * nc + j] > 0.0f64 { npos += 1.0f64 }
            if w[i * nc + j] < 0.0f64 { nneg += 1.0f64 }
            i += 1usize
        }
        var ss = 0.0f64
        i = 0usize
        while i < d {
            var val = 0.0f64
            if w[i * nc + j] > 0.0f64 { val = nneg }
            if w[i * nc + j] < 0.0f64 { val = 0.0f64 - npos }
            v[i * nc + j] = val
            ss += val * val
            i += 1usize
        }
        let nrm = math.sqrt[f64](ss)
        i = 0usize
        while i < d {
            v[i * nc + j] = v[i * nc + j] / nrm
            i += 1usize
        }
        j += 1usize
    }
}

// balanceBase for balance j with the parts in pos (mask 1) against those in neg (mask 1): 1 / #pos on the first, -1 / #neg on the second, normalised; col receives D values
fn balance_col(pos: []const f64, neg: []const f64, col: []f64) {
    let d = pos.len
    var np = 0.0f64
    var nn = 0.0f64
    var i = 0usize
    while i < d {
        np += pos[i]
        nn += neg[i]
        i += 1usize
    }
    var ss = 0.0f64
    i = 0usize
    while i < d {
        var v = 0.0f64
        if pos[i] != 0.0f64 { v = 1.0f64 / np }
        if neg[i] != 0.0f64 { v = 0.0f64 - 1.0f64 / nn }
        col[i] = v
        ss += v * v
        i += 1usize
    }
    let nrm = math.sqrt[f64](ss)
    i = 0usize
    while i < d {
        col[i] = col[i] / nrm
        i += 1usize
    }
}

// ilr(X, V): clr(x) %*% V for a D by nc base V (row-major), n by nc
fn ilr_base(a: *mem.Arena, x: []const f64, n: usize, d: usize, v: []const f64, nc: usize, out: []f64) -> err {
    let (c, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    let e2 = cm.clr_closed(a, x, n, d, c)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < nc {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += c[i * d + k] * v[k * nc + j]
                k += 1usize
            }
            out[i * nc + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the "balanced" ilrBase(D): the signary from gsi.merge2signary(M) with M = matrix(c(-(1:D), floor(D / 2):1, (floor(D / 2) + 1):(D - 2)), byrow = TRUE, ncol = 2),
// built into an orthonormal base (D by D - 1, row-major)
fn balanced_base(a: *mem.Arena, d: usize, v: []f64) -> err {
    let nr = d - 1usize
    let (m, e1) = mem.alloc[f64](a, 2usize * nr)
    let (sv, e2) = mem.alloc[f64](a, nr * d)
    let (w, e3) = mem.alloc[f64](a, d * nr)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    // the vector c(-(1:D), floor(D / 2):1, (floor(D / 2) + 1):(D - 2)) with R's : (counting down when the start is above the end), recycled or cut to 2 (D - 1) values
    let (vec, e4) = mem.alloc[f64](a, 4usize * d + 8usize)
    if e4 != ok { ret e4 }
    var k = 0usize
    var i = 1usize
    while i <= d {
        vec[k] = 0.0f64 - f64(i)
        k += 1usize
        i += 1usize
    }
    let h = d / 2usize
    var from = h
    var to = 1usize
    if from >= to {
        i = from
        while i >= to {
            vec[k] = f64(i)
            k += 1usize
            if i == to { break }
            i -= 1usize
        }
    } else {
        i = from
        while i <= to {
            vec[k] = f64(i)
            k += 1usize
            i += 1usize
        }
    }
    from = h + 1usize
    var to2 = 0usize
    if d >= 2usize { to2 = d - 2usize }
    if from <= to2 {
        i = from
        while i <= to2 {
            vec[k] = f64(i)
            k += 1usize
            i += 1usize
        }
    } else {
        i = from
        while i >= to2 {
            vec[k] = f64(i)
            k += 1usize
            if i == to2 { break }
            i -= 1usize
        }
    }
    i = 0usize
    while i < 2usize * nr {
        m[i] = vec[i % k]
        i += 1usize
    }
    i = 0usize
    while i < nr * d {
        sv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nr {
        var jj = 0usize
        while jj < 2usize {
            var weight = 1.0f64
            if jj == 0usize { weight = 0.0f64 - 1.0f64 }
            let kk = m[i * 2usize + jj]
            if kk < 0.0f64 { sv[i * d + usize(0.0f64 - kk) - 1usize] = weight }
            if kk > 0.0f64 {
                let row = usize(kk) - 1usize
                var c = 0usize
                while c < d {
                    if sv[row * d + c] != 0.0f64 { sv[i * d + c] = weight }
                    c += 1usize
                }
            }
            jj += 1usize
        }
        i += 1usize
    }
    // the signary is t(V): D by D - 1
    i = 0usize
    while i < d {
        var j = 0usize
        while j < nr {
            w[i * nr + j] = sv[j * d + i]
            j += 1usize
        }
        i += 1usize
    }
    signary_base(w, d, nr, v)
    ret ok
}

// zeroreplace(x, d, a): zeros are replaced by a times the detection limit of their column (dl has D values)
fn zero_replace(x: []const f64, n: usize, d: usize, dl: []const f64, a: f64, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            var v = x[i * d + j]
            if v == 0.0f64 { v = a * dl[j] }
            out[i * d + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// ---- normal location tests ----

// gsi.betterPvalue(p, digits): rounded, and 10^-digits when that rounds to zero
fn better_p(p: f64, digits: usize) -> f64 {
    let r = pu.fround(p, digits)
    if r == 0.0f64 { ret math.pow[f64](10.0f64, 0.0f64 - f64(digits)) }
    ret r
}

// the log determinant of the symmetric positive definite m by m (row-major) s by Cholesky
fn logdet_pd(s: []const f64, m: usize, tmp: []f64) -> f64 {
    var i = 0usize
    while i < m * m {
        tmp[i] = s[i]
        i += 1usize
    }
    var ld = 0.0f64
    var j = 0usize
    while j < m {
        var k = 0usize
        while k < j {
            tmp[j * m + j] = tmp[j * m + j] - tmp[j * m + k] * tmp[j * m + k]
            k += 1usize
        }
        let dj = math.sqrt[f64](tmp[j * m + j])
        tmp[j * m + j] = dj
        ld += 2.0f64 * math.log[f64](dj)
        i = j + 1usize
        while i < m {
            k = 0usize
            while k < j {
                tmp[i * m + j] = tmp[i * m + j] - tmp[i * m + k] * tmp[j * m + k]
                k += 1usize
            }
            tmp[i * m + j] = tmp[i * m + j] / dj
            i += 1usize
        }
        j += 1usize
    }
    ret ld
}

// scatter matrices of the rows x (n by m): total about zero (t(x) x, tss) and about the column means (css), both m by m
fn scatter(x: []const f64, n: usize, m: usize, zero_center: bool, mean: []f64, out: []f64) {
    var j = 0usize
    while j < m {
        var s = 0.0f64
        if !zero_center {
            var i = 0usize
            while i < n {
                s += x[i * m + j]
                i += 1usize
            }
            s = s / f64(n)
        }
        mean[j] = s
        j += 1usize
    }
    j = 0usize
    while j < m {
        var k = 0usize
        while k < m {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * m + j] - mean[j]) * (x[i * m + k] - mean[k])
                i += 1usize
            }
            out[j * m + k] = s
            k += 1usize
        }
        j += 1usize
    }
}

// n (log det(tss / n) - log det(rss / n)) for a sample x of n rows and m columns (the one sample statistic of acompNormalLocation.test)
fn loglik_one(a: *mem.Arena, x: []const f64, n: usize, m: usize) -> f64 {
    let (tss, e1) = mem.alloc[f64](a, m * m)
    let (rss, e2) = mem.alloc[f64](a, m * m)
    let (mn, e3) = mem.alloc[f64](a, m)
    let (tmp, e4) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    scatter(x, n, m, true, mn, tss)
    scatter(x, n, m, false, mn, rss)
    let nf = f64(n)
    var i = 0usize
    while i < m * m {
        tss[i] = tss[i] / nf
        rss[i] = rss[i] / nf
        i += 1usize
    }
    ret nf * (logdet_pd(tss, m, tmp) - logdet_pd(rss, m, tmp))
}

// the statistic of the equal variance test for the groups stacked in x (sizes in sz, m columns): n (log det(TSS / n) - log det(sum of RSS / n))
fn loglik_equal(a: *mem.Arena, x: []const f64, sz: []const usize, m: usize) -> f64 {
    var n = 0usize
    var g = 0usize
    while g < sz.len {
        n += sz[g]
        g += 1usize
    }
    let (tss, e1) = mem.alloc[f64](a, m * m)
    let (rss, e2) = mem.alloc[f64](a, m * m)
    let (cur, e3) = mem.alloc[f64](a, m * m)
    let (mn, e4) = mem.alloc[f64](a, m)
    let (tmp, e5) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan() }
    scatter(x[0usize..n * m], n, m, false, mn, tss)
    var i = 0usize
    while i < m * m {
        rss[i] = 0.0f64
        i += 1usize
    }
    var at = 0usize
    g = 0usize
    while g < sz.len {
        scatter(x[at * m..(at + sz[g]) * m], sz[g], m, false, mn, cur)
        i = 0usize
        while i < m * m {
            rss[i] += cur[i]
            i += 1usize
        }
        at += sz[g]
        g += 1usize
    }
    let nf = f64(n)
    i = 0usize
    while i < m * m {
        tss[i] = tss[i] / nf
        rss[i] = rss[i] / nf
        i += 1usize
    }
    ret nf * (logdet_pd(tss, m, tmp) - logdet_pd(rss, m, tmp))
}

// the different variance statistic: sum over groups of n_g (log det Sigma_g - log det (css_g / n_g)) with Sigma_g from fitSameMeanDifferentVarianceModel (20 iterations)
fn loglik_diff(a: *mem.Arena, x: []const f64, sz: []const usize, m: usize) -> f64 {
    let g = sz.len
    let (s0, e1) = mem.alloc[f64](a, g * m * m)
    let (sg, e2) = mem.alloc[f64](a, g * m * m)
    let (css, e3) = mem.alloc[f64](a, g * m * m)
    let (means, e4) = mem.alloc[f64](a, g * m)
    let (mm, e5) = mem.alloc[f64](a, m)
    let (inv, e6) = mem.alloc[f64](a, m * m)
    let (lhs, e7) = mem.alloc[f64](a, m * m)
    let (lhi, e8) = mem.alloc[f64](a, m * m)
    let (rhs, e9) = mem.alloc[f64](a, m)
    let (tmp, e10) = mem.alloc[f64](a, m * m)
    let (cur, e11) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret nan() }
    var at = 0usize
    var k = 0usize
    while k < g {
        scatter(x[at * m..(at + sz[k]) * m], sz[k], m, false, means[k * m..(k + 1usize) * m], css[k * m * m..(k + 1usize) * m * m])
        var i = 0usize
        while i < m * m {
            s0[k * m * m + i] = css[k * m * m + i] / f64(sz[k] - 1usize)
            sg[k * m * m + i] = s0[k * m * m + i]
            i += 1usize
        }
        at += sz[k]
        k += 1usize
    }
    var j = 0usize
    while j < m {
        var s = 0.0f64
        k = 0usize
        while k < g {
            s += means[k * m + j]
            k += 1usize
        }
        mm[j] = s / f64(g)
        j += 1usize
    }
    var it = 0usize
    while it < 20usize {
        var i = 0usize
        while i < m * m {
            lhs[i] = 0.0f64
            i += 1usize
        }
        j = 0usize
        while j < m {
            rhs[j] = 0.0f64
            j += 1usize
        }
        k = 0usize
        while k < g {
            let (rc, ei) = hr.inv_pivot(a, sg[k * m * m..(k + 1usize) * m * m], m, inv)
            if ei != ok { ret nan() }
            let nk = f64(sz[k])
            i = 0usize
            while i < m {
                j = 0usize
                while j < m {
                    lhs[i * m + j] += nk * inv[i * m + j]
                    rhs[i] += nk * inv[i * m + j] * means[k * m + j]
                    j += 1usize
                }
                i += 1usize
            }
            k += 1usize
        }
        let (rc2, ei2) = hr.inv_pivot(a, lhs, m, lhi)
        if ei2 != ok { ret nan() }
        i = 0usize
        while i < m {
            var s = 0.0f64
            j = 0usize
            while j < m {
                s += lhi[i * m + j] * rhs[j]
                j += 1usize
            }
            mm[i] = s
            i += 1usize
        }
        k = 0usize
        while k < g {
            i = 0usize
            while i < m {
                j = 0usize
                while j < m {
                    sg[k * m * m + i * m + j] = s0[k * m * m + i * m + j] + (means[k * m + i] - mm[i]) * (means[k * m + j] - mm[j])
                    j += 1usize
                }
                i += 1usize
            }
            k += 1usize
        }
        it += 1usize
    }
    var tot = 0.0f64
    k = 0usize
    while k < g {
        let nk = f64(sz[k])
        var i = 0usize
        while i < m * m {
            cur[i] = css[k * m * m + i] / nk
            i += 1usize
        }
        tot += nk * (logdet_pd(sg[k * m * m..(k + 1usize) * m * m], m, tmp) - logdet_pd(cur, m, tmp))
        k += 1usize
    }
    ret tot
}

// acompNormalLocation.test on ilr coordinates z (n by m row-major): kind 0 one sample, 1 equal variances (groups sizes sz), 2 different variances. nrep 0 gives the chi-squared
// p value (3 digits), otherwise the Monte Carlo p value of nrep standard normal replicates drawn from r (floor(log10(nrep)) digits). res = (statistic, df, p value)
fn normal_location(a: *mem.Arena, r: *rng.Rng, kind: usize, z: []const f64, sz: []const usize, m: usize, nrep: usize, res: []f64) -> err {
    var n = 0usize
    var g = 0usize
    while g < sz.len {
        n += sz[g]
        g += 1usize
    }
    var ll = 0.0f64
    var df = f64(m)
    if kind == 0usize { ll = loglik_one(a, z, n, m) }
    if kind == 1usize {
        ll = loglik_equal(a, z, sz, m)
        df = f64((sz.len - 1usize) * m)
    }
    if kind == 2usize {
        ll = loglik_diff(a, z, sz, m)
        df = f64((sz.len - 1usize) * m)
    }
    res[0usize] = ll
    res[1usize] = df
    if nrep == 0usize {
        res[2usize] = better_p(1.0f64 - nm.pchisq(ll, df, true, false), 3usize)
        ret ok
    }
    let (buf, e) = mem.alloc[f64](a, n * m)
    if e != ok { ret e }
    var le = 0usize
    var cnt = 0usize
    var rr = 0usize
    while rr < nrep {
        let start = mem.mark(a)
        // rnorm(n m) fills a matrix column by column: the draw j * n + i is the entry (i, j)
        var off = 0usize
        var gg = 0usize
        while gg < sz.len {
            let ng = sz[gg]
            var q = 0usize
            while q < ng * m {
                let v = rng.norm(r)
                let col = q / ng
                let row = q % ng
                buf[(off + row) * m + col] = v
                q += 1usize
            }
            off += ng
            gg += 1usize
        }
        var s = 0.0f64
        if kind == 0usize { s = loglik_one(a, buf, n, m) }
        if kind == 1usize { s = loglik_equal(a, buf, sz, m) }
        if kind == 2usize { s = loglik_diff(a, buf, sz, m) }
        mem.reset(a, start)
        if ll <= s { cnt += 1usize }
        rr += 1usize
    }
    // mean(logLik <= c(sample, logLik)): the observed value counts as one replicate
    le = cnt + 1usize
    var digits = 0usize
    var pw = 1usize
    while pw * 10usize <= nrep {
        pw *= 10usize
        digits += 1usize
    }
    res[2usize] = better_p(f64(le) / f64(nrep + 1usize), digits)
    ret ok
}

// Gauss.test(x, mean, sd, alternative): statistic mean(x), p value 6 digits; alternative 0 two.sided 1 less 2 greater
fn gauss_test(x: []const f64, mu: f64, sd: f64, alt: usize, res: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    let t = s / f64(x.len)
    let isd = math.sqrt[f64](sd * sd / f64(x.len))
    let p2 = dist.pnorm(t, mu, isd, true, false)
    let p1 = 1.0f64 - p2
    var pv = 0.0f64
    if alt == 0usize {
        var mn = p1
        if p2 < mn { mn = p2 }
        pv = 2.0f64 * mn
    }
    if alt == 1usize { pv = p2 }
    if alt == 2usize { pv = p1 }
    res[0usize] = t
    res[1usize] = better_p(pv, 6usize)
}

// ---- the energy test of normality ----

// gsl hyperg_1F1(-1/2, b, x) for x <= 0 through Kummer's transformation e^x M(b + 1/2, b, -x), a series of positive terms
fn hyperg_m(b: f64, x: f64) -> f64 {
    let z = 0.0f64 - x
    let ap = b + 0.5f64
    var term = 1.0f64
    var sum = 1.0f64
    var k = 0usize
    while k < 100000usize {
        let kk = f64(k)
        term = term * (ap + kk) / (b + kk) * z / (kk + 1.0f64)
        sum += term
        if term < 1.0e-18f64 * sum && f64(k) > z { break }
        k += 1usize
    }
    ret math.exp[f64](x) * sum
}

// energy:::mvnorm.e(x) for the n by d sample x (row-major): d = 1 is normal.e
fn mvnorm_e(a: *mem.Arena, x: []const f64, n: usize, d: usize) -> f64 {
    let nf = f64(n)
    if d == 1usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i]
            i += 1usize
        }
        let mn = s / nf
        var ss = 0.0f64
        i = 0usize
        while i < n {
            ss += (x[i] - mn) * (x[i] - mn)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / (nf - 1.0f64))
        let (y, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        i = 0usize
        while i < n {
            y[i] = (x[i] - mn) / sd
            i += 1usize
        }
        // sort ascending (insertion)
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
        var sm = 0.0f64
        var mk = 0.0f64
        i = 0usize
        while i < n {
            sm += 2.0f64 * y[i] * dist.pnorm(y[i], 0.0f64, 1.0f64, true, false) + 2.0f64 * dist.dnorm(y[i], 0.0f64, 1.0f64, false)
            let kv = f64(1usize + 2usize * i) - nf
            mk += kv * y[i]
            i += 1usize
        }
        ret 2.0f64 * (sm - nf / math.sqrt[f64](3.141592653589793f64) - mk / nf)
    }
    let (cv, e1) = mem.alloc[f64](a, d * d)
    let (mn, e2) = mem.alloc[f64](a, d)
    let (w, e3) = mem.alloc[f64](a, d)
    let (zv, e4) = mem.alloc[f64](a, d * d)
    let (z, e5) = mem.alloc[f64](a, n * d)
    let (y, e6) = mem.alloc[f64](a, n * d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan() }
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i * d + j]
            i += 1usize
        }
        mn[j] = s / nf
        j += 1usize
    }
    j = 0usize
    while j < d {
        var k = 0usize
        while k < d {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * d + j] - mn[j]) * (x[i * d + k] - mn[k])
                i += 1usize
            }
            cv[k * d + j] = s / (nf - 1.0f64)
            k += 1usize
        }
        j += 1usize
    }
    if sy.dsyevr_all(a, cv, d, w, zv) != ok { ret nan() }
    // y = z P D P', P D P' = sum_k v_k v_k' / sqrt(lambda_k)
    var i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            z[i * d + j] = x[i * d + j] - mn[j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                var c = 0.0f64
                var q = 0usize
                while q < d {
                    c += z[i * d + q] * zv[k * d + q]
                    q += 1usize
                }
                s += c * zv[k * d + j] / math.sqrt[f64](w[k])
                k += 1usize
            }
            y[i * d + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let c0 = math.exp[f64](nm.lgammafn((f64(d) + 1.0f64) / 2.0f64) - nm.lgammafn(f64(d) / 2.0f64))
    let mean2 = 2.0f64 * c0
    var m1 = 0.0f64
    i = 0usize
    while i < n {
        var ysq = 0.0f64
        j = 0usize
        while j < d {
            ysq += y[i * d + j] * y[i * d + j]
            j += 1usize
        }
        m1 += hyperg_m(f64(d) / 2.0f64, 0.0f64 - ysq / 2.0f64)
        i += 1usize
    }
    let mean1 = math.sqrt[f64](2.0f64) * c0 * (m1 / nf)
    var dsum = 0.0f64
    i = 0usize
    while i + 1usize < n {
        var q = i + 1usize
        while q < n {
            var s = 0.0f64
            j = 0usize
            while j < d {
                s += (y[i * d + j] - y[q * d + j]) * (y[i * d + j] - y[q * d + j])
                j += 1usize
            }
            dsum += math.sqrt[f64](s)
            q += 1usize
        }
        i += 1usize
    }
    let mean3 = 2.0f64 * dsum / (nf * nf)
    ret nf * (2.0f64 * mean1 - mean2 - mean3)
}

// acompNormalGOF.test(x, R) on the ilr coordinates z (n by d): the E-statistic and the Monte Carlo p value 1 - mean(t < t0) of R replicates (matrix(rnorm(n d), n, d))
// drawn from r; with nrep 0 the p value is NaN (NA)
fn energy_normal(a: *mem.Arena, r: *rng.Rng, z: []const f64, n: usize, d: usize, nrep: usize, res: []f64) -> err {
    let t0 = mvnorm_e(a, z, n, d)
    res[0usize] = t0
    res[1usize] = nan()
    if nrep == 0usize { ret ok }
    let (buf, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret e }
    var below = 0usize
    var rr = 0usize
    while rr < nrep {
        let start = mem.mark(a)
        var q = 0usize
        while q < n * d {
            let v = rng.norm(r)
            let col = q / n
            let row = q % n
            buf[row * d + col] = v
            q += 1usize
        }
        let s = mvnorm_e(a, buf, n, d)
        mem.reset(a, start)
        if s < t0 { below += 1usize }
        rr += 1usize
    }
    res[1usize] = 1.0f64 - f64(below) / f64(nrep)
    ret ok
}
