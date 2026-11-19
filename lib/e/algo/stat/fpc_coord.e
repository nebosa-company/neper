// R fpc: adcoord, mvdcoord, awcoord and ancoord (method "classical"), the discriminant coordinates built from a between matrix and the covariance of the
// class. Matrices are row-major. Every product is summed left to right as the reference dgemm does, and every colMeans, rowSums and sum in extended
// precision as R does, because the sign of the last eigenvector follows the last bits of the matrix.

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.fpc as fp
use e.math
use e.math.nmath as nm
use e.mem

error Malformed

// c = a (ar by ac) times b (ac by bc)
fn mm(a: []const f64, ar: usize, ac: usize, b: []const f64, bc: usize, out: []f64) {
    var i = 0usize
    while i < ar {
        var j = 0usize
        while j < bc {
            var s = 0.0f64
            var q = 0usize
            while q < ac {
                s += a[i * ac + q] * b[q * bc + j]
                q += 1usize
            }
            out[i * bc + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn transpose(a: []const f64, r: usize, c: usize, out: []f64) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            out[j * r + i] = a[i * c + j]
            j += 1usize
        }
        i += 1usize
    }
}

// R's colMeans of the rows of x (n by p) with sel[row] == l: a long double sum divided by the count
fn col_means(x: []const f64, n: usize, p: usize, sel: []const usize, l: usize, out: []f64) {
    var cnt = 0usize
    var i = 0usize
    while i < n {
        if sel[i] == l { cnt += 1usize }
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var sh = 0.0f64
        var sl = 0.0f64
        i = 0usize
        while i < n {
            if sel[i] == l {
                let (h1, l1) = fp.dd_add(sh, sl, x[i * p + j], 0.0f64)
                sh = h1
                sl = l1
            }
            i += 1usize
        }
        let (qh, ql) = fp.dd_div(sh, sl, f64(cnt))
        out[j] = qh + ql
        j += 1usize
    }
}

// the eigen part every one of these shares: ev decreasing, units = Tinv V for T = tdecomp(s1) and the symmetric z = t(Tinv) b Tinv
fn coord_tail(a: *mem.Arena, s1: []const f64, bm: []const f64, p: usize, ev: []f64, units: []f64) -> err {
    let (tm, e1) = mem.alloc[f64](a, p * p)
    let (tinv, e2) = mem.alloc[f64](a, p * p)
    let (tt, e3) = mem.alloc[f64](a, p * p)
    let (tb, e4) = mem.alloc[f64](a, p * p)
    let (zm, e5) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Malformed }
    let e6 = fp.tdecomp(a, s1, p, tm)
    if e6 != ok { ret e6 }
    let e7 = fp.lu_inverse(a, tm, p, tinv)
    if e7 != ok { ret e7 }
    transpose(tinv, p, p, tt)
    mm(tt, p, p, bm, p, tb)
    mm(tb, p, p, tinv, p, zm)
    sym_lower(zm, p)
    ret eig_units(a, zm, tinv, p, 1.0f64, ev, units)
}

// LAPACK reads the lower triangle of the column-major matrix, the upper one of this row-major one: copy R's lower triangle over it
fn sym_lower(zm: []f64, p: usize) {
    var r = 0usize
    while r < p {
        var c = r + 1usize
        while c < p {
            zm[r * p + c] = zm[c * p + r]
            c += 1usize
        }
        r += 1usize
    }
}

// the eigen decomposition of zm in R's order, ev and units = left V scale
fn eig_units(a: *mem.Arena, zm: []const f64, left: []const f64, p: usize, scale: f64, ev: []f64, units: []f64) -> err {
    let (wv, e1) = mem.alloc[f64](a, p)
    let (vv, e2) = mem.alloc[f64](a, p * p)
    let (vr, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret Malformed }
    let e4 = sy.dsyevr_all(a, zm, p, wv, vv)
    if e4 != ok { ret e4 }
    var k = 0usize
    while k < p {
        ev[k] = wv[p - 1usize - k]
        var r = 0usize
        while r < p {
            vr[r * p + k] = vv[(p - 1usize - k) * p + r]
            r += 1usize
        }
        k += 1usize
    }
    mm(left, p, p, vr, p, units)
    var i = 0usize
    while i < p * p {
        units[i] = units[i] * scale
        i += 1usize
    }
    ret ok
}

