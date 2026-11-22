// R nleqslv: Newton and Broyden iterations with the global strategies none, cline, qline, gline, dbldog and pwldog, ported from the package's Fortran (nwnleq, nwsolv, brsolv,
// nwclsh, nwqlsh, nwglsh, nwddlg, nwpdlg, nwtrup, brupdt, liqrup) over the LAPACK and BLAS reference steps it calls (dgeqr2, dorm2r, dorg2r, dtrcon with dlacn2, dlartg).
// Termination codes 1 to 7, iteration, function and Jacobian counts are the package's. The Jacobian is the forward difference nleqslv takes (numerical only), with
// xscalm "fixed" or "auto" and allowSingular. Not here: the hook strategy, a supplied Jacobian, a banded Jacobian, jacobian = TRUE, chkjac, trace output.
// The equations are a fixed set of test systems (nleqslvpkg.system plus five more), written with products only so R's x^2 and Neper agree to the bit.

use e.algo.stat.nleqslvpkg as base
use e.math
use e.mem

type Ws = struct {
    sys: usize, n: usize,
    xc: []f64, fc: []f64, xp: []f64, fp: []f64, gp: []f64, dn: []f64, d: []f64, qtf: []f64, fq: []f64,
    w1: []f64, w2: []f64, w3: []f64, w4: []f64, xw: []f64, sx: []f64,
    jac: []f64, rr: []f64, tau: []f64, sd: []f64, wk: []f64, vv: []f64, tx: []f64, tv: []f64, ti: []f64,
    delta: f64, info: []f64
}

fn dim_of(sys: usize) -> usize {
    if sys == 5usize { ret 4usize }
    if sys == 7usize || sys == 11usize { ret 3usize }
    if sys < 5usize { ret base.dim_of(sys) }
    ret 2usize
}

// the equations of system sys: 0 to 4 are nleqslvpkg's; 5 Powell singular, 6 a linear pair with a singular Jacobian, 7 Brown almost linear, 8 Rosenbrock residuals, 10 circle and hyperbola, 11 a three-variable polynomial triple, 12 a rational pair, any other id Freudenstein-Roth
fn eqs(sys: usize, x: []const f64, out: []f64) {
    if sys < 5usize {
        base.system(sys, x, out)
    } else if sys == 5usize {
        let t = x[1usize] - 2.0f64 * x[2usize]
        let u = x[0usize] - x[3usize]
        out[0usize] = x[0usize] + 10.0f64 * x[1usize]
        out[1usize] = math.sqrt[f64](5.0f64) * (x[2usize] - x[3usize])
        out[2usize] = t * t
        out[3usize] = math.sqrt[f64](10.0f64) * (u * u)
    } else if sys == 6usize {
        out[0usize] = x[0usize] + x[1usize] - 1.0f64
        out[1usize] = 2.0f64 * x[0usize] + 2.0f64 * x[1usize] - 2.0f64
    } else if sys == 7usize {
        let s = x[0usize] + x[1usize] + x[2usize]
        out[0usize] = x[0usize] + s - 4.0f64
        out[1usize] = x[1usize] + s - 4.0f64
        out[2usize] = x[0usize] * x[1usize] * x[2usize] - 1.0f64
    } else if sys == 8usize {
        out[0usize] = 10.0f64 * (x[1usize] - x[0usize] * x[0usize])
        out[1usize] = 1.0f64 - x[0usize]
    } else if sys == 10usize {
        out[0usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] - 4.0f64
        out[1usize] = x[0usize] * x[1usize] - 1.0f64
    } else if sys == 11usize {
        out[0usize] = x[0usize] + x[1usize] + x[2usize] - 3.0f64
        out[1usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize] - 5.0f64
        out[2usize] = x[0usize] * x[1usize] * x[2usize] - 1.0f64
    } else if sys == 13usize {
        out[0usize] = 1.0f64
        out[1usize] = 2.0f64
    } else if sys == 12usize {
        out[0usize] = 1.0f64 / (1.0f64 + x[0usize] * x[0usize]) + x[1usize] - 1.5f64
        out[1usize] = x[0usize] * x[1usize] - 0.5f64 - x[1usize] * x[1usize]
    } else {
        out[0usize] = 0.0f64 - 13.0f64 + x[0usize] + ((5.0f64 - x[1usize]) * x[1usize] - 2.0f64) * x[1usize]
        out[1usize] = 0.0f64 - 29.0f64 + x[0usize] + ((x[1usize] + 1.0f64) * x[1usize] - 14.0f64) * x[1usize]
    }
}

fn fsign(a: f64, b: f64) -> f64 {
    if b >= 0.0f64 { ret math.abs[f64](a) }
    ret 0.0f64 - math.abs[f64](a)
}

fn nrm2(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * v[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

fn ddot(a: []const f64, b: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += a[i] * b[i]
        i += 1usize
    }
    ret s
}

fn asum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += math.abs[f64](v[i])
        i += 1usize
    }
    ret s
}

fn idamax(v: []const f64, n: usize) -> usize {
    var at = 0usize
    var m = math.abs[f64](v[0usize])
    var i = 1usize
    while i < n {
        if math.abs[f64](v[i]) > m {
            m = math.abs[f64](v[i])
            at = i
        }
        i += 1usize
    }
    ret at
}

fn copy(src: []const f64, dst: []f64, n: usize) {
    var i = 0usize
    while i < n {
        dst[i] = src[i]
        i += 1usize
    }
}

