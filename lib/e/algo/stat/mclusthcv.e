// R mclust: hc for the VVV model, a statement-for-statement port of the Fortran hcvvv with its QR-factor storage.
//
// The Fortran keeps the triangular factor of every cluster inside the data matrix and rewrites it in place; the criterion of later merges reads those rows back, so the
// port keeps the same storage (indices are the Fortran ones, one-based, through the helper offsets). Only the singleton starting partition is supported.

use e.math
use e.mem

fn xo(n: usize, i: usize, j: usize) -> usize { ret (j - 1usize) * n + (i - 1usize) }

fn dcopy_s(cnt: usize, src: []const f64, so: usize, si: usize, dst: []f64, dof: usize, di: usize) {
    var t = 0usize
    while t < cnt {
        dst[dof + t * di] = src[so + t * si]
        t += 1usize
    }
}

fn dscal_s(cnt: usize, alpha: f64, x: []f64, xof: usize, xi: usize) {
    var t = 0usize
    while t < cnt {
        x[xof + t * xi] = alpha * x[xof + t * xi]
        t += 1usize
    }
}

fn daxpy_s(cnt: usize, alpha: f64, x: []const f64, xof: usize, xi: usize, y: []f64, yof: usize, yi: usize) {
    var t = 0usize
    while t < cnt {
        y[yof + t * yi] = y[yof + t * yi] + alpha * x[xof + t * xi]
        t += 1usize
    }
}

fn ddot_s(cnt: usize, x: []const f64, xof: usize, xi: usize, y: []const f64, yof: usize, yi: usize) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < cnt {
        s += x[xof + t * xi] * y[yof + t * yi]
        t += 1usize
    }
    ret s
}

// the rotation of reference BLAS 3.12 drotg: returns (c, s, r)
fn rotg(f: f64, g: f64) -> (f64, f64, f64) {
    if g == 0.0f64 { ret (1.0f64, 0.0f64, f) }
    if f == 0.0f64 {
        var sg = 1.0f64
        if g < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        ret (0.0f64, sg, math.abs[f64](g))
    }
    let d = math.sqrt[f64](f * f + g * g)
    var r = d
    if f < 0.0f64 { r = 0.0f64 - d }
    ret (math.abs[f64](f) / d, g / r, r)
}

fn drot_s(cnt: usize, xs: []f64, xof: usize, xi: usize, ys: []f64, yof: usize, yi: usize, c: f64, s: f64) {
    var t = 0usize
    while t < cnt {
        let xv = xs[xof + t * xi]
        let yv = ys[yof + t * yi]
        xs[xof + t * xi] = c * xv + s * yv
        ys[yof + t * yi] = c * yv - s * xv
        t += 1usize
    }
}

// mclrup(l, n, v, r, lr) with r starting at offset ro of the array rr
fn mclrup(l: usize, n: usize, v: []f64, rr: []f64, ro: usize, lr: usize) {
    if l == 1usize { ret }
    let k = l - 1usize
    if k <= n {
        var t = 0usize
        while t < n {
            rr[ro + t * lr + (k - 1usize)] = v[t]
            t += 1usize
        }
        if k == 1usize { ret }
        if n > 1usize {
            var i = 1usize
            var m = n
            var j = 2usize
            while j <= k {
                let ia = ro + (i - 1usize) * lr + (i - 1usize)
                let ib = ro + (i - 1usize) * lr + (k - 1usize)
                let (c, s, r) = rotg(rr[ia], rr[ib])
                rr[ia] = r
                rr[ib] = 0.0f64
                m -= 1usize
                drot_s(m, rr, ro + (j - 1usize) * lr + (i - 1usize), lr, rr, ro + (j - 1usize) * lr + (k - 1usize), lr, c, s)
                i = j
                j += 1usize
            }
        } else {
            let (c, s, r) = rotg(rr[ro], rr[ro + (k - 1usize)])
            rr[ro] = r
            rr[ro + (k - 1usize)] = 0.0f64
        }
    } else {
        if n > 1usize {
            var i = 1usize
            var m = n
            var j = 2usize
            while j <= n {
                let ia = ro + (i - 1usize) * lr + (i - 1usize)
                let (c, s, r) = rotg(rr[ia], v[i - 1usize])
                rr[ia] = r
                v[i - 1usize] = 0.0f64
                m -= 1usize
                drot_s(m, rr, ro + (j - 1usize) * lr + (i - 1usize), lr, v, j - 1usize, 1usize, c, s)
                i = j
                j += 1usize
            }
        }
        let ia = ro + (n - 1usize) * lr + (n - 1usize)
        let (c, s, r) = rotg(rr[ia], v[n - 1usize])
        rr[ia] = r
        v[n - 1usize] = 0.0f64
    }
}

