// Barnes-Hut t-SNE: Rtsne with theta > 0 (bhtsne's sptree and sparse affinities). The K = int(3 perplexity) neighbours are the exact nearest (the vantage-point tree of Rtsne searches
// exactly, so its shape only matters for distance ties); the tree's one observable effect is the number of runif draws spent building it, which is replayed so the random start (no Y_init)
// lines up with R's generator. mode 0 plain, 1 normalize, 2 x is an n by n distance matrix.

use e.algo.rand.r as rng
use e.algo.stat.tsne as ts
use e.math
use e.mem

type Sp = struct { dims: usize, nc: usize, cap: usize, data: []const f64, f: []f64, u: []usize, meta: []usize }

// Each Rcpp::RNGScope reloads the generator from the last saved seed on entry and saves it on exit, and the vantage-point tree nests them (one per node with more than one point), so a node's
// draw restarts from the seed saved by the last scope to close: st[0] is that saved position, st[1] the live one.
fn vp_sim(s: usize, st: []usize) {
    if s <= 1usize { ret }
    st[1usize] = st[0usize] + 1usize
    vp_sim(s / 2usize - 1usize, st)
    vp_sim(s - s / 2usize, st)
    st[0usize] = st[1usize]
}

fn sp_init_node(t: Sp, node: usize) {
    var k = 0usize
    while k < 9usize {
        t.f[node * 9usize + k] = 0.0f64
        k += 1usize
    }
    t.u[node * 5usize] = 0usize
    t.u[node * 5usize + 1usize] = 0usize
    t.u[node * 5usize + 2usize] = 0usize
    t.u[node * 5usize + 3usize] = 1usize
    t.u[node * 5usize + 4usize] = 0usize
}

fn sp_contains(t: Sp, node: usize, pi: usize) -> bool {
    var d = 0usize
    while d < t.dims {
        let c = t.f[node * 9usize + d]
        let w = t.f[node * 9usize + 3usize + d]
        let p = t.data[pi * t.dims + d]
        if c - w > p { ret false }
        if c + w < p { ret false }
        d += 1usize
    }
    ret true
}

fn sp_subdivide(t: Sp, node: usize) {
    let first = t.meta[0usize]
    t.meta[0usize] = first + t.nc
    t.u[node * 5usize + 4usize] = first
    var i = 0usize
    while i < t.nc {
        let ch = first + i
        sp_init_node(t, ch)
        var div = 1usize
        var d = 0usize
        while d < t.dims {
            let pw = t.f[node * 9usize + 3usize + d]
            let pc = t.f[node * 9usize + d]
            t.f[ch * 9usize + 3usize + d] = 0.5f64 * pw
            if (i / div) % 2usize == 1usize { t.f[ch * 9usize + d] = pc - 0.5f64 * pw } else { t.f[ch * 9usize + d] = pc + 0.5f64 * pw }
            div *= 2usize
            d += 1usize
        }
        i += 1usize
    }
    if t.u[node * 5usize + 1usize] > 0usize {
        let moved = t.u[node * 5usize + 2usize]
        var success = false
        var j = 0usize
        while j < t.nc {
            if !success { success = sp_insert(t, first + j, moved) }
            j += 1usize
        }
    }
    t.u[node * 5usize + 1usize] = 0usize
    t.u[node * 5usize + 3usize] = 0usize
}

fn sp_insert(t: Sp, node: usize, pi: usize) -> bool {
    if !sp_contains(t, node, pi) { ret false }
    let ub = node * 5usize
    let fb = node * 9usize
    t.u[ub] += 1usize
    let cs = t.u[ub]
    let mult1 = f64(cs - 1usize) / f64(cs)
    let mult2 = 1.0f64 / f64(cs)
    var d = 0usize
    while d < t.dims {
        t.f[fb + 6usize + d] = t.f[fb + 6usize + d] * mult1 + mult2 * t.data[pi * t.dims + d]
        d += 1usize
    }
    if t.u[ub + 3usize] == 1usize && t.u[ub + 1usize] < 1usize {
        t.u[ub + 2usize] = pi
        t.u[ub + 1usize] = 1usize
        ret true
    }
    var any_dup = false
    if t.u[ub + 1usize] > 0usize {
        var dup = true
        d = 0usize
        while d < t.dims {
            if t.data[pi * t.dims + d] != t.data[t.u[ub + 2usize] * t.dims + d] {
                dup = false
                d = t.dims
            } else {
                d += 1usize
            }
        }
        any_dup = dup
    }
    if any_dup { ret true }
    if t.u[ub + 3usize] == 1usize {
        if t.meta[0usize] + t.nc > t.cap { ret false }
        sp_subdivide(t, node)
    }
    let first = t.u[ub + 4usize]
    var i = 0usize
    while i < t.nc {
        if sp_insert(t, first + i, pi) { ret true }
        i += 1usize
    }
    ret false
}

