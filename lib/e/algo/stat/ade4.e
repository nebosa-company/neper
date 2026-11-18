// The duality diagrams of the R package ade4: as.dudi (the generalised principal-axes analysis of a table with row and column weights) and the
// analyses built on it, dudi.pca and dudi.coa. The eigenvectors are LAPACK's (e.algo.linalg.lapack_syevr), so their signs are the ones R's eigen returns.

use e.algo.linalg.lapack_gesdd as gs
use e.algo.linalg.lapack_syevr as sy
use e.math
use e.mem

error Malformed

// c1 and co are p by nf, li and l1 are n by nf (row-major); eig holds the rank positive eigenvalues
type Dudi = struct { rank: usize, nf: usize, eig: []f64, c1: []f64, li: []f64, co: []f64, l1: []f64 }

// as.dudi on the n by p row-major table tab, row weights lw, column weights cw, nf axes (clamped to the rank) and the rank tolerance tol
fn as_dudi(a: *mem.Arena, tab: []const f64, n: usize, p: usize, lw: []const f64, cw: []const f64, nf0: usize, tol: f64) -> (Dudi, err) {
    var out: Dudi = zero
    var transpose = false
    var m = p
    if n < p {
        transpose = true
        m = n
    }
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (cross, e2) = mem.alloc[f64](a, m * m)
    let (w, e3) = mem.alloc[f64](a, m)
    let (z, e4) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, Malformed) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            xs[i * p + j] = tab[i * p + j] * math.sqrt[f64](lw[i]) * math.sqrt[f64](cw[j])
            j += 1usize
        }
        i += 1usize
    }
    var r = 0usize
    while r < m {
        var c = 0usize
        while c < m {
            var s = 0.0f64
            var k = 0usize
            if transpose {
                while k < p {
                    s += xs[r * p + k] * xs[c * p + k]
                    k += 1usize
                }
            } else {
                while k < n {
                    s += xs[k * p + r] * xs[k * p + c]
                    k += 1usize
                }
            }
            cross[r * m + c] = s
            c += 1usize
        }
        r += 1usize
    }
    let e5 = sy.dsyevr_all(a, cross, m, w, z)
    if e5 != ok { ret (out, e5) }
    let (eig, e6) = mem.alloc[f64](a, m)
    if e6 != ok { ret (out, e6) }
    var k = 0usize
    while k < m {
        eig[k] = w[m - 1usize - k]
        k += 1usize
    }
    var rank = 0usize
    k = 0usize
    while k < m {
        if eig[k] / eig[0usize] > tol { rank += 1usize }
        k += 1usize
    }
    var nf = nf0
    if nf == 0usize { nf = 2usize }
    if nf > rank { nf = rank }
    out.rank = rank
    out.nf = nf
    out.eig = eig[0usize..rank]
    let (c1, e7) = mem.alloc[f64](a, p * nf)
    let (li, e8) = mem.alloc[f64](a, n * nf)
    let (co, e9) = mem.alloc[f64](a, p * nf)
    let (l1, e10) = mem.alloc[f64](a, n * nf)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (out, Malformed) }
    k = 0usize
    while k < nf {
        let dval = math.sqrt[f64](eig[k])
        let col = m - 1usize - k
        if !transpose {
            var j = 0usize
            while j < p {
                var cwj = cw[j]
                if cwj == 0.0f64 { cwj = 1.0f64 }
                c1[j * nf + k] = z[col * m + j] * (1.0f64 / math.sqrt[f64](cwj))
                co[j * nf + k] = c1[j * nf + k] * dval
                j += 1usize
            }
            i = 0usize
            while i < n {
                var s = 0.0f64
                var j2 = 0usize
                while j2 < p {
                    s += tab[i * p + j2] * cw[j2] * c1[j2 * nf + k]
                    j2 += 1usize
                }
                li[i * nf + k] = s
                l1[i * nf + k] = s / dval
                i += 1usize
            }
        } else {
            i = 0usize
            while i < n {
                var lwi = lw[i]
                if lwi == 0.0f64 { lwi = 1.0f64 }
                l1[i * nf + k] = z[col * m + i] * (1.0f64 / math.sqrt[f64](lwi))
                li[i * nf + k] = l1[i * nf + k] * dval
                i += 1usize
            }
            var j = 0usize
            while j < p {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += tab[i * p + j] * lw[i] * l1[i * nf + k]
                    i += 1usize
                }
                co[j * nf + k] = s
                c1[j * nf + k] = s / dval
                j += 1usize
            }
        }
        k += 1usize
    }
    out.c1 = c1
    out.li = li
    out.co = co
    out.l1 = l1
    ret (out, ok)
}

