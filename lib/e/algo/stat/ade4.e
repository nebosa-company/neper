// The duality diagrams of the R package ade4: as.dudi (the generalised principal-axes analysis of a table with row and column weights) and the
// analyses built on it, dudi.pca and dudi.coa. The eigenvectors are LAPACK's (e.algo.linalg.lapack_syevr), so their signs are the ones R's eigen returns.

use e.algo.linalg.lapack_gesdd as gs
use e.algo.linalg.lapack_syevr as sy
use e.algo.linalg.lapack_base as lb
use e.algo.stat.armld as arm
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
    var t1 = 0.0f64
    var t2 = 0.0f64
    var i = 0usize
    while i < n * p {
        if x[i] < 0.0f64 { ret Malformed }
        let (q1, q2) = nstep(t1, t2, x[i])
        t1 = q1
        t2 = q2
        i += 1usize
    }
    let tot = t1 + t2
    if tot == 0.0f64 { ret Malformed }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var sc = 0.0f64
        var j = 0usize
        while j < p {
            let (q1, q2) = nstep(s, sc, x[i * p + j] / tot)
            s = q1
            sc = q2
            j += 1usize
        }
        lw[i] = s + sc
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var sc = 0.0f64
        i = 0usize
        while i < n {
            let (q1, q2) = nstep(s, sc, x[i * p + j] / tot)
            s = q1
            sc = q2
            i += 1usize
        }
        cw[j] = s + sc
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

// The general real eigenproblem R's eigen() solves with LAPACK 3.12.1 dgeev (jobvl N, jobvr V) for a nonsymmetric matrix: dgebal, dgehd2, dorghr, dlahqr
// (dhseqr below its 75 by 75 crossover), dtrevc3 (right vectors, back-transformed) and dgebak, so the eigenvector signs are R's. Complex eigenpairs only
// occur as rounding noise around multiple zero eigenvalues of a product of two positive semidefinite matrices; their columns are returned as zeros.

fn gx(i: i64, j: i64, ld: i64) -> usize { ret usize((i - 1i64) + (j - 1i64) * ld) }

fn gabs(x: f64) -> f64 { ret math.abs[f64](x) }

// dgebal job B on the n by n column-major h; scale gets the permutation indices and scale factors; returns ilo and ihi
fn g_balance(n: i64, h: []f64, scale: []f64) -> (i64, i64) {
    var k = 1i64
    var l = n
    var noconv = true
    while noconv {
        noconv = false
        let top = l
        var i = top
        while i >= 1i64 {
            var canswap = true
            var j = 1i64
            while j <= l {
                if i != j && h[gx(i, j, n)] != 0.0f64 {
                    canswap = false
                    break
                }
                j = j + 1i64
            }
            if canswap {
                scale[usize(l - 1i64)] = f64(i)
                if i != l {
                    lb.dswap(l, h[gx(1i64, i, n)..], 1i64, h[gx(1i64, l, n)..], 1i64)
                    lb.dswap(n - k + 1i64, h[gx(i, k, n)..], n, h[gx(l, k, n)..], n)
                }
                noconv = true
                if l == 1i64 { ret (1i64, 1i64) }
                l = l - 1i64
            }
            i = i - 1i64
        }
    }
    noconv = true
    while noconv {
        noconv = false
        let bot = l
        var j = k
        while j <= bot {
            var canswap = true
            var i = k
            while i <= l {
                if i != j && h[gx(i, j, n)] != 0.0f64 {
                    canswap = false
                    break
                }
                i = i + 1i64
            }
            if canswap {
                scale[usize(k - 1i64)] = f64(j)
                if j != k {
                    lb.dswap(l, h[gx(1i64, j, n)..], 1i64, h[gx(1i64, k, n)..], 1i64)
                    lb.dswap(n - k + 1i64, h[gx(j, k, n)..], n, h[gx(k, k, n)..], n)
                }
                noconv = true
                k = k + 1i64
            }
            j = j + 1i64
        }
    }
    var q = k
    while q <= l {
        scale[usize(q - 1i64)] = 1.0f64
        q = q + 1i64
    }
    let sfmin1 = 2.2250738585072014e-308f64 / 2.220446049250313e-16f64
    let sfmax1 = 1.0f64 / sfmin1
    let sfmin2 = sfmin1 * 2.0f64
    let sfmax2 = 1.0f64 / sfmin2
    noconv = true
    while noconv {
        noconv = false
        var i = k
        while i <= l {
            var c = lb.dnrm2(l - k + 1i64, h[gx(k, i, n)..], 1i64)
            var r = lb.dnrm2(l - k + 1i64, h[gx(i, k, n)..], n)
            let ica = lb.idamax(l, h[gx(1i64, i, n)..], 1i64)
            var ca = gabs(h[gx(ica, i, n)])
            let ira = lb.idamax(n - k + 1i64, h[gx(i, k, n)..], n)
            var ra = gabs(h[gx(i, ira + k - 1i64, n)])
            if c == 0.0f64 || r == 0.0f64 {
                i = i + 1i64
                continue
            }
            var g = r / 2.0f64
            var f = 1.0f64
            let s = c + r
            while c < g && lb.f_max(lb.f_max(f, c), ca) < sfmax2 && lb.f_min(lb.f_min(r, g), ra) > sfmin2 {
                f = f * 2.0f64
                c = c * 2.0f64
                ca = ca * 2.0f64
                r = r / 2.0f64
                g = g / 2.0f64
                ra = ra / 2.0f64
            }
            g = c / 2.0f64
            while g >= r && lb.f_max(r, ra) < sfmax2 && lb.f_min(lb.f_min(f, c), lb.f_min(g, ca)) > sfmin2 {
                f = f / 2.0f64
                c = c / 2.0f64
                g = g / 2.0f64
                ca = ca / 2.0f64
                r = r * 2.0f64
                ra = ra * 2.0f64
            }
            var skip = false
            if c + r >= 0.95f64 * s { skip = true }
            let si = scale[usize(i - 1i64)]
            if !skip && f < 1.0f64 && si < 1.0f64 {
                if f * si <= sfmin1 { skip = true }
            }
            if !skip && f > 1.0f64 && si > 1.0f64 {
                if si >= sfmax1 / f { skip = true }
            }
            if !skip {
                scale[usize(i - 1i64)] = si * f
                noconv = true
                lb.dscal(n - k + 1i64, 1.0f64 / f, h[gx(i, k, n)..], n)
                lb.dscal(l, f, h[gx(1i64, i, n)..], 1i64)
            }
            i = i + 1i64
        }
    }
    ret (k, l)
}

type Nv2 = struct { a: f64, b: f64, c: f64, d: f64, r1r: f64, r1i: f64, r2r: f64, r2i: f64, cs: f64, sn: f64 }

// dlanv2: the Schur factorisation of a real 2 by 2 block
fn g_lanv2(a0: f64, b0: f64, c0: f64, d0: f64) -> Nv2 {
    var a = a0
    var b = b0
    var c = c0
    var d = d0
    var cs = 1.0f64
    var sn = 0.0f64
    let eps = 2.220446049250313e-16f64
    let safmn2 = lb.f_powi(2.0f64, -485i64)
    let safmx2 = 1.0f64 / safmn2
    if c == 0.0f64 {
        cs = 1.0f64
        sn = 0.0f64
    } else if b == 0.0f64 {
        cs = 0.0f64
        sn = 1.0f64
        let temp = d
        d = a
        a = temp
        b = -c
        c = 0.0f64
    } else if a - d == 0.0f64 && lb.f_sign(1.0f64, b) != lb.f_sign(1.0f64, c) {
        cs = 1.0f64
        sn = 0.0f64
    } else {
        var temp = a - d
        var p = 0.5f64 * temp
        let bcmax = lb.f_max(gabs(b), gabs(c))
        let bcmis = lb.f_min(gabs(b), gabs(c)) * lb.f_sign(1.0f64, b) * lb.f_sign(1.0f64, c)
        var scl = lb.f_max(gabs(p), bcmax)
        var z = (p / scl) * p + (bcmax / scl) * bcmis
        if z >= 4.0f64 * eps {
            z = p + lb.f_sign(math.sqrt[f64](scl) * math.sqrt[f64](z), p)
            a = d + z
            d = d - (bcmax / z) * bcmis
            let tau = lb.dlapy2(c, z)
            cs = z / tau
            sn = c / tau
            b = b - c
            c = 0.0f64
        } else {
            var count = 0i64
            var sigma = b + c
            var again = true
            while again {
                again = false
                count = count + 1i64
                scl = lb.f_max(gabs(temp), gabs(sigma))
                if scl >= safmx2 {
                    sigma = sigma * safmn2
                    temp = temp * safmn2
                    if count <= 20i64 {
                        again = true
                        continue
                    }
                }
                if scl <= safmn2 {
                    sigma = sigma * safmx2
                    temp = temp * safmx2
                    if count <= 20i64 {
                        again = true
                        continue
                    }
                }
            }
            p = 0.5f64 * temp
            var tau = lb.dlapy2(sigma, temp)
            cs = math.sqrt[f64](0.5f64 * (1.0f64 + gabs(sigma) / tau))
            sn = -(p / (tau * cs)) * lb.f_sign(1.0f64, sigma)
            let aa = a * cs + b * sn
            let bb = -a * sn + b * cs
            let cc = c * cs + d * sn
            let dd = -c * sn + d * cs
            a = aa * cs + cc * sn
            b = (bb * cs) + (dd * sn)
            c = -(aa * sn) + (cc * cs)
            d = -bb * sn + dd * cs
            temp = 0.5f64 * (a + d)
            a = temp
            d = temp
            if c != 0.0f64 {
                if b != 0.0f64 {
                    if lb.f_sign(1.0f64, b) == lb.f_sign(1.0f64, c) {
                        let sab = math.sqrt[f64](gabs(b))
                        let sac = math.sqrt[f64](gabs(c))
                        p = lb.f_sign(sab * sac, c)
                        tau = 1.0f64 / math.sqrt[f64](gabs(b + c))
                        a = temp + p
                        d = temp - p
                        b = b - c
                        c = 0.0f64
                        let cs1 = sab * tau
                        let sn1 = sac * tau
                        temp = cs * cs1 - sn * sn1
                        sn = cs * sn1 + sn * cs1
                        cs = temp
                    }
                } else {
                    b = -c
                    c = 0.0f64
                    temp = cs
                    cs = -sn
                    sn = temp
                }
            }
        }
    }
    var o: Nv2 = zero
    o.a = a
    o.b = b
    o.c = c
    o.d = d
    o.r1r = a
    o.r2r = d
    o.cs = cs
    o.sn = sn
    if c != 0.0f64 {
        o.r1i = math.sqrt[f64](gabs(b)) * math.sqrt[f64](gabs(c))
        o.r2i = -o.r1i
    }
    ret o
}

