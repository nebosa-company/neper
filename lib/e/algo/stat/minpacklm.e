// R minpack.lm::nls.lm without an analytic Jacobian: MINPACK's lmdif (Levenberg-Marquardt with the forward
// difference Jacobian of fdjac2, the QR factorisation with column pivoting of qrfac, the trust-region parameter of
// lmpar and the triangular solve of qrsolv) ported line for line, with the package's wrapper around it: the
// parameters clamped into [lower, upper] on every evaluation, `nprint = 1` internally so that one iteration is
// counted per Jacobian evaluation plus one at the end, and the stop at `maxiter` reported as info -1.
//
// Not here: lmder (an analytic Jacobian), the `diag` option (mode 2), the hessian output, nlsLM's model interface.

use e.math
use e.mem

type Fit = struct { info: i64, nfev: i64, niter: i64, deviance: f64 }

fn rdwarf() -> f64 { ret 3.834e-20f64 }
fn rgiant() -> f64 { ret 1.304e19f64 }

// MINPACK's scaled Euclidean norm
fn enorm(x: []const f64) -> f64 {
    var s1 = 0.0f64
    var s2 = 0.0f64
    var s3 = 0.0f64
    var x1max = 0.0f64
    var x3max = 0.0f64
    let n = x.len
    let agiant = rgiant() / f64(n)
    var i = 0usize
    while i < n {
        let xabs = math.abs[f64](x[i])
        if xabs > rdwarf() && xabs < agiant {
            s2 += xabs * xabs
        } else if xabs > rdwarf() {
            if xabs > x1max {
                s1 = 1.0f64 + s1 * (x1max / xabs) * (x1max / xabs)
                x1max = xabs
            } else {
                s1 += (xabs / x1max) * (xabs / x1max)
            }
        } else {
            if xabs > x3max {
                s3 = 1.0f64 + s3 * (x3max / xabs) * (x3max / xabs)
                x3max = xabs
            } else if xabs != 0.0f64 {
                s3 += (xabs / x3max) * (xabs / x3max)
            }
        }
        i += 1usize
    }
    if s1 != 0.0f64 { ret x1max * math.sqrt[f64](s1 + (s2 / x1max) / x1max) }
    if s2 != 0.0f64 {
        if s2 >= x3max { ret math.sqrt[f64](s2 * (1.0f64 + (x3max / s2) * (x3max * s3))) }
        ret math.sqrt[f64](x3max * ((s2 / x3max) + (x3max * s3)))
    }
    ret x3max * math.sqrt[f64](s3)
}

type Ctx[C: type] = struct { f: fn(*C, []const f64, []f64), user: *C, lower: []const f64, upper: []const f64, niter: i64, maxiter: i64 }

// the package's fcn: clamp par in place, then evaluate (iflag 1 and 2); iflag 0 only counts
fn call[C: type](o: *Ctx[C], x: []f64, fvec: []f64, iflag: i64) -> i64 {
    var i = 0usize
    while i < x.len {
        if x[i] < o.lower[i] { x[i] = o.lower[i] }
        if x[i] > o.upper[i] { x[i] = o.upper[i] }
        i += 1usize
    }
    if iflag == 0i64 {
        o.niter += 1i64
    } else {
        o.f(o.user, x, fvec)
    }
    if o.niter == o.maxiter { ret 0i64 - 1i64 }
    ret iflag
}

fn fdjac2[C: type](o: *Ctx[C], m: usize, n: usize, x: []f64, fvec: []const f64, fjac: []f64, epsfcn: f64, wa: []f64) -> i64 {
    let epsmch = 2.220446049250313e-16f64
    var e = epsfcn
    if epsmch > e { e = epsmch }
    let eps = math.sqrt[f64](e)
    var j = 0usize
    while j < n {
        let temp = x[j]
        var h = eps * math.abs[f64](temp)
        if h == 0.0f64 { h = eps }
        x[j] = temp + h
        let fl = call[C](o, x, wa, 2i64)
        if fl < 0i64 { ret fl }
        x[j] = temp
        var i = 0usize
        while i < m {
            fjac[j * m + i] = (wa[i] - fvec[i]) / h
            i += 1usize
        }
        j += 1usize
    }
    ret 2i64
}

