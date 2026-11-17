// R lmom, the whole of the Fortran library by J. R. M. Hosking that the package wraps: L-moments of a distribution (`lmrx`),
// its quantile and distribution functions (`quax`, `cdfx`), parameters from L-moments (`pelx`) and sample L-moments with
// trimming (`samlmu_trim`), for the fourteen kinds below. Every routine follows its Fortran original, constants included
// (pelgev and pelgam use the original's rounded constants on purpose), so the answers equal the package's.
//
// kind: 0 exp, 1 gam, 2 gev, 3 glo, 4 gno, 5 gpa, 6 gum, 7 kap, 8 ln3, 9 nor, 10 pe3, 11 wak, 12 wa0 (pel only), 13 wei
// parameters: exp (xi, alpha); gam (alpha, beta); gev, glo, gno, gpa (xi, alpha, k); gum (xi, alpha); kap (xi, alpha, k, h);
// ln3 (zeta, mu, sigma); nor (mu, sigma); pe3 (mu, sigma, gamma); wak (xi, alpha, beta, gamma, delta); wei (zeta, beta, delta)
// ifail codes are the library's: 0 good, 7000 invalid, 7010 too many moments or not converged, 71xx some moments unconverged.

use e.algo.sort
use e.algo.stat.lmomtab as tab
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn pi_const() -> f64 { ret 3.141592653589793238f64 }

fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

// XLGAMA: the library's log gamma
fn xlgama(x: f64) -> f64 {
    if x <= 0.0f64 { ret 1.0e300f64 }
    let s1 = 0.0f64 - 0.5772156649015328610f64
    let s2 = 0.8224670334241132180f64
    if x <= 1.0e-5f64 { ret 0.0f64 - math.log[f64](x) + s1 * x }
    var xx = 0.0f64
    var res = 0.0f64
    if math.abs[f64](x - 2.0f64) <= 1.0e-5f64 {
        res = math.log[f64](x - 1.0f64)
        xx = x - 2.0f64
        ret res + xx * (s1 + xx * s2)
    }
    if math.abs[f64](x - 1.0f64) <= 1.0e-5f64 {
        xx = x - 1.0f64
        ret xx * (s1 + xx * s2)
    }
    let c0 = 0.9189385332046727420f64
    let c1 = 0.08333333333333333333f64
    let c2 = 0.0f64 - 0.002777777777777777778f64
    let c3 = 0.0007936507936507936510f64
    let c4 = 0.0f64 - 0.0005952380952380952380f64
    let c5 = 0.0008417508417508417510f64
    let c6 = 0.0f64 - 0.001917526917526917530f64
    let c7 = 0.006410256410256410260f64
    var sum1 = 0.0f64
    var y = x
    if y < 13.0f64 {
        var z = 1.0f64
        while y < 13.0f64 {
            z = z * y
            y = y + 1.0f64
        }
        sum1 = sum1 - math.log[f64](z)
    }
    sum1 = sum1 + (y - 0.5f64) * math.log[f64](y) - y + c0
    var sum2 = 0.0f64
    if y < 1.0e9f64 {
        let z = 1.0f64 / (y * y)
        sum2 = ((((((c7 * z + c6) * z + c5) * z + c4) * z + c3) * z + c2) * z + c1) / y
    }
    ret sum1 + sum2
}

// DIGAMD: the library's digamma
fn digamd(x: f64) -> f64 {
    if x <= 0.0f64 { ret 1.0e300f64 }
    let c1 = 0.08333333333333333333f64
    let c2 = 0.0f64 - 0.008333333333333333333f64
    let c3 = 0.003968253968253968250f64
    let c4 = 0.0f64 - 0.004166666666666666660f64
    let c5 = 0.007575757575757575750f64
    let c6 = 0.0f64 - 0.02109279609279609280f64
    let c7 = 0.08333333333333333333f64
    let eu = 0.0f64 - 0.5772156649015328610f64
    if x <= 1.0e-9f64 { ret eu - 1.0f64 / x }
    var d = 0.0f64
    var y = x
    while y < 13.0f64 {
        d = d - 1.0f64 / y
        y = y + 1.0f64
    }
    d = d + math.log[f64](y) - 0.5f64 / y
    y = 1.0f64 / (y * y)
    let sum = ((((((c7 * y + c6) * y + c5) * y + c4) * y + c3) * y + c2) * y + c1) * y
    ret d - sum
}

// XERF: the library's erf (a rational approximation of Cody)
fn xerf(x: f64) -> f64 {
    if x == 0.0f64 { ret 0.0f64 }
    let xx = math.abs[f64](x)
    if xx > 6.25f64 {
        if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
        ret 1.0f64
    }
    let p0 = 0.220206867912376e3f64
    let p1 = 0.221213596169931e3f64
    let p2 = 0.112079291497870e3f64
    let p3 = 0.339128660783830e2f64
    let p4 = 0.637396220353165e1f64
    let p5 = 0.700383064443688f64
    let p6 = 0.352624965998910e-1f64
    let q0 = 0.440413735824752e3f64
    let q1 = 0.793826512519948e3f64
    let q2 = 0.637333633378831e3f64
    let q3 = 0.296564248779674e3f64
    let q4 = 0.867807322029461e2f64
    let q5 = 0.160641775792695e2f64
    let q6 = 0.175566716318264e1f64
    let q7 = 0.883883476483184e-1f64
    let c1 = 1.41421356237309f64
    let c2 = 0.797884560802865f64
    let ex = math.exp[f64](0.0f64 - x * x)
    let zz = math.abs[f64](x * c1)
    var r = 0.0f64
    if xx > 5.0f64 {
        r = ex * c2 / (zz + 1.0f64 / (zz + 2.0f64 / (zz + 3.0f64 / (zz + 4.0f64 / (zz + 0.65f64)))))
        if x < 0.0f64 { ret r - 1.0f64 }
        ret 1.0f64 - r
    }
    r = ex * ((((((p6 * zz + p5) * zz + p4) * zz + p3) * zz + p2) * zz + p1) * zz + p0) / (((((((q7 * zz + q6) * zz + q5) * zz + q4) * zz + q3) * zz + q2) * zz + q1) * zz + q0)
    if x < 0.0f64 { ret 2.0f64 * r - 1.0f64 }
    ret 1.0f64 - 2.0f64 * r
}

// ---- L-moments of a distribution -------------------------------------------------------------------------------

fn lmr_ev_small(u: f64, a: f64, nmom: usize, x: []f64) -> i32 {
    var z: [20]f64 = zero
    tab.zmom_ev(z[0usize..20usize])
    x[0usize] = u + a * z[0usize]
    if nmom == 1usize { ret 0i32 }
    x[1usize] = a * z[1usize]
    var i = 2usize
    while i < nmom {
        x[i] = z[i]
        i += 1usize
    }
    ret 0i32
}

// the recurrence from the gev and kappa beta terms: x[j-1] for j = 3 .. nmom from beta (j) and the normaliser
fn lmr_recur(nmom: usize, b1: f64, bj: []const f64, alam2: f64, x: []f64) {
    var z0 = 1.0f64
    var j = 3usize
    while j < nmom + 1usize {
        let dj = f64(j)
        z0 = z0 * (4.0f64 * dj - 6.0f64) / dj
        var z = z0 * 3.0f64 * (dj - 1.0f64) / (dj + 1.0f64)
        var sum = z0 * (bj[j] - b1) / alam2 - z
        if j != 3usize {
            var i = 2usize
            while i < j - 1usize {
                let di = f64(i)
                z = z * (di + di + 1.0f64) * (dj - di) / ((di + di - 1.0f64) * (dj + di))
                sum = sum - z * x[i]
                i += 1usize
            }
        }
        x[j - 1usize] = sum
        j += 1usize
    }
}

fn lmr_exp(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let a = p[1usize]
    if a <= 0.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    x[0usize] = p[0usize] + a
    if nmom == 1usize { ret 0i32 }
    x[1usize] = 0.5f64 * a
    var j = 3usize
    while j < nmom + 1usize {
        x[j - 1usize] = 2.0f64 / f64(j * (j - 1usize))
        j += 1usize
    }
    ret 0i32
}

fn lmr_gam(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let alpha = p[0usize]
    let beta = p[1usize]
    if alpha <= 0.0f64 || beta <= 0.0f64 { ret 7000i32 }
    if nmom > 4usize { ret 7010i32 }
    x[0usize] = alpha * beta
    if nmom == 1usize { ret 0i32 }
    x[1usize] = beta * 0.5641895835477562870f64 * math.exp[f64](xlgama(alpha + 0.5f64) - xlgama(alpha))
    if nmom == 2usize { ret 0i32 }
    ret gam_pe3_shape(alpha, nmom, x)
}

