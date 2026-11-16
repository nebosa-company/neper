// The nearest-neighbour classifiers of the R package class: knn1, knn (with l, prob and use.all) and
// knn.cv, as VR_knn1 and VR_knn compute them, tie breaking by reservoir sampling on the Mersenne-Twister
// stream of e.algo.rand.r. Training and test rows are row-major; classes are 1-based.
//
// Not here: SOM, batchSOM, the LVQ family and the FNN estimators.

use e.algo.rand.r as rng
use e.math
use e.mem

error TooManyTies

fn dbl_max() -> f64 { ret 1.7976931348623157e308f64 }

fn dist2(train: []const f64, tr: usize, test: []const f64, te: usize, p: usize) -> f64 {
    var d = 0.0f64
    var k = 0usize
    while k < p {
        let t = test[te * p + k] - train[tr * p + k]
        d += t * t
        k += 1usize
    }
    ret d
}

// knn1: the nearest training row of each test row; answers the class of each (1-based)
fn knn1(a: *mem.Arena, g: *rng.Rng, train: []const f64, cl: []const i64, test: []const f64, p: usize, nc: usize) -> ([]i64, err) {
    let ntr = cl.len
    let nte = test.len / p
    let eps = 1.0e-4f64
    var none: []i64 = zero
    let (res, re) = mem.alloc[i64](a, nte)
    if re != ok { ret (none, re) }
    let (ind, ie) = mem.alloc[usize](a, ntr)
    if ie != ok { ret (none, ie) }
    let (votes, ve) = mem.alloc[i64](a, nc + 1usize)
    if ve != ok { ret (none, ve) }
    var nind = 0usize
    var npat = 0usize
    while npat < nte {
        var dm = dbl_max()
        var j = 0usize
        while j < ntr {
            let dist = dist2(train, j, test, npat, p)
            if dist <= dm * (1.0f64 + eps) {
                if dist < dm * (1.0f64 - eps) { nind = 0usize } else { nind += 1usize }
                dm = dist
                ind[nind] = j
            }
            j += 1usize
        }
        var i = 1usize
        while i <= nc {
            votes[i] = 0i64
            i += 1usize
        }
        var index = 0i64
        if nind == 0usize {
            index = cl[ind[0usize]]
        } else {
            i = 0usize
            while i <= nind {
                votes[usize(cl[ind[i]])] += 1i64
                i += 1usize
            }
            var best = votes[1usize]
            index = 1i64
            var ntie = 1i64
            i = 2usize
            while i <= nc {
                if votes[i] > best {
                    ntie = 1i64
                    index = i64(i)
                    best = votes[i]
                } else if votes[i] == best {
                    ntie += 1i64
                    if f64(ntie) * rng.unif(g) < 1.0f64 { index = i64(i) }
                }
                i += 1usize
            }
        }
        res[npat] = index
        npat += 1usize
    }
    ret (res, ok)
}