fn qrfac(m: usize, n: usize, a: []f64, ipvt: []usize, rdiag: []f64, acnorm: []f64, wa: []f64) {
    let epsmch = 2.220446049250313e-16f64
    var j = 0usize
    while j < n {
        acnorm[j] = enorm(a[j * m..j * m + m])
        rdiag[j] = acnorm[j]
        wa[j] = rdiag[j]
        ipvt[j] = j
        j += 1usize
    }
    var minmn = m
    if n < m { minmn = n }
    j = 0usize
    while j < minmn {
        var kmax = j
        var k = j
        while k < n {
            if rdiag[k] > rdiag[kmax] { kmax = k }
            k += 1usize
        }
        if kmax != j {
            var i = 0usize
            while i < m {
                let t = a[j * m + i]
                a[j * m + i] = a[kmax * m + i]
                a[kmax * m + i] = t
                i += 1usize
            }
            rdiag[kmax] = rdiag[j]
            wa[kmax] = wa[j]
            let kk = ipvt[j]
            ipvt[j] = ipvt[kmax]
            ipvt[kmax] = kk
        }
        var ajnorm = enorm(a[j * m + j..j * m + m])
        if ajnorm != 0.0f64 {
            if a[j * m + j] < 0.0f64 { ajnorm = 0.0f64 - ajnorm }
            var i = j
            while i < m {
                a[j * m + i] = a[j * m + i] / ajnorm
                i += 1usize
            }
            a[j * m + j] = a[j * m + j] + 1.0f64
            var kk = j + 1usize
            while kk < n {
                var sum = 0.0f64
                i = j
                while i < m {
                    sum += a[j * m + i] * a[kk * m + i]
                    i += 1usize
                }
                let temp = sum / a[j * m + j]
                i = j
                while i < m {
                    a[kk * m + i] = a[kk * m + i] - temp * a[j * m + i]
                    i += 1usize
                }
                if rdiag[kk] != 0.0f64 {
                    let t2 = a[kk * m + j] / rdiag[kk]
                    var inner = 1.0f64 - t2 * t2
                    if inner < 0.0f64 { inner = 0.0f64 }
                    rdiag[kk] = rdiag[kk] * math.sqrt[f64](inner)
                    let ratio = rdiag[kk] / wa[kk]
                    if !(0.05f64 * ratio * ratio > epsmch) {
                        rdiag[kk] = enorm(a[kk * m + j + 1usize..kk * m + m])
                        wa[kk] = rdiag[kk]
                    }
                }
                kk += 1usize
            }
        }
        rdiag[j] = 0.0f64 - ajnorm
        j += 1usize
    }
}

