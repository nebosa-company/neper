// R pcaPP: `cor_fk` (Knight's O(n log n) Kendall tau-b, cov.kendall.cpp) and the geometric median `l1median_hocr` (Hossjer and
// Croux) and `l1median_vazh` (Vardi and Zhang) of L1Median_HoCr.cpp and L1Median_VardiZhang.cpp. R's `l1median` itself runs `nlm`;
// the minimum of the sum of Euclidean distances is unique, so these reach it to the tolerance asked.
//
// And PCAproj (the eachobs search with the optional update, scale estimators sd, mad and qn). Not here: PCAgrid and sPCAgrid, the
// lincomb and sphere candidate sets (they draw random directions) and the null-space completion R applies when the data collapse.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

// Stable ascending merge sort of keys with their companions, counting the inversions (strictly smaller on the right).
fn msort(x: []f64, buf: []f64, lo: usize, len: usize) -> u64 {
    if len < 2usize { ret 0u64 }
    let half = len / 2usize
    var sw = msort(x, buf, lo, half)
    sw += msort(x, buf, lo + half, len - half)
    var l = lo
    let le = lo + half
    var r = lo + half
    let re = lo + len
    var b = lo
    while l < le && r < re {
        if x[r] < x[l] {
            buf[b] = x[r]
            sw += u64(le - l)
            r += 1usize
        } else {
            buf[b] = x[l]
            l += 1usize
        }
        b += 1usize
    }
    while l < le {
        buf[b] = x[l]
        l += 1usize
        b += 1usize
    }
    while r < re {
        buf[b] = x[r]
        r += 1usize
        b += 1usize
    }
    var i = lo
    while i < lo + len {
        x[i] = buf[i]
        i += 1usize
    }
    ret sw
}

// pairs among ties in sorted data[lo..lo+len)
fn get_ms(data: []const f64, lo: usize, len: usize) -> u64 {
    var ms = 0u64
    var tie = 0u64
    var i = lo + 1usize
    while i < lo + len {
        if data[i] == data[i - 1usize] {
            tie += 1u64
        } else if tie > 0u64 {
            ms += tie * (tie + 1u64) / 2u64
            tie = 0u64
        }
        i += 1usize
    }
    if tie > 0u64 { ms += tie * (tie + 1u64) / 2u64 }
    ret ms
}

// order(x) as R gives it (ties keep their positions): sort the pairs by a merge on the index
fn order_stable(a: *mem.Arena, x: []const f64, idx: []usize) -> bool {
    let n = x.len
    let (buf, e) = mem.alloc[usize](a, n)
    if e != ok { ret false }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    var w = 1usize
    while w < n {
        var lo = 0usize
        while lo < n {
            var mid = lo + w
            if mid > n { mid = n }
            var hi = lo + 2usize * w
            if hi > n { hi = n }
            var l = lo
            var r = mid
            var b = lo
            while l < mid && r < hi {
                if x[idx[r]] < x[idx[l]] {
                    buf[b] = idx[r]
                    r += 1usize
                } else {
                    buf[b] = idx[l]
                    l += 1usize
                }
                b += 1usize
            }
            while l < mid {
                buf[b] = idx[l]
                l += 1usize
                b += 1usize
            }
            while r < hi {
                buf[b] = idx[r]
                r += 1usize
                b += 1usize
            }
            lo = lo + 2usize * w
        }
        i = 0usize
        while i < n {
            idx[i] = buf[i]
            i += 1usize
        }
        w = w * 2usize
    }
    ret true
}

// cor.fk(x, y): Kendall's tau-b of two vectors, the covariance 2 s when cor is false.
fn cor_fk(a: *mem.Arena, x: []const f64, y: []const f64, cor: bool) -> f64 {
    let n = x.len
    let nan = 0.0f64 / 0.0f64
    let (idx, e1) = mem.alloc[usize](a, n)
    let (a1, e2) = mem.alloc[f64](a, n)
    let (a2, e3) = mem.alloc[f64](a, n)
    let (buf, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    if !order_stable(a, x, idx) { ret nan }
    var i = 0usize
    while i < n {
        a1[i] = x[idx[i]]
        a2[i] = y[idx[i]]
        i += 1usize
    }
    let np = u64(n) * (u64(n) - 1u64) / 2u64
    var s = i64(np)
    var m1 = 0u64
    var tie = 0usize
    i = 1usize
    while i < n {
        if a1[i - 1usize] == a1[i] {
            tie += 1usize
        } else if tie > 0usize {
            let lo = i - tie - 1usize
            let _ = msort(a2, buf, lo, tie + 1usize)
            m1 += u64(tie) * (u64(tie) + 1u64) / 2u64
            s += i64(get_ms(a2, lo, tie + 1usize))
            tie = 0usize
        }
        i += 1usize
    }
    if tie > 0usize {
        let lo = n - tie - 1usize
        let _ = msort(a2, buf, lo, tie + 1usize)
        m1 += u64(tie) * (u64(tie) + 1u64) / 2u64
        s += i64(get_ms(a2, lo, tie + 1usize))
    }
    let swaps = msort(a2, buf, 0usize, n)
    let m2 = get_ms(a2, 0usize, n)
    s = s - i64(m1 + m2) - 2i64 * i64(swaps)
    if cor {
        let d1 = f64(np - m1)
        let d2 = f64(np - m2)
        ret f64(s) / math.sqrt[f64](d1) / math.sqrt[f64](d2)
    }
    ret 2.0f64 * f64(s)
}

type L1Res = struct { code: i64, iter: i64 }

// sum of the Euclidean distances of the n rows of the column-major x to med
fn l1_obj(x: []const f64, n: usize, p: usize, med: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var q = 0.0f64
        var j = 0usize
        while j < p {
            let d = x[j * n + i] - med[j]
            q += d * d
            j += 1usize
        }
        s += math.sqrt[f64](q)
        i += 1usize
    }
    ret s
}