// knn(train, test, cl, k, l, prob, use.all) and, with cv, knn.cv (the test rows are the training rows,
// each one leaving itself out). Answers the class and the winning proportion of each test row.
fn knn(a: *mem.Arena, g: *rng.Rng, train: []const f64, cl: []const i64, test: []const f64, p: usize, nc: usize, kin: usize, l: i64, cv: bool, use_all: bool) -> ([]i64, []f64, err) {
    let ntr = cl.len
    let nte = test.len / p
    let eps = 1.0e-4f64
    var none: []i64 = zero
    var nonef: []f64 = zero
    let max_ties = 1000usize
    let (res, re) = mem.alloc[i64](a, nte)
    if re != ok { ret (none, nonef, re) }
    let (pr, pe) = mem.alloc[f64](a, nte)
    if pe != ok { ret (none, nonef, pe) }
    let (pos, poe) = mem.alloc[usize](a, max_ties)
    if poe != ok { ret (none, nonef, poe) }
    let (nclass, nce) = mem.alloc[i64](a, max_ties)
    if nce != ok { ret (none, nonef, nce) }
    let (nn, ne) = mem.alloc[f64](a, max_ties)
    if ne != ok { ret (none, nonef, ne) }
    let (votes, ve) = mem.alloc[i64](a, nc + 1usize)
    if ve != ok { ret (none, nonef, ve) }
    var npat = 0usize
    while npat < nte {
        var kn = kin
        var k = 0usize
        while k < kn {
            nn[k] = 0.99f64 * dbl_max()
            k += 1usize
        }
        var j = 0usize
        while j < ntr {
            if !(cv && j == npat) {
                let dist = dist2(train, j, test, npat, p)
                if dist <= nn[kin - 1usize] * (1.0f64 + eps) {
                    k = 0usize
                    var placed = false
                    while k <= kn && !placed {
                        if dist < nn[k] {
                            var k1 = kn
                            while k1 > k {
                                nn[k1] = nn[k1 - 1usize]
                                pos[k1] = pos[k1 - 1usize]
                                k1 -= 1usize
                            }
                            nn[k] = dist
                            pos[k] = j
                            if nn[kn] <= nn[kin - 1usize] {
                                kn += 1usize
                                if kn == max_ties - 1usize { ret (none, nonef, TooManyTies) }
                            }
                            placed = true
                        } else {
                            k += 1usize
                        }
                    }
                }
                nn[kn] = 0.99f64 * dbl_max()
            }
            j += 1usize
        }
        j = 0usize
        while j <= nc {
            votes[j] = 0i64
            j += 1usize
        }
        var extras = 0usize
        if use_all {
            j = 0usize
            while j < kin {
                votes[usize(cl[pos[j]])] += 1i64
                j += 1usize
            }
            j = kin
            var stop = false
            while j < kn && !stop {
                if nn[j] > nn[kin - 1usize] * (1.0f64 + eps) {
                    stop = true
                } else {
                    extras += 1usize
                    votes[usize(cl[pos[j]])] += 1i64
                    j += 1usize
                }
            }
        } else {
            j = 0usize
            var stop = false
            while j < kin && !stop {
                if nn[j] >= nn[kin - 1usize] * (1.0f64 - eps) {
                    stop = true
                } else {
                    votes[usize(cl[pos[j]])] += 1i64
                    j += 1usize
                }
            }
            var j1 = j
            if j1 == kin - 1usize {
                votes[usize(cl[pos[j1]])] += 1i64
            } else {
                j1 = j
                let needed = kin - j1
                j = 0usize
                while j < needed {
                    nclass[j] = cl[pos[j1 + j]]
                    j += 1usize
                }
                var t = needed
                j = j1 + needed
                var stop2 = false
                while j < kn && !stop2 {
                    if nn[j] > nn[kin - 1usize] * (1.0f64 + eps) {
                        stop2 = true
                    } else {
                        t += 1usize
                        if f64(t) * rng.unif(g) < f64(needed) {
                            let j2 = j1 + usize(rng.unif(g) * f64(needed))
                            nclass[j2] = cl[pos[j]]
                        }
                        j += 1usize
                    }
                }
                j = 0usize
                while j < needed {
                    votes[usize(nclass[j])] += 1i64
                    j += 1usize
                }
            }
        }
        var ntie = 1i64
        var mm = 0i64
        if l > 0i64 { mm = l - 1i64 + i64(extras) }
        var index = 0i64
        var i = 1usize
        while i <= nc {
            if votes[i] > mm {
                ntie = 1i64
                index = i64(i)
                mm = votes[i]
            } else if votes[i] == mm && votes[i] >= l {
                ntie += 1i64
                if f64(ntie) * rng.unif(g) < 1.0f64 { index = i64(i) }
            }
            i += 1usize
        }
        res[npat] = index
        pr[npat] = f64(mm) / f64(kin + extras)
        npat += 1usize
    }
    ret (res, pr, ok)
}