fn project(x: []const f64, n: usize, p: usize, units: []const f64, proj: []f64) {
    mm(x, n, p, units, p, proj)
}

// adcoord(x, clvec, clnum): ci[i] is 1 for the points of the class
fn adcoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, ci: []const usize, ev: []f64, units: []f64, proj: []f64) -> err {
    let (lab, e1) = mem.alloc[usize](a, n)
    let (ones, e2) = mem.alloc[usize](a, n)
    let (s1, e3) = mem.alloc[f64](a, p * p)
    let (s2, e4) = mem.alloc[f64](a, p * p)
    let (st, e5) = mem.alloc[f64](a, p * p)
    let (bm, e6) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret Malformed }
    var cln = 0usize
    var i = 0usize
    while i < n {
        lab[i] = 2usize
        ones[i] = 1usize
        if ci[i] == 1usize {
            lab[i] = 1usize
            cln += 1usize
        }
        i += 1usize
    }
    let (_, e7) = fp.cov_rows(a, x, n, p, lab, 1usize, s1)
    let (_, e8) = fp.cov_rows(a, x, n, p, lab, 2usize, s2)
    let (_, e9) = fp.cov_rows(a, x, n, p, ones, 1usize, st)
    if e7 != ok || e8 != ok || e9 != ok { ret Malformed }
    let nf = f64(n)
    let cf = f64(cln)
    i = 0usize
    while i < p * p {
        let w1 = (cf - 1.0f64) * s1[i]
        bm[i] = (nf * (nf - 1.0f64) * st[i] - cf * w1 - (nf - cf) * (nf - cf - 1.0f64) * s2[i]) / (nf - cf)
        i += 1usize
    }
    let e10 = coord_tail(a, s1, bm, p, ev, units)
    if e10 != ok { ret e10 }
    project(x, n, p, units, proj)
    ret ok
}

// mvdcoord(x, clvecd, sphere = matrix or "none" when sphere is empty): cl holds the labels 1..kn
fn mvdcoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const usize, kn: usize, sphere: []const f64, ev: []f64, units: []f64, proj: []f64) -> err {
    let (z, e1) = mem.alloc[f64](a, n * p)
    let (yy, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret Malformed }
    var i = 0usize
    if sphere.len > 0usize {
        let (tm, e3) = mem.alloc[f64](a, p * p)
        if e3 != ok { ret e3 }
        let e4 = fp.tdecomp(a, sphere, p, tm)
        if e4 != ok { ret e4 }
        let e5 = fp.lu_inverse(a, tm, p, yy)
        if e5 != ok { ret e5 }
        mm(x, n, p, yy, p, z)
    } else {
        i = 0usize
        while i < n * p {
            z[i] = x[i]
            i += 1usize
        }
        i = 0usize
        while i < p * p {
            yy[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < p {
            yy[i * p + i] = 1.0f64
            i += 1usize
        }
    }
    let q = (kn - 1usize) * (p + 1usize)
    let (m0, e6) = mem.alloc[f64](a, p * q)
    let (mt, e7) = mem.alloc[f64](a, q * p)
    let (mmt, e8) = mem.alloc[f64](a, p * p)
    let (mx1, e9) = mem.alloc[f64](a, p)
    let (mxi, e10) = mem.alloc[f64](a, p)
    let (v1, e11) = mem.alloc[f64](a, p * p)
    let (vi, e12) = mem.alloc[f64](a, p * p)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret Malformed }
    col_means(z, n, p, cl, 1usize, mx1)
    let (_, e13) = fp.cov_rows(a, z, n, p, cl, 1usize, v1)
    if e13 != ok { ret e13 }
    var g = 2usize
    while g <= kn {
        col_means(z, n, p, cl, g, mxi)
        let (_, e14) = fp.cov_rows(a, z, n, p, cl, g, vi)
        if e14 != ok { ret e14 }
        var r = 0usize
        while r < p {
            m0[r * q + (g - 2usize)] = mxi[r] - mx1[r]
            var c = 0usize
            while c < p {
                m0[r * q + (kn - 1usize) + (g - 2usize) * p + c] = vi[r * p + c] - v1[r * p + c]
                c += 1usize
            }
            r += 1usize
        }
        g += 1usize
    }
    transpose(m0, p, q, mt)
    mm(m0, p, q, mt, p, mmt)
    sym_lower(mmt, p)
    let e15 = eig_units(a, mmt, yy, p, 1.0f64, ev, units)
    if e15 != ok { ret e15 }
    project(x, n, p, units, proj)
    ret ok
}

// R's mahalanobis(x, center, cov, inverted = TRUE) for every row of x
fn mahal_rows(a: *mem.Arena, x: []const f64, n: usize, p: usize, center: []const f64, cinv: []const f64, out: []f64) -> err {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (xm, e2) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            xc[i * p + j] = x[i * p + j] - center[j]
            j += 1usize
        }
        i += 1usize
    }
    mm(xc, n, p, cinv, p, xm)
    i = 0usize
    while i < n {
        var sh = 0.0f64
        var sl = 0.0f64
        var j = 0usize
        while j < p {
            let (h1, l1) = fp.dd_add(sh, sl, xm[i * p + j] * xc[i * p + j], 0.0f64)
            sh = h1
            sl = l1
            j += 1usize
        }
        out[i] = sh + sl
        i += 1usize
    }
    ret ok
}