// dlahqr with wantt and wantz: the double-shift QR iteration on the Hessenberg h (n by n column-major, active block ilo..ihi), accumulating into z;
// returns info (0 when it converged)
fn g_lahqr(n: i64, ilo: i64, ihi: i64, h: []f64, wr: []f64, wi: []f64, z: []f64) -> i64 {
    if ilo == ihi {
        wr[usize(ilo - 1i64)] = h[gx(ilo, ilo, n)]
        wi[usize(ilo - 1i64)] = 0.0f64
        ret 0i64
    }
    var j0 = ilo
    while j0 <= ihi - 3i64 {
        h[gx(j0 + 2i64, j0, n)] = 0.0f64
        h[gx(j0 + 3i64, j0, n)] = 0.0f64
        j0 = j0 + 1i64
    }
    if ilo <= ihi - 2i64 { h[gx(ihi, ihi - 2i64, n)] = 0.0f64 }
    let nh = ihi - ilo + 1i64
    let nz = ihi - ilo + 1i64
    let safmin = 2.2250738585072014e-308f64
    let ulp = 2.220446049250313e-16f64
    let smlnum = safmin * (f64(nh) / ulp)
    let i1 = 1i64
    let i2 = n
    let itmax = 30i64 * lb.i_max(10i64, nh)
    var kdefl = 0i64
    var i = ihi
    var v: [3]f64 = zero
    while i >= ilo {
        var l = ilo
        var found = false
        var its = 0i64
        while its <= itmax {
            var k = i
            var stop = false
            while k >= l + 1i64 && !stop {
                if gabs(h[gx(k, k - 1i64, n)]) <= smlnum {
                    stop = true
                } else {
                    var tst = gabs(h[gx(k - 1i64, k - 1i64, n)]) + gabs(h[gx(k, k, n)])
                    if tst == 0.0f64 {
                        if k - 2i64 >= ilo { tst = tst + gabs(h[gx(k - 1i64, k - 2i64, n)]) }
                        if k + 1i64 <= ihi { tst = tst + gabs(h[gx(k + 1i64, k, n)]) }
                    }
                    if gabs(h[gx(k, k - 1i64, n)]) <= ulp * tst {
                        let ab = lb.f_max(gabs(h[gx(k, k - 1i64, n)]), gabs(h[gx(k - 1i64, k, n)]))
                        let ba = lb.f_min(gabs(h[gx(k, k - 1i64, n)]), gabs(h[gx(k - 1i64, k, n)]))
                        let aa = lb.f_max(gabs(h[gx(k, k, n)]), gabs(h[gx(k - 1i64, k - 1i64, n)] - h[gx(k, k, n)]))
                        let bb = lb.f_min(gabs(h[gx(k, k, n)]), gabs(h[gx(k - 1i64, k - 1i64, n)] - h[gx(k, k, n)]))
                        let s = aa + ab
                        if ba * (ab / s) <= lb.f_max(smlnum, ulp * (bb * (aa / s))) { stop = true }
                    }
                }
                if !stop { k = k - 1i64 }
            }
            l = k
            if l > ilo { h[gx(l, l - 1i64, n)] = 0.0f64 }
            if l >= i - 1i64 {
                found = true
                break
            }
            kdefl = kdefl + 1i64
            var h11 = 0.0f64
            var h21 = 0.0f64
            var h12 = 0.0f64
            var h22 = 0.0f64
            if kdefl % 20i64 == 0i64 {
                let s = gabs(h[gx(i, i - 1i64, n)]) + gabs(h[gx(i - 1i64, i - 2i64, n)])
                h11 = 0.75f64 * s + h[gx(i, i, n)]
                h12 = -0.4375f64 * s
                h21 = s
                h22 = h11
            } else if kdefl % 10i64 == 0i64 {
                let s = gabs(h[gx(l + 1i64, l, n)]) + gabs(h[gx(l + 2i64, l + 1i64, n)])
                h11 = 0.75f64 * s + h[gx(l, l, n)]
                h12 = -0.4375f64 * s
                h21 = s
                h22 = h11
            } else {
                h11 = h[gx(i - 1i64, i - 1i64, n)]
                h21 = h[gx(i, i - 1i64, n)]
                h12 = h[gx(i - 1i64, i, n)]
                h22 = h[gx(i, i, n)]
            }
            var rt1r = 0.0f64
            var rt1i = 0.0f64
            var rt2r = 0.0f64
            var rt2i = 0.0f64
            let s0 = gabs(h11) + gabs(h12) + gabs(h21) + gabs(h22)
            if s0 != 0.0f64 {
                h11 = h11 / s0
                h21 = h21 / s0
                h12 = h12 / s0
                h22 = h22 / s0
                let tr = (h11 + h22) / 2.0f64
                let det = (h11 - tr) * (h22 - tr) - h12 * h21
                let rtdisc = math.sqrt[f64](gabs(det))
                if det >= 0.0f64 {
                    rt1r = tr * s0
                    rt2r = rt1r
                    rt1i = rtdisc * s0
                    rt2i = -rt1i
                } else {
                    rt1r = tr + rtdisc
                    rt2r = tr - rtdisc
                    if gabs(rt1r - h22) <= gabs(rt2r - h22) {
                        rt1r = rt1r * s0
                        rt2r = rt1r
                    } else {
                        rt2r = rt2r * s0
                        rt1r = rt2r
                    }
                    rt1i = 0.0f64
                    rt2i = 0.0f64
                }
            }
            var m = i - 2i64
            while true {
                var h21s = h[gx(m + 1i64, m, n)]
                var s = gabs(h[gx(m, m, n)] - rt2r) + gabs(rt2i) + gabs(h21s)
                h21s = h[gx(m + 1i64, m, n)] / s
                v[0usize] = h21s * h[gx(m, m + 1i64, n)] + (h[gx(m, m, n)] - rt1r) * ((h[gx(m, m, n)] - rt2r) / s) - rt1i * (rt2i / s)
                v[1usize] = h21s * (h[gx(m, m, n)] + h[gx(m + 1i64, m + 1i64, n)] - rt1r - rt2r)
                v[2usize] = h21s * h[gx(m + 2i64, m + 1i64, n)]
                s = gabs(v[0usize]) + gabs(v[1usize]) + gabs(v[2usize])
                v[0usize] = v[0usize] / s
                v[1usize] = v[1usize] / s
                v[2usize] = v[2usize] / s
                if m == l { break }
                let h00 = gabs(h[gx(m, m - 1i64, n)]) * (gabs(v[1usize]) + gabs(v[2usize]))
                let h01 = ulp * gabs(v[0usize]) * (gabs(h[gx(m - 1i64, m - 1i64, n)]) + gabs(h[gx(m, m, n)]) + gabs(h[gx(m + 1i64, m + 1i64, n)]))
                if h00 <= h01 { break }
                m = m - 1i64
            }
            var kk = m
            while kk <= i - 1i64 {
                let nr = lb.i_min(3i64, i - kk + 1i64)
                if kk > m {
                    var q = 0i64
                    while q < nr {
                        v[usize(q)] = h[gx(kk + q, kk - 1i64, n)]
                        q = q + 1i64
                    }
                }
                var alpha = v[0usize]
                var t1 = 0.0f64
                lb.dlarfg(nr, &alpha, v[1usize..], 1i64, &t1)
                v[0usize] = alpha
                if kk > m {
                    h[gx(kk, kk - 1i64, n)] = v[0usize]
                    h[gx(kk + 1i64, kk - 1i64, n)] = 0.0f64
                    if kk < i - 1i64 { h[gx(kk + 2i64, kk - 1i64, n)] = 0.0f64 }
                } else if m > l {
                    h[gx(kk, kk - 1i64, n)] = h[gx(kk, kk - 1i64, n)] * (1.0f64 - t1)
                }
                let v2 = v[1usize]
                let t2 = t1 * v2
                if nr == 3i64 {
                    let v3 = v[2usize]
                    let t3 = t1 * v3
                    var j = kk
                    while j <= i2 {
                        let sum = h[gx(kk, j, n)] + v2 * h[gx(kk + 1i64, j, n)] + v3 * h[gx(kk + 2i64, j, n)]
                        h[gx(kk, j, n)] = h[gx(kk, j, n)] - sum * t1
                        h[gx(kk + 1i64, j, n)] = h[gx(kk + 1i64, j, n)] - sum * t2
                        h[gx(kk + 2i64, j, n)] = h[gx(kk + 2i64, j, n)] - sum * t3
                        j = j + 1i64
                    }
                    j = i1
                    let jend = lb.i_min(kk + 3i64, i)
                    while j <= jend {
                        let sum = h[gx(j, kk, n)] + v2 * h[gx(j, kk + 1i64, n)] + v3 * h[gx(j, kk + 2i64, n)]
                        h[gx(j, kk, n)] = h[gx(j, kk, n)] - sum * t1
                        h[gx(j, kk + 1i64, n)] = h[gx(j, kk + 1i64, n)] - sum * t2
                        h[gx(j, kk + 2i64, n)] = h[gx(j, kk + 2i64, n)] - sum * t3
                        j = j + 1i64
                    }
                    j = ilo
                    while j <= ihi {
                        let sum = z[gx(j, kk, n)] + v2 * z[gx(j, kk + 1i64, n)] + v3 * z[gx(j, kk + 2i64, n)]
                        z[gx(j, kk, n)] = z[gx(j, kk, n)] - sum * t1
                        z[gx(j, kk + 1i64, n)] = z[gx(j, kk + 1i64, n)] - sum * t2
                        z[gx(j, kk + 2i64, n)] = z[gx(j, kk + 2i64, n)] - sum * t3
                        j = j + 1i64
                    }
                } else if nr == 2i64 {
                    var j = kk
                    while j <= i2 {
                        let sum = h[gx(kk, j, n)] + v2 * h[gx(kk + 1i64, j, n)]
                        h[gx(kk, j, n)] = h[gx(kk, j, n)] - sum * t1
                        h[gx(kk + 1i64, j, n)] = h[gx(kk + 1i64, j, n)] - sum * t2
                        j = j + 1i64
                    }
                    j = i1
                    while j <= i {
                        let sum = h[gx(j, kk, n)] + v2 * h[gx(j, kk + 1i64, n)]
                        h[gx(j, kk, n)] = h[gx(j, kk, n)] - sum * t1
                        h[gx(j, kk + 1i64, n)] = h[gx(j, kk + 1i64, n)] - sum * t2
                        j = j + 1i64
                    }
                    j = ilo
                    while j <= ihi {
                        let sum = z[gx(j, kk, n)] + v2 * z[gx(j, kk + 1i64, n)]
                        z[gx(j, kk, n)] = z[gx(j, kk, n)] - sum * t1
                        z[gx(j, kk + 1i64, n)] = z[gx(j, kk + 1i64, n)] - sum * t2
                        j = j + 1i64
                    }
                }
                kk = kk + 1i64
            }
            its = its + 1i64
        }
        if !found { ret i }
        if l == i {
            wr[usize(i - 1i64)] = h[gx(i, i, n)]
            wi[usize(i - 1i64)] = 0.0f64
        } else if l == i - 1i64 {
            let nv = g_lanv2(h[gx(i - 1i64, i - 1i64, n)], h[gx(i - 1i64, i, n)], h[gx(i, i - 1i64, n)], h[gx(i, i, n)])
            h[gx(i - 1i64, i - 1i64, n)] = nv.a
            h[gx(i - 1i64, i, n)] = nv.b
            h[gx(i, i - 1i64, n)] = nv.c
            h[gx(i, i, n)] = nv.d
            wr[usize(i - 2i64)] = nv.r1r
            wi[usize(i - 2i64)] = nv.r1i
            wr[usize(i - 1i64)] = nv.r2r
            wi[usize(i - 1i64)] = nv.r2i
            if i2 > i { lb.drot(i2 - i, h[gx(i - 1i64, i + 1i64, n)..], n, h[gx(i, i + 1i64, n)..], n, nv.cs, nv.sn) }
            lb.drot(i - i1 - 1i64, h[gx(i1, i - 1i64, n)..], 1i64, h[gx(i1, i, n)..], 1i64, nv.cs, nv.sn)
            lb.drot(nz, z[gx(ilo, i - 1i64, n)..], 1i64, z[gx(ilo, i, n)..], 1i64, nv.cs, nv.sn)
        }
        kdefl = 0i64
        i = l - 1i64
    }
    ret 0i64
}