fn sp_nonedge(t: Sp, node: usize, pi: usize, theta: f64, neg: []f64, nb: usize) -> f64 {
    let ub = node * 5usize
    let fb = node * 9usize
    if t.u[ub] == 0usize { ret 0.0f64 }
    if t.u[ub + 3usize] == 1usize && t.u[ub + 1usize] == 1usize && t.u[ub + 2usize] == pi { ret 0.0f64 }
    var buff0 = 0.0f64
    var buff1 = 0.0f64
    var buff2 = 0.0f64
    var sqdist = 0.0f64
    var d = 0usize
    while d < t.dims {
        let b = t.data[pi * t.dims + d] - t.f[fb + 6usize + d]
        if d == 0usize { buff0 = b }
        if d == 1usize { buff1 = b }
        if d == 2usize { buff2 = b }
        sqdist += b * b
        d += 1usize
    }
    var max_width = 0.0f64
    d = 0usize
    while d < t.dims {
        let cw = t.f[fb + 3usize + d]
        if !(max_width > cw) { max_width = cw }
        d += 1usize
    }
    if t.u[ub + 3usize] == 1usize || max_width / math.sqrt[f64](sqdist) < theta {
        let sq = 1.0f64 / (1.0f64 + sqdist)
        var mult = f64(t.u[ub]) * sq
        let res = mult
        mult *= sq
        neg[nb] += mult * buff0
        if t.dims > 1usize { neg[nb + 1usize] += mult * buff1 }
        if t.dims > 2usize { neg[nb + 2usize] += mult * buff2 }
        ret res
    }
    var sum = 0.0f64
    let first = t.u[ub + 4usize]
    var i = 0usize
    while i < t.nc {
        sum += sp_nonedge(t, first + i, pi, theta, neg, nb)
        i += 1usize
    }
    ret sum
}

