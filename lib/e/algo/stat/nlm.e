// R's nlm: the Dennis-Schnabel line-search quasi-Newton method of src/appl/uncmin.c (optif9 with method 1, iexp 1: the factored BFGS secant update, no analytic
// gradient or Hessian, forward-difference gradient switching to central differences when a step fails), driven as src/library/stats/src/optimize.c drives it
// (a non-finite objective is replaced by +-DBL_MAX; msg = 9). typsize is 1 and fscale 1, the defaults of nlm().

use e.algo.linalg.lapack_base as lbase
use e.math
use e.mem

type Nlm = struct { fv: f64, code: i64, iters: usize, good: bool }

fn dbl_max() -> f64 { ret 1.7976931348623157e308f64 }

fn fcn_[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []const f64) -> f64 {
    let v = f(c, x)
    if v - v == 0.0f64 { ret v }
    if v == 0.0f64 - 1.0f64 / 0.0f64 { ret 0.0f64 - dbl_max() }
    ret dbl_max()
}

fn nrm2_(x: []f64, n: usize) -> f64 { ret lbase.dnrm2(i64(n), x, 1i64) }

fn hypot_(a: f64, b: f64) -> f64 { ret math.sqrt[f64](a * a + b * b) }

fn fmax2_(a: f64, b: f64) -> f64 {
    if a < b { ret b }
    ret a
}

// a is column-major n by n; solve (L L^T) x = b with L its lower triangle (LINPACK dtrsl twice); x and b may be one array
fn lltslv(n: usize, a: []const f64, x: []f64, b: []const f64) {
    var i = 0usize
    while i < n {
        x[i] = b[i]
        i += 1usize
    }
    x[0usize] = x[0usize] / a[0usize]
    var j = 1usize
    while j < n {
        let temp = 0.0f64 - x[j - 1usize]
        i = j
        while i < n {
            x[i] = x[i] + temp * a[i + (j - 1usize) * n]
            i += 1usize
        }
        x[j] = x[j] / a[j + j * n]
        j += 1usize
    }
    x[n - 1usize] = x[n - 1usize] / a[(n - 1usize) + (n - 1usize) * n]
    var jj = 2usize
    while jj <= n {
        let jx = n - jj
        var s = 0.0f64
        var k = 0usize
        while k < jj - 1usize {
            s = s + a[(jx + 1usize + k) + jx * n] * x[jx + 1usize + k]
            k += 1usize
        }
        x[jx] = x[jx] - s
        x[jx] = x[jx] / a[jx + jx * n]
        jj += 1usize
    }
}

fn mvmltl(n: usize, a: []const f64, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j <= i {
            s = s + a[i + j * n] * x[j]
            j += 1usize
        }
        y[i] = s
        i += 1usize
    }
}

fn mvmltu(n: usize, a: []const f64, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var k = i
        while k < n {
            s = s + a[k + i * n] * x[k]
            k += 1usize
        }
        y[i] = s
        i += 1usize
    }
}

fn qraux1(n: usize, r: []f64, i: usize) {
    var k = i
    while k < n {
        let t = r[i + k * n]
        r[i + k * n] = r[i + 1usize + k * n]
        r[i + 1usize + k * n] = t
        k += 1usize
    }
}

fn qraux2(n: usize, r: []f64, i: usize, a: f64, b: f64) {
    let den = hypot_(a, b)
    let c = a / den
    let s = b / den
    var k = i
    while k < n {
        let y = r[i + k * n]
        let z = r[i + 1usize + k * n]
        r[i + k * n] = c * y - s * z
        r[i + 1usize + k * n] = s * y + c * z
        k += 1usize
    }
}

fn qrupdt(n: usize, a: []f64, u: []f64, v: []const f64) {
    var k = n - 1usize
    while k > 0usize && u[k] == 0.0f64 { k -= 1usize }
    if k > 0usize {
        var ii = k
        while ii > 0usize {
            let i = ii - 1usize
            if u[i] == 0.0f64 {
                qraux1(n, a, i)
                u[i] = u[ii]
            } else {
                qraux2(n, a, i, u[i], 0.0f64 - u[ii])
                u[i] = hypot_(u[i], u[ii])
            }
            ii = i
        }
    }
    var j = 0usize
    while j < n {
        a[j * n] = a[j * n] + u[0usize] * v[j]
        j += 1usize
    }
    var i2 = 0usize
    while i2 < k {
        if a[i2 + i2 * n] == 0.0f64 {
            qraux1(n, a, i2)
        } else {
            let t1 = a[i2 + i2 * n]
            let t2 = 0.0f64 - a[i2 + 1usize + i2 * n]
            qraux2(n, a, i2, t1, t2)
        }
        i2 += 1usize
    }
}

