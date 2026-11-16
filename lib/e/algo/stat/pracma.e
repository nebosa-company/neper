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
