// R polspline oldlogspline: the censored-data log-spline density estimator of the package's lsdall.c (the engine
// behind oldlogspline()). A cubic spline in the truncated power basis whose tails are linear (left) and constant plus
// linear (right), fitted by Newton-Raphson with Gauss-Legendre integrals over each knot interval and exact tail
// integrals; uncensored, interval, right and left censored observations; knots are placed by the package's "five
// rule", then removed one at a time by the smallest Wald ratio, and the model with the smallest AIC wins. The C
// code keeps its working state in file-level statics: they are the fields of St here, in the same order of
// updates. LINPACK dsifa, dsisl and dsidi come from e.algo.stat.lspec; xssort (SLATEC singleton sort) is below.
//
// oldlogspline_fit takes what the R wrapper hands to .C (it does the same pre-processing: nsample, bounds, user knots,
// the uncensored-only second run). Not here: the printed warnings, plot, roldlogspline.

use e.algo.stat.lspec as lsp
use e.math
use e.mem

const NC: usize = 50usize
const NCI: i64 = 50i64

error Invalid

type St = struct {
    nknots: i64, czheta: f64, itrouble: i64,
    ns: []i64, sample: []f64, bound: []f64, sorc: []i64,
    knots: []f64, coef: []f64, zheta: []f64, xg: []f64, dfunpar: []f64, ng3: []i64, ng4: []i64,
    ww6: []f64, yy6: []f64, ww7: []f64, yy7: []f64,
    info: []f64, suff: []f64, coef2: []f64, cp: []f64, der: []f64, suffc: []f64,
    smp2: []f64, smp3: []f64, iknots: []i64, rknots: []f64, qt0: f64, qt1: f64, il: []i64, iu: []i64,
    z1: []f64, z2: []f64, onerr: i64
}

fn zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zi(a: *mem.Arena, n: usize) -> ([]i64, err) {
    let (v, e) = mem.alloc[i64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0i64
        i += 1usize
    }
    ret (v, ok)
}

fn u(i: i64) -> usize { ret usize(i) }
fn m2(i: i64, j: i64) -> usize { ret u(i) * NC + u(j) }
fn cx(i: i64, k: i64, j: i64) -> usize { ret (u(i) * 4usize + u(k)) * NC + u(j) }
fn q7(i2: i64, i1: i64) -> usize { ret u(i2) * (NC + 1usize) + u(i1) }
fn fabs(x: f64) -> f64 { ret math.abs[f64](x) }
fn pw(x: f64, y: f64) -> f64 { ret math.pow[f64](x, y) }
fn flt(x: i64) -> f64 { ret f64(x) }

// SLATEC ssort of the package (1-based X(i) = x[i - 1]); kk = 2 also permutes y, kk = 1 sorts x alone, increasing
fn ssort(x: []f64, y: []f64, nn: i64, kk: i64, il: []i64, iu: []i64) {
    if nn < 1i64 { ret }
    let wy = kk == 2i64
    var m = 1i64
    var i = 1i64
    var j = nn
    var r = 0.375f64
    var k = 0i64
    var l = 0i64
    var ij = 0i64
    var t = 0.0f64
    var ty = 0.0f64
    var tt = 0.0f64
    var st = 210i64
    var run = true
    while run {
        if st == 210i64 {
            if i == j {
                st = 255i64
            } else {
                if r > 0.5898437f64 {
                    r = r - 0.21875f64
                } else {
                    r = r + 0.0390625f64
                }
                st = 225i64
            }
        }
        if st == 225i64 {
            k = i
            ij = i + i64(f64(j - i) * r)
            t = x[u(ij - 1i64)]
            if wy { ty = y[u(ij - 1i64)] }
            if x[u(i - 1i64)] > t {
                x[u(ij - 1i64)] = x[u(i - 1i64)]
                x[u(i - 1i64)] = t
                t = x[u(ij - 1i64)]
                if wy {
                    y[u(ij - 1i64)] = y[u(i - 1i64)]
                    y[u(i - 1i64)] = ty
                    ty = y[u(ij - 1i64)]
                }
            }
            l = j
            if x[u(j - 1i64)] < t {
                x[u(ij - 1i64)] = x[u(j - 1i64)]
                x[u(j - 1i64)] = t
                t = x[u(ij - 1i64)]
                if wy {
                    y[u(ij - 1i64)] = y[u(j - 1i64)]
                    y[u(j - 1i64)] = ty
                    ty = y[u(ij - 1i64)]
                }
                if x[u(i - 1i64)] > t {
                    x[u(ij - 1i64)] = x[u(i - 1i64)]
                    x[u(i - 1i64)] = t
                    t = x[u(ij - 1i64)]
                    if wy {
                        y[u(ij - 1i64)] = y[u(i - 1i64)]
                        y[u(i - 1i64)] = ty
                        ty = y[u(ij - 1i64)]
                    }
                }
            }
            st = 240i64
        }
        if st == 240i64 {
            l = l - 1i64
            while x[u(l - 1i64)] > t { l = l - 1i64 }
            k = k + 1i64
            while x[u(k - 1i64)] < t { k = k + 1i64 }
            if k <= l {
                tt = x[u(l - 1i64)]
                x[u(l - 1i64)] = x[u(k - 1i64)]
                x[u(k - 1i64)] = tt
                if wy {
                    tt = y[u(l - 1i64)]
                    y[u(l - 1i64)] = y[u(k - 1i64)]
                    y[u(k - 1i64)] = tt
                }
            } else {
                if l - i <= j - k {
                    il[u(m)] = k
                    iu[u(m)] = j
                    j = l
                    m = m + 1i64
                } else {
                    il[u(m)] = i
                    iu[u(m)] = l
                    i = k
                    m = m + 1i64
                }
                st = 260i64
            }
        }
        if st == 255i64 {
            m = m - 1i64
            if m == 0i64 {
                run = false
            } else {
                i = il[u(m)]
                j = iu[u(m)]
                st = 260i64
            }
        }
        if run && st == 260i64 {
            if j - i >= 1i64 {
                st = 225i64
            } else {
                if i == 1i64 {
                    st = 210i64
                } else {
                    i = i - 1i64
                    st = 265i64
                }
            }
        }
        if run && st == 265i64 {
            i = i + 1i64
            if i == j {
                st = 255i64
            } else {
                t = x[u(i)]
                if wy { ty = y[u(i)] }
                if x[u(i - 1i64)] <= t {
                    st = 265i64
                } else {
                    k = i
                    x[u(k)] = x[u(k - 1i64)]
                    if wy { y[u(k)] = y[u(k - 1i64)] }
                    k = k - 1i64
                    while t < x[u(k - 1i64)] {
                        x[u(k)] = x[u(k - 1i64)]
                        if wy { y[u(k)] = y[u(k - 1i64)] }
                        k = k - 1i64
                    }
                    x[u(k)] = t
                    if wy { y[u(k)] = ty }
                    st = 265i64
                }
            }
        }
    }
}

// LINPACK dsidi with job = 100 (inertia only), on the factors of dsifa: the number of non-positive eigenvalues
fn dsidi_nonpos(a: []f64, lda: usize, n: usize, kpvt: []i64) -> i64 {
    var cnt = 0i64
    var t = 0.0f64
    var k = 1usize
    while k <= n {
        var d = a[lsp.aix(lda, k, k)]
        if kpvt[k - 1usize] <= 0i64 {
            if t != 0.0f64 {
                d = t
                t = 0.0f64
            } else {
                t = fabs(a[lsp.aix(lda, k, k + 1usize)])
                d = (d / t) * a[lsp.aix(lda, k + 1usize, k + 1usize)] - t
            }
        }
        if d < 0.0f64 || d == 0.0f64 { cnt += 1i64 }
        k += 1usize
    }
    ret cnt
}

// -Inf: 0, +Inf: 1, NaN: 2, otherwise 3
fn numbertester(aa: f64) -> i64 {
    var i1 = 0i64
    var i2 = 0i64
    var i3 = 0i64
    var i4 = 0i64
    if aa < 2.0f64 { i1 = 1i64 }
    if aa > 0.0f64 { i2 = 1i64 }
    if aa < pw(10.0f64, 200.0f64) { i3 = 1i64 }
    if aa > 0.0f64 - pw(10.0f64, 200.0f64) { i4 = 1i64 }
    if i1 + i2 + i3 + i4 >= 3i64 { ret 3i64 }
    if i2 == 1i64 && i4 == 1i64 { ret 1i64 }
    if i1 == 1i64 && i3 == 1i64 { ret 0i64 }
    ret 2i64
}

// the integral of (a1 x^2 + a2 x + a3) exp(a4 x + a5) over (-inf,t1) (1), (t1,t2) (2), (t1,inf) (3) or (t1,t2) the other way (4)
fn expin(version: i64, t1: f64, t2: f64, a: []f64) -> f64 {
    if a[4usize] != 0.0f64 || version == 1i64 || version == 3i64 {
        let a1 = a[1usize] / a[4usize]
        let b1 = (a[2usize] - 2.0f64 * a1) / a[4usize]
        let c1 = (a[3usize] - b1) / a[4usize]
        var f1 = a1 * t1 * t1 + b1 * t1 + c1
        var i1 = 1.0f64
        if f1 < 0.0f64 { i1 = 0.0f64 - 1.0f64 }
        f1 = math.log[f64](fabs(f1)) + a[4usize] * t1 + a[5usize]
        if f1 > 2000.0f64 { f1 = 2000.0f64 }
        if version == 2i64 || version == 4i64 {
            var f2 = a1 * t2 * t2 + b1 * t2 + c1
            var i2 = 1.0f64
            if f2 < 0.0f64 { i2 = 0.0f64 - 1.0f64 }
            f2 = math.log[f64](fabs(f2)) + a[4usize] * t2 + a[5usize]
            if f2 > 2000.0f64 { f2 = 2000.0f64 }
            if version == 2i64 { ret i1 * math.exp[f64](f1) - i2 * math.exp[f64](f2) }
            ret i2 * math.exp[f64](f2) - i1 * math.exp[f64](f1)
        }
        if version == 1i64 { ret i1 * math.exp[f64](f1) }
        ret (0.0f64 - i1) * math.exp[f64](f1)
    }
    let d = t2 - t1
    let r = (((a[1usize] / 3.0f64) * d + a[2usize] / 2.0f64) * d + a[3usize]) * d * math.exp[f64](a[5usize])
    if version == 4i64 { ret r }
    ret 0.0f64 - r
}

