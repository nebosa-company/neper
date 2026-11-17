// R package cluster: the dissimilarity kernels (dysta, daisy), pam in every variant (BUILD, SWAP, pamonce 0..6, given medoids), clara
// (its own generator or R's), silhouette (sildist) -- ported from cluster 2.1.8.2's pam.c, clara.c, daisy.c, dysta.c and sildist.c.
//
// Layout follows the C code: a data matrix x is column-major n by p (x[i + j * n]), a dissimilarity is the packed lower triangle
// dys[ind2(i, j)] with dys[0] = 0 and 1-based i, j; every working array is 1-based (index 0 unused) as in the C source.
// Missing data: a column with an NA has jtmd[j] = -1 and the NA is replaced by valmd[j] (na_prepare does it as R does).
//
// agnes, diana, mona and the coefficients are in e.algo.stat.clustertree; fanny, ellipsoidhull and clusGap in e.algo.stat.clusterfuzzy.

use e.algo.rand.r as rng
use e.math
use e.mem

error BadArgument

type PamFit = struct {
    clu: []usize, med: []usize, obj_build: f64, obj_swap: f64, isol: []usize, clusinf: []f64,
    silinfo: []f64, avsil: []f64, ttsil: f64, has_sil: bool
}

fn zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zu(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (v, e) = mem.alloc[usize](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0usize
        i += 1usize
    }
    ret (v, ok)
}

fn zi(a: *mem.Arena, n: usize) -> ([]i64, err) {
    let (v, e) = mem.alloc[i64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0i64
        i += 1usize
    }
    ret (v, ok)
}

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

// the index of d(l, j) in the packed dys: 0 on the diagonal, (m - 2)(m - 1) / 2 + n for m > n (1-based)
fn ind2(l: usize, j: usize) -> usize {
    if l == j { ret 0usize }
    var m = l
    var q = j
    if j > l {
        m = j
        q = l
    }
    ret (m - 2usize) * (m - 1usize) / 2usize + q
}

// (h - 2)(h - 1) / 2 with h = 1 giving 0, the base of the pamonce 2, 5, 6 row walk
fn tri(h: usize) -> usize {
    if h < 2usize { ret 0usize }
    ret (h - 2usize) * (h - 1usize) / 2usize
}

fn nhalf_of(n: usize) -> usize {
    if n % 2usize == 0usize { ret n / 2usize * (n - 1usize) + 1usize }
    ret (n - 1usize) / 2usize * n + 1usize
}