fn qrsolv(n: usize, ldr: usize, r: []f64, ipvt: []const usize, diag: []const f64, qtb: []const f64, x: []f64, sdiag: []f64, wa: []f64) {
    var j = 0usize
    while j < n {
        var i = j
        while i < n {
            r[j * ldr + i] = r[i * ldr + j]
            i += 1usize
        }
        x[j] = r[j * ldr + j]
        wa[j] = qtb[j]
        j += 1usize
    }
    j = 0usize
    while j < n {
        let l = ipvt[j]
        if diag[l] != 0.0f64 {
            var k = j
            while k < n {
                sdiag[k] = 0.0f64
                k += 1usize
            }
            sdiag[j] = diag[l]
            var qtbpj = 0.0f64
            k = j
            while k < n {
                if sdiag[k] != 0.0f64 {
                    var cs = 0.0f64
                    var sn = 0.0f64
                    if math.abs[f64](r[k * ldr + k]) < math.abs[f64](sdiag[k]) {
                        let cotan = r[k * ldr + k] / sdiag[k]
                        sn = 0.5f64 / math.sqrt[f64](0.25f64 + 0.25f64 * cotan * cotan)
                        cs = sn * cotan
                    } else {
                        let tn = sdiag[k] / r[k * ldr + k]
                        cs = 0.5f64 / math.sqrt[f64](0.25f64 + 0.25f64 * tn * tn)
                        sn = cs * tn
                    }
                    r[k * ldr + k] = cs * r[k * ldr + k] + sn * sdiag[k]
                    let temp = cs * wa[k] + sn * qtbpj
                    qtbpj = 0.0f64 - sn * wa[k] + cs * qtbpj
                    wa[k] = temp
                    var i = k + 1usize
                    while i < n {
                        let t2 = cs * r[k * ldr + i] + sn * sdiag[i]
                        sdiag[i] = 0.0f64 - sn * r[k * ldr + i] + cs * sdiag[i]
                        r[k * ldr + i] = t2
                        i += 1usize
                    }
                }
                k += 1usize
            }
        }
        sdiag[j] = r[j * ldr + j]
        r[j * ldr + j] = x[j]
        j += 1usize
    }
    var nsing = n
    j = 0usize
    while j < n {
        if sdiag[j] == 0.0f64 && nsing == n { nsing = j }
        if nsing < n { wa[j] = 0.0f64 }
        j += 1usize
    }
    var kk = 0usize
    while kk < nsing {
        let jj = nsing - 1usize - kk
        var sum = 0.0f64
        var i = jj + 1usize
        while i < nsing {
            sum += r[jj * ldr + i] * wa[i]
            i += 1usize
        }
        wa[jj] = (wa[jj] - sum) / sdiag[jj]
        kk += 1usize
    }
    j = 0usize
    while j < n {
        x[ipvt[j]] = wa[j]
        j += 1usize
    }
}