// the same with a polynomial of degree 6 (aa[0..6]) times exp(b1 x + b0)
fn expin2(version: i64, t1: f64, t2: f64, aa: []f64, b1: f64, b0: f64) -> f64 {
    if b1 != 0.0f64 || version == 1i64 || version == 3i64 {
        let u6 = aa[6usize] / b1
        let u5 = (aa[5usize] - 6.0f64 * u6) / b1
        let u4 = (aa[4usize] - 5.0f64 * u5) / b1
        let u3 = (aa[3usize] - 4.0f64 * u4) / b1
        let u2 = (aa[2usize] - 3.0f64 * u3) / b1
        let u1 = (aa[1usize] - 2.0f64 * u2) / b1
        let u0 = (aa[0usize] - u1) / b1
        var f1 = (((((u6 * t1 + u5) * t1 + u4) * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
        var i1 = 1.0f64
        if f1 < 0.0f64 { i1 = 0.0f64 - 1.0f64 }
        f1 = math.log[f64](fabs(f1)) + b1 * t1 + b0
        if f1 > 2000.0f64 { f1 = 2000.0f64 }
        if version == 2i64 || version == 4i64 {
            var f2 = (((((u6 * t2 + u5) * t2 + u4) * t2 + u3) * t2 + u2) * t2 + u1) * t2 + u0
            var i2 = 1.0f64
            if f2 < 0.0f64 { i2 = 0.0f64 - 1.0f64 }
            f2 = math.log[f64](fabs(f2)) + b1 * t2 + b0
            if f2 > 2000.0f64 { f2 = 2000.0f64 }
            if version == 2i64 { ret i1 * math.exp[f64](f1) - i2 * math.exp[f64](f2) }
            ret i2 * math.exp[f64](f2) - i1 * math.exp[f64](f1)
        }
        if version == 1i64 { ret i1 * math.exp[f64](f1) }
        ret (0.0f64 - i1) * math.exp[f64](f1)
    }
    let d = t2 - t1
    var v6 = (((aa[6usize] / 7.0f64 * d + aa[5usize] / 6.0f64) * d + aa[4usize] / 5.0f64) * d + aa[3usize] / 4.0f64) * d
    v6 = (((v6 + aa[2usize] / 3.0f64) * d + aa[1usize] / 2.0f64) * d + aa[0usize]) * d * math.exp[f64](b0)
    if version == 4i64 { ret v6 }
    ret 0.0f64 - v6
}

fn dens33(s: *St, x: f64) -> f64 {
    var j = 0i64
    while j < s.nknots && x > s.knots[u(j)] { j += 1i64 }
    var f = 0.0f64 - math.log[f64](s.czheta)
    var k = j - 3i64
    while k < j + 1i64 {
        if k >= 0i64 && k <= s.nknots {
            f = f + s.zheta[u(k)] * (s.coef[cx(k, 0i64, j)] + x * (s.coef[cx(k, 1i64, j)] + x * (s.coef[cx(k, 2i64, j)] + x * s.coef[cx(k, 3i64, j)])))
        }
        k += 1i64
    }
    ret f
}

fn dens3(s: *St, x: f64) -> f64 { ret math.exp[f64](dens33(s, x)) }

fn fun2(s: *St, x: f64) -> f64 {
    let d = s.dfunpar
    ret math.exp[f64](d[1usize] + x * (d[2usize] + x * (d[3usize] + x * d[4usize])))
}

// the Gauss-Legendre weights and abscissae scaled by r1 (3 points for accuracy 0 and 1, 32 otherwise); returns the count
fn nodes(s: *St, r1: f64, acc: i64, w: []f64, y: []f64) -> usize {
    var n = 32usize
    if acc == 0i64 || acc == 1i64 { n = 3usize }
    var i = 1usize
    while i <= n {
        if n == 3usize {
            w[i] = s.ww6[i] * r1
            y[i] = s.yy6[i] * r1
        } else {
            w[i] = s.ww7[i] * r1
            y[i] = s.yy7[i] * r1
        }
        i += 1usize
    }
    ret n
}

fn numint(s: *St, k1: f64, k2: f64, acc: i64) -> f64 {
    let r1 = (k2 - k1) / 2.0f64
    let r2 = (k2 + k1) / 2.0f64
    var w: [33]f64 = zero
    var y: [33]f64 = zero
    let n = nodes(s, r1, acc, w[0usize..33usize], y[0usize..33usize])
    var sum = 0.0f64
    var i = 1usize
    while i <= n {
        sum = sum + w[i] * (dens3(s, r2 - y[i]) + dens3(s, r2 + y[i]))
        i += 1usize
    }
    ret sum
}

fn numint2(s: *St, k1: f64, k2: f64, acc: i64) -> f64 {
    let r1 = (k2 - k1) / 2.0f64
    let r2 = (k2 + k1) / 2.0f64
    var w: [33]f64 = zero
    var y: [33]f64 = zero
    let n = nodes(s, r1, acc, w[0usize..33usize], y[0usize..33usize])
    var sum = 0.0f64
    var i = 1usize
    while i <= n {
        sum = sum + w[i] * (fun2(s, r2 - y[i]) + fun2(s, r2 + y[i]))
        i += 1usize
    }
    ret sum
}

fn fun48(s: *St, w: f64, x: f64, vv: []f64, ip: i64) {
    var vx = w * dens3(s, x)
    vv[0usize] = vv[0usize] + vx
    var i1 = 1i64
    while i1 < ip {
        vx = vx * x
        vv[u(i1)] = vv[u(i1)] + vx
        i1 += 1i64
    }
}

// vv[0..ip) = the integrals of x^i times the density over (k1, k2)
fn numints(s: *St, vv: []f64, k1: f64, k2: f64, acc: i64, ip: i64) {
    let r1 = (k2 - k1) / 2.0f64
    let r2 = (k2 + k1) / 2.0f64
    var w: [33]f64 = zero
    var y: [33]f64 = zero
    let n = nodes(s, r1, acc, w[0usize..33usize], y[0usize..33usize])
    var i1 = 0i64
    while i1 < ip {
        vv[u(i1)] = 0.0f64
        i1 += 1i64
    }
    var i = 1usize
    while i <= n {
        fun48(s, w[i], r2 - y[i], vv, ip)
        fun48(s, w[i], r2 + y[i], vv, ip)
        i += 1usize
    }
}

// the coefficient matrices of the basis functions (coef2: basis by power basis; s.coef: per interval power coefficients)
fn coeff(s: *St) {
    let c2 = s.coef2
    let kn = s.knots
    let nk = s.nknots
    var i = 0i64
    var j = 0i64
    var k = 0i64
    while i < nk {
        j = 0i64
        while j < nk + 3i64 {
            c2[m2(i, j)] = 0.0f64
            if j < nk + 2i64 {
                k = 0i64
                while k < 4i64 {
                    s.coef[cx(i, k, j)] = 0.0f64
                    k += 1i64
                }
            }
            j += 1i64
        }
        i += 1i64
    }
    c2[m2(0i64, 2i64)] = 1.0f64
    c2[m2(0i64, 3i64)] = (kn[0usize] - kn[2usize]) / (kn[2usize] - kn[1usize])
    c2[m2(0i64, 4i64)] = (kn[1usize] - kn[0usize]) / (kn[2usize] - kn[1usize])
    c2[m2(0i64, 1i64)] = -3.0f64 * (pw(kn[0usize], 2.0f64) + c2[m2(0i64, 3i64)] * pw(kn[1usize], 2.0f64) + c2[m2(0i64, 4i64)] * pw(kn[2usize], 2.0f64))
    c2[m2(0i64, 0i64)] = 0.0f64 - kn[u(nk - 1i64)] * c2[m2(0i64, 1i64)] - c2[m2(0i64, 2i64)] * pw(kn[u(nk - 1i64)] - kn[0usize], 3.0f64) - c2[m2(0i64, 3i64)] * pw(kn[u(nk - 1i64)] - kn[1usize], 3.0f64) - c2[m2(0i64, 4i64)] * pw(kn[u(nk - 1i64)] - kn[2usize], 3.0f64)
    c2[m2(0i64, 5i64)] = 0.0f64
    c2[m2(nk - 2i64, nk - 1i64)] = 1.0f64
    c2[m2(nk - 2i64, nk)] = (kn[u(nk - 3i64)] - kn[u(nk - 1i64)]) / (kn[u(nk - 1i64)] - kn[u(nk - 2i64)])
    c2[m2(nk - 2i64, nk + 1i64)] = (kn[u(nk - 2i64)] - kn[u(nk - 3i64)]) / (kn[u(nk - 1i64)] - kn[u(nk - 2i64)])
    if nk >= 4i64 {
        i = 1i64
        while i < nk - 2i64 {
            c2[m2(i, i + 1i64)] = 1.0f64
            c2[m2(i, i + 4i64)] = (kn[u(i + 1i64)] - kn[u(i - 1i64)]) * (kn[u(i - 1i64)] - kn[u(i)]) / ((kn[u(i + 1i64)] - kn[u(i + 2i64)]) * (kn[u(i)] - kn[u(i + 2i64)]))
            c2[m2(i, i + 3i64)] = (c2[m2(i, i + 4i64)] * (kn[u(i)] - kn[u(i + 2i64)]) + kn[u(i)] - kn[u(i - 1i64)]) / (kn[u(i + 1i64)] - kn[u(i)])
            c2[m2(i, i + 2i64)] = -1.0f64 - c2[m2(i, i + 3i64)] - c2[m2(i, i + 4i64)]
            i += 1i64
        }
        if nk >= 5i64 {
            i = 1i64
            while i < nk - 3i64 {
                var z0 = 0.0f64
                var z1 = 0.0f64
                j = 2i64
                while j < nk + 1i64 {
                    z0 = z0 + c2[m2(i, j)] * pw(kn[u(nk - 1i64)] - kn[u(j - 2i64)], 3.0f64)
                    z1 = z1 + c2[m2(i + 1i64, j)] * pw(kn[u(nk - 1i64)] - kn[u(j - 2i64)], 3.0f64)
                    j += 1i64
                }
                j = 2i64
                while j < nk + 2i64 {
                    c2[m2(i, j)] = c2[m2(i, j)] - (z0 / z1) * c2[m2(i + 1i64, j)]
                    j += 1i64
                }
                i += 1i64
            }
        }
    }
    k = 0i64
    while k < 3i64 {
        s.coef[cx(0i64, 1i64, k)] = c2[m2(0i64, 1i64)]
        s.coef[cx(0i64, 0i64, k)] = c2[m2(0i64, 0i64)]
        k += 1i64
    }
    i = 0i64
    while i < nk - 1i64 {
        j = i
        while j < i + 4i64 {
            k = i + 1i64
            while k < j + 2i64 {
                if j > 0i64 && j < nk + 1i64 && (i != 0i64 || j != 3i64) {
                    if k != 1i64 {
                        let kk = kn[u(k - 2i64)]
                        s.coef[cx(i, 0i64, j)] = s.coef[cx(i, 0i64, j)] - c2[m2(i, k)] * pw(kk, 3.0f64)
                        s.coef[cx(i, 1i64, j)] = s.coef[cx(i, 1i64, j)] + 3.0f64 * c2[m2(i, k)] * pw(kk, 2.0f64)
                        s.coef[cx(i, 2i64, j)] = s.coef[cx(i, 2i64, j)] - 3.0f64 * c2[m2(i, k)] * kk
                        s.coef[cx(i, 3i64, j)] = s.coef[cx(i, 3i64, j)] + c2[m2(i, k)]
                    }
                }
                k += 1i64
            }
            j += 1i64
        }
        i += 1i64
    }
}

// derivatives and crossproducts of the power basis, used by start2 (crossprods cp, derivatives der)
fn start1(s: *St) {
    let cp = s.cp
    let der = s.der
    let sm = s.sample
    let kn = s.knots
    let nk = s.nknots
    let n0 = s.ns[0usize]
    let n1 = s.ns[1usize]
    let n2 = s.ns[2usize]
    let n3 = s.ns[3usize]
    let n4 = s.ns[4usize]
    var i = 0i64
    var j = 0i64
    var k = 0i64
    while i < nk + 1i64 {
        der[u(i)] = 0.0f64
        j = 0i64
        while j < nk + 1i64 {
            cp[m2(i, j)] = 0.0f64
            j += 1i64
        }
        i += 1i64
    }
    cp[m2(0i64, 0i64)] = flt(n0)
    var rr = sm[0usize]
    var rs = sm[0usize]
    i = 0i64
    while i < n0 + n2 {
        if sm[u(i)] > rr { rr = sm[u(i)] }
        i += 1i64
    }
    i = 0i64
    while i < n0 + n2 {
        if sm[u(i)] < rs { rs = sm[u(i)] }
        i += 1i64
    }
    if n1 > 0i64 {
        j = 0i64
        while j < nk {
            i = 0i64
            while i < n1 {
                if sm[u(i)] > kn[u(j)] {
                    der[u(j + 1i64)] = der[u(j + 1i64)] + 6.0f64 * (sm[u(i)] - kn[u(j)])
                    cp[m2(j + 1i64, 0i64)] = cp[m2(j + 1i64, 0i64)] + 3.0f64 * pw(sm[u(i)] - kn[u(j)], 2.0f64)
                    k = 0i64
                    while k <= j {
                        cp[m2(j + 1i64, k + 1i64)] = cp[m2(j + 1i64, k + 1i64)] + 9.0f64 * pw((sm[u(i)] - kn[u(j)]) * (sm[u(i)] - kn[u(k)]), 2.0f64)
                        k += 1i64
                    }
                }
                i += 1i64
            }
            j += 1i64
        }
    }
    if n2 > 0i64 {
        j = 0i64
        while j < nk {
            i = 0i64
            while i < n2 {
                let xs = (sm[u(n1 + 2i64 * i)] + sm[u(n1 + 2i64 * i + 1i64)]) / 2.0f64
                if xs > kn[u(j)] {
                    der[u(j + 1i64)] = der[u(j + 1i64)] + 6.0f64 * (xs - kn[u(j)])
                    cp[m2(j + 1i64, 0i64)] = cp[m2(j + 1i64, 0i64)] + 3.0f64 * pw(xs - kn[u(j)], 2.0f64)
                    k = 0i64
                    while k <= j {
                        cp[m2(j + 1i64, k + 1i64)] = cp[m2(j + 1i64, k + 1i64)] + 9.0f64 * pw((xs - kn[u(j)]) * (xs - kn[u(k)]), 2.0f64)
                        k += 1i64
                    }
                }
                i += 1i64
            }
            j += 1i64
        }
    }
    if n3 > 0i64 {
        j = 0i64
        while j < nk {
            var i2 = 0i64
            while i2 < n3 {
                i = n1 + 2i64 * n2 + i2
                var uuu = 0.0f64
                var i3 = 0i64
                while i3 < 4i64 {
                    uuu = flt(i3) * rr / 4.0f64 + flt(4i64 - i3) * sm[u(i)] / 4.0f64
                    i3 += 1i64
                }
                if uuu > kn[u(j)] {
                    der[u(j + 1i64)] = der[u(j + 1i64)] + 1.5f64 * (uuu - kn[u(j)])
                    cp[m2(j + 1i64, 0i64)] = cp[m2(j + 1i64, 0i64)] + 0.75f64 * pw(uuu - kn[u(j)], 2.0f64)
                    k = 0i64
                    while k <= j {
                        cp[m2(j + 1i64, k + 1i64)] = cp[m2(j + 1i64, k + 1i64)] + 2.25f64 * pw((uuu - kn[u(j)]) * (uuu - kn[u(k)]), 2.0f64)
                        k += 1i64
                    }
                }
                i2 += 1i64
            }
            j += 1i64
        }
    }
    if n4 > 0i64 {
        j = 0i64
        while j < nk {
            var i2 = 0i64
            while i2 < n4 {
                i = n1 + 2i64 * n2 + n3 + i2
                var uuu = 0.0f64
                var i3 = 0i64
                while i3 < 4i64 {
                    uuu = flt(i3) * rs / 4.0f64 + flt(4i64 - i3) * sm[u(i)] / 4.0f64
                    i3 += 1i64
                }
                if uuu > kn[u(j)] {
                    der[u(j + 1i64)] = der[u(j + 1i64)] + 1.5f64 * (uuu - kn[u(j)])
                    cp[m2(j + 1i64, 0i64)] = cp[m2(j + 1i64, 0i64)] + 0.75f64 * pw(uuu - kn[u(j)], 2.0f64)
                    k = 0i64
                    while k <= j {
                        cp[m2(j + 1i64, k + 1i64)] = cp[m2(j + 1i64, k + 1i64)] + 2.25f64 * pw((uuu - kn[u(j)]) * (uuu - kn[u(k)]), 2.0f64)
                        k += 1i64
                    }
                }
                i2 += 1i64
            }
            j += 1i64
        }
    }
    j = 0i64
    while j < nk {
        k = j + 1i64
        while k < nk + 1i64 {
            cp[m2(j, k)] = cp[m2(k, j)]
            k += 1i64
        }
        j += 1i64
    }
}

fn start2(s: *St, nkstart: i64, iremove: i64) {
    let c2 = s.coef2
    let cp = s.cp
    let der = s.der
    let zh = s.zheta
    let nk = s.nknots
    var work: [2500]f64 = zero
    var kpvt: [200]i64 = zero
    let r1 = zh[0usize]
    let r2 = zh[1usize]
    let r3 = zh[u(nk - 2i64)]
    let r4 = zh[u(nk - 1i64)]
    var i = 0i64
    var j = 0i64
    var k = 0i64
    if nk > 4i64 {
        i = 0i64
        while i < nk {
            zh[u(i)] = 0.0f64
            j = 0i64
            while j < nk {
                work[m2(i, j)] = 0.0f64
                j += 1i64
            }
            i += 1i64
        }
        i = 0i64
        while i < nk - 1i64 {
            var j2 = i + 1i64
            while j2 < i + 6i64 && j2 < nk + 2i64 {
                j = j2
                if i == 0i64 && j == 5i64 { j = 1i64 }
                zh[u(i)] = zh[u(i)] - c2[m2(i, j)] * der[u(j - 1i64)]
                k = i
                while k < nk - 1i64 {
                    var l2 = k + 1i64
                    while l2 < k + 6i64 && l2 < nk + 2i64 {
                        var l = l2
                        if k == 0i64 && l == 5i64 { l = 1i64 }
                        work[m2(i, k)] = work[m2(i, k)] + c2[m2(i, j)] * c2[m2(k, l)] * cp[m2(j - 1i64, l - 1i64)]
                        l2 += 1i64
                    }
                    k += 1i64
                }
                j2 += 1i64
            }
            i += 1i64
        }
        i = 1i64
        while i < nk - 1i64 {
            j = 0i64
            while j < i {
                work[m2(i, j)] = work[m2(j, i)]
                j += 1i64
            }
            i += 1i64
        }
        let _ = lsp.dsifa(work[0usize..2500usize], NC, u(nk - 1i64), kpvt[0usize..200usize])
        lsp.dsisl(work[0usize..2500usize], NC, u(nk - 1i64), kpvt[0usize..200usize], zh)
        if nkstart != nk {
            if iremove > 2i64 {
                zh[0usize] = r1
                zh[1usize] = r2
            }
            if iremove < 3i64 {
                zh[0usize] = r1 / 25.0f64
                zh[1usize] = r2 / 25.0f64
            }
            if iremove < nk - 2i64 {
                zh[u(nk - 3i64)] = r3
                zh[u(nk - 2i64)] = r4
            }
            if iremove > nk - 3i64 {
                zh[u(nk - 3i64)] = r3 / 25.0f64
                if nk == 4i64 && iremove == 3i64 { zh[1usize] = (r2 + r3) / 50.0f64 }
                zh[u(nk - 2i64)] = r4 / 25.0f64
            }
        } else {
            var q = 0.0f64
            i = 0i64
            while i < nk - 2i64 {
                q = q + fabs(zh[u(i)])
                i += 1i64
            }
            if q > 10000.0f64 {
                i = 0i64
                while i < nk - 2i64 {
                    zh[u(i)] = zh[u(i)] * 10000.0f64 / q
                    i += 1i64
                }
            }
        }
    } else {
        i = 0i64
        while i < 3i64 {
            zh[u(i)] = 0.0f64
            i += 1i64
        }
    }
}

fn suffstat1(s: *St) {
    let sc = s.suffc
    let sm = s.sample
    let kn = s.knots
    let nk = s.nknots
    let n0 = s.ns[0usize]
    let n1 = s.ns[1usize]
    let n2 = s.ns[2usize]
    var i = 1i64
    while i < nk + 2i64 {
        sc[u(i) * 2usize] = 0.0f64
        sc[u(i) * 2usize + 1usize] = 0.0f64
        i += 1i64
    }
    sc[0usize] = flt(n1) / flt(n0)
    sc[1usize] = flt(n2) / flt(n0)
    var j = 0i64
    while j < n1 {
        sc[2usize] = sc[2usize] + sm[u(j)] / flt(n0)
        i = 2i64
        while i < nk + 2i64 {
            if sm[u(j)] > kn[u(i - 2i64)] {
                sc[u(i) * 2usize] = sc[u(i) * 2usize] + pw(sm[u(j)] - kn[u(i - 2i64)], 3.0f64) / flt(n0)
            }
            i += 1i64
        }
        j += 1i64
    }
    j = 0i64
    while j < n2 {
        let rr = (sm[u(n1 + 2i64 * j)] + sm[u(n1 + 2i64 * j + 1i64)]) / 2.0f64
        sc[3usize] = sc[3usize] + rr / flt(n0)
        i = 2i64
        while i < nk + 2i64 {
            if rr > kn[u(i - 2i64)] {
                sc[u(i) * 2usize + 1usize] = sc[u(i) * 2usize + 1usize] + pw(rr - kn[u(i - 2i64)], 3.0f64) / flt(n0)
            }
            i += 1i64
        }
        j += 1i64
    }
}

fn suffstat2(s: *St) {
    let sc = s.suffc
    let su = s.suff
    let c2 = s.coef2
    let nk = s.nknots
    var i = 0i64
    while i < nk {
        su[u(i) * 2usize] = 0.0f64
        su[u(i) * 2usize + 1usize] = 0.0f64
        var j = 0i64
        while j < nk + 2i64 {
            su[u(i) * 2usize] = su[u(i) * 2usize] + sc[u(j) * 2usize] * c2[m2(i, j)]
            su[u(i) * 2usize + 1usize] = su[u(i) * 2usize + 1usize] + sc[u(j) * 2usize + 1usize] * c2[m2(i, j)]
            j += 1i64
        }
        i += 1i64
    }
}

// --- the tails (exact) and the middle (numerical) parts of the score, the information and C(zheta)

fn tails(s: *St, info: []f64, shift: []f64, z: []f64, what: i64) -> f64 {
    let nk = s.nknots
    let kn = s.knots
    let bd = s.bound
    let cf = s.coef
    var a: [8]f64 = zero
    var cth = 0.0f64
    var i = 0i64
    var j = 0i64
    if what >= 1i64 {
        while i < nk {
            shift[u(i)] = 0.0f64
            if what == 2i64 {
                j = 0i64
                while j < nk {
                    info[m2(i, j)] = 0.0f64
                    j += 1i64
                }
            }
            i += 1i64
        }
    }
    var version = 1i64
    if bd[1usize] > 0.5f64 { version = 2i64 }
    a[1usize] = 0.0f64
    a[4usize] = z[0usize] * cf[cx(0i64, 1i64, 0i64)]
    a[5usize] = z[0usize] * cf[cx(0i64, 0i64, 0i64)]
    if what == 0i64 {
        a[2usize] = 0.0f64
        a[3usize] = 1.0f64
        cth = expin(version, kn[0usize], bd[2usize], a[0usize..8usize])
    } else {
        a[2usize] = cf[cx(0i64, 1i64, 0i64)]
        a[3usize] = cf[cx(0i64, 0i64, 0i64)]
        shift[0usize] = expin(version, kn[0usize], bd[2usize], a[0usize..8usize]) / s.czheta
        if what == 2i64 {
            a[1usize] = cf[cx(0i64, 1i64, 0i64)] * cf[cx(0i64, 1i64, 0i64)]
            a[2usize] = cf[cx(0i64, 1i64, 0i64)] * cf[cx(0i64, 0i64, 0i64)] * 2.0f64
            a[3usize] = cf[cx(0i64, 0i64, 0i64)] * cf[cx(0i64, 0i64, 0i64)]
            info[m2(0i64, 0i64)] = expin(version, kn[0usize], bd[2usize], a[0usize..8usize]) / s.czheta
        }
    }
    version = 3i64
    if bd[3usize] > 0.5f64 { version = 4i64 }
    a[1usize] = 0.0f64
    a[4usize] = z[u(nk - 2i64)] * cf[cx(nk - 2i64, 1i64, nk)]
    if nk > 3i64 {
        a[5usize] = z[u(nk - 2i64)] * cf[cx(nk - 2i64, 0i64, nk)] + z[u(nk - 3i64)] * cf[cx(nk - 3i64, 0i64, nk)]
    } else {
        a[5usize] = z[u(nk - 2i64)] * cf[cx(nk - 2i64, 0i64, nk)]
    }
    if what == 0i64 {
        a[2usize] = 0.0f64
        a[3usize] = 1.0f64
        cth = cth + expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize])
    } else {
        if nk > 3i64 {
            a[2usize] = 0.0f64
            a[3usize] = cf[cx(nk - 3i64, 0i64, nk)]
            shift[u(nk - 3i64)] = expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize]) / s.czheta
        }
        a[2usize] = cf[cx(nk - 2i64, 1i64, nk)]
        a[3usize] = cf[cx(nk - 2i64, 0i64, nk)]
        shift[u(nk - 2i64)] = expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize]) / s.czheta
    }
    if what == 2i64 && nk > 3i64 {
        a[2usize] = 0.0f64
        a[3usize] = cf[cx(nk - 3i64, 0i64, nk)] * cf[cx(nk - 3i64, 0i64, nk)]
        info[m2(nk - 3i64, nk - 3i64)] = expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize]) / s.czheta
        a[2usize] = cf[cx(nk - 3i64, 0i64, nk)] * cf[cx(nk - 2i64, 1i64, nk)]
        a[3usize] = cf[cx(nk - 3i64, 0i64, nk)] * cf[cx(nk - 2i64, 0i64, nk)]
        info[m2(nk - 2i64, nk - 3i64)] = expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize]) / s.czheta
        info[m2(nk - 3i64, nk - 2i64)] = info[m2(nk - 2i64, nk - 3i64)]
    }
    if what == 2i64 {
        a[1usize] = cf[cx(nk - 2i64, 1i64, nk)] * cf[cx(nk - 2i64, 1i64, nk)]
        a[2usize] = cf[cx(nk - 2i64, 0i64, nk)] * cf[cx(nk - 2i64, 1i64, nk)] * 2.0f64
        a[3usize] = cf[cx(nk - 2i64, 0i64, nk)] * cf[cx(nk - 2i64, 0i64, nk)]
        info[m2(nk - 2i64, nk - 2i64)] = expin(version, kn[u(nk - 1i64)], bd[4usize], a[0usize..8usize]) / s.czheta
    }
    ret cth
}

