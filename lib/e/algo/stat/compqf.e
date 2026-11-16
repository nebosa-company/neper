// R CompQuadForm: the distribution of a quadratic form in normal variables `sum_j lambda_j chisq(h_j, delta_j) + sigma Z`:
// `davies` (Algorithm AS 155, the numerical inversion of the characteristic function with the package's error bounds and
// convergence factor, qfc.cpp line for line) and `farebrother` (Algorithm AS 204 of Ruben, the expansion in central chi-squares).
//
// Not here: `imhof` (it runs R's integrate), `liu` (it needs the non-central chi-squared distribution).

use e.math
use e.math.dist as dist
use e.mem

fn pi_c() -> f64 { ret 3.14159265358979f64 }
fn log28_c() -> f64 { ret 0.0866f64 }

type Qf = struct {
    sigsq: f64, lmax: f64, lmin: f64, mean: f64, c: f64, intl: f64, ersm: f64,
    count: i64, r: usize, lim: i64, ndtsrt: bool, fail: bool, abort: bool,
    n: []const i64, th: []usize, lb: []const f64, nc: []const f64
}

fn exp1(x: f64) -> f64 {
    if x < 0.0f64 - 50.0f64 { ret 0.0f64 }
    ret math.exp[f64](x)
}

fn counter(s: *Qf) {
    s.count += 1i64
    if s.count > s.lim { s.abort = true }
}

fn sq(x: f64) -> f64 { ret x * x }

fn cube(x: f64) -> f64 { ret x * x * x }

// if first: log(1 + x), else log(1 + x) - x
fn log1(x: f64, first: bool) -> f64 {
    if math.abs[f64](x) > 0.1f64 {
        if first { ret math.log[f64](1.0f64 + x) }
        ret math.log[f64](1.0f64 + x) - x
    }
    let y0 = x / (2.0f64 + x)
    var term = 2.0f64 * cube(y0)
    var k = 3.0f64
    var s = 0.0f64 - x
    if first { s = 2.0f64 }
    s = s * y0
    let y = sq(y0)
    var s1 = s + term / k
    while s1 != s {
        k = k + 2.0f64
        term = term * y
        s = s1
        s1 = s + term / k
    }
    ret s
}

fn order(s: *Qf) {
    var j = 0usize
    while j < s.r {
        let lj = math.abs[f64](s.lb[j])
        var k = i64(j) - 1i64
        var done = false
        while k >= 0i64 && !done {
            if lj > math.abs[f64](s.lb[s.th[usize(k)]]) {
                s.th[usize(k) + 1usize] = s.th[usize(k)]
                k -= 1i64
            } else { done = true }
        }
        s.th[usize(k + 1i64)] = j
        j += 1usize
    }
    s.ndtsrt = false
}

// the bound on the tail probability from the mgf; the cutoff goes to cx[0]
fn errbd(s: *Qf, u0: f64, cx: []f64) -> f64 {
    counter(s)
    var u = u0
    var xconst = u * s.sigsq
    var sum1 = u * xconst
    u = 2.0f64 * u
    var j = i64(s.r) - 1i64
    while j >= 0i64 {
        let nj = f64(s.n[usize(j)])
        let lj = s.lb[usize(j)]
        let ncj = s.nc[usize(j)]
        let x = u * lj
        let y = 1.0f64 - x
        xconst = xconst + lj * (ncj / y + nj) / y
        sum1 = sum1 + ncj * sq(x / y) + nj * (sq(x) / y + log1(0.0f64 - x, false))
        j -= 1i64
    }
    cx[0usize] = xconst
    ret exp1(0.0f64 - 0.5f64 * sum1)
}

// find ctff so that p(qf > ctff) < accx (upn > 0) or p(qf < ctff) < accx otherwise; upn[0] is updated
fn ctff(s: *Qf, a: *mem.Arena, accx: f64, upn: []f64) -> f64 {
    let (cb, e) = mem.alloc[f64](a, 1usize)
    if e != ok { ret 0.0f64 }
    var u2 = upn[0usize]
    var u1 = 0.0f64
    var c1 = s.mean
    var c2 = 0.0f64
    var rb = 2.0f64 * s.lmin
    if u2 > 0.0f64 { rb = 2.0f64 * s.lmax }
    var u = u2 / (1.0f64 + u2 * rb)
    while errbd(s, u, cb) > accx && !s.abort {
        c2 = cb[0usize]
        u1 = u2
        c1 = c2
        u2 = 2.0f64 * u2
        u = u2 / (1.0f64 + u2 * rb)
    }
    c2 = cb[0usize]
    if s.abort { ret c2 }
    u = (c1 - s.mean) / (c2 - s.mean)
    while u < 0.9f64 && !s.abort {
        u = (u1 + u2) / 2.0f64
        if errbd(s, u / (1.0f64 + u * rb), cb) > accx {
            u1 = u
            c1 = cb[0usize]
        } else {
            u2 = u
            c2 = cb[0usize]
        }
        u = (c1 - s.mean) / (c2 - s.mean)
    }
    upn[0usize] = u2
    ret c2
}