fn det2mc(p: usize, r: []const f64, s: f64) -> f64 {
    var det = 0.0f64
    var k = 0usize
    while k < p {
        let q = r[k * p + k] * s
        if math.abs[f64](q) <= 0.0f64 { ret 0.0f64 - 1.7976931348623157e308f64 }
        det += math.log[f64](math.abs[f64](q))
        k += 1usize
    }
    ret 2.0f64 * det
}

fn vvvtij(l: usize, p: usize, r: []const f64, s: f64, trac: f64, alpha: f64, beta: f64) -> f64 {
    let ll = f64(l)
    var v = 0.0f64
    if l <= p {
        v = math.log[f64](beta * (trac + alpha) / ll)
    } else if trac == 0.0f64 {
        v = math.log[f64]((alpha * beta) / ll)
    } else {
        let detlog = det2mc(p, r, s)
        if detlog == 0.0f64 - 1.7976931348623157e308f64 {
            v = math.log[f64](beta * (trac + alpha) / ll)
        } else if detlog <= 0.0f64 {
            v = math.log[f64](math.exp[f64](detlog) + beta * (trac + alpha) / ll)
        } else {
            v = math.log[f64](1.0f64 + math.exp[f64](0.0f64 - detlog) * (beta * (trac + alpha) / ll)) + detlog
        }
    }
    ret ll * v
}

fn wardsw(i: usize, nn: usize, d: []f64) {
    let i1 = i - 1usize
    var ii = (i1 * (i1 - 1usize)) / 2usize + 1usize
    let n1 = nn - 1usize
    var nx = (n1 * (n1 - 1usize)) / 2usize + 1usize
    var t = 0usize
    while t < i1 {
        let tmp = d[nx - 1usize + t]
        d[nx - 1usize + t] = d[ii - 1usize + t]
        d[ii - 1usize + t] = tmp
        t += 1usize
    }
    ii = ii + i1 + i1
    nx = nx + i
    if n1 == i { ret }
    var k = i
    var again = true
    while again {
        let tmp = d[ii - 1usize]
        d[ii - 1usize] = d[nx - 1usize]
        d[nx - 1usize] = tmp
        ii = ii + k
        nx = nx + 1usize
        k += 1usize
        again = k < n1
    }
}

