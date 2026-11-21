// R igraph random graph generators, draw for draw under `set.seed`: sample_gnp, sample_gnm, sample_sbm,
// sample_pa (psumtree, psumtree-multiple and bag), sample_smallworld (dim 1), sample_degseq (configuration)
// and sample_k_regular, ported from igraph 2.3.4 (C core games/*.c, operators/rewire_edges.c). The R
// binding installs R's own streams as igraph's generator, so integers come from two 30-bit draws of
// `unif_rand` through Lemire's bounded method, reals are `unif_rand`, and the geometric is `rgeom`.
//
// An edge list is flat pairs in igraph's edge order; an undirected edge is written (smaller, larger)
// as `as_edgelist` shows it. A failed allocation aborts: these builders are for graphs that fit the arena.
//
// Not here: sample_degseq's "vl" and the other simple-graph methods, a start graph for sample_pa,
// sample_smallworld in dimension above one.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.math
use e.mem
use e.os

type Edges = struct { b: []i64, n: usize }

fn zi(a: *mem.Arena, n: usize) -> []i64 {
    let (x, e) = mem.alloc[i64](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0i64
        i += 1usize
    }
    ret x
}

fn zf(a: *mem.Arena, n: usize) -> []f64 {
    let (x, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0.0f64
        i += 1usize
    }
    ret x
}

fn push(a: *mem.Arena, el: *Edges, x: i64, y: i64) {
    if el.n + 2usize > el.b.len {
        var cap = el.b.len * 2usize
        if cap < 16usize { cap = 16usize }
        let nb = zi(a, cap)
        var i = 0usize
        while i < el.n {
            nb[i] = el.b[i]
            i += 1usize
        }
        el.b = nb
    }
    el.b[el.n] = x
    el.b[el.n + 1usize] = y
    el.n += 2usize
}

fn new_el(a: *mem.Arena) -> Edges {
    let el = Edges { b: zi(a, 16usize), n: 0usize }
    ret el
}

fn count(el: *Edges) -> usize { ret el.n / 2usize }

// igraph_rng_get_integer(l, h) over R's generator (get_int is NULL, so the 32-bit bounded path).
fn gint(r: *rg.Rng, lo: i64, hi: i64) -> i64 {
    if hi == lo { ret lo }
    let range = u64(hi - lo) + 1u64
    let t = (4294967296u64 - range) % range
    var lw = 0u64
    var m = 0u64
    while true {
        let g1 = u64(rg.unif(r) * 1073741824.0f64)
        let g2 = u64(rg.unif(r) * 1073741824.0f64)
        let x = ((g1 << 2u64) + (g2 >> 28u64)) & 4294967295u64
        m = x * range
        lw = m & 4294967295u64
        if lw >= t { break }
    }
    ret lo + i64(m >> 32u64)
}

// igraph_rng_get_unif(l, h)
fn gunif(r: *rg.Rng, l: f64, h: f64) -> f64 {
    if l == h { ret h }
    var v = rg.unif(r) * (h - l) + l
    while v == h { v = rg.unif(r) * (h - l) + l }
    ret v
}

fn geom(r: *rg.Rng, p: f64) -> f64 { ret rd.rgeom(r, p) }

