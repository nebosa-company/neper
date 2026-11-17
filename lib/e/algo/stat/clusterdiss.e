// R cluster (Maechler et al., 2.1.8.2): the dissimilarity half of the package, ported from the package's C sources.
//
//   dysta       euclidean or manhattan dissimilarities of a data matrix with missing values (dysta.c)
//   daisy       daisy(): euclidean, manhattan and Gower for mixed variable types, with weights and stand (daisy.R and daisy.c)
//   sildist     silhouette widths and neighbours of a clustering (sildist.c) and the silhouette.default / sortSilhouette wrapper
//   ind_2       index of d(l, j) in the package's half dissimilarity vector
//
// Two layouts of a dissimilarity vector occur. The C layout ("cdv") has n(n-1)/2 + 1 entries, entry 0 is 0, then the pairs
// (l, k) for l = 2..n and k = 1..l-1; pam, clara, agnes and diana work on it. R's own dist layout has n(n-1)/2 entries, the
// pairs (i, j), i < j, ordered by i then j (so a column-wise lower triangle); fanny and the silhouette work on it. A data matrix is
// n by p row-major and NaN is a missing value.
//
// Not here: the data frame type detection of daisy (the caller names the type of each column), the print and summary methods.

use e.math
use e.mem

// the 1-based index of d(l, j) in a cdv
fn ind_2(l: usize, j: usize) -> usize {
    if l == j { ret 0usize }
    var m = l
    var q = j
    if j > l {
        m = j
        q = l
    }
    ret (m - 2usize) * (m - 1usize) / 2usize + q
}

// the index of d(i, j), 0-based i < j, in a dist vector of n objects
fn dist_index(n: usize, i: usize, j: usize) -> usize {
    ret i * n + j - (i + 1usize) * (i + 2usize) / 2usize
}

// cdv of the n objects from an R dist vector
fn cdv_from_dist(a: *mem.Arena, d: []const f64, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e != ok { ret (v, e) }
    v[0usize] = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            v[ind_2(j + 1usize, i + 1usize)] = d[dist_index(n, i, j)]
            j += 1usize
        }
        i += 1usize
    }
    ret (v, ok)
}

// the dist vector from a cdv
fn dist_from_cdv(a: *mem.Arena, v: []const f64, n: usize) -> ([]f64, err) {
    let (d, e) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
    if e != ok { ret (d, e) }
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            d[dist_index(n, i, j)] = v[ind_2(j + 1usize, i + 1usize)]
            j += 1usize
        }
        i += 1usize
    }
    ret (d, ok)
}

// R's mean(): the average, then the average of the residuals added back
fn mean_of(v: []const f64, cnt: usize) -> f64 {
    if cnt == 0usize { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i]
        i += 1usize
    }
    let m = s / f64(cnt)
    var t = 0.0f64
    i = 0usize
    while i < cnt {
        t += v[i] - m
        i += 1usize
    }
    ret m + t / f64(cnt)
}

