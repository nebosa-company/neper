// R stats::stl (the Cleveland et al. seasonal-trend decomposition by loess) as stats/src/stl.c does it, with the R
// level of stl(): the window and jump defaults, the periodic option and the robustness iterations. Series are n
// values with a period np (the series starting at the first position of the cycle).
//
// Not here: missing values (the series must be complete) and a start inside a cycle.

use e.math
use e.mem

fn ipow3(x: f64) -> f64 { ret x * (x * x) }

// the loess value at xs (1-based abscissa) from the neighbours nleft..nright (1-based): false when the weights sum to nothing
fn stlest(y: []const f64, n: usize, len: usize, ideg: i64, xs: f64, ys: []f64, yi: usize, nleft: usize, nright: usize, w: []f64, use_rw: bool, rw: []const f64) -> bool {
    let range = f64(n - 1usize)
    var h = math.max[f64](xs - f64(nleft), f64(nright) - xs)
    if len > n { h += f64((len - n) / 2usize) }
    let h9 = h * 0.999f64
    let h1 = h * 0.001f64
    var a = 0.0f64
    var j = nleft - 1usize
    while j < nright {
        let r = math.abs[f64](f64(j + 1usize) - xs)
        if r <= h9 {
            if r <= h1 { w[j] = 1.0f64 } else { w[j] = ipow3(1.0f64 - ipow3(r / h)) }
            if use_rw { w[j] = rw[j] * w[j] }
            a += w[j]
        } else {
            w[j] = 0.0f64
        }
        j += 1usize
    }
    if a <= 0.0f64 { ret false }
    j = nleft - 1usize
    while j < nright {
        w[j] = w[j] / a
        j += 1usize
    }
    if h > 0.0f64 && ideg > 0i64 {
        a = 0.0f64
        j = nleft - 1usize
        while j < nright {
            a += w[j] * f64(j + 1usize)
            j += 1usize
        }
        var b = xs - a
        var c = 0.0f64
        j = nleft - 1usize
        while j < nright {
            let d = f64(j + 1usize) - a
            c += w[j] * (d * d)
            j += 1usize
        }
        if math.sqrt[f64](c) > range * 0.001f64 {
            b = b / c
            j = nleft - 1usize
            while j < nright {
                w[j] = w[j] * (b * (f64(j + 1usize) - a) + 1.0f64)
                j += 1usize
            }
        }
    }
    var s = 0.0f64
    j = nleft - 1usize
    while j < nright {
        s += w[j] * y[j]
        j += 1usize
    }
    ys[yi] = s
    ret true
}

// loess smoothing of y at every njump-th point with linear interpolation between; ys receives n values, res is workspace
fn stless(y: []const f64, n: usize, len: usize, ideg: i64, njump: usize, use_rw: bool, rw: []const f64, ys: []f64, res: []f64) {
    if n < 2usize {
        ys[0usize] = y[0usize]
        ret
    }
    var newnj = njump
    if n - 1usize < newnj { newnj = n - 1usize }
    var nleft = 1usize
    var nright = n
    if len >= n {
        nleft = 1usize
        nright = n
        var i = 0usize
        while i < n {
            let ok_ = stlest(y, n, len, ideg, f64(i + 1usize), ys, i, nleft, nright, res, use_rw, rw)
            if !ok_ { ys[i] = y[i] }
            i += newnj
        }
    } else {
        let nsh = (len + 1usize) / 2usize
        if newnj == 1usize {
            nleft = 1usize
            nright = len
            var i = 0usize
            while i < n {
                if i + 1usize > nsh && nright != n {
                    nleft += 1usize
                    nright += 1usize
                }
                let ok_ = stlest(y, n, len, ideg, f64(i + 1usize), ys, i, nleft, nright, res, use_rw, rw)
                if !ok_ { ys[i] = y[i] }
                i += 1usize
            }
        } else {
            nleft = 1usize
            nright = len
            var i = 0usize
            while i < n {
                if i + 1usize < nsh {
                    nleft = 1usize
                    nright = len
                } else if i >= n - nsh {
                    nleft = n - len + 1usize
                    nright = n
                } else {
                    nleft = i + 1usize - nsh + 1usize
                    nright = len + i + 1usize - nsh
                }
                let ok_ = stlest(y, n, len, ideg, f64(i + 1usize), ys, i, nleft, nright, res, use_rw, rw)
                if !ok_ { ys[i] = y[i] }
                i += newnj
            }
        }
    }
    if newnj != 1usize {
        var i = 0usize
        while i + newnj < n {
            let delta = (ys[i + newnj] - ys[i]) / f64(newnj)
            var j = i + 1usize
            while j <= i + newnj - 1usize {
                ys[j] = ys[i] + delta * f64(j - i)
                j += 1usize
            }
            i += newnj
        }
        let k = (n - 1usize) / newnj * newnj
        if k != n - 1usize {
            let ok_ = stlest(y, n, len, ideg, f64(n), ys, n - 1usize, nleft, nright, res, use_rw, rw)
            if !ok_ { ys[n - 1usize] = y[n - 1usize] }
            let delta = (ys[n - 1usize] - ys[k]) / f64(n - 1usize - k)
            var j = k + 1usize
            while j < n - 1usize {
                ys[j] = ys[k] + delta * f64(j - k)
                j += 1usize
            }
        }
    }
}