// the sorted sample of `length` of l..h (igraph_random_sample_real), Vitter's method D then A
fn sample_real(a: *mem.Arena, r: *rg.Rng, l0: f64, h: f64, length: usize) -> []f64 {
    let res = zf(a, length)
    var cnt = 0usize
    var l = l0
    var nn = h - l + 1.0f64
    var n = f64(length)
    var nreal = n
    var ninv = 0.0f64
    if nreal != 0.0f64 { ninv = 1.0f64 / nreal }
    var bign = nn
    let ntot = nn
    var qu1 = 0.0f64 - n + 1.0f64 + nn
    var qu1real = 0.0f64 - nreal + 1.0f64 + bign
    let negalphainv = 0.0f64 - 13.0f64
    var threshold = 0.0f64 - negalphainv * n
    if l == h {
        res[0usize] = l
        ret res[0usize..1usize]
    }
    if length == 0usize { ret res[0usize..0usize] }
    if f64(length) == ntot {
        var i = 0usize
        while i < length {
            res[i] = l
            l += 1.0f64
            i += 1usize
        }
        ret res[0usize..length]
    }
    var vprime = math.exp[f64](math.log[f64](rg.unif(r)) * ninv)
    l = l - 1.0f64
    var s = 0.0f64
    while n > 1.0f64 && threshold < nn {
        var x = 0.0f64
        var negs = 0.0f64
        let nmin1inv = 1.0f64 / (0.0f64 - 1.0f64 + nreal)
        while true {
            while true {
                x = bign * (0.0f64 - vprime + 1.0f64)
                s = math.floor[f64](x)
                if s < qu1 { break }
                vprime = math.exp[f64](math.log[f64](rg.unif(r)) * ninv)
            }
            let u = rg.unif(r)
            negs = 0.0f64 - s
            let y1 = math.exp[f64](math.log[f64](u * bign / qu1real) * nmin1inv)
            vprime = y1 * (0.0f64 - x / bign + 1.0f64) * (qu1real / (negs + qu1real))
            if vprime <= 1.0f64 { break }
            var y2 = 1.0f64
            var top = 0.0f64 - 1.0f64 + bign
            var bottom = 0.0f64
            var limit = 0.0f64
            if 0.0f64 - 1.0f64 + n > s {
                bottom = 0.0f64 - nreal + bign
                limit = 0.0f64 - s + nn
            } else {
                bottom = 0.0f64 - 1.0f64 + negs + bign
                limit = qu1
            }
            var t = 0.0f64 - 1.0f64 + nn
            while t >= limit {
                y2 = (y2 * top) / bottom
                top = 0.0f64 - 1.0f64 + top
                bottom = 0.0f64 - 1.0f64 + bottom
                t -= 1.0f64
            }
            if bign / (0.0f64 - x + bign) >= y1 * math.exp[f64](math.log[f64](y2) * nmin1inv) {
                vprime = math.exp[f64](math.log[f64](rg.unif(r)) * nmin1inv)
                break
            }
            vprime = math.exp[f64](math.log[f64](rg.unif(r)) * ninv)
        }
        l += s + 1.0f64
        res[cnt] = l
        cnt += 1usize
        nn = 0.0f64 - s + (0.0f64 - 1.0f64 + nn)
        bign = negs + (0.0f64 - 1.0f64 + bign)
        n = 0.0f64 - 1.0f64 + n
        nreal = 0.0f64 - 1.0f64 + nreal
        ninv = nmin1inv
        qu1 = 0.0f64 - s + qu1
        qu1real = negs + qu1real
        threshold = threshold + negalphainv
    }
    if n > 1.0f64 {
        // igraph_i_random_sample_alga_real(res, l + 1, h, n)
        var ll = l + 1.0f64
        let bn = h - ll + 1.0f64
        var k = n
        var top = bn - k
        var nr = bn
        ll = ll - 1.0f64
        while k >= 2.0f64 {
            let v = rg.unif(r)
            var sk = 1.0f64
            var quot = top / nr
            while quot > v {
                sk += 1.0f64
                top = 0.0f64 - 1.0f64 + top
                nr = 0.0f64 - 1.0f64 + nr
                quot = (quot * top) / nr
            }
            ll += sk
            res[cnt] = ll
            cnt += 1usize
            nr = 0.0f64 - 1.0f64 + nr
            k = 0.0f64 - 1.0f64 + k
        }
        let sk = math.trunc[f64](math.round[f64](nr) * rg.unif(r))
        ll += sk + 1.0f64
        res[cnt] = ll
        cnt += 1usize
    } else {
        s = math.floor[f64](nn * vprime)
        l += s + 1.0f64
        res[cnt] = l
        cnt += 1usize
    }
    ret res[0usize..cnt]
}

// igraph_full's edge order
fn full(a: *mem.Arena, n: usize, directed: bool, loops: bool) -> Edges {
    var el = new_el(a)
    var i = 0usize
    while i < n {
        var j = 0usize
        if !directed { j = i }
        while j < n {
            if loops || i != j { push(a, &el, i64(i), i64(j)) }
            j += 1usize
        }
        i += 1usize
    }
    ret el
}

// every undirected edge as (smaller, larger), the way `as_edgelist` reports it
fn canon(el: *Edges) {
    var i = 0usize
    while i < el.n {
        if el.b[i] > el.b[i + 1usize] {
            let t = el.b[i]
            el.b[i] = el.b[i + 1usize]
            el.b[i + 1usize] = t
        }
        i += 2usize
    }
}

fn maxedges(n: usize, directed: bool, loops: bool) -> f64 {
    var me = f64(n)
    let nf = f64(n)
    if directed && loops { me = me * nf }
    if directed && !loops { me = me * (nf - 1.0f64) }
    if !directed && loops { me = me * ((nf + 1.0f64) / 2.0f64) }
    if !directed && !loops { me = me * ((nf - 1.0f64) / 2.0f64) }
    ret me
}