// the three censored-data contributions to score and information; x1/x2 intnum2 (interval), x intnum3 (right), intnum4 (left)
fn cens_update(s: *St, z0: f64, n1: i64, n2: i64, shift: []f64, info: []f64, lim: i64, what: i64) {
    let z1 = s.z1
    let z2 = s.z2
    if z0 > 0.0f64 {
        var i3 = 0i64
        while i3 < lim {
            shift[u(i3)] = shift[u(i3)] - flt(n1) * z1[u(i3)] / (z0 * flt(n2))
            if what == 2i64 {
                var i4 = 0i64
                while i4 < lim {
                    info[m2(i3, i4)] = info[m2(i3, i4)] + flt(n1) * (z1[u(i3)] * z1[u(i4)] / z0 - z2[m2(i3, i4)]) / (flt(n2) * z0)
                    i4 += 1i64
                }
            }
            i3 += 1i64
        }
    }
}

fn zinit(s: *St, what: i64) {
    let nk = s.nknots
    var i1 = 0i64
    while i1 < nk {
        s.z1[u(i1)] = 0.0f64
        if what == 2i64 {
            var i2 = 0i64
            while i2 < nk {
                s.z2[m2(i1, i2)] = 0.0f64
                i2 += 1i64
            }
        }
        i1 += 1i64
    }
}

// adds the contribution of interval i1 (power integrals q) to z1 and z2 (when `use` holds)
fn zadd(s: *St, q: []f64, qstride: bool, y: []f64, i1: i64, what: i64) {
    let nk = s.nknots
    let cf = s.coef
    var i3 = i1 - 3i64
    while i3 <= i1 && i3 < nk - 1i64 {
        if i3 >= 0i64 {
            var i2 = 0i64
            while i2 < 4i64 {
                if qstride {
                    s.z1[u(i3)] = s.z1[u(i3)] + cf[cx(i3, i2, i1)] * q[q7(i2, i1)]
                } else {
                    s.z1[u(i3)] = s.z1[u(i3)] + cf[cx(i3, i2, i1)] * y[u(i2)]
                }
                i2 += 1i64
            }
            if what == 2i64 {
                var i4 = i1 - 3i64
                while i4 <= i1 && i4 < nk - 1i64 {
                    if i4 >= 0i64 {
                        i2 = 0i64
                        while i2 < 4i64 {
                            var i5 = 0i64
                            while i5 < 4i64 {
                                if qstride {
                                    s.z2[m2(i3, i4)] = s.z2[m2(i3, i4)] + cf[cx(i3, i2, i1)] * q[q7(i2 + i5, i1)] * cf[cx(i4, i5, i1)]
                                } else {
                                    s.z2[m2(i3, i4)] = s.z2[m2(i3, i4)] + cf[cx(i3, i2, i1)] * y[u(i2 + i5)] * cf[cx(i4, i5, i1)]
                                }
                                i5 += 1i64
                            }
                            i2 += 1i64
                        }
                    }
                    i4 += 1i64
                }
            }
        }
        i3 += 1i64
    }
}

fn intnum2(s: *St, x1: f64, x2: f64, qol: []f64, shift: []f64, info: []f64, n1: i64, n2: i64, what: i64) {
    let kn = s.knots
    let nk = s.nknots
    let im = 3i64 * what + 1i64
    var y1: [7]f64 = zero
    var y2: [7]f64 = zero
    var jl = 0i64
    while jl < nk && kn[u(jl)] < x1 { jl += 1i64 }
    var jr = 0i64
    while jr < nk && kn[u(jr)] < x2 { jr += 1i64 }
    if jl == jr {
        numints(s, y1[0usize..7usize], x1, x2, 0i64, im)
    } else {
        numints(s, y1[0usize..7usize], x1, kn[u(jl)], 0i64, im)
        numints(s, y2[0usize..7usize], kn[u(jr - 1i64)], x2, 0i64, im)
    }
    var z0 = 0.0f64
    zinit(s, what)
    var i1 = 1i64
    while i1 < nk {
        if i1 > jl && i1 < jr {
            z0 = z0 + qol[q7(0i64, i1)]
            zadd(s, qol, true, y1[0usize..7usize], i1, what)
        } else {
            // C adds nothing for this interval except through the guards above
        }
        i1 += 1i64
    }
    z0 = z0 + y1[0usize] + y2[0usize]
    zadd(s, qol, false, y1[0usize..7usize], jl, what)
    zadd(s, qol, false, y2[0usize..7usize], jr, what)
    cens_update(s, z0, n1, n2, shift, info, nk, what)
}

fn intnum34(s: *St, right: bool, x: f64, qol: []f64, d1: f64, e1: f64, vs: i64, bd: f64, shift: []f64, info: []f64, n1: i64, n2: i64, what: i64) {
    let kn = s.knots
    let nk = s.nknots
    let im = 3i64 * what + 1i64
    var aa: [7]f64 = zero
    var yy: [7]f64 = zero
    var jin = 0i64
    while jin < nk && kn[u(jin)] < x { jin += 1i64 }
    if right {
        if jin < nk {
            numints(s, yy[0usize..7usize], x, kn[u(jin)], 0i64, im)
        } else {
            var i1 = 0i64
            while i1 < 7i64 {
                aa[u(i1)] = 1.0f64
                if i1 != 0i64 { aa[u(i1 - 1i64)] = 0.0f64 }
                yy[u(i1)] = expin2(vs, x, bd, aa[0usize..7usize], d1, e1)
                i1 += 1i64
            }
        }
    } else {
        if jin > 0i64 {
            numints(s, yy[0usize..7usize], kn[u(jin - 1i64)], x, 0i64, im)
        } else {
            var i1 = 0i64
            while i1 < 7i64 {
                aa[u(i1)] = 1.0f64
                if i1 != 0i64 { aa[u(i1 - 1i64)] = 0.0f64 }
                yy[u(i1)] = expin2(vs, x, bd, aa[0usize..7usize], d1, e1)
                i1 += 1i64
            }
        }
    }
    var z0 = 0.0f64
    zinit(s, what)
    var i1 = 1i64
    if !right { i1 = 0i64 }
    var top = nk
    if right { top = nk + 1i64 }
    while i1 < top {
        var inside = i1 > jin
        if !right { inside = i1 < jin }
        if inside {
            z0 = z0 + qol[q7(0i64, i1)]
            zadd(s, qol, true, yy[0usize..7usize], i1, what)
        }
        i1 += 1i64
    }
    z0 = z0 + yy[0usize]
    zadd(s, qol, false, yy[0usize..7usize], jin, what)
    cens_update(s, z0, n1, n2, shift, info, nk - 1i64, what)
}

fn middle(s: *St, info: []f64, shift: []f64, z: []f64, acc: i64, what: i64) -> f64 {
    let nk = s.nknots
    let kn = s.knots
    let bd = s.bound
    let ns = s.ns
    var cth = tails(s, info, shift, z, what)
    var i1 = 1i64
    var i2 = 0i64
    var i3 = 0i64
    if what == 0i64 {
        while i1 < nk {
            i2 = 1i64
            while i2 < 5i64 {
                s.dfunpar[u(i2)] = 0.0f64
                i3 = i1 - 3i64
                while i3 < i1 + 1i64 {
                    if i3 >= 0i64 && i3 < nk - 1i64 {
                        s.dfunpar[u(i2)] = s.dfunpar[u(i2)] + s.coef[cx(i3, i2 - 1i64, i1)] * z[u(i3)]
                    }
                    i3 += 1i64
                }
                i2 += 1i64
            }
            cth = cth + numint2(s, kn[u(i1 - 1i64)], kn[u(i1)], acc)
            i1 += 1i64
        }
        ret cth
    }
    var qol: [357]f64 = zero
    var aa: [7]f64 = zero
    while i1 < nk {
        numints(s, aa[0usize..7usize], kn[u(i1 - 1i64)], kn[u(i1)], acc, 7i64)
        i2 = 0i64
        while i2 < 7i64 {
            qol[q7(i2, i1)] = aa[u(i2)]
            i2 += 1i64
        }
        i2 = i1 - 3i64
        while i2 <= i1 {
            if i2 >= 0i64 && i2 < nk - 1i64 && (i2 != 0i64 || i1 != 3i64) {
                shift[u(i2)] = shift[u(i2)] + qol[q7(0i64, i1)] * s.coef[cx(i2, 0i64, i1)] + qol[q7(1i64, i1)] * s.coef[cx(i2, 1i64, i1)] + qol[q7(2i64, i1)] * s.coef[cx(i2, 2i64, i1)] + qol[q7(3i64, i1)] * s.coef[cx(i2, 3i64, i1)]
                if what == 2i64 {
                    i3 = i1 - 3i64
                    while i3 <= i2 {
                        if i3 >= 0i64 && i3 < nk - 1i64 && (i3 != 0i64 || i1 != 3i64) {
                            var i5 = 0i64
                            while i5 < 4i64 {
                                var i4 = 0i64
                                while i4 < 4i64 {
                                    info[m2(i2, i3)] = info[m2(i2, i3)] + qol[q7(i5 + i4, i1)] * s.coef[cx(i2, i5, i1)] * s.coef[cx(i3, i4, i1)]
                                    i4 += 1i64
                                }
                                i5 += 1i64
                            }
                        }
                        i3 += 1i64
                    }
                }
            }
            i2 += 1i64
        }
        i1 += 1i64
    }
    if what == 2i64 {
        i1 = 0i64
        while i1 < nk - 1i64 {
            i2 = 0i64
            while i2 <= i1 {
                info[m2(i1, i2)] = info[m2(i1, i2)] - shift[u(i1)] * shift[u(i2)]
                info[m2(i2, i1)] = info[m2(i1, i2)]
                i2 += 1i64
            }
            i1 += 1i64
        }
    }
    if ns[0usize] != ns[1usize] {
        var version = 3i64
        if bd[3usize] > 0.5f64 { version = 4i64 }
        var version2 = 1i64
        if bd[1usize] > 0.5f64 { version2 = 2i64 }
        let d1 = z[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 1i64, nk)]
        let d2 = z[0usize] * s.coef[cx(0i64, 1i64, 0i64)]
        let e2 = z[0usize] * s.coef[cx(0i64, 0i64, 0i64)] - math.log[f64](s.czheta)
        var e1 = 0.0f64
        if nk > 3i64 {
            e1 = z[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 0i64, nk)] + z[u(nk - 3i64)] * s.coef[cx(nk - 3i64, 0i64, nk)] - math.log[f64](s.czheta)
        } else {
            e1 = z[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 0i64, nk)] - math.log[f64](s.czheta)
        }
        i2 = 0i64
        while i2 < 7i64 {
            aa[u(i2)] = 0.0f64
            i2 += 1i64
        }
        i2 = 0i64
        while i2 < 7i64 {
            aa[u(i2)] = 1.0f64
            if i2 != 0i64 { aa[u(i2 - 1i64)] = 0.0f64 }
            qol[q7(i2, nk)] = expin2(version, kn[u(nk - 1i64)], bd[4usize], aa[0usize..7usize], d1, e1)
            i2 += 1i64
        }
        i2 = 0i64
        while i2 < 7i64 {
            aa[u(i2)] = 0.0f64
            i2 += 1i64
        }
        i2 = 0i64
        while i2 < 7i64 {
            aa[u(i2)] = 1.0f64
            if i2 != 0i64 { aa[u(i2 - 1i64)] = 0.0f64 }
            qol[q7(i2, 0i64)] = expin2(version2, kn[0usize], bd[2usize], aa[0usize..7usize], d2, e2)
            i2 += 1i64
        }
        let o3 = ns[1usize] + 2i64 * ns[2usize]
        if acc != 0i64 {
            if ns[3usize] > 0i64 {
                var k0 = 1i64
                i2 = 0i64
                while i2 < ns[3usize] {
                    if i2 == ns[3usize] - 1i64 || s.sample[u(i2 + o3)] != s.sample[u(i2 + o3 + 1i64)] {
                        intnum34(s, true, s.sample[u(i2 + o3)], qol[0usize..357usize], d1, e1, version, bd[4usize], shift, info, k0, ns[0usize], what)
                        k0 = 0i64
                    }
                    k0 += 1i64
                    i2 += 1i64
                }
            }
            if ns[4usize] > 0i64 {
                var k0 = 1i64
                i2 = 0i64
                while i2 < ns[4usize] {
                    if i2 == ns[4usize] - 1i64 || s.sample[u(i2 + o3 + ns[3usize])] != s.sample[u(i2 + o3 + ns[3usize] + 1i64)] {
                        intnum34(s, false, s.sample[u(i2 + o3 + ns[3usize])], qol[0usize..357usize], d2, e2, version2, bd[2usize], shift, info, k0, ns[0usize], what)
                        k0 = 0i64
                    }
                    k0 += 1i64
                    i2 += 1i64
                }
            }
            if ns[2usize] > 0i64 {
                var k0 = 1i64
                i2 = 0i64
                while i2 < ns[2usize] {
                    i1 = ns[1usize] + 2i64 * i2
                    if i2 == ns[2usize] - 1i64 || s.sample[u(i1)] != s.sample[u(i1 + 2i64)] || s.sample[u(i1 + 1i64)] != s.sample[u(i1 + 3i64)] {
                        intnum2(s, s.sample[u(i1)], s.sample[u(i1 + 1i64)], qol[0usize..357usize], shift, info, k0, ns[0usize], what)
                        k0 = 0i64
                    }
                    k0 += 1i64
                    i2 += 1i64
                }
            }
        } else {
            if ns[3usize] > 0i64 {
                i1 = 0i64
                i2 = 0i64
                while i2 < NCI {
                    if s.ng3[u(i2)] > 0i64 {
                        i1 = i1 + s.ng3[u(i2)]
                        intnum34(s, true, s.xg[u(i2)], qol[0usize..357usize], d1, e1, version, bd[4usize], shift, info, s.ng3[u(i2)], ns[0usize], what)
                        if i1 == ns[3usize] { i2 = NCI + 3i64 }
                    }
                    i2 += 1i64
                }
            }
            if ns[4usize] > 0i64 {
                i1 = 0i64
                i2 = 0i64
                while i2 < NCI {
                    if s.ng4[u(i2)] > 0i64 {
                        i1 = i1 + s.ng4[u(i2)]
                        intnum34(s, false, s.xg[u(i2)], qol[0usize..357usize], d2, e2, version2, bd[2usize], shift, info, s.ng4[u(i2)], ns[0usize], what)
                        if i1 == ns[4usize] { i2 = NCI + 3i64 }
                    }
                    i2 += 1i64
                }
            }
        }
    }
    i1 = 0i64
    while i1 < nk - 1i64 {
        shift[u(i1)] = s.suff[u(i1) * 2usize] - shift[u(i1)]
        i1 += 1i64
    }
    if acc == 0i64 && ns[2usize] > 0i64 {
        i1 = 0i64
        while i1 < nk - 1i64 {
            shift[u(i1)] = s.suff[u(i1) * 2usize + 1usize] + shift[u(i1)]
            i1 += 1i64
        }
    }
    ret s.czheta
}