// bound the integration error due to truncation at u
fn truncation(s: *Qf, u0: f64, tausq: f64) -> f64 {
    counter(s)
    var sum1 = 0.0f64
    var prod2 = 0.0f64
    var prod3 = 0.0f64
    var ss = 0i64
    let sum2 = (s.sigsq + tausq) * sq(u0)
    var prod1 = 2.0f64 * sum2
    let u = 2.0f64 * u0
    var j = 0usize
    while j < s.r {
        let lj = s.lb[j]
        let ncj = s.nc[j]
        let nj = f64(s.n[j])
        let x = sq(u * lj)
        sum1 = sum1 + ncj * x / (1.0f64 + x)
        if x > 1.0f64 {
            prod2 = prod2 + nj * math.log[f64](x)
            prod3 = prod3 + nj * log1(x, true)
            ss = ss + s.n[j]
        } else {
            prod1 = prod1 + nj * log1(x, true)
        }
        j += 1usize
    }
    sum1 = 0.5f64 * sum1
    prod2 = prod1 + prod2
    prod3 = prod1 + prod3
    var x = exp1(0.0f64 - sum1 - 0.25f64 * prod2) / pi_c()
    let y = exp1(0.0f64 - sum1 - 0.25f64 * prod3) / pi_c()
    var err1 = 1.0f64
    if ss != 0i64 { err1 = x * 2.0f64 / f64(ss) }
    var err2 = 1.0f64
    if prod3 > 1.0f64 { err2 = 2.5f64 * y }
    if err2 < err1 { err1 = err2 }
    x = 0.5f64 * sum2
    err2 = 1.0f64
    if x > y { err2 = y / x }
    if err1 < err2 { ret err1 }
    ret err2
}

// find u such that truncation(u) < accx and truncation(u / 1.2) > accx
fn findu(s: *Qf, utx: []f64, accx: f64) {
    var ut = utx[0usize]
    var u = ut / 4.0f64
    if truncation(s, u, 0.0f64) > accx {
        u = ut
        while truncation(s, u, 0.0f64) > accx && !s.abort {
            ut = ut * 4.0f64
            u = ut
        }
    } else {
        ut = u
        u = u / 4.0f64
        while truncation(s, u, 0.0f64) <= accx && !s.abort {
            ut = u
            u = u / 4.0f64
        }
    }
    var i = 0usize
    while i < 4usize {
        var dv = 2.0f64
        if i == 1usize { dv = 1.4f64 }
        if i == 2usize { dv = 1.2f64 }
        if i == 3usize { dv = 1.1f64 }
        u = ut / dv
        if truncation(s, u, 0.0f64) <= accx { ut = u }
        i += 1usize
    }
    utx[0usize] = ut
}

// carry out the integration with nterm terms at step interv; if not mainx multiply the integrand by 1 - exp(-0.5 tausq u^2)
fn integrate(s: *Qf, nterm: i64, interv: f64, tausq: f64, mainx: bool) {
    let inpi = interv / pi_c()
    var k = nterm
    while k >= 0i64 {
        let u = (f64(k) + 0.5f64) * interv
        var sum1 = 0.0f64 - 2.0f64 * u * s.c
        var sum2 = math.abs[f64](sum1)
        var sum3 = 0.0f64 - 0.5f64 * s.sigsq * sq(u)
        var j = i64(s.r) - 1i64
        while j >= 0i64 {
            let nj = f64(s.n[usize(j)])
            let x = 2.0f64 * s.lb[usize(j)] * u
            var y = sq(x)
            sum3 = sum3 - 0.25f64 * nj * log1(y, true)
            y = s.nc[usize(j)] * x / (1.0f64 + y)
            let z = nj * math.atan[f64](x) + y
            sum1 = sum1 + z
            sum2 = sum2 + math.abs[f64](z)
            sum3 = sum3 - 0.5f64 * x * y
            j -= 1i64
        }
        var x = inpi * exp1(sum3) / u
        if !mainx { x = x * (1.0f64 - exp1(0.0f64 - 0.5f64 * tausq * sq(u))) }
        sum1 = math.sin[f64](0.5f64 * sum1) * x
        sum2 = 0.5f64 * sum2 * x
        s.intl = s.intl + sum1
        s.ersm = s.ersm + sum2
        k -= 1i64
    }
}