// the moving average of length len over x (n values), n - len + 1 results in ave
fn stlma(x: []const f64, n: usize, len: usize, ave: []f64) {
    let flen = f64(len)
    var v = 0.0f64
    var i = 0usize
    while i < len {
        v += x[i]
        i += 1usize
    }
    ave[0usize] = v / flen
    let newn = n - len + 1usize
    if newn > 1usize {
        var k = len
        var m = 0usize
        var j = 1usize
        while j < newn {
            v += x[k] - x[m]
            ave[j] = v / flen
            j += 1usize
            k += 1usize
            m += 1usize
        }
    }
}

fn stlfts(x: []const f64, n: usize, np: usize, trend: []f64, work: []f64) {
    stlma(x, n, np, trend)
    stlma(trend, n - np + 1usize, np, work)
    stlma(work, n - 2usize * np + 2usize, 3usize, trend)
}

// the cycle-subseries smoothing of one inner iteration
fn stlss(y: []const f64, n: usize, np: usize, ns: usize, isdeg: i64, nsjump: usize, use_rw: bool, rw: []const f64, season: []f64, work1: []f64, work2: []f64, work3: []f64, work4: []f64) {
    var j = 0usize
    while j < np {
        let k = (n - (j + 1usize)) / np + 1usize
        var i = 0usize
        while i < k {
            work1[i] = y[i * np + j]
            i += 1usize
        }
        if use_rw {
            i = 0usize
            while i < k {
                work3[i] = rw[i * np + j]
                i += 1usize
            }
        }
        stless(work1, k, ns, isdeg, nsjump, use_rw, work3, work2[1usize..work2.len], work4)
        var nright = ns
        if k < nright { nright = k }
        var ok_ = stlest(work1, k, ns, isdeg, 0.0f64, work2, 0usize, 1usize, nright, work4, use_rw, work3)
        if !ok_ { work2[0usize] = work2[1usize] }
        var nleft = 1usize
        if k + 1usize > ns { nleft = k - ns + 1usize }
        ok_ = stlest(work1, k, ns, isdeg, f64(k + 1usize), work2, k + 1usize, nleft, k, work4, use_rw, work3)
        if !ok_ { work2[k + 1usize] = work2[k] }
        var m = 0usize
        while m < k + 2usize {
            season[m * np + j] = work2[m]
            m += 1usize
        }
        j += 1usize
    }
}

// the robustness weights from the residuals y - fit (a partial sort of the two middle order statistics)
fn stlrwt(a: *mem.Arena, y: []const f64, n: usize, fit: []const f64, rw: []f64) -> err {
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        s[i] = math.abs[f64](y[i] - fit[i])
        i += 1usize
    }
    let mid0 = n / 2usize + 1usize
    let mid1 = n - mid0 + 1usize
    let (mid, em) = mem.alloc[usize](a, 2usize)
    if em != ok { ret em }
    mid[0usize] = mid0
    mid[1usize] = mid1
    psort(s, n, mid, 2usize)
    let cmad = (s[mid0 - 1usize] + s[mid1 - 1usize]) * 3.0f64
    let c9 = cmad * 0.999f64
    let c1 = cmad * 0.001f64
    i = 0usize
    while i < n {
        let r = math.abs[f64](y[i] - fit[i])
        if r <= c1 {
            rw[i] = 1.0f64
        } else if r <= c9 {
            let d2 = r / cmad
            let id2 = 1.0f64 - d2 * d2
            rw[i] = id2 * id2
        } else {
            rw[i] = 0.0f64
        }
        i += 1usize
    }
    ret ok
}