// the third and fourth L-moment ratios of a gamma distribution of shape alpha (shared by lmrgam and lmrpe3)
fn gam_pe3_shape(alpha: f64, nmom: usize, x: []f64) -> i32 {
    if alpha >= 1.0f64 {
        let z = 1.0f64 / alpha
        x[2usize] = math.sqrt[f64](z) * (((0.0f64 - 0.29120539e-2f64 * z + 0.78327243e-1f64) * z + 0.16869150f64) * z + 0.32573501f64) / ((0.24255406f64 * z + 0.46697102f64) * z + 1.0f64)
        if nmom == 3usize { ret 0i32 }
        x[3usize] = (((0.11101277e-1f64 * z + 0.43384378e-1f64) * z + 0.53730130e-1f64) * z + 0.12260172f64) / ((0.20166036f64 * z + 0.18324466f64) * z + 1.0f64)
        if nmom > 4usize { ret 7010i32 }
        ret 0i32
    }
    let z = alpha
    x[2usize] = (((0.11618371f64 * z + 0.15931792e1f64) * z + 0.23807576e1f64) * z + 1.0f64) / (((0.19745056e1f64 * z + 0.71425260e1f64) * z + 0.51533299e1f64) * z + 1.0f64)
    if nmom == 3usize { ret 0i32 }
    x[3usize] = (((0.31925299e1f64 * z + 0.41670213e1f64) * z + 0.21235833e1f64) * z + 1.0f64) / (((0.26193668e2f64 * z + 0.26649995e2f64) * z + 0.90551443e1f64) * z + 1.0f64)
    ret 0i32
}

fn lmr_gev(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let u = p[0usize]
    let a = p[1usize]
    let g = p[2usize]
    if a <= 0.0f64 || g <= 0.0f64 - 1.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    if math.abs[f64](g) <= 1.0e-6f64 { ret lmr_ev_small(u, a, nmom, x) }
    let gam = math.exp[f64](xlgama(1.0f64 + g))
    x[0usize] = u + a * (1.0f64 - gam) / g
    if nmom == 1usize { ret 0i32 }
    let xx2 = 1.0f64 - math.pow[f64](2.0f64, 0.0f64 - g)
    x[1usize] = a * xx2 * gam / g
    if nmom == 2usize { ret 0i32 }
    var bj: [22]f64 = zero
    var j = 3usize
    while j < nmom + 1usize {
        bj[j] = (1.0f64 - math.pow[f64](f64(j), 0.0f64 - g)) / xx2
        j += 1usize
    }
    lmr_recur(nmom, 0.0f64, bj[0usize..22usize], 1.0f64, x)
    ret 0i32
}

fn lmr_glo(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let u = p[0usize]
    let a = p[1usize]
    let g = p[2usize]
    if a <= 0.0f64 || math.abs[f64](g) >= 1.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    let c1 = 0.1644934066848226440e1f64
    let c2 = 0.1894065658994491840e1f64
    let gg = g * g
    var alam1 = 0.0f64 - g * (c1 + gg * c2)
    var alam2 = 1.0f64 + gg * (c1 + gg * c2)
    if math.abs[f64](g) > 1.0e-4f64 {
        alam2 = g * pi_const() / math.sin(g * pi_const())
        alam1 = (1.0f64 - alam2) / g
    }
    x[0usize] = u + a * alam1
    if nmom == 1usize { ret 0i32 }
    x[1usize] = a * alam2
    if nmom == 2usize { ret 0i32 }
    var zt: [200]f64 = zero
    tab.glo_z(zt[0usize..200usize])
    var m = 3usize
    while m < nmom + 1usize {
        let kmax = m / 2usize
        var sum = zt[(kmax - 1usize) + 10usize * (m - 1usize)]
        var k = kmax - 1usize
        while k >= 1usize {
            sum = sum * gg + zt[(k - 1usize) + 10usize * (m - 1usize)]
            k -= 1usize
        }
        if m != m / 2usize * 2usize { sum = 0.0f64 - g * sum }
        x[m - 1usize] = sum
        m += 1usize
    }
    ret 0i32
}

fn lmr_gno(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let u = p[0usize]
    let a = p[1usize]
    let g = p[2usize]
    if a <= 0.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    var zm: [20]f64 = zero
    tab.zmom_no(zm[0usize..20usize])
    if math.abs[f64](g) <= 1.0e-8f64 {
        x[0usize] = u
        if nmom == 1usize { ret 0i32 }
        x[1usize] = a * zm[1usize]
        var i = 2usize
        while i < nmom {
            x[i] = zm[i]
            i += 1usize
        }
        ret 0i32
    }
    let egg = math.exp[f64](0.5f64 * g * g)
    x[0usize] = u + a * (1.0f64 - egg) / g
    if nmom == 1usize { ret 0i32 }
    let alam2 = egg * xerf(0.5f64 * g) / g
    x[1usize] = a * alam2
    if nmom == 2usize { ret 0i32 }
    let rrt2 = 0.7071067811865475244f64
    let rrtpi = 0.5641895835477562870f64
    let cc = 0.0f64 - g * rrt2
    let xmin = cc - 5.0f64
    let xmax = cc + 5.0f64
    var sum: [22]f64 = zero
    var est: [22]f64 = zero
    var estx: [22]f64 = zero
    var n = 16usize
    var m = 3usize
    var xinc = (xmax - xmin) / f64(n)
    var i = 1usize
    while i < n {
        let xv = xmin + f64(i) * xinc
        let e = math.exp[f64](0.0f64 - (xv - cc) * (xv - cc))
        let d = xerf(xv)
        var p1 = 1.0f64
        var pp = d
        m = 3usize
        while m < nmom + 1usize {
            let c1 = f64(m + m) - 3.0f64
            let c2 = f64(m) - 2.0f64
            let c3 = f64(m) - 1.0f64
            let p2 = p1
            p1 = pp
            pp = (c1 * d * p1 - c2 * p2) / c3
            sum[m] = sum[m] + e * pp
            m += 1usize
        }
        i += 1usize
    }
    m = 3usize
    while m < nmom + 1usize {
        est[m] = sum[m] * xinc
        m += 1usize
    }
    var notcgd = 0usize
    var it = 1usize
    var done = false
    while it <= 10usize && !done {
        m = 3usize
        while m < nmom + 1usize {
            estx[m] = est[m]
            m += 1usize
        }
        n = n * 2usize
        xinc = (xmax - xmin) / f64(n)
        i = 1usize
        while i < n {
            let xv = xmin + f64(i) * xinc
            let e = math.exp[f64](0.0f64 - (xv - cc) * (xv - cc))
            let d = xerf(xv)
            var p1 = 1.0f64
            var pp = d
            m = 3usize
            while m < nmom + 1usize {
                let c1 = f64(m + m) - 3.0f64
                let c2 = f64(m) - 2.0f64
                let c3 = f64(m) - 1.0f64
                let p2 = p1
                p1 = pp
                pp = (c1 * d * p1 - c2 * p2) / c3
                sum[m] = sum[m] + e * pp
                m += 1usize
            }
            i += 2usize
        }
        notcgd = 0usize
        m = nmom
        while m >= 3usize {
            est[m] = sum[m] * xinc
            if math.abs[f64](est[m] - estx[m]) > 1.0e-8f64 * math.abs[f64](est[m]) { notcgd = m }
            m -= 1usize
        }
        if notcgd == 0usize { done = true }
        it += 1usize
    }
    var ifail = 0i32
    if !done { ifail = 7100i32 + i32(notcgd) - 1i32 }
    let cst = 0.0f64 - math.exp[f64](cc * cc) * rrtpi / (alam2 * g)
    m = 3usize
    while m < nmom + 1usize {
        x[m - 1usize] = cst * est[m]
        m += 1usize
    }
    ret ifail
}

fn lmr_gpa(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let a = p[1usize]
    let g = p[2usize]
    if a <= 0.0f64 || g < 0.0f64 - 1.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    var y = 1.0f64 / (1.0f64 + g)
    x[0usize] = p[0usize] + a * y
    if nmom == 1usize { ret 0i32 }
    y = y / (2.0f64 + g)
    x[1usize] = a * y
    if nmom == 2usize { ret 0i32 }
    y = 1.0f64
    var m = 3usize
    while m < nmom + 1usize {
        let am = f64(m) - 2.0f64
        y = y * (am - g) / (f64(m) + g)
        x[m - 1usize] = y
        m += 1usize
    }
    ret 0i32
}

fn lmr_gum(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let a = p[1usize]
    if a <= 0.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    ret lmr_ev_small(p[0usize], a, nmom, x)
}