// the BFGS factored secant update of the Cholesky factor in a (lower triangle); s, y, u, w are scratch
fn secfac(n: usize, x: []const f64, g: []const f64, a: []f64, xpls: []const f64, gpls: []const f64, epsm: f64, itncnt: usize, rnf: f64, iagflg: i64, s: []f64, y: []f64, u: []f64, w: []f64) {
    var noupdt = itncnt == 1usize
    var i = 0usize
    while i < n {
        s[i] = xpls[i] - x[i]
        y[i] = gpls[i] - g[i]
        i += 1usize
    }
    var den1 = 0.0f64
    i = 0usize
    while i < n {
        den1 = den1 + s[i] * y[i]
        i += 1usize
    }
    let snorm2 = nrm2_(s, n)
    let ynrm2 = nrm2_(y, n)
    if den1 < math.sqrt[f64](epsm) * snorm2 * ynrm2 { ret }
    mvmltu(n, a, s, u)
    var den2 = 0.0f64
    i = 0usize
    while i < n {
        den2 = den2 + u[i] * u[i]
        i += 1usize
    }
    var alp = math.sqrt[f64](den1 / den2)
    if noupdt {
        var j = 0usize
        while j < n {
            u[j] = alp * u[j]
            i = j
            while i < n {
                a[i + j * n] = a[i + j * n] * alp
                i += 1usize
            }
            j += 1usize
        }
        noupdt = false
        den2 = den1
        alp = 1.0f64
    }
    mvmltl(n, a, u, w)
    var reltol = rnf
    if iagflg == 0i64 { reltol = math.sqrt[f64](rnf) }
    var skpupd = true
    i = 0usize
    while i < n {
        skpupd = math.abs[f64](y[i] - w[i]) < reltol * fmax2_(math.abs[f64](g[i]), math.abs[f64](gpls[i]))
        if !skpupd { break }
        i += 1usize
    }
    if skpupd { ret }
    i = 0usize
    while i < n {
        w[i] = y[i] - alp * w[i]
        i += 1usize
    }
    alp = alp / den1
    i = 0usize
    while i < n {
        u[i] = u[i] * alp
        i += 1usize
    }
    i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            a[j + i * n] = a[i + j * n]
            a[i + j * n] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    qrupdt(n, a, u, w)
    i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            a[i + j * n] = a[j + i * n]
            j += 1usize
        }
        i += 1usize
    }
}

fn opt_stop(n: usize, xpls: []const f64, fpls: f64, gpls: []const f64, x: []const f64, itncnt: usize, icscmx: *usize, gradtl: f64, steptl: f64, fscale: f64, itnlim: usize, iretcd: i64, mxtake: bool) -> i64 {
    if iretcd == 1i64 { ret 3i64 }
    let d = fmax2_(math.abs[f64](fpls), fscale)
    var rgx = 0.0f64
    var i = 0usize
    while i < n {
        let relgrd = math.abs[f64](gpls[i]) * fmax2_(math.abs[f64](xpls[i]), 1.0f64) / d
        if rgx < relgrd { rgx = relgrd }
        i += 1usize
    }
    var jtrmcd = 1i64
    if rgx > gradtl {
        if itncnt == 0usize { ret 0i64 }
        var rsx = 0.0f64
        i = 0usize
        while i < n {
            let relstp = math.abs[f64](xpls[i] - x[i]) / fmax2_(math.abs[f64](xpls[i]), 1.0f64)
            if rsx < relstp { rsx = relstp }
            i += 1usize
        }
        jtrmcd = 2i64
        if rsx > steptl {
            jtrmcd = 4i64
            if itncnt < itnlim {
                if !mxtake {
                    *icscmx = 0usize
                    ret 0i64
                }
                *icscmx += 1usize
                if *icscmx < 5usize { ret 0i64 }
                jtrmcd = 5i64
            }
        }
    }
    ret jtrmcd
}