fn lmpar(n: usize, ldr: usize, r: []f64, ipvt: []const usize, diag: []const f64, qtb: []const f64, delta: f64, par: *f64, x: []f64, sdiag: []f64, wa1: []f64, wa2: []f64) {
    let dwarf = 2.2250738585072014e-308f64
    var nsing = n
    var j = 0usize
    while j < n {
        wa1[j] = qtb[j]
        if r[j * ldr + j] == 0.0f64 && nsing == n { nsing = j }
        if nsing < n { wa1[j] = 0.0f64 }
        j += 1usize
    }
    var k = 0usize
    while k < nsing {
        let jj = nsing - 1usize - k
        wa1[jj] = wa1[jj] / r[jj * ldr + jj]
        let temp = wa1[jj]
        var i = 0usize
        while i < jj {
            wa1[i] = wa1[i] - r[jj * ldr + i] * temp
            i += 1usize
        }
        k += 1usize
    }
    j = 0usize
    while j < n {
        x[ipvt[j]] = wa1[j]
        j += 1usize
    }
    var iter = 0usize
    j = 0usize
    while j < n {
        wa2[j] = diag[j] * x[j]
        j += 1usize
    }
    var dxnorm = enorm(wa2[0usize..n])
    var fp = dxnorm - delta
    if fp <= 0.1f64 * delta {
        *par = 0.0f64
        ret
    }
    var parl = 0.0f64
    if nsing >= n {
        j = 0usize
        while j < n {
            let l = ipvt[j]
            wa1[j] = diag[l] * (wa2[l] / dxnorm)
            j += 1usize
        }
        j = 0usize
        while j < n {
            var sum = 0.0f64
            var i = 0usize
            while i < j {
                sum += r[j * ldr + i] * wa1[i]
                i += 1usize
            }
            wa1[j] = (wa1[j] - sum) / r[j * ldr + j]
            j += 1usize
        }
        let temp = enorm(wa1)
        parl = ((fp / delta) / temp) / temp
    }
    j = 0usize
    while j < n {
        var sum = 0.0f64
        var i = 0usize
        while i <= j {
            sum += r[j * ldr + i] * qtb[i]
            i += 1usize
        }
        let l = ipvt[j]
        wa1[j] = sum / diag[l]
        j += 1usize
    }
    let gnorm = enorm(wa1)
    var paru = gnorm / delta
    if paru == 0.0f64 {
        var d = delta
        if 0.1f64 < d { d = 0.1f64 }
        paru = dwarf / d
    }
    var p = *par
    if parl > p { p = parl }
    if paru < p { p = paru }
    if p == 0.0f64 { p = gnorm / dxnorm }
    while true {
        iter += 1usize
        if p == 0.0f64 {
            var t = 0.001f64 * paru
            if dwarf > t { t = dwarf }
            p = t
        }
        let temp = math.sqrt[f64](p)
        j = 0usize
        while j < n {
            wa1[j] = temp * diag[j]
            j += 1usize
        }
        qrsolv(n, ldr, r, ipvt, wa1, qtb, x, sdiag, wa2)
        j = 0usize
        while j < n {
            wa2[j] = diag[j] * x[j]
            j += 1usize
        }
        dxnorm = enorm(wa2[0usize..n])
        let prev = fp
        fp = dxnorm - delta
        if math.abs[f64](fp) <= 0.1f64 * delta || (parl == 0.0f64 && fp <= prev && prev < 0.0f64) || iter == 10usize { break }
        j = 0usize
        while j < n {
            let l = ipvt[j]
            wa1[j] = diag[l] * (wa2[l] / dxnorm)
            j += 1usize
        }
        j = 0usize
        while j < n {
            wa1[j] = wa1[j] / sdiag[j]
            let t = wa1[j]
            var i = j + 1usize
            while i < n {
                wa1[i] = wa1[i] - r[j * ldr + i] * t
                i += 1usize
            }
            j += 1usize
        }
        let tt = enorm(wa1)
        let parc = ((fp / delta) / tt) / tt
        if fp > 0.0f64 && p > parl { parl = p }
        if fp < 0.0f64 && p < paru { paru = p }
        var np = p + parc
        if parl > np { np = parl }
        p = np
    }
    *par = p
    if iter == 0usize { *par = 0.0f64 }
}

