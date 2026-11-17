// R fda, the B-spline basis of create.bspline.basis and its eval.basis: order `norder` on the breaks (the end points included), nbasis = number of breaks + norder - 2 values at x, the derivative of order `deriv`.
//
// Not here: the Fourier and other bases, smooth.basis and the roughness penalty, fd objects and the functional-data analyses.

use e.algo.stat.bayesmpkg as bz
use e.algo.stat.splines as sp
use e.math
use e.mem

// out receives the nbasis basis values (or derivatives) at x
fn eval_bspline(a: *mem.Arena, norder: usize, breaks: []const f64, x: f64, deriv: usize, out: []f64) -> err {
    let degree = norder - 1usize
    let nint = breaks.len - 2usize
    let (t, e1) = mem.alloc[f64](a, nint + 2usize * norder + 2usize)
    let (tmp, e2) = mem.alloc[f64](a, 4usize * norder + 8usize)
    let (o, e3) = mem.alloc[f64](a, nint + norder + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let cnt = sp.row(t, tmp, breaks[1usize..breaks.len - 1usize], breaks[0usize], breaks[breaks.len - 1usize], degree, true, 0u8, deriv, x, o)
    var i = 0usize
    while i < cnt {
        out[i] = o[i]
        i += 1usize
    }
    ret ok
}


// the m-point Gauss-Legendre nodes and weights on [-1, 1], by Newton's method on the Legendre polynomial
fn gauss_legendre(m: usize, nodes: []f64, wts: []f64) {
    var i = 0usize
    while i < m {
        var z = math.cos[f64](3.141592653589793f64 * (f64(i) + 0.75f64) / (f64(m) + 0.5f64))
        var pp = 1.0f64
        var it = 0usize
        while it < 100usize {
            var p1 = 1.0f64
            var p2 = 0.0f64
            var j = 0usize
            while j < m {
                let p3 = p2
                p2 = p1
                p1 = ((2.0f64 * f64(j) + 1.0f64) * z * p2 - f64(j) * p3) / (f64(j) + 1.0f64)
                j += 1usize
            }
            pp = f64(m) * (z * p1 - p2) / (z * z - 1.0f64)
            let z1 = z
            z = z1 - p1 / pp
            if math.abs[f64](z - z1) < 1.0e-15f64 { break }
            it += 1usize
        }
        nodes[i] = z
        wts[i] = 2.0f64 / ((1.0f64 - z * z) * pp * pp)
        i += 1usize
    }
}

// the roughness penalty matrix of getbasispenalty(basis, Lfdobj = m-th derivative): the integrals of D^m phi_i D^m phi_j over the range, exact by Gauss-Legendre quadrature on every break interval; nbasis by nbasis, column-major in out
fn penalty_matrix(a: *mem.Arena, norder: usize, breaks: []const f64, m: usize, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let ng = 10usize
    let (nodes, e1) = mem.alloc[f64](a, ng)
    let (wts, e2) = mem.alloc[f64](a, ng)
    let (v, e3) = mem.alloc[f64](a, nb + norder)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    gauss_legendre(ng, nodes, wts)
    var q = 0usize
    while q < nb * nb {
        out[q] = 0.0f64
        q += 1usize
    }
    var iv = 0usize
    while iv + 1usize < breaks.len {
        let lo = breaks[iv]
        let hi = breaks[iv + 1usize]
        var g = 0usize
        while g < ng {
            let x = 0.5f64 * (hi - lo) * nodes[g] + 0.5f64 * (hi + lo)
            let wgt = 0.5f64 * (hi - lo) * wts[g]
            // evaluate just inside the interval so the right-continuous basis uses this interval's polynomial
            let e = eval_bspline(a, norder, breaks, x, m, v)
            if e != ok { ret e }
            var i = 0usize
            while i < nb {
                var j = 0usize
                while j < nb {
                    out[j * nb + i] += wgt * v[i] * v[j]
                    j += 1usize
                }
                i += 1usize
            }
            g += 1usize
        }
        iv += 1usize
    }
    ret ok
}

// smooth.basis(argvals, y, fdPar(basis, Lfdobj = m, lambda)): the coefficients (Phi' Phi + lambda R)^-1 Phi' y of the penalised least squares fit with unit weights; coef has nbasis values
fn smooth_basis(a: *mem.Arena, norder: usize, breaks: []const f64, argvals: []const f64, y: []const f64, m: usize, lambda: f64, coef: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let n = argvals.len
    let (r, e1) = mem.alloc[f64](a, nb * nb)
    let (lhs, e2) = mem.alloc[f64](a, nb * nb)
    let (rhs, e3) = mem.alloc[f64](a, nb)
    let (v, e4) = mem.alloc[f64](a, nb + norder)
    let (u, e5) = mem.alloc[f64](a, nb * nb)
    let (iu, e6) = mem.alloc[f64](a, nb * nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    let e = penalty_matrix(a, norder, breaks, m, r)
    if e != ok { ret e }
    var q = 0usize
    while q < nb * nb {
        lhs[q] = lambda * r[q]
        q += 1usize
    }
    q = 0usize
    while q < nb {
        rhs[q] = 0.0f64
        q += 1usize
    }
    var t = 0usize
    while t < n {
        let e2b = eval_bspline(a, norder, breaks, argvals[t], 0usize, v)
        if e2b != ok { ret e2b }
        var i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                lhs[j * nb + i] += v[i] * v[j]
                j += 1usize
            }
            rhs[i] += v[i] * y[t]
            i += 1usize
        }
        t += 1usize
    }
    if !bz.chol_upper(lhs, nb, u) { ret mem.Full }
    bz.inv_upper(u, nb, iu)
    // solution = iu iu' rhs
    var i = 0usize
    while i < nb {
        var s = 0.0f64
        var j = 0usize
        while j < nb {
            var inv = 0.0f64
            var k = 0usize
            while k < nb {
                inv += iu[k * nb + i] * iu[k * nb + j]
                k += 1usize
            }
            s += inv * rhs[j]
            j += 1usize
        }
        coef[i] = s
        i += 1usize
    }
    ret ok
}