// dlaln2 for one right-hand side: solves (T - wr I) x = b for a 1 by 1 (na 1) or 2 by 2 (na 2, column-major c) real block; returns x1, x2, scale, xnorm
type Ln2 = struct { x1: f64, x2: f64, scale: f64, xnorm: f64 }

fn g_ipiv(i: i64, icmax: i64) -> i64 {
    if icmax == 1i64 { ret i }
    if icmax == 2i64 {
        if i == 1i64 { ret 2i64 }
        if i == 2i64 { ret 1i64 }
        if i == 3i64 { ret 4i64 }
        ret 3i64
    }
    if icmax == 3i64 {
        if i == 1i64 { ret 3i64 }
        if i == 2i64 { ret 4i64 }
        if i == 3i64 { ret 1i64 }
        ret 2i64
    }
    ret 5i64 - i
}

fn g_laln2(na: i64, smin: f64, c11: f64, c21: f64, c12: f64, c22: f64, b1: f64, b2: f64) -> Ln2 {
    var o: Ln2 = zero
    let smlnum = 2.0f64 * 2.2250738585072014e-308f64
    let bignum = 1.0f64 / smlnum
    let smini = lb.f_max(smin, smlnum)
    o.scale = 1.0f64
    if na == 1i64 {
        var csr = c11
        var cnorm = gabs(csr)
        if cnorm < smini {
            csr = smini
            cnorm = smini
        }
        let bnorm = gabs(b1)
        if cnorm < 1.0f64 && bnorm > 1.0f64 {
            if bnorm > bignum * cnorm { o.scale = 1.0f64 / bnorm }
        }
        o.x1 = (b1 * o.scale) / csr
        o.xnorm = gabs(o.x1)
        ret o
    }
    var crv: [4]f64 = zero
    crv[0usize] = c11
    crv[1usize] = c21
    crv[2usize] = c12
    crv[3usize] = c22
    var cmax = 0.0f64
    var icmax = 0i64
    var j = 1i64
    while j <= 4i64 {
        if gabs(crv[usize(j - 1i64)]) > cmax {
            cmax = gabs(crv[usize(j - 1i64)])
            icmax = j
        }
        j = j + 1i64
    }
    if cmax < smini {
        let bnorm = lb.f_max(gabs(b1), gabs(b2))
        if smini < 1.0f64 && bnorm > 1.0f64 {
            if bnorm > bignum * smini { o.scale = 1.0f64 / bnorm }
        }
        let temp = o.scale / smini
        o.x1 = temp * b1
        o.x2 = temp * b2
        o.xnorm = temp * bnorm
        ret o
    }
    let ur11 = crv[usize(icmax - 1i64)]
    let cr21 = crv[usize(g_ipiv(2i64, icmax) - 1i64)]
    let ur12 = crv[usize(g_ipiv(3i64, icmax) - 1i64)]
    let cr22 = crv[usize(g_ipiv(4i64, icmax) - 1i64)]
    let ur11r = 1.0f64 / ur11
    let lr21 = ur11r * cr21
    var ur22 = cr22 - ur12 * lr21
    if gabs(ur22) < smini { ur22 = smini }
    var br1 = b1
    var br2 = b2
    if icmax == 2i64 || icmax == 4i64 {
        br1 = b2
        br2 = b1
    }
    br2 = br2 - lr21 * br1
    let bbnd = lb.f_max(gabs(br1 * (ur22 * ur11r)), gabs(br2))
    if bbnd > 1.0f64 && gabs(ur22) < 1.0f64 {
        if bbnd >= bignum * gabs(ur22) { o.scale = 1.0f64 / bbnd }
    }
    let xr2 = (br2 * o.scale) / ur22
    let xr1 = (o.scale * br1) * ur11r - xr2 * (ur11r * ur12)
    if icmax == 3i64 || icmax == 4i64 {
        o.x1 = xr2
        o.x2 = xr1
    } else {
        o.x1 = xr1
        o.x2 = xr2
    }
    o.xnorm = lb.f_max(gabs(xr1), gabs(xr2))
    if o.xnorm > 1.0f64 && cmax > 1.0f64 {
        if o.xnorm > bignum / cmax {
            let temp = cmax / bignum
            o.x1 = temp * o.x1
            o.x2 = temp * o.x2
            o.xnorm = temp * o.xnorm
            o.scale = temp * o.scale
        }
    }
    ret o
}

