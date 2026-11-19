// R fpc: clusexpect, itnumber, minsize, distancefactor, randcmatrix, randconf, mahalanofix (method "ml"), mahalanofuz, localshape (mscatter "cov"), cat2bin and
// discrete.recode for numeric variables. Matrices are row-major.

use e.algo.rand.r as rg
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.math
use e.math.nmath_beta as nb
use e.mem

error Malformed

// R's choose(n, k) for an integer n and a small k: the product loop of nmath, forced to an integer
fn choose_r(n: f64, k: f64) -> f64 {
    if k < 2.0f64 {
        if k < 0.0f64 { ret 0.0f64 }
        if k == 0.0f64 { ret 1.0f64 }
        ret n
    }
    if n < k { ret 0.0f64 }
    var r = n
    var j = 2.0f64
    while j <= k {
        r = r * ((n - j + 1.0f64) / j)
        j += 1.0f64
    }
    ret math.round[f64](r)
}

fn clusexpect(n: f64, p: f64, cn: f64, ir: f64) -> f64 {
    ret ir * (choose_r(cn, p + 2.0f64) / choose_r(n, p + 2.0f64))
}

// itnumber(n, p, cn, mtf, prob, maxir)
fn itnumber(n: f64, p: f64, cn: f64, mtf: f64, prob: f64, maxir0: f64) -> f64 {
    var minir = 1.0f64
    var maxir = maxir0
    var ir = 0.0f64
    let ce = clusexpect(n, p, cn, 1.0f64)
    while true {
        if nb.qbinom(1.0f64 - prob, minir, ce, true, false) >= mtf {
            ir = minir
            break
        }
        if nb.qbinom(1.0f64 - prob, maxir, ce, true, false) < mtf {
            ir = maxir
            break
        }
        ir = math.round[f64]((minir + maxir) / 2.0f64)
        if nb.qbinom(1.0f64 - prob, ir, ce, true, false) < mtf {
            minir = ir
        } else {
            maxir = ir
        }
        if maxir <= minir + 1.0f64 { break }
    }
    ret ir
}

// minsize(n, p, ir, mtf, prob)
fn minsize(n: f64, p: f64, ir: f64, mtf: f64, prob: f64) -> f64 {
    var mincn = p + 2.0f64
    var maxcn = n - 1.0f64
    var cn = 0.0f64
    while true {
        if nb.qbinom(1.0f64 - prob, ir, clusexpect(n, p, mincn, 1.0f64), true, false) >= mtf {
            cn = mincn
            break
        }
        if nb.qbinom(1.0f64 - prob, ir, clusexpect(n, p, maxcn, 1.0f64), true, false) < mtf {
            cn = maxcn
            break
        }
        cn = math.round[f64]((mincn + maxcn) / 2.0f64)
        if nb.qbinom(1.0f64 - prob, ir, clusexpect(n, p, cn, 1.0f64), true, false) < mtf {
            mincn = cn
        } else {
            maxcn = cn
        }
        if maxcn <= mincn + 1.0f64 { break }
    }
    ret cn
}

// distancefactor(cat, n = , catsizes = , type, normfactor, qfactor): catsizes empty means rep(round(n / cat), cat); ordinal 0 categorical, 1 ordinal
fn distancefactor(cat: usize, n: f64, catsizes: []const f64, ordinal: bool, normfactor: f64, qfactor: f64) -> f64 {
    var nn = 0.0f64
    var i = 0usize
    while i < cat {
        if catsizes.len == 0usize {
            nn += math.round[f64](n / f64(cat))
        } else {
            nn += catsizes[i]
        }
        i += 1usize
    }
    let overall = (nn + 1.0f64) * nn / 2.0f64
    var out = 0.0f64
    if !ordinal {
        var wit = 0.0f64
        i = 0usize
        while i < cat {
            var s = math.round[f64](n / f64(cat))
            if catsizes.len != 0usize { s = catsizes[i] }
            wit += (s + 1.0f64) * s / 2.0f64
            i += 1usize
        }
        let bet = overall - wit
        out = math.sqrt[f64](qfactor * normfactor * overall / (2.0f64 * bet))
    } else {
        var bd = 0.0f64
        i = 0usize
        while i + 1usize < cat {
            var j = i + 1usize
            while j < cat {
                var si = math.round[f64](n / f64(cat))
                var sj = si
                if catsizes.len != 0usize {
                    si = catsizes[i]
                    sj = catsizes[j]
                }
                let d = f64(j - i)
                bd += d * d * si * sj
                j += 1usize
            }
            i += 1usize
        }
        out = math.sqrt[f64](qfactor * normfactor * overall / bd)
    }
    ret out
}