// dlartg (LAPACK 3.10): c, s, r with [c s; -s c] [f; g] = [r; 0]
fn lartg(f: f64, g: f64) -> (f64, f64, f64) {
    if g == 0.0f64 { ret (1.0f64, 0.0f64, f) }
    if f == 0.0f64 { ret (0.0f64, fsign(1.0f64, g), math.abs[f64](g)) }
    let d = math.sqrt[f64](f * f + g * g)
    let c = math.abs[f64](f) / d
    let r = fsign(d, f)
    ret (c, g / r, r)
}

// dtrmv upper, no transpose: x = R x
fn trmv_un(r: []const f64, n: usize, x: []f64) {
    var j = 0usize
    while j < n {
        if x[j] != 0.0f64 {
            let temp = x[j]
            var i = 0usize
            while i < j {
                x[i] = x[i] + temp * r[i + j * n]
                i += 1usize
            }
            x[j] = x[j] * r[j + j * n]
        }
        j += 1usize
    }
}

// dtrmv upper, transpose: x = R' x
fn trmv_ut(r: []const f64, n: usize, x: []f64) {
    var jj = n
    while jj > 0usize {
        let j = jj - 1usize
        var temp = x[j] * r[j + j * n]
        var ii = j
        while ii > 0usize {
            let i = ii - 1usize
            temp += r[i + j * n] * x[i]
            ii -= 1usize
        }
        x[j] = temp
        jj -= 1usize
    }
}

// dtrsv upper, no transpose: x = R^-1 x
fn trsv_un(r: []const f64, n: usize, x: []f64) {
    var jj = n
    while jj > 0usize {
        let j = jj - 1usize
        if x[j] != 0.0f64 {
            x[j] = x[j] / r[j + j * n]
            let temp = x[j]
            var ii = j
            while ii > 0usize {
                let i = ii - 1usize
                x[i] = x[i] - temp * r[i + j * n]
                ii -= 1usize
            }
        }
        jj -= 1usize
    }
}

// dtrsv upper, transpose: x = R'^-1 x
fn trsv_ut(r: []const f64, n: usize, x: []f64) {
    var j = 0usize
    while j < n {
        var temp = x[j]
        var i = 0usize
        while i < j {
            temp = temp - r[i + j * n] * x[i]
            i += 1usize
        }
        x[j] = temp / r[j + j * n]
        j += 1usize
    }
}

// H = I - tau v v' on rows row0.. of columns col0 to col1 - 1 of the column-major n by n matrix c; v (length n - row0) has v[0] = 1
fn apply_h(c: []f64, n: usize, row0: usize, v: []const f64, tau: f64, col0: usize, col1: usize) {
    let m = n - row0
    var j = col0
    while j < col1 {
        var tail = 0.0f64
        var k = 1usize
        while k < m {
            tail += c[row0 + k + j * n] * v[k]
            k += 1usize
        }
        let w = c[row0 + j * n] + tail
        let temp = 0.0f64 - tau * w
        c[row0 + j * n] = c[row0 + j * n] + temp
        k = 1usize
        while k < m {
            c[row0 + k + j * n] = c[row0 + k + j * n] + v[k] * temp
            k += 1usize
        }
        j += 1usize
    }
}

// dgeqr2 on the n by n matrix a: R in the upper triangle, the Householder vectors below, tau
fn geqr2(a: []f64, n: usize, tau: []f64, vv: []f64) {
    var i = 0usize
    while i < n {
        let m = n - i
        var alpha = a[i + i * n]
        var s = 0.0f64
        var k = i + 1usize
        while k < n {
            s += a[k + i * n] * a[k + i * n]
            k += 1usize
        }
        let xn = math.sqrt[f64](s)
        if m <= 1usize || xn == 0.0f64 {
            tau[i] = 0.0f64
        } else {
            var w = math.abs[f64](alpha)
            var z = xn
            if xn > w {
                w = xn
                z = math.abs[f64](alpha)
            }
            var hyp = w
            if z != 0.0f64 { hyp = w * math.sqrt[f64](1.0f64 + (z / w) * (z / w)) }
            let beta = 0.0f64 - fsign(hyp, alpha)
            tau[i] = (beta - alpha) / beta
            let scale = 1.0f64 / (alpha - beta)
            k = i + 1usize
            while k < n {
                a[k + i * n] = a[k + i * n] * scale
                k += 1usize
            }
            alpha = beta
        }
        a[i + i * n] = alpha
        if i + 1usize < n {
            vv[0usize] = 1.0f64
            k = i + 1usize
            while k < n {
                vv[k - i] = a[k + i * n]
                k += 1usize
            }
            apply_h(a, n, i, vv, tau[i], i + 1usize, n)
        }
        i += 1usize
    }
}

// dorm2r left, transpose, one column: y = Q' y
fn qt_apply(a: []const f64, n: usize, tau: []const f64, y: []f64, vv: []f64) {
    var i = 0usize
    while i < n {
        let m = n - i
        vv[0usize] = 1.0f64
        var k = 1usize
        while k < m {
            vv[k] = a[i + k + i * n]
            k += 1usize
        }
        var tail = 0.0f64
        k = 1usize
        while k < m {
            tail += y[i + k] * vv[k]
            k += 1usize
        }
        let wsum = y[i] + tail
        let temp = 0.0f64 - tau[i] * wsum
        y[i] = y[i] + temp
        k = 1usize
        while k < m {
            y[i + k] = y[i + k] + vv[k] * temp
            k += 1usize
        }
        i += 1usize
    }
}