// dgeev jobvl N, jobvr V on the n by n row-major m: vals gets the real parts of the eigenvalues and vecs (n by n row-major, one eigenvector per
// column) the unit-norm right eigenvectors, both ordered by decreasing modulus as eigen() orders them
fn eigen_general(a: *mem.Arena, m: []const f64, n: usize, vals: []f64, vecs: []f64) -> err {
    let nn = i64(n)
    let (h, e1) = mem.alloc[f64](a, n * n)
    let (z, e2) = mem.alloc[f64](a, n * n)
    let (scale, e3) = mem.alloc[f64](a, n)
    let (tau, e4) = mem.alloc[f64](a, n)
    let (wr, e5) = mem.alloc[f64](a, n)
    let (wi, e6) = mem.alloc[f64](a, n)
    let (work, e7) = mem.alloc[f64](a, n * 64usize + 64usize)
    let (xv, e8) = mem.alloc[f64](a, n)
    let (cnorm, e9) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret Malformed }
    var q = 0usize
    while q < n * n {
        h[q] = 0.0f64
        z[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < n {
        scale[q] = 0.0f64
        tau[q] = 0.0f64
        wr[q] = 0.0f64
        wi[q] = 0.0f64
        xv[q] = 0.0f64
        cnorm[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < n * 64usize + 64usize {
        work[q] = 0.0f64
        q += 1usize
    }
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            h[r + c * n] = m[r * n + c]
            c += 1usize
        }
        r += 1usize
    }
    let (ilo, ihi) = g_balance(nn, h, scale)
    // dgehd2
    var i = ilo
    while i <= ihi - 1i64 {
        var alpha = h[gx(i + 1i64, i, nn)]
        var t = 0.0f64
        lb.dlarfg(ihi - i, &alpha, h[gx(lb.i_min(i + 2i64, nn), i, nn)..], 1i64, &t)
        h[gx(i + 1i64, i, nn)] = alpha
        tau[usize(i - 1i64)] = t
        lb.dlarf1f("Right", ihi, ihi - i, h[gx(i + 1i64, i, nn)..], 1i64, t, h[gx(1i64, i + 1i64, nn)..], nn, work)
        lb.dlarf1f("Left", ihi - i, nn - i, h[gx(i + 1i64, i, nn)..], 1i64, t, h[gx(i + 1i64, i + 1i64, nn)..], nn, work)
        i = i + 1i64
    }
    // dlacpy L, then dorghr
    var c0 = 1i64
    while c0 <= nn {
        var r0 = c0
        while r0 <= nn {
            z[gx(r0, c0, nn)] = h[gx(r0, c0, nn)]
            r0 = r0 + 1i64
        }
        c0 = c0 + 1i64
    }
    var j = ihi
    while j >= ilo + 1i64 {
        var i2 = 1i64
        while i2 <= j - 1i64 {
            z[gx(i2, j, nn)] = 0.0f64
            i2 = i2 + 1i64
        }
        i2 = j + 1i64
        while i2 <= ihi {
            z[gx(i2, j, nn)] = z[gx(i2, j - 1i64, nn)]
            i2 = i2 + 1i64
        }
        i2 = ihi + 1i64
        while i2 <= nn {
            z[gx(i2, j, nn)] = 0.0f64
            i2 = i2 + 1i64
        }
        j = j - 1i64
    }
    j = 1i64
    while j <= ilo {
        var i2 = 1i64
        while i2 <= nn {
            z[gx(i2, j, nn)] = 0.0f64
            i2 = i2 + 1i64
        }
        z[gx(j, j, nn)] = 1.0f64
        j = j + 1i64
    }
    j = ihi + 1i64
    while j <= nn {
        var i2 = 1i64
        while i2 <= nn {
            z[gx(i2, j, nn)] = 0.0f64
            i2 = i2 + 1i64
        }
        z[gx(j, j, nn)] = 1.0f64
        j = j + 1i64
    }
    let nh = ihi - ilo
    if nh > 0i64 {
        var info = 0i64
        lb.dorgqr(nh, nh, nh, z[gx(ilo + 1i64, ilo + 1i64, nn)..], nn, tau[usize(ilo - 1i64)..], work, i64(n * 64usize + 64usize), &info)
        if info != 0i64 { ret Malformed }
    }
    // dhseqr: eigenvalues isolated by dgebal, then dlahqr
    i = 1i64
    while i < ilo {
        wr[usize(i - 1i64)] = h[gx(i, i, nn)]
        wi[usize(i - 1i64)] = 0.0f64
        i = i + 1i64
    }
    i = ihi + 1i64
    while i <= nn {
        wr[usize(i - 1i64)] = h[gx(i, i, nn)]
        wi[usize(i - 1i64)] = 0.0f64
        i = i + 1i64
    }
    if nn > 75i64 { ret Malformed }
    if ilo == ihi {
        wr[usize(ilo - 1i64)] = h[gx(ilo, ilo, nn)]
        wi[usize(ilo - 1i64)] = 0.0f64
    } else {
        let info = g_lahqr(nn, ilo, ihi, h, wr, wi, z)
        if info != 0i64 { ret Malformed }
    }
    if nn > 2i64 {
        var c1 = 1i64
        while c1 <= nn - 2i64 {
            var r1 = c1 + 2i64
            while r1 <= nn {
                h[gx(r1, c1, nn)] = 0.0f64
                r1 = r1 + 1i64
            }
            c1 = c1 + 1i64
        }
    }
    // dtrevc3 right eigenvectors of the quasi-triangular h, back-transformed by z (the unblocked path; the blocked one rounds differently only)
    let unfl = 2.2250738585072014e-308f64
    let ulp = 2.220446049250313e-16f64
    let smlnum = unfl * (f64(nn) / ulp)
    let bignum = (1.0f64 - ulp) / smlnum
    var jj = 2i64
    while jj <= nn {
        var s = 0.0f64
        var ii = 1i64
        while ii <= jj - 1i64 {
            s = s + gabs(h[gx(ii, jj, nn)])
            ii = ii + 1i64
        }
        cnorm[usize(jj - 1i64)] = s
        jj = jj + 1i64
    }
    var ip = 0i64
    var ki = nn
    while ki >= 1i64 {
        if ip == -1i64 {
            ip = 1i64
            ki = ki - 1i64
            continue
        } else if ki == 1i64 {
            ip = 0i64
        } else if h[gx(ki, ki - 1i64, nn)] == 0.0f64 {
            ip = 0i64
        } else {
            ip = -1i64
        }
        if ip != 0i64 {
            ki = ki - 1i64
            continue
        }
        let wrk = h[gx(ki, ki, nn)]
        let smin = lb.f_max(ulp * gabs(wrk), smlnum)
        xv[usize(ki - 1i64)] = 1.0f64
        var kq = 1i64
        while kq <= ki - 1i64 {
            xv[usize(kq - 1i64)] = -h[gx(kq, ki, nn)]
            kq = kq + 1i64
        }
        var jnxt = ki - 1i64
        var jq = ki - 1i64
        while jq >= 1i64 {
            if jq > jnxt {
                jq = jq - 1i64
                continue
            }
            var j1 = jq
            jnxt = jq - 1i64
            if jq > 1i64 {
                if h[gx(jq, jq - 1i64, nn)] != 0.0f64 {
                    j1 = jq - 1i64
                    jnxt = jq - 2i64
                }
            }
            if j1 == jq {
                let sol = g_laln2(1i64, smin, h[gx(jq, jq, nn)] - wrk, 0.0f64, 0.0f64, 0.0f64, xv[usize(jq - 1i64)], 0.0f64)
                var x11 = sol.x1
                var sc = sol.scale
                if sol.xnorm > 1.0f64 {
                    if cnorm[usize(jq - 1i64)] > bignum / sol.xnorm {
                        x11 = x11 / sol.xnorm
                        sc = sc / sol.xnorm
                    }
                }
                if sc != 1.0f64 { lb.dscal(ki, sc, xv, 1i64) }
                xv[usize(jq - 1i64)] = x11
                lb.daxpy(jq - 1i64, -x11, h[gx(1i64, jq, nn)..], 1i64, xv, 1i64)
            } else {
                let sol = g_laln2(2i64, smin, h[gx(jq - 1i64, jq - 1i64, nn)] - wrk, h[gx(jq, jq - 1i64, nn)], h[gx(jq - 1i64, jq, nn)], h[gx(jq, jq, nn)] - wrk, xv[usize(jq - 2i64)], xv[usize(jq - 1i64)])
                var x11 = sol.x1
                var x21 = sol.x2
                var sc = sol.scale
                if sol.xnorm > 1.0f64 {
                    let beta = lb.f_max(cnorm[usize(jq - 2i64)], cnorm[usize(jq - 1i64)])
                    if beta > bignum / sol.xnorm {
                        x11 = x11 / sol.xnorm
                        x21 = x21 / sol.xnorm
                        sc = sc / sol.xnorm
                    }
                }
                if sc != 1.0f64 { lb.dscal(ki, sc, xv, 1i64) }
                xv[usize(jq - 2i64)] = x11
                xv[usize(jq - 1i64)] = x21
                lb.daxpy(jq - 2i64, -x11, h[gx(1i64, jq - 1i64, nn)..], 1i64, xv, 1i64)
                lb.daxpy(jq - 2i64, -x21, h[gx(1i64, jq, nn)..], 1i64, xv, 1i64)
            }
            jq = jq - 1i64
        }
        if ki > 1i64 { lb.dgemv("N", nn, ki - 1i64, 1.0f64, z, nn, xv, 1i64, xv[usize(ki - 1i64)], z[gx(1i64, ki, nn)..], 1i64) }
        let iim = lb.idamax(nn, z[gx(1i64, ki, nn)..], 1i64)
        let remax = 1.0f64 / gabs(z[gx(iim, ki, nn)])
        lb.dscal(nn, remax, z[gx(1i64, ki, nn)..], 1i64)
        ki = ki - 1i64
    }
    // dgebak B, R
    if ilo != ihi {
        i = ilo
        while i <= ihi {
            lb.dscal(nn, scale[usize(i - 1i64)], z[gx(i, 1i64, nn)..], nn)
            i = i + 1i64
        }
    }
    var iiq = 1i64
    while iiq <= nn {
        var ib = iiq
        var skip = false
        if ib >= ilo && ib <= ihi { skip = true }
        if !skip {
            if ib < ilo { ib = ilo - iiq }
            let kb = i64(scale[usize(ib - 1i64)])
            if kb != ib { lb.dswap(nn, z[gx(ib, 1i64, nn)..], nn, z[gx(kb, 1i64, nn)..], nn) }
        }
        iiq = iiq + 1i64
    }
    // normalise the real columns, zero the complex ones, order by modulus
    var cplx = false
    i = 1i64
    while i <= nn {
        if wi[usize(i - 1i64)] == 0.0f64 {
            let scl = 1.0f64 / lb.dnrm2(nn, z[gx(1i64, i, nn)..], 1i64)
            lb.dscal(nn, scl, z[gx(1i64, i, nn)..], 1i64)
        } else {
            cplx = true
            var rr = 1i64
            while rr <= nn {
                z[gx(rr, i, nn)] = 0.0f64
                rr = rr + 1i64
            }
        }
        i = i + 1i64
    }
    let (ord, e10) = mem.alloc[usize](a, n)
    let (modv, e11) = mem.alloc[f64](a, n)
    if e10 != ok || e11 != ok { ret Malformed }
    q = 0usize
    while q < n {
        ord[q] = q
        modv[q] = math.sqrt[f64](wr[q] * wr[q] + wi[q] * wi[q])
        q += 1usize
    }
    q = 1usize
    while q < n {
        let cur = ord[q]
        var w = q
        while w > 0usize && modv[ord[w - 1usize]] < modv[cur] {
            ord[w] = ord[w - 1usize]
            w -= 1usize
        }
        ord[w] = cur
        q += 1usize
    }
    q = 0usize
    while q < n {
        vals[q] = wr[ord[q]]
        var rr = 0usize
        while rr < n {
            vecs[rr * n + q] = z[rr + ord[q] * n]
            rr += 1usize
        }
        q += 1usize
    }
    ret ok
}

type Coin = struct { d: Dudi, lx: []f64, ly: []f64, rv: f64 }

// coinertia's branch for both tables having more columns than rows: the nonsymmetric eigenproblem of (lw * X cwx t(X)) (lw * Y cwy t(Y)) (R's eigen
// goes through dgeev), nf already clamped to both ranks
fn coin_wide(a: *mem.Arena, xt: []const f64, yt: []const f64, n: usize, px: usize, py: usize, lw: []const f64, cwx: []const f64, cwy: []const f64, nf0: usize) -> (Dudi, err) {
    var out: Dudi = zero
    let (w1, a1) = mem.alloc[f64](a, n * n)
    let (w2, a2) = mem.alloc[f64](a, n * n)
    let (pm, a3) = mem.alloc[f64](a, n * n)
    let (vals, a4) = mem.alloc[f64](a, n)
    let (vecs, a5) = mem.alloc[f64](a, n * n)
    if a1 != ok || a2 != ok || a3 != ok || a4 != ok || a5 != ok { ret (out, Malformed) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var sx = 0.0f64
            var k = 0usize
            while k < px {
                sx += xt[i * px + k] * (xt[j * px + k] * cwx[k])
                k += 1usize
            }
            var sy2 = 0.0f64
            k = 0usize
            while k < py {
                sy2 += yt[i * py + k] * (yt[j * py + k] * cwy[k])
                k += 1usize
            }
            w1[i * n + j] = lw[i] * sx
            w2[i * n + j] = lw[i] * sy2
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += w1[i * n + k] * w2[k * n + j]
                k += 1usize
            }
            pm[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let eg = eigen_general(a, pm, n, vals, vecs)
    if eg != ok { ret (out, eg) }
    var rank = 0usize
    i = 0usize
    while i < n {
        if vals[i] / vals[0usize] > 0.0000001f64 { rank += 1usize }
        i += 1usize
    }
    var nf = nf0
    if nf == 0usize { nf = 2usize }
    if nf > rank { nf = rank }
    let (eg2, b1) = mem.alloc[f64](a, rank)
    let (l1, b2) = mem.alloc[f64](a, py * nf)
    let (li, b3) = mem.alloc[f64](a, py * nf)
    let (co, b4) = mem.alloc[f64](a, px * nf)
    let (c1, b5) = mem.alloc[f64](a, px * nf)
    let (tmp, b6) = mem.alloc[f64](a, n)
    if b1 != ok || b2 != ok || b3 != ok || b4 != ok || b5 != ok || b6 != ok { ret (out, Malformed) }
    i = 0usize
    while i < rank {
        eg2[i] = vals[i]
        i += 1usize
    }
    var c = 0usize
    while c < nf {
        var r = 0usize
        var nrm = 0.0f64
        while r < py {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += yt[i * py + r] * vecs[i * n + c]
                i += 1usize
            }
            l1[r * nf + c] = s
            nrm += s * s * cwy[r]
            r += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        r = 0usize
        while r < py {
            l1[r * nf + c] = l1[r * nf + c] / nrm
            li[r * nf + c] = l1[r * nf + c] * math.sqrt[f64](eg2[c])
            r += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            r = 0usize
            while r < py {
                s += (yt[i * py + r] * lw[i]) * (l1[r * nf + c] * cwy[r])
                r += 1usize
            }
            tmp[i] = s
            i += 1usize
        }
        var q = 0usize
        while q < px {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += xt[i * px + q] * tmp[i]
                i += 1usize
            }
            co[q * nf + c] = s
            c1[q * nf + c] = s / math.sqrt[f64](eg2[c])
            q += 1usize
        }
        c += 1usize
    }
    out.rank = rank
    out.nf = nf
    out.eig = eg2
    out.c1 = c1
    out.li = li
    out.co = co
    out.l1 = l1
    ret (out, ok)
}

// coinertia (the branch with at least one table having no more columns than rows): the analysis of t(Ytab) diag(lw) Xtab with column weights cwx
// and row weights cwy; lx and ly are the row scores of the two tables; rv is the RV coefficient. The tables share the n row weights lw.
fn coinertia(a: *mem.Arena, xt: []const f64, yt: []const f64, n: usize, px: usize, py: usize, lw: []const f64, cwx: []const f64, cwy: []const f64, nf0: usize) -> (Coin, err) {
    var out: Coin = zero
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
    var d: Dudi = zero
    if n < px && n < py {
        let (dw, ew) = coin_wide(a, xt, yt, n, px, py, lw, cwx, cwy, nf)
        if ew != ok { ret (out, ew) }
        d = dw
    } else {
        let (dn, e4) = as_dudi(a, tc, py, px, cwy, cwx, nf, 0.0000001f64)
        if e4 != ok { ret (out, e4) }
        d = dn
    }
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

// rx (n by py) and ry (n by px) are the rotated tables X u t(v) and Y v t(u) (R keeps them only when nf equals both column counts)
type Procuste = struct { rank: usize, nf: usize, d: []f64, lx: []f64, ly: []f64, sx: []f64, sy: []f64, rx: []f64, ry: []f64 }

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
    let (rx, e12) = mem.alloc[f64](a, n * py)
    let (ry, e13) = mem.alloc[f64](a, n * px)
    if e12 != ok || e13 != ok { ret (out, Malformed) }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < py {
            var t1 = 0.0f64
            q = 0usize
            while q < nf {
                t1 += sx[i * nf + q] * ly[c * nf + q]
                q += 1usize
            }
            rx[i * py + c] = t1
            c += 1usize
        }
        c = 0usize
        while c < px {
            var t2 = 0.0f64
            q = 0usize
            while q < nf {
                t2 += sy2[i * nf + q] * lx[c * nf + q]
                q += 1usize
            }
            ry[i * px + c] = t2
            c += 1usize
        }
        i += 1usize
    }
    out.rx = rx
    out.ry = ry
    ret (out, ok)
}