fn lmr_kap(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let u = p[0usize]
    let a = p[1usize]
    let g = p[2usize]
    let h = p[3usize]
    if a <= 0.0f64 { ret 7000i32 }
    if g <= 0.0f64 - 1.0f64 { ret 7000i32 }
    if h < 0.0f64 && g * h <= 0.0f64 - 1.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    let eu = 0.577215664901532861f64
    let xlgam = xlgama(1.0f64 + g)
    var beta: [22]f64 = zero
    var ir = 1usize
    while ir < nmom + 1usize {
        let r = f64(ir)
        if g == 0.0f64 {
            if h < 0.0f64 {
                beta[ir] = eu + math.log[f64](0.0f64 - h) + digamd(0.0f64 - r / h)
            } else if math.abs[f64](h) < 1.0e-8f64 {
                beta[ir] = eu + math.log[f64](r)
            } else {
                beta[ir] = eu + math.log[f64](h) + digamd(1.0f64 + r / h)
            }
        } else {
            if h < 0.0f64 {
                let arg = xlgam + xlgama(0.0f64 - r / h - g) - xlgama(0.0f64 - r / h) - g * math.log[f64](0.0f64 - h)
                if math.abs[f64](arg) > 170.0f64 { ret 7020i32 }
                beta[ir] = math.exp[f64](arg)
            } else if math.abs[f64](h) < 1.0e-8f64 {
                beta[ir] = math.exp[f64](xlgam - g * math.log[f64](r)) * (1.0f64 - 0.5f64 * h * g * (1.0f64 + g) / r)
            } else {
                let arg = xlgam + xlgama(1.0f64 + r / h) - xlgama(1.0f64 + g + r / h) - g * math.log[f64](h)
                if math.abs[f64](arg) > 170.0f64 { ret 7020i32 }
                beta[ir] = math.exp[f64](arg)
            }
        }
        ir += 1usize
    }
    if g == 0.0f64 { x[0usize] = u + a * beta[1usize] }
    if g != 0.0f64 { x[0usize] = u + a * (1.0f64 - beta[1usize]) / g }
    if nmom == 1usize { ret 0i32 }
    let alam2 = beta[2usize] - beta[1usize]
    if g == 0.0f64 { x[1usize] = a * alam2 }
    if g != 0.0f64 { x[1usize] = a * alam2 / (0.0f64 - g) }
    if nmom == 2usize { ret 0i32 }
    lmr_recur(nmom, beta[1usize], beta[0usize..22usize], alam2, x)
    ret 0i32
}

fn lmr_nor(p: []const f64, nmom: usize, x: []f64) -> i32 {
    if p[1usize] <= 0.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    var zm: [20]f64 = zero
    tab.zmom_no(zm[0usize..20usize])
    x[0usize] = p[0usize]
    if nmom == 1usize { ret 0i32 }
    x[1usize] = p[1usize] * zm[1usize]
    var i = 2usize
    while i < nmom {
        x[i] = zm[i]
        i += 1usize
    }
    ret 0i32
}

fn lmr_pe3(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let sd = p[1usize]
    if sd <= 0.0f64 { ret 7000i32 }
    if nmom > 4usize { ret 7010i32 }
    x[0usize] = p[0usize]
    if nmom == 1usize { ret 0i32 }
    let gamma = p[2usize]
    let cst = 0.5641895835477562870f64
    if math.abs[f64](gamma) < 1.0e-6f64 {
        x[1usize] = cst * sd
        if nmom == 2usize { ret 0i32 }
        x[2usize] = 0.0f64
        if nmom == 3usize { ret 0i32 }
        x[3usize] = 0.12260172f64
        if nmom > 4usize { ret 7010i32 }
        ret 0i32
    }
    let alpha = 4.0f64 / (gamma * gamma)
    let beta = math.abs[f64](0.5f64 * sd * gamma)
    x[1usize] = cst * math.exp[f64](xlgama(alpha + 0.5f64) - xlgama(alpha)) * beta
    if nmom == 2usize { ret 0i32 }
    let r = gam_pe3_shape(alpha, nmom, x)
    if gamma < 0.0f64 { x[2usize] = 0.0f64 - x[2usize] }
    ret r
}

fn lmr_wak(p: []const f64, nmom: usize, x: []f64) -> i32 {
    let xi = p[0usize]
    let a = p[1usize]
    let b = p[2usize]
    let c = p[3usize]
    let d = p[4usize]
    if d >= 1.0f64 { ret 7000i32 }
    if b + d <= 0.0f64 && (b != 0.0f64 || c != 0.0f64 || d != 0.0f64) { ret 7000i32 }
    if a == 0.0f64 && b != 0.0f64 { ret 7000i32 }
    if c == 0.0f64 && d != 0.0f64 { ret 7000i32 }
    if c < 0.0f64 { ret 7000i32 }
    if a + c < 0.0f64 { ret 7000i32 }
    if a == 0.0f64 && c == 0.0f64 { ret 7000i32 }
    if nmom > 20usize { ret 7010i32 }
    var y = a / (1.0f64 + b)
    var z = c / (1.0f64 - d)
    x[0usize] = xi + y + z
    if nmom == 1usize { ret 0i32 }
    y = y / (2.0f64 + b)
    z = z / (2.0f64 - d)
    let alam2 = y + z
    x[1usize] = alam2
    var m = 3usize
    while m < nmom + 1usize {
        let am = f64(m)
        y = y * (am - 2.0f64 - b) / (am + b)
        z = z * (am - 2.0f64 + d) / (am - d)
        x[m - 1usize] = (y + z) / alam2
        m += 1usize
    }
    ret 0i32
}

// lmrx: the first nmom L-moments (l1, l2, then the ratios t3 ..) of the distribution `kind`; ifail as in the library.
// The ln3 and wei kinds are the package's own wrappers over gno and gev.
fn lmrx(kind: i32, p: []const f64, nmom: usize, x: []f64) -> i32 {
    if kind == 0i32 { ret lmr_exp(p, nmom, x) }
    if kind == 1i32 { ret lmr_gam(p, nmom, x) }
    if kind == 2i32 { ret lmr_gev(p, nmom, x) }
    if kind == 3i32 { ret lmr_glo(p, nmom, x) }
    if kind == 4i32 { ret lmr_gno(p, nmom, x) }
    if kind == 5i32 { ret lmr_gpa(p, nmom, x) }
    if kind == 6i32 { ret lmr_gum(p, nmom, x) }
    if kind == 7i32 { ret lmr_kap(p, nmom, x) }
    if kind == 9i32 { ret lmr_nor(p, nmom, x) }
    if kind == 10i32 { ret lmr_pe3(p, nmom, x) }
    if kind == 11i32 { ret lmr_wak(p, nmom, x) }
    var q: [3]f64 = zero
    if kind == 8i32 {
        if p[2usize] <= 0.0f64 { ret 7000i32 }
        let expmu = math.exp[f64](p[1usize])
        q[0usize] = p[0usize] + expmu
        q[1usize] = expmu * p[2usize]
        q[2usize] = 0.0f64 - p[2usize]
        ret lmr_gno(q[0usize..3usize], nmom, x)
    }
    if p[1usize] <= 0.0f64 || p[2usize] <= 0.0f64 { ret 7000i32 }
    q[0usize] = 0.0f64
    q[1usize] = p[1usize] / p[2usize]
    q[2usize] = 1.0f64 / p[2usize]
    let r = lmr_gev(q[0usize..3usize], nmom, x)
    x[0usize] = p[0usize] + p[1usize] - x[0usize]
    if nmom >= 3usize { x[2usize] = 0.0f64 - x[2usize] }
    ret r
}

// ---- quantile and distribution functions ------------------------------------------------------------------------

fn wak_ok(p: []const f64) -> bool {
    let alpha = p[1usize]
    let beta = p[2usize]
    let gamma = p[3usize]
    let delta = p[4usize]
    if gamma > 0.0f64 && alpha + gamma > 0.0f64 && beta + delta > 0.0f64 { ret true }
    if gamma < 0.0f64 { ret false }
    if alpha + gamma < 0.0f64 { ret false }
    if beta + delta <= 0.0f64 && (beta != 0.0f64 || gamma != 0.0f64 || delta != 0.0f64) { ret false }
    if alpha == 0.0f64 && beta != 0.0f64 { ret false }
    if gamma == 0.0f64 && delta != 0.0f64 { ret false }
    ret true
}