// dorg2r: overwrite a (QR form) with Q
fn orgqr(a: []f64, n: usize, tau: []const f64, vv: []f64) {
    var ii = n
    while ii > 0usize {
        let i = ii - 1usize
        if i + 1usize < n {
            a[i + i * n] = 1.0f64
            let m = n - i
            var k = 0usize
            while k < m {
                vv[k] = a[i + k + i * n]
                k += 1usize
            }
            apply_h(a, n, i, vv, tau[i], i + 1usize, n)
            k = i + 1usize
            while k < n {
                a[k + i * n] = a[k + i * n] * (0.0f64 - tau[i])
                k += 1usize
            }
        }
        a[i + i * n] = 1.0f64 - tau[i]
        var l = 0usize
        while l < i {
            a[l + i * n] = 0.0f64
            l += 1usize
        }
        ii -= 1usize
    }
}

fn sgn1(v: f64) -> f64 {
    if v >= 0.0f64 { ret 1.0f64 }
    ret 0.0f64 - 1.0f64
}

// dtrcon (1-norm) for the upper triangle r, with dlacn2's estimate of the norm of the inverse; x, v are scratch of n, isg of n
fn trcon(r: []const f64, n: usize, x: []f64, isg: []f64) -> f64 {
    var anorm = 0.0f64
    var j = 0usize
    while j < n {
        var s = 0.0f64
        var i = 0usize
        while i <= j {
            s += math.abs[f64](r[i + j * n])
            i += 1usize
        }
        if s > anorm { anorm = s }
        j += 1usize
    }
    if !(anorm > 0.0f64) { ret 0.0f64 }
    var i0 = 0usize
    while i0 < n {
        x[i0] = 1.0f64 / f64(n)
        i0 += 1usize
    }
    trsv_un(r, n, x)
    var est = 0.0f64
    if n == 1usize {
        est = math.abs[f64](x[0usize])
        ret (1.0f64 / anorm) / est
    }
    est = asum(x, n)
    i0 = 0usize
    while i0 < n {
        isg[i0] = sgn1(x[i0])
        x[i0] = isg[i0]
        i0 += 1usize
    }
    trsv_ut(r, n, x)
    var jj = idamax(x, n)
    var it = 2usize
    var go = true
    while go {
        i0 = 0usize
        while i0 < n {
            x[i0] = 0.0f64
            i0 += 1usize
        }
        x[jj] = 1.0f64
        trsv_un(r, n, x)
        let estold = est
        est = asum(x, n)
        var same = true
        i0 = 0usize
        while i0 < n {
            if sgn1(x[i0]) != isg[i0] { same = false }
            i0 += 1usize
        }
        if same || est <= estold { break }
        i0 = 0usize
        while i0 < n {
            isg[i0] = sgn1(x[i0])
            x[i0] = isg[i0]
            i0 += 1usize
        }
        trsv_ut(r, n, x)
        let jlast = jj
        jj = idamax(x, n)
        if x[jlast] != math.abs[f64](x[jj]) && it < 5usize {
            it += 1usize
        } else {
            go = false
        }
    }
    var alt = 1.0f64
    i0 = 0usize
    while i0 < n {
        x[i0] = alt * (1.0f64 + f64(i0) / f64(n - 1usize))
        alt = 0.0f64 - alt
        i0 += 1usize
    }
    trsv_un(r, n, x)
    let temp = 2.0f64 * (asum(x, n) / f64(3usize * n))
    if temp > est { est = temp }
    ret (1.0f64 / anorm) / est
}

// the machine constants dlamch gives: 'P' precision and 'E' epsilon
fn epsp() -> f64 { ret 2.220446049250313e-16f64 }
fn epse() -> f64 { ret 1.1102230246251565e-16f64 }
fn bigv() -> f64 { ret 1.7976931348623157e308f64 }

// nwfvec: the function at the scaled x, and half its squared 2-norm
fn nwfvec(w: *Ws, x: []const f64, f: []f64) -> f64 {
    var i = 0usize
    while i < w.n {
        w.xw[i] = x[i] / w.sx[i]
        i += 1usize
    }
    eqs(w.sys, w.xw, f)
    let r = nrm2(f, w.n)
    ret 0.5f64 * (r * r)
}

// nwfjac and fdjac0: the forward-difference Jacobian at the scaled x (column-major into w.jac)
fn nwfjac(w: *Ws, x: []const f64, f: []const f64) {
    let n = w.n
    let epsm = epsp()
    let ndigit = 0.0f64 - math.log10[f64](epsm)
    let pw = math.pow[f64](10.0f64, 0.0f64 - ndigit)
    var pm = pw
    if epsm > pm { pm = epsm }
    let p = math.sqrt[f64](pm)
    var i = 0usize
    while i < n {
        w.xw[i] = x[i] / w.sx[i]
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var h = p + p * math.abs[f64](w.xw[j])
        let xcj = w.xw[j]
        w.xw[j] = xcj + h
        h = w.xw[j] - xcj
        eqs(w.sys, w.xw, w.fq)
        w.xw[j] = xcj
        i = 0usize
        while i < n {
            w.jac[i + j * n] = (w.fq[i] - f[i]) / h
            i += 1usize
        }
        j += 1usize
    }
}

fn nudnrm(d: []const f64, x: []const f64, n: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        var m = math.abs[f64](x[i])
        if m < 1.0f64 { m = 1.0f64 }
        let q = math.abs[f64](d[i]) / m
        if q > t { t = q }
        i += 1usize
    }
    ret t
}

