// R mclust: hc for the EEE model, a statement-for-statement port of the Fortran hceee (trace phase, trace plus determinant phase, determinant phase) with an initial partition.
//
// Indices are the Fortran ones (one-based, through xo). The initial partition ic0 holds one-based group numbers in order of first appearance (dupPartition / partconv),
// ng is the number of groups; out receives 2 (ng - 1) merge entries (the group names, smaller first) the way unclass(hc) shows them column by column.
// p must be at least 2.

use e.math
use e.mem
use e.algo.stat.mclusthcv as hv

fn swap_rows(x: []f64, n: usize, p: usize, a: usize, b: usize) {
    var j = 1usize
    while j <= p {
        let t = x[hv.xo(n, a, j)]
        x[hv.xo(n, a, j)] = x[hv.xo(n, b, j)]
        x[hv.xo(n, b, j)] = t
        j += 1usize
    }
}

fn hc_eee(a: *mem.Arena, xin: []const f64, n: usize, p: usize, ic0: []const usize, ng: usize, out: []usize) -> err {
    let ns = ng - 1usize
    let flmax = 1.7976931348623157e308f64
    let epsmin = 1.1102230246251565e-16f64
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (ic, e2) = mem.alloc[usize](a, n + 1usize)
    let (v, e4) = mem.alloc[f64](a, p)
    let (u, e5) = mem.alloc[f64](a, p * p)
    let (s, e6) = mem.alloc[f64](a, p * p)
    let (r, e7) = mem.alloc[f64](a, p * p)
    let (ia, e8) = mem.alloc[usize](a, ns + 2usize)
    let (ja, e9) = mem.alloc[usize](a, ns + 2usize)
    let (lab, e10) = mem.alloc[usize](a, ng + 2usize)
    if e1 != ok || e2 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    if ng < 2usize { ret ok }
    let lw = p * p
    var q = 0usize
    while q < n * p {
        x[q] = xin[q]
        q += 1usize
    }
    q = 1usize
    while q <= n {
        ic[q] = ic0[q - 1usize]
        q += 1usize
    }
    q = 0usize
    while q < p {
        v[q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < lw {
        u[q] = 0.0f64
        s[q] = 0.0f64
        r[q] = 0.0f64
        q += 1usize
    }
    // the scaled column sums
    hv.dscal_s(n * p, 1.0f64 / math.sqrt[f64](f64(n)), x, 0usize, 1usize)
    var si = 1.0f64 / math.sqrt[f64](f64(p))
    var sj = si / f64(n)
    var k = 1usize
    while k <= n {
        hv.daxpy_s(p, sj, x, hv.xo(n, k, 1usize), n, v, 0usize, 1usize)
        k += 1usize
    }
    var trc0 = 0.0f64
    k = 1usize
    while k <= n {
        hv.dcopy_s(p, v, 0usize, 1usize, s, 0usize, 1usize)
        hv.daxpy_s(p, 0.0f64 - si, x, hv.xo(n, k, 1usize), n, s, 0usize, 1usize)
        trc0 += hv.ddot_s(p, s, 0usize, 1usize, s, 0usize, 1usize)
        hv.mclrup(k + 1usize, p, s, r, 0usize, p)
        k += 1usize
    }
    let delog = math.log[f64](trc0 + epsmin)
    // the group heads first among the rows of x
    var i = 1usize
    var j = 2usize
    var head_done = false
    while !head_done {
        if ic[j] != j {
            var kk = i
            let m0 = j + 1usize
            var jj = m0
            while jj <= n {
                let icj = ic[jj]
                if icj > kk {
                    kk += 1usize
                    swap_rows(x, n, p, kk, jj)
                    ic[jj] = ic[kk]
                    ic[kk] = icj
                }
                jj += 1usize
            }
            head_done = true
        } else if j == ng {
            head_done = true
        } else {
            i = j
            j += 1usize
        }
    }
    q = 0usize
    while q < lw {
        r[q] = 0.0f64
        q += 1usize
    }
    var qq = 1usize
    var trcw = 0.0f64
    j = 1usize
    while j <= n {
        i = ic[j]
        if i != j {
            qq += 2usize
            let ni0 = ic[i]
            let ri0 = f64(ni0)
            let rij0 = f64(ni0 + 1usize)
            sj = math.sqrt[f64](1.0f64 / rij0)
            si = math.sqrt[f64](ri0) * sj
            hv.dcopy_s(p, x, hv.xo(n, i, 1usize), n, v, 0usize, 1usize)
            hv.dscal_s(p, sj, v, 0usize, 1usize)
            hv.daxpy_s(p, 0.0f64 - si, x, hv.xo(n, j, 1usize), n, v, 0usize, 1usize)
            trcw += hv.ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
            hv.mclrup(qq, p, v, r, 0usize, p)
            ic[j] = 0usize
            ic[i] = ic[i] + 1usize
            hv.dscal_s(p, si, x, hv.xo(n, i, 1usize), n)
            hv.daxpy_s(p, sj, x, hv.xo(n, j, 1usize), n, x, hv.xo(n, i, 1usize), n)
        } else {
            ic[j] = 1usize
        }
        j += 1usize
    }
    var detw = 0.0f64 - flmax
    if qq >= p { detw = hv.det2mc(p, r, 1.0f64) }
    var ls = 1usize
    var lg = ng
    var iopt = 0usize
    var jopt = 0usize
    var nopt = 0usize
    var siop = 0.0f64
    var sjop = 0.0f64
    var dopt = 0.0f64
    var zopt = 0.0f64
    var tdet = 0.0f64
    var ndet = 0usize
    var sidt = 0.0f64
    var sjdt = 0.0f64
    var idet = 0usize
    var jdet = 0usize
    var dijo = 0.0f64
    var tijo = 0.0f64
    var phase = 1usize
    var fin = false
    while !fin {
        if phase == 1usize {
            if qq >= p {
                if detw < delog { phase = 2usize } else { phase = 3usize }
            } else {
                dopt = flmax
                j = 2usize
                while j <= lg {
                    let nj = ic[j]
                    let rj = f64(nj)
                    i = 1usize
                    while i <= j - 1usize {
                        let ni = ic[i]
                        let ri = f64(ni)
                        let nij = ni + nj
                        let rij = f64(nij)
                        si = math.sqrt[f64](ri / rij)
                        sj = math.sqrt[f64](rj / rij)
                        hv.dcopy_s(p, x, hv.xo(n, i, 1usize), n, s, 0usize, 1usize)
                        hv.dscal_s(p, sj, s, 0usize, 1usize)
                        hv.daxpy_s(p, 0.0f64 - si, x, hv.xo(n, j, 1usize), n, s, 0usize, 1usize)
                        let tij = trcw + hv.ddot_s(p, s, 0usize, 1usize, s, 0usize, 1usize)
                        var zij = tij
                        if zij < epsmin { zij = epsmin }
                        if zij <= dopt {
                            dopt = zij
                            nopt = nij
                            siop = si
                            sjop = sj
                            iopt = i
                            jopt = j
                            hv.dcopy_s(p, s, 0usize, 1usize, v, 0usize, 1usize)
                        }
                        i += 1usize
                    }
                    j += 1usize
                }
                trcw = dopt
                if ls == ns {
                    fin = true
                } else {
                    hv.dscal_s(p, siop, x, hv.xo(n, iopt, 1usize), n)
                    hv.daxpy_s(p, sjop, x, hv.xo(n, jopt, 1usize), n, x, hv.xo(n, iopt, 1usize), n)
                    if jopt != lg {
                        hv.dcopy_s(p, x, hv.xo(n, lg, 1usize), n, x, hv.xo(n, jopt, 1usize), n)
                        ic[jopt] = ic[lg]
                    }
                    ic[iopt] = nopt
                    ia[ls] = iopt
                    ja[ls] = jopt
                    qq += 1usize
                    hv.mclrup(qq, p, v, r, 0usize, p)
                    ls += 1usize
                    lg -= 1usize
                }
            }
        } else if phase == 2usize {
            qq += 1usize
            dopt = flmax
            zopt = flmax
            j = 2usize
            while j <= lg {
                let nj = ic[j]
                let rj = f64(nj)
                i = 1usize
                while i <= j - 1usize {
                    let ni = ic[i]
                    let ri = f64(ni)
                    let nij = ni + nj
                    let rij = f64(nij)
                    si = math.sqrt[f64](ri / rij)
                    sj = math.sqrt[f64](rj / rij)
                    hv.dcopy_s(p, x, hv.xo(n, i, 1usize), n, v, 0usize, 1usize)
                    hv.dscal_s(p, sj, v, 0usize, 1usize)
                    hv.daxpy_s(p, 0.0f64 - si, x, hv.xo(n, j, 1usize), n, v, 0usize, 1usize)
                    let tij = trcw + hv.ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
                    hv.dcopy_s(lw, r, 0usize, 1usize, u, 0usize, 1usize)
                    hv.mclrup(qq, p, v, u, 0usize, p)
                    let dij = hv.det2mc(p, u, 1.0f64)
                    if dij <= dopt {
                        dopt = dij
                        tdet = tij
                        ndet = nij
                        sidt = si
                        sjdt = sj
                        idet = i
                        jdet = j
                    }
                    var zij = 0.0f64 - flmax
                    if tij != 0.0f64 {
                        zij = tij
                        if zij < epsmin { zij = epsmin }
                        if dij == 0.0f64 - flmax {
                            zij = math.log[f64](zij)
                        } else if dij <= 0.0f64 {
                            zij = math.log[f64](math.exp[f64](dij) + zij)
                        } else {
                            zij = math.log[f64](1.0f64 + zij * math.exp[f64](0.0f64 - dij)) + dij
                        }
                    }
                    if zij <= zopt {
                        zopt = zij
                        dijo = dij
                        tijo = tij
                        nopt = nij
                        siop = si
                        sjop = sj
                        iopt = i
                        jopt = j
                        hv.dcopy_s(lw, u, 0usize, 1usize, s, 0usize, 1usize)
                    }
                    i += 1usize
                }
                j += 1usize
            }
            if dopt < delog {
                trcw = tijo
                detw = dijo
                hv.dcopy_s(lw, s, 0usize, 1usize, r, 0usize, 1usize)
            } else {
                trcw = tdet
                detw = dopt
                siop = sidt
                sjop = sjdt
                nopt = ndet
                iopt = idet
                jopt = jdet
                hv.dcopy_s(p, x, hv.xo(n, iopt, 1usize), n, v, 0usize, 1usize)
                hv.dscal_s(p, sjop, v, 0usize, 1usize)
                hv.daxpy_s(p, 0.0f64 - siop, x, hv.xo(n, jopt, 1usize), n, v, 0usize, 1usize)
                hv.mclrup(qq, p, v, r, 0usize, p)
            }
            if ls == ns {
                fin = true
            } else {
                hv.dscal_s(p, siop, x, hv.xo(n, iopt, 1usize), n)
                hv.daxpy_s(p, sjop, x, hv.xo(n, jopt, 1usize), n, x, hv.xo(n, iopt, 1usize), n)
                if jopt != lg {
                    hv.dcopy_s(p, x, hv.xo(n, lg, 1usize), n, x, hv.xo(n, jopt, 1usize), n)
                    ic[jopt] = ic[lg]
                }
                ic[iopt] = nopt
                ia[ls] = iopt
                ja[ls] = jopt
                ls += 1usize
                lg -= 1usize
                if detw >= delog { phase = 3usize }
            }
        } else {
            qq += 1usize
            detw = flmax
            j = 2usize
            while j <= lg {
                let nj = ic[j]
                let rj = f64(nj)
                i = 1usize
                while i <= j - 1usize {
                    let ni = ic[i]
                    let ri = f64(ni)
                    let nij = ni + nj
                    let rij = f64(nij)
                    si = math.sqrt[f64](ri / rij)
                    sj = math.sqrt[f64](rj / rij)
                    hv.dcopy_s(p, x, hv.xo(n, i, 1usize), n, v, 0usize, 1usize)
                    hv.dscal_s(p, sj, v, 0usize, 1usize)
                    hv.daxpy_s(p, 0.0f64 - si, x, hv.xo(n, j, 1usize), n, v, 0usize, 1usize)
                    hv.dcopy_s(lw, r, 0usize, 1usize, u, 0usize, 1usize)
                    hv.mclrup(qq, p, v, u, 0usize, p)
                    let dij = hv.det2mc(p, u, 1.0f64)
                    if dij <= detw {
                        detw = dij
                        nopt = nij
                        siop = si
                        sjop = sj
                        iopt = i
                        jopt = j
                        hv.dcopy_s(lw, u, 0usize, 1usize, s, 0usize, 1usize)
                    }
                    i += 1usize
                }
                j += 1usize
            }
            hv.dcopy_s(p, x, hv.xo(n, iopt, 1usize), n, v, 0usize, 1usize)
            hv.dscal_s(p, sjop, v, 0usize, 1usize)
            hv.daxpy_s(p, 0.0f64 - siop, x, hv.xo(n, jopt, 1usize), n, v, 0usize, 1usize)
            trcw += hv.ddot_s(p, v, 0usize, 1usize, v, 0usize, 1usize)
            if ls == ns {
                fin = true
            } else {
                hv.dcopy_s(lw, s, 0usize, 1usize, r, 0usize, 1usize)
                hv.dscal_s(p, siop, x, hv.xo(n, iopt, 1usize), n)
                hv.daxpy_s(p, sjop, x, hv.xo(n, jopt, 1usize), n, x, hv.xo(n, iopt, 1usize), n)
                if jopt != lg {
                    hv.dcopy_s(p, x, hv.xo(n, lg, 1usize), n, x, hv.xo(n, jopt, 1usize), n)
                    ic[jopt] = ic[lg]
                }
                ic[iopt] = nopt
                ia[ls] = iopt
                ja[ls] = jopt
                ls += 1usize
                lg -= 1usize
            }
        }
    }
    // the last merge (the smaller position first), then decode positions into group names
    if iopt < jopt {
        ia[ls] = iopt
        ja[ls] = jopt
    } else {
        ia[ls] = jopt
        ja[ls] = iopt
    }
    k = 1usize
    while k <= ng {
        lab[k] = k
        k += 1usize
    }
    let mm = ng + 1usize
    k = 1usize
    while k <= ns {
        let pi = ia[k]
        let pj = ja[k]
        let ici = lab[pi]
        let icj = lab[pj]
        if ici > icj { lab[pi] = icj }
        lab[pj] = lab[mm - k]
        if ici < icj {
            out[2usize * (k - 1usize)] = ici
            out[2usize * (k - 1usize) + 1usize] = icj
        } else {
            out[2usize * (k - 1usize)] = icj
            out[2usize * (k - 1usize) + 1usize] = ici
        }
        k += 1usize
    }
    ret ok
}

// hclass(hc, g) with an initial partition init (n, one-based group numbers in order of first appearance, k groups): the one-based group of each observation, numbered by first appearance
fn hclass_init(a: *mem.Arena, pairs: []const usize, init: []const usize, n: usize, k: usize, g: usize, lab: []usize) -> err {
    let (cur, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        cur[i] = init[i]
        i += 1usize
    }
    var l = 0usize
    while l + g < k {
        let pa = pairs[2usize * l]
        let pb = pairs[2usize * l + 1usize]
        var lo = pa
        var hi = pb
        if pb < pa {
            lo = pb
            hi = pa
        }
        i = 0usize
        while i < n {
            if cur[i] == hi { cur[i] = lo }
            i += 1usize
        }
        l += 1usize
    }
    var next = 1usize
    i = 0usize
    while i < n {
        var found = false
        var jj = 0usize
        while jj < i && !found {
            if cur[jj] == cur[i] {
                lab[i] = lab[jj]
                found = true
            }
            jj += 1usize
        }
        if !found {
            lab[i] = next
            next += 1usize
        }
        i += 1usize
    }
    ret ok
}