// randcmatrix(n, cln, p): the n by cln 0/1 membership matrix, redrawn until every column holds at least p + 3 ones
fn randcmatrix(g: *rg.Rng, n: usize, cln: usize, p: usize, m: []f64, summ: []usize) {
    var ct = 0usize
    while ct < p + 3usize {
        var i = 0usize
        while i < n * cln {
            m[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < cln {
            summ[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            let u = rg.unif(g)
            let nu = usize(math.round[f64](0.5f64 + f64(cln) * u)) - 1usize
            m[i * cln + nu] = 1.0f64
            summ[nu] += 1usize
            i += 1usize
        }
        ct = summ[0usize]
        i = 1usize
        while i < cln {
            if summ[i] < ct { ct = summ[i] }
            i += 1usize
        }
    }
}

// randconf(n, p): p of the n flags set, the positions drawn by sample(n, p)
fn randconf(a: *mem.Arena, g: *rg.Rng, n: usize, p: usize, gv: []f64) -> err {
    var i = 0usize
    while i < n {
        gv[i] = 0.0f64
        i += 1usize
    }
    let (s, e) = rg.sample_int(a, g, i64(n), i64(p), false)
    if e != ok { ret e }
    i = 0usize
    while i < p {
        gv[usize(s[i]) - 1usize] = 1.0f64
        i += 1usize
    }
    ret ok
}

// mahalanofix(x, gv, method = "ml") and mahalanofuz(x, gv): the distances md[n], the centre mg[p], the covariance covg[p * p] and its inverse covinv[p * p]; fuzzy 0 for the
// ml version (the mean and (ng - 1) / ng of the covariance of the rows with gv set), 1 for the weighted one
fn mahalanofix(a: *mem.Arena, x: []const f64, n: usize, p: usize, gv: []const f64, fuzzy: bool, unbiased: bool, md: []f64, mg: []f64, covg: []f64, covinv: []f64) -> err {
    var j = 0usize
    var i = 0usize
    if !fuzzy {
        let (cl, e0) = mem.alloc[usize](a, n)
        if e0 != ok { ret Malformed }
        var ng = 0usize
        i = 0usize
        while i < n {
            cl[i] = 0usize
            if gv[i] != 0.0f64 {
                cl[i] = 1usize
                ng += 1usize
            }
            i += 1usize
        }
        fc.col_means(x, n, p, cl, 1usize, mg)
        let (k, e1) = fp.cov_rows(a, x, n, p, cl, 1usize, covg)
        if e1 != ok { ret e1 }
        // unbiased is method "classical" (cov.rob's cov.wt covariance with the n - 1 divisor), otherwise "ml"
        j = 0usize
        while j < p * p && !unbiased {
            covg[j] = f64(k - 1usize) * covg[j] / f64(k)
            j += 1usize
        }
    } else {
        var sw = 0.0f64
        i = 0usize
        while i < n {
            sw += gv[i]
            i += 1usize
        }
        j = 0usize
        while j < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += gv[i] / sw * x[i * p + j]
                i += 1usize
            }
            mg[j] = s
            j += 1usize
        }
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                covg[r * p + c] = fp.cov_wml(x, n, p, gv, r, c)
                c += 1usize
            }
            r += 1usize
        }
    }
    let e2 = fp.lu_inverse(a, covg, p, covinv)
    if e2 != ok { ret e2 }
    ret fc.mahal_rows(a, x, n, p, mg, covinv, md)
}

// localshape(xdata, proportion, mscatter = "cov", covstandard): 0 trace, 1 det, 2 none
fn localshape(a: *mem.Arena, x: []const f64, n: usize, p: usize, proportion: f64, covstandard: usize, lcov: []f64) -> err {
    let (cl0, e0) = mem.alloc[usize](a, n)
    let (cl, e1) = mem.alloc[usize](a, n)
    let (scatter, e2) = mem.alloc[f64](a, p * p)
    let (sinv, e3) = mem.alloc[f64](a, p * p)
    let (mm, e4) = mem.alloc[f64](a, n)
    let (idx, e5) = mem.alloc[usize](a, n)
    let (xc, e6) = mem.alloc[f64](a, p * p)
    let (mu, e7) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        cl0[i] = 1usize
        i += 1usize
    }
    let (kk, e8) = fp.cov_rows(a, x, n, p, cl0, 1usize, scatter)
    if e8 != ok { ret e8 }
    let e9 = fp.lu_inverse(a, scatter, p, sinv)
    if e9 != ok { ret e9 }
    let np = usize(math.round[f64](proportion * f64(n)))
    var j = 0usize
    while j < p * p {
        lcov[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < p {
            mu[j] = x[i * p + j]
            j += 1usize
        }
        let e10 = fc.mahal_rows(a, x, n, p, mu, sinv, mm)
        if e10 != ok { ret e10 }
        var q = 0usize
        while q < n {
            idx[q] = q
            q += 1usize
        }
        q = 1usize
        while q < n {
            let t = idx[q]
            var w = q
            while w > 0usize && mm[idx[w - 1usize]] > mm[t] {
                idx[w] = idx[w - 1usize]
                w -= 1usize
            }
            idx[w] = t
            q += 1usize
        }
        q = 0usize
        while q < n {
            cl[q] = 0usize
            q += 1usize
        }
        q = 0usize
        while q < np {
            cl[idx[q]] = 1usize
            q += 1usize
        }
        let (k2, e11) = fp.cov_rows(a, x, n, p, cl, 1usize, xc)
        if e11 != ok { ret e11 }
        var f = 1.0f64
        if covstandard == 0usize {
            var tr = 0.0f64
            j = 0usize
            while j < p {
                tr += xc[j * p + j]
                j += 1usize
            }
            f = 1.0f64 / tr
        }
        if covstandard == 1usize {
            let (dt, e12) = fp.lu_det(a, xc, p)
            if e12 != ok { ret e12 }
            f = 1.0f64 / dt
        }
        j = 0usize
        while j < p * p {
            lcov[j] += xc[j] * f
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < p * p {
        lcov[j] = lcov[j] / f64(n)
        j += 1usize
    }
    ret ok
}

// discrete.recode for one column: out[i] is the 1-based rank of v[i] among the sorted distinct values; the count of distinct values is returned
fn recode_col(v: []const f64, n: usize, out: []f64) -> usize {
    var cnt = 0usize
    var i = 0usize
    while i < n {
        var seen = 0usize
        var j = 0usize
        while j < n {
            if v[j] < v[i] {
                var dup = false
                var q = 0usize
                while q < j {
                    if v[q] == v[j] { dup = true }
                    q += 1usize
                }
                if !dup { seen += 1usize }
            }
            j += 1usize
        }
        out[i] = f64(seen + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < n {
        if out[i] > f64(cnt) { cnt = usize(out[i]) }
        i += 1usize
    }
    ret cnt
}