// quax: the quantile function at probability f (NaN for invalid parameters)
fn quax(kind: i32, f: f64, p: []const f64) -> f64 {
    if kind == 0i32 { ret p[0usize] + p[1usize] * (0.0f64 - math.log[f64](1.0f64 - f)) }
    if kind == 1i32 { ret p[1usize] * fmax(0.0f64, nm.qgamma(f, p[0usize], 1.0f64, true, false)) }
    if kind == 2i32 {
        if p[2usize] == 0.0f64 { ret p[0usize] - p[1usize] * math.log[f64](0.0f64 - math.log[f64](f)) }
        ret p[0usize] + p[1usize] / p[2usize] * (1.0f64 - math.pow[f64](0.0f64 - math.log[f64](f), p[2usize]))
    }
    if kind == 3i32 {
        if p[2usize] == 0.0f64 { ret p[0usize] + p[1usize] * math.log[f64](f / (1.0f64 - f)) }
        ret p[0usize] + p[1usize] / p[2usize] * (1.0f64 - math.pow[f64]((1.0f64 - f) / f, p[2usize]))
    }
    if kind == 4i32 {
        if p[2usize] == 0.0f64 { ret p[0usize] + p[1usize] * dist.qnorm(f, 0.0f64, 1.0f64, true, false) }
        ret p[0usize] + p[1usize] / p[2usize] * (1.0f64 - math.exp[f64](0.0f64 - dist.qnorm(f, 0.0f64, 1.0f64, true, false) * p[2usize]))
    }
    if kind == 5i32 {
        if p[2usize] == 0.0f64 { ret p[0usize] + p[1usize] * (0.0f64 - math.log[f64](1.0f64 - f)) }
        ret p[0usize] + p[1usize] / p[2usize] * (1.0f64 - math.pow[f64](1.0f64 - f, p[2usize]))
    }
    if kind == 6i32 { ret p[0usize] - p[1usize] * math.log[f64](math.log[f64](1.0f64 / f)) }
    if kind == 7i32 {
        var v = f
        if p[3usize] == 0.0f64 { v = 0.0f64 - math.log[f64](v) } else { v = (1.0f64 - math.pow[f64](v, p[3usize])) / p[3usize] }
        if p[2usize] == 0.0f64 { v = 0.0f64 - math.log[f64](v) } else { v = (1.0f64 - math.pow[f64](v, p[2usize])) / p[2usize] }
        var res = p[0usize] + p[1usize] * v
        if p[3usize] <= 0.0f64 && p[2usize] <= 0.0f64 && v == 1.0f64 { res = 1.0f64 / 0.0f64 }
        ret res
    }
    if kind == 8i32 { ret p[0usize] + dist.qlnorm(f, p[1usize], p[2usize], true, false) }
    if kind == 9i32 { ret dist.qnorm(f, p[0usize], p[1usize], true, false) }
    if kind == 10i32 {
        if math.abs[f64](p[2usize]) <= 1.0e-8f64 { ret dist.qnorm(f, p[0usize], p[1usize], true, false) }
        let alpha = 4.0f64 / (p[2usize] * p[2usize])
        let beta = math.abs[f64](0.5f64 * p[1usize] * p[2usize])
        if p[2usize] > 0.0f64 { ret p[0usize] - alpha * beta + beta * fmax(0.0f64, nm.qgamma(f, alpha, 1.0f64, true, false)) }
        ret p[0usize] + alpha * beta - beta * fmax(0.0f64, nm.qgamma(1.0f64 - f, alpha, 1.0f64, true, false))
    }
    if kind == 11i32 {
        if !wak_ok(p) { ret nan() }
        let flog = 0.0f64 - math.log[f64](1.0f64 - f)
        var t1 = 0.0f64
        if p[1usize] != 0.0f64 {
            if p[2usize] == 0.0f64 { t1 = p[1usize] * flog } else { t1 = p[1usize] * (1.0f64 - math.exp[f64](0.0f64 - p[2usize] * flog)) / p[2usize] }
        }
        var t2 = 0.0f64
        if p[3usize] != 0.0f64 {
            if p[4usize] == 0.0f64 { t2 = p[3usize] * flog } else { t2 = p[3usize] * (0.0f64 - (1.0f64 - math.exp[f64](p[4usize] * flog)) / p[4usize]) }
        }
        ret p[0usize] + t1 + t2
    }
    ret p[0usize] + p[1usize] * math.pow[f64](0.0f64 - math.log[f64](1.0f64 - f), 1.0f64 / p[2usize])
}

// the reduced variate of the gev, glo, gno, gpa and kappa cdfs
fn red_y(x: f64, xi: f64, alpha: f64, k: f64) -> f64 {
    if k == 0.0f64 { ret (x - xi) / alpha }
    ret 0.0f64 - 1.0f64 / k * math.log[f64](fmax(0.0f64, 1.0f64 - k * (x - xi) / alpha))
}

// cdfwak: the Wakeby cdf by Halley iteration on the quantile function; ok is false when the iteration did not converge
fn cdf_wak(x: f64, p: []const f64, conv_ok: *bool) -> f64 {
    let xi = p[0usize]
    let a = p[1usize]
    let b = p[2usize]
    let c = p[3usize]
    let d = p[4usize]
    if b + d <= 0.0f64 && (b != 0.0f64 || c != 0.0f64 || d != 0.0f64) { ret nan() }
    if a == 0.0f64 && b != 0.0f64 { ret nan() }
    if c == 0.0f64 && d != 0.0f64 { ret nan() }
    if c < 0.0f64 || a + c < 0.0f64 { ret nan() }
    if a == 0.0f64 && c == 0.0f64 { ret nan() }
    var z = 0.1f64
    var eb = 0.0f64
    var bz = 0.0f64 - b * z
    if bz >= 0.0f64 - 170.0f64 { eb = math.exp[f64](bz) }
    var gb = z
    if math.abs[f64](b) > 1.0e-8f64 { gb = (1.0f64 - eb) / b }
    var ed = math.exp[f64](d * z)
    var gd = 0.0f64 - z
    if math.abs[f64](d) > 1.0e-8f64 { gd = (1.0f64 - ed) / d }
    let q10 = xi + a * gb - c * gd
    z = 5.0f64
    eb = 0.0f64
    bz = 0.0f64 - b * z
    if bz >= 0.0f64 - 170.0f64 { eb = math.exp[f64](bz) }
    gb = z
    if math.abs[f64](b) > 1.0e-8f64 { gb = (1.0f64 - eb) / b }
    ed = math.exp[f64](d * z)
    gd = 0.0f64 - z
    if math.abs[f64](d) > 1.0e-8f64 { gd = (1.0f64 - ed) / d }
    let q99 = xi + a * gb - c * gd
    if x <= xi { ret 0.0f64 }
    if b == 0.0f64 && c == 0.0f64 && d == 0.0f64 {
        z = (x - xi) / a
    } else if c == 0.0f64 {
        if x >= xi + a / b { ret 1.0f64 }
        z = 0.0f64 - math.log[f64](1.0f64 - (x - xi) * b / a) / b
    } else if a == 0.0f64 {
        z = math.log[f64](1.0f64 + (x - xi) * d / c) / d
    } else {
        if d < 0.0f64 && x >= xi + a / b - c / d { ret 1.0f64 }
        z = 0.7f64
        if x < q10 { z = 0.0f64 }
        if x >= q99 {
            if d < 0.0f64 { z = math.log[f64]((x - xi - a / b) * d / c + 1.0f64) / d }
            if d == 0.0f64 { z = (x - xi - a / b) / c }
            if d > 0.0f64 { z = math.log[f64]((x - xi) * d / c + 1.0f64) / d }
        }
        var it = 1usize
        var conv = false
        while it <= 20usize && !conv {
            eb = 0.0f64
            bz = 0.0f64 - b * z
            if bz >= 0.0f64 - 170.0f64 { eb = math.exp[f64](bz) }
            gb = z
            if math.abs[f64](b) > 1.0e-8f64 { gb = (1.0f64 - eb) / b }
            ed = math.exp[f64](d * z)
            gd = 0.0f64 - z
            if math.abs[f64](d) > 1.0e-8f64 { gd = (1.0f64 - ed) / d }
            let xest = xi + a * gb - c * gd
            let func = x - xest
            let deriv1 = a * eb + c * ed
            let deriv2 = 0.0f64 - a * b * eb + c * d * ed
            var temp = deriv1 + 0.5f64 * func * deriv2 / deriv1
            if temp <= 0.0f64 { temp = deriv1 }
            var zinc = func / temp
            if zinc > 3.0f64 { zinc = 3.0f64 }
            let znew = z + zinc
            if znew <= 0.0f64 {
                z = z * 0.2f64
            } else {
                z = znew
                if math.abs[f64](zinc) <= 1.0e-8f64 { conv = true }
            }
            it += 1usize
        }
        if !conv { *conv_ok = false }
    }
    if 0.0f64 - z < 0.0f64 - 170.0f64 { ret 1.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - z)
}

