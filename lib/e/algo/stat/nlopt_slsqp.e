// NLOPT_LD_SLSQP of NLopt 2.10.0 (algs/slsqp, Kraft's sequential least-squares programming): the Lawson-Hanson
// NNLS / LDP / LSI / HFTI / LSEI chain, the LSQ subproblem, the BFGS update in LDL' form and the reverse-communication
// driver, ported statement for statement so iterates, evaluation counts and return codes match nloptr.
//
// The Fortran arrays are 1-based; ix1(i) and ix2(i, j, ld) turn a Fortran index into the 0-based slice index.
// Constraints are the equalities h = 0 first, then the inequalities c <= 0, as in nlopt_slsqp.

use e.math
use e.mem
use e.algo.stat.nlopt as nl

fn ix1(i: i64) -> usize { ret usize(i - 1i64) }

fn ix2(i: i64, j: i64, ld: i64) -> usize { ret usize((i - 1i64) + (j - 1i64) * ld) }

fn mn(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}

fn mx(a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}

fn dcopy(n: i64, dx: []const f64, incx: i64, dy: []f64, incy: i64) {
    if n <= 0i64 { ret }
    var i = 0i64
    if incx == 1i64 && incy == 1i64 {
        while i < n {
            dy[usize(i)] = dx[usize(i)]
            i += 1i64
        }
    } else if incx == 0i64 && incy == 1i64 {
        let x = dx[0usize]
        while i < n {
            dy[usize(i)] = x
            i += 1i64
        }
    } else {
        while i < n {
            dy[usize(i * incy)] = dx[usize(i * incx)]
            i += 1i64
        }
    }
}

fn daxpy(n: i64, da: f64, dx: []const f64, incx: i64, dy: []f64, incy: i64) {
    if n <= 0i64 || da == 0.0f64 { ret }
    var i = 0i64
    while i < n {
        dy[usize(i * incy)] += da * dx[usize(i * incx)]
        i += 1i64
    }
}

fn ddot(n: i64, dx: []const f64, incx: i64, dy: []const f64, incy: i64) -> f64 {
    if n <= 0i64 { ret 0.0f64 }
    var s = 0.0f64
    var i = 0i64
    while i < n {
        s += dx[usize(i * incx)] * dy[usize(i * incy)]
        i += 1i64
    }
    ret s
}

fn dnrm2(n: i64, dx: []const f64, incx: i64) -> f64 {
    var xmax = 0.0f64
    var i = 0i64
    while i < n {
        let xabs = math.abs[f64](dx[usize(incx * i)])
        if xmax < xabs { xmax = xabs }
        i += 1i64
    }
    if xmax == 0.0f64 { ret 0.0f64 }
    let scale = 1.0f64 / xmax
    var sum = 0.0f64
    i = 0i64
    while i < n {
        let xs = scale * dx[usize(incx * i)]
        sum += xs * xs
        i += 1i64
    }
    ret xmax * math.sqrt[f64](sum)
}

fn dsrot(n: i64, dx: []f64, incx: i64, dy: []f64, incy: i64, c: f64, s: f64) {
    var i = 0i64
    while i < n {
        let x = dx[usize(incx * i)]
        let y = dy[usize(incy * i)]
        dx[usize(incx * i)] = c * x + s * y
        dy[usize(incy * i)] = c * y - s * x
        i += 1i64
    }
}

fn dsrotg(da: *f64, db: *f64, c: *f64, s: *f64) {
    let absa = math.abs[f64](*da)
    let absb = math.abs[f64](*db)
    var roe = 0.0f64
    var scale = 0.0f64
    if absa > absb {
        roe = *da
        scale = absa
    } else {
        roe = *db
        scale = absb
    }
    if scale != 0.0f64 {
        let iscale = 1.0f64 / scale
        let tmpa = (*da) * iscale
        let tmpb = (*db) * iscale
        var sg = scale
        if roe < 0.0f64 { sg = 0.0f64 - scale }
        let r = sg * math.sqrt[f64]((tmpa * tmpa) + (tmpb * tmpb))
        *c = *da / r
        *s = *db / r
        *da = r
        if *c != 0.0f64 && math.abs[f64](*c) <= *s {
            *db = 1.0f64 / *c
        } else {
            *db = *s
        }
    } else {
        *c = 1.0f64
        *s = 0.0f64
        *da = 0.0f64
        *db = 0.0f64
    }
}

fn dscal(n: i64, alpha: f64, dx: []f64, incx: i64) {
    var i = 0i64
    while i < n {
        dx[usize(i * incx)] *= alpha
        i += 1i64
    }
}

// Householder transformation (Lawson and Hanson); u is the pivot vector with storage increment iue
fn h12(mode: i64, lpivot: i64, l1: i64, m: i64, u: []f64, iue: i64, up: *f64, c: []f64, ice: i64, icv: i64, ncv: i64) {
    if 0i64 >= lpivot || lpivot >= l1 || l1 > m { ret }
    let lp = usize((lpivot - 1i64) * iue)
    var cl = math.abs[f64](u[lp])
    if mode != 2i64 {
        var j = l1
        while j <= m {
            let sm0 = math.abs[f64](u[usize((j - 1i64) * iue)])
            cl = nl.fmax(sm0, cl)
            j += 1i64
        }
        if cl <= 0.0f64 { ret }
        let clinv = 1.0f64 / cl
        var d = u[lp] * clinv
        var sm = d * d
        j = l1
        while j <= m {
            d = u[usize((j - 1i64) * iue)] * clinv
            sm += d * d
            j += 1i64
        }
        cl *= math.sqrt[f64](sm)
        if u[lp] > 0.0f64 { cl = 0.0f64 - cl }
        *up = u[lp] - cl
        u[lp] = cl
    } else {
        if cl <= 0.0f64 { ret }
    }
    if ncv <= 0i64 { ret }
    var b = *up * u[lp]
    if b >= 0.0f64 { ret }
    b = 1.0f64 / b
    var i2 = 1i64 - icv + ice * (lpivot - 1i64)
    let incr = ice * (l1 - lpivot)
    var j = 1i64
    while j <= ncv {
        i2 += icv
        var i3 = i2 + incr
        var i4 = i3
        var sm = c[ix1(i2)] * (*up)
        var i = l1
        while i <= m {
            sm += c[ix1(i3)] * u[usize((i - 1i64) * iue)]
            i3 += ice
            i += 1i64
        }
        if sm != 0.0f64 {
            sm *= b
            c[ix1(i2)] += sm * (*up)
            i = l1
            while i <= m {
                c[ix1(i4)] += sm * u[usize((i - 1i64) * iue)]
                i4 += ice
                i += 1i64
            }
        }
        j += 1i64
    }
}

