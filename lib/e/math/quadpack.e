// QUADPACK's adaptive integration over an infinite range, as R's integrate() runs it (appl/integrate.c rdqagie, with rdqk15i,
// the epsilon algorithm rdqelg and the error-list sort rdqpsrt): the range is mapped onto (0,1), cut by repeated bisection of the
// interval with the largest error, and the sequence of partial sums is extrapolated by Wynn's epsilon algorithm.

use e.math
use e.mem

type Qagi = struct { result: f64, abserr: f64, neval: i64, ier: i64, last: usize }

type Eps = struct { n: usize, nres: usize, result: f64, abserr: f64 }

type Srt = struct { maxerr: usize, ermax: f64, nrmax: usize }

fn epmach() -> f64 { ret 2.220446049250313e-16f64 }

fn dbl_min() -> f64 { ret 2.2250738585072014e-308f64 }

fn dbl_max() -> f64 { ret 1.7976931348623157e308f64 }

fn mx(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn mn(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn ab(a: f64) -> f64 { ret math.abs[f64](a) }

fn wg15(j: usize) -> f64 {
    if j == 1usize { ret 0.129484966168869693270611432679082f64 }
    if j == 3usize { ret 0.27970539148927666790146777142378f64 }
    if j == 5usize { ret 0.381830050505118944950369775488975f64 }
    if j == 7usize { ret 0.417959183673469387755102040816327f64 }
    ret 0.0f64
}

fn xgk15(j: usize) -> f64 {
    if j == 0usize { ret 0.991455371120812639206854697526329f64 }
    if j == 1usize { ret 0.949107912342758524526189684047851f64 }
    if j == 2usize { ret 0.864864423359769072789712788640926f64 }
    if j == 3usize { ret 0.741531185599394439863864773280788f64 }
    if j == 4usize { ret 0.58608723546769113029414483825873f64 }
    if j == 5usize { ret 0.405845151377397166906606412076961f64 }
    if j == 6usize { ret 0.207784955007898467600689403773245f64 }
    ret 0.0f64
}

fn wgk15(j: usize) -> f64 {
    if j == 0usize { ret 0.02293532201052922496373200805897f64 }
    if j == 1usize { ret 0.063092092629978553290700663189204f64 }
    if j == 2usize { ret 0.104790010322250183839876322541518f64 }
    if j == 3usize { ret 0.140653259715525918745189590510238f64 }
    if j == 4usize { ret 0.16900472663926790282658342659855f64 }
    if j == 5usize { ret 0.190350578064785409913256402421014f64 }
    if j == 6usize { ret 0.204432940075298892414161999234649f64 }
    ret 0.209482141084727828012999174891714f64
}

// The transformed integrand at x in (0,1), summing both tails when inf == 2.
fn tf[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, boun: f64, dinf: f64, inf: i64, t: f64) -> f64 {
    let x = boun + dinf * (1.0f64 - t) / t
    var v = f(ctx, x)
    if inf == 2i64 { v += f(ctx, 0.0f64 - x) }
    ret v / t / t
}


type Kron = struct { result: f64, abserr: f64, resabs: f64, resasc: f64 }

// The 15-point Kronrod rule over (a,b) of the transformed range. R keeps the 14 off-centre values for the second pass; this
// evaluates them again, which gives the same numbers.
fn qk15i[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, boun: f64, inf: i64, a: f64, b: f64) -> Kron {
    var dinf = 1.0f64
    if inf == 0i64 - 1i64 { dinf = 0.0f64 - 1.0f64 }
    let centr = (a + b) * 0.5f64
    let hlgth = (b - a) * 0.5f64
    let fc = tf(ctx, f, boun, dinf, inf, centr)
    var resg = wg15(7usize) * fc
    var resk = wgk15(7usize) * fc
    var resabs = ab(resk)
    var j = 0usize
    while j < 7usize {
        let absc = hlgth * xgk15(j)
        let v1 = tf(ctx, f, boun, dinf, inf, centr - absc)
        let v2 = tf(ctx, f, boun, dinf, inf, centr + absc)
        let fsum = v1 + v2
        resg += wg15(j) * fsum
        resk += wgk15(j) * fsum
        resabs += wgk15(j) * (ab(v1) + ab(v2))
        j += 1usize
    }
    let reskh = resk * 0.5f64
    var resasc = wgk15(7usize) * ab(fc - reskh)
    j = 0usize
    while j < 7usize {
        let absc = hlgth * xgk15(j)
        let v1 = tf(ctx, f, boun, dinf, inf, centr - absc)
        let v2 = tf(ctx, f, boun, dinf, inf, centr + absc)
        resasc += wgk15(j) * (ab(v1 - reskh) + ab(v2 - reskh))
        j += 1usize
    }
    let result = resk * hlgth
    resasc = resasc * hlgth
    resabs = resabs * hlgth
    var abserr = ab((resk - resg) * hlgth)
    if resasc != 0.0f64 && abserr != 0.0f64 {
        abserr = resasc * mn(1.0f64, math.pow[f64](abserr * 200.0f64 / resasc, 1.5f64))
    }
    if resabs > dbl_min() / (epmach() * 50.0f64) {
        abserr = mx(epmach() * 50.0f64 * resabs, abserr)
    }
    var kr: Kron = zero
    kr = Kron { result: result, abserr: abserr, resabs: resabs, resasc: resasc }
    ret kr
}

// Wynn's epsilon algorithm on the 1-based table epstab (at least 54 long); res3la is 1-based and 4 long.
fn qelg(st: *Eps, epstab: []f64, res3la: []f64) {
    let eps = epmach()
    let oflow = dbl_max()
    st.nres += 1usize
    st.abserr = oflow
    st.result = epstab[st.n]
    var done = false
    if st.n >= 3usize {
        let limexp = 50usize
        epstab[st.n + 2usize] = epstab[st.n]
        let newelm = (st.n - 1usize) / 2usize
        epstab[st.n] = oflow
        let num = st.n
        var k1 = st.n
        var i = 1usize
        var stop = false
        while i <= newelm && !stop {
            let k2 = k1 - 1usize
            let k3 = k1 - 2usize
            var res = epstab[k1 + 2usize]
            let e0 = epstab[k3]
            let e1 = epstab[k2]
            let e2 = res
            let e1abs = ab(e1)
            let delta2 = e2 - e1
            let err2 = ab(delta2)
            let tol2 = mx(ab(e2), e1abs) * eps
            let delta3 = e1 - e0
            let err3 = ab(delta3)
            let tol3 = mx(e1abs, ab(e0)) * eps
            if err2 <= tol2 && err3 <= tol3 {
                st.result = res
                st.abserr = err2 + err3
                done = true
                stop = true
            } else {
                let e3 = epstab[k1]
                epstab[k1] = e1
                let delta1 = e1 - e3
                let err1 = ab(delta1)
                let tol1 = mx(e1abs, ab(e3)) * eps
                var good = false
                var ss = 0.0f64
                if err1 > tol1 && err2 > tol2 && err3 > tol3 {
                    ss = 1.0f64 / delta1 + 1.0f64 / delta2 - 1.0f64 / delta3
                    if ab(ss * e1) > 1.0e-4f64 { good = true }
                }
                if !good {
                    st.n = i + i - 1usize
                    stop = true
                } else {
                    res = e1 + 1.0f64 / ss
                    epstab[k1] = res
                    k1 -= 2usize
                    let erra = err2 + ab(res - e2) + err3
                    if erra <= st.abserr {
                        st.abserr = erra
                        st.result = res
                    }
                    i += 1usize
                }
            }
        }
        if !done {
            if st.n == limexp { st.n = (limexp / 2usize) * 2usize - 1usize }
            var ib = 1usize
            if (num / 2usize) * 2usize == num { ib = 2usize }
            let ie = newelm + 1usize
            var q = 1usize
            while q <= ie {
                let ib2 = ib + 2usize
                epstab[ib] = epstab[ib2]
                ib = ib2
                q += 1usize
            }
            if num != st.n {
                var indx = num - st.n + 1usize
                q = 1usize
                while q <= st.n {
                    epstab[q] = epstab[indx]
                    indx += 1usize
                    q += 1usize
                }
            }
            if st.nres >= 4usize {
                st.abserr = ab(st.result - res3la[3usize]) + ab(st.result - res3la[2usize]) + ab(st.result - res3la[1usize])
                res3la[1usize] = res3la[2usize]
                res3la[2usize] = res3la[3usize]
                res3la[3usize] = st.result
            } else {
                res3la[st.nres] = st.result
                st.abserr = oflow
            }
        }
    }
    st.abserr = mx(st.abserr, eps * 5.0f64 * ab(st.result))
}

// Keeps iord (1-based) ordered by decreasing error and selects the nrmax-th largest.
fn qpsrt(limit: usize, last: usize, s: *Srt, elist: []f64, iord: []usize) {
    if last <= 2usize {
        iord[1usize] = 1usize
        iord[2usize] = 2usize
    } else {
        let errmax = elist[s.maxerr]
        if s.nrmax > 1usize {
            let ido = s.nrmax - 1usize
            var i = 1usize
            while i <= ido {
                let isucc = iord[s.nrmax - 1usize]
                if errmax <= elist[isucc] { break }
                iord[s.nrmax] = isucc
                s.nrmax -= 1usize
                i += 1usize
            }
        }
        var jupbn = last
        if last > limit / 2usize + 2usize { jupbn = limit + 3usize - last }
        let errmin = elist[last]
        let jbnd = jupbn - 1usize
        var i = s.nrmax + 1usize
        var placed = false
        while i <= jbnd && !placed {
            let isucc = iord[i]
            if errmax >= elist[isucc] {
                iord[i - 1usize] = s.maxerr
                var j = i
                var k = jbnd
                var inserted = false
                while j <= jbnd && !inserted {
                    let is2 = iord[k]
                    if errmin < elist[is2] {
                        iord[k + 1usize] = last
                        inserted = true
                    } else {
                        iord[k + 1usize] = is2
                        j += 1usize
                        k -= 1usize
                    }
                }
                if !inserted { iord[i] = last }
                placed = true
            } else {
                iord[i - 1usize] = isucc
                i += 1usize
            }
        }
        if !placed {
            iord[jbnd] = s.maxerr
            iord[jupbn] = last
        }
    }
    s.maxerr = iord[s.nrmax]
    s.ermax = elist[s.maxerr]
}

// qagi(f, bound, inf, epsabs, epsrel, limit): inf 1 is (bound, Inf), -1 is (-Inf, bound), 2 is the whole line.
fn qagi[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64) -> f64, bound: f64, inf: i64, epsabs: f64, epsrel: f64, limit: usize) -> (Qagi, err) {
    var out = Qagi { result: 0.0f64, abserr: 0.0f64, neval: 0i64, ier: 0i64, last: 0usize }
    let eps = epmach()
    if epsabs <= 0.0f64 && epsrel < mx(eps * 50.0f64, 5.0e-29f64) {
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
    blist[1usize] = 1.0f64
    var boun = bound
    if inf == 2i64 { boun = 0.0f64 }
    let k0 = qk15i(ctx, f, boun, inf, 0.0f64, 1.0f64)
    var result = k0.result
    var abserr = k0.abserr
    let defabs = k0.resabs
    let resabs0 = k0.resasc
    var ier = 0i64
    var last = 1usize
    rlist[1usize] = result
    elist[1usize] = abserr
    iord[1usize] = 1usize
    let dres = ab(result)
    var errbnd = mx(epsabs, epsrel * dres)
    if abserr <= eps * 100.0f64 * defabs && abserr > errbnd { ier = 2i64 }
    if limit == 1usize { ier = 1i64 }
    var phase = 0i64
    if ier != 0i64 || (abserr <= errbnd && abserr != resabs0) || abserr == 0.0f64 { phase = 130 }
    var area = result
    var errsum = abserr
    let oflow = dbl_max()
    let uflow = dbl_min()
    var small = 0.0f64
    var erlarg = 0.0f64
    var ertest = 0.0f64
    var correc = 0.0f64
    var ierro = 0i64
    var ksgn = 0i64 - 1i64
    var es = Eps { n: 2usize, nres: 0usize, result: 0.0f64, abserr: 0.0f64 }
    var sr = Srt { maxerr: 1usize, ermax: abserr, nrmax: 1usize }
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
                let q1 = qk15i(ctx, f, boun, inf, a1, b1)
                let q2 = qk15i(ctx, f, boun, inf, a2, b2)
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
                    if ab(rlist[sr.maxerr] - area12) <= ab(area12) * 1.0e-5f64 && erro12 >= sr.ermax * 0.99f64 {
                        if extrap { iroff2 += 1i64 } else { iroff1 += 1i64 }
                    }
                    if last > 10usize && erro12 > sr.ermax { iroff3 += 1i64 }
                }
                rlist[sr.maxerr] = area1
                rlist[last] = area2
                errbnd = mx(epsabs, epsrel * ab(area))
                if iroff1 + iroff2 >= 10i64 || iroff3 >= 20i64 { ier = 2i64 }
                if iroff2 >= 5i64 { ierro = 3i64 }
                if last == limit { ier = 1i64 }
                if mx(ab(a1), ab(b2)) <= (eps * 100.0f64 + 1.0f64) * (ab(a2) + uflow * 1000.0f64) { ier = 4i64 }
                if error2 <= error1 {
                    alist[last] = a2
                    blist[sr.maxerr] = b1
                    blist[last] = b2
                    elist[sr.maxerr] = error1
                    elist[last] = error2
                } else {
                    alist[sr.maxerr] = a2
                    alist[last] = a1
                    blist[last] = b1
                    rlist[sr.maxerr] = area2
                    rlist[last] = area1
                    elist[sr.maxerr] = error2
                    elist[last] = error1
                }
                qpsrt(limit, last, &sr, elist, iord)
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
                    small = 0.375f64
                    erlarg = errsum
                    ertest = errbnd
                    rlist2[2usize] = area
                    break
                }
                if noext { break }
                erlarg -= erlast
                if ab(b1 - a1) > small { erlarg += erro12 }
                if !extrap {
                    if ab(blist[sr.maxerr] - alist[sr.maxerr]) > small { break }
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
                        if ab(blist[sr.maxerr] - alist[sr.maxerr]) > small {
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
                qelg(&es, rlist2, res3la)
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
                    ertest = mx(epsabs, epsrel * ab(reseps))
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
                } else if abserr / ab(result) > errsum / ab(area) {
                    t = 115i64
                }
            }
            if t == 110i64 {
                if ksgn == 0i64 - 1i64 && mx(ab(result), ab(area)) <= defabs * 0.01f64 {
                    t = 130i64
                } else {
                    if 0.01f64 > result / area || result / area > 100.0f64 || errsum > ab(area) { ier = 6i64 }
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
    out.neval = i64(last) * 30i64 - 15i64
    if inf == 2i64 { out.neval = out.neval * 2i64 }
    if ier > 2i64 { ier -= 1i64 }
    out.ier = ier
    ret (out, ok)
}

fn wg21(j: usize) -> f64 {
    if j == 0usize { ret 0.066671344308688137593568809893332f64 }
    if j == 1usize { ret 0.149451349150580593145776339657697f64 }
    if j == 2usize { ret 0.219086362515982043995534934228163f64 }
    if j == 3usize { ret 0.26926671930999635509122692156947f64 }
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

// QUADPACK dqk21 as R's rdqk21: the 21-point Gauss-Kronrod rule over (a, b)
fn qk21[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, a: f64, b: f64) -> Kron {
    let centr = (a + b) * 0.5f64
    let hlgth = (b - a) * 0.5f64
    let dhlgth = ab(hlgth)
    var resg = 0.0f64
    let fc = f(ctx, centr)
    var resk = wgk21(10usize) * fc
    var resabs = ab(resk)
    var j = 0usize
    while j < 5usize {
        let jtw = 2usize * j + 1usize
        let absc = hlgth * xgk21(jtw)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        let fsum = v1 + v2
        resg += wg21(j) * fsum
        resk += wgk21(jtw) * fsum
        resabs += wgk21(jtw) * (ab(v1) + ab(v2))
        j += 1usize
    }
    j = 0usize
    while j < 5usize {
        let jtwm1 = 2usize * j
        let absc = hlgth * xgk21(jtwm1)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        let fsum = v1 + v2
        resk += wgk21(jtwm1) * fsum
        resabs += wgk21(jtwm1) * (ab(v1) + ab(v2))
        j += 1usize
    }
    let reskh = resk * 0.5f64
    var resasc = wgk21(10usize) * ab(fc - reskh)
    j = 0usize
    while j < 10usize {
        let absc = hlgth * xgk21(j)
        let v1 = f(ctx, centr - absc)
        let v2 = f(ctx, centr + absc)
        resasc += wgk21(j) * (ab(v1 - reskh) + ab(v2 - reskh))
        j += 1usize
    }
    let result = resk * hlgth
    resasc = resasc * dhlgth
    resabs = resabs * dhlgth
    var abserr = ab((resk - resg) * hlgth)
    if resasc != 0.0f64 && abserr != 0.0f64 {
        abserr = resasc * mn(1.0f64, math.pow[f64](abserr * 200.0f64 / resasc, 1.5f64))
    }
    if resabs > dbl_min() / (epmach() * 50.0f64) {
        abserr = mx(epmach() * 50.0f64 * resabs, abserr)
    }
    var kr: Kron = zero
    kr = Kron { result: result, abserr: abserr, resabs: resabs, resasc: resasc }
    ret kr
}

// R's integrate() on a finite range (rdqagse): adaptive bisection with Wynn's epsilon extrapolation; the same extrapolation code as qagi
fn qags[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64, epsabs: f64, epsrel: f64, limit: usize) -> (Qagi, err) {
    var out = Qagi { result: 0.0f64, abserr: 0.0f64, neval: 0i64, ier: 0i64, last: 0usize }
    let eps = epmach()
    if epsabs <= 0.0f64 && epsrel < mx(eps * 50.0f64, 5.0e-29f64) {
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
    let dres = ab(result)
    var errbnd = mx(epsabs, epsrel * dres)
    if abserr <= eps * 100.0f64 * defabs && abserr > errbnd { ier = 2i64 }
    if limit == 1usize { ier = 1i64 }
    var phase = 0i64
    if ier != 0i64 || (abserr <= errbnd && abserr != resabs0) || abserr == 0.0f64 { phase = 130 }
    var area = result
    var errsum = abserr
    let oflow = dbl_max()
    let uflow = dbl_min()
    var small = 0.0f64
    var erlarg = 0.0f64
    var ertest = 0.0f64
    var correc = 0.0f64
    var ierro = 0i64
    var ksgn = 0i64 - 1i64
    var es = Eps { n: 2usize, nres: 0usize, result: 0.0f64, abserr: 0.0f64 }
    var sr = Srt { maxerr: 1usize, ermax: abserr, nrmax: 1usize }
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
                    if ab(rlist[sr.maxerr] - area12) <= ab(area12) * 1.0e-5f64 && erro12 >= sr.ermax * 0.99f64 {
                        if extrap { iroff2 += 1i64 } else { iroff1 += 1i64 }
                    }
                    if last > 10usize && erro12 > sr.ermax { iroff3 += 1i64 }
                }
                rlist[sr.maxerr] = area1
                rlist[last] = area2
                errbnd = mx(epsabs, epsrel * ab(area))
                if iroff1 + iroff2 >= 10i64 || iroff3 >= 20i64 { ier = 2i64 }
                if iroff2 >= 5i64 { ierro = 3i64 }
                if last == limit { ier = 1i64 }
                if mx(ab(a1), ab(b2)) <= (eps * 100.0f64 + 1.0f64) * (ab(a2) + uflow * 1000.0f64) { ier = 4i64 }
                if error2 <= error1 {
                    alist[last] = a2
                    blist[sr.maxerr] = b1
                    blist[last] = b2
                    elist[sr.maxerr] = error1
                    elist[last] = error2
                } else {
                    alist[sr.maxerr] = a2
                    alist[last] = a1
                    blist[last] = b1
                    rlist[sr.maxerr] = area2
                    rlist[last] = area1
                    elist[sr.maxerr] = error2
                    elist[last] = error1
                }
                qpsrt(limit, last, &sr, elist, iord)
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
                    small = ab(hi - lo) * 0.375f64
                    erlarg = errsum
                    ertest = errbnd
                    rlist2[2usize] = area
                    break
                }
                if noext { break }
                erlarg -= erlast
                if ab(b1 - a1) > small { erlarg += erro12 }
                if !extrap {
                    if ab(blist[sr.maxerr] - alist[sr.maxerr]) > small { break }
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
                        if ab(blist[sr.maxerr] - alist[sr.maxerr]) > small {
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
                qelg(&es, rlist2, res3la)
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
                    ertest = mx(epsabs, epsrel * ab(reseps))
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
                } else if abserr / ab(result) > errsum / ab(area) {
                    t = 115i64
                }
            }
            if t == 110i64 {
                if ksgn == 0i64 - 1i64 && mx(ab(result), ab(area)) <= defabs * 0.01f64 {
                    t = 130i64
                } else {
                    if 0.01f64 > result / area || result / area > 100.0f64 || errsum > ab(area) { ier = 6i64 }
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
    if ier > 2i64 { ier -= 1i64 }
    out.ier = ier
    ret (out, ok)
}
