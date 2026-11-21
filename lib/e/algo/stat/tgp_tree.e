// R's tgp::btlm and tgp::bcart: the Bayesian treed linear model (bcart: constant mean), the flat beta prior and the
// limiting linear model forced on at every leaf (gamma = -1, nugget fixed at zero). The Markov chain is tgp's:
// Model::rounds with a tree move every 4th round (Model::modify_tree: grow 1/5, prune 1/5, change 2/5, swap 1/5, and
// Tree::grow / prune / change / swap / rotate / match with the triangular split-point proposal over Xsplit), then
// Gp::Draw at every leaf in order, the s2 hyper-prior step over all leaves, then Tree::Predict leaf by leaf.
// Under the forced LLM a leaf's Split costs two uniforms (the d index, the tau2 index), a Combine three, and Match
// copies parameters the next Gp::Draw overwrites, so the leaf carries no correlation state. Not here: the GP leaves
// (btgp, btgpllm), tempering, the MAP tree summaries, R > 1.

use e.algo.rand.r as rr
use e.algo.stat.tgp as tgp
use e.algo.stat.tgp_blm as lm
use e.algo.stat.tgp_design as dz
use e.algo.stat.tgp_gp as gpm
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

const NONE: usize = 1000000usize

type TS = struct {
    n: usize, d: usize, col: usize, nsplit: usize, minpart: usize, nmax: usize,
    par: []usize, lc: []usize, rc: []usize, dep: []usize, vr: []usize, vl: []f64,
    cnt: []usize, idx: []usize, lo: []f64, hi: []f64, gt: []usize,
    gx: []gpm.Gx, fbuf: []f64, zbuf: []f64, xbuf: []f64, kbuf: []f64,
    gmode: bool, gam0: f64, gam1: f64, gam2: f64,
    freel: []usize, nfree: usize, root: usize,
    xn: []f64, z: []f64, xs: []f64,
    xo: []f64, pr: []f64, xmm: []f64, ord: []usize, cum: []f64,
    talpha: f64, tbeta: f64, a0: f64, g0: f64, tree_op: i64,
    l1: []usize, l2: []usize, l3: []usize, l4: []usize, ll: []usize,
    tries: [4]usize, wins: [4]usize,
    xorig: []f64, rlo: []f64, rhi: []f64, mp_post: []f64, mp_var: []usize, mp_val: []f64, mp_n: []usize
}

// map_*: the best tree of each height by full posterior (preorder: split variable or NONE for a leaf, split value on the
// data scale as R reads it back from the printed tree), maph the height holding the largest
type Tgt = struct { b: lm.Blm, gpcs: [4]f64, lposts: []f64, nh: usize, maph: usize, map_var: []usize, map_val: []f64, map_n: usize }

fn lg(x: f64) -> f64 { ret math.log[f64](x) }

fn zi(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (s, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n + 1usize {
        s[i] = 0usize
        i += 1usize
    }
    ret (s, ok)
}


// ---- node pool ----

fn new_node(ts: *TS, parent: usize) -> usize {
    ts.nfree -= 1usize
    let id = ts.freel[ts.nfree]
    ts.par[id] = parent
    ts.lc[id] = NONE
    ts.rc[id] = NONE
    if parent == NONE { ts.dep[id] = 0usize } else { ts.dep[id] = ts.dep[parent] + 1usize }
    ts.cnt[id] = 0usize
    ts.vr[id] = 0usize
    ts.vl[id] = 0.0f64
    var gx: gpm.Gx = zero
    gx.g.col = ts.col
    gx.g.kd = 1.0f64
    gx.g.s2 = 1.0f64
    gx.col = ts.col
    gx.d = ts.d
    gx.gam0 = ts.gam0
    gx.gam1 = ts.gam1
    gx.gam2 = ts.gam2
    if ts.gmode {
        gx.nug = 0.1f64
        gx.linear = ts.gam0 > 0.0f64
        var j = 0usize
        while j < ts.d {
            gx.dv[j] = 0.5f64
            gx.bv[j] = 1i64
            gx.deff[j] = 0.5f64
            j += 1usize
        }
    }
    ts.gx[id] = gx
    ret id
}

fn free_tree(ts: *TS, id: usize) {
    if id == NONE { ret }
    if ts.lc[id] != NONE {
        free_tree(ts, ts.lc[id])
        free_tree(ts, ts.rc[id])
    }
    ts.freel[ts.nfree] = id
    ts.nfree += 1usize
}

fn is_leaf(ts: *TS, id: usize) -> bool { ret ts.lc[id] == NONE }

fn is_prunable(ts: *TS, id: usize) -> bool {
    if ts.lc[id] == NONE { ret false }
    ret ts.lc[ts.lc[id]] == NONE && ts.lc[ts.rc[id]] == NONE
}

// ---- node lists, in the orders of Tree::leaves / internals / prunable / swapable ----

fn collect_leaves(ts: *TS, id: usize, out: []usize, c: usize) -> usize {
    if ts.lc[id] == NONE {
        out[c] = id
        ret c + 1usize
    }
    let c1 = collect_leaves(ts, ts.lc[id], out, c)
    ret collect_leaves(ts, ts.rc[id], out, c1)
}

fn collect_internals(ts: *TS, id: usize, out: []usize, c: usize) -> usize {
    if ts.lc[id] == NONE { ret c }
    out[c] = id
    let c1 = collect_internals(ts, ts.lc[id], out, c + 1usize)
    ret collect_internals(ts, ts.rc[id], out, c1)
}

fn collect_swapable(ts: *TS, id: usize, out: []usize, c: usize) -> usize {
    if ts.lc[id] == NONE { ret c }
    var c0 = c
    if ts.par[id] != NONE {
        out[c0] = id
        c0 += 1usize
    }
    let c1 = collect_swapable(ts, ts.lc[id], out, c0)
    ret collect_swapable(ts, ts.rc[id], out, c1)
}

fn collect_prunable(ts: *TS, id: usize, out: []usize, c: usize) -> usize {
    if ts.lc[id] == NONE { ret c }
    if is_prunable(ts, id) {
        out[c] = id
        ret c + 1usize
    }
    let c1 = collect_prunable(ts, ts.lc[id], out, c)
    ret collect_prunable(ts, ts.rc[id], out, c1)
}

fn adjust_depth(ts: *TS, id: usize, a: i64) {
    if ts.lc[id] != NONE {
        adjust_depth(ts, ts.lc[id], a)
        adjust_depth(ts, ts.rc[id], a)
    }
    ts.dep[id] = usize(i64(ts.dep[id]) + a)
}

// ---- RNG helpers ----

// isample / dsample: the index drawn from the cumulative sums of the probabilities
fn pick_cum(rk: *tgp.Rk, cum: []const f64, len: usize) -> usize {
    let pick = tgp.runi(rk)
    var counter = 0usize
    while counter + 1usize < len && cum[counter] < pick { counter += 1usize }
    ret counter
}

// sample_seq(0, len - 1): no draw when there is one choice
fn sample_idx(ts: *TS, rk: *tgp.Rk, len: usize) -> usize {
    if len == 1usize { ret 0usize }
    let p = 1.0f64 / f64(len)
    ts.cum[0usize] = p
    var i = 1usize
    while i < len {
        ts.cum[i] = ts.cum[i - 1usize] + p
        i += 1usize
    }
    if ts.cum[len - 1usize] < 1.0f64 { ts.cum[len - 1usize] = 1.0f64 }
    ret pick_cum(rk, ts.cum, len)
}

// ---- leaf model ----

fn leaf_update(ts: *TS, id: usize) {
    let n = ts.cnt[id]
    let col = ts.col
    let d = ts.d
    let fo = id * col * ts.n
    let zo = id * ts.n
    var gx = ts.gx[id]
    gx.g.n = n
    gx.g.col = col
    gx.g.f = ts.fbuf[fo..fo + col * n]
    gx.g.z = ts.zbuf[zo..zo + n]
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let row = ts.idx[id * ts.n + i]
        gx.g.f[i] = 1.0f64
        var j = 1usize
        while j < col {
            gx.g.f[j * n + i] = ts.xn[row * d + (j - 1usize)]
            j += 1usize
        }
        gx.g.z[i] = ts.z[row]
        s += gx.g.z[i]
        i += 1usize
    }
    gx.g.mean = s / f64(n)
    gx.g.kd = 1.0f64
    gx.g.a0 = ts.a0
    gx.g.g0 = ts.g0
    if !ts.gmode {
        lm.compute(&gx.g)
        gx.logdet = 0.0f64
        ts.gx[id] = gx
        ret
    }
    // Gp::Update: the leaf's data, then K, its inverse and determinant unless at the LLM; then Gp::Compute
    let xo = id * ts.n * d
    gx.n = n
    gx.x = ts.xbuf[xo..xo + n * d]
    i = 0usize
    while i < n {
        let row = ts.idx[id * ts.n + i]
        var j = 0usize
        while j < d {
            gx.x[i * d + j] = ts.xn[row * d + j]
            j += 1usize
        }
        i += 1usize
    }
    let n2 = ts.n * ts.n
    let ko = id * 7usize * n2
    gx.k = ts.kbuf[ko..ko + n * n]
    gx.ki = ts.kbuf[ko + n2..ko + n2 + n * n]
    gx.kc = ts.kbuf[ko + 2usize * n2..ko + 2usize * n2 + n * n]
    gx.kn = ts.kbuf[ko + 3usize * n2..ko + 3usize * n2 + n * n]
    gx.kin = ts.kbuf[ko + 4usize * n2..ko + 4usize * n2 + n * n]
    gx.kcn = ts.kbuf[ko + 5usize * n2..ko + 5usize * n2 + n * n]
    gx.w = ts.kbuf[ko + 6usize * n2..ko + 6usize * n2 + n * n]
    if !gx.linear {
        gpm.corr_symm(gx.k, gx.x, n, d, gx.deff, gx.nug)
        if gpm.chol_inv(gx.k, gx.ki, gx.kc, n, gx.w) { gx.logdet = gpm.log_det_chol(gx.kc, n) } else { gx.logdet = gpm.ninf() }
    } else {
        gx.logdet = f64(n) * lg(1.0f64 + gx.nug)
    }
    gpm.gp_compute(&gx)
    ts.gx[id] = gx
}