// --- likelihood, step search, error criterion

fn erroradjust(s: *St, shift: []f64) -> f64 {
    let nk = s.nknots
    var r1 = 0.0f64
    var r2 = 0.0f64
    var i = 0i64
    while i < nk - 1i64 {
        r2 = s.zheta[u(i)] * s.zheta[u(i)]
        if r2 < 0.0000001f64 { r2 = 0.0000001f64 }
        r1 = r1 + shift[u(i)] * shift[u(i)] / r2
        i += 1i64
    }
    if numbertester(r1) != 1i64 {
        r2 = math.sqrt[f64](r1)
    } else {
        r1 = 0.0f64
        i = 0i64
        while i < nk - 1i64 {
            r2 = fabs(s.zheta[u(i)])
            if r2 < 0.00001f64 { r2 = 0.00001f64 }
            r1 = r1 + fabs(shift[u(i)]) / r2
            i += 1i64
        }
        r2 = r1
    }
    i = 0i64
    while i < nk - 1i64 && r1 > 1000.0f64 {
        shift[u(i)] = shift[u(i)] * 3.0f64 / r2
        i += 1i64
    }
    ret r1
}

fn error2(s: *St, shift: []f64, rvr: []f64) -> f64 {
    var r = 0.0f64
    var i = 0i64
    while i < s.nknots - 1i64 {
        r = r + shift[u(i)] * rvr[u(i)] / 2.0f64
        i += 1i64
    }
    var j = -1i64
    if r >= 0.0f64 { j += 1i64 }
    if numbertester(r) == 1i64 { j = j - 2i64 }
    if j < 0i64 { r = 1000.0f64 }
    ret r
}

fn likeli(s: *St, cand: []f64, acc: i64) -> f64 {
    let nk = s.nknots
    let kn = s.knots
    let ns = s.ns
    let sm = s.sample
    let bd = s.bound
    let zh = s.zheta
    let r0 = math.exp[f64](0.0f64 - 740.0f64)
    var r3: [51]f64 = zero
    var aa: [8]f64 = zero
    var bb: [8]f64 = zero
    var i1 = 0i64
    var i2 = 0i64
    var i3 = 0i64
    var i4 = 0i64
    var r1 = 0.0f64
    while i1 < nk - 1i64 {
        r1 = zh[u(i1)]
        zh[u(i1)] = cand[u(i1)]
        cand[u(i1)] = r1
        i1 += 1i64
    }
    var likl = 0.0f64
    i1 = 0i64
    while i1 < ns[1usize] {
        likl = likl + dens33(s, sm[u(i1)])
        i1 += 1i64
    }
    var iv = 3i64
    if bd[3usize] > 0.5f64 { iv = 4i64 }
    var iw = 1i64
    if bd[1usize] > 0.5f64 { iw = 2i64 }
    aa[1usize] = 0.0f64
    aa[2usize] = 0.0f64
    aa[3usize] = 1.0f64
    aa[4usize] = zh[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 1i64, nk)]
    aa[5usize] = zh[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 0i64, nk)] + zh[u(nk - 3i64)] * s.coef[cx(nk - 3i64, 0i64, nk)] - math.log[f64](s.czheta)
    if nk < 4i64 {
        aa[5usize] = zh[u(nk - 2i64)] * s.coef[cx(nk - 2i64, 0i64, nk)] - math.log[f64](s.czheta)
    }
    r3[u(nk)] = expin(iv, kn[u(nk - 1i64)], bd[4usize], aa[0usize..8usize])
    bb[1usize] = 0.0f64
    bb[2usize] = 0.0f64
    bb[3usize] = 1.0f64
    bb[4usize] = zh[0usize] * s.coef[cx(0i64, 1i64, 0i64)]
    bb[5usize] = zh[0usize] * s.coef[cx(0i64, 0i64, 0i64)] - math.log[f64](s.czheta)
    r3[0usize] = expin(iw, kn[0usize], bd[2usize], bb[0usize..8usize])
    i1 = 1i64
    while i1 < nk {
        r3[u(i1)] = numint(s, kn[u(i1 - 1i64)], kn[u(i1)], acc)
        i1 += 1i64
    }
    if acc != 0i64 {
        i1 = 0i64
        while i1 < ns[2usize] {
            i2 = i1 * 2i64 + ns[1usize]
            i3 = 0i64
            while i3 < nk && kn[u(i3)] < sm[u(i2)] { i3 += 1i64 }
            i4 = 0i64
            while i4 < nk && kn[u(i4)] < sm[u(i2 + 1i64)] { i4 += 1i64 }
            if i3 == i4 {
                likl = likl + math.log[f64](numint(s, sm[u(i2)], sm[u(i2 + 1i64)], 0i64))
            } else {
                r1 = numint(s, sm[u(i2)], kn[u(i3)], 0i64)
                r1 = r1 + numint(s, kn[u(i4 - 1i64)], sm[u(i2 + 1i64)], 0i64)
                i3 = i3 + 1i64
                while i3 < i4 {
                    r1 = r1 + r3[u(i3)]
                    i3 += 1i64
                }
                likl = likl + math.log[f64](r1)
            }
            i1 += 1i64
        }
        i1 = 0i64
        while i1 < ns[3usize] {
            i2 = i1 + ns[1usize] + 2i64 * ns[2usize]
            i3 = 0i64
            while i3 < nk && kn[u(i3)] < sm[u(i2)] { i3 += 1i64 }
            if i3 < nk {
                r1 = numint(s, sm[u(i2)], kn[u(i3)], 0i64)
                i3 = i3 + 1i64
                while i3 <= nk {
                    r1 = r1 + r3[u(i3)]
                    i3 += 1i64
                }
                if r1 > r0 {
                    likl = likl + math.log[f64](r1)
                } else {
                    likl = likl - 1000.0f64
                }
            } else {
                likl = likl + math.log[f64](expin(iv, sm[u(i2)], bd[4usize], aa[0usize..8usize]))
            }
            i1 += 1i64
        }
        i1 = 0i64
        while i1 < ns[4usize] {
            i2 = i1 + ns[1usize] + 2i64 * ns[2usize] + ns[3usize]
            i3 = 0i64
            while i3 < nk && kn[u(i3)] < sm[u(i2)] { i3 += 1i64 }
            if i3 > 0i64 {
                r1 = numint(s, kn[u(i3 - 1i64)], sm[u(i2)], 0i64)
                i4 = 0i64
                while i4 < i3 {
                    r1 = r1 + r3[u(i4)]
                    i4 += 1i64
                }
                if r1 > r0 {
                    likl = likl + math.log[f64](r1)
                } else {
                    likl = likl - 1000.0f64
                }
            } else {
                likl = likl + math.log[f64](expin(iw, sm[u(i2)], bd[2usize], bb[0usize..8usize]))
            }
            i1 += 1i64
        }
    } else {
        if ns[3usize] > 0i64 {
            i1 = 0i64
            i2 = 0i64
            while i2 < NCI {
                if s.ng3[u(i2)] > 0i64 {
                    i1 = i1 + s.ng3[u(i2)]
                    i3 = 0i64
                    while i3 < nk && kn[u(i3)] < s.xg[u(i2)] { i3 += 1i64 }
                    if i3 < nk {
                        r1 = numint(s, s.xg[u(i2)], kn[u(i3)], 0i64)
                        i3 = i3 + 1i64
                        while i3 <= nk {
                            r1 = r1 + r3[u(i3)]
                            i3 += 1i64
                        }
                        if r1 > r0 {
                            likl = likl + flt(s.ng3[u(i2)]) * math.log[f64](r1)
                        } else {
                            likl = likl - 1000.0f64 * flt(s.ng3[u(i2)])
                        }
                    } else {
                        likl = likl + flt(s.ng3[u(i2)]) * math.log[f64](expin(iv, s.xg[u(i2)], bd[4usize], aa[0usize..8usize]))
                    }
                    if i1 == ns[3usize] { i2 = NCI + 3i64 }
                }
                i2 += 1i64
            }
        }
        if ns[4usize] > 0i64 {
            i1 = 0i64
            i2 = 0i64
            while i2 < NCI {
                if s.ng4[u(i2)] > 0i64 {
                    i1 = i1 + s.ng4[u(i2)]
                    i3 = 0i64
                    while i3 < nk && kn[u(i3)] < s.xg[u(i2)] { i3 += 1i64 }
                    if i3 > 0i64 {
                        r1 = numint(s, kn[u(i3 - 1i64)], s.xg[u(i2)], 0i64)
                        i4 = 0i64
                        while i4 < i3 {
                            r1 = r1 + r3[u(i4)]
                            i4 += 1i64
                        }
                        if r1 > r0 {
                            likl = likl + flt(s.ng4[u(i2)]) * math.log[f64](r1)
                        } else {
                            likl = likl - 1000.0f64 * flt(s.ng4[u(i2)])
                        }
                    } else {
                        likl = likl + flt(s.ng4[u(i2)]) * math.log[f64](expin(iw, s.xg[u(i2)], bd[2usize], bb[0usize..8usize]))
                    }
                    if i1 == ns[4usize] { i2 = NCI + 3i64 }
                }
                i2 += 1i64
            }
        }
        if ns[2usize] > 0i64 {
            i1 = 0i64
            while i1 < ns[2usize] {
                r1 = (sm[u(ns[1usize] + i1 * 2i64)] + sm[u(ns[1usize] + i1 * 2i64 + 1i64)]) / 2.0f64
                likl = likl + dens33(s, r1)
                i1 += 1i64
            }
        }
    }
    i1 = 0i64
    while i1 < nk - 1i64 {
        r1 = zh[u(i1)]
        zh[u(i1)] = cand[u(i1)]
        cand[u(i1)] = r1
        i1 += 1i64
    }
    ret likl / flt(ns[0usize])
}

// the loglikelihood in zheta + 2^rt shift; s.onerr = 1 when czheta is out of range
fn onesearch(s: *St, rt0: f64, shift: []f64, acc: i64) -> f64 {
    var rv: [50]f64 = zero
    s.onerr = 0i64
    let rt = pw(2.0f64, rt0)
    var i = 0i64
    while i < s.nknots - 1i64 {
        rv[u(i)] = s.zheta[u(i)] + rt * shift[u(i)]
        i += 1i64
    }
    s.czheta = middle(s, s.info, shift, rv[0usize..50usize], acc, 0i64)
    if s.czheta <= 0.0f64 {
        s.onerr = 1i64
        ret 0.0f64
    }
    if math.log[f64](s.czheta) > 200.0f64 {
        s.onerr = 1i64
        ret 0.0f64
    }
    var j = 0i64
    if s.czheta > 0.0f64 - 5.0f64 { j += 1i64 }
    if s.czheta < 5.0f64 { j += 1i64 }
    if j == 0i64 {
        s.onerr = 1i64
        ret 0.0f64
    }
    ret likeli(s, rv[0usize..50usize], acc)
}

fn linsearch(s: *St, shift: []f64, oldll: f64, acc: i64) -> f64 {
    let nk = s.nknots
    let zh = s.zheta
    var rl = 1000.0f64
    var rr = 1000.0f64
    if s.bound[1usize] < 0.5f64 && shift[0usize] * zh[0usize] < 0.0f64 { rl = (0.0f64 - zh[0usize]) / shift[0usize] }
    if s.bound[3usize] < 0.5f64 && shift[u(nk - 2i64)] * zh[u(nk - 2i64)] < 0.0f64 { rr = (0.0f64 - zh[u(nk - 2i64)]) / shift[u(nk - 2i64)] }
    if rl < rr { rr = rl }
    var maxll = oldll
    var maxrt = 0.0f64 - 100.0f64
    var rt = 0.0f64
    if rr > 0.5f64 {
        rt = 0.0f64 - 2.0f64
    } else {
        rt = math.floor[f64](math.log[f64](rr) / math.log[f64](2.0f64)) - 2.0f64
    }
    var ll = onesearch(s, rt, shift, acc)
    if s.onerr == 0i64 && ll > maxll {
        var more = true
        while more {
            maxrt = rt
            maxll = ll
            rt = rt + 2.0f64
            ll = onesearch(s, rt, shift, acc)
            more = rt < 8.5f64 && ll > maxll && s.onerr == 0i64
        }
    } else {
        var more = true
        while more {
            rt = rt - 2.0f64
            ll = onesearch(s, rt, shift, acc)
            more = rt > 0.0f64 - 14.1f64 && (ll < maxll || s.onerr == 1i64)
        }
    }
    if s.onerr == 0i64 && ll > maxll {
        maxrt = rt
        maxll = ll
    }
    if maxrt > 0.0f64 - 50.0f64 {
        rt = maxrt + 1.0f64
        ll = onesearch(s, rt, shift, acc)
        if s.onerr == 0i64 && ll > maxll {
            maxrt = rt
            maxll = ll
        }
        maxrt = pw(2.0f64, maxrt)
        var i = 0i64
        while i < nk - 1i64 {
            zh[u(i)] = zh[u(i)] + maxrt * shift[u(i)]
            i += 1i64
        }
    }
    ret maxll
}