fn nuxnrm(xn: []const f64, xc: []const f64, n: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        var m = math.abs[f64](xn[i])
        if m < 1.0f64 { m = 1.0f64 }
        let q = math.abs[f64](xn[i] - xc[i]) / m
        if q > t { t = q }
        i += 1usize
    }
    ret t
}

// liqrev: the step of the regularised system (R; mu I) x = (b; 0) by Givens rotations; r is overwritten and restored as lirslv does
fn liqrev(w: *Ws, r: []f64, mu: f64, b: []const f64, x: []f64) {
    let n = w.n
    var j = 0usize
    while j < n {
        var i = 0usize
        while j + i < n {
            r[j + i + j * n] = r[j + (j + i) * n]
            i += 1usize
        }
        w.wk[j] = r[j + j * n]
        j += 1usize
    }
    copy(b, x, n)
    var jj = n
    while jj > 0usize {
        let jx = jj - 1usize
        var q = jx
        while q < n {
            w.sd[q] = 0.0f64
            q += 1usize
        }
        w.sd[jx] = mu
        var bj = 0.0f64
        var k = jx
        while k < n {
            if w.sd[k] != 0.0f64 {
                let (c, s, t) = lartg(r[k + k * n], w.sd[k])
                r[k + k * n] = t
                w.sd[k] = 0.0f64
                var m = k + 1usize
                while m < n {
                    let tmp = c * r[m + k * n] + s * w.sd[m]
                    w.sd[m] = c * w.sd[m] - s * r[m + k * n]
                    r[m + k * n] = tmp
                    m += 1usize
                }
                let temp = c * x[k] + s * bj
                bj = (0.0f64 - s) * x[k] + c * bj
                x[k] = temp
            }
            k += 1usize
        }
        jj -= 1usize
    }
    var k2 = 0usize
    while k2 < n {
        w.sd[k2] = r[k2 + k2 * n]
        r[k2 + k2 * n] = w.wk[k2]
        k2 += 1usize
    }
    x[n - 1usize] = x[n - 1usize] / w.sd[n - 1usize]
    var j2 = n - 1usize
    while j2 > 0usize {
        let jx = j2 - 1usize
        var sum = 0.0f64
        var m = jx + 1usize
        while m < n {
            sum += r[m + jx * n] * x[m]
            m += 1usize
        }
        x[jx] = (x[jx] - sum) / w.sd[jx]
        j2 -= 1usize
    }
}

// lirslv with cndjac and compmu: the Newton step dn from R and Q'f (qtf); returns ierr (0 fine, 1 ill-conditioned, 2 singular, 3 unusable)
fn lirslv(w: *Ws, r: []f64, cndtol: f64, stepadj: bool) -> usize {
    let n = w.n
    var ierr = 0usize
    var rsing = false
    var i = 0usize
    while i < n {
        if r[i + i * n] == 0.0f64 { rsing = true }
        i += 1usize
    }
    if rsing {
        ierr = 2usize
    } else {
        let rcond = trcon(r, n, w.tx, w.ti)
        if rcond == 0.0f64 {
            ierr = 2usize
        } else if rcond <= cndtol {
            ierr = 1usize
        }
    }
    if ierr == 0usize {
        copy(w.qtf, w.dn, n)
        trsv_un(r, n, w.dn)
        i = 0usize
        while i < n {
            w.dn[i] = 0.0f64 - w.dn[i]
            i += 1usize
        }
    } else if stepadj {
        var ainf = 0.0f64
        var a1 = 0.0f64
        i = 0usize
        while i < n {
            var rs = 0.0f64
            var k = i
            while k < n {
                rs += math.abs[f64](r[i + k * n])
                k += 1usize
            }
            if rs > ainf { ainf = rs }
            i += 1usize
        }
        var jc = 0usize
        while jc < n {
            var cs = 0.0f64
            var q = 0usize
            while q <= jc {
                cs += math.abs[f64](r[q + jc * n])
                q += 1usize
            }
            if cs > a1 { a1 = cs }
            jc += 1usize
        }
        let mu = math.sqrt[f64](f64(n) * epsp() * 100.0f64) * ainf * a1
        ierr = 0usize
        if mu <= 100.0f64 * epsp() { ierr = 3usize }
        if ierr == 0usize {
            liqrev(w, r, mu, w.qtf, w.dn)
            i = 0usize
            while i < n {
                w.dn[i] = 0.0f64 - w.dn[i]
                i += 1usize
            }
            var k3 = 0usize
            while k3 < n {
                var m = 0usize
                while k3 + m < n {
                    r[k3 + (k3 + m) * n] = r[k3 + m + k3 * n]
                    m += 1usize
                }
                r[k3 + k3 * n] = w.sd[k3]
                k3 += 1usize
            }
        }
    }
    ret ierr
}

// nwtcvg: the termination code after a step
fn nwtcvg(w: *Ws, xplus: []const f64, fplus: []const f64, xc: []const f64, xtol: f64, retcd: usize, ftol: f64, iter: usize, maxit: usize, ierr: usize) -> usize {
    if ierr != 0usize { ret 4usize + ierr }
    let fmax = math.abs[f64](fplus[idamax(fplus, w.n)])
    if fmax <= ftol { ret 1usize }
    if iter == 0usize { ret 0usize }
    if retcd == 1usize { ret 3usize }
    let rsx = nuxnrm(xplus, xc, w.n)
    if rsx <= xtol { ret 2usize }
    if iter >= maxit { ret 4usize }
    ret 0usize
}