// post_margin_rj with the flat beta prior (T = 0, tau2 = 1, itemp = 1) and the prior (a0, g0) of s2
fn post_rj(ts: *TS, id: usize) -> f64 {
    let g = &ts.gx[id].g
    let n = f64(g.n)
    let col = f64(g.col)
    let ldv = gpm.log_det_small(g.vb, g.col)
    let ldk = ts.gx[id].logdet
    if ldv == gpm.ninf() || g.lambda < 0.0f64 || ldk == gpm.ninf() { ret gpm.ninf() }
    let one = ldv - n * 0.91893853320467274178f64 * 2.0f64 - ldk
    let two = 0.5f64 * ts.a0 * lg(0.5f64 * ts.g0) - 0.5f64 * (ts.a0 + (n - col)) * lg(0.5f64 * (ts.g0 + g.lambda)) + nm.lgammafn(0.5f64 * (ts.a0 + (n - col))) - nm.lgammafn(0.5f64 * ts.a0)
    let p = 0.5f64 * one + two
    if p != p { ret gpm.ninf() }
    ret p
}

fn leaf_post(ts: *TS, id: usize) -> f64 {
    if ts.gx[id].g.n == 0usize { leaf_update(ts, id) }
    ret post_rj(ts, id)
}

// Tree::leavesPosterior: stops summing at the first non-finite leaf
fn leaves_post(ts: *TS, id: usize, buf: []usize) -> f64 {
    let c = collect_leaves(ts, id, buf, 0usize)
    var p = 0.0f64
    var i = 0usize
    while i < c {
        p += leaf_post(ts, buf[i])
        if p != p || p == gpm.ninf() || p == 1.0f64 / 0.0f64 { ret p }
        i += 1usize
    }
    ret p
}

fn clear_g(ts: *TS, id: usize) { ts.gx[id].g.n = 0usize }

// ---- partitions ----

// Tree::Singular
fn singular(ts: *TS, id: usize) -> bool {
    let n = ts.cnt[id]
    let d = ts.d
    let xr = ts.xn
    var i = 0usize
    while i < d {
        let f = xr[ts.idx[id * ts.n] * d + i]
        var j = 1usize
        while j < n {
            if f != xr[ts.idx[id * ts.n + j] * d + i] { j = n + 1usize } else { j += 1usize }
        }
        if j == n { ret true }
        i += 1usize
    }
    // fewer than d + 1 distinct rows
    var un = 1usize
    var u: [64]usize = zero
    u[0usize] = ts.idx[id * ts.n]
    i = 1usize
    while i < n && un < d + 1usize {
        let row = ts.idx[id * ts.n + i]
        var j = 0usize
        var same = false
        while j < un && !same {
            var e = true
            var k = 0usize
            while k < d {
                if xr[row * d + k] != xr[u[j] * d + k] { e = false }
                k += 1usize
            }
            if e { same = true } else { j += 1usize }
        }
        if !same {
            u[un] = row
            un += 1usize
        }
        i += 1usize
    }
    if un <= d { ret true }
    let f0 = ts.z[ts.idx[id * ts.n]]
    var j2 = 1usize
    while j2 < n {
        if f0 != ts.z[ts.idx[id * ts.n + j2]] { j2 = n + 1usize } else { j2 += 1usize }
    }
    if j2 == n { ret true }
    ret false
}

// Tree::wellSized
fn well_sized(ts: *TS, id: usize) -> bool {
    if ts.cnt[id] <= ts.minpart { ret false }
    if ts.col == 1usize { ret true }
    var area = 1.0f64
    var i = 0usize
    while i < ts.d {
        area = area * (ts.hi[id * ts.d + i] - ts.lo[id * ts.d + i])
        i += 1usize
    }
    if !(area > 0.0f64) { ret false }
    ret !singular(ts, id)
}

// Tree::grow_child: the child over rows of `node` with x[var] <= val (LEQ) or > val (GT); NONE when it is empty
fn grow_child(ts: *TS, node: usize, op_gt: bool) -> (usize, usize) {
    let d = ts.d
    let v = ts.vr[node]
    let val = ts.vl[node]
    var plen = 0usize
    var i = 0usize
    while i < ts.cnt[node] {
        let x = ts.xn[ts.idx[node * ts.n + i] * d + v]
        if op_gt {
            if x > val { plen += 1usize }
        } else {
            if x <= val { plen += 1usize }
        }
        i += 1usize
    }
    if plen == 0usize { ret (NONE, 0usize) }
    let c = new_node(ts, node)
    var k = 0usize
    i = 0usize
    while i < ts.cnt[node] {
        let row = ts.idx[node * ts.n + i]
        let x = ts.xn[row * d + v]
        var inn = false
        if op_gt { inn = x > val } else { inn = x <= val }
        if inn {
            ts.idx[c * ts.n + k] = row
            k += 1usize
        }
        i += 1usize
    }
    ts.cnt[c] = plen
    var j = 0usize
    while j < d {
        ts.lo[c * d + j] = ts.lo[node * d + j]
        ts.hi[c * d + j] = ts.hi[node * d + j]
        ts.gt[c * d + j] = ts.gt[node * d + j]
        j += 1usize
    }
    if op_gt {
        ts.gt[c * d + v] = 1usize
        ts.lo[c * d + v] = val
    } else {
        ts.hi[c * d + v] = val
    }
    ret (c, plen)
}

// Tree::grow_children
fn grow_children(ts: *TS, id: usize) -> bool {
    let (l, pl) = grow_child(ts, id, false)
    if pl == 0usize || !well_sized(ts, l) {
        free_tree(ts, l)
        ts.lc[id] = NONE
        ts.rc[id] = NONE
        ret false
    }
    ts.lc[id] = l
    let (r, pr) = grow_child(ts, id, true)
    if pr == 0usize || !well_sized(ts, r) {
        free_tree(ts, l)
        free_tree(ts, r)
        ts.lc[id] = NONE
        ts.rc[id] = NONE
        ret false
    }
    ts.rc[id] = r
    ret true
}

// ---- split-point proposal (Tree::val_order_probs, TRIANGULAR) ----

fn val_order_probs(ts: *TS, id: usize, v: usize) {
    let rn = ts.nsplit
    let d = ts.d
    let lo = ts.lo[id * d + v]
    let hi = ts.hi[id * d + v]
    let mid = (hi + lo) / 2.0f64
    var i = 0usize
    while i < rn {
        let df = ts.xs[i * d + v] - mid
        ts.xmm[i] = df * df
        ts.ord[i] = i
        i += 1usize
    }
    // order(): ascending, ties by index
    i = 1usize
    while i < rn {
        let o = ts.ord[i]
        let key = ts.xmm[o]
        var j = i
        while j > 0usize && ts.xmm[ts.ord[j - 1usize]] > key {
            ts.ord[j] = ts.ord[j - 1usize]
            j -= 1usize
        }
        ts.ord[j] = o
        i += 1usize
    }
    var sl = 0.0f64
    var sr = 0.0f64
    i = 0usize
    while i < rn {
        let x = ts.xs[ts.ord[i] * d + v]
        ts.xo[i] = x
        if x < lo || x >= hi { ts.pr[i] = 0.0f64 } else { ts.pr[i] = 1.0f64 / f64(i + 1usize) }
        if x < mid { sl += ts.pr[i] } else { sr += ts.pr[i] }
        i += 1usize
    }
    var mult = 1.0f64
    if sl > 0.0f64 && sr > 0.0f64 { mult = 0.5f64 }
    i = 0usize
    while i < rn {
        if ts.pr[i] != 0.0f64 {
            if ts.xo[i] < mid { ts.pr[i] = mult * ts.pr[i] / sl } else { ts.pr[i] = mult * ts.pr[i] / sr }
        }
        i += 1usize
    }
}

// Tree::propose_split: (value, probability)
fn propose_split(ts: *TS, id: usize, rk: *tgp.Rk) -> (f64, f64) {
    val_order_probs(ts, id, ts.vr[id])
    var c = ts.pr[0usize]
    ts.cum[0usize] = c
    var i = 1usize
    while i < ts.nsplit {
        c += ts.pr[i]
        ts.cum[i] = c
        i += 1usize
    }
    if ts.cum[ts.nsplit - 1usize] < 1.0f64 { ts.cum[ts.nsplit - 1usize] = 1.0f64 }
    let k = pick_cum(rk, ts.cum, ts.nsplit)
    ret (ts.xo[k], ts.pr[k])
}

// Tree::split_prob: log probability of the node's current split
fn split_prob(ts: *TS, id: usize) -> f64 {
    val_order_probs(ts, id, ts.vr[id])
    var i = 0usize
    while i < ts.nsplit {
        if ts.xo[i] == ts.vl[id] { ret lg(ts.pr[i]) }
        i += 1usize
    }
    ret lg(0.0f64)
}

// ---- the correlation parameters at a split / combine / match (ExpSep::Split, Combine; Gp::Split, Combine) ----

// linear_rand_sep for the node's d: the booleans b, then d_eff = d * b and the LLM flag
fn lin_rand_node(ts: *TS, rk: *tgp.Rk, id: usize) {
    var all = true
    var j = 0usize
    while j < ts.d {
        if ts.gam0 == 0.0f64 {
            ts.gx[id].bv[j] = 1i64
            all = false
        } else {
            let pb = ts.gam1 + ts.gam2 / (1.0f64 + math.exp[f64](0.0f64 - ts.gam0 * (ts.gx[id].dv[j] - 0.5f64)))
            if tgp.runi(rk) < pb {
                ts.gx[id].bv[j] = 0i64
            } else {
                ts.gx[id].bv[j] = 1i64
                all = false
            }
        }
        ts.gx[id].deff[j] = ts.gx[id].dv[j] * f64(ts.gx[id].bv[j])
        j += 1usize
    }
    ts.gx[id].linear = all
}

