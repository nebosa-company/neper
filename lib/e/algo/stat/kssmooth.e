// R stats smooth.spline(x, y, spar = s) followed by predict(): the unique-x merging at tolerance 1e-6 * IQR(x), the knot choice of .nknots.smspl, the cubic
// B-spline basis (bsplvb, bsplvd), the Gram matrix of second derivatives (sgram, with R's constant 0.3330), X'WX and X'Wy (stxwx), the banded Cholesky
// solve (dpbfa, dpbsl) at lambda = ratio * 16^(6 spar - 2), and bvalue with the linear extrapolation of predict.smooth.spline.fit.
//
// Not here: the search over spar (cv, gcv, df matching), weights, leverages.

use e.algo.stat.classint as ci
use e.math
use e.mem

error Failed

// interv with rightmost_closed = all_inside = FALSE: the 1-based index and mflag
fn interv(xt: []const f64, n: usize, x: f64) -> (usize, i64) {
    if x < xt[0usize] { ret (1usize, 0i64 - 1i64) }
    if x >= xt[n - 1usize] { ret (n, 1i64) }
    var lo = 0usize
    var hi = n
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if xt[mid] <= x {
            lo = mid + 1usize
        } else {
            hi = mid
        }
    }
    ret (lo, 0i64)
}

// bsplvb: st[0] is the saved j, st[1..21] deltal, st[21..41] deltar (index 1-based into them)
fn bsplvb(t: []const f64, jhigh: usize, index: usize, x: f64, left: usize, biatx: []f64, st: []f64) {
    var j = usize(st[0usize])
    var go = true
    if index != 2usize {
        j = 1usize
        biatx[0usize] = 1.0f64
        if j >= jhigh { go = false }
    }
    while go {
        let jp1 = j + 1usize
        st[21usize + j - 1usize] = t[left + j - 1usize] - x
        st[1usize + j - 1usize] = x - t[left + 1usize - j - 1usize]
        var saved = 0.0f64
        var i = 1usize
        while i <= j {
            let term = biatx[i - 1usize] / (st[21usize + i - 1usize] + st[1usize + jp1 - i - 1usize])
            biatx[i - 1usize] = saved + st[21usize + i - 1usize] * term
            saved = st[1usize + jp1 - i - 1usize] * term
            i += 1usize
        }
        biatx[jp1 - 1usize] = saved
        j = jp1
        if j >= jhigh { go = false }
    }
    st[0usize] = f64(j)
}

// bsplvd for order 4: db(r, c) = db[(c - 1) * 4 + r - 1], the values (c = 1) and derivatives of the four nonzero B-splines at x
fn bsplvd(t: []const f64, x: f64, left: usize, nderiv: usize, db: []f64, st: []f64) {
    var a: [16]f64 = zero
    var mhigh = nderiv
    if mhigh > 4usize { mhigh = 4usize }
    if mhigh < 1usize { mhigh = 1usize }
    let kp1 = 5usize
    bsplvb(t, kp1 - mhigh, 1usize, x, left, db[0usize..4usize], st)
    if mhigh == 1usize { ret }
    var ideriv = mhigh
    var m = 2usize
    while m <= mhigh {
        var jp1mid = 1usize
        var j = ideriv
        while j <= 4usize {
            db[(ideriv - 1usize) * 4usize + j - 1usize] = db[jp1mid - 1usize]
            jp1mid += 1usize
            j += 1usize
        }
        ideriv -= 1usize
        bsplvb(t, kp1 - ideriv, 2usize, x, left, db[0usize..4usize], st)
        m += 1usize
    }
    var jlow = 1usize
    var i = 1usize
    while i <= 4usize {
        var j = jlow
        while j <= 4usize {
            a[(i - 1usize) * 4usize + j - 1usize] = 0.0f64
            j += 1usize
        }
        jlow = i
        a[(i - 1usize) * 4usize + i - 1usize] = 1.0f64
        i += 1usize
    }
    m = 2usize
    while m <= mhigh {
        let kp1mm = kp1 - m
        let fkp1mm = f64(kp1mm)
        var il = left
        i = 4usize
        var ld = 1usize
        while ld <= kp1mm {
            let factor = fkp1mm / (t[il + kp1mm - 1usize] - t[il - 1usize])
            var j = 1usize
            while j <= i {
                a[(j - 1usize) * 4usize + i - 1usize] = (a[(j - 1usize) * 4usize + i - 1usize] - a[(j - 1usize) * 4usize + i - 2usize]) * factor
                j += 1usize
            }
            il -= 1usize
            i -= 1usize
            ld += 1usize
        }
        i = 1usize
        while i <= 4usize {
            var sum = 0.0f64
            jlow = i
            if m > jlow { jlow = m }
            var j = jlow
            while j <= 4usize {
                sum = a[(i - 1usize) * 4usize + j - 1usize] * db[(m - 1usize) * 4usize + j - 1usize] + sum
                j += 1usize
            }
            db[(m - 1usize) * 4usize + i - 1usize] = sum
            i += 1usize
        }
        m += 1usize
    }
}

