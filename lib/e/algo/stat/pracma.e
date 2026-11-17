// R pracma: trapz, cumtrapz, polyval, polyfit (Householder least squares), findpeaks, rref, primes, factors, extended gcd, nchoosek, cross.
//
// Not here: the rest of the toolbox (quadrature, root finders, interpolation, orthogonal polynomials, matrix functions).

use e.math
use e.algo.linalg.decomp as decomp
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
    if method == 3usize {
        // "constant": the value of the last knot at or below xi
        if xi == x[n - 1usize] { ret y[n - 1usize] }
        ret y[k]
    }
    if method == 4usize { ret pchip(a, x, y, xi) }
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

// kron(A, B): the Kronecker product of the ra by ca matrix a and the rb by cb matrix b (row-major) into out ((ra rb) by (ca cb))
fn kron(a: []const f64, ra: usize, ca: usize, b: []const f64, rb: usize, cb: usize, out: []f64) {
    let oc = ca * cb
    var i = 0usize
    while i < ra {
        var j = 0usize
        while j < ca {
            var k = 0usize
            while k < rb {
                var l = 0usize
                while l < cb {
                    out[(i * rb + k) * oc + j * cb + l] = a[i * ca + j] * b[k * cb + l]
                    l += 1usize
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
}

// the inverse of a p by p matrix by Gauss-Jordan with partial pivoting into out; scratch holds 2 p p values; false when singular
fn mat_inverse(m: []const f64, p: usize, out: []f64, scratch: []f64) -> bool {
    let w = 2usize * p
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            scratch[i * w + j] = m[i * p + j]
            scratch[i * w + p + j] = 0.0f64
            if i == j { scratch[i * w + p + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var col = 0usize
    while col < p {
        var piv = col
        var r = col + 1usize
        while r < p {
            if math.abs[f64](scratch[r * w + col]) > math.abs[f64](scratch[piv * w + col]) { piv = r }
            r += 1usize
        }
        if scratch[piv * w + col] == 0.0f64 { ret false }
        if piv != col {
            var k = 0usize
            while k < w {
                let t = scratch[col * w + k]
                scratch[col * w + k] = scratch[piv * w + k]
                scratch[piv * w + k] = t
                k += 1usize
            }
        }
        let d = scratch[col * w + col]
        var k = 0usize
        while k < w {
            scratch[col * w + k] = scratch[col * w + k] / d
            k += 1usize
        }
        r = 0usize
        while r < p {
            if r != col {
                let f = scratch[r * w + col]
                k = 0usize
                while k < w {
                    scratch[r * w + k] = scratch[r * w + k] - f * scratch[col * w + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            out[i * p + j] = scratch[i * w + p + j]
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// pinv(A) for a matrix of full rank (m by n, row-major) into out (n by m): (A'A)^-1 A' when m >= n, A' (A A')^-1 otherwise
fn pinv_full(a: *mem.Arena, m: []const f64, rows: usize, cols: usize, out: []f64) -> bool {
    var k = cols
    if rows < cols { k = rows }
    let (g, e1) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret false }
    let (gi, e2) = mem.alloc[f64](a, k * k)
    if e2 != ok { ret false }
    let (sc, e3) = mem.alloc[f64](a, 2usize * k * k)
    if e3 != ok { ret false }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var t = 0usize
            if rows >= cols {
                while t < rows {
                    s += m[t * cols + i] * m[t * cols + j]
                    t += 1usize
                }
            } else {
                while t < cols {
                    s += m[i * cols + t] * m[j * cols + t]
                    t += 1usize
                }
            }
            g[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if !mat_inverse(g, k, gi, sc) { ret false }
    i = 0usize
    while i < cols {
        var j = 0usize
        while j < rows {
            var s = 0.0f64
            var t = 0usize
            while t < k {
                if rows >= cols { s += gi[i * k + t] * m[j * cols + t] } else { s += m[t * cols + i] * gi[t * k + j] }
                t += 1usize
            }
            out[i * rows + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// the singular values of the m by n row-major matrix (m >= n or not) by one-sided Jacobi rotations on a copy of its columns, in descending order into s (min(m, n) values);
// work holds m * n + n values
fn singular_values(a: []const f64, m: usize, n: usize, s: []f64, work: []f64) {
    // work on the matrix with more rows than columns: transpose a wide input
    var rows = m
    var cols = n
    var wide = false
    if m < n {
        rows = n
        cols = m
        wide = true
    }
    let u = work[0usize..rows * cols]
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            if wide { u[j * cols + i] = a[i * n + j] } else { u[i * cols + j] = a[i * n + j] }
            j += 1usize
        }
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 60usize {
        var rotated = false
        var p = 0usize
        while p + 1usize < cols {
            var q = p + 1usize
            while q < cols {
                var alpha = 0.0f64
                var beta = 0.0f64
                var gamma = 0.0f64
                var r = 0usize
                while r < rows {
                    alpha += u[r * cols + p] * u[r * cols + p]
                    beta += u[r * cols + q] * u[r * cols + q]
                    gamma += u[r * cols + p] * u[r * cols + q]
                    r += 1usize
                }
                if math.abs[f64](gamma) > 1.0e-15f64 * math.sqrt[f64](alpha * beta) && gamma != 0.0f64 {
                    rotated = true
                    let zeta = (beta - alpha) / (2.0f64 * gamma)
                    var t = 1.0f64 / (math.abs[f64](zeta) + math.sqrt[f64](1.0f64 + zeta * zeta))
                    if zeta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](1.0f64 + t * t)
                    let sn = c * t
                    r = 0usize
                    while r < rows {
                        let up = u[r * cols + p]
                        let uq = u[r * cols + q]
                        u[r * cols + p] = c * up - sn * uq
                        u[r * cols + q] = sn * up + c * uq
                        r += 1usize
                    }
                }
                q += 1usize
            }
            p += 1usize
        }
        if !rotated { break }
        sweep += 1usize
    }
    var c = 0usize
    while c < cols {
        var ss = 0.0f64
        var r = 0usize
        while r < rows {
            ss += u[r * cols + c] * u[r * cols + c]
            r += 1usize
        }
        s[c] = math.sqrt[f64](ss)
        c += 1usize
    }
    // descending order
    var a2 = 1usize
    while a2 < cols {
        let t = s[a2]
        var b2 = a2
        while b2 > 0usize && s[b2 - 1usize] < t {
            s[b2] = s[b2 - 1usize]
            b2 -= 1usize
        }
        s[b2] = t
        a2 += 1usize
    }
}

// the thin SVD of a tall or square m by n matrix (m >= n) by one-sided Jacobi: u (m by n, columns scaled to unit length where the singular value is above 1e-300), s (n, unsorted)
// and v (n by n); work holds m * n values
fn svd_jacobi(a: []const f64, m: usize, n: usize, u: []f64, s: []f64, v: []f64) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            u[i * n + j] = a[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            v[i * n + j] = 0.0f64
            if i == j { v[i * n + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 60usize {
        var rotated = false
        var p = 0usize
        while p + 1usize < n {
            var q = p + 1usize
            while q < n {
                var alpha = 0.0f64
                var beta = 0.0f64
                var gamma = 0.0f64
                var r = 0usize
                while r < m {
                    alpha += u[r * n + p] * u[r * n + p]
                    beta += u[r * n + q] * u[r * n + q]
                    gamma += u[r * n + p] * u[r * n + q]
                    r += 1usize
                }
                if gamma != 0.0f64 && math.abs[f64](gamma) > 1.0e-15f64 * math.sqrt[f64](alpha * beta) {
                    rotated = true
                    let zeta = (beta - alpha) / (2.0f64 * gamma)
                    var t = 1.0f64 / (math.abs[f64](zeta) + math.sqrt[f64](1.0f64 + zeta * zeta))
                    if zeta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](1.0f64 + t * t)
                    let sn = c * t
                    r = 0usize
                    while r < m {
                        let up = u[r * n + p]
                        let uq = u[r * n + q]
                        u[r * n + p] = c * up - sn * uq
                        u[r * n + q] = sn * up + c * uq
                        r += 1usize
                    }
                    r = 0usize
                    while r < n {
                        let vp = v[r * n + p]
                        let vq = v[r * n + q]
                        v[r * n + p] = c * vp - sn * vq
                        v[r * n + q] = sn * vp + c * vq
                        r += 1usize
                    }
                }
                q += 1usize
            }
            p += 1usize
        }
        if !rotated { break }
        sweep += 1usize
    }
    var c = 0usize
    while c < n {
        var ss = 0.0f64
        var r = 0usize
        while r < m {
            ss += u[r * n + c] * u[r * n + c]
            r += 1usize
        }
        s[c] = math.sqrt[f64](ss)
        if s[c] > 1.0e-300f64 {
            r = 0usize
            while r < m {
                u[r * n + c] = u[r * n + c] / s[c]
                r += 1usize
            }
        }
        c += 1usize
    }
}

// the entry (i, j) of the projector onto orth(A) (the range of A, m by n tall) when `range` is true, or of the projector onto null(A) (n by n) when false; the rank is the
// number of singular values above 1e-10 times the largest
fn svd_projector(a: *mem.Arena, m: []const f64, rows: usize, cols: usize, range: bool, i: usize, j: usize) -> f64 {
    let (u, e1) = mem.alloc[f64](a, rows * cols)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (s, e2) = mem.alloc[f64](a, cols)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (v, e3) = mem.alloc[f64](a, cols * cols)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    svd_jacobi(m, rows, cols, u, s, v)
    var smax = 0.0f64
    var k = 0usize
    while k < cols {
        if s[k] > smax { smax = s[k] }
        k += 1usize
    }
    var acc = 0.0f64
    k = 0usize
    while k < cols {
        if s[k] > 1.0e-10f64 * smax {
            if range { acc += u[i * cols + k] * u[j * cols + k] } else { acc += v[i * cols + k] * v[j * cols + k] }
        }
        k += 1usize
    }
    if range { ret acc }
    if i == j { ret 1.0f64 - acc }
    ret 0.0f64 - acc
}

// pracma::expm(A, np = 128): the contour integral of the resolvent over a circle (centre z0 = ceiling(mean(range(Re(eig(A)))) + 0.1), radius ceiling(max|eig - z0| + 0.1)),
// as the package computes it, then zapsmall(digits = 7); m is n by n row-major
fn expm(a: *mem.Arena, m: []const f64, n: usize, np: usize, out: []f64) -> err {
    let nn = n * n
    let (ev, ee) = decomp.eigen(a, m, n)
    if ee != ok { ret ee }
    var lo = ev.re[0usize]
    var hi = ev.re[0usize]
    var i = 0usize
    while i < n {
        if ev.re[i] < lo { lo = ev.re[i] }
        if ev.re[i] > hi { hi = ev.re[i] }
        i += 1usize
    }
    let z0 = math.ceil[f64]((lo + hi) / 2.0f64 + 0.1f64)
    var rmax = 0.0f64
    i = 0usize
    while i < n {
        let d = math.sqrt[f64]((ev.re[i] - z0) * (ev.re[i] - z0) + ev.im[i] * ev.im[i])
        if d > rmax { rmax = d }
        i += 1usize
    }
    let radius = math.ceil[f64](rmax + 0.1f64)
    let (wr, e1) = mem.alloc[f64](a, n * 2usize * n)
    let (wi, e2) = mem.alloc[f64](a, n * 2usize * n)
    let (br, e3) = mem.alloc[f64](a, nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    i = 0usize
    while i < nn {
        br[i] = 0.0f64
        i += 1usize
    }
    let w2 = 2usize * n
    var k = 1usize
    while k <= np {
        let ang = 2.0f64 * 3.141592653589793238462643383279f64 * f64(k) / f64(np)
        let zr = z0 + radius * math.cos[f64](ang)
        let zi = radius * math.sin[f64](ang)
        // [z I - A | I] by Gauss-Jordan with partial pivoting
        var r = 0usize
        while r < n {
            var c = 0usize
            while c < n {
                wr[r * w2 + c] = 0.0f64 - m[r * n + c]
                wi[r * w2 + c] = 0.0f64
                if r == c {
                    wr[r * w2 + c] += zr
                    wi[r * w2 + c] = zi
                }
                wr[r * w2 + n + c] = 0.0f64
                wi[r * w2 + n + c] = 0.0f64
                if r == c { wr[r * w2 + n + c] = 1.0f64 }
                c += 1usize
            }
            r += 1usize
        }
        var col = 0usize
        while col < n {
            var piv = col
            var best = wr[col * w2 + col] * wr[col * w2 + col] + wi[col * w2 + col] * wi[col * w2 + col]
            var rr = col + 1usize
            while rr < n {
                let mg = wr[rr * w2 + col] * wr[rr * w2 + col] + wi[rr * w2 + col] * wi[rr * w2 + col]
                if mg > best {
                    best = mg
                    piv = rr
                }
                rr += 1usize
            }
            var cc = 0usize
            while cc < w2 {
                let t1 = wr[col * w2 + cc]
                let t2 = wi[col * w2 + cc]
                wr[col * w2 + cc] = wr[piv * w2 + cc]
                wi[col * w2 + cc] = wi[piv * w2 + cc]
                wr[piv * w2 + cc] = t1
                wi[piv * w2 + cc] = t2
                cc += 1usize
            }
            let pr = wr[col * w2 + col]
            let pi = wi[col * w2 + col]
            let den = pr * pr + pi * pi
            cc = 0usize
            while cc < w2 {
                let xr = wr[col * w2 + cc]
                let xi = wi[col * w2 + cc]
                wr[col * w2 + cc] = (xr * pr + xi * pi) / den
                wi[col * w2 + cc] = (xi * pr - xr * pi) / den
                cc += 1usize
            }
            rr = 0usize
            while rr < n {
                if rr != col {
                    let fr = wr[rr * w2 + col]
                    let fi = wi[rr * w2 + col]
                    cc = 0usize
                    while cc < w2 {
                        wr[rr * w2 + cc] -= fr * wr[col * w2 + cc] - fi * wi[col * w2 + cc]
                        wi[rr * w2 + cc] -= fr * wi[col * w2 + cc] + fi * wr[col * w2 + cc]
                        cc += 1usize
                    }
                }
                rr += 1usize
            }
            col += 1usize
        }
        // weight (z - z0) exp(z)
        let ex = math.exp[f64](zr)
        let er = ex * math.cos[f64](zi)
        let ei = ex * math.sin[f64](zi)
        let dr = zr - z0
        let di = zi
        let sr = dr * er - di * ei
        let si = dr * ei + di * er
        r = 0usize
        while r < n {
            var c = 0usize
            while c < n {
                br[r * n + c] += wr[r * w2 + n + c] * sr - wi[r * w2 + n + c] * si
                c += 1usize
            }
            r += 1usize
        }
        k += 1usize
    }
    var mx = 0.0f64
    i = 0usize
    while i < nn {
        out[i] = br[i] / f64(np)
        if math.abs[f64](out[i]) > mx { mx = math.abs[f64](out[i]) }
        i += 1usize
    }
    if mx > 0.0f64 {
        var dg = math.floor[f64](7.0f64 - math.log10[f64](mx) + 0.5f64)
        if dg < 0.0f64 { dg = 0.0f64 }
        let sc10 = math.pow[f64](10.0f64, dg)
        i = 0usize
        while i < nn {
            out[i] = math.round[f64](out[i] * sc10) / sc10
            i += 1usize
        }
    }
    ret ok
}

// pracma::integral(f, lo, hi) (method "Kronrod", no_intervals = 8, reltol 1e-8): quadgk on the 8 pieces of linspace(lo, hi, 9)
fn integral(id: usize, lo: f64, hi: f64) -> f64 {
    if lo == hi { ret 0.0f64 }
    let by = (hi - lo) / 8.0f64
    var q = 0.0f64
    var i = 0usize
    while i < 8usize {
        var x0 = lo + f64(i) * by
        var x1 = lo + f64(i + 1usize) * by
        if i + 1usize == 8usize { x1 = hi }
        if i == 0usize { x0 = lo }
        q = q + quadgk(id, x0, x1, 1.0e-8f64)
        i += 1usize
    }
    ret q
}

// polynomial division of b by a (highest power first) as pracma's deconv: the quotient into q (len b - len a + 1); returns its length
fn deconv_q(b0: []const f64, a: []const f64, q: []f64, scratch: []f64) -> usize {
    var nb = b0.len
    var i = 0usize
    while i < nb {
        scratch[i] = b0[i]
        i += 1usize
    }
    if nb < a.len {
        q[0usize] = 0.0f64
        ret 1usize
    }
    var nq = 0usize
    var off = 0usize
    while nb >= a.len {
        let d = scratch[off] / a[0usize]
        i = 0usize
        while i < a.len {
            scratch[off + i] -= d * a[i]
            i += 1usize
        }
        q[nq] = d
        nq += 1usize
        off += 1usize
        nb -= 1usize
    }
    ret nq
}

// pracma::polyroots(p, ntol = 1e-4, ztol = 1e-8): the distinct roots (re, im) and their multiplicities; returns the count
fn polyroots(a: *mem.Arena, p: []const f64, re: []f64, im: []f64, mult: []f64) -> usize {
    let ntol = 1.0e-4f64
    let ztol = 1.0e-8f64
    var cnt = 0usize
    var minp = p.len
    var maxp = 0usize
    var i = 0usize
    while i < p.len {
        if p[i] != 0.0f64 {
            if i < minp { minp = i }
            maxp = i
        }
        i += 1usize
    }
    if minp == p.len { ret 0usize }
    let mz = p.len - 1usize - maxp
    if mz > 0usize {
        re[0usize] = 0.0f64
        im[0usize] = 0.0f64
        mult[0usize] = f64(mz)
        cnt = 1usize
    }
    let n0 = maxp - minp + 1usize
    if n0 < 2usize { ret cnt }
    let (p0, e1) = mem.alloc[f64](a, n0)
    let (q0, e2) = mem.alloc[f64](a, n0)
    let (g1, e3) = mem.alloc[f64](a, 2usize * n0 + 2usize)
    let (g2, e4) = mem.alloc[f64](a, 2usize * n0 + 2usize)
    let (g3, e5) = mem.alloc[f64](a, 2usize * n0 + 2usize)
    let (uq, e6) = mem.alloc[f64](a, n0)
    let (vq, e7) = mem.alloc[f64](a, n0)
    let (sc, e8) = mem.alloc[f64](a, n0)
    let (w0, e9) = mem.alloc[f64](a, n0)
    let (zr, e10) = mem.alloc[f64](a, n0)
    let (zi, e11) = mem.alloc[f64](a, n0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret cnt }
    i = 0usize
    while i < n0 {
        p0[i] = p[minp + i]
        i += 1usize
    }
    let s = math.abs[f64](p0[n0 - 1usize] / p0[0usize])
    if s < 1.0f64 {
        i = 0usize
        while i < n0 {
            sc[i] = p0[n0 - 1usize - i]
            i += 1usize
        }
        i = 0usize
        while i < n0 {
            p0[i] = sc[i]
            i += 1usize
        }
    }
    polyder(p0, q0[0usize..n0 - 1usize])
    var l1 = n0
    i = 0usize
    while i < n0 {
        g1[i] = p0[i] / p0[0usize]
        i += 1usize
    }
    var l2 = n0 - 1usize
    while l2 > 1usize && q0[l2 - 1usize] == 0.0f64 { l2 -= 1usize }
    i = 0usize
    while i < l2 {
        g2[i] = q0[i] / q0[0usize]
        i += 1usize
    }
    var k = 3usize
    while k <= 2usize * n0 {
        var l3 = l1
        if l2 > l1 { l3 = l2 }
        i = 0usize
        while i < l3 {
            var av = 0.0f64
            var bv = 0.0f64
            if i < l2 { av = g2[i] }
            if i < l1 { bv = g1[i] }
            g3[i] = av - bv
            i += 1usize
        }
        var lo = l3
        var hi = 0usize
        i = 0usize
        while i < l3 {
            if math.abs[f64](g3[i]) > ztol {
                if i < lo { lo = i }
                hi = i
            }
            i += 1usize
        }
        var n3 = 1usize
        var mx3 = 0.0f64
        if lo == l3 {
            g3[0usize] = 0.0f64
        } else {
            n3 = hi - lo + 1usize
            i = 0usize
            while i < n3 {
                g3[i] = g3[lo + i]
                i += 1usize
            }
        }
        i = 0usize
        while i < n3 {
            if math.abs[f64](g3[i]) > mx3 { mx3 = math.abs[f64](g3[i]) }
            i += 1usize
        }
        var mx2 = 0.0f64
        i = 0usize
        while i < l2 {
            if math.abs[f64](g2[i]) > mx2 { mx2 = math.abs[f64](g2[i]) }
            i += 1usize
        }
        if mx3 / mx2 < ntol { break }
        if l1 >= l2 {
            i = 0usize
            while i < l2 {
                g1[i] = g2[i]
                i += 1usize
            }
            l1 = l2
        }
        i = 0usize
        while i < n3 {
            g2[i] = g3[i] / g3[0usize]
            i += 1usize
        }
        l2 = n3
        k += 1usize
    }
    let nu = deconv_q(p0, g1[0usize..l1], uq, sc)
    let nv = deconv_q(q0[0usize..n0 - 1usize], g1[0usize..l1], vq, sc)
    if nu < 2usize { ret cnt }
    polyder(uq[0usize..nu], w0[0usize..nu - 1usize])
    poly_roots(uq[0usize..nu], zr[0usize..nu - 1usize], zi[0usize..nu - 1usize])
    i = 0usize
    while i + 1usize < nu {
        var vr = 0.0f64
        var vi = 0.0f64
        var j = 0usize
        while j < nv {
            let t = vr * zr[i] - vi * zi[i] + vq[j]
            vi = vr * zi[i] + vi * zr[i]
            vr = t
            j += 1usize
        }
        var wr = 0.0f64
        var wi = 0.0f64
        j = 0usize
        while j + 1usize < nu {
            let t = wr * zr[i] - wi * zi[i] + w0[j]
            wi = wr * zi[i] + wi * zr[i]
            wr = t
            j += 1usize
        }
        let mg = math.sqrt[f64]((vr * vr + vi * vi) / (wr * wr + wi * wi))
        var rr = zr[i]
        var ri = zi[i]
        if s < 1.0f64 {
            let dn = rr * rr + ri * ri
            rr = rr / dn
            ri = 0.0f64 - ri / dn
        }
        re[cnt] = rr
        im[cnt] = ri
        mult[cnt] = math.round[f64](mg)
        cnt += 1usize
        i += 1usize
    }
    ret cnt
}

// pinv(A) of any rank by the singular value decomposition, as pracma does: singular values at most tol * d[1] (tol = eps^(2/3)) are dropped; m is rows by cols row-major, out is cols by rows row-major
fn pinv_svd(a: *mem.Arena, m: []const f64, rows: usize, cols: usize, out: []f64) -> bool {
    let (cm, e1) = mem.alloc[f64](a, rows * cols)
    if e1 != ok { ret false }
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            cm[j * rows + i] = m[i * cols + j]
            j += 1usize
        }
        i += 1usize
    }
    let (sv, e) = decomp.svd(a, cm, rows, cols)
    if e != ok { ret false }
    var k = rows
    if cols < rows { k = cols }
    let tol = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
    i = 0usize
    while i < cols * rows {
        out[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        if sv.d[c] > tol * sv.d[0usize] {
            var r = 0usize
            while r < cols {
                var q = 0usize
                while q < rows {
                    out[r * rows + q] += sv.v[c * cols + r] * sv.u[c * rows + q] / sv.d[c]
                    q += 1usize
                }
                r += 1usize
            }
        }
        c += 1usize
    }
    ret true
}

// ---- R's polyroot: the Jenkins-Traub complex polynomial zero finder (R's cpoly), ported with its state and iteration order, so the roots come out in R's order ----

type Cp = struct { nn: i64, pr: []f64, pi: []f64, hr: []f64, hi: []f64, qpr: []f64, qpi: []f64, qhr: []f64, qhi: []f64, shr: []f64, shi: []f64, sr: f64, si: f64, tr: f64, ti: f64, pvr: f64, pvi: f64, relstp: f64, omp: f64 }

fn cp_cdivid(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) {
    if br == 0.0f64 && bi == 0.0f64 {
        let inf = 1.0e308f64 * 10.0f64
        ret (inf, inf)
    }
    if math.abs[f64](br) >= math.abs[f64](bi) {
        let r = bi / br
        let d = br + r * bi
        ret ((ar + ai * r) / d, (ai - ar * r) / d)
    }
    let r = br / bi
    let d = bi + r * br
    ret ((ar * r + ai) / d, (ai * r - ar) / d)
}

fn cp_hypot(x: f64, y: f64) -> f64 { ret math.sqrt[f64](x * x + y * y) }

// evaluates p at s by the Horner recurrence, the partial sums in q; returns the value
fn cp_polyev(n: i64, s_r: f64, s_i: f64, p_r: []const f64, p_i: []const f64, q_r: []f64, q_i: []f64) -> (f64, f64) {
    q_r[0usize] = p_r[0usize]
    q_i[0usize] = p_i[0usize]
    var vr = q_r[0usize]
    var vi = q_i[0usize]
    var i = 1i64
    while i < n {
        let t = vr * s_r - vi * s_i + p_r[usize(i)]
        vi = vr * s_i + vi * s_r + p_i[usize(i)]
        q_i[usize(i)] = vi
        vr = t
        q_r[usize(i)] = vr
        i += 1i64
    }
    ret (vr, vi)
}

fn cp_errev(n: i64, qr: []const f64, qi: []const f64, ms: f64, mp: f64, a_re: f64, m_re: f64) -> f64 {
    var e = cp_hypot(qr[0usize], qi[0usize]) * m_re / (a_re + m_re)
    var i = 0i64
    while i < n {
        e = e * ms + cp_hypot(qr[usize(i)], qi[usize(i)])
        i += 1i64
    }
    ret e * (a_re + m_re) - mp * m_re
}

fn cp_cauchy(n: i64, pot: []f64, q: []f64) -> f64 {
    let n1 = n - 1i64
    pot[usize(n1)] = 0.0f64 - pot[usize(n1)]
    var x = math.exp[f64]((math.log[f64](0.0f64 - pot[usize(n1)]) - math.log[f64](pot[0usize])) / f64(n1))
    if pot[usize(n1 - 1i64)] != 0.0f64 {
        let xm = (0.0f64 - pot[usize(n1)]) / pot[usize(n1 - 1i64)]
        if xm < x { x = xm }
    }
    var go = true
    while go {
        let xm = x * 0.1f64
        var f = pot[0usize]
        var i = 1i64
        while i < n {
            f = f * xm + pot[usize(i)]
            i += 1i64
        }
        if f <= 0.0f64 { go = false } else { x = xm }
    }
    var dx = x
    while math.abs[f64](dx / x) > 0.005f64 {
        q[0usize] = pot[0usize]
        var i = 1i64
        while i < n {
            q[usize(i)] = q[usize(i - 1i64)] * x + pot[usize(i)]
            i += 1i64
        }
        let f = q[usize(n1)]
        var delf = q[0usize]
        i = 1i64
        while i < n1 {
            delf = delf * x + q[usize(i)]
            i += 1i64
        }
        dx = f / delf
        x -= dx
    }
    ret x
}

fn cp_scale(n: i64, pot: []const f64, epsv: f64, big: f64, small: f64, base: f64) -> f64 {
    let high = math.sqrt[f64](big)
    let lo = small / epsv
    var max_ = 0.0f64
    var min_ = big
    var i = 0i64
    while i < n {
        let x = pot[usize(i)]
        if x > max_ { max_ = x }
        if x != 0.0f64 && x < min_ { min_ = x }
        i += 1i64
    }
    if min_ < lo || max_ > high {
        let x = lo / min_
        var sc = 0.0f64
        if x <= 1.0f64 {
            sc = 1.0f64 / (math.sqrt[f64](max_) * math.sqrt[f64](min_))
        } else {
            sc = x
            if big / sc > max_ { sc = 1.0f64 }
        }
        let ell = i64(math.log[f64](sc) / math.log[f64](base) + 0.5f64)
        ret math.pow[f64](base, f64(ell))
    }
    ret 1.0f64
}

// t = -p(s) / h(s); returns whether h(s) is essentially zero
fn cp_calct(g: *Cp) -> bool {
    let n = g.nn - 1i64
    let (hvr, hvi) = cp_polyev(n, g.sr, g.si, g.hr, g.hi, g.qhr, g.qhi)
    let h_s_0 = cp_hypot(hvr, hvi) <= 2.220446049250313e-16f64 * 10.0f64 * cp_hypot(g.hr[usize(n - 1i64)], g.hi[usize(n - 1i64)])
    if !h_s_0 {
        let (a1, b1) = cp_cdivid(0.0f64 - g.pvr, 0.0f64 - g.pvi, hvr, hvi)
        g.tr = a1
        g.ti = b1
    } else {
        g.tr = 0.0f64
        g.ti = 0.0f64
    }
    ret h_s_0
}

fn cp_nexth(g: *Cp, h_s_0: bool) {
    let n = g.nn - 1i64
    if !h_s_0 {
        var j = 1i64
        while j < n {
            let t1 = g.qhr[usize(j - 1i64)]
            let t2 = g.qhi[usize(j - 1i64)]
            g.hr[usize(j)] = g.tr * t1 - g.ti * t2 + g.qpr[usize(j)]
            g.hi[usize(j)] = g.tr * t2 + g.ti * t1 + g.qpi[usize(j)]
            j += 1i64
        }
        g.hr[0usize] = g.qpr[0usize]
        g.hi[0usize] = g.qpi[0usize]
    } else {
        var j = 1i64
        while j < n {
            g.hr[usize(j)] = g.qhr[usize(j - 1i64)]
            g.hi[usize(j)] = g.qhi[usize(j - 1i64)]
            j += 1i64
        }
        g.hr[0usize] = 0.0f64
        g.hi[0usize] = 0.0f64
    }
}

fn cp_noshft(g: *Cp, l1: i64) {
    let n = g.nn - 1i64
    let nm1 = n - 1i64
    var i = 0i64
    while i < n {
        let xni = f64(g.nn - i - 1i64)
        g.hr[usize(i)] = xni * g.pr[usize(i)] / f64(n)
        g.hi[usize(i)] = xni * g.pi[usize(i)] / f64(n)
        i += 1i64
    }
    var jj = 1i64
    while jj <= l1 {
        if cp_hypot(g.hr[usize(n - 1i64)], g.hi[usize(n - 1i64)]) <= 2.220446049250313e-16f64 * 10.0f64 * cp_hypot(g.pr[usize(n - 1i64)], g.pi[usize(n - 1i64)]) {
            i = 1i64
            while i <= nm1 {
                let j = g.nn - i
                g.hr[usize(j - 1i64)] = g.hr[usize(j - 2i64)]
                g.hi[usize(j - 1i64)] = g.hi[usize(j - 2i64)]
                i += 1i64
            }
            g.hr[0usize] = 0.0f64
            g.hi[0usize] = 0.0f64
        } else {
            let (a1, b1) = cp_cdivid(0.0f64 - g.pr[usize(g.nn - 1i64)], 0.0f64 - g.pi[usize(g.nn - 1i64)], g.hr[usize(n - 1i64)], g.hi[usize(n - 1i64)])
            g.tr = a1
            g.ti = b1
            i = 1i64
            while i <= nm1 {
                let j = g.nn - i
                let t1 = g.hr[usize(j - 2i64)]
                let t2 = g.hi[usize(j - 2i64)]
                g.hr[usize(j - 1i64)] = g.tr * t1 - g.ti * t2 + g.pr[usize(j - 1i64)]
                g.hi[usize(j - 1i64)] = g.tr * t2 + g.ti * t1 + g.pi[usize(j - 1i64)]
                i += 1i64
            }
            g.hr[0usize] = g.pr[0usize]
            g.hi[0usize] = g.pi[0usize]
        }
        jj += 1i64
    }
}

// the third stage: l3 steps from (zr, zi); returns convergence and the iterate
fn cp_vrshft(g: *Cp, l3: i64, zr0: f64, zi0: f64) -> (bool, f64, f64) {
    var b = false
    g.sr = zr0
    g.si = zi0
    var i = 1i64
    while i <= l3 {
        let (v1, v2) = cp_polyev(g.nn, g.sr, g.si, g.pr, g.pi, g.qpr, g.qpi)
        g.pvr = v1
        g.pvi = v2
        let mp = cp_hypot(g.pvr, g.pvi)
        let ms = cp_hypot(g.sr, g.si)
        if mp <= 20.0f64 * cp_errev(g.nn, g.qpr, g.qpi, ms, mp, 2.220446049250313e-16f64, 2.0f64 * 1.4142135623730951f64 * 2.220446049250313e-16f64) {
            ret (true, g.sr, g.si)
        }
        var skip_omp = false
        if i != 1i64 {
            if !b && mp >= g.omp && g.relstp < 0.05f64 {
                var tp = g.relstp
                b = true
                if g.relstp < 2.220446049250313e-16f64 { tp = 2.220446049250313e-16f64 }
                let r1 = math.sqrt[f64](tp)
                let r2 = g.sr * (r1 + 1.0f64) - g.si * r1
                g.si = g.sr * r1 + g.si * (r1 + 1.0f64)
                g.sr = r2
                let (w1, w2) = cp_polyev(g.nn, g.sr, g.si, g.pr, g.pi, g.qpr, g.qpi)
                g.pvr = w1
                g.pvi = w2
                var j = 1i64
                while j <= 5i64 {
                    let hs = cp_calct(g)
                    cp_nexth(g, hs)
                    j += 1i64
                }
                g.omp = 1.7976931348623157e308f64
                skip_omp = true
            } else {
                if mp * 0.1f64 > g.omp { ret (false, g.sr, g.si) }
            }
        }
        if !skip_omp { g.omp = mp }
        var h_s_0 = cp_calct(g)
        cp_nexth(g, h_s_0)
        h_s_0 = cp_calct(g)
        if !h_s_0 {
            g.relstp = cp_hypot(g.tr, g.ti) / cp_hypot(g.sr, g.si)
            g.sr += g.tr
            g.si += g.ti
        }
        i += 1i64
    }
    ret (false, zr0, zi0)
}

// the second stage: l2 fixed-shift steps with tests; returns convergence and the zero
fn cp_fxshft(g: *Cp, l2: i64) -> (bool, f64, f64) {
    let n = g.nn - 1i64
    let (v1, v2) = cp_polyev(g.nn, g.sr, g.si, g.pr, g.pi, g.qpr, g.qpi)
    g.pvr = v1
    g.pvi = v2
    var test = true
    var pasd = false
    var h_s_0 = cp_calct(g)
    var zr = 0.0f64
    var zi = 0.0f64
    var j = 1i64
    while j <= l2 {
        let otr = g.tr
        let oti = g.ti
        cp_nexth(g, h_s_0)
        h_s_0 = cp_calct(g)
        zr = g.sr + g.tr
        zi = g.si + g.ti
        if !h_s_0 && test && j != l2 {
            if cp_hypot(g.tr - otr, g.ti - oti) >= cp_hypot(zr, zi) * 0.5f64 {
                pasd = false
            } else if !pasd {
                pasd = true
            } else {
                var i = 0i64
                while i < n {
                    g.shr[usize(i)] = g.hr[usize(i)]
                    g.shi[usize(i)] = g.hi[usize(i)]
                    i += 1i64
                }
                let svsr = g.sr
                let svsi = g.si
                let (ok1, z1, z2) = cp_vrshft(g, 10i64, zr, zi)
                if ok1 { ret (true, z1, z2) }
                test = false
                i = 1i64
                while i <= n {
                    g.hr[usize(i - 1i64)] = g.shr[usize(i - 1i64)]
                    g.hi[usize(i - 1i64)] = g.shi[usize(i - 1i64)]
                    i += 1i64
                }
                g.sr = svsr
                g.si = svsi
                let (w1, w2) = cp_polyev(g.nn, g.sr, g.si, g.pr, g.pi, g.qpr, g.qpi)
                g.pvr = w1
                g.pvi = w2
                h_s_0 = cp_calct(g)
            }
        }
        j += 1i64
    }
    let (okf, zf1, zf2) = cp_vrshft(g, 10i64, zr, zi)
    ret (okf, zf1, zf2)
}

// polyroot(z) for the real coefficients z (increasing powers): the complex roots in R's order into re and im (degree entries); returns the degree, or -1 when the finder fails
fn polyroot_c(a: *mem.Arena, z: []const f64, re: []f64, im: []f64) -> i64 {
    var degree = 0i64
    var i = 0usize
    while i < z.len {
        if z[i] != 0.0f64 { degree = i64(i) }
        i += 1usize
    }
    if degree < 1i64 { ret 0i64 }
    let n = degree + 1i64
    let (opr, e1) = mem.alloc[f64](a, usize(n))
    let (opi, e2) = mem.alloc[f64](a, usize(n))
    let (tmp, e3) = mem.alloc[f64](a, usize(10i64 * n))
    if e1 != ok || e2 != ok || e3 != ok { ret 0i64 - 1i64 }
    i = 0usize
    while i < usize(n) {
        opr[usize(degree) - i] = z[i]
        opi[usize(degree) - i] = 0.0f64
        i += 1usize
    }
    var nn = degree
    let d1 = nn - 1i64
    if opr[0usize] == 0.0f64 && opi[0usize] == 0.0f64 { ret 0i64 - 1i64 }
    var dn = 0i64
    while opr[usize(nn)] == 0.0f64 && opi[usize(nn)] == 0.0f64 {
        dn = d1 - nn + 1i64
        re[usize(dn)] = 0.0f64
        im[usize(dn)] = 0.0f64
        nn -= 1i64
    }
    nn += 1i64
    if nn == 1i64 { ret degree }
    let w = usize(nn)
    var g = Cp{ nn: nn, pr: tmp[0usize..w], pi: tmp[w..2usize * w], hr: tmp[2usize * w..3usize * w], hi: tmp[3usize * w..4usize * w], qpr: tmp[4usize * w..5usize * w], qpi: tmp[5usize * w..6usize * w], qhr: tmp[6usize * w..7usize * w], qhi: tmp[7usize * w..8usize * w], shr: tmp[8usize * w..9usize * w], shi: tmp[9usize * w..10usize * w], sr: 0.0f64, si: 0.0f64, tr: 0.0f64, ti: 0.0f64, pvr: 0.0f64, pvi: 0.0f64, relstp: 0.0f64, omp: 0.0f64 }
    i = 0usize
    while i < w {
        g.pr[i] = opr[i]
        g.pi[i] = opi[i]
        g.shr[i] = cp_hypot(g.pr[i], g.pi[i])
        i += 1usize
    }
    let eta = 2.220446049250313e-16f64
    let bnd0 = cp_scale(nn, g.shr, eta, 1.7976931348623157e308f64, 2.2250738585072014e-308f64, 2.0f64)
    if bnd0 != 1.0f64 {
        i = 0usize
        while i < w {
            g.pr[i] *= bnd0
            g.pi[i] *= bnd0
            i += 1usize
        }
    }
    var xx = 0.7071067811865476f64
    var yy = 0.0f64 - xx
    let cosr = 0.0f64 - 0.06975647374412529990f64
    let sinr = 0.99756405025982424767f64
    while g.nn > 2i64 {
        i = 0usize
        while i < usize(g.nn) {
            g.shr[i] = cp_hypot(g.pr[i], g.pi[i])
            i += 1usize
        }
        let bnd = cp_cauchy(g.nn, g.shr, g.shi)
        var found = false
        var zr = 0.0f64
        var zi = 0.0f64
        var i1 = 1i64
        while i1 <= 2i64 && !found {
            cp_noshft(&g, 5i64)
            var i2 = 1i64
            while i2 <= 9i64 && !found {
                let xxx = cosr * xx - sinr * yy
                yy = sinr * xx + cosr * yy
                xx = xxx
                g.sr = bnd * xx
                g.si = bnd * yy
                let (cv, z1, z2) = cp_fxshft(&g, i2 * 10i64)
                if cv {
                    found = true
                    zr = z1
                    zi = z2
                }
                i2 += 1i64
            }
            i1 += 1i64
        }
        if !found { ret 0i64 - 1i64 }
        dn = d1 + 2i64 - g.nn
        re[usize(dn)] = zr
        im[usize(dn)] = zi
        g.nn -= 1i64
        i = 0usize
        while i < usize(g.nn) {
            g.pr[i] = g.qpr[i]
            g.pi[i] = g.qpi[i]
            i += 1usize
        }
    }
    let (fr, fi) = cp_cdivid(0.0f64 - g.pr[1usize], 0.0f64 - g.pi[1usize], g.pr[0usize], g.pi[0usize])
    re[usize(d1)] = fr
    im[usize(d1)] = fi
    ret degree
}