// d_prior_rand: the default mixture of Gamma(1, 20) and Gamma(10, 10)
fn d_prior_draw(rk: *tgp.Rk) -> f64 {
    var dr = 0.0f64
    if tgp.runi(rk) < 0.5f64 {
        dr = lm.rgamma_wb(rk, 1.0f64, 20.0f64)
        if dr == 0.0f64 { dr = 1.0f64 / 20.0f64 }
    } else {
        dr = lm.rgamma_wb(rk, 10.0f64, 10.0f64)
        if dr == 0.0f64 { dr = 1.0f64 }
    }
    ret dr
}

fn gp_split(ts: *TS, id: usize, l: usize, r: usize, rk: *tgp.Rk) {
    let u = tgp.runi(rk)
    var i0 = 0usize
    var i1 = 1usize
    if !(u <= 0.5f64) {
        i0 = 1usize
        i1 = 0usize
    }
    var dn: [32]f64 = zero
    var j = 0usize
    while j < ts.d {
        dn[i0 * 16usize + j] = ts.gx[id].dv[j]
        j += 1usize
    }
    j = 0usize
    while j < ts.d {
        dn[i1 * 16usize + j] = d_prior_draw(rk)
        j += 1usize
    }
    j = 0usize
    while j < ts.d {
        ts.gx[l].dv[j] = dn[j]
        ts.gx[r].dv[j] = dn[16usize + j]
        j += 1usize
    }
    lin_rand_node(ts, rk, l)
    lin_rand_node(ts, rk, r)
    // Corr::SplitNug: one child keeps the nugget, the other draws from the prior (nug.p = (1, 1, 1, 1))
    let u2 = tgp.runi(rk)
    var n0 = 0usize
    if !(u2 <= 0.5f64) { n0 = 1usize }
    var ng = 0.0f64
    if tgp.runi(rk) < 0.5f64 { ng = lm.rgamma_wb(rk, 1.0f64, 1.0f64) } else { ng = lm.rgamma_wb(rk, 1.0f64, 1.0f64) }
    if ng == 0.0f64 { ng = 1.0f64 }
    ng += 0.0000000001f64
    ts.gx[l].nug = ts.gx[id].nug
    ts.gx[r].nug = ts.gx[id].nug
    if n0 == 0usize { ts.gx[r].nug = ng } else { ts.gx[l].nug = ng }
    let _t = tgp.runi(rk)
}

fn gp_combine(ts: *TS, id: usize, l: usize, r: usize, rk: *tgp.Rk) {
    var c = l
    if !(tgp.runi(rk) <= 0.5f64) { c = r }
    ts.gx[id].dv = ts.gx[c].dv
    lin_rand_node(ts, rk, id)
    var c2 = l
    if !(tgp.runi(rk) <= 0.5f64) { c2 = r }
    ts.gx[id].nug = ts.gx[c2].nug
    let _t = tgp.runi(rk)
}

fn gp_match(ts: *TS, nw: usize, old: usize) {
    if !ts.gmode { ret }
    ts.gx[nw].dv = ts.gx[old].dv
    ts.gx[nw].bv = ts.gx[old].bv
    ts.gx[nw].deff = ts.gx[old].deff
    ts.gx[nw].nug = ts.gx[old].nug
    ts.gx[nw].linear = ts.gx[old].linear
}

// ---- Tree::grow / prune ----

fn tree_grow(ts: *TS, id: usize, ratio: f64, rk: *tgp.Rk) -> bool {
    ts.tree_op = 1i64
    var v = 0usize
    if ts.d > 1usize { v = sample_idx(ts, rk, ts.d) }
    ts.vr[id] = v
    if ts.lo[id * ts.d + v] == ts.hi[id * ts.d + v] { ret false }
    let (val, qf) = propose_split(ts, id, rk)
    ts.vl[id] = val
    let logp_split = 0.0f64 - lg(f64(ts.nsplit))
    if !grow_children(ts, id) { ret false }
    // Gp::Split: under the forced LLM the d index and the tau2 index
    if ts.gmode {
        gp_split(ts, id, ts.lc[id], ts.rc[id], rk)
    } else {
        let _u1 = tgp.runi(rk)
        let _u2 = tgp.runi(rk)
    }
    let pk =leaf_post(ts, ts.lc[id]) + leaf_post(ts, ts.rc[id])
    let pklast = leaf_post(ts, id)
    let alpha = ratio * math.exp[f64](pk - pklast + logp_split) / qf
    if tgp.runi(rk) > alpha {
        free_tree(ts, ts.lc[id])
        free_tree(ts, ts.rc[id])
        ts.lc[id] = NONE
        ts.rc[id] = NONE
        ret false
    }
    clear_g(ts, id)
    ret true
}

fn tree_prune(ts: *TS, id: usize, ratio: f64, rk: *tgp.Rk) -> bool {
    ts.tree_op = 2i64
    let pklast = leaves_post(ts, id, ts.l4)
    let logq_bak = split_prob(ts, id)
    let logp_split = 0.0f64 - lg(f64(ts.nsplit))
    // Gp::Combine: the d index, the nugget index, the tau2 index
    if ts.gmode {
        gp_combine(ts, id, ts.lc[id], ts.rc[id], rk)
    } else {
        let _u1 = tgp.runi(rk)
        let _u2 = tgp.runi(rk)
        let _u3 = tgp.runi(rk)
    }
    leaf_update(ts, id)
    let pk = post_rj(ts, id)
    let alpha = ratio * math.exp[f64](logq_bak + pk - pklast - logp_split)
    if tgp.runi(rk) < alpha {
        free_tree(ts, ts.lc[id])
        free_tree(ts, ts.rc[id])
        ts.lc[id] = NONE
        ts.rc[id] = NONE
        ret true
    }
    clear_g(ts, id)
    ret false
}

// ---- match / change / swap / rotate ----

fn tree_match(ts: *TS, nw: usize, old: usize, rk: *tgp.Rk) -> bool {
    if ts.lc[old] == NONE {
        gp_match(ts, nw, old)
        ret true
    }
    ts.vr[nw] = ts.vr[old]
    ts.vl[nw] = ts.vl[old]
    clear_g(ts, nw)
    if grow_children(ts, nw) {
        if !tree_match(ts, ts.lc[nw], ts.lc[old], rk) { ret false }
        if !tree_match(ts, ts.rc[nw], ts.rc[old], rk) { ret false }
        ret true
    }
    if ts.tree_op != 3i64 { ret false }
    // CPRUNEOP: growing failed on a small partition, adopt a subtree of the old node instead
    ts.tree_op = 5i64
    let ol = ts.lc[old]
    let orr = ts.rc[old]
    if ts.lc[orr] != NONE { ret tree_match(ts, nw, orr, rk) }
    if ts.lc[ol] != NONE { ret tree_match(ts, nw, ol, rk) }
    if tgp.runi(rk) > 0.5f64 { ret tree_match(ts, nw, ol, rk) }
    ret tree_match(ts, nw, orr, rk)
}

// Tree::try_revert on a failure: the new children go, the old ones come back
fn revert(ts: *TS, id: usize, olc: usize, orc: usize, ovar: usize, oval: f64) {
    ts.vl[id] = oval
    ts.vr[id] = ovar
    if ts.lc[id] != NONE { free_tree(ts, ts.lc[id]) }
    if ts.rc[id] != NONE { free_tree(ts, ts.rc[id]) }
    ts.lc[id] = olc
    ts.rc[id] = orc
}

fn propose_val(ts: *TS, id: usize, rk: *tgp.Rk) -> f64 {
    let v = ts.vr[id]
    let val = ts.vl[id]
    var mn = 1.0f64 / 0.0f64
    var mx = 0.0f64 - 1.0f64 / 0.0f64
    var i = 0usize
    while i < ts.nsplit {
        let x = ts.xs[i * ts.d + v]
        if x > val && x < mn {
            mn = x
        } else {
            if x < val && x > mx { mx = x }
        }
        i += 1usize
    }
    if tgp.runi(rk) < 0.5f64 { ret mn }
    ret mx
}

fn tree_change(ts: *TS, id: usize, rk: *tgp.Rk) -> bool {
    ts.tree_op = 3i64
    let oval = ts.vl[id]
    let ovar = ts.vr[id]
    ts.vl[id] = propose_val(ts, id, rk)
    let olc = ts.lc[id]
    let orc = ts.rc[id]
    ts.lc[id] = NONE
    ts.rc[id] = NONE
    let (l, pl) = grow_child(ts, id, false)
    ts.lc[id] = l
    if pl == 0usize || !well_sized(ts, l) {
        revert(ts, id, olc, orc, ovar, oval)
        ret false
    }
    let (r, pr) = grow_child(ts, id, true)
    ts.rc[id] = r
    if pr == 0usize || !well_sized(ts, r) {
        revert(ts, id, olc, orc, ovar, oval)
        ret false
    }
    if !tree_match(ts, l, olc, rk) {
        revert(ts, id, olc, orc, ovar, oval)
        ret false
    }
    if !tree_match(ts, r, orc, rk) {
        revert(ts, id, olc, orc, ovar, oval)
        ret false
    }
    let pklast = leaves_post(ts, olc, ts.l4) + leaves_post(ts, orc, ts.l4)
    let pk = leaves_post(ts, id, ts.l4)
    let alpha = math.exp[f64](pk - pklast)
    if tgp.runi(rk) < alpha {
        free_tree(ts, olc)
        free_tree(ts, orc)
        ret true
    }
    revert(ts, id, olc, orc, ovar, oval)
    ret false
}

