// R seriation, the criteria that score a permutation of a dissimilarity matrix or a data matrix: path length, lazy
// path length, least squares, inertia, anti-Robinson events and deviations, the gradient measures, banded
// anti-Robinson form, relative generalised anti-Robinson events, the measure of effectiveness and the Moore and von
// Neumann stress. Dissimilarities are a full symmetric n by n row-major matrix d; an order is a permutation of 0..n-1.
//
// Not here: the seriation methods themselves (TSP, GW, OLO, ARSA and the rest), the QAP-based 2SUM and the
// rank-correlation criteria.

use e.algo.stat.hclust as hc
use e.math
use e.mem

// the sum of the dissimilarities of consecutive objects (an open path)
fn path_length(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        s += d[o[i] * n + o[i + 1usize]]
        i += 1usize
    }
    ret s
}

// sum (n - i) d(o[i], o[i + 1]) over the open path, i from 1
fn lazy_path_length(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        s += f64(n - i) * d[o[i - 1usize] * n + o[i]]
        i += 1usize
    }
    ret s
}

// 2 sum_{j < i} (d(o[i], o[j]) - |i - j|)^2
fn least_squares(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            let x = d[o[i] * n + o[j]] - f64(i - j)
            s += x * x
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * s
}

// 2 sum_{j < i} d(o[i], o[j]) |i - j|^2
fn inertia(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            let x = f64(i - j)
            s += d[o[i] * n + o[j]] * x * x
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * s
}

