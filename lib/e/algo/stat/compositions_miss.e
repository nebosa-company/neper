// R compositions: missing and zero parts in acomp data (the clr over the observed parts `cdt`, `mean.acomp` by the missing-value projectors,
// `var.acomp` on the complete rows) and the seeded generators rnorm.acomp, rnorm.rcomp and rDirichlet.acomp.
//
// Data are n by D, row-major; a missing or zero part is NaN or <= 0.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.compositions as cp
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nmv(v: f64) -> bool { ret v - v == 0.0f64 && v > 0.0f64 }

// the covariance matrix (divisor n - 1) of the n by m row-major c
fn cov_rows(c: []const f64, n: usize, m: usize, out: []f64) {
    var j = 0usize
    while j < m {
        var k = 0usize
        while k <= j {
            var mj = 0.0f64
            var mk = 0.0f64
            var i = 0usize
            while i < n {
                mj += c[i * m + j]
                mk += c[i * m + k]
                i += 1usize
            }
            mj = mj / f64(n)
            mk = mk / f64(n)
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += (c[i * m + j] - mj) * (c[i * m + k] - mk)
                i += 1usize
            }
            out[j * m + k] = s / f64(n - 1usize)
            out[k * m + j] = s / f64(n - 1usize)
            k += 1usize
        }
        j += 1usize
    }
}

// cdt.acomp: the clr over the observed parts of each row, zero for the missing ones
fn cdt_missing(x: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var cnt = 0.0f64
        var j = 0usize
        while j < d {
            if is_nmv(x[i * d + j]) {
                s += math.log[f64](x[i * d + j])
                cnt += 1.0f64
            }
            j += 1usize
        }
        j = 0usize
        while j < d {
            if is_nmv(x[i * d + j]) { out[i * d + j] = math.log[f64](x[i * d + j]) - s / cnt } else { out[i * d + j] = 0.0f64 }
            j += 1usize
        }
        i += 1usize
    }
}