// Tree::pT_rotate
fn pt_rotate(ts: *TS, low: usize, high: usize) -> f64 {
    let lni = collect_internals(ts, low, ts.l1, 0usize)
    let lnl = collect_leaves(ts, low, ts.l2, 0usize)
    let hni = collect_internals(ts, high, ts.l3, 0usize)
    let hnl = collect_leaves(ts, high, ts.l4, 0usize)
    let al = ts.talpha
    let be = ts.tbeta
    var p = 0.0f64
    var i = 0usize
    while i < lni {
        p += lg(al) - be * lg(1.0f64 + f64(ts.dep[ts.l1[i]]))
        i += 1usize
    }
    i = 0usize
    while i < lnl {
        p += lg(1.0f64 - al * math.pow[f64](1.0f64 + f64(ts.dep[ts.l2[i]]), 0.0f64 - be))
        i += 1usize
    }
    i = 0usize
    while i < hni {
        p += lg(al) - be * lg(1.0f64 + f64(ts.dep[ts.l3[i]]))
        i += 1usize
    }
    i = 0usize
    while i < hnl {
        p += lg(1.0f64 - al * math.pow[f64](1.0f64 + f64(ts.dep[ts.l4[i]]), 0.0f64 - be))
        i += 1usize
    }
    var ps = 0.0f64
    i = 0usize
    while i < lni {
        ps += lg(al) - be * lg(f64(ts.dep[ts.l1[i]]))
        i += 1usize
    }
    i = 0usize
    while i < lnl {
        ps += lg(1.0f64 - al * math.pow[f64](f64(ts.dep[ts.l2[i]]), 0.0f64 - be))
        i += 1usize
    }
    i = 0usize
    while i < hni {
        ps += lg(al) - be * lg(2.0f64 + f64(ts.dep[ts.l3[i]]))
        i += 1usize
    }
    i = 0usize
    while i < hnl {
        ps += lg(1.0f64 - al * math.pow[f64](2.0f64 + f64(ts.dep[ts.l4[i]]), 0.0f64 - be))
        i += 1usize
    }
    let a = math.exp[f64](ps - p)
    if a >= 1.0f64 { ret 1.0f64 }
    ret a
}

// Tree::swapData: `id` takes the data of its old parent pt, and pt gets the part of it on the side of id's split
fn swap_data(ts: *TS, id: usize, pt: usize) {
    let d = ts.d
    let n = ts.n
    // the partition of pt: id's split over pt's data, LEQ unless pt is now the right child
    var op_gt = false
    if ts.rc[id] == pt { op_gt = true }
    var tmp: [4096]usize = zero
    var k = 0usize
    var i = 0usize
    while i < ts.cnt[pt] {
        let row = ts.idx[pt * n + i]
        let x = ts.xn[row * d + ts.vr[id]]
        var inn = false
        if op_gt { inn = x > ts.vl[id] } else { inn = x <= ts.vl[id] }
        if inn {
            tmp[k] = row
            k += 1usize
        }
        i += 1usize
    }
    // id gets pt's data and rectangle
    i = 0usize
    while i < ts.cnt[pt] {
        ts.idx[id * n + i] = ts.idx[pt * n + i]
        i += 1usize
    }
    ts.cnt[id] = ts.cnt[pt]
    var rl: [16]f64 = zero
    var rh: [16]f64 = zero
    var rg: [16]usize = zero
    var j = 0usize
    while j < d {
        ts.lo[id * d + j] = ts.lo[pt * d + j]
        ts.hi[id * d + j] = ts.hi[pt * d + j]
        ts.gt[id * d + j] = ts.gt[pt * d + j]
        rl[j] = ts.lo[pt * d + j]
        rh[j] = ts.hi[pt * d + j]
        rg[j] = ts.gt[pt * d + j]
        j += 1usize
    }
    // pt: the new child of id
    i = 0usize
    while i < k {
        ts.idx[pt * n + i] = tmp[i]
        i += 1usize
    }
    ts.cnt[pt] = k
    j = 0usize
    while j < d {
        ts.lo[pt * d + j] = rl[j]
        ts.hi[pt * d + j] = rh[j]
        ts.gt[pt * d + j] = rg[j]
        j += 1usize
    }
    if op_gt {
        ts.gt[pt * d + ts.vr[id]] = 1usize
        ts.lo[pt * d + ts.vr[id]] = ts.vl[id]
    } else {
        ts.hi[pt * d + ts.vr[id]] = ts.vl[id]
    }
}

fn rotate_right(ts: *TS, id: usize) {
    let pt = ts.par[id]
    let gp = ts.par[pt]
    if gp != NONE {
        if ts.lc[gp] == pt { ts.lc[gp] = id } else { ts.rc[gp] = id }
    } else {
        ts.root = id
    }
    ts.par[id] = gp
    ts.lc[pt] = ts.rc[id]
    ts.par[ts.lc[pt]] = pt
    ts.rc[id] = pt
    ts.par[pt] = id
    ts.dep[pt] += 1usize
    ts.dep[id] -= 1usize
    adjust_depth(ts, ts.lc[id], 0i64 - 1i64)
    adjust_depth(ts, ts.rc[pt], 1i64)
    swap_data(ts, id, pt)
    clear_g(ts, id)
    clear_g(ts, pt)
}

fn rotate_left(ts: *TS, id: usize) {
    let pt = ts.par[id]
    let gp = ts.par[pt]
    if gp != NONE {
        if ts.rc[gp] == pt { ts.rc[gp] = id } else { ts.lc[gp] = id }
    } else {
        ts.root = id
    }
    ts.par[id] = gp
    ts.rc[pt] = ts.lc[id]
    ts.par[ts.rc[pt]] = pt
    ts.lc[id] = pt
    ts.par[pt] = id
    ts.dep[pt] += 1usize
    ts.dep[id] -= 1usize
    adjust_depth(ts, ts.rc[id], 0i64 - 1i64)
    adjust_depth(ts, ts.lc[pt], 1i64)
    swap_data(ts, id, pt)
    clear_g(ts, id)
    clear_g(ts, pt)
}

fn tree_rotate(ts: *TS, id: usize, rk: *tgp.Rk) -> bool {
    ts.tree_op = 4i64
    let pt = ts.par[id]
    if ts.rc[pt] == id {
        let alpha = pt_rotate(ts, ts.rc[id], ts.lc[pt])
        if tgp.runi(rk) < alpha {
            rotate_left(ts, id)
            ret true
        }
        ret false
    }
    let alpha2 = pt_rotate(ts, ts.lc[id], ts.rc[pt])
    if tgp.runi(rk) < alpha2 {
        rotate_right(ts, id)
        ret true
    }
    ret false
}

fn tree_swap(ts: *TS, id: usize, rk: *tgp.Rk) -> bool {
    ts.tree_op = 4i64
    let pt = ts.par[id]
    if ts.vr[pt] == ts.vr[id] { ret tree_rotate(ts, id, rk) }
    let pval = ts.vl[pt]
    let pvar = ts.vr[pt]
    let oval = ts.vl[id]
    let ovar = ts.vr[id]
    let oplc = ts.lc[pt]
    let oprc = ts.rc[pt]
    ts.vl[pt] = oval
    ts.vl[id] = pval
    ts.vr[pt] = ovar
    ts.vr[id] = pvar
    ts.lc[pt] = NONE
    ts.rc[pt] = NONE
    if !grow_children(ts, pt) {
        ts.lc[pt] = oplc
        ts.rc[pt] = oprc
        ts.vl[pt] = pval
        ts.vr[pt] = pvar
        ts.vl[id] = oval
        ts.vr[id] = ovar
        ret false
    }
    if !tree_match(ts, ts.lc[pt], oplc, rk) {
        revert(ts, pt, oplc, oprc, pvar, pval)
        ts.vl[id] = oval
        ts.vr[id] = ovar
        ret false
    }
    if !tree_match(ts, ts.rc[pt], oprc, rk) {
        revert(ts, pt, oplc, oprc, pvar, pval)
        ts.vl[id] = oval
        ts.vr[id] = ovar
        ret false
    }
    let pklast = leaves_post(ts, oprc, ts.l4) + leaves_post(ts, oplc, ts.l4)
    let pk = leaves_post(ts, pt, ts.l4)
    let alpha = math.exp[f64](pk - pklast)
    if tgp.runi(rk) < alpha {
        free_tree(ts, oprc)
        free_tree(ts, oplc)
        ret true
    }
    revert(ts, pt, oplc, oprc, pvar, pval)
    ts.vl[id] = oval
    ts.vr[id] = ovar
    ret false
}

// ---- Model::modify_tree ----

fn num_leaves(ts: *TS) -> usize { ret collect_leaves(ts, ts.root, ts.ll, 0usize) }

fn model_grow(ts: *TS, rk: *tgp.Rk) {
    if ts.talpha == 0.0f64 || ts.tbeta == 0.0f64 { ret }
    let len = collect_leaves(ts, ts.root, ts.ll, 0usize)
    let qf = 1.0f64 / f64(len)
    let k = sample_idx(ts, rk, len)
    let node = ts.ll[k]
    let np = f64(collect_prunable(ts, ts.root, ts.l3, 0usize))
    var qb = 1.0f64 / np
    let pk = ts.par[node]
    if pk == NONE {
        qb = 1.0f64 / (np + 1.0f64)
    } else {
        if is_prunable(ts, pk) { qb = 1.0f64 / (np + 1.0f64) }
    }
    let depth = f64(ts.dep[node])
    let pet = ts.talpha * math.pow[f64](1.0f64 + depth, 0.0f64 - ts.tbeta)
    let pect = ts.talpha * math.pow[f64](1.0f64 + depth + 1.0f64, 0.0f64 - ts.tbeta)
    let diff = 1.0f64 - pect
    let ptr = pet * (diff * diff) / (1.0f64 - pet)
    let ok1 = tree_grow(ts, node, (qb / qf) * ptr, rk)
    ts.tries[0usize] += 1usize
    if ok1 { ts.wins[0usize] += 1usize }
}