fn setbounds(s: *St, cb: []f64) {
    let bd = s.bound
    let kn = s.knots
    let zh = s.zheta
    let nk = s.nknots
    let ns = s.ns
    cb[2usize] = bd[2usize]
    cb[1usize] = bd[1usize]
    cb[5usize] = 1.0f64
    if ns[3usize] * 3i64 > ns[1usize] { cb[5usize] = 0.5f64 }
    bd[2usize] = cb[5usize] * (kn[0usize] - kn[1usize]) + kn[0usize]
    if zh[0usize] < 0.0f64 && cb[1usize] < 0.5f64 && ns[0usize] == ns[1usize] { cb[5usize] = 0.0f64 - 1.0f64 }
    if cb[1usize] < 0.5f64 && (zh[0usize] >= 0.0f64 || ns[0usize] != ns[1usize]) { bd[1usize] = 1.0f64 }
    if cb[1usize] > 0.5f64 { bd[1usize] = 2.0f64 }
    if cb[1usize] > 0.5f64 && zh[1usize] >= 0.0f64 && bd[2usize] >= cb[2usize] { bd[1usize] = 1.0f64 }
    if cb[1usize] > 0.5f64 && (zh[0usize] < 0.0f64 || (zh[0usize] >= 0.0f64 && bd[2usize] < cb[2usize])) { bd[2usize] = cb[2usize] }
    cb[4usize] = bd[4usize]
    cb[3usize] = bd[3usize]
    cb[6usize] = 1.0f64
    if ns[4usize] * 3i64 > ns[1usize] { cb[6usize] = 0.5f64 }
    bd[4usize] = cb[6usize] * (kn[u(nk - 1i64)] - kn[u(nk - 2i64)]) + kn[u(nk - 1i64)]
    if zh[u(nk - 2i64)] < 0.0f64 && cb[3usize] < 0.5f64 && ns[0usize] == ns[1usize] { cb[6usize] = 0.0f64 - cb[6usize] }
    if cb[3usize] < 0.5f64 && (zh[u(nk - 2i64)] >= 0.0f64 || ns[0usize] != ns[1usize]) { bd[3usize] = 1.0f64 }
    if cb[3usize] > 0.5f64 { bd[3usize] = 2.0f64 }
    if cb[3usize] > 0.5f64 && zh[u(nk - 2i64)] >= 0.0f64 && cb[4usize] >= bd[4usize] { bd[3usize] = 1.0f64 }
    if cb[3usize] > 0.5f64 && (zh[u(nk - 2i64)] < 0.0f64 || (zh[u(nk - 2i64)] >= 0.0f64 && bd[4usize] > cb[4usize])) { bd[4usize] = cb[4usize] }
}

fn restore_bounds(s: *St, cb: []f64) {
    var i = 1usize
    while i < 5usize {
        s.bound[i] = cb[i]
        i += 1usize
    }
}

fn okc(c: f64) -> bool {
    var f = 0i64
    if c > 0.0f64 { f += 1i64 }
    if c < 2.0f64 { f += 1i64 }
    if numbertester(c) == 1i64 { f = f - 4i64 }
    ret f > 0i64
}

// the Newton-Raphson iteration of the C code for the present knots; returns the loglikelihood per observation
fn liter(s: *St, acc0: i64) -> f64 {
    let info = s.info
    let ns = s.ns
    let bd = s.bound
    let kn = s.knots
    let zh = s.zheta
    let nk = s.nknots
    var accuracy = acc0
    var counter = 0i64
    var zerror = 0.0f64
    var oldlik = 0.0f64
    var newlik = 0.0f64
    var cbound: [8]f64 = zero
    var shift: [50]f64 = zero
    var candidate: [50]f64 = zero
    var work: [2500]f64 = zero
    var rvr: [100]f64 = zero
    var kpvt: [50]i64 = zero
    var iii1 = 0i64
    var iii3 = 0i64
    var nrc = 0i64
    var nrc2 = 0i64
    var jaja1 = 0i64
    var i7 = 0i64
    var i2 = 0i64
    let one = 0.99999f64
    setbounds(s, cbound[0usize..8usize])
    if accuracy == 0i64 && ns[0usize] == ns[1usize] { accuracy = 1i64 }
    var i1 = 1i64
    while i1 < 500i64 {
        var ithere = 0i64
        if bd[3usize] < 0.5f64 || bd[3usize] > 1.5f64 {
            ithere = 5i64
        } else {
            if bd[4usize] >= 25.0f64 * kn[u(nk - 1i64)] - 24.0f64 * kn[0usize] {
                s.sorc[24usize] = nk
                s.itrouble = 17i64
                restore_bounds(s, cbound[0usize..8usize])
                ret 0.0f64
            }
        }
        if bd[1usize] < 0.5f64 || bd[1usize] > 1.5f64 {
            ithere = ithere + 5i64
        } else {
            if bd[2usize] <= 0.0f64 - 24.0f64 * kn[u(nk - 1i64)] + 25.0f64 * kn[0usize] {
                s.sorc[23usize] = nk
                s.itrouble = 17i64
                restore_bounds(s, cbound[0usize..8usize])
                ret 0.0f64
            }
        }
        if accuracy == 0i64 && i1 == 250i64 {
            accuracy = 1i64
            counter = 0i64
        }
        jaja1 = 0i64
        counter += 1i64
        i7 = 0i64
        var infol = 1usize
        while infol != 0usize {
            if counter == 1i64 {
                var again = true
                while again {
                    s.czheta = middle(s, info, shift[0usize..50usize], zh, accuracy, 0i64)
                    var f = -1i64
                    if s.czheta > 0.0f64 { f += 1i64 }
                    if s.czheta < 2.0f64 { f += 1i64 }
                    if numbertester(s.czheta) == 1i64 { f = f - 4i64 }
                    if f < 0i64 {
                        i2 = 0i64
                        while i2 < nk - 1i64 {
                            zh[u(i2)] = zh[u(i2)] / 10.0f64
                            i2 += 1i64
                        }
                        if i7 > 7i64 && s.itrouble == 0i64 {
                            s.itrouble = 2i64
                            restore_bounds(s, cbound[0usize..8usize])
                            ret 0.0f64
                        }
                        f = 0i64 - 6i64
                        i7 += 1i64
                        if i7 == 200i64 {
                            s.itrouble = 5i64
                            ret 1.0f64
                        }
                    }
                    again = f < 0i64
                }
                newlik = likeli(s, zh, accuracy)
            }
            s.czheta = middle(s, info, shift[0usize..50usize], zh, accuracy, 2i64)
            oldlik = newlik
            i2 = 0i64
            while i2 < nk - 1i64 {
                var i3 = 0i64
                while i3 < nk - 1i64 {
                    work[m2(i2, i3)] = info[m2(i2, i3)]
                    i3 += 1i64
                }
                i2 += 1i64
            }
            infol = lsp.dsifa(work[0usize..2500usize], NC, u(nk - 1i64), kpvt[0usize..50usize])
            if infol != 0usize {
                i2 = 0i64
                while i2 < nk - 1i64 {
                    zh[u(i2)] = zh[u(i2)] / 100.0f64
                    i2 += 1i64
                }
                if i7 > 7i64 && s.itrouble == 0i64 {
                    s.itrouble = 2i64
                    restore_bounds(s, cbound[0usize..8usize])
                    ret 0.0f64
                }
                i7 += 1i64
                if i7 == 200i64 {
                    s.itrouble = 5i64
                    ret 1.0f64
                }
            }
        }
        iii1 = 0i64
        if ns[2usize] + ns[3usize] + ns[4usize] > 0i64 {
            iii1 = dsidi_nonpos(work[0usize..2500usize], NC, u(nk - 1i64), kpvt[0usize..50usize])
        }
        i2 = 0i64
        while i2 < nk - 1i64 {
            rvr[u(i2)] = shift[u(i2)]
            i2 += 1i64
        }
        iii3 = iii1
        if iii1 == 0i64 {
            nrc = 0i64
            nrc2 = 0i64
        }
        if iii1 > 0i64 && nrc + nrc2 >= 5i64 && nrc >= 2i64 {
            nrc2 += 1i64
            if nrc2 == 15i64 && s.itrouble == 0i64 {
                s.itrouble = 2i64
                restore_bounds(s, cbound[0usize..8usize])
                ret 0.0f64
            }
            if nrc2 == 48i64 && s.itrouble != 0i64 {
                s.itrouble = 5i64
                restore_bounds(s, cbound[0usize..8usize])
                ret 1.0f64
            }
            iii1 = 0i64
            nrc = 0i64
        }
        if iii1 == 0i64 {
            lsp.dsisl(work[0usize..2500usize], NC, u(nk - 1i64), kpvt[0usize..50usize], shift[0usize..50usize])
            i7 = 0i64
            var again = true
            while again {
                var zerrorx = error2(s, shift[0usize..50usize], rvr[0usize..100usize])
                zerrorx = zerrorx * 100.0f64
                zerror = erroradjust(s, shift[0usize..50usize])
                if iii3 == 0i64 { zerror = zerrorx }
                var f = -1i64
                if zerror > 0.0f64 { f += 2i64 }
                if zerror < 2.0f64 { f += 2i64 }
                if numbertester(zerror) == 1i64 { f = f - 4i64 }
                if f < 0i64 {
                    i2 = 0i64
                    while i2 < nk - 1i64 {
                        shift[u(i2)] = shift[u(i2)] / 10.0f64
                        i2 += 1i64
                    }
                    if i7 > 7i64 && s.itrouble == 0i64 {
                        s.itrouble = 2i64
                        restore_bounds(s, cbound[0usize..8usize])
                        ret 0.0f64
                    }
                    i7 += 1i64
                    if i7 == 200i64 {
                        s.itrouble = 5i64
                        ret 1.0f64
                    }
                    f = 0i64 - 7i64
                }
                again = f < 0i64
            }
            i7 = 0i64
            again = true
            while again {
                if counter < 0i64 - 1000i64 { counter = counter + 10000i64 }
                if zh[0usize] + shift[0usize] >= 0.0f64 && bd[1usize] < 0.5f64 {
                    cbound[5usize] = 0.0f64 - cbound[5usize]
                    bd[2usize] = cbound[5usize] * (kn[0usize] - kn[1usize]) + kn[0usize]
                    bd[1usize] = 1.0f64
                    counter = 0i64
                }
                if zh[u(nk - 2i64)] + shift[u(nk - 2i64)] >= 0.0f64 && bd[3usize] < 0.5f64 {
                    cbound[6usize] = 0.0f64 - cbound[6usize]
                    bd[4usize] = cbound[6usize] * (kn[u(nk - 1i64)] - kn[u(nk - 2i64)]) + kn[u(nk - 1i64)]
                    bd[3usize] = 1.0f64
                    counter = 0i64
                }
                if counter > 0i64 {
                    i2 = 0i64
                    while i2 < nk - 1i64 {
                        candidate[u(i2)] = shift[u(i2)] + zh[u(i2)]
                        i2 += 1i64
                    }
                    s.czheta = middle(s, info, shift[0usize..50usize], candidate[0usize..50usize], accuracy, 0i64)
                    if okc(s.czheta) {
                        newlik = likeli(s, candidate[0usize..50usize], accuracy)
                        if newlik < oldlik && ((newlik / oldlik < one) || (oldlik / newlik < one)) && zerror > 0.00001f64 {
                            jaja1 += 1i64
                            if jaja1 < 12i64 || i1 < 3i64 {
                                i2 = 0i64
                                while i2 < nk - 1i64 {
                                    shift[u(i2)] = shift[u(i2)] / 2.0f64
                                    i2 += 1i64
                                }
                                counter = counter - 10000i64
                            }
                        }
                    } else {
                        if i7 > 7i64 && s.itrouble == 0i64 {
                            s.itrouble = 2i64
                            restore_bounds(s, cbound[0usize..8usize])
                            ret 0.0f64
                        }
                        i7 += 1i64
                        if i7 == 200i64 {
                            s.itrouble = 5i64
                            ret 1.0f64
                        }
                        i2 = 0i64
                        while i2 < nk - 1i64 {
                            shift[u(i2)] = shift[u(i2)] / 10.0f64
                            i2 += 1i64
                        }
                        counter = counter - 10000i64
                    }
                }
                again = counter < 0i64
            }
        }
        if jaja1 == 25i64 {
            restore_bounds(s, cbound[0usize..8usize])
            ret newlik
        }
        if iii1 > 0i64 {
            nrc += 1i64
            i2 = 0i64
            while i2 < nk - 1i64 {
                shift[u(i2)] = rvr[u(i2)]
                i2 += 1i64
            }
            i2 = 0i64
            while i2 < nk - 1i64 {
                rvr[u(i2)] = zh[u(i2)]
                i2 += 1i64
            }
            let _ = erroradjust(s, shift[0usize..50usize])
            if cbound[5usize] < 0.0f64 && bd[1usize] < 0.5f64 && (cbound[5usize] > 0.0f64 - 6.0f64 || zh[0usize] + shift[0usize] > 0.0f64) {
                cbound[5usize] = 0.0f64 - cbound[5usize]
                bd[2usize] = cbound[5usize] * (kn[0usize] - kn[1usize]) + kn[0usize]
                bd[1usize] = 1.0f64
                counter = 0i64
            }
            if cbound[6usize] < 0.0f64 && bd[3usize] < 0.5f64 && (cbound[6usize] > 0.0f64 - 6.0f64 || zh[u(nk - 2i64)] + shift[u(nk - 2i64)] > 0.0f64) {
                cbound[6usize] = 0.0f64 - cbound[6usize]
                bd[4usize] = cbound[6usize] * (kn[u(nk - 1i64)] - kn[u(nk - 2i64)]) + kn[u(nk - 1i64)]
                bd[3usize] = 1.0f64
                counter = 0i64
            }
            if counter == 0i64 {
                s.czheta = middle(s, info, shift[0usize..50usize], zh, accuracy, 0i64)
                let _ = middle(s, info, shift[0usize..50usize], zh, accuracy, 1i64)
                oldlik = likeli(s, zh, accuracy)
                i2 = 0i64
                while i2 < nk - 1i64 {
                    shift[u(i2)] = rvr[u(i2)]
                    i2 += 1i64
                }
                i2 = 0i64
                while i2 < nk - 1i64 {
                    rvr[u(i2)] = zh[u(i2)]
                    i2 += 1i64
                }
                let _ = erroradjust(s, shift[0usize..50usize])
            }
            oldlik = linsearch(s, shift[0usize..50usize], oldlik, accuracy)
            s.czheta = middle(s, info, shift[0usize..50usize], zh, accuracy, 0i64)
            let _ = middle(s, info, shift[0usize..50usize], zh, accuracy, 1i64)
            let _ = erroradjust(s, shift[0usize..50usize])
            oldlik = linsearch(s, shift[0usize..50usize], oldlik, accuracy)
            i2 = 0i64
            while i2 < nk - 1i64 {
                shift[u(i2)] = zh[u(i2)] - rvr[u(i2)]
                i2 += 1i64
            }
            oldlik = linsearch(s, shift[0usize..50usize], oldlik, accuracy)
            s.czheta = middle(s, info, shift[0usize..50usize], zh, accuracy, 0i64)
            i2 = 0i64
            while i2 < nk - 1i64 {
                shift[u(i2)] = 0.0f64
                i2 += 1i64
            }
            i2 = 0i64
            while i2 < nk - 1i64 {
                rvr[u(i2)] = zh[u(i2)] - rvr[u(i2)]
                i2 += 1i64
            }
            zerror = 100.0f64 * erroradjust(s, rvr[0usize..100usize])
            newlik = oldlik
        }
        if counter > 0i64 {
            i2 = 0i64
            while i2 < nk - 1i64 {
                zh[u(i2)] = zh[u(i2)] + shift[u(i2)]
                i2 += 1i64
            }
            if ithere < 10i64 { zerror = zerror / 100.0f64 }
            if zerror < 0.000001f64 {
                if ithere > 9i64 {
                    if accuracy == 5i64 {
                        restore_bounds(s, cbound[0usize..8usize])
                        rvr[99usize] = middle(s, info, shift[0usize..50usize], zh, 5i64, 0i64)
                        if iii1 != 0i64 {
                            rvr[99usize] = middle(s, info, shift[0usize..50usize], zh, 5i64, 0i64)
                        }
                        if okc(rvr[99usize]) {
                            s.czheta = rvr[99usize]
                            newlik = likeli(s, zh, 5i64)
                        }
                        ret newlik
                    } else {
                        accuracy = 5i64
                        counter = 0i64
                    }
                } else {
                    counter = 0i64
                    if cbound[5usize] < 0.0f64 {
                        cbound[5usize] = 2.0f64 * cbound[5usize]
                    } else {
                        if cbound[1usize] < 0.5f64 && zh[0usize] >= 0.0f64 {
                            cbound[5usize] = 2.0f64 * cbound[5usize]
                            bd[2usize] = cbound[5usize] * (kn[0usize] - kn[1usize]) + kn[0usize]
                        }
                        if cbound[1usize] < 0.5f64 && zh[0usize] < 0.0f64 {
                            cbound[5usize] = 0.0f64 - 2.0f64 * cbound[5usize]
                            bd[1usize] = 0.0f64
                        }
                        if cbound[1usize] > 0.5f64 && bd[1usize] > 0.5f64 && bd[1usize] < 1.5f64 {
                            cbound[5usize] = 2.0f64 * cbound[5usize]
                            bd[2usize] = cbound[5usize] * (kn[0usize] - kn[1usize]) + kn[0usize]
                            if bd[2usize] < cbound[2usize] {
                                bd[2usize] = cbound[2usize]
                                bd[1usize] = 2.0f64
                            }
                        }
                    }
                    if cbound[6usize] < 0.0f64 {
                        cbound[6usize] = 2.0f64 * cbound[6usize]
                    } else {
                        if cbound[3usize] < 0.5f64 && zh[u(nk - 2i64)] >= 0.0f64 {
                            cbound[6usize] = 2.0f64 * cbound[6usize]
                            bd[4usize] = cbound[6usize] * (kn[u(nk - 1i64)] - kn[u(nk - 2i64)]) + kn[u(nk - 1i64)]
                        }
                        if cbound[3usize] < 0.5f64 && zh[u(nk - 2i64)] < 0.0f64 {
                            cbound[6usize] = 0.0f64 - 2.0f64 * cbound[6usize]
                            bd[3usize] = 0.0f64
                        }
                        if cbound[3usize] > 0.5f64 && bd[3usize] > 0.5f64 && bd[3usize] < 1.5f64 {
                            cbound[6usize] = 2.0f64 * cbound[6usize]
                            bd[4usize] = cbound[6usize] * (kn[u(nk - 1i64)] - kn[u(nk - 2i64)]) + kn[u(nk - 1i64)]
                            if bd[4usize] > cbound[4usize] {
                                bd[4usize] = cbound[4usize]
                                bd[3usize] = 2.0f64
                            }
                        }
                    }
                }
            }
        }
        i1 += 1i64
    }
    if s.sorc[0usize] == 0i64 {
        s.sorc[0usize] = 0i64 - 647i64
    } else {
        s.sorc[0usize] = 0i64 - s.sorc[0usize]
    }
    ret newlik
}