// non-negative least squares; a is m x n (leading dimension mda), b has m entries; mode 1 success, 2 bad dimensions,
// 3 too many iterations
fn nnls(a: []f64, mda: i64, m: i64, n: i64, b: []f64, x: []f64, rnorm: *f64, w: []f64, z: []f64, indx: []i64, mode: *i64) {
    *mode = 2i64
    if m <= 0i64 || n <= 0i64 { ret }
    *mode = 1i64
    var iter = 0i64
    let itmax = n * 3i64
    var i = 1i64
    while i <= n {
        indx[ix1(i)] = i
        i += 1i64
    }
    var iz1 = 1i64
    var iz2 = n
    var nsetp = 0i64
    var npp1 = 1i64
    x[0usize] = 0.0f64
    dcopy(n, x[0usize..1usize], 0i64, x, 1i64)
    var up = 0.0f64
    var cc = 0.0f64
    var ss = 0.0f64
    var j = 0i64
    var jj = 0i64
    var izmax = 0i64
    var iz = 0i64
    var done = false
    while !done {
        // L110
        if iz1 > iz2 || nsetp >= m { break }
        iz = iz1
        while iz <= iz2 {
            j = indx[ix1(iz)]
            w[ix1(j)] = ddot(m - nsetp, a[ix2(npp1, j, mda)..a.len], 1i64, b[ix1(npp1)..b.len], 1i64)
            iz += 1i64
        }
        var accepted = false
        var wzero = false
        while !accepted {
            var wmax = 0.0f64
            iz = iz1
            while iz <= iz2 {
                j = indx[ix1(iz)]
                if w[ix1(j)] > wmax {
                    wmax = w[ix1(j)]
                    izmax = iz
                }
                iz += 1i64
            }
            if wmax <= 0.0f64 {
                wzero = true
                break
            }
            iz = izmax
            j = indx[ix1(iz)]
            let asave = a[ix2(npp1, j, mda)]
            h12(1i64, npp1, npp1 + 1i64, m, a[ix2(1i64, j, mda)..a.len], 1i64, &up, z, 1i64, 1i64, 0i64)
            let unorm = dnrm2(nsetp, a[ix2(1i64, j, mda)..a.len], 1i64)
            var t = 0.01f64 * math.abs[f64](a[ix2(npp1, j, mda)])
            var reject = false
            if (unorm + t) - unorm <= 0.0f64 {
                reject = true
            } else {
                dcopy(m, b, 1i64, z, 1i64)
                h12(2i64, npp1, npp1 + 1i64, m, a[ix2(1i64, j, mda)..a.len], 1i64, &up, z, 1i64, 1i64, 1i64)
                if !(z[ix1(npp1)] / a[ix2(npp1, j, mda)] > 0.0f64) { reject = true }
            }
            if reject {
                a[ix2(npp1, j, mda)] = asave
                w[ix1(j)] = 0.0f64
            } else {
                accepted = true
            }
        }
        if wzero { break }
        // L160
        dcopy(m, z, 1i64, b, 1i64)
        indx[ix1(iz)] = indx[ix1(iz1)]
        indx[ix1(iz1)] = j
        iz1 += 1i64
        nsetp = npp1
        npp1 += 1i64
        var jz = iz1
        while jz <= iz2 {
            jj = indx[ix1(jz)]
            h12(2i64, nsetp, npp1, m, a[ix2(1i64, j, mda)..a.len], 1i64, &up, a[ix2(1i64, jj, mda)..a.len], 1i64, mda, 1i64)
            jz += 1i64
        }
        let k = mn(npp1, mda)
        w[ix1(j)] = 0.0f64
        dcopy(m - nsetp, w[ix1(j)..w.len], 0i64, a[ix2(k, j, mda)..a.len], 1i64)
        // L180
        var inner = true
        while inner {
            var ip = nsetp
            while ip >= 1i64 {
                if ip != nsetp {
                    daxpy(ip, 0.0f64 - z[ix1(ip + 1i64)], a[ix2(1i64, jj, mda)..a.len], 1i64, z, 1i64)
                }
                jj = indx[ix1(ip)]
                z[ix1(ip)] /= a[ix2(ip, jj, mda)]
                ip -= 1i64
            }
            iter += 1i64
            if iter > itmax {
                *mode = 3i64
                done = true
                break
            }
            var alpha = 1.0f64
            jj = 0i64
            ip = 1i64
            while ip <= nsetp {
                if z[ix1(ip)] > 0.0f64 {
                } else {
                    let l = indx[ix1(ip)]
                    let t = (0.0f64 - x[ix1(l)]) / (z[ix1(ip)] - x[ix1(l)])
                    if alpha < t {
                    } else {
                        alpha = t
                        jj = ip
                    }
                }
                ip += 1i64
            }
            ip = 1i64
            while ip <= nsetp {
                let l = indx[ix1(ip)]
                x[ix1(l)] = (1.0f64 - alpha) * x[ix1(l)] + alpha * z[ix1(ip)]
                ip += 1i64
            }
            if jj == 0i64 {
                inner = false
            } else {
                i = indx[ix1(jj)]
                var l250 = true
                while l250 {
                    x[ix1(i)] = 0.0f64
                    jj += 1i64
                    var jx = jj
                    while jx <= nsetp {
                        let ii = indx[ix1(jx)]
                        indx[ix1(jx - 1i64)] = ii
                        dsrotg(&a[ix2(jx - 1i64, ii, mda)], &a[ix2(jx, ii, mda)], &cc, &ss)
                        let t = a[ix2(jx - 1i64, ii, mda)]
                        dsrot(n, a[ix2(jx - 1i64, 1i64, mda)..a.len], mda, a[ix2(jx, 1i64, mda)..a.len], mda, cc, ss)
                        a[ix2(jx - 1i64, ii, mda)] = t
                        a[ix2(jx, ii, mda)] = 0.0f64
                        dsrot(1i64, b[ix1(jx - 1i64)..b.len], 1i64, b[ix1(jx)..b.len], 1i64, cc, ss)
                        jx += 1i64
                    }
                    npp1 = nsetp
                    nsetp -= 1i64
                    iz1 -= 1i64
                    indx[ix1(iz1)] = i
                    if nsetp <= 0i64 {
                        *mode = 3i64
                        done = true
                        l250 = false
                        inner = false
                    } else {
                        var found = false
                        jj = 1i64
                        while jj <= nsetp && !found {
                            i = indx[ix1(jj)]
                            if x[ix1(i)] <= 0.0f64 {
                                found = true
                            } else {
                                jj += 1i64
                            }
                        }
                        if !found {
                            l250 = false
                            dcopy(m, b, 1i64, z, 1i64)
                        }
                    }
                }
            }
        }
    }
    // L280
    let k = mn(npp1, m)
    *rnorm = dnrm2(m - nsetp, b[ix1(k)..b.len], 1i64)
    if npp1 > m {
        w[0usize] = 0.0f64
        dcopy(n, w[0usize..1usize], 0i64, w, 1i64)
    }
}