// the (from, to) pair of the s-th slot of the n-vertex pair space, as erdos_renyi.c decodes it
fn decode(a: *mem.Arena, el: *Edges, s: f64, n: usize, directed: bool, loops: bool, by_edges: bool) {
    let nf = f64(n)
    if directed && loops {
        let to = math.floor[f64](s / nf)
        let from = s - to * nf
        push(a, el, i64(from), i64(to))
    } else if directed && !loops && by_edges {
        let from = math.floor[f64](s / (nf - 1.0f64))
        var to = s - from * (nf - 1.0f64)
        if from == to { to = nf - 1.0f64 }
        push(a, el, i64(from), i64(to))
    } else if directed && !loops {
        let to0 = math.floor[f64](s / nf)
        let from = s - to0 * nf
        var to = to0
        if from == to { to = nf - 1.0f64 }
        push(a, el, i64(from), i64(to))
    } else if !directed && loops {
        let to = math.floor[f64]((math.sqrt[f64](8.0f64 * s + 1.0f64) - 1.0f64) / 2.0f64)
        let from = s - (to * (to + 1.0f64)) / 2.0f64
        push(a, el, i64(from), i64(to))
    } else {
        let to = math.floor[f64]((math.sqrt[f64](8.0f64 * s + 1.0f64) + 1.0f64) / 2.0f64)
        let from = s - (to * (to - 1.0f64)) / 2.0f64
        push(a, el, i64(from), i64(to))
    }
}

fn gnp(a: *mem.Arena, r: *rg.Rng, n: usize, p: f64, directed: bool, loops: bool) -> Edges {
    if p == 0.0f64 || n == 0usize { ret new_el(a) }
    if p == 1.0f64 { ret full(a, n, directed, loops) }
    let me = maxedges(n, directed, loops)
    var el = new_el(a)
    var last = geom(r, p)
    while last < me {
        decode(a, &el, last, n, directed, loops, false)
        last += geom(r, p)
        last += 1.0f64
    }
    ret el
}

fn gnm(a: *mem.Arena, r: *rg.Rng, n: usize, m: usize, directed: bool, loops: bool) -> Edges {
    if m == 0usize || n == 0usize { ret new_el(a) }
    let me = maxedges(n, directed, loops)
    if f64(m) == me { ret full(a, n, directed, loops) }
    let s = sample_real(a, r, 0.0f64, me - 1.0f64, m)
    var el = new_el(a)
    var i = 0usize
    while i < s.len {
        decode(a, &el, s[i], n, directed, loops, true)
        i += 1usize
    }
    ret el
}

// sample_sbm: pref row-major k*k, bs the block sizes
fn sbm(a: *mem.Arena, r: *rg.Rng, pref: []const f64, bs: []const usize, directed: bool, loops: bool) -> Edges {
    var el = new_el(a)
    let k = bs.len
    var fromoff = 0usize
    var from = 0usize
    while from < k {
        let fromsize = f64(bs[from])
        var start = from
        if directed { start = 0usize }
        var tooff = 0usize
        var q = 0usize
        while q < start {
            tooff += bs[q]
            q += 1usize
        }
        var to = start
        while to < k {
            let tosize = f64(bs[to])
            let prob = pref[from * k + to]
            var last = geom(r, prob)
            var me = 0.0f64
            var mode = 0usize
            // 0 rectangle, 1 directed within a block without loops, 2 undirected within a block with loops, 3 without
            if directed && !loops && from == to { mode = 1usize }
            if !directed && loops && from == to { mode = 2usize }
            if !directed && !loops && from == to { mode = 3usize }
            if mode == 0usize { me = fromsize * tosize }
            if mode == 1usize { me = fromsize * (fromsize - 1.0f64) }
            if mode == 2usize { me = fromsize * (fromsize + 1.0f64) / 2.0f64 }
            if mode == 3usize { me = fromsize * (fromsize - 1.0f64) / 2.0f64 }
            while last < me {
                var vto = 0.0f64
                var vfrom = 0.0f64
                if mode == 0usize || mode == 1usize {
                    vto = math.floor[f64](last / fromsize)
                    vfrom = last - vto * fromsize
                    if mode == 1usize && vfrom == vto { vto = fromsize - 1.0f64 }
                } else if mode == 2usize {
                    vto = math.floor[f64]((math.sqrt[f64](8.0f64 * last + 1.0f64) - 1.0f64) / 2.0f64)
                    vfrom = last - (vto * (vto + 1.0f64)) / 2.0f64
                } else {
                    vto = math.floor[f64]((math.sqrt[f64](8.0f64 * last + 1.0f64) + 1.0f64) / 2.0f64)
                    vfrom = last - (vto * (vto - 1.0f64)) / 2.0f64
                }
                push(a, &el, i64(fromoff) + i64(vfrom), i64(tooff) + i64(vto))
                last += geom(r, prob)
                last += 1.0f64
            }
            tooff += bs[to]
            to += 1usize
        }
        fromoff += bs[from]
        from += 1usize
    }
    ret el
}

