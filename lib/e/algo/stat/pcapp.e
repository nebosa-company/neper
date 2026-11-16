// R pcaPP: `cor_fk` (Knight's O(n log n) Kendall tau-b, cov.kendall.cpp) and the geometric median `l1median_hocr` (Hossjer and
// Croux) and `l1median_vazh` (Vardi and Zhang) of L1Median_HoCr.cpp and L1Median_VardiZhang.cpp. R's `l1median` itself runs `nlm`;
// the minimum of the sum of Euclidean distances is unique, so these reach it to the tolerance asked.
//
// Not here: PCAproj, PCAgrid and sPCAgrid.

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
