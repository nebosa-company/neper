// R package cluster: agnes (every method, flexible and gaverage with par.method), diana, mona and the agglomerative / divisive coefficient, ported from
// cluster 2.1.8.2's twins.c and mona.c. A dissimilarity is the packed lower triangle of e.algo.stat.clusterpkg (dys[ind2(i, j)], dys[0] = 0); every
// working array is 1-based as in the C source. cutree and the coefficient of a merge tree reuse e.algo.stat.hclust's Tree.

use e.algo.stat.clusterpkg as cp
use e.algo.stat.hclust as hc
use e.math
use e.mem

error BadTree

// order: the plotting order (1-based observation numbers); height: the n - 1 merge heights (banner); coef: agglomerative (agnes) or divisive (diana) coefficient;
// merge_a, merge_b: the two columns of the merge matrix (negative: an observation, positive: an earlier step)
type TwinsFit = struct { order: []usize, height: []f64, coef: f64, merge_a: []i64, merge_b: []i64 }

// the coefficient of a banner: ban[0..n) as the C code receives it (ban[0] is 0 for agnes and diana); the heights are ban[1..n)
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
        var syze = ban[kearl]
        if ban[kafte] < syze { syze = ban[kafte] }
        cf += (1.0f64 - syze / sup)
        // k has been advanced as in the C loop
    }
    ret cf / f64(n)
}

// the coefficient from the heights alone, as coefHier(): ban = c(0, height)
fn coef_hier(a: *mem.Arena, height: []const f64) -> (f64, err) {
    let n = height.len + 1usize
    let (ban, e) = cp.zf(a, n)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < height.len {
        ban[i + 1usize] = height[i]
        i += 1usize
    }
    ret (bncoef(n, ban), ok)
}

// the merge matrix entry of step i, column 1 or 2 (Merge(i, j) of the C code)
fn merge_new(l1: i64, l2: i64, merge_a: []i64, merge_b: []i64, nmerge: usize) -> (i64, i64) {
    var a1 = l1
    var a2 = l2
    var j = 0usize
    while j < nmerge {
        if merge_a[j] == a1 || merge_b[j] == a1 { a1 = i64(j) + 1i64 }
        if merge_a[j] == a2 || merge_b[j] == a2 { a2 = i64(j) + 1i64 }
        j += 1usize
    }
    ret (a1, a2)
}

