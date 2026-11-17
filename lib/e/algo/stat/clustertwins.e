// R cluster (Maechler et al., 2.1.8.2): agnes and diana, ported from the package's twins.c.
//
//   agnes_core    agglomerative nesting for the methods average, single, complete, ward, weighted, flexible and gaverage
//                 (Lance-Williams with the parameters alpha[0..3]); order, banner heights, merge matrix, agglomerative coefficient
//   diana_core    divisive analysis: the order, the splitting heights, the merge matrix, the divisive coefficient
//   twins_tree    the answer as an hclust Tree (as.hclust.twins), so cutree and the cophenetic functions of e.algo.stat.hclust apply
//   coef_hclust   coef.hclust and coefHier: the agglomerative coefficient of the heights of a tree
//
// The input is a cdv (see e.algo.stat.clusterdiss) of n objects; the method codes are those of the package: 1 average, 2 single,
// 3 complete, 4 ward, 5 weighted, 6 flexible, 7 gaverage. ban[0] is 0 and ban[1..n-1] are R's height, as R's `ban` is.
//
// Not here: the banner and dendrogram plots.

use e.algo.stat.clusterdiss as cd
use e.algo.stat.hclust as hc
use e.math
use e.mem

error BadMerge

type TwinsOut = struct { ner: []usize, ban: []f64, merge_a: []i32, merge_b: []i32, coef: f64 }

// the agglomerative or divisive coefficient from a banner (0-based, ban[0] = 0)
fn bncoef(n: usize, ban: []const f64) -> f64 {
    var sup = 0.0f64
    var k = 1usize
    while k < n {
        if sup < ban[k] { sup = ban[k] }
        k += 1usize
    }
    var cf = 0.0f64
    k = 0usize
    while k < n {
        var kearl = 1usize
        if k > 0usize { kearl = k }
        k += 1usize
        var kafte = n - 1usize
        if k < n { kafte = k }
        let syze = math.min[f64](ban[kearl], ban[kafte])
        cf += 1.0f64 - syze / sup
    }
    ret cf / f64(n)
}

// the position-in-merge bookkeeping both algorithms share: l1 and l2 (negative object numbers) become the number of the
// earlier merge they joined
fn twins_relabel(ma: []const i64, mb: []const i64, nmerge: usize, l: i64) -> i64 {
    var r = l
    var j = 0usize
    while j < nmerge {
        if ma[j] == r || mb[j] == r { r = i64(j) + 1i64 }
        j += 1usize
    }
    ret r
}