// cdfx: the distribution function at x (NaN for invalid parameters)
fn cdfx(kind: i32, x: f64, p: []const f64) -> f64 {
    if kind == 0i32 { ret 1.0f64 - math.exp[f64](0.0f64 - fmax(0.0f64, x - p[0usize]) / p[1usize]) }
    if kind == 1i32 { ret nm.pgamma(x / p[1usize], p[0usize], 1.0f64, true, false) }
    if kind == 2i32 { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - red_y(x, p[0usize], p[1usize], p[2usize]))) }
    if kind == 3i32 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - red_y(x, p[0usize], p[1usize], p[2usize]))) }
    if kind == 4i32 { ret dist.pnorm(red_y(x, p[0usize], p[1usize], p[2usize]), 0.0f64, 1.0f64, true, false) }
    if kind == 5i32 { ret 1.0f64 - math.exp[f64](0.0f64 - fmax(red_y(x, p[0usize], p[1usize], p[2usize]), 0.0f64)) }
    if kind == 6i32 { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - (x - p[0usize]) / p[1usize])) }
    if kind == 7i32 {
        var y = (x - p[0usize]) / p[1usize]
        if p[2usize] != 0.0f64 { y = 0.0f64 - 1.0f64 / p[2usize] * math.log[f64](fmax(0.0f64, 1.0f64 - p[2usize] * y)) }
        y = math.exp[f64](0.0f64 - y)
        if p[3usize] != 0.0f64 { y = 0.0f64 - 1.0f64 / p[3usize] * math.log[f64](fmax(0.0f64, 1.0f64 - p[3usize] * y)) }
        ret math.exp[f64](0.0f64 - y)
    }
    if kind == 8i32 { ret dist.plnorm(x - p[0usize], p[1usize], p[2usize], true, false) }
    if kind == 9i32 { ret dist.pnorm(x, p[0usize], p[1usize], true, false) }
    if kind == 10i32 {
        if math.abs[f64](p[2usize]) <= 1.0e-6f64 { ret dist.pnorm(x, p[0usize], p[1usize], true, false) }
        let alpha = 4.0f64 / (p[2usize] * p[2usize])
        let z = 2.0f64 * (x - p[0usize]) / (p[1usize] * p[2usize]) + alpha
        var r = nm.pgamma(fmax(0.0f64, z), alpha, 1.0f64, true, false)
        if p[2usize] < 0.0f64 { r = 1.0f64 - r }
        ret r
    }
    if kind == 11i32 {
        var good = true
        ret cdf_wak(x, p, &good)
    }
    if x <= p[0usize] { ret 0.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - math.pow[f64]((x - p[0usize]) / p[1usize], p[2usize]))
}

// ---- parameters from L-moments ----------------------------------------------------------------------------------

fn pel_gev(l: []const f64, q: []f64) -> i32 {
    let t3 = l[2usize]
    if l[1usize] <= 0.0f64 { ret 7000i32 }
    if math.abs[f64](t3) >= 1.0f64 { ret 7000i32 }
    let dl2 = 0.69314718f64
    let dl3 = 1.0986123f64
    var g = 0.0f64
    var ifail = 0i32
    var small = false
    var iterate = false
    if t3 <= 0.0f64 {
        g = (0.28377530f64 + t3 * (0.0f64 - 1.21096399f64 + t3 * (0.0f64 - 2.50728214f64 + t3 * (0.0f64 - 1.13455566f64 + t3 * (0.0f64 - 0.07138022f64))))) / (1.0f64 + t3 * (2.06189696f64 + t3 * (1.31912239f64 + t3 * 0.25077104f64)))
        if t3 < 0.0f64 - 0.8f64 {
            iterate = true
            if t3 <= 0.0f64 - 0.97f64 { g = 1.0f64 - math.log[f64](1.0f64 + t3) / dl2 }
        }
    } else {
        let z = 1.0f64 - t3
        g = (0.0f64 - 1.0f64 + z * (1.59921491f64 + z * (0.0f64 - 0.48832213f64 + z * 0.01573152f64))) / (1.0f64 + z * (0.0f64 - 0.64363929f64 + z * 0.08985247f64))
        if math.abs[f64](g) < 1.0e-5f64 { small = true }
    }
    if small {
        q[2usize] = 0.0f64
        q[1usize] = l[1usize] / dl2
        q[0usize] = l[0usize] - 0.57721566f64 * q[1usize]
        ret 0i32
    }
    if iterate {
        let t0 = (t3 + 3.0f64) * 0.5f64
        var it = 1usize
        var done = false
        while it <= 20usize && !done {
            let x2 = math.pow[f64](2.0f64, 0.0f64 - g)
            let x3 = math.pow[f64](3.0f64, 0.0f64 - g)
            let xx2 = 1.0f64 - x2
            let xx3 = 1.0f64 - x3
            let t = xx3 / xx2
            let deriv = (xx2 * x3 * dl3 - xx3 * x2 * dl2) / (xx2 * xx2)
            let gold = g
            g = g - (t - t0) / deriv
            if math.abs[f64](g - gold) <= 1.0e-6f64 * g { done = true }
            it += 1usize
        }
        if !done { ifail = 7020i32 }
    }
    q[2usize] = g
    let gam = math.exp[f64](xlgama(1.0f64 + g))
    q[1usize] = l[1usize] * g / (gam * (1.0f64 - math.pow[f64](2.0f64, 0.0f64 - g)))
    q[0usize] = l[0usize] - q[1usize] * (1.0f64 - gam) / g
    ret ifail
}