// the coefficient of tausq in the error when the convergence factor exp1(-0.5 tausq u^2) is used at x
fn cfe(s: *Qf, x0: f64) -> f64 {
    counter(s)
    if s.ndtsrt { order(s) }
    var axl = math.abs[f64](x0)
    var sxl = 0.0f64 - 1.0f64
    if x0 > 0.0f64 { sxl = 1.0f64 }
    var sum1 = 0.0f64
    var j = i64(s.r) - 1i64
    var done = false
    while j >= 0i64 && !done {
        let t = s.th[usize(j)]
        if s.lb[t] * sxl > 0.0f64 {
            let lj = math.abs[f64](s.lb[t])
            let axl1 = axl - lj * (f64(s.n[t]) + s.nc[t])
            let axl2 = lj / log28_c()
            if axl1 > axl2 {
                axl = axl1
            } else {
                if axl > axl2 { axl = axl2 }
                sum1 = (axl - axl1) / lj
                var k = j - 1i64
                while k >= 0i64 {
                    sum1 = sum1 + (f64(s.n[s.th[usize(k)]]) + s.nc[s.th[usize(k)]])
                    k -= 1i64
                }
                done = true
            }
        }
        if !done { j -= 1i64 }
    }
    if sum1 > 100.0f64 {
        s.fail = true
        ret 1.0f64
    }
    ret math.pow[f64](2.0f64, sum1 / 4.0f64) / (pi_c() * sq(axl))
}

type DaviesRes = struct { qq: f64, ifault: i64, trace: [7]f64 }