fn twins_finish(a: *mem.Arena, n: usize, ner: []const usize, ban: []const f64, ma: []const i64, mb: []const i64) -> (TwinsOut, err) {
    let (o, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (zero, e1) }
    let (b, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (zero, e2) }
    let (ia, e3) = mem.alloc[i32](a, n - 1usize)
    if e3 != ok { ret (zero, e3) }
    let (ib, e4) = mem.alloc[i32](a, n - 1usize)
    if e4 != ok { ret (zero, e4) }
    var i = 0usize
    while i < n {
        o[i] = ner[i + 1usize]
        b[i] = ban[i + 1usize]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < n {
        ia[i] = i32(ma[i])
        ib[i] = i32(mb[i])
        i += 1usize
    }
    let cf = bncoef(n, b)
    ret (TwinsOut { ner: o, ban: b, merge_a: ia, merge_b: ib, coef: cf }, ok)
}

// agnes(): dys0 is a cdv, method 1..7, alpha the four Lance-Williams parameters (read for methods 6 and 7)
fn agnes_core(a: *mem.Arena, dys0: []const f64, n: usize, method: usize, alpha: []const f64) -> (TwinsOut, err) {
    let nh = n * (n - 1usize) / 2usize + 1usize
    let (dys, e1) = mem.alloc[f64](a, nh)
    if e1 != ok { ret (zero, e1) }
    let (kwan, e2) = mem.alloc[usize](a, n + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (ner, e3) = mem.alloc[usize](a, n + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (ban, e4) = mem.alloc[f64](a, n + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (ma, e5) = mem.alloc[i64](a, n)
    if e5 != ok { ret (zero, e5) }
    let (mb, e6) = mem.alloc[i64](a, n)
    if e6 != ok { ret (zero, e6) }
    var i = 0usize
    while i < nh {
        dys[i] = dys0[i]
        i += 1usize
    }
    let n_1 = n - 1usize
    let flex_meth = method == 6usize || method == 7usize
    var has_a3 = false
    var has_a4 = false
    if flex_meth {
        has_a3 = alpha[2usize] != 0.0f64
        has_a4 = alpha[3usize] != 0.0f64
    }
    i = 0usize
    while i <= n {
        kwan[i] = 1usize
        ner[i] = i
        ban[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        ma[i] = 0i64
        mb[i] = 0i64
        i += 1usize
    }
    var la = 0usize
    var lb = 0usize
    var nmerge = 0usize
    while nmerge < n_1 {
        var j = 2usize
        while kwan[j] == 0usize { j += 1usize }
        var d_min = dys[cd.ind_2(1usize, j)] * 1.100000023841858f64 + 1.0f64
        var k = 1usize
        while k <= n_1 {
            if kwan[k] > 0usize {
                j = k + 1usize
                while j <= n {
                    if kwan[j] > 0usize {
                        let k_j = cd.ind_2(k, j)
                        if d_min >= dys[k_j] {
                            d_min = dys[k_j]
                            la = k
                            lb = j
                        }
                    }
                    j += 1usize
                }
            }
            k += 1usize
        }
        let l1 = twins_relabel(ma, mb, nmerge, 0i64 - i64(la))
        let l2 = twins_relabel(ma, mb, nmerge, 0i64 - i64(lb))
        ma[nmerge] = l1
        mb[nmerge] = l2
        if flex_meth && l1 == l2 { ret (zero, BadMerge) }
        var llast = 0usize
        var lfyrs = 0usize
        k = 1usize
        while k <= n {
            if ner[k] == la { lfyrs = k }
            if ner[k] == lb { llast = k }
            k += 1usize
        }
        ban[llast] = d_min
        let lnext = lfyrs + kwan[la]
        if lnext != llast {
            let lput = lfyrs + kwan[la]
            let lenda = llast + kwan[lb] - 2usize
            k = 1usize
            while k + lput <= llast {
                let lka = ner[lput]
                let akb = ban[lput]
                j = lput
                while j <= lenda {
                    ner[j] = ner[j + 1usize]
                    ban[j] = ban[j + 1usize]
                    j += 1usize
                }
                ner[lenda + 1usize] = lka
                ban[lenda + 1usize] = akb
                k += 1usize
            }
        }
        var lq = 1usize
        while lq <= n {
            if lq != la && lq != lb && kwan[lq] != 0usize {
                let naq = cd.ind_2(la, lq)
                let nbq = cd.ind_2(lb, lq)
                if method == 1usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let fa = ta / (ta + tb)
                    let fb = tb / (ta + tb)
                    dys[naq] = fa * dys[naq] + fb * dys[nbq]
                }
                if method == 2usize { dys[naq] = math.min[f64](dys[naq], dys[nbq]) }
                if method == 3usize { dys[naq] = math.max[f64](dys[naq], dys[nbq]) }
                if method == 4usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let tq = f64(kwan[lq])
                    let fa = (ta + tq) / (ta + tb + tq)
                    let fb = (tb + tq) / (ta + tb + tq)
                    let fc = 0.0f64 - tq / (ta + tb + tq)
                    let nab = cd.ind_2(la, lb)
                    dys[naq] = math.sqrt[f64](fa * dys[naq] * dys[naq] + fb * dys[nbq] * dys[nbq] + fc * dys[nab] * dys[nab])
                }
                if method == 5usize { dys[naq] = (dys[naq] + dys[nbq]) / 2.0f64 }
                if method == 6usize {
                    var dnew = alpha[0usize] * dys[naq] + alpha[1usize] * dys[nbq]
                    if has_a3 { dnew += alpha[2usize] * dys[cd.ind_2(la, lb)] }
                    if has_a4 { dnew += alpha[3usize] * math.abs[f64](dys[naq] - dys[nbq]) }
                    dys[naq] = dnew
                }
                if method == 7usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let fa = alpha[0usize] * ta / (ta + tb)
                    let fb = alpha[1usize] * tb / (ta + tb)
                    var dnew = fa * dys[naq] + fb * dys[nbq]
                    if has_a3 { dnew += alpha[2usize] * dys[cd.ind_2(la, lb)] }
                    if has_a4 { dnew += alpha[3usize] * math.abs[f64](dys[naq] - dys[nbq]) }
                    dys[naq] = dnew
                }
            }
            lq += 1usize
        }
        kwan[la] += kwan[lb]
        kwan[lb] = 0usize
        nmerge += 1usize
    }
    let (res, ef) = twins_finish(a, n, ner, ban, ma, mb)
    ret (res, ef)
}

// the largest dissimilarity inside the cluster at positions ka..kb of ner
fn min_dis(dys: []const f64, ka: usize, kb: usize, ner: []const usize) -> f64 {
    var dm = 0.0f64
    var k = ka
    while k < kb {
        var j = k + 1usize
        while j <= kb {
            let v = dys[cd.ind_2(ner[k], ner[j])]
            if dm < v { dm = v }
            j += 1usize
        }
        k += 1usize
    }
    ret dm
}

// diana() (splyt): dys0 a cdv
fn diana_core(a: *mem.Arena, dys: []const f64, n: usize) -> (TwinsOut, err) {
    let (kwan0, e1) = mem.alloc[i64](a, n + 1usize)
    if e1 != ok { ret (zero, e1) }
    let (ner, e2) = mem.alloc[usize](a, n + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (ban, e3) = mem.alloc[f64](a, n + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (ma, e4) = mem.alloc[i64](a, n)
    if e4 != ok { ret (zero, e4) }
    let (mb, e5) = mem.alloc[i64](a, n)
    if e5 != ok { ret (zero, e5) }
    let n_1 = n - 1usize
    var nclu = 1usize
    let nhalf = n * n_1 / 2usize + 1usize
    var l = 1usize
    while l <= n {
        kwan0[l] = 0i64
        ban[l] = 0.0f64
        ner[l] = l
        l += 1usize
    }
    kwan0[0usize] = 0i64
    ban[0usize] = 0.0f64
    ner[0usize] = 0usize
    kwan0[1usize] = i64(n)
    ma[0usize] = 0i64
    mb[0usize] = 0i64
    var ja = 1usize
    var cs = 0.0f64
    var k = 0usize
    while k < nhalf {
        if cs < dys[k] { cs = dys[k] }
        k += 1usize
    }
    var jb = 0usize
    var jma = 0usize
    var jmb = 0usize
    var more = true
    while more {
        // L30
        jb = ja + usize(kwan0[ja]) - 1usize
        jma = jb
        if kwan0[ja] == 2i64 {
            kwan0[ja] = 1i64
            kwan0[jb] = 1i64
            ban[jb] = dys[cd.ind_2(ner[ja], ner[jb])]
        } else {
            var bygsd = 0.0f64 - 1.0f64
            var lndsd = 0usize
            l = ja
            while l <= jb {
                let lner = ner[l]
                var sd = 0.0f64
                var j = ja
                while j <= jb {
                    sd += dys[cd.ind_2(lner, ner[j])]
                    j += 1usize
                }
                if bygsd < sd {
                    bygsd = sd
                    lndsd = l
                }
                l += 1usize
            }
            kwan0[ja] -= 1i64
            kwan0[jb] = 1i64
            if jb != lndsd {
                let lchan = ner[lndsd]
                var lmma = lndsd
                while lmma + 1usize <= jb {
                    ner[lmma] = ner[lmma + 1usize]
                    lmma += 1usize
                }
                ner[jb] = lchan
            }
            var splyn = 0usize
            jma = jb - 1usize
            var shifting = true
            while shifting {
                splyn += 1usize
                let rest = jma - ja
                var jaway = 0usize
                var bdyff = 0.0f64 - 1.0f64
                l = ja
                while l <= jma {
                    let lner = ner[l]
                    var da = 0.0f64
                    var db = 0.0f64
                    var j = ja
                    while j <= jma {
                        da += dys[cd.ind_2(lner, ner[j])]
                        j += 1usize
                    }
                    da = da / f64(rest)
                    j = jma + 1usize
                    while j <= jb {
                        db += dys[cd.ind_2(lner, ner[j])]
                        j += 1usize
                    }
                    db = db / f64(splyn)
                    let dyff = da - db
                    if bdyff < dyff {
                        bdyff = dyff
                        jaway = l
                    }
                    l += 1usize
                }
                jmb = jma + 1usize
                if bdyff <= 0.0f64 {
                    shifting = false
                } else {
                    if jma != jaway {
                        let lchan = ner[jaway]
                        var lxx = jaway
                        while lxx + 1usize <= jma {
                            ner[lxx] = ner[lxx + 1usize]
                            lxx += 1usize
                        }
                        ner[jma] = lchan
                    }
                    var lxx = jmb
                    var stop = false
                    while lxx <= jb && !stop {
                        let l_1 = lxx - 1usize
                        if ner[l_1] < ner[lxx] {
                            stop = true
                        } else {
                            let lchan = ner[l_1]
                            ner[l_1] = ner[lxx]
                            ner[lxx] = lchan
                            lxx += 1usize
                        }
                    }
                    kwan0[ja] -= 1i64
                    kwan0[jma] = kwan0[jmb] + 1i64
                    kwan0[jmb] = 0i64
                    jma -= 1usize
                    jmb = jma + 1usize
                    if jma == ja { shifting = false }
                }
            }
            // switch the two parts when necessary
            if ner[ja] >= ner[jmb] {
                var lxxa = ja
                var lgrb = jmb
                while lgrb <= jb {
                    lxxa += 1usize
                    let lchan = ner[lgrb]
                    var lxg = 0usize
                    var ll = lxxa
                    while ll <= lgrb {
                        let lxf = lgrb - ll + lxxa
                        lxg = lxf - 1usize
                        ner[lxf] = ner[lxg]
                        ll += 1usize
                    }
                    ner[lxg] = lchan
                    lgrb += 1usize
                }
                let llq = kwan0[jmb]
                kwan0[jmb] = 0i64
                jma = ja + jb - jma - 1usize
                jmb = jma + 1usize
                kwan0[jmb] = kwan0[ja]
                kwan0[ja] = llq
            }
            if nclu == 1usize {
                ban[jmb] = cs
            } else {
                ban[jmb] = min_dis(dys, ja, jb, ner)
            }
        }
        nclu += 1usize
        if nclu < n {
            var st = 1usize
            if jb != n { st = 2usize } else { st = 3usize }
            var found = false
            while !found {
                if st == 2usize {
                    ja += usize(kwan0[ja])
                    if ja <= n {
                        if kwan0[ja] <= 1i64 { st = 2usize } else { found = true }
                    } else {
                        st = 3usize
                    }
                } else {
                    ja = 1usize
                    if kwan0[ja] == 1i64 { st = 2usize } else { found = true }
                }
            }
        } else {
            more = false
        }
    }
    // merge structure
    var nmerge = 0usize
    while nmerge < n_1 {
        var nj = 0usize
        var dmin = cs
        var j = 2usize
        while j <= n {
            if kwan0[j] >= 0i64 && dmin >= ban[j] {
                dmin = ban[j]
                nj = j
            }
            j += 1usize
        }
        kwan0[nj] = 0i64 - 1i64
        let l1 = twins_relabel(ma, mb, nmerge, 0i64 - i64(ner[nj - 1usize]))
        let l2 = twins_relabel(ma, mb, nmerge, 0i64 - i64(ner[nj]))
        ma[nmerge] = l1
        mb[nmerge] = l2
        nmerge += 1usize
    }
    let (res, ef) = twins_finish(a, n, ner, ban, ma, mb)
    ret (res, ef)
}

// as.hclust(twins): the merge matrix and the sorted heights as an hclust Tree
fn twins_tree(a: *mem.Arena, t: TwinsOut, n: usize) -> (hc.Tree, err) {
    let (ord, e1) = mem.alloc[i32](a, n)
    if e1 != ok { ret (zero, e1) }
    let (h, e2) = mem.alloc[f64](a, n - 1usize)
    if e2 != ok { ret (zero, e2) }
    var i = 0usize
    while i < n {
        ord[i] = i32(t.ner[i])
        i += 1usize
    }
    i = 0usize
    while i + 1usize < n {
        let v = t.ban[i + 1usize]
        var j = i
        while j > 0usize && h[j - 1usize] > v {
            h[j] = h[j - 1usize]
            j -= 1usize
        }
        h[j] = v
        i += 1usize
    }
    ret (hc.Tree { merge_a: t.merge_a, merge_b: t.merge_b, height: h, order: ord }, ok)
}

// the four Lance-Williams parameters of agnes(method = "flexible" or "gaverage") from par.method (np 0 only for gaverage)
fn lance_alpha(method: usize, par: []const f64, np: usize, out: []f64) {
    out[3usize] = 0.0f64
    if np == 0usize {
        out[0usize] = 1.1f64
        out[1usize] = 1.1f64
        out[2usize] = 0.0f64 - 0.1f64
        ret
    }
    if np == 1usize {
        if method == 6usize {
            out[0usize] = par[0usize]
            out[1usize] = par[0usize]
            out[2usize] = 1.0f64 - 2.0f64 * par[0usize]
        } else {
            out[0usize] = 1.0f64 - par[0usize]
            out[1usize] = 1.0f64 - par[0usize]
            out[2usize] = par[0usize]
        }
        ret
    }
    out[0usize] = par[0usize]
    out[1usize] = par[1usize]
    out[2usize] = par[2usize]
    if np == 4usize { out[3usize] = par[3usize] }
}

// coef.hclust(): one minus the weighted mean of the heights at which observations first merge, over the largest height
fn coef_hclust(t: *const hc.Tree, n: usize) -> f64 {
    var s = 0.0f64
    var mx = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        var cnt = 0.0f64
        if t.merge_a[i] < 0i32 { cnt += 1.0f64 }
        if t.merge_b[i] < 0i32 { cnt += 1.0f64 }
        s += cnt * t.height[i]
        if t.height[i] > mx { mx = t.height[i] }
        i += 1usize
    }
    ret 1.0f64 - s / mx / f64(n)
}