// mean.acomp with missing parts: the closed exp of svdsolve(sumMissingProjector, column sums of the observed clr), singular values below 1e-10 of the largest dropped
fn mean_missing(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> err {
    let (cd, e1) = mem.alloc[f64](a, n * d)
    let (p, e2) = mem.alloc[f64](a, d * d)
    let (cs, e3) = mem.alloc[f64](a, d)
    let (canz, e4) = mem.alloc[f64](a, d)
    let (ranz, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    cdt_missing(x, n, d, cd)
    var j = 0usize
    while j < d {
        cs[j] = 0.0f64
        canz[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        ranz[i] = 0.0f64
        j = 0usize
        while j < d {
            if is_nmv(x[i * d + j]) {
                canz[j] += 1.0f64
                ranz[i] += 1.0f64
            }
            cs[j] += cd[i * d + j]
            j += 1usize
        }
        i += 1usize
    }
    // P = diag(canz) - t(has / ranz) %*% has
    var r = 0usize
    while r < d {
        var c = 0usize
        while c < d {
            var s = 0.0f64
            i = 0usize
            while i < n {
                var rz = ranz[i]
                if rz <= 0.0f64 { rz = 1.0f64 }
                var h1 = 0.0f64
                var h2 = 0.0f64
                if is_nmv(x[i * d + r]) { h1 = 1.0f64 }
                if is_nmv(x[i * d + c]) { h2 = 1.0f64 }
                s += h1 / rz * h2
                i += 1usize
            }
            var v = 0.0f64 - s
            if r == c { v += canz[r] }
            p[c * d + r] = v
            c += 1usize
        }
        r += 1usize
    }
    let (sv, es) = decomp.svd(a, p, d, d)
    if es != ok { ret es }
    var l1 = 0.0f64
    j = 0usize
    while j < sv.k {
        if sv.d[j] > l1 { l1 = sv.d[j] }
        j += 1usize
    }
    let (est, e6) = mem.alloc[f64](a, d)
    if e6 != ok { ret e6 }
    j = 0usize
    while j < d {
        est[j] = 0.0f64
        j += 1usize
    }
    var k = 0usize
    while k < sv.k {
        if !(sv.d[k] < l1 * 1.0e-10f64) {
            var ut = 0.0f64
            r = 0usize
            while r < d {
                ut += sv.u[k * d + r] * cs[r]
                r += 1usize
            }
            r = 0usize
            while r < d {
                est[r] += sv.v[k * d + r] * ut / sv.d[k]
                r += 1usize
            }
        }
        k += 1usize
    }
    var tot = 0.0f64
    j = 0usize
    while j < d {
        out[j] = math.exp[f64](est[j])
        tot += out[j]
        j += 1usize
    }
    j = 0usize
    while j < d {
        out[j] = out[j] / tot
        j += 1usize
    }
    ret ok
}

// var.acomp with missing parts and use = "all.obs": the clr covariance (D by D in out) of the rows whose parts are all observed; answers how many rows that is
fn var_complete(a: *mem.Arena, x: []const f64, n: usize, d: usize, out: []f64) -> usize {
    let (rows, e) = mem.alloc[f64](a, n * d)
    if e != ok { ret 0usize }
    var m = 0usize
    var i = 0usize
    while i < n {
        var full = true
        var j = 0usize
        while j < d {
            if !is_nmv(x[i * d + j]) { full = false }
            j += 1usize
        }
        if full {
            j = 0usize
            while j < d {
                rows[m * d + j] = x[i * d + j]
                j += 1usize
            }
            m += 1usize
        }
        i += 1usize
    }
    if m < 2usize { ret m }
    let (c, e2) = mem.alloc[f64](a, m * d)
    if e2 != ok { ret 0usize }
    if cp.clr_closed(a, rows[0usize..m * d], m, d, c) != ok { ret 0usize }
    cov_rows(c, m, d, out)
    ret m
}

// the lower Cholesky factor of the ilr variance V' var V (m = D - 1) of the D by D row-major clr variance vr
fn ilr_var_chol(a: *mem.Arena, vr: []const f64, d: usize, l: []f64) {
    let m = d - 1usize
    let (iv, e) = mem.alloc[f64](a, m * m)
    if e != ok { ret }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var p = 0usize
            while p < d {
                var q = 0usize
                while q < d {
                    s += cp.ilr_v(p, i) * vr[p * d + q] * cp.ilr_v(q, j)
                    q += 1usize
                }
                p += 1usize
            }
            iv[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m * m {
        l[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j <= i {
            var s = iv[i * m + j]
            var k = 0usize
            while k < j {
                s -= l[i * m + k] * l[j * m + k]
                k += 1usize
            }
            if i == j { l[i * m + j] = math.sqrt[f64](s) } else { l[i * m + j] = s / l[j * m + j] }
            j += 1usize
        }
        i += 1usize
    }
}

// rnorm.acomp(n, mean, var): the n by D row-major composition draws, perturbed by mean; vr is the D by D clr variance
fn rnorm_acomp(a: *mem.Arena, r: *rng.Rng, n: usize, mean: []const f64, vr: []const f64, d: usize, out: []f64) -> err {
    let m = d - 1usize
    let (l, e2) = mem.alloc[f64](a, m * m)
    let (zz, e3) = mem.alloc[f64](a, n * m)
    let (y, e4) = mem.alloc[f64](a, n * m)
    let (c, e5) = mem.alloc[f64](a, n * d)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    ilr_var_chol(a, vr, d, l)
    // matrix(rnorm(n * m), ncol = m) fills column by column
    var k = 0usize
    while k < n * m {
        zz[(k % n) * m + k / n] = rng.norm(r)
        k += 1usize
    }
    // z %*% chol: the upper factor is the transpose of l
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var q = 0usize
            while q <= j {
                s += zz[i * m + q] * l[j * m + q]
                q += 1usize
            }
            y[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if cp.ilr_inv(a, y, n, d, c) != ok { ret mem.Full }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            out[i * d + j] = c[i * d + j] * mean[j]
            s += out[i * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = out[i * d + j] / s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// rnorm.rcomp(n, mean, var): rcomp(pmax(ilr2clr(z chol(ilr var)) + closed mean, 0)); the package adds the mean vector to the n by D matrix by plain recycling, column-major,
// so element (i, j) gets mean[(j n + i) mod D] (R warns of incompatible methods and falls back to that sum)
fn rnorm_rcomp(a: *mem.Arena, r: *rng.Rng, n: usize, mean: []const f64, vr: []const f64, d: usize, out: []f64) -> err {
    let m = d - 1usize
    let (l, e2) = mem.alloc[f64](a, m * m)
    let (zz, e3) = mem.alloc[f64](a, n * m)
    if e2 != ok || e3 != ok { ret mem.Full }
    ilr_var_chol(a, vr, d, l)
    var k = 0usize
    while k < n * m {
        zz[(k % n) * m + k / n] = rng.norm(r)
        k += 1usize
    }
    var msum = 0.0f64
    var i = 0usize
    while i < d {
        msum += mean[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var tot = 0.0f64
        var j = 0usize
        while j < d {
            var s = 0.0f64
            var q = 0usize
            while q < m {
                var yq = 0.0f64
                var p = 0usize
                while p <= q {
                    yq += zz[i * m + p] * l[q * m + p]
                    p += 1usize
                }
                s += yq * cp.ilr_v(j, q)
                q += 1usize
            }
            var v = s + mean[(j * n + i) % d] / msum
            if v < 0.0f64 { v = 0.0f64 }
            out[i * d + j] = v
            tot += v
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i * d + j] = out[i * d + j] / tot
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// rDirichlet.acomp(n, alpha): sapply(alpha, rgamma, n = n) closed, the columns drawn one after another; n by D row-major
fn rdirichlet(r: *rng.Rng, n: usize, alpha: []const f64, out: []f64) {
    let d = alpha.len
    var j = 0usize
    while j < d {
        var i = 0usize
        while i < n {
            out[i * d + j] = rd.rgamma(r, alpha[j], 1.0f64)
            i += 1usize
        }
        j += 1usize
    }
    var i2 = 0usize
    while i2 < n {
        var s = 0.0f64
        j = 0usize
        while j < d {
            s += out[i2 * d + j]
            j += 1usize
        }
        j = 0usize
        while j < d {
            out[i2 * d + j] = out[i2 * d + j] / s
            j += 1usize
        }
        i2 += 1usize
    }
}