fn gram_term(w: f64, y1: f64, y2: f64, z1: f64, z2: f64) -> f64 {
    ret w * (y1 * z1 + (y2 * z1 + z2 * y1) * 0.5f64 + y2 * z2 * 0.333f64)
}

// sgram: the banded Gram matrix of the B-spline second derivatives (sg0 diagonal, sg1..sg3 the superdiagonals)
fn sgram(sg0: []f64, sg1: []f64, sg2: []f64, sg3: []f64, tb: []const f64, nb: usize) {
    var st: [41]f64 = zero
    var vnikx: [12]f64 = zero
    var yw1: [4]f64 = zero
    var yw2: [4]f64 = zero
    var i = 0usize
    while i < nb {
        sg0[i] = 0.0f64
        sg1[i] = 0.0f64
        sg2[i] = 0.0f64
        sg3[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i <= nb {
        let (ileft, _mf) = interv(tb, nb + 1usize, tb[i - 1usize])
        bsplvd(tb, tb[i - 1usize], ileft, 3usize, vnikx[0usize..12usize], st[0usize..41usize])
        var ii = 0usize
        while ii < 4usize {
            yw1[ii] = vnikx[8usize + ii]
            ii += 1usize
        }
        bsplvd(tb, tb[i], ileft, 3usize, vnikx[0usize..12usize], st[0usize..41usize])
        ii = 0usize
        while ii < 4usize {
            yw2[ii] = vnikx[8usize + ii] - yw1[ii]
            ii += 1usize
        }
        let wpt = tb[i] - tb[i - 1usize]
        if ileft >= 4usize {
            ii = 0usize
            while ii < 4usize {
                let at = ileft - 4usize + ii
                sg0[at] += gram_term(wpt, yw1[ii], yw2[ii], yw1[ii], yw2[ii])
                if ii + 1usize < 4usize { sg1[at] += gram_term(wpt, yw1[ii], yw2[ii], yw1[ii + 1usize], yw2[ii + 1usize]) }
                if ii + 2usize < 4usize { sg2[at] += gram_term(wpt, yw1[ii], yw2[ii], yw1[ii + 2usize], yw2[ii + 2usize]) }
                if ii + 3usize < 4usize { sg3[at] += gram_term(wpt, yw1[ii], yw2[ii], yw1[ii + 3usize], yw2[ii + 3usize]) }
                ii += 1usize
            }
        }
        i += 1usize
    }
}

// stxwx with weights w (squared inside, as in sbart): xwy = X'Wy and the diagonals hs0..hs3 of X'WX; false when a point lies beyond the last knot
fn stxwx(x: []const f64, z: []const f64, w: []const f64, k: usize, xknot: []const f64, n: usize, y: []f64, hs0: []f64, hs1: []f64, hs2: []f64, hs3: []f64) -> bool {
    var st: [41]f64 = zero
    var v: [4]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = 0.0f64
        hs0[i] = 0.0f64
        hs1[i] = 0.0f64
        hs2[i] = 0.0f64
        hs3[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        let (il0, mf) = interv(xknot, n + 1usize, x[i])
        var ileft = il0
        if mf == 1i64 {
            if x[i] <= xknot[ileft - 1usize] + 1.0e-10f64 {
                ileft -= 1usize
            } else {
                ret false
            }
        }
        bsplvd(xknot, x[i], ileft, 1usize, v[0usize..4usize], st[0usize..41usize])
        let w2 = w[i] * w[i]
        let j0 = ileft - 4usize
        y[j0] += w2 * z[i] * v[0usize]
        hs0[j0] += w2 * v[0usize] * v[0usize]
        hs1[j0] += w2 * v[0usize] * v[1usize]
        hs2[j0] += w2 * v[0usize] * v[2usize]
        hs3[j0] += w2 * v[0usize] * v[3usize]
        y[j0 + 1usize] += w2 * z[i] * v[1usize]
        hs0[j0 + 1usize] += w2 * v[1usize] * v[1usize]
        hs1[j0 + 1usize] += w2 * v[1usize] * v[2usize]
        hs2[j0 + 1usize] += w2 * v[1usize] * v[3usize]
        y[j0 + 2usize] += w2 * z[i] * v[2usize]
        hs0[j0 + 2usize] += w2 * v[2usize] * v[2usize]
        hs1[j0 + 2usize] += w2 * v[2usize] * v[3usize]
        y[j0 + 3usize] += w2 * z[i] * v[3usize]
        hs0[j0 + 3usize] += w2 * v[3usize] * v[3usize]
        i += 1usize
    }
    ret true
}

// abd(r, c) with lda = 4 as abd[(c - 1) * 4 + r - 1]
fn dpbfa(abd: []f64, n: usize) -> usize {
    let m = 3usize
    var j = 1usize
    while j <= n {
        var s = 0.0f64
        var ik = m + 1usize
        var jk = 1usize
        if j > m { jk = j - m }
        var mu = 1usize
        if m + 2usize > j { mu = m + 2usize - j }
        var k = mu
        while k <= m {
            var dot = 0.0f64
            var l = 0usize
            while l < k - mu {
                dot += abd[(jk - 1usize) * 4usize + ik - 1usize + l] * abd[(j - 1usize) * 4usize + mu - 1usize + l]
                l += 1usize
            }
            var t = abd[(j - 1usize) * 4usize + k - 1usize] - dot
            t = t / abd[(jk - 1usize) * 4usize + m]
            abd[(j - 1usize) * 4usize + k - 1usize] = t
            s += t * t
            ik -= 1usize
            jk += 1usize
            k += 1usize
        }
        s = abd[(j - 1usize) * 4usize + m] - s
        if s <= 0.0f64 { ret j }
        abd[(j - 1usize) * 4usize + m] = math.sqrt[f64](s)
        j += 1usize
    }
    ret 0usize
}

fn dpbsl(abd: []const f64, n: usize, b: []f64) {
    let m = 3usize
    var k = 1usize
    while k <= n {
        var lm = k - 1usize
        if lm > m { lm = m }
        let la = m + 1usize - lm
        let lb = k - lm
        var t = 0.0f64
        var l = 0usize
        while l < lm {
            t += abd[(k - 1usize) * 4usize + la - 1usize + l] * b[lb - 1usize + l]
            l += 1usize
        }
        b[k - 1usize] = (b[k - 1usize] - t) / abd[(k - 1usize) * 4usize + m]
        k += 1usize
    }
    var kb = 1usize
    while kb <= n {
        k = n + 1usize - kb
        var lm = k - 1usize
        if lm > m { lm = m }
        let la = m + 1usize - lm
        let lb = k - lm
        b[k - 1usize] = b[k - 1usize] / abd[(k - 1usize) * 4usize + m]
        let t = 0.0f64 - b[k - 1usize]
        var l = 0usize
        while l < lm {
            b[lb - 1usize + l] += t * abd[(k - 1usize) * 4usize + la - 1usize + l]
            l += 1usize
        }
        kb += 1usize
    }
}

// bvalue(t, bcoef, n, 4, x, jderiv)
fn bvalue(t: []const f64, bcoef: []const f64, n: usize, x: f64, jderiv: usize) -> f64 {
    let k = 4usize
    var aj: [20]f64 = zero
    var dm: [20]f64 = zero
    var dp: [20]f64 = zero
    if jderiv >= k { ret 0.0f64 }
    var i = n
    if x != t[n] || t[n] != t[n + k - 1usize] {
        let (ii, mf) = interv(t, n + k, x)
        if mf != 0i64 { ret 0.0f64 }
        i = ii
    }
    let km1 = k - 1usize
    var jcmin = 1usize
    let imk = i - k
    var j = 1usize
    while j <= km1 {
        dm[j - 1usize] = x - t[i - j]
        j += 1usize
    }
    var jcmax = k
    j = 1usize
    while j <= km1 {
        dp[j - 1usize] = t[i + j - 1usize] - x
        j += 1usize
    }
    var jc = jcmin
    while jc <= jcmax {
        aj[jc - 1usize] = bcoef[imk + jc - 1usize]
        jc += 1usize
    }
    var jd = 1usize
    while jd <= jderiv {
        let kmj = k - jd
        let fkmj = f64(kmj)
        var ilo = kmj
        var jj = 1usize
        while jj <= kmj {
            aj[jj - 1usize] = ((aj[jj] - aj[jj - 1usize]) / (dm[ilo - 1usize] + dp[jj - 1usize])) * fkmj
            ilo -= 1usize
            jj += 1usize
        }
        jd += 1usize
    }
    if jderiv != km1 {
        j = jderiv + 1usize
        while j <= km1 {
            let kmj = k - j
            var ilo = kmj
            var jj = 1usize
            while jj <= kmj {
                aj[jj - 1usize] = (aj[jj] * dm[ilo - 1usize] + aj[jj - 1usize] * dp[jj - 1usize]) / (dm[ilo - 1usize] + dp[jj - 1usize])
                ilo -= 1usize
                jj += 1usize
            }
            j += 1usize
        }
    }
    ret aj[0usize]
}

// R's round: half to even
fn round_even(v: f64) -> f64 {
    let f = math.floor[f64](v)
    let d = v - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    if (f - 2.0f64 * math.floor[f64](f / 2.0f64)) == 0.0f64 { ret f }
    ret f + 1.0f64
}

// .nknots.smspl
fn nknots_of(n: usize) -> usize {
    if n < 50usize { ret n }
    let nn = f64(n)
    let a1 = math.log2[f64](50.0f64)
    let a2 = math.log2[f64](100.0f64)
    let a3 = math.log2[f64](140.0f64)
    let a4 = math.log2[f64](200.0f64)
    var v = 0.0f64
    if n < 200usize {
        v = math.pow[f64](2.0f64, a1 + (a2 - a1) * (nn - 50.0f64) / 150.0f64)
    } else if n < 800usize {
        v = math.pow[f64](2.0f64, a2 + (a3 - a2) * (nn - 200.0f64) / 600.0f64)
    } else if n < 3200usize {
        v = math.pow[f64](2.0f64, a3 + (a4 - a3) * (nn - 800.0f64) / 2400.0f64)
    } else {
        v = 200.0f64 + math.pow[f64]((nn - 3200.0f64), 0.2f64)
    }
    ret usize(math.floor[f64](v))
}

// stable ordering of x ascending: ord[i] is the index of the i-th smallest
fn order_of(a: *mem.Arena, x: []const f64, ord: []usize) -> err {
    let n = x.len
    let (tmp, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    var width = 1usize
    while width < n {
        var lo = 0usize
        while lo < n {
            var mid = lo + width
            if mid > n { mid = n }
            var hi = lo + 2usize * width
            if hi > n { hi = n }
            var p = lo
            var q = mid
            var o = lo
            while p < mid && q < hi {
                if x[ord[q]] < x[ord[p]] {
                    tmp[o] = ord[q]
                    q += 1usize
                } else {
                    tmp[o] = ord[p]
                    p += 1usize
                }
                o += 1usize
            }
            while p < mid {
                tmp[o] = ord[p]
                p += 1usize
                o += 1usize
            }
            while q < hi {
                tmp[o] = ord[q]
                q += 1usize
                o += 1usize
            }
            lo = lo + 2usize * width
        }
        i = 0usize
        while i < n {
            ord[i] = tmp[i]
            i += 1usize
        }
        width = width * 2usize
    }
    ret ok
}

// predict(smooth.spline(x, y, spar = spar), xp)$y for each point of xp
fn smooth_spline(a: *mem.Arena, x: []const f64, y: []const f64, spar: f64, xp: []const f64, out: []f64) -> err {
    let n = x.len
    let (ord, e0) = mem.alloc[usize](a, n)
    if e0 != ok { ret e0 }
    let oe = order_of(a, x, ord)
    if oe != ok { ret oe }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var corr = 0.0f64
    i = 0usize
    while i < n {
        corr += x[i] - mean
        i += 1usize
    }
    mean = mean + corr / f64(n)
    let (xs, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    i = 0usize
    while i < n {
        xs[i] = x[ord[i]]
        i += 1usize
    }
    let (q, qe) = ci.sorted_copy(a, x)
    if qe != ok { ret qe }
    let tol = 1.0e-6f64 * (ci.quantile7(q, 0.75f64) - ci.quantile7(q, 0.25f64))
    let (ux, e2) = mem.alloc[f64](a, n)
    let (wbar, e3) = mem.alloc[f64](a, n)
    let (ybar, e4) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok { ret e2 }
    var nx = 0usize
    var prev = 0.0f64
    i = 0usize
    while i < n {
        let cls = round_even((xs[i] - mean) / tol)
        if i == 0usize || prev < cls {
            ux[nx] = xs[i]
            wbar[nx] = 0.0f64
            ybar[nx] = 0.0f64
            nx += 1usize
            prev = cls
        }
        wbar[nx - 1usize] += 1.0f64
        ybar[nx - 1usize] += y[ord[i]]
        i += 1usize
    }
    if nx <= 3usize { ret Failed }
    i = 0usize
    while i < nx {
        ybar[i] = ybar[i] / wbar[i]
        i += 1usize
    }
    let r_ux = ux[nx - 1usize] - ux[0usize]
    let (xbar, e5) = mem.alloc[f64](a, nx)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < nx {
        xbar[i] = (ux[i] - ux[0usize]) / r_ux
        i += 1usize
    }
    let nknots = nknots_of(nx)
    let nk = nknots + 2usize
    let (knot, e6) = mem.alloc[f64](a, nknots + 6usize)
    if e6 != ok { ret e6 }
    knot[0usize] = xbar[0usize]
    knot[1usize] = xbar[0usize]
    knot[2usize] = xbar[0usize]
    var by = 0.0f64
    if nknots > 2usize { by = (f64(nx) - 1.0f64) / f64(nknots - 1usize) }
    i = 0usize
    while i < nknots {
        var pos = 1.0f64
        if i == nknots - 1usize {
            pos = f64(nx)
        } else {
            pos = 1.0f64 + f64(i) * by
        }
        knot[3usize + i] = xbar[usize(math.floor[f64](pos)) - 1usize]
        i += 1usize
    }
    knot[3usize + nknots] = xbar[nx - 1usize]
    knot[4usize + nknots] = xbar[nx - 1usize]
    knot[5usize + nknots] = xbar[nx - 1usize]
    let (ws, e7) = mem.alloc[f64](a, nx)
    let (xwy, e8) = mem.alloc[f64](a, nk)
    let (hs, e9) = mem.alloc[f64](a, 4usize * nk)
    let (sg, e10) = mem.alloc[f64](a, 4usize * nk)
    let (abd, e11) = mem.alloc[f64](a, 4usize * nk)
    let (coef, e12) = mem.alloc[f64](a, nk)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret e7 }
    i = 0usize
    while i < nx {
        ws[i] = math.sqrt[f64](wbar[i])
        i += 1usize
    }
    sgram(sg[0usize..nk], sg[nk..2usize * nk], sg[2usize * nk..3usize * nk], sg[3usize * nk..4usize * nk], knot, nk)
    if !stxwx(xbar, ybar, ws, nx, knot, nk, xwy, hs[0usize..nk], hs[nk..2usize * nk], hs[2usize * nk..3usize * nk], hs[3usize * nk..4usize * nk]) { ret Failed }
    var t1 = 0.0f64
    var t2 = 0.0f64
    i = 2usize
    while i < nk - 3usize {
        t1 += hs[i]
        t2 += sg[i]
        i += 1usize
    }
    let ratio = t1 / t2
    let lambda = ratio * math.pow[f64](16.0f64, spar * 6.0f64 - 2.0f64)
    i = 0usize
    while i < nk {
        coef[i] = xwy[i]
        abd[i * 4usize + 3usize] = hs[i] + lambda * sg[i]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < nk {
        abd[(i + 1usize) * 4usize + 2usize] = hs[nk + i] + lambda * sg[nk + i]
        i += 1usize
    }
    i = 0usize
    while i + 2usize < nk {
        abd[(i + 2usize) * 4usize + 1usize] = hs[2usize * nk + i] + lambda * sg[2usize * nk + i]
        i += 1usize
    }
    i = 0usize
    while i + 3usize < nk {
        abd[(i + 3usize) * 4usize] = hs[3usize * nk + i] + lambda * sg[3usize * nk + i]
        i += 1usize
    }
    if dpbfa(abd, nk) != 0usize { ret Failed }
    dpbsl(abd, nk, coef)
    let e0v = bvalue(knot, coef, nk, 0.0f64, 0usize)
    let e1v = bvalue(knot, coef, nk, 1.0f64, 0usize)
    let s0 = bvalue(knot, coef, nk, 0.0f64, 1usize)
    let s1 = bvalue(knot, coef, nk, 1.0f64, 1usize)
    i = 0usize
    while i < xp.len {
        let u = (xp[i] - ux[0usize]) / r_ux
        if u < 0.0f64 {
            out[i] = e0v + s0 * u
        } else if u > 1.0f64 {
            out[i] = e1v + s1 * (u - 1.0f64)
        } else {
            out[i] = bvalue(knot, coef, nk, u, 0usize)
        }
        i += 1usize
    }
    ret ok
}