// the line searches nwclsh (kind 1), nwqlsh (2), nwglsh (3) and the pure step nwpure (0): returns (retcd, gcnt, fpnorm), writes xp and fp
fn lsearch(w: *Ws, kind: usize, fcnorm: f64, stepmx: f64, xtol: f64, sigma: f64) -> (usize, usize, f64) {
    let n = w.n
    let dlen = nrm2(w.dn, n)
    var lamhi = 1.0f64
    if dlen > stepmx { lamhi = stepmx / dlen }
    var fpnorm = 0.0f64
    var i = 0usize
    if kind == 0usize {
        while i < n {
            w.xp[i] = w.xc[i] + lamhi * w.dn[i]
            i += 1usize
        }
        fpnorm = nwfvec(w, w.xp, w.fp)
        ret (0usize, 1usize, fpnorm)
    }
    let alpha = 1.0e-4f64
    let slope = ddot(w.gp, w.dn, n)
    let rsclen = nudnrm(w.dn, w.xc, n)
    let lamlo = xtol / rsclen
    var retcd = 2usize
    var lambda = lamhi
    var gcnt = 0usize
    var firstback = true
    var lambda0 = 0.0f64
    var fpnorm0 = 0.0f64
    while retcd == 2usize {
        i = 0usize
        while i < n {
            w.xp[i] = w.xc[i] + lambda * w.dn[i]
            i += 1usize
        }
        fpnorm = nwfvec(w, w.xp, w.fp)
        gcnt += 1usize
        let ftarg = fcnorm + alpha * lambda * slope
        if fpnorm <= ftarg {
            retcd = 0usize
        } else if kind == 3usize {
            lambda = sigma * lambda
            if lambda < lamlo { retcd = 1usize }
        } else if kind == 2usize {
            let t = ((0.0f64 - lambda * lambda) * slope / 2.0f64) / (fpnorm - fcnorm - lambda * slope)
            lambda = math.max[f64](lambda / 10.0f64, t)
            if lambda < lamlo { retcd = 1usize }
        } else {
            if fpnorm > lamlo * lamlo * math.sqrt[f64](bigv()) {
                lambda = lambda / 10.0f64
                firstback = true
            } else {
                var t = 0.0f64
                if firstback {
                    t = ((0.0f64 - lambda * lambda) * slope / 2.0f64) / (fpnorm - fcnorm - lambda * slope)
                    firstback = false
                } else {
                    let fpt = fpnorm - fcnorm - lambda * slope
                    let fpt0 = fpnorm0 - fcnorm - lambda0 * slope
                    var a = fpt / (lambda * lambda) - fpt0 / (lambda0 * lambda0)
                    var b = (0.0f64 - lambda0) * fpt / (lambda * lambda) + lambda * fpt0 / (lambda0 * lambda0)
                    a = a / (lambda - lambda0)
                    b = b / (lambda - lambda0)
                    if math.abs[f64](a) <= epse() {
                        t = (0.0f64 - slope) / (2.0f64 * b)
                    } else {
                        let disc = math.max[f64](b * b - 3.0f64 * a * slope, 0.0f64)
                        let t1 = (0.0f64 - (b + fsign(1.0f64, b) * math.sqrt[f64](disc))) / (3.0f64 * a)
                        let t2 = slope / (3.0f64 * a) / t1
                        if a > 0.0f64 {
                            t = math.max[f64](t1, t2)
                        } else {
                            t = math.min[f64](t1, t2)
                        }
                    }
                    t = math.min[f64](t, 0.5f64 * lambda)
                }
                lambda0 = lambda
                fpnorm0 = fpnorm
                lambda = math.max[f64](t, lambda / 10.0f64)
                if lambda < lamlo { retcd = 1usize }
            }
        }
    }
    ret (retcd, gcnt, fpnorm)
}

