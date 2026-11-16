// R pracma: trapz, cumtrapz, polyval, polyfit (Householder least squares), findpeaks, rref, primes, factors, extended gcd, nchoosek, cross.
//
// Not here: the rest of the toolbox (quadrature, root finders, interpolation, orthogonal polynomials, matrix functions).

use e.math
use e.mem

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

fn trapz(x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < x.len {
        s += (x[i] - x[i - 1usize]) * (y[i] + y[i - 1usize]) / 2.0f64
        i += 1usize
    }
    ret s
}

fn cumtrapz(a: *mem.Arena, x: []const f64, y: []const f64) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (o, e) }
    var s = 0.0f64
    o[0usize] = 0.0f64
    var i = 1usize
    while i < x.len {
        s += (x[i] - x[i - 1usize]) * (y[i] + y[i - 1usize]) / 2.0f64
        o[i] = s
        i += 1usize
    }
    ret (o, ok)
}

// coefficients highest power first
fn polyval(p: []const f64, x: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < p.len {
        s = s * x + p[i]
        i += 1usize
    }
    ret s
}

// polyfit: least squares by Householder QR of the Vandermonde matrix, coefficients highest power first
fn polyfit(a: *mem.Arena, x: []const f64, y: []const f64, deg: usize) -> ([]f64, err) {
    let m = x.len
    let n = deg + 1usize
    let (q, e1) = mem.alloc[f64](a, m * n)
    if e1 != ok { ret (q, e1) }
    let (b, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret (b, e2) }
    let (r, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret (r, e3) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            q[i * n + j] = math.pow[f64](x[i], f64(deg - j))
            j += 1usize
        }
        b[i] = y[i]
        i += 1usize
    }
    var k = 0usize
    while k < n {
        var nrm = 0.0f64
        i = k
        while i < m {
            nrm += q[i * n + k] * q[i * n + k]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        var alpha = nrm
        if q[k * n + k] > 0.0f64 { alpha = 0.0f64 - nrm }
        var vnorm = 0.0f64
        let (v, e4) = mem.alloc[f64](a, m)
        if e4 != ok { ret (v, e4) }
        i = k
        while i < m {
            v[i] = q[i * n + k]
            i += 1usize
        }
        v[k] = v[k] - alpha
        i = k
        while i < m {
            vnorm += v[i] * v[i]
            i += 1usize
        }
        if vnorm > 0.0f64 {
            var j = k
            while j < n {
                var d = 0.0f64
                i = k
                while i < m {
                    d += v[i] * q[i * n + j]
                    i += 1usize
                }
                let f = 2.0f64 * d / vnorm
                i = k
                while i < m {
                    q[i * n + j] -= f * v[i]
                    i += 1usize
                }
                j += 1usize
            }
            var d2 = 0.0f64
            i = k
            while i < m {
                d2 += v[i] * b[i]
                i += 1usize
            }
            let f2 = 2.0f64 * d2 / vnorm
            i = k
            while i < m {
                b[i] -= f2 * v[i]
                i += 1usize
            }
        }
        k += 1usize
    }
    var ii = n
    while ii > 0usize {
        ii -= 1usize
        var s = b[ii]
        var j = ii + 1usize
        while j < n {
            s -= q[ii * n + j] * r[j]
            j += 1usize
        }
        r[ii] = s / q[ii * n + ii]
    }
    ret (r, ok)
}

// findpeaks: rows of (height, peak position, start, end), 1-based, flattened row-major; the count of rows comes back with it
fn findpeaks(a: *mem.Arena, x: []const f64, nups: usize, ndowns: usize, minh: f64, mindist: usize, thr: f64, npeaks: usize, sortstr: bool) -> ([]f64, usize, err) {
    let n = x.len
    let (sg, e0) = mem.alloc[i32](a, n)
    if e0 != ok { ret (zero, 0usize, e0) }
    var i = 0usize
    while i + 1usize < n {
        var s = 0i32
        if x[i + 1usize] > x[i] { s = 1i32 }
        if x[i + 1usize] < x[i] { s = 0i32 - 1i32 }
        sg[i] = s
        i += 1usize
    }
    let nd = n - 1usize
    let (rows, e1) = mem.alloc[f64](a, 4usize * (nd + 1usize))
    if e1 != ok { ret (rows, 0usize, e1) }
    var cnt = 0usize
    var p = 0usize
    while p < nd {
        if sg[p] == 1i32 {
            var q = p
            while q < nd && sg[q] == 1i32 { q += 1usize }
            var r = q
            while r < nd && sg[r] == 0i32 - 1i32 { r += 1usize }
            if q - p >= nups && r - q >= ndowns {
                let x1 = p + 1usize
                let x2 = x1 + (r - p)
                var best = x1
                var j = x1
                while j <= x2 {
                    if x[j - 1usize] > x[best - 1usize] { best = j }
                    j += 1usize
                }
                var mx = x[x1 - 1usize]
                if x[x2 - 1usize] > mx { mx = x[x2 - 1usize] }
                let h = x[best - 1usize]
                if h >= minh && h - mx >= thr {
                    rows[cnt * 4usize] = h
                    rows[cnt * 4usize + 1usize] = f64(best)
                    rows[cnt * 4usize + 2usize] = f64(x1)
                    rows[cnt * 4usize + 3usize] = f64(x2)
                    cnt += 1usize
                }
                p = r
            } else {
                p = q
            }
        } else {
            p += 1usize
        }
    }
    if sortstr || mindist > 1usize {
        // stable insertion sort by height, decreasing
        var a1 = 1usize
        while a1 < cnt {
            let h0 = rows[a1 * 4usize]
            let h1 = rows[a1 * 4usize + 1usize]
            let h2 = rows[a1 * 4usize + 2usize]
            let h3 = rows[a1 * 4usize + 3usize]
            var b1 = a1
            while b1 > 0usize && rows[(b1 - 1usize) * 4usize] < h0 {
                var c = 0usize
                while c < 4usize {
                    rows[b1 * 4usize + c] = rows[(b1 - 1usize) * 4usize + c]
                    c += 1usize
                }
                b1 -= 1usize
            }
            rows[b1 * 4usize] = h0
            rows[b1 * 4usize + 1usize] = h1
            rows[b1 * 4usize + 2usize] = h2
            rows[b1 * 4usize + 3usize] = h3
            a1 += 1usize
        }
    }
    if mindist > 1usize && cnt > 0usize {
        let (bad, e2) = mem.alloc[bool](a, cnt)
        if e2 != ok { ret (rows, 0usize, e2) }
        var u = 0usize
        while u < cnt {
            bad[u] = false
            u += 1usize
        }
        u = 0usize
        while u < cnt {
            if !bad[u] {
                var k = 0usize
                while k < cnt {
                    var dp = rows[u * 4usize + 1usize] - rows[k * 4usize + 1usize]
                    if dp < 0.0f64 { dp = 0.0f64 - dp }
                    if dp > 0.0f64 && dp < f64(mindist) { bad[k] = true }
                    k += 1usize
                }
            }
            u += 1usize
        }
        var w = 0usize
        u = 0usize
        while u < cnt {
            if !bad[u] {
                var c = 0usize
                while c < 4usize {
                    rows[w * 4usize + c] = rows[u * 4usize + c]
                    c += 1usize
                }
                w += 1usize
            }
            u += 1usize
        }
        cnt = w
    }
    if npeaks > 0usize && npeaks < cnt { cnt = npeaks }
    ret (rows, cnt, ok)
}