// davies(q, lambda, h, delta, sigma, lim, acc): Qq = 1 - qfval as the package answers it
fn davies(a: *mem.Arena, lb: []const f64, nc: []const f64, n: []const i64, sigma: f64, c: f64, lim: i64, acc: f64) -> (DaviesRes, err) {
    var out: DaviesRes = zero
    let r = lb.len
    let (th, te) = mem.alloc[usize](a, r + 1usize)
    if te != ok { ret (out, te) }
    var s = Qf { sigsq: 0.0f64, lmax: 0.0f64, lmin: 0.0f64, mean: 0.0f64, c: c, intl: 0.0f64, ersm: 0.0f64, count: 0i64, r: r, lim: lim, ndtsrt: true, fail: false, abort: false, n: n, th: th, lb: lb, nc: nc }
    var qfval = 0.0f64 - 1.0f64
    var acc1 = acc
    var xlim = f64(lim)
    s.sigsq = sq(sigma)
    var sd = s.sigsq
    var j = 0usize
    var bad = false
    while j < r {
        let nj = n[j]
        let lj = lb[j]
        let ncj = nc[j]
        if nj < 0i64 || ncj < 0.0f64 { bad = true }
        sd = sd + sq(lj) * (f64(2i64 * nj) + 4.0f64 * ncj)
        s.mean = s.mean + lj * (f64(nj) + ncj)
        if s.lmax < lj { s.lmax = lj } else if s.lmin > lj { s.lmin = lj }
        j += 1usize
    }
    var finished = false
    if bad {
        out.ifault = 3i64
        finished = true
    }
    if !finished && sd == 0.0f64 {
        if c > 0.0f64 { qfval = 1.0f64 } else { qfval = 0.0f64 }
        finished = true
    }
    if !finished && s.lmin == 0.0f64 && s.lmax == 0.0f64 && sigma == 0.0f64 {
        out.ifault = 3i64
        finished = true
    }
    if !finished {
        sd = math.sqrt[f64](sd)
        var almx = s.lmax
        if s.lmax < 0.0f64 - s.lmin { almx = 0.0f64 - s.lmin }
        let (ub, ue) = mem.alloc[f64](a, 1usize)
        let (upb, upe) = mem.alloc[f64](a, 1usize)
        let (unb, une) = mem.alloc[f64](a, 1usize)
        if ue != ok || upe != ok || une != ok { ret (out, ue) }
        ub[0usize] = 16.0f64 / sd
        upb[0usize] = 4.5f64 / sd
        unb[0usize] = 0.0f64 - 4.5f64 / sd
        findu(&s, ub, 0.5f64 * acc1)
        var tausq = 0.0f64
        if c != 0.0f64 && almx > 0.07f64 * sd {
            tausq = 0.25f64 * acc1 / cfe(&s, c)
            if s.fail {
                s.fail = false
            } else if truncation(&s, ub[0usize], tausq) < 0.2f64 * acc1 {
                s.sigsq = s.sigsq + tausq
                findu(&s, ub, 0.25f64 * acc1)
                out.trace[5usize] = math.sqrt[f64](tausq)
            }
        }
        out.trace[4usize] = ub[0usize]
        acc1 = 0.5f64 * acc1
        var l2 = false
        var intv = 0.0f64
        var xnt = 0.0f64
        while !l2 && !finished && !s.abort {
            let d1 = ctff(&s, a, acc1, upb) - c
            if d1 < 0.0f64 {
                qfval = 1.0f64
                finished = true
            } else {
                let d2 = c - ctff(&s, a, acc1, unb)
                if d2 < 0.0f64 {
                    qfval = 0.0f64
                    finished = true
                } else {
                    var dm = d2
                    if d1 > d2 { dm = d1 }
                    intv = 2.0f64 * pi_c() / dm
                    xnt = ub[0usize] / intv
                    let xntm = 3.0f64 / math.sqrt[f64](acc1)
                    if xnt > xntm * 1.5f64 {
                        if xntm > xlim {
                            out.ifault = 1i64
                            finished = true
                        } else {
                            let ntm = i64(math.floor[f64](xntm + 0.5f64))
                            let intv1 = ub[0usize] / f64(ntm)
                            let x = 2.0f64 * pi_c() / intv1
                            if x <= math.abs[f64](c) {
                                l2 = true
                            } else {
                                tausq = 0.33f64 * acc1 / (1.1f64 * (cfe(&s, c - x) + cfe(&s, c + x)))
                                if s.fail {
                                    l2 = true
                                } else {
                                    acc1 = 0.67f64 * acc1
                                    integrate(&s, ntm, intv1, tausq, false)
                                    xlim = xlim - xntm
                                    s.sigsq = s.sigsq + tausq
                                    out.trace[2usize] = out.trace[2usize] + 1.0f64
                                    out.trace[1usize] = out.trace[1usize] + f64(ntm) + 1.0f64
                                    findu(&s, ub, 0.25f64 * acc1)
                                    acc1 = 0.75f64 * acc1
                                }
                            }
                        }
                    } else { l2 = true }
                }
            }
        }
        if s.abort {
            out.ifault = 4i64
            finished = true
            qfval = 0.0f64 - 1.0f64
        }
        if !finished {
            out.trace[3usize] = intv
            if xnt > xlim {
                out.ifault = 1i64
            } else {
                let nt = i64(math.floor[f64](xnt + 0.5f64))
                integrate(&s, nt, intv, 0.0f64, true)
                out.trace[2usize] = out.trace[2usize] + 1.0f64
                out.trace[1usize] = out.trace[1usize] + f64(nt) + 1.0f64
                qfval = 0.5f64 - s.intl
                out.trace[0usize] = s.ersm
                let up = s.ersm
                let x = up + acc / 10.0f64
                var rats: [4]f64 = zero
                rats[0usize] = 1.0f64
                rats[1usize] = 2.0f64
                rats[2usize] = 4.0f64
                rats[3usize] = 8.0f64
                var q = 0usize
                while q < 4usize {
                    if rats[q] * x == rats[q] * up { out.ifault = 2i64 }
                    q += 1usize
                }
            }
        }
    }
    out.trace[6usize] = f64(s.count)
    out.qq = 1.0f64 - qfval
    ret (out, ok)
}

type RubenRes = struct { qq: f64, dnsty: f64, ifault: i64 }