// least distance programming: min ||x|| s.t. g x >= h (g is m x n, leading dimension mg)
fn ldp(g: []f64, mg: i64, m: i64, n: i64, h: []f64, x: []f64, xnorm: *f64, w: []f64, indx: []i64, mode: *i64) {
    *mode = 2i64
    if n <= 0i64 { ret }
    *mode = 1i64
    x[0usize] = 0.0f64
    dcopy(n, x[0usize..1usize], 0i64, x, 1i64)
    *xnorm = 0.0f64
    if m == 0i64 { ret }
    var iw = 0i64
    var j = 1i64
    while j <= m {
        var i = 1i64
        while i <= n {
            iw += 1i64
            w[ix1(iw)] = g[ix2(j, i, mg)]
            i += 1i64
        }
        iw += 1i64
        w[ix1(iw)] = h[ix1(j)]
        j += 1i64
    }
    let if_ = iw + 1i64
    var i = 1i64
    while i <= n {
        iw += 1i64
        w[ix1(iw)] = 0.0f64
        i += 1i64
    }
    w[ix1(iw + 1i64)] = 1.0f64
    let n1 = n + 1i64
    let iz = iw + 2i64
    let iy = iz + n1
    let iwdual = iy + m
    var rnorm = 0.0f64
    nnls(w, n1, n1, m, w[ix1(if_)..w.len], w[ix1(iy)..w.len], &rnorm, w[ix1(iwdual)..w.len], w[ix1(iz)..w.len], indx, mode)
    if *mode != 1i64 { ret }
    *mode = 4i64
    if rnorm <= 0.0f64 { ret }
    var fac = 1.0f64 - ddot(m, h, 1i64, w[ix1(iy)..w.len], 1i64)
    if (1.0f64 + fac) - 1.0f64 <= 0.0f64 { ret }
    *mode = 1i64
    fac = 1.0f64 / fac
    j = 1i64
    while j <= n {
        x[ix1(j)] = fac * ddot(m, g[ix2(1i64, j, mg)..g.len], 1i64, w[ix1(iy)..w.len], 1i64)
        j += 1i64
    }
    *xnorm = dnrm2(n, x, 1i64)
    w[0usize] = 0.0f64
    dcopy(m, w[0usize..1usize], 0i64, w, 1i64)
    daxpy(m, fac, w[ix1(iy)..w.len], 1i64, w, 1i64)
}

// least squares with inequality constraints: min ||e x - f|| s.t. g x >= h
fn lsi(e: []f64, f: []f64, g: []f64, h: []f64, le: i64, me: i64, lg: i64, mg: i64, n: i64, x: []f64, xnorm: *f64, w: []f64, jw: []i64, mode: *i64) {
    let epmach = 2.22e-16f64
    var t = 0.0f64
    var i = 1i64
    while i <= n {
        let j = mn(i + 1i64, n)
        h12(1i64, i, i + 1i64, me, e[ix2(1i64, i, le)..e.len], 1i64, &t, e[ix2(1i64, j, le)..e.len], 1i64, le, n - i)
        h12(2i64, i, i + 1i64, me, e[ix2(1i64, i, le)..e.len], 1i64, &t, f, 1i64, 1i64, 1i64)
        i += 1i64
    }
    *mode = 5i64
    i = 1i64
    while i <= mg {
        var j = 1i64
        while j <= n {
            if math.abs[f64](e[ix2(j, j, le)]) < epmach { ret }
            g[ix2(i, j, lg)] = (g[ix2(i, j, lg)] - ddot(j - 1i64, g[ix2(i, 1i64, lg)..g.len], lg, e[ix2(1i64, j, le)..e.len], 1i64)) / e[ix2(j, j, le)]
            j += 1i64
        }
        h[ix1(i)] -= ddot(n, g[ix2(i, 1i64, lg)..g.len], lg, f, 1i64)
        i += 1i64
    }
    ldp(g, lg, mg, n, h, x, xnorm, w, jw, mode)
    if *mode != 1i64 { ret }
    daxpy(n, 1.0f64, f, 1i64, x, 1i64)
    i = n
    while i >= 1i64 {
        let j = mn(i + 1i64, n)
        x[ix1(i)] = (x[ix1(i)] - ddot(n - i, e[ix2(i, j, le)..e.len], le, x[ix1(j)..x.len], 1i64)) / e[ix2(i, i, le)]
        i -= 1i64
    }
    let j = mn(n + 1i64, me)
    t = dnrm2(me - n, f[ix1(j)..f.len], 1i64)
    *xnorm = math.sqrt[f64](*xnorm * *xnorm + t * t)
}

// Householder forward triangulation with column pivoting (b is mdb x nb)
fn hfti(a: []f64, mda: i64, m: i64, n: i64, b: []f64, mdb: i64, nb: i64, tau: f64, krank: *i64, rnorm: *f64, h: []f64, g: []f64, ip: []i64) {
    let factor = 0.001f64
    var k = 0i64
    let ldiag = mn(m, n)
    var hmax = 0.0f64
    if ldiag <= 0i64 {
        *krank = k
        ret
    }
    var j = 1i64
    while j <= ldiag {
        var lmax = 0i64
        var skip20 = false
        if j != 1i64 {
            lmax = j
            var l = j
            while l <= n {
                let d = a[ix2(j - 1i64, l, mda)]
                h[ix1(l)] -= d * d
                if h[ix1(l)] > h[ix1(lmax)] { lmax = l }
                l += 1i64
            }
            if (hmax + factor * h[ix1(lmax)]) - hmax > 0.0f64 { skip20 = true }
        }
        if !skip20 {
            lmax = j
            var l = j
            while l <= n {
                h[ix1(l)] = 0.0f64
                var i = j
                while i <= m {
                    let d = a[ix2(i, l, mda)]
                    h[ix1(l)] += d * d
                    i += 1i64
                }
                if h[ix1(l)] > h[ix1(lmax)] { lmax = l }
                l += 1i64
            }
            hmax = h[ix1(lmax)]
        }
        ip[ix1(j)] = lmax
        if ip[ix1(j)] != j {
            var i = 1i64
            while i <= m {
                let tmp = a[ix2(i, j, mda)]
                a[ix2(i, j, mda)] = a[ix2(i, lmax, mda)]
                a[ix2(i, lmax, mda)] = tmp
                i += 1i64
            }
            h[ix1(lmax)] = h[ix1(j)]
        }
        let i = mn(j + 1i64, n)
        h12(1i64, j, j + 1i64, m, a[ix2(1i64, j, mda)..a.len], 1i64, &h[ix1(j)], a[ix2(1i64, i, mda)..a.len], 1i64, mda, n - j)
        h12(2i64, j, j + 1i64, m, a[ix2(1i64, j, mda)..a.len], 1i64, &h[ix1(j)], b, 1i64, mdb, nb)
        j += 1i64
    }
    j = 1i64
    var found = false
    while j <= ldiag && !found {
        if math.abs[f64](a[ix2(j, j, mda)]) <= tau {
            found = true
        } else {
            j += 1i64
        }
    }
    if found {
        k = j - 1i64
    } else {
        k = ldiag
    }
    let kp1 = k + 1i64
    var jb = 1i64
    while jb <= nb {
        if jb == 1i64 { *rnorm = dnrm2(m - k, b[ix2(kp1, jb, mdb)..b.len], 1i64) }
        jb += 1i64
    }
    if k <= 0i64 {
        jb = 1i64
        while jb <= nb {
            var i = 1i64
            while i <= n {
                b[ix2(i, jb, mdb)] = 0.0f64
                i += 1i64
            }
            jb += 1i64
        }
        *krank = k
        ret
    }
    if k != n {
        var i = k
        while i >= 1i64 {
            h12(1i64, i, kp1, n, a[ix2(i, 1i64, mda)..a.len], mda, &g[ix1(i)], a, mda, 1i64, i - 1i64)
            i -= 1i64
        }
    }
    jb = 1i64
    while jb <= nb {
        var i = k
        while i >= 1i64 {
            let jj = mn(i + 1i64, n)
            b[ix2(i, jb, mdb)] = (b[ix2(i, jb, mdb)] - ddot(k - i, a[ix2(i, jj, mda)..a.len], mda, b[ix2(jj, jb, mdb)..b.len], 1i64)) / a[ix2(i, i, mda)]
            i -= 1i64
        }
        if k != n {
            var jx = kp1
            while jx <= n {
                b[ix2(jx, jb, mdb)] = 0.0f64
                jx += 1i64
            }
            i = 1i64
            while i <= k {
                h12(2i64, i, kp1, n, a[ix2(i, 1i64, mda)..a.len], mda, &g[ix1(i)], b[ix2(1i64, jb, mdb)..b.len], 1i64, mdb, 1i64)
                i += 1i64
            }
        }
        var jd = ldiag
        while jd >= 1i64 {
            if ip[ix1(jd)] != jd {
                let l = ip[ix1(jd)]
                let tmp = b[ix2(l, jb, mdb)]
                b[ix2(l, jb, mdb)] = b[ix2(jd, jb, mdb)]
                b[ix2(jd, jb, mdb)] = tmp
            }
            jd -= 1i64
        }
        jb += 1i64
    }
    *krank = k
}