// l1median_HoCr: the modified Weiszfeld iteration with step halving; med holds the start and is overwritten. Codes: 0 converged,
// 1 not converged, 2 step halving failed, 3 more than half the observations sit at the estimate.
fn l1median_hocr(a: *mem.Arena, x: []const f64, n: usize, p: usize, med: []f64, tol: f64, maxit: i64) -> (L1Res, err) {
    var out = L1Res { code: 1i64, iter: 0i64 }
    let (old, e1) = mem.alloc[f64](a, p)
    let (delta, e2) = mem.alloc[f64](a, p)
    let (sq, e3) = mem.alloc[f64](a, n)
    let (w, e4) = mem.alloc[f64](a, n)
    let (ord, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (out, e1) }
    let ln2 = math.log[f64](2.0f64)
    var obj_old = 0.0f64
    var k = 0i64
    var fin = false
    while k < maxit && !fin {
        var i = 0usize
        var nz = 0usize
        var sumw = 0.0f64
        while i < n {
            var q = 0.0f64
            var j = 0usize
            while j < p {
                let d = x[j * n + i] - med[j]
                q += d * d
                j += 1usize
            }
            sq[i] = q
            if q <= 0.0f64 {
                w[i] = 0.0f64
                nz += 1usize
            } else {
                w[i] = math.pow[f64](q, 0.0f64 - 0.5f64)
            }
            i += 1usize
        }
        // R adds the weights in the order of increasing distance
        if !order_stable(a, sq, ord) { ret (out, e1) }
        i = 0usize
        while i < n {
            if sq[ord[i]] > 0.0f64 { sumw += w[ord[i]] }
            i += 1usize
        }
        if k == 0i64 {
            i = 0usize
            while i < n {
                obj_old += math.sqrt[f64](sq[i])
                i += 1usize
            }
        }
        if nz > 0usize && nz - 1usize > (n + 1usize) / 2usize {
            out.code = 3i64
            fin = true
        } else {
            var j = 0usize
            while j < p {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += (x[j * n + i] - med[j]) * w[i]
                    i += 1usize
                }
                delta[j] = s / sumw
                j += 1usize
            }
            var nd = 0.0f64
            j = 0usize
            while j < p {
                nd += delta[j] * delta[j]
                old[j] = med[j]
                med[j] += delta[j]
                j += 1usize
            }
            nd = math.sqrt[f64](nd)
            var obj = l1_obj(x, n, p, med)
            if nd < tol {
                out.code = 0i64
                fin = true
            } else {
                var steps = i64(math.ceil[f64](math.log[f64](nd / tol) / ln2))
                while obj >= obj_old && !fin {
                    j = 0usize
                    while j < p {
                        delta[j] = delta[j] / 2.0f64
                        med[j] = old[j] + delta[j]
                        j += 1usize
                    }
                    obj = l1_obj(x, n, p, med)
                    if steps == 0i64 {
                        j = 0usize
                        while j < p {
                            med[j] = old[j]
                            j += 1usize
                        }
                        out.code = 2i64
                        fin = true
                    } else {
                        steps -= 1i64
                    }
                }
                obj_old = obj
            }
        }
        if !fin { k += 1i64 }
    }
    out.iter = k
    ret (out, ok)
}

