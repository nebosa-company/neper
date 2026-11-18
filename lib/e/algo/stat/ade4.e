// The duality diagrams of the R package ade4: as.dudi (the generalised principal-axes analysis of a table with row and column weights) and the
// analyses built on it, dudi.pca and dudi.coa. The eigenvectors are LAPACK's (e.algo.linalg.lapack_syevr), so their signs are the ones R's eigen returns.

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

// dudi.pca: row weights 1 / n, column weights 1; centre and scale (the population standard deviation, a norm below 1e-8 is taken as 1) as asked
fn dudi_pca(a: *mem.Arena, x: []const f64, n: usize, p: usize, center: bool, scale: bool, nf: usize) -> (Dudi, err) {
    let (t, e1) = mem.alloc[f64](a, n * p)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        lw[i] = 1.0f64 / f64(n)
        i += 1usize
    }
    var j = 0usize
    while j < p {
        cw[j] = 1.0f64
        var mu = 0.0f64
        if center {
            i = 0usize
            while i < n {
                mu += x[i * p + j] * lw[i]
                i += 1usize
            }
        }
        var ss = 0.0f64
        i = 0usize
        while i < n {
            t[i * p + j] = x[i * p + j] - mu
            ss += t[i * p + j] * t[i * p + j] * lw[i]
            i += 1usize
        }
        if scale {
            var nm = math.sqrt[f64](ss)
            if nm < 0.00000001f64 { nm = 1.0f64 }
            i = 0usize
            while i < n {
                t[i * p + j] = t[i * p + j] / nm
                i += 1usize
            }
        }
        j += 1usize
    }
    let (d, ed) = as_dudi(a, t, n, p, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
}

// dudi.coa: the correspondence analysis of a table of non-negative counts
fn dudi_coa(a: *mem.Arena, x: []const f64, n: usize, p: usize, nf: usize) -> (Dudi, err) {
    let (t, e1) = mem.alloc[f64](a, n * p)
    let (lw, e2) = mem.alloc[f64](a, n)
    let (cw, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    var tot = 0.0f64
    var i = 0usize
    while i < n * p {
        if x[i] < 0.0f64 { ret (zero, Malformed) }
        tot += x[i]
        i += 1usize
    }
    if tot == 0.0f64 { ret (zero, Malformed) }
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
    let (d, ed) = as_dudi(a, t, n, p, lw, cw, nf, 0.0000001f64)
    ret (d, ed)
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