// least squares with equality and inequality constraints
fn lsei(c: []f64, d: []f64, e: []f64, f: []f64, g: []f64, h: []f64, lc: i64, mc: i64, le: i64, me: i64, lg: i64, mg: i64, n: i64, x: []f64, xnrm: *f64, w: []f64, jw: []i64, mode: *i64) {
    let epmach = 2.22e-16f64
    *mode = 2i64
    if mc > n { ret }
    let l = n - mc
    let mc1 = mc + 1i64
    let iw = (l + 1i64) * (mg + 2i64) + (mg * 2i64) + mc
    let ie = iw + mc + 1i64
    let if_ = ie + me * l
    let ig = if_ + me
    var i = 1i64
    while i <= mc {
        let j = mn(i + 1i64, lc)
        h12(1i64, i, i + 1i64, n, c[ix2(i, 1i64, lc)..c.len], lc, &w[ix1(iw + i)], c[ix2(j, 1i64, lc)..c.len], lc, 1i64, mc - i)
        h12(2i64, i, i + 1i64, n, c[ix2(i, 1i64, lc)..c.len], lc, &w[ix1(iw + i)], e, le, 1i64, me)
        h12(2i64, i, i + 1i64, n, c[ix2(i, 1i64, lc)..c.len], lc, &w[ix1(iw + i)], g, lg, 1i64, mg)
        i += 1i64
    }
    *mode = 6i64
    i = 1i64
    while i <= mc {
        if math.abs[f64](c[ix2(i, i, lc)]) < epmach { ret }
        x[ix1(i)] = (d[ix1(i)] - ddot(i - 1i64, c[ix2(i, 1i64, lc)..c.len], lc, x, 1i64)) / c[ix2(i, i, lc)]
        i += 1i64
    }
    *mode = 1i64
    w[ix1(mc1)] = 0.0f64
    dcopy(mg, w[ix1(mc1)..w.len], 0i64, w[ix1(mc1)..w.len], 1i64)
    var toend = false
    if mc != n {
        i = 1i64
        while i <= me {
            w[ix1(if_ - 1i64 + i)] = f[ix1(i)] - ddot(mc, e[ix2(i, 1i64, le)..e.len], le, x, 1i64)
            i += 1i64
        }
        i = 1i64
        while i <= me {
            dcopy(l, e[ix2(i, mc1, le)..e.len], le, w[ix1(ie - 1i64 + i)..w.len], me)
            i += 1i64
        }
        i = 1i64
        while i <= mg {
            dcopy(l, g[ix2(i, mc1, lg)..g.len], lg, w[ix1(ig - 1i64 + i)..w.len], mg)
            i += 1i64
        }
        if mg > 0i64 {
            i = 1i64
            while i <= mg {
                h[ix1(i)] -= ddot(mc, g[ix2(i, 1i64, lg)..g.len], lg, x, 1i64)
                i += 1i64
            }
            lsi(w[ix1(ie)..w.len], w[ix1(if_)..w.len], w[ix1(ig)..w.len], h, me, me, mg, mg, l, x[ix1(mc1)..x.len], xnrm, w[ix1(mc1)..w.len], jw, mode)
            if mc == 0i64 { ret }
            let t = dnrm2(mc, x, 1i64)
            *xnrm = math.sqrt[f64](*xnrm * *xnrm + t * t)
            if *mode != 1i64 { ret }
        } else {
            *mode = 7i64
            let k = mx(le, n)
            var t = math.sqrt[f64](epmach)
            var krank = 0i64
            hfti(w[ix1(ie)..w.len], me, me, l, w[ix1(if_)..w.len], k, 1i64, t, &krank, xnrm, w, w[ix1(l + 1i64)..w.len], jw)
            dcopy(l, w[ix1(if_)..w.len], 1i64, x[ix1(mc1)..x.len], 1i64)
            if krank != l { ret }
            *mode = 1i64
        }
    }
    // L50
    i = 1i64
    while i <= me {
        f[ix1(i)] = ddot(n, e[ix2(i, 1i64, le)..e.len], le, x, 1i64) - f[ix1(i)]
        i += 1i64
    }
    i = 1i64
    while i <= mc {
        d[ix1(i)] = ddot(me, e[ix2(1i64, i, le)..e.len], 1i64, f, 1i64) - ddot(mg, g[ix2(1i64, i, lg)..g.len], 1i64, w[ix1(mc1)..w.len], 1i64)
        i += 1i64
    }
    i = mc
    while i >= 1i64 {
        h12(2i64, i, i + 1i64, n, c[ix2(i, 1i64, lc)..c.len], lc, &w[ix1(iw + i)], x, 1i64, 1i64, 1i64)
        i -= 1i64
    }
    i = mc
    while i >= 1i64 {
        let j = mn(i + 1i64, lc)
        w[ix1(i)] = (d[ix1(i)] - ddot(mc - i, c[ix2(j, i, lc)..c.len], 1i64, w[ix1(j)..w.len], 1i64)) / c[ix2(i, i, lc)]
        i -= 1i64
    }
}

