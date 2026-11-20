// RcppAnnoy 0.0.23 (Annoy 1.17.3 as the package builds it: single-threaded build, float vectors, 64-bit KISS generator): the same random-projection forest,
// draw for draw, so an index built after set_seed(s) with the same items and tree count is the index R builds, byte for byte in its saved file.
//
// The index is Annoy's own node array in bytes (little endian, node size 12 + 4f for angular, 16 + 4f for euclidean and manhattan, 16 + 8f for hamming), so
// `save` yields the file RcppAnnoy writes and `load` reads one. Metrics: euclidean, angular, manhattan, and hamming (f 64-bit words per item, as a numeric
// vector of integers below 2^53 when it comes from R).
//
// Not here: the dot-product metric, on_disk_build and mmap, multithreaded builds (their draws depend on the thread count), verbose output.
// ponytail: search sorts its candidates by insertion, quadratic in the number of distinct candidates; a heap select when search_k runs to many thousands.

use e.math
use e.mem

error Invalid

const EUCLIDEAN: u8 = 0u8
const ANGULAR: u8 = 1u8
const MANHATTAN: u8 = 2u8
const HAMMING: u8 = 3u8

type Kiss = struct { x: u64, y: u64, z: u64, c: u64 }

type Index = struct {
    metric: u8, f: usize, s: usize, k: usize, off_c: usize, off_v: usize,
    nodes: []u8, cap: usize, n_nodes: usize, n_items: usize,
    roots: []usize, n_roots: usize, seed: u64, loaded: bool, built: bool,
    sv: []f32, sa: f32, sd: u64, pv: []f32, qv: []f32, xa: []f32, xb: []f32, ua: []u64, ub: []u64
}

fn kiss_new(seed: u64) -> Kiss {
    ret Kiss { x: seed, y: 362436362436362436u64, z: 1066149217761810u64, c: 123456123456123456u64 }
}

fn kiss(r: *Kiss) -> u64 {
    r.z = 6906969069u64 *% r.z +% 1234567u64
    r.y = r.y ^ (r.y << 13u64)
    r.y = r.y ^ (r.y >> 17u64)
    r.y = r.y ^ (r.y << 43u64)
    let t = (r.x << 58u64) +% r.c
    r.c = r.x >> 6u64
    r.x = r.x +% t
    if r.x < t { r.c = r.c +% 1u64 }
    ret r.x +% r.y +% r.z
}

fn kiss_index(r: *Kiss, n: usize) -> usize { ret usize(kiss(r) % u64(n)) }

fn kiss_flip(r: *Kiss) -> bool { ret (kiss(r) & 1u64) == 1u64 }

fn rd32(b: []const u8, at: usize) -> u32 {
    ret u32(b[at]) | (u32(b[at + 1usize]) << 8u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 3usize]) << 24u32)
}

fn wr32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v & 255u32)
    b[at + 1usize] = u8((v >> 8u32) & 255u32)
    b[at + 2usize] = u8((v >> 16u32) & 255u32)
    b[at + 3usize] = u8((v >> 24u32) & 255u32)
}

fn rd64(b: []const u8, at: usize) -> u64 { ret u64(rd32(b, at)) | (u64(rd32(b, at + 4usize)) << 32u64) }

fn wr64(b: []u8, at: usize, v: u64) {
    wr32(b, at, u32(v & 4294967295u64))
    wr32(b, at + 4usize, u32(v >> 32u64))
}

fn rdf(b: []const u8, at: usize) -> f32 { ret mem.bitcast[f32](rd32(b, at)) }

fn wrf(b: []u8, at: usize, v: f32) { wr32(b, at, mem.bitcast[u32](v)) }

fn dotf(x: []const f32, y: []const f32, f: usize) -> f32 {
    var s = 0.0f32
    var z = 0usize
    while z < f {
        s += x[z] * y[z]
        z += 1usize
    }
    ret s
}

fn euclid_d(x: []const f32, y: []const f32, f: usize) -> f32 {
    var d = 0.0f32
    var z = 0usize
    while z < f {
        let t = x[z] - y[z]
        d += t * t
        z += 1usize
    }
    ret d
}

