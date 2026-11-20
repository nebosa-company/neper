// R fda, eval.fd, deriv.fd and an unsmoothed pca.fd over the bases that are not B-splines: kind 1 Fourier (period), 2 monomial (par the exponents), 3 exponential (par the rates), 4 polygonal (par the argvals),
// on the range [lo, hi]. The basis rows are fa.gen_row, the integrals fa.inprod_coefs_k.

use e.algo.stat.fdabase as fb
use e.algo.stat.fdapkg as fa
use e.math
use e.mem

// eval.fd(x, fd(coefs, basis), Lfdobj = nd): sum c_j D^nd phi_j(x) for one curve
fn eval_fd_gen(a: *mem.Arena, kind: usize, period: f64, par: []const f64, nbasis: usize, coefs: []const f64, x: f64, nd: usize) -> f64 {
    let (v, e) = mem.alloc[f64](a, nbasis + 2usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if fa.gen_row(a, kind, period, par, nbasis, x, nd, v) != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var j = 0usize
    while j < nbasis {
        s += coefs[j] * v[j]
        j += 1usize
    }
    ret s
}

// deriv.fd(fd(coefs, basis), nd) for one curve: fda evaluates the derivative at 10 nbasis + 1 equally spaced points of [lo, hi] and projects it on the same basis (project.basis, the normal equations by Cholesky)
fn deriv_fd_gen(a: *mem.Arena, kind: usize, period: f64, par: []const f64, nbasis: usize, lo: f64, hi: f64, coefs: []const f64, nd: usize, out: []f64) -> err {
    let n = 10usize * nbasis + 1usize
    let (cm, e2) = mem.alloc[f64](a, nbasis * nbasis)
    let (v, e3) = mem.alloc[f64](a, nbasis + 2usize)
    let (w, e4) = mem.alloc[f64](a, nbasis + 2usize)
    let (rhs, e5) = mem.alloc[f64](a, nbasis)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var q = 0usize
    while q < nbasis * nbasis {
        cm[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nbasis {
        rhs[q] = 0.0f64
        q += 1usize
    }
    let by = (hi - lo) / f64(n - 1usize)
    var i = 0usize
    while i < n {
        let x = lo + f64(i) * by
        var e = fa.gen_row(a, kind, period, par, nbasis, x, 0usize, v)
        if e != ok { ret e }
        e = fa.gen_row(a, kind, period, par, nbasis, x, nd, w)
        if e != ok { ret e }
        var y = 0.0f64
        var j = 0usize
        while j < nbasis {
            y += coefs[j] * w[j]
            j += 1usize
        }
        j = 0usize
        while j < nbasis {
            rhs[j] += v[j] * y
            var k = 0usize
            while k < nbasis {
                cm[k * nbasis + j] += v[j] * v[k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret fb.spd_solve(a, cm, nbasis, rhs, out)
}

// the exact Gram matrix of eval.penalty(basis, 0) for the monomial, exponential and polygonal bases
fn gram_gen(kind: usize, par: []const f64, nbasis: usize, lo: f64, hi: f64, out: []f64) {
    var i = 0usize
    while i < nbasis {
        var j = 0usize
        while j < nbasis {
            var s = 0.0f64
            if kind == 2usize {
                let ip = par[i] + par[j] + 1.0f64
                s = (math.pow[f64](hi, ip) - math.pow[f64](lo, ip)) / ip
            }
            if kind == 3usize {
                let rs = par[i] + par[j]
                if rs != 0.0f64 {
                    s = (math.exp[f64](rs * hi) - math.exp[f64](rs * lo)) / rs
                } else {
                    s = hi - lo
                }
            }
            if kind == 4usize {
                let n = nbasis
                if i == j {
                    if i == 0usize { s = (par[1usize] - par[0usize]) / 3.0f64 }
                    if i == n - 1usize { s = (par[n - 1usize] - par[n - 2usize]) / 3.0f64 }
                    if i > 0usize && i < n - 1usize { s = (par[i + 1usize] - par[i - 1usize]) / 3.0f64 }
                }
                if i + 1usize == j { s = (par[j] - par[i]) / 6.0f64 }
                if j + 1usize == i { s = (par[i] - par[j]) / 6.0f64 }
            }
            out[j * nbasis + i] = s
            j += 1usize
        }
        i += 1usize
    }
}

// pca.fd(fd(coefs, basis)) with no smoothing over the monomial, exponential or polygonal basis: the exact Gram matrix, J = inprod(basis, basis) by Romberg integration; values and varprop as in fa.pca_fd_values
fn pca_fd_gen(a: *mem.Arena, kind: usize, par: []const f64, nbasis: usize, lo: f64, hi: f64, coefs: []const f64, nrep: usize, values: []f64, varprop: []f64) -> err {
    let (gm, e1) = mem.alloc[f64](a, nbasis * nbasis)
    let (jm, e2) = mem.alloc[f64](a, nbasis * nbasis)
    let (id, e3) = mem.alloc[f64](a, nbasis * nbasis)
    let (br, e4) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    br[0usize] = lo
    br[1usize] = hi
    var q = 0usize
    while q < nbasis * nbasis {
        id[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nbasis {
        id[q * nbasis + q] = 1.0f64
        q += 1usize
    }
    gram_gen(kind, par, nbasis, lo, hi, gm)
    let e = fa.inprod_coefs_k(a, kind, 0.0f64, par, nbasis, br, id, nbasis, id, nbasis, jm)
    if e != ok { ret e }
    ret fa.pca_fd_values(a, gm, jm, coefs, nbasis, nrep, values, varprop)
}