fn pel_kap(l: []const f64, q: []f64) -> i32 {
    var del1 = 0.0f64
    var del2 = 0.0f64
    var xg = 0.0f64
    var xh = 0.0f64
    let t3 = l[2usize]
    let t4 = l[3usize]
    q[0usize] = 0.0f64
    q[1usize] = 0.0f64
    q[2usize] = 0.0f64
    q[3usize] = 0.0f64
    if l[1usize] <= 0.0f64 { ret 7000i32 }
    if math.abs[f64](t3) >= 1.0f64 || math.abs[f64](t4) >= 1.0f64 { ret 7000i32 }
    if t4 <= (5.0f64 * t3 * t3 - 1.0f64) / 4.0f64 { ret 7000i32 }
    if t4 >= (5.0f64 * t3 * t3 + 1.0f64) / 6.0f64 { ret 2i32 }
    var g = (1.0f64 - 3.0f64 * t3) / (1.0f64 + t3)
    var h = 1.001f64
    var z = g + h * 0.725f64
    var xdist = 10.0f64
    var xz = 0.0f64
    var u1 = 0.0f64
    var alam2 = 0.0f64
    var it = 1usize
    while it <= 20usize {
        var i = 1usize
        var found = false
        var dist1 = 0.0f64
        var e1 = 0.0f64
        var e2 = 0.0f64
        var u2 = 0.0f64
        var u3 = 0.0f64
        var u4 = 0.0f64
        var tau3 = 0.0f64
        var tau4 = 0.0f64
        while i <= 10usize && !found {
            if g > 53.0f64 { ret 5i32 }
            if h <= 0.0f64 {
                u1 = math.exp[f64](xlgama(0.0f64 - 1.0f64 / h - g) - xlgama(0.0f64 - 1.0f64 / h + 1.0f64))
                u2 = math.exp[f64](xlgama(0.0f64 - 2.0f64 / h - g) - xlgama(0.0f64 - 2.0f64 / h + 1.0f64))
                u3 = math.exp[f64](xlgama(0.0f64 - 3.0f64 / h - g) - xlgama(0.0f64 - 3.0f64 / h + 1.0f64))
                u4 = math.exp[f64](xlgama(0.0f64 - 4.0f64 / h - g) - xlgama(0.0f64 - 4.0f64 / h + 1.0f64))
            } else {
                u1 = math.exp[f64](xlgama(1.0f64 / h) - xlgama(1.0f64 / h + 1.0f64 + g))
                u2 = math.exp[f64](xlgama(2.0f64 / h) - xlgama(2.0f64 / h + 1.0f64 + g))
                u3 = math.exp[f64](xlgama(3.0f64 / h) - xlgama(3.0f64 / h + 1.0f64 + g))
                u4 = math.exp[f64](xlgama(4.0f64 / h) - xlgama(4.0f64 / h + 1.0f64 + g))
            }
            alam2 = u1 - 2.0f64 * u2
            let alam3 = 0.0f64 - u1 + 6.0f64 * u2 - 6.0f64 * u3
            let alam4 = u1 - 12.0f64 * u2 + 30.0f64 * u3 - 20.0f64 * u4
            if alam2 == 0.0f64 { ret 5i32 }
            tau3 = alam3 / alam2
            tau4 = alam4 / alam2
            e1 = tau3 - t3
            e2 = tau4 - t4
            dist1 = fmax(math.abs[f64](e1), math.abs[f64](e2))
            if dist1 < xdist {
                found = true
            } else {
                del1 = 0.5f64 * del1
                del2 = 0.5f64 * del2
                g = xg - del1
                h = xh - del2
                i += 1usize
            }
        }
        if !found { ret 4i32 }
        if dist1 < 1.0e-6f64 {
            q[3usize] = h
            q[2usize] = g
            var temp = xlgama(1.0f64 + g)
            if temp > 170.0f64 { ret 6i32 }
            let gam = math.exp[f64](temp)
            temp = (1.0f64 + g) * math.log[f64](math.abs[f64](h))
            if temp > 170.0f64 { ret 6i32 }
            let hh = math.exp[f64](temp)
            q[1usize] = l[1usize] * g * hh / (alam2 * gam)
            q[0usize] = l[0usize] - q[1usize] / g * (1.0f64 - gam * u1 / hh)
            ret 0i32
        }
        xg = g
        xh = h
        xz = z
        xdist = dist1
        let rhh = 1.0f64 / (h * h)
        var u1g = 0.0f64
        var u2g = 0.0f64
        var u3g = 0.0f64
        var u4g = 0.0f64
        var u1h = 0.0f64
        var u2h = 0.0f64
        var u3h = 0.0f64
        var u4h = 0.0f64
        if h <= 0.0f64 {
            u1g = 0.0f64 - u1 * digamd(0.0f64 - 1.0f64 / h - g)
            u2g = 0.0f64 - u2 * digamd(0.0f64 - 2.0f64 / h - g)
            u3g = 0.0f64 - u3 * digamd(0.0f64 - 3.0f64 / h - g)
            u4g = 0.0f64 - u4 * digamd(0.0f64 - 4.0f64 / h - g)
            u1h = rhh * (0.0f64 - u1g - u1 * digamd(0.0f64 - 1.0f64 / h + 1.0f64))
            u2h = 2.0f64 * rhh * (0.0f64 - u2g - u2 * digamd(0.0f64 - 2.0f64 / h + 1.0f64))
            u3h = 3.0f64 * rhh * (0.0f64 - u3g - u3 * digamd(0.0f64 - 3.0f64 / h + 1.0f64))
            u4h = 4.0f64 * rhh * (0.0f64 - u4g - u4 * digamd(0.0f64 - 4.0f64 / h + 1.0f64))
        } else {
            u1g = 0.0f64 - u1 * digamd(1.0f64 / h + 1.0f64 + g)
            u2g = 0.0f64 - u2 * digamd(2.0f64 / h + 1.0f64 + g)
            u3g = 0.0f64 - u3 * digamd(3.0f64 / h + 1.0f64 + g)
            u4g = 0.0f64 - u4 * digamd(4.0f64 / h + 1.0f64 + g)
            u1h = rhh * (0.0f64 - u1g - u1 * digamd(1.0f64 / h))
            u2h = 2.0f64 * rhh * (0.0f64 - u2g - u2 * digamd(2.0f64 / h))
            u3h = 3.0f64 * rhh * (0.0f64 - u3g - u3 * digamd(3.0f64 / h))
            u4h = 4.0f64 * rhh * (0.0f64 - u4g - u4 * digamd(4.0f64 / h))
        }
        let dl2g = u1g - 2.0f64 * u2g
        let dl2h = u1h - 2.0f64 * u2h
        let dl3g = 0.0f64 - u1g + 6.0f64 * u2g - 6.0f64 * u3g
        let dl3h = 0.0f64 - u1h + 6.0f64 * u2h - 6.0f64 * u3h
        let dl4g = u1g - 12.0f64 * u2g + 30.0f64 * u3g - 20.0f64 * u4g
        let dl4h = u1h - 12.0f64 * u2h + 30.0f64 * u3h - 20.0f64 * u4h
        let d11 = (dl3g - tau3 * dl2g) / alam2
        let d12 = (dl3h - tau3 * dl2h) / alam2
        let d21 = (dl4g - tau4 * dl2g) / alam2
        let d22 = (dl4h - tau4 * dl2h) / alam2
        let det = d11 * d22 - d12 * d21
        let h11 = d22 / det
        let h12 = 0.0f64 - d12 / det
        let h21 = 0.0f64 - d21 / det
        let h22 = d11 / det
        del1 = e1 * h11 + e2 * h12
        del2 = e1 * h21 + e2 * h22
        g = xg - del1
        h = xh - del2
        z = g + h * 0.725f64
        var factor = 1.0f64
        if g <= 0.0f64 - 1.0f64 { factor = 0.8f64 * (xg + 1.0f64) / del1 }
        if h <= 0.0f64 - 1.0f64 { factor = fmin(factor, 0.8f64 * (xh + 1.0f64) / del2) }
        if z <= 0.0f64 - 1.0f64 { factor = fmin(factor, 0.8f64 * (xz + 1.0f64) / (xz - z)) }
        if h <= 0.0f64 && g * h <= 0.0f64 - 1.0f64 { factor = fmin(factor, 0.8f64 * (xg * xh + 1.0f64) / (xg * xh - g * h)) }
        if factor != 1.0f64 {
            del1 = del1 * factor
            del2 = del2 * factor
            g = xg - del1
            h = xh - del2
            z = g + h * 0.725f64
        }
        it += 1usize
    }
    ret 3i32
}

fn pel_pe3(l: []const f64, q: []f64) -> i32 {
    let t3 = math.abs[f64](l[2usize])
    if l[1usize] <= 0.0f64 || t3 >= 1.0f64 {
        q[0usize] = 0.0f64
        q[1usize] = 0.0f64
        q[2usize] = 0.0f64
        ret 7000i32
    }
    let rootpi = 1.7724539f64
    if t3 <= 1.0e-6f64 {
        q[0usize] = l[0usize]
        q[1usize] = l[1usize] * rootpi
        q[2usize] = 0.0f64
        ret 0i32
    }
    var alpha = 0.0f64
    if t3 >= 0.33333333f64 {
        let t = 1.0f64 - t3
        alpha = t * (0.36067f64 + t * (0.0f64 - 0.59567f64 + t * 0.25361f64)) / (1.0f64 + t * (0.0f64 - 2.78861f64 + t * (2.56096f64 + t * (0.0f64 - 0.77045f64))))
    } else {
        let t = 9.4247780f64 * t3 * t3
        alpha = (1.0f64 + 0.2906f64 * t) / (t * (1.0f64 + t * (0.1882f64 + t * 0.0442f64)))
    }
    let rtalph = math.sqrt[f64](alpha)
    let beta = rootpi * l[1usize] * math.exp[f64](xlgama(alpha) - xlgama(alpha + 0.5f64))
    q[0usize] = l[0usize]
    q[1usize] = beta * rtalph
    q[2usize] = 2.0f64 / rtalph
    if l[2usize] < 0.0f64 { q[2usize] = 0.0f64 - q[2usize] }
    ret 0i32
}

// the shared tail of the Wakeby fits: b and d from the roots of a quadratic, a and c by the formulas of each; false when the
// roots do not give a proper Wakeby (the caller then fits a generalised Pareto)
fn wak_roots(xa: f64, xb: f64, xc: f64, b: *f64, d: *f64) -> bool {
    var disc = xb * xb - 4.0f64 * xa * xc
    if disc < 0.0f64 { ret false }
    disc = math.sqrt[f64](disc)
    let root1 = 0.5f64 * (0.0f64 - xb + disc) / xa
    let root2 = 0.5f64 * (0.0f64 - xb - disc) / xa
    *b = fmax(root1, root2)
    *d = 0.0f64 - fmin(root1, root2)
    if *d >= 1.0f64 { ret false }
    ret true
}

fn pel_wak(l: []const f64, q: []f64) -> i32 {
    if l[1usize] <= 0.0f64 || math.abs[f64](l[2usize]) >= 1.0f64 || math.abs[f64](l[3usize]) >= 1.0f64 || math.abs[f64](l[4usize]) >= 1.0f64 {
        var i = 0usize
        while i < 5usize {
            q[i] = 0.0f64
            i += 1usize
        }
        ret 7000i32
    }
    let alam1 = l[0usize]
    let alam2 = l[1usize]
    let alam3 = l[2usize] * alam2
    let alam4 = l[3usize] * alam2
    let alam5 = l[4usize] * alam2
    let xn1 = 3.0f64 * alam2 - 25.0f64 * alam3 + 32.0f64 * alam4
    let xn2 = 0.0f64 - 3.0f64 * alam2 + 5.0f64 * alam3 + 8.0f64 * alam4
    let xn3 = 3.0f64 * alam2 + 5.0f64 * alam3 + 2.0f64 * alam4
    let xc1 = 7.0f64 * alam2 - 85.0f64 * alam3 + 203.0f64 * alam4 - 125.0f64 * alam5
    let xc2 = 0.0f64 - 7.0f64 * alam2 + 25.0f64 * alam3 + 7.0f64 * alam4 - 25.0f64 * alam5
    let xc3 = 7.0f64 * alam2 + 5.0f64 * alam3 - 7.0f64 * alam4 - 5.0f64 * alam5
    let xa = xn2 * xc3 - xc2 * xn3
    let xb = xn1 * xc3 - xc1 * xn3
    let xc = xn1 * xc2 - xc1 * xn2
    var b = 0.0f64
    var d = 0.0f64
    var a = 0.0f64
    var c = 0.0f64
    var xi = 0.0f64
    var good = wak_roots(xa, xb, xc, &b, &d)
    if good {
        a = (1.0f64 + b) * (2.0f64 + b) * (3.0f64 + b) / (4.0f64 * (b + d)) * ((1.0f64 + d) * alam2 - (3.0f64 - d) * alam3)
        c = 0.0f64 - (1.0f64 - d) * (2.0f64 - d) * (3.0f64 - d) / (4.0f64 * (b + d)) * ((1.0f64 - b) * alam2 - (3.0f64 + b) * alam3)
        xi = alam1 - a / (1.0f64 + b) - c / (1.0f64 - d)
        if !(c >= 0.0f64 && a + c >= 0.0f64) { good = false }
    }
    var ifail = 0i32
    if !good {
        ifail = 1i32
        d = 0.0f64 - (1.0f64 - 3.0f64 * l[2usize]) / (1.0f64 + l[2usize])
        c = (1.0f64 - d) * (2.0f64 - d) * l[1usize]
        b = 0.0f64
        a = 0.0f64
        xi = l[0usize] - c / (1.0f64 - d)
        if !(d > 0.0f64) {
            a = c
            b = 0.0f64 - d
            c = 0.0f64
            d = 0.0f64
        }
    }
    q[0usize] = xi
    q[1usize] = a
    q[2usize] = b
    q[3usize] = c
    q[4usize] = d
    ret ifail
}