// the correlation ratios of dudi.acm: for factor v (codes as dudi_acm) and axis k, the weighted between-level sum of squares of the row scores l1 (n by nf,
// row weights lw); out is nv by nf row-major
fn acm_cr(a: *mem.Arena, codes: []const f64, n: usize, nv: usize, lw: []const f64, l1: []const f64, nf: usize, out: []f64) -> err {
    var v = 0usize
    while v < nv {
        var nl = 0usize
        var i = 0usize
        while i < n {
            if usize(codes[i * nv + v]) + 1usize > nl { nl = usize(codes[i * nv + v]) + 1usize }
            i += 1usize
        }
        var k = 0usize
        while k < nf {
            var tot = 0.0f64
            var l = 0usize
            while l < nl {
                var p1 = 0.0f64
                var p2 = 0.0f64
                var z1 = 0.0f64
                var z2 = 0.0f64
                i = 0usize
                while i < n {
                    if usize(codes[i * nv + v]) == l {
                        let (u1, u2) = nstep(p1, p2, lw[i])
                        p1 = u1
                        p2 = u2
                        let (w1, w2) = nstep(z1, z2, l1[i * nf + k] * lw[i])
                        z1 = w1
                        z2 = w2
                    }
                    i += 1usize
                }
                let poi = p1 + p2
                let z = (z1 + z2) / poi
                tot += poi * z * z
                l += 1usize
            }
            out[v * nf + k] = tot
            k += 1usize
        }
        v += 1usize
    }
    ret ok
}