// awcoord(x, clvecd, clnum, mahal, method = "classical", clweight, alpha, subsample = 0): wg gets the n weights (of the points of clxa)
fn awcoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, ci: []const usize, md: bool, clweight: bool, alpha: f64, ev: []f64, units: []f64, proj: []f64, wg: []f64) -> err {
    var cn = 0usize
    var i = 0usize
    while i < n {
        if ci[i] == 1usize { cn += 1usize }
        i += 1usize
    }
    let nc = n - cn
    let (clx, e1) = mem.alloc[f64](a, cn * p)
    let (clxc, e2) = mem.alloc[f64](a, nc * p)
    let (s1, e3) = mem.alloc[f64](a, p * p)
    let (mg, e4) = mem.alloc[f64](a, p)
    let (cinv, e5) = mem.alloc[f64](a, p * p)
    let (mah, e6) = mem.alloc[f64](a, n)
    let (d12, e7) = mem.alloc[f64](a, p * p)
    let (d22, e8) = mem.alloc[f64](a, p * p)
    let (d1, e9) = mem.alloc[f64](a, p)
    let (d2, e10) = mem.alloc[f64](a, p)
    let (bm, e11) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret Malformed }
    var i1 = 0usize
    var i0 = 0usize
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            if ci[i] == 1usize {
                clx[i1 * p + j] = x[i * p + j]
            } else {
                clxc[i0 * p + j] = x[i * p + j]
            }
            j += 1usize
        }
        if ci[i] == 1usize { i1 += 1usize } else { i0 += 1usize }
        i += 1usize
    }
    let (ones, e12) = mem.alloc[usize](a, cn)
    if e12 != ok { ret Malformed }
    i = 0usize
    while i < cn {
        ones[i] = 1usize
        i += 1usize
    }
    let (_, e13) = fp.cov_rows(a, clx, cn, p, ones, 1usize, s1)
    if e13 != ok { ret e13 }
    col_means(clx, cn, p, ones, 1usize, mg)
    let e14 = fp.lu_inverse(a, s1, p, cinv)
    if e14 != ok { ret e14 }
    // clxa: all points when clweight, else the points outside the class
    var na = nc
    var e15 = ok
    if clweight {
        na = n
        e15 = mahal_rows(a, x, n, p, mg, cinv, mah)
    } else {
        e15 = mahal_rows(a, clxc, nc, p, mg, cinv, mah)
    }
    if e15 != ok { ret e15 }
    var chi = nm.qchisq(alpha, f64(p), true, false)
    if md {
        i = 0usize
        while i < na {
            mah[i] = math.sqrt[f64](mah[i])
            i += 1usize
        }
        chi = math.sqrt[f64](chi)
    }
    i = 0usize
    while i < na {
        wg[i] = fp.cweight(mah[i], chi)
        i += 1usize
    }
    // the weights of the points outside the class (wg0) and, with clweight, inside it (wg1)
    let (wg0, e16) = mem.alloc[f64](a, nc)
    let (wg1, e17) = mem.alloc[f64](a, cn + 1usize)
    if e16 != ok || e17 != ok { ret Malformed }
    i1 = 0usize
    i0 = 0usize
    i = 0usize
    while i < na {
        if clweight {
            if ci[i] == 1usize {
                wg1[i1] = wg[i]
                i1 += 1usize
            } else {
                wg0[i0] = wg[i]
                i0 += 1usize
            }
        } else {
            wg0[i] = wg[i]
        }
        i += 1usize
    }
    var s0h = 0.0f64
    var s0l = 0.0f64
    i = 0usize
    while i < nc {
        let (h1, l1) = fp.dd_add(s0h, s0l, wg0[i], 0.0f64)
        s0h = h1
        s0l = l1
        i += 1usize
    }
    let wsum0 = s0h + s0l
    var s1h = 0.0f64
    var s1l = 0.0f64
    if clweight {
        i = 0usize
        while i < cn {
            let (h1, l1) = fp.dd_add(s1h, s1l, wg1[i], 0.0f64)
            s1h = h1
            s1l = l1
            i += 1usize
        }
    }
    let wsum1 = s1h + s1l
    i = 0usize
    while i < p * p {
        d12[i] = 0.0f64
        d22[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        d1[i] = 0.0f64
        d2[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < cn {
        var wi = 1.0f64
        if clweight { wi = wg1[i] }
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                if clweight {
                    d12[r * p + c] = d12[r * p + c] + wi * (clx[i * p + r] * clx[i * p + c])
                } else {
                    d12[r * p + c] = d12[r * p + c] + clx[i * p + r] * clx[i * p + c]
                }
                c += 1usize
            }
            if clweight {
                d1[r] = d1[r] + wi * clx[i * p + r]
            } else {
                d1[r] = d1[r] + clx[i * p + r]
            }
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nc {
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                d22[r * p + c] = d22[r * p + c] + wg0[i] * (clxc[i * p + r] * clxc[i * p + c])
                c += 1usize
            }
            d2[r] = d2[r] + wg0[i] * clxc[i * p + r]
            r += 1usize
        }
        i += 1usize
    }
    var wsum = wsum0 * f64(cn)
    if clweight {
        var th = 0.0f64
        var tl = 0.0f64
        var q1 = 0usize
        while q1 < cn {
            var q0 = 0usize
            while q0 < nc {
                let (h1, l1) = fp.dd_add(th, tl, wg0[q0] * wg1[q1], 0.0f64)
                th = h1
                tl = l1
                q0 += 1usize
            }
            q1 += 1usize
        }
        wsum = th + tl
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            let d21 = d1[r] * d2[c]
            let d21t = d1[c] * d2[r]
            if clweight {
                bm[r * p + c] = (((wsum0 * d12[r * p + c] - d21) - d21t) + wsum1 * d22[r * p + c]) / wsum
            } else {
                bm[r * p + c] = (((wsum0 * d12[r * p + c] - d21) - d21t) + f64(cn) * d22[r * p + c]) / wsum
            }
            c += 1usize
        }
        r += 1usize
    }
    let e18 = coord_tail(a, s1, bm, p, ev, units)
    if e18 != ok { ret e18 }
    project(x, n, p, units, proj)
    ret ok
}