// anti-Robinson events (which = 1, a count) or their summed absolute deviations (which = 2)
fn anti_robinson(d: []const f64, n: usize, o: []const usize, which: usize) -> f64 {
    var s = 0.0f64
    var i = 2usize
    while i < n {
        var k = 1usize
        while k < i {
            let dik = d[o[i] * n + o[k]]
            var j = 0usize
            while j < k {
                let dij = d[o[i] * n + o[j]]
                if dij < dik {
                    if which == 1usize { s += 1.0f64 } else { s += math.abs[f64](dij - dik) }
                }
                j += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i + 2usize < n {
        var j = i + 1usize
        while j + 1usize < n {
            let dij = d[o[i] * n + o[j]]
            var k = j + 1usize
            while k < n {
                let dik = d[o[i] * n + o[k]]
                if dij > dik {
                    if which == 1usize { s += 1.0f64 } else { s += math.abs[f64](dij - dik) }
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// the gradient measure: raw (which = 1, signs) or weighted (which = 2, differences)
fn gradient(d: []const f64, n: usize, o: []const usize, which: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 2usize < n {
        var k = i + 1usize
        while k + 1usize < n {
            let dik = d[o[i] * n + o[k]]
            var j = k + 1usize
            while j < n {
                let dij = d[o[i] * n + o[j]]
                let dkj = d[o[k] * n + o[j]]
                let a1 = dij - dik
                let a2 = dij - dkj
                if which > 1usize {
                    s += a1
                    s += a2
                } else {
                    if a1 > 0.0f64 { s += 1.0f64 } else if a1 < 0.0f64 { s -= 1.0f64 }
                    if a2 > 0.0f64 { s += 1.0f64 } else if a2 < 0.0f64 { s -= 1.0f64 }
                }
                j += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    ret s
}

// banded anti-Robinson form: sum over i < j <= i + b of (b + 1 - (j - i)) d
fn bar(d: []const f64, n: usize, o: []const usize, b: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n && j <= i + b {
            s += f64(b + 1usize - (j - i)) * d[o[i] * n + o[j]]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// relative (or, when `relative` is false, the count of) generalised anti-Robinson events within a window of w
fn rgar(d: []const f64, n: usize, o: []const usize, w: usize, relative: bool) -> f64 {
    var ar = 0usize
    var total = 0usize
    var i = 3i64
    let ni = i64(n)
    let wi = i64(w)
    while i <= ni {
        var k = i - wi + 1i64
        if k < 2i64 { k = 2i64 }
        while k < i {
            let dik = d[o[usize(i - 1i64)] * n + o[usize(k - 1i64)]]
            var j = i - wi
            if j < 1i64 { j = 1i64 }
            while j < k {
                let dij = d[o[usize(i - 1i64)] * n + o[usize(j - 1i64)]]
                total += 1usize
                if dij < dik { ar += 1usize }
                j += 1i64
            }
            k += 1i64
        }
        i += 1i64
    }
    var ii = 1usize
    while ii + 2usize <= n {
        var jmax = ii + w - 1usize
        if jmax > n - 1usize { jmax = n - 1usize }
        var j = ii + 1usize
        while j <= jmax {
            let dij = d[o[ii - 1usize] * n + o[j - 1usize]]
            var kmax = ii + w
            if kmax > n { kmax = n }
            var k = j + 1usize
            while k <= kmax {
                let dik = d[o[ii - 1usize] * n + o[k - 1usize]]
                total += 1usize
                if dij > dik { ar += 1usize }
                k += 1usize
            }
            j += 1usize
        }
        ii += 1usize
    }
    if relative { ret f64(ar) / f64(total) }
    ret f64(ar)
}

// the measure of effectiveness of the nr by nc nonnegative matrix x (row-major) under the row and column orders
fn measure_of_effectiveness(x: []const f64, nr: usize, nc: usize, ro: []const usize, co: []const usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < nr {
        var j = 0usize
        while j < nc {
            let ii = ro[i]
            let jj = co[j]
            var s = 0.0f64
            if i > 0usize { s += x[ro[i - 1usize] * nc + jj] }
            if i + 1usize < nr { s += x[ro[i + 1usize] * nc + jj] }
            if j > 0usize { s += x[ii * nc + co[j - 1usize]] }
            if j + 1usize < nc { s += x[ii * nc + co[j + 1usize]] }
            m += x[ii * nc + jj] * s
            j += 1usize
        }
        i += 1usize
    }
    ret 0.5f64 * m
}

fn sq(v: f64) -> f64 { ret v * v }

// the Moore (neumann = false) or von Neumann stress: twice the sum of squared differences between each cell and its neighbours, each pair counted once
fn stress(x: []const f64, nc0: usize, ro: []const usize, co: []const usize, neumann: bool) -> f64 {
    let nr = ro.len
    let nc = co.len
    var z = 0.0f64
    var l = ro[0usize]
    var i = 0usize
    while i + 1usize < nr {
        let ll = ro[i + 1usize]
        var k = co[0usize]
        var j = 0usize
        while j + 1usize < nc {
            let kk = co[j + 1usize]
            let v = x[l * nc0 + k]
            z += sq(v - x[ll * nc0 + k])
            if !neumann {
                z += sq(v - x[ll * nc0 + kk])
                z += sq(x[ll * nc0 + k] - x[l * nc0 + kk])
            }
            z += sq(v - x[l * nc0 + kk])
            k = kk
            j += 1usize
        }
        z += sq(x[l * nc0 + k] - x[ll * nc0 + k])
        l = ll
        i += 1usize
    }
    var k = co[0usize]
    var j = 0usize
    while j + 1usize < nc {
        let kk = co[j + 1usize]
        z += sq(x[l * nc0 + k] - x[l * nc0 + kk])
        k = kk
        j += 1usize
    }
    ret 2.0f64 * z
}

// seriate(d, method = "GW"): gclus::reorder.hclust of the complete-linkage tree (seriation's default linkage) (Gruvaeus and Wainer): the end points of every subtree are chosen to be closest to
// the neighbouring subtree and the merges flipped to match, the order read off from the flipped tree; d is the n by n full dissimilarity matrix, out receives the 0-based order
fn gw_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err { ret gw_order_m(a, d, n, 3usize, out) }

// the same for the hclust linkage method code given (1 ward.D, 2 single, 3 complete, 4 average, 8 ward.D2)
fn gw_order_m(a: *mem.Arena, d: []const f64, n: usize, method: usize, out: []usize) -> err {
    let (tree, te) = hc.hclust(a, d, n, method)
    if te != ok { ret te }
    let nm = n - 1usize
    let (ml, e1) = mem.alloc[i32](a, nm)
    let (mr, e2) = mem.alloc[i32](a, nm)
    let (ep, e3) = mem.alloc[usize](a, nm * 2usize)
    let (dir, e4) = mem.alloc[i32](a, nm * 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < nm {
        ml[i] = tree.merge_a[i]
        mr[i] = tree.merge_b[i]
        dir[i * 2usize] = 1i32
        dir[i * 2usize + 1usize] = 1i32
        i += 1usize
    }
    // endpoints (0-based leaves) and flip directions bottom-up
    i = 0usize
    while i < nm {
        let j = ml[i]
        let k = mr[i]
        if j < 0i32 && k < 0i32 {
            ep[i * 2usize] = usize(0i32 - j) - 1usize
            ep[i * 2usize + 1usize] = usize(0i32 - k) - 1usize
        } else if j < 0i32 {
            let jl = usize(0i32 - j) - 1usize
            ep[i * 2usize] = jl
            let e1v = ep[(usize(k) - 1usize) * 2usize]
            let e2v = ep[(usize(k) - 1usize) * 2usize + 1usize]
            if d[jl * n + e1v] < d[jl * n + e2v] {
                ep[i * 2usize + 1usize] = e2v
            } else {
                ep[i * 2usize + 1usize] = e1v
                dir[i * 2usize + 1usize] = 0i32 - 1i32
            }
        } else if k < 0i32 {
            let kl = usize(0i32 - k) - 1usize
            ep[i * 2usize + 1usize] = kl
            let e1v = ep[(usize(j) - 1usize) * 2usize]
            let e2v = ep[(usize(j) - 1usize) * 2usize + 1usize]
            if d[kl * n + e1v] < d[kl * n + e2v] {
                ep[i * 2usize] = e2v
                dir[i * 2usize] = 0i32 - 1i32
            } else {
                ep[i * 2usize] = e1v
            }
        } else {
            let ek1 = ep[(usize(k) - 1usize) * 2usize]
            let ek2 = ep[(usize(k) - 1usize) * 2usize + 1usize]
            let ej1 = ep[(usize(j) - 1usize) * 2usize]
            let ej2 = ep[(usize(j) - 1usize) * 2usize + 1usize]
            let d11 = d[ej1 * n + ek1]
            let d12 = d[ej1 * n + ek2]
            let d21 = d[ej2 * n + ek1]
            let d22 = d[ej2 * n + ek2]
            var dmin = d11
            if d12 < dmin { dmin = d12 }
            if d21 < dmin { dmin = d21 }
            if d22 < dmin { dmin = d22 }
            if dmin == d21 {
                ep[i * 2usize] = ej1
                ep[i * 2usize + 1usize] = ek2
            } else if dmin == d11 {
                ep[i * 2usize] = ej2
                ep[i * 2usize + 1usize] = ek2
                dir[i * 2usize] = 0i32 - 1i32
            } else if dmin == d12 {
                ep[i * 2usize] = ej2
                ep[i * 2usize + 1usize] = ek1
                dir[i * 2usize] = 0i32 - 1i32
                dir[i * 2usize + 1usize] = 0i32 - 1i32
            } else {
                ep[i * 2usize] = ej1
                ep[i * 2usize + 1usize] = ek1
                dir[i * 2usize + 1usize] = 0i32 - 1i32
            }
        }
        i += 1usize
    }
    // propagate the flips top-down
    var ii = nm
    while ii > 1usize {
        ii -= 1usize
        let row = ii
        if dir[row * 2usize] == 0i32 - 1i32 {
            let m = ml[row]
            if m > 0i32 {
                let mi = usize(m) - 1usize
                let m1 = ml[mi]
                ml[mi] = mr[mi]
                mr[mi] = m1
                if dir[mi * 2usize] == dir[mi * 2usize + 1usize] {
                    dir[mi * 2usize] = 0i32 - dir[mi * 2usize]
                    dir[mi * 2usize + 1usize] = 0i32 - dir[mi * 2usize + 1usize]
                }
            }
        }
        if dir[row * 2usize + 1usize] == 0i32 - 1i32 {
            let m = mr[row]
            if m > 0i32 {
                let mi = usize(m) - 1usize
                let m1 = ml[mi]
                ml[mi] = mr[mi]
                mr[mi] = m1
                if dir[mi * 2usize] == dir[mi * 2usize + 1usize] {
                    dir[mi * 2usize] = 0i32 - dir[mi * 2usize]
                    dir[mi * 2usize + 1usize] = 0i32 - dir[mi * 2usize + 1usize]
                }
            }
        }
    }
    // the leaf order of the flipped tree: every merge's leaves are its left subtree's then its right subtree's
    let (buf, e5) = mem.alloc[usize](a, n * nm)
    let (st, e6) = mem.alloc[usize](a, nm)
    let (ln, e7) = mem.alloc[usize](a, nm)
    if e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var used = 0usize
    i = 0usize
    while i < nm {
        st[i] = used
        let j = ml[i]
        let k = mr[i]
        if j < 0i32 {
            buf[used] = usize(0i32 - j) - 1usize
            used += 1usize
        } else {
            let sj = st[usize(j) - 1usize]
            var q = 0usize
            while q < ln[usize(j) - 1usize] {
                buf[used] = buf[sj + q]
                used += 1usize
                q += 1usize
            }
        }
        if k < 0i32 {
            buf[used] = usize(0i32 - k) - 1usize
            used += 1usize
        } else {
            let sk = st[usize(k) - 1usize]
            var q = 0usize
            while q < ln[usize(k) - 1usize] {
                buf[used] = buf[sk + q]
                used += 1usize
                q += 1usize
            }
        }
        ln[i] = used - st[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = buf[st[nm - 1usize] + i]
        i += 1usize
    }
    ret ok
}

// 2SUM: sum over all i, j of (i - j)^2 / (1 + d(o[i], o[j]))
fn two_sum(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dd = f64(i) - f64(j)
            s += dd * dd / (1.0f64 + d[o[i] * n + o[j]])
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// Rho: the absolute Spearman rank correlation (ties averaged) between the dissimilarities of the permuted objects and their distances |i - j| in the order, over the pairs in dist order
fn rho(a: *mem.Arena, d: []const f64, n: usize, o: []const usize) -> f64 {
    let m = n * (n - 1usize) / 2usize
    let (x, e1) = mem.alloc[f64](a, m)
    let (y, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    var j = 0usize
    while j + 1usize < n {
        var i = j + 1usize
        while i < n {
            x[k] = d[o[i] * n + o[j]]
            y[k] = f64(i - j)
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    ret math.abs[f64](hc.spearman_vec(a, x, y))
}

// MDS_stress(d, order): the one-dimensional unfolding of the order (the package uniscale: t_i = (r_i - sum r / n) / n with r_i = sum_j delta_ij sign(rank_i - rank_j), delta the dissimilarities
// scaled to unit mean square; the ranks themselves when t does not keep the order), then sqrt(sum (d - d_emb)^2 / sum d_emb^2) over the pairs with both distance sets scaled to unit mean square
fn mds_stress(a: *mem.Arena, d: []const f64, n: usize, o: []const usize) -> f64 {
    let m = n * (n - 1usize) / 2usize
    let (rank, e1) = mem.alloc[f64](a, n)
    let (t, e2) = mem.alloc[f64](a, n)
    let (r, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < n {
        rank[o[k]] = f64(k + 1usize)
        k += 1usize
    }
    // the squared sum over the pair vector (each pair once) for the scaling
    var ss = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            ss += d[i * n + j] * d[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    let scale = math.sqrt[f64](f64(m)) / math.sqrt[f64](ss)
    var tot = 0.0f64
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            if j != i {
                var sg = 0.0f64
                if rank[i] > rank[j] { sg = 1.0f64 } else if rank[i] < rank[j] { sg = 0.0f64 - 1.0f64 }
                s += d[i * n + j] * scale * sg
            }
            j += 1usize
        }
        r[i] = s
        tot += s
        i += 1usize
    }
    i = 0usize
    while i < n {
        t[i] = r[i] / f64(n) - tot / (f64(n) * f64(n))
        i += 1usize
    }
    // does t keep the order of the ranks
    var same = true
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            if (rank[i] < rank[j]) != (t[i] < t[j]) { same = false }
            j += 1usize
        }
        i += 1usize
    }
    if !same {
        i = 0usize
        while i < n {
            t[i] = rank[i]
            i += 1usize
        }
    }
    var se = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            let de = math.abs[f64](t[i] - t[j])
            se += de * de
            j += 1usize
        }
        i += 1usize
    }
    let escale = math.sqrt[f64](f64(m)) / math.sqrt[f64](se)
    var num = 0.0f64
    var den = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            let de = math.abs[f64](t[i] - t[j]) * escale
            let dn = d[i * n + j] * scale
            num += (dn - de) * (dn - de)
            den += de * de
            j += 1usize
        }
        i += 1usize
    }
    ret math.sqrt[f64](num / den)
}

// seriate(d, "VAT"): start from the row of the first largest entry in column-major order and repeatedly append the unvisited object with the smallest dissimilarity to any visited one (the first such column on ties); out receives the 0-based order
fn vat_order(d: []const f64, n: usize, out: []usize) {
    var mx = d[0usize]
    var i = 0usize
    while i < n * n {
        if d[i] > mx { mx = d[i] }
        i += 1usize
    }
    // the first occurrence of the maximum scanning columns first: the smallest column, then the smallest row in it
    var start = 0usize
    var found = false
    var c = 0usize
    while c < n && !found {
        var r = 0usize
        while r < n && !found {
            if d[r * n + c] == mx {
                start = r
                found = true
            }
            r += 1usize
        }
        c += 1usize
    }
    var seen = 0usize
    out[0usize] = start
    seen = 1usize
    var done = 0usize
    while done + 1usize < n {
        var best = 1.0e300f64
        var pick = 0usize
        var col = 0usize
        while col < n {
            var vis = false
            var q = 0usize
            while q < seen {
                if out[q] == col { vis = true }
                q += 1usize
            }
            if !vis {
                var cm = 1.0e300f64
                q = 0usize
                while q < seen {
                    let v = d[out[q] * n + col]
                    if v < cm { cm = v }
                    q += 1usize
                }
                if cm < best {
                    best = cm
                    pick = col
                }
            }
            col += 1usize
        }
        out[seen] = pick
        seen += 1usize
        done += 1usize
    }
}

type OloCtx = struct { n: usize, d: []const f64, mm: []f64, inn: []bool, ca: []usize, cb: []usize, out: []usize, tmp: []usize }

fn olo_best(c: *const OloCtx, v: usize, u: usize, w: usize, bm: *usize, bk: *usize) {
    let n = c.n
    let na = c.ca[v]
    let nb2 = c.cb[v]
    var best = 1.0e300f64
    var m = 0usize
    while m < n {
        if c.inn[na * n + m] {
            let c1 = c.mm[na * n * n + u * n + m]
            if c1 < 1.0e299f64 {
                var k = 0usize
                while k < n {
                    if c.inn[nb2 * n + k] {
                        let c2 = c.mm[nb2 * n * n + k * n + w]
                        if c2 < 1.0e299f64 {
                            let cost = c1 + c.d[m * n + k] + c2
                            if cost < best {
                                best = cost
                                *bm = m
                                *bk = k
                            }
                        }
                    }
                    k += 1usize
                }
            }
        }
        m += 1usize
    }
}

// the a-first ordering of node v with u (in the first child) leftmost and w (in the second) rightmost, written to out from pos; returns the next position
fn olo_emit(c: *OloCtx, v: usize, u: usize, w: usize, pos: usize, dest: []usize) -> usize {
    let n = c.n
    if v < n {
        dest[pos] = u
        ret pos + 1usize
    }
    if c.inn[c.cb[v] * n + u] {
        // u lies in the second child: build the mirror ordering (w first) and reverse it in place
        let endp = olo_emit(c, v, w, u, pos, dest)
        var lo = pos
        var hi = endp - 1usize
        while lo < hi {
            let t = dest[lo]
            dest[lo] = dest[hi]
            dest[hi] = t
            lo += 1usize
            hi -= 1usize
        }
        ret endp
    }
    var m = 0usize
    var k = 0usize
    olo_best(c, v, u, w, &m, &k)
    let p1 = olo_emit(c, c.ca[v], u, m, pos, dest)
    ret olo_emit(c, c.cb[v], k, w, p1, dest)
}

// the optimal leaf ordering (Bar-Joseph, Gifford and Jaakkola) of the hclust tree of the given linkage code, minimising the summed dissimilarity of adjacent leaves; out receives the 0-based order
fn olo_order(a: *mem.Arena, d: []const f64, n: usize, method: usize, out: []usize) -> err {
    let (tree, te) = hc.hclust(a, d, n, method)
    if te != ok { ret te }
    let nm = n - 1usize
    let nodes = n + nm
    let (mm, e1) = mem.alloc[f64](a, nodes * n * n)
    let (inn, e2) = mem.alloc[bool](a, nodes * n)
    let (ca, e3) = mem.alloc[usize](a, nodes)
    let (cb, e4) = mem.alloc[usize](a, nodes)
    let (tmp, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < nodes * n * n {
        mm[i] = 1.0e300f64
        i += 1usize
    }
    i = 0usize
    while i < nodes * n {
        inn[i] = false
        i += 1usize
    }
    i = 0usize
    while i < n {
        inn[i * n + i] = true
        mm[i * n * n + i * n + i] = 0.0f64
        i += 1usize
    }
    var ctx = OloCtx{ n: n, d: d, mm: mm, inn: inn, ca: ca, cb: cb, out: out, tmp: tmp }
    var s = 0usize
    while s < nm {
        var na = 0usize
        var nb2 = 0usize
        if tree.merge_a[s] < 0i32 { na = usize(0i32 - tree.merge_a[s]) - 1usize } else { na = n + usize(tree.merge_a[s]) - 1usize }
        if tree.merge_b[s] < 0i32 { nb2 = usize(0i32 - tree.merge_b[s]) - 1usize } else { nb2 = n + usize(tree.merge_b[s]) - 1usize }
        let v = n + s
        ca[v] = na
        cb[v] = nb2
        var u = 0usize
        while u < n {
            if inn[na * n + u] || inn[nb2 * n + u] { inn[v * n + u] = true }
            u += 1usize
        }
        u = 0usize
        while u < n {
            if inn[na * n + u] {
                var w = 0usize
                while w < n {
                    if inn[nb2 * n + w] {
                        var bm = 0usize
                        var bk = 0usize
                        olo_best(&ctx, v, u, w, &bm, &bk)
                        let cost = mm[na * n * n + u * n + bm] + d[bm * n + bk] + mm[nb2 * n * n + bk * n + w]
                        mm[v * n * n + u * n + w] = cost
                        mm[v * n * n + w * n + u] = cost
                    }
                    w += 1usize
                }
            }
            u += 1usize
        }
        s += 1usize
    }
    let root = n + nm - 1usize
    var bu = 0usize
    var bw = 0usize
    var best = 1.0e300f64
    var u = 0usize
    while u < n {
        if inn[ca[root] * n + u] {
            var w = 0usize
            while w < n {
                if inn[cb[root] * n + w] {
                    if mm[root * n * n + u * n + w] < best {
                        best = mm[root * n * n + u * n + w]
                        bu = u
                        bw = w
                    }
                }
                w += 1usize
            }
        }
        u += 1usize
    }
    let end = olo_emit(&ctx, root, bu, bw, 0usize, out)
    if end != n { ret mem.Full }
    ret ok
}