fn pel_wa0(l: []const f64, q: []f64) -> i32 {
    if l[0usize] <= 0.0f64 || l[1usize] <= 0.0f64 || math.abs[f64](l[2usize]) >= 1.0f64 || math.abs[f64](l[3usize]) >= 1.0f64 {
        var i = 0usize
        while i < 5usize {
            q[i] = 0.0f64
            i += 1usize
        }
        ret 7000i32
    }
    let alam1 = l[0usize]
    let alam2 = l[1usize]
    let alam3 = l[2usize] * alam2
    let alam4 = l[3usize] * alam2
    let zn1 = 4.0f64 * alam1 - 11.0f64 * alam2 + 9.0f64 * alam3
    let zn2 = 0.0f64 - alam2 + 3.0f64 * alam3
    let zn3 = alam2 + alam3
    let zc1 = 10.0f64 * alam1 - 29.0f64 * alam2 + 35.0f64 * alam3 - 16.0f64 * alam4
    let zc2 = 0.0f64 - alam2 + 5.0f64 * alam3 - 4.0f64 * alam4
    let zc3 = alam2 - alam4
    let za = zn2 * zc3 - zc2 * zn3
    let zb = zn1 * zc3 - zc1 * zn3
    let zc = zn1 * zc2 - zc1 * zn2
    var b = 0.0f64
    var d = 0.0f64
    var a = 0.0f64
    var c = 0.0f64
    var good = wak_roots(za, zb, zc, &b, &d)
    if good {
        a = (1.0f64 + b) * (2.0f64 + b) / (b + d) * (alam1 - (2.0f64 - d) * alam2)
        c = 0.0f64 - (1.0f64 - d) * (2.0f64 - d) / (b + d) * (alam1 - (2.0f64 + b) * alam2)
        if !(c >= 0.0f64 && a + c >= 0.0f64) { good = false }
    }
    var ifail = 0i32
    if !good {
        ifail = 1i32
        d = 2.0f64 - alam1 / alam2
        c = (1.0f64 - d) * alam1
        b = 0.0f64
        a = 0.0f64
        if !(d > 0.0f64) {
            a = c
            b = 0.0f64 - d
            c = 0.0f64
            d = 0.0f64
        }
    }
    q[0usize] = 0.0f64
    q[1usize] = a
    q[2usize] = b
    q[3usize] = c
    q[4usize] = d
    ret ifail
}

// pelx: parameters (as listed at the top) from L-moments (l1, l2, then the ratios; gam, exp, gum, nor need 2; gev, glo, gno,
// gpa, pe3, ln3, wei 3; kap and wa0 4; wak 5). `bound` is the lower bound of the gpa, ln3, wei and wak (NaN: none).
// Returns the library's ifail, 7000 when the L-moments are invalid.
fn pelx(kind: i32, l: []const f64, bound: f64, q: []f64) -> i32 {
    let bounded = bound == bound
    if kind == 0i32 {
        if l[1usize] <= 0.0f64 { ret 7000i32 }
        q[1usize] = 2.0f64 * l[1usize]
        q[0usize] = l[0usize] - q[1usize]
        ret 0i32
    }
    if kind == 1i32 {
        if l[0usize] <= l[1usize] || l[1usize] <= 0.0f64 {
            q[0usize] = 0.0f64
            q[1usize] = 0.0f64
            ret 7000i32
        }
        let cv = l[1usize] / l[0usize]
        var alpha = 0.0f64
        if cv >= 0.5f64 {
            let t = 1.0f64 - cv
            alpha = t * (0.7213f64 + t * (0.0f64 - 0.5947f64)) / (1.0f64 + t * (0.0f64 - 2.1817f64 + t * 1.2113f64))
        } else {
            let t = 3.1415927f64 * cv * cv
            alpha = (1.0f64 + (0.0f64 - 0.3080f64) * t) / (t * (1.0f64 + t * (0.0f64 - 0.05812f64 + t * 0.01765f64)))
        }
        q[0usize] = alpha
        q[1usize] = l[0usize] / alpha
        ret 0i32
    }
    if kind == 2i32 { ret pel_gev(l, q) }
    if kind == 3i32 {
        let g = 0.0f64 - l[2usize]
        if l[1usize] <= 0.0f64 || math.abs[f64](g) >= 1.0f64 { ret 7000i32 }
        if math.abs[f64](g) <= 1.0e-6f64 {
            q[2usize] = 0.0f64
            q[1usize] = l[1usize]
            q[0usize] = l[0usize]
            ret 0i32
        }
        let gg = g * pi_const() / math.sin(g * pi_const())
        let a = l[1usize] / gg
        q[0usize] = l[0usize] - a * (1.0f64 - gg) / g
        q[1usize] = a
        q[2usize] = g
        ret 0i32
    }
    if kind == 4i32 {
        let t3 = l[2usize]
        if l[1usize] <= 0.0f64 || math.abs[f64](t3) >= 1.0f64 { ret 7000i32 }
        if math.abs[f64](t3) >= 0.95f64 {
            q[0usize] = 0.0f64
            q[1usize] = 0.0f64 - 1.0f64
            q[2usize] = 0.0f64
            ret 7010i32
        }
        if math.abs[f64](t3) <= 1.0e-8f64 {
            q[0usize] = l[0usize]
            q[1usize] = l[1usize] * 1.772453850905516027f64
            q[2usize] = 0.0f64
            ret 0i32
        }
        let tt = t3 * t3
        let g = 0.0f64 - t3 * (0.20466534e1f64 + tt * (0.0f64 - 0.36544371e1f64 + tt * (0.18396733e1f64 + tt * (0.0f64 - 0.20360244f64)))) / (1.0f64 + tt * (0.0f64 - 0.20182173e1f64 + tt * (0.12420401e1f64 + tt * (0.0f64 - 0.21741801f64))))
        let e = math.exp[f64](0.5f64 * g * g)
        let a = l[1usize] * g / (e * xerf(0.5f64 * g))
        q[0usize] = l[0usize] + a * (e - 1.0f64) / g
        q[1usize] = a
        q[2usize] = g
        ret 0i32
    }
    if kind == 5i32 {
        if bounded {
            let lam1 = l[0usize] - bound
            if lam1 <= 0.0f64 || l[1usize] <= 0.0f64 || l[1usize] >= lam1 { ret 7000i32 }
            let k = lam1 / l[1usize] - 2.0f64
            q[0usize] = bound
            q[1usize] = (1.0f64 + k) * lam1
            q[2usize] = k
            ret 0i32
        }
        let t3 = l[2usize]
        if l[1usize] <= 0.0f64 || math.abs[f64](t3) >= 1.0f64 { ret 7000i32 }
        let g = (1.0f64 - 3.0f64 * t3) / (1.0f64 + t3)
        q[2usize] = g
        q[1usize] = (1.0f64 + g) * (2.0f64 + g) * l[1usize]
        q[0usize] = l[0usize] - q[1usize] / (1.0f64 + g)
        ret 0i32
    }
    if kind == 6i32 {
        if l[1usize] <= 0.0f64 { ret 7000i32 }
        q[1usize] = l[1usize] / 0.693147180559945309f64
        q[0usize] = l[0usize] - 0.577215664901532861f64 * q[1usize]
        ret 0i32
    }
    if kind == 7i32 { ret pel_kap(l, q) }
    if kind == 9i32 {
        if l[1usize] <= 0.0f64 { ret 7000i32 }
        q[1usize] = l[1usize] * 1.772453850905516027f64
        q[0usize] = l[0usize]
        ret 0i32
    }
    if kind == 10i32 { ret pel_pe3(l, q) }
    if kind == 11i32 {
        if bounded {
            var m: [4]f64 = zero
            m[0usize] = l[0usize] - bound
            m[1usize] = l[1usize]
            m[2usize] = l[2usize]
            m[3usize] = l[3usize]
            let r = pel_wa0(m[0usize..4usize], q)
            q[0usize] = q[0usize] + bound
            ret r
        }
        ret pel_wak(l, q)
    }
    if kind == 12i32 { ret pel_wa0(l, q) }
    if kind == 8i32 {
        if bounded {
            let lam1 = l[0usize] - bound
            if lam1 <= 0.0f64 || l[1usize] <= 0.0f64 || l[1usize] >= lam1 { ret 7000i32 }
            let sigma = math.sqrt[f64](2.0f64) * dist.qnorm((1.0f64 + l[1usize] / lam1) / 2.0f64, 0.0f64, 1.0f64, true, false)
            q[0usize] = bound
            q[1usize] = math.log[f64](lam1) - 0.5f64 * sigma * sigma
            q[2usize] = sigma
            ret 0i32
        }
        if l[1usize] <= 0.0f64 || l[2usize] >= 1.0f64 || l[2usize] <= 0.0f64 { ret 7000i32 }
        var g: [3]f64 = zero
        let r = pelx(4i32, l, nan(), g[0usize..3usize])
        if r == 7010i32 { ret r }
        let sigma = 0.0f64 - g[2usize]
        let expmu = g[1usize] / sigma
        q[0usize] = g[0usize] - expmu
        q[1usize] = math.log[f64](expmu)
        q[2usize] = sigma
        ret 0i32
    }
    // weibull
    if bounded {
        let lam1 = l[0usize] - bound
        if lam1 <= 0.0f64 || l[1usize] <= 0.0f64 || l[1usize] >= lam1 { ret 7000i32 }
        let delta = 0.0f64 - math.log[f64](2.0f64) / math.log[f64](1.0f64 - l[1usize] / lam1)
        q[0usize] = bound
        q[1usize] = lam1 / nm.gammafn(1.0f64 + 1.0f64 / delta)
        q[2usize] = delta
        ret 0i32
    }
    if l[1usize] <= 0.0f64 || l[2usize] >= 1.0f64 || l[2usize] <= 0.0f64 - 0.16992500144231237f64 { ret 7000i32 }
    var m: [3]f64 = zero
    m[0usize] = 0.0f64 - l[0usize]
    m[1usize] = l[1usize]
    m[2usize] = 0.0f64 - l[2usize]
    var pg: [3]f64 = zero
    let r = pel_gev(m[0usize..3usize], pg[0usize..3usize])
    let delta = 1.0f64 / pg[2usize]
    let beta = pg[1usize] / pg[2usize]
    q[0usize] = 0.0f64 - pg[0usize] - beta
    q[1usize] = beta
    q[2usize] = delta
    ret r
}