// y is the start on entry when init, else tsne_bh draws it from g (after the tree's draws); the embedding on exit.
fn tsne_bh(a: *mem.Arena, x: []const f64, n: usize, d: usize, dims: usize, perplexity: f64, theta: f64, y: []f64, max_iter: usize, stop_lying: usize, mom_switch: usize, momentum0: f64, final_momentum: f64, eta: f64, exaggeration: f64, mode: usize, g: *rng.Rng, init: bool) -> err {
    let kk = usize(3.0f64 * perplexity)
    let (xs, e0) = mem.alloc[f64](a, n * d)
    let (rowp, e1) = mem.alloc[usize](a, n + 1usize)
    let (colp, e2) = mem.alloc[usize](a, n * kk)
    let (valp, e3) = mem.alloc[f64](a, n * kk)
    let (dy, e4) = mem.alloc[f64](a, n * dims)
    let (uy, e5) = mem.alloc[f64](a, n * dims)
    let (gains, e6) = mem.alloc[f64](a, n * dims)
    let (posf, e7) = mem.alloc[f64](a, n * dims)
    let (negf, e8) = mem.alloc[f64](a, n * dims)
    let (nnd, e9) = mem.alloc[f64](a, kk + 1usize)
    let (nni, e10) = mem.alloc[usize](a, kk + 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e0 }
    var i = 0usize
    while i < n * d {
        xs[i] = x[i]
        i += 1usize
    }
    if mode == 1usize {
        ts.zero_mean(xs, n, d)
        var mx = 0.0f64
        i = 0usize
        while i < n * d {
            let v = math.abs[f64](xs[i])
            if v > mx { mx = v }
            i += 1usize
        }
        i = 0usize
        while i < n * d {
            xs[i] /= mx
            i += 1usize
        }
    }
    if !init {
        let (st, es) = mem.alloc[usize](a, 2usize)
        if es != ok { ret es }
        st[0usize] = 0usize
        st[1usize] = 0usize
        vp_sim(n, st)
        var draws = st[0usize]
        while draws > 0usize {
            let _ = rng.unif(g)
            draws -= 1usize
        }
    }
    let lp = math.log[f64](perplexity)
    var r = 0usize
    while r < n {
        var cnt = 0usize
        var m = 0usize
        while m < n {
            var dist = 0.0f64
            if mode == 2usize {
                dist = xs[r * d + m]
            } else {
                var s = 0.0f64
                var c = 0usize
                while c < d {
                    let t = xs[r * d + c] - xs[m * d + c]
                    s += t * t
                    c += 1usize
                }
                dist = math.sqrt[f64](s)
            }
            if cnt < kk + 1usize || dist < nnd[cnt - 1usize] {
                var p = cnt
                if cnt == kk + 1usize { p = kk }
                while p > 0usize && nnd[p - 1usize] > dist {
                    nnd[p] = nnd[p - 1usize]
                    nni[p] = nni[p - 1usize]
                    p -= 1usize
                }
                nnd[p] = dist
                nni[p] = m
                if cnt < kk + 1usize { cnt += 1usize }
            }
            m += 1usize
        }
        rowp[r] = r * kk
        var found = false
        var beta = 1.0f64
        var minb = 0.0f64 - ts.dbl_max()
        var maxb = ts.dbl_max()
        var it = 0usize
        var sum_p = 0.0f64
        while !found && it < 200usize {
            m = 0usize
            while m < kk {
                valp[r * kk + m] = math.exp[f64](0.0f64 - beta * nnd[m + 1usize] * nnd[m + 1usize])
                m += 1usize
            }
            sum_p = ts.dbl_min()
            m = 0usize
            while m < kk {
                sum_p += valp[r * kk + m]
                m += 1usize
            }
            var h = 0.0f64
            m = 0usize
            while m < kk {
                h += beta * (nnd[m + 1usize] * nnd[m + 1usize] * valp[r * kk + m])
                m += 1usize
            }
            h = h / sum_p + math.log[f64](sum_p)
            let hd = h - lp
            if hd < 1.0e-5f64 && 0.0f64 - hd < 1.0e-5f64 {
                found = true
            } else {
                if hd > 0.0f64 {
                    minb = beta
                    if maxb == ts.dbl_max() || maxb == 0.0f64 - ts.dbl_max() { beta *= 2.0f64 } else { beta = (beta + maxb) / 2.0f64 }
                } else {
                    maxb = beta
                    if minb == 0.0f64 - ts.dbl_max() || minb == ts.dbl_max() { beta /= 2.0f64 } else { beta = (beta + minb) / 2.0f64 }
                }
                it += 1usize
            }
        }
        m = 0usize
        while m < kk {
            valp[r * kk + m] /= sum_p
            colp[r * kk + m] = nni[m + 1usize]
            m += 1usize
        }
        r += 1usize
    }
    rowp[n] = n * kk
    let (cnts, e11) = mem.alloc[usize](a, n)
    let (offs, e12) = mem.alloc[usize](a, n)
    let (srow, e13) = mem.alloc[usize](a, n + 1usize)
    if e11 != ok || e12 != ok || e13 != ok { ret e11 }
    r = 0usize
    while r < n {
        cnts[r] = 0usize
        offs[r] = 0usize
        r += 1usize
    }
    r = 0usize
    while r < n {
        i = rowp[r]
        while i < rowp[r + 1usize] {
            var present = false
            var m = rowp[colp[i]]
            while m < rowp[colp[i] + 1usize] {
                if colp[m] == r { present = true }
                m += 1usize
            }
            cnts[r] += 1usize
            if !present { cnts[colp[i]] += 1usize }
            i += 1usize
        }
        r += 1usize
    }
    var no_elem = 0usize
    r = 0usize
    while r < n {
        no_elem += cnts[r]
        r += 1usize
    }
    let (scol, e14) = mem.alloc[usize](a, no_elem)
    let (sval, e15) = mem.alloc[f64](a, no_elem)
    if e14 != ok || e15 != ok { ret e14 }
    srow[0usize] = 0usize
    r = 0usize
    while r < n {
        srow[r + 1usize] = srow[r] + cnts[r]
        r += 1usize
    }
    r = 0usize
    while r < n {
        i = rowp[r]
        while i < rowp[r + 1usize] {
            let cj = colp[i]
            var present = false
            var m = rowp[cj]
            while m < rowp[cj + 1usize] {
                if colp[m] == r {
                    present = true
                    if r <= cj {
                        scol[srow[r] + offs[r]] = cj
                        scol[srow[cj] + offs[cj]] = r
                        sval[srow[r] + offs[r]] = valp[i] + valp[m]
                        sval[srow[cj] + offs[cj]] = valp[i] + valp[m]
                    }
                }
                m += 1usize
            }
            if !present {
                scol[srow[r] + offs[r]] = cj
                scol[srow[cj] + offs[cj]] = r
                sval[srow[r] + offs[r]] = valp[i]
                sval[srow[cj] + offs[cj]] = valp[i]
            }
            if !present || r <= cj {
                offs[r] += 1usize
                if cj != r { offs[cj] += 1usize }
            }
            i += 1usize
        }
        r += 1usize
    }
    i = 0usize
    while i < no_elem {
        sval[i] /= 2.0f64
        i += 1usize
    }
    var sump = 0.0f64
    i = 0usize
    while i < no_elem {
        sump += sval[i]
        i += 1usize
    }
    i = 0usize
    while i < no_elem {
        sval[i] /= sump
        sval[i] *= exaggeration
        i += 1usize
    }
    if !init { ts.tsne_start(g, n, dims, y) }
    var nc = 1usize
    i = 0usize
    while i < dims {
        nc *= 2usize
        i += 1usize
    }
    let cap = 1usize + nc * n * 40usize
    let (tf, e16) = mem.alloc[f64](a, cap * 9usize)
    let (tu, e17) = mem.alloc[usize](a, cap * 5usize)
    let (tm, e18) = mem.alloc[usize](a, 1usize)
    if e16 != ok || e17 != ok || e18 != ok { ret e16 }
    var t: Sp = zero
    t.dims = dims
    t.nc = nc
    t.cap = cap
    t.data = y
    t.f = tf
    t.u = tu
    t.meta = tm
    i = 0usize
    while i < n * dims {
        uy[i] = 0.0f64
        gains[i] = 1.0f64
        i += 1usize
    }
    var momentum = momentum0
    var iter = 0usize
    while iter < max_iter {
        if iter == stop_lying {
            i = 0usize
            while i < no_elem {
                sval[i] /= exaggeration
                i += 1usize
            }
        }
        if iter == mom_switch { momentum = final_momentum }
        tm[0usize] = 1usize
        sp_init_node(t, 0usize)
        var c = 0usize
        while c < dims {
            var mean = 0.0f64
            var mn = ts.dbl_max()
            var mxv = 0.0f64 - ts.dbl_max()
            r = 0usize
            while r < n {
                let v = y[r * dims + c]
                mean += v
                if v < mn { mn = v }
                if v > mxv { mxv = v }
                r += 1usize
            }
            mean /= f64(n)
            tf[c] = mean
            var w1 = mxv - mean
            let w2 = mean - mn
            if w1 <= w2 { w1 = w2 }
            tf[3usize + c] = w1 + 1.0e-5f64
            c += 1usize
        }
        r = 0usize
        while r < n {
            let _ = sp_insert(t, 0usize, r)
            r += 1usize
        }
        i = 0usize
        while i < n * dims {
            posf[i] = 0.0f64
            negf[i] = 0.0f64
            i += 1usize
        }
        r = 0usize
        while r < n {
            var j = srow[r]
            while j < srow[r + 1usize] {
                var sq = 1.0f64
                let o2 = scol[j] * dims
                var b0 = 0.0f64
                var b1 = 0.0f64
                var b2 = 0.0f64
                c = 0usize
                while c < dims {
                    let b = y[r * dims + c] - y[o2 + c]
                    if c == 0usize { b0 = b }
                    if c == 1usize { b1 = b }
                    if c == 2usize { b2 = b }
                    sq += b * b
                    c += 1usize
                }
                sq = sval[j] / sq
                posf[r * dims] += sq * b0
                if dims > 1usize { posf[r * dims + 1usize] += sq * b1 }
                if dims > 2usize { posf[r * dims + 2usize] += sq * b2 }
                j += 1usize
            }
            r += 1usize
        }
        var sum_q = 0.0f64
        r = 0usize
        while r < n {
            sum_q += sp_nonedge(t, 0usize, r, theta, negf, r * dims)
            r += 1usize
        }
        i = 0usize
        while i < n * dims {
            dy[i] = posf[i] - negf[i] / sum_q
            i += 1usize
        }
        i = 0usize
        while i < n * dims {
            if ts.sgn(dy[i]) != ts.sgn(uy[i]) { gains[i] += 0.2f64 } else { gains[i] *= 0.8f64 }
            if gains[i] < 0.01f64 { gains[i] = 0.01f64 }
            i += 1usize
        }
        i = 0usize
        while i < n * dims {
            uy[i] = momentum * uy[i] - eta * gains[i] * dy[i]
            y[i] += uy[i]
            i += 1usize
        }
        ts.zero_mean(y, n, dims)
        iter += 1usize
    }
    ret ok
}