// the knot whose Wald ratio is largest goes; the information matrix (s.info) is inverted in place
fn removeknot(s: *St) -> i64 {
    let nk = s.nknots
    let c2 = s.coef2
    let info = s.info
    var ratmax = 0.0f64
    var wk1: [50]f64 = zero
    var se: [50]f64 = zero
    var phi: [50]f64 = zero
    var kpvt: [50]i64 = zero
    var irmax = 1i64
    var i = 0i64
    var j = 0i64
    var k = 0i64
    while i < nk - 1i64 {
        phi[u(i)] = 0.0f64
        j = 0i64
        while j < nk - 1i64 {
            phi[u(i)] = phi[u(i)] + s.zheta[u(j)] * c2[m2(j, i + 2i64)]
            j += 1i64
        }
        phi[u(i)] = fabs(phi[u(i)])
        i += 1i64
    }
    let _ = lsp.dsifa(info, NC, u(nk - 1i64), kpvt[0usize..50usize])
    lsp.dsidi_inv(info, NC, u(nk - 1i64), kpvt[0usize..50usize], wk1[0usize..50usize])
    i = 1i64
    while i < nk - 1i64 {
        j = 0i64
        while j < i {
            info[m2(j, i)] = info[m2(i, j)]
            j += 1i64
        }
        i += 1i64
    }
    i = 1i64
    while i < nk - 1i64 {
        se[u(i)] = 0.0f64
        j = 0i64
        while j < nk - 1i64 {
            k = 0i64
            while k < nk - 1i64 {
                se[u(i)] = se[u(i)] + c2[m2(j, i + 2i64)] * c2[m2(k, i + 2i64)] * info[m2(j, k)]
                k += 1i64
            }
            j += 1i64
        }
        if se[u(i)] > 0.0f64 {
            se[u(i)] = math.sqrt[f64](se[u(i)])
            if se[u(i)] > phi[u(i)] * ratmax {
                ratmax = se[u(i)] / phi[u(i)]
                irmax = i
            }
        }
        i += 1i64
    }
    s.nknots = nk - 1i64
    ret irmax
}

fn fits(s: *St, xc2: []f64, xz: []f64, xcz: f64, ycoef: []f64, xik: []i64, xnk: i64) {
    var i = 0i64
    while i < NCI {
        ycoef[u(i)] = 0.0f64
        i += 1i64
    }
    ycoef[0usize] = 0.0f64 - math.log[f64](xcz)
    i = 0i64
    while i < xnk {
        ycoef[u(xik[u(i)] + 2i64)] = 0.0f64
        var j = 0i64
        while j < xnk - 1i64 {
            ycoef[u(xik[u(i)] + 2i64)] = ycoef[u(xik[u(i)] + 2i64)] + xz[u(j)] * xc2[m2(j, i + 2i64)]
            j += 1i64
        }
        i += 1i64
    }
    var j = 0i64
    while j < xnk - 1i64 {
        ycoef[0usize] = ycoef[0usize] + xz[u(j)] * xc2[m2(j, 0i64)]
        ycoef[1usize] = ycoef[1usize] + xz[u(j)] * xc2[m2(j, 1i64)]
        j += 1i64
    }
}

// --- knot placement

fn piecedens(s: *St) -> i64 {
    let ns = s.ns
    let sm = s.sample
    let smp2 = s.smp2
    let smp3 = s.smp3
    let n0 = ns[0usize]
    let n1 = ns[1usize]
    let n2 = ns[2usize]
    let n3 = ns[3usize]
    let n4 = ns[4usize]
    var i = 0i64
    var j = 0i64
    if n1 > 0i64 { ssort(sm, smp3, n1, 1i64, s.il, s.iu) }
    if n2 > 0i64 {
        i = 0i64
        while i < n2 {
            smp2[u(i)] = sm[u(n1 + 2i64 * i)]
            smp3[u(i)] = sm[u(n1 + 2i64 * i + 1i64)]
            i += 1i64
        }
        ssort(smp2, smp3, n2, 2i64, s.il, s.iu)
        i = 0i64
        while i < n2 {
            sm[u(n1 + 2i64 * i)] = smp2[u(i)]
            sm[u(n1 + 2i64 * i + 1i64)] = smp3[u(i)]
            i += 1i64
        }
    }
    if n3 > 0i64 {
        i = 0i64
        while i < n3 {
            smp2[u(i)] = sm[u(i + n1 + 2i64 * n2)]
            i += 1i64
        }
        ssort(smp2, smp3, n3, 1i64, s.il, s.iu)
        i = 0i64
        while i < n3 {
            sm[u(i + n1 + 2i64 * n2)] = smp2[u(i)]
            i += 1i64
        }
    }
    if n4 > 0i64 {
        i = 0i64
        while i < n4 {
            smp2[u(i)] = sm[u(i + n1 + 2i64 * n2 + n3)]
            i += 1i64
        }
        ssort(smp2, smp3, n4, 1i64, s.il, s.iu)
        i = 0i64
        while i < n4 {
            sm[u(i + n1 + 2i64 * n2 + n3)] = smp2[u(i)]
            i += 1i64
        }
    }
    i = 0i64
    while i < n1 {
        smp2[u(i)] = sm[u(i)]
        smp3[u(i)] = 1.0f64
        i += 1i64
    }
    i = 0i64
    while i < n3 + n4 {
        j = n1 + 2i64 * n2 + i
        smp2[u(j)] = sm[u(j)]
        smp3[u(j)] = 1.0f64
        i += 1i64
    }
    if n2 > 0i64 {
        i = 0i64
        while i < n2 {
            j = n1 + i * 2i64
            smp2[u(j)] = sm[u(j)]
            smp3[u(j)] = 0.0f64
            smp2[u(j + 1i64)] = sm[u(j + 1i64)]
            smp3[u(j + 1i64)] = 0.0f64
            i += 1i64
        }
    }
    ssort(smp2, smp3, n0 + n2, 2i64, s.il, s.iu)
    i = 0i64
    j = 1i64
    while j < n0 + n2 {
        if smp2[u(j)] == smp2[u(i)] {
            smp3[u(i)] = smp3[u(i)] + smp3[u(j)]
        } else {
            i += 1i64
            smp2[u(i)] = smp2[u(j)]
            smp3[u(i)] = smp3[u(j)]
        }
        j += 1i64
    }
    let il = i
    i = il - 1i64
    while i >= 0i64 {
        if smp3[u(i)] > 0.0f64 {
            smp3[u(i + 1i64)] = smp3[u(i + 1i64)] + 0.5f64 * smp3[u(i)]
            smp3[u(i)] = 0.5f64 * smp3[u(i)]
        }
        i = i - 1i64
    }
    if n2 > 0i64 {
        var k = 0i64
        i = 0i64
        while i < n2 {
            j = n1 + i * 2i64
            var m = k
            while m <= il {
                if sm[u(j)] < smp2[u(m)] {
                    k = m
                    m = 2i64 * il + 1i64
                    var n = k
                    while n <= il {
                        if sm[u(j + 1i64)] < smp2[u(n)] {
                            n = 2i64 * il + 1i64
                        } else {
                            smp3[u(n)] = smp3[u(n)] + (smp2[u(n)] - smp2[u(n - 1i64)]) / (sm[u(j + 1i64)] - sm[u(j)])
                        }
                        n += 1i64
                    }
                }
                m += 1i64
            }
            i += 1i64
        }
    }
    i = 1i64
    while i <= il {
        smp3[u(i)] = smp3[u(i)] + smp3[u(i - 1i64)]
        i += 1i64
    }
    ret il
}

fn knotnumber(s: *St, idelete: i64, nk0: i64) -> i64 {
    let ns = s.ns
    var nknots = nk0
    let nn = ns[1usize] + ns[2usize] + (ns[3usize] + ns[4usize]) / 2i64
    if nknots >= NCI || (nknots > ns[5usize] + 1i64 && ns[5usize] > 1i64) {
        s.sorc[20usize] = 1i64
        nknots = NCI - 1i64
        if nknots > ns[5usize] + 1i64 { nknots = ns[5usize] + 1i64 }
    }
    if nknots > 0i64 { ret nknots }
    var r = 2.5f64 * pw(flt(nn), 0.2f64)
    if idelete > 0i64 { r = 1.6f64 * r }
    if idelete > 0i64 && nn < 51i64 { r = flt(nn) / 6.0f64 }
    if r > flt(NCI) - 1.1f64 { r = flt(NCI) - 1.1f64 }
    if r < 2.5f64 { r = 2.5f64 }
    if ns[5usize] != 0i64 && r > flt(ns[5usize]) + 1.0f64 { r = flt(ns[5usize]) + 0.1f64 }
    ret i64(math.ceil[f64](r))
}