// nwddlg (pw false) and nwpdlg (pw true): the double dogleg and the powell dogleg trust-region step with nwtrup's radius update; r is the upper triangular factor
fn dogleg(w: *Ws, pw: bool, r: []const f64, fcnorm: f64, stepmx: f64, xtol: f64) -> (usize, usize, f64) {
    let n = w.n
    let dnlen = nrm2(w.dn, n)
    let sqalpha = nrm2(w.gp, n)
    let alpha = sqalpha * sqalpha
    copy(w.gp, w.d, n)
    trmv_un(r, n, w.d)
    let bn = nrm2(w.d, n)
    let beta = bn * bn
    var i = 0usize
    while i < n {
        w.w1[i] = w.gp[i] * (0.0f64 - alpha / beta)
        i += 1usize
    }
    let ssdlen = alpha * sqalpha / beta
    if w.delta == 0.0f64 - 1.0f64 {
        w.delta = math.min[f64](ssdlen, stepmx)
    } else if w.delta == 0.0f64 - 2.0f64 {
        w.delta = math.min[f64](dnlen, stepmx)
    }
    var eta = 1.0f64
    if !pw {
        let gamma = alpha * alpha / ((0.0f64 - beta) * ddot(w.gp, w.dn, n))
        let rp2 = 2.0f64 / 10.0f64
        eta = math.max[f64](0.0f64, math.min[f64](1.0f64, rp2 + (1.0f64 - rp2) * gamma))
    }
    var retcd = 4usize
    var gcnt = 0usize
    var fpnorm = 0.0f64
    var fpnsav = 0.0f64
    while retcd > 1usize {
        var dtype = 0usize
        var nwtstep = false
        if dnlen <= w.delta {
            copy(w.dn, w.d, n)
            w.delta = dnlen
            dtype = 4usize
        } else if !pw && eta * dnlen <= w.delta {
            copy(w.dn, w.d, n)
            let sc = w.delta / dnlen
            i = 0usize
            while i < n {
                w.d[i] = w.d[i] * sc
                i += 1usize
            }
            dtype = 3usize
        } else if ssdlen >= w.delta {
            copy(w.w1, w.d, n)
            let sc = w.delta / ssdlen
            i = 0usize
            while i < n {
                w.d[i] = w.d[i] * sc
                i += 1usize
            }
            dtype = 1usize
        } else {
            i = 0usize
            while i < n {
                if pw {
                    w.w2[i] = w.dn[i] - w.w1[i]
                } else {
                    w.w2[i] = eta * w.dn[i] - w.w1[i]
                }
                i += 1usize
            }
            let vssd = ddot(w.w2, w.w1, n)
            let vn = nrm2(w.w2, n)
            let vlen = vn * vn
            let lambda = ((0.0f64 - vssd) + math.sqrt[f64](vssd * vssd - vlen * (ssdlen * ssdlen - w.delta * w.delta))) / vlen
            copy(w.w1, w.d, n)
            i = 0usize
            while i < n {
                w.d[i] = w.d[i] + lambda * w.w2[i]
                i += 1usize
            }
            dtype = 2usize
        }
        nwtstep = dtype == 4usize
        copy(w.d, w.w3, n)
        trmv_un(r, n, w.w3)
        i = 0usize
        while i < n {
            w.w3[i] = w.w3[i] + w.qtf[i]
            i += 1usize
        }
        let wn = nrm2(w.w3, n)
        let fpred = 0.5f64 * (wn * wn)
        i = 0usize
        while i < n {
            w.xp[i] = w.xc[i] + w.d[i]
            i += 1usize
        }
        fpnorm = nwfvec(w, w.xp, w.fp)
        gcnt += 1usize
        // nwtrup
        let ared = fpnorm - fcnorm
        let pred = fpred - fcnorm
        let slope = ddot(w.gp, w.d, n)
        let tal = 1.0e-4f64
        var ret3ok = false
        if retcd == 3usize { ret3ok = fpnorm >= fpnsav || ared > tal * slope }
        if retcd == 3usize && ret3ok {
            retcd = 0usize
            copy(w.fq, w.xp, n)
            copy(w.w4, w.fp, n)
            fpnorm = fpnsav
            w.delta = 0.5f64 * w.delta
        } else if ared > tal * slope {
            let rln = nudnrm(w.d, w.xp, n)
            if rln < xtol {
                retcd = 1usize
            } else {
                retcd = 2usize
                let sclen = nrm2(w.d, n)
                let dltmp = (0.0f64 - slope) * sclen / (2.0f64 * (ared - slope))
                if dltmp < 0.1f64 * w.delta {
                    w.delta = 0.1f64 * w.delta
                } else {
                    w.delta = math.min[f64](0.5f64 * w.delta, dltmp)
                }
            }
        } else if retcd != 2usize && math.abs[f64](pred - ared) <= 0.1f64 * math.abs[f64](ared) && !nwtstep && w.delta <= (1.0f64 - 1.0f64 / 100.0f64) * stepmx {
            copy(w.xp, w.fq, n)
            copy(w.fp, w.w4, n)
            fpnsav = fpnorm
            w.delta = math.min[f64](2.0f64 * w.delta, stepmx)
            retcd = 3usize
        } else {
            retcd = 0usize
            if ared >= 0.1f64 * pred {
                w.delta = 0.5f64 * w.delta
            } else if ared <= 0.75f64 * pred {
                w.delta = math.min[f64](2.0f64 * w.delta, stepmx)
            }
        }
    }
    ret (retcd, gcnt, fpnorm)
}