// agnes on the packed dissimilarity dys (not changed); method 1 average, 2 single, 3 complete, 4 ward, 5 weighted, 6 flexible, 7 gaverage; alpha is
// par.method of length 4 (alpha[0..3]) for the last two: flexible c(a1, a2, b, c), gaverage the same with a1, a2 scaled by cluster size
fn agnes(a: *mem.Arena, dys_in: []const f64, nn: usize, method: usize, alpha: []const f64) -> (TwinsFit, err) {
    var fit: TwinsFit = zero
    if nn < 2usize || method < 1usize || method > 7usize { ret (fit, cp.BadArgument) }
    let (dys, e0) = cp.zf(a, dys_in.len)
    if e0 != ok { ret (fit, e0) }
    var q = 0usize
    while q < dys_in.len {
        dys[q] = dys_in[q]
        q += 1usize
    }
    let n_1 = nn - 1usize
    let (kwan, e1) = cp.zu(a, nn + 2usize)
    if e1 != ok { ret (fit, e1) }
    let (ner, e2) = cp.zu(a, nn + 2usize)
    if e2 != ok { ret (fit, e2) }
    let (ban, e3) = cp.zf(a, nn + 2usize)
    if e3 != ok { ret (fit, e3) }
    let (merge_a, e4) = cp.zi(a, n_1)
    if e4 != ok { ret (fit, e4) }
    let (merge_b, e5) = cp.zi(a, n_1)
    if e5 != ok { ret (fit, e5) }
    let flex = method == 6usize || method == 7usize
    var has_a3 = false
    var has_a4 = false
    if flex {
        has_a3 = alpha[2usize] != 0.0f64
        has_a4 = alpha[3usize] != 0.0f64
    }
    var j = 1usize
    while j <= nn {
        kwan[j] = 1usize
        ner[j] = j
        j += 1usize
    }
    var la = 0usize
    var lb = 0usize
    var nmerge = 0usize
    while nmerge < n_1 {
        j = 1usize
        j += 1usize
        while kwan[j] == 0usize { j += 1usize }
        var d_min = dys[cp.ind2(1usize, j)] * 1.10000002384185791015625f64 + 1.0f64
        var k = 1usize
        while k <= n_1 {
            if kwan[k] > 0usize {
                j = k + 1usize
                while j <= nn {
                    if kwan[j] > 0usize {
                        let k_j = cp.ind2(k, j)
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
        let (l1, l2) = merge_new(0i64 - i64(la), 0i64 - i64(lb), merge_a, merge_b, nmerge)
        merge_a[nmerge] = l1
        merge_b[nmerge] = l2
        if flex && l1 == l2 { ret (fit, BadTree) }
        var llast = 0usize
        var lfyrs = 0usize
        k = 1usize
        while k <= nn {
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
        while lq <= nn {
            if lq != la && lq != lb && kwan[lq] != 0usize {
                let naq = cp.ind2(la, lq)
                let nbq = cp.ind2(lb, lq)
                if method == 1usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let fa = ta / (ta + tb)
                    let fb = tb / (ta + tb)
                    dys[naq] = fa * dys[naq] + fb * dys[nbq]
                }
                if method == 2usize {
                    if dys[nbq] < dys[naq] { dys[naq] = dys[nbq] }
                }
                if method == 3usize {
                    if dys[nbq] > dys[naq] { dys[naq] = dys[nbq] }
                }
                if method == 4usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let tq = f64(kwan[lq])
                    let fa = (ta + tq) / (ta + tb + tq)
                    let fb = (tb + tq) / (ta + tb + tq)
                    let fc = (0.0f64 - tq) / (ta + tb + tq)
                    let nab = cp.ind2(la, lb)
                    dys[naq] = math.sqrt[f64](fa * dys[naq] * dys[naq] + fb * dys[nbq] * dys[nbq] + fc * dys[nab] * dys[nab])
                }
                if method == 5usize { dys[naq] = (dys[naq] + dys[nbq]) / 2.0f64 }
                if method == 6usize {
                    var d_new = alpha[0usize] * dys[naq] + alpha[1usize] * dys[nbq]
                    if has_a3 { d_new += alpha[2usize] * dys[cp.ind2(la, lb)] }
                    if has_a4 { d_new += alpha[3usize] * math.abs[f64](dys[naq] - dys[nbq]) }
                    dys[naq] = d_new
                }
                if method == 7usize {
                    let ta = f64(kwan[la])
                    let tb = f64(kwan[lb])
                    let fa = alpha[0usize] * ta / (ta + tb)
                    let fb = alpha[1usize] * tb / (ta + tb)
                    var d_new = fa * dys[naq] + fb * dys[nbq]
                    if has_a3 { d_new += alpha[2usize] * dys[cp.ind2(la, lb)] }
                    if has_a4 { d_new += alpha[3usize] * math.abs[f64](dys[naq] - dys[nbq]) }
                    dys[naq] = d_new
                }
            }
            lq += 1usize
        }
        kwan[la] += kwan[lb]
        kwan[lb] = 0usize
        nmerge += 1usize
    }
    let (height, e6) = cp.zf(a, n_1)
    if e6 != ok { ret (fit, e6) }
    let (order, e7) = cp.zu(a, nn)
    if e7 != ok { ret (fit, e7) }
    let (raw, e8) = cp.zf(a, nn)
    if e8 != ok { ret (fit, e8) }
    j = 0usize
    while j < nn {
        raw[j] = ban[j + 1usize]
        order[j] = ner[j + 1usize]
        if j >= 1usize { height[j - 1usize] = ban[j + 1usize] }
        j += 1usize
    }
    fit.order = order
    fit.height = height
    fit.coef = bncoef(nn, raw)
    fit.merge_a = merge_a
    fit.merge_b = merge_b
    ret (fit, ok)
}

// the smallest-diameter helper of splyt: the largest dissimilarity among the objects ner[ja..jb]
fn min_dis(dys: []const f64, ka: usize, kb: usize, ner: []const usize) -> f64 {
    var dm = 0.0f64
    var k = ka
    while k < kb {
        let ner_k = ner[k]
        var j = k + 1usize
        while j <= kb {
            let k_j = cp.ind2(ner_k, ner[j])
            if dm < dys[k_j] { dm = dys[k_j] }
            j += 1usize
        }
        k += 1usize
    }
    ret dm
}

// diana on the packed dissimilarity dys (not changed)
fn diana(a: *mem.Arena, dys: []const f64, nn: usize) -> (TwinsFit, err) {
    var fit: TwinsFit = zero
    if nn < 2usize { ret (fit, cp.BadArgument) }
    let n_1 = nn - 1usize
    let nhalf = nn * n_1 / 2usize + 1usize
    let (kwan, e1) = cp.zu(a, nn + 2usize)
    if e1 != ok { ret (fit, e1) }
    let (ner, e2) = cp.zu(a, nn + 2usize)
    if e2 != ok { ret (fit, e2) }
    let (ban, e3) = cp.zf(a, nn + 2usize)
    if e3 != ok { ret (fit, e3) }
    let (merge_a, e4) = cp.zi(a, n_1)
    if e4 != ok { ret (fit, e4) }
    let (merge_b, e5) = cp.zi(a, n_1)
    if e5 != ok { ret (fit, e5) }
    var nclu = 1usize
    var l = 1usize
    while l <= nn {
        kwan[l] = 0usize
        ban[l] = 0.0f64
        ner[l] = l
        l += 1usize
    }
    kwan[1usize] = nn
    var ja = 1usize
    var cs = 0.0f64
    var k = 0usize
    while k < nhalf {
        if cs < dys[k] { cs = dys[k] }
        k += 1usize
    }
    var j = 0usize
    var jb = 0usize
    var jma = 0usize
    var jmb = 0usize
    while true {
        jb = ja + kwan[ja] - 1usize
        jma = jb
        if kwan[ja] == 2usize {
            kwan[ja] = 1usize
            kwan[jb] = 1usize
            ban[jb] = dys[cp.ind2(ner[ja], ner[jb])]
        } else {
            var bygsd = 0.0f64 - 1.0f64
            var lndsd = 0usize
            l = ja
            while l <= jb {
                let lner = ner[l]
                var sd = 0.0f64
                j = ja
                while j <= jb {
                    sd += dys[cp.ind2(lner, ner[j])]
                    j += 1usize
                }
                if bygsd < sd {
                    bygsd = sd
                    lndsd = l
                }
                l += 1usize
            }
            kwan[ja] -= 1usize
            kwan[jb] = 1usize
            if jb != lndsd {
                let lchan = ner[lndsd]
                let lmm = jb - 1usize
                var lmma = lndsd
                while lmma <= lmm {
                    ner[lmma] = ner[lmma + 1usize]
                    lmma += 1usize
                }
                ner[jb] = lchan
            }
            var splyn = 0usize
            jma = jb - 1usize
            while true {
                splyn += 1usize
                let rest = jma - ja
                var jaway = 0usize
                var bdyff = 0.0f64 - 1.0f64
                l = ja
                while l <= jma {
                    let lner = ner[l]
                    var da = 0.0f64
                    var db = 0.0f64
                    j = ja
                    while j <= jma {
                        da += dys[cp.ind2(lner, ner[j])]
                        j += 1usize
                    }
                    da /= f64(rest)
                    j = jma + 1usize
                    while j <= jb {
                        db += dys[cp.ind2(lner, ner[j])]
                        j += 1usize
                    }
                    db /= f64(splyn)
                    let dyff = da - db
                    if bdyff < dyff {
                        bdyff = dyff
                        jaway = l
                    }
                    l += 1usize
                }
                jmb = jma + 1usize
                if bdyff <= 0.0f64 { break }
                if jma != jaway {
                    let lchan = ner[jaway]
                    let lmz = jma - 1usize
                    var lxx = jaway
                    while lxx <= lmz {
                        ner[lxx] = ner[lxx + 1usize]
                        lxx += 1usize
                    }
                    ner[jma] = lchan
                }
                var lxx = jmb
                while lxx <= jb {
                    let l_1 = lxx - 1usize
                    if ner[l_1] < ner[lxx] { break }
                    let lchan = ner[l_1]
                    ner[l_1] = ner[lxx]
                    ner[lxx] = lchan
                    lxx += 1usize
                }
                kwan[ja] -= 1usize
                kwan[jma] = kwan[jmb] + 1usize
                kwan[jmb] = 0usize
                jma -= 1usize
                jmb = jma + 1usize
                if jma == ja { break }
            }
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
                let llq = kwan[jmb]
                kwan[jmb] = 0usize
                jma = ja + jb - jma - 1usize
                jmb = jma + 1usize
                kwan[jmb] = kwan[ja]
                kwan[ja] = llq
            }
            if nclu == 1usize {
                ban[jmb] = cs
            } else {
                ban[jmb] = min_dis(dys, ja, jb, ner)
            }
        }
        nclu += 1usize
        if !(nclu < nn) { break }
        var l420 = jb != nn
        while true {
            if l420 {
                ja += kwan[ja]
                if ja <= nn {
                    if kwan[ja] <= 1usize { continue }
                    break
                }
            }
            ja = 1usize
            if kwan[ja] == 1usize {
                l420 = true
                continue
            }
            break
        }
    }
    let (used, e6) = cp.zu(a, nn + 2usize)
    if e6 != ok { ret (fit, e6) }
    var nmerge = 0usize
    while nmerge < n_1 {
        var nj = 0usize
        var dmin = cs
        j = 2usize
        while j <= nn {
            if used[j] == 0usize && dmin >= ban[j] {
                dmin = ban[j]
                nj = j
            }
            j += 1usize
        }
        if nj == 0usize { ret (fit, BadTree) }
        used[nj] = 1usize
        let (l1, l2) = merge_new(0i64 - i64(ner[nj - 1usize]), 0i64 - i64(ner[nj]), merge_a, merge_b, nmerge)
        merge_a[nmerge] = l1
        merge_b[nmerge] = l2
        nmerge += 1usize
    }
    let (height, e7) = cp.zf(a, n_1)
    if e7 != ok { ret (fit, e7) }
    let (order, e8) = cp.zu(a, nn)
    if e8 != ok { ret (fit, e8) }
    let (raw, e9) = cp.zf(a, nn)
    if e9 != ok { ret (fit, e9) }
    j = 0usize
    while j < nn {
        raw[j] = ban[j + 1usize]
        order[j] = ner[j + 1usize]
        if j >= 1usize { height[j - 1usize] = ban[j + 1usize] }
        j += 1usize
    }
    fit.order = order
    fit.height = height
    fit.coef = bncoef(nn, raw)
    fit.merge_a = merge_a
    fit.merge_b = merge_b
    ret (fit, ok)
}

// the merge tree of a twins fit as e.algo.stat.hclust's Tree, for cutree and cophenetic distances
fn to_tree(a: *mem.Arena, fit: *const TwinsFit) -> (hc.Tree, err) {
    let m = fit.height.len
    let (ma, e1) = mem.alloc[i32](a, m)
    if e1 != ok { ret (zero, e1) }
    let (mb, e2) = mem.alloc[i32](a, m)
    if e2 != ok { ret (zero, e2) }
    let (ord, e3) = mem.alloc[i32](a, fit.order.len)
    if e3 != ok { ret (zero, e3) }
    var i = 0usize
    while i < m {
        ma[i] = i32(fit.merge_a[i])
        mb[i] = i32(fit.merge_b[i])
        i += 1usize
    }
    i = 0usize
    while i < fit.order.len {
        ord[i] = i32(fit.order[i])
        i += 1usize
    }
    ret (hc.Tree { merge_a: ma, merge_b: mb, height: fit.height, order: ord }, ok)
}

// coef.hclust: 1 - sum(rowSums(merge < 0) * height) / max(height) / (nh + 1)
// (as.hclust of a twins object sorts the heights, which is what coef.hclust then sees)
fn coef_hclust(a: *mem.Arena, fit: *const TwinsFit) -> (f64, err) {
    let nh = fit.height.len
    let (ht, e) = cp.zf(a, nh)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < nh {
        let v = fit.height[i]
        var j = i
        while j > 0usize && ht[j - 1usize] > v {
            ht[j] = ht[j - 1usize]
            j -= 1usize
        }
        ht[j] = v
        i += 1usize
    }
    var mx = 0.0f64
    var s = 0.0f64
    i = 0usize
    while i < nh {
        if ht[i] > mx { mx = ht[i] }
        var cnt = 0.0f64
        if fit.merge_a[i] < 0i64 { cnt += 1.0f64 }
        if fit.merge_b[i] < 0i64 { cnt += 1.0f64 }
        s += cnt * ht[i]
        i += 1usize
    }
    ret (1.0f64 - s / mx / f64(nh + 1usize), ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// mona

// order, variable (the variable of each of steps 2..n, 0 for none) and step (the pass of each split); jerr is 0 or the C code's error 1..5; data is the revised
// 0/1 matrix (missing values filled in)
type MonaFit = struct { order: []usize, variable: []usize, step: []usize, jerr: usize, data: []i64 }

fn iabs(v: i64) -> i64 {
    if v >= 0i64 { ret v }
    ret 0i64 - v
}

// x is n by p column-major with 0, 1 and 2 (missing); not changed
fn mona(a: *mem.Arena, x_in: []const i64, nn: usize, pp: usize) -> (MonaFit, err) {
    var fit: MonaFit = zero
    let (x, e0) = cp.zi(a, nn * pp)
    if e0 != ok { ret (fit, e0) }
    var q = 0usize
    while q < nn * pp {
        x[q] = x_in[q]
        q += 1usize
    }
    fit.data = x
    if pp < 2usize {
        fit.jerr = 5usize
        ret (fit, ok)
    }
    let (kwan, e1) = cp.zi(a, nn + 2usize)
    if e1 != ok { ret (fit, e1) }
    let (ner, e2) = cp.zu(a, nn + 2usize)
    if e2 != ok { ret (fit, e2) }
    let (nban, e3) = cp.zu(a, nn + 2usize)
    if e3 != ok { ret (fit, e3) }
    let (lava, e4) = cp.zu(a, nn + 2usize)
    if e4 != ok { ret (fit, e4) }
    let (jlack, e5) = cp.zu(a, pp + 2usize)
    if e5 != ok { ret (fit, e5) }
    var j = 1usize
    var j0 = 0usize
    var j1 = 0usize
    var jma = 0usize
    var jtel = 0usize
    var jtelz = 0usize
    let nhalf = (nn + 1usize) / 2usize
    var has_na = false
    var l = 1usize
    while l <= nn {
        var n_miss = 0usize
        j = 1usize
        while j <= pp {
            if x[(l - 1usize) + (j - 1usize) * nn] > 1i64 { n_miss += 1usize }
            j += 1usize
        }
        if n_miss == pp {
            fit.jerr = 1usize
            ret (fit, ok)
        }
        if n_miss != 0usize {
            has_na = true
            break
        }
        l += 1usize
    }
    if has_na {
        var lack = 0usize
        j = 1usize
        while j <= pp {
            j0 = 0usize
            j1 = 0usize
            l = 1usize
            while l <= nn {
                let v = x[(l - 1usize) + (j - 1usize) * nn]
                if v == 0i64 { j0 += 1usize } else {
                    if v == 1i64 { j1 += 1usize }
                }
                l += 1usize
            }
            jlack[j] = nn - j0 - j1
            if jlack[j] != 0usize { lack += 1usize }
            if jlack[j] >= nhalf {
                fit.jerr = 2usize
                ret (fit, ok)
            }
            if j0 == 0usize || j1 == 0usize {
                fit.jerr = 3usize
                ret (fit, ok)
            }
            j += 1usize
        }
        if lack == pp {
            fit.jerr = 4usize
            ret (fit, ok)
        }
        j = 1usize
        while j <= pp {
            if jlack[j] != 0usize {
                var lama = 0i64 - 1i64
                var syn = true
                var ja = 1usize
                while ja <= pp {
                    if jlack[ja] == 0usize {
                        var ca = 0i64
                        var cb = 0i64
                        var cc = 0i64
                        var cd = 0i64
                        var k = 1usize
                        while k <= nn {
                            let xj = x[(k - 1usize) + (j - 1usize) * nn]
                            let xa = x[(k - 1usize) + (ja - 1usize) * nn]
                            if xj != 1i64 {
                                if xa == 0i64 { ca += 1i64 } else {
                                    if xa == 1i64 { cb += 1i64 }
                                }
                            } else {
                                if xa == 0i64 { cc += 1i64 } else {
                                    if xa == 1i64 { cd += 1i64 }
                                }
                            }
                            k += 1usize
                        }
                        let kal = ca * cd - cb * cc
                        let kalf = iabs(kal)
                        if kalf >= lama {
                            lama = kalf
                            jma = ja
                            if kal < 0i64 { syn = false }
                        }
                    }
                    ja += 1usize
                }
                var k = 1usize
                while k <= nn {
                    if x[(k - 1usize) + (j - 1usize) * nn] > 1i64 {
                        if syn {
                            x[(k - 1usize) + (j - 1usize) * nn] = x[(k - 1usize) + (jma - 1usize) * nn]
                        } else {
                            if x[(k - 1usize) + (jma - 1usize) * nn] == 1i64 { x[(k - 1usize) + (j - 1usize) * nn] = 0i64 }
                            if x[(k - 1usize) + (jma - 1usize) * nn] == 0i64 { x[(k - 1usize) + (j - 1usize) * nn] = 1i64 }
                        }
                    }
                    k += 1usize
                }
            }
            j += 1usize
        }
    }
    var k = 1usize
    while k <= nn {
        kwan[k] = 0i64
        ner[k] = k
        lava[k] = 0usize
        k += 1usize
    }
    var npass = 1usize
    kwan[1usize] = i64(nn)
    var nclu = 1usize
    var ka = 1usize
    while true {
        let kb = ka + usize(kwan[ka]) - 1usize
        var lama = 0i64 - 1i64
        var jnat = pp
        j = 1usize
        while j <= pp {
            var proceed = false
            if nclu == 1usize {
                proceed = true
            } else {
                j0 = 0usize
                j1 = 0usize
                k = ka
                while k <= kb {
                    let n_k = ner[k]
                    let v = x[(n_k - 1usize) + (j - 1usize) * nn]
                    if v == 0i64 { j0 += 1usize } else {
                        if v == 1i64 { j1 += 1usize }
                    }
                    k += 1usize
                }
                if j1 != 0usize && j0 != 0usize { proceed = true }
            }
            if proceed {
                jnat -= 1usize
                var ca = 0i64
                var cb = 0i64
                var cc = 0i64
                var cd = 0i64
                var lams = 0i64
                var jb = 1usize
                while jb <= pp {
                    if jb != j {
                        ca = 0i64
                        cb = 0i64
                        cc = 0i64
                        cd = 0i64
                        k = ka
                        while k <= kb {
                            let n_k = ner[k]
                            let xj = x[(n_k - 1usize) + (j - 1usize) * nn]
                            let xb = x[(n_k - 1usize) + (jb - 1usize) * nn]
                            if xj == 0i64 {
                                if xb == 0i64 { ca += 1i64 } else {
                                    if xb == 1i64 { cb += 1i64 }
                                }
                            } else {
                                if xb == 0i64 { cc += 1i64 } else {
                                    if xb == 1i64 { cd += 1i64 }
                                }
                            }
                            k += 1usize
                        }
                        lams += iabs(ca * cd - cb * cc)
                    }
                    jb += 1usize
                }
                if lama < lams {
                    lama = lams
                    jtel = usize(cc + cd)
                    jtelz = usize(ca + cb)
                    jma = j
                }
            }
            j += 1usize
        }
        if jnat < pp {
            var nzf = 0i64
            var jtel2 = 0usize
            let nel = ner[ka]
            if x[(nel - 1usize) + (jma - 1usize) * nn] == 1i64 {
                nzf = 0i64
                jtel2 = jtel
            } else {
                nzf = 1i64
                jtel2 = jtelz
            }
            let jres = kb - ka + 1usize - jtel2
            let km = ka + jtel2
            k = ka
            var n_b = 0usize
            while true {
                let n_k = ner[k]
                if x[(n_k - 1usize) + (jma - 1usize) * nn] == nzf {
                    var c = 0usize
                    var b = k
                    while b <= kb {
                        n_b = ner[b]
                        if x[(n_b - 1usize) + (jma - 1usize) * nn] != nzf {
                            c = b - 1usize
                            break
                        }
                        b += 1usize
                    }
                    var aa = k
                    while aa <= c {
                        let d = c + k - aa
                        ner[d + 1usize] = ner[d]
                        aa += 1usize
                    }
                    ner[k] = n_b
                } else {
                    k += 1usize
                }
                if !(k < km) { break }
            }
            nclu += 1usize
            nban[km] = npass
            kwan[ka] = i64(jtel2)
            kwan[km] = i64(jres)
            lava[km] = jma
            ka += usize(kwan[ka])
        } else {
            kwan[ka] = 0i64 - kwan[ka]
        }
        var to500 = false
        if kb == nn {
            to500 = true
        } else {
            while true {
                ka += usize(iabs(kwan[ka]))
                if ka > nn {
                    to500 = true
                    break
                }
                if kwan[ka] >= 2i64 { break }
            }
        }
        if to500 {
            npass += 1usize
            var found = false
            var ka2 = 1usize
            while ka2 <= nn {
                if kwan[ka2] >= 2i64 {
                    found = true
                    ka = ka2
                    break
                }
                ka2 += 1usize
            }
            if !found { break }
        }
    }
    let (order, e6) = cp.zu(a, nn)
    if e6 != ok { ret (fit, e6) }
    let (variable, e7) = cp.zu(a, nn - 1usize)
    if e7 != ok { ret (fit, e7) }
    let (step, e8) = cp.zu(a, nn - 1usize)
    if e8 != ok { ret (fit, e8) }
    k = 0usize
    while k < nn {
        order[k] = ner[k + 1usize]
        if k >= 1usize {
            variable[k - 1usize] = lava[k + 1usize]
            step[k - 1usize] = nban[k + 1usize]
        }
        k += 1usize
    }
    fit.order = order
    fit.variable = variable
    fit.step = step
    ret (fit, ok)
}

// agnes' par.method of length np (0 when missing) as the four Lance-Williams parameters (R's agnes() prologue); false for a length R refuses
fn par_method(method: usize, par: []const f64, np: usize, out: []f64) -> bool {
    out[0usize] = 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64
    out[3usize] = 0.0f64
    if method == 6usize {
        if np == 1usize {
            out[0usize] = par[0usize]
            out[1usize] = par[0usize]
            out[2usize] = 1.0f64 - 2.0f64 * par[0usize]
        } else {
            if np == 3usize || np == 4usize {
                var i = 0usize
                while i < np {
                    out[i] = par[i]
                    i += 1usize
                }
            } else {
                ret false
            }
        }
    }
    if method == 7usize {
        if np == 0usize {
            out[0usize] = 1.1f64
            out[1usize] = 1.1f64
            out[2usize] = 0.0f64 - 0.1f64
        } else {
            if np == 1usize {
                out[0usize] = 1.0f64 - par[0usize]
                out[1usize] = 1.0f64 - par[0usize]
                out[2usize] = par[0usize]
            } else {
                if np == 3usize || np == 4usize {
                    var i = 0usize
                    while i < np {
                        out[i] = par[i]
                        i += 1usize
                    }
                } else {
                    ret false
                }
            }
        }
    }
    ret true
}