fn model_prune(ts: *TS, rk: *tgp.Rk) {
    let len = collect_prunable(ts, ts.root, ts.ll, 0usize)
    if len == 0usize { ret }
    let qf = 1.0f64 / f64(len)
    let nl = collect_leaves(ts, ts.root, ts.l3, 0usize)
    let qb = 1.0f64 / f64(nl - 1usize)
    let k = sample_idx(ts, rk, len)
    let node = ts.ll[k]
    let depth = f64(ts.dep[node] + 1usize)
    let pet = ts.talpha * math.pow[f64](1.0f64 + depth, 0.0f64 - ts.tbeta)
    let pept = ts.talpha * math.pow[f64](1.0f64 + depth - 1.0f64, 0.0f64 - ts.tbeta)
    let diff = 1.0f64 - pet
    let ptr = (1.0f64 - pept) / ((diff * diff) * pept)
    let ok1 = tree_prune(ts, node, (qb / qf) * ptr, rk)
    ts.tries[1usize] += 1usize
    if ok1 { ts.wins[1usize] += 1usize }
}

fn model_change(ts: *TS, rk: *tgp.Rk) {
    let len = collect_internals(ts, ts.root, ts.ll, 0usize)
    if len == 0usize { ret }
    let k = sample_idx(ts, rk, len)
    let ok1 = tree_change(ts, ts.ll[k], rk)
    ts.tries[2usize] += 1usize
    if ok1 { ts.wins[2usize] += 1usize }
}

fn model_swap(ts: *TS, rk: *tgp.Rk) {
    let len = collect_swapable(ts, ts.root, ts.ll, 0usize)
    if len == 0usize { ret }
    let k = sample_idx(ts, rk, len)
    let ok1 = tree_swap(ts, ts.ll[k], rk)
    ts.tries[3usize] += 1usize
    if ok1 { ts.wins[3usize] += 1usize }
}

fn modify_tree(ts: *TS, rk: *tgp.Rk) {
    // isample over the actions with probabilities 1/5, 1/5, 2/5, 1/5
    var cum: [4]f64 = zero
    cum[0usize] = 0.2f64
    cum[1usize] = cum[0usize] + 0.2f64
    cum[2usize] = cum[1usize] + 0.4f64
    cum[3usize] = cum[2usize] + 0.2f64
    if cum[3usize] < 1.0f64 { cum[3usize] = 1.0f64 }
    let act = pick_cum(rk, cum[0usize..4usize], 4usize)
    if act == 0usize { model_grow(ts, rk) }
    if act == 1usize { model_prune(ts, rk) }
    if act == 2usize { model_change(ts, rk) }
    if act == 3usize { model_swap(ts, rk) }
}

// ---- the hyper-prior step of Gp_Prior::Draw: sigma2_prior_draw over every leaf ----

fn s2_hyper(ts: *TS, leaves: []const usize, nl: usize, rk: *tgp.Rk) {
    let (r1, qf, qb) = lm.unif_propose_pos(rk, ts.a0 - 2.0f64)
    let a0n = 2.0f64 + r1
    var lp = 0.0f64
    var i = 0usize
    while i < nl {
        let s2 = ts.gx[leaves[i]].g.s2
        lp += lm.invgam_lp(s2, a0n / 2.0f64, ts.g0 / 2.0f64)
        lp -= lm.invgam_lp(s2, ts.a0 / 2.0f64, ts.g0 / 2.0f64)
        i += 1usize
    }
    lp += lm.gam_lp(a0n, 1.0f64, 0.2f64)
    lp -= lm.gam_lp(ts.a0, 1.0f64, 0.2f64)
    let al = math.exp[f64](lp) * qb / qf
    if tgp.runi(rk) < al { ts.a0 = a0n }
    let (r2, qf2, qb2) = lm.unif_propose_pos(rk, ts.g0 - 0.0000000001f64)
    let g0n = r2 + 0.0000000001f64
    var lp2 = 0.0f64
    i = 0usize
    while i < nl {
        let s2 = ts.gx[leaves[i]].g.s2
        lp2 += lm.invgam_lp(s2, ts.a0 / 2.0f64, g0n / 2.0f64)
        lp2 -= lm.invgam_lp(s2, ts.a0 / 2.0f64, ts.g0 / 2.0f64)
        i += 1usize
    }
    lp2 += lm.gam_lp(g0n, 1.0f64, 10.0f64)
    lp2 -= lm.gam_lp(ts.g0, 1.0f64, 10.0f64)
    let al2 = math.exp[f64](lp2) * qb2 / qf2
    if tgp.runi(rk) < al2 { ts.g0 = g0n }
}

// ---- Tree::Predict at one leaf ----

