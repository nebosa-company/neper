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