// nls.lm(par, lower, upper, fn) with the default control (ftol = ptol = sqrt(eps), gtol = 0, epsfcn = 0,
// factor = 100, maxiter = 50, maxfev = 100 (n + 1)); x holds the start and receives the solution; fn writes the
// m residuals
fn nls_lm_core[C: type](a: *mem.Arena, f: fn(*C, []const f64, []f64), jac: fn(*C, []const f64, []f64), analytic: bool, user: *C, m: usize, n: usize, x: []f64, lower: []const f64, upper: []const f64, ftol: f64, ptol: f64, gtol: f64, maxfev: i64, maxiter: i64) -> (Fit, err) {
    var fit: Fit = zero
    let (fvec, e1) = mem.alloc[f64](a, m)
    let (fjac, e2) = mem.alloc[f64](a, m * n)
    let (diag, e3) = mem.alloc[f64](a, n)
    let (qtf, e4) = mem.alloc[f64](a, n)
    let (wa1, e5) = mem.alloc[f64](a, n)
    let (wa2, e6) = mem.alloc[f64](a, n)
    let (wa3, e7) = mem.alloc[f64](a, n)
    let (wa4, e8) = mem.alloc[f64](a, m)
    let (ipvt, e9) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (fit, e1) }
    var o = Ctx[C] { f: f, user: user, lower: lower, upper: upper, niter: 0i64, maxiter: maxiter }
    let epsmch = 2.220446049250313e-16f64
    let factor = 100.0f64
    var info = 0i64
    var nfev = 0i64
    var iflag = call[C](&o, x, fvec, 1i64)
    nfev = 1i64
    var par = 0.0f64
    var iter = 1i64
    var delta = 0.0f64
    var xnorm = 0.0f64
    var fnorm = enorm(fvec)
    var j = 0usize
    var i = 0usize
    var outer = iflag >= 0i64
    while outer {
        if analytic {
            // lmder: the user's Jacobian of the residuals at the clamped x, in the column-major layout fdjac2 fills; no function evaluations are charged
            jac(user, x, fjac)
            iflag = 2i64
        } else {
            iflag = fdjac2[C](&o, m, n, x, fvec, fjac, 0.0f64, wa4)
            nfev += i64(n)
        }
        if iflag < 0i64 { break }
        iflag = call[C](&o, x, fvec, 0i64)
        if iflag < 0i64 { break }
        qrfac(m, n, fjac, ipvt, wa1, wa2, wa3)
        if iter == 1i64 {
            j = 0usize
            while j < n {
                diag[j] = wa2[j]
                if wa2[j] == 0.0f64 { diag[j] = 1.0f64 }
                wa3[j] = diag[j] * x[j]
                j += 1usize
            }
            xnorm = enorm(wa3)
            delta = factor * xnorm
            if delta == 0.0f64 { delta = factor }
        }
        i = 0usize
        while i < m {
            wa4[i] = fvec[i]
            i += 1usize
        }
        j = 0usize
        while j < n {
            if fjac[j * m + j] != 0.0f64 {
                var sum = 0.0f64
                i = j
                while i < m {
                    sum += fjac[j * m + i] * wa4[i]
                    i += 1usize
                }
                let temp = 0.0f64 - sum / fjac[j * m + j]
                i = j
                while i < m {
                    wa4[i] = wa4[i] + fjac[j * m + i] * temp
                    i += 1usize
                }
            }
            fjac[j * m + j] = wa1[j]
            qtf[j] = wa4[j]
            j += 1usize
        }
        var gnorm = 0.0f64
        if fnorm != 0.0f64 {
            j = 0usize
            while j < n {
                let l = ipvt[j]
                if wa2[l] != 0.0f64 {
                    var sum = 0.0f64
                    i = 0usize
                    while i <= j {
                        sum += fjac[j * m + i] * (qtf[i] / fnorm)
                        i += 1usize
                    }
                    var g = math.abs[f64](sum / wa2[l])
                    if gnorm > g { g = gnorm }
                    gnorm = g
                }
                j += 1usize
            }
        }
        if gnorm <= gtol { info = 4i64 }
        if info != 0i64 { break }
        j = 0usize
        while j < n {
            if wa2[j] > diag[j] { diag[j] = wa2[j] }
            j += 1usize
        }
        var inner = true
        var ratio = 0.0f64
        while inner {
            lmpar(n, m, fjac, ipvt, diag, qtf, delta, &par, wa1, wa2, wa3, wa4)
            j = 0usize
            while j < n {
                wa1[j] = 0.0f64 - wa1[j]
                wa2[j] = x[j] + wa1[j]
                wa3[j] = diag[j] * wa1[j]
                j += 1usize
            }
            let pnorm = enorm(wa3)
            if iter == 1i64 && pnorm < delta { delta = pnorm }
            iflag = call[C](&o, wa2, wa4, 1i64)
            nfev += 1i64
            if iflag < 0i64 {
                outer = false
                break
            }
            let fnorm1 = enorm(wa4)
            var actred = 0.0f64 - 1.0f64
            if 0.1f64 * fnorm1 < fnorm { actred = 1.0f64 - (fnorm1 / fnorm) * (fnorm1 / fnorm) }
            j = 0usize
            while j < n {
                wa3[j] = 0.0f64
                j += 1usize
            }
            j = 0usize
            while j < n {
                let l = ipvt[j]
                let temp = wa1[l]
                i = 0usize
                while i <= j {
                    wa3[i] = wa3[i] + fjac[j * m + i] * temp
                    i += 1usize
                }
                j += 1usize
            }
            let temp1 = enorm(wa3) / fnorm
            let temp2 = (math.sqrt[f64](par) * pnorm) / fnorm
            let prered = temp1 * temp1 + temp2 * temp2 / 0.5f64
            let dirder = 0.0f64 - (temp1 * temp1 + temp2 * temp2)
            ratio = 0.0f64
            if prered != 0.0f64 { ratio = actred / prered }
            if ratio <= 0.25f64 {
                var temp = 0.5f64
                if actred >= 0.0f64 { temp = 0.5f64 } else { temp = 0.5f64 * dirder / (dirder + 0.5f64 * actred) }
                if 0.1f64 * fnorm1 >= fnorm || temp < 0.1f64 { temp = 0.1f64 }
                var dm = delta
                if pnorm / 0.1f64 < dm { dm = pnorm / 0.1f64 }
                delta = temp * dm
                par = par / temp
            } else if !(par != 0.0f64 && ratio < 0.75f64) {
                delta = pnorm / 0.5f64
                par = 0.5f64 * par
            }
            if ratio >= 0.0001f64 {
                j = 0usize
                while j < n {
                    x[j] = wa2[j]
                    wa2[j] = diag[j] * x[j]
                    j += 1usize
                }
                i = 0usize
                while i < m {
                    fvec[i] = wa4[i]
                    i += 1usize
                }
                xnorm = enorm(wa2)
                fnorm = fnorm1
                iter += 1i64
            }
            if math.abs[f64](actred) <= ftol && prered <= ftol && 0.5f64 * ratio <= 1.0f64 { info = 1i64 }
            if delta <= ptol * xnorm { info = 2i64 }
            if math.abs[f64](actred) <= ftol && prered <= ftol && 0.5f64 * ratio <= 1.0f64 && info == 2i64 { info = 3i64 }
            if info != 0i64 {
                outer = false
                break
            }
            if nfev >= maxfev { info = 5i64 }
            if math.abs[f64](actred) <= epsmch && prered <= epsmch && 0.5f64 * ratio <= 1.0f64 { info = 6i64 }
            if delta <= epsmch * xnorm { info = 7i64 }
            if gnorm <= epsmch { info = 8i64 }
            if info != 0i64 {
                outer = false
                break
            }
            if ratio >= 0.0001f64 { inner = false }
        }
    }
    if iflag < 0i64 { info = iflag }
    iflag = call[C](&o, x, fvec, 0i64)
    fit.info = info
    fit.nfev = nfev
    fit.niter = o.niter - 1i64
    var dev = 0.0f64
    i = 0usize
    while i < m {
        dev += fvec[i] * fvec[i]
        i += 1usize
    }
    fit.deviance = dev
    ret (fit, ok)
}

// nls.lm with the numerical Jacobian (lmdif)
fn nls_lm[C: type](a: *mem.Arena, f: fn(*C, []const f64, []f64), user: *C, m: usize, n: usize, x: []f64, lower: []const f64, upper: []const f64, ftol: f64, ptol: f64, gtol: f64, maxfev: i64, maxiter: i64) -> (Fit, err) {
    let (fit, e) = nls_lm_core[C](a, f, f, false, user, m, n, x, lower, upper, ftol, ptol, gtol, maxfev, maxiter)
    ret (fit, e)
}

// nls.lm with an analytic Jacobian (lmder): jac fills the m by n Jacobian of the residuals column by column (fjac[j * m + i] = d resid_i / d x_j)
fn nls_lm_der[C: type](a: *mem.Arena, f: fn(*C, []const f64, []f64), jac: fn(*C, []const f64, []f64), user: *C, m: usize, n: usize, x: []f64, lower: []const f64, upper: []const f64, ftol: f64, ptol: f64, gtol: f64, maxfev: i64, maxiter: i64) -> (Fit, err) {
    let (fit, e) = nls_lm_core[C](a, f, jac, true, user, m, n, x, lower, upper, ftol, ptol, gtol, maxfev, maxiter)
    ret (fit, e)
}
