// R kernlab ipop: the primal-dual interior point solver for  min c'x + x'Hx/2  subject to  b <= Ax <= b + r,  l <= x <= u,
// for a square H (the package's smw = 0 branch, which solves the (n + m) by (n + m) bordered system with a dense LU each
// half step). Matrices are row-major: h is n by n, am is m by n.
//
// Not here: a decomposed (non-square) H, which kernlab handles by the Sherman-Morrison-Woodbury route, and the infeasibility
// norms it only prints.

use e.math
use e.mem

fn sl(ws: []f64, o: usize, k: usize) -> []f64 { ret ws[o..o + k] }

fn pmaxb(v: f64, bound: f64) -> f64 {
    var r = math.abs[f64](v)
    if bound > r { r = bound }
    ret r
}

fn dotp(u: []const f64, v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < u.len {
        s += u[i] * v[i]
        i += 1usize
    }
    ret s
}

// fills ap (n + m square) with [[-(H + diag(dx)), A'], [A, diag(ey)]]
fn bordered(ap: []f64, h: []const f64, am: []const f64, dx: []const f64, ey: []const f64, n: usize, m: usize) {
    let t = n + m
    var i = 0usize
    while i < t {
        var j = 0usize
        while j < t {
            var v = 0.0f64
            if i < n && j < n {
                v = 0.0f64 - h[i * n + j]
                if i == j { v = 0.0f64 - (h[i * n + j] + dx[i]) }
            }
            if i < n && j >= n { v = am[(j - n) * n + i] }
            if i >= n && j < n { v = am[(i - n) * n + j] }
            if i >= n && j >= n && i == j { v = ey[i - n] }
            ap[i * t + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// LAPACK 3.12 dgetrf2 (the recursive LU that R's solve() reaches through dgesv for matrices below the block size), column-major with leading dimension lda, element (i, j) at a[o + i + j * lda]; piv holds the row swapped with row k, relative to the block
fn getrf2(a: []f64, o: usize, lda: usize, m: usize, n: usize, piv: []usize, po: usize) {
    if m == 1usize {
        piv[po] = 0usize
        ret
    }
    if n == 1usize {
        var pm = 0usize
        var best = math.abs[f64](a[o])
        var i = 1usize
        while i < m {
            if math.abs[f64](a[o + i]) > best {
                best = math.abs[f64](a[o + i])
                pm = i
            }
            i += 1usize
        }
        piv[po] = pm
        if a[o + pm] != 0.0f64 {
            if pm != 0usize {
                let tmp = a[o]
                a[o] = a[o + pm]
                a[o + pm] = tmp
            }
            if math.abs[f64](a[o]) >= 2.2250738585072014e-308f64 {
                let rc = 1.0f64 / a[o]
                i = 1usize
                while i < m {
                    a[o + i] *= rc
                    i += 1usize
                }
            } else {
                i = 1usize
                while i < m {
                    a[o + i] = a[o + i] / a[o]
                    i += 1usize
                }
            }
        }
        ret
    }
    var mn = m
    if n < mn { mn = n }
    let n1 = mn / 2usize
    let n2 = n - n1
    getrf2(a, o, lda, m, n1, piv, po)
    var k = 0usize
    while k < n1 {
        let pk = piv[po + k]
        if pk != k {
            var c = n1
            while c < n {
                let tmp = a[o + k + c * lda]
                a[o + k + c * lda] = a[o + pk + c * lda]
                a[o + pk + c * lda] = tmp
                c += 1usize
            }
        }
        k += 1usize
    }
    var jc = 0usize
    while jc < n2 {
        let col = n1 + jc
        k = 0usize
        while k < n1 {
            let bk = a[o + k + col * lda]
            if bk != 0.0f64 {
                var i = k + 1usize
                while i < n1 {
                    a[o + i + col * lda] -= bk * a[o + i + k * lda]
                    i += 1usize
                }
            }
            k += 1usize
        }
        jc += 1usize
    }
    jc = 0usize
    while jc < n2 {
        let col = n1 + jc
        var l2 = 0usize
        while l2 < n1 {
            let temp = 0.0f64 - a[o + l2 + col * lda]
            var i = 0usize
            while i < m - n1 {
                a[o + n1 + i + col * lda] += temp * a[o + n1 + i + l2 * lda]
                i += 1usize
            }
            l2 += 1usize
        }
        jc += 1usize
    }
    getrf2(a, o + n1 + n1 * lda, lda, m - n1, n2, piv, po + n1)
    var i = po + n1
    while i < po + mn {
        piv[i] += n1
        i += 1usize
    }
    k = n1
    while k < mn {
        let pk = piv[po + k]
        if pk != k {
            var c = 0usize
            while c < n1 {
                let tmp = a[o + k + c * lda]
                a[o + k + c * lda] = a[o + pk + c * lda]
                a[o + pk + c * lda] = tmp
                c += 1usize
            }
        }
        k += 1usize
    }
}

// R's solve(A, b) for a square row-major ap (t by t): LAPACK dgesv, i.e. dgetrf2 then the dgetrs forward and back substitutions in reference-BLAS order
fn solve_ap(a: *mem.Arena, ap: []const f64, rhs: []const f64, out: []f64, t: usize) -> err {
    let (cm, e1) = mem.alloc[f64](a, t * t)
    let (piv, e2) = mem.alloc[usize](a, t)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < t {
        var j = 0usize
        while j < t {
            cm[j * t + i] = ap[i * t + j]
            j += 1usize
        }
        out[i] = rhs[i]
        i += 1usize
    }
    getrf2(cm, 0usize, t, t, t, piv, 0usize)
    i = 0usize
    while i < t {
        let pk = piv[i]
        if pk != i {
            let tmp = out[i]
            out[i] = out[pk]
            out[pk] = tmp
        }
        i += 1usize
    }
    var k = 0usize
    while k < t {
        if out[k] != 0.0f64 {
            i = k + 1usize
            while i < t {
                out[i] -= out[k] * cm[k * t + i]
                i += 1usize
            }
        }
        k += 1usize
    }
    k = t
    while k > 0usize {
        k -= 1usize
        if out[k] != 0.0f64 {
            out[k] = out[k] / cm[k * t + k]
            i = 0usize
            while i < k {
                out[i] -= out[k] * cm[k * t + i]
                i += 1usize
            }
        }
    }
    ret ok
}

// answers the significant figures reached and the iteration count; xo (n) and yo (m) receive the primal and dual solutions
fn ipop(a: *mem.Arena, c: []const f64, h: []const f64, am: []const f64, b: []const f64, l: []const f64, u: []const f64, r: []const f64, n: usize, m: usize, sigf: f64, maxiter: usize, margin: f64, bound: f64, xo: []f64, yo: []f64) -> (f64, usize, err) {
    let t2 = n + m
    let (ws, e0) = mem.alloc[f64](a, 40usize * (n + m) + 4usize * t2 * t2 + 64usize)
    if e0 != ok { ret (0.0f64, 0usize, e0) }
    var o = 0usize
    let x = sl(ws, o, n)
    o += n
    let g = sl(ws, o, n)
    o += n
    let z = sl(ws, o, n)
    o += n
    let tt = sl(ws, o, n)
    o += n
    let s = sl(ws, o, n)
    o += n
    let y = sl(ws, o, m)
    o += m
    let v = sl(ws, o, m)
    o += m
    let w = sl(ws, o, m)
    o += m
    let p = sl(ws, o, m)
    o += m
    let q = sl(ws, o, m)
    o += m
    let hdx = sl(ws, o, n)
    o += n
    let rho = sl(ws, o, m)
    o += m
    let nu = sl(ws, o, n)
    o += n
    let tau = sl(ws, o, n)
    o += n
    let alpha = sl(ws, o, m)
    o += m
    let sigma = sl(ws, o, n)
    o += n
    let beta = sl(ws, o, m)
    o += m
    let gz = sl(ws, o, n)
    let gw = sl(ws, o + n, m)
    let gs = sl(ws, o + n + m, n)
    let gq = sl(ws, o + 2usize * n + m, m)
    o += 2usize * (n + m)
    let hbeta = sl(ws, o, m)
    o += m
    let halpha = sl(ws, o, m)
    o += m
    let hnu = sl(ws, o, n)
    o += n
    let htau = sl(ws, o, n)
    o += n
    let d = sl(ws, o, n)
    o += n
    let ey = sl(ws, o, m)
    o += m
    let cx = sl(ws, o, n)
    o += n
    let cy = sl(ws, o, m)
    o += m
    let dxv = sl(ws, o, n)
    o += n
    let dyv = sl(ws, o, m)
    o += m
    let dw = sl(ws, o, m)
    let ds = sl(ws, o + m, n)
    let dz = sl(ws, o + m + n, n)
    let dq = sl(ws, o + m + 2usize * n, m)
    o += 2usize * (m + n)
    let dv = sl(ws, o, m)
    let dp = sl(ws, o + m, m)
    let dg = sl(ws, o + 2usize * m, n)
    let dt = sl(ws, o + 2usize * m + n, n)
    o += 2usize * (m + n)
    let ones = sl(ws, o, n)
    o += n
    let rhs = sl(ws, o, t2)
    o += t2
    let sol = sl(ws, o, t2)
    o += t2
    let (ap, e1) = mem.alloc[f64](a, t2 * t2)
    if e1 != ok { ret (0.0f64, 0usize, e1) }
    var i = 0usize
    while i < n {
        ones[i] = 1.0f64
        i += 1usize
    }
    // starting point: (H + I) x ... solved with the bordered system
    bordered(ap, h, am, ones, ones, n, m)
    i = 0usize
    while i < t2 {
        if i < n {
            rhs[i] = c[i]
        } else {
            rhs[i] = b[i - n]
        }
        i += 1usize
    }
    // the initial H.y is diag(1, m), the bottom-right block of the bordered system
    var er = solve_ap(a, ap, rhs, sol, t2)
    if er != ok { ret (0.0f64, 0usize, er) }
    i = 0usize
    while i < n {
        x[i] = sol[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        y[i] = sol[n + i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        g[i] = pmaxb(x[i] - l[i], bound)
        z[i] = pmaxb(x[i], bound)
        tt[i] = pmaxb(u[i] - x[i], bound)
        s[i] = pmaxb(x[i], bound)
        i += 1usize
    }
    i = 0usize
    while i < m {
        v[i] = pmaxb(y[i], bound)
        w[i] = pmaxb(y[i], bound)
        p[i] = pmaxb(r[i] - w[i], bound)
        q[i] = pmaxb(y[i], bound)
        i += 1usize
    }
    var mu = (dotp(z, g) + dotp(v, w) + dotp(s, tt) + dotp(p, q)) / (2.0f64 * f64(m + n))
    var sigfig = 0.0f64
    var counter = 0usize
    var alfa = 1.0f64
    while counter < maxiter {
        counter += 1usize
        i = 0usize
        while i < n {
            var acc = 0.0f64
            var j = 0usize
            while j < n {
                acc += h[i * n + j] * x[j]
                j += 1usize
            }
            hdx[i] = acc
            i += 1usize
        }
        i = 0usize
        while i < m {
            var acc = 0.0f64
            var j = 0usize
            while j < n {
                acc += am[i * n + j] * x[j]
                j += 1usize
            }
            rho[i] = b[i] - acc + w[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            var acc = 0.0f64
            var j = 0usize
            while j < m {
                acc += am[j * n + i] * y[j]
                j += 1usize
            }
            nu[i] = l[i] - x[i] + g[i]
            tau[i] = u[i] - x[i] - tt[i]
            sigma[i] = c[i] - acc - z[i] + s[i] + hdx[i]
            gz[i] = 0.0f64 - z[i]
            gs[i] = 0.0f64 - s[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            alpha[i] = r[i] - w[i] - p[i]
            beta[i] = y[i] + q[i] - v[i]
            gw[i] = 0.0f64 - w[i]
            gq[i] = 0.0f64 - q[i]
            i += 1usize
        }
        let xhx = dotp(x, hdx)
        let pobj = dotp(c, x) + 0.5f64 * xhx
        let dobj = dotp(b, y) - 0.5f64 * xhx + dotp(l, z) - dotp(u, s) - dotp(r, q)
        sigfig = 0.0f64
        let rel = math.abs[f64](pobj - dobj) / (math.abs[f64](pobj) + 1.0f64)
        let lg = 0.0f64 - math.log10[f64](rel)
        if lg > 0.0f64 { sigfig = lg }
        if sigfig >= sigf { break }
        i = 0usize
        while i < m {
            hbeta[i] = beta[i] - v[i] * gw[i] / w[i]
            halpha[i] = alpha[i] - p[i] * gq[i] / q[i]
            ey[i] = 1.0f64 / (v[i] / w[i] + q[i] / p[i])
            i += 1usize
        }
        i = 0usize
        while i < n {
            hnu[i] = nu[i] + g[i] * gz[i] / z[i]
            htau[i] = tau[i] - tt[i] * gs[i] / s[i]
            d[i] = z[i] / g[i] + s[i] / tt[i]
            cx[i] = sigma[i] - z[i] * hnu[i] / g[i] - s[i] * htau[i] / tt[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            cy[i] = rho[i] - ey[i] * (hbeta[i] - q[i] * halpha[i] / p[i])
            i += 1usize
        }
        bordered(ap, h, am, d, ey, n, m)
        i = 0usize
        while i < t2 {
            if i < n {
                rhs[i] = cx[i]
            } else {
                rhs[i] = cy[i - n]
            }
            i += 1usize
        }
        er = solve_ap(a, ap, rhs, sol, t2)
        if er != ok { ret (0.0f64, 0usize, er) }
        i = 0usize
        while i < n {
            dxv[i] = sol[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            dyv[i] = sol[n + i]
            i += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            i = 0usize
            while i < m {
                dw[i] = 0.0f64 - ey[i] * (hbeta[i] - q[i] * halpha[i] / p[i] + dyv[i])
                i += 1usize
            }
            i = 0usize
            while i < n {
                ds[i] = s[i] * (dxv[i] - htau[i]) / tt[i]
                dz[i] = z[i] * (hnu[i] - dxv[i]) / g[i]
                i += 1usize
            }
            i = 0usize
            while i < m {
                dq[i] = q[i] * (dw[i] - halpha[i]) / p[i]
                dv[i] = v[i] * (gw[i] - dw[i]) / w[i]
                dp[i] = p[i] * (gq[i] - dq[i]) / q[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                dg[i] = g[i] * (gz[i] - dz[i]) / z[i]
                dt[i] = tt[i] * (gs[i] - ds[i]) / s[i]
                i += 1usize
            }
            var mn = 0.0f64 - 1.0f64
            i = 0usize
            while i < n {
                if dg[i] / g[i] < mn { mn = dg[i] / g[i] }
                if dt[i] / tt[i] < mn { mn = dt[i] / tt[i] }
                if dz[i] / z[i] < mn { mn = dz[i] / z[i] }
                if ds[i] / s[i] < mn { mn = ds[i] / s[i] }
                i += 1usize
            }
            i = 0usize
            while i < m {
                if dw[i] / w[i] < mn { mn = dw[i] / w[i] }
                if dp[i] / p[i] < mn { mn = dp[i] / p[i] }
                if dv[i] / v[i] < mn { mn = dv[i] / v[i] }
                if dq[i] / q[i] < mn { mn = dq[i] / q[i] }
                i += 1usize
            }
            alfa = 0.0f64 - (1.0f64 - margin) / mn
            if pass == 1usize { break }
            let f = (alfa - 1.0f64) / (alfa + 10.0f64)
            let newmu = mu * f * f
            i = 0usize
            while i < n {
                gz[i] = mu / g[i] - z[i] - dz[i] * dg[i] / g[i]
                gs[i] = mu / tt[i] - s[i] - ds[i] * dt[i] / tt[i]
                i += 1usize
            }
            i = 0usize
            while i < m {
                gw[i] = mu / v[i] - w[i] - dw[i] * dv[i] / v[i]
                gq[i] = mu / p[i] - q[i] - dq[i] * dp[i] / p[i]
                hbeta[i] = beta[i] - v[i] * gw[i] / w[i]
                halpha[i] = alpha[i] - p[i] * gq[i] / q[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                hnu[i] = nu[i] + g[i] * gz[i] / z[i]
                htau[i] = tau[i] - tt[i] * gs[i] / s[i]
                cx[i] = sigma[i] - z[i] * hnu[i] / g[i] - s[i] * htau[i] / tt[i]
                i += 1usize
            }
            i = 0usize
            while i < m {
                cy[i] = rho[i] - ey[i] * (hbeta[i] - q[i] * halpha[i] / p[i])
                i += 1usize
            }
            i = 0usize
            while i < t2 {
                if i < n {
                    rhs[i] = cx[i]
                } else {
                    rhs[i] = cy[i - n]
                }
                i += 1usize
            }
            er = solve_ap(a, ap, rhs, sol, t2)
            if er != ok { ret (0.0f64, 0usize, er) }
            i = 0usize
            while i < n {
                dxv[i] = sol[i]
                i += 1usize
            }
            i = 0usize
            while i < m {
                dyv[i] = sol[n + i]
                i += 1usize
            }
            mu = newmu
            pass += 1usize
        }
        i = 0usize
        while i < n {
            x[i] += dxv[i] * alfa
            g[i] += dg[i] * alfa
            tt[i] += dt[i] * alfa
            z[i] += dz[i] * alfa
            s[i] += ds[i] * alfa
            i += 1usize
        }
        i = 0usize
        while i < m {
            w[i] += dw[i] * alfa
            p[i] += dp[i] * alfa
            y[i] += dyv[i] * alfa
            v[i] += dv[i] * alfa
            q[i] += dq[i] * alfa
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        xo[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        yo[i] = y[i]
        i += 1usize
    }
    ret (sigfig, counter, ok)
}
