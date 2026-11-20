// R fda, the B-spline basis of create.bspline.basis and its eval.basis: order `norder` on the breaks (the end points included), nbasis = number of breaks + norder - 2 values at x, the derivative of order `deriv`.
//
// Not here: the Fourier and other bases, smooth.basis and the roughness penalty, fd objects and the functional-data analyses.

use e.algo.linalg.decomp as dc
use e.algo.stat.bayesmpkg as bz
use e.algo.stat.splines as sp
use e.math
use e.mem

// create.monomial.basis: x^e of eval.basis, derivatives as fda's monomial() computes them: for 1 <= nderiv <= e the factor is e (e - 2) (e - 3) .. (e - nderiv), a quirk of fda that skips the (e - 1)
fn eval_monomial(e: f64, x: f64, nderiv: usize) -> f64 {
    if nderiv > 0usize {
        if f64(nderiv) > e { ret 0.0f64 }
        var fac = e
        var k = 2usize
        while k <= nderiv {
            fac = fac * (e - f64(k))
            k += 1usize
        }
        var q = 0usize
        var pw = 1.0f64
        while q < usize(e) - nderiv {
            pw = pw * x
            q += 1usize
        }
        ret fac * pw
    }
    var pw0 = 1.0f64
    var q0 = 0usize
    while q0 < usize(e) {
        pw0 = pw0 * x
        q0 += 1usize
    }
    ret pw0
}

// create.exponential.basis: exp(rate x), the derivative of order nderiv is rate^nderiv exp(rate x)
fn eval_exponential(rate: f64, x: f64, nderiv: usize) -> f64 {
    var r = 1.0f64
    var k = 0usize
    while k < nderiv {
        r = r * rate
        k += 1usize
    }
    ret r * math.exp[f64](rate * x)
}

// create.polygonal.basis(argvals): the hat functions, the order 2 B-splines on the argvals; fda's getbasismatrix passes no derivative order to polyg, so eval.basis answers the values whatever nderiv is
fn eval_polygonal(a: *mem.Arena, argvals: []const f64, x: f64, out: []f64) -> err {
    ret eval_bspline(a, 2usize, argvals, x, 0usize, out)
}

// the row of eval.basis at x for a basis other than the B-spline one: kind 1 Fourier (nbasis, period), 2 monomial (par the exponents), 3 exponential (par the rates), 4 polygonal (par the argvals); nd the derivative order
fn gen_row(a: *mem.Arena, kind: usize, period: f64, par: []const f64, nbasis: usize, x: f64, nd: usize, v: []f64) -> err {
    if kind == 1usize {
        eval_fourier(nbasis, period, x, nd, v)
        ret ok
    }
    if kind == 4usize { ret eval_polygonal(a, par, x, v) }
    var j = 0usize
    while j < nbasis {
        if kind == 2usize {
            v[j] = eval_monomial(par[j], x, nd)
        } else {
            v[j] = eval_exponential(par[j], x, nd)
        }
        j += 1usize
    }
    ret ok
}