// the table dudi.mix builds: t is n by total (row-major), lw the row weights, cw the column weights, cnt[v] the number of columns variable v contributed
type MixTab = struct { t: []f64, lw: []f64, cw: []f64, total: usize, cnt: []usize }

// the number of levels of a coded variable (0-based codes, every level present)
fn mix_levels(x: []const f64, n: usize, nv: usize, v: usize) -> usize {
    var mx = 0usize
    var i = 0usize
    while i < n {
        if usize(x[i * nv + v]) + 1usize > mx { mx = usize(x[i * nv + v]) + 1usize }
        i += 1usize
    }
    ret mx
}

fn mix_cols(kind: f64, nlev: usize) -> usize {
    if kind == 0.0f64 { ret 1usize }
    if kind == 3.0f64 { ret 2usize }
    if kind == 2.0f64 {
        if nlev > 2usize { ret 2usize }
        ret nlev - 1usize
    }
    ret nlev
}

// LINPACK dqrdc2 of the n by kk column-major q without pivoting (false when a column is negligible, which dqrdc2 would pivot, tolerance 1e-7), with the
// dnrm2 of the current BLAS (Blue's algorithm: plain sums of squares), which e.algo.linalg.decomp's scaled dnrm2 does not reproduce
fn hh_qr(q: []f64, qraux: []f64, n: usize, kk: usize) -> bool {
    var w2: [3]f64 = zero
    var j = 0usize
    while j < kk {
        qraux[j] = lb.dnrm2(i64(n), q[j * n..], 1i64)
        w2[j] = qraux[j]
        if w2[j] == 0.0f64 { w2[j] = 1.0f64 }
        j += 1usize
    }
    var lup = n
    if kk < lup { lup = kk }
    var l = 0usize
    while l < lup {
        if qraux[l] < w2[l] * 0.0000001f64 { ret false }
        if l + 1usize == n { ret true }
        var nrmxl = lb.dnrm2(i64(n - l), q[l * n + l..], 1i64)
        if nrmxl != 0.0f64 {
            if q[l * n + l] != 0.0f64 {
                if q[l * n + l] < 0.0f64 { nrmxl = 0.0f64 - math.abs[f64](nrmxl) } else { nrmxl = math.abs[f64](nrmxl) }
            }
            let inv = 1.0f64 / nrmxl
            var r = l
            while r < n {
                q[l * n + r] = q[l * n + r] * inv
                r += 1usize
            }
            q[l * n + l] = 1.0f64 + q[l * n + l]
            var c = l + 1usize
            while c < kk {
                var dot = 0.0f64
                r = l
                while r < n {
                    dot = dot + q[l * n + r] * q[c * n + r]
                    r += 1usize
                }
                let t = 0.0f64 - dot / q[l * n + l]
                r = l
                while r < n {
                    q[c * n + r] = q[c * n + r] + t * q[l * n + r]
                    r += 1usize
                }
                if qraux[c] != 0.0f64 {
                    var tt = 1.0f64 - (math.abs[f64](q[c * n + l]) / qraux[c]) * (math.abs[f64](q[c * n + l]) / qraux[c])
                    if tt < 0.0f64 { tt = 0.0f64 }
                    if math.abs[f64](tt) < 0.000001f64 {
                        qraux[c] = lb.dnrm2(i64(n - l - 1usize), q[c * n + l + 1usize..], 1i64)
                    } else {
                        qraux[c] = qraux[c] * math.sqrt[f64](tt)
                    }
                }
                c += 1usize
            }
            qraux[l] = q[l * n + l]
            q[l * n + l] = 0.0f64 - nrmxl
        }
        l += 1usize
    }
    ret true
}

// y becomes Q y (dqrsl job 10000) for the factorisation hh_qr left in q and qraux
fn hh_qy(q: []const f64, qraux: []const f64, n: usize, kk: usize, y: []f64) {
    var ju = kk
    if n - 1usize < ju { ju = n - 1usize }
    var jj = ju
    while jj > 0usize {
        jj -= 1usize
        if qraux[jj] != 0.0f64 {
            var dot = qraux[jj] * y[jj]
            var i = jj + 1usize
            while i < n {
                dot = dot + q[jj * n + i] * y[i]
                i += 1usize
            }
            let t = 0.0f64 - dot / qraux[jj]
            y[jj] = y[jj] + t * qraux[jj]
            i = jj + 1usize
            while i < n {
                y[i] = y[i] + t * q[jj * n + i]
                i += 1usize
            }
        }
    }
}