// ---- sample_pa ----

type Psum = struct { v: []f64, offset: usize, size: usize }

fn psum_new(a: *mem.Arena, size: usize) -> Psum {
    var p2 = 1usize
    while p2 < size { p2 *= 2usize }
    let t = Psum { v: zf(a, p2 - 1usize + size), offset: p2 - 1usize, size: size }
    ret t
}

fn psum_update(t: *Psum, idx: usize, nv: f64) {
    var i = idx + t.offset + 1usize
    let diff = nv - t.v[i - 1usize]
    while i >= 1usize {
        t.v[i - 1usize] += diff
        i = i >> 1usize
    }
}

fn psum_search(t: *Psum, s0: f64) -> usize {
    var s = s0
    var i = 1usize
    let size = t.v.len - 1usize
    while 2usize * i + 1usize <= size {
        if s < t.v[i * 2usize - 1usize] {
            i = i << 1usize
        } else {
            s -= t.v[i * 2usize - 1usize]
            i = i << 1usize
            i += 1usize
        }
    }
    if 2usize * i <= size { i = 2usize * i }
    ret i - 1usize - t.offset
}

fn attraction(degree: f64, power: f64, aa: f64) -> f64 {
    var base = 1.0f64
    if power != 0.0f64 { base = math.pow[f64](degree, power) }
    ret base + aa
}