// brupdt: the Broyden update of the QR factors (q in w.jac, r in w.rr) for the step xc to xp
fn brupdt(w: *Ws) {
    let n = w.n
    let eta = 100.0f64 * 2.0f64 * epsp()
    var doupdt = false
    var i = 0usize
    while i < n {
        w.w1[i] = w.xp[i] - w.xc[i]
        w.w2[i] = w.fp[i] - w.fc[i]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < n {
        var k = i + 1usize
        while k < n {
            w.rr[k + i * n] = 0.0f64
            k += 1usize
        }
        i += 1usize
    }
    copy(w.w1, w.w3, n)
    trmv_un(w.rr, n, w.w3)
    var j = 0usize
    while j < n {
        let temp = (0.0f64 - 1.0f64) * w.w3[j]
        i = 0usize
        while i < n {
            w.w2[i] = w.w2[i] + temp * w.jac[i + j * n]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        if math.abs[f64](w.w2[i]) > eta * (math.abs[f64](w.fp[i]) + math.abs[f64](w.fc[i])) {
            doupdt = true
        } else {
            w.w2[i] = 0.0f64
        }
        i += 1usize
    }
    if doupdt {
        let sts = nrm2(w.w1, n)
        let rs = 1.0f64 / sts
        i = 0usize
        while i < n {
            w.w1[i] = w.w1[i] * rs
            w.w2[i] = w.w2[i] * rs
            i += 1usize
        }
        // liqrup: Q R + u v' re-factored, u = w2, v = w1
        i = 0usize
        while i < n {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += w.jac[k + i * n] * w.w2[k]
                k += 1usize
            }
            w.w3[i] = s
            i += 1usize
        }
        var kk = n - 1usize
        while kk > 0usize {
            let k = kk - 1usize
            let (c, s, t) = lartg(w.w3[k], w.w3[k + 1usize])
            w.w3[k] = t
            w.w3[k + 1usize] = 0.0f64
            var m = k
            while m < n {
                let a = w.rr[k + m * n]
                let b = w.rr[k + 1usize + m * n]
                w.rr[k + m * n] = c * a + s * b
                w.rr[k + 1usize + m * n] = c * b - s * a
                m += 1usize
            }
            m = 0usize
            while m < n {
                let a = w.jac[m + k * n]
                let b = w.jac[m + (k + 1usize) * n]
                w.jac[m + k * n] = c * a + s * b
                w.jac[m + (k + 1usize) * n] = c * b - s * a
                m += 1usize
            }
            kk -= 1usize
        }
        j = 0usize
        while j < n {
            w.rr[j * n] = w.rr[j * n] + w.w3[0usize] * w.w1[j]
            j += 1usize
        }
        var k2 = 0usize
        while k2 + 1usize < n {
            let (c, s, t) = lartg(w.rr[k2 + k2 * n], w.rr[k2 + 1usize + k2 * n])
            w.rr[k2 + k2 * n] = t
            w.rr[k2 + 1usize + k2 * n] = 0.0f64
            var m = k2 + 1usize
            while m < n {
                let a = w.rr[k2 + m * n]
                let b = w.rr[k2 + 1usize + m * n]
                w.rr[k2 + m * n] = c * a + s * b
                w.rr[k2 + 1usize + m * n] = c * b - s * a
                m += 1usize
            }
            m = 0usize
            while m < n {
                let a = w.jac[m + k2 * n]
                let b = w.jac[m + (k2 + 1usize) * n]
                w.jac[m + k2 * n] = c * a + s * b
                w.jac[m + (k2 + 1usize) * n] = c * b - s * a
                m += 1usize
            }
            k2 += 1usize
        }
    }
}

fn new_ws(a: *mem.Arena, sys: usize) -> (Ws, bool) {
    let n = dim_of(sys)
    var good = true
    let (xc, e1) = mem.alloc[f64](a, n)
    let (fc, e2) = mem.alloc[f64](a, n)
    let (xp, e3) = mem.alloc[f64](a, n)
    let (fp, e4) = mem.alloc[f64](a, n)
    let (gp, e5) = mem.alloc[f64](a, n)
    let (dn, e6) = mem.alloc[f64](a, n)
    let (d, e7) = mem.alloc[f64](a, n)
    let (qtf, e8) = mem.alloc[f64](a, n)
    let (fq, e9) = mem.alloc[f64](a, n)
    let (w1, e10) = mem.alloc[f64](a, n)
    let (w2, e11) = mem.alloc[f64](a, n)
    let (w3, e12) = mem.alloc[f64](a, n)
    let (w4, e13) = mem.alloc[f64](a, n)
    let (xw, e14) = mem.alloc[f64](a, n)
    let (sx, e15) = mem.alloc[f64](a, n)
    let (jac, e16) = mem.alloc[f64](a, n * n)
    let (rr, e17) = mem.alloc[f64](a, n * n)
    let (tau, e18) = mem.alloc[f64](a, n)
    let (sd, e19) = mem.alloc[f64](a, n)
    let (wk, e20) = mem.alloc[f64](a, n)
    let (vv, e21) = mem.alloc[f64](a, n + 1usize)
    let (tx, e22) = mem.alloc[f64](a, n)
    let (tv, e23) = mem.alloc[f64](a, n)
    let (ti, e24) = mem.alloc[f64](a, n)
    let (info, e25) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { good = false }
    if e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok || e25 != ok { good = false }
    let w = Ws { sys: sys, n: n, xc: xc, fc: fc, xp: xp, fp: fp, gp: gp, dn: dn, d: d, qtf: qtf, fq: fq, w1: w1, w2: w2, w3: w3, w4: w4, xw: xw, sx: sx,
        jac: jac, rr: rr, tau: tau, sd: sd, wk: wk, vv: vv, tx: tx, tv: tv, ti: ti, delta: 0.0f64, info: info }
    ret (w, good)
}

// nwnleq for system w.sys from x0: method 0 Newton, 1 Broyden; global 0 none, 1 cline, 2 qline, 3 gline, 4 dbldog, 5 pwldog; xscalm 0 fixed, 1 auto; delta -1 cauchy, -2 newton.
// Leaves the answer in w.xp (unscaled), fp, the scale factors in w.sx and [termcd, iter, nfcnt, njcnt] in w.info.
fn solve(w: *Ws, x0: []const f64, method: usize, global: usize, xscalm: usize, allow_sing: bool, maxit0: usize, delta0: f64) {
    let n = w.n
    let epsm = epsp()
    let xtol = 1.0e-8f64
    let ftol = 1.0e-8f64
    var btol = 1.0e-3f64
    var cndtol = 1.0e-12f64
    let sigma = 0.5f64
    if btol < xtol { btol = xtol }
    if cndtol < epsm { cndtol = epsm }
    let stepmx = bigv()
    var delta = delta0
    if delta <= 0.0f64 {
        if delta != 0.0f64 - 2.0f64 { delta = 0.0f64 - 1.0f64 }
    } else if delta > stepmx {
        delta = stepmx
    }
    w.delta = delta
    let dlt0 = delta
    let maxit = maxit0
    var i = 0usize
    while i < n {
        w.sx[i] = 1.0f64
        w.xc[i] = x0[i]
        i += 1usize
    }
    var retcd = 0usize
    var iter = 0usize
    var njcnt = 0usize
    var nfcnt = 0usize
    var ierr = 0usize
    i = 0usize
    while i < n {
        w.xc[i] = w.sx[i] * w.xc[i]
        i += 1usize
    }
    var fcnorm = nwfvec(w, w.xc, w.fc)
    var fpnorm = 0.0f64
    var termcd = nwtcvg(w, w.xc, w.fc, w.xc, xtol, retcd, ftol, iter, maxit, ierr)
    if termcd > 0usize {
        copy(w.xc, w.xp, n)
        copy(w.fc, w.fp, n)
        w.info[0usize] = f64(termcd)
        w.info[1usize] = f64(iter)
        w.info[2usize] = f64(nfcnt)
        w.info[3usize] = f64(njcnt)
        ret
    }
    var jacevl = true
    var jacupd = false
    while termcd == 0usize {
        iter += 1usize
        var gcnt = 0usize
        if method == 0usize || jacevl {
            nwfjac(w, w.xc, w.fc)
            njcnt += 1usize
            if xscalm == 1usize {
                i = 0usize
                while i < n {
                    w.xc[i] = w.xc[i] / w.sx[i]
                    i += 1usize
                }
                var k = 0usize
                while k < n {
                    var cn = nrm2(w.jac[k * n..k * n + n], n)
                    if iter == 1usize {
                        if cn <= epsm { cn = 1.0f64 }
                        w.sx[k] = cn
                    } else {
                        if cn > w.sx[k] { w.sx[k] = cn }
                    }
                    k += 1usize
                }
                i = 0usize
                while i < n {
                    w.xc[i] = w.sx[i] * w.xc[i]
                    i += 1usize
                }
            }
            var j = 0usize
            while j < n {
                let t = 1.0f64 / w.sx[j]
                i = 0usize
                while i < n {
                    w.jac[i + j * n] = w.jac[i + j * n] * t
                    i += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < n {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += w.jac[i + j * n] * w.fc[i]
                    i += 1usize
                }
                w.gp[j] = s
                j += 1usize
            }
            copy(w.fc, w.fq, n)
            geqr2(w.jac, n, w.tau, w.vv)
            copy(w.fq, w.qtf, n)
            qt_apply(w.jac, n, w.tau, w.qtf, w.vv)
            if method == 0usize {
                ierr = lirslv(w, w.jac, cndtol, allow_sing)
            } else {
                j = 0usize
                while j < n {
                    i = 0usize
                    while i <= j {
                        w.rr[i + j * n] = w.jac[i + j * n]
                        i += 1usize
                    }
                    j += 1usize
                }
                orgqr(w.jac, n, w.tau, w.vv)
                ierr = lirslv(w, w.rr, cndtol, allow_sing)
            }
        } else {
            copy(w.fc, w.fq, n)
            var j = 0usize
            while j < n {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += w.jac[i + j * n] * w.fq[i]
                    i += 1usize
                }
                w.qtf[j] = s
                j += 1usize
            }
            ierr = lirslv(w, w.rr, cndtol, allow_sing)
            if ierr == 0usize {
                copy(w.qtf, w.gp, n)
                trmv_ut(w.rr, n, w.gp)
            }
        }
        if ierr > 0usize {
            copy(w.xc, w.xp, n)
            copy(w.fc, w.fp, n)
            fpnorm = fcnorm
            gcnt = 0usize
        } else if global <= 3usize {
            let (rc, gc, fpn) = lsearch(w, global, fcnorm, stepmx, btol, sigma)
            retcd = rc
            gcnt = gc
            fpnorm = fpn
        } else {
            if method == 0usize {
                let (rc, gc, fpn) = dogleg(w, global == 5usize, w.jac, fcnorm, stepmx, btol)
                retcd = rc
                gcnt = gc
                fpnorm = fpn
            } else {
                let (rc, gc, fpn) = dogleg(w, global == 5usize, w.rr, fcnorm, stepmx, btol)
                retcd = rc
                gcnt = gc
                fpnorm = fpn
            }
        }
        nfcnt += gcnt
        termcd = nwtcvg(w, w.xp, w.fp, w.xc, xtol, retcd, ftol, iter, maxit, ierr)
        if method == 0usize {
            if termcd == 0usize {
                copy(w.xp, w.xc, n)
                copy(w.fp, w.fc, n)
                fcnorm = fpnorm
            }
        } else {
            if termcd == 3usize && !jacevl {
                jacevl = true
                jacupd = false
                w.delta = dlt0
                termcd = 0usize
            } else if termcd > 0usize {
                jacupd = false
            } else {
                jacupd = true
                jacevl = false
            }
            if jacupd {
                brupdt(w)
                copy(w.xp, w.xc, n)
                copy(w.fp, w.fc, n)
                fcnorm = fpnorm
            }
        }
    }
    i = 0usize
    while i < n {
        w.xp[i] = w.xp[i] / w.sx[i]
        i += 1usize
    }
    w.info[0usize] = f64(termcd)
    w.info[1usize] = f64(iter)
    w.info[2usize] = f64(nfcnt)
    w.info[3usize] = f64(njcnt)
}