// ancoord(x, clvecd, clnum, nn, method = "classical"): the nearest-neighbour between matrix around the points of the class. ok unless the matrix is zero.
fn ancoord(a: *mem.Arena, x: []const f64, n: usize, p: usize, ci: []const usize, nn: usize, ev: []f64, units: []f64, proj: []f64) -> err {
    var nc = 0usize
    var i = 0usize
    while i < n {
        if ci[i] == 1usize { nc += 1usize }
        i += 1usize
    }
    let (clxf, e1) = mem.alloc[f64](a, nc * p)
    let (ones, e2) = mem.alloc[usize](a, nc)
    let (s1, e3) = mem.alloc[f64](a, p * p)
    let (cinv, e4) = mem.alloc[f64](a, p * p)
    let (mds, e5) = mem.alloc[f64](a, n)
    let (omah, e6) = mem.alloc[usize](a, nn)
    let (omc, e7) = mem.alloc[usize](a, nn)
    let (xo, e8) = mem.alloc[f64](a, nn * p)
    let (bm, e9) = mem.alloc[f64](a, p * p)
    let (bi, e10) = mem.alloc[f64](a, p * p)
    let (mi, e11) = mem.alloc[f64](a, p)
    let (vi, e12) = mem.alloc[f64](a, p)
    let (vr, e13) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret Malformed }
    var k = 0usize
    i = 0usize
    while i < n {
        if ci[i] == 1usize {
            var j = 0usize
            while j < p {
                clxf[k * p + j] = x[i * p + j]
                j += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nc {
        ones[i] = 1usize
        i += 1usize
    }
    let (_, e14) = fp.cov_rows(a, clxf, nc, p, ones, 1usize, s1)
    if e14 != ok { ret e14 }
    let e15 = fp.lu_inverse(a, s1, p, cinv)
    if e15 != ok { ret e15 }
    i = 0usize
    while i < p * p {
        bm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nc {
        let e16 = mahal_rows(a, x, n, p, clxf[i * p..i * p + p], cinv, mds)
        if e16 != ok { ret e16 }
        var q = 0usize
        while q < n {
            var rank = 0usize
            var r = 0usize
            while r < n {
                if mds[r] < mds[q] || (mds[r] == mds[q] && r < q) { rank += 1usize }
                r += 1usize
            }
            if rank < nn { omah[rank] = q }
            q += 1usize
        }
        var ni = 0usize
        var r = 0usize
        while r < nn {
            var j = 0usize
            while j < p {
                xo[r * p + j] = x[omah[r] * p + j]
                j += 1usize
            }
            omc[r] = 2usize
            if ci[omah[r]] == 1usize {
                omc[r] = 1usize
                ni += 1usize
            }
            r += 1usize
        }
        let nr = nn - ni
        let (ones2, e17) = mem.alloc[usize](a, nn)
        if e17 != ok { ret Malformed }
        r = 0usize
        while r < nn {
            ones2[r] = 1usize
            r += 1usize
        }
        col_means(xo, nn, p, ones2, 1usize, mi)
        var t = 0usize
        while t < p * p {
            bi[t] = 0.0f64
            t += 1usize
        }
        if ni * nr > 0usize {
            col_means(xo, nn, p, omc, 1usize, vi)
            col_means(xo, nn, p, omc, 2usize, vr)
            var j = 0usize
            while j < p {
                vi[j] = vi[j] - mi[j]
                vr[j] = vr[j] - mi[j]
                j += 1usize
            }
            var u1 = 0usize
            while u1 < p {
                var u2 = 0usize
                while u2 < p {
                    bi[u1 * p + u2] = (bi[u1 * p + u2] + f64(ni) * (vi[u1] * vi[u2])) + f64(nr) * (vr[u1] * vr[u2])
                    u2 += 1usize
                }
                u1 += 1usize
            }
        }
        var sh = 0.0f64
        var sl = 0.0f64
        var dg = 0usize
        while dg < p {
            let (h1, l1) = fp.dd_add(sh, sl, bi[dg * p + dg], 0.0f64)
            sh = h1
            sl = l1
            dg += 1usize
        }
        let sb = sh + sl
        if sb > 0.0f64 {
            var u = 0usize
            while u < p * p {
                bi[u] = bi[u] / (f64(nn) * sb)
                u += 1usize
            }
        }
        var u = 0usize
        while u < p * p {
            bm[u] = bm[u] + bi[u]
            u += 1usize
        }
        i += 1usize
    }
    let e18 = coord_tail(a, s1, bm, p, ev, units)
    if e18 != ok { ret e18 }
    project(x, n, p, units, proj)
    ret ok
}

// R's dist(data): the n by n Euclidean distances
fn euclid(data: []const f64, n: usize, p: usize, d: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                let t = data[i * p + q] - data[j * p + q]
                s += t * t
                q += 1usize
            }
            d[i * n + j] = math.sqrt[f64](s)
            j += 1usize
        }
        i += 1usize
    }
}

// R's mean(x) of m values: the long double sum, refined by a second pass
fn r_mean(x: []const f64, m: usize) -> f64 {
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < m {
        let (h1, l1) = fp.dd_add(sh, sl, x[i], 0.0f64)
        sh = h1
        sl = l1
        i += 1usize
    }
    let (th, tl) = fp.dd_div(sh, sl, f64(m))
    var rh = 0.0f64
    var rl = 0.0f64
    i = 0usize
    while i < m {
        let (vh, vl) = fp.dd_add(x[i], 0.0f64, 0.0f64 - th, 0.0f64 - tl)
        let (h2, l2) = fp.dd_add(rh, rl, vh, vl)
        rh = h2
        rl = l2
        i += 1usize
    }
    let (qh, ql) = fp.dd_div(rh, rl, f64(m))
    let (mh, ml) = fp.dd_add(th, tl, qh, ql)
    ret mh + ml
}