fn is_inf(v: f64) -> bool { ret nl.isinf(v) }

// the quadratic subproblem: min 1/2 x' L D L' x + g' x s.t. the linearised constraints and the bounds xl <= x <= xu;
// nlen is the length of the packed factor l
fn lsq(m: i64, meq: i64, n: i64, nlen: i64, la: i64, l: []f64, g: []f64, a: []f64, b: []f64, xl: []const f64, xu: []const f64, x: []f64, y: []f64, w: []f64, jw: []i64, mode: *i64) {
    let n1 = n + 1i64
    let mineq = m - meq
    let m1 = mineq + n + n
    var n2 = n1 * n / 2i64 + 1i64
    if n2 == nlen {
        n2 = 0i64
    } else {
        n2 = 1i64
    }
    let n3 = n - n2
    var i2 = 1i64
    var i3 = 1i64
    var i4 = 1i64
    let ie = 1i64
    let if_ = n * n + 1i64
    var i = 1i64
    while i <= n3 {
        let i1 = n1 - i
        let diag = math.sqrt[f64](l[ix1(i2)])
        w[ix1(i3)] = 0.0f64
        dcopy(i1, w[ix1(i3)..w.len], 0i64, w[ix1(i3)..w.len], 1i64)
        dcopy(i1 - n2, l[ix1(i2)..l.len], 1i64, w[ix1(i3)..w.len], n)
        dscal(i1 - n2, diag, w[ix1(i3)..w.len], n)
        w[ix1(i3)] = diag
        w[ix1(if_ - 1i64 + i)] = (g[ix1(i)] - ddot(i - 1i64, w[ix1(i4)..w.len], 1i64, w[ix1(if_)..w.len], 1i64)) / diag
        i2 = i2 + i1 - n2
        i3 += n1
        i4 += n
        i += 1i64
    }
    if n2 == 1i64 {
        w[ix1(i3)] = l[ix1(nlen)]
        w[ix1(i4)] = 0.0f64
        dcopy(n3, w[ix1(i4)..w.len], 0i64, w[ix1(i4)..w.len], 1i64)
        w[ix1(if_ - 1i64 + n)] = 0.0f64
    }
    dscal(n, 0.0f64 - 1.0f64, w[ix1(if_)..w.len], 1i64)
    let ic = if_ + n
    let id = ic + meq * n
    if meq > 0i64 {
        i = 1i64
        while i <= meq {
            dcopy(n, a[ix2(i, 1i64, la)..a.len], la, w[ix1(ic - 1i64 + i)..w.len], meq)
            i += 1i64
        }
        dcopy(meq, b, 1i64, w[ix1(id)..w.len], 1i64)
        dscal(meq, 0.0f64 - 1.0f64, w[ix1(id)..w.len], 1i64)
    }
    let ig = id + meq
    if mineq > 0i64 {
        i = 1i64
        while i <= mineq {
            dcopy(n, a[ix2(meq + i, 1i64, la)..a.len], la, w[ix1(ig - 1i64 + i)..w.len], m1)
            i += 1i64
        }
    }
    let ip = ig + mineq
    i = 1i64
    while i <= n {
        w[ix1(ip - 1i64 + i)] = 0.0f64
        dcopy(n, w[ix1(ip - 1i64 + i)..w.len], 0i64, w[ix1(ip - 1i64 + i)..w.len], m1)
        i += 1i64
    }
    let i1 = m1 + 1i64
    i = 1i64
    while i <= n {
        if !is_inf(xl[ix1(i)]) { w[ix1((ip - i1) + i * i1)] = 1.0f64 }
        i += 1i64
    }
    let im = ip + n
    i = 1i64
    while i <= n {
        w[ix1(im - 1i64 + i)] = 0.0f64
        dcopy(n, w[ix1(im - 1i64 + i)..w.len], 0i64, w[ix1(im - 1i64 + i)..w.len], m1)
        i += 1i64
    }
    i = 1i64
    while i <= n {
        if !is_inf(xu[ix1(i)]) { w[ix1((im - i1) + i * i1)] = 0.0f64 - 1.0f64 }
        i += 1i64
    }
    let ih = ig + m1 * n
    if mineq > 0i64 {
        dcopy(mineq, b[ix1(meq + 1i64)..b.len], 1i64, w[ix1(ih)..w.len], 1i64)
        dscal(mineq, 0.0f64 - 1.0f64, w[ix1(ih)..w.len], 1i64)
    }
    let il = ih + mineq
    let iu = il + n
    i = 1i64
    while i <= n {
        if is_inf(xl[ix1(i)]) {
            w[ix1(il - 1i64 + i)] = 0.0f64
        } else {
            w[ix1(il - 1i64 + i)] = xl[ix1(i)]
        }
        if is_inf(xu[ix1(i)]) {
            w[ix1(iu - 1i64 + i)] = 0.0f64
        } else {
            w[ix1(iu - 1i64 + i)] = 0.0f64 - xu[ix1(i)]
        }
        i += 1i64
    }
    let iw = iu + n
    var xnorm = 0.0f64
    lsei(w[ix1(ic)..w.len], w[ix1(id)..w.len], w[ix1(ie)..w.len], w[ix1(if_)..w.len], w[ix1(ig)..w.len], w[ix1(ih)..w.len], mx(1i64, meq), meq, n, n, m1, m1, n, x, &xnorm, w[ix1(iw)..w.len], jw, mode)
    if *mode == 1i64 {
        dcopy(m, w[ix1(iw)..w.len], 1i64, y, 1i64)
        dcopy(n3, w[ix1(iw + m)..w.len], 1i64, y[ix1(m + 1i64)..y.len], 1i64)
        dcopy(n3, w[ix1(iw + m + n)..w.len], 1i64, y[ix1(m + n3 + 1i64)..y.len], 1i64)
        i = 1i64
        while i <= n {
            if x[ix1(i)] < xl[ix1(i)] {
                x[ix1(i)] = xl[ix1(i)]
            } else if x[ix1(i)] > xu[ix1(i)] {
                x[ix1(i)] = xu[ix1(i)]
            }
            i += 1i64
        }
    }
}