fn predict_leaf(ts: *TS, run: *lm.Run, rk: *tgp.Rk, id: usize, row: usize, nn: usize, pred_n: bool, improv_on: bool, ds2x_on: bool, ppl: []usize, ffl: []f64, wz: usize) {
    let n = ts.n
    let d = ts.d
    let col = ts.col
    let nl = ts.cnt[id]
    var m = 0usize
    var q = 0usize
    while q < nn {
        var inn = true
        var j = 0usize
        while j < d && inn {
            let x = run.xxn[q * d + j]
            if ts.gt[id * d + j] == 1usize {
                inn = x > ts.lo[id * d + j] && x <= ts.hi[id * d + j]
            } else {
                inn = x >= ts.lo[id * d + j] && x <= ts.hi[id * d + j]
            }
            j += 1usize
        }
        if inn {
            ppl[m] = q
            m += 1usize
        }
        q += 1usize
    }
    if m == 0usize && !pred_n { ret }
    var g = ts.gx[id].g
    g.kd = 1.0f64 + ts.gx[id].nug
    g.a0 = ts.a0
    g.g0 = ts.g0
    var inp = false
    var i = 0usize
    while i < nl {
        if ts.idx[id * n + i] == wz { inp = true }
        i += 1usize
    }
    let w1 = run.w1
    let w2 = run.w2
    let w3 = run.w3
    let w4 = run.w4
    let ez1 = run.ez1
    if pred_n {
        lm.predict_linear(&g, g.f, nl, w1, w2, run.dsr, false)
        i = 0usize
        while i < nl {
            run.zpm[row * n + ts.idx[id * n + i]] = w1[i]
            run.zps[row * n + ts.idx[id * n + i]] = w2[i]
            i += 1usize
        }
        lm.predict_draw(rk, run.zpz, w1, w2, nl)
        i = 0usize
        while i < nl {
            run.zpd[row * n + ts.idx[id * n + i]] = run.zpz[i]
            ez1[i] = w2[i] - g.s2
            i += 1usize
        }
        lm.predict_draw(rk, run.zpvm, w1, ez1, nl)
        i = 0usize
        while i < nl {
            run.zpv[row * n + ts.idx[id * n + i]] = run.zpvm[i]
            i += 1usize
        }
    }
    if m > 0usize {
        i = 0usize
        while i < m {
            ffl[i] = 1.0f64
            var j = 1usize
            while j < col {
                ffl[j * m + i] = run.xxn[ppl[i] * d + (j - 1usize)]
                j += 1usize
            }
            i += 1usize
        }
        lm.predict_linear(&g, ffl, m, w3, w4, run.dsr, ds2x_on)
        i = 0usize
        while i < m {
            run.zzm[row * nn + ppl[i]] = w3[i]
            run.zzs[row * nn + ppl[i]] = w4[i]
            if ds2x_on { run.ds[row * nn + ppl[i]] = run.dsr[i] / f64(nn) }
            i += 1usize
        }
        lm.predict_draw(rk, run.zzz, w3, w4, m)
        i = 0usize
        while i < m {
            run.zzd[row * nn + ppl[i]] = run.zzz[i]
            ez1[i] = w4[i] - g.s2
            i += 1usize
        }
        lm.predict_draw(rk, run.zzvm, w3, ez1, m)
        i = 0usize
        while i < m {
            run.zzv[row * nn + ppl[i]] = run.zzvm[i]
            i += 1usize
        }
        if improv_on {
            if pred_n {
                var fmin = run.zpz[0usize]
                var p = 1usize
                while p < nl {
                    if run.zpz[p] < fmin { fmin = run.zpz[p] }
                    p += 1usize
                }
                if !inp && run.zlow < fmin { fmin = run.zlow }
                i = 0usize
                while i < m {
                    let df = fmin - run.zzz[i]
                    if df > 0.0f64 { run.imp[row * nn + ppl[i]] = df } else { run.imp[row * nn + ppl[i]] = 0.0f64 }
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < m {
                    let zs = math.sqrt[f64](w4[i])
                    let df = run.zlow - w3[i]
                    let st = df / zs
                    let dl = 0.0f64 - 0.91893853320467274f64 - 0.5f64 * (st * st)
                    let dd = math.exp[f64](dl)
                    let pp = dist.pnorm(st, 0.0f64, 1.0f64, true, false)
                    var iv = df * pp + zs * dd
                    if iv < 0.0f64 { iv = 0.0f64 }
                    run.imp[row * nn + ppl[i]] = iv
                    i += 1usize
                }
            }
        }
    }
}

// ---- the full posterior and the best tree of each height (Model::Posterior, register_posterior) ----

// Gp::FullPosterior at a leaf, itemp = 1: the likelihood, the correlation prior and the prior of s2
fn leaf_full(ts: *TS, id: usize) -> f64 {
    let gx = &ts.gx[id]
    let n = gx.g.n
    let col = ts.col
    let lin = !ts.gmode || gx.linear
    var quad = 0.0f64
    let zr = ts.xmm
    var i = 0usize
    while i < n {
        var s = gx.g.z[i]
        var j = 0usize
        while j < col {
            s -= gx.g.f[j * n + i] * gx.g.b[j]
            j += 1usize
        }
        zr[i] = s
        i += 1usize
    }
    var logdet = 0.0f64
    if lin {
        let kd = 1.0f64 + gx.nug
        i = 0usize
        while i < n {
            quad += zr[i] * zr[i] / kd
            i += 1usize
        }
        logdet = f64(n) * lg(kd)
    } else {
        i = 0usize
        while i < n {
            var t = 0.0f64
            var j = 0usize
            while j < n {
                t += gx.ki[i * n + j] * zr[j]
                j += 1usize
            }
            quad += zr[i] * t
            i += 1usize
        }
        logdet = gx.logdet
    }
    let s2 = gx.g.s2
    var post = 0.0f64 - f64(n) * 0.91893853320467274178f64 - 0.5f64 * (logdet + f64(n) * lg(s2)) - 0.5f64 * quad / s2
    if ts.gmode {
        post += gpm.gamma_mix_lp(gx.nug - 0.0000000001f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64)
        post += gpm.log_d_prior(gx.dv, ts.d)
        if ts.gam0 > 0.0f64 {
            var lp = 0.0f64
            var allb = true
            var j = 0usize
            while j < ts.d {
                let pb = ts.gam1 + ts.gam2 / (1.0f64 + math.exp[f64](0.0f64 - ts.gam0 * (gx.dv[j] - 0.5f64)))
                if gx.bv[j] == 0i64 { lp += lg(pb) } else { lp += lg(1.0f64 - pb) }
                j += 1usize
            }
            if gx.linear {
                lp = 0.0f64
                j = 0usize
                while j < ts.d {
                    lp += lg(ts.gam1 + ts.gam2 / (1.0f64 + math.exp[f64](0.0f64 - ts.gam0 * (gx.dv[j] - 0.5f64))))
                    j += 1usize
                }
            }
            post += lp
        }
    }
    post += lm.invgam_lp(s2, ts.a0 / 2.0f64, ts.g0 / 2.0f64)
    ret post
}

fn tree_full(ts: *TS, id: usize) -> f64 {
    let depth = f64(ts.dep[id])
    if ts.lc[id] == NONE {
        ret lg(1.0f64 - ts.talpha * math.pow[f64](1.0f64 + depth, 0.0f64 - ts.tbeta)) + leaf_full(ts, id)
    }
    ret lg(ts.talpha) - ts.tbeta * lg(1.0f64 + depth) + tree_full(ts, ts.lc[id]) + tree_full(ts, ts.rc[id])
}

fn tree_height(ts: *TS, id: usize) -> usize {
    if ts.lc[id] == NONE { ret 1usize }
    let l = tree_height(ts, ts.lc[id])
    let r = tree_height(ts, ts.rc[id])
    if l > r { ret 1usize + l }
    ret 1usize + r
}

// the preorder of the tree into slot h of the map arrays
fn map_store(ts: *TS, id: usize, base: usize, c: usize) -> usize {
    if ts.lc[id] == NONE {
        ts.mp_var[base + c] = NONE
        ts.mp_val[base + c] = 0.0f64
        ret c + 1usize
    }
    let v = ts.vr[id]
    let vn = (ts.rhi[v] - ts.rlo[v]) * ts.vl[id] + ts.rlo[v]
    ts.mp_var[base + c] = v
    // printed with %15f, read back, then tgp.get.trees snaps it to the nearest Xsplit coordinate (the first on a tie)
    let v6 = math.floor[f64](vn * 1000000.0f64 + 0.5f64) / 1000000.0f64
    var best = ts.xorig[v]
    var bd = math.abs[f64](best - v6)
    var xi = 1usize
    while xi < ts.nsplit {
        let dd = math.abs[f64](ts.xorig[xi * ts.d + v] - v6)
        if dd < bd {
            bd = dd
            best = ts.xorig[xi * ts.d + v]
        }
        xi += 1usize
    }
    ts.mp_val[base + c] = best
    let c1 = map_store(ts, ts.lc[id], base, c + 1usize)
    ret map_store(ts, ts.rc[id], base, c1)
}

fn register_posterior(ts: *TS) {
    let hier = lm.gam_lp(ts.a0, 1.0f64, 10.0f64) + lm.gam_lp(ts.g0, 1.0f64, 0.2f64)
    let post = tree_full(ts, ts.root) + hier
    let h = tree_height(ts, ts.root)
    if ts.mp_post[h - 1usize] < post {
        ts.mp_post[h - 1usize] = post
        ts.mp_n[h - 1usize] = map_store(ts, ts.root, (h - 1usize) * ts.nmax, 0usize)
    }
}

// the predictive locations inside the leaf's rectangle, as matrix_constrained reads it
fn xx_members(ts: *TS, run: *lm.Run, id: usize, nn: usize, ppl: []usize) -> usize {
    let d = ts.d
    var m = 0usize
    var q = 0usize
    while q < nn {
        var inn = true
        var j = 0usize
        while j < d && inn {
            let x = run.xxn[q * d + j]
            if ts.gt[id * d + j] == 1usize {
                inn = x > ts.lo[id * d + j] && x <= ts.hi[id * d + j]
            } else {
                inn = x >= ts.lo[id * d + j] && x <= ts.hi[id * d + j]
            }
            j += 1usize
        }
        if inn {
            ppl[m] = q
            m += 1usize
        }
        q += 1usize
    }
    ret m
}

// Tree::Predict at a GP leaf (the LLM leaves go through predict_leaf): ZZ before Zp, as Gp::Predict draws
fn predict_leaf_gp(ts: *TS, run: *lm.Run, rk: *tgp.Rk, id: usize, row: usize, nn: usize, pred_n: bool, improv_on: bool, ds2x_on: bool, ppl: []usize, ffl: []f64, xxl: []f64, wz: usize) {
    let n = ts.n
    let d = ts.d
    let col = ts.col
    let m = xx_members(ts, run, id, nn, ppl)
    if m == 0usize && !pred_n { ret }
    var gm = ts.gx[id]
    let nl = gm.n
    gm.g.a0 = ts.a0
    gm.g.g0 = ts.g0
    var inp = false
    var i = 0usize
    while i < nl {
        if ts.idx[id * n + i] == wz { inp = true }
        i += 1usize
    }
    let ss2 = gm.g.s2
    let nug = gm.nug
    let w1 = run.w1
    let w2 = run.w2
    let w3 = run.w3
    let w4 = run.w4
    let ez1 = run.ez1
    let zmfb = run.w1
    i = 0usize
    while i < nl {
        var s = gm.g.z[i]
        var j = 0usize
        while j < col {
            s -= lm.fz(&gm.g, j, i) * gm.g.bmu[j]
            j += 1usize
        }
        zmfb[i] = s
        i += 1usize
    }
    let kz = run.kz
    i = 0usize
    while i < nl {
        var s = 0.0f64
        var q = 0usize
        while q < nl {
            s += gm.ki[i * nl + q] * zmfb[q]
            q += 1usize
        }
        kz[i] = s
        i += 1usize
    }
    if m > 0usize {
        i = 0usize
        while i < m {
            ffl[i] = 1.0f64
            var j = 0usize
            while j < d {
                xxl[i * d + j] = run.xxn[ppl[i] * d + j]
                j += 1usize
            }
            j = 1usize
            while j < col {
                ffl[j * m + i] = run.xxn[ppl[i] * d + (j - 1usize)]
                j += 1usize
            }
            i += 1usize
        }
        gpm.corr_cross(run.kk, xxl, m, gm.x, nl, d, gm.deff)
        if ds2x_on { gpm.corr_symm(run.kxx, xxl, m, d, gm.deff, nug) }
        i = 0usize
        while i < m {
            var mean = 0.0f64
            var j = 0usize
            while j < col {
                mean += ffl[j * m + i] * gm.g.bmu[j]
                j += 1usize
            }
            var kt = 0.0f64
            var q = 0usize
            while q < nl {
                kt += run.kk[i * nl + q] * kz[q]
                q += 1usize
            }
            w3[i] = mean + kt
            q = 0usize
            while q < nl {
                var s = 0.0f64
                var t = 0usize
                while t < nl {
                    s += gm.ki[q * nl + t] * run.kk[i * nl + t]
                    t += 1usize
                }
                run.rhs[q] = s
                q += 1usize
            }
            var last = 0.0f64
            q = 0usize
            while q < nl {
                last += run.kk[i * nl + q] * run.rhs[q]
                q += 1usize
            }
            var cdiag = 1.0f64 + nug
            if ds2x_on { cdiag = run.kxx[i * m + i] + nug }
            var s2cor = cdiag - last
            var s2v = ss2 * s2cor
            if s2v <= 0.0f64 {
                s2v = 0.0f64
                s2cor = cdiag - 1.0f64
            }
            w4[i] = s2v
            if ds2x_on {
                var tot = 0.0f64
                var y = 0usize
                while y < m {
                    var lt = 0.0f64
                    q = 0usize
                    while q < nl {
                        lt += run.kk[y * nl + q] * run.rhs[q]
                        q += 1usize
                    }
                    let diff = lt - run.kxx[y * m + i]
                    if s2cor > 0.0f64 { tot += ss2 * diff * diff / s2cor }
                    y += 1usize
                }
                run.dsr[i] = tot
            }
            i += 1usize
        }
        i = 0usize
        while i < m {
            run.zzm[row * nn + ppl[i]] = w3[i]
            run.zzs[row * nn + ppl[i]] = w4[i]
            if ds2x_on { run.ds[row * nn + ppl[i]] = run.dsr[i] / f64(nn) }
            i += 1usize
        }
        lm.predict_draw(rk, run.zzz, w3, w4, m)
        i = 0usize
        while i < m {
            run.zzd[row * nn + ppl[i]] = run.zzz[i]
            ez1[i] = w4[i] - ss2 * nug
            i += 1usize
        }
        lm.predict_draw(rk, run.zzvm, w3, ez1, m)
        i = 0usize
        while i < m {
            run.zzv[row * nn + ppl[i]] = run.zzvm[i]
            i += 1usize
        }
    }
    if pred_n {
        i = 0usize
        while i < nl {
            var mean = 0.0f64
            var j = 0usize
            while j < col {
                mean += lm.fz(&gm.g, j, i) * gm.g.bmu[j]
                j += 1usize
            }
            var kt = 0.0f64
            var q = 0usize
            while q < nl {
                var kv = gm.k[i * nl + q]
                if q == i { kv = kv - nug }
                kt += kv * kz[q]
                q += 1usize
            }
            w1[i] = mean + kt
            w2[i] = nug * ss2
            i += 1usize
        }
        i = 0usize
        while i < nl {
            run.zpm[row * n + ts.idx[id * n + i]] = w1[i]
            run.zps[row * n + ts.idx[id * n + i]] = w2[i]
            i += 1usize
        }
        lm.predict_draw(rk, run.zpz, w1, w2, nl)
        i = 0usize
        while i < nl {
            run.zpd[row * n + ts.idx[id * n + i]] = run.zpz[i]
            ez1[i] = w2[i] - ss2 * nug
            i += 1usize
        }
        lm.predict_draw(rk, run.zpvm, w1, ez1, nl)
        i = 0usize
        while i < nl {
            run.zpv[row * n + ts.idx[id * n + i]] = run.zpvm[i]
            i += 1usize
        }
    }
    if improv_on && m > 0usize {
        if pred_n {
            var fmin = run.zpz[0usize]
            var p = 1usize
            while p < nl {
                if run.zpz[p] < fmin { fmin = run.zpz[p] }
                p += 1usize
            }
            if !inp && run.zlow < fmin { fmin = run.zlow }
            i = 0usize
            while i < m {
                let df = fmin - run.zzz[i]
                if df > 0.0f64 { run.imp[row * nn + ppl[i]] = df } else { run.imp[row * nn + ppl[i]] = 0.0f64 }
                i += 1usize
            }
        } else {
            i = 0usize
            while i < m {
                let zs = math.sqrt[f64](w4[i])
                let df = run.zlow - w3[i]
                let st = df / zs
                let dl = 0.0f64 - 0.91893853320467274f64 - 0.5f64 * (st * st)
                let dd = math.exp[f64](dl)
                let pp = dist.pnorm(st, 0.0f64, 1.0f64, true, false)
                var iv = df * pp + zs * dd
                if iv < 0.0f64 { iv = 0.0f64 }
                run.imp[row * nn + ppl[i]] = iv
                i += 1usize
            }
        }
    }
}

// btlm (linear_mean) / bcart (constant mean) under set.seed: x is n x d, xx is nn x d, both row-major
fn treed(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool, pred_n: bool, improv_on: bool, ds2x_on: bool, talpha: f64, tbeta: f64, gmode: bool, gam0: f64, gam1: f64, gam2: f64) -> (Tgt, err) {
    var out: Tgt = zero
    let (run0, es) = lm.setup(a, r, x, z0, xx, n, d, nn, bb, tt, ee, linear_mean, m0r1)
    if es != ok { ret (out, es) }
    var run = run0
    var rk = run.rk
    let col = run.col
    var mp = d + 2usize
    if mp < 10usize { mp = 10usize }
    var nmax = 128usize
    if gmode { nmax = 4usize * (2usize * (n / (mp + 1usize)) + 1usize) + 8usize }
    var ts: TS = zero
    ts.n = n
    ts.d = d
    ts.col = col
    ts.nsplit = n + nn
    ts.gmode = gmode
    ts.gam0 = gam0
    ts.gam1 = gam1
    ts.gam2 = gam2
    ts.minpart = mp
    ts.nmax = nmax
    ts.talpha = talpha
    ts.tbeta = tbeta
    ts.a0 = 5.0f64
    ts.g0 = 10.0f64
    let (par, e1) = zi(a, nmax)
    let (lcc, e2) = zi(a, nmax)
    let (rcc, e3) = zi(a, nmax)
    let (dep, e4) = zi(a, nmax)
    let (vr, e5) = zi(a, nmax)
    let (vl, e6) = lm.zeros(a, nmax)
    let (cnt, e7) = zi(a, nmax)
    let (idx, e8) = zi(a, nmax * n)
    let (lo, e9) = lm.zeros(a, nmax * d)
    let (hi, e10) = lm.zeros(a, nmax * d)
    let (gtt, e11) = zi(a, nmax * d)
    let (gg, e12) = mem.alloc[gpm.Gx](a, nmax)
    var kn = 1usize
    if gmode { kn = nmax * 7usize * n * n }
    let (kbuf, e29) = lm.zeros(a, kn)
    let (xbuf, e30) = lm.zeros(a, nmax * n * d)
    if e29 != ok || e30 != ok { ret (out, lm.BadInput) }
    let (fbuf, e13) = lm.zeros(a, nmax * col * n)
    let (zbuf, e14) = lm.zeros(a, nmax * n)
    let (freel, e15) = zi(a, nmax)
    let (xs, e16) = lm.zeros(a, (n + nn) * d)
    let (xo, e17) = lm.zeros(a, n + nn)
    let (pr, e18) = lm.zeros(a, n + nn)
    let (xmm, e19) = lm.zeros(a, n + nn)
    let (ord, e20) = zi(a, n + nn)
    let (cum, e21) = lm.zeros(a, n + nn + nmax)
    let (l1, e22) = zi(a, nmax)
    let (l2, e23) = zi(a, nmax)
    let (l3, e24) = zi(a, nmax)
    let (l4, e25) = zi(a, nmax)
    let (ll, e26) = zi(a, nmax)
    let (ppl, e27) = zi(a, nn + 1usize)
    let (ffl, e28) = lm.zeros(a, col * (nn + 1usize))
    let (xxl, e31) = lm.zeros(a, d * (nn + 1usize))
    let (rlo, e37) = lm.zeros(a, d)
    let (rhi, e38) = lm.zeros(a, d)
    let (mpp, e39) = lm.zeros(a, nmax)
    let (mpv, e40) = zi(a, nmax * nmax)
    let (mpl, e41) = lm.zeros(a, nmax * nmax)
    let (mpn, e42) = zi(a, nmax)
    if e37 != ok || e38 != ok || e39 != ok || e40 != ok || e41 != ok || e42 != ok { ret (out, lm.BadInput) }
    let (c1, e32) = lm.zeros(a, nn * n)
    let (c2, e33) = lm.zeros(a, nn * nn)
    let (c3, e34) = lm.zeros(a, n)
    let (c4, e35) = lm.zeros(a, n)
    if e31 != ok || e32 != ok || e33 != ok || e34 != ok || e35 != ok { ret (out, lm.BadInput) }
    run.kk = c1
    run.kxx = c2
    run.rhs = c3
    run.kz = c4
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (out, lm.BadInput) }
    if e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok || e25 != ok || e26 != ok || e27 != ok || e28 != ok { ret (out, lm.BadInput) }
    ts.par = par
    ts.lc = lcc
    ts.rc = rcc
    ts.dep = dep
    ts.vr = vr
    ts.vl = vl
    ts.cnt = cnt
    ts.idx = idx
    ts.lo = lo
    ts.hi = hi
    ts.gt = gtt
    ts.gx = gg
    ts.kbuf = kbuf
    ts.xbuf = xbuf
    ts.fbuf = fbuf
    ts.zbuf = zbuf
    ts.freel = freel
    ts.xs = xs
    ts.xo = xo
    ts.pr = pr
    ts.xmm = xmm
    ts.ord = ord
    ts.cum = cum
    ts.l1 = l1
    ts.l2 = l2
    ts.l3 = l3
    ts.l4 = l4
    ts.ll = ll
    ts.xn = run.xn
    ts.rlo = rlo
    ts.rhi = rhi
    ts.mp_post = mpp
    ts.mp_var = mpv
    ts.mp_val = mpl
    ts.mp_n = mpn
    var hi0 = 0usize
    while hi0 < nmax {
        ts.mp_post[hi0] = 0.0f64 - 1.0f64 / 0.0f64
        hi0 += 1usize
    }
    let (xorig, e43) = lm.zeros(a, (n + nn) * d)
    if e43 != ok { ret (out, lm.BadInput) }
    ts.xorig = xorig
    var oi = 0usize
    while oi < n * d {
        ts.xorig[oi] = x[oi]
        oi += 1usize
    }
    oi = 0usize
    while oi < nn * d {
        ts.xorig[n * d + oi] = xx[oi]
        oi += 1usize
    }
    // the rectangle of rbind(X, XX) that Xsplit and the printed trees are scaled by
    var rj = 0usize
    while rj < d {
        ts.rlo[rj] = x[rj]
        ts.rhi[rj] = x[rj]
        var ri = 0usize
        while ri < n + nn {
            var v = 0.0f64
            if ri < n { v = x[ri * d + rj] } else { v = xx[(ri - n) * d + rj] }
            if v < ts.rlo[rj] {
                ts.rlo[rj] = v
            } else {
                if v > ts.rhi[rj] { ts.rhi[rj] = v }
            }
            ri += 1usize
        }
        rj += 1usize
    }
    ts.z = run.g.z
    var i = 0usize
    while i < nmax {
        ts.freel[i] = nmax - 1usize - i
        i += 1usize
    }
    ts.nfree = nmax
    // Xsplit: normalised rbind(X, XX)
    i = 0usize
    while i < n * d {
        ts.xs[i] = run.xn[i]
        i += 1usize
    }
    i = 0usize
    while i < nn * d {
        ts.xs[n * d + i] = run.xxn[i]
        i += 1usize
    }
    // Zmin and its index
    var wz = 0usize
    i = 1usize
    while i < n {
        if ts.z[i] < ts.z[wz] { wz = i }
        i += 1usize
    }
    // the root
    let root = new_node(&ts, NONE)
    ts.root = root
    i = 0usize
    while i < n {
        ts.idx[root * n + i] = i
        i += 1usize
    }
    ts.cnt[root] = n
    var j = 0usize
    while j < d {
        ts.lo[root * d + j] = 0.0f64
        ts.hi[root * d + j] = 1.0f64
        ts.gt[root * d + j] = 0usize
        j += 1usize
    }
    leaf_update(&ts, root)
    let trc = run.trc
    var phase = 0usize
    while phase < 2usize {
        var total = bb
        if phase == 1usize { total = tt - bb }
        var rd = 0usize
        while rd < total {
            if (rd + 1usize) % 4usize == 0usize { modify_tree(&ts, &rk) }
            let nl = collect_leaves(&ts, ts.root, ts.ll, 0usize)
            i = 0usize
            while i < nl {
                let id = ts.ll[i]
                // Gp::Draw at the leaf: two uniforms for the correlation and nugget, then s2 and beta
                ts.gx[id].g.a0 = ts.a0
                ts.gx[id].g.g0 = ts.g0
                if gmode {
                    // Gp::Draw: up to five tries at the correlation draw
                    var success = 0i64
                    var tries = 0usize
                    while tries < 5usize {
                        success = gpm.corr_draw(&ts.gx[id], &rk)
                        if success != 0i64 - 1i64 { tries = 5usize } else { tries += 1usize }
                    }
                    if success < 0i64 { ret (out, gpm.BadChain) }
                } else {
                    let _u1 = tgp.runi(&rk)
                    let _u2 = tgp.runi(&rk)
                }
                lm.draw_s2_beta(&ts.gx[id].g, &rk, run.tmp)
                i += 1usize
            }
            s2_hyper(&ts, ts.ll, nl, &rk)
            i = 0usize
            while i < nl {
                if gmode {
                    gpm.gp_compute(&ts.gx[ts.ll[i]])
                } else {
                    lm.compute(&ts.gx[ts.ll[i]].g)
                }
                i += 1usize
            }
            if phase == 1usize && rd % ee == 0usize {
                let row = rd / ee
                register_posterior(&ts)
                i = 0usize
                while i < nl {
                    if gmode && !ts.gx[ts.ll[i]].linear {
                        predict_leaf_gp(&ts, &run, &rk, ts.ll[i], row, nn, pred_n, improv_on, ds2x_on, ppl, ffl, xxl, wz)
                    } else {
                        predict_leaf(&ts, &run, &rk, ts.ll[i], row, nn, pred_n, improv_on, ds2x_on, ppl, ffl, wz)
                    }
                    i += 1usize
                }
            }
            rd += 1usize
        }
        phase += 1usize
    }
    let (sm, se) = lm.summarize(a, &run, n, nn, pred_n, improv_on, ds2x_on, m0r1)
    if se != ok { ret (out, se) }
    out.b = sm
    var bestp = 0.0f64 - 1.0f64 / 0.0f64
    var nh = 0usize
    var hq = 0usize
    while hq < nmax {
        if ts.mp_n[hq] > 0usize {
            ts.mp_post[nh] = ts.mp_post[hq]
            nh += 1usize
            if ts.mp_post[hq] > bestp {
                bestp = ts.mp_post[hq]
                out.maph = hq
            }
        }
        hq += 1usize
    }
    out.nh = nh
    out.lposts = ts.mp_post
    out.map_n = ts.mp_n[out.maph]
    out.map_var = ts.mp_var[out.maph * nmax..out.maph * nmax + out.map_n]
    out.map_val = ts.mp_val[out.maph * nmax..out.maph * nmax + out.map_n]
    var q = 0usize
    while q < 4usize {
        out.gpcs[q] = f64(ts.wins[q]) / f64(ts.tries[q])
        q += 1usize
    }
    ret (out, ok)
}