// out receives the nbasis basis values (or derivatives) at x
fn eval_bspline(a: *mem.Arena, norder: usize, breaks: []const f64, x: f64, deriv: usize, out: []f64) -> err {
    let degree = norder - 1usize
    let nint = breaks.len - 2usize
    let (t, e1) = mem.alloc[f64](a, nint + 2usize * norder + 2usize)
    let (tmp, e2) = mem.alloc[f64](a, 4usize * norder + 8usize)
    let (o, e3) = mem.alloc[f64](a, nint + norder + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let cnt = sp.row(t, tmp, breaks[1usize..breaks.len - 1usize], breaks[0usize], breaks[breaks.len - 1usize], degree, true, 0u8, deriv, x, o)
    // fda answers zero for the highest derivative at the right end point
    if x == breaks[breaks.len - 1usize] && deriv >= norder - 1usize {
        var z0 = 0usize
        while z0 < cnt {
            o[z0] = 0.0f64
            z0 += 1usize
        }
    }
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
    if breaks.len == 2usize {
        // fda: with no interior knots bsplinepen answers the penalty of the MONOMIAL basis x^0 .. x^(nbasis - 1) (monomialpen), not that of the B-splines
        var i0 = 0usize
        while i0 < nb {
            var j0 = 0usize
            while j0 < nb {
                out[j0 * nb + i0] = 0.0f64
                if i0 >= m && j0 >= m {
                    var ifac = 1.0f64
                    var jfac = 1.0f64
                    var k0 = 0usize
                    while k0 < m {
                        ifac = ifac * (f64(i0) - f64(k0))
                        jfac = jfac * (f64(j0) - f64(k0))
                        k0 += 1usize
                    }
                    let ipow = i0 + j0 - 2usize * m + 1usize
                    var phi = 1.0f64
                    var plo = 1.0f64
                    var q0 = 0usize
                    while q0 < ipow {
                        phi = phi * breaks[1usize]
                        plo = plo * breaks[0usize]
                        q0 += 1usize
                    }
                    out[j0 * nb + i0] = (phi - plo) * ifac * jfac / f64(ipow)
                }
                j0 += 1usize
            }
            i0 += 1usize
        }
        ret ok
    }
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


// fda numerical inprod(basis, basis) for a B-spline basis with simple knots: Romberg integration (NR qromb with fda tolerances, JMAX 15, JMIN 5, EPS 1e-4) of every product over the whole range at once, the convergence
// test taken over the whole matrix; out is nbasis by nbasis column-major. It differs from the exact Gram matrix at the 1e-5 level, which is what pca.fd and the other inprod users see
// f[c] = sum_k v[k] coefs[c * nb + k]: the curves of a coefficient matrix at one point whose basis row is v
fn pair_values(v: []const f64, nb: usize, coefs: []const f64, n: usize, f: []f64) {
    var c = 0usize
    while c < n {
        var s = 0.0f64
        var k = 0usize
        while k < nb {
            s += v[k] * coefs[c * nb + k]
            k += 1usize
        }
        f[c] = s
        c += 1usize
    }
}

fn inprod_coefs(a: *mem.Arena, norder: usize, breaks: []const f64, c1: []const f64, n1: usize, c2: []const f64, n2: usize, out: []f64) -> err {
    ret inprod_coefs_k(a, 0usize, 0.0f64, breaks, norder, breaks, c1, n1, c2, n2, out)
}

// a basis for the integrals: kind 0 B-spline (norder, breaks), 1 Fourier, 2 monomial, 3 exponential, 4 polygonal (kinds 1 to 4: breaks are the two ends of the range, nbasis = norder, par as in gen_row), 5 the constant basis
type Bspec = struct { kind: usize, period: f64, par: []const f64, norder: usize, breaks: []const f64 }

fn spec_nbasis(b: *const Bspec) -> usize {
    if b.kind == 5usize { ret 1usize }
    ret b.breaks.len + b.norder - 2usize
}

// the basis row at x
fn basis_row(a: *mem.Arena, b: *const Bspec, x: f64, v: []f64) -> err {
    if b.kind == 5usize {
        v[0usize] = 1.0f64
        ret ok
    }
    if b.kind >= 1usize { ret gen_row(a, b.kind, b.period, b.par, spec_nbasis(b), x, 0usize, v) }
    ret eval_bspline(a, b.norder, b.breaks, x, 0usize, v)
}

// inprod_coefs for one basis of any kind: both coefficient matrices in the basis (kind 1 Fourier is over [breaks[0], breaks[last]] with the given period)
fn inprod_coefs_k(a: *mem.Arena, kind: usize, period: f64, par: []const f64, norder: usize, breaks: []const f64, c1: []const f64, n1: usize, c2: []const f64, n2: usize, out: []f64) -> err {
    let b = Bspec{ kind: kind, period: period, par: par, norder: norder, breaks: breaks }
    ret inprod_general(a, &b, c1, n1, &b, c2, n2, &b, c1[0usize..0usize], out)
}

// the curve values of both coefficient matrices at x, the second times the weight function when wc is not empty
fn point_values(a: *mem.Arena, b1: *const Bspec, c1: []const f64, n1: usize, b2: *const Bspec, c2: []const f64, n2: usize, w: *const Bspec, wc: []const f64, x: f64, v: []f64, v2: []f64, vw: []f64, f1: []f64, f2: []f64) -> err {
    var e = basis_row(a, b1, x, v)
    if e != ok { ret e }
    e = basis_row(a, b2, x, v2)
    if e != ok { ret e }
    pair_values(v, spec_nbasis(b1), c1, n1, f1)
    pair_values(v2, spec_nbasis(b2), c2, n2, f2)
    if wc.len > 0usize {
        e = basis_row(a, w, x, vw)
        if e != ok { ret e }
        var wv = 0.0f64
        var k = 0usize
        while k < wc.len {
            wv += vw[k] * wc[k]
            k += 1usize
        }
        k = 0usize
        while k < n2 {
            f2[k] = wv * f2[k]
            k += 1usize
        }
    }
    ret ok
}

// inprod(fd(c1, basis1), fd(c2, basis2), 0, 0, rng, wtfd) by fda's Romberg integration over the range of basis1; the weight function is wc in the basis w when wc is not empty
fn inprod_general(a: *mem.Arena, b1: *const Bspec, c1: []const f64, n1: usize, b2: *const Bspec, c2: []const f64, n2: usize, ws: *const Bspec, wc: []const f64, out: []f64) -> err {
    let nb = spec_nbasis(b1)
    let nb2 = spec_nbasis(b2)
    let nbw = spec_nbasis(ws)
    let breaks = b1.breaks
    let nn = n1 * n2
    let (f1, e8) = mem.alloc[f64](a, n1)
    let (f2, e9) = mem.alloc[f64](a, n2)
    if e8 != ok || e9 != ok { ret mem.Full }
    let jmaxp = 16usize
    let (sm, e1) = mem.alloc[f64](a, jmaxp * nn)
    let (v, e2) = mem.alloc[f64](a, nb + b1.norder + 2usize)
    let (v2, e2b) = mem.alloc[f64](a, nb2 + b2.norder + 2usize)
    let (vw, e2c) = mem.alloc[f64](a, nbw + ws.norder + 2usize)
    if e2b != ok || e2c != ok { ret mem.Full }
    let (cs, e3) = mem.alloc[f64](a, 5usize * nn)
    let (ds, e4) = mem.alloc[f64](a, 5usize * nn)
    let (y, e5) = mem.alloc[f64](a, nn)
    let (dy, e6) = mem.alloc[f64](a, nn)
    let (h, e7) = mem.alloc[f64](a, jmaxp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    let lo = breaks[0usize]
    let hi = breaks[breaks.len - 1usize]
    let width = hi - lo
    var k = 0usize
    while k < jmaxp {
        h[k] = 1.0f64
        k += 1usize
    }
    h[1usize] = 0.25f64
    k = 0usize
    while k < nn {
        sm[k] = 0.0f64
        k += 1usize
    }
    var side = 0usize
    while side < 2usize {
        var xe = lo
        if side == 1usize { xe = hi }
        let e = point_values(a, b1, c1, n1, b2, c2, n2, ws, wc, xe, v, v2, vw, f1, f2)
        if e != ok { ret e }
        var i = 0usize
        while i < n1 {
            var j = 0usize
            while j < n2 {
                sm[j * n1 + i] += width * f1[i] * f2[j] / 2.0f64
                j += 1usize
            }
            i += 1usize
        }
        side += 1usize
    }
    var tnm = 0.5f64
    var iter = 2usize
    var done = false
    while iter <= 15usize && !done {
        tnm = tnm * 2.0f64
        let del = width / tnm
        var npts = tnm
        if iter == 2usize { npts = 1.0f64 }
        k = 0usize
        while k < nn {
            sm[(iter - 1usize) * nn + k] = 0.0f64
            k += 1usize
        }
        var q = 0usize
        while f64(q) < npts {
            var xp = 0.5f64 * (lo + hi)
            if iter > 2usize { xp = lo + del / 2.0f64 + f64(q) * del }
            let e = point_values(a, b1, c1, n1, b2, c2, n2, ws, wc, xp, v, v2, vw, f1, f2)
            if e != ok { ret e }
            var i = 0usize
            while i < n1 {
                var j = 0usize
                while j < n2 {
                    sm[(iter - 1usize) * nn + j * n1 + i] += width * f1[i] * f2[j] / tnm
                    j += 1usize
                }
                i += 1usize
            }
            q += 1usize
        }
        k = 0usize
        while k < nn {
            sm[(iter - 1usize) * nn + k] = (sm[(iter - 2usize) * nn + k] + sm[(iter - 1usize) * nn + k]) / 2.0f64
            k += 1usize
        }
        if iter >= 5usize {
            var r = 0usize
            while r < 5usize {
                k = 0usize
                while k < nn {
                    cs[r * nn + k] = sm[(iter - 5usize + r) * nn + k]
                    ds[r * nn + k] = cs[r * nn + k]
                    k += 1usize
                }
                r += 1usize
            }
            k = 0usize
            while k < nn {
                y[k] = cs[4usize * nn + k]
                k += 1usize
            }
            var ns = 4usize
            var mm = 1usize
            while mm <= 4usize {
                var ii = 0usize
                while ii < 5usize - mm {
                    let ho = h[iter - 5usize + ii]
                    let hp = h[iter - 5usize + ii + mm]
                    k = 0usize
                    while k < nn {
                        let w = (cs[(ii + 1usize) * nn + k] - ds[ii * nn + k]) / (ho - hp)
                        ds[ii * nn + k] = hp * w
                        cs[ii * nn + k] = ho * w
                        k += 1usize
                    }
                    ii += 1usize
                }
                if 2usize * ns < 5usize - mm {
                    k = 0usize
                    while k < nn {
                        dy[k] = cs[ns * nn + k]
                        k += 1usize
                    }
                } else {
                    k = 0usize
                    while k < nn {
                        dy[k] = ds[(ns - 1usize) * nn + k]
                        k += 1usize
                    }
                    ns -= 1usize
                }
                k = 0usize
                while k < nn {
                    y[k] += dy[k]
                    k += 1usize
                }
                mm += 1usize
            }
            var errval = 0.0f64
            var ssq = 0.0f64
            k = 0usize
            while k < nn {
                if math.abs[f64](dy[k]) > errval { errval = math.abs[f64](dy[k]) }
                if math.abs[f64](y[k]) > ssq { ssq = math.abs[f64](y[k]) }
                out[k] = y[k]
                k += 1usize
            }
            var crit = errval
            if ssq > 0.0f64 { crit = errval / ssq }
            if crit < 0.0001f64 && iter >= 5usize { done = true }
        }
        if !done {
            if iter < 15usize {
                k = 0usize
                while k < nn {
                    sm[iter * nn + k] = sm[(iter - 1usize) * nn + k]
                    k += 1usize
                }
            }
            h[iter] = 0.25f64 * h[iter - 1usize]
            iter += 1usize
        }
    }
    ret ok
}


// inprod(basis, basis): the identity coefficient matrices
fn inprod_romberg(a: *mem.Arena, norder: usize, breaks: []const f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let (id, e) = mem.alloc[f64](a, nb * nb)
    if e != ok { ret e }
    var q = 0usize
    while q < nb * nb {
        id[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nb {
        id[q * nb + q] = 1.0f64
        q += 1usize
    }
    ret inprod_coefs(a, norder, breaks, id, nb, id, nb, out)
}

// pca.fd with no smoothing, the harmonics in the basis of the data: the eigenvalues in values (nbasis entries, descending, zero past min(nbasis, nrep)) and the proportions of variance in varprop. gram is the exact basis Gram matrix
// (penalty_matrix with m = 0, whose Cholesky factor M fda uses), jmat the inprod matrix (inprod_romberg); the eigenvalues are the squared singular values of M^-T J C / sqrt(nrep) with C the centred coefficients (nbasis by nrep, column-major)
fn pca_fd_values(a: *mem.Arena, gram: []const f64, jmat: []const f64, coefs: []const f64, nb: usize, nrep: usize, values: []f64, varprop: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, nb * nb)
    let (iu, e1b) = mem.alloc[f64](a, nb * nb)
    let (kk, e1c) = mem.alloc[f64](a, nb * nb)
    let (mc, e2) = mem.alloc[f64](a, nb * nrep)
    let (cm, e3) = mem.alloc[f64](a, nb)
    if e1 != ok || e1b != ok || e1c != ok || e2 != ok || e3 != ok { ret mem.Full }
    if !bz.chol_upper(gram, nb, u) { ret mem.Full }
    bz.inv_upper(u, nb, iu)
    var i = 0usize
    while i < nb {
        var j = 0usize
        while j < nb {
            var s = 0.0f64
            var q = 0usize
            while q <= i {
                s += iu[i * nb + q] * jmat[j * nb + q]
                q += 1usize
            }
            kk[j * nb + i] = s
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < nb {
        var s = 0.0f64
        var t = 0usize
        while t < nrep {
            s += coefs[t * nb + j]
            t += 1usize
        }
        cm[j] = s / f64(nrep)
        j += 1usize
    }
    i = 0usize
    while i < nb {
        var t = 0usize
        while t < nrep {
            var s = 0.0f64
            j = 0usize
            while j < nb {
                s += kk[j * nb + i] * (coefs[t * nb + j] - cm[j])
                j += 1usize
            }
            mc[t * nb + i] = s / math.sqrt[f64](f64(nrep))
            t += 1usize
        }
        i += 1usize
    }
    let (mt, e5) = mem.alloc[f64](a, nb * nrep)
    if e5 != ok { ret mem.Full }
    i = 0usize
    while i < nb {
        var t = 0usize
        while t < nrep {
            mt[i * nrep + t] = mc[t * nb + i]
            t += 1usize
        }
        i += 1usize
    }
    let (sv, e4) = dc.jacobi_svd(a, mt, nrep, nb)
    if e4 != ok { ret e4 }
    i = 0usize
    while i < nb {
        values[i] = 0.0f64
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < sv.d.len && i < nb {
        values[i] = sv.d[i] * sv.d[i]
        tot += values[i]
        i += 1usize
    }
    i = 0usize
    while i < nb {
        varprop[i] = values[i] / tot
        i += 1usize
    }
    ret ok
}

// eval.fd(x, fd(coefs, basis), Lfdobj = deriv) for a B-spline basis: the derivative of order deriv of the curve sum c_j phi_j at x
fn eval_fd_bspline(a: *mem.Arena, norder: usize, breaks: []const f64, coefs: []const f64, x: f64, deriv: usize) -> f64 {
    let nb = breaks.len + norder - 2usize
    let (v, e) = mem.alloc[f64](a, nb + norder)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if eval_bspline(a, norder, breaks, x, deriv, v) != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var j = 0usize
    while j < nb {
        s += coefs[j] * v[j]
        j += 1usize
    }
    ret s
}

// fRegress(y, list(const, xfd), list(const, fdPar(basis, 2, lambda))) for a scalar response and one functional covariate whose curves and coefficient function share a B-spline basis: Z = [1, x_i' J] with J the numerical inprod matrix of the basis,
// the penalised normal equations (Z' Z + diag(0, lambda R)) c = Z' y with R the second-derivative penalty; out receives the intercept then the nbasis coefficients of the regression function (xcoefs is nbasis by nobs, column-major)
fn fregress_scalar(a: *mem.Arena, norder: usize, breaks: []const f64, xcoefs: []const f64, nobs: usize, y: []const f64, lambda: f64, out: []f64) -> err {
    let nb = breaks.len + norder - 2usize
    let np = nb + 1usize
    let (jm, e1) = mem.alloc[f64](a, nb * nb)
    let (rm, e2) = mem.alloc[f64](a, nb * nb)
    let (z, e3) = mem.alloc[f64](a, nobs * np)
    let (lhs, e4) = mem.alloc[f64](a, np * np)
    let (rhs, e5) = mem.alloc[f64](a, np)
    let (u, e6) = mem.alloc[f64](a, np * np)
    let (iu, e7) = mem.alloc[f64](a, np * np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var e = inprod_romberg(a, norder, breaks, jm)
    if e != ok { ret e }
    e = penalty_matrix(a, norder, breaks, 2usize, rm)
    if e != ok { ret e }
    var i = 0usize
    while i < nobs {
        z[i] = 1.0f64
        var k = 0usize
        while k < nb {
            var s = 0.0f64
            var j = 0usize
            while j < nb {
                s += xcoefs[i * nb + j] * jm[k * nb + j]
                j += 1usize
            }
            z[(k + 1usize) * nobs + i] = s
            k += 1usize
        }
        i += 1usize
    }
    var p1 = 0usize
    while p1 < np {
        var p2 = 0usize
        while p2 < np {
            var s = 0.0f64
            i = 0usize
            while i < nobs {
                s += z[p1 * nobs + i] * z[p2 * nobs + i]
                i += 1usize
            }
            if p1 > 0usize && p2 > 0usize { s += lambda * rm[(p2 - 1usize) * nb + (p1 - 1usize)] }
            lhs[p2 * np + p1] = s
            p2 += 1usize
        }
        var sy = 0.0f64
        i = 0usize
        while i < nobs {
            sy += z[p1 * nobs + i] * y[i]
            i += 1usize
        }
        rhs[p1] = sy
        p1 += 1usize
    }
    if !bz.chol_upper(lhs, np, u) { ret mem.Full }
    bz.inv_upper(u, np, iu)
    p1 = 0usize
    while p1 < np {
        var s = 0.0f64
        var p2 = 0usize
        while p2 < np {
            var inv = 0.0f64
            var q = 0usize
            while q < np {
                inv += iu[q * np + p1] * iu[q * np + p2]
                q += 1usize
            }
            s += inv * rhs[p2]
            p2 += 1usize
        }
        out[p1] = s
        p1 += 1usize
    }
    ret ok
}
