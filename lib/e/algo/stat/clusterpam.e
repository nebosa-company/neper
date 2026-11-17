// R cluster (Maechler et al., 2.1.8.2): pam and clara, ported from the package's pam.c and clara.c.
//
//   pam_core    partitioning around medoids from a cdv (see e.algo.stat.clusterdiss): BUILD, then SWAP in the package's seven
//               variants (pamonce 0 original, 1 and 2 the Reynolds et al. speed-ups, 3 FastPAM1, 4 and 5 FastPAM2, 6 FasterPAM),
//               starting medoids given or not, do.swap, the cluster statistics (clusinfo, isolation) and the silhouette
//   pam_random  the random starts of pam(medoids = "random", nstart) over R's sample.int
//   clara_core  clustering large applications: the sampled sub-problems, their medoids, the assignment of all objects, the
//               silhouette of the best sample; the sampling is clara's own generator or R's (rngR)
//
// Data matrices are n by p row-major with NaN as a missing value, medoid and observation numbers are 1-based as in R. The vectors
// of a result are 0-based of the length R answers; clusinf and silinf are column-major.
//
// Not here: the Gower metric of clara (disabled in the package since 2023), the print and summary methods.

use e.algo.stat.clusterdiss as cd
use e.algo.rand.r as rr
use e.math
use e.mem

error BadPam

type PamOut = struct {
    med: []usize,
    clu: []usize,
    obj0: f64,
    obj1: f64,
    isol: []usize,
    clusinf: []f64,
    silinf: []f64,
    avsil: []f64,
    ttsil: f64,
    dosyl: bool
}