fn btlm(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool, pred_n: bool, improv_on: bool, ds2x_on: bool, talpha: f64, tbeta: f64) -> (Tgt, err) {
    let (res, e) = treed(a, r, x, z0, xx, n, d, nn, bb, tt, ee, linear_mean, m0r1, pred_n, improv_on, ds2x_on, talpha, tbeta, false, 0.0f64, 0.0f64, 0.0f64)
    ret (res, e)
}

// btgp (gam0 = 0) and btgpllm (gam0 > 0, gamma = (gam0, gam1, gam2)): the treed GP, the separable exponential correlation
fn btgp(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool, pred_n: bool, improv_on: bool, ds2x_on: bool, talpha: f64, tbeta: f64, gam0: f64, gam1: f64, gam2: f64) -> (Tgt, err) {
    let (res, e) = treed(a, r, x, z0, xx, n, d, nn, bb, tt, ee, linear_mean, m0r1, pred_n, improv_on, ds2x_on, talpha, tbeta, true, gam0, gam1, gam2)
    ret (res, e)
}

// ---- tgp.design on a fit with a tree: the candidates and the data cut by the best tree, dopt.gp in each part ----

fn subtree_end(pv: []const usize, pos: usize) -> usize {
    if pv[pos] == NONE { ret pos + 1usize }
    let e1 = subtree_end(pv, pos + 1usize)
    ret subtree_end(pv, e1)
}