fn knotplace(s: *St, iknotauto: i64) {
    let ns = s.ns
    let sm = s.sample
    let bd = s.bound
    let kn = s.knots
    let rk = s.rknots
    let smp2 = s.smp2
    let smp3 = s.smp3
    let w1 = ns[0usize]
    let w2 = ns[1usize]
    let w3 = ns[2usize]
    let w4 = ns[3usize]
    let w5 = ns[4usize]
    let w6 = ns[5usize]
    var i = 0i64
    var j = 0i64
    var j2 = 0i64
    var k = 0i64
    var ia = 0i64
    var kk = 0i64
    var ll = 0i64
    var kx = 0i64
    var il = 0i64
    let five = 4.0f64
    var u3 = 0.0f64
    var u4 = 0.0f64
    var u1 = 0.0f64
    var u2 = 0.0f64
    var eps = 0.0f64
    var eps1 = 0.0f64
    var eps2 = 0.0f64
    var ss = 0.0f64
    var v = 0.0f64
    var w = 0.0f64
    if s.sorc[16usize] == 1i64 {
        ns[0usize] = w2
        ns[1usize] = w2
        ns[2usize] = 0i64
        ns[3usize] = 0i64
        ns[4usize] = 0i64
        ns[5usize] = w2 - 1i64
    }
    s.qt0 = 0.0f64 - 1.0f64
    s.qt1 = 1.0f64
    var nk = s.nknots
    if iknotauto == 0i64 && nk > 12i64 {
        s.qt0 = kn[4usize]
        s.qt1 = kn[u(nk - 5i64)]
    }
    if iknotauto == 0i64 && nk > 9i64 && nk < 13i64 {
        s.qt0 = kn[3usize]
        s.qt1 = kn[u(nk - 4i64)]
    }
    if iknotauto == 0i64 && nk > 6i64 && nk < 10i64 {
        s.qt0 = kn[2usize]
        s.qt1 = kn[u(nk - 3i64)]
    }
    if iknotauto == 0i64 && nk == 3i64 {
        s.qt0 = (kn[0usize] + kn[1usize]) / 2.0f64
        s.qt1 = (kn[2usize] + kn[1usize]) / 2.0f64
    }
    if iknotauto == 0i64 && nk > 3i64 && nk < 7i64 {
        s.qt0 = kn[1usize]
        s.qt1 = kn[u(nk - 2i64)]
    }
    if iknotauto == 1i64 {
        il = piecedens(s)
        kk = i64(math.floor[f64](flt(il) / 2.0f64 + 2.1f64))
        if nk > kk && ns[5usize] == 0i64 {
            nk = kk
            s.sorc[20usize] = 1i64
        }
        s.nknots = nk
        if nk == ns[5usize] + 1i64 { s.sorc[20usize] = 1i64 }
        kk = 0i64
        ll = 0i64
        var again = true
        while again {
            ll = kk + ll
            kk = 0i64
            if bd[1usize] < 0.5f64 && bd[3usize] < 0.5f64 {
                if flt(nk - 1i64) * five >= flt(ns[0usize] - 1i64) {
                    i = i64(math.floor[f64](1.0f64 + (flt(ns[0usize]) - 1.0f64) / five))
                    s.sorc[0usize] = 0i64 - 2i64
                    s.sorc[1usize] = i
                    ret
                }
                rk[0usize] = 1.0f64
                rk[u(nk - 1i64)] = flt(ns[0usize])
                j = i64(math.ceil[f64](flt(nk - 1i64) / 2.0f64))
                j2 = i64(math.floor[f64](flt(nk - 1i64) / 2.0f64))
                eps1 = five - pw(flt(ns[0usize] - 1i64) / five, 1.0f64 / flt(j - 1i64))
                if eps1 > 0.0f64 { eps1 = 0.0f64 }
                eps2 = five - 1.0f64
                var more = true
                while more {
                    eps = (eps1 + eps2) / 2.0f64
                    ss = 1.0f64
                    w = five
                    i = 1i64
                    while i <= j2 {
                        v = flt(i)
                        ss = ss + w
                        rk[u(i)] = ss
                        rk[u(nk - i - 1i64)] = flt(ns[0usize]) + 1.0f64 - ss
                        v = five - v * eps
                        if v < 1.0f64 { v = 1.0f64 }
                        w = w * v
                        i += 1i64
                    }
                    if j * 2i64 == nk {
                        ss = ss + w / 2.0f64
                    } else {
                        rk[u(j)] = (flt(ns[0usize]) + 1.0f64) / 2.0f64
                    }
                    if 2.0f64 * ss >= flt(ns[0usize]) + 1.0f64 {
                        eps1 = eps
                    } else {
                        eps2 = eps
                    }
                    more = eps2 - eps1 > 0.001f64
                }
            } else {
                if bd[1usize] > 0.5f64 && bd[3usize] > 0.5f64 {
                    i = 0i64
                    while i < nk {
                        rk[u(i)] = 1.0f64 + flt(ns[0usize] - 1i64) * flt(i) / flt(nk - 1i64)
                        i += 1i64
                    }
                } else {
                    rk[0usize] = 1.0f64
                    rk[u(nk - 1i64)] = flt(ns[0usize])
                    eps1 = 0.0f64
                    eps2 = five
                    var more = true
                    while more {
                        eps = (eps1 + eps2) / 2.0f64
                        ss = 1.0f64
                        w = five
                        i = 1i64
                        while i < nk - 1i64 {
                            v = flt(i)
                            ss = ss + w
                            if bd[3usize] > 0.5f64 {
                                rk[u(i)] = ss
                            } else {
                                rk[u(nk - i - 1i64)] = flt(ns[0usize]) + 1.0f64 - ss
                            }
                            v = five - v * eps
                            if v < 1.0f64 { v = 1.0f64 }
                            w = w * v
                            i += 1i64
                        }
                        if ss + w > flt(ns[0usize]) {
                            eps1 = eps
                        } else {
                            eps2 = eps
                        }
                        more = eps2 - eps1 > 0.001f64
                    }
                }
            }
            if nk == 3i64 { rk[1usize] = flt(ns[0usize]) / 2.0f64 }
            if ll == 0i64 {
                kn[0usize] = smp2[0usize]
                kn[u(nk - 1i64)] = smp2[u(il)]
                k = 0i64
                i = 1i64
                while i < nk - 1i64 {
                    rk[u(i)] = rk[u(i)] - 0.5f64
                    kx = k
                    k = kx
                    while k <= il {
                        if smp3[u(k)] >= rk[u(i)] {
                            kn[u(i)] = ((rk[u(i)] - smp3[u(k - 1i64)]) * smp2[u(k)] + (smp3[u(k)] - rk[u(i)]) * smp2[u(k - 1i64)]) / (smp3[u(k)] - smp3[u(k - 1i64)])
                            ia = k
                            k = k + 4i64 * il
                        }
                        k += 1i64
                    }
                    k = ia
                    i += 1i64
                }
            }
            i = 1i64
            while i < il {
                if smp3[u(i)] > 0.25f64 * flt(ns[0usize]) {
                    u3 = smp2[u(i)]
                    i = i + 2i64 * il
                    s.qt0 = u3
                }
                i += 1i64
            }
            i = 1i64
            while i < il + 1i64 {
                if smp3[u(i)] > 0.75f64 * flt(ns[0usize]) {
                    u4 = smp2[u(i)]
                    i = i + 2i64 * il
                    s.qt1 = u4
                }
                i += 1i64
            }
            if bd[1usize] < 0.5f64 {
                u1 = kn[2usize] - kn[0usize]
                u2 = u4 - u3
                if u1 < u2 / 30.0f64 {
                    s.sorc[21usize] = 1i64
                    kk = kk + 1i64
                    bd[1usize] = 1.0f64
                    bd[2usize] = kn[0usize]
                }
            }
            if bd[3usize] < 0.5f64 {
                u1 = kn[u(nk - 1i64)] - kn[u(nk - 3i64)]
                u2 = u4 - u3
                if u1 < u2 / 30.0f64 {
                    s.sorc[22usize] = 1i64
                    kk = kk + 2i64
                    bd[3usize] = 1.0f64
                    bd[4usize] = kn[u(nk - 1i64)]
                }
            }
            again = kk > 0i64
        }
        if ll == 1i64 || ll == 3i64 { bd[1usize] = 0.0f64 }
        if ll == 2i64 || ll == 3i64 { bd[3usize] = 0.0f64 }
        u1 = kn[u(nk - 1i64)] - kn[u(nk - 3i64)]
        u2 = u4 - u3
        if u1 < u2 / 30.0f64 {
            s.sorc[22usize] = 3i64
            kn[u(nk - 3i64)] = (kn[u(nk - 3i64)] + kn[u(nk - 2i64)]) / 2.0f64
            kn[u(nk - 2i64)] = kn[u(nk - 1i64)]
            nk = nk - 1i64
        }
        again = true
        while again {
            u1 = kn[u(nk - 1i64)] - kn[u(nk - 3i64)]
            u2 = u4 - u3
            if u1 < u2 / 30.0f64 {
                kn[u(nk - 3i64)] = (kn[u(nk - 3i64)] + kn[u(nk - 2i64)]) / 2.0f64
                nk = nk - 1i64
            }
            again = u1 < u2 / 30.0f64
        }
        u1 = kn[2usize] - kn[0usize]
        u2 = u4 - u3
        if u1 < u2 / 30.0f64 {
            s.sorc[21usize] = 3i64
            kn[1usize] = (kn[1usize] + kn[2usize]) / 2.0f64
            i = 2i64
            while i < nk - 1i64 {
                kn[u(i)] = kn[u(i + 1i64)]
                i += 1i64
            }
            nk = nk - 1i64
        }
        again = true
        while again {
            u1 = kn[2usize] - kn[0usize]
            u2 = u4 - u3
            if u1 < u2 / 30.0f64 {
                kn[1usize] = (kn[1usize] + kn[2usize]) / 2.0f64
                i = 1i64
                while i < nk - 1i64 {
                    kn[u(i)] = kn[u(i + 1i64)]
                    i += 1i64
                }
                nk = nk - 1i64
            }
            again = u1 < u2 / 30.0f64
        }
        s.nknots = nk
    }
    j = 0i64
    k = 0i64
    i = 1i64
    while i < nk {
        if kn[u(i)] > kn[u(j)] {
            j += 1i64
            kn[u(j)] = kn[u(i)]
        } else {
            k += 1i64
            if s.sorc[0usize] != 8i64 {
                s.sorc[0usize] = 2i64 + k
                if s.sorc[0usize] == 23i64 { ret }
                s.sorc[u(k)] = i + 1i64
            }
        }
        i += 1i64
    }
    nk = j + 1i64
    s.nknots = nk
    ns[0usize] = w1
    ns[1usize] = w2
    ns[2usize] = w3
    ns[3usize] = w4
    ns[4usize] = w5
    ns[5usize] = w6
    u3 = 2.0f64 / (s.qt1 - s.qt0)
    u4 = 1.0f64 - 2.0f64 * s.qt1 / (s.qt1 - s.qt0)
    s.qt0 = u4
    s.qt1 = u3
    i = 0i64
    while i < nk {
        rk[u(i)] = u4 + u3 * kn[u(i)]
        kn[u(i)] = u4 + u3 * kn[u(i)]
        s.iknots[u(i)] = i
        i += 1i64
    }
    i = 0i64
    while i < ns[0usize] + ns[2usize] {
        sm[u(i)] = u4 + u3 * sm[u(i)]
        i += 1i64
    }
}

// the C entry logcensor: returns the number of starting knots (ynknots); yknots and ycoef are NC long, logl has room for NC
fn logcensor(s: *St, idelete: i64, iknotauto: i64, alpha: f64, ynk0: i64, yknots: []f64, ycoef: []f64, logl: []f64) -> i64 {
    let ns = s.ns
    let sm = s.sample
    let bd = s.bound
    let kn = s.knots
    var xcoef2: [2500]f64 = zero
    var xzheta: [50]f64 = zero
    var xiknots: [50]i64 = zero
    var xczheta = 0.0f64
    var xnknots = 0i64
    var aicmin = 0.0f64
    var aic = 0.0f64
    var loglik = 0.0f64
    var r1 = 0.0f64
    var iremove = 0i64
    var i = 0i64
    var j = 0i64
    while i < NCI {
        s.ng3[u(i)] = 0i64
        s.ng4[u(i)] = 0i64
        i += 1i64
    }
    s.nknots = ynk0
    i = 0i64
    while i < NCI {
        kn[u(i)] = yknots[u(i)]
        i += 1i64
    }
    if ns[0usize] < 14i64 {
        s.sorc[0usize] = 2i64
        ret ynk0
    }
    s.nknots = knotnumber(s, idelete, s.nknots)
    knotplace(s, iknotauto)
    bd[2usize] = s.qt0 + s.qt1 * bd[2usize]
    bd[4usize] = s.qt0 + s.qt1 * bd[4usize]
    aicmin = pw(10.0f64, 100.0f64)
    let nkstart = s.nknots
    i = 0i64
    while i < s.nknots {
        s.xg[u(i)] = kn[u(i)]
        i += 1i64
    }
    i = ns[1usize] + 2i64 * ns[2usize]
    while i < ns[0usize] + ns[2usize] - ns[4usize] {
        j = 0i64
        while j < s.nknots && kn[u(j)] < sm[u(i)] { j += 1i64 }
        if j != 0i64 && j != s.nknots {
            if sm[u(i)] - kn[u(j - 1i64)] < kn[u(j)] - sm[u(i)] { j = j - 1i64 }
        }
        if j == s.nknots { j = j - 1i64 }
        s.ng3[u(j)] = s.ng3[u(j)] + 1i64
        i += 1i64
    }
    i = ns[1usize] + 2i64 * ns[2usize] + ns[3usize]
    while i < ns[0usize] + ns[2usize] {
        j = 0i64
        while j < s.nknots && kn[u(j)] < sm[u(i)] { j += 1i64 }
        if j != 0i64 && j != s.nknots {
            if sm[u(i)] - kn[u(j - 1i64)] < kn[u(j)] - sm[u(i)] { j = j - 1i64 }
        }
        if j == s.nknots { j = j - 1i64 }
        s.ng4[u(j)] = s.ng4[u(j)] + 1i64
        i += 1i64
    }
    i = 0i64
    while i < s.nknots {
        yknots[u(i)] = kn[u(i)]
        i += 1i64
    }
    if s.sorc[0usize] == 0i64 - 2i64 { ret ynk0 }
    if s.sorc[0usize] == 647i64 { ret ynk0 }
    if s.sorc[0usize] == 23i64 { ret ynk0 }
    suffstat1(s)
    start1(s)
    s.itrouble = 0i64
    var again = true
    while again {
        coeff(s)
        suffstat2(s)
        start2(s, nkstart, iremove)
        if s.itrouble == 1i64 {
            i = 0i64
            while i < s.nknots - 1i64 {
                s.zheta[u(i)] = 0.0f64
                i += 1i64
            }
            loglik = liter(s, 5i64)
        } else {
            loglik = liter(s, 0i64)
            if s.itrouble == 2i64 {
                i = 0i64
                while i < s.nknots - 1i64 {
                    s.zheta[u(i)] = 0.0f64
                    i += 1i64
                }
                s.itrouble = 1i64
                loglik = liter(s, 5i64)
            }
        }
        s.sorc[27usize] = 0i64
        if s.sorc[0usize] < 0i64 || s.itrouble == 5i64 || s.itrouble == 17i64 {
            if s.nknots == nkstart {
                s.sorc[0usize] = 0i64 - 1i64
                s.sorc[27usize] = 0i64
                ret ynk0
            }
            s.sorc[27usize] = s.nknots
            s.nknots = 0i64
        }
        if s.nknots > 0i64 {
            if idelete == 0i64 {
                xczheta = s.czheta
                xnknots = s.nknots
                i = 0i64
                while i < NCI {
                    xzheta[u(i)] = s.zheta[u(i)]
                    xiknots[u(i)] = s.iknots[u(i)]
                    j = 0i64
                    while j < NCI {
                        xcoef2[m2(i, j)] = s.coef2[m2(i, j)]
                        j += 1i64
                    }
                    i += 1i64
                }
                logl[0usize] = loglik * flt(ns[0usize]) + math.log[f64](s.qt1) * flt(ns[1usize])
            } else {
                aic = 0.0f64 - 2.0f64 * loglik * flt(ns[0usize]) + alpha * flt(s.nknots - 1i64)
                logl[u(s.nknots - 1i64)] = loglik * flt(ns[0usize]) + math.log[f64](s.qt1) * flt(ns[1usize])
                if aic <= aicmin {
                    aicmin = aic
                    xczheta = s.czheta
                    xnknots = s.nknots
                    i = 0i64
                    while i < NCI {
                        xzheta[u(i)] = s.zheta[u(i)]
                        xiknots[u(i)] = s.iknots[u(i)]
                        j = 0i64
                        while j < NCI {
                            xcoef2[m2(i, j)] = s.coef2[m2(i, j)]
                            j += 1i64
                        }
                        i += 1i64
                    }
                } else {
                    r1 = 0.0f64 - 2.0f64 * loglik * flt(ns[0usize]) + alpha * 2.0f64
                    if r1 >= aicmin { s.nknots = 0i64 }
                }
                if s.nknots >= 4i64 {
                    iremove = removeknot(s)
                    let nk = s.nknots
                    i = iremove
                    while i < nk {
                        kn[u(i)] = kn[u(i + 1i64)]
                        s.iknots[u(i)] = s.iknots[u(i + 1i64)]
                        s.der[u(i + 1i64)] = s.der[u(i + 2i64)]
                        s.suffc[u(i + 2i64) * 2usize] = s.suffc[u(i + 3i64) * 2usize]
                        s.suffc[u(i + 2i64) * 2usize + 1usize] = s.suffc[u(i + 3i64) * 2usize + 1usize]
                        s.cp[m2(0i64, i + 1i64)] = s.cp[m2(0i64, i + 2i64)]
                        s.cp[m2(i + 1i64, 0i64)] = s.cp[m2(i + 2i64, 0i64)]
                        i += 1i64
                    }
                    j = 0i64
                    while j < nk {
                        i = iremove
                        while i < nk && j >= iremove {
                            s.cp[m2(i + 1i64, j + 1i64)] = s.cp[m2(i + 2i64, j + 2i64)]
                            i += 1i64
                        }
                        i = iremove
                        while i < nk && j < iremove {
                            s.cp[m2(i + 1i64, j + 1i64)] = s.cp[m2(i + 2i64, j + 1i64)]
                            i += 1i64
                        }
                        i = 0i64
                        while i < iremove && j >= iremove {
                            s.cp[m2(i + 1i64, j + 1i64)] = s.cp[m2(i + 1i64, j + 2i64)]
                            i += 1i64
                        }
                        j += 1i64
                    }
                } else {
                    if s.nknots == 3i64 { s.nknots = 2i64 }
                }
            }
        }
        again = s.nknots >= 3i64 && idelete > 0i64
    }
    s.nknots = nkstart
    fits(s, xcoef2[0usize..2500usize], xzheta[0usize..50usize], xczheta, ycoef, xiknots[0usize..50usize], xnknots)
    bd[2usize] = (bd[2usize] - s.qt0) / s.qt1
    bd[4usize] = (bd[4usize] - s.qt0) / s.qt1
    i = 0i64
    while i < nkstart {
        yknots[u(i)] = (yknots[u(i)] - s.qt0) / s.qt1
        i += 1i64
    }
    i = 0i64
    while i < nkstart {
        ycoef[u(i + 2i64)] = ycoef[u(i + 2i64)] * s.qt1 * s.qt1 * s.qt1
        i += 1i64
    }
    ycoef[0usize] = ycoef[0usize] + ycoef[1usize] * s.qt0 + math.log[f64](s.qt1)
    ycoef[1usize] = ycoef[1usize] * s.qt1
    ret nkstart
}

// --- the R wrapper

type OldFit = struct {
    code: i64, nk: i64, coef: []f64, knots: []f64, bound: []f64, logl: []f64, penalty: f64, sample: i64, delete: i64, sorc: []i64
}

