// R AlgDesign's optBlock for the D criterion on a within-block model (OptBlock.c, BlockOptimize): the rows of the model matrix X
// (row-major, N by k, intercept removed) are assigned to blocks of the given sizes by exchanging a row of one block with a row of
// another (or with a row outside the design), the determinant of the within-block information T being kept by Givens updates. This
// is also how a balanced incomplete block design is searched for. The R wrapper's formula and factor coding are the caller's.
//
// Not here: wholeBlockData, and the criteria Dpc, Dp, OB and OBS.

use e.algo.rand.r as rng
use e.math
use e.mem

type BRes = struct { dd: f64, diagonality: f64, iter: i64, errcode: i64, block_array: []i64 }

type Blk = struct {
    n: usize,
    k: usize,
    nb: usize,
    maxn: usize,
    nex: usize,
    extra: bool,
    x: []f64,
    tx: []f64,
    bm: []f64,
    tbm: []f64,
    b: []i64,
    t: []f64,
    tip: []f64,
    w: []f64,
    vec: []f64,
    sc: []f64,
    sizes: []const usize,
}

fn imat(r: usize, c: usize, nc: usize) -> usize { ret c + r * nc - (r * (r + 1usize)) / 2usize }

fn fabs_(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn permute_b(g: *rng.Rng, a: []i64, n: usize) {
    var i = 1usize
    while i < n {
        let j = usize(f64(1usize + i) * rng.unif(g))
        let t = a[j]
        a[j] = a[i]
        a[i] = t
        i += 1usize
    }
}

fn rotate_b(vec: []const f64, tvec: []f64, m: []f64, nterms: usize, ncols: usize, weight0: f64) {
    var weight = weight0
    var i = 0usize
    while i < ncols {
        tvec[i] = vec[i]
        i += 1usize
    }
    i = 0usize
    while i < nterms {
        let x = tvec[i]
        if x == 0.0f64 {
            i += 1usize
            continue
        }
        var kidx = imat(i, i, ncols)
        let d = m[kidx]
        let dp = d + weight * x * x
        if fabs_(dp) < 1.0e-50f64 {
            i += 1usize
            continue
        }
        m[kidx] = dp
        let c = d / dp
        let s = weight * x / dp
        var skip = false
        if d == 0.0f64 {
            skip = true
            weight = 0.0f64
        } else {
            weight = weight * c
        }
        kidx += 1usize
        var j = i + 1usize
        while j < ncols {
            let r = m[kidx]
            m[kidx] = s * tvec[j] + c * r
            tvec[j] = tvec[j] - x * r
            j += 1usize
            kidx += 1usize
        }
        if skip { break }
        i += 1usize
    }
}

// the inverse of the unit upper triangular T in place (BacksolveB with INVERSEONLY)
fn backsolve_inverse(m: []f64, nt: usize) {
    var col = nt - 1usize
    while col > 0usize {
        var j = col
        while j > 0usize {
            j -= 1usize
            let l = imat(j, col, nt)
            var kk = imat(j, j + 1usize, nt)
            m[l] = m[l] * (0.0f64 - 1.0f64)
            var i = 1usize
            while i < col - j {
                m[l] = m[l] - m[imat(i + j, col, nt)] * m[kk]
                kk += 1usize
                i += 1usize
            }
        }
        col -= 1usize
    }
    var i = 0usize
    while i < nt {
        m[imat(i, i, nt)] = 1.0f64 / m[imat(i, i, nt)]
        i += 1usize
    }
}

fn form_block_means(f: *Blk) {
    let k = f.k
    var i = 0usize
    while i < f.nb * k {
        f.bm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < f.nb {
        var j = 0usize
        while j < f.sizes[i] {
            let rowno = usize(f.b[i * f.maxn + j])
            var l = 0usize
            while l < k {
                f.bm[i * k + l] += f.x[rowno * k + l]
                l += 1usize
            }
            j += 1usize
        }
        let rn = f64(f.sizes[i])
        var l = 0usize
        while l < k {
            f.bm[i * k + l] = f.bm[i * k + l] / rn
            l += 1usize
        }
        i += 1usize
    }
}

// reduceXtoT: the within-block deviations of all rows rotated into T; the log determinant and singular flag
fn reduce_x_to_t(f: *Blk) -> (f64, bool) {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var i = 0usize
    while i < k {
        f.sc[i] = 0.0f64 - 1.0e16f64
        f.sc[k + i] = 1.0e16f64
        i += 1usize
    }
    i = 0usize
    while i < kk {
        f.t[i] = 0.0f64
        i += 1usize
    }
    let dv = f.vec[0usize..k]
    let tv = f.vec[k..2usize * k]
    i = 0usize
    while i < f.nb {
        var j = 0usize
        while j < f.sizes[i] {
            let rowno = usize(f.b[i * f.maxn + j])
            var l = 0usize
            while l < k {
                dv[l] = f.x[rowno * k + l] - f.bm[i * k + l]
                l += 1usize
            }
            l = 0usize
            while l < k {
                if dv[l] > f.sc[l] { f.sc[l] = dv[l] }
                if dv[l] < f.sc[k + l] { f.sc[k + l] = dv[l] }
                l += 1usize
            }
            rotate_b(dv, tv, f.t, k, k, 1.0f64)
            j += 1usize
        }
        i += 1usize
    }
    var logdet = 0.0f64
    var pt = 0usize
    i = 0usize
    while i < k {
        let r = (f.sc[i] + f.sc[k + i]) / 2.0f64
        let t = f.t[pt]
        if t <= 0.0f64 || t < r * 1.0e-10f64 { ret (0.0f64, true) }
        logdet += math.log[f64](t)
        pt += k - i
        i += 1usize
    }
    ret (logdet, false)
}

// makeTiFromTB: Tip (the scaled transposed inverse of T), and the average variance
fn make_ti_from_t(f: *Blk) -> f64 {
    let k = f.k
    let kk = k * (k + 1usize) / 2usize
    var i = 0usize
    while i < kk {
        f.w[i] = f.t[i]
        i += 1usize
    }
    backsolve_inverse(f.w, k)
    var g = 0usize
    var j = 0usize
    while j < k {
        i = 0usize
        while i <= j {
            f.tip[g] = f.w[imat(i, j, k)]
            g += 1usize
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < k {
        f.w[i] = 0.0f64
        i += 1usize
    }
    var pt = 0usize
    i = 0usize
    while i < k {
        let d = math.sqrt[f64](f.tip[pt + i])
        f.tip[pt + i] = 1.0f64
        var jj = 0usize
        while jj <= i {
            let t = d * f.tip[pt]
            f.tip[pt] = t
            f.w[jj] += t * t
            pt += 1usize
            jj += 1usize
        }
        i += 1usize
    }
    var avar = 0.0f64
    i = 0usize
    while i < k {
        avar += math.log[f64](f.w[i])
        i += 1usize
    }
    ret math.exp[f64](avar / f64(k))
}

fn transform(f: *Blk) {
    let k = f.k
    var i = 0usize
    while i < f.nb * k {
        f.tbm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < f.n * k {
        f.tx[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < f.n {
        var pt = 0usize
        var j = 0usize
        while j < k {
            var l = 0usize
            while l <= j {
                f.tx[i * k + j] += f.x[i * k + l] * f.tip[pt]
                pt += 1usize
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < f.nb {
        var pt = 0usize
        var j = 0usize
        while j < k {
            var l = 0usize
            while l <= j {
                f.tbm[i * k + j] += f.bm[i * k + l] * f.tip[pt]
                pt += 1usize
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
}

// findDeltaBlock: the best exchange of row xcur of curBlock; returns (delta, xnew, newBlock)
fn find_delta_block(f: *Blk, xcur: usize, cur_block: usize) -> (f64, usize, usize) {
    let k = f.k
    var delta = 0.0f64
    var xnew = 0usize
    var new_block = 0usize
    var gi: [3]f64 = zero
    var mi: [3]f64 = zero
    var m1: [3]f64 = zero
    gi[1usize] = 1.0f64
    gi[2usize] = 0.0f64
    let cur_row = usize(f.b[cur_block * f.maxn + xcur])
    let ni = f.sizes[cur_block]
    var i = 0usize
    while i < f.nb {
        if i != cur_block {
            let nj = f.sizes[i]
            gi[0usize] = f64(ni + nj) / f64(ni * nj)
            var g = 0.0f64
            var l = 0usize
            while l < k {
                let dif = f.tbm[i * k + l] - f.tbm[cur_block * k + l]
                g += dif * dif
                l += 1usize
            }
            mi[0usize] = g
            var j = 0usize
            while j < nj {
                let rowno = usize(f.b[i * f.maxn + j])
                g = 0.0f64
                var h = 0.0f64
                l = 0usize
                while l < k {
                    let dif1 = f.tbm[i * k + l] - f.tbm[cur_block * k + l]
                    let dif2 = f.tx[rowno * k + l] - f.tx[cur_row * k + l]
                    g += dif1 * dif2
                    h += dif2 * dif2
                    l += 1usize
                }
                mi[1usize] = g
                mi[2usize] = h
                l = 0usize
                while l < 3usize {
                    m1[l] = gi[l] + mi[l]
                    l += 1usize
                }
                let d = 0.0f64 - (1.0f64 + m1[0usize] * m1[2usize] - m1[1usize] * m1[1usize])
                if (d - delta) > 1.0e-12f64 {
                    delta = d
                    new_block = i
                    xnew = j
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    if f.extra {
        gi[0usize] = f64(ni + 1usize) / f64(ni)
        gi[1usize] = 1.0f64 / f64(ni)
        gi[2usize] = 0.0f64 - f64(ni - 1usize) / f64(ni)
        var g = 0.0f64
        var l = 0usize
        while l < k {
            let dif = f.tx[cur_row * k + l] - f.tbm[cur_block * k + l]
            g += dif * dif
            l += 1usize
        }
        mi[2usize] = g
        var j = 0usize
        while j < f.nex {
            let rowno = usize(f.b[f.nb * f.maxn + j])
            g = 0.0f64
            var h = 0.0f64
            l = 0usize
            while l < k {
                let dif1 = f.tx[cur_row * k + l] - f.tbm[cur_block * k + l]
                let dif2 = f.tx[rowno * k + l] - f.tbm[cur_block * k + l]
                g += dif1 * dif2
                h += dif2 * dif2
                l += 1usize
            }
            mi[0usize] = h
            mi[1usize] = g
            l = 0usize
            while l < 3usize {
                m1[l] = gi[l] + mi[l]
                l += 1usize
            }
            let d = 0.0f64 - (1.0f64 + (m1[0usize] * m1[2usize] - m1[1usize] * m1[1usize]))
            if (d - delta) > 1.0e-12f64 {
                delta = d
                new_block = f.nb
                xnew = j
            }
            j += 1usize
        }
    }
    ret (delta, xnew, new_block)
}

fn exchange_block(f: *Blk, xcur: usize, xnew: usize, cur_block: usize, new_block: usize) {
    let k = f.k
    let ib = f.nb * f.maxn
    let rowno_i = usize(f.b[cur_block * f.maxn + xcur])
    let ni = f.sizes[cur_block]
    let dv = f.vec[0usize..k]
    let tv = f.vec[k..2usize * k]
    if f.extra && new_block == f.nb {
        let rowno_j = usize(f.b[ib + xnew])
        var i = 0usize
        while i < k {
            dv[i] = f.x[rowno_j * k + i] - f.bm[cur_block * k + i]
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 1.0f64)
        i = 0usize
        while i < k {
            dv[i] = f.x[rowno_i * k + i] - f.bm[cur_block * k + i]
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 0.0f64 - 1.0f64)
        i = 0usize
        while i < k {
            dv[i] = f.x[rowno_j * k + i] - f.x[rowno_i * k + i]
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 0.0f64 - 1.0f64 / f64(ni))
        f.b[ib + xnew] = i64(rowno_i)
        f.b[cur_block * f.maxn + xcur] = i64(rowno_j)
    } else {
        let rowno_j = usize(f.b[new_block * f.maxn + xnew])
        let nj = f.sizes[new_block]
        let c = f64(ni + nj) / f64(ni * nj)
        var i = 0usize
        while i < k {
            dv[i] = f.bm[new_block * k + i] - f.bm[cur_block * k + i]
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 1.0f64)
        i = 0usize
        while i < k {
            dv[i] = dv[i] - (f.x[rowno_j * k + i] - f.x[rowno_i * k + i])
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 0.0f64 - 1.0f64)
        i = 0usize
        while i < k {
            dv[i] = f.x[rowno_j * k + i] - f.x[rowno_i * k + i]
            i += 1usize
        }
        rotate_b(dv, tv, f.t, k, k, 1.0f64 - c)
        i = 0usize
        while i < k {
            f.bm[cur_block * k + i] += (f.x[rowno_j * k + i] - f.x[rowno_i * k + i]) / f64(ni)
            i += 1usize
        }
        i = 0usize
        while i < k {
            f.bm[new_block * k + i] += (f.x[rowno_i * k + i] - f.x[rowno_j * k + i]) / f64(nj)
            i += 1usize
        }
        f.b[new_block * f.maxn + xnew] = i64(rowno_i)
        f.b[cur_block * f.maxn + xcur] = i64(rowno_j)
    }
}

// NoDupPermuteB: permutes rows until none of the first n entries of block row bi (already placed) is among the first bs - n of rows
fn no_dup_permute(f: *Blk, g: *rng.Rng, rows: []i64, nn: usize, bi: usize, n: usize, bs: usize) {
    var nodup = false
    while !nodup {
        nodup = true
        permute_b(g, rows, nn)
        var i = 0usize
        while i < n {
            let cur = f.b[bi * f.maxn + i]
            var j = 0usize
            while j + n < bs {
                if rows[j] == cur {
                    nodup = false
                    break
                }
                j += 1usize
            }
            if !nodup { break }
            i += 1usize
        }
    }
}

fn initialize_b(f: *Blk, g: *rng.Rng, rows: []i64, irows: []const i64, init_rows: bool, nxb: usize, first_repeat: bool) {
    var nt = f.n
    if init_rows { nt = nxb }
    var i = 0usize
    while i < nt {
        rows[i] = i64(i)
        i += 1usize
    }
    if init_rows {
        i = 0usize
        while i < nxb {
            let t = rows[i]
            rows[i] = irows[i]
            rows[usize(irows[i])] = t
            i += 1usize
        }
        if !first_repeat { permute_b(g, rows, nxb) }
    } else {
        permute_b(g, rows, nt)
    }
    var total = f.nb * f.maxn
    if f.extra { total += f.nex }
    i = 0usize
    while i < total {
        f.b[i] = 0i64 - 1i64
        i += 1usize
    }
    var l = 0usize
    i = 0usize
    while i < f.nb {
        let bs = f.sizes[i]
        var j = 0usize
        while j < bs {
            if l >= nt {
                l = 0usize
                no_dup_permute(f, g, rows, f.n, i, j, bs)
            }
            f.b[i * f.maxn + j] = rows[l]
            l += 1usize
            j += 1usize
        }
        i += 1usize
    }
    if f.extra {
        var ib = f.nb * f.maxn
        i = l
        while i < nt {
            f.b[ib] = rows[i]
            ib += 1usize
            i += 1usize
        }
    }
}

// BlockOptimize for the D criterion. x is N by k row-major; sizes the block sizes; irows the initial rows (0-based) or empty
fn block_optimize(a: *mem.Arena, g: *rng.Rng, x: []const f64, n: usize, k: usize, sizes: []const usize, irows: []const i64, init_rows: bool, n_repeats: i64) -> (BRes, err) {
    var res: BRes = zero
    let nb = sizes.len
    var nxb = 0usize
    var maxn = 0usize
    var i = 0usize
    while i < nb {
        nxb += sizes[i]
        if sizes[i] > maxn { maxn = sizes[i] }
        i += 1usize
    }
    var f: Blk = zero
    f.n = n
    f.k = k
    f.nb = nb
    f.maxn = maxn
    f.extra = nxb < n
    f.nex = 0usize
    if f.extra { f.nex = n - nxb }
    let kk = k * (k + 1usize) / 2usize
    var nt = n
    if nt < 5usize * k { nt = 5usize * k }
    let (xx, e1) = mem.alloc[f64](a, n * k)
    let (tx, e2) = mem.alloc[f64](a, nt * k)
    let (bm, e3) = mem.alloc[f64](a, nb * k)
    let (tbm, e4) = mem.alloc[f64](a, nb * k)
    let (b, e5) = mem.alloc[i64](a, nb * maxn + f.nex + 1usize)
    let (t, e6) = mem.alloc[f64](a, kk)
    let (tip, e7) = mem.alloc[f64](a, kk)
    let (w, e8) = mem.alloc[f64](a, k * k + 5usize * k)
    let (vec, e9) = mem.alloc[f64](a, 2usize * k)
    let (sc, e10) = mem.alloc[f64](a, 2usize * k)
    var nr = n
    if nxb > nr { nr = nxb }
    let (rows, e11) = mem.alloc[i64](a, nr)
    let (ba, e12) = mem.alloc[i64](a, nxb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (res, e1) }
    i = 0usize
    while i < n * k {
        xx[i] = x[i]
        i += 1usize
    }
    f.x = xx
    f.tx = tx
    f.bm = bm
    f.tbm = tbm
    f.b = b
    f.t = t
    f.tip = tip
    f.w = w
    f.vec = vec
    f.sc = sc
    f.sizes = sizes
    // initializeBlockArray: the answer when every repeat is singular or nothing improves
    var nt0 = n
    if init_rows { nt0 = nxb }
    i = 0usize
    while i < nt0 {
        if init_rows { rows[i] = irows[i] } else { rows[i] = i64(i) }
        i += 1usize
    }
    var l = 0usize
    var m = 0usize
    i = 0usize
    while i < nb {
        var j = 0usize
        while j < sizes[i] {
            if l >= nt0 { l = 0usize }
            ba[m] = rows[l] + 1i64
            m += 1usize
            l += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var logd_crit = 0.0f64
    var logd_best = 0.0f64
    var avvar = 1.0f64
    var count_singular = 0i64
    var counts = n_repeats
    var iter = 0i64
    var again = true
    while again {
        initialize_b(&f, g, rows, irows, init_rows, nxb, counts == n_repeats)
        form_block_means(&f)
        let (ld, singular) = reduce_x_to_t(&f)
        logd_crit = ld
        if !singular {
            var avar = make_ti_from_t(&f)
            transform(&f)
            var exchanged = true
            while exchanged {
                exchanged = false
                var cb = 0usize
                while cb < nb {
                    var xcur = 0usize
                    while xcur < sizes[cb] {
                        let (delta, xnew, newb) = find_delta_block(&f, xcur, cb)
                        if 10.0f64 > delta && delta > 1.0e-12f64 {
                            exchange_block(&f, xcur, xnew, cb, newb)
                            logd_crit += math.log[f64](1.0f64 + delta)
                            exchanged = true
                            avar = make_ti_from_t(&f)
                            transform(&f)
                        }
                        xcur += 1usize
                    }
                    cb += 1usize
                }
            }
            if logd_crit > logd_best {
                iter += 1i64
                logd_best = logd_crit
                avvar = avar
                var jj = 0usize
                i = 0usize
                while i < nb * maxn {
                    if f.b[i] != 0i64 - 1i64 {
                        ba[jj] = f.b[i] + 1i64
                        jj += 1usize
                    }
                    i += 1usize
                }
            }
        } else {
            count_singular += 1i64
        }
        counts -= 1i64
        if counts == 0i64 { again = false }
    }
    if count_singular == n_repeats {
        res.errcode = 13i64
    } else {
        res.errcode = 0i64
        if logd_best == 0.0f64 {
            res.errcode = 22i64
            res.dd = math.exp[f64](logd_crit / f64(k)) / f64(nxb)
            res.diagonality = 0.0f64
        } else {
            res.dd = math.exp[f64](logd_best / f64(k)) / f64(nxb)
            res.diagonality = 1.0f64 / (res.dd * avvar * f64(nxb))
        }
    }
    res.iter = iter
    res.block_array = ba
    ret (res, ok)
}