// Neumaier step: R's sum() accumulates in long double, which a compensated sum reproduces (the sum rounded once)
fn nstep(s: f64, c: f64, v: f64) -> (f64, f64) {
    let t = s + v
    var cc = c
    if math.abs[f64](s) >= math.abs[f64](v) { cc += (s - t) + v } else { cc += (v - t) + s }
    ret (t, cc)
}

// the table, row weights and column weights dudi.pca hands to as.dudi (centre and scale: the population standard deviation, a norm below 1e-8 is taken as 1)
fn pca_prep(a: *mem.Arena, x: []const f64, n: usize, p: usize, center: bool, scale: bool, t: []f64, lw: []f64, cw: []f64) {
    var i = 0usize
    while i < n {
        lw[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    pca_prep_w(a, x, n, p, center, scale, t, lw, cw)
}

// the same with the row weights lw given (they should sum to one)
fn pca_prep_w(a: *mem.Arena, x: []const f64, n: usize, p: usize, center: bool, scale: bool, t: []f64, lw: []const f64, cw: []f64) {
    var i = 0usize
    var j = 0usize
    while j < p {
        cw[j] = 1.0f64
        var mu = 0.0f64
        var sw = 0.0f64
        var swc = 0.0f64
        i = 0usize
        while i < n {
            let (a1, a2) = nstep(sw, swc, lw[i])
            sw = a1
            swc = a2
            i += 1usize
        }
        sw = sw + swc
        if center {
            var m1 = 0.0f64
            var m2 = 0.0f64
            i = 0usize
            while i < n {
                let (b1, b2) = nstep(m1, m2, x[i * p + j] * lw[i])
                m1 = b1
                m2 = b2
                i += 1usize
            }
            mu = (m1 + m2) / sw
        }
        var s1 = 0.0f64
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            t[i * p + j] = x[i * p + j] - mu
            let (c1v, c2v) = nstep(s1, s2, t[i * p + j] * t[i * p + j] * lw[i])
            s1 = c1v
            s2 = c2v
            i += 1usize
        }
        if scale {
            var nm = math.sqrt[f64]((s1 + s2) / sw)
            if nm < 0.00000001f64 { nm = 1.0f64 }
            i = 0usize
            while i < n {
                t[i * p + j] = t[i * p + j] / nm
                i += 1usize
            }
        }
        j += 1usize
    }
}

// dudi.pca: row weights 1 / n, column weights 1
fn dudi_pca(a: *mem.Arena, x: []const f64, n: usize, p: usize, center: bool, scale: bool, nf: usize) -> (Dudi, err) {
    let (t, e1) = mem.alloc[f64](a, n * p)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    pca_prep(a, x, n, p, center, scale, t, lw, cw)
    let (d, ed) = as_dudi(a, t, n, p, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
}

// the class means of the table (nl by p), with the class weights (the sum of lw over the class) in cla; fac holds 0-based class codes
fn class_means(a: *mem.Arena, tab: []const f64, n: usize, p: usize, lw: []const f64, fac: []const f64, nl: usize, cla: []f64, mean: []f64) {
    var l = 0usize
    while l < nl {
        var c1 = 0.0f64
        var c2 = 0.0f64
        let (cs, e0) = mem.alloc[f64](a, p * 2usize)
        if e0 != ok { ret }
        var j = 0usize
        while j < p * 2usize {
            cs[j] = 0.0f64
            j += 1usize
        }
        var i = 0usize
        while i < n {
            if usize(fac[i]) == l {
                let (u1, u2) = nstep(c1, c2, lw[i])
                c1 = u1
                c2 = u2
                j = 0usize
                while j < p {
                    let (v1, v2) = nstep(cs[j * 2usize], cs[j * 2usize + 1usize], tab[i * p + j] * lw[i])
                    cs[j * 2usize] = v1
                    cs[j * 2usize + 1usize] = v2
                    j += 1usize
                }
            }
            i += 1usize
        }
        cla[l] = c1 + c2
        j = 0usize
        while j < p {
            mean[l * p + j] = (cs[j * 2usize] + cs[j * 2usize + 1usize]) / cla[l]
            j += 1usize
        }
        l += 1usize
    }
}

fn eig_sum(d: *const Dudi) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d.rank {
        s += d.eig[k]
        k += 1usize
    }
    ret s
}

// bca.dudi: the between-class analysis of the dudi (tab, lw, cw) with the class codes fac (0-based, nl classes): the analysis of the class means weighted by
// the class weights; ratio is the between inertia over the total
fn bca(a: *mem.Arena, tab: []const f64, n: usize, p: usize, lw: []const f64, cw: []const f64, fac: []const f64, nl: usize, nf: usize) -> (Dudi, f64, err) {
    let (cla, e1) = mem.alloc[f64](a, nl)
    let (mean, e2) = mem.alloc[f64](a, nl * p)
    if e1 != ok || e2 != ok { ret (zero, 0.0f64, Malformed) }
    class_means(a, tab, n, p, lw, fac, nl, cla, mean)
    let (whole, e3) = as_dudi(a, tab, n, p, lw, cw, nf, 0.0000001f64)
    if e3 != ok { ret (zero, 0.0f64, e3) }
    let (d, e4) = as_dudi(a, mean, nl, p, cla, cw, nf, 0.0000001f64)
    if e4 != ok { ret (zero, 0.0f64, e4) }
    ret (d, eig_sum(&d) / eig_sum(&whole), ok)
}

// wca.dudi: the within-class analysis, the table minus its class means
fn wca(a: *mem.Arena, tab: []const f64, n: usize, p: usize, lw: []const f64, cw: []const f64, fac: []const f64, nl: usize, nf: usize) -> (Dudi, f64, err) {
    let (cla, e1) = mem.alloc[f64](a, nl)
    let (mean, e2) = mem.alloc[f64](a, nl * p)
    let (wit, e5) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e5 != ok { ret (zero, 0.0f64, Malformed) }
    class_means(a, tab, n, p, lw, fac, nl, cla, mean)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            wit[i * p + j] = tab[i * p + j] - mean[usize(fac[i]) * p + j]
            j += 1usize
        }
        i += 1usize
    }
    let (whole, e3) = as_dudi(a, tab, n, p, lw, cw, nf, 0.0000001f64)
    if e3 != ok { ret (zero, 0.0f64, e3) }
    let (d, e4) = as_dudi(a, wit, n, p, lw, cw, nf, 0.0000001f64)
    if e4 != ok { ret (zero, 0.0f64, e4) }
    ret (d, eig_sum(&d) / eig_sum(&whole), ok)
}