fn newst(a: *mem.Arena, nsv: usize) -> (St, err) {
    var s: St = zero
    let (ns, e1) = zi(a, 12usize)
    let (sm, e2) = zf(a, nsv + 8usize)
    let (bd, e3) = zf(a, 12usize)
    let (so, e4) = zi(a, 48usize)
    let (kn, e5) = zf(a, 64usize)
    let (cf, e6) = zf(a, NC * 4usize * NC)
    let (zh, e7) = zf(a, 64usize)
    let (xg, e8) = zf(a, 64usize)
    let (df, e9) = zf(a, 8usize)
    let (g3, e10) = zi(a, 64usize)
    let (g4, e11) = zi(a, 64usize)
    let (w6, e12) = zf(a, 8usize)
    let (y6, e13) = zf(a, 8usize)
    let (w7, e14) = zf(a, 40usize)
    let (y7, e15) = zf(a, 40usize)
    let (inf, e16) = zf(a, NC * NC)
    let (su, e17) = zf(a, 2usize * NC + 16usize)
    let (c2, e18) = zf(a, NC * NC)
    let (cp, e19) = zf(a, NC * NC)
    let (de, e20) = zf(a, 64usize)
    let (sc, e21) = zf(a, 2usize * NC + 16usize)
    let (s2, e22) = zf(a, nsv + 8usize)
    let (s3, e23) = zf(a, nsv + 8usize)
    let (ik, e24) = zi(a, 64usize)
    let (rk, e25) = zf(a, 64usize)
    let (il, e26) = zi(a, 48usize)
    let (iu, e27) = zi(a, 48usize)
    let (z1, e28) = zf(a, 64usize)
    let (z2, e29) = zf(a, NC * NC)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (s, mem.Full) }
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret (s, mem.Full) }
    if e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok || e25 != ok || e26 != ok || e27 != ok { ret (s, mem.Full) }
    if e28 != ok || e29 != ok { ret (s, mem.Full) }
    s.ns = ns
    s.sample = sm
    s.bound = bd
    s.sorc = so
    s.knots = kn
    s.coef = cf
    s.zheta = zh
    s.xg = xg
    s.dfunpar = df
    s.ng3 = g3
    s.ng4 = g4
    s.ww6 = w6
    s.yy6 = y6
    s.ww7 = w7
    s.yy7 = y7
    s.info = inf
    s.suff = su
    s.coef2 = c2
    s.cp = cp
    s.der = de
    s.suffc = sc
    s.smp2 = s2
    s.smp3 = s3
    s.iknots = ik
    s.rknots = rk
    s.il = il
    s.iu = iu
    s.z1 = z1
    s.z2 = z2
    // Gaussian quadrature coefficients (Abramowitz and Stegun)
    w6[1usize] = 0.467913934572691f64
    y6[1usize] = 0.238619186083197f64
    w6[2usize] = 0.360761573048139f64
    y6[2usize] = 0.661209386466265f64
    w6[3usize] = 0.171324429379170f64
    y6[3usize] = 0.932469514203152f64
    w7[1usize] = 0.00178328072169643f64
    y7[1usize] = 0.99930504173577217f64
    w7[2usize] = 0.00414703326056247f64
    y7[2usize] = 0.99634011677195533f64
    w7[3usize] = 0.00650445796897836f64
    y7[3usize] = 0.99101337147674429f64
    w7[4usize] = 0.00884675982636395f64
    y7[4usize] = 0.98333625388462598f64
    w7[5usize] = 0.01116813946013113f64
    y7[5usize] = 0.97332682778991098f64
    w7[6usize] = 0.01346304789671864f64
    y7[6usize] = 0.96100879965205377f64
    w7[7usize] = 0.01572603047602472f64
    y7[7usize] = 0.94641137485840277f64
    w7[8usize] = 0.01795171577569734f64
    y7[8usize] = 0.92956917213193957f64
    w7[9usize] = 0.02013482315353021f64
    y7[9usize] = 0.91052213707850282f64
    w7[10usize] = 0.02227017380838325f64
    y7[10usize] = 0.88931544599511414f64
    w7[11usize] = 0.02435270256871087f64
    y7[11usize] = 0.86599939815409277f64
    w7[12usize] = 0.02637746971505466f64
    y7[12usize] = 0.84062929625258032f64
    w7[13usize] = 0.02833967261425948f64
    y7[13usize] = 0.81326531512279754f64
    w7[14usize] = 0.03023465707240248f64
    y7[14usize] = 0.78397235894334139f64
    w7[15usize] = 0.03205792835485155f64
    y7[15usize] = 0.75281990726053194f64
    w7[16usize] = 0.03380516183714161f64
    y7[16usize] = 0.71988185017161088f64
    w7[17usize] = 0.03547221325688239f64
    y7[17usize] = 0.68523631305423327f64
    w7[18usize] = 0.03705512854024005f64
    y7[18usize] = 0.64896547125465731f64
    w7[19usize] = 0.03855015317861563f64
    y7[19usize] = 0.61115535517239328f64
    w7[20usize] = 0.03995374113272034f64
    y7[20usize] = 0.57189564620263400f64
    w7[21usize] = 0.04126256324262353f64
    y7[21usize] = 0.53127946401989457f64
    w7[22usize] = 0.04247351512365359f64
    y7[22usize] = 0.48940314570705296f64
    w7[23usize] = 0.04358372452932345f64
    y7[23usize] = 0.44636601725346409f64
    w7[24usize] = 0.04459055816375657f64
    y7[24usize] = 0.40227015796399163f64
    w7[25usize] = 0.04549162792741814f64
    y7[25usize] = 0.35722015833766813f64
    w7[26usize] = 0.04628479658131442f64
    y7[26usize] = 0.31132287199021097f64
    w7[27usize] = 0.04696818281621002f64
    y7[27usize] = 0.26468716220876742f64
    w7[28usize] = 0.04754016571483031f64
    y7[28usize] = 0.21742364374000708f64
    w7[29usize] = 0.04799938859645831f64
    y7[29usize] = 0.16964442042399283f64
    w7[30usize] = 0.04834476223480295f64
    y7[30usize] = 0.12146281929612056f64
    w7[31usize] = 0.04857546744150343f64
    y7[31usize] = 0.07299312178779904f64
    w7[32usize] = 0.04869095700913972f64
    y7[32usize] = 0.02435029266342443f64
    ret (s, ok)
}

fn shell(x: []f64, n: usize) {
    var gap = n / 2usize
    while gap > 0usize {
        var i = gap
        while i < n {
            let t = x[i]
            var j = i
            while j >= gap && x[j - gap] > t {
                x[j] = x[j - gap]
                j = j - gap
            }
            x[j] = t
            i += 1usize
        }
        gap = gap / 2usize
    }
}

fn nunique_sorted(x: []f64, n: usize) -> i64 {
    var c = 1i64
    var i = 1usize
    while i < n {
        if x[i] != x[i - 1usize] { c += 1i64 }
        i += 1usize
    }
    ret c
}

type Run = struct { done: bool, sorc: []i64, bound: []f64, nk: i64, yknots: []f64, ycoef: []f64, logl: []f64 }

fn run_c(a: *mem.Arena, sample: []const f64, nsamp: []const i64, xbound: []const f64, auto: i64, del: i64, nknots: i64, kts: []const f64, alpha: f64, sorc16: i64) -> (Run, err) {
    var r: Run = zero
    let nsv = sample.len + 4usize
    let (s, e0) = newst(a, nsv)
    if e0 != ok { ret (r, e0) }
    var st = s
    var i = 0usize
    while i < sample.len {
        st.sample[i] = sample[i]
        i += 1usize
    }
    i = 0usize
    while i < 6usize {
        st.ns[i] = nsamp[i]
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        st.bound[i] = xbound[i]
        i += 1usize
    }
    st.sorc[0usize] = 1i64
    st.sorc[16usize] = sorc16
    let (yk, e1) = zf(a, 64usize)
    let (yc, e2) = zf(a, 64usize)
    let (lg, e3) = zf(a, 64usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (r, mem.Full) }
    i = 0usize
    while i < kts.len && i < 64usize {
        yk[i] = kts[i]
        i += 1usize
    }
    let nkout = logcensor(&st, del, auto, alpha, nknots, yk, yc, lg)
    r.done = true
    r.sorc = st.sorc
    r.bound = st.bound
    r.nk = nkout
    r.yknots = yk
    r.ycoef = yc
    r.logl = lg
    ret (r, ok)
}

// oldlogspline(uncensored, right, left, interval, lbound, ubound, nknots, knots, penalty, delete): interval holds
// lower, upper pairs; hasl/hasu say whether lbound/ubound were given; nknots_arg < 0 means missing; ukn = user knots
// (empty when missing); penalty < 0 means the default log(n). code != 0 is an R error() of the wrapper.
fn oldlogspline_fit(a: *mem.Arena, unc: []const f64, right: []const f64, left: []const f64, interval: []const f64, hasl: bool, lbound: f64, hasu: bool, ubound: f64, nknots_arg: i64, ukn: []const f64, penalty_arg: f64, del: bool) -> (OldFit, err) {
    var fit: OldFit = zero
    let nu = unc.len
    let nint = interval.len / 2usize
    let nr = right.len
    let nl = left.len
    let total = nu + nint + nr + nl
    let (sm, e0) = zf(a, nu + 2usize * nint + nr + nl + 1usize)
    if e0 != ok { ret (fit, e0) }
    var nsv: [6]i64 = zero
    var p = 0usize
    var i = 0usize
    // interval data (clipped at the bounds), then the uncensored, right and left in the order the wrapper puts them
    let (iv, e1) = zf(a, interval.len + 1usize)
    if e1 != ok { ret (fit, e1) }
    i = 0usize
    while i < nint {
        iv[2usize * i] = interval[2usize * i]
        iv[2usize * i + 1usize] = interval[2usize * i + 1usize]
        if hasl && iv[2usize * i] < lbound { iv[2usize * i] = lbound }
        if hasu && iv[2usize * i + 1usize] > ubound { iv[2usize * i + 1usize] = ubound }
        i += 1usize
    }
    i = 0usize
    while i < nu {
        sm[p] = unc[i]
        p += 1usize
        i += 1usize
    }
    i = 0usize
    while i < 2usize * nint {
        sm[p] = iv[i]
        p += 1usize
        i += 1usize
    }
    i = 0usize
    while i < nr {
        sm[p] = right[i]
        p += 1usize
        i += 1usize
    }
    i = 0usize
    while i < nl {
        sm[p] = left[i]
        p += 1usize
        i += 1usize
    }
    nsv[0usize] = i64(total)
    nsv[1usize] = i64(nu)
    nsv[2usize] = i64(nint)
    nsv[3usize] = i64(nr)
    nsv[4usize] = i64(nl)
    var nun = 0i64
    if nint > 0usize {
        // distinct (lower, upper) pairs
        let (lo, e2) = zf(a, nint + 1usize)
        let (hi, e3) = zf(a, nint + 1usize)
        if e2 != ok || e3 != ok { ret (fit, mem.Full) }
        i = 0usize
        while i < nint {
            lo[i] = iv[2usize * i]
            hi[i] = iv[2usize * i + 1usize]
            i += 1usize
        }
        // insertion sort on (lo, hi)
        i = 1usize
        while i < nint {
            let tl = lo[i]
            let th = hi[i]
            var j = i
            while j > 0usize && (lo[j - 1usize] > tl || (lo[j - 1usize] == tl && hi[j - 1usize] > th)) {
                lo[j] = lo[j - 1usize]
                hi[j] = hi[j - 1usize]
                j -= 1usize
            }
            lo[j] = tl
            hi[j] = th
            i += 1usize
        }
        nun = 1i64
        i = 1usize
        while i < nint {
            if lo[i] != lo[i - 1usize] || hi[i] != hi[i - 1usize] { nun += 1i64 }
            i += 1usize
        }
    }
    if nu > 0usize {
        let (t, e4) = zf(a, nu + 1usize)
        if e4 != ok { ret (fit, e4) }
        i = 0usize
        while i < nu {
            t[i] = unc[i]
            i += 1usize
        }
        shell(t, nu)
        nun = nun + nunique_sorted(t, nu)
    }
    if nr > 0usize {
        let (t, e5) = zf(a, nr + 1usize)
        if e5 != ok { ret (fit, e5) }
        i = 0usize
        while i < nr {
            t[i] = right[i]
            i += 1usize
        }
        shell(t, nr)
        nun = nun + nunique_sorted(t, nr)
    }
    if nl > 0usize {
        let (t, e6) = zf(a, nl + 1usize)
        if e6 != ok { ret (fit, e6) }
        i = 0usize
        while i < nl {
            t[i] = left[i]
            i += 1usize
        }
        shell(t, nl)
        nun = nun + nunique_sorted(t, nl)
    }
    if total == 0usize || nu + nint == 0usize {
        fit.code = 5i64
        ret (fit, ok)
    }
    let n = nu + 2usize * nint + nr + nl
    let (srt, e7) = zf(a, n + 1usize)
    if e7 != ok { ret (fit, e7) }
    i = 0usize
    while i < n {
        srt[i] = sm[i]
        i += 1usize
    }
    shell(srt, n)
    let nuniq = nunique_sorted(srt, n)
    if nuniq < 3i64 {
        fit.code = 5i64
        ret (fit, ok)
    }
    let smin = srt[0usize]
    let smax = srt[n - 1usize]
    var penalty = penalty_arg
    if penalty < 0.0f64 { penalty = math.log[f64](f64(total)) }
    var xb: [5]f64 = zero
    xb[0usize] = 1.0f64
    if hasl {
        xb[1usize] = 1.0f64
        xb[2usize] = lbound
        if lbound > smin {
            fit.code = 5i64
            ret (fit, ok)
        }
    }
    if hasu {
        xb[3usize] = 1.0f64
        xb[4usize] = ubound
        if ubound < smax {
            fit.code = 5i64
            ret (fit, ok)
        }
    }
    var autok = 1i64
    var nknots = 0i64
    let (kts, e8) = zf(a, 64usize)
    if e8 != ok { ret (fit, e8) }
    if ukn.len > 0usize {
        nknots = i64(ukn.len)
        autok = 0i64
        i = 0usize
        while i < ukn.len {
            kts[i] = ukn[i]
            i += 1usize
        }
        shell(kts, ukn.len)
        if kts[0usize] > smin || kts[ukn.len - 1usize] < smax {
            fit.code = 5i64
            ret (fit, ok)
        }
    } else {
        if nknots_arg >= 0i64 { nknots = nknots_arg }
    }
    nsv[5usize] = nun - 1i64
    var dlt = 0i64
    if del { dlt = 1i64 }
    let (r1, e9) = run_c(a, sm[0usize..n], nsv[0usize..6usize], xb[0usize..5usize], autok, dlt, nknots, kts, penalty, 0i64)
    if e9 != ok { ret (fit, e9) }
    var rr = r1
    if rr.sorc[0usize] == 0i64 - 1i64 && rr.sorc[27usize] == 0i64 && nsv[0usize] != nsv[1usize] && nsv[1usize] > 15i64 {
        let (r2, e10) = run_c(a, sm[0usize..n], nsv[0usize..6usize], xb[0usize..5usize], autok, dlt, nknots, kts, penalty, 1i64)
        if e10 != ok { ret (fit, e10) }
        rr = r2
    }
    var so0 = rr.sorc[0usize]
    var absso = so0
    if absso < 0i64 { absso = 0i64 - absso }
    if absso > 2i64 {
        if so0 < 0i64 { so0 = 0i64 - 1i64 }
        if so0 == 23i64 { so0 = 0i64 - 3i64 }
    }
    absso = so0
    if absso < 0i64 { absso = 0i64 - absso }
    if absso > 3i64 { so0 = 1i64 }
    rr.sorc[0usize] = so0
    fit.sorc = rr.sorc
    if so0 == 0i64 - 3i64 {
        fit.code = 4i64
        ret (fit, ok)
    }
    if so0 == 0i64 - 1i64 && rr.sorc[27usize] == 0i64 {
        fit.code = 1i64
        ret (fit, ok)
    }
    if so0 == 2i64 {
        fit.code = 2i64
        ret (fit, ok)
    }
    if so0 == 0i64 - 2i64 {
        fit.code = 3i64
        ret (fit, ok)
    }
    var dflag = dlt
    if del && rr.sorc[27usize] > 0i64 { dflag = 3i64 }
    let nk = rr.nk
    let (cf, e11) = zf(a, u(nk) + 2usize)
    let (kk, e12) = zf(a, u(nk))
    let (bb, e13) = zf(a, 4usize)
    if e11 != ok || e12 != ok || e13 != ok { ret (fit, mem.Full) }
    i = 0usize
    while i < u(nk) + 2usize {
        cf[i] = rr.ycoef[i]
        i += 1usize
    }
    i = 0usize
    while i < u(nk) {
        kk[i] = rr.yknots[i]
        i += 1usize
    }
    bb[0usize] = rr.bound[1usize]
    bb[1usize] = rr.bound[2usize]
    bb[2usize] = rr.bound[3usize]
    bb[3usize] = rr.bound[4usize]
    var nl2 = 1usize
    var lo = 0usize
    if dflag != 0i64 {
        lo = 2usize
        nl2 = u(nk) - 2usize
    }
    let (lg, e14) = zf(a, nl2)
    if e14 != ok { ret (fit, e14) }
    i = 0usize
    while i < nl2 {
        lg[i] = rr.logl[lo + i]
        i += 1usize
    }
    fit.code = 0i64
    fit.nk = nk
    fit.coef = cf
    fit.knots = kk
    fit.bound = bb
    fit.logl = lg
    fit.penalty = penalty
    fit.sample = i64(total)
    fit.delete = dflag
    ret (fit, ok)
}
