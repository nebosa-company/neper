// R kSamples, the multiple-comparison side: Steel.test (the Steel-Dwass style many-to-one Wilcoxon test against the first sample, with its
// asymptotic p-value through R's integrate), jt.test (Jonckheere-Terpstra) with the distribution functions djt, pjt and qjt (Harding's
// recursion), and SteelConfInt's building blocks (pmaxWilcox, qmaxWilcox, the achieved confidence).
//
// The permutation draws follow e.algo.stat.ksamples_sim, so a stream seeded like set.seed reproduces the package's simulated p-values.
// Method codes: 0 asymptotic, 1 simulated, 2 exact. Alternatives of Steel.test: 1 greater, -1 less, 0 two-sided.

use e.algo.rand.r as rng
use e.algo.stat.ksamples_sim as sm
use e.math
use e.math.dist as mdist
use e.math.quadpack as qp
use e.math.special as special
use e.mem

// ---- R's integrate() over a finite range: QUADPACK dqags with the 21-point Gauss-Kronrod rule ----

fn wg21(j: usize) -> f64 {
    if j == 0usize { ret 0.066671344308688137593568809893332f64 }
    if j == 1usize { ret 0.149451349150580593145776339657697f64 }
    if j == 2usize { ret 0.219086362515982043995534934228163f64 }
    if j == 3usize { ret 0.269266719309996355091226921569469f64 }
    ret 0.295524224714752870173892994651338f64
}

fn xgk21(j: usize) -> f64 {
    if j == 0usize { ret 0.995657163025808080735527280689003f64 }
    if j == 1usize { ret 0.973906528517171720077964012084452f64 }
    if j == 2usize { ret 0.930157491355708226001207180059508f64 }
    if j == 3usize { ret 0.865063366688984510732096688423493f64 }
    if j == 4usize { ret 0.780817726586416897063717578345042f64 }
    if j == 5usize { ret 0.679409568299024406234327365114874f64 }
    if j == 6usize { ret 0.562757134668604683339000099272694f64 }
    if j == 7usize { ret 0.433395394129247190799265943165784f64 }
    if j == 8usize { ret 0.294392862701460198131126603103866f64 }
    if j == 9usize { ret 0.14887433898163121088482600112972f64 }
    ret 0.0f64
}

fn wgk21(j: usize) -> f64 {
    if j == 0usize { ret 0.011694638867371874278064396062192f64 }
    if j == 1usize { ret 0.03255816230796472747881897245939f64 }
    if j == 2usize { ret 0.05475589657435199603138130024458f64 }
    if j == 3usize { ret 0.07503967481091995276704314091619f64 }
    if j == 4usize { ret 0.093125454583697605535065465083366f64 }
    if j == 5usize { ret 0.109387158802297641899210590325805f64 }
    if j == 6usize { ret 0.123491976262065851077958109831074f64 }
    if j == 7usize { ret 0.134709217311473325928054001771707f64 }
    if j == 8usize { ret 0.142775938577060080797094273138717f64 }
    if j == 9usize { ret 0.147739104901338491374841515972068f64 }
    ret 0.149445554002916905664936468389821f64
}

// rdqk21 over (lo, hi); the off-centre values are evaluated again for resasc, which gives the same numbers
fn qk21[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64) -> qp.Kron {
    let centr = (lo + hi) * 0.5f64
    let hlgth = (hi - lo) * 0.5f64
    let dhlgth = qp.ab(hlgth)
    let fc = f(ctx, centr)
    var resg = 0.0f64
    var resk = wgk21(10usize) * fc
    var resabs = qp.ab(resk)
    var j = 1usize
    while j <= 5usize {
        let jtw = j * 2usize
        let absc = hlgth * xgk21(jtw - 1usize)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        let fsum = v1 + v2
        resg += wg21(j - 1usize) * fsum
        resk += wgk21(jtw - 1usize) * fsum
        resabs += wgk21(jtw - 1usize) * (qp.ab(v1) + qp.ab(v2))
        j += 1usize
    }
    j = 1usize
    while j <= 5usize {
        let jtwm1 = j * 2usize - 1usize
        let absc = hlgth * xgk21(jtwm1 - 1usize)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        let fsum = v1 + v2
        resk += wgk21(jtwm1 - 1usize) * fsum
        resabs += wgk21(jtwm1 - 1usize) * (qp.ab(v1) + qp.ab(v2))
        j += 1usize
    }
    let reskh = resk * 0.5f64
    var resasc = wgk21(10usize) * qp.ab(fc - reskh)
    j = 0usize
    while j < 10usize {
        let absc = hlgth * xgk21(j)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        resasc += wgk21(j) * (qp.ab(v1 - reskh) + qp.ab(v2 - reskh))
        j += 1usize
    }
    let result = resk * hlgth
    resabs = resabs * dhlgth
    resasc = resasc * dhlgth
    var abserr = qp.ab((resk - resg) * hlgth)
    if resasc != 0.0f64 && abserr != 0.0f64 {
        abserr = resasc * qp.mn(1.0f64, math.pow[f64](abserr * 200.0f64 / resasc, 1.5f64))
    }
    if resabs > qp.dbl_min() / (qp.epmach() * 50.0f64) {
        abserr = qp.mx(qp.epmach() * 50.0f64 * resabs, abserr)
    }
    var kr: qp.Kron = zero
    kr = qp.Kron { result: result, abserr: abserr, resabs: resabs, resasc: resasc }
    ret kr
}