// sqrt(n - 1) * stats::poly(w, deg) for deg 1 or 2 written into columns col.. of t, as poly computes it: dqrdc2 of the powers of the centred variable, then
// Q times the diagonal of R (qr.qy), each column divided by its root sum of squares
fn mix_poly(a: *mem.Arena, w: []const f64, n: usize, deg: usize, t: []f64, total: usize, col: usize) -> err {
    let kk = deg + 1usize
    let (xm, e1) = mem.alloc[f64](a, n * kk)
    let (zc, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret Malformed }
    let xbar = arm.mean_ld(w[0usize..n])
    var i = 0usize
    var j = 0usize
    while j < kk {
        i = 0usize
        while i < n {
            let xc = w[i] - xbar
            var pw = 1.0f64
            if j == 1usize { pw = xc }
            if j == 2usize { pw = xc * xc }
            xm[j * n + i] = pw
            i += 1usize
        }
        j += 1usize
    }
    let (qraux, e3) = mem.alloc[f64](a, kk)
    if e3 != ok { ret Malformed }
    if !hh_qr(xm, qraux, n, kk) { ret Malformed }
    j = 1usize
    while j < kk {
        i = 0usize
        while i < n {
            zc[i] = 0.0f64
            i += 1usize
        }
        zc[j] = xm[j * n + j]
        hh_qy(xm, qraux, n, kk, zc)
        var s1 = 0.0f64
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            let (u1, u2) = nstep(s1, s2, zc[i] * zc[i])
            s1 = u1
            s2 = u2
            i += 1usize
        }
        let nr = math.sqrt[f64](s1 + s2)
        i = 0usize
        while i < n {
            t[i * total + col + j - 1usize] = math.sqrt[f64](f64(n - 1usize)) * (zc[i] / nr)
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

fn mix_table(a: *mem.Arena, x: []const f64, kinds: []const f64, n: usize, nv: usize, lwin: []const f64, uni: bool) -> (MixTab, err) {
    var total = 0usize
    var v = 0usize
    while v < nv {
        var nlev = 0usize
        if kinds[v] != 0.0f64 && kinds[v] != 3.0f64 { nlev = mix_levels(x, n, nv, v) }
        total += mix_cols(kinds[v], nlev)
        v += 1usize
    }
    let (t, e1) = mem.alloc[f64](a, n * total)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, total)
    let (cnt, e4) = mem.alloc[usize](a, nv)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (zero, Malformed) }
    var i = 0usize
    var sw1 = 0.0f64
    var sw2 = 0.0f64
    while i < n {
        lw[i] = lwin[i]
        let (q1, q2) = nstep(sw1, sw2, lw[i])
        sw1 = q1
        sw2 = q2
        i += 1usize
    }
    let swt = sw1 + sw2
    let (wv, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret (zero, Malformed) }
    var col = 0usize
    v = 0usize
    while v < nv {
        let kd = kinds[v]
        if kd == 0.0f64 {
            var m1 = 0.0f64
            var m2 = 0.0f64
            i = 0usize
            while i < n {
                var xv = x[i * nv + v]
                if !uni { xv = xv * lw[i] }
                let (u1, u2) = nstep(m1, m2, xv)
                m1 = u1
                m2 = u2
                i += 1usize
            }
            var moy = (m1 + m2) / swt
            if uni { moy = (m1 + m2) / f64(n) }
            var s1 = 0.0f64
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                let d = x[i * nv + v] - moy
                t[i * total + col] = d
                var dd = d * d
                if !uni { dd = lw[i] * dd }
                let (w1, w2) = nstep(s1, s2, dd)
                s1 = w1
                s2 = w2
                i += 1usize
            }
            var vr = (s1 + s2) / swt
            if uni { vr = (s1 + s2) / f64(n) }
            if vr < 0.00000000000001f64 { vr = 1.0f64 }
            let et = math.sqrt[f64](vr)
            i = 0usize
            while i < n {
                t[i * total + col] = t[i * total + col] / et
                i += 1usize
            }
            cw[col] = 1.0f64
            cnt[v] = 1usize
            col += 1usize
        } else if kd == 1.0f64 {
            let nl = mix_levels(x, n, nv, v)
            var l = 0usize
            while l < nl {
                var c1 = 0.0f64
                var c2 = 0.0f64
                i = 0usize
                while i < n {
                    var ind = 0.0f64
                    if usize(x[i * nv + v]) == l { ind = 1.0f64 }
                    if uni {
                        let (u1, u2) = nstep(c1, c2, ind * lw[i])
                        c1 = u1
                        c2 = u2
                    } else {
                        // hillsmith's row.w %*% w is a BLAS dgemv: a plain double dot product
                        c1 += ind * lw[i]
                    }
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
            cnt[v] = nl
        } else {
            var nlev = 0usize
            if kd == 2.0f64 { nlev = mix_levels(x, n, nv, v) }
            let nc = mix_cols(kd, nlev)
            if nc == 0usize { ret (zero, Malformed) }
            i = 0usize
            while i < n {
                wv[i] = x[i * nv + v]
                // as.numeric of an ordered factor counts from 1, and the shift changes poly's rounding
                if kd == 2.0f64 { wv[i] += 1.0f64 }
                i += 1usize
            }
            let pe = mix_poly(a, wv, n, nc, t, total, col)
            if pe != ok { ret (zero, Malformed) }
            var c = 0usize
            while c < nc {
                cw[col + c] = 1.0f64
                c += 1usize
            }
            cnt[v] = nc
            col += nc
        }
        v += 1usize
    }
    ret (MixTab { t: t, lw: lw, cw: cw, total: total, cnt: cnt }, ok)
}

// dudi.mix on variables of four kinds (kinds[v]): 0 quantitative (standardised with the population standard deviation), 1 unordered factor (0-based codes,
// every level present: dudi.acm disjunctive columns divided by their weights minus one), 2 ordered factor (sqrt(n - 1) times poly of the level numbers, degree
// min(levels - 1, 2)) and 3 quantitative with add.square = TRUE (degree 2 poly of the values). Row weights 1 / n, column weights 1 except for factor levels,
// which carry their frequency.
fn dudi_mix(a: *mem.Arena, x: []const f64, kinds: []const f64, n: usize, nv: usize, nf: usize) -> (Dudi, err) {
    let (u, eu) = mem.alloc[f64](a, n)
    if eu != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        u[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    let (m, em) = mix_table(a, x, kinds, n, nv, u, true)
    if em != ok { ret (zero, Malformed) }
    let (d, ed) = as_dudi(a, m.t, n, m.total, m.lw, m.cw, nf, 0.0000001f64)
    ret (d, ed)
}

// dudi.hillsmith: dudi.mix restricted to quantitative (0) and unordered factor (1) variables with row weights rw0 (rescaled to sum to one)
fn dudi_hillsmith(a: *mem.Arena, x: []const f64, kinds: []const f64, n: usize, nv: usize, rw0: []const f64, nf: usize) -> (Dudi, err) {
    let (u, eu) = mem.alloc[f64](a, n)
    if eu != ok { ret (zero, Malformed) }
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        let (q1, q2) = nstep(s1, s2, rw0[i])
        s1 = q1
        s2 = q2
        i += 1usize
    }
    let st = s1 + s2
    i = 0usize
    while i < n {
        u[i] = rw0[i] / st
        i += 1usize
    }
    let (m, em) = mix_table(a, x, kinds, n, nv, u, false)
    if em != ok { ret (zero, Malformed) }
    let (d, ed) = as_dudi(a, m.t, n, m.total, m.lw, m.cw, nf, 0.0000001f64)
    ret (d, ed)
}

// X$cr of dudi.mix, nv by d.nf row-major: a factor's correlation ratio, a quantitative or ordered variable's squared sum of the weighted products of its
// columns with l1 (per column for an ordered factor; for add.square ade4 sums both columns before squaring, which this follows)
fn mix_cr(a: *mem.Arena, x: []const f64, kinds: []const f64, n: usize, nv: usize, nf: usize, out: []f64) -> err {
    let (u, eu) = mem.alloc[f64](a, n)
    if eu != ok { ret Malformed }
    var ui = 0usize
    while ui < n {
        u[ui] = 1.0f64 / f64(n)
        ui += 1usize
    }
    let (m, em) = mix_table(a, x, kinds, n, nv, u, true)
    if em != ok { ret Malformed }
    let (d, ed) = as_dudi(a, m.t, n, m.total, m.lw, m.cw, nf, 0.0000001f64)
    if ed != ok { ret ed }
    var col = 0usize
    var v = 0usize
    while v < nv {
        var k = 0usize
        while k < d.nf {
            if kinds[v] == 1.0f64 {
                let nl = m.cnt[v]
                var tot = 0.0f64
                var l = 0usize
                while l < nl {
                    var p1 = 0.0f64
                    var p2 = 0.0f64
                    var z1 = 0.0f64
                    var z2 = 0.0f64
                    var i = 0usize
                    while i < n {
                        if usize(x[i * nv + v]) == l {
                            let (u1, u2) = nstep(p1, p2, m.lw[i])
                            p1 = u1
                            p2 = u2
                            let (w1, w2) = nstep(z1, z2, d.l1[i * d.nf + k] * m.lw[i])
                            z1 = w1
                            z2 = w2
                        }
                        i += 1usize
                    }
                    let poi = p1 + p2
                    let z = (z1 + z2) / poi
                    tot += poi * z * z
                    l += 1usize
                }
                out[v * d.nf + k] = tot
            } else {
                var all1 = 0.0f64
                var all2 = 0.0f64
                var sq = 0.0f64
                var c = 0usize
                while c < m.cnt[v] {
                    var s1 = 0.0f64
                    var s2 = 0.0f64
                    var i = 0usize
                    while i < n {
                        let (u1, u2) = nstep(s1, s2, m.t[i * m.total + col + c] * (m.lw[i] * d.l1[i * d.nf + k]))
                        s1 = u1
                        s2 = u2
                        i += 1usize
                    }
                    let cs = s1 + s2
                    sq += cs * cs
                    let (b1, b2) = nstep(all1, all2, cs)
                    all1 = b1
                    all2 = b2
                    c += 1usize
                }
                let al = all1 + all2
                if kinds[v] == 2.0f64 { out[v * d.nf + k] = sq } else { out[v * d.nf + k] = al * al }
            }
            k += 1usize
        }
        col += m.cnt[v]
        v += 1usize
    }
    ret ok
}

// prep.fuzzy.var on the n by p row-major table x whose columns form consecutive blocks of the sizes in blocks (each at least two): every row of a block is
// divided by its sum (a zero row stays zero), the row weights are normalised, a block's column frequencies are the weighted means of its rows (rows of zero
// marginal weight take them); tab (n by p), roww (n) and colw (p, the "col.freq" attribute) are written.
fn prep_fuzzy_var(a: *mem.Arena, x: []const f64, n: usize, p: usize, blocks: []const f64, rw: []const f64, tab: []f64, roww: []f64, colw: []f64) -> err {
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        let (u1, u2) = nstep(s1, s2, rw[i])
        s1 = u1
        s2 = u2
        i += 1usize
    }
    let rs = s1 + s2
    i = 0usize
    while i < n {
        roww[i] = rw[i] / rs
        i += 1usize
    }
    let (mg, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret Malformed }
    var k1 = 0usize
    var b = 0usize
    while b < blocks.len {
        let k = usize(blocks[b])
        if k < 2usize || k1 + k > p { ret Malformed }
        i = 0usize
        while i < n {
            var r1 = 0.0f64
            var r2 = 0.0f64
            var j = 0usize
            while j < k {
                let (u1, u2) = nstep(r1, r2, x[i * p + k1 + j])
                r1 = u1
                r2 = u2
                j += 1usize
            }
            let tot = r1 + r2
            j = 0usize
            while j < k {
                if tot == 0.0f64 { tab[i * p + k1 + j] = 0.0f64 } else { tab[i * p + k1 + j] = x[i * p + k1 + j] / tot }
                j += 1usize
            }
            var m1 = 0.0f64
            var m2 = 0.0f64
            j = 0usize
            while j < k {
                let (u1, u2) = nstep(m1, m2, tab[i * p + k1 + j])
                m1 = u1
                m2 = u2
                j += 1usize
            }
            mg[i] = (m1 + m2) * roww[i]
            i += 1usize
        }
        var g1 = 0.0f64
        var g2 = 0.0f64
        i = 0usize
        while i < n {
            let (u1, u2) = nstep(g1, g2, mg[i])
            g1 = u1
            g2 = u2
            i += 1usize
        }
        let gs0 = g1 + g2
        i = 0usize
        while i < n {
            mg[i] = mg[i] / gs0
            i += 1usize
        }
        var j = 0usize
        while j < k {
            var c1 = 0.0f64
            var c2 = 0.0f64
            i = 0usize
            while i < n {
                let (u1, u2) = nstep(c1, c2, tab[i * p + k1 + j] * mg[i])
                c1 = u1
                c2 = u2
                i += 1usize
            }
            colw[k1 + j] = c1 + c2
            j += 1usize
        }
        i = 0usize
        while i < n {
            if mg[i] == 0.0f64 {
                j = 0usize
                while j < k {
                    tab[i * p + k1 + j] = colw[k1 + j]
                    j += 1usize
                }
            }
            i += 1usize
        }
        k1 += k
        b += 1usize
    }
    if k1 != p { ret Malformed }
    ret ok
}