// algo 0 psumtree, 1 psumtree-multiple, 2 bag; outseq (length n, its first entry unused) overrides m when not empty
fn pa(a: *mem.Arena, r: *rg.Rng, n: usize, power: f64, m: usize, outseq: []const usize, outpref0: bool, aa: f64, directed: bool, algo: usize) -> Edges {
    var el = new_el(a)
    if n == 0usize { ret el }
    var outpref = outpref0
    if !directed { outpref = true }
    var nb = m
    if algo == 2usize {
        var total = 0usize
        var q = 1usize
        while q < n {
            if outseq.len > 0usize { total += outseq[q] } else { total += m }
            q += 1usize
        }
        var bagsize = n + total
        if outpref { bagsize += total }
        let bag = zi(a, bagsize)
        var bagp = 0usize
        bag[bagp] = 0i64
        bagp += 1usize
        var i = 1usize
        while i < n {
            if outseq.len > 0usize { nb = outseq[i] }
            let base = el.n
            var j = 0usize
            while j < nb {
                let to = bag[usize(gint(r, 0i64, i64(bagp) - 1i64))]
                push(a, &el, i64(i), to)
                j += 1usize
            }
            bag[bagp] = i64(i)
            bagp += 1usize
            j = 0usize
            while j < nb {
                bag[bagp] = el.b[base + 2usize * (nb - 1usize - j) + 1usize]
                bagp += 1usize
                if outpref {
                    bag[bagp] = i64(i)
                    bagp += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
    } else {
        var tree = psum_new(a, n)
        let deg = zi(a, n)
        psum_update(&tree, 0usize, 1.0f64)
        var i = 1usize
        while i < n {
            if outseq.len > 0usize { nb = outseq[i] }
            if algo == 0usize && nb >= i {
                var to = 0usize
                while to < i {
                    deg[to] += 1i64
                    push(a, &el, i64(i), i64(to))
                    psum_update(&tree, to, attraction(f64(deg[to]), power, aa))
                    to += 1usize
                }
            } else {
                let sum0 = tree.v[0usize]
                var j = 0usize
                while j < nb {
                    var sum = sum0
                    if algo == 0usize { sum = tree.v[0usize] }
                    var to = 0usize
                    if sum == 0.0f64 {
                        to = usize(gint(r, 0i64, i64(i) - 1i64))
                    } else {
                        to = psum_search(&tree, gunif(r, 0.0f64, sum))
                    }
                    deg[to] += 1i64
                    push(a, &el, i64(i), i64(to))
                    if algo == 0usize { psum_update(&tree, to, 0.0f64) }
                    j += 1usize
                }
                j = 0usize
                while j < nb {
                    let nn = usize(el.b[el.n - 2usize * j - 1usize])
                    psum_update(&tree, nn, attraction(f64(deg[nn]), power, aa))
                    j += 1usize
                }
            }
            if outpref {
                var add = nb
                if algo == 0usize && nb > i { add = i }
                deg[i] += i64(add)
                psum_update(&tree, i, attraction(f64(deg[i]), power, aa))
            } else {
                psum_update(&tree, i, attraction(0.0f64, power, aa))
            }
            i += 1usize
        }
    }
    if !directed { canon(&el) }
    ret el
}

// ---- sample_smallworld (dim 1) ----

// the sorted neighbours of each vertex of an undirected simple edge list, n*n slots
fn adjacency(a: *mem.Arena, el: *Edges, n: usize, nbr: []i64, deg: []usize) {
    var i = 0usize
    while i < el.n {
        let x = usize(el.b[i])
        let y = usize(el.b[i + 1usize])
        nbr[x * n + deg[x]] = i64(y)
        deg[x] += 1usize
        nbr[y * n + deg[y]] = i64(x)
        deg[y] += 1usize
        i += 2usize
    }
    var v = 0usize
    while v < n {
        var p = 1usize
        while p < deg[v] {
            let key = nbr[v * n + p]
            var q = p
            while q > 0usize && nbr[v * n + q - 1usize] > key {
                nbr[v * n + q] = nbr[v * n + q - 1usize]
                q -= 1usize
            }
            nbr[v * n + q] = key
            p += 1usize
        }
        v += 1usize
    }
}

fn lattice1(a: *mem.Arena, size: usize, nei: usize) -> Edges {
    var el = new_el(a)
    var i = 0usize
    while i < size {
        var nx = i + 1usize
        if i == size - 1usize { nx = 0usize }
        if nx != i && (size != 2usize || i != 1usize) { push(a, &el, i64(i), i64(nx)) }
        i += 1usize
    }
    if nei >= 2usize {
        let nbr = zi(a, size * size)
        let deg = alloc_u(a, size)
        adjacency(a, &el, size, nbr, deg)
        let added = zi(a, size)
        let qn = zi(a, size * 2usize + 2usize)
        var extra = new_el(a)
        var v = 0usize
        while v < size {
            added[v] = i64(v) + 1i64
            var head = 0usize
            var tail = 0usize
            var j = 0usize
            while j < deg[v] {
                let w = nbr[v * size + j]
                added[usize(w)] = i64(v) + 1i64
                qn[tail] = w
                qn[tail + 1usize] = 1i64
                tail += 2usize
                j += 1usize
            }
            while head < tail {
                let act = usize(qn[head])
                let dist = qn[head + 1usize]
                head += 2usize
                var jj = 0usize
                while jj < deg[act] {
                    let w = nbr[act * size + jj]
                    if added[usize(w)] != i64(v) + 1i64 {
                        added[usize(w)] = i64(v) + 1i64
                        if dist < i64(nei) - 1i64 {
                            qn[tail] = w
                            qn[tail + 1usize] = dist + 1i64
                            tail += 2usize
                        }
                        if i64(v) < w { push(a, &extra, i64(v), w) }
                    }
                    jj += 1usize
                }
            }
            v += 1usize
        }
        var q = 0usize
        while q < extra.n {
            push(a, &el, extra.b[q], extra.b[q + 1usize])
            q += 2usize
        }
    }
    canon(&el)
    ret el
}

fn alloc_u(a: *mem.Arena, n: usize) -> []usize {
    let (x, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0usize
        i += 1usize
    }
    ret x
}

// igraph_vector_int_order1: indices sorted by value, equal values in decreasing index
fn order1(a: *mem.Arena, v: []const i64, nodes: usize) -> []i64 {
    let ptr = zi(a, nodes + 1usize)
    let rad = zi(a, v.len)
    let res = zi(a, v.len)
    var i = 0usize
    while i < v.len {
        let radix = usize(v[i])
        if ptr[radix] != 0i64 { rad[i] = ptr[radix] }
        ptr[radix] = i64(i) + 1i64
        i += 1usize
    }
    var j = 0usize
    i = 0usize
    while i < nodes + 1usize {
        if ptr[i] != 0i64 {
            var nx = usize(ptr[i] - 1i64)
            res[j] = i64(nx)
            j += 1usize
            while rad[nx] != 0i64 {
                nx = usize(rad[nx] - 1i64)
                res[j] = i64(nx)
                j += 1usize
            }
        }
        i += 1usize
    }
    ret res
}

// one pass of igraph_i_rewire_edges_no_multiple: `second` is false for the first endpoint pass (stubs odd)
fn rewire_pass(a: *mem.Arena, r: *rg.Rng, ed: []i64, eorder: []const i64, first: []i64, next: []i64, prev: []i64, marked: []i64, nv: usize, ne: usize, p: f64, loops: bool, second: bool) {
    var last_other = 0i64 - 1i64
    var tr = usize(0usize)
    let g0 = geom(r, p)
    var tr_f = g0
    while tr_f < f64(ne) {
        tr = usize(tr_f)
        var stub = 2usize * usize(eorder[tr]) + 1usize
        if second { stub = 2usize * usize(eorder[tr]) }
        let v = ed[stub]
        var ostub = stub + 1usize
        if !second { ostub = stub - 1usize }
        let other = ed[ostub]
        if last_other != other {
            var xx = usize(first[usize(other)])
            while xx != 0usize {
                var oi = xx
                if xx % 2usize == 0usize { oi = xx - 2usize }
                let o = ed[oi]
                marked[usize(o)] = other + 1i64
                xx = usize(next[xx - 1usize])
            }
        }
        var pot = 0i64
        while true {
            if loops {
                pot = gint(r, 0i64, i64(nv) - 1i64)
            } else {
                pot = gint(r, 0i64, i64(nv) - 2i64)
                if pot == other { pot = i64(nv) - 1i64 }
            }
            if !(marked[usize(pot)] == other + 1i64 && pot != v) { break }
        }
        if pot != v {
            // DEL_STUB(v, stub)
            let nx = usize(next[stub])
            if nx != 0usize { prev[nx - 1usize] = prev[stub] }
            if prev[stub] != 0i64 {
                next[usize(prev[stub]) - 1usize] = i64(nx)
            } else {
                first[usize(v)] = i64(nx)
            }
            // ADD_STUB(pot, stub)
            if first[usize(pot)] != 0i64 { prev[usize(first[usize(pot)]) - 1usize] = i64(stub) + 1i64 }
            next[stub] = first[usize(pot)]
            prev[stub] = 0i64
            first[usize(pot)] = i64(stub) + 1i64
            marked[usize(v)] = 0i64
            marked[usize(pot)] = other + 1i64
            ed[stub] = pot
        }
        tr_f += geom(r, p) + 1.0f64
        last_other = other
    }
}

// igraph_rewire_edges on an undirected edge list (edges smaller, larger)
fn rewire(a: *mem.Arena, r: *rg.Rng, el: *Edges, nv: usize, p: f64, loops: bool, multiple: bool) {
    let ne = el.n / 2usize
    if p == 0.0f64 || ne == 0usize { ret }
    if multiple {
        var tr = geom(r, p)
        while tr < f64(el.n) {
            let t = usize(tr)
            if loops {
                el.b[t] = gint(r, 0i64, i64(nv) - 1i64)
            } else {
                var opos = t + 1usize
                if t % 2usize == 1usize { opos = t - 1usize }
                let nei = el.b[opos]
                let rr = gint(r, 0i64, i64(nv) - 2i64)
                if rr != nei { el.b[t] = rr } else { el.b[t] = i64(nv) - 1i64 }
            }
            tr += geom(r, p) + 1.0f64
        }
    } else {
        let first = zi(a, nv)
        let next = zi(a, el.n)
        let prev = zi(a, el.n)
        let tmp = zi(a, ne)
        var i = 0usize
        while i < ne {
            let i1 = 2usize * i
            let i2 = i1 + 1usize
            tmp[i] = el.b[i1]
            var s = 0usize
            while s < 2usize {
                var stub = i1
                var vx = el.b[i1]
                if s == 1usize {
                    stub = i2
                    vx = el.b[i2]
                }
                let fv = usize(vx)
                if first[fv] != 0i64 { prev[usize(first[fv]) - 1usize] = i64(stub) + 1i64 }
                next[stub] = first[fv]
                prev[stub] = 0i64
                first[fv] = i64(stub) + 1i64
                s += 1usize
            }
            i += 1usize
        }
        var eorder = order1(a, tmp[0usize..ne], nv)
        let marked = zi(a, nv)
        rewire_pass(a, r, el.b, eorder, first, next, prev, marked, nv, ne, p, loops, false)
        let tmp2 = zi(a, ne)
        i = 0usize
        while i < ne {
            tmp2[i] = el.b[2usize * i + 1usize]
            i += 1usize
        }
        eorder = order1(a, tmp2[0usize..ne], nv)
        i = 0usize
        while i < nv {
            marked[i] = 0i64
            i += 1usize
        }
        rewire_pass(a, r, el.b, eorder, first, next, prev, marked, nv, ne, p, loops, true)
    }
    canon(el)
}

fn smallworld(a: *mem.Arena, r: *rg.Rng, size: usize, nei: usize, p: f64, loops: bool, multiple: bool) -> Edges {
    var el = lattice1(a, size, nei)
    rewire(a, r, &el, size, p, loops, multiple)
    ret el
}

// ---- degree sequences ----

fn shuffle(r: *rg.Rng, v: []i64, len: usize) {
    var n = len
    while n > 1usize {
        let k = usize(gint(r, 0i64, i64(n) - 1i64))
        n -= 1usize
        let d = v[n]
        v[n] = v[k]
        v[k] = d
    }
}

// sample_degseq(method = "configuration"): inn empty means undirected
fn degseq_config(a: *mem.Arena, r: *rg.Rng, outd: []const usize, inn: []const usize) -> Edges {
    var el = new_el(a)
    let directed = inn.len != 0usize
    var outsum = 0usize
    var insum = 0usize
    var i = 0usize
    while i < outd.len {
        outsum += outd[i]
        if directed { insum += inn[i] }
        i += 1usize
    }
    let bag1 = zi(a, outsum)
    let bag2 = zi(a, insum)
    var bagp1 = 0usize
    var bagp2 = 0usize
    i = 0usize
    while i < outd.len {
        var j = 0usize
        while j < outd[i] {
            bag1[bagp1] = i64(i)
            bagp1 += 1usize
            j += 1usize
        }
        if directed {
            j = 0usize
            while j < inn[i] {
                bag2[bagp2] = i64(i)
                bagp2 += 1usize
                j += 1usize
            }
        }
        i += 1usize
    }
    var ne = outsum / 2usize
    if directed { ne = outsum }
    i = 0usize
    while i < ne {
        if directed {
            let from = usize(gint(r, 0i64, i64(bagp1) - 1i64))
            let to = usize(gint(r, 0i64, i64(bagp2) - 1i64))
            push(a, &el, bag1[from], bag2[to])
            bag1[from] = bag1[bagp1 - 1usize]
            bag2[to] = bag2[bagp2 - 1usize]
            bagp1 -= 1usize
            bagp2 -= 1usize
        } else {
            let from = usize(gint(r, 0i64, i64(bagp1) - 1i64))
            let x = bag1[from]
            bag1[from] = bag1[bagp1 - 1usize]
            bagp1 -= 1usize
            let to = usize(gint(r, 0i64, i64(bagp1) - 1i64))
            let y = bag1[to]
            bag1[to] = bag1[bagp1 - 1usize]
            bagp1 -= 1usize
            push(a, &el, x, y)
        }
        i += 1usize
    }
    if !directed { canon(&el) }
    ret el
}

// position of key in the sorted list nbr[base .. base+len): found, and where it is or would go
fn bsearch(nbr: []const i64, base: usize, len: usize, key: i64) -> (bool, usize) {
    var lo = 0usize
    var hi = len
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if nbr[base + mid] < key {
            lo = mid + 1usize
        } else {
            hi = mid
        }
    }
    var found = false
    if lo < len && nbr[base + lo] == key { found = true }
    ret (found, lo)
}

fn insert_at(nbr: []i64, base: usize, len: usize, at: usize, key: i64) {
    var q = len
    while q > at {
        nbr[base + q] = nbr[base + q - 1usize]
        q -= 1usize
    }
    nbr[base + at] = key
}

fn next_flag(flags: []const bool, from: usize, n: usize) -> i64 {
    var v = from
    while v < n {
        if flags[v] { ret i64(v) }
        v += 1usize
    }
    ret 0i64 - 1i64
}

// sample_degseq(method = "fast.heur.simple"), also what sample_k_regular uses
fn degseq_simple(a: *mem.Arena, r: *rg.Rng, outd: []const usize, inn: []const usize) -> Edges {
    let directed = inn.len != 0usize
    let n = outd.len
    var total = 0usize
    var i = 0usize
    while i < n {
        total += outd[i]
        i += 1usize
    }
    let stubs = zi(a, total)
    let istubs = zi(a, total)
    let nbr = zi(a, n * n)
    let al = alloc_u(a, n)
    let resout = zi(a, n)
    let resin = zi(a, n)
    let incout = zb(a, n)
    let incin = zb(a, n)
    var finished = false
    while !finished {
        var failed = false
        i = 0usize
        while i < n {
            al[i] = 0usize
            resout[i] = i64(outd[i])
            if directed { resin[i] = i64(inn[i]) }
            i += 1usize
        }
        while !finished && !failed {
            var k = 0usize
            var k2 = 0usize
            i = 0usize
            while i < n {
                var j = 0i64
                while j < resout[i] {
                    stubs[k] = i64(i)
                    k += 1usize
                    j += 1i64
                }
                if directed {
                    j = 0i64
                    while j < resin[i] {
                        istubs[k2] = i64(i)
                        k2 += 1usize
                        j += 1i64
                    }
                }
                resout[i] = 0i64
                resin[i] = 0i64
                incout[i] = false
                incin[i] = false
                i += 1usize
            }
            shuffle(r, stubs, k)
            if directed {
                i = 0usize
                while i < k {
                    let from = usize(stubs[i])
                    let to = istubs[i]
                    let (found, pos) = bsearch(nbr, from * n, al[from], to)
                    if i64(from) == to || found {
                        resout[from] += 1i64
                        resin[usize(to)] += 1i64
                        incout[from] = true
                        incin[usize(to)] = true
                    } else {
                        insert_at(nbr, from * n, al[from], pos, to)
                        al[from] += 1usize
                    }
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < k {
                    var from = stubs[i]
                    var to = stubs[i + 1usize]
                    i += 2usize
                    if from > to {
                        let d = from
                        from = to
                        to = d
                    }
                    let (found, pos) = bsearch(nbr, usize(from) * n, al[usize(from)], to)
                    if from == to || found {
                        resout[usize(from)] += 1i64
                        resout[usize(to)] += 1i64
                        incout[usize(from)] = true
                        incout[usize(to)] = true
                    } else {
                        insert_at(nbr, usize(from) * n, al[usize(from)], pos, to)
                        al[usize(from)] += 1usize
                    }
                }
            }
            finished = next_flag(incout, 0usize, n) < 0i64
            if !finished {
                failed = true
                var fi = 0usize
                while failed {
                    let fv = next_flag(incout, fi, n)
                    if fv < 0i64 { break }
                    var from = fv
                    fi = usize(fv) + 1usize
                    var tj = 0usize
                    while true {
                        var tv = 0i64 - 1i64
                        if directed { tv = next_flag(incin, tj, n) } else { tv = next_flag(incout, tj, n) }
                        if tv < 0i64 { break }
                        var to = tv
                        tj = usize(tv) + 1usize
                        if directed {
                            let (f2, p2) = bsearch(nbr, usize(from) * n, al[usize(from)], to)
                            if from != to && !f2 {
                                failed = false
                                break
                            }
                        } else {
                            if from == to { break }
                            if from > to {
                                let d = from
                                from = to
                                to = d
                            }
                            let (f2, p2) = bsearch(nbr, usize(from) * n, al[usize(from)], to)
                            if !f2 {
                                failed = false
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    var el = new_el(a)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < al[i] {
            push(a, &el, i64(i), nbr[i * n + j])
            j += 1usize
        }
        i += 1usize
    }
    if !directed { canon(&el) }
    ret el
}

fn zb(a: *mem.Arena, n: usize) -> []bool {
    let (x, e) = mem.alloc[bool](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        x[i] = false
        i += 1usize
    }
    ret x
}

fn k_regular(a: *mem.Arena, r: *rg.Rng, n: usize, k: usize, directed: bool, multiple: bool) -> Edges {
    let d = alloc_u(a, n)
    var i = 0usize
    while i < n {
        d[i] = k
        i += 1usize
    }
    var none = d[0usize..0usize]
    if multiple {
        if directed { ret degseq_config(a, r, d[0usize..n], d[0usize..n]) }
        ret degseq_config(a, r, d[0usize..n], none)
    }
    if directed { ret degseq_simple(a, r, d[0usize..n], d[0usize..n]) }
    ret degseq_simple(a, r, d[0usize..n], none)
}

fn zf32(a: *mem.Arena, n: usize) -> []f32 {
    let (x, e) = mem.alloc[f32](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0.0f32
        i += 1usize
    }
    ret x
}