// rref of an nr by nc row-major matrix, in place
fn rref(m: []f64, nr: usize, nc: usize) {
    var mxa = 0.0f64
    var t = 0usize
    while t < nr * nc {
        if math.abs[f64](m[t]) > mxa { mxa = math.abs[f64](m[t]) }
        t += 1usize
    }
    var big = nr
    if nc > big { big = nc }
    let tol = eps() * f64(big) * mxa
    var r = 0usize
    var i = 0usize
    while i < nc {
        var piv = r
        var best = math.abs[f64](m[r * nc + i])
        var k = r + 1usize
        while k < nr {
            if math.abs[f64](m[k * nc + i]) > best {
                best = math.abs[f64](m[k * nc + i])
                piv = k
            }
            k += 1usize
        }
        if best <= tol {
            k = r
            while k < nr {
                m[k * nc + i] = 0.0f64
                k += 1usize
            }
        } else {
            var c = i
            while c < nc {
                let tmp = m[piv * nc + c]
                m[piv * nc + c] = m[r * nc + c]
                m[r * nc + c] = tmp
                c += 1usize
            }
            let d = m[r * nc + i]
            c = i
            while c < nc {
                m[r * nc + c] = m[r * nc + c] / d
                c += 1usize
            }
            k = 0usize
            while k < nr {
                if k != r {
                    let f = m[k * nc + i]
                    c = i
                    while c < nc {
                        m[k * nc + c] -= f * m[r * nc + c]
                        c += 1usize
                    }
                }
                k += 1usize
            }
            if r == nr - 1usize { break }
            r += 1usize
        }
        i += 1usize
    }
    t = 0usize
    while t < nr * nc {
        if math.abs[f64](m[t]) < tol { m[t] = 0.0f64 }
        t += 1usize
    }
}

fn primes_count(n: u64) -> u64 {
    var c = 0u64
    var k = 2u64
    while k <= n {
        var isp = true
        var d = 2u64
        while d * d <= k {
            if k % d == 0u64 {
                isp = false
                break
            }
            d += 1u64
        }
        if isp { c += 1u64 }
        k += 1u64
    }
    ret c
}

// sum of the prime factors with multiplicity and their number, as in factors()
fn factors(n0: u64) -> (u64, u64) {
    var n = n0
    var sum = 0u64
    var cnt = 0u64
    var q = 2u64
    while q * q <= n {
        while n % q == 0u64 {
            sum += q
            cnt += 1u64
            n = n / q
        }
        q += 1u64
    }
    if n > 1u64 {
        sum += n
        cnt += 1u64
    }
    ret (sum, cnt)
}

// extended Euclid as in gcd(a, b, extended = TRUE): (g, c, d) with c * a + d * b = g
fn gcd_ext(a: i64, b: i64) -> (i64, i64, i64) {
    var u0 = 1i64
    var u1 = 0i64
    var u2 = a
    if u2 < 0i64 { u2 = 0i64 - u2 }
    var v0 = 0i64
    var v1 = 1i64
    var v2 = b
    if v2 < 0i64 { v2 = 0i64 - v2 }
    while v2 != 0i64 {
        let q = u2 / v2
        let t0 = u0 - v0 * q
        let t1 = u1 - v1 * q
        let t2 = u2 - v2 * q
        u0 = v0
        u1 = v1
        u2 = v2
        v0 = t0
        v1 = t1
        v2 = t2
    }
    var sa = 1i64
    if a < 0i64 { sa = 0i64 - 1i64 }
    ret (u2, u0 * sa, u1 * sa)
}

