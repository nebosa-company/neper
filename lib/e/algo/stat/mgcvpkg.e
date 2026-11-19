// The R package mgcv, smooth construction: the cubic regression spline basis ("cr") of a covariate, with its penalty matrix. The knots are mgcv's place.knots (the sorted
// unique values interpolated at equal ranks); the basis is the natural cubic spline written in terms of its values at the knots, f(x) = a-_j b_j + a+_j b_{j+1} + c-_j d_j +
// c+_j d_{j+1} with d = F b, F = B^-1 D (zero first and last rows) and the penalty S = D' B^-1 D, B and D the tridiagonal matrices of the natural spline conditions
// (Wood, Generalized Additive Models, 5.3.1). Values outside the knot range are extrapolated linearly in mgcv and are not covered here.

use e.math
use e.mem

error Malformed

// place.knots(x, nk): the first and last unique sorted values and nk - 2 interior knots interpolated at ranks delta * i + 1 with delta = (n - 1) / (nk - 1)
fn place_knots(a: *mem.Arena, x: []const f64, nk: usize, out: []f64) -> err {
    let (s, e0) = mem.alloc[f64](a, x.len)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    // sort ascending (insertion), then the unique values
    i = 1usize
    while i < x.len {
        let v = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > v {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = v
        i += 1usize
    }
    var n = 0usize
    i = 0usize
    while i < x.len {
        if i == 0usize || s[i] != s[i - 1usize] {
            s[n] = s[i]
            n += 1usize
        }
        i += 1usize
    }
    if nk > n || nk < 2usize { ret Malformed }
    if nk == 2usize {
        out[0usize] = s[0usize]
        out[1usize] = s[n - 1usize]
        ret ok
    }
    let delta = (f64(n) - 1.0f64) / (f64(nk) - 1.0f64)
    out[0usize] = s[0usize]
    out[nk - 1usize] = s[n - 1usize]
    i = 1usize
    while i + 1usize < nk {
        let pos = delta * f64(i)
        let lbi = usize(math.floor[f64](pos))
        let frac = pos + 1.0f64 - f64(lbi + 1usize)
        out[i] = s[lbi] * (1.0f64 - frac) + s[lbi + 1usize] * frac
        i += 1usize
    }
    ret ok
}

// F (k by k, row-major) and the penalty S (k by k) of the natural cubic spline with the knots xk (k >= 3)
fn cr_penalty(a: *mem.Arena, xk: []const f64, k: usize, f: []f64, s: []f64) -> err {
    let m = k - 2usize
    let (h, e0) = mem.alloc[f64](a, k - 1usize)
    let (bd, e1) = mem.alloc[f64](a, m)
    let (bo, e2) = mem.alloc[f64](a, m)
    let (d, e3) = mem.alloc[f64](a, m * k)
    let (w, e4) = mem.alloc[f64](a, m * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i + 1usize < k {
        h[i] = xk[i + 1usize] - xk[i]
        i += 1usize
    }
    i = 0usize
    while i < m * k {
        d[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        bd[i] = (h[i] + h[i + 1usize]) / 3.0f64
        bo[i] = h[i + 1usize] / 6.0f64
        d[i * k + i] = 1.0f64 / h[i]
        d[i * k + i + 1usize] = 0.0f64 - 1.0f64 / h[i] - 1.0f64 / h[i + 1usize]
        d[i * k + i + 2usize] = 1.0f64 / h[i + 1usize]
        i += 1usize
    }
    // w = B^-1 D by the symmetric tridiagonal elimination (Thomas), column by column
    var c = 0usize
    while c < k {
        // forward sweep on a copy of the diagonal
        let (dd, e5) = mem.alloc[f64](a, m)
        let (rr, e6) = mem.alloc[f64](a, m)
        if e5 != ok || e6 != ok { ret mem.Full }
        i = 0usize
        while i < m {
            dd[i] = bd[i]
            rr[i] = d[i * k + c]
            i += 1usize
        }
        i = 1usize
        while i < m {
            let ratio = bo[i - 1usize] / dd[i - 1usize]
            dd[i] = dd[i] - ratio * bo[i - 1usize]
            rr[i] = rr[i] - ratio * rr[i - 1usize]
            i += 1usize
        }
        w[(m - 1usize) * k + c] = rr[m - 1usize] / dd[m - 1usize]
        if m >= 2usize {
            var q = m - 1usize
            while q > 0usize {
                q -= 1usize
                w[q * k + c] = (rr[q] - bo[q] * w[(q + 1usize) * k + c]) / dd[q]
            }
        }
        c += 1usize
    }
    // F: zero first and last rows, the interior rows from w
    i = 0usize
    while i < k * k {
        f[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < k {
            f[(i + 1usize) * k + j] = w[i * k + j]
            j += 1usize
        }
        i += 1usize
    }
    // S = D' B^-1 D = D' w
    var r = 0usize
    while r < k {
        var cc = 0usize
        while cc < k {
            var v = 0.0f64
            var q = 0usize
            while q < m {
                v += d[q * k + r] * w[q * k + cc]
                q += 1usize
            }
            s[r * k + cc] = v
            cc += 1usize
        }
        r += 1usize
    }
    ret ok
}

// the cr basis matrix X (n by k, row-major) of the covariate x at the knots xk (x within the knot range); f is the F of cr_penalty
fn cr_basis(x: []const f64, xk: []const f64, k: usize, f: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        // the interval j with xk[j] <= x <= xk[j + 1]
        var j = 0usize
        while j + 2usize < k && x[i] > xk[j + 1usize] { j += 1usize }
        let h = xk[j + 1usize] - xk[j]
        let xm = xk[j + 1usize] - x[i]
        let xp = x[i] - xk[j]
        let am = xm / h
        let ap = xp / h
        let cm = (xm * xm * xm / h - h * xm) / 6.0f64
        let cp = (xp * xp * xp / h - h * xp) / 6.0f64
        var c = 0usize
        while c < k {
            out[i * k + c] = cm * f[j * k + c] + cp * f[(j + 1usize) * k + c]
            c += 1usize
        }
        out[i * k + j] += am
        out[i * k + j + 1usize] += ap
        i += 1usize
    }
}

// smoothCon's penalty scaling (scale.penalty = TRUE): S is divided by norm(S, "O") / norm(X, "I")^2 (the largest column sum of |S| over the squared largest row sum of |X|),
// so that the penalty is on the scale of X'X
fn scale_penalty(x: []const f64, n: usize, k: usize, s: []f64) {
    var maxrow = 0.0f64
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < k {
            rs += math.abs[f64](x[i * k + j])
            j += 1usize
        }
        if rs > maxrow { maxrow = rs }
        i += 1usize
    }
    let maxx = maxrow * maxrow
    var maxcol = 0.0f64
    var j = 0usize
    while j < k {
        var cs = 0.0f64
        i = 0usize
        while i < k {
            cs += math.abs[f64](s[i * k + j])
            i += 1usize
        }
        if cs > maxcol { maxcol = cs }
        j += 1usize
    }
    let mas = maxcol / maxx
    i = 0usize
    while i < k * k {
        s[i] = s[i] / mas
        i += 1usize
    }
}

// absorb the sum-to-zero constraint (smoothCon's default): with c the column sums of X, the Householder reflection H = I - u u' / u[0] of LINPACK's dqrdc2 (u = c / nrmxl with
// nrmxl carrying the sign of c[0], then u[0] += 1) maps c to a multiple of e1; Z is H without its first column, X becomes X Z (n by k - 1) and S becomes Z' S Z (k - 1 square).
// xz and sz receive the results (n * (k - 1) and (k - 1) * (k - 1) row-major); x and s are as built (the penalty already scaled).
fn absorb_sum_zero(a: *mem.Arena, x: []const f64, n: usize, k: usize, s: []const f64, xz: []f64, sz: []f64) -> err {
    let (c, e0) = mem.alloc[f64](a, k)
    let (z, e1) = mem.alloc[f64](a, k * (k - 1usize))
    let (sz0, e2) = mem.alloc[f64](a, k * (k - 1usize))
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var j = 0usize
    while j < k {
        var cs = 0.0f64
        var i = 0usize
        while i < n {
            cs += x[i * k + j]
            i += 1usize
        }
        c[j] = cs
        j += 1usize
    }
    var nrm = 0.0f64
    j = 0usize
    while j < k {
        nrm += c[j] * c[j]
        j += 1usize
    }
    nrm = math.sqrt[f64](nrm)
    if c[0usize] < 0.0f64 { nrm = 0.0f64 - nrm }
    j = 0usize
    while j < k {
        c[j] = c[j] / nrm
        j += 1usize
    }
    c[0usize] += 1.0f64
    // H = I - u u' / u[0]; Z is columns 1..k - 1
    var r = 0usize
    while r < k {
        var q = 1usize
        while q < k {
            var h = 0.0f64
            if r == q { h = 1.0f64 }
            z[r * (k - 1usize) + q - 1usize] = h - c[r] * c[q] / c[0usize]
            q += 1usize
        }
        r += 1usize
    }
    var i = 0usize
    while i < n {
        var cc = 0usize
        while cc < k - 1usize {
            var v = 0.0f64
            var q = 0usize
            while q < k {
                v += x[i * k + q] * z[q * (k - 1usize) + cc]
                q += 1usize
            }
            xz[i * (k - 1usize) + cc] = v
            cc += 1usize
        }
        i += 1usize
    }
    // Z' S Z
    r = 0usize
    while r < k {
        var cc = 0usize
        while cc < k - 1usize {
            var v = 0.0f64
            var q = 0usize
            while q < k {
                v += s[r * k + q] * z[q * (k - 1usize) + cc]
                q += 1usize
            }
            sz0[r * (k - 1usize) + cc] = v
            cc += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < k - 1usize {
        var cc = 0usize
        while cc < k - 1usize {
            var v = 0.0f64
            var q = 0usize
            while q < k {
                v += z[q * (k - 1usize) + r] * sz0[q * (k - 1usize) + cc]
                q += 1usize
            }
            sz[r * (k - 1usize) + cc] = v
            cc += 1usize
        }
        r += 1usize
    }
    ret ok
}

// ---- the P-spline smooth (bs = "ps"): B-splines of order m1 + 2 (cubic by default, m1 = 2) on equally spaced knots, with the difference penalty of order m2 (default 2).
// ps_knots writes mgcv's nk + 2 m1 + 2 knots (nk = k - m1; the data range widened by 0.1 percent each side, spacing dx = range / (nk - 1), extended m1 + 1 steps beyond);
// ps_basis the Cox-de Boor design matrix (n by len(kn) - order, row-major); ps_penalty D'D of the m2-th difference matrix of the basis dimension.
fn ps_knots(x: []const f64, kdim: usize, m1: usize, out: []f64) {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let nk = kdim - m1
    let xr = hi - lo
    let xl = lo - xr * 0.001f64
    let xu = hi + xr * 0.001f64
    let dx = (xu - xl) / (f64(nk) - 1.0f64)
    let from = xl - dx * f64(m1 + 1usize)
    let to = xu + dx * f64(m1 + 1usize)
    let total = nk + 2usize * m1 + 2usize
    i = 0usize
    while i < total {
        out[i] = from + (to - from) * f64(i) / f64(total - 1usize)
        i += 1usize
    }
}

fn ps_basis(a: *mem.Arena, x: []const f64, kn: []const f64, ord: usize, out: []f64) -> err {
    let nb = kn.len - ord
    let (b, e0) = mem.alloc[f64](a, kn.len)
    let (nx, e1) = mem.alloc[f64](a, kn.len)
    if e0 != ok || e1 != ok { ret e0 }
    var r = 0usize
    while r < x.len {
        // the order-1 indicators
        var i = 0usize
        while i + 1usize < kn.len {
            b[i] = 0.0f64
            if kn[i] <= x[r] && x[r] < kn[i + 1usize] { b[i] = 1.0f64 }
            i += 1usize
        }
        var p = 2usize
        while p <= ord {
            i = 0usize
            while i + p < kn.len {
                var left = 0.0f64
                let d1 = kn[i + p - 1usize] - kn[i]
                if d1 > 0.0f64 { left = (x[r] - kn[i]) / d1 * b[i] }
                var right = 0.0f64
                let d2 = kn[i + p] - kn[i + 1usize]
                if d2 > 0.0f64 { right = (kn[i + p] - x[r]) / d2 * b[i + 1usize] }
                nx[i] = left + right
                i += 1usize
            }
            i = 0usize
            while i + p < kn.len {
                b[i] = nx[i]
                i += 1usize
            }
            p += 1usize
        }
        var c = 0usize
        while c < nb {
            out[r * nb + c] = b[c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// S = D'D with D the m2-th order difference matrix of size (nb - m2) by nb
fn ps_penalty(a: *mem.Arena, nb: usize, m2: usize, s: []f64) -> err {
    let rows = nb - m2
    let (d, e0) = mem.alloc[f64](a, rows * nb)
    let (cur, e1) = mem.alloc[f64](a, (m2 + 1usize))
    if e0 != ok || e1 != ok { ret e0 }
    // the coefficients of the m2-th difference: (-1)^(m2 - j) choose(m2, j)
    var j = 0usize
    while j <= m2 {
        var ch = 1.0f64
        var q = 0usize
        while q < j {
            ch = ch * f64(m2 - q) / f64(q + 1usize)
            q += 1usize
        }
        var sg = 1.0f64
        if (m2 - j) % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
        cur[j] = sg * ch
        j += 1usize
    }
    var i = 0usize
    while i < rows * nb {
        d[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < rows {
        j = 0usize
        while j <= m2 {
            d[i * nb + i + j] = cur[j]
            j += 1usize
        }
        i += 1usize
    }
    var r = 0usize
    while r < nb {
        var c = 0usize
        while c < nb {
            var v = 0.0f64
            var q = 0usize
            while q < rows {
                v += d[q * nb + r] * d[q * nb + c]
                q += 1usize
            }
            s[r * nb + c] = v
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}