fn manhattan_d(x: []const f32, y: []const f32, f: usize) -> f32 {
    var d = 0.0f32
    var z = 0usize
    while z < f {
        d += math.abs[f32](x[z] - y[z])
        z += 1usize
    }
    ret d
}

fn angular_d(x: []const f32, xn: f32, y: []const f32, yn: f32, f: usize) -> f32 {
    var pp = xn
    if xn == 0.0f32 { pp = dotf(x, x, f) }
    var qq = yn
    if yn == 0.0f32 { qq = dotf(y, y, f) }
    let pq = dotf(x, y, f)
    let ppqq = pp * qq
    if ppqq > 0.0f32 { ret f32(2.0f64 - 2.0f64 * f64(pq) / f64(math.sqrt[f32](ppqq))) }
    ret 2.0f32
}

// the raw (squared) distance of the metric; xn and yn are the stored angular norms
fn fdist(ix: *Index, x: []const f32, xn: f32, y: []const f32, yn: f32) -> f32 {
    if ix.metric == ANGULAR { ret angular_d(x, xn, y, yn, ix.f) }
    if ix.metric == MANHATTAN { ret manhattan_d(x, y, ix.f) }
    ret euclid_d(x, y, ix.f)
}

fn popcount(v: u64) -> u64 {
    var c = 0u64
    var x = v
    while x != 0u64 {
        x = x & (x - 1u64)
        c += 1u64
    }
    ret c
}

fn hdist(x: []const u64, y: []const u64, f: usize) -> u64 {
    var d = 0u64
    var z = 0usize
    while z < f {
        d += popcount(x[z] ^ y[z])
        z += 1usize
    }
    ret d
}

fn hmargin(dim: u64, y: []const u64) -> bool {
    let chunk = usize(dim / 64u64)
    ret (y[chunk] & (1u64 << (63u64 - dim % 64u64))) != 0u64
}

fn load_f(ix: *Index, node: usize, dst: []f32) {
    let base = node * ix.s + ix.off_v
    var z = 0usize
    while z < ix.f {
        dst[z] = rdf(ix.nodes, base + 4usize * z)
        z += 1usize
    }
}

fn load_u(ix: *Index, node: usize, dst: []u64) {
    let base = node * ix.s + ix.off_v
    var z = 0usize
    while z < ix.f {
        dst[z] = rd64(ix.nodes, base + 8usize * z)
        z += 1usize
    }
}

fn node_norm(ix: *Index, node: usize) -> f32 {
    if ix.metric == ANGULAR { ret rdf(ix.nodes, node * ix.s + 4usize) }
    ret 0.0f32
}