fn nchoosek(n: f64, k: f64) -> f64 {
    var kk = k
    if n - k < kk { kk = n - k }
    var r = 1.0f64
    var i = 1.0f64
    while i <= kk {
        r = r * (n - kk + i) / i
        i += 1.0f64
    }
    ret math.floor[f64](r + 0.5f64)
}

fn cross(x: []const f64, y: []const f64, o: []f64) {
    o[0usize] = x[1usize] * y[2usize] - x[2usize] * y[1usize]
    o[1usize] = x[2usize] * y[0usize] - x[0usize] * y[2usize]
    o[2usize] = x[0usize] * y[1usize] - x[1usize] * y[0usize]
}

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

fn pchip_end(h1: f64, h2: f64, del1: f64, del2: f64) -> f64 {
    var d = ((2.0f64 * h1 + h2) * del1 - h1 * del2) / (h1 + h2)
    if sgn(d) != sgn(del1) {
        d = 0.0f64
    } else if sgn(del1) != sgn(del2) && math.abs[f64](d) > math.abs[f64](3.0f64 * del1) {
        d = 3.0f64 * del1
    }
    ret d
}

// pchip: shape-preserving cubic Hermite interpolation of (xi, yi) at x (xi sorted, at least three points)
fn pchip(a: *mem.Arena, xi: []const f64, yi: []const f64, x: f64) -> f64 {
    let n = xi.len
    let (h, e1) = mem.alloc[f64](a, n - 1usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (dl, e2) = mem.alloc[f64](a, n - 1usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (d, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i + 1usize < n {
        h[i] = xi[i + 1usize] - xi[i]
        dl[i] = (yi[i + 1usize] - yi[i]) / h[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        d[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i + 1usize < n {
        if sgn(dl[i - 1usize]) * sgn(dl[i]) > 0.0f64 {
            let w1 = 2.0f64 * h[i] + h[i - 1usize]
            let w2 = h[i] + 2.0f64 * h[i - 1usize]
            d[i] = (w1 + w2) / (w1 / dl[i - 1usize] + w2 / dl[i])
        }
        i += 1usize
    }
    d[0usize] = pchip_end(h[0usize], h[1usize], dl[0usize], dl[1usize])
    d[n - 1usize] = pchip_end(h[n - 2usize], h[n - 3usize], dl[n - 2usize], dl[n - 3usize])
    var k = 0usize
    var j = 1usize
    while j + 1usize < n {
        if xi[j] <= x { k = j }
        j += 1usize
    }
    let aa = (3.0f64 * dl[k] - 2.0f64 * d[k] - d[k + 1usize]) / h[k]
    let bb = (d[k] - 2.0f64 * dl[k] + d[k + 1usize]) / (h[k] * h[k])
    let s = x - xi[k]
    ret yi[k] + s * (d[k] + s * (aa + s * bb))
}

fn quad_f(id: usize, x: f64) -> f64 {
    if id == 0usize { ret math.sin[f64](x) }
    if id == 1usize { ret math.exp[f64](0.0f64 - x * x) }
    if id == 2usize { ret 1.0f64 / (1.0f64 + x * x) }
    if id == 3usize { ret math.sqrt[f64](x) }
    ret math.cos[f64](5.0f64 * x) * math.exp[f64](0.0f64 - x)
}

fn gk_node15(i: usize) -> f64 {
    if i == 0usize { ret 0.0f64 - 0.991455371120813f64 }
    if i == 1usize { ret 0.0f64 - 0.949107912342758f64 }
    if i == 2usize { ret 0.0f64 - 0.864864423359769f64 }
    if i == 3usize { ret 0.0f64 - 0.741531185599394f64 }
    if i == 4usize { ret 0.0f64 - 0.586087235467691f64 }
    if i == 5usize { ret 0.0f64 - 0.405845151377397f64 }
    if i == 6usize { ret 0.0f64 - 0.207784955007899f64 }
    if i == 7usize { ret 0.0f64 }
    if i == 8usize { ret 0.207784955007899f64 }
    if i == 9usize { ret 0.405845151377397f64 }
    if i == 10usize { ret 0.586087235467691f64 }
    if i == 11usize { ret 0.741531185599394f64 }
    if i == 12usize { ret 0.864864423359769f64 }
    if i == 13usize { ret 0.949107912342758f64 }
    ret 0.991455371120813f64
}

fn gk_w15(i: usize) -> f64 {
    if i == 0usize || i == 14usize { ret 0.0229353220105292f64 }
    if i == 1usize || i == 13usize { ret 0.0630920926299785f64 }
    if i == 2usize || i == 12usize { ret 0.10479001032225f64 }
    if i == 3usize || i == 11usize { ret 0.140653259715526f64 }
    if i == 4usize || i == 10usize { ret 0.169004726639268f64 }
    if i == 5usize || i == 9usize { ret 0.190350578064785f64 }
    if i == 6usize || i == 8usize { ret 0.204432940075299f64 }
    ret 0.209482141084728f64
}

fn gk_w7(i: usize) -> f64 {
    if i == 0usize || i == 6usize { ret 0.12948496616887f64 }
    if i == 1usize || i == 5usize { ret 0.279705391489277f64 }
    if i == 2usize || i == 4usize { ret 0.381830050505119f64 }
    ret 0.417959183673469f64
}

// quadgk: the package's recursive Gauss-Kronrod 7/15 with its truncated nodes, on a fixed set of integrands (id)
fn quadgk(id: usize, lo: f64, hi: f64, tol: f64) -> f64 {
    if lo == hi { ret 0.0f64 }
    if lo > hi { ret 0.0f64 - quadgk(id, hi, lo, tol) }
    var q7 = 0.0f64
    var q15 = 0.0f64
    var i = 0usize
    while i < 15usize {
        q15 += gk_w15(i) * quad_f(id, 0.5f64 * ((hi - lo) * gk_node15(i) + hi + lo))
        i += 1usize
    }
    // the 7-point nodes are the odd-indexed 15-point nodes
    i = 0usize
    while i < 7usize {
        q7 += gk_w7(i) * quad_f(id, 0.5f64 * ((hi - lo) * gk_node15(2usize * i + 1usize) + hi + lo))
        i += 1usize
    }
    q7 = q7 * (hi - lo) / 2.0f64
    q15 = q15 * (hi - lo) / 2.0f64
    if q7 != q7 || q15 != q15 { ret q15 }
    if math.abs[f64](q15 - q7) < tol { ret q15 }
    let mid = (lo + hi) / 2.0f64
    if math.abs[f64](hi - lo) < 16.0f64 * eps() { ret quadgk(id, mid, hi, tol) }
    let q2 = quadgk(id, mid, hi, tol)
    let q1 = quadgk(id, lo, mid, tol)
    ret q1 + q2
}

// the derivative of a polynomial given highest power first, into out (len p.len - 1)
fn polyder(p: []const f64, out: []f64) {
    let n = p.len
    var i = 0usize
    while i + 1usize < n {
        out[i] = p[i] * f64(n - 1usize - i)
        i += 1usize
    }
}

// legendre(n, x): the associated Legendre functions P_n^m(x), m = 0..n, written to out (n + 1 values); a.arena scratch for the coefficients
fn legendre(a: *mem.Arena, n: usize, x: f64, out: []f64) -> err {
    if n == 0usize {
        out[0usize] = 1.0f64
        ret ok
    }
    let w = n + 1usize
    let (lp, e) = mem.alloc[f64](a, w * w)
    if e != ok { ret e }
    var t = 0usize
    while t < w * w {
        lp[t] = 0.0f64
        t += 1usize
    }
    lp[0usize * w + n] = 1.0f64
    lp[1usize * w + n - 1usize] = 1.0f64
    var i = 2usize
    while i <= n {
        let j = f64(i)
        var c = n - i
        // row i (0-based) of the 1-based recurrence over i + 1: columns (n - i + 1 ..= n)
        while c <= n {
            var prev_shift = 0.0f64
            if c + 1usize <= n { prev_shift = lp[(i - 1usize) * w + c + 1usize] }
            lp[i * w + c] = (2.0f64 * j - 1.0f64) / j * prev_shift - (j - 1.0f64) / j * lp[(i - 2usize) * w + c]
            c += 1usize
        }
        i += 1usize
    }
    let (cur, e2) = mem.alloc[f64](a, w)
    if e2 != ok { ret e2 }
    var len = w
    var k = 0usize
    while k < w {
        cur[k] = lp[n * w + k]
        k += 1usize
    }
    out[0usize] = polyval(cur[0usize..len], x)
    var jj = 1usize
    while jj <= n {
        let (d, e3) = mem.alloc[f64](a, len)
        if e3 != ok { ret e3 }
        polyder(cur[0usize..len], d)
        len -= 1usize
        var k2 = 0usize
        while k2 < len {
            cur[k2] = d[k2]
            k2 += 1usize
        }
        var sg = 1.0f64
        if jj % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
        out[jj] = sg * math.sqrt[f64](math.pow[f64](1.0f64 - x * x, f64(jj))) * polyval(cur[0usize..len], x)
        jj += 1usize
    }
    ret ok
}

// chebPoly(n): the coefficients of T_n, highest power first, n + 1 values
fn cheb_poly(a: *mem.Arena, n: usize, out: []f64) -> err {
    var big = n + 1usize
    if big < 2usize { big = 2usize }
    let (t, e) = mem.alloc[f64](a, big * big)
    if e != ok { ret e }
    var q = 0usize
    while q < big * big {
        t[q] = 0.0f64
        q += 1usize
    }
    t[0usize] = 1.0f64
    t[1usize * big + 1usize] = 1.0f64
    var i = 2usize
    while i < big {
        var c = 0usize
        while c < big {
            var sh = 0.0f64
            if c >= 1usize { sh = t[(i - 1usize) * big + c - 1usize] }
            t[i * big + c] = 2.0f64 * sh - t[(i - 2usize) * big + c]
            c += 1usize
        }
        i += 1usize
    }
    var c2 = 0usize
    while c2 <= n {
        out[c2] = t[n * big + (n - c2)]
        c2 += 1usize
    }
    ret ok
}

// laguerre(p, x0): the package's Laguerre root iteration for a real polynomial (NaN when the square root is negative)
fn laguerre(a: *mem.Arena, p: []const f64, x0: f64, nmax: usize) -> f64 {
    let n = f64(p.len - 1usize)
    let (p1, e1) = mem.alloc[f64](a, p.len - 1usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (p2, e2) = mem.alloc[f64](a, p.len - 2usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    polyder(p, p1)
    polyder(p1, p2)
    let tol = math.sqrt[f64](2.220446049250313e-16f64)
    var xa = x0
    var y0 = polyval(p, xa)
    if math.abs[f64](y0) < tol { ret xa }
    var x = xa
    var m = 1usize
    while m <= nmax {
        let aa = polyval(p1, xa) / y0
        let a2 = aa * aa
        let b = a2 - polyval(p2, xa) / y0
        let sq = math.sqrt[f64]((n - 1.0f64) * (n * b - a2))
        x = xa - n / (aa + aa / math.abs[f64](aa) * sq)
        if x != x { ret x }
        let y = polyval(p, x)
        if math.abs[f64](y) < tol { break }
        xa = x
        y0 = y
        m += 1usize
    }
    ret x
}

// roots(p): the zeros of a polynomial (highest power first, leading coefficient non-zero) by Aberth-Ehrlich iteration; re and im receive them
fn poly_roots(p: []const f64, re: []f64, im: []f64) {
    let n = p.len - 1usize
    // a starting circle of radius 1 + max |c_k / c_0|
    var rad = 0.0f64
    var k = 1usize
    while k <= n {
        let v = math.abs[f64](p[k] / p[0usize])
        if v > rad { rad = v }
        k += 1usize
    }
    rad = 1.0f64 + rad
    k = 0usize
    while k < n {
        let ang = 2.0f64 * 3.141592653589793238462643383279f64 * f64(k) / f64(n) + 0.4f64
        re[k] = rad * math.cos[f64](ang) * 0.5f64
        im[k] = rad * math.sin[f64](ang) * 0.5f64
        k += 1usize
    }
    var it = 0usize
    while it < 500usize {
        var worst = 0.0f64
        k = 0usize
        while k < n {
            // Horner for p(z) and p'(z)
            var fr = p[0usize]
            var fi = 0.0f64
            var dr = 0.0f64
            var di = 0.0f64
            var j = 1usize
            while j <= n {
                let ndr = dr * re[k] - di * im[k] + fr
                let ndi = dr * im[k] + di * re[k] + fi
                dr = ndr
                di = ndi
                let nfr = fr * re[k] - fi * im[k] + p[j]
                let nfi = fr * im[k] + fi * re[k]
                fr = nfr
                fi = nfi
                j += 1usize
            }
            // the Newton ratio p / p'
            let den = dr * dr + di * di
            var wr = 0.0f64
            var wi = 0.0f64
            if den > 0.0f64 {
                wr = (fr * dr + fi * di) / den
                wi = (fi * dr - fr * di) / den
            }
            // the repulsion sum 1 / (z_k - z_j)
            var sr = 0.0f64
            var si = 0.0f64
            j = 0usize
            while j < n {
                if j != k {
                    let ar = re[k] - re[j]
                    let ai = im[k] - im[j]
                    let dd = ar * ar + ai * ai
                    if dd > 0.0f64 {
                        sr += ar / dd
                        si -= ai / dd
                    }
                }
                j += 1usize
            }
            // w / (1 - w s)
            let tr = 1.0f64 - (wr * sr - wi * si)
            let ti = 0.0f64 - (wr * si + wi * sr)
            let td = tr * tr + ti * ti
            var cr = 0.0f64
            var ci = 0.0f64
            if td > 0.0f64 {
                cr = (wr * tr + wi * ti) / td
                ci = (wi * tr - wr * ti) / td
            }
            re[k] -= cr
            im[k] -= ci
            let mag = math.sqrt[f64](cr * cr + ci * ci)
            if mag > worst { worst = mag }
            k += 1usize
        }
        if worst < 1.0e-15f64 { break }
        it += 1usize
    }
}

// conv(a, b): the polynomial product, highest power first; out has a.len + b.len - 1 entries
fn conv(a: []const f64, b: []const f64, out: []f64) {
    var i = 0usize
    while i < a.len + b.len - 1usize {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < a.len {
        var j = 0usize
        while j < b.len {
            out[i + j] += a[i] * b[j]
            j += 1usize
        }
        i += 1usize
    }
}

// deconv(y, a): the quotient q (y.len - a.len + 1 entries) and remainder r (y.len entries) with y = conv(a, q) + r
fn deconv(y: []const f64, a: []const f64, q: []f64, r: []f64) {
    var i = 0usize
    while i < y.len {
        r[i] = y[i]
        i += 1usize
    }
    let nq = y.len - a.len + 1usize
    i = 0usize
    while i < nq {
        q[i] = r[i] / a[0usize]
        var j = 0usize
        while j < a.len {
            r[i + j] -= q[i] * a[j]
            j += 1usize
        }
        i += 1usize
    }
}

// polyint(p, k): the antiderivative with constant k; out has p.len + 1 entries
fn polyint(p: []const f64, k: f64, out: []f64) {
    let n = p.len
    var i = 0usize
    while i < n {
        out[i] = p[i] / f64(n - i)
        i += 1usize
    }
    out[n] = k
}

fn root_f(id: usize, x: f64) -> f64 {
    if id == 0usize { ret x * x * x - 2.0f64 * x - 5.0f64 }
    if id == 1usize { ret math.cos[f64](x) - x }
    if id == 2usize { ret math.exp[f64](x) - 3.0f64 }
    if id == 3usize { ret x * math.exp[f64](x) - 1.0f64 }
    ret math.log[f64](x) + x - 2.0f64
}

// newtonRaphson over one of five fixed functions with the package's numerical derivative (central difference, h = tol^(2/3)); (root, f(root), iterations, estimated precision)
fn newton_raphson(id: usize, x0: f64, maxiter: usize, tol: f64) -> (f64, f64, usize, f64) {
    let h = math.pow[f64](tol, 2.0f64 / 3.0f64)
    var x = x0
    var fx = root_f(id, x)
    var dfx = (root_f(id, x + h) - root_f(id, x - h)) / (2.0f64 * h)
    var niter = 0usize
    var diff = tol + 1.0f64
    while diff >= tol && niter <= maxiter {
        niter += 1usize
        if dfx == 0.0f64 { break }
        diff = 0.0f64 - fx / dfx
        x = x + diff
        diff = math.abs[f64](diff)
        fx = root_f(id, x)
        dfx = (root_f(id, x + h) - root_f(id, x - h)) / (2.0f64 * h)
    }
    ret (x, fx, niter, diff)
}

// romberg(f, a, b, maxit = 25, tol = 1e-12) over the fixed integrands of quadgk: (value, iterations, estimated error)
fn romberg(id: usize, a: f64, b: f64, maxit: usize, tol: f64) -> (f64, usize, f64) {
    let (value, iter, esti) = romberg_run(id, a, b, maxit, tol)
    ret (value, iter, esti)
}

fn romberg_run(id: usize, a: f64, b: f64, maxit: usize, tol: f64) -> (f64, usize, f64) {
    if a == b { ret (0.0f64, 0usize, 0.0f64) }
    if a > b {
        let (v, it, er) = romberg_run(id, b, a, maxit, tol)
        ret (0.0f64 - v, it, er)
    }
    let w = maxit + 1usize
    var tab: [676]f64 = zero
    var n = 1usize
    var iter = 0usize
    var esti = 1.0f64
    while esti > tol && iter < maxit {
        iter += 1usize
        n = 2usize * n
        let h = (b - a) / f64(n)
        var s = quad_f(id, a)
        var i = 1usize
        while i < n {
            s += 2.0f64 * quad_f(id, a + h * f64(i))
            i += 1usize
        }
        s = (s + quad_f(id, b)) * h / 2.0f64
        tab[iter * w] = s
        var k = 2usize
        while k <= iter + 1usize {
            let j = iter + 1usize - k
            let p = math.pow[f64](4.0f64, f64(k - 1usize))
            tab[j * w + (k - 1usize)] = (p * tab[(j + 1usize) * w + (k - 2usize)] - tab[j * w + (k - 2usize)]) / (p - 1.0f64)
            k += 1usize
        }
        esti = math.abs[f64](tab[iter] - tab[1usize * w + (iter - 1usize)])
    }
    ret (tab[iter], iter, esti)
}

// quadl: the package's adaptive Gauss-Lobatto (Gander and Gautschi) on the quad_f integrands
fn lob_step(id: usize, a: f64, b: f64, fa: f64, fb: f64, ab: f64) -> f64 {
    let h = (b - a) / 2.0f64
    let m = (a + b) / 2.0f64
    let alpha = math.sqrt[f64](2.0f64 / 3.0f64)
    let beta = 1.0f64 / math.sqrt[f64](5.0f64)
    let mll = m - alpha * h
    let ml = m - beta * h
    let mr = m + beta * h
    let mrr = m + alpha * h
    let fmll = quad_f(id, mll)
    let fml = quad_f(id, ml)
    let fm = quad_f(id, m)
    let fmr = quad_f(id, mr)
    let fmrr = quad_f(id, mrr)
    let i2 = (h / 6.0f64) * (fa + fb + 5.0f64 * (fml + fmr))
    let i1 = (h / 1470.0f64) * (77.0f64 * (fa + fb) + 432.0f64 * (fmll + fmrr) + 625.0f64 * (fml + fmr) + 672.0f64 * fm)
    if ab + (i1 - i2) == ab || mll <= a || b <= mrr { ret i1 }
    ret lob_step(id, a, mll, fa, fmll, ab) + lob_step(id, mll, ml, fmll, fml, ab) + lob_step(id, ml, m, fml, fm, ab) + lob_step(id, m, mr, fm, fmr, ab) + lob_step(id, mr, mrr, fmr, fmrr, ab) + lob_step(id, mrr, b, fmrr, fb, ab)
}

fn quadl(id: usize, xa0: f64, xb0: f64, tol0: f64) -> f64 {
    if xa0 == xb0 { ret 0.0f64 }
    var xa = xa0
    var xb = xb0
    var rev = false
    if xa > xb {
        xa = xb0
        xb = xa0
        rev = true
    }
    let e = eps()
    if quad_f(id, xa) - quad_f(id, xa) != 0.0f64 { xa += 2.0f64 * e }
    if quad_f(id, xb) - quad_f(id, xb) != 0.0f64 { xb -= 2.0f64 * e }
    let a = xa
    let b = xb
    let m = (a + b) / 2.0f64
    let h = (b - a) / 2.0f64
    let alpha = math.sqrt[f64](2.0f64 / 3.0f64)
    let beta = 1.0f64 / math.sqrt[f64](5.0f64)
    let x1 = 0.94288241569548f64
    let x2 = 0.641853342345781f64
    let x3 = 0.23638319966215f64
    let y1 = quad_f(id, a)
    let y2 = quad_f(id, m - x1 * h)
    let y3 = quad_f(id, m - alpha * h)
    let y4 = quad_f(id, m - x2 * h)
    let y5 = quad_f(id, m - beta * h)
    let y6 = quad_f(id, m - x3 * h)
    let y7 = quad_f(id, m)
    let y8 = quad_f(id, m + x3 * h)
    let y9 = quad_f(id, m + beta * h)
    let y10 = quad_f(id, m + x2 * h)
    let y11 = quad_f(id, m + alpha * h)
    let y12 = quad_f(id, m + x1 * h)
    let y13 = quad_f(id, b)
    let i2 = (h / 6.0f64) * (y1 + y13 + 5.0f64 * (y5 + y9))
    let i1 = (h / 1470.0f64) * (77.0f64 * (y1 + y13) + 432.0f64 * (y3 + y11) + 625.0f64 * (y5 + y9) + 672.0f64 * y7)
    var ab = h * (0.0158271919734802f64 * (y1 + y13) + 0.09427384021885f64 * (y2 + y12) + 0.155071987336585f64 * (y3 + y11) + 0.188821573960182f64 * (y4 + y10) + 0.199773405226859f64 * (y5 + y9) + 0.22492646533334f64 * (y6 + y8) + 0.242611071901408f64 * y7)
    var s = 1.0f64
    if ab < 0.0f64 { s = 0.0f64 - 1.0f64 }
    let erri1 = math.abs[f64](i1 - ab)
    let erri2 = math.abs[f64](i2 - ab)
    var r = 1.0f64
    if erri2 != 0.0f64 { r = erri1 / erri2 }
    var tol = tol0
    if r > 0.0f64 && r < 1.0f64 { tol = tol / r }
    ab = s * math.abs[f64](ab) * tol / e
    if ab == 0.0f64 { ab = b - a }
    var q = lob_step(id, a, b, y1, y13, ab)
    if rev { q = 0.0f64 - q }
    ret q
}

fn fz_f(id: usize, x: f64) -> f64 {
    if id == 0usize { ret math.cos[f64](x) - x }
    if id == 1usize { ret x * x * x - 2.0f64 * x - 5.0f64 }
    if id == 2usize { ret math.exp[f64](x) - 3.0f64 }
    if id == 3usize { ret x * math.exp[f64](0.0f64 - x) - 0.2f64 }
    ret math.sin[f64](x) - 0.5f64 * x
}

// fzero on a bracket [a, b] with f(a) f(b) < 0: Brent's method to tol, the root the package reports
fn fzero(id: usize, a0: f64, b0: f64, tol: f64) -> f64 {
    var a = a0
    var b = b0
    var fa = fz_f(id, a)
    var fb = fz_f(id, b)
    var c = a
    var fc = fa
    var d = b - a
    var e = d
    var it = 0usize
    while it < 500usize {
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
            d = b - a
            e = d
        }
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol1 = 2.0f64 * eps() * math.abs[f64](b) + 0.5f64 * tol
        let xm = 0.5f64 * (c - b)
        if math.abs[f64](xm) <= tol1 || fb == 0.0f64 { ret b }
        if math.abs[f64](e) >= tol1 && math.abs[f64](fa) > math.abs[f64](fb) {
            let sv = fb / fa
            var p = 0.0f64
            var q = 0.0f64
            if a == c {
                p = 2.0f64 * xm * sv
                q = 1.0f64 - sv
            } else {
                let qq = fa / fc
                let r = fb / fc
                p = sv * (2.0f64 * xm * qq * (qq - r) - (b - a) * (r - 1.0f64))
                q = (qq - 1.0f64) * (r - 1.0f64) * (sv - 1.0f64)
            }
            if p > 0.0f64 { q = 0.0f64 - q }
            p = math.abs[f64](p)
            let m1 = 3.0f64 * xm * q - math.abs[f64](tol1 * q)
            let m2 = math.abs[f64](e * q)
            var mn = m1
            if m2 < mn { mn = m2 }
            if 2.0f64 * p < mn {
                e = d
                d = p / q
            } else {
                d = xm
                e = d
            }
        } else {
            d = xm
            e = d
        }
        a = b
        fa = fb
        if math.abs[f64](d) > tol1 {
            b += d
        } else if xm > 0.0f64 {
            b += tol1
        } else {
            b -= tol1
        }
        fb = fz_f(id, b)
        it += 1usize
    }
    ret b
}

// interp1(x, y, xi, method) at one xi inside [x[0], x[n-1]] (x sorted): method 0 linear, 1 nearest, 2 spline (the package's not-a-knot slopes, at least three points)
fn interp1(a: *mem.Arena, x: []const f64, y: []const f64, xi: f64, method: usize) -> f64 {
    let n = x.len
    var k = 0usize
    var j = 1usize
    // approx: the last knot at or below xi, the final interval when xi is the last knot
    while j < n - 1usize {
        if x[j] <= xi { k = j }
        j += 1usize
    }
    if method == 0usize {
        let t = (xi - x[k]) / (x[k + 1usize] - x[k])
        if xi == x[n - 1usize] { ret y[n - 1usize] }
        ret y[k] + t * (y[k + 1usize] - y[k])
    }
    if method == 1usize {
        // constant on the midpoints, right-continuous: the knot whose cell [mid_left, mid_right) holds xi
        var i = 0usize
        while i + 1usize < n && xi >= (x[i] + x[i + 1usize]) / 2.0f64 { i += 1usize }
        ret y[i]
    }
    let (h, e1) = mem.alloc[f64](a, n - 1usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (dl, e2) = mem.alloc[f64](a, n - 1usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i + 1usize < n {
        h[i] = x[i + 1usize] - x[i]
        dl[i] = (y[i + 1usize] - y[i]) / h[i]
        i += 1usize
    }
    let (sa, e3) = mem.alloc[f64](a, n - 1usize)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (sb, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let (sc, e5) = mem.alloc[f64](a, n - 1usize)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    let (r, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i + 2usize < n {
        sa[i] = h[i + 1usize]
        i += 1usize
    }
    sa[n - 2usize] = h[n - 3usize] + h[n - 2usize]
    sb[0usize] = h[1usize]
    i = 1usize
    while i + 1usize < n {
        sb[i] = 2.0f64 * (h[i] + h[i - 1usize])
        i += 1usize
    }
    sb[n - 1usize] = h[n - 3usize]
    sc[0usize] = h[0usize] + h[1usize]
    i = 1usize
    while i + 1usize < n {
        sc[i] = h[i - 1usize]
        i += 1usize
    }
    r[0usize] = ((h[0usize] + 2.0f64 * sc[0usize]) * h[1usize] * dl[0usize] + h[0usize] * h[0usize] * dl[1usize]) / sc[0usize]
    i = 1usize
    while i + 1usize < n {
        r[i] = 3.0f64 * (h[i] * dl[i - 1usize] + h[i - 1usize] * dl[i])
        i += 1usize
    }
    r[n - 1usize] = (h[n - 2usize] * h[n - 2usize] * dl[n - 3usize] + (2.0f64 * sa[n - 2usize] + h[n - 2usize]) * h[n - 3usize] * dl[n - 2usize]) / sa[n - 2usize]
    i = 0usize
    while i + 1usize < n {
        let mu = sa[i] / sb[i]
        sb[i + 1usize] = sb[i + 1usize] - mu * sc[i]
        r[i + 1usize] = r[i + 1usize] - mu * r[i]
        i += 1usize
    }
    r[n - 1usize] = r[n - 1usize] / sb[n - 1usize]
    i = n - 1usize
    while i > 0usize {
        r[i - 1usize] = (r[i - 1usize] - sc[i - 1usize] * r[i]) / sb[i - 1usize]
        i -= 1usize
    }
    let cc = (3.0f64 * dl[k] - 2.0f64 * r[k] - r[k + 1usize]) / h[k]
    let bb = (r[k] - 2.0f64 * dl[k] + r[k + 1usize]) / (h[k] * h[k])
    let s = xi - x[k]
    ret y[k] + s * (r[k] + s * (cc + s * bb))
}

// savgol(T, fl, forder, dorder): row dorder of the pseudo-inverse of the Vandermonde matrix (-fc .. fc)^(0 .. forder), convolved with T and trimmed to T's length (zero outside the data)
fn savgol(a: *mem.Arena, t: []const f64, fl: usize, forder: usize, dorder: usize, out: []f64) -> err {
    let fc = (fl - 1usize) / 2usize
    let p = forder + 1usize
    let (xt, e1) = mem.alloc[f64](a, p * fl)
    if e1 != ok { ret e1 }
    var r = 0usize
    while r < fl {
        let v = f64(r) - f64(fc)
        var pw = 1.0f64
        var c = 0usize
        while c < p {
            xt[c * fl + r] = pw
            pw = pw * v
            c += 1usize
        }
        r += 1usize
    }
    // X'X (p by p), inverted by Gauss-Jordan, then row dorder of (X'X)^-1 X'
    let (g, e2) = mem.alloc[f64](a, p * 2usize * p)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < fl {
                s += xt[i * fl + k] * xt[j * fl + k]
                k += 1usize
            }
            g[i * 2usize * p + j] = s
            g[i * 2usize * p + p + j] = 0.0f64
            if i == j { g[i * 2usize * p + p + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var col = 0usize
    while col < p {
        var piv = col
        var rr = col + 1usize
        while rr < p {
            if math.abs[f64](g[rr * 2usize * p + col]) > math.abs[f64](g[piv * 2usize * p + col]) { piv = rr }
            rr += 1usize
        }
        if piv != col {
            var k = 0usize
            while k < 2usize * p {
                let tmp = g[col * 2usize * p + k]
                g[col * 2usize * p + k] = g[piv * 2usize * p + k]
                g[piv * 2usize * p + k] = tmp
                k += 1usize
            }
        }
        let d = g[col * 2usize * p + col]
        var k = 0usize
        while k < 2usize * p {
            g[col * 2usize * p + k] = g[col * 2usize * p + k] / d
            k += 1usize
        }
        rr = 0usize
        while rr < p {
            if rr != col {
                let f = g[rr * 2usize * p + col]
                k = 0usize
                while k < 2usize * p {
                    g[rr * 2usize * p + k] = g[rr * 2usize * p + k] - f * g[col * 2usize * p + k]
                    k += 1usize
                }
            }
            rr += 1usize
        }
        col += 1usize
    }
    let (y, e3) = mem.alloc[f64](a, fl)
    if e3 != ok { ret e3 }
    var k = 0usize
    while k < fl {
        var s = 0.0f64
        var q = 0usize
        while q < p {
            s += g[dorder * 2usize * p + p + q] * xt[q * fl + k]
            q += 1usize
        }
        y[k] = s
        k += 1usize
    }
    var sign = 1.0f64
    if dorder % 2usize == 1usize { sign = 0.0f64 - 1.0f64 }
    let n = t.len
    i = 0usize
    while i < n {
        var s = 0.0f64
        var m = 0usize
        while m < fl {
            // the coefficient on T[i + m - fc] is y[fl - 1 - m]
            let idx = i + m
            if idx >= fc && idx - fc < n { s += t[idx - fc] * y[fl - 1usize - m] }
            m += 1usize
        }
        out[i] = sign * s
        i += 1usize
    }
    ret ok
}