// dudi.coa: the correspondence analysis of a table of non-negative counts
fn dudi_coa(a: *mem.Arena, x: []const f64, n: usize, p: usize, nf: usize) -> (Dudi, err) {
    let (t, e1) = mem.alloc[f64](a, n * p)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    let ep = coa_prep(a, x, n, p, t, lw, cw)
    if ep != ok { ret (zero, ep) }
    let (d, ed) = as_dudi(a, t, n, p, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
}

// the table, row weights and column weights dudi.coa hands to as.dudi
fn coa_prep(a: *mem.Arena, x: []const f64, n: usize, p: usize, t: []f64, lw: []f64, cw: []f64) -> err {
    var tot = 0.0f64
    var i = 0usize
    while i < n * p {
        if x[i] < 0.0f64 { ret Malformed }
        tot += x[i]
        i += 1usize
    }
    if tot == 0.0f64 { ret Malformed }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += x[i * p + j] / tot
            j += 1usize
        }
        lw[i] = s
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += x[i * p + j] / tot
            i += 1usize
        }
        cw[j] = s
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < p {
            t[i * p + j] = 0.0f64
            if lw[i] > 0.0f64 && cw[j] > 0.0f64 { t[i * p + j] = (x[i * p + j] / tot / lw[i]) / cw[j] - 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// dudi.fca: the fuzzy correspondence analysis of a table of fuzzy coded variables (nb blocks) with row weights rw: the columns divided by their weighted sums
// minus one, column weights those sums over nb
fn dudi_fca(a: *mem.Arena, x: []const f64, n: usize, p: usize, rw: []const f64, nb: usize, nf: usize) -> (Dudi, err) {
    let (t, e1) = mem.alloc[f64](a, n * p)
    let (cw, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var j = 0usize
    while j < p {
        var c1 = 0.0f64
        var c2 = 0.0f64
        var i = 0usize
        while i < n {
            let (u1, u2) = nstep(c1, c2, x[i * p + j] * rw[i])
            c1 = u1
            c2 = u2
            i += 1usize
        }
        cw[j] = c1 + c2
        i = 0usize
        while i < n {
            t[i * p + j] = x[i * p + j] / cw[j] - 1.0f64
            i += 1usize
        }
        cw[j] = cw[j] / f64(nb)
        j += 1usize
    }
    let (d, ed) = as_dudi(a, t, n, p, rw, cw, nf, 0.0000001f64)
    ret (d, ed)
}

type Rlq = struct { d: Dudi, lq: []f64, lr: []f64 }

// rlq: the RLQ analysis of the tables R (n by pr: tab, row weights lw, column weights cwr), L (a correspondence analysis of n by nl: tab, lw, cw) and Q
// (nl by pq: tab, column weights cwq); the analysis of t(Rtab) diag(L.lw) Ltab diag(L.cw) Qtab. lq and lr are the row scores of Q (nl by nf) and R (n by nf).
fn rlq(a: *mem.Arena, rt: []const f64, cwr: []const f64, n: usize, pr: usize, lt: []const f64, lw: []const f64, lcw: []const f64, nl: usize, qt: []const f64, cwq: []const f64, pq: usize, nf0: usize) -> (Rlq, err) {
    var out: Rlq = zero
    let (tc, e1) = mem.alloc[f64](a, pr * pq)
    let (m1, e2) = mem.alloc[f64](a, pr * nl)
    if e1 != ok || e2 != ok { ret (out, Malformed) }
    // m1 = t(R) diag(lw) L  (pr by nl)
    var r = 0usize
    while r < pr {
        var c = 0usize
        while c < nl {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += rt[i * pr + r] * lw[i] * lt[i * nl + c]
                i += 1usize
            }
            m1[r * nl + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < pr {
        var c = 0usize
        while c < pq {
            var s = 0.0f64
            var l = 0usize
            while l < nl {
                s += m1[r * nl + l] * lcw[l] * qt[l * pq + c]
                l += 1usize
            }
            tc[r * pq + c] = s
            c += 1usize
        }
        r += 1usize
    }
    let (dr, e3) = as_dudi(a, rt, n, pr, lw, cwr, 2usize, 0.0000001f64)
    let (dq, e4) = as_dudi(a, qt, nl, pq, lcw, cwq, 2usize, 0.0000001f64)
    if e3 != ok || e4 != ok { ret (out, Malformed) }
    var nf = nf0
    if nf > dr.nf { nf = dr.nf }
    if nf > dq.nf { nf = dq.nf }
    let (d, e5) = as_dudi(a, tc, pr, pq, cwr, cwq, nf, 0.0000001f64)
    if e5 != ok { ret (out, e5) }
    out.d = d
    let (lq, e6) = mem.alloc[f64](a, nl * d.nf)
    let (lr, e7) = mem.alloc[f64](a, n * d.nf)
    if e6 != ok || e7 != ok { ret (out, Malformed) }
    var k = 0usize
    while k < d.nf {
        var i = 0usize
        while i < nl {
            var s = 0.0f64
            var j = 0usize
            while j < pq {
                s += qt[i * pq + j] * (d.c1[j * d.nf + k] * cwq[j])
                j += 1usize
            }
            lq[i * d.nf + k] = s
            i += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < pr {
                s += rt[i * pr + j] * (d.l1[j * d.nf + k] * cwr[j])
                j += 1usize
            }
            lr[i * d.nf + k] = s
            i += 1usize
        }
        k += 1usize
    }
    out.lq = lq
    out.lr = lr
    ret (out, ok)
}

// dudi.acm: the multiple correspondence analysis of nv factors (codes: n by nv row-major, 0-based level codes, every level of every factor present).
// The table is the disjunctive one, divided by the column weights minus 1; the column weights are the category frequencies over nv.
fn dudi_acm(a: *mem.Arena, codes: []const f64, n: usize, nv: usize, nf: usize) -> (Dudi, err) {
    var total = 0usize
    let (off, e0) = mem.alloc[usize](a, nv + 1usize)
    if e0 != ok { ret (zero, Malformed) }
    var v = 0usize
    while v < nv {
        var mx = 0usize
        var i = 0usize
        while i < n {
            let c = usize(codes[i * nv + v])
            if c > mx { mx = c }
            i += 1usize
        }
        off[v] = total
        total += mx + 1usize
        v += 1usize
    }
    let (t, e1) = mem.alloc[f64](a, n * total)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n * total {
        t[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        lw[i] = 1.0f64 / f64(n)
        v = 0usize
        while v < nv {
            t[i * total + off[v] + usize(codes[i * nv + v])] = 1.0f64
            v += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < total {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += t[i * total + j] * lw[i]
            i += 1usize
        }
        if s == 0.0f64 { ret (zero, Malformed) }
        cw[j] = s
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < total {
            t[i * total + j] = t[i * total + j] / cw[j] - 1.0f64
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < total {
        cw[j] = cw[j] / f64(nv)
        j += 1usize
    }
    let (d, ed) = as_dudi(a, t, n, total, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
}

type Coin = struct { d: Dudi, lx: []f64, ly: []f64, rv: f64 }

// coinertia (the branch with at least one table having no more columns than rows): the analysis of t(Ytab) diag(lw) Xtab with column weights cwx
// and row weights cwy; lx and ly are the row scores of the two tables; rv is the RV coefficient. The tables share the n row weights lw.
fn coinertia(a: *mem.Arena, xt: []const f64, yt: []const f64, n: usize, px: usize, py: usize, lw: []const f64, cwx: []const f64, cwy: []const f64, nf0: usize) -> (Coin, err) {
    var out: Coin = zero
    if n < px && n < py { ret (out, Malformed) }
    let (dx, e1) = as_dudi(a, xt, n, px, lw, cwx, 2usize, 0.0000001f64)
    let (dy, e2) = as_dudi(a, yt, n, py, lw, cwy, 2usize, 0.0000001f64)
    if e1 != ok || e2 != ok { ret (out, Malformed) }
    let (tc, e3) = mem.alloc[f64](a, py * px)
    if e3 != ok { ret (out, Malformed) }
    var r = 0usize
    while r < py {
        var c = 0usize
        while c < px {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += yt[i * py + r] * (xt[i * px + c] * lw[i])
                i += 1usize
            }
            tc[r * px + c] = s
            c += 1usize
        }
        r += 1usize
    }
    var nf = nf0
    if nf > dx.rank { nf = dx.rank }
    if nf > dy.rank { nf = dy.rank }
    let (d, e4) = as_dudi(a, tc, py, px, cwy, cwx, nf, 0.0000001f64)
    if e4 != ok { ret (out, e4) }
    out.d = d
    let (lx, e5) = mem.alloc[f64](a, n * d.nf)
    let (ly, e6) = mem.alloc[f64](a, n * d.nf)
    if e5 != ok || e6 != ok { ret (out, Malformed) }
    var k = 0usize
    while k < d.nf {
        var i = 0usize
        while i < n {
            var sx = 0.0f64
            var j = 0usize
            while j < px {
                sx += xt[i * px + j] * (d.c1[j * d.nf + k] * cwx[j])
                j += 1usize
            }
            var sv = 0.0f64
            j = 0usize
            while j < py {
                sv += yt[i * py + j] * (d.l1[j * d.nf + k] * cwy[j])
                j += 1usize
            }
            lx[i * d.nf + k] = sx
            ly[i * d.nf + k] = sv
            i += 1usize
        }
        k += 1usize
    }
    out.lx = lx
    out.ly = ly
    var sxx = 0.0f64
    var q = 0usize
    while q < dx.rank {
        sxx += dx.eig[q] * dx.eig[q]
        q += 1usize
    }
    var syy = 0.0f64
    q = 0usize
    while q < dy.rank {
        syy += dy.eig[q] * dy.eig[q]
        q += 1usize
    }
    out.rv = eig_sum(&d) / math.sqrt[f64](sxx) / math.sqrt[f64](syy)
    ret (out, ok)
}

type Procuste = struct { rank: usize, nf: usize, d: []f64, lx: []f64, ly: []f64, sx: []f64, sy: []f64 }

// the n by p table centred (and, when scale, divided by the square root of the sum of its squares), compensated sums as R's sum()
fn proc_centre(x: []const f64, n: usize, p: usize, scale: bool, out: []f64) {
    var j = 0usize
    while j < p {
        var m1 = 0.0f64
        var m2 = 0.0f64
        var i = 0usize
        while i < n {
            let (u1, u2) = nstep(m1, m2, x[i * p + j])
            m1 = u1
            m2 = u2
            i += 1usize
        }
        let mu = (m1 + m2) / f64(n)
        i = 0usize
        while i < n {
            out[i * p + j] = x[i * p + j] - mu
            i += 1usize
        }
        j += 1usize
    }
    if scale {
        var t1 = 0.0f64
        var t2 = 0.0f64
        j = 0usize
        while j < p {
            var c1 = 0.0f64
            var c2 = 0.0f64
            var i = 0usize
            while i < n {
                let (u1, u2) = nstep(c1, c2, out[i * p + j] * out[i * p + j])
                c1 = u1
                c2 = u2
                i += 1usize
            }
            let (w1, w2) = nstep(t1, t2, c1 + c2)
            t1 = w1
            t2 = w2
            j += 1usize
        }
        let nm = math.sqrt[f64](t1 + t2)
        var i = 0usize
        while i < n * p {
            out[i] = out[i] / nm
            i += 1usize
        }
    }
}

// procuste: the Procrustes analysis of two tables with the same rows: the singular value decomposition of t(X) Y; lx (px by nf) and ly (py by nf) are the
// loadings, sx and sy (n by nf) the scores
fn procuste(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, px: usize, py: usize, scale: bool, nf0: usize, tol: f64) -> (Procuste, err) {
    var out: Procuste = zero
    let (xc, e1) = mem.alloc[f64](a, n * px)
    let (yc, e2) = mem.alloc[f64](a, n * py)
    if e1 != ok || e2 != ok { ret (out, Malformed) }
    proc_centre(x, n, px, scale, xc)
    proc_centre(y, n, py, scale, yc)
    var k = px
    if py < px { k = py }
    let (ps, e3) = mem.alloc[f64](a, px * py)
    let (sv, e4) = mem.alloc[f64](a, k)
    let (uu, e5) = mem.alloc[f64](a, px * k)
    let (vt, e6) = mem.alloc[f64](a, k * py)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, Malformed) }
    var r = 0usize
    while r < px {
        var c = 0usize
        while c < py {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += xc[i * px + r] * yc[i * py + c]
                i += 1usize
            }
            ps[c * px + r] = s
            c += 1usize
        }
        r += 1usize
    }
    let e7 = gs.svd_all(a, ps, px, py, sv, uu, vt)
    if e7 != ok { ret (out, e7) }
    var rank = 0usize
    var q = 0usize
    while q < k {
        if sv[q] / sv[0usize] > tol { rank += 1usize }
        q += 1usize
    }
    var nf = nf0
    if nf > rank { nf = rank }
    out.rank = rank
    out.nf = nf
    out.d = sv
    let (lx, e8) = mem.alloc[f64](a, px * nf)
    let (ly, e9) = mem.alloc[f64](a, py * nf)
    let (sx, e10) = mem.alloc[f64](a, n * nf)
    let (sy2, e11) = mem.alloc[f64](a, n * nf)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (out, Malformed) }
    q = 0usize
    while q < nf {
        r = 0usize
        while r < px {
            lx[r * nf + q] = uu[q * px + r]
            r += 1usize
        }
        r = 0usize
        while r < py {
            ly[r * nf + q] = vt[r * k + q]
            r += 1usize
        }
        q += 1usize
    }
    var i = 0usize
    while i < n {
        q = 0usize
        while q < nf {
            var s1 = 0.0f64
            var j = 0usize
            while j < px {
                s1 += xc[i * px + j] * lx[j * nf + q]
                j += 1usize
            }
            var s2 = 0.0f64
            j = 0usize
            while j < py {
                s2 += yc[i * py + j] * ly[j * nf + q]
                j += 1usize
            }
            sx[i * nf + q] = s1
            sy2[i * nf + q] = s2
            q += 1usize
        }
        i += 1usize
    }
    out.lx = lx
    out.ly = ly
    out.sx = sx
    out.sy = sy2
    ret (out, ok)
}

// dudi.mix on quantitative (kind 0) and unordered factor (kind 1, 0-based codes, every level present) variables: the quantitative ones standardised
// with the population standard deviation, the factors as dudi.acm's disjunctive columns divided by their weights minus one; row weights 1 / n and column
// weights 1 for a quantitative variable and the level frequency for a factor level.
fn dudi_mix(a: *mem.Arena, x: []const f64, kinds: []const f64, n: usize, nv: usize, nf: usize) -> (Dudi, err) {
    var total = 0usize
    var v = 0usize
    while v < nv {
        if kinds[v] == 0.0f64 {
            total += 1usize
        } else {
            var mx = 0usize
            var i = 0usize
            while i < n {
                if usize(x[i * nv + v]) > mx { mx = usize(x[i * nv + v]) }
                i += 1usize
            }
            total += mx + 1usize
        }
        v += 1usize
    }
    let (t, e1) = mem.alloc[f64](a, n * total)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        lw[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    var col = 0usize
    v = 0usize
    while v < nv {
        if kinds[v] == 0.0f64 {
            var m1 = 0.0f64
            var m2 = 0.0f64
            i = 0usize
            while i < n {
                let (u1, u2) = nstep(m1, m2, x[i * nv + v])
                m1 = u1
                m2 = u2
                i += 1usize
            }
            let moy = (m1 + m2) / f64(n)
            var s1 = 0.0f64
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                let d = x[i * nv + v] - moy
                t[i * total + col] = d
                let (w1, w2) = nstep(s1, s2, d * d)
                s1 = w1
                s2 = w2
                i += 1usize
            }
            let et = math.sqrt[f64]((s1 + s2) / f64(n))
            i = 0usize
            while i < n {
                t[i * total + col] = t[i * total + col] / et
                i += 1usize
            }
            cw[col] = 1.0f64
            col += 1usize
        } else {
            var nl = 0usize
            i = 0usize
            while i < n {
                if usize(x[i * nv + v]) + 1usize > nl { nl = usize(x[i * nv + v]) + 1usize }
                i += 1usize
            }
            var l = 0usize
            while l < nl {
                var c1 = 0.0f64
                var c2 = 0.0f64
                i = 0usize
                while i < n {
                    var ind = 0.0f64
                    if usize(x[i * nv + v]) == l { ind = 1.0f64 }
                    let (u1, u2) = nstep(c1, c2, ind * lw[i])
                    c1 = u1
                    c2 = u2
                    i += 1usize
                }
                let cl = c1 + c2
                if cl == 0.0f64 { ret (zero, Malformed) }
                i = 0usize
                while i < n {
                    var ind = 0.0f64
                    if usize(x[i * nv + v]) == l { ind = 1.0f64 }
                    t[i * total + col] = ind / cl - 1.0f64
                    i += 1usize
                }
                cw[col] = cl
                col += 1usize
                l += 1usize
            }
        }
        v += 1usize
    }
    let (d, ed) = as_dudi(a, t, n, total, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
}