// LDL' rank-one update of the packed factor a by sigma z z'
fn ldl(n: i64, a: []f64, z: []f64, sigma: f64, w: []f64) {
    let epmach = 2.22e-16f64
    if sigma == 0.0f64 { ret }
    var ij = 1i64
    var t = 1.0f64 / sigma
    if sigma <= 0.0f64 {
        var i = 1i64
        while i <= n {
            w[ix1(i)] = z[ix1(i)]
            i += 1i64
        }
        i = 1i64
        while i <= n {
            let v = w[ix1(i)]
            t += v * v / a[ix1(ij)]
            var j = i + 1i64
            while j <= n {
                ij += 1i64
                w[ix1(j)] -= v * a[ix1(ij)]
                j += 1i64
            }
            ij += 1i64
            i += 1i64
        }
        if t >= 0.0f64 { t = epmach / sigma }
        i = 1i64
        while i <= n {
            let j = n + 1i64 - i
            ij -= i
            let u = w[ix1(j)]
            w[ix1(j)] = t
            t -= u * u / a[ix1(ij)]
            i += 1i64
        }
    }
    var i = 1i64
    while i <= n {
        let v = z[ix1(i)]
        let delta = v / a[ix1(ij)]
        var tp = 0.0f64
        if sigma < 0.0f64 {
            tp = w[ix1(i)]
        } else {
            tp = t + delta * v
        }
        let alpha = tp / t
        a[ix1(ij)] = alpha * a[ix1(ij)]
        if i == n { ret }
        let beta = delta / tp
        if alpha > 4.0f64 {
            let gamma = t / tp
            var j = i + 1i64
            while j <= n {
                ij += 1i64
                let u = a[ix1(ij)]
                a[ix1(ij)] = gamma * u + beta * z[ix1(j)]
                z[ix1(j)] -= v * u
                j += 1i64
            }
        } else {
            var j = i + 1i64
            while j <= n {
                ij += 1i64
                z[ix1(j)] -= v * a[ix1(ij)]
                a[ix1(ij)] += beta * z[ix1(j)]
                j += 1i64
            }
        }
        ij += 1i64
        t = tp
        i += 1i64
    }
}

type SlState = struct {
    t: f64, f0: f64, h1: f64, h2: f64, h3: f64, h4: f64, n1: i64, n2: i64, n3: i64, t0: f64, gs: f64, tol: f64,
    line: i64, alpha: f64, iexact: i64, incons: i64, ireset: i64, itermx: i64
}

// one reverse-communication step of SLSQP; mode on entry 0 starts, -1 after a line search, else after an evaluation
fn slsqpb(m: i64, meq: i64, la: i64, n: i64, x: []f64, xl: []const f64, xu: []const f64, f: f64, c: []f64, g: []f64, a: []f64, acc: *f64, iter: *i64, mode: *i64, r: []f64, l: []f64, x0: []f64, mu: []f64, s: []f64, u: []f64, v: []f64, w: []f64, iw: []i64, st: *SlState) {
    let alfmin = 0.1f64
    let hun = 100.0f64
    let ten = 10.0f64
    var pc = 0i64
    if *mode == 0i64 - 1i64 {
        pc = 260i64
    } else if *mode == 0i64 {
        pc = 100i64
    } else {
        pc = 220i64
    }
    while true {
        if pc == 100i64 {
            st.itermx = *iter
            if *acc >= 0.0f64 {
                st.iexact = 0i64
            } else {
                st.iexact = 1i64
            }
            *acc = math.abs[f64](*acc)
            st.tol = ten * *acc
            *iter = 0i64
            st.ireset = 0i64
            st.n1 = n + 1i64
            st.n2 = st.n1 * n / 2i64
            st.n3 = st.n2 + 1i64
            s[0usize] = 0.0f64
            mu[0usize] = 0.0f64
            dcopy(n, s[0usize..1usize], 0i64, s, 1i64)
            dcopy(m, mu[0usize..1usize], 0i64, mu, 1i64)
            pc = 110i64
        }
        if pc == 110i64 {
            st.ireset += 1i64
            if st.ireset > 5i64 {
                pc = 255i64
            } else {
                l[0usize] = 0.0f64
                dcopy(st.n2, l[0usize..1usize], 0i64, l, 1i64)
                var j = 1i64
                var i = 1i64
                while i <= n {
                    l[ix1(j)] = 1.0f64
                    j = j + st.n1 - i
                    i += 1i64
                }
                pc = 130i64
            }
        }
        if pc == 130i64 {
            *iter += 1i64
            *mode = 9i64
            if *iter > st.itermx && st.itermx > 0i64 { ret }
            dcopy(n, xl, 1i64, u, 1i64)
            dcopy(n, xu, 1i64, v, 1i64)
            daxpy(n, 0.0f64 - 1.0f64, x, 1i64, u, 1i64)
            daxpy(n, 0.0f64 - 1.0f64, x, 1i64, v, 1i64)
            st.h4 = 1.0f64
            lsq(m, meq, n, st.n3, la, l, g, a, c, u, v, s, r, w, iw, mode)
            if *mode == 6i64 {
                if n == meq { *mode = 4i64 }
            }
            if *mode == 4i64 {
                var j = 1i64
                while j <= m {
                    if j <= meq {
                        a[ix2(j, st.n1, la)] = 0.0f64 - c[ix1(j)]
                    } else {
                        a[ix2(j, st.n1, la)] = nl.fmax(0.0f64 - c[ix1(j)], 0.0f64)
                    }
                    j += 1i64
                }
                s[0usize] = 0.0f64
                dcopy(n, s[0usize..1usize], 0i64, s, 1i64)
                st.h3 = 0.0f64
                g[ix1(st.n1)] = 0.0f64
                l[ix1(st.n3)] = hun
                s[ix1(st.n1)] = 1.0f64
                u[ix1(st.n1)] = 0.0f64
                v[ix1(st.n1)] = 1.0f64
                st.incons = 0i64
                var again = true
                while again {
                    lsq(m, meq, st.n1, st.n3, la, l, g, a, c, u, v, s, r, w, iw, mode)
                    st.h4 = 1.0f64 - s[ix1(st.n1)]
                    if *mode == 4i64 {
                        l[ix1(st.n3)] = ten * l[ix1(st.n3)]
                        st.incons += 1i64
                        if st.incons > 5i64 { ret }
                    } else if *mode != 1i64 {
                        ret
                    } else {
                        again = false
                    }
                }
            } else if *mode != 1i64 {
                ret
            }
            var i = 1i64
            while i <= n {
                v[ix1(i)] = g[ix1(i)] - ddot(m, a[ix2(1i64, i, la)..a.len], 1i64, r, 1i64)
                i += 1i64
            }
            st.f0 = f
            dcopy(n, x, 1i64, x0, 1i64)
            st.gs = ddot(n, g, 1i64, s, 1i64)
            st.h1 = math.abs[f64](st.gs)
            st.h2 = 0.0f64
            var j = 1i64
            while j <= m {
                if j <= meq {
                    st.h3 = c[ix1(j)]
                } else {
                    st.h3 = 0.0f64
                }
                st.h2 += nl.fmax(0.0f64 - c[ix1(j)], st.h3)
                st.h3 = math.abs[f64](r[ix1(j)])
                mu[ix1(j)] = nl.fmax(st.h3, (mu[ix1(j)] + st.h3) / 2.0f64)
                st.h1 += st.h3 * math.abs[f64](c[ix1(j)])
                j += 1i64
            }
            *mode = 0i64
            if st.h1 < *acc && st.h2 < *acc { ret }
            st.h1 = 0.0f64
            j = 1i64
            while j <= m {
                if j <= meq {
                    st.h3 = c[ix1(j)]
                } else {
                    st.h3 = 0.0f64
                }
                st.h1 += mu[ix1(j)] * nl.fmax(0.0f64 - c[ix1(j)], st.h3)
                j += 1i64
            }
            st.t0 = f + st.h1
            st.h3 = st.gs - st.h1 * st.h4
            *mode = 8i64
            if st.h3 >= 0.0f64 {
                pc = 110i64
            } else {
                st.line = 0i64
                st.alpha = 1.0f64
                if st.iexact == 1i64 {
                    pc = 210i64
                } else {
                    pc = 190i64
                }
            }
        }
        if pc == 190i64 {
            st.line += 1i64
            st.h3 = st.alpha * st.h3
            dscal(n, st.alpha, s, 1i64)
            dcopy(n, x0, 1i64, x, 1i64)
            daxpy(n, 1.0f64, s, 1i64, x, 1i64)
            var i = 1i64
            while i <= n {
                if x[ix1(i)] < xl[ix1(i)] {
                    x[ix1(i)] = xl[ix1(i)]
                } else if x[ix1(i)] > xu[ix1(i)] {
                    x[ix1(i)] = xu[ix1(i)]
                }
                i += 1i64
            }
            if st.line == 1i64 {
                *mode = 0i64 - 2i64
            } else {
                *mode = 1i64
            }
            ret
        }
        if pc == 200i64 {
            if nl.isfinite(st.h1) {
                if st.h1 <= st.h3 / ten || st.line > 10i64 {
                    pc = 240i64
                } else {
                    st.alpha = nl.fmax(st.h3 / (2.0f64 * (st.h3 - st.h1)), alfmin)
                    pc = 190i64
                }
            } else {
                st.alpha = nl.fmax(st.alpha * 0.5f64, alfmin)
                pc = 190i64
            }
        }
        if pc == 210i64 {
            *mode = 9i64
            ret
        }
        if pc == 220i64 {
            st.t = f
            var j = 1i64
            while j <= m {
                if j <= meq {
                    st.h1 = c[ix1(j)]
                } else {
                    st.h1 = 0.0f64
                }
                st.t += mu[ix1(j)] * nl.fmax(0.0f64 - c[ix1(j)], st.h1)
                j += 1i64
            }
            st.h1 = st.t - st.t0
            if st.iexact == 0i64 {
                pc = 200i64
            } else {
                pc = 210i64
            }
        }
        if pc == 240i64 {
            st.h3 = 0.0f64
            var j = 1i64
            while j <= m {
                if j <= meq {
                    st.h1 = c[ix1(j)]
                } else {
                    st.h1 = 0.0f64
                }
                st.h3 += nl.fmax(0.0f64 - c[ix1(j)], st.h1)
                j += 1i64
            }
            if (math.abs[f64](f - st.f0) < *acc || dnrm2(n, s, 1i64) < *acc) && st.h3 < *acc {
                *mode = 0i64
            } else {
                *mode = 0i64 - 1i64
            }
            ret
        }
        if pc == 255i64 {
            if (math.abs[f64](f - st.f0) < st.tol || dnrm2(n, s, 1i64) < st.tol) && st.h3 < st.tol {
                *mode = 0i64
            } else {
                *mode = 8i64
            }
            ret
        }
        if pc == 260i64 {
            var i = 1i64
            while i <= n {
                u[ix1(i)] = g[ix1(i)] - ddot(m, a[ix2(1i64, i, la)..a.len], 1i64, r, 1i64) - v[ix1(i)]
                i += 1i64
            }
            var k = 0i64
            i = 1i64
            while i <= n {
                st.h1 = 0.0f64
                k += 1i64
                var j = i + 1i64
                while j <= n {
                    k += 1i64
                    st.h1 += l[ix1(k)] * s[ix1(j)]
                    j += 1i64
                }
                v[ix1(i)] = s[ix1(i)] + st.h1
                i += 1i64
            }
            k = 1i64
            i = 1i64
            while i <= n {
                v[ix1(i)] = l[ix1(k)] * v[ix1(i)]
                k = k + st.n1 - i
                i += 1i64
            }
            i = n
            while i >= 1i64 {
                st.h1 = 0.0f64
                k = i
                var j = 1i64
                while j <= i - 1i64 {
                    st.h1 += l[ix1(k)] * v[ix1(j)]
                    k = k + n - j
                    j += 1i64
                }
                v[ix1(i)] += st.h1
                i -= 1i64
            }
            st.h1 = ddot(n, s, 1i64, u, 1i64)
            st.h2 = ddot(n, s, 1i64, v, 1i64)
            st.h3 = st.h2 * 0.2f64
            if st.h1 < st.h3 {
                st.h4 = (st.h2 - st.h3) / (st.h2 - st.h1)
                st.h1 = st.h3
                dscal(n, st.h4, u, 1i64)
                daxpy(n, 1.0f64 - st.h4, v, 1i64, u, 1i64)
            }
            ldl(n, l, u, 1.0f64 / st.h1, v)
            ldl(n, l, v, (0.0f64 - 1.0f64) / st.h2, u)
            pc = 130i64
        }
    }
}