// the ordinal (left to right) of the leaf holding the point x: right of a split when x[var] > val
fn leaf_ordinal(pv: []const usize, pl: []const f64, x: []const f64) -> usize {
    var pos = 0usize
    var ordv = 0usize
    while pv[pos] != NONE {
        if x[pv[pos]] > pl[pos] {
            let e = subtree_end(pv, pos + 1usize)
            var q = pos + 1usize
            while q < e {
                if pv[q] == NONE { ordv += 1usize }
                q += 1usize
            }
            pos = e
        } else {
            pos += 1usize
        }
    }
    ret ordv
}

// the rows with ordinal `which` of the m-wide matrix x (ordinals in xo): the sub-matrix and the row numbers
fn pick_rows(a: *mem.Arena, x: []const f64, xo: []const usize, nrows: usize, m: usize, which: usize) -> ([]f64, []usize, usize, err) {
    var cnt = 0usize
    var i = 0usize
    while i < nrows {
        if xo[i] == which { cnt += 1usize }
        i += 1usize
    }
    let (sub, e1) = lm.zeros(a, cnt * m)
    let (rows, e2) = zi(a, cnt)
    if e1 != ok || e2 != ok { ret (sub, rows, 0usize, lm.BadInput) }
    var k = 0usize
    i = 0usize
    while i < nrows {
        if xo[i] == which {
            var j = 0usize
            while j < m {
                sub[k * m + j] = x[i * m + j]
                j += 1usize
            }
            rows[k] = i
            k += 1usize
        }
        i += 1usize
    }
    ret (sub, rows, cnt, ok)
}

// tgp.design(howmany, Xcand, fit) for a fit whose best tree is (pv, pl) in preorder, iter rounds of the ascent; the
// 1-based candidate numbers of the design rows, in order. The partitions are the non-empty ones, listed separately for
// the data and the candidates and matched by position, as tgp.design does.
fn design_treed(a: *mem.Arena, r: *rr.Rng, howmany: usize, xc: []const f64, ncand: usize, x: []const f64, n: usize, m: usize, pv: []const usize, pl: []const f64, nnodes: usize, iter: usize) -> ([]i64, usize, err) {
    var none: []i64 = zero
    var nleaves = 0usize
    var q = 0usize
    while q < nnodes {
        if pv[q] == NONE { nleaves += 1usize }
        q += 1usize
    }
    let (xo, e1) = zi(a, n)
    let (co, e2) = zi(a, ncand)
    let (xcnt, e3) = zi(a, nleaves)
    let (ccnt, e4) = zi(a, nleaves)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (none, 0usize, lm.BadInput) }
    q = 0usize
    while q < n {
        xo[q] = leaf_ordinal(pv, pl, x[q * m..q * m + m])
        xcnt[xo[q]] += 1usize
        q += 1usize
    }
    q = 0usize
    while q < ncand {
        co[q] = leaf_ordinal(pv, pl, xc[q * m..q * m + m])
        ccnt[co[q]] += 1usize
        q += 1usize
    }
    let (out, e5) = mem.alloc[i64](a, ncand + nleaves + 4usize)
    if e5 != ok { ret (none, 0usize, lm.BadInput) }
    var total = 0usize
    var xk = 0usize
    var ck = 0usize
    var lf = 0usize
    while lf < nleaves {
        if ccnt[lf] > 0usize {
            // the position-matched data part: the (ck)-th non-empty one
            var xl = 0usize
            var seen = 0usize
            var found = false
            while xl < nleaves && !found {
                if xcnt[xl] > 0usize {
                    if seen == ck { found = true } else { seen += 1usize }
                }
                if !found { xl += 1usize }
            }
            if !found { ret (none, 0usize, dz.BadDesign) }
            let nn = usize(math.ceil[f64](f64(howmany * ccnt[lf]) / f64(ncand)))
            if nn > 0usize {
                let (xs, xr, nx, e6) = pick_rows(a, x, xo, n, m, xl)
                let (cs, cr, nc, e7) = pick_rows(a, xc, co, ncand, m, lf)
                if e6 != ok || e7 != ok { ret (none, 0usize, lm.BadInput) }
                let (fi, e8) = dz.dopt_gp(a, r, nn, xs, nx, m, cs, nc, iter)
                if e8 != ok { ret (none, 0usize, e8) }
                var t = 0usize
                while t < nn {
                    out[total] = i64(cr[usize(fi[t] - 1i64)]) + 1i64
                    total += 1usize
                    t += 1usize
                }
            }
            ck += 1usize
        }
        lf += 1usize
    }
    ret (out, total, ok)
}