// farebrother(q, lambda, h, delta, maxit, eps, mode): Qq = 1 - the probability, the density, the fault code
fn farebrother(a: *mem.Arena, lambda: []const f64, mult: []const i64, delta: []const f64, c: f64, mode: f64, maxit: usize, eps: f64) -> (RubenRes, err) {
    var out: RubenRes = zero
    let n = lambda.len
    if n < 1usize || c <= 0.0f64 || maxit < 1usize || eps <= 0.0f64 {
        out.qq = 1.0f64 - (0.0f64 - 2.0f64)
        out.ifault = 2i64
        ret (out, ok)
    }
    let (gamma, e1) = mem.alloc[f64](a, n)
    let (theta, e2) = mem.alloc[f64](a, n)
    let (aa, e3) = mem.alloc[f64](a, maxit)
    let (bb, e4) = mem.alloc[f64](a, maxit)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, e1) }
    let tol = 0.0f64 - 200.0f64
    var sum = lambda[0usize]
    var bbeta = sum
    var i = 1usize
    while i <= n {
        let hold = lambda[i - 1usize]
        if hold <= 0.0f64 || mult[i - 1usize] < 1i64 || delta[i - 1usize] < 0.0f64 {
            out.qq = 1.0f64 - (0.0f64 - 7.0f64)
            out.ifault = 0i64 - i64(i)
            ret (out, ok)
        }
        if bbeta > hold { bbeta = hold }
        if sum < hold { sum = hold }
        i += 1usize
    }
    if mode > 0.0f64 {
        bbeta = mode * bbeta
    } else {
        bbeta = 2.0f64 / (1.0f64 / bbeta + 1.0f64 / sum)
    }
    var k = 0i64
    sum = 1.0f64
    var sum1 = 0.0f64
    i = 1usize
    while i <= n {
        let hold = bbeta / lambda[i - 1usize]
        gamma[i - 1usize] = 1.0f64 - hold
        sum = sum * math.pow[f64](hold, f64(mult[i - 1usize]))
        sum1 = sum1 + delta[i - 1usize]
        k = k + mult[i - 1usize]
        theta[i - 1usize] = 1.0f64
        i += 1usize
    }
    let ao = math.exp[f64](0.5f64 * (math.log[f64](sum) - sum1))
    var prbty = 0.0f64
    if ao <= 0.0f64 {
        out.dnsty = 0.0f64
        out.ifault = 1i64
        out.qq = 1.0f64 - 0.0f64
        ret (out, ok)
    }
    let z = c / bbeta
    var lans = 0.0f64
    var dans = 0.0f64
    var pans = 0.0f64
    var st = 0i64
    if k % 2i64 == 0i64 {
        st = 2i64
        lans = 0.0f64 - 0.5f64 * z
        dans = math.exp[f64](lans)
        pans = 1.0f64 - dans
    } else {
        st = 1i64
        lans = 0.0f64 - 0.5f64 * (z + math.log[f64](z)) - 0.22579135264473f64
        dans = math.exp[f64](lans)
        pans = dist.pnorm(math.sqrt[f64](z), 0.0f64, 1.0f64, true, false) - dist.pnorm(0.0f64 - math.sqrt[f64](z), 0.0f64, 1.0f64, true, false)
    }
    k = k - 2i64
    var j = st
    while j <= k {
        if lans < tol {
            lans = lans + math.log[f64](z / f64(j))
            dans = math.exp[f64](lans)
        } else {
            dans = dans * z / f64(j)
        }
        pans = pans - dans
        j += 2i64
    }
    prbty = pans
    var dn = dans
    let eps2 = eps / ao
    let aoinv = 1.0f64 / ao
    sum = aoinv - 1.0f64
    var m = 1usize
    var ifault = 0i64
    var stopped = false
    while m <= maxit && !stopped {
        sum1 = 0.0f64
        i = 1usize
        while i <= n {
            let hold = theta[i - 1usize]
            let hold2 = hold * gamma[i - 1usize]
            theta[i - 1usize] = hold2
            sum1 = sum1 + hold2 * f64(mult[i - 1usize]) + f64(m) * delta[i - 1usize] * (hold - hold2)
            i += 1usize
        }
        sum1 = 0.5f64 * sum1
        bb[m - 1usize] = sum1
        var ii = m - 1usize
        while ii >= 1usize {
            sum1 = sum1 + bb[ii - 1usize] * aa[m - ii - 1usize]
            ii -= 1usize
        }
        sum1 = sum1 / f64(m)
        aa[m - 1usize] = sum1
        k = k + 2i64
        if lans < tol {
            lans = lans + math.log[f64](z / f64(k))
            dans = math.exp[f64](lans)
        } else {
            dans = dans * z / f64(k)
        }
        pans = pans - dans
        sum = sum - sum1
        dn = dn + dans * sum1
        sum1 = pans * sum1
        prbty = prbty + sum1
        if prbty < 0.0f64 - aoinv {
            out.qq = 1.0f64 - (0.0f64 - 3.0f64)
            out.ifault = 3i64
            ret (out, ok)
        }
        if math.abs[f64](pans * sum) < eps2 {
            if math.abs[f64](sum1) < eps2 {
                ifault = 0i64
                stopped = true
            }
        }
        if !stopped { m += 1usize }
    }
    // after the loop m is the iteration at which it stopped, or maxit + 1
    if m >= maxit { ifault = 4i64 }
    dn = ao * dn / (bbeta + bbeta)
    prbty = ao * prbty
    if prbty < 0.0f64 || prbty > 1.0f64 {
        ifault = ifault + 5i64
    } else if dn < 0.0f64 {
        ifault = ifault + 6i64
    }
    out.qq = 1.0f64 - prbty
    out.dnsty = dn
    out.ifault = ifault
    ret (out, ok)
}