// NLOPT_LD_SLSQP. The constraints are the equalities h = 0 (me results, tolerance htol) then the inequalities c <= 0
// (mi results, tolerance ctol), each block a vector function with a row-major Jacobian. x is the start and receives
// the best point found; answers (minf, code).
fn slsqp_minimize[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ineq: fn(*C, []const f64, []f64, []f64), eqc: fn(*C, []const f64, []f64, []f64), ctx: *C, mi: usize, ctol: []const f64, me: usize, htol: []const f64, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop) -> (f64, i64) {
    let n = x.len
    let mpi = mi + me
    var mpi1 = mpi
    if mpi1 < 1usize { mpi1 = 1usize }
    let nI = i64(n)
    let n1 = nI + 1i64
    let mI = i64(mpi)
    let meqI = i64(me)
    let mineq = mI - meqI + n1 + n1
    let lenw = (3i64 * n1 + mI) * (n1 + 1i64) + (n1 - meqI + 1i64) * (mineq + 2i64) + 2i64 * mineq + (n1 + mineq) * (n1 - meqI) + 2i64 * meqI + n1 + (nI + 1i64) * nI / 2i64 + 2i64 * mI + 3i64 * nI + 3i64 * n1 + 1i64
    let lenjw = mineq
    var maxcd = mi
    if me > maxcd { maxcd = me }
    let (cgrad, e1) = mem.alloc[f64](ar, mpi1 * (n + 1usize) + 1usize)
    let (c, e2) = mem.alloc[f64](ar, mpi + 1usize)
    let (grad, e3) = mem.alloc[f64](ar, n + 2usize)
    let (xcur0, e4) = mem.alloc[f64](ar, n + 1usize)
    let (xprev0, e5) = mem.alloc[f64](ar, n + 1usize)
    let (cgt, e6) = mem.alloc[f64](ar, maxcd * n + 1usize)
    let (w, e7) = mem.alloc[f64](ar, usize(lenw) + 8usize)
    let (jw, e8) = mem.alloc[i64](ar, usize(lenjw) + 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0.0f64, nl.OUT_OF_MEMORY) }
    let xcur = xcur0[0usize..n]
    let xprev = xprev0[0usize..n]
    var i = 0usize
    while i < n {
        xcur[i] = x[i]
        xprev[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < mpi1 * (n + 1usize) + 1usize {
        cgrad[i] = 0.0f64
        i += 1usize
    }
    var fcur = nl.inf()
    var fprev = nl.inf()
    var minf = nl.inf()
    var feasible = false
    var feasible_cur = false
    var infeasibility = nl.inf()
    var infeasibility_cur = nl.inf()
    var mode = 0i64
    var prev_mode = 0i64
    var acc = 0.0f64
    var iter = 0i64
    var want_grad = true
    var code = nl.SUCCESS
    var st = SlState { t: 0.0f64, f0: 0.0f64, h1: 0.0f64, h2: 0.0f64, h3: 0.0f64, h4: 0.0f64, n1: 0i64, n2: 0i64, n3: 0i64, t0: 0.0f64, gs: 0.0f64, tol: 0.0f64, line: 0i64, alpha: 0.0f64, iexact: 0i64, incons: 0i64, ireset: 0i64, itermx: 0i64 }
    let empty = x[0usize..0usize]
    // workspace layout of slsqp()
    let la = i64(mpi1)
    let im = 1i64
    let il = im + la
    let ix = il + n1 * nI / 2i64 + 1i64
    let ir = ix + nI
    let is_ = ir + nI + nI + la
    let iu = is_ + n1
    let iv = iu + n1
    let iw = iv + n1
    var first = true
    var done = false
    while code == nl.SUCCESS && !done {
        var doeval = false
        var skip = false
        if first {
            first = false
            want_grad = true
            doeval = true
        } else {
            slsqpb(mI, meqI, la, nI, xcur, lb, ub, fcur, c, grad, cgrad, &acc, &iter, &mode, w[ix1(ir)..w.len], w[ix1(il)..w.len], w[ix1(ix)..w.len], w[ix1(im)..w.len], w[ix1(is_)..w.len], w[ix1(iu)..w.len], w[ix1(iv)..w.len], w[ix1(iw)..w.len], jw, &st)
            if mode == 0i64 - 1i64 {
                if prev_mode == 0i64 - 2i64 && !want_grad {
                    skip = true
                } else {
                    want_grad = true
                    doeval = true
                }
            } else if mode == 0i64 - 2i64 {
                want_grad = true
                doeval = true
            } else if mode == 1i64 {
                doeval = true
            } else if mode == 0i64 {
                done = true
            } else if mode == 8i64 {
                code = nl.ROUNDOFF_LIMITED
                if feasible_cur {
                    let sfr = stop.ftol_rel
                    let sxr = stop.xtol_rel
                    let sfa = stop.ftol_abs
                    stop.ftol_rel *= 10.0f64
                    stop.ftol_abs *= 10.0f64
                    stop.xtol_rel *= 10.0f64
                    if nl.stop_ftol(stop, fcur, st.f0) {
                        code = nl.FTOL_REACHED
                    } else if nl.stop_x(stop, xcur, w[ix1(ix)..w.len]) {
                        code = nl.XTOL_REACHED
                    }
                    stop.ftol_rel = sfr
                    stop.ftol_abs = sfa
                    stop.xtol_rel = sxr
                }
                done = true
            } else if mode == 5i64 || mode == 6i64 || mode == 7i64 {
                code = nl.ROUNDOFF_LIMITED
                done = true
            } else if mode == 4i64 || mode == 3i64 || mode == 9i64 {
                code = nl.FAILURE
                done = true
            } else {
                code = nl.INVALID_ARGS
                done = true
            }
        }
        if !done {
            if doeval {
                var gslice = grad[0usize..0usize]
                var cgslice = cgt[0usize..0usize]
                if want_grad {
                    gslice = grad[0usize..n]
                    cgslice = cgt
                }
                feasible_cur = true
                infeasibility_cur = 0.0f64
                fcur = f(ctx, xcur, gslice)
                stop.nevals += 1i64
                if nl.isfinite(fcur) {
                    want_grad = false
                    var ii = 0usize
                    if me > 0usize {
                        eqc(ctx, xcur, c[0usize..me], cgslice)
                        var k = 0usize
                        while k < me {
                            infeasibility_cur = nl.fmax(infeasibility_cur, math.abs[f64](c[ii]))
                            feasible_cur = feasible_cur && math.abs[f64](c[ii]) <= htol[k]
                            if cgslice.len > 0usize {
                                var j = 0usize
                                while j < n {
                                    cgrad[j * mpi1 + ii] = cgt[k * n + j]
                                    j += 1usize
                                }
                            }
                            k += 1usize
                            ii += 1usize
                        }
                    }
                    if mi > 0usize {
                        ineq(ctx, xcur, c[ii..ii + mi], cgslice)
                        var k = 0usize
                        while k < mi {
                            infeasibility_cur = nl.fmax(infeasibility_cur, c[ii])
                            feasible_cur = feasible_cur && c[ii] <= ctol[k]
                            if cgslice.len > 0usize {
                                var j = 0usize
                                while j < n {
                                    cgrad[j * mpi1 + ii] = 0.0f64 - cgt[k * n + j]
                                    j += 1usize
                                }
                            }
                            c[ii] = 0.0f64 - c[ii]
                            k += 1usize
                            ii += 1usize
                        }
                    }
                }
            }
            prev_mode = mode
            if nl.isfinite(fcur) && ((fcur < minf && (feasible_cur || !feasible)) || (!feasible && infeasibility_cur < infeasibility)) {
                minf = fcur
                feasible = feasible_cur
                infeasibility = infeasibility_cur
                i = 0usize
                while i < n {
                    x[i] = xcur[i]
                    i += 1usize
                }
            }
            if mode == 0i64 - 1i64 {
                if !nl.isinf(fprev) && feasible_cur {
                    if nl.stop_ftol(stop, fcur, fprev) {
                        code = nl.FTOL_REACHED
                    } else if nl.stop_x(stop, xcur, xprev) {
                        code = nl.XTOL_REACHED
                    }
                }
                fprev = fcur
                i = 0usize
                while i < n {
                    xprev[i] = xcur[i]
                    i += 1usize
                }
            }
            if nl.stop_evals(stop) {
                code = nl.MAXEVAL_REACHED
            } else if feasible && minf < stop.minf_max {
                code = nl.STOPVAL_REACHED
            }
            if skip { prev_mode = mode }
        }
    }
    if nl.isinf(minf) {
        if nl.isinf(fcur) {
            minf = fprev
            i = 0usize
            while i < n {
                x[i] = xprev[i]
                i += 1usize
            }
        } else {
            minf = fcur
            i = 0usize
            while i < n {
                x[i] = xcur[i]
                i += 1usize
            }
        }
    }
    ret (minf, code)
}