// x <- scale(x, scale = apply(x, 2, meanabsdev)): the columns centred on their means and divided by their mean absolute deviation,
// NaN left missing
fn stand_meanabsdev(a: *mem.Arena, x: []f64, n: usize, p: usize) -> err {
    let (col, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var j = 0usize
    while j < p {
        var cnt = 0usize
        var i = 0usize
        while i < n {
            let v = x[i * p + j]
            if v == v {
                col[cnt] = v
                cnt += 1usize
            }
            i += 1usize
        }
        let m = mean_of(col, cnt)
        i = 0usize
        while i < cnt {
            col[i] = math.abs[f64](col[i] - m)
            i += 1usize
        }
        let mad = mean_of(col, cnt)
        i = 0usize
        while i < n {
            x[i * p + j] = (x[i * p + j] - m) / mad
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// dysta(): dys receives 1 + n(n-1)/2 entries (a cdv). Pairs sharing no observed column get -1 and the result is 1, otherwise 0.
// ndyst 1 is euclidean, anything else manhattan.
fn dysta(x: []const f64, n: usize, p: usize, ndyst: usize, dys: []f64) -> usize {
    var nlk = 0usize
    var jhalt = 0usize
    dys[0usize] = 0.0f64
    let pp = f64(p)
    var l = 2usize
    while l <= n {
        var k = 1usize
        while k < l {
            var clk = 0.0f64
            nlk += 1usize
            var npres = 0usize
            var j = 0usize
            while j < p {
                let u = x[(l - 1usize) * p + j]
                let v = x[(k - 1usize) * p + j]
                if u == u && v == v {
                    npres += 1usize
                    if ndyst == 1usize {
                        clk += (u - v) * (u - v)
                    } else {
                        clk += math.abs[f64](u - v)
                    }
                }
                j += 1usize
            }
            let rpres = f64(npres)
            if npres == 0usize {
                jhalt = 1usize
                dys[nlk] = 0.0f64 - 1.0f64
            } else {
                if ndyst == 1usize {
                    dys[nlk] = math.sqrt[f64](clk * (pp / rpres))
                } else {
                    dys[nlk] = clk * (pp / rpres)
                }
            }
            k += 1usize
        }
        l += 1usize
    }
    ret jhalt
}

// the type codes of daisy, as in the package
const DAISY_A: usize = 1usize
const DAISY_S: usize = 2usize
const DAISY_N: usize = 3usize
const DAISY_O: usize = 4usize
const DAISY_I: usize = 5usize
const DAISY_T: usize = 6usize
// a column that daisy log10-transforms (type$logratio) and then treats as interval scaled
const DAISY_L: usize = 7usize

// the dense rank (as.ordered codes) of a column, NaN kept missing
fn dense_rank_column(a: *mem.Arena, x: []f64, n: usize, p: usize, j: usize) -> err {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var cnt = 0usize
    var i = 0usize
    while i < n {
        let u = x[i * p + j]
        if u == u {
            var at = 0usize
            while at < cnt && v[at] < u { at += 1usize }
            if at == cnt || v[at] != u {
                var m = cnt
                while m > at {
                    v[m] = v[m - 1usize]
                    m -= 1usize
                }
                v[at] = u
                cnt += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        let u = x[i * p + j]
        if u == u {
            var at = 0usize
            while v[at] != u { at += 1usize }
            x[i * p + j] = f64(at + 1usize)
        }
        i += 1usize
    }
    ret ok
}

// daisy(x, metric, stand, type, weights). x is n by p row-major (it is not modified); metric 1 euclidean, 2 manhattan, 3 gower;
// vtype[j] in A S N O I T L (the DAISY_ codes; a factor's codes, as data.matrix gives them, stand in x); weights has p entries
// and is read only for a mixed or gower dissimilarity. out receives n(n-1)/2 entries in R's dist order, NaN where daisy answers NA.
fn daisy(a: *mem.Arena, xin: []const f64, n: usize, p: usize, metric: usize, stand: bool, vtype: []const usize, weights: []const f64, out: []f64) -> err {
    let (x, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret e1 }
    let (typ, e2) = mem.alloc[usize](a, p)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n * p {
        x[i] = xin[i]
        i += 1usize
    }
    var j = 0usize
    var all_i = true
    while j < p {
        typ[j] = vtype[j]
        if vtype[j] == DAISY_T {
            let e = dense_rank_column(a, x, n, p, j)
            if e != ok { ret e }
        }
        if vtype[j] == DAISY_L {
            i = 0usize
            while i < n {
                x[i * p + j] = math.log10[f64](x[i * p + j])
                i += 1usize
            }
            typ[j] = DAISY_I
        }
        if typ[j] != DAISY_I { all_i = false }
        j += 1usize
    }
    var jdat = 1usize
    var ndyst = 0usize
    if all_i && metric != 3usize {
        if stand {
            let (col, e3) = mem.alloc[f64](a, n)
            if e3 != ok { ret e3 }
            j = 0usize
            while j < p {
                var cnt = 0usize
                i = 0usize
                while i < n {
                    let v = x[i * p + j]
                    if v == v {
                        col[cnt] = v
                        cnt += 1usize
                    }
                    i += 1usize
                }
                let m = mean_of(col, cnt)
                i = 0usize
                while i < n {
                    x[i * p + j] = x[i * p + j] - m
                    i += 1usize
                }
                i = 0usize
                cnt = 0usize
                while i < n {
                    let v = x[i * p + j]
                    if v == v {
                        col[cnt] = math.abs[f64](v)
                        cnt += 1usize
                    }
                    i += 1usize
                }
                var sx = mean_of(col, cnt)
                if sx == 0.0f64 { sx = 1.0f64 }
                i = 0usize
                while i < n {
                    x[i * p + j] = x[i * p + j] / sx
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
            var hi = 0.0f64 - lo
            i = 0usize
            while i < n {
                let v = x[i * p + j]
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
                x[i * p + j] = (x[i * p + j] - lo) / sx
                i += 1usize
            }
            j += 1usize
        }
    }
    // missing values become the package's sentinel valmisdat, columns holding one are flagged
    let (jtmd, e4) = mem.alloc[usize](a, p)
    if e4 != ok { ret e4 }
    var mdata = false
    var mx = 0.0f64
    j = 0usize
    while j < p {
        jtmd[j] = 1usize
        i = 0usize
        while i < n {
            let v = x[i * p + j]
            if v == v {
                if math.abs[f64](v) > mx { mx = math.abs[f64](v) }
            } else {
                jtmd[j] = 0usize
                mdata = true
            }
            i += 1usize
        }
        j += 1usize
    }
    let valmd = 1.1f64 * mx
    if mdata {
        i = 0usize
        while i < n * p {
            if x[i] != x[i] { x[i] = valmd }
            i += 1usize
        }
    }
    // the dissimilarities in the C order, then into dist order
    let (cd, e5) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e5 != ok { ret e5 }
    var nlk = 0usize
    var l = 1usize
    while l < n {
        var k = 0usize
        while k < l {
            if jdat == 1usize {
                var ppa = 0.0f64
                var dlk = 0.0f64
                j = 0usize
                while j < p {
                    let u = x[l * p + j]
                    let v = x[k * p + j]
                    if typ[j] >= 3usize {
                        var skip = false
                        if mdata && jtmd[j] == 0usize {
                            if u == valmd || v == valmd { skip = true }
                        }
                        if !skip {
                            ppa += weights[j]
                            if typ[j] == 3usize {
                                if u != v { dlk += weights[j] }
                            } else {
                                dlk += weights[j] * math.abs[f64](u - v)
                            }
                        }
                    } else {
                        if (u == 0.0f64 || u == 1.0f64) && (v == 0.0f64 || v == 1.0f64) {
                            if typ[j] == 2usize || u != 0.0f64 || v != 0.0f64 { ppa += weights[j] }
                            if u != v { dlk += weights[j] }
                        }
                    }
                    j += 1usize
                }
                if ppa == 0.0f64 {
                    cd[nlk] = 0.0f64 - 1.0f64
                } else {
                    cd[nlk] = dlk / ppa
                }
            } else {
                var clk = 0.0f64
                var npres = 0usize
                j = 0usize
                while j < p {
                    let u = x[l * p + j]
                    let v = x[k * p + j]
                    var skip = false
                    if mdata && jtmd[j] == 0usize {
                        if u == valmd || v == valmd { skip = true }
                    }
                    if !skip {
                        npres += 1usize
                        if ndyst == 1usize {
                            clk += (u - v) * (u - v)
                        } else {
                            clk += math.abs[f64](u - v)
                        }
                    }
                    j += 1usize
                }
                let rpres = f64(npres)
                if npres == 0usize {
                    cd[nlk] = 0.0f64 - 1.0f64
                } else {
                    if ndyst == 1usize {
                        cd[nlk] = math.sqrt[f64](clk * (f64(p) / rpres))
                    } else {
                        cd[nlk] = clk * (f64(p) / rpres)
                    }
                }
            }
            nlk += 1usize
            k += 1usize
        }
        l += 1usize
    }
    // pair (k, l), k < l, is the (l-1)(l-2)/2 + k-th C entry
    i = 0usize
    while i + 1usize < n {
        var q = i + 1usize
        while q < n {
            var v = cd[q * (q - 1usize) / 2usize + i]
            if v == 0.0f64 - 1.0f64 { v = 0.0f64 / 0.0f64 }
            out[dist_index(n, i, q)] = v
            q += 1usize
        }
        i += 1usize
    }
    ret ok
}

// silhouette.default(x, dist) for clustering codes cl (any integers); d is an R dist vector (ismat false) or an n by n matrix.
// width and neighbor (in the original codes) are answered per observation; the answer is 1 when R answers NA (one cluster, or as
// many as observations).
fn silhouette_widths(a: *mem.Arena, cl: []const i64, n: usize, d: []const f64, ismat: bool, width: []f64, neighbor: []i64) -> (usize, err) {
    let (codes, e1) = mem.alloc[i64](a, n)
    if e1 != ok { ret (0usize, e1) }
    var k = 0usize
    var i = 0usize
    while i < n {
        var at = 0usize
        while at < k && codes[at] < cl[i] { at += 1usize }
        if at == k || codes[at] != cl[i] {
            var m = k
            while m > at {
                codes[m] = codes[m - 1usize]
                m -= 1usize
            }
            codes[at] = cl[i]
            k += 1usize
        }
        i += 1usize
    }
    if k <= 1usize || k >= n { ret (1usize, ok) }
    let (x, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (0usize, e2) }
    i = 0usize
    while i < n {
        var at = 0usize
        while codes[at] != cl[i] { at += 1usize }
        x[i] = at
        i += 1usize
    }
    let (dic, e3) = mem.alloc[f64](a, n * k)
    if e3 != ok { ret (0usize, e3) }
    let (counts, e4) = mem.alloc[usize](a, k)
    if e4 != ok { ret (0usize, e4) }
    i = 0usize
    while i < n * k {
        dic[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        counts[i] = 0usize
        i += 1usize
    }
    var l = 0usize
    i = 0usize
    while i < n {
        let ci = x[i]
        counts[ci] += 1usize
        if ismat { l = n * i + i + 1usize }
        var j = i + 1usize
        while j < n {
            let cj = x[j]
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
        let ci = x[i]
        var compute = true
        var j = 0usize
        while j < k {
            if j == ci {
                if counts[j] == 1usize {
                    compute = false
                } else {
                    dic[ki + j] = dic[ki + j] / f64(counts[j] - 1usize)
                }
            } else {
                dic[ki + j] = dic[ki + j] / f64(counts[j])
            }
            j += 1usize
        }
        let ai = dic[ki + ci]
        var bi = 0.0f64
        var nb = 0usize
        if ci == 0usize {
            bi = dic[ki + 1usize]
            nb = 1usize
        } else {
            bi = dic[ki]
            nb = 0usize
        }
        j = 1usize
        while j < k {
            if j != ci {
                if bi > dic[ki + j] {
                    bi = dic[ki + j]
                    nb = j
                }
            }
            j += 1usize
        }
        neighbor[i] = codes[nb]
        if compute && bi != ai {
            var mxab = ai
            if bi > mxab { mxab = bi }
            width[i] = (bi - ai) / mxab
        } else {
            width[i] = 0.0f64
        }
        i += 1usize
    }
    ret (0usize, ok)
}

// sortSilhouette: the order(cluster, -sil_width) permutation (stable), 0-based
fn silhouette_order(a: *mem.Arena, cl: []const i64, width: []const f64, n: usize) -> ([]usize, err) {
    let (o, e) = mem.alloc[usize](a, n)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize {
            let p = o[j - 1usize]
            var later = false
            if cl[p] > cl[i] { later = true }
            if cl[p] == cl[i] && width[p] < width[i] { later = true }
            if !later { break }
            o[j] = p
            j -= 1usize
        }
        o[j] = i
        i += 1usize
    }
    ret (o, ok)
}