// bswap(): BUILD (unless the medoids are given) and SWAP. nrepr[1..n] flags the medoids on entry (given) and exit; arrays are 1-based.
fn pam_bswap(a: *mem.Arena, kk: usize, n: usize, nrepr: []usize, med_given: bool, do_swap: bool, pamonce: usize, dysma: []f64, dysmb: []f64, beter: []f64, dys: []const f64, s0: f64, obj: []f64) -> err {
    let s = s0 * 1.1f64 + 1.0f64
    var i = 1usize
    var j = 1usize
    var k = 1usize
    var h = 1usize
    while i <= n {
        dysma[i] = s
        i += 1usize
    }
    if med_given {
        i = 1usize
        while i <= n {
            if nrepr[i] == 1usize {
                j = 1usize
                while j <= n {
                    let ij = cd.ind_2(i, j)
                    if dysma[j] > dys[ij] { dysma[j] = dys[ij] }
                    j += 1usize
                }
            }
            i += 1usize
        }
    } else {
        k = 1usize
        while k <= kk {
            var nmax = 0usize
            var ammax = 0.0f64
            i = 1usize
            while i <= n {
                if nrepr[i] == 0usize {
                    beter[i] = 0.0f64
                    j = 1usize
                    while j <= n {
                        let cmd = dysma[j] - dys[cd.ind_2(i, j)]
                        if cmd > 0.0f64 { beter[i] += cmd }
                        j += 1usize
                    }
                    if ammax <= beter[i] {
                        ammax = beter[i]
                        nmax = i
                    }
                }
                i += 1usize
            }
            nrepr[nmax] = 1usize
            j = 1usize
            while j <= n {
                let ij = cd.ind_2(nmax, j)
                if dysma[j] > dys[ij] { dysma[j] = dys[ij] }
                j += 1usize
            }
            k += 1usize
        }
    }
    var sky = 0.0f64
    j = 1usize
    while j <= n {
        sky += dysma[j]
        j += 1usize
    }
    obj[0usize] = sky / f64(n)
    if do_swap && (kk > 1usize || med_given) {
        let (medoids, e1) = mem.alloc[usize](a, kk + 1usize)
        if e1 != ok { ret e1 }
        let (cm, e2) = mem.alloc[usize](a, n + 1usize)
        if e2 != ok { ret e2 }
        let (cmb, e3) = mem.alloc[usize](a, n + 1usize)
        if e3 != ok { ret e3 }
        let (fvect, e4) = mem.alloc[f64](a, n + 1usize)
        if e4 != ok { ret e4 }
        let (best_h, e5) = mem.alloc[usize](a, kk + 1usize)
        if e5 != ok { ret e5 }
        let (best_d, e6) = mem.alloc[f64](a, kk + 1usize)
        if e6 != ok { ret e6 }
        let (remove_loss, e7) = mem.alloc[f64](a, kk + 1usize)
        if e7 != ok { ret e7 }
        i = 0usize
        while i <= kk {
            medoids[i] = 0usize
            best_h[i] = 0usize
            best_d[i] = 0.0f64
            remove_loss[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i <= n {
            cm[i] = 0usize
            cmb[i] = 0usize
            fvect[i] = 0.0f64
            i += 1usize
        }
        if pamonce != 0usize {
            k = 1usize
            i = 1usize
            while i <= n {
                if nrepr[i] != 0usize {
                    medoids[k] = i
                    k += 1usize
                }
                i += 1usize
            }
        }
        let tiny = 16.0f64 * 2.220446049250313e-16f64
        var hbest = 0usize
        var nbest = 0usize
        var kbest = 0usize
        var lastswap = 0usize
        var done = false
        while !done {
            // L60: the nearest and second nearest medoid of every object
            if pamonce == 0usize {
                j = 1usize
                while j <= n {
                    dysma[j] = s
                    dysmb[j] = s
                    i = 1usize
                    while i <= n {
                        if nrepr[i] != 0usize {
                            let ij = cd.ind_2(i, j)
                            if dysma[j] > dys[ij] {
                                dysmb[j] = dysma[j]
                                dysma[j] = dys[ij]
                            } else {
                                if dysmb[j] > dys[ij] { dysmb[j] = dys[ij] }
                            }
                        }
                        i += 1usize
                    }
                    j += 1usize
                }
            } else {
                if pamonce >= 3usize && pamonce <= 6usize {
                    j = 1usize
                    while j <= n {
                        var dysmaj = s
                        var dysmbj = s
                        k = 1usize
                        while k <= kk {
                            let dysij = dys[cd.ind_2(medoids[k], j)]
                            if dysmaj > dysij {
                                cmb[j] = cm[j]
                                dysmbj = dysmaj
                                cm[j] = k
                                dysmaj = dysij
                            } else {
                                if dysmbj > dysij {
                                    cmb[j] = k
                                    dysmbj = dysij
                                }
                            }
                            k += 1usize
                        }
                        dysma[j] = dysmaj
                        dysmb[j] = dysmbj
                        j += 1usize
                    }
                } else {
                    j = 1usize
                    while j <= n {
                        dysma[j] = s
                        dysmb[j] = s
                        k = 1usize
                        while k <= kk {
                            i = medoids[k]
                            let ij = cd.ind_2(i, j)
                            if dysma[j] > dys[ij] {
                                cm[j] = i
                                dysmb[j] = dysma[j]
                                dysma[j] = dys[ij]
                            } else {
                                if dysmb[j] > dys[ij] { dysmb[j] = dys[ij] }
                            }
                            k += 1usize
                        }
                        j += 1usize
                    }
                }
            }
            var again = true
            while again {
                again = false
                // L60b
                var dzsky = 1.0f64
                if pamonce == 0usize {
                    h = 1usize
                    while h <= n {
                        if nrepr[h] == 0usize {
                            i = 1usize
                            while i <= n {
                                if nrepr[i] != 0usize {
                                    var dz = 0.0f64
                                    j = 1usize
                                    while j <= n {
                                        let hj = cd.ind_2(h, j)
                                        let ij = cd.ind_2(i, j)
                                        if dys[ij] == dysma[j] {
                                            var small = dysmb[j]
                                            if dysmb[j] > dys[hj] { small = dys[hj] }
                                            dz += 0.0f64 - dysma[j] + small
                                        } else {
                                            if dys[hj] < dysma[j] { dz += 0.0f64 - dysma[j] + dys[hj] }
                                        }
                                        j += 1usize
                                    }
                                    if dzsky > dz {
                                        dzsky = dz
                                        hbest = h
                                        nbest = i
                                    }
                                }
                                i += 1usize
                            }
                        }
                        h += 1usize
                    }
                } else {
                    if pamonce == 1usize || pamonce == 2usize {
                        k = 1usize
                        while k <= kk {
                            i = medoids[k]
                            var remove_cost = 0.0f64
                            j = 1usize
                            while j <= n {
                                if cm[j] == i {
                                    remove_cost += dysmb[j] - dysma[j]
                                    fvect[j] = dysmb[j]
                                } else {
                                    fvect[j] = dysma[j]
                                }
                                j += 1usize
                            }
                            h = 1usize
                            while h <= n {
                                if nrepr[h] == 0usize {
                                    var add_gain = remove_cost
                                    if pamonce == 2usize { add_gain = remove_cost - fvect[h] }
                                    j = 1usize
                                    while j <= n {
                                        if pamonce == 1usize || j != h {
                                            let hj = cd.ind_2(h, j)
                                            if dys[hj] < fvect[j] { add_gain += dys[hj] - fvect[j] }
                                        }
                                        j += 1usize
                                    }
                                    if dzsky > add_gain {
                                        dzsky = add_gain
                                        hbest = h
                                        nbest = i
                                        kbest = k
                                    }
                                }
                                h += 1usize
                            }
                            k += 1usize
                        }
                    } else {
                        k = 1usize
                        while k <= kk {
                            remove_loss[k] = 0.0f64
                            k += 1usize
                        }
                        j = 1usize
                        while j <= n {
                            remove_loss[cm[j]] += dysmb[j] - dysma[j]
                            j += 1usize
                        }
                        if pamonce == 3usize {
                            h = 1usize
                            while h <= n {
                                if nrepr[h] == 0usize {
                                    k = 1usize
                                    while k <= kk {
                                        beter[k] = 0.0f64
                                        k += 1usize
                                    }
                                    var acc = 0.0f64
                                    j = 1usize
                                    while j <= n {
                                        let dist_h = dys[cd.ind_2(h, j)]
                                        let memb = cm[j]
                                        let distcur = dysma[j]
                                        let distsec = dysmb[j]
                                        if dist_h < distcur {
                                            acc += dist_h - distcur
                                            beter[memb] += distcur - distsec
                                        } else {
                                            if dist_h < distsec { beter[memb] += dist_h - distsec }
                                        }
                                        j += 1usize
                                    }
                                    k = 1usize
                                    while k <= kk {
                                        let loss = beter[k] + acc + remove_loss[k]
                                        if loss < dzsky {
                                            dzsky = loss
                                            hbest = h
                                            nbest = medoids[k]
                                            kbest = k
                                        }
                                        k += 1usize
                                    }
                                }
                                h += 1usize
                            }
                        } else {
                            if pamonce == 4usize || pamonce == 5usize {
                                k = 1usize
                                while k <= kk {
                                    best_d[k] = 1.0f64
                                    k += 1usize
                                }
                            }
                            // the candidates h: all of them (4, 5), or from the last swap on until the first improvement (6)
                            var h2 = 1usize
                            h = 1usize
                            if pamonce == 6usize { h = lastswap + 1usize }
                            while h2 <= n {
                                if h == n + 1usize { h = 1usize }
                                if nrepr[h] == 0usize {
                                    k = 1usize
                                    while k <= kk {
                                        beter[k] = 0.0f64
                                        k += 1usize
                                    }
                                    var acc = 0.0f64
                                    if pamonce != 4usize {
                                        acc = 0.0f64 - dysma[h]
                                        if pamonce == 5usize {
                                            beter[cm[h]] = dysma[h] - dysmb[h]
                                        } else {
                                            beter[cm[h]] += dysma[h] - dysmb[h]
                                        }
                                    }
                                    j = 1usize
                                    while j <= n {
                                        if pamonce == 4usize || j != h {
                                            let dist_h = dys[cd.ind_2(h, j)]
                                            let memb = cm[j]
                                            let distcur = dysma[j]
                                            let distsec = dysmb[j]
                                            if dist_h < distcur {
                                                acc += dist_h - distcur
                                                beter[memb] += distcur - distsec
                                            } else {
                                                if dist_h < distsec { beter[memb] += dist_h - distsec }
                                            }
                                        }
                                        j += 1usize
                                    }
                                    k = 1usize
                                    while k <= kk {
                                        let loss = beter[k] + acc + remove_loss[k]
                                        if pamonce == 6usize {
                                            if loss < dzsky {
                                                dzsky = loss
                                                hbest = h
                                                nbest = medoids[k]
                                                kbest = k
                                            }
                                        } else {
                                            if loss < best_d[k] {
                                                best_d[k] = loss
                                                best_h[k] = h
                                            }
                                        }
                                        k += 1usize
                                    }
                                    if pamonce == 6usize && dzsky < 0.0f64 { break }
                                }
                                h += 1usize
                                h2 += 1usize
                            }
                            if pamonce != 6usize {
                                k = 1usize
                                while k <= kk {
                                    if best_d[k] < dzsky {
                                        dzsky = best_d[k]
                                        kbest = k
                                    }
                                    k += 1usize
                                }
                                hbest = best_h[kbest]
                                nbest = medoids[kbest]
                            }
                        }
                    }
                }
                if dzsky < 0.0f64 - tiny * math.abs[f64](sky) {
                    nrepr[hbest] = 1usize
                    nrepr[nbest] = 0usize
                    if pamonce != 0usize { medoids[kbest] = hbest }
                    if pamonce == 6usize { lastswap = hbest }
                    sky += dzsky
                    if pamonce == 3usize || pamonce == 6usize {
                        // FasterPAM: update the nearest and second nearest instead of recomputing them
                        var newloss = 0.0f64
                        j = 1usize
                        while j <= n {
                            let dnew = dys[cd.ind_2(hbest, j)]
                            var rescan = false
                            if cm[j] == kbest {
                                if dnew < dysmb[j] {
                                    dysma[j] = dnew
                                } else {
                                    rescan = true
                                }
                            } else {
                                if dnew < dysma[j] {
                                    cmb[j] = cm[j]
                                    dysmb[j] = dysma[j]
                                    cm[j] = kbest
                                    dysma[j] = dnew
                                } else {
                                    if cmb[j] == kbest {
                                        rescan = true
                                    } else {
                                        if dnew < dysmb[j] {
                                            cmb[j] = kbest
                                            dysmb[j] = dnew
                                        }
                                    }
                                }
                            }
                            if rescan {
                                var dysmaj = s
                                var dysmbj = s
                                k = 1usize
                                while k <= kk {
                                    let dysij = dys[cd.ind_2(medoids[k], j)]
                                    if dysmaj > dysij {
                                        cmb[j] = cm[j]
                                        dysmbj = dysmaj
                                        cm[j] = k
                                        dysmaj = dysij
                                    } else {
                                        if dysmbj > dysij {
                                            cmb[j] = k
                                            dysmbj = dysij
                                        }
                                    }
                                    k += 1usize
                                }
                                dysma[j] = dysmaj
                                dysmb[j] = dysmbj
                            }
                            newloss += dysma[j]
                            j += 1usize
                        }
                        sky = newloss
                        again = true
                    } else {
                        if pamonce == 4usize || pamonce == 5usize {
                            // FastPAM2: try the next best medoids while they still improve
                            var more = true
                            while more {
                                best_d[kbest] = 1.0f64
                                dzsky = 1.0f64
                                k = 1usize
                                while k <= kk {
                                    if best_d[k] < dzsky {
                                        dzsky = best_d[k]
                                        kbest = k
                                    }
                                    k += 1usize
                                }
                                hbest = best_h[kbest]
                                nbest = medoids[kbest]
                                if dzsky >= 0.0f64 - tiny * math.abs[f64](sky) {
                                    more = false
                                } else {
                                    j = 1usize
                                    while j <= n {
                                        dysma[j] = s
                                        dysmb[j] = s
                                        k = 1usize
                                        while k <= kk {
                                            i = medoids[k]
                                            let ij = cd.ind_2(i, j)
                                            if dysma[j] > dys[ij] {
                                                cm[j] = k
                                                dysmb[j] = dysma[j]
                                                dysma[j] = dys[ij]
                                            } else {
                                                if dysmb[j] > dys[ij] { dysmb[j] = dys[ij] }
                                            }
                                            k += 1usize
                                        }
                                        j += 1usize
                                    }
                                    dzsky = 0.0f64
                                    j = 1usize
                                    while j <= n {
                                        let hj = cd.ind_2(hbest, j)
                                        let ij = cd.ind_2(nbest, j)
                                        if dys[ij] == dysma[j] {
                                            dzsky += 0.0f64 - dysma[j] + math.min[f64](dysmb[j], dys[hj])
                                        } else {
                                            if dys[hj] < dysma[j] { dzsky += 0.0f64 - dysma[j] + dys[hj] }
                                        }
                                        j += 1usize
                                    }
                                    if dzsky >= 0.0f64 - tiny * math.abs[f64](sky) {
                                        more = false
                                    } else {
                                        nrepr[hbest] = 1usize
                                        nrepr[nbest] = 0usize
                                        medoids[kbest] = hbest
                                        sky += dzsky
                                    }
                                }
                            }
                        }
                    }
                } else {
                    done = true
                }
            }
        }
    }
    obj[1usize] = sky / f64(n)
    ret ok
}

// pam(): a cdv of n objects, kk clusters. medgiven holds kk 1-based starting medoids, or is empty for BUILD.
fn pam_core(a: *mem.Arena, dys: []const f64, n: usize, kk: usize, medgiven: []const usize, do_swap: bool, pamonce: usize, all_stats: bool) -> (PamOut, err) {
    let nhalf = n * (n - 1usize) / 2usize + 1usize
    var s = 0.0f64
    var i = 1usize
    while i < nhalf {
        if s < dys[i] { s = dys[i] }
        i += 1usize
    }
    let (nsend, e1) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok { ret (zero, e1) }
    let (nelem, e2) = mem.alloc[usize](a, n + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (nrepr, e3) = mem.alloc[usize](a, n + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (radus, e4) = mem.alloc[f64](a, n + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (damer, e5) = mem.alloc[f64](a, n + 1usize)
    if e5 != ok { ret (zero, e5) }
    let (avsyl, e6) = mem.alloc[f64](a, n + 1usize)
    if e6 != ok { ret (zero, e6) }
    let (separ, e7) = mem.alloc[f64](a, kk + 1usize)
    if e7 != ok { ret (zero, e7) }
    let (ncluv, e8) = mem.alloc[usize](a, n + 1usize)
    if e8 != ok { ret (zero, e8) }
    let (nisol, e9) = mem.alloc[usize](a, kk + 1usize)
    if e9 != ok { ret (zero, e9) }
    let (med, e10) = mem.alloc[usize](a, kk + 1usize)
    if e10 != ok { ret (zero, e10) }
    i = 0usize
    while i <= n {
        nrepr[i] = 0usize
        nsend[i] = 0usize
        nelem[i] = 0usize
        ncluv[i] = 0usize
        radus[i] = 0.0f64
        damer[i] = 0.0f64
        avsyl[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i <= kk {
        separ[i] = 0.0f64
        nisol[i] = 0usize
        med[i] = 0usize
        i += 1usize
    }
    let med_given = medgiven.len > 0usize
    if med_given {
        i = 0usize
        while i < kk {
            nrepr[medgiven[i]] = 1usize
            i += 1usize
        }
    }
    let (obj, e11) = mem.alloc[f64](a, 2usize)
    if e11 != ok { ret (zero, e11) }
    let e12 = pam_bswap(a, kk, n, nrepr, med_given, do_swap, pamonce, radus, damer, avsyl, dys, s, obj)
    if e12 != ok { ret (zero, e12) }
    // cstat(): the clustering and its statistics
    let ss = s * 1.1f64 + 1.0f64
    var ksmal = 0usize
    var k = 0usize
    var j = 1usize
    while j <= n {
        if nrepr[j] == 0usize {
            var dsmal = ss
            k = 1usize
            while k <= n {
                if nrepr[k] == 1usize {
                    let kj = cd.ind_2(k, j)
                    if dsmal > dys[kj] {
                        dsmal = dys[kj]
                        ksmal = k
                    }
                }
                k += 1usize
            }
            nsend[j] = ksmal
        } else {
            nsend[j] = j
        }
        j += 1usize
    }
    var jk = 1usize
    var nplac = nsend[1usize]
    j = 1usize
    while j <= n {
        ncluv[j] = 0usize
        if nsend[j] == nplac { ncluv[j] = 1usize }
        j += 1usize
    }
    var ja = 2usize
    while ja <= n {
        nplac = nsend[ja]
        if ncluv[nplac] == 0usize {
            jk += 1usize
            j = 2usize
            while j <= n {
                if nsend[j] == nplac { ncluv[j] = jk }
                j += 1usize
            }
            if jk == kk { break }
        }
        ja += 1usize
    }
    let (clusinf, e13) = mem.alloc[f64](a, kk * 5usize)
    if e13 != ok { ret (zero, e13) }
    let (avsil_out, e14) = mem.alloc[f64](a, kk)
    if e14 != ok { ret (zero, e14) }
    let (silinf, e15) = mem.alloc[f64](a, n * 4usize)
    if e15 != ok { ret (zero, e15) }
    i = 0usize
    while i < kk * 5usize {
        clusinf[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < kk {
        avsil_out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * 4usize {
        silinf[i] = 0.0f64
        i += 1usize
    }
    var ttsil = 0.0f64
    let dosyl = all_stats && 1usize < kk && kk < n
    if all_stats {
        k = 1usize
        while k <= kk {
            var ntt = 0usize
            var m = 0usize
            var ttt = 0.0f64
            radus[k] = 0.0f64 - 1.0f64
            j = 1usize
            while j <= n {
                if ncluv[j] == k {
                    ntt += 1usize
                    m = nsend[j]
                    nelem[ntt] = j
                    let djm = dys[cd.ind_2(j, m)]
                    ttt += djm
                    if radus[k] < djm { radus[k] = djm }
                }
                j += 1usize
            }
            if ntt == 0usize { ret (zero, BadPam) }
            avsyl[k] = ttt / f64(ntt)
            med[k] = m
            k += 1usize
        }
        if kk == 1usize {
            damer[1usize] = s
            nrepr[1usize] = n
            nisol[1usize] = 0usize
            separ[1usize] = 0.0f64
        } else {
            k = 1usize
            while k <= kk {
                var nel = 0usize
                j = 1usize
                while j <= n {
                    if ncluv[j] == k {
                        nel += 1usize
                        nelem[nel] = j
                    }
                    j += 1usize
                }
                nrepr[k] = nel
                var isolated = false
                if nel == 1usize {
                    let nvn = nelem[1usize]
                    damer[k] = 0.0f64
                    separ[k] = ss
                    j = 1usize
                    while j <= n {
                        if j != nvn {
                            let mevj = cd.ind_2(nvn, j)
                            if separ[k] > dys[mevj] { separ[k] = dys[mevj] }
                        }
                        j += 1usize
                    }
                } else {
                    var dam = 0.0f64 - 1.0f64
                    var sep = ss
                    var kand = true
                    var jx = 1usize
                    while jx <= nel {
                        let nvna = nelem[jx]
                        var aja = 0.0f64 - 1.0f64
                        var ajb = ss
                        var jb = 1usize
                        while jb <= n {
                            let jndz = cd.ind_2(nvna, jb)
                            if ncluv[jb] == k {
                                if aja < dys[jndz] { aja = dys[jndz] }
                            } else {
                                if ajb > dys[jndz] { ajb = dys[jndz] }
                            }
                            jb += 1usize
                        }
                        if kand && aja >= ajb { kand = false }
                        if dam < aja { dam = aja }
                        if sep > ajb { sep = ajb }
                        jx += 1usize
                    }
                    separ[k] = sep
                    damer[k] = dam
                    if kand {
                        isolated = true
                        if dam >= sep {
                            nisol[k] = 1usize
                        } else {
                            nisol[k] = 2usize
                        }
                    }
                }
                if !isolated { nisol[k] = 0usize }
                k += 1usize
            }
        }
        k = 1usize
        while k <= kk {
            let c0 = k - 1usize
            clusinf[c0] = f64(nrepr[k])
            clusinf[c0 + kk] = radus[k]
            clusinf[c0 + 2usize * kk] = avsyl[k]
            clusinf[c0 + 3usize * kk] = damer[k]
            clusinf[c0 + 4usize * kk] = separ[k]
            k += 1usize
        }
        if dosyl {
            // dark(): the silhouette
            let (syl, e16) = mem.alloc[f64](a, n + 1usize)
            if e16 != ok { ret (zero, e16) }
            let (srank, e17) = mem.alloc[f64](a, n + 1usize)
            if e17 != ok { ret (zero, e17) }
            let (negbr, e18) = mem.alloc[usize](a, n + 1usize)
            if e18 != ok { ret (zero, e18) }
            let (ne, e19) = mem.alloc[usize](a, n + 1usize)
            if e19 != ok { ret (zero, e19) }
            let (ns, e20) = mem.alloc[usize](a, n + 1usize)
            if e20 != ok { ret (zero, e20) }
            var nsylr = 0usize
            ttsil = 0.0f64
            k = 1usize
            while k <= kk {
                var ntt = 0usize
                j = 1usize
                while j <= n {
                    if ncluv[j] == k {
                        ne[ntt] = j
                        ntt += 1usize
                    }
                    j += 1usize
                }
                var jj = 0usize
                while jj < ntt {
                    let nj = ne[jj]
                    var dysb = s * 1.1f64 + 1.0f64
                    negbr[jj] = 0usize
                    var kq = 1usize
                    while kq <= kk {
                        if kq != k {
                            var db = 0.0f64
                            var nbb = 0usize
                            var l = 1usize
                            while l <= n {
                                if ncluv[l] == kq {
                                    nbb += 1usize
                                    if l != nj { db += dys[cd.ind_2(nj, l)] }
                                }
                                l += 1usize
                            }
                            db = db / f64(nbb)
                            if dysb > db {
                                dysb = db
                                negbr[jj] = kq
                            }
                        }
                        kq += 1usize
                    }
                    if ntt > 1usize {
                        var dysa = 0.0f64
                        var l = 0usize
                        while l < ntt {
                            let nl = ne[l]
                            if nj != nl { dysa += dys[cd.ind_2(nj, nl)] }
                            l += 1usize
                        }
                        dysa = dysa / f64(ntt - 1usize)
                        if dysa > 0.0f64 {
                            if dysb > 0.0f64 {
                                if dysb > dysa {
                                    syl[jj] = 1.0f64 - dysa / dysb
                                } else {
                                    if dysb < dysa {
                                        syl[jj] = dysb / dysa - 1.0f64
                                    } else {
                                        syl[jj] = 0.0f64
                                    }
                                }
                                if syl[jj] < 0.0f64 - 1.0f64 {
                                    syl[jj] = 0.0f64 - 1.0f64
                                } else {
                                    if syl[jj] > 1.0f64 { syl[jj] = 1.0f64 }
                                }
                            } else {
                                syl[jj] = 0.0f64 - 1.0f64
                            }
                        } else {
                            if dysb > 0.0f64 {
                                syl[jj] = 1.0f64
                            } else {
                                syl[jj] = 0.0f64
                            }
                        }
                    } else {
                        syl[jj] = 0.0f64
                    }
                    jj += 1usize
                }
                avsyl[k] = 0.0f64
                if ntt > 0usize {
                    jj = 0usize
                    while jj < ntt {
                        var lang = 0usize
                        var symax = 0.0f64 - 2.0f64
                        var l = 0usize
                        while l < ntt {
                            if symax < syl[l] {
                                symax = syl[l]
                                lang = l
                            }
                            l += 1usize
                        }
                        ns[jj] = lang
                        srank[jj] = symax
                        avsyl[k] += srank[jj]
                        syl[lang] = 0.0f64 - 3.0f64
                        jj += 1usize
                    }
                    ttsil += avsyl[k]
                    avsyl[k] = avsyl[k] / f64(ntt)
                    if ntt == 1usize {
                        silinf[nsylr] = f64(k)
                        silinf[nsylr + n] = f64(negbr[0usize])
                        silinf[nsylr + 2usize * n] = 0.0f64
                        silinf[nsylr + 3usize * n] = f64(ne[0usize])
                        nsylr += 1usize
                    } else {
                        jj = 0usize
                        while jj < ntt {
                            let lplac = ns[jj]
                            silinf[nsylr] = f64(k)
                            silinf[nsylr + n] = f64(negbr[lplac])
                            silinf[nsylr + 2usize * n] = srank[jj]
                            silinf[nsylr + 3usize * n] = f64(ne[lplac])
                            nsylr += 1usize
                            jj += 1usize
                        }
                    }
                }
                k += 1usize
            }
            ttsil = ttsil / f64(n)
        }
    }
    k = 1usize
    while k <= kk {
        avsil_out[k - 1usize] = avsyl[k]
        k += 1usize
    }
    let (med_out, e21) = mem.alloc[usize](a, kk)
    if e21 != ok { ret (zero, e21) }
    let (isol_out, e22) = mem.alloc[usize](a, kk)
    if e22 != ok { ret (zero, e22) }
    let (clu_out, e23) = mem.alloc[usize](a, n)
    if e23 != ok { ret (zero, e23) }
    k = 0usize
    while k < kk {
        med_out[k] = med[k + 1usize]
        isol_out[k] = nisol[k + 1usize]
        k += 1usize
    }
    i = 0usize
    while i < n {
        clu_out[i] = ncluv[i + 1usize]
        i += 1usize
    }
    ret (PamOut { med: med_out, clu: clu_out, obj0: obj[0usize], obj1: obj[1usize], isol: isol_out, clusinf: clusinf, silinf: silinf, avsil: avsil_out, ttsil: ttsil, dosyl: dosyl }, ok)
}

// pam(medoids = "random", nstart): the first start is sample.int(n, kk), each further start is another one and the best swap
// objective wins (the earlier one on a tie). nstart 1 is variant "faster"'s default.
fn pam_random(a: *mem.Arena, dys: []const f64, n: usize, kk: usize, nstart: usize, do_swap: bool, pamonce: usize, all_stats: bool, rg: *rr.Rng) -> (PamOut, err) {
    let (m0, e0) = rr.sample_int(a, rg, i64(n), i64(kk), false)
    if e0 != ok { ret (zero, e0) }
    let (start, e1) = mem.alloc[usize](a, kk)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < kk {
        start[i] = usize(m0[i])
        i += 1usize
    }
    let (best0, e2) = pam_core(a, dys, n, kk, start, do_swap, pamonce, all_stats)
    if e2 != ok { ret (zero, e2) }
    var best = best0
    var it = 2usize
    while it <= nstart {
        let (m1, e3) = rr.sample_int(a, rg, i64(n), i64(kk), false)
        if e3 != ok { ret (zero, e3) }
        i = 0usize
        while i < kk {
            start[i] = usize(m1[i])
            i += 1usize
        }
        let (r, e4) = pam_core(a, dys, n, kk, start, do_swap, pamonce, all_stats)
        if e4 != ok { ret (zero, e4) }
        if r.obj1 < best.obj1 { best = r }
        it += 1usize
    }
    ret (best, ok)
}

// clara()'s own generator
fn clara_randm(nrun: usize) -> usize {
    ret (nrun * 5761usize + 999usize) & 65535usize
}

type ClaraOut = struct {
    sample: []usize,
    imed: []usize,
    clustering: []usize,
    obj: f64,
    size: []usize,
    maxdis: []f64,
    avdis: []f64,
    ratdis: []f64,
    avsil: []f64,
    ttsil: f64,
    silinf: []f64,
    dys: []f64,
    jstop: usize
}

// dysta2(): the dissimilarities of the sub-sample nsel[0..nsam) (1-based observation numbers); true when some pair has no
// distance (those get -1)
fn clara_dysta2(x: []const f64, n: usize, p: usize, nsam: usize, nsel: []const usize, dys: []f64, diss_kind: usize, has_na: bool) -> bool {
    var toomany = false
    var nlk = 0usize
    dys[0usize] = 0.0f64
    var l = 1usize
    while l < nsam {
        let lsel = nsel[l]
        var k = 0usize
        while k < l {
            let ksel = nsel[k]
            nlk += 1usize
            var npres = 0usize
            var n_ones = 0usize
            var clk = 0.0f64
            var j = 0usize
            while j < p {
                let u = x[(lsel - 1usize) * p + j]
                let v = x[(ksel - 1usize) * p + j]
                var present = true
                if has_na && (u != u || v != v) { present = false }
                if present {
                    npres += 1usize
                    if diss_kind == 1usize {
                        clk += (u - v) * (u - v)
                    } else {
                        if diss_kind == 3usize {
                            if u > 0.9f64 && v > 0.9f64 {
                                clk += 1.0f64
                                n_ones += 1usize
                            } else {
                                if u > 0.9f64 || v > 0.9f64 { n_ones += 1usize }
                            }
                        } else {
                            clk += math.abs[f64](u - v)
                        }
                    }
                }
                j += 1usize
            }
            if npres == 0usize {
                toomany = true
                dys[nlk] = 0.0f64 - 1.0f64
            } else {
                let d1 = clk * (f64(p) / f64(npres))
                if diss_kind == 1usize {
                    dys[nlk] = math.sqrt[f64](d1)
                } else {
                    if diss_kind == 3usize {
                        dys[nlk] = 1.0f64 - clk / f64(n_ones)
                    } else {
                        dys[nlk] = d1
                    }
                }
            }
            k += 1usize
        }
        l += 1usize
    }
    ret toomany
}

// bswap2(): BUILD and SWAP of one sample; nrepr[1..n] flags the medoids, dysma, dysmb and beter are scratch (1-based)
fn clara_bswap2(kk: usize, n: usize, s0: f64, dys: []const f64, pam_like: bool, nrepr: []usize, dysma: []f64, dysmb: []f64, beter: []f64) {
    let s = s0 * 1.1f64 + 1.0f64
    var i = 1usize
    while i <= n {
        nrepr[i] = 0usize
        dysma[i] = s
        i += 1usize
    }
    var k = 0usize
    while k < kk {
        var nmax = 0usize
        var ammax = 0.0f64
        i = 1usize
        while i <= n {
            if nrepr[i] == 0usize {
                beter[i] = 0.0f64
                var j = 1usize
                while j <= n {
                    let cmd = dysma[j] - dys[cd.ind_2(i, j)]
                    if cmd > 0.0f64 { beter[i] += cmd }
                    j += 1usize
                }
                if ammax <= beter[i] {
                    ammax = beter[i]
                    nmax = i
                }
            }
            i += 1usize
        }
        nrepr[nmax] = 1usize
        var j = 1usize
        while j <= n {
            let ij = cd.ind_2(nmax, j)
            if dysma[j] > dys[ij] { dysma[j] = dys[ij] }
            j += 1usize
        }
        k += 1usize
    }
    if kk == 1usize { ret }
    var improving = true
    while improving {
        improving = false
        var j = 1usize
        while j <= n {
            dysma[j] = s
            dysmb[j] = s
            i = 1usize
            while i <= n {
                if nrepr[i] != 0usize {
                    let ij = cd.ind_2(i, j)
                    if dysma[j] > dys[ij] {
                        dysmb[j] = dysma[j]
                        dysma[j] = dys[ij]
                    } else {
                        if dysmb[j] > dys[ij] { dysmb[j] = dys[ij] }
                    }
                }
                i += 1usize
            }
            j += 1usize
        }
        var dzsky = 1.0f64
        var hbest = 0usize
        var nbest = 0usize
        var h = 1usize
        while h <= n {
            if nrepr[h] == 0usize {
                i = 1usize
                while i <= n {
                    if nrepr[i] != 0usize {
                        var dz = 0.0f64
                        j = 1usize
                        while j <= n {
                            let ij = cd.ind_2(i, j)
                            let hj = cd.ind_2(h, j)
                            if dys[ij] == dysma[j] {
                                var small = dysmb[j]
                                if pam_like {
                                    if dysmb[j] > dys[hj] { small = dys[hj] }
                                } else {
                                    if dysmb[j] > dys[ij] { small = dys[hj] }
                                }
                                dz += 0.0f64 - dysma[j] + small
                            } else {
                                if dys[hj] < dysma[j] { dz += 0.0f64 - dysma[j] + dys[hj] }
                            }
                            j += 1usize
                        }
                        if dzsky > dz {
                            dzsky = dz
                            hbest = h
                            nbest = i
                        }
                    }
                    i += 1usize
                }
            }
            h += 1usize
        }
        if dzsky < 0.0f64 {
            nrepr[hbest] = 1usize
            nrepr[nbest] = 0usize
            improving = true
        }
    }
}

// selec(): assign all n objects to the nearest of the sample's medoids; true when an object could not be assigned.
// nr, ttd, radus, ratt are 1-based outputs of kk entries (medoids as observation numbers, mean and maximal distance, isolation)
fn clara_selec(a: *mem.Arena, kk: usize, n: usize, p: usize, diss_kind: usize, nsam: usize, has_na: bool, nrepr: []const usize, nsel: []const usize, dys: []const f64, x: []const f64, nr: []usize, ttd: []f64, radus: []f64, ratt: []f64, correct_d: bool, zb: []f64) -> (bool, err) {
    let (ns, e1) = mem.alloc[usize](a, kk + 1usize)
    if e1 != ok { ret (true, e1) }
    let (np, e2) = mem.alloc[usize](a, kk + 1usize)
    if e2 != ok { ret (true, e2) }
    let (nw, e3) = mem.alloc[usize](a, kk + 1usize)
    if e3 != ok { ret (true, e3) }
    let (nrnew, e4) = mem.alloc[usize](a, kk + 1usize)
    if e4 != ok { ret (true, e4) }
    let (nsnew, e5) = mem.alloc[usize](a, kk + 1usize)
    if e5 != ok { ret (true, e5) }
    let (npnew, e6) = mem.alloc[usize](a, kk + 1usize)
    if e6 != ok { ret (true, e6) }
    let (ttnew, e7) = mem.alloc[f64](a, kk + 1usize)
    if e7 != ok { ret (true, e7) }
    let (rdnew, e8) = mem.alloc[f64](a, kk + 1usize)
    if e8 != ok { ret (true, e8) }
    var jk = 0usize
    var j = 1usize
    while j <= nsam {
        if nrepr[j] != 0usize {
            jk += 1usize
            nr[jk] = nsel[j - 1usize]
            ns[jk] = 0usize
            ttd[jk] = 0.0f64
            radus[jk] = 0.0f64 - 1.0f64
            np[jk] = j
        }
        j += 1usize
    }
    let pp = f64(p)
    zb[0usize] = 0.0f64
    var newf = 0usize
    var i = 1usize
    while i <= n {
        var jkabc = 0usize
        var dsum = 0.0f64
        var dnull = 0.0f64 - 9.0f64
        if !has_na {
            jk = 1usize
            while jk <= kk {
                dsum = 0.0f64
                let nr_k = nr[jk]
                var skip = false
                if nr_k != i {
                    var n_ones = 0usize
                    var tra = 0.0f64
                    var jp = 0usize
                    while jp < p {
                        let xa = x[(nr_k - 1usize) * p + jp]
                        let xb = x[(i - 1usize) * p + jp]
                        if diss_kind == 3usize {
                            if xa > 0.9f64 && xb > 0.9f64 {
                                tra += 1.0f64
                                n_ones += 1usize
                            } else {
                                if xa > 0.9f64 || xb > 0.9f64 { n_ones += 1usize }
                            }
                        } else {
                            tra = math.abs[f64](xa - xb)
                            if diss_kind == 1usize { tra = tra * tra }
                            dsum += tra
                        }
                        jp += 1usize
                    }
                    if diss_kind == 3usize { dsum = 1.0f64 - tra / f64(n_ones) }
                    if jk != 1usize && dsum >= dnull { skip = true }
                }
                if !skip {
                    dnull = dsum
                    jkabc = jk
                }
                jk += 1usize
            }
        } else {
            var first = true
            jk = 1usize
            while jk <= kk {
                dsum = 0.0f64
                let nr_k = nr[jk]
                var skip = false
                if nr_k != i {
                    var nobs = 0usize
                    var n_ones = 0usize
                    var tra = 0.0f64
                    var jp = 0usize
                    while jp < p {
                        let xa = x[(nr_k - 1usize) * p + jp]
                        let xb = x[(i - 1usize) * p + jp]
                        if !(xa != xa || xb != xb) {
                            nobs += 1usize
                            if diss_kind == 3usize {
                                if xa > 0.9f64 && xb > 0.9f64 {
                                    tra += 1.0f64
                                    n_ones += 1usize
                                } else {
                                    if xa > 0.9f64 || xb > 0.9f64 { n_ones += 1usize }
                                }
                            } else {
                                tra = math.abs[f64](xa - xb)
                                if diss_kind == 1usize { tra = tra * tra }
                                dsum += tra
                            }
                        }
                        jp += 1usize
                    }
                    if nobs == 0usize {
                        skip = true
                    } else {
                        if diss_kind == 3usize { dsum = 1.0f64 - tra / f64(n_ones) }
                        if correct_d {
                            dsum = dsum * (pp / f64(nobs))
                        } else {
                            dsum = dsum * (f64(nobs) / pp)
                        }
                    }
                }
                if !skip {
                    if first {
                        first = false
                        dnull = dsum
                        jkabc = jk
                    } else {
                        if !(dnull <= dsum) {
                            dnull = dsum
                            jkabc = jk
                        }
                    }
                }
                jk += 1usize
            }
            if first { ret (true, ok) }
        }
        if diss_kind == 1usize { dnull = math.sqrt[f64](dnull) }
        zb[0usize] += dnull
        ttd[jkabc] += dnull
        if radus[jkabc] < dnull { radus[jkabc] = dnull }
        ns[jkabc] += 1usize
        if newf < kk {
            var seen = false
            var jn = 1usize
            while jn <= newf {
                if jkabc == nw[jn] { seen = true }
                jn += 1usize
            }
            if !seen {
                newf += 1usize
                nw[newf] = jkabc
            }
        }
        i += 1usize
    }
    j = 1usize
    while j <= kk {
        let nj = nw[j]
        nrnew[j] = nr[nj]
        nsnew[j] = ns[nj]
        npnew[j] = np[nj]
        ttnew[j] = ttd[nj]
        rdnew[j] = radus[nj]
        j += 1usize
    }
    j = 1usize
    while j <= kk {
        nr[j] = nrnew[j]
        ns[j] = nsnew[j]
        np[j] = npnew[j]
        ttd[j] = ttnew[j] / f64(ns[j])
        radus[j] = rdnew[j]
        j += 1usize
    }
    if kk > 1usize {
        var ka = 1usize
        while ka <= kk {
            var first = true
            let npa = np[ka]
            var kb = 1usize
            while kb <= kk {
                if kb != ka {
                    let npb = np[kb]
                    let npab = cd.ind_2(npa, npb)
                    var take = true
                    if first {
                        first = false
                    } else {
                        if dys[npab] >= ratt[ka] { take = false }
                    }
                    if take {
                        ratt[ka] = dys[npab]
                        if ratt[ka] == 0.0f64 { ratt[ka] = 0.0f64 - 1.0f64 }
                    }
                }
                kb += 1usize
            }
            if ratt[ka] > 0.0f64 - 0.5f64 { ratt[ka] = radus[ka] / ratt[ka] }
            ka += 1usize
        }
    }
    ret (false, ok)
}

// clara(x, k, metric, samples, sampsize, rngR, pamLike, correct.d): diss_kind 1 euclidean, 2 manhattan, 3 jaccard. x is n by p
// row-major (already standardised when stand is wanted). rg is read only with rng_r (R's generator, seeded by the caller).
fn clara_core(a: *mem.Arena, x: []const f64, n: usize, p: usize, kk: usize, nran: usize, nsam: usize, diss_kind: usize, rng_r: bool, pam_like: bool, correct_d: bool, rg: *rr.Rng) -> (ClaraOut, err) {
    var has_na = false
    var i = 0usize
    while i < n * p {
        if x[i] != x[i] { has_na = true }
        i += 1usize
    }
    let nsamb = nsam * 2usize
    let full_sample = n == nsam
    let lrg_sam = n < nsamb
    var n_sam = nsam
    if lrg_sam { n_sam = n - nsam }
    let n_dys = nsam * (nsam - 1usize) / 2usize
    let (dys, e1) = mem.alloc[f64](a, n_dys + 1usize)
    if e1 != ok { ret (zero, e1) }
    let (nrepr, e2) = mem.alloc[usize](a, nsam + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (nsel, e3) = mem.alloc[usize](a, nsam + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (nbest, e4) = mem.alloc[usize](a, nsam + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (nr, e5) = mem.alloc[usize](a, kk + 1usize)
    if e5 != ok { ret (zero, e5) }
    let (nrx, e6) = mem.alloc[usize](a, kk + 1usize)
    if e6 != ok { ret (zero, e6) }
    let (radus, e7) = mem.alloc[f64](a, kk + 1usize)
    if e7 != ok { ret (zero, e7) }
    let (ttd, e8) = mem.alloc[f64](a, kk + 1usize)
    if e8 != ok { ret (zero, e8) }
    let (ratt, e9) = mem.alloc[f64](a, kk + 1usize)
    if e9 != ok { ret (zero, e9) }
    let (ttbes, e10) = mem.alloc[f64](a, kk + 1usize)
    if e10 != ok { ret (zero, e10) }
    let (rdbes, e11) = mem.alloc[f64](a, kk + 1usize)
    if e11 != ok { ret (zero, e11) }
    let (rabes, e12) = mem.alloc[f64](a, kk + 1usize)
    if e12 != ok { ret (zero, e12) }
    let (t1, e13) = mem.alloc[f64](a, nsam + 1usize)
    if e13 != ok { ret (zero, e13) }
    let (t2, e14) = mem.alloc[f64](a, nsam + 1usize)
    if e14 != ok { ret (zero, e14) }
    let (t3, e15) = mem.alloc[f64](a, nsam + 1usize)
    if e15 != ok { ret (zero, e15) }
    let (zbv, e16) = mem.alloc[f64](a, 1usize)
    if e16 != ok { ret (zero, e16) }
    i = 0usize
    while i <= nsam {
        nrepr[i] = 0usize
        nsel[i] = 0usize
        nbest[i] = 0usize
        t1[i] = 0.0f64
        t2[i] = 0.0f64
        t3[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i <= kk {
        nr[i] = 0usize
        nrx[i] = 0usize
        radus[i] = 0.0f64
        ttd[i] = 0.0f64
        ratt[i] = 0.0f64
        ttbes[i] = 0.0f64
        rdbes[i] = 0.0f64
        rabes[i] = 0.0f64
        i += 1usize
    }
    let rnn = f64(n)
    var zba = 0.0f64 - 1.0f64
    var sx = 0.0f64 - 1.0f64
    var nrun = 0usize
    var kall = false
    var nunfs = 0usize
    var jran = 1usize
    while jran <= nran {
        if !full_sample {
            var ntt = 0usize
            var skip_fill = false
            if kall && nunfs + 1usize != jran && !lrg_sam {
                var jk = 0usize
                while jk < kk {
                    nsel[jk] = nrx[jk]
                    jk += 1usize
                }
                jk = 0usize
                while jk + 1usize < kk {
                    var nsm = nsel[jk]
                    var jsm = jk
                    var jkk = jk + 1usize
                    while jkk < kk {
                        if nsm > nsel[jkk] {
                            nsm = nsel[jkk]
                            jsm = jkk
                        }
                        jkk += 1usize
                    }
                    nsel[jsm] = nsel[jk]
                    nsel[jk] = nsm
                    jk += 1usize
                }
                ntt = kk
            } else {
                var placed = false
                while !placed {
                    var u = 0.0f64
                    if rng_r {
                        u = rr.unif(rg)
                    } else {
                        nrun = clara_randm(nrun)
                        u = f64(nrun) / 65536.0f64
                    }
                    var rand_k = 1usize + usize(rnn * u)
                    if rand_k > n { rand_k = n }
                    var reject = false
                    if kall {
                        var jk = 0usize
                        while jk < kk {
                            if rand_k == nrx[jk] { reject = true }
                            jk += 1usize
                        }
                    }
                    if !reject {
                        nsel[ntt] = rand_k
                        placed = true
                    }
                }
                ntt += 1usize
                if ntt == n_sam { skip_fill = true }
            }
            if !skip_fill {
                while ntt < n_sam {
                    var placed = false
                    while !placed {
                        var u = 0.0f64
                        if rng_r {
                            u = rr.unif(rg)
                        } else {
                            nrun = clara_randm(nrun)
                            u = f64(nrun) / 65536.0f64
                        }
                        var rand_k = 1usize + usize(rnn * u)
                        if rand_k > n { rand_k = n }
                        var reject = false
                        if kall && lrg_sam {
                            var jk = 0usize
                            while jk < kk {
                                if rand_k == nrx[jk] { reject = true }
                                jk += 1usize
                            }
                        }
                        if !reject {
                            var ka = 0usize
                            var inserted = false
                            var dup = false
                            while ka < ntt && !inserted && !dup {
                                if nsel[ka] >= rand_k {
                                    if nsel[ka] == rand_k {
                                        dup = true
                                    } else {
                                        var na = ntt
                                        while na > ka {
                                            nsel[na] = nsel[na - 1usize]
                                            na -= 1usize
                                        }
                                        nsel[ka] = rand_k
                                        inserted = true
                                    }
                                }
                                ka += 1usize
                            }
                            if !dup {
                                if !inserted { nsel[ntt] = rand_k }
                                placed = true
                            }
                        }
                    }
                    ntt += 1usize
                }
            }
            if lrg_sam {
                var jk = 0usize
                var js = 0usize
                var jx = 1usize
                while jx <= n {
                    if jk < n_sam && nsel[jk] == jx {
                        jk += 1usize
                    } else {
                        nrepr[js] = jx
                        js += 1usize
                    }
                    jx += 1usize
                }
                var q = 0usize
                while q < nsam {
                    nsel[q] = nrepr[q]
                    q += 1usize
                }
            }
        } else {
            var q = 0usize
            while q < nsam {
                nsel[q] = q + 1usize
                q += 1usize
            }
        }
        let toomany = clara_dysta2(x, n, p, nsam, nsel, dys, diss_kind, has_na)
        if toomany {
            nunfs += 1usize
        } else {
            var s = 0.0f64
            var l = 1usize
            while l <= n_dys {
                if s < dys[l] { s = dys[l] }
                l += 1usize
            }
            clara_bswap2(kk, nsam, s, dys, pam_like, nrepr, t1, t2, t3)
            let (nafs, e17) = clara_selec(a, kk, n, p, diss_kind, nsam, has_na, nrepr, nsel, dys, x, nr, ttd, radus, ratt, correct_d, zbv)
            if e17 != ok { ret (zero, e17) }
            let zb = zbv[0usize]
            if nafs {
                nunfs += 1usize
            } else {
                if !kall || zba > zb {
                    kall = true
                    zba = zb
                    var jk = 0usize
                    while jk < kk {
                        ttbes[jk] = ttd[jk + 1usize]
                        rdbes[jk] = radus[jk + 1usize]
                        rabes[jk] = ratt[jk + 1usize]
                        nrx[jk] = nr[jk + 1usize]
                        jk += 1usize
                    }
                    var js = 0usize
                    while js < nsam {
                        nbest[js] = nsel[js]
                        js += 1usize
                    }
                    sx = s
                }
            }
            if full_sample { break }
        }
        jran += 1usize
    }
    var jstop = 0usize
    let obj = zba / rnn
    if nunfs >= nran { jstop = 1usize }
    if jstop == 0usize && !kall { jstop = 2usize }
    let (clu, e18) = mem.alloc[usize](a, n)
    if e18 != ok { ret (zero, e18) }
    let (size, e19) = mem.alloc[usize](a, kk)
    if e19 != ok { ret (zero, e19) }
    let (silinf, e20) = mem.alloc[f64](a, nsam * 4usize)
    if e20 != ok { ret (zero, e20) }
    let (avsil, e21) = mem.alloc[f64](a, kk)
    if e21 != ok { ret (zero, e21) }
    let (sample, e22) = mem.alloc[usize](a, nsam)
    if e22 != ok { ret (zero, e22) }
    let (imed, e23) = mem.alloc[usize](a, kk)
    if e23 != ok { ret (zero, e23) }
    let (maxdis, e24) = mem.alloc[f64](a, kk)
    if e24 != ok { ret (zero, e24) }
    let (avdis, e25) = mem.alloc[f64](a, kk)
    if e25 != ok { ret (zero, e25) }
    let (ratdis, e26) = mem.alloc[f64](a, kk)
    if e26 != ok { ret (zero, e26) }
    var ttsil = 0.0f64
    i = 0usize
    while i < nsam * 4usize {
        silinf[i] = 0.0f64
        i += 1usize
    }
    if jstop != 0usize {
        ret (ClaraOut { sample: sample, imed: imed, clustering: clu, obj: obj, size: size, maxdis: maxdis, avdis: avdis, ratdis: ratdis, avsil: avsil, ttsil: ttsil, silinf: silinf, dys: dys, jstop: jstop }, ok)
    }
    let toomany2 = clara_dysta2(x, n, p, nsam, nbest, dys, diss_kind, has_na)
    if toomany2 { ret (zero, BadPam) }
    // resul(): assign every object to the nearest medoid
    let pp = f64(p)
    i = 0usize
    while i < n {
        var is_med = false
        var jk = 0usize
        while jk < kk {
            if nrx[jk] == i + 1usize { is_med = true }
            jk += 1usize
        }
        if !is_med {
            var jksky = 0usize
            var dnull = 0.0f64 - 9.0f64
            jk = 0usize
            while jk < kk {
                var dsum = 0.0f64
                let nrjk = nrx[jk] - 1usize
                var nobs = 0usize
                var jj = 0usize
                while jj < p {
                    let xa = x[nrjk * p + jj]
                    let xb = x[i * p + jj]
                    if !(has_na && (xa != xa || xb != xb)) {
                        nobs += 1usize
                        var tra = math.abs[f64](xa - xb)
                        if diss_kind == 1usize { tra = tra * tra }
                        dsum += tra
                    }
                    jj += 1usize
                }
                if diss_kind == 1usize { dsum = math.sqrt[f64](dsum) }
                if has_na {
                    if correct_d {
                        dsum = dsum * (pp / f64(nobs))
                    } else {
                        dsum = dsum * (f64(nobs) / pp)
                    }
                }
                if jk == 0usize || dnull > dsum {
                    dnull = dsum
                    jksky = jk
                }
                jk += 1usize
            }
            clu[i] = jksky + 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < kk {
        clu[nrx[i] - 1usize] = i + 1usize
        i += 1usize
    }
    var ka = 0usize
    while ka < kk {
        size[ka] = 0usize
        i = 0usize
        while i < n {
            if clu[i] == ka + 1usize { size[ka] += 1usize }
            i += 1usize
        }
        ka += 1usize
    }
    if kk > 1usize {
        // black(): the silhouette of the best sample
        let (ncluv, e27) = mem.alloc[usize](a, nsam + 1usize)
        if e27 != ok { ret (zero, e27) }
        let (nsend, e28) = mem.alloc[usize](a, nsam + 1usize)
        if e28 != ok { ret (zero, e28) }
        let (nelem, e29) = mem.alloc[usize](a, nsam + 1usize)
        if e29 != ok { ret (zero, e29) }
        let (negbr, e30) = mem.alloc[usize](a, nsam + 1usize)
        if e30 != ok { ret (zero, e30) }
        let (syl, e31) = mem.alloc[f64](a, nsam + 1usize)
        if e31 != ok { ret (zero, e31) }
        let (srank, e32) = mem.alloc[f64](a, nsam + 1usize)
        if e32 != ok { ret (zero, e32) }
        var l = 1usize
        while l <= nsam {
            ncluv[l] = clu[nbest[l - 1usize] - 1usize]
            l += 1usize
        }
        var nsylr = 0usize
        ttsil = 0.0f64
        var numcl = 1usize
        while numcl <= kk {
            var ntt = 0usize
            var j = 1usize
            while j <= nsam {
                if ncluv[j] == numcl {
                    ntt += 1usize
                    nelem[ntt] = j
                }
                j += 1usize
            }
            j = 1usize
            while j <= ntt {
                let nj = nelem[j]
                var dysb = sx * 1.1f64 + 1.0f64
                negbr[j] = 0usize
                var nclu = 1usize
                while nclu <= kk {
                    if nclu != numcl {
                        var nbb = 0usize
                        var db = 0.0f64
                        l = 1usize
                        while l <= nsam {
                            if ncluv[l] == nclu {
                                nbb += 1usize
                                db += dys[cd.ind_2(nj, l)]
                            }
                            l += 1usize
                        }
                        db = db / f64(nbb)
                        if db < dysb {
                            dysb = db
                            negbr[j] = nclu
                        }
                    }
                    nclu += 1usize
                }
                if ntt == 1usize {
                    syl[j] = 0.0f64
                } else {
                    var dysa = 0.0f64
                    l = 1usize
                    while l <= ntt {
                        let nl = nelem[l]
                        dysa += dys[cd.ind_2(nj, nl)]
                        l += 1usize
                    }
                    dysa = dysa / f64(ntt - 1usize)
                    if dysa <= 0.0f64 {
                        if dysb > 0.0f64 {
                            syl[j] = 1.0f64
                        } else {
                            syl[j] = 0.0f64
                        }
                    } else {
                        if dysb > 0.0f64 {
                            if dysb > dysa {
                                syl[j] = 1.0f64 - dysa / dysb
                            } else {
                                if dysb < dysa {
                                    syl[j] = dysb / dysa - 1.0f64
                                } else {
                                    syl[j] = 0.0f64
                                }
                            }
                            if syl[j] < 0.0f64 - 1.0f64 {
                                syl[j] = 0.0f64 - 1.0f64
                            } else {
                                if syl[j] > 1.0f64 { syl[j] = 1.0f64 }
                            }
                        } else {
                            syl[j] = 0.0f64 - 1.0f64
                        }
                    }
                }
                j += 1usize
            }
            avsil[numcl - 1usize] = 0.0f64
            j = 1usize
            while j <= ntt {
                var lang = 0usize
                var symax = 0.0f64 - 2.0f64
                l = 1usize
                while l <= ntt {
                    if syl[l] > symax {
                        symax = syl[l]
                        lang = l
                    }
                    l += 1usize
                }
                nsend[j] = lang
                srank[j] = syl[lang]
                avsil[numcl - 1usize] += srank[j]
                syl[lang] = 0.0f64 - 3.0f64
                j += 1usize
            }
            ttsil += avsil[numcl - 1usize]
            avsil[numcl - 1usize] = avsil[numcl - 1usize] / f64(ntt)
            if ntt >= 2usize {
                l = 1usize
                while l <= ntt {
                    let lplac = nsend[l]
                    nsylr += 1usize
                    silinf[nsylr - 1usize] = f64(numcl)
                    silinf[nsylr - 1usize + nsam] = f64(negbr[lplac])
                    silinf[nsylr - 1usize + 2usize * nsam] = srank[l]
                    silinf[nsylr - 1usize + 3usize * nsam] = f64(nbest[nelem[lplac] - 1usize])
                    l += 1usize
                }
            } else {
                nsylr += 1usize
                silinf[nsylr - 1usize] = f64(numcl)
                silinf[nsylr - 1usize + nsam] = f64(negbr[1usize])
                silinf[nsylr - 1usize + 2usize * nsam] = 0.0f64
                silinf[nsylr - 1usize + 3usize * nsam] = f64(nbest[nelem[1usize] - 1usize])
            }
            numcl += 1usize
        }
        ttsil = ttsil / f64(nsam)
    }
    i = 0usize
    while i < nsam {
        sample[i] = nbest[i]
        i += 1usize
    }
    i = 0usize
    while i < kk {
        imed[i] = nrx[i]
        maxdis[i] = rdbes[i]
        avdis[i] = ttbes[i]
        ratdis[i] = rabes[i]
        i += 1usize
    }
    ret (ClaraOut { sample: sample, imed: imed, clustering: clu, obj: obj, size: size, maxdis: maxdis, avdis: avdis, ratdis: ratdis, avsil: avsil, ttsil: ttsil, silinf: silinf, dys: dys, jstop: jstop }, ok)
}

// medoids(x, clustering): per cluster, in sorted label order, the 1-based observation pam(rows of the cluster, k = 1) picks;
// returns the number of clusters (a cluster of one observation is an error, as in R)
fn cluster_medoids(a: *mem.Arena, x: []const f64, n: usize, p: usize, cl: []const i64, metric: usize, out: []usize) -> (usize, err) {
    var ncl = 0usize
    var lo = 0i64
    var first = true
    var done = 0usize
    while done < n {
        var cur = 0i64
        var have = false
        var i = 0usize
        while i < n {
            if first || cl[i] > lo {
                if !have || cl[i] < cur {
                    cur = cl[i]
                    have = true
                }
            }
            i += 1usize
        }
        var size = 0usize
        i = 0usize
        while i < n {
            if cl[i] == cur { size += 1usize }
            i += 1usize
        }
        if size < 2usize { ret (0usize, BadPam) }
        let (rows, e1) = mem.alloc[usize](a, size)
        if e1 != ok { ret (0usize, e1) }
        let (sub, e2) = mem.alloc[f64](a, size * p)
        if e2 != ok { ret (0usize, e2) }
        var m = 0usize
        i = 0usize
        while i < n {
            if cl[i] == cur {
                rows[m] = i
                var j = 0usize
                while j < p {
                    sub[m * p + j] = x[i * p + j]
                    j += 1usize
                }
                m += 1usize
            }
            i += 1usize
        }
        let (dys, e3) = mem.alloc[f64](a, size * (size - 1usize) / 2usize + 1usize)
        if e3 != ok { ret (0usize, e3) }
        if cd.dysta(sub, size, p, metric, dys) != 0usize { ret (0usize, BadPam) }
        let empty: []const usize = zero
        let (r, e4) = pam_core(a, dys, size, 1usize, empty, true, 0usize, true)
        if e4 != ok { ret (0usize, e4) }
        out[ncl] = rows[r.med[0usize] - 1usize] + 1usize
        ncl += 1usize
        done += size
        lo = cur
        first = false
    }
    ret (ncl, ok)
}