// the Fourier basis of create.fourier.basis(rangeval, nbasis, period) at x and its derivative of order deriv: the constant 1 / sqrt(period), then for j = 1 ..: sin(j w x) / sqrt(period / 2) and cos(j w x) / sqrt(period / 2), w = 2 pi / period
fn eval_fourier(nbasis: usize, period: f64, x: f64, deriv: usize, out: []f64) {
    let w = 6.283185307179586f64 / period
    let cs = 1.0f64 / math.sqrt[f64](period)
    let sc = 1.0f64 / math.sqrt[f64](period / 2.0f64)
    var i = 0usize
    while i < nbasis {
        if i == 0usize {
            out[0usize] = 0.0f64
            if deriv == 0usize { out[0usize] = cs }
        } else {
            let j = f64((i + 1usize) / 2usize)
            let jw = j * w
            let isin = i % 2usize == 1usize
            // d^k / dx^k of sin(jw x) and cos(jw x): the pair rotates by a quarter turn each derivative
            var amp = sc
            var kk = 0usize
            while kk < deriv {
                amp = amp * jw
                kk += 1usize
            }
            let ph = f64(deriv % 4usize)
            // sin: sin(t + k pi / 2); cos: cos(t + k pi / 2)
            let t = jw * x
            if isin {
                out[i] = amp * math.sin[f64](t + ph * 1.5707963267948966f64)
            } else {
                out[i] = amp * math.cos[f64](t + ph * 1.5707963267948966f64)
            }
        }
        i += 1usize
    }
}

// smooth.basis with weights wt (empty for unit weights): out = (df, sse, gcv) with df = trace(Phi (Phi' W Phi + lambda R)^-1 Phi' W), sse = sum (y - fit)^2 (unweighted, as fda reports it) and gcv = (sse / n) / ((n - df) / n)^2; coef receives the coefficients
fn smooth_basis_stats(a: *mem.Arena, norder: usize, breaks: []const f64, argvals: []const f64, y: []const f64, wt: []const f64, m: usize, lambda: f64, coef: []f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let n = argvals.len
    let (r, e1) = mem.alloc[f64](a, nb * nb)
    let (lhs, e2) = mem.alloc[f64](a, nb * nb)
    let (rhs, e3) = mem.alloc[f64](a, nb)
    let (v, e4) = mem.alloc[f64](a, nb + norder)
    let (u, e5) = mem.alloc[f64](a, nb * nb)
    let (iu, e6) = mem.alloc[f64](a, nb * nb)
    let (inv, e7) = mem.alloc[f64](a, nb * nb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    let e = penalty_matrix(a, norder, breaks, m, r)
    if e != ok { ret e }
    var q = 0usize
    while q < nb * nb {
        lhs[q] = lambda * r[q]
        q += 1usize
    }
    q = 0usize
    while q < nb {
        rhs[q] = 0.0f64
        q += 1usize
    }
    var t = 0usize
    while t < n {
        var wv = 1.0f64
        if wt.len == n { wv = wt[t] }
        let e2b = eval_bspline(a, norder, breaks, argvals[t], 0usize, v)
        if e2b != ok { ret e2b }
        var i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                lhs[j * nb + i] += wv * v[i] * v[j]
                j += 1usize
            }
            rhs[i] += wv * v[i] * y[t]
            i += 1usize
        }
        t += 1usize
    }
    if !bz.chol_upper(lhs, nb, u) { ret mem.Full }
    bz.inv_upper(u, nb, iu)
    var i = 0usize
    while i < nb {
        var j = 0usize
        while j < nb {
            var s = 0.0f64
            var k = 0usize
            while k < nb {
                s += iu[k * nb + i] * iu[k * nb + j]
                k += 1usize
            }
            inv[j * nb + i] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        var s = 0.0f64
        var j = 0usize
        while j < nb {
            s += inv[j * nb + i] * rhs[j]
            j += 1usize
        }
        coef[i] = s
        i += 1usize
    }
    var df = 0.0f64
    var sse = 0.0f64
    t = 0usize
    while t < n {
        var wv = 1.0f64
        if wt.len == n { wv = wt[t] }
        let e2c = eval_bspline(a, norder, breaks, argvals[t], 0usize, v)
        if e2c != ok { ret e2c }
        var fit = 0.0f64
        i = 0usize
        while i < nb {
            fit += v[i] * coef[i]
            i += 1usize
        }
        var qf = 0.0f64
        i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                qf += v[i] * inv[j * nb + i] * v[j]
                j += 1usize
            }
            i += 1usize
        }
        df += wv * qf
        sse += (y[t] - fit) * (y[t] - fit)
        t += 1usize
    }
    let nf = f64(n)
    out[0usize] = df
    out[1usize] = sse
    out[2usize] = (sse / nf) / ((nf - df) / nf) / ((nf - df) / nf)
    ret ok
}