// stl.c's stl(): the decomposition into season and trend with the spans, degrees and jumps given
fn stl_core(a: *mem.Arena, y: []const f64, np0: usize, ns0: usize, nt0: usize, nl0: usize, isdeg: i64, itdeg: i64, ildeg: i64, nsjump: usize, ntjump: usize, nljump: usize, niter: usize, nout: usize, rw: []f64, season: []f64, trend: []f64) -> err {
    let n = y.len
    var ns = ns0
    if ns < 3usize { ns = 3usize }
    var nt = nt0
    if nt < 3usize { nt = 3usize }
    var nl = nl0
    if nl < 3usize { nl = 3usize }
    if ns % 2usize == 0usize { ns += 1usize }
    if nt % 2usize == 0usize { nt += 1usize }
    if nl % 2usize == 0usize { nl += 1usize }
    var np = np0
    if np < 2usize { np = 2usize }
    let n2p = n + 2usize * np
    let (w1, e1) = mem.alloc[f64](a, n2p)
    let (w2, e2) = mem.alloc[f64](a, n2p)
    let (w3, e3) = mem.alloc[f64](a, n2p)
    let (w4, e4) = mem.alloc[f64](a, n2p)
    let (w5, e5) = mem.alloc[f64](a, n2p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        trend[i] = 0.0f64
        season[i] = 0.0f64
        i += 1usize
    }
    var use_rw = false
    var k = 0usize
    var go = true
    while go {
        var it = 1usize
        while it <= niter {
            i = 0usize
            while i < n {
                w1[i] = y[i] - trend[i]
                i += 1usize
            }
            stlss(w1, n, np, ns, isdeg, nsjump, use_rw, rw, w2, w3, w4, w5, season)
            stlfts(w2, n2p, np, w3, w1)
            stless(w3, n, nl, ildeg, nljump, false, w4, w1, w5)
            i = 0usize
            while i < n {
                season[i] = w2[np + i] - w1[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                w1[i] = y[i] - season[i]
                i += 1usize
            }
            stless(w1, n, nt, itdeg, ntjump, use_rw, rw, trend, w3)
            it += 1usize
        }
        k += 1usize
        if k > nout {
            go = false
        } else {
            i = 0usize
            while i < n {
                w1[i] = trend[i] + season[i]
                i += 1usize
            }
            let er = stlrwt(a, y, n, w1, rw)
            if er != ok { ret er }
            use_rw = true
        }
    }
    if nout == 0usize {
        i = 0usize
        while i < n {
            rw[i] = 1.0f64
            i += 1usize
        }
    }
    ret ok
}

fn nextodd(x: f64) -> usize {
    var r = x - math.floor[f64](x)
    var fl = math.floor[f64](x)
    var v = fl
    if r > 0.5f64 { v = fl + 1.0f64 }
    if r == 0.5f64 {
        if math.floor[f64](fl / 2.0f64) * 2.0f64 == fl { v = fl } else { v = fl + 1.0f64 }
    }
    var k = usize(v)
    if k % 2usize == 0usize { k += 1usize }
    ret k
}

fn win_check(x: f64) -> usize {
    let k = nextodd(x)
    if k < 3usize { ret 3usize }
    ret k
}

fn ceil_usize(x: f64) -> usize { ret usize(math.ceil[f64](x)) }

// R's stl() with the defaults of the R level: swin is the s.window (ignored when periodic), twin and lwin the t.window and l.window (0 for the defaults), the jumps 0 for the defaults; out arrays are n long
fn stl(a: *mem.Arena, y: []const f64, period: usize, periodic: bool, swin: f64, sdeg: i64, twin: f64, tdeg: i64, lwin: f64, ldeg: i64, sjump: usize, tjump: usize, ljump: usize, robust: bool, season: []f64, trend: []f64, rw: []f64) -> err {
    let n = y.len
    var sw = swin
    var sd = sdeg
    if periodic {
        sw = 10.0f64 * f64(n) + 1.0f64
        sd = 0i64
    }
    var tw = twin
    if twin == 0.0f64 { tw = math.ceil[f64](1.5f64 * f64(period) / (1.0f64 - 1.5f64 / sw)) }
    let t_win = win_check(tw)
    let s_win = win_check(sw)
    var lw = lwin
    if lwin == 0.0f64 { lw = f64(nextodd(f64(period))) }
    let l_win = win_check(lw)
    var sj = sjump
    if sj == 0usize { sj = ceil_usize(f64(s_win) / 10.0f64) }
    var tj = tjump
    if tj == 0usize { tj = ceil_usize(f64(t_win) / 10.0f64) }
    var lj = ljump
    if lj == 0usize { lj = ceil_usize(f64(l_win) / 10.0f64) }
    if sj < 1usize { sj = 1usize }
    if tj < 1usize { tj = 1usize }
    if lj < 1usize { lj = 1usize }
    var inner = 2usize
    var outer = 0usize
    if robust {
        inner = 1usize
        outer = 15usize
    }
    let e = stl_core(a, y, period, s_win, t_win, l_win, sd, tdeg, ldeg, sj, tj, lj, inner, outer, rw, season, trend)
    if e != ok { ret e }
    if periodic {
        var j = 0usize
        while j < period {
            var s = 0.0f64
            var c = 0.0f64
            var i = j
            while i < n {
                s += season[i]
                c += 1.0f64
                i += period
            }
            let m = s / c
            i = j
            while i < n {
                season[i] = m
                i += period
            }
            j += 1usize
        }
    }
    ret ok
}

// R's psort (stats/src/stl.c): a partial sort of the n values of a that puts the order statistics at the 1-based positions ind[0..ni] in place. The index list is used as given: for the two middle positions of an even n it is descending, so the partial sort can leave the lower position unsorted, exactly as R does.
fn psort(a: []f64, n: usize, ind: []const usize, ni: usize) {
    if n < 2usize || ni == 0usize { ret }
    var il: [16]usize = zero
    var iu: [16]usize = zero
    var indl: [16]usize = zero
    var indu: [16]usize = zero
    var jl = 1usize
    var ju = ni
    var i = 1usize
    var j = n
    var m = 0usize
    indl[0usize] = 1usize
    indu[0usize] = ni
    var k = 0usize
    var l = 0usize
    var t = 0.0f64
    // states: 0 outer test, 1 pop, 2 while (j - i > 10), 3 partition, 4 the final insertion sort
    var st = 0usize
    var done = false
    while !done {
        if st == 0usize {
            if i < j { st = 3usize } else { st = 1usize }
        } else if st == 1usize {
            if m == 0usize {
                done = true
            } else {
                m -= 1usize
                i = il[m]
                j = iu[m]
                jl = indl[m]
                ju = indu[m]
                if jl <= ju { st = 2usize } else { st = 1usize }
            }
        } else if st == 2usize {
            if j - i > 10usize { st = 3usize } else { st = 4usize }
        } else if st == 3usize {
            k = i
            l = j
            let ij = (i + j) / 2usize
            t = a[ij - 1usize]
            if a[i - 1usize] > t {
                a[ij - 1usize] = a[i - 1usize]
                a[i - 1usize] = t
                t = a[ij - 1usize]
            }
            if a[j - 1usize] < t {
                a[ij - 1usize] = a[j - 1usize]
                a[j - 1usize] = t
                t = a[ij - 1usize]
                if a[i - 1usize] > t {
                    a[ij - 1usize] = a[i - 1usize]
                    a[i - 1usize] = t
                    t = a[ij - 1usize]
                }
            }
            var brk = false
            while !brk {
                l -= 1usize
                if a[l - 1usize] <= t {
                    let tt = a[l - 1usize]
                    k += 1usize
                    while a[k - 1usize] < t { k += 1usize }
                    if k > l {
                        brk = true
                    } else {
                        a[l - 1usize] = a[k - 1usize]
                        a[k - 1usize] = tt
                    }
                }
            }
            indl[m] = jl
            indu[m] = ju
            let p1 = m
            m += 1usize
            if l - i <= j - k {
                il[p1] = k
                iu[p1] = j
                j = l
                var back = false
                var go = true
                while go {
                    if jl > ju {
                        back = true
                        go = false
                    } else if ind[ju - 1usize] > j {
                        ju -= 1usize
                    } else {
                        go = false
                    }
                }
                if back { st = 1usize } else {
                    indl[p1] = ju + 1usize
                    st = 2usize
                }
            } else {
                il[p1] = i
                iu[p1] = l
                i = k
                var back = false
                var go = true
                while go {
                    if jl > ju {
                        back = true
                        go = false
                    } else if ind[jl - 1usize] < i {
                        jl += 1usize
                    } else {
                        go = false
                    }
                }
                if back { st = 1usize } else {
                    indu[p1] = jl - 1usize
                    st = 2usize
                }
            }
        } else {
            if i != 1usize {
                i -= 1usize
                var fin = false
                while !fin {
                    i += 1usize
                    if i == j {
                        fin = true
                        st = 1usize
                    } else {
                        t = a[i]
                        if a[i - 1usize] > t {
                            k = i
                            var sh = true
                            while sh {
                                a[k] = a[k - 1usize]
                                k -= 1usize
                                if t >= a[k - 1usize] { sh = false }
                            }
                            a[k] = t
                        }
                    }
                }
            } else {
                st = 0usize
            }
        }
    }
}