// l1median_VaZh: Vardi and Zhang's iteration (including the package's own treatment of an estimate that equals observations).
fn l1median_vazh(a: *mem.Arena, x: []const f64, n: usize, p: usize, med: []f64, tol: f64, zero_tol: f64, maxit: i64) -> (L1Res, err) {
    var out = L1Res { code: 0i64, iter: 0i64 }
    let (old, e1) = mem.alloc[f64](a, p)
    let (tt, e2) = mem.alloc[f64](a, p)
    let (rt, e3) = mem.alloc[f64](a, p)
    let (d, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, e1) }
    var i = maxit - 1i64
    var go = true
    while i >= 0i64 && go {
        var j = 0usize
        while j < p {
            old[j] = med[j]
            j += 1usize
        }
        // one iteration
        var r = 0usize
        var dmin = 1.0e308f64
        while r < n {
            var q = 0.0f64
            j = 0usize
            while j < p {
                let dd = x[j * n + r] - med[j]
                q += dd * dd
                j += 1usize
            }
            d[r] = math.sqrt[f64](q)
            if d[r] < dmin { dmin = d[r] }
            r += 1usize
        }
        var greater = 0usize
        r = 0usize
        while r < n {
            if dmin / zero_tol <= d[r] { greater += 1usize }
            r += 1usize
        }
        var cont = true
        if greater * 2usize > n {
            // median of the distances, by a sort on a copy
            let (cp, ec) = mem.alloc[f64](a, n)
            let (bf, eb) = mem.alloc[f64](a, n)
            if ec != ok || eb != ok { ret (out, ec) }
            r = 0usize
            while r < n {
                cp[r] = d[r]
                r += 1usize
            }
            let _ = msort(cp, bf, 0usize, n)
            var md = cp[n / 2usize]
            if n % 2usize == 0usize { md = (cp[n / 2usize - 1usize] + cp[n / 2usize]) / 2.0f64 }
            let thr = md * zero_tol
            var nonzero = 0usize
            r = 0usize
            while r < n {
                if d[r] > thr { nonzero += 1usize }
                r += 1usize
            }
            let dwzero = n - nonzero
            if dwzero > n / 2usize {
                cont = false
            } else {
                j = 0usize
                while j < p {
                    tt[j] = 0.0f64
                    rt[j] = 0.0f64
                    j += 1usize
                }
                var inv = 0.0f64
                r = 0usize
                while r < n {
                    if d[r] > thr {
                        j = 0usize
                        while j < p {
                            tt[j] += x[j * n + r] / d[r]
                            rt[j] += (x[j * n + r] - med[j]) / d[r]
                            j += 1usize
                        }
                        inv += 1.0f64 / d[r]
                    }
                    r += 1usize
                }
                j = 0usize
                var rr = 0.0f64
                while j < p {
                    tt[j] = tt[j] / inv
                    rr += rt[j] * rt[j]
                    j += 1usize
                }
                let edivr = f64(dwzero) / math.sqrt[f64](rr)
                if edivr > 1.0f64 {
                    j = 0usize
                    while j < p {
                        med[j] = med[j] * edivr
                        j += 1usize
                    }
                }
                if edivr < 1.0f64 {
                    j = 0usize
                    while j < p {
                        med[j] += (1.0f64 - edivr) * tt[j]
                        j += 1usize
                    }
                }
            }
        } else {
            j = 0usize
            while j < p {
                med[j] = 0.0f64
                j += 1usize
            }
            var sw = 0.0f64
            r = 0usize
            while r < n {
                j = 0usize
                while j < p {
                    med[j] += x[j * n + r] / d[r]
                    j += 1usize
                }
                sw += 1.0f64 / d[r]
                r += 1usize
            }
            j = 0usize
            while j < p {
                med[j] = med[j] / sw
                j += 1usize
            }
        }
        if !cont {
            go = false
        } else {
            var sum = 0.0f64
            var diff = 0.0f64
            j = 0usize
            while j < p {
                sum += math.abs[f64](med[j])
                diff += math.abs[f64](old[j] - med[j])
                j += 1usize
            }
            if diff < tol * sum {
                go = false
            } else {
                i -= 1i64
            }
        }
    }
    out.iter = maxit - i
    ret (out, ok)
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> []f64 {
    let n = v.len
    let (c, e1) = mem.alloc[f64](a, n)
    let (b, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret c }
    var i = 0usize
    while i < n {
        c[i] = v[i]
        i += 1usize
    }
    let _ = msort(c, b, 0usize, n)
    ret c
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let n = v.len
    if n == 0usize { ret 0.0f64 / 0.0f64 }
    let s = sorted_copy(a, v)
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

fn mad_of(a: *mem.Arena, v: []const f64, centre: bool) -> f64 {
    let n = v.len
    let (d, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var c = 0.0f64
    if centre { c = median_of(a, v) }
    var i = 0usize
    while i < n {
        d[i] = math.abs[f64](v[i] - c)
        i += 1usize
    }
    ret median_of(a, d) * 1.482602218505602f64
}

fn sd_of(v: []const f64) -> f64 {
    let n = v.len
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i]
        i += 1usize
    }
    let m = s / f64(n)
    var d = 0.0f64
    i = 0usize
    while i < n {
        d += (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](d / f64(n - 1usize))
}

// qn: the Croux and Rousseeuw scale, the k-th smallest pairwise distance with k = C(n/2 + 1, 2), times pcaPP's small-sample factor.
fn qn_of(a: *mem.Arena, v: []const f64) -> f64 {
    let n = v.len
    let y = sorted_copy(a, v)
    let m = n * (n - 1usize) / 2usize
    let (dd, e1) = mem.alloc[f64](a, m)
    let (bf, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var t = 0usize
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            dd[t] = y[i] - y[j]
            t += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let _ = msort(dd, bf, 0usize, m)
    let h = n / 2usize + 1usize
    let kk = h * (h - 1usize) / 2usize
    let raw = dd[kk - 1usize]
    var fact = 0.0f64
    if n <= 9usize {
        var c = 0.400f64
        if n == 3usize { c = 0.993f64 }
        if n == 4usize { c = 0.514f64 }
        if n == 5usize { c = 0.845f64 }
        if n == 6usize { c = 0.612f64 }
        if n == 7usize { c = 0.859f64 }
        if n == 8usize { c = 0.670f64 }
        if n == 9usize { c = 0.874f64 }
        fact = 2.21914446598508f64 * c
    } else if n % 2usize == 1usize {
        fact = 2.21914446598508f64 * f64(n) / (f64(n) + 1.4f64)
    } else {
        fact = 2.21914446598508f64 * f64(n) / (f64(n) + 3.8f64)
    }
    ret raw * fact
}

// ApplyMethod of pcaPP: 0 sd, 1 mad, 2 qn, 3 scaled median of absolute values, 5 mean square
fn scale_method(a: *mem.Arena, v: []const f64, method: i64) -> f64 {
    if method == 0i64 { ret sd_of(v) }
    if method == 1i64 { ret mad_of(a, v, true) }
    if method == 2i64 { ret qn_of(a, v) }
    if method == 3i64 { ret mad_of(a, v, false) }
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * v[i]
        i += 1usize
    }
    ret s / f64(v.len)
}

// out = x %*% w over the first nr rows of the nn by p column-major x
fn proj(x: []const f64, nn: usize, p: usize, nr: usize, w: []const f64, out: []f64) {
    var r = 0usize
    while r < nr {
        out[r] = 0.0f64
        r += 1usize
    }
    var c = 0usize
    while c < p {
        r = 0usize
        while r < nr {
            out[r] += w[c] * x[c * nn + r]
            r += 1usize
        }
        c += 1usize
    }
}

// PCAproj on the centred data y (nn by p, column-major, the first nr rows are the observations): loadings (p by k), scores (nr by k) and
// lambda (k) as C_pcaProj and C_pcaProj_up return them, before R sorts the components. A lambda of -1 marks a column left unfilled.
fn pca_proj(a: *mem.Arena, y: []const f64, nn: usize, p: usize, nr: usize, k: usize, method: i64, zero_tol: f64, update: bool, maxit: usize, maxhalf: usize, load: []f64, z: []f64, lam: []f64) -> err {
    let (x, e1) = mem.alloc[f64](a, nn * p)
    let (hlp, e2) = mem.alloc[f64](a, nn)
    let (tf, e3) = mem.alloc[bool](a, nn)
    let (cs, e4) = mem.alloc[f64](a, nn)
    let (ts, e5) = mem.alloc[f64](a, nn)
    let (vh, e6) = mem.alloc[f64](a, p)
    let (cur, e7) = mem.alloc[f64](a, p)
    let (am, e8) = mem.alloc[f64](a, nn * p)
    let (sg, e9) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret e1 }
    var i = 0usize
    while i < nn * p {
        x[i] = y[i]
        i += 1usize
    }
    i = 0usize
    while i < p * k {
        load[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nr * k {
        z[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        lam[i] = 0.0f64
        i += 1usize
    }
    var cur_lambda = 0.0f64
    var ki = 0usize
    var done = false
    while ki < k && !done {
        var r = 0usize
        while r < nn {
            hlp[r] = 0.0f64
            r += 1usize
        }
        var c = 0usize
        while c < p {
            r = 0usize
            while r < nn {
                hlp[r] += x[c * nn + r] * x[c * nn + r]
                r += 1usize
            }
            c += 1usize
        }
        var short = 0usize
        r = 0usize
        while r < nn {
            tf[r] = hlp[r] > zero_tol
            if tf[r] { short += 1usize }
            r += 1usize
        }
        if short == 0usize {
            var q = ki
            while q < k {
                lam[q] = 0.0f64
                if ki > 0usize { lam[q] = 0.0f64 - 1.0f64 }
                q += 1usize
            }
            if ki == 0usize {
                var d = 0usize
                while d < p && d < k {
                    load[d * p + d] = 1.0f64
                    d += 1usize
                }
            }
            done = true
        } else {
            var rr = 0usize
            r = 0usize
            while r < nn {
                if tf[r] {
                    c = 0usize
                    while c < p {
                        am[c * short + rr] = x[c * nn + r] / math.sqrt[f64](hlp[r])
                        c += 1usize
                    }
                    rr += 1usize
                }
                r += 1usize
            }
            if ki < p - 1usize {
                var best = short
                var has_best = false
                var j = short
                while j > 0usize {
                    j -= 1usize
                    c = 0usize
                    while c < p {
                        cur[c] = am[c * short + j]
                        c += 1usize
                    }
                    proj(x, nn, p, nr, cur, cs)
                    let scat = scale_method(a, cs[0usize..nr], method)
                    if !has_best || cur_lambda < scat {
                        best = j
                        has_best = true
                        cur_lambda = scat
                    }
                }
                c = 0usize
                while c < p {
                    load[ki * p + c] = am[c * short + best]
                    c += 1usize
                }
                proj(x, nn, p, nn, load[ki * p..ki * p + p], cs)
                if update {
                    var m = maxit
                    var stop = false
                    while m > 0usize && !stop {
                        var q = 0usize
                        r = 0usize
                        while r < nn {
                            if tf[r] {
                                sg[q] = 1.0f64
                                if cs[r] < 0.0f64 { sg[q] = 0.0f64 - 1.0f64 }
                                q += 1usize
                            }
                            r += 1usize
                        }
                        c = 0usize
                        var sq = 0.0f64
                        while c < p {
                            var s = 0.0f64
                            q = 0usize
                            while q < short {
                                s += am[c * short + q] * sg[q]
                                q += 1usize
                            }
                            vh[c] = s
                            sq += s * s
                            c += 1usize
                        }
                        var new_obj = 0.0f64
                        var kk = 0usize
                        var step_ok = false
                        while kk <= maxhalf && !step_ok {
                            if kk > 0usize {
                                sq = 0.0f64
                                c = 0usize
                                while c < p {
                                    vh[c] = (vh[c] + load[ki * p + c]) / 2.0f64
                                    sq += vh[c] * vh[c]
                                    c += 1usize
                                }
                            }
                            let nrm = math.sqrt[f64](sq)
                            c = 0usize
                            while c < p {
                                vh[c] = vh[c] / nrm
                                c += 1usize
                            }
                            proj(x, nn, p, nn, vh, ts)
                            new_obj = scale_method(a, ts[0usize..nn], method)
                            if new_obj >= cur_lambda { step_ok = true }
                            kk += 1usize
                        }
                        if new_obj < cur_lambda {
                            stop = true
                        } else {
                            r = 0usize
                            while r < nn {
                                cs[r] = ts[r]
                                r += 1usize
                            }
                            c = 0usize
                            while c < p {
                                load[ki * p + c] = vh[c]
                                c += 1usize
                            }
                            cur_lambda = new_obj
                            m -= 1usize
                        }
                    }
                }
                r = 0usize
                while r < nr {
                    z[ki * nr + r] = cs[r]
                    r += 1usize
                }
                if ki < k - 1usize {
                    c = 0usize
                    while c < p {
                        r = 0usize
                        while r < nn {
                            x[c * nn + r] -= cs[r] * load[ki * p + c]
                            r += 1usize
                        }
                        c += 1usize
                    }
                }
                lam[ki] = cur_lambda
            } else {
                let lc = ki * p
                var r2 = 0usize
                while r2 < p {
                    var s = 1.0f64
                    c = 0usize
                    while c < p - 1usize {
                        s -= load[c * p + r2] * load[c * p + r2]
                        c += 1usize
                    }
                    load[lc + r2] = math.sqrt[f64](s)
                    r2 += 1usize
                }
                // pcaPP's which_max1 assigns pMax = p instead of pCur, so it always answers the first element
                let nmax = 0usize
                r2 = 0usize
                while r2 < p {
                    var s = 0.0f64
                    c = 0usize
                    while c < p - 1usize {
                        s += load[c * p + r2] * load[c * p + nmax]
                        c += 1usize
                    }
                    if r2 == nmax { s = 0.0f64 - s }
                    if s > 0.0f64 { load[lc + r2] = 0.0f64 - load[lc + r2] }
                    r2 += 1usize
                }
                proj(x, nn, p, nn, load[lc..lc + p], cs)
                lam[ki] = scale_method(a, cs[0usize..nr], method)
                r = 0usize
                while r < nr {
                    z[ki * nr + r] = cs[r]
                    r += 1usize
                }
            }
            ki += 1usize
        }
    }
    ret ok
}

// R's .DataPostProc and .loadSgnU: the components in decreasing order of lambda (ties keep their order), each loading column signed so
// its largest entry is positive.
fn proj_finish(p: usize, nr: usize, k: usize, load: []f64, z: []f64, lam: []f64) {
    var pass = 0usize
    while pass < k {
        var i = 0usize
        while i + 1usize < k {
            if lam[i + 1usize] > lam[i] {
                let t = lam[i]
                lam[i] = lam[i + 1usize]
                lam[i + 1usize] = t
                var c = 0usize
                while c < p {
                    let u = load[i * p + c]
                    load[i * p + c] = load[(i + 1usize) * p + c]
                    load[(i + 1usize) * p + c] = u
                    c += 1usize
                }
                c = 0usize
                while c < nr {
                    let u = z[i * nr + c]
                    z[i * nr + c] = z[(i + 1usize) * nr + c]
                    z[(i + 1usize) * nr + c] = u
                    c += 1usize
                }
            }
            i += 1usize
        }
        pass += 1usize
    }
    var i = 0usize
    while i < k {
        var im = 0usize
        var c = 1usize
        while c < p {
            if math.abs[f64](load[i * p + c]) > math.abs[f64](load[i * p + im]) { im = c }
            c += 1usize
        }
        if load[i * p + im] < 0.0f64 {
            c = 0usize
            while c < p {
                load[i * p + c] = 0.0f64 - load[i * p + c]
                c += 1usize
            }
        }
        i += 1usize
    }
}

// the scale estimate of v by `method`, with the arena handed back
fn grid_scat(a: *mem.Arena, v: []const f64, method: i64) -> f64 {
    let start = mem.mark(a)
    let r = scale_method(a, v, method)
    mem.reset(a, start)
    ret r
}

// the sparseness penalty of sPCAgrid for the direction (cs, sn): minus lambda times (sum |cs * others + sn * this|^q)^s
fn grid_pen(oth: []const f64, thi: []const f64, p: usize, cs: f64, sn: f64, q: f64, s: f64, zt: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret 0.0f64 }
    var d = 0.0f64
    var i = 0usize
    while i < p {
        var v = 0.0f64
        if math.abs[f64](cs) <= zt { v = math.abs[f64](thi[i]) } else if math.abs[f64](sn) <= zt { v = math.abs[f64](oth[i]) } else { v = math.abs[f64](cs * oth[i] + sn * thi[i]) }
        if q != 1.0f64 { v = math.pow[f64](v, q) }
        d += v
        i += 1usize
    }
    if s != 1.0f64 { d = math.pow[f64](d, s) }
    ret 0.0f64 - d * lambda
}

fn norm2_of(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * v[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

// PCAgrid (CPCAGrid::Calc with kIni 0 and no dimension reduction) on the centred, scaled data x (n by p, column-major, n >= p):
// `load` (p by p, column-major) and `sdev` (p) as C_PCAgrid returns them, and `obj` (k). R then cuts to k, signs and orders them.
// A non-empty `lam` (k values) makes it sPCAgrid: the objective is the squared scale minus lambda * (sum |loading|^qn)^sn_ times the
// overall scatter of the data (glo.scatter 0).
fn pca_grid(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, method: i64, maxiter: usize, splitcircle: usize, zero_tol: f64, lam: []const f64, qn: f64, sn_: f64, load: []f64, sdev: []f64, obj: []f64) -> err {
    let (ya, e1) = mem.alloc[f64](a, n * p)
    let (yb, e2) = mem.alloc[f64](a, n * p)
    let (afin, e3) = mem.alloc[f64](a, p)
    let (best, e4) = mem.alloc[f64](a, p)
    let (scl, e5) = mem.alloc[f64](a, p)
    let (ord, e6) = mem.alloc[usize](a, p)
    let (yopt, e7) = mem.alloc[f64](a, n)
    let (pr, e8) = mem.alloc[f64](a, n)
    let (tpp, e9) = mem.alloc[f64](a, p * p)
    let (ps, e10) = mem.alloc[f64](a, p * p)
    let (old, e11) = mem.alloc[f64](a, p * p)
    let (oth, e12) = mem.alloc[f64](a, p)
    let (thi, e13) = mem.alloc[f64](a, p)
    if e12 != ok || e13 != ok { ret e12 }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret e1 }
    if k > p { ret mem.Invalid }
    var y = ya
    var yn = yb
    var i = 0usize
    while i < n * p {
        y[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        load[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        load[i * p + i] = 1.0f64
        sdev[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        obj[i] = 0.0f64
        i += 1usize
    }
    let sqrt2 = math.sqrt[f64](2.0f64)
    let pi = 3.141592653589793f64
    var glo = 1.0f64
    if lam.len > 0usize {
        var tt = 0.0f64
        var c0 = 0usize
        while c0 < p {
            let s0 = grid_scat(a, x[c0 * n..c0 * n + n], method)
            tt += s0 * s0
            c0 += 1usize
        }
        let g0 = math.sqrt[f64](tt / f64(p))
        glo = g0 * g0
    }
    var ck = 0usize
    while ck < k {
        let ps_n = p - ck
        if ps_n == 1usize {
            sdev[ck] = grid_scat(a, y[0usize..n], method)
            ck += 1usize
            continue
        }
        var c = 0usize
        while c < ps_n {
            scl[c] = grid_scat(a, y[c * n..c * n + n], method)
            ord[c] = c
            c += 1usize
        }
        c = 1usize
        while c < ps_n {
            let o = ord[c]
            var d = c
            while d > 0usize && scl[ord[d - 1usize]] < scl[o] {
                ord[d] = ord[d - 1usize]
                d -= 1usize
            }
            ord[d] = o
            c += 1usize
        }
        var cur_p = ord[0usize]
        c = 0usize
        while c < ps_n {
            afin[c] = 0.0f64
            c += 1usize
        }
        afin[cur_p] = 1.0f64
        c = 0usize
        while c < n {
            yopt[c] = y[cur_p * n + c]
            c += 1usize
        }
        var scat_best = 0.0f64
        var obj_best = 0.0f64
        var best_obj = 0.0f64
        var cur_scat = 0.0f64
        var it = 0usize
        while it <= maxiter {
            var cur_split = 1.0f64
            var q = 0usize
            while q < it {
                cur_split = cur_split * 0.5f64
                q += 1usize
            }
            var j = 0usize
            while j < ps_n {
                cur_p = ord[j]
                let dl = afin[cur_p]
                if math.abs[f64](dl) == 1.0f64 {
                    j += 1usize
                    continue
                }
                let cy = y[cur_p * n..cur_p * n + n]
                if dl != 0.0f64 {
                    let dcl = math.sqrt[f64](1.0f64 - dl * dl)
                    c = 0usize
                    while c < n {
                        yopt[c] = (yopt[c] - cy[c] * dl) / dcl
                        c += 1usize
                    }
                    c = 0usize
                    while c < ps_n {
                        afin[c] = afin[c] / dcl
                        c += 1usize
                    }
                    afin[cur_p] = 0.0f64
                }
                var cur_lam = 0.0f64
                if lam.len > 0usize { cur_lam = lam[ck] }
                if cur_lam != 0.0f64 {
                    var r0 = 0usize
                    while r0 < p {
                        var sm = 0.0f64
                        var c1 = 0usize
                        while c1 < ps_n {
                            sm += load[(ck + c1) * p + r0] * afin[c1]
                            c1 += 1usize
                        }
                        oth[r0] = sm
                        thi[r0] = load[(ck + cur_p) * p + r0]
                        r0 += 1usize
                    }
                }
                var nl = dl
                var ncl = 0.0f64
                let asin_nl = math.asin[f64](nl)
                var sm1 = 1.0f64
                if splitcircle > 1usize { sm1 = f64(splitcircle - 1usize) }
                let split_fact = pi * cur_split
                best_obj = 0.0f64 - 1.0e308f64
                var dir = 0usize
                var dir_end = splitcircle
                if cur_split == 1.0f64 { dir_end = splitcircle - 1usize }
                if nl != 0.0f64 && math.abs[f64](nl) < 1.0e-6f64 {
                    c = 0usize
                    while c < n {
                        pr[c] = yopt[c]
                        c += 1usize
                    }
                    let sc = grid_scat(a, pr, method)
                    let ob = sc * sc + grid_pen(oth, thi, p, 1.0f64, 0.0f64, qn, sn_, zero_tol, cur_lam) * glo
                    if ob > best_obj {
                        best_obj = ob
                        cur_scat = sc
                        nl = 0.0f64
                        ncl = 1.0f64
                    }
                }
                while dir < dir_end {
                    let ang = (f64(dir) / sm1 - 0.5f64) * split_fact + asin_nl
                    let cs = math.cos[f64](ang)
                    let sn = math.sin[f64](ang)
                    c = 0usize
                    while c < n {
                        pr[c] = yopt[c] * cs + cy[c] * sn
                        c += 1usize
                    }
                    let sc = grid_scat(a, pr, method)
                    let ob = sc * sc + grid_pen(oth, thi, p, cs, sn, qn, sn_, zero_tol, cur_lam) * glo
                    if ob > best_obj {
                        best_obj = ob
                        cur_scat = sc
                        nl = sn
                        ncl = cs
                    }
                    dir += 1usize
                }
                c = 0usize
                while c < n {
                    yopt[c] = yopt[c] * ncl + cy[c] * nl
                    c += 1usize
                }
                c = 0usize
                while c < ps_n {
                    afin[c] = afin[c] * ncl
                    c += 1usize
                }
                afin[cur_p] = nl
                j += 1usize
            }
            let nrm = norm2_of(afin[0usize..ps_n])
            c = 0usize
            while c < ps_n {
                afin[c] = afin[c] / nrm
                c += 1usize
            }
            if it == 0usize || obj_best <= best_obj {
                obj_best = best_obj
                c = 0usize
                while c < ps_n {
                    best[c] = afin[c]
                    c += 1usize
                }
                scat_best = cur_scat
            }
            it += 1usize
        }
        sdev[ck] = scat_best
        obj[ck] = obj_best
        let ref0 = ord[0usize]
        c = 0usize
        while c < ps_n {
            best[c] = 0.0f64 - best[c]
            c += 1usize
        }
        best[ref0] = best[ref0] + 1.0f64
        let nb = norm2_of(best[0usize..ps_n])
        c = 0usize
        while c < ps_n * ps_n {
            tpp[c] = 0.0f64
            c += 1usize
        }
        c = 0usize
        while c < ps_n {
            tpp[c * ps_n + c] = 1.0f64
            c += 1usize
        }
        if nb > zero_tol {
            c = 0usize
            while c < ps_n {
                best[c] = best[c] / (nb / sqrt2)
                c += 1usize
            }
            var u = 0usize
            while u < ps_n {
                var v = 0usize
                while v < ps_n {
                    tpp[u * ps_n + v] = tpp[u * ps_n + v] - best[v] * best[u]
                    v += 1usize
                }
                u += 1usize
            }
        }
        c = 0usize
        while c < ps_n {
            var r = 0usize
            while r < ps_n {
                ps[c * ps_n + r] = tpp[ord[c] * ps_n + r]
                r += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < ps_n {
            var r = 0usize
            while r < p {
                old[c * p + r] = load[(ck + c) * p + r]
                r += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < ps_n {
            var r = 0usize
            while r < p {
                var s = 0.0f64
                var t = 0usize
                while t < ps_n {
                    s += old[t * p + r] * ps[c * ps_n + t]
                    t += 1usize
                }
                load[(ck + c) * p + r] = s
                r += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c + 1usize < ps_n {
            var r = 0usize
            while r < n {
                var s = 0.0f64
                var t = 0usize
                while t < ps_n {
                    s += y[t * n + r] * ps[(c + 1usize) * ps_n + t]
                    t += 1usize
                }
                yn[c * n + r] = s
                r += 1usize
            }
            c += 1usize
        }
        let sw = y
        y = yn
        yn = sw
        ck += 1usize
    }
    ret ok
}

// R's PCAgrid post-processing on the first k components: .loadSgnU (the largest entry of each loading positive), then .orderPCs
// (decreasing sdev, ties keep their order) applied to the loadings (p by k), sdev and obj together.
fn pca_grid_finish(p: usize, k: usize, load: []f64, sdev: []f64, obj: []f64) {
    var i = 0usize
    while i < k {
        var im = 0usize
        var c = 1usize
        while c < p {
            if math.abs[f64](load[i * p + c]) > math.abs[f64](load[i * p + im]) { im = c }
            c += 1usize
        }
        if load[i * p + im] < 0.0f64 {
            c = 0usize
            while c < p {
                load[i * p + c] = 0.0f64 - load[i * p + c]
                c += 1usize
            }
        }
        i += 1usize
    }
    var pass = 0usize
    while pass < k {
        i = 0usize
        while i + 1usize < k {
            if sdev[i + 1usize] > sdev[i] {
                let t = sdev[i]
                sdev[i] = sdev[i + 1usize]
                sdev[i + 1usize] = t
                let o = obj[i]
                obj[i] = obj[i + 1usize]
                obj[i + 1usize] = o
                var c = 0usize
                while c < p {
                    let u = load[i * p + c]
                    load[i * p + c] = load[(i + 1usize) * p + c]
                    load[(i + 1usize) * p + c] = u
                    c += 1usize
                }
            }
            i += 1usize
        }
        pass += 1usize
    }
}

// PCAgrid for n < p as R runs it: svd(t(x)) = U D V', the search on V D (n by n), and the loadings mapped back by U. `load` is p by k
// (column-major), `sdev` has n entries, `obj` k; the first k components then go through pca_grid_finish(p, k, ...).
fn pca_grid_hd(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, method: i64, maxiter: usize, splitcircle: usize, zero_tol: f64, lam: []const f64, qn: f64, sn_: f64, load: []f64, sdev: []f64, obj: []f64) -> err {
    let (mt, e1) = mem.alloc[f64](a, n * p)
    let (xr, e2) = mem.alloc[f64](a, n * n)
    let (lr, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var c = 0usize
    while c < p {
        var r = 0usize
        while r < n {
            mt[r * p + c] = x[c * n + r]
            r += 1usize
        }
        c += 1usize
    }
    let (sv, se) = decomp.svd(a, mt, p, n)
    if se != ok { ret se }
    var ordv = sv.k
    if ordv != n { ret mem.Invalid }
    let (od, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret e4 }
    c = 0usize
    while c < n {
        od[c] = c
        c += 1usize
    }
    c = 1usize
    while c < n {
        let o = od[c]
        var d = c
        while d > 0usize && sv.d[od[d - 1usize]] < sv.d[o] {
            od[d] = od[d - 1usize]
            d -= 1usize
        }
        od[d] = o
        c += 1usize
    }
    c = 0usize
    while c < n {
        var r = 0usize
        while r < n {
            xr[c * n + r] = sv.v[od[c] * n + r] * sv.d[od[c]]
            r += 1usize
        }
        c += 1usize
    }
    let e = pca_grid(a, xr, n, n, k, method, maxiter, splitcircle, zero_tol, lam, qn, sn_, lr, sdev, obj)
    if e != ok { ret e }
    c = 0usize
    while c < k {
        var r = 0usize
        while r < p {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += sv.u[od[t] * p + r] * lr[c * n + t]
                t += 1usize
            }
            load[c * p + r] = s
            r += 1usize
        }
        c += 1usize
    }
    ret ok
}