fn alloc_f(a: *mem.Arena, n: usize) -> ([]f32, err) {
    let (v, e) = mem.alloc[f32](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < v.len {
        v[i] = 0.0f32
        i += 1usize
    }
    ret (v, ok)
}

fn alloc_u(a: *mem.Arena, n: usize) -> ([]u64, err) {
    let (v, e) = mem.alloc[u64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < v.len {
        v[i] = 0u64
        i += 1usize
    }
    ret (v, ok)
}

fn alloc_z(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < v.len {
        v[i] = 0usize
        i += 1usize
    }
    ret (v, ok)
}

fn alloc_b(a: *mem.Arena, n: usize) -> ([]u8, err) {
    let (v, e) = mem.alloc[u8](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < v.len {
        v[i] = 0u8
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

// metric: EUCLIDEAN, ANGULAR, MANHATTAN or HAMMING (f counts 64-bit words); an empty index with the generator's default seed
fn new_index(a: *mem.Arena, metric: u8, f: usize) -> (Index, err) {
    var ix: Index = zero
    if metric > HAMMING || f == 0usize { ret (ix, Invalid) }
    ix.metric = metric
    ix.f = f
    if metric == ANGULAR {
        ix.s = 12usize + 4usize * f
        ix.off_c = 4usize
        ix.off_v = 12usize
    } else {
        if metric == HAMMING {
            ix.s = 16usize + 8usize * f
            ix.off_c = 4usize
        } else {
            ix.s = 16usize + 4usize * f
            ix.off_c = 8usize
        }
        ix.off_v = 16usize
    }
    ix.k = (ix.s - ix.off_c) / 4usize
    ix.seed = 1234567890987654321u64
    let (sv, e1) = alloc_f(a, f)
    let (pv, e2) = alloc_f(a, f)
    let (qv, e3) = alloc_f(a, f)
    let (xa, e4) = alloc_f(a, f)
    let (xb, e5) = alloc_f(a, f)
    let (ua, e6) = alloc_u(a, f)
    let (ub, e7) = alloc_u(a, f)
    if e1 != ok { ret (ix, e1) }
    if e2 != ok { ret (ix, e2) }
    if e3 != ok { ret (ix, e3) }
    if e4 != ok { ret (ix, e4) }
    if e5 != ok { ret (ix, e5) }
    if e6 != ok { ret (ix, e6) }
    if e7 != ok { ret (ix, e7) }
    ix.sv = sv
    ix.pv = pv
    ix.qv = qv
    ix.xa = xa
    ix.xb = xb
    ix.ua = ua
    ix.ub = ub
    ret (ix, ok)
}

fn set_seed(ix: *Index, seed: u64) { ix.seed = seed }

fn n_items(ix: *Index) -> usize { ret ix.n_items }

fn n_trees(ix: *Index) -> usize { ret ix.n_roots }

fn grow(a: *mem.Arena, ix: *Index, n: usize) -> err {
    if n <= ix.cap { ret ok }
    var nc = usize(f64(ix.cap + 1usize) * 1.3f64)
    if nc < n { nc = n }
    let (nb, e) = alloc_b(a, nc * ix.s)
    if e != ok { ret e }
    var i = 0usize
    while i < ix.cap * ix.s {
        nb[i] = ix.nodes[i]
        i += 1usize
    }
    ix.nodes = nb
    ix.cap = nc
    ret ok
}

fn push_root(a: *mem.Arena, ix: *Index, r: usize) -> err {
    if ix.n_roots + 1usize > ix.roots.len {
        let (nr, e) = alloc_z(a, 2usize * ix.roots.len + 8usize)
        if e != ok { ret e }
        var i = 0usize
        while i < ix.n_roots {
            nr[i] = ix.roots[i]
            i += 1usize
        }
        ix.roots = nr
    }
    ix.roots[ix.n_roots] = r
    ix.n_roots += 1usize
    ret ok
}

// the item's vector as R hands it over: f numbers (hamming words below 2^53)
fn add_item(a: *mem.Arena, ix: *Index, item: usize, w: []const f64) -> err {
    if ix.loaded || w.len < ix.f { ret Invalid }
    let ge = grow(a, ix, item + 1usize)
    if ge != ok { ret ge }
    let base = item * ix.s
    wr32(ix.nodes, base, 1u32)
    wr32(ix.nodes, base + ix.off_c, 0u32)
    wr32(ix.nodes, base + ix.off_c + 4usize, 0u32)
    var z = 0usize
    while z < ix.f {
        if ix.metric == HAMMING {
            wr64(ix.nodes, base + ix.off_v + 8usize * z, u64(w[z]))
        } else {
            ix.xa[z] = f32(w[z])
            wrf(ix.nodes, base + ix.off_v + 4usize * z, ix.xa[z])
        }
        z += 1usize
    }
    if ix.metric == ANGULAR { wrf(ix.nodes, base + 4usize, dotf(ix.xa, ix.xa, ix.f)) }
    if item >= ix.n_items { ix.n_items = item + 1usize }
    ret ok
}

fn normalize(v: []f32, f: usize) {
    let norm = math.sqrt[f32](dotf(v, v, f))
    if norm > 0.0f32 {
        var z = 0usize
        while z < f {
            v[z] = v[z] / norm
            z += 1usize
        }
    }
}

// two_means: centroids pv and qv of Annoy's 200-step heuristic over the items in `idx`
fn two_means(ix: *Index, idx: []const usize, m: usize, rng: *Kiss, cosine: bool) {
    let f = ix.f
    let i = kiss_index(rng, m)
    var j = kiss_index(rng, m - 1usize)
    if j >= i { j += 1usize }
    load_f(ix, idx[i], ix.pv)
    load_f(ix, idx[j], ix.qv)
    if cosine {
        normalize(ix.pv, f)
        normalize(ix.qv, f)
    }
    var pn = 0.0f32
    var qn = 0.0f32
    if ix.metric == ANGULAR {
        pn = dotf(ix.pv, ix.pv, f)
        qn = dotf(ix.qv, ix.qv, f)
    }
    var ic = 1i32
    var jc = 1i32
    var l = 0usize
    while l < 200usize {
        let k = kiss_index(rng, m)
        load_f(ix, idx[k], ix.xa)
        let xn = node_norm(ix, idx[k])
        let di = f32(ic) * fdist(ix, ix.pv, pn, ix.xa, xn)
        let dj = f32(jc) * fdist(ix, ix.qv, qn, ix.xa, xn)
        var nrm = 1.0f32
        if cosine { nrm = math.sqrt[f32](dotf(ix.xa, ix.xa, f)) }
        if nrm > 0.0f32 {
            if di < dj {
                var z = 0usize
                while z < f {
                    ix.pv[z] = (ix.pv[z] * f32(ic) + ix.xa[z] / nrm) / f32(ic + 1i32)
                    z += 1usize
                }
                if ix.metric == ANGULAR { pn = dotf(ix.pv, ix.pv, f) }
                ic += 1i32
            } else {
                if dj < di {
                    var z = 0usize
                    while z < f {
                        ix.qv[z] = (ix.qv[z] * f32(jc) + ix.xa[z] / nrm) / f32(jc + 1i32)
                        z += 1usize
                    }
                    if ix.metric == ANGULAR { qn = dotf(ix.qv, ix.qv, f) }
                    jc += 1i32
                }
            }
        }
        l += 1usize
    }
}

fn hsplit_count(ix: *Index, idx: []const usize, m: usize, dim: u64) -> usize {
    var cur = 0usize
    var i = 0usize
    while i < m {
        load_u(ix, idx[i], ix.ua)
        if hmargin(dim, ix.ua) { cur += 1usize }
        i += 1usize
    }
    ret cur
}

// create_split into ix.sv / ix.sa (float metrics) or ix.sd (hamming)
fn create_split(ix: *Index, idx: []const usize, m: usize, rng: *Kiss) {
    let f = ix.f
    if ix.metric == HAMMING {
        let dim = u64(f) * 64u64
        var i = 0usize
        var cur = 0usize
        while i < 20usize {
            ix.sd = kiss(rng) % dim
            cur = hsplit_count(ix, idx, m, ix.sd)
            if cur > 0usize && cur < m { break }
            i += 1usize
        }
        if i == 20usize {
            var j = 0u64
            while j < dim {
                ix.sd = j
                cur = hsplit_count(ix, idx, m, ix.sd)
                if cur > 0usize && cur < m { break }
                j += 1u64
            }
        }
        ret
    }
    two_means(ix, idx, m, rng, ix.metric == ANGULAR)
    var z = 0usize
    while z < f {
        ix.sv[z] = ix.pv[z] - ix.qv[z]
        z += 1usize
    }
    normalize(ix.sv, f)
    if ix.metric != ANGULAR {
        ix.sa = 0.0f32
        z = 0usize
        while z < f {
            ix.sa += -ix.sv[z] * (ix.pv[z] + ix.qv[z]) / 2.0f32
            z += 1usize
        }
    }
}

fn fmargin(ix: *Index, y: []const f32) -> f32 {
    var mg = dotf(ix.sv, y, ix.f)
    if ix.metric != ANGULAR { mg = ix.sa + mg }
    ret mg
}

fn side_of(ix: *Index, node: usize, rng: *Kiss) -> usize {
    if ix.metric == HAMMING {
        load_u(ix, node, ix.ua)
        if hmargin(ix.sd, ix.ua) { ret 1usize }
        ret 0usize
    }
    load_f(ix, node, ix.xb)
    let mg = fmargin(ix, ix.xb)
    if mg != 0.0f32 {
        if mg > 0.0f32 { ret 1usize }
        ret 0usize
    }
    if kiss_flip(rng) { ret 1usize }
    ret 0usize
}

fn imbalance(l0: usize, l1: usize) -> f64 {
    let ls = f64(f32(l0))
    let rs = f64(f32(l1))
    let r = f32(ls / (ls + rs + 1.0e-9f64))
    ret f64(math.max[f32](r, 1.0f32 - r))
}

fn make_tree(a: *mem.Arena, ix: *Index, rng: *Kiss, idx: []const usize, m: usize, is_root: bool) -> (usize, err) {
    if m == 1usize && !is_root { ret (idx[0usize], ok) }
    if m <= ix.k && (!is_root || ix.n_items <= ix.k || m == 1usize) {
        let ge = grow(a, ix, ix.n_nodes + 1usize)
        if ge != ok { ret (0usize, ge) }
        let item = ix.n_nodes
        ix.n_nodes += 1usize
        let base = item * ix.s
        var nd = m
        if is_root { nd = ix.n_items }
        wr32(ix.nodes, base, u32(nd))
        var i = 0usize
        while i < m {
            wr32(ix.nodes, base + ix.off_c + 4usize * i, u32(idx[i]))
            i += 1usize
        }
        ret (item, ok)
    }
    let (c0, e0) = alloc_z(a, m)
    let (c1, e1) = alloc_z(a, m)
    let (mb, e2) = alloc_b(a, ix.s)
    if e0 != ok { ret (0usize, e0) }
    if e1 != ok { ret (0usize, e1) }
    if e2 != ok { ret (0usize, e2) }
    var l0 = 0usize
    var l1 = 0usize
    var attempt = 0usize
    while attempt < 3usize {
        l0 = 0usize
        l1 = 0usize
        create_split(ix, idx, m, rng)
        var i = 0usize
        while i < m {
            let j = idx[i]
            if side_of(ix, j, rng) == 1usize {
                c1[l1] = j
                l1 += 1usize
            } else {
                c0[l0] = j
                l0 += 1usize
            }
            i += 1usize
        }
        if imbalance(l0, l1) < 0.95f64 { break }
        attempt += 1usize
    }
    while imbalance(l0, l1) > 0.99f64 {
        l0 = 0usize
        l1 = 0usize
        var z = 0usize
        while z < ix.f {
            ix.sv[z] = 0.0f32
            z += 1usize
        }
        ix.sd = 0u64
        var i = 0usize
        while i < m {
            if kiss_flip(rng) {
                c1[l1] = idx[i]
                l1 += 1usize
            } else {
                c0[l0] = idx[i]
                l0 += 1usize
            }
            i += 1usize
        }
    }
    var flip = 0usize
    if l0 > l1 { flip = 1usize }
    var nd = m
    if is_root { nd = ix.n_items }
    wr32(mb, 0usize, u32(nd))
    if ix.metric == HAMMING {
        wr64(mb, ix.off_v, ix.sd)
    } else {
        var z = 0usize
        while z < ix.f {
            wrf(mb, ix.off_v + 4usize * z, ix.sv[z])
            z += 1usize
        }
        if ix.metric != ANGULAR { wrf(mb, 4usize, ix.sa) }
    }
    var side = 0usize
    while side < 2usize {
        let which = side ^ flip
        var child = 0usize
        if which == 0usize {
            let (r, re) = make_tree(a, ix, rng, c0, l0, false)
            if re != ok { ret (0usize, re) }
            child = r
        } else {
            let (r, re) = make_tree(a, ix, rng, c1, l1, false)
            if re != ok { ret (0usize, re) }
            child = r
        }
        wr32(mb, ix.off_c + 4usize * which, u32(child))
        side += 1usize
    }
    let ge = grow(a, ix, ix.n_nodes + 1usize)
    if ge != ok { ret (0usize, ge) }
    let item = ix.n_nodes
    ix.n_nodes += 1usize
    var b = 0usize
    while b < ix.s {
        ix.nodes[item * ix.s + b] = mb[b]
        b += 1usize
    }
    ret (item, ok)
}

// build q trees (q = -1: until the nodes reach twice the items), drawing from the generator seeded by set_seed
fn build(a: *mem.Arena, ix: *Index, q: i64) -> err {
    if ix.loaded || ix.built { ret Invalid }
    ix.n_nodes = ix.n_items
    var rng = kiss_new(ix.seed)
    var made = 0i64
    while true {
        if q == -1i64 {
            if ix.n_nodes >= 2usize * ix.n_items { break }
        } else {
            if made >= q { break }
        }
        let (idx, e) = alloc_z(a, ix.n_items)
        if e != ok { ret e }
        var m = 0usize
        var i = 0usize
        while i < ix.n_items {
            if rd32(ix.nodes, i * ix.s) >= 1u32 {
                idx[m] = i
                m += 1usize
            }
            i += 1usize
        }
        let (root, te) = make_tree(a, ix, &rng, idx, m, true)
        if te != ok { ret te }
        let pe = push_root(a, ix, root)
        if pe != ok { ret pe }
        made += 1i64
    }
    let ge = grow(a, ix, ix.n_nodes + ix.n_roots)
    if ge != ok { ret ge }
    var r = 0usize
    while r < ix.n_roots {
        var b = 0usize
        while b < ix.s {
            ix.nodes[(ix.n_nodes + r) * ix.s + b] = ix.nodes[ix.roots[r] * ix.s + b]
            b += 1usize
        }
        r += 1usize
    }
    ix.n_nodes += ix.n_roots
    ix.built = true
    ret ok
}

fn unbuild(ix: *Index) -> err {
    if ix.loaded { ret Invalid }
    ix.n_roots = 0usize
    ix.n_nodes = ix.n_items
    ix.built = false
    ret ok
}

// load an index file (the bytes of `save`): roots are the trailing nodes with the most descendants
fn load(a: *mem.Arena, ix: *Index, data: []const u8) -> err {
    if data.len == 0usize || data.len % ix.s != 0usize { ret Invalid }
    let (nb, e) = alloc_b(a, data.len)
    if e != ok { ret e }
    var i = 0usize
    while i < data.len {
        nb[i] = data[i]
        i += 1usize
    }
    ix.nodes = nb
    ix.n_nodes = data.len / ix.s
    ix.cap = ix.n_nodes
    ix.n_roots = 0usize
    var m = 0u32
    var have = false
    var at = ix.n_nodes
    while at > 0usize {
        at -= 1usize
        let kk = rd32(ix.nodes, at * ix.s)
        if !have || kk == m {
            let pe = push_root(a, ix, at)
            if pe != ok { ret pe }
            m = kk
            have = true
        } else {
            break
        }
    }
    if ix.n_roots > 1usize {
        if rd32(ix.nodes, ix.roots[0usize] * ix.s + ix.off_c) == rd32(ix.nodes, ix.roots[ix.n_roots - 1usize] * ix.s + ix.off_c) { ix.n_roots -= 1usize }
    }
    ix.loaded = true
    ix.built = true
    ix.n_items = usize(m)
    ret ok
}

// the file bytes of a built index; like Annoy the index then reloads from them, so it can no longer take items
fn save(a: *mem.Arena, ix: *Index) -> ([]u8, err) {
    if !ix.built { ret (ix.nodes, Invalid) }
    let total = ix.n_nodes * ix.s
    let (out, e) = alloc_b(a, total)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < total {
        out[i] = ix.nodes[i]
        i += 1usize
    }
    ix.loaded = false
    ix.built = false
    ix.seed = 1234567890987654321u64
    ix.n_roots = 0usize
    let le = load(a, ix, out)
    ret (out, le)
}

fn norm_dist(ix: *Index, d: f32) -> f32 {
    if ix.metric == MANHATTAN { ret math.max[f32](d, 0.0f32) }
    ret math.sqrt[f32](math.max[f32](d, 0.0f32))
}

fn get_distance(ix: *Index, i: usize, j: usize) -> f64 {
    if ix.metric == HAMMING {
        load_u(ix, i, ix.ua)
        load_u(ix, j, ix.ub)
        ret f64(hdist(ix.ua, ix.ub, ix.f))
    }
    load_f(ix, i, ix.xa)
    load_f(ix, j, ix.xb)
    ret f64(norm_dist(ix, fdist(ix, ix.xa, node_norm(ix, i), ix.xb, node_norm(ix, j))))
}

fn get_item(ix: *Index, item: usize, out: []f64) {
    var z = 0usize
    if ix.metric == HAMMING {
        load_u(ix, item, ix.ua)
        while z < ix.f {
            out[z] = f64(ix.ua[z])
            z += 1usize
        }
        ret
    }
    load_f(ix, item, ix.xa)
    while z < ix.f {
        out[z] = f64(ix.xa[z])
        z += 1usize
    }
}

fn enc_f(x: f32) -> u64 {
    var bits = 0u32
    if x != 0.0f32 { bits = mem.bitcast[u32](x) }
    if (bits & 2147483648u32) != 0u32 { ret u64(~bits) }
    ret u64(bits | 2147483648u32)
}

fn dec_f(k: u64) -> f32 {
    let b = u32(k)
    if (b & 2147483648u32) != 0u32 { ret mem.bitcast[f32](b ^ 2147483648u32) }
    ret mem.bitcast[f32](~b)
}

// max-heap on (key, id)
type Heap = struct { k: []u64, id: []usize, n: usize }

fn heap_less(h: *Heap, x: usize, y: usize) -> bool {
    if h.k[x] != h.k[y] { ret h.k[x] < h.k[y] }
    ret h.id[x] < h.id[y]
}

fn heap_swap(h: *Heap, x: usize, y: usize) {
    let tk = h.k[x]
    let ti = h.id[x]
    h.k[x] = h.k[y]
    h.id[x] = h.id[y]
    h.k[y] = tk
    h.id[y] = ti
}

fn heap_push(h: *Heap, key: u64, id: usize) {
    var at = h.n
    h.k[at] = key
    h.id[at] = id
    h.n += 1usize
    while at > 0usize {
        let parent = (at - 1usize) / 2usize
        if heap_less(h, parent, at) {
            heap_swap(h, parent, at)
            at = parent
        } else {
            break
        }
    }
}

fn heap_pop(h: *Heap) {
    h.n -= 1usize
    h.k[0usize] = h.k[h.n]
    h.id[0usize] = h.id[h.n]
    var at = 0usize
    while true {
        let l = 2usize * at + 1usize
        let r = l + 1usize
        var big = at
        if l < h.n && heap_less(h, big, l) { big = l }
        if r < h.n && heap_less(h, big, r) { big = r }
        if big == at { break }
        heap_swap(h, at, big)
        at = big
    }
}

// Annoy's best-first walk over all trees; the query is in ix.xa (float metrics) or ix.ua (hamming). Fills items and dists (each at least n long), returns the count.
fn all_nns(a: *mem.Arena, ix: *Index, n: usize, search_k_in: i64, items: []usize, dists: []f64) -> (usize, err) {
    var search_k = search_k_in
    if search_k == -1i64 { search_k = i64(n * ix.n_roots) }
    var qn = 0.0f32
    if ix.metric == ANGULAR { qn = dotf(ix.xa, ix.xa, ix.f) }
    let (hi, e2) = alloc_z(a, ix.n_nodes + ix.n_roots + 2usize)
    let (nns, e3) = alloc_z(a, ix.n_items * (ix.n_roots + 1usize) + ix.k + 2usize)
    let (seen, e4) = alloc_z(a, ix.n_items)
    let (cand, e5) = alloc_z(a, ix.n_items)
    if e2 != ok { ret (0usize, e2) }
    if e3 != ok { ret (0usize, e3) }
    if e4 != ok { ret (0usize, e4) }
    if e5 != ok { ret (0usize, e5) }
    let (kb, e7) = mem.alloc[u64](a, ix.n_nodes + ix.n_roots + 2usize)
    if e7 != ok { ret (0usize, e7) }
    var h = Heap { k: kb, id: hi, n: 0usize }
    var start = enc_f(mem.bitcast[f32](2139095040u32))
    if ix.metric == HAMMING { start = 18446744073709551615u64 }
    var r = 0usize
    while r < ix.n_roots {
        heap_push(&h, start, ix.roots[r])
        r += 1usize
    }
    var cnt = 0usize
    while search_k > 0i64 && cnt < usize(search_k) && h.n > 0usize {
        let d = h.k[0usize]
        let i = h.id[0usize]
        heap_pop(&h)
        let nd = usize(rd32(ix.nodes, i * ix.s))
        if nd == 1usize && i < ix.n_items {
            nns[cnt] = i
            cnt += 1usize
        } else {
            if nd <= ix.k {
                var c = 0usize
                while c < nd {
                    nns[cnt] = usize(rd32(ix.nodes, i * ix.s + ix.off_c + 4usize * c))
                    cnt += 1usize
                    c += 1usize
                }
            } else {
                let c0 = usize(rd32(ix.nodes, i * ix.s + ix.off_c))
                let c1 = usize(rd32(ix.nodes, i * ix.s + ix.off_c + 4usize))
                if ix.metric == HAMMING {
                    let dim = rd64(ix.nodes, i * ix.s + ix.off_v)
                    var mg = 0u64
                    if hmargin(dim, ix.ua) { mg = 1u64 }
                    var k0 = d
                    if mg != 0u64 { k0 = d -% 1u64 }
                    var k1 = d
                    if mg != 1u64 { k1 = d -% 1u64 }
                    heap_push(&h, k1, c1)
                    heap_push(&h, k0, c0)
                } else {
                    load_f(ix, i, ix.xb)
                    var mg = dotf(ix.xb, ix.xa, ix.f)
                    if ix.metric != ANGULAR { mg = rdf(ix.nodes, i * ix.s + 4usize) + mg }
                    let dv = dec_f(d)
                    var m1 = mg
                    if !(m1 < dv) { m1 = dv }
                    var m0 = -mg
                    if !(m0 < dv) { m0 = dv }
                    heap_push(&h, enc_f(m1), c1)
                    heap_push(&h, enc_f(m0), c0)
                }
            }
        }
    }
    // distinct candidates, by (distance, id)
    var m = 0usize
    var q = 0usize
    while q < cnt {
        let j = nns[q]
        if j < ix.n_items && seen[j] == 0usize && rd32(ix.nodes, j * ix.s) == 1u32 {
            seen[j] = 1usize
            cand[m] = j
            m += 1usize
        }
        q += 1usize
    }
    let (dd, e8) = mem.alloc[f64](a, m + 1usize)
    if e8 != ok { ret (0usize, e8) }
    var t = 0usize
    while t < m {
        if ix.metric == HAMMING {
            load_u(ix, cand[t], ix.ub)
            dd[t] = f64(hdist(ix.ua, ix.ub, ix.f))
        } else {
            load_f(ix, cand[t], ix.xb)
            dd[t] = f64(fdist(ix, ix.xa, qn, ix.xb, node_norm(ix, cand[t])))
        }
        t += 1usize
    }
    var s = 1usize
    while s < m {
        let dk = dd[s]
        let ck = cand[s]
        var p = s
        while p > 0usize && (dd[p - 1usize] > dk || (dd[p - 1usize] == dk && cand[p - 1usize] > ck)) {
            dd[p] = dd[p - 1usize]
            cand[p] = cand[p - 1usize]
            p -= 1usize
        }
        dd[p] = dk
        cand[p] = ck
        s += 1usize
    }
    var take = m
    if n < take { take = n }
    var o = 0usize
    while o < take {
        items[o] = cand[o]
        if ix.metric == HAMMING { dists[o] = dd[o] } else { dists[o] = f64(norm_dist(ix, f32(dd[o]))) }
        o += 1usize
    }
    ret (take, ok)
}

fn set_query(ix: *Index, w: []const f64) {
    var z = 0usize
    while z < ix.f {
        if ix.metric == HAMMING { ix.ua[z] = u64(w[z]) } else { ix.xa[z] = f32(w[z]) }
        z += 1usize
    }
}

fn nns_by_vector(a: *mem.Arena, ix: *Index, w: []const f64, n: usize, search_k: i64, items: []usize, dists: []f64) -> (usize, err) {
    if w.len < ix.f || items.len < n || dists.len < n { ret (0usize, Invalid) }
    set_query(ix, w)
    let (cnt, ce) = all_nns(a, ix, n, search_k, items, dists)
    ret (cnt, ce)
}

fn nns_by_item(a: *mem.Arena, ix: *Index, item: usize, n: usize, search_k: i64, items: []usize, dists: []f64) -> (usize, err) {
    if items.len < n || dists.len < n { ret (0usize, Invalid) }
    if ix.metric == HAMMING {
        load_u(ix, item, ix.ua)
    } else {
        load_f(ix, item, ix.xa)
    }
    let (cnt, ce) = all_nns(a, ix, n, search_k, items, dists)
    ret (cnt, ce)
}