fn fstofd[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, n: usize, xpls: []f64, fpls: f64, g: []f64, rnoise: f64) {
    var j = 0usize
    while j < n {
        let temp1 = math.abs[f64](xpls[j])
        let stepsz = math.sqrt[f64](rnoise) * fmax2_(temp1, 1.0f64)
        let xtmpj = xpls[j]
        xpls[j] = xtmpj + stepsz
        let fhat = fcn_[Ctx](c, f, xpls)
        xpls[j] = xtmpj
        g[j] = (fhat - fpls) / stepsz
        j += 1usize
    }
}

fn fstocd[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, n: usize, x: []f64, rnoise: f64, g: []f64) {
    var i = 0usize
    while i < n {
        let xtempi = x[i]
        let stepi = math.pow[f64](rnoise, 1.0f64 / 3.0f64) * fmax2_(math.abs[f64](xtempi), 1.0f64)
        x[i] = xtempi + stepi
        let fplus = fcn_[Ctx](c, f, x)
        x[i] = xtempi - stepi
        let fminus = fcn_[Ctx](c, f, x)
        x[i] = xtempi
        g[i] = (fplus - fminus) / (stepi * 2.0f64)
        i += 1usize
    }
}

// the line search; returns (fpls, iretcd, mxtake)
fn lnsrch[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, n: usize, x: []const f64, fx: f64, g: []const f64, p: []f64, xpls: []f64, stepmx: f64, steptl: f64) -> (f64, i64, bool) {
    var firstback = true
    var temp1 = 0.0f64
    var i = 0usize
    while i < n {
        temp1 = temp1 + p[i] * p[i]
        i += 1usize
    }
    var sln = math.sqrt[f64](temp1)
    if sln > stepmx {
        let scl = stepmx / sln
        i = 0usize
        while i < n {
            p[i] = p[i] * scl
            i += 1usize
        }
        sln = stepmx
    }
    var slp = 0.0f64
    i = 0usize
    while i < n {
        slp = slp + g[i] * p[i]
        i += 1usize
    }
    var rln = 0.0f64
    i = 0usize
    while i < n {
        let t = math.abs[f64](p[i]) / fmax2_(math.abs[f64](x[i]), 1.0f64)
        if rln < t { rln = t }
        i += 1usize
    }
    let rmnlmb = steptl / rln
    var lambda = 1.0f64
    var iretcd = 2i64
    var mxtake = false
    var fpls = 0.0f64
    var pfpls = 0.0f64
    var plmbda = 0.0f64
    var tlmbda = 0.0f64
    while iretcd > 1i64 {
        i = 0usize
        while i < n {
            xpls[i] = x[i] + lambda * p[i]
            i += 1usize
        }
        fpls = fcn_[Ctx](c, f, xpls)
        if fpls <= fx + slp * 0.0001f64 * lambda {
            iretcd = 0i64
            if lambda == 1.0f64 && sln > stepmx * 0.99f64 { mxtake = true }
            ret (fpls, iretcd, mxtake)
        }
        if lambda < rmnlmb {
            iretcd = 1i64
            ret (fpls, iretcd, mxtake)
        }
        if fpls >= dbl_max() {
            lambda = lambda * 0.1f64
            firstback = true
        } else {
            if firstback {
                tlmbda = (0.0f64 - lambda) * slp / ((fpls - fx - slp) * 2.0f64)
                firstback = false
            } else {
                let t1 = fpls - fx - lambda * slp
                let t2 = pfpls - fx - plmbda * slp
                let t3 = 1.0f64 / (lambda - plmbda)
                let a3 = 3.0f64 * t3 * (t1 / (lambda * lambda) - t2 / (plmbda * plmbda))
                let b = t3 * (t2 * lambda / (plmbda * plmbda) - t1 * plmbda / (lambda * lambda))
                let disc = b * b - a3 * slp
                var sq = math.sqrt[f64](disc)
                if disc > b * b {
                    if a3 < 0.0f64 { sq = 0.0f64 - sq }
                    tlmbda = ((0.0f64 - b) + sq) / a3
                } else {
                    if !(a3 < 0.0f64) { sq = 0.0f64 - sq }
                    tlmbda = ((0.0f64 - b) + sq) / a3
                }
                if tlmbda > lambda * 0.5f64 { tlmbda = lambda * 0.5f64 }
            }
            plmbda = lambda
            pfpls = fpls
            if tlmbda < lambda * 0.1f64 {
                lambda = lambda * 0.1f64
            } else {
                lambda = tlmbda
            }
        }
    }
    ret (fpls, iretcd, mxtake)
}