// R's treatment of NA before the C call: x2[NA] <- 1.1 * max |range|, jtmd[j] = -1 for columns with an NA; returns whether any NA was there.
// x is column-major n by p and has NaN for NA; valmd is filled with the code for every column
fn na_prepare(x: []f64, n: usize, p: usize, jtmd: []i64, valmd: []f64) -> bool {
    var has = false
    var mx = 0.0f64
    var j = 0usize
    while j < p {
        jtmd[j] = 0i64
        var i = 0usize
        while i < n {
            let v = x[i + j * n]
            if v != v {
                jtmd[j] = 0i64 - 1i64
                has = true
            } else {
                if math.abs[f64](v) > mx { mx = math.abs[f64](v) }
            }
            i += 1usize
        }
        j += 1usize
    }
    if !has { ret false }
    let code = 1.1f64 * mx
    j = 0usize
    while j < p {
        valmd[j] = code
        var i = 0usize
        while i < n {
            if x[i + j * n] != x[i + j * n] { x[i + j * n] = code }
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

// dysta: euclidean (ndyst 1) or manhattan (2) dissimilarities of the rows of x (n by p, column-major) into the packed dys; 1 when some pair has no
// variable in common (that entry is -1)
fn dysta(x: []const f64, nn: usize, p: usize, dys: []f64, ndyst: usize, jtmd: []const i64, valmd: []const f64) -> usize {
    var nlk = 0usize
    var jhalt = 0usize
    dys[0usize] = 0.0f64
    let pp = f64(p)
    var l = 1usize
    while l < nn {
        var k = 0usize
        while k < l {
            var clk = 0.0f64
            nlk += 1usize
            var npres = 0usize
            var j = 0usize
            while j < p {
                var skip = false
                if jtmd[j] < 0i64 {
                    if x[l + j * nn] == valmd[j] || x[k + j * nn] == valmd[j] { skip = true }
                }
                if !skip {
                    npres += 1usize
                    let dv = x[l + j * nn] - x[k + j * nn]
                    if ndyst == 1usize { clk += dv * dv } else { clk += math.abs[f64](dv) }
                }
                j += 1usize
            }
            let rpres = f64(npres)
            if npres == 0usize {
                jhalt = 1usize
                dys[nlk] = 0.0f64 - 1.0f64
            } else {
                if ndyst == 1usize { dys[nlk] = math.sqrt[f64](clk * (pp / rpres)) } else { dys[nlk] = clk * (pp / rpres) }
            }
            k += 1usize
        }
        l += 1usize
    }
    ret jhalt
}

// the packed dys of a full n by n matrix d (row-major, symmetric)
fn pack_full(d: []const f64, n: usize, dys: []f64) {
    dys[0usize] = 0.0f64
    var l = 2usize
    while l <= n {
        var k = 1usize
        while k < l {
            dys[ind2(l, k)] = d[(l - 1usize) * n + (k - 1usize)]
            k += 1usize
        }
        l += 1usize
    }
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// pam

// the BUILD and SWAP phases; nrepr[1..n] is 1 for a medoid (given on entry when med_given), obj[0] and obj[1] receive the average distance after each phase.
// dysma, dysmb and beter are n + 1 long scratch; s is the largest dissimilarity
fn bswap(a: *mem.Arena, kk: usize, n: usize, nrepr: []usize, med_given: bool, do_swap: bool, dys: []const f64, s0: f64,
         dysma: []f64, dysmb: []f64, beter: []f64, obj: []f64, pamonce: usize) -> err {
    if pamonce > 6usize { ret BadArgument }
    let s = s0 * 1.1f64 + 1.0f64
    var i = 1usize
    var j = 1usize
    var k = 1usize
    var h = 1usize
    var ij = 0usize
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
                    ij = ind2(i, j)
                    if dysma[j] > dys[ij] { dysma[j] = dys[ij] }
                    j += 1usize
                }
            }
            i += 1usize
        }
    } else {
        k = 1usize
        while k <= kk {
            var nmax = 1usize
            var ammax = 0.0f64
            i = 1usize
            while i <= n {
                if nrepr[i] == 0usize {
                    beter[i] = 0.0f64
                    j = 1usize
                    while j <= n {
                        let cmd = dysma[j] - dys[ind2(i, j)]
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
                ij = ind2(nmax, j)
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
        var dzsky = 0.0f64
        var hbest = 1usize
        var nbest = 1usize
        var kbest = 1usize
        let (medoids, e1) = zu(a, kk + 1usize)
        if e1 != ok { ret e1 }
        let (cm, e2) = zu(a, n + 1usize)
        if e2 != ok { ret e2 }
        let (cmb, e3) = zu(a, n + 1usize)
        if e3 != ok { ret e3 }
        let (fvect, e4) = zf(a, n + 1usize)
        if e4 != ok { ret e4 }
        let (best_h, e5) = zu(a, kk + 1usize)
        if e5 != ok { ret e5 }
        let (best_d, e6) = zf(a, kk + 1usize)
        if e6 != ok { ret e6 }
        let (remove_loss, e7) = zf(a, kk + 1usize)
        if e7 != ok { ret e7 }
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
        var lastswap = 0usize
        var recompute = true
        while true {
            if recompute {
                if pamonce == 0usize {
                    j = 1usize
                    while j <= n {
                        dysma[j] = s
                        dysmb[j] = s
                        i = 1usize
                        while i <= n {
                            if nrepr[i] != 0usize {
                                ij = ind2(i, j)
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
                                let dysij = dys[ind2(medoids[k], j)]
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
                                ij = ind2(i, j)
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
            }
            recompute = true
            dzsky = 1.0f64
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
                                    let hj = ind2(h, j)
                                    ij = ind2(i, j)
                                    if dys[ij] == dysma[j] {
                                        var small = dysmb[j]
                                        if dysmb[j] > dys[hj] { small = dys[hj] }
                                        dz += (0.0f64 - dysma[j] + small)
                                    } else {
                                        if dys[hj] < dysma[j] { dz += (0.0f64 - dysma[j] + dys[hj]) }
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
                                remove_cost += (dysmb[j] - dysma[j])
                                fvect[j] = dysmb[j]
                            } else {
                                fvect[j] = dysma[j]
                            }
                            j += 1usize
                        }
                        if pamonce == 1usize {
                            h = 1usize
                            while h <= n {
                                if nrepr[h] == 0usize {
                                    var add_gain = remove_cost
                                    j = 1usize
                                    while j <= n {
                                        let hj = ind2(h, j)
                                        if dys[hj] < fvect[j] { add_gain += (dys[hj] - fvect[j]) }
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
                        } else {
                            h = 1usize
                            while h <= n {
                                if nrepr[h] == 0usize {
                                    var add_gain = remove_cost - fvect[h]
                                    var ijbase = tri(h)
                                    j = 1usize
                                    while j < h {
                                        let hj = ijbase + j
                                        if dys[hj] < fvect[j] { add_gain += (dys[hj] - fvect[j]) }
                                        j += 1usize
                                    }
                                    ijbase += h
                                    j = h + 1usize
                                    while j <= n {
                                        ijbase += j - 2usize
                                        if dys[ijbase] < fvect[j] { add_gain += (dys[ijbase] - fvect[j]) }
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
                                    let dist_h = dys[ind2(h, j)]
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
                        if pamonce == 4usize {
                            k = 1usize
                            while k <= kk {
                                best_d[k] = 1.0f64
                                k += 1usize
                            }
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
                                        let dist_h = dys[ind2(h, j)]
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
                                        if loss < best_d[k] {
                                            best_d[k] = loss
                                            best_h[k] = h
                                        }
                                        k += 1usize
                                    }
                                }
                                h += 1usize
                            }
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
                        } else {
                            // pamonce 5 and 6 walk the packed row of h
                            if pamonce == 5usize {
                                k = 1usize
                                while k <= kk {
                                    best_d[k] = 1.0f64
                                    k += 1usize
                                }
                            }
                            var h2 = 1usize
                            h = 1usize
                            if pamonce == 6usize { h = lastswap + 1usize }
                            while h2 <= n {
                                if pamonce == 6usize && h == n + 1usize { h = 1usize }
                                if nrepr[h] != 0usize {
                                    h += 1usize
                                    h2 += 1usize
                                    continue
                                }
                                k = 1usize
                                while k <= kk {
                                    beter[k] = 0.0f64
                                    k += 1usize
                                }
                                var acc = 0.0f64 - dysma[h]
                                if pamonce == 5usize { beter[cm[h]] = dysma[h] - dysmb[h] } else { beter[cm[h]] += dysma[h] - dysmb[h] }
                                var ijbase = tri(h)
                                j = 1usize
                                while j < h {
                                    let dist_h = dys[ijbase + j]
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
                                ijbase += h
                                j = h + 1usize
                                while j <= n {
                                    ijbase += j - 2usize
                                    let dist_h = dys[ijbase]
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
                                    if pamonce == 5usize {
                                        if loss < best_d[k] {
                                            best_d[k] = loss
                                            best_h[k] = h
                                        }
                                    } else {
                                        if loss < dzsky {
                                            dzsky = loss
                                            hbest = h
                                            nbest = medoids[k]
                                            kbest = k
                                        }
                                    }
                                    k += 1usize
                                }
                                if pamonce == 6usize && dzsky < 0.0f64 { break }
                                h += 1usize
                                h2 += 1usize
                            }
                            if pamonce == 5usize {
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
            }
            if dzsky < 0.0f64 - 16.0f64 * eps() * math.abs[f64](sky) {
                nrepr[hbest] = 1usize
                nrepr[nbest] = 0usize
                if pamonce != 0usize { medoids[kbest] = hbest }
                if pamonce == 6usize { lastswap = hbest }
                sky += dzsky
                if pamonce == 3usize || pamonce == 6usize {
                    var newloss = 0.0f64
                    j = 1usize
                    while j <= n {
                        let dnew = dys[ind2(hbest, j)]
                        var redo = false
                        if cm[j] == kbest {
                            if dnew < dysmb[j] { dysma[j] = dnew } else { redo = true }
                        } else {
                            if dnew < dysma[j] {
                                cmb[j] = cm[j]
                                dysmb[j] = dysma[j]
                                cm[j] = kbest
                                dysma[j] = dnew
                            } else {
                                if cmb[j] == kbest {
                                    redo = true
                                } else {
                                    if dnew < dysmb[j] {
                                        cmb[j] = kbest
                                        dysmb[j] = dnew
                                    }
                                }
                            }
                        }
                        if redo {
                            var dysmaj = s
                            var dysmbj = s
                            k = 1usize
                            while k <= kk {
                                let dysij = dys[ind2(medoids[k], j)]
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
                    recompute = false
                    continue
                }
                if pamonce == 4usize || pamonce == 5usize {
                    while true {
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
                        if dzsky >= 0.0f64 - 16.0f64 * eps() * math.abs[f64](sky) { break }
                        j = 1usize
                        while j <= n {
                            dysma[j] = s
                            dysmb[j] = s
                            k = 1usize
                            while k <= kk {
                                i = medoids[k]
                                ij = ind2(i, j)
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
                            let hj = ind2(hbest, j)
                            ij = ind2(nbest, j)
                            if dys[ij] == dysma[j] {
                                var small = dysmb[j]
                                if dys[hj] < small { small = dys[hj] }
                                dzsky += (0.0f64 - dysma[j] + small)
                            } else {
                                if dys[hj] < dysma[j] { dzsky += (0.0f64 - dysma[j] + dys[hj]) }
                            }
                            j += 1usize
                        }
                        if dzsky >= 0.0f64 - 16.0f64 * eps() * math.abs[f64](sky) { break }
                        nrepr[hbest] = 1usize
                        nrepr[nbest] = 0usize
                        medoids[kbest] = hbest
                        sky += dzsky
                    }
                }
            } else {
                break
            }
        }
        obj[1usize] = sky / f64(n)
        ret ok
    }
    obj[1usize] = sky / f64(n)
    ret ok
}

// cstat: the clustering (ncluv), the medoid of each cluster (med) and the statistics of each cluster; every array is 1-based
fn cstat(kk: usize, nn: usize, nsend: []usize, nrepr: []usize, all_stats: bool, radus: []f64, damer: []f64, avsyl: []f64, separ: []f64,
         s: f64, dys: []const f64, ncluv: []usize, nelem: []usize, med: []usize, nisol: []usize) -> bool {
    let ss = s * 1.1f64 + 1.0f64
    var ksmal = 0usize
    var j = 1usize
    var k = 1usize
    while j <= nn {
        if nrepr[j] == 0usize {
            var dsmal = ss
            k = 1usize
            while k <= nn {
                if nrepr[k] == 1usize {
                    let kj_ = ind2(k, j)
                    if dsmal > dys[kj_] {
                        dsmal = dys[kj_]
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
    while j <= nn {
        ncluv[j] = 0usize
        if nsend[j] == nplac { ncluv[j] = 1usize }
        j += 1usize
    }
    var ja = 2usize
    while ja <= nn {
        nplac = nsend[ja]
        if ncluv[nplac] == 0usize {
            jk += 1usize
            j = 2usize
            while j <= nn {
                if nsend[j] == nplac { ncluv[j] = jk }
                j += 1usize
            }
            if jk == kk { break }
        }
        ja += 1usize
    }
    if all_stats {
        k = 1usize
        while k <= kk {
            var ntt = 0usize
            var m = 0usize
            var ttt = 0.0f64
            radus[k] = 0.0f64 - 1.0f64
            j = 1usize
            while j <= nn {
                if ncluv[j] == k {
                    ntt += 1usize
                    m = nsend[j]
                    nelem[ntt] = j
                    let djm = dys[ind2(j, m)]
                    ttt += djm
                    if radus[k] < djm { radus[k] = djm }
                }
                j += 1usize
            }
            if ntt == 0usize { ret false }
            avsyl[k] = ttt / f64(ntt)
            med[k] = m
            k += 1usize
        }
        if kk == 1usize {
            damer[1usize] = s
            nrepr[1usize] = nn
            nisol[1usize] = 0usize
            separ[1usize] = 0.0f64
            ret true
        }
        k = 1usize
        while k <= kk {
            var nel = 0usize
            j = 1usize
            while j <= nn {
                if ncluv[j] == k {
                    nel += 1usize
                    nelem[nel] = j
                }
                j += 1usize
            }
            nrepr[k] = nel
            var done = false
            if nel == 1usize {
                let nvn = nelem[1usize]
                damer[k] = 0.0f64
                separ[k] = ss
                j = 1usize
                while j <= nn {
                    if j != nvn {
                        let mevj = ind2(nvn, j)
                        if separ[k] > dys[mevj] { separ[k] = dys[mevj] }
                    }
                    j += 1usize
                }
            } else {
                var dam = 0.0f64 - 1.0f64
                var sep = ss
                var kand = true
                ja = 1usize
                while ja <= nel {
                    let nvna = nelem[ja]
                    var aja = 0.0f64 - 1.0f64
                    var ajb = ss
                    var jb = 1usize
                    while jb <= nn {
                        let jndz = ind2(nvna, jb)
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
                    ja += 1usize
                }
                separ[k] = sep
                damer[k] = dam
                if kand {
                    if dam >= sep { nisol[k] = 1usize } else { nisol[k] = 2usize }
                    done = true
                }
            }
            if !done { nisol[k] = 0usize }
            k += 1usize
        }
    }
    ret true
}

// dark: the silhouette information; sylinf is n by 4 column-major (cluster, neighbour, width, observation), avsyl[1..kk] the average width per cluster;
// returns the overall average
fn dark(a: *mem.Arena, kk: usize, nn: usize, ncluv: []const usize, dys: []const f64, s: f64, avsyl: []f64, sylinf: []f64) -> (f64, err) {
    let (nelem, e1) = zu(a, nn + 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    let (nsend, e2) = zu(a, nn + 1usize)
    if e2 != ok { ret (0.0f64, e2) }
    let (negbr, e3) = zi(a, nn + 1usize)
    if e3 != ok { ret (0.0f64, e3) }
    let (syl, e4) = zf(a, nn + 1usize)
    if e4 != ok { ret (0.0f64, e4) }
    let (srank, e5) = zf(a, nn + 1usize)
    if e5 != ok { ret (0.0f64, e5) }
    var nsylr = 0usize
    var ttsyl = 0.0f64
    var k = 1usize
    while k <= kk {
        var ntt = 0usize
        var j = 1usize
        while j <= nn {
            if ncluv[j] == k {
                nelem[ntt] = j
                ntt += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < ntt {
            let nj = nelem[j]
            var dysb = s * 1.1f64 + 1.0f64
            negbr[j] = 0i64 - 1i64
            var kq = 1usize
            while kq <= kk {
                if kq != k {
                    var db = 0.0f64
                    var nbb = 0usize
                    var l = 1usize
                    while l <= nn {
                        if ncluv[l] == kq {
                            nbb += 1usize
                            if l != nj { db += dys[ind2(nj, l)] }
                        }
                        l += 1usize
                    }
                    db /= f64(nbb)
                    if dysb > db {
                        dysb = db
                        negbr[j] = i64(kq)
                    }
                }
                kq += 1usize
            }
            if ntt > 1usize {
                var dysa = 0.0f64
                var l = 0usize
                while l < ntt {
                    let nl = nelem[l]
                    if nj != nl { dysa += dys[ind2(nj, nl)] }
                    l += 1usize
                }
                dysa /= f64(ntt - 1usize)
                if dysa > 0.0f64 {
                    if dysb > 0.0f64 {
                        if dysb > dysa {
                            syl[j] = 1.0f64 - dysa / dysb
                        } else {
                            if dysb < dysa { syl[j] = dysb / dysa - 1.0f64 } else { syl[j] = 0.0f64 }
                        }
                        if syl[j] < 0.0f64 - 1.0f64 {
                            syl[j] = 0.0f64 - 1.0f64
                        } else {
                            if syl[j] > 1.0f64 { syl[j] = 1.0f64 }
                        }
                    } else {
                        syl[j] = 0.0f64 - 1.0f64
                    }
                } else {
                    if dysb > 0.0f64 { syl[j] = 1.0f64 } else { syl[j] = 0.0f64 }
                }
            } else {
                syl[j] = 0.0f64
            }
            j += 1usize
        }
        avsyl[k] = 0.0f64
        if ntt == 0usize {
            k += 1usize
            continue
        }
        j = 0usize
        while j < ntt {
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
            nsend[j] = lang
            srank[j] = symax
            avsyl[k] += srank[j]
            syl[lang] = 0.0f64 - 3.0f64
            j += 1usize
        }
        ttsyl += avsyl[k]
        avsyl[k] /= f64(ntt)
        if ntt == 1usize {
            sylinf[nsylr] = f64(k)
            sylinf[nn + nsylr] = f64(negbr[0usize])
            sylinf[2usize * nn + nsylr] = 0.0f64
            sylinf[3usize * nn + nsylr] = f64(nelem[0usize])
            nsylr += 1usize
        } else {
            j = 0usize
            while j < ntt {
                let lplac = nsend[j]
                sylinf[nsylr] = f64(k)
                sylinf[nn + nsylr] = f64(negbr[lplac])
                sylinf[2usize * nn + nsylr] = srank[j]
                sylinf[3usize * nn + nsylr] = f64(nelem[lplac])
                nsylr += 1usize
                j += 1usize
            }
        }
        k += 1usize
    }
    ret (ttsyl / f64(nn), ok)
}

// cluster::pam on a packed dissimilarity dys (length n (n - 1) / 2 + 1). given holds the starting medoids (1-based) when has_given; pamonce is 0 (original),
// 1, 2 (o_1, o_2), 3, 4, 5 (f_3, f_4, f_5) or 6 ("faster"); all_stats false is cluster.only
fn pam(a: *mem.Arena, dys: []const f64, n: usize, kk: usize, given: []const usize, has_given: bool, do_swap: bool, pamonce: usize, all_stats: bool) -> (PamFit, err) {
    if kk < 1usize || kk >= n { ret (zero, BadArgument) }
    let nhalf = nhalf_of(n)
    var s = 0.0f64
    var i = 1usize
    while i < nhalf {
        if s < dys[i] { s = dys[i] }
        i += 1usize
    }
    let (nrepr, e1) = zu(a, n + 1usize)
    if e1 != ok { ret (zero, e1) }
    let (dysma, e2) = zf(a, n + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (dysmb, e3) = zf(a, n + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (beter, e4) = zf(a, n + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (obj, e5) = zf(a, 2usize)
    if e5 != ok { ret (zero, e5) }
    if has_given {
        var k = 0usize
        while k < kk {
            nrepr[given[k]] = 1usize
            k += 1usize
        }
    }
    let eb = bswap(a, kk, n, nrepr, has_given, do_swap, dys, s, dysma, dysmb, beter, obj, pamonce)
    if eb != ok { ret (zero, eb) }
    let (nsend, e6) = zu(a, n + 1usize)
    if e6 != ok { ret (zero, e6) }
    let (ncluv, e7) = zu(a, n + 1usize)
    if e7 != ok { ret (zero, e7) }
    let (nelem, e8) = zu(a, n + 1usize)
    if e8 != ok { ret (zero, e8) }
    let (med1, e9) = zu(a, kk + 1usize)
    if e9 != ok { ret (zero, e9) }
    let (nisol1, e10) = zu(a, kk + 1usize)
    if e10 != ok { ret (zero, e10) }
    let (radus, e11) = zf(a, n + 1usize)
    if e11 != ok { ret (zero, e11) }
    let (damer, e12) = zf(a, n + 1usize)
    if e12 != ok { ret (zero, e12) }
    let (avsyl, e13) = zf(a, n + 1usize)
    if e13 != ok { ret (zero, e13) }
    let (separ, e14) = zf(a, kk + 1usize)
    if e14 != ok { ret (zero, e14) }
    let good = cstat(kk, n, nsend, nrepr, all_stats, radus, damer, avsyl, separ, s, dys, ncluv, nelem, med1, nisol1)
    if !good { ret (zero, BadArgument) }
    var fit: PamFit = zero
    fit.obj_build = obj[0usize]
    fit.obj_swap = obj[1usize]
    let (clu, e15) = zu(a, n)
    if e15 != ok { ret (zero, e15) }
    i = 0usize
    while i < n {
        clu[i] = ncluv[i + 1usize]
        i += 1usize
    }
    fit.clu = clu
    let (med, e16) = zu(a, kk)
    if e16 != ok { ret (zero, e16) }
    i = 0usize
    while i < kk {
        med[i] = med1[i + 1usize]
        i += 1usize
    }
    fit.med = med
    if !all_stats { ret (fit, ok) }
    let (isol, e17) = zu(a, kk)
    if e17 != ok { ret (zero, e17) }
    let (clusinf, e18) = zf(a, kk * 5usize)
    if e18 != ok { ret (zero, e18) }
    i = 0usize
    while i < kk {
        isol[i] = nisol1[i + 1usize]
        clusinf[i] = f64(nrepr[i + 1usize])
        clusinf[i + kk] = radus[i + 1usize]
        clusinf[i + 2usize * kk] = avsyl[i + 1usize]
        clusinf[i + 3usize * kk] = damer[i + 1usize]
        clusinf[i + 4usize * kk] = separ[i + 1usize]
        i += 1usize
    }
    fit.isol = isol
    fit.clusinf = clusinf
    if kk > 1usize {
        let (sylinf, e19) = zf(a, n * 4usize)
        if e19 != ok { ret (zero, e19) }
        let (av2, e20) = zf(a, kk + 1usize)
        if e20 != ok { ret (zero, e20) }
        let (tt, e21) = dark(a, kk, n, ncluv, dys, s, av2, sylinf)
        if e21 != ok { ret (zero, e21) }
        let (avs, e22) = zf(a, kk)
        if e22 != ok { ret (zero, e22) }
        i = 0usize
        while i < kk {
            avs[i] = av2[i + 1usize]
            i += 1usize
        }
        fit.silinfo = sylinf
        fit.avsil = avs
        fit.ttsil = tt
        fit.has_sil = true
    }
    ret (fit, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// R sums in 80-bit long double, so its means are (nearly always) the correctly rounded sum / count; two-sum accumulation reproduces that

// (hi, lo) + v with the rounding error of the sum kept in lo
fn two_sum_add(hi: f64, lo: f64, v: f64) -> (f64, f64) {
    let t = hi + v
    let bb = t - hi
    let rounding = (hi - (t - bb)) + (v - bb)
    ret (t, lo + rounding)
}

// (hi + lo) / cnt correctly rounded: the remainder of the first quotient is formed with an exact product
fn div_count(hi: f64, lo: f64, cnt: usize) -> f64 {
    let c = f64(cnt)
    let q1 = hi / c
    let split = 134217729.0f64 * q1
    let qh = split - (split - q1)
    let ql = q1 - qh
    let p = q1 * c
    let pe = ((qh * c - p) + ql * c)
    let r = ((hi - p) - pe) + lo
    ret q1 + r / c
}

// colMeans(x, na.rm = TRUE) of column j, of |x| when use_abs
fn col_mean(x: []const f64, n: usize, j: usize, use_abs: bool) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < n {
        var v = x[i + j * n]
        if v == v {
            if use_abs { v = math.abs[f64](v) }
            let (h2, l2) = two_sum_add(hi, lo, v)
            hi = h2
            lo = l2
            cnt += 1usize
        }
        i += 1usize
    }
    ret div_count(hi, lo, cnt)
}

// meanabsdev(x[, j]) = mean(abs(y - mean(y, na.rm = TRUE)), na.rm = TRUE)
fn mean_abs_dev(x: []const f64, n: usize, j: usize) -> f64 {
    let mu = col_mean(x, n, j, false)
    var hi = 0.0f64
    var lo = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < n {
        let v = x[i + j * n]
        if v == v {
            let (h2, l2) = two_sum_add(hi, lo, math.abs[f64](v - mu))
            hi = h2
            lo = l2
            cnt += 1usize
        }
        i += 1usize
    }
    ret div_count(hi, lo, cnt)
}

// stand = TRUE: scale(x, scale = apply(x, 2, meanabsdev)) in place, NaN skipped
fn stand_data(x: []f64, n: usize, p: usize) {
    var j = 0usize
    while j < p {
        let mu = col_mean(x, n, j, false)
        let sd = mean_abs_dev(x, n, j)
        var i = 0usize
        while i < n {
            let v = x[i + j * n]
            if v == v { x[i + j * n] = (v - mu) / sd }
            i += 1usize
        }
        j += 1usize
    }
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// silhouette (sildist): d is n by n (ismat) or the dist vector (column-wise lower triangle); clustering holds 1..k. si and neighbour (1-based) per observation
fn sildist(a: *mem.Arena, d: []const f64, n: usize, clustering: []const usize, k: usize, ismat: bool, si: []f64, neighbor: []usize) -> err {
    let (dic, e1) = zf(a, n * k)
    if e1 != ok { ret e1 }
    let (counts, e2) = zu(a, k)
    if e2 != ok { ret e2 }
    var l = 0usize
    var i = 0usize
    while i < n {
        let ci = clustering[i] - 1usize
        counts[ci] += 1usize
        if ismat { l = n * i + i + 1usize }
        var j = i + 1usize
        while j < n {
            let cj = clustering[j] - 1usize
            dic[k * i + cj] += d[l]
            dic[k * j + ci] += d[l]
            j += 1usize
            l += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        let ki = k * i
        let ci = clustering[i] - 1usize
        var compute_si = true
        var j = 0usize
        while j < k {
            if j == ci {
                if counts[j] == 1usize { compute_si = false } else { dic[ki + j] /= f64(counts[j] - 1usize) }
            } else {
                dic[ki + j] /= f64(counts[j])
            }
            j += 1usize
        }
        let ai = dic[ki + ci]
        var bi = dic[ki]
        neighbor[i] = 1usize
        if ci == 0usize {
            bi = dic[ki + 1usize]
            neighbor[i] = 2usize
        }
        j = 1usize
        while j < k {
            if j != ci {
                if bi > dic[ki + j] {
                    bi = dic[ki + j]
                    neighbor[i] = j + 1usize
                }
            }
            j += 1usize
        }
        si[i] = 0.0f64
        if compute_si && bi != ai {
            var m = ai
            if bi > m { m = bi }
            si[i] = (bi - ai) / m
        }
        i += 1usize
    }
    ret ok
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// daisy

// the C kernel: x is n by p column-major, valmd the code for NA, jtmd[j] < 0 when column j has NA; vtype 1..6 (A, S, N, O, I, T); jdat 1 is mixed (gower) and
// 2 all interval; ndyst 0 mixed, 1 euclidean, 2 manhattan. disv is the packed lower triangle by rows, 0-based, with -1 for NA
fn cldaisy(nn: usize, jpp: usize, x: []const f64, valmd: []const f64, weights: []const f64, jtmd: []const i64, jdat: usize, vtype: []const usize,
           ndyst: usize, hasna: bool, disv: []f64) {
    var nlk = 0usize
    if jdat == 1usize {
        var l = 1usize
        while l < nn {
            var k = 0usize
            while k < l {
                var ppa = 0.0f64
                var dlk = 0.0f64
                var j = 0usize
                while j < jpp {
                    let xl = x[l + j * nn]
                    let xk = x[k + j * nn]
                    if vtype[j] >= 3usize {
                        var skip = false
                        if hasna {
                            if jtmd[j] < 0i64 {
                                if xl == valmd[j] || xk == valmd[j] { skip = true }
                            }
                        }
                        if !skip {
                            ppa += weights[j]
                            if vtype[j] == 3usize {
                                if xl != xk { dlk += weights[j] }
                            } else {
                                dlk += weights[j] * math.abs[f64](xl - xk)
                            }
                        }
                    } else {
                        var skip = false
                        if (xl != 0.0f64 && xl != 1.0f64) || (xk != 0.0f64 && xk != 1.0f64) { skip = true }
                        if !skip {
                            if vtype[j] == 2usize || xl != 0.0f64 || xk != 0.0f64 { ppa += weights[j] }
                            if xl != xk { dlk += weights[j] }
                        }
                    }
                    j += 1usize
                }
                if ppa == 0.0f64 { disv[nlk] = 0.0f64 - 1.0f64 } else { disv[nlk] = dlk / ppa }
                nlk += 1usize
                k += 1usize
            }
            l += 1usize
        }
    } else {
        let pp = f64(jpp)
        var l = 1usize
        while l < nn {
            var k = 0usize
            while k < l {
                var clk = 0.0f64
                var npres = 0usize
                var j = 0usize
                while j < jpp {
                    var skip = false
                    if hasna {
                        if jtmd[j] < 0i64 {
                            if x[l + j * nn] == valmd[j] || x[k + j * nn] == valmd[j] { skip = true }
                        }
                    }
                    if !skip {
                        npres += 1usize
                        let dv = x[l + j * nn] - x[k + j * nn]
                        if ndyst == 1usize { clk += dv * dv } else { clk += math.abs[f64](dv) }
                    }
                    j += 1usize
                }
                let rpres = f64(npres)
                if npres == 0usize {
                    disv[nlk] = 0.0f64 - 1.0f64
                } else {
                    if ndyst == 1usize { disv[nlk] = math.sqrt[f64](clk * (pp / rpres)) } else { disv[nlk] = clk * (pp / rpres) }
                }
                nlk += 1usize
                k += 1usize
            }
            l += 1usize
        }
    }
}

// cluster::daisy: x is n by p column-major with NaN for NA (factors and ordered factors already as their integer codes, logicals as 0/1); types[j] is
// 1 A, 2 S, 3 N, 4 O, 5 I, 6 T (the values are replaced by their dense ranks, as.ordered), 7 an interval column log10-transformed (type = list(logratio));
// metric 1 euclidean, 2 manhattan, 3 gower (a mixed set is gower whatever metric asks). out is the n by n symmetric matrix, row-major, NaN where no pair is shared.
// x is modified (standardised, rank-coded, scaled)
fn daisy(a: *mem.Arena, x: []f64, n: usize, p: usize, types: []const usize, weights: []const f64, metric: usize, stand: bool, out: []f64) -> err {
    let (vt, e1) = zu(a, p)
    if e1 != ok { ret e1 }
    let (col, e0) = zf(a, n)
    if e0 != ok { ret e0 }
    var j = 0usize
    var all_i = true
    while j < p {
        vt[j] = types[j]
        if vt[j] == 6usize {
            var i = 0usize
            while i < n {
                col[i] = x[i + j * n]
                i += 1usize
            }
            i = 0usize
            while i < n {
                let v = col[i]
                if v == v {
                    // the rank among the distinct values: count each smaller value once
                    var below = 0usize
                    var i2 = 0usize
                    while i2 < n {
                        let w = col[i2]
                        if w == w && w < v {
                            var seen = false
                            var i3 = 0usize
                            while i3 < i2 {
                                if col[i3] == w { seen = true }
                                i3 += 1usize
                            }
                            if !seen { below += 1usize }
                        }
                        i2 += 1usize
                    }
                    x[i + j * n] = f64(below + 1usize)
                }
                i += 1usize
            }
        }
        if vt[j] == 7usize {
            var i = 0usize
            while i < n {
                let v = x[i + j * n]
                if v == v { x[i + j * n] = math.log10[f64](v) }
                i += 1usize
            }
            vt[j] = 5usize
        }
        if vt[j] != 5usize { all_i = false }
        j += 1usize
    }
    var jdat = 1usize
    var ndyst = 0usize
    if all_i && metric != 3usize {
        if stand {
            j = 0usize
            while j < p {
                let mu = col_mean(x, n, j, false)
                var i = 0usize
                while i < n {
                    let v = x[i + j * n]
                    if v == v { x[i + j * n] = v - mu }
                    i += 1usize
                }
                var sx = col_mean(x, n, j, true)
                if sx == 0.0f64 { sx = 1.0f64 }
                i = 0usize
                while i < n {
                    let v = x[i + j * n]
                    if v == v { x[i + j * n] = v / sx }
                    i += 1usize
                }
                j += 1usize
            }
        }
        jdat = 2usize
        ndyst = 1usize
        if metric == 2usize { ndyst = 2usize }
    } else {
        j = 0usize
        while j < p {
            var lo = 1.0e300f64
            var hi = 0.0f64 - 1.0e300f64
            var i = 0usize
            while i < n {
                let v = x[i + j * n]
                if v == v {
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
                i += 1usize
            }
            var sx = hi - lo
            if sx == 0.0f64 { sx = 1.0f64 }
            i = 0usize
            while i < n {
                let v = x[i + j * n]
                if v == v { x[i + j * n] = (v - lo) / sx }
                i += 1usize
            }
            j += 1usize
        }
    }
    let (jtmd, e3) = zi(a, p)
    if e3 != ok { ret e3 }
    let (valmd, e4) = zf(a, p)
    if e4 != ok { ret e4 }
    let mdata = na_prepare(x, n, p, jtmd, valmd)
    let (disv, e5) = zf(a, n * (n - 1usize) / 2usize + 1usize)
    if e5 != ok { ret e5 }
    cldaisy(n, p, x, valmd, weights, jtmd, jdat, vt, ndyst, mdata, disv)
    var nlk = 0usize
    var l = 1usize
    while l < n {
        var k = 0usize
        while k < l {
            var v = disv[nlk]
            if v == 0.0f64 - 1.0f64 { v = 0.0f64 / 0.0f64 }
            out[l * n + k] = v
            out[k * n + l] = v
            nlk += 1usize
            k += 1usize
        }
        out[l * n + l] = 0.0f64
        l += 1usize
    }
    out[0usize] = 0.0f64
    ret ok
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// clara

type ClaraGen = struct { nrun: i64, use_r: bool }

type ClaraFit = struct {
    clu: []usize, med: []usize, sample: []usize, obj: f64, size: []usize, maxdis: []f64, avdis: []f64, ratdis: []f64,
    silinf: []f64, avsil: []f64, ttsil: f64, has_sil: bool, dys: []f64, jstop: usize
}

// clara's own generator, machine independent with period 2^16
fn randm(g: *ClaraGen) -> f64 {
    g.nrun = (g.nrun * 5761i64 + 999i64) & 65535i64
    ret f64(g.nrun) / 65536.0f64
}

// k = 1 + (int)(n * unif), from R's generator or randm
fn clara_draw(g: *ClaraGen, rg: *rng.Rng, n: usize) -> usize {
    var u = 0.0f64
    if g.use_r { u = rng.unif(rg) } else { u = randm(g) }
    var k = 1usize + usize(f64(n) * u)
    if k > n { k = n }
    ret k
}

// the dissimilarities of the sample nsel[0..nsam) (1-based observation numbers) into dys; false when some pair shares no variable
fn dysta2(nsam: usize, jpp: usize, nsel: []const usize, x: []const f64, n: usize, dys: []f64, diss_kind: usize, jtmd: []const i64, valmd: []const f64, has_na: bool) -> bool {
    var nlk = 0usize
    var toomany = false
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
            var lj = lsel - 1usize
            var kj = ksel - 1usize
            while j < jpp {
                var skip = false
                if has_na && jtmd[j] < 0i64 {
                    if x[lj] == valmd[j] || x[kj] == valmd[j] { skip = true }
                }
                if !skip {
                    npres += 1usize
                    if diss_kind == 1usize {
                        clk += (x[lj] - x[kj]) * (x[lj] - x[kj])
                    } else {
                        if diss_kind == 3usize {
                            if x[lj] > 0.9f64 && x[kj] > 0.9f64 {
                                clk += 1.0f64
                                n_ones += 1usize
                            } else {
                                if x[lj] > 0.9f64 || x[kj] > 0.9f64 { n_ones += 1usize }
                            }
                        } else {
                            clk += math.abs[f64](x[lj] - x[kj])
                        }
                    }
                }
                j += 1usize
                lj += n
                kj += n
            }
            if npres == 0usize {
                toomany = true
                dys[nlk] = 0.0f64 - 1.0f64
            } else {
                let d1 = clk * (f64(jpp) / f64(npres))
                if diss_kind == 1usize {
                    dys[nlk] = math.sqrt[f64](d1)
                } else {
                    if diss_kind == 3usize { dys[nlk] = 1.0f64 - clk / f64(n_ones) } else { dys[nlk] = d1 }
                }
            }
            k += 1usize
        }
        l += 1usize
    }
    ret !toomany
}

// bswap2: BUILD and the SWAP loop on a sample; returns the sky of the C code through sky[0]
fn bswap2(kk: usize, n: usize, s0: f64, dys: []const f64, pam_like: bool, sky: []f64, nrepr: []usize, dysma: []f64, dysmb: []f64, beter: []f64) {
    let s = s0 * 1.1f64 + 1.0f64
    var i = 1usize
    var j = 1usize
    var ij = 0usize
    var hbest = 1usize
    var nbest = 1usize
    while i <= n {
        nrepr[i] = 0usize
        dysma[i] = s
        i += 1usize
    }
    var k = 0usize
    while k < kk {
        var nmax = 1usize
        var ammax = 0.0f64
        i = 1usize
        while i <= n {
            if nrepr[i] == 0usize {
                beter[i] = 0.0f64
                j = 1usize
                while j <= n {
                    let cmd = dysma[j] - dys[ind2(i, j)]
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
            ij = ind2(nmax, j)
            if dysma[j] > dys[ij] { dysma[j] = dys[ij] }
            j += 1usize
        }
        k += 1usize
    }
    sky[0usize] = 0.0f64
    j = 1usize
    while j <= n {
        sky[0usize] += dysma[j]
        j += 1usize
    }
    if kk == 1usize { ret }
    while true {
        j = 1usize
        while j <= n {
            dysma[j] = s
            dysmb[j] = s
            i = 1usize
            while i <= n {
                if nrepr[i] != 0usize {
                    ij = ind2(i, j)
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
        var h = 1usize
        while h <= n {
            if nrepr[h] == 0usize {
                i = 1usize
                while i <= n {
                    if nrepr[i] != 0usize {
                        var dz = 0.0f64
                        j = 1usize
                        while j <= n {
                            let ij2 = ind2(i, j)
                            let hj = ind2(h, j)
                            if dys[ij2] == dysma[j] {
                                var small = 0.0f64
                                if pam_like {
                                    small = dysmb[j]
                                    if dysmb[j] > dys[hj] { small = dys[hj] }
                                } else {
                                    small = dysmb[j]
                                    if dysmb[j] > dys[ij2] { small = dys[hj] }
                                }
                                dz += (0.0f64 - dysma[j] + small)
                            } else {
                                if dys[hj] < dysma[j] { dz += (0.0f64 - dysma[j] + dys[hj]) }
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
            sky[0usize] += dzsky
        } else {
            break
        }
    }
}

// selec: assign every object of the data set to the nearest sample medoid; false (nafs) when an object cannot be assigned.
// nr, ns, np, ttd, radus, ratt are kk + 1 long (1-based); zb[0] the criterion
fn selec(a: *mem.Arena, kk: usize, n: usize, jpp: usize, diss_kind: usize, zb: []f64, nsam: usize, has_na: bool, jtmd: []const i64, valmd: []const f64,
         nrepr: []const usize, nsel: []const usize, dys: []const f64, x: []const f64, nr: []usize, ttd: []f64, radus: []f64, ratt: []f64, correct_d: bool) -> (bool, err) {
    let (ns, e1) = zu(a, kk + 1usize)
    if e1 != ok { ret (false, e1) }
    let (np, e2) = zu(a, kk + 1usize)
    if e2 != ok { ret (false, e2) }
    let (nrnew, e3) = zu(a, kk + 1usize)
    if e3 != ok { ret (false, e3) }
    let (nsnew, e4) = zu(a, kk + 1usize)
    if e4 != ok { ret (false, e4) }
    let (npnew, e5) = zu(a, kk + 1usize)
    if e5 != ok { ret (false, e5) }
    let (newv, e6) = zu(a, kk + 1usize)
    if e6 != ok { ret (false, e6) }
    let (ttnew, e7) = zf(a, kk + 1usize)
    if e7 != ok { ret (false, e7) }
    let (rdnew, e8) = zf(a, kk + 1usize)
    if e8 != ok { ret (false, e8) }
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
    let pp = f64(jpp)
    zb[0usize] = 0.0f64
    var newf = 0usize
    var i = 1usize
    while i <= n {
        var jkabc = 1usize
        var dsum = 0.0f64
        var dnull = 0.0f64 - 9.0f64
        if !has_na {
            jk = 1usize
            while jk <= kk {
                dsum = 0.0f64
                let nr_k = nr[jk]
                var skip_jk = false
                if nr_k != i {
                    var n_ones = 0usize
                    var tra = 0.0f64
                    var jp = 0usize
                    while jp < jpp {
                        let na = (nr_k - 1usize) + jp * n
                        let nb = (i - 1usize) + jp * n
                        if diss_kind == 3usize {
                            if x[na] > 0.9f64 && x[nb] > 0.9f64 {
                                tra += 1.0f64
                                n_ones += 1usize
                            } else {
                                if x[na] > 0.9f64 || x[nb] > 0.9f64 { n_ones += 1usize }
                            }
                        } else {
                            tra = math.abs[f64](x[na] - x[nb])
                            if diss_kind == 1usize { tra *= tra }
                            dsum += tra
                        }
                        jp += 1usize
                    }
                    if diss_kind == 3usize { dsum = 1.0f64 - tra / f64(n_ones) }
                    if jk != 1usize && dsum >= dnull { skip_jk = true }
                }
                if !skip_jk {
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
                var skip_jk = false
                if nr_k != i {
                    var nobs = 0usize
                    var n_ones = 0usize
                    var tra = 0.0f64
                    var jp = 0usize
                    while jp < jpp {
                        let na = (nr_k - 1usize) + jp * n
                        let nb = (i - 1usize) + jp * n
                        var skip_jp = false
                        if jtmd[jp] < 0i64 {
                            if x[na] == valmd[jp] || x[nb] == valmd[jp] { skip_jp = true }
                        }
                        if !skip_jp {
                            nobs += 1usize
                            if diss_kind == 3usize {
                                if x[na] > 0.9f64 && x[nb] > 0.9f64 {
                                    tra += 1.0f64
                                    n_ones += 1usize
                                } else {
                                    if x[na] > 0.9f64 || x[nb] > 0.9f64 { n_ones += 1usize }
                                }
                            } else {
                                tra = math.abs[f64](x[na] - x[nb])
                                if diss_kind == 1usize { tra *= tra }
                                dsum += tra
                            }
                        }
                        jp += 1usize
                    }
                    if nobs == 0usize {
                        skip_jk = true
                    } else {
                        if diss_kind == 3usize { dsum = 1.0f64 - tra / f64(n_ones) }
                        if correct_d { dsum *= (pp / f64(nobs)) } else { dsum *= (f64(nobs) / pp) }
                    }
                }
                if !skip_jk {
                    if first {
                        first = false
                        dnull = dsum
                        jkabc = jk
                    } else {
                        if dnull > dsum {
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
            if newf != 0usize {
                var jnew = 1usize
                while jnew <= newf {
                    if jkabc == newv[jnew] { seen = true }
                    jnew += 1usize
                }
            }
            if !seen {
                newf += 1usize
                newv[newf] = jkabc
            }
        }
        i += 1usize
    }
    j = 1usize
    while j <= kk {
        let nj = newv[j]
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
                    let npab = ind2(npa, npb)
                    var skip_kb = false
                    if first { first = false } else {
                        if dys[npab] >= ratt[ka] { skip_kb = true }
                    }
                    if !skip_kb {
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

// resul: every object takes the nearest medoid of nrx (1-based observation numbers); clu[0..n) are the labels 1..kk, mtt the sizes
fn resul(kk: usize, n: usize, jpp: usize, diss_kind: usize, has_na: bool, jtmd: []const i64, valmd: []const f64, x: []const f64, nrx: []const usize,
         clu: []usize, mtt: []usize, correct_d: bool) {
    var i = 0usize
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
                if !has_na {
                    var j = 0usize
                    while j < jpp {
                        var tra = math.abs[f64](x[nrjk + j * n] - x[i + j * n])
                        if diss_kind == 1usize { tra *= tra }
                        dsum += tra
                        j += 1usize
                    }
                    if diss_kind == 1usize { dsum = math.sqrt[f64](dsum) }
                } else {
                    let pp = f64(jpp)
                    var nobs = 0usize
                    var j = 0usize
                    while j < jpp {
                        let na = nrjk + j * n
                        let nb = i + j * n
                        var skip = false
                        if jtmd[j] < 0i64 {
                            if x[na] == valmd[j] || x[nb] == valmd[j] { skip = true }
                        }
                        if !skip {
                            nobs += 1usize
                            var tra = math.abs[f64](x[na] - x[nb])
                            if diss_kind == 1usize { tra *= tra }
                            dsum += tra
                        }
                        j += 1usize
                    }
                    if diss_kind == 1usize { dsum = math.sqrt[f64](dsum) }
                    if correct_d { dsum *= (pp / f64(nobs)) } else { dsum *= (f64(nobs) / pp) }
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
    var jk = 0usize
    while jk < kk {
        clu[nrx[jk] - 1usize] = jk + 1usize
        jk += 1usize
    }
    var ka = 0usize
    while ka < kk {
        mtt[ka] = 0usize
        i = 0usize
        while i < n {
            if clu[i] == ka + 1usize { mtt[ka] += 1usize }
            i += 1usize
        }
        ka += 1usize
    }
}

// black: silhouette of the best sample; sylinf is nsam by 4 column-major, avsyl[1..kk]; returns the overall average
fn black(a: *mem.Arena, kk: usize, nsam: usize, nbest: []const usize, dys: []const f64, s: f64, clu: []const usize, avsyl: []f64, sylinf: []f64) -> (f64, err) {
    let (ncluv, e1) = zu(a, nsam + 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    let (nelem, e2) = zu(a, nsam + 1usize)
    if e2 != ok { ret (0.0f64, e2) }
    let (nsend, e3) = zu(a, nsam + 1usize)
    if e3 != ok { ret (0.0f64, e3) }
    let (negbr, e4) = zi(a, nsam + 1usize)
    if e4 != ok { ret (0.0f64, e4) }
    let (syl, e5) = zf(a, nsam + 1usize)
    if e5 != ok { ret (0.0f64, e5) }
    let (srank, e6) = zf(a, nsam + 1usize)
    if e6 != ok { ret (0.0f64, e6) }
    var l = 1usize
    while l <= nsam {
        ncluv[l] = clu[nbest[l - 1usize] - 1usize]
        l += 1usize
    }
    var nsylr = 0usize
    var ttsyl = 0.0f64
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
            var dysb = s * 1.1f64 + 1.0f64
            negbr[j] = 0i64 - 1i64
            var nclu = 1usize
            while nclu <= kk {
                if nclu != numcl {
                    var nbb = 0usize
                    var db = 0.0f64
                    l = 1usize
                    while l <= nsam {
                        if ncluv[l] == nclu {
                            nbb += 1usize
                            db += dys[ind2(nj, l)]
                        }
                        l += 1usize
                    }
                    db /= f64(nbb)
                    if db < dysb {
                        dysb = db
                        negbr[j] = i64(nclu)
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
                    dysa += dys[ind2(nj, nl)]
                    l += 1usize
                }
                dysa /= f64(ntt - 1usize)
                if dysa <= 0.0f64 {
                    if dysb > 0.0f64 { syl[j] = 1.0f64 } else { syl[j] = 0.0f64 }
                } else {
                    if dysb > 0.0f64 {
                        if dysb > dysa {
                            syl[j] = 1.0f64 - dysa / dysb
                        } else {
                            if dysb < dysa { syl[j] = dysb / dysa - 1.0f64 } else { syl[j] = 0.0f64 }
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
        avsyl[numcl] = 0.0f64
        j = 1usize
        while j <= ntt {
            var lang = 1usize
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
            avsyl[numcl] += srank[j]
            syl[lang] = 0.0f64 - 3.0f64
            j += 1usize
        }
        ttsyl += avsyl[numcl]
        avsyl[numcl] /= f64(ntt)
        if ntt >= 2usize {
            l = 1usize
            while l <= ntt {
                let lplac = nsend[l]
                sylinf[nsylr] = f64(numcl)
                sylinf[nsam + nsylr] = f64(negbr[lplac])
                sylinf[2usize * nsam + nsylr] = srank[l]
                sylinf[3usize * nsam + nsylr] = f64(nbest[nelem[lplac] - 1usize])
                nsylr += 1usize
                l += 1usize
            }
        } else {
            sylinf[nsylr] = f64(numcl)
            sylinf[nsam + nsylr] = f64(negbr[1usize])
            sylinf[2usize * nsam + nsylr] = 0.0f64
            sylinf[3usize * nsam + nsylr] = f64(nbest[nelem[1usize] - 1usize])
            nsylr += 1usize
        }
        numcl += 1usize
    }
    ret (ttsyl / f64(nsam), ok)
}

// cluster::clara. x is n by jpp column-major (NA already coded with valmd, see na_prepare); diss_kind 1 euclidean, 2 manhattan, 3 jaccard; with rng_r the draws
// come from rg (seed it first, as set.seed does), otherwise from clara's own generator. jstop is 0 on success, 1 when every sample had an unusable pair,
// 2 when every sample left an object unassigned
fn clara(a: *mem.Arena, x: []const f64, n: usize, jpp: usize, kk: usize, nran: usize, nsam: usize, has_na: bool, valmd: []const f64, jtmd: []const i64,
         diss_kind: usize, rng_r: bool, rg: *rng.Rng, pam_like: bool, correct_d: bool) -> (ClaraFit, err) {
    var fit: ClaraFit = zero
    if kk < 1usize || kk + 1usize > n || nsam < 2usize || nsam < kk + 1usize || nsam > n || nran < 1usize { ret (fit, BadArgument) }
    var g: ClaraGen = zero
    g.nrun = 0i64
    g.use_r = rng_r
    let (dys, e1) = zf(a, nsam * (nsam - 1usize) / 2usize + 1usize)
    if e1 != ok { ret (fit, e1) }
    let (nrepr, e2) = zu(a, nsam + 1usize)
    if e2 != ok { ret (fit, e2) }
    let (nsel, e3) = zu(a, nsam + 1usize)
    if e3 != ok { ret (fit, e3) }
    let (nbest, e4) = zu(a, nsam)
    if e4 != ok { ret (fit, e4) }
    let (nr, e5) = zu(a, kk + 1usize)
    if e5 != ok { ret (fit, e5) }
    let (nrx, e6) = zu(a, kk)
    if e6 != ok { ret (fit, e6) }
    let (radus, e7) = zf(a, kk + 1usize)
    if e7 != ok { ret (fit, e7) }
    let (ttd, e8) = zf(a, kk + 1usize)
    if e8 != ok { ret (fit, e8) }
    let (ratt, e9) = zf(a, kk + 1usize)
    if e9 != ok { ret (fit, e9) }
    let (ttbes, e10) = zf(a, kk)
    if e10 != ok { ret (fit, e10) }
    let (rdbes, e11) = zf(a, kk)
    if e11 != ok { ret (fit, e11) }
    let (rabes, e12) = zf(a, kk)
    if e12 != ok { ret (fit, e12) }
    let (dysma, e13) = zf(a, nsam + 1usize)
    if e13 != ok { ret (fit, e13) }
    let (dysmb, e14) = zf(a, nsam + 1usize)
    if e14 != ok { ret (fit, e14) }
    let (beter, e15) = zf(a, nsam + 1usize)
    if e15 != ok { ret (fit, e15) }
    let (sky, e16) = zf(a, 1usize)
    if e16 != ok { ret (fit, e16) }
    let (zbv, e17) = zf(a, 1usize)
    if e17 != ok { ret (fit, e17) }
    let rnn = f64(n)
    var zba = 0.0f64 - 1.0f64
    var sx = 0.0f64 - 1.0f64
    let n_dys = nsam * (nsam - 1usize) / 2usize
    let nsamb = nsam * 2usize
    let full_sample = n == nsam
    let lrg_sam = n < nsamb
    var n_sam = nsam
    if lrg_sam { n_sam = n - nsam }
    var kall = false
    var nunfs = 0usize
    var jran = 1usize
    while jran <= nran {
        if !full_sample {
            var ntt = 0usize
            var skip_loop = false
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
                var rand_k = 0usize
                while true {
                    rand_k = clara_draw(&g, rg, n)
                    var clash = false
                    if kall {
                        var jk = 0usize
                        while jk < kk {
                            if rand_k == nrx[jk] { clash = true }
                            jk += 1usize
                        }
                    }
                    if !clash { break }
                }
                nsel[ntt] = rand_k
                ntt += 1usize
                if ntt == n_sam { skip_loop = true }
            }
            if !skip_loop {
                while true {
                    var rand_k = clara_draw(&g, rg, n)
                    var redraw = false
                    if kall && lrg_sam {
                        var jk = 0usize
                        while jk < kk {
                            if rand_k == nrx[jk] { redraw = true }
                            jk += 1usize
                        }
                    }
                    if !redraw {
                        var placed = false
                        var ka = 0usize
                        while ka < ntt && !placed && !redraw {
                            if nsel[ka] >= rand_k {
                                if nsel[ka] == rand_k {
                                    redraw = true
                                } else {
                                    var na = ntt
                                    while na > ka {
                                        nsel[na] = nsel[na - 1usize]
                                        na -= 1usize
                                    }
                                    nsel[ka] = rand_k
                                    placed = true
                                }
                            }
                            ka += 1usize
                        }
                        if !redraw {
                            if !placed { nsel[ntt] = rand_k }
                            ntt += 1usize
                            if ntt >= n_sam { break }
                        }
                    }
                }
            }
            if lrg_sam {
                var jk = 0usize
                var js = 0usize
                var j = 1usize
                while j <= n {
                    if jk < n_sam && nsel[jk] == j {
                        jk += 1usize
                    } else {
                        nrepr[js] = j
                        js += 1usize
                    }
                    j += 1usize
                }
                j = 0usize
                while j < nsam {
                    nsel[j] = nrepr[j]
                    j += 1usize
                }
            }
        } else {
            var j = 0usize
            while j < nsam {
                nsel[j] = j + 1usize
                j += 1usize
            }
        }
        let fine = dysta2(nsam, jpp, nsel, x, n, dys, diss_kind, jtmd, valmd, has_na)
        if !fine {
            nunfs += 1usize
            jran += 1usize
            continue
        }
        var s = 0.0f64
        var l = 1usize
        while l <= n_dys {
            if s < dys[l] { s = dys[l] }
            l += 1usize
        }
        bswap2(kk, nsam, s, dys, pam_like, sky, nrepr, dysma, dysmb, beter)
        let (nafs, e18) = selec(a, kk, n, jpp, diss_kind, zbv, nsam, has_na, jtmd, valmd, nrepr, nsel, dys, x, nr, ttd, radus, ratt, correct_d)
        if e18 != ok { ret (fit, e18) }
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
        jran += 1usize
    }
    fit.obj = zba / rnn
    if nunfs >= nran {
        fit.jstop = 1usize
        ret (fit, ok)
    }
    if !kall {
        fit.jstop = 2usize
        ret (fit, ok)
    }
    let fine2 = dysta2(nsam, jpp, nbest, x, n, dys, diss_kind, jtmd, valmd, has_na)
    if !fine2 { ret (fit, BadArgument) }
    var jz = 0usize
    while jz < kk {
        if nrx[jz] == 0usize { ret (fit, BadArgument) }
        jz += 1usize
    }
    let (clu, e19) = zu(a, n)
    if e19 != ok { ret (fit, e19) }
    let (mtt, e20) = zu(a, kk)
    if e20 != ok { ret (fit, e20) }
    resul(kk, n, jpp, diss_kind, has_na, jtmd, valmd, x, nrx, clu, mtt, correct_d)
    fit.clu = clu
    fit.med = nrx
    fit.sample = nbest
    fit.size = mtt
    fit.maxdis = rdbes
    fit.avdis = ttbes
    fit.ratdis = rabes
    fit.dys = dys
    if kk > 1usize {
        let (sylinf, e21) = zf(a, nsam * 4usize)
        if e21 != ok { ret (fit, e21) }
        let (av2, e22) = zf(a, kk + 1usize)
        if e22 != ok { ret (fit, e22) }
        let (tt, e23) = black(a, kk, nsam, nbest, dys, sx, clu, av2, sylinf)
        if e23 != ok { ret (fit, e23) }
        let (avs, e24) = zf(a, kk)
        if e24 != ok { ret (fit, e24) }
        var i = 0usize
        while i < kk {
            avs[i] = av2[i + 1usize]
            i += 1usize
        }
        fit.silinf = sylinf
        fit.avsil = avs
        fit.ttsil = tt
        fit.has_sil = true
    }
    ret (fit, ok)
}