// qags(f, lo, hi, epsabs, epsrel, limit): the integral of f over a finite range as R's integrate() computes it
fn qags[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64, epsabs: f64, epsrel: f64, limit: usize) -> (qp.Qagi, err) {
    var out = qp.Qagi { result: 0.0f64, abserr: 0.0f64, neval: 0i64, ier: 0i64, last: 0usize }
    let eps = qp.epmach()
    if epsabs <= 0.0f64 && epsrel < qp.mx(eps * 50.0f64, 5.0e-29f64) {
        out.ier = 6i64
        ret (out, ok)
    }
    let (alist, e1) = mem.alloc[f64](a, limit + 2usize)
    let (blist, e2) = mem.alloc[f64](a, limit + 2usize)
    let (rlist, e3) = mem.alloc[f64](a, limit + 2usize)
    let (elist, e4) = mem.alloc[f64](a, limit + 2usize)
    let (iord, e5) = mem.alloc[usize](a, limit + 2usize)
    let (rlist2, e6) = mem.alloc[f64](a, 56usize)
    let (res3la, e7) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (out, e1) }
    var i = 0usize
    while i < limit + 2usize {
        alist[i] = 0.0f64
        blist[i] = 0.0f64
        rlist[i] = 0.0f64
        elist[i] = 0.0f64
        iord[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < 56usize {
        rlist2[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        res3la[i] = 0.0f64
        i += 1usize
    }
    alist[1usize] = lo
    blist[1usize] = hi
    let k0 = qk21(ctx, f, lo, hi)
    var result = k0.result
    var abserr = k0.abserr
    let defabs = k0.resabs
    let resabs0 = k0.resasc
    var ier = 0i64
    var last = 1usize
    rlist[1usize] = result
    elist[1usize] = abserr
    iord[1usize] = 1usize
    let dres = qp.ab(result)
    var errbnd = qp.mx(epsabs, epsrel * dres)
    if abserr <= eps * 100.0f64 * defabs && abserr > errbnd { ier = 2i64 }
    if limit == 1usize { ier = 1i64 }
    var phase = 0i64
    if ier != 0i64 || (abserr <= errbnd && abserr != resabs0) || abserr == 0.0f64 { phase = 130 }
    var area = result
    var errsum = abserr
    let oflow = qp.dbl_max()
    let uflow = qp.dbl_min()
    var small = 0.0f64
    var erlarg = 0.0f64
    var ertest = 0.0f64
    var correc = 0.0f64
    var ierro = 0i64
    var ksgn = 0i64 - 1i64
    var es = qp.Eps { n: 2usize, nres: 0usize, result: 0.0f64, abserr: 0.0f64 }
    var sr = qp.Srt { maxerr: 1usize, ermax: abserr, nrmax: 1usize }
    if phase == 0i64 {
        rlist2[1usize] = result
        abserr = oflow
        var noext = false
        var extrap = false
        var ktmin = 0i64
        var iroff1 = 0i64
        var iroff2 = 0i64
        var iroff3 = 0i64
        if dres >= (1.0f64 - eps * 50.0f64) * defabs { ksgn = 1i64 }
        last = 2usize
        var run = true
        while run && last <= limit {
            var once = true
            while once {
                once = false
                let a1 = alist[sr.maxerr]
                let b1 = (alist[sr.maxerr] + blist[sr.maxerr]) * 0.5f64
                let a2 = b1
                let b2 = blist[sr.maxerr]
                let erlast = sr.ermax
                let q1 = qk21(ctx, f, a1, b1)
                let q2 = qk21(ctx, f, a2, b2)
                let area1 = q1.result
                let error1 = q1.abserr
                let defab1 = q1.resasc
                let area2 = q2.result
                let error2 = q2.abserr
                let defab2 = q2.resasc
                let area12 = area1 + area2
                let erro12 = error1 + error2
                errsum = errsum + erro12 - sr.ermax
                area = area + area12 - rlist[sr.maxerr]
                if !(defab1 == error1 || defab2 == error2) {
                    if qp.ab(rlist[sr.maxerr] - area12) <= qp.ab(area12) * 1.0e-5f64 && erro12 >= sr.ermax * 0.99f64 {
                        if extrap { iroff2 += 1i64 } else { iroff1 += 1i64 }
                    }
                    if last > 10usize && erro12 > sr.ermax { iroff3 += 1i64 }
                }
                rlist[sr.maxerr] = area1
                rlist[last] = area2
                errbnd = qp.mx(epsabs, epsrel * qp.ab(area))
                if iroff1 + iroff2 >= 10i64 || iroff3 >= 20i64 { ier = 2i64 }
                if iroff2 >= 5i64 { ierro = 3i64 }
                if last == limit { ier = 1i64 }
                if qp.mx(qp.ab(a1), qp.ab(b2)) <= (eps * 100.0f64 + 1.0f64) * (qp.ab(a2) + uflow * 1000.0f64) { ier = 4i64 }
                if error2 > error1 {
                    alist[sr.maxerr] = a2
                    alist[last] = a1
                    blist[last] = b1
                    rlist[sr.maxerr] = area2
                    rlist[last] = area1
                    elist[sr.maxerr] = error2
                    elist[last] = error1
                } else {
                    alist[last] = a2
                    blist[sr.maxerr] = b1
                    blist[last] = b2
                    elist[sr.maxerr] = error1
                    elist[last] = error2
                }
                qp.qpsrt(limit, last, &sr, elist, iord)
                if errsum <= errbnd {
                    phase = 115i64
                    run = false
                    break
                }
                if ier != 0i64 {
                    run = false
                    break
                }
                if last == 2usize {
                    small = qp.ab(hi - lo) * 0.375f64
                    erlarg = errsum
                    ertest = errbnd
                    rlist2[2usize] = area
                    break
                }
                if noext { break }
                erlarg -= erlast
                if qp.ab(b1 - a1) > small { erlarg += erro12 }
                if !extrap {
                    if qp.ab(blist[sr.maxerr] - alist[sr.maxerr]) > small { break }
                    extrap = true
                    sr.nrmax = 2usize
                }
                var skip = false
                if ierro != 3i64 && erlarg > ertest {
                    let id = sr.nrmax
                    var jupbnd = last
                    if last > limit / 2usize + 2usize { jupbnd = limit + 3usize - last }
                    var k = id
                    while k <= jupbnd && !skip {
                        sr.maxerr = iord[sr.nrmax]
                        sr.ermax = elist[sr.maxerr]
                        if qp.ab(blist[sr.maxerr] - alist[sr.maxerr]) > small {
                            skip = true
                        } else {
                            sr.nrmax += 1usize
                            k += 1usize
                        }
                    }
                }
                if skip { break }
                es.n += 1usize
                rlist2[es.n] = area
                qp.qelg(&es, rlist2, res3la)
                let reseps = es.result
                let abseps = es.abserr
                ktmin += 1i64
                if ktmin > 5i64 && abserr < errsum * 0.001f64 { ier = 5i64 }
                var stop = false
                if abseps < abserr {
                    ktmin = 0i64
                    abserr = abseps
                    result = reseps
                    correc = erlarg
                    ertest = qp.mx(epsabs, epsrel * qp.ab(reseps))
                    if abserr <= ertest {
                        run = false
                        stop = true
                    }
                }
                if !stop {
                    if es.n == 1usize { noext = true }
                    if ier == 5i64 {
                        run = false
                    } else {
                        sr.maxerr = iord[1usize]
                        sr.ermax = elist[sr.maxerr]
                        sr.nrmax = 1usize
                        extrap = false
                        small = small * 0.5f64
                        erlarg = errsum
                    }
                }
            }
            if run { last += 1usize }
        }
        if phase == 0i64 {
            var t = 110i64
            if abserr == oflow {
                t = 115i64
            } else if ier + ierro != 0i64 {
                if ierro == 3i64 { abserr += correc }
                if ier == 0i64 { ier = 3i64 }
                if result == 0.0f64 || area == 0.0f64 {
                    if abserr > errsum {
                        t = 115i64
                    } else if area == 0.0f64 {
                        t = 130i64
                    }
                } else if abserr / qp.ab(result) > errsum / qp.ab(area) {
                    t = 115i64
                }
            }
            if t == 110i64 {
                if ksgn == 0i64 - 1i64 && qp.mx(qp.ab(result), qp.ab(area)) <= defabs * 0.01f64 {
                    t = 130i64
                } else {
                    if 0.01f64 > result / area || result / area > 100.0f64 || errsum > qp.ab(area) { ier = 5i64 }
                    t = 130i64
                }
            }
            phase = t
        }
        if phase == 115i64 {
            result = 0.0f64
            var k = 1usize
            while k <= last {
                result += rlist[k]
                k += 1usize
            }
            abserr = errsum
        }
    }
    out.result = result
    out.abserr = abserr
    out.last = last
    out.neval = i64(last) * 42i64 - 21i64
    out.ier = ier
    ret (out, ok)
}

// ---- Steel.test ----

// the integrand of Steelnormal: dnorm(z) times the product over the comparisons; kind 0 greater, 1 less, 2 two-sided
type SnCtx = struct { k: usize, sig0: f64, sig: []const f64, tau: []const f64, ni: []const f64, s: f64, kind: usize }

fn kx_pnorm(x: f64) -> f64 { ret mdist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn sn_f(c: *SnCtx, z: f64) -> f64 {
    var fac = 1.0f64
    var i = 0usize
    while i < c.k {
        let u = (c.s * c.tau[i] - c.ni[i] * c.sig0 * z) / c.sig[i]
        if c.kind == 0usize { fac = fac * kx_pnorm(u) }
        if c.kind == 1usize { fac = fac * (1.0f64 - kx_pnorm(u)) }
        if c.kind == 2usize {
            let w = (0.0f64 - c.s * c.tau[i] - c.ni[i] * c.sig0 * z) / c.sig[i]
            fac = fac * (kx_pnorm(u) - kx_pnorm(w))
        }
        i += 1usize
    }
    ret mdist.dnorm(z, 0.0f64, 1.0f64, false) * fac
}

// Steelnormal: one adjusted asymptotic p-value per comparison
fn kx_steelnormal(a: *mem.Arena, mu: []const f64, sig0: f64, sig: []const f64, tau: []const f64, wvec: []const f64, ni: []const f64, alt: i64, cc: bool, corr: []const f64, out: []f64) -> err {
    let k = ni.len
    var kind = 0usize
    if alt == 0i64 - 1i64 { kind = 1usize }
    if alt == 0i64 { kind = 2usize }
    var j = 0usize
    while j < k {
        var cj = corr[j]
        if !cc { cj = 0.0f64 }
        var s = 0.0f64
        if kind == 0usize { s = (wvec[j] - cj - mu[j]) / tau[j] }
        if kind == 1usize { s = (wvec[j] + cj - mu[j]) / tau[j] }
        if kind == 2usize {
            var d = wvec[j] - cj - mu[j]
            if d < 0.0f64 { d = 0.0f64 - d }
            s = d / tau[j]
        }
        var c = SnCtx { k: k, sig0: sig0, sig: sig, tau: tau, ni: ni, s: s, kind: kind }
        let (r, e) = qags(a, &c, sn_f, 0.0f64 - 10.0f64, 10.0f64, 1.220703125e-4f64, 1.220703125e-4f64, 100usize)
        if e != ok { ret e }
        out[j] = 1.0f64 - r.result
        j += 1usize
    }
    ret ok
}

// the midranks of x
fn kx_midranks(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < x.len {
        var less = 0.0f64
        var eq = 0.0f64
        var j = 0usize
        while j < x.len {
            if x[j] < x[i] { less += 1.0f64 }
            if x[j] == x[i] { eq += 1.0f64 }
            j += 1usize
        }
        r[i] = less + (eq + 1.0f64) / 2.0f64
        i += 1usize
    }
    ret (r, ok)
}

// the tie counts of x: d2 = sum d (d - 1), d3 = sum d (d - 1) (d - 2) over the distinct values
type Ties = struct { d2: f64, d3: f64, d5: f64 }

fn kx_tie_sums(x: []const f64) -> Ties {
    var s2 = 0.0f64
    var s3 = 0.0f64
    var s5 = 0.0f64
    var i = 0usize
    while i < x.len {
        var first = true
        var cnt = 0.0f64
        var j = 0usize
        while j < x.len {
            if x[j] == x[i] {
                cnt += 1.0f64
                if j < i { first = false }
            }
            j += 1usize
        }
        if first {
            s2 += cnt * (cnt - 1.0f64)
            s3 += cnt * (cnt - 1.0f64) * (cnt - 2.0f64)
            s5 += cnt * (cnt - 1.0f64) * (2.0f64 * cnt + 5.0f64)
        }
        i += 1usize
    }
    ret Ties { d2: s2, d3: s3, d5: s5 }
}

type SteelOut = struct {
    stat: f64, asym: f64, p: f64, method: usize, nsim: usize, nties: usize, dist: []f64,
    w: []f64, wstand: []f64, asymadj: []f64, padj: []f64, mu: []f64, tau: []f64, sig0: f64, sig: []f64
}

// Steel.test over the samples stored back to back in x (the first is the control); alt 1 greater, -1 less, 0 two-sided
fn kx_steel_test(a: *mem.Arena, g: *rng.Rng, x: []const f64, sizes: []const usize, alt0: i64, cc: bool, method0: usize, dist0: bool, nsim0: usize) -> (SteelOut, err) {
    let k = sizes.len
    let n = x.len
    let n0 = f64(sizes[0usize])
    var res = SteelOut { stat: 0.0f64, asym: 0.0f64, p: 0.0f64, method: method0, nsim: nsim0, nties: 0usize, dist: sm.kx_empty(a), w: sm.kx_empty(a), wstand: sm.kx_empty(a), asymadj: sm.kx_empty(a), padj: sm.kx_empty(a), mu: sm.kx_empty(a), tau: sm.kx_empty(a), sig0: 0.0f64, sig: sm.kx_empty(a) }
    let (xs, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (res, e0) }
    var i = 0usize
    while i < n {
        xs[i] = x[i]
        if alt0 == 0i64 - 1i64 { xs[i] = 0.0f64 - x[i] }
        i += 1usize
    }
    var alt = alt0
    if alt == 0i64 - 1i64 { alt = 1i64 }
    let (wv, e1) = mem.alloc[f64](a, k)
    let (corr, e2) = mem.alloc[f64](a, k)
    let (mu, e3) = mem.alloc[f64](a, k)
    let (tau, e4) = mem.alloc[f64](a, k)
    let (sig, e5) = mem.alloc[f64](a, k)
    let (ni, e6) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (res, e1) }
    var xst = 0usize
    var s = 1usize
    while s < k {
        xst += sizes[s - 1usize]
        // the pooled control and sample s: the Wilcoxon count of the sample against the control
        let nc = sizes[0usize]
        let nsa = sizes[s]
        var w = 0.0f64
        var ties = false
        var q = 0usize
        while q < nsa {
            let v = xs[xst + q]
            var below = 0.0f64
            var eq = 0.0f64
            var r = 0usize
            while r < nc {
                if xs[r] < v { below += 1.0f64 }
                if xs[r] == v { eq += 1.0f64 }
                r += 1usize
            }
            w += below + eq / 2.0f64
            q += 1usize
        }
        var r2 = 0usize
        while r2 < nc && !ties {
            var q2 = 0usize
            while q2 < nsa {
                if xs[r2] == xs[xst + q2] { ties = true }
                q2 += 1usize
            }
            r2 += 1usize
        }
        // the unique count of the control with itself matters too: a tie inside either sample is a tie of the pooled pair
        var qa = 0usize
        while qa < nc && !ties {
            var qb = qa + 1usize
            while qb < nc {
                if xs[qa] == xs[qb] { ties = true }
                qb += 1usize
            }
            qa += 1usize
        }
        qa = 0usize
        while qa < nsa && !ties {
            var qb = qa + 1usize
            while qb < nsa {
                if xs[xst + qa] == xs[xst + qb] { ties = true }
                qb += 1usize
            }
            qa += 1usize
        }
        wv[s - 1usize] = w
        if ties { corr[s - 1usize] = 0.25f64 } else { corr[s - 1usize] = 0.5f64 }
        ni[s - 1usize] = f64(nsa)
        s += 1usize
    }
    let (rx, e7) = kx_midranks(a, xs)
    if e7 != ok { ret (res, e7) }
    let tie = kx_tie_sums(rx)
    let d2 = tie.d2
    let d3 = tie.d3
    let d5 = tie.d5
    let nn = f64(n)
    let n2 = nn * (nn - 1.0f64)
    let n3 = n2 * (nn - 2.0f64)
    let sig02 = (n0 / 12.0f64) * (1.0f64 - d3 / n3)
    let sig0 = math.sqrt[f64](sig02)
    s = 0usize
    while s + 1usize < k {
        let nis = ni[s]
        let sg2 = (n0 * nis / 12.0f64) * (n0 + 1.0f64 - 3.0f64 * d2 / n2 - (n0 - 2.0f64) * d3 / n3)
        sig[s] = math.sqrt[f64](sg2)
        tau[s] = math.sqrt[f64](nis * nis * sig02 + sg2)
        mu[s] = n0 * nis / 2.0f64
        s += 1usize
    }
    // distinct rank values for the number of ties
    var zl = 0usize
    i = 0usize
    while i < n {
        var first = true
        var j = 0usize
        while j < i {
            if rx[j] == rx[i] { first = false }
            j += 1usize
        }
        if first { zl += 1usize }
        i += 1usize
    }
    var method = method0
    var dist = dist0
    var nsim = nsim0
    if dist && nsim > 100000000usize { nsim = 100000000usize }
    let ncomb = sm.kx_ncomb(sizes)
    if method == 2usize && f64(nsim) < ncomb { method = 1usize }
    if method == 0usize {
        nsim = 1usize
        dist = false
    }
    var nrow = 0usize
    if method == 2usize { nrow = usize(ncomb) }
    if method == 1usize && dist { nrow = nsim }
    let (cx, ec) = sm.kx_ctx(a, 2usize, rx, sizes, rx[0usize..0usize])
    if ec != ok { ret (res, ec) }
    var c = cx
    c.alt = alt
    c.mu = mu
    c.tau = tau
    sm.kx_steelstat(rx, sizes, mu, tau, alt, c.tc)
    var obs = c.tc[0usize]
    var pv = 0.0f64
    var dv = sm.kx_empty(a)
    if method != 0usize {
        let (ov, eo) = mem.alloc[f64](a, 2usize)
        if eo != ok { ret (res, eo) }
        ov[0usize] = obs
        c.teststat = ov
        c.pval[0usize] = 0.0f64
        let (m1, e8) = mem.alloc[f64](a, nrow + 1usize)
        if e8 != ok { ret (res, e8) }
        dv = m1[0usize..nrow]
        if method == 2usize {
            c.ncomb = usize(ncomb)
            if dist {
                c.smat = dv
                c.gets = true
            }
            let er = sm.kx_run_exact(&c)
            if er != ok { ret (res, er) }
            pv = c.pval[0usize] / ncomb
        } else {
            let (rc, er2) = mem.alloc[f64](a, n)
            if er2 != ok { ret (res, er2) }
            var is = 0usize
            var h = 0.0f64
            while is < nsim {
                var q = 0usize
                while q < n {
                    rc[q] = rx[q]
                    q += 1usize
                }
                sm.kx_rand_perm(g, rc, n, sizes[0usize])
                sm.kx_steelstat(rc, sizes, mu, tau, alt, c.tc)
                if c.tc[0usize] >= obs { h += 1.0f64 }
                if dist { dv[is] = c.tc[0usize] }
                is += 1usize
            }
            pv = h / f64(nsim)
        }
    }
    if alt0 == 0i64 - 1i64 {
        obs = 0.0f64 - obs
        i = 0usize
        while i < dv.len {
            dv[i] = 0.0f64 - dv[i]
            i += 1usize
        }
        s = 0usize
        while s + 1usize < k {
            wv[s] = n0 * ni[s] - wv[s]
            s += 1usize
        }
    }
    let wst = ni
    s = 0usize
    let (wstand, e9) = mem.alloc[f64](a, k)
    let (asymadj, e10) = mem.alloc[f64](a, k)
    let (padj, e11) = mem.alloc[f64](a, k)
    if e9 != ok || e10 != ok || e11 != ok { ret (res, e9) }
    while s + 1usize < k {
        wstand[s] = (wv[s] - mu[s]) / tau[s]
        s += 1usize
    }
    let ee = kx_steelnormal(a, mu[0usize..k - 1usize], sig0, sig[0usize..k - 1usize], tau[0usize..k - 1usize], wv[0usize..k - 1usize], ni[0usize..k - 1usize], alt0, cc, corr[0usize..k - 1usize], asymadj)
    if ee != ok { ret (res, ee) }
    var pa = asymadj[0usize]
    s = 1usize
    while s + 1usize < k {
        if asymadj[s] < pa { pa = asymadj[s] }
        s += 1usize
    }
    s = 0usize
    while s + 1usize < k {
        padj[s] = 0.0f64 / 0.0f64
        if method != 0usize && dist {
            var cnt = 0.0f64
            var z = 0usize
            while z < dv.len {
                if alt0 == 0i64 {
                    var av = dv[z]
                    if av < 0.0f64 { av = 0.0f64 - av }
                    var bv = wstand[s]
                    if bv < 0.0f64 { bv = 0.0f64 - bv }
                    if av >= bv { cnt += 1.0f64 }
                }
                if alt0 == 0i64 - 1i64 {
                    if dv[z] <= wstand[s] { cnt += 1.0f64 }
                }
                if alt0 == 1i64 {
                    if dv[z] >= wstand[s] { cnt += 1.0f64 }
                }
                z += 1usize
            }
            padj[s] = cnt / f64(dv.len)
        }
        s += 1usize
    }
    ret (SteelOut { stat: obs, asym: pa, p: pv, method: method, nsim: nsim, nties: n - zl, dist: dv, w: wv[0usize..k - 1usize], wstand: wstand[0usize..k - 1usize], asymadj: asymadj[0usize..k - 1usize], padj: padj[0usize..k - 1usize], mu: mu[0usize..k - 1usize], tau: tau[0usize..k - 1usize], sig0: sig0, sig: sig[0usize..k - 1usize] }, ok)
}

// ---- jt.test and Harding's distribution ----

type JtOut = struct { stat: f64, mu: f64, sig: f64, asym: f64, p: f64, method: usize, nsim: usize, nties: usize, dist: []f64 }

fn kx_jt_test(a: *mem.Arena, g: *rng.Rng, x: []const f64, sizes: []const usize, method0: usize, dist0: bool, nsim0: usize) -> (JtOut, err) {
    let k = sizes.len
    let n = x.len
    var res = JtOut { stat: 0.0f64, mu: 0.0f64, sig: 0.0f64, asym: 0.0f64, p: 0.0f64, method: method0, nsim: nsim0, nties: 0usize, dist: sm.kx_empty(a) }
    let (rx, e0) = kx_midranks(a, x)
    if e0 != ok { ret (res, e0) }
    var zl = 0usize
    var i = 0usize
    while i < n {
        var first = true
        var j = 0usize
        while j < i {
            if rx[j] == rx[i] { first = false }
            j += 1usize
        }
        if first { zl += 1usize }
        i += 1usize
    }
    var method = method0
    var dist = dist0
    var nsim = nsim0
    if dist && nsim > 100000000usize { nsim = 100000000usize }
    let ncomb = sm.kx_ncomb(sizes)
    if method == 2usize && f64(nsim) < ncomb { method = 1usize }
    if method == 0usize {
        nsim = 1usize
        dist = false
    }
    var nrow = 0usize
    if method == 2usize && dist { nrow = usize(ncomb) }
    if method == 1usize && dist { nrow = nsim }
    let (cx, ec) = sm.kx_ctx(a, 3usize, rx, sizes, rx[0usize..0usize])
    if ec != ok { ret (res, ec) }
    var c = cx
    sm.kx_jtstat(rx, sizes, c.tc)
    let obs = c.tc[0usize]
    var pv = 0.0f64
    var dv = sm.kx_empty(a)
    if method != 0usize {
        let (ov, eo) = mem.alloc[f64](a, 2usize)
        if eo != ok { ret (res, eo) }
        ov[0usize] = obs
        c.teststat = ov
        c.pval[0usize] = 0.0f64
        let (m1, e8) = mem.alloc[f64](a, nrow + 1usize)
        if e8 != ok { ret (res, e8) }
        dv = m1[0usize..nrow]
        if method == 2usize {
            c.ncomb = usize(ncomb)
            if dist {
                c.smat = dv
                c.gets = true
            }
            let er = sm.kx_run_exact(&c)
            if er != ok { ret (res, er) }
            pv = c.pval[0usize] / ncomb
        } else {
            let (rc, er2) = mem.alloc[f64](a, n)
            if er2 != ok { ret (res, er2) }
            var is = 0usize
            var h = 0.0f64
            while is < nsim {
                var q = 0usize
                while q < n {
                    rc[q] = rx[q]
                    q += 1usize
                }
                sm.kx_rand_perm(g, rc, n, sizes[0usize])
                sm.kx_jtstat(rc, sizes, c.tc)
                if c.tc[0usize] >= obs { h += 1.0f64 }
                if dist { dv[is] = c.tc[0usize] }
                is += 1usize
            }
            pv = h / f64(nsim)
        }
    }
    if dist {
        i = 0usize
        while i < dv.len {
            dv[i] = sm.kx_round(dv[i], 8i64)
            i += 1usize
        }
    }
    // JTmusig
    let tie = kx_tie_sums(rx)
    let d2 = tie.d2
    let d3 = tie.d3
    let d5 = tie.d5
    let nn = f64(n)
    var x2 = 0.0f64
    var s2 = 0.0f64
    var s3 = 0.0f64
    var cross = 0.0f64
    i = 0usize
    while i < k {
        let ni = f64(sizes[i])
        x2 += ni * (ni - 1.0f64) * (2.0f64 * ni + 5.0f64)
        s2 += ni * (ni - 1.0f64) * (ni - 2.0f64)
        s3 += ni * (ni - 1.0f64)
        var j = i + 1usize
        while j < k {
            cross += ni * f64(sizes[j])
            j += 1usize
        }
        i += 1usize
    }
    let a1 = (nn * (nn - 1.0f64) * (2.0f64 * nn + 5.0f64) - x2 - d5) / 72.0f64
    var a2 = s2 * d3
    a2 = a2 / (36.0f64 * nn * (nn - 1.0f64) * (nn - 2.0f64))
    let a3 = s3 * d2 / (8.0f64 * nn * (nn - 1.0f64))
    let sig = math.sqrt[f64](a1 + a2 + a3)
    let mu = cross / 2.0f64
    let asym = 1.0f64 - kx_pnorm((obs - mu) / sig)
    ret (JtOut { stat: obs, mu: mu, sig: sig, asym: asym, p: pv, method: method, nsim: nsim, nties: n - zl, dist: dv }, ok)
}

// Harding: the null distribution of the Jonckheere-Terpstra count over 0..L for the sample sizes nn (sorted ascending inside)
fn kx_harding(a: *mem.Arena, nn0: []const usize) -> ([]f64, err) {
    let k = nn0.len
    let (nn, e1) = mem.alloc[usize](a, k)
    let (nvec, e2) = mem.alloc[usize](a, k)
    if e1 != ok { ret (sm.kx_empty(a), e1) }
    if e2 != ok { ret (sm.kx_empty(a), e2) }
    var i = 0usize
    while i < k {
        nn[i] = nn0[i]
        i += 1usize
    }
    i = 1usize
    while i < k {
        let t = nn[i]
        var j = i
        while j > 0usize && nn[j - 1usize] > t {
            nn[j] = nn[j - 1usize]
            j -= 1usize
        }
        nn[j] = t
        i += 1usize
    }
    var run = 0usize
    i = k
    while i > 0usize {
        run += nn[i - 1usize]
        nvec[i - 1usize] = run
        i -= 1usize
    }
    var l1 = 1usize
    i = 0usize
    while i + 1usize < k {
        l1 += nn[i] * nvec[i + 1usize]
        i += 1usize
    }
    let (freq, e3) = mem.alloc[f64](a, l1)
    if e3 != ok { ret (freq, e3) }
    let l = l1 - 1usize
    let mm = l / 2usize
    freq[0usize] = 1.0f64
    i = 1usize
    while i < l1 {
        freq[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i + 1usize <= k {
        let m = nvec[i - 1usize] - nvec[i]
        let n = nvec[i]
        if n + 1usize <= mm {
            var p = m + n
            if mm < p { p = mm }
            var t = n + 1usize
            while t <= p {
                var u = mm
                while u >= t {
                    freq[u] = freq[u] - freq[u - t]
                    u -= 1usize
                }
                t += 1usize
            }
        }
        var q = mm
        if m < mm { q = m }
        var s = 1usize
        while s <= q {
            var u = s
            while u <= mm {
                freq[u] = freq[u] + freq[u - s]
                u += 1usize
            }
            s += 1usize
        }
        let mnm = special.choose(f64(m + n), f64(m))
        var ii = 0usize
        while ii < l1 {
            freq[ii] = freq[ii] / mnm
            ii += 1usize
        }
        i += 1usize
    }
    if l % 2usize == 0usize {
        i = 1usize
        while i <= mm {
            freq[mm + i] = freq[mm - i]
            i += 1usize
        }
    } else {
        i = 1usize
        while i <= mm + 1usize {
            freq[mm + i] = freq[mm + 1usize - i]
            i += 1usize
        }
    }
    var tot = 0.0f64
    i = 0usize
    while i < l1 {
        tot += freq[i]
        i += 1usize
    }
    var gap = tot - 1.0f64
    if gap < 0.0f64 { gap = 0.0f64 - gap }
    if tot != tot || gap > 0.0000001f64 {
        i = 0usize
        while i < l1 {
            freq[i] = 0.0f64 / 0.0f64
            i += 1usize
        }
    }
    ret (freq, ok)
}

// djt(x, nn): the probability of the count x (0 outside 0..L)
fn kx_djt(a: *mem.Arena, x: f64, nn: []const usize) -> (f64, err) {
    let (d, e) = kx_harding(a, nn)
    if e != ok { ret (0.0f64, e) }
    if d[0usize] != d[0usize] { ret (0.0f64 / 0.0f64, ok) }
    if x < 0.0f64 || x > f64(d.len - 1usize) || x != math.floor[f64](x) { ret (0.0f64, ok) }
    ret (d[usize(x)], ok)
}

// cumsum as R computes it: the running sum is carried in extended precision (here a double-double) and each partial sum rounded to double
fn kx_cumsum(a: *mem.Arena, d: []const f64, shift: usize) -> ([]f64, err) {
    let (cum, e) = mem.alloc[f64](a, d.len + shift)
    if e != ok { ret (cum, e) }
    var hi = 0.0f64
    var lo = 0.0f64
    if shift == 1usize { cum[0usize] = 0.0f64 }
    var i = 0usize
    while i < d.len {
        let s = hi + d[i]
        let bb = s - hi
        let err2 = (hi - (s - bb)) + (d[i] - bb)
        lo += err2
        hi = s + lo
        lo = lo - (hi - s)
        cum[i + shift] = hi
        i += 1usize
    }
    ret (cum, ok)
}

// pjt(x, nn): the probability of a count of at most floor(x)
fn kx_pjt(a: *mem.Arena, x0: f64, nn: []const usize) -> (f64, err) {
    let (d, e) = kx_harding(a, nn)
    if e != ok { ret (0.0f64, e) }
    if d[0usize] != d[0usize] { ret (0.0f64 / 0.0f64, ok) }
    let x = math.floor[f64](x0)
    if x > f64(d.len - 1usize) { ret (1.0f64, ok) }
    if x < 0.0f64 { ret (0.0f64, ok) }
    let (cum, e2) = kx_cumsum(a, d, 0usize)
    if e2 != ok { ret (0.0f64, e2) }
    ret (cum[usize(x)], ok)
}

// qjt(p, nn): the smallest count whose cumulative probability reaches p, as the package finds it with findInterval
fn kx_qjt(a: *mem.Arena, p: f64, nn: []const usize) -> (f64, err) {
    let (d, e) = kx_harding(a, nn)
    if e != ok { ret (0.0f64, e) }
    if d[0usize] != d[0usize] { ret (0.0f64 / 0.0f64, ok) }
    let (cum, e2) = kx_cumsum(a, d, 1usize)
    if e2 != ok { ret (0.0f64, e2) }
    var i = 0usize
    // findInterval: how many of the cumulative values are at most p
    var out = 0usize
    var hit = false
    i = 0usize
    while i < cum.len {
        if cum[i] <= p { out += 1usize }
        if cum[i] == p { hit = true }
        i += 1usize
    }
    if hit { out -= 1usize }
    if out == 0usize { ret (0.0f64 - 1.0f64 / 0.0f64, ok) }
    ret (f64(out - 1usize), ok)
}