// nlm(f, par, ndigit = 12, gradtol = 1e-6, steptol = 1e-6, iterlim = itnlim): par is the start and gets the estimate; the result holds the minimum, the code and the
// iteration count
fn nlm[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, par: []f64, itnlim: usize) -> Nlm {
    var res: Nlm = zero
    let n = par.len
    let ndigit = 12i64
    let gradtl = 0.000001f64
    let steptl = 0.000001f64
    let epsm = 2.220446049250313e-16f64
    let fscale = 1.0f64
    var ss = 0.0f64
    var i = 0usize
    while i < n {
        ss = ss + par[i] * par[i]
        i += 1usize
    }
    let stepmx = fmax2_(1000.0f64 * math.sqrt[f64](ss), 1000.0f64)
    let (ws, e) = mem.alloc[f64](a, 10usize * n + n * n + 1usize)
    if e != ok { ret res }
    let x = ws[0usize..n]
    let xpls = ws[n..2usize * n]
    let g = ws[2usize * n..3usize * n]
    let gpls = ws[3usize * n..4usize * n]
    let p = ws[4usize * n..5usize * n]
    let w0 = ws[5usize * n..6usize * n]
    let w1 = ws[6usize * n..7usize * n]
    let w2 = ws[7usize * n..8usize * n]
    let w3 = ws[8usize * n..9usize * n]
    let h = ws[9usize * n..9usize * n + n * n]
    i = 0usize
    while i < n {
        x[i] = par[i]
        p[i] = 0.0f64
        i += 1usize
    }
    var rnf = math.pow[f64](10.0f64, 0.0f64 - f64(ndigit))
    rnf = fmax2_(rnf, epsm)
    var fx = fcn_[Ctx](c, f, x)
    fstofd[Ctx](c, f, n, x, fx, g, rnf)
    var iagflg = 0i64
    var icscmx = 0usize
    var itncnt = 0usize
    var itrmcd = opt_stop(n, x, fx, g, w1, itncnt, &icscmx, gradtl, steptl, fscale, itnlim, 0i64 - 1i64, false)
    if itrmcd != 0i64 {
        res.fv = fx
        res.code = itrmcd
        res.iters = 0usize
        res.good = true
        ret res
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            h[i + j * n] = 0.0f64
            j += 1usize
        }
        h[i + i * n] = 1.0f64
        i += 1usize
    }
    var fpls = 0.0f64
    var running = true
    while running {
        itncnt += 1usize
        var again = true
        var iretcd = 0i64
        var mxtake = false
        while again {
            again = false
            i = 0usize
            while i < n {
                w1[i] = 0.0f64 - g[i]
                i += 1usize
            }
            lltslv(n, h, p, w1)
            let (fp, ir, mt) = lnsrch[Ctx](c, f, n, x, fx, g, p, xpls, stepmx, steptl)
            fpls = fp
            iretcd = ir
            mxtake = mt
            if iretcd == 1i64 && iagflg == 0i64 {
                iagflg = 0i64 - 1i64
                fstocd[Ctx](c, f, n, x, rnf, g)
                again = true
            }
        }
        i = 0usize
        while i < n {
            p[i] = xpls[i] - x[i]
            i += 1usize
        }
        if iagflg == 0i64 - 1i64 {
            fstocd[Ctx](c, f, n, xpls, rnf, gpls)
        } else {
            fstofd[Ctx](c, f, n, xpls, fpls, gpls, rnf)
        }
        itrmcd = opt_stop(n, xpls, fpls, gpls, x, itncnt, &icscmx, gradtl, steptl, fscale, itnlim, iretcd, mxtake)
        if itrmcd != 0i64 {
            running = false
        } else {
            secfac(n, x, g, h, xpls, gpls, epsm, itncnt, rnf, iagflg, w0, w1, w2, w3)
            fx = fpls
            i = 0usize
            while i < n {
                x[i] = xpls[i]
                g[i] = gpls[i]
                i += 1usize
            }
        }
    }
    if itrmcd == 3i64 {
        fpls = fx
        i = 0usize
        while i < n {
            xpls[i] = x[i]
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        par[i] = xpls[i]
        i += 1usize
    }
    res.fv = fpls
    res.code = itrmcd
    res.iters = itncnt
    res.good = true
    ret res
}