// ---- sample L-moments with trimming -----------------------------------------------------------------------------

// samlm: the library's SAMLM on sorted data, the first nmom (<= n) L-moments (the ratios are not taken here)
fn samlm(s: []const f64, nmom: usize, sorted: bool, x: []f64) {
    let n = s.len
    let dn = f64(n)
    var coef1: [64]f64 = zero
    var coef2: [64]f64 = zero
    var j = 0usize
    while j < nmom {
        x[j] = 0.0f64
        j += 1usize
    }
    if nmom <= 2usize {
        var sum1 = 0.0f64
        var sum2 = 0.0f64
        var temp = 0.0f64 - dn + 1.0f64
        var i = 0usize
        while i < n {
            sum1 += s[i]
            sum2 += s[i] * temp
            temp += 2.0f64
            i += 1usize
        }
        x[0usize] = sum1 / dn
        if nmom == 1usize { ret }
        x[1usize] = sum2 / (dn * (dn - 1.0f64))
        if sorted && s[0usize] >= 0.0f64 && x[1usize] > x[0usize] { x[1usize] = x[0usize] }
        ret
    }
    j = 3usize
    while j < nmom + 1usize {
        let t = 1.0f64 / (f64(j - 1usize) * f64(n + 1usize - j))
        coef1[j] = f64(j + j - 3usize) * t
        coef2[j] = f64(j - 2usize) * f64(n + j - 2usize) * t
        j += 1usize
    }
    var temp = 0.0f64 - dn - 1.0f64
    let cst = 1.0f64 / (dn - 1.0f64)
    let nhalf = n / 2usize
    var i = 1usize
    while i <= nhalf {
        temp = temp + 2.0f64
        let xi = s[i - 1usize]
        let xii = s[n - i]
        let termp = xi + xii
        let termn = xi - xii
        x[0usize] = x[0usize] + termp
        var s1 = 1.0f64
        var sv = temp * cst
        x[1usize] = x[1usize] + sv * termn
        j = 3usize
        while j <= nmom {
            var s2 = s1
            s1 = sv
            sv = coef1[j] * temp * s1 - coef2[j] * s2
            x[j - 1usize] = x[j - 1usize] + sv * termp
            if j != nmom {
                let jj = j + 1usize
                s2 = s1
                s1 = sv
                sv = coef1[jj] * temp * s1 - coef2[jj] * s2
                x[jj - 1usize] = x[jj - 1usize] + sv * termn
            }
            j += 2usize
        }
        i += 1usize
    }
    if n != nhalf + nhalf {
        let term = s[nhalf]
        var sv = 1.0f64
        x[0usize] = x[0usize] + term
        j = 3usize
        while j <= nmom {
            sv = 0.0f64 - coef2[j] * sv
            x[j - 1usize] = x[j - 1usize] + sv * term
            j += 2usize
        }
    }
    let rn = 1.0f64 / dn
    j = 3usize
    while j <= nmom {
        x[j - 1usize] = x[j - 1usize] * rn
        j += 1usize
    }
    x[0usize] = x[0usize] * rn
    x[1usize] = x[1usize] * rn
}

// samlmu_trim: R samlmu(x, nmom, ratios = ratios, trim = c(t1, t2)); NaN where there are too few data for the moment
fn samlmu_trim(a: *mem.Arena, x: []const f64, nmom: usize, t1: usize, t2: usize, ratios: bool, out: []f64) -> err {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    var maxmom = nmom + t1 + t2
    if n < maxmom { maxmom = n }
    var actual = 0usize
    if maxmom > t1 + t2 { actual = maxmom - t1 - t2 }
    i = 0usize
    while i < nmom {
        out[i] = nan()
        i += 1usize
    }
    if actual == 0usize { ret ok }
    var sorted = true
    if t1 + t2 > 0usize {
        var lo = math.abs[f64](s[0usize])
        var hi = lo
        i = 1usize
        while i < n {
            let v = math.abs[f64](s[i])
            if v < lo { lo = v }
            if v > hi { hi = v }
            i += 1usize
        }
        if hi / lo > 1.0e8f64 {
            sorted = false
            i = 0usize
            while i < t1 {
                s[i] = s[t1]
                i += 1usize
            }
            i = 1usize
            while i <= t2 {
                s[n - i] = s[n - 1usize - t2]
                i += 1usize
            }
        }
    }
    var lm: [64]f64 = zero
    var nw: [64]f64 = zero
    samlm(s, maxmom, sorted, lm[0usize..64usize])
    var j = 1usize
    while j <= t2 {
        maxmom -= 1usize
        var r = 1usize
        while r <= maxmom {
            nw[r - 1usize] = (lm[r - 1usize] * f64(r + j) - lm[r] * f64(r + 1usize)) / f64(2usize * r + j - 1usize)
            r += 1usize
        }
        r = 0usize
        while r < maxmom {
            lm[r] = nw[r]
            r += 1usize
        }
        j += 1usize
    }
    j = 1usize
    while j <= t1 {
        maxmom -= 1usize
        var r = 1usize
        while r <= maxmom {
            nw[r - 1usize] = (lm[r - 1usize] * f64(r + j + t2) + lm[r] * f64(r + 1usize) * f64(r + t2) / f64(r)) / f64(2usize * r + j + t2 - 1usize)
            r += 1usize
        }
        r = 0usize
        while r < maxmom {
            lm[r] = nw[r]
            r += 1usize
        }
        j += 1usize
    }
    var same = true
    i = t1 + 1usize
    while i < n - t2 {
        if s[i] != s[t1] { same = false }
        i += 1usize
    }
    if same {
        i = 1usize
        while i < maxmom {
            lm[i] = 0.0f64
            i += 1usize
        }
    }
    i = 0usize
    while i < nmom && i < maxmom {
        out[i] = lm[i]
        i += 1usize
    }
    if ratios && nmom > 2usize {
        i = 2usize
        while i < nmom {
            out[i] = out[i] / out[1usize]
            i += 1usize
        }
    }
    ret ok
}