// dudi.fpca: dudi.pca of the prepared fuzzy table with its row weights, centred, not scaled, column weights 1 / (the block size)
fn dudi_fpca(a: *mem.Arena, x: []const f64, n: usize, p: usize, blocks: []const f64, rw: []const f64, nf: usize) -> (Dudi, err) {
    let (t0, e1) = mem.alloc[f64](a, n * p)
    let (r0, e2) = mem.alloc[f64](a, n)
    let (c0, e3) = mem.alloc[f64](a, p)
    let (t, e4) = mem.alloc[f64](a, n * p)
    let (cw, e5) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, Malformed) }
    let pe = prep_fuzzy_var(a, x, n, p, blocks, rw, t0, r0, c0)
    if pe != ok { ret (zero, Malformed) }
    pca_prep_w(a, t0, n, p, true, false, t, r0, cw)
    var k1 = 0usize
    var b = 0usize
    while b < blocks.len {
        let k = usize(blocks[b])
        var j = 0usize
        while j < k {
            cw[k1 + j] = 1.0f64 / f64(k)
            j += 1usize
        }
        k1 += k
        b += 1usize
    }
    let (d, ed) = as_dudi(a, t, n, p, r0, cw, nf, 0.0000001f64)
    ret (d, ed)
}

// dudi.pco on the n by n distance matrix dm (full, symmetric) with row weights rw0 (rescaled to sum to one). The Dudi has rank columns in c1 (the identity
// part) and co (sqrt(eig) on the diagonal) with nf axes; tab is the n by rank table of principal coordinates.
type Pco = struct { d: Dudi, tab: []f64 }

fn dudi_pco(a: *mem.Arena, dm: []const f64, n: usize, rw0: []const f64, nf0: usize) -> (Pco, err) {
    var out: Pco = zero
    let (rw, e1) = mem.alloc[f64](a, n)
    let (sq, e2) = mem.alloc[f64](a, n)
    let (bw, e14) = mem.alloc[f64](a, n)
    let (dl, e3) = mem.alloc[f64](a, n * n)
    let (rm, e4) = mem.alloc[f64](a, n)
    let (cm, e5) = mem.alloc[f64](a, n)
    let (w, e6) = mem.alloc[f64](a, n)
    let (z, e7) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e14 != ok { ret (out, Malformed) }
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        let (q1, q2) = nstep(s1, s2, rw0[i])
        s1 = q1
        s2 = q2
        i += 1usize
    }
    let st = s1 + s2
    i = 0usize
    while i < n {
        rw[i] = rw0[i] / st
        sq[i] = math.sqrt[f64](rw[i])
        i += 1usize
    }
    // bicenter.wt renormalises its weights by their sum once more, which is not exactly 1
    var u1 = 0.0f64
    var u2 = 0.0f64
    i = 0usize
    while i < n {
        let (q1, q2) = nstep(u1, u2, rw[i])
        u1 = q1
        u2 = q2
        i += 1usize
    }
    let sr = u1 + u2
    i = 0usize
    while i < n {
        bw[i] = rw[i] / sr
        i += 1usize
    }
    // bicenter.wt: row.mean[j] = sum_i rw[i] X[i, j], col.mean[i] = sum_j rw[j] X[i, j] - sum_j row.mean[j] rw[j]
    var j = 0usize
    while j < n {
        var a1 = 0.0f64
        var a2 = 0.0f64
        i = 0usize
        while i < n {
            let (q1, q2) = nstep(a1, a2, bw[i] * (dm[i * n + j] * dm[i * n + j]))
            a1 = q1
            a2 = q2
            i += 1usize
        }
        rm[j] = a1 + a2
        j += 1usize
    }
    var t1 = 0.0f64
    var t2 = 0.0f64
    j = 0usize
    while j < n {
        let (q1, q2) = nstep(t1, t2, rm[j] * bw[j])
        t1 = q1
        t2 = q2
        j += 1usize
    }
    let corr = t1 + t2
    i = 0usize
    while i < n {
        var b1 = 0.0f64
        var b2 = 0.0f64
        j = 0usize
        while j < n {
            let (q1, q2) = nstep(b1, b2, bw[j] * (dm[i * n + j] * dm[i * n + j]))
            b1 = q1
            b2 = q2
            j += 1usize
        }
        cm[i] = (b1 + b2) - corr
        i += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            let x = (dm[i * n + j] * dm[i * n + j] - rm[j]) - cm[i]
            // stored transposed: delta is not exactly symmetric and dsyevr reads the column-major lower triangle, as R does
            dl[j * n + i] =((-0.5f64 * x) * sq[i]) * sq[j]
            j += 1usize
        }
        i += 1usize
    }
    let ee = sy.dsyevr_all(a, dl, n, w, z)
    if ee != ok { ret (out, ee) }
    let (lam, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret (out, Malformed) }
    var k = 0usize
    while k < n {
        lam[k] = w[n - 1usize - k]
        k += 1usize
    }
    var r = 0usize
    k = 0usize
    while k < n {
        if lam[k] > lam[0usize] * 0.0000001f64 { r += 1usize }
        k += 1usize
    }
    var nf = nf0
    if nf == 0usize { nf = 2usize }
    if nf > r { nf = r }
    let (tab, e9) = mem.alloc[f64](a, n * r)
    let (li, e10) = mem.alloc[f64](a, n * nf)
    let (l1, e11) = mem.alloc[f64](a, n * nf)
    let (c1, e12) = mem.alloc[f64](a, r * nf)
    let (co, e13) = mem.alloc[f64](a, r * nf)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (out, Malformed) }
    k = 0usize
    while k < r {
        i = 0usize
        while i < n {
            tab[i * r + k] = (z[(n - 1usize - k) * n + i] * math.sqrt[f64](lam[k])) / sq[i]
            i += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < r * nf {
        c1[k] = 0.0f64
        co[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < nf {
        i = 0usize
        while i < n {
            li[i * nf + k] = tab[i * r + k]
            l1[i * nf + k] = z[(n - 1usize - k) * n + i] / sq[i]
            i += 1usize
        }
        c1[k * nf + k] = 1.0f64
        co[k * nf + k] = math.sqrt[f64](lam[k])
        k += 1usize
    }
    out.d.rank = r
    out.d.nf = nf
    out.d.eig = lam[0usize..r]
    out.d.c1 = c1
    out.d.co = co
    out.d.li = li
    out.d.l1 = l1
    out.tab = tab
    ret (out, ok)
}

// prep.binary: the n by p table of presences (x > 0) in blocks of columns; a row with no presence in a block gets NaN there (R's NA)
fn prep_binary(x: []const f64, n: usize, p: usize, blocks: []const f64, out: []f64) {
    var k1 = 0usize
    var b = 0usize
    while b < blocks.len {
        let k2 = k1 + usize(blocks[b])
        var i = 0usize
        while i < n {
            var cnt = 0usize
            var j = k1
            while j < k2 {
                if x[i * p + j] > 0.0f64 { cnt += 1usize }
                j += 1usize
            }
            j = k1
            while j < k2 {
                var v = 0.0f64
                if cnt == 0usize { v = 0.0f64 / 0.0f64 } else if x[i * p + j] > 0.0f64 { v = 1.0f64 }
                out[i * p + j] = v
                j += 1usize
            }
            i += 1usize
        }
        k1 = k2
        b += 1usize
    }
}

// prep.circular: the table minus the column minima rmin, and the attribute max = rmax - rmin + 1
fn prep_circular(x: []const f64, n: usize, p: usize, rmin: []const f64, rmax: []const f64, out: []f64, mx: []f64) {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            out[i * p + j] = x[i * p + j] - rmin[j]
            i += 1usize
        }
        mx[j] = (rmax[j] - rmin[j]) + 1.0f64
        j += 1usize
    }
}