// the pair evaluated for the merge of position j (cluster j) with position iold in the second and third scans needs the same pieces; the whole algorithm is one function.
// xin is n by p; out holds the merges as 2 (n - 1) one-based observation numbers (smaller name first); alpha_mult and beta are the arguments of hc.
fn hc_vvv(a: *mem.Arena, xin: []const f64, n: usize, p: usize, alpha_mult: f64, beta: f64, out: []usize) -> err {
    let ng = n
    let ns = n - 1usize
    var ll = (ng * (ng - 1usize)) / 2usize + 1usize
    var nd = n
    if ll > nd { nd = ll }
    if 3usize * ns > nd { nd = 3usize * ns }
    let (x, e1) = mem.alloc[f64](a, n * (p + 1usize))
    let (ic, e2) = mem.alloc[usize](a, n + 1usize)
    let (d, e3) = mem.alloc[f64](a, nd)
    let (v, e4) = mem.alloc[f64](a, p)
    let (u, e5) = mem.alloc[f64](a, p * p)
    let (s, e6) = mem.alloc[f64](a, p * p)
    let (r, e7) = mem.alloc[f64](a, p * p)
    let (ri_, e8) = mem.alloc[usize](a, ns + 1usize)
    let (rj_, e9) = mem.alloc[usize](a, ns + 1usize)
    let (lab, e10) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    if ng == 1usize { ret ok }
    let pp1 = p + 1usize
    let psq = p * p
    var q = 0usize
    while q < n * pp1 {
        x[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < nd {
        d[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < p * p {
        u[q] = 0.0f64
        s[q] = 0.0f64
        r[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < p {
        v[q] = 0.0f64
        q += 1usize
    }
    var j = 1usize
    while j <= p {
        var i = 1usize
        while i <= n {
            x[xo(n, i, j)] = xin[(j - 1usize) * n + (i - 1usize)]
            i += 1usize
        }
        j += 1usize
    }
    // alpha * traceW(data / sqrt(n p))
    var tw = 0.0f64
    j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += xin[j * n + i]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            let dd = xin[j * n + i] - m
            tw += dd * dd
            i += 1usize
        }
        j += 1usize
    }
    var alpha = alpha_mult * tw / (f64(n) * f64(p))
    if alpha < 2.220446049250313e-16f64 { alpha = 2.220446049250313e-16f64 }
    let ablog = math.log[f64](beta * alpha)
    let rthalf = 0.7071067811865476f64
    let flmax = 1.7976931348623157e308f64
    var lg = ng
    var ld = (ng * (ng - 1usize)) / 2usize
    var lo = nd
    var k = 1usize
    while k <= ng {
        ic[k] = 1usize
        k += 1usize
    }
    var iopt = 0usize
    var jopt = 0usize
    var niop = 0usize
    var njop = 0usize
    var nopt = 0usize
    var tmop = 0.0f64
    var trop = 0.0f64
    var siop = 0.0f64
    var sjop = 0.0f64
    var dopt = flmax
    var ij = 0usize
    var ni = 1usize
    var nj = 1usize
    var nij = 0usize
    var ici = 0usize
    var icj = 0usize
    var l = 0usize
    var m = 0usize
    var trcij = 0.0f64
    var trmij = 0.0f64
    var traci = 0.0f64
    var tracj = 0.0f64
    var termi = 0.0f64
    var termj = 0.0f64
    var si = 0.0f64
    var sj = 0.0f64
    var sij = 0.0f64
    var qi = 0.0f64
    var qj = 0.0f64
    var qij = 0.0f64
    var rj = 0.0f64
    var rij = 0.0f64
    var rni = 0.0f64
    var dij = 0.0f64
    // the first scan over every pair of positions
    j = 2usize
    while j <= ng {
        icj = ic[j]
        nj = 1usize
        if icj == 1usize {
            tracj = 0.0f64
            termj = ablog
            var i = 1usize
            while i <= j - 1usize {
                ni = 1usize
                ici = ic[i]
                if ici == 1usize {
                    nij = 2usize
                    rij = 2.0f64
                    si = rthalf
                    sj = rthalf
                    sij = rthalf
                    dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - 1.0f64, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, rthalf, v, 0usize, 1usize)
                    trcij = ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    dcopy_s(p, v, 0usize, 1usize, u, 0usize, p)
                    trmij = 2.0f64 * math.log[f64](beta * (trcij + alpha) / 2.0f64)
                    termi = ablog
                } else {
                    m = p
                    l = ici
                    var again = true
                    while again {
                        dcopy_s(m, x, xo(n, l, ni), n, u, (ni - 1usize) * p + (ni - 1usize), p)
                        ni += 1usize
                        m -= 1usize
                        l = ic[l]
                        again = l <= n
                    }
                    ni = l - n
                    traci = x[xo(n, i, pp1)]
                    termi = x[xo(n, ic[i], pp1)]
                    let ri = f64(ni)
                    nij = ni + 1usize
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = ri * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qij)
                    sij = sj
                    dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, sj, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    trcij = traci + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    mclrup(nij, p, v, u, 0usize, p)
                    trmij = vvvtij(nij, p, u, sij, trcij, alpha, beta)
                }
                dij = trmij - (termi + termj)
                ij += 1usize
                d[ij - 1usize] = dij
                if dij <= dopt {
                    dopt = dij
                    trop = trcij
                    tmop = trmij
                    nopt = nij
                    niop = ni
                    njop = nj
                    siop = si
                    sjop = sj
                    iopt = i
                    jopt = j
                    m = p
                    k = 1usize
                    while k <= nij - 1usize && k <= p {
                        dcopy_s(m, u, (k - 1usize) * p + (k - 1usize), p, r, (k - 1usize) * p + (k - 1usize), p)
                        m -= 1usize
                        k += 1usize
                    }
                }
                i += 1usize
            }
        } else {
            m = p
            l = icj
            var again = true
            while again {
                dcopy_s(m, x, xo(n, l, nj), n, s, (nj - 1usize) * p + (nj - 1usize), p)
                nj += 1usize
                m -= 1usize
                l = ic[l]
                again = l <= n
            }
            nj = l - n
            tracj = x[xo(n, j, pp1)]
            termj = x[xo(n, ic[j], pp1)]
            rj = f64(nj)
            var i = 1usize
            while i <= j - 1usize {
                m = p
                k = 1usize
                while k <= nj - 1usize && k <= p {
                    dcopy_s(m, s, (k - 1usize) * p + (k - 1usize), p, u, (k - 1usize) * p + (k - 1usize), p)
                    m -= 1usize
                    k += 1usize
                }
                ni = 1usize
                ici = ic[i]
                if ici == 1usize {
                    nij = nj + 1usize
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = qij
                    qj = rj * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qj)
                    sij = math.sqrt[f64](qij)
                    dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, sj, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    trcij = tracj + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    termi = ablog
                } else {
                    m = p
                    l = ici
                    k = nj + 1usize
                    var again2 = true
                    while again2 {
                        dcopy_s(m, x, xo(n, l, ni), n, v, 0usize, 1usize)
                        mclrup(k, m, v, u, (ni - 1usize) * p + (ni - 1usize), p)
                        ni += 1usize
                        m -= 1usize
                        l = ic[l]
                        again2 = l <= n
                    }
                    ni = l - n
                    traci = x[xo(n, i, pp1)]
                    termi = x[xo(n, ic[i], pp1)]
                    let ri = f64(ni)
                    nij = ni + nj
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = ri * qij
                    qj = rj * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qj)
                    sij = math.sqrt[f64](qij)
                    dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, sj, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    trcij = (traci + tracj) + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                }
                mclrup(nij, p, v, u, 0usize, p)
                trmij = vvvtij(nij, p, u, sij, trcij, alpha, beta)
                dij = trmij - (termi + termj)
                ij += 1usize
                d[ij - 1usize] = dij
                if dij <= dopt {
                    dopt = dij
                    trop = trcij
                    tmop = trmij
                    nopt = nij
                    niop = ni
                    njop = nj
                    siop = si
                    sjop = sj
                    iopt = i
                    jopt = j
                    m = p
                    k = 1usize
                    while k <= nij - 1usize && k <= p {
                        dcopy_s(m, u, (k - 1usize) * p + (k - 1usize), p, r, (k - 1usize) * p + (k - 1usize), p)
                        m -= 1usize
                        k += 1usize
                    }
                }
                i += 1usize
            }
        }
        j += 1usize
    }
    var ls = 1usize
    var done = false
    var iold = 0usize
    if ns == 1usize { done = true }
    while !done {
        // label 200: merge the optimal pair
        ri_[ls] = iopt
        rj_[ls] = jopt
        dcopy_s(p, x, xo(n, iopt, 1usize), n, v, 0usize, 1usize)
        dscal_s(p, siop, v, 0usize, 1usize)
        daxpy_s(p, sjop, x, xo(n, jopt, 1usize), n, v, 0usize, 1usize)
        if jopt != lg {
            wardsw(jopt, lg, d)
            dcopy_s(p, x, xo(n, lg, 1usize), n, x, xo(n, jopt, 1usize), n)
            m = ic[jopt]
            icj = ic[lg]
            if icj != 1usize { x[xo(n, jopt, pp1)] = x[xo(n, lg, pp1)] }
            ic[jopt] = icj
            ic[lg] = m
        }
        if niop == 1usize {
            ic[iopt] = lg
        } else {
            l = ic[iopt]
            k = 1usize
            while k <= niop - 1usize && k <= p {
                m = l
                l = ic[l]
                k += 1usize
            }
            ic[m] = lg
        }
        l = ic[iopt]
        k = 1usize
        while k <= nopt - 1usize && k <= p {
            dcopy_s(p, r, 0usize, p, x, xo(n, l, 1usize), n)
            m = l
            l = ic[l]
            k += 1usize
        }
        ic[m] = nopt + n
        x[xo(n, iopt, pp1)] = 0.0f64
        if nopt >= 2usize {
            x[xo(n, iopt, pp1)] = trop
            x[xo(n, ic[iopt], pp1)] = tmop
        }
        dcopy_s(p, v, 0usize, 1usize, x, xo(n, iopt, 1usize), n)
        lo -= 3usize
        lg -= 1usize
        ld = ld - lg
        iold = iopt
        dopt = flmax
        ni = nopt
        let ri = f64(ni)
        rni = ri
        termi = tmop
        traci = trop
        ij = 0usize
        if iold > 1usize {
            ij = ((iold - 1usize) * (iold - 2usize)) / 2usize
            j = 1usize
            while j <= iold - 1usize {
                q = 0usize
                while q < psq {
                    u[q] = 0.0f64
                    q += 1usize
                }
                m = p
                k = 1usize
                while k <= ni - 1usize && k <= p {
                    dcopy_s(m, r, (k - 1usize) * p + (k - 1usize), p, u, (k - 1usize) * p + (k - 1usize), p)
                    m -= 1usize
                    k += 1usize
                }
                nj = 1usize
                icj = ic[j]
                if icj == 1usize {
                    nij = ni + 1usize
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = rni * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qij)
                    sij = sj
                    dcopy_s(p, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, si, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - sj, x, xo(n, iold, 1usize), n, v, 0usize, 1usize)
                    trcij = traci + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    tracj = 0.0f64
                    termj = ablog
                } else {
                    m = p
                    l = icj
                    k = ni + 1usize
                    var again = true
                    while again {
                        dcopy_s(m, x, xo(n, l, nj), n, v, 0usize, 1usize)
                        mclrup(k, m, v, u, (nj - 1usize) * p + (nj - 1usize), p)
                        k += 1usize
                        nj += 1usize
                        m -= 1usize
                        l = ic[l]
                        again = l <= n
                    }
                    nj = l - n
                    tracj = x[xo(n, j, pp1)]
                    termj = x[xo(n, ic[j], pp1)]
                    rj = f64(nj)
                    nij = ni + nj
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = rni * qij
                    qj = rj * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qj)
                    sij = math.sqrt[f64](qij)
                    dcopy_s(p, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, si, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - sj, x, xo(n, iold, 1usize), n, v, 0usize, 1usize)
                    trcij = (traci + tracj) + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                }
                mclrup(nij, p, v, u, 0usize, p)
                trmij = vvvtij(nij, p, u, sij, trcij, alpha, beta)
                dij = trmij - (termi + termj)
                ij += 1usize
                d[ij - 1usize] = dij
                if dij <= dopt {
                    dopt = dij
                    trop = trcij
                    tmop = trmij
                    nopt = nij
                    niop = nj
                    njop = ni
                    siop = sj
                    sjop = si
                    iopt = j
                    jopt = iold
                    m = p
                    k = 1usize
                    while k <= nij - 1usize && k <= p {
                        dcopy_s(m, u, (k - 1usize) * p + (k - 1usize), p, s, (k - 1usize) * p + (k - 1usize), p)
                        m -= 1usize
                        k += 1usize
                    }
                }
                j += 1usize
            }
        }
        if iold < lg {
            var i = iold
            ij = ij + i
            j = iold + 1usize
            while j <= lg {
                q = 0usize
                while q < psq {
                    u[q] = 0.0f64
                    q += 1usize
                }
                m = p
                k = 1usize
                while k <= ni - 1usize && k <= p {
                    dcopy_s(m, r, (k - 1usize) * p + (k - 1usize), p, u, (k - 1usize) * p + (k - 1usize), p)
                    m -= 1usize
                    k += 1usize
                }
                nj = 1usize
                icj = ic[j]
                if icj == 1usize {
                    nij = ni + 1usize
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = rni * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qij)
                    sij = sj
                    dcopy_s(p, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, si, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - sj, x, xo(n, iold, 1usize), n, v, 0usize, 1usize)
                    trcij = traci + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    termj = ablog
                } else {
                    m = p
                    l = icj
                    k = ni + 1usize
                    var again = true
                    while again {
                        dcopy_s(m, x, xo(n, l, nj), n, v, 0usize, 1usize)
                        mclrup(k, m, v, u, (nj - 1usize) * p + (nj - 1usize), p)
                        k += 1usize
                        nj += 1usize
                        m -= 1usize
                        l = ic[l]
                        again = l <= n
                    }
                    nj = l - n
                    tracj = x[xo(n, j, pp1)]
                    termj = x[xo(n, ic[j], pp1)]
                    rj = f64(nj)
                    nij = ni + nj
                    rij = f64(nij)
                    qij = 1.0f64 / rij
                    qi = rni * qij
                    qj = rj * qij
                    si = math.sqrt[f64](qi)
                    sj = math.sqrt[f64](qj)
                    sij = math.sqrt[f64](qij)
                    dcopy_s(p, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                    dscal_s(p, si, v, 0usize, 1usize)
                    daxpy_s(p, 0.0f64 - sj, x, xo(n, iold, 1usize), n, v, 0usize, 1usize)
                    trcij = (traci + tracj) + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                }
                mclrup(nij, p, v, u, 0usize, p)
                trmij = vvvtij(nij, p, u, sij, trcij, alpha, beta)
                dij = trmij - (termi + termj)
                d[ij - 1usize] = dij
                ij = ij + i
                i = j
                if dij <= dopt {
                    dopt = dij
                    trop = trcij
                    tmop = trmij
                    nopt = nij
                    niop = ni
                    njop = nj
                    siop = si
                    sjop = sj
                    iopt = iold
                    jopt = j
                    m = p
                    k = 1usize
                    while k <= nij - 1usize && k <= p {
                        dcopy_s(m, u, (k - 1usize) * p + (k - 1usize), p, s, (k - 1usize) * p + (k - 1usize), p)
                        m -= 1usize
                        k += 1usize
                    }
                }
                j += 1usize
            }
        }
        jopt = 2usize
        iopt = 1usize
        dopt = d[0usize]
        if lg == 2usize {
            ls += 1usize
            done = true
        } else {
            var ijx = 1usize
            var i = 2usize
            while i <= ld {
                let qv = d[i - 1usize]
                if qv <= dopt {
                    ijx = i
                    dopt = qv
                }
                i += 1usize
            }
            if ijx > 1usize {
                i = 2usize
                while i <= ijx {
                    iopt += 1usize
                    if iopt >= jopt {
                        jopt += 1usize
                        iopt = 1usize
                    }
                    i += 1usize
                }
            }
            k = 0usize
            while k < psq {
                r[k] = 0.0f64
                k += 1usize
            }
            if iopt != iold && jopt != iold {
                i = iopt
                j = jopt
                nj = 1usize
                icj = ic[j]
                ni = 1usize
                ici = ic[i]
                if icj == 1usize {
                    termj = ablog
                    if ici == 1usize {
                        nij = 2usize
                        rij = 2.0f64
                        si = rthalf
                        sj = rthalf
                        dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                        daxpy_s(p, 0.0f64 - 1.0f64, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                        dscal_s(p, rthalf, v, 0usize, 1usize)
                        trcij = ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                        dcopy_s(p, v, 0usize, 1usize, r, 0usize, p)
                        termi = ablog
                    } else {
                        m = p
                        l = ici
                        var again = true
                        while again {
                            dcopy_s(m, x, xo(n, l, ni), n, r, (ni - 1usize) * p + (ni - 1usize), p)
                            ni += 1usize
                            m -= 1usize
                            l = ic[l]
                            again = l <= n
                        }
                        ni = l - n
                        traci = x[xo(n, i, pp1)]
                        termi = x[xo(n, ic[i], pp1)]
                        let ri2 = f64(ni)
                        nij = ni + 1usize
                        rij = f64(nij)
                        qij = 1.0f64 / rij
                        qi = ri2 * qij
                        si = math.sqrt[f64](qi)
                        sj = math.sqrt[f64](qij)
                        dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                        dscal_s(p, sj, v, 0usize, 1usize)
                        daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                        trcij = traci + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                        mclrup(nij, p, v, r, 0usize, p)
                    }
                } else {
                    m = p
                    l = icj
                    var again = true
                    while again {
                        dcopy_s(m, x, xo(n, l, nj), n, r, (nj - 1usize) * p + (nj - 1usize), p)
                        nj += 1usize
                        m -= 1usize
                        l = ic[l]
                        again = l <= n
                    }
                    nj = l - n
                    tracj = x[xo(n, j, pp1)]
                    termj = x[xo(n, ic[j], pp1)]
                    rj = f64(nj)
                    if ici == 1usize {
                        nij = nj + 1usize
                        rij = f64(nij)
                        qij = 1.0f64 / rij
                        qj = rj * qij
                        si = math.sqrt[f64](qij)
                        sj = math.sqrt[f64](qj)
                        dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                        dscal_s(p, sj, v, 0usize, 1usize)
                        daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                        trcij = tracj + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                        termi = ablog
                    } else {
                        m = p
                        l = ici
                        k = nj + 1usize
                        var again2 = true
                        while again2 {
                            dcopy_s(m, x, xo(n, l, ni), n, v, 0usize, 1usize)
                            mclrup(k, m, v, r, (ni - 1usize) * p + (ni - 1usize), p)
                            ni += 1usize
                            m -= 1usize
                            l = ic[l]
                            again2 = l <= n
                        }
                        ni = l - n
                        traci = x[xo(n, i, pp1)]
                        termi = x[xo(n, ic[i], pp1)]
                        let ri2 = f64(ni)
                        nij = ni + nj
                        rij = f64(nij)
                        qij = 1.0f64 / rij
                        qi = ri2 * qij
                        qj = rj * qij
                        si = math.sqrt[f64](qi)
                        sj = math.sqrt[f64](qj)
                        dcopy_s(p, x, xo(n, i, 1usize), n, v, 0usize, 1usize)
                        dscal_s(p, sj, v, 0usize, 1usize)
                        daxpy_s(p, 0.0f64 - si, x, xo(n, j, 1usize), n, v, 0usize, 1usize)
                        trcij = (traci + tracj) + ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    }
                    mclrup(nij, p, v, r, 0usize, p)
                }
                trop = trcij
                tmop = dopt + (termi + termj)
                nopt = nij
                niop = ni
                njop = nj
                siop = si
                sjop = sj
            } else {
                m = p
                k = 1usize
                while k <= nopt - 1usize && k <= p {
                    dcopy_s(m, s, (k - 1usize) * p + (k - 1usize), p, r, (k - 1usize) * p + (k - 1usize), p)
                    m -= 1usize
                    k += 1usize
                }
                l = ic[iopt]
                if l != 1usize {
                    while l <= n { l = ic[l] }
                    niop = l - n
                } else {
                    niop = 1usize
                }
                l = ic[jopt]
                if l != 1usize {
                    while l <= n { l = ic[l] }
                    njop = l - n
                } else {
                    njop = 1usize
                }
                nopt = niop + njop
            }
            ls += 1usize
            if ls == ns { done = true }
        }
    }
    // the last merge
    ri_[ls] = iopt
    rj_[ls] = jopt
    // decode positions into cluster names (smallest member)
    var pos = 1usize
    while pos <= n {
        lab[pos] = pos
        pos += 1usize
    }
    var last = n
    var st = 1usize
    while st <= ns {
        let pi = ri_[st]
        let pj = rj_[st]
        var lo2 = lab[pi]
        var hi2 = lab[pj]
        if hi2 < lo2 {
            let t = lo2
            lo2 = hi2
            hi2 = t
        }
        out[2usize * (st - 1usize)] = lo2
        out[2usize * (st - 1usize) + 1usize] = hi2
        lab[pi] = lo2
        lab[pj] = lab[last]
        last -= 1usize
        st += 1usize
    }
    ret ok
}
