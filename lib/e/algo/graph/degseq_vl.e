// R igraph sample_degseq(method = "vl"), the Viger-Latapy sampler of a connected simple graph with a given degree sequence, ported
// from igraph 2.3.4 (games/degree_sequence_vl/gengraph_*.cpp): Havel-Hakimi realisation, make_connected, then the heuristic edge-swap
// shuffle (FINAL_HEURISTICS, 5a swaps wanted of at most 100a attempted). Draws are igraph's RNG_INTEGER(0, 0x7fffffff) over R's streams.
// The edge list is flat pairs in igraph's order.

use e.algo.graph.games as gg
use e.algo.rand.r as rg
use e.math
use e.mem
use e.os

fn rnd(r: *rg.Rng) -> i64 { ret gg.gint(r, 0i64, 2147483647i64) }

type Vg = struct { n: usize, a: usize, deg: []i64, links: []i64, off: []usize }

fn fast_rpl(g: *Vg, v: usize, x: i64, y: i64) {
    var p = g.off[v]
    while g.links[p] != x { p += 1usize }
    g.links[p] = y
}

fn swap_edges(g: *Vg, from1: i64, to1: i64, from2: i64, to2: i64) {
    fast_rpl(g, usize(from1), to1, to2)
    fast_rpl(g, usize(from2), to2, to1)
    fast_rpl(g, usize(to1), from1, from2)
    fast_rpl(g, usize(to2), from2, from1)
}

fn havelhakimi(a: *mem.Arena, g: *Vg) {
    let n = g.n
    var dmax = 0i64
    var i = 0usize
    while i < n {
        if g.deg[i] > dmax { dmax = g.deg[i] }
        i += 1usize
    }
    dmax += 1i64
    let nb = gg.zi(a, usize(dmax))
    let sorted = gg.zi(a, n)
    let cur = gg.alloc_u(a, n)
    i = 0usize
    while i < n {
        cur[i] = g.off[i]
        nb[usize(g.deg[i])] += 1i64
        i += 1usize
    }
    var c = 0i64
    var k = dmax - 1i64
    while k >= 0i64 {
        c += nb[usize(k)]
        nb[usize(k)] = 0i64 - nb[usize(k)] + c
        k -= 1i64
    }
    i = 0usize
    while i < n {
        let d = usize(g.deg[i])
        sorted[usize(nb[d])] = i64(i)
        nb[d] += 1i64
        i += 1usize
    }
    var first = 0i64
    var d = dmax - 1i64
    c = i64(g.a / 2usize)
    while c > 0i64 {
        let v = usize(sorted[usize(first)])
        while nb[usize(d)] <= first { d -= 1i64 }
        var dv = d
        c -= dv
        var dc = d
        first += 1i64
        var fc = first
        while dv > 0i64 && dc > 0i64 {
            var lc = nb[usize(dc)]
            if lc != fc {
                while dv > 0i64 && lc > fc {
                    dv -= 1i64
                    lc -= 1i64
                    let w = usize(sorted[usize(lc)])
                    g.links[cur[v]] = i64(w)
                    cur[v] += 1usize
                    g.links[cur[w]] = i64(v)
                    cur[w] += 1usize
                }
                fc = nb[usize(dc)]
                nb[usize(dc)] = lc
            }
            dc -= 1i64
        }
    }
}

fn make_connected(a: *mem.Arena, g: *Vg) -> bool {
    let n = g.n
    if g.a / 2usize < n - 1usize { ret false }
    let buff = gg.zi(a, n + 4usize)
    let dist = gg.zi(a, n)
    var i = 0usize
    while i < n {
        dist[i] = 255i64
        i += 1usize
    }
    let ffub = n + 2usize
    var edges = ffub
    var trees = ffub
    var min_ffub = 1usize
    if (n + 2usize) % 2usize == 0usize { min_ffub = 2usize }
    var fatty_from = 0i64 - 1i64
    var fatty_to = 0i64 - 1i64
    var enough = false
    var v0 = 0usize
    while v0 < n {
        if dist[v0] == 255i64 {
            if g.deg[v0] == 0i64 { ret false }
            dist[v0] = 0i64
            var to_visit = 0usize
            var current = 0usize
            buff[to_visit] = i64(v0)
            to_visit += 1usize
            var is_a_tree = true
            while current != to_visit {
                let v = usize(buff[current])
                current += 1usize
                let cd = dist[v]
                let nd = (cd + 1i64) & 3i64
                var kk = 0usize
                while kk < usize(g.deg[v]) {
                    let w = g.links[g.off[v] + kk]
                    kk += 1usize
                    if dist[usize(w)] == 255i64 {
                        dist[usize(w)] = nd
                        buff[to_visit] = w
                        to_visit += 1usize
                        if to_visit > min_ffub { min_ffub += 2usize }
                    } else if dist[usize(w)] == nd || (w >= i64(v) && dist[usize(w)] == cd) {
                        if trees != ffub {
                            let tr = usize(buff[trees])
                            swap_edges(g, i64(v), w, i64(tr), g.links[g.off[tr]])
                            trees += 1usize
                        } else if is_a_tree {
                            is_a_tree = false
                            if fatty_from < 0i64 {
                                fatty_from = i64(v)
                                fatty_to = w
                            } else {
                                swap_edges(g, fatty_from, fatty_to, i64(v), w)
                                fatty_to = w
                            }
                        } else if !enough {
                            if edges <= min_ffub + 2usize {
                                enough = true
                            } else {
                                edges -= 2usize
                                buff[edges] = i64(v)
                                buff[edges + 1usize] = w
                            }
                        }
                    }
                }
            }
            while to_visit != 0usize {
                to_visit -= 1usize
                dist[usize(buff[to_visit])] = 254i64
            }
            if is_a_tree {
                if edges != ffub {
                    if edges < min_ffub { edges = min_ffub }
                    swap_edges(g, i64(v0), g.links[g.off[v0]], buff[edges], buff[edges + 1usize])
                    edges += 2usize
                } else if fatty_from >= 0i64 {
                    swap_edges(g, i64(v0), g.links[g.off[v0]], fatty_from, fatty_to)
                    fatty_from = 0i64 - 1i64
                    fatty_to = 0i64 - 1i64
                } else {
                    trees -= 1usize
                    buff[trees] = i64(v0)
                }
            }
        }
        v0 += 1usize
    }
    ret trees == ffub || (trees + 1usize == ffub && fatty_from < 0i64)
}

// The shuffle runs on graph_molloy_hash: a vertex of degree above 100 keeps its neighbours in an open-addressing table of
// HASH_EXPAND(d) slots (-1 = empty), any other in a plain array of d slots.
type Hg = struct { n: usize, size: usize, deg: []i64, links: []i64, off: []usize }

fn is_hash(d: i64) -> bool { ret d > 100i64 }

fn hash_expand(d: i64) -> usize {
    var x = u64(d) + u64(d)
    x = x | (x >> 1u64)
    x = x | (x >> 2u64)
    x = x | (x >> 4u64)
    x = x | (x >> 8u64)
    x = x | (x >> 16u64)
    x = x | (x >> 32u64)
    ret usize(x + 1u64)
}

fn hash_size(d: i64) -> usize {
    if is_hash(d) { ret hash_expand(d) }
    ret usize(d)
}

fn hkey(x: i64, size: usize) -> usize { ret usize((u64(x) * 2198737u64) & (u64(size) - 1u64)) }

fn rekey(k: usize, size: usize) -> usize {
    if k == 0usize { ret size - 1usize }
    ret k - 1usize
}

// would an element be well placed in newk ?
fn h_better(a: i64, size: usize, currentk: usize, newk: usize) -> bool {
    let k = hkey(a, size)
    if newk < currentk { ret k < currentk && k >= newk }
    ret k < currentk || k >= newk
}

// h is the table of v, k an offset into it
fn h_rm(g: *Hg, v: usize, size: usize, k0: usize) {
    let base = g.off[v]
    var k = k0
    var lasthole = k0
    var go = true
    while go {
        k = rekey(k, size)
        let next = g.links[base + k]
        if next == 0i64 - 1i64 {
            go = false
        } else if h_better(next, size, k, lasthole) {
            g.links[base + lasthole] = next
            lasthole = k
        }
    }
    g.links[base + lasthole] = 0i64 - 1i64
}

// first empty slot on a's probe path (a is known to be absent)
fn h_put(g: *Hg, v: usize, size: usize, a: i64) -> usize {
    let base = g.off[v]
    var k = hkey(a, size)
    while g.links[base + k] != 0i64 - 1i64 { k = rekey(k, size) }
    g.links[base + k] = a
    ret base + k
}

fn h_find(g: *Hg, v: usize, size: usize, a: i64) -> usize {
    let base = g.off[v]
    var k = hkey(a, size)
    while g.links[base + k] != a { k = rekey(k, size) }
    ret k
}

fn h_is(g: *Hg, v: usize, x: i64) -> bool {
    let d = g.deg[v]
    let base = g.off[v]
    if is_hash(d) {
        let size = hash_expand(d)
        var k = hkey(x, size)
        if g.links[base + k] == 0i64 - 1i64 { ret false }
        while g.links[base + k] != x {
            k = rekey(k, size)
            if g.links[base + k] == 0i64 - 1i64 { ret false }
        }
        ret true
    }
    var p = 0usize
    while p < usize(d) {
        if g.links[base + p] == x { ret true }
        p += 1usize
    }
    ret false
}

fn is_edge(g: *Hg, u: usize, v: usize) -> bool {
    if g.deg[u] < g.deg[v] { ret h_is(g, u, i64(v)) }
    ret h_is(g, v, i64(u))
}

// H_rpl by slot: replace the neighbour at absolute index p of v by b, return the new absolute index
fn rpl_slot(g: *Hg, v: usize, p: usize, b: i64) -> usize {
    let d = g.deg[v]
    if !is_hash(d) {
        g.links[p] = b
        ret p
    }
    let size = hash_expand(d)
    h_rm(g, v, size, p - g.off[v])
    ret h_put(g, v, size, b)
}

// H_rpl by value
fn rpl_val(g: *Hg, v: usize, a: i64, b: i64) -> usize {
    let d = g.deg[v]
    let base = g.off[v]
    if !is_hash(d) {
        var p = base
        while g.links[p] != a { p += 1usize }
        g.links[p] = b
        ret p
    }
    let size = hash_expand(d)
    h_rm(g, v, size, h_find(g, v, size, a))
    ret h_put(g, v, size, b)
}

// graph_molloy_hash::add_edge: dd is the final degree sequence, g.deg the count so far
fn add_edge(g: *Hg, u: usize, v: usize, dd: []const i64) {
    let du = dd[u]
    let dv = dd[v]
    if is_hash(du) {
        let size = hash_expand(du)
        var k = hkey(i64(v), size)
        while g.links[g.off[u] + k] != 0i64 - 1i64 { k = rekey(k, size) }
        g.links[g.off[u] + k] = i64(v)
    } else {
        g.links[g.off[u] + usize(g.deg[u])] = i64(v)
    }
    if is_hash(dv) {
        let size = hash_expand(dv)
        var k = hkey(i64(u), size)
        while g.links[g.off[v] + k] != 0i64 - 1i64 { k = rekey(k, size) }
        g.links[g.off[v] + k] = i64(u)
    } else {
        g.links[g.off[v] + usize(g.deg[v])] = i64(u)
    }
    g.deg[u] += 1i64
    g.deg[v] += 1i64
}

// restore from the list of larger neighbours (init, zero the degrees, add edges)
fn restore(g: *Hg, dd: []const i64, b: []const i64) {
    var i = 0usize
    while i < g.size {
        g.links[i] = 0i64 - 1i64
        i += 1usize
    }
    i = 0usize
    while i < g.n {
        g.deg[i] = 0i64
        i += 1usize
    }
    var bp = 0usize
    i = 0usize
    while i + 1usize < g.n {
        while g.deg[i] < dd[i] {
            add_edge(g, i, usize(b[bp]), dd)
            bp += 1usize
        }
        i += 1usize
    }
}

fn backup(a: *mem.Arena, g: *Hg, arcs: usize) -> []i64 {
    let b = gg.zi(a, arcs / 2usize)
    var c = 0usize
    var i = 0usize
    while i < g.n {
        var k = 0usize
        let hs = hash_size(g.deg[i])
        while k < hs {
            let x = g.links[g.off[i] + k]
            if x != 0i64 - 1i64 && x > i64(i) {
                b[c] = x
                c += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    ret b[0usize..c]
}

fn depth_search(a: *mem.Arena, g: *Hg, visited: []bool, buff: []i64) -> usize {
    var i = 0usize
    while i < g.n {
        visited[i] = false
        i += 1usize
    }
    var to_visit = 0usize
    var nb = 1usize
    visited[0usize] = true
    buff[to_visit] = 0i64
    to_visit += 1usize
    while to_visit != 0usize && nb < g.n {
        to_visit -= 1usize
        let v = usize(buff[to_visit])
        var k = 0usize
        let hs = hash_size(g.deg[v])
        while k < hs {
            let x = g.links[g.off[v] + k]
            if x != 0i64 - 1i64 && !visited[usize(x)] {
                let w = usize(x)
                visited[w] = true
                nb += 1usize
                buff[to_visit] = i64(w)
                to_visit += 1usize
            }
            k += 1usize
        }
    }
    ret nb
}

fn isolated(g: *Hg, v0: usize, kk: usize, kbuff: []i64, visited: []bool) -> bool {
    if kk < 2usize { ret false }
    var seen = 0usize
    var known = 0usize
    kbuff[known] = i64(v0)
    known += 1usize
    visited[v0] = true
    var iso = true
    var v = v0
    var done = false
    while known != seen && !done {
        v = usize(kbuff[seen])
        seen += 1usize
        var d = 0usize
        let hs = hash_size(g.deg[v])
        while d < hs && !done {
            let x = g.links[g.off[v] + d]
            d += 1usize
            if x != 0i64 - 1i64 && !visited[usize(x)] {
                if known == kk {
                    iso = false
                    done = true
                } else {
                    let w = usize(x)
                    visited[w] = true
                    kbuff[known] = i64(w)
                    known += 1usize
                }
            }
        }
    }
    while known != 0usize {
        known -= 1usize
        visited[usize(kbuff[known])] = false
    }
    ret iso
}

fn random_neighbour(r: *rg.Rng, g: *Hg, v: usize) -> usize {
    let d = g.deg[v]
    if !is_hash(d) { ret g.off[v] + usize(rnd(r)) % usize(d) }
    let size = hash_expand(d)
    var p = g.off[v] + hkey(rnd(r), size)
    while g.links[p] == 0i64 - 1i64 { p = g.off[v] + hkey(rnd(r), size) }
    ret p
}

fn pick_random_vertex(r: *rg.Rng, g: *Hg) -> usize {
    var v = g.links[usize(rnd(r)) % g.size]
    while v == 0i64 - 1i64 { v = g.links[usize(rnd(r)) % g.size] }
    ret usize(v)
}

fn random_edge_swap(r: *rg.Rng, g: *Hg, kk: usize, kbuff: []i64, visited: []bool) -> i64 {
    let f1 = pick_random_vertex(r, g)
    let f2 = pick_random_vertex(r, g)
    if f1 == f2 { ret 0i64 }
    let p1 = random_neighbour(r, g, f1)
    let t1 = usize(g.links[p1])
    let p2 = random_neighbour(r, g, f2)
    let t2 = usize(g.links[p2])
    if t1 == t2 || f1 == t2 || f2 == t1 { ret 0i64 }
    if is_edge(g, f1, t2) || is_edge(g, f2, t1) { ret 0i64 }
    let f1t2 = rpl_slot(g, f1, p1, i64(t2))
    let f2t1 = rpl_slot(g, f2, p2, i64(t1))
    let t1f2 = rpl_val(g, t1, i64(f1), i64(f2))
    let t2f1 = rpl_val(g, t2, i64(f2), i64(f1))
    if kk <= 2usize { ret 1i64 }
    if !isolated(g, f1, kk, kbuff, visited) && !isolated(g, f2, kk, kbuff, visited) { ret 1i64 }
    let u1 = rpl_slot(g, f1, f1t2, i64(t1))
    let u2 = rpl_slot(g, f2, f2t1, i64(t2))
    let u3 = rpl_slot(g, t1, t1f2, i64(f1))
    let u4 = rpl_slot(g, t2, t2f1, i64(f2))
    ret 0i64
}

// sample_degseq(seq, method = "vl"): the sequence must be graphical and realisable as a connected graph
fn vl(a: *mem.Arena, r: *rg.Rng, seq: []const usize) -> gg.Edges {
    let n = seq.len
    var el = gg.new_el(a)
    var total = 0usize
    var i = 0usize
    while i < n {
        total += seq[i]
        i += 1usize
    }
    var g = Vg { n: n, a: total, deg: gg.zi(a, n), links: gg.zi(a, total), off: gg.alloc_u(a, n) }
    var o = 0usize
    i = 0usize
    while i < n {
        g.deg[i] = i64(seq[i])
        g.off[i] = o
        o += seq[i]
        i += 1usize
    }
    havelhakimi(a, &g)
    if !make_connected(a, &g) { ret el }
    // hard copy, then the hash graph built from it
    let dd = gg.zi(a, n)
    var hsum = 0usize
    i = 0usize
    while i < n {
        dd[i] = g.deg[i]
        hsum += hash_size(dd[i])
        i += 1usize
    }
    let hc = gg.zi(a, total / 2usize + 1usize)
    var c = 0usize
    i = 0usize
    while i < n {
        var k = 0usize
        while k < usize(g.deg[i]) {
            let x = g.links[g.off[i] + k]
            if x >= i64(i) {
                hc[c] = x
                c += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    var h = Hg { n: n, size: hsum, deg: gg.zi(a, n), links: gg.zi(a, hsum), off: gg.alloc_u(a, n) }
    o = 0usize
    i = 0usize
    while i < n {
        h.off[i] = o
        o += hash_size(dd[i])
        i += 1usize
    }
    restore(&h, dd[0usize..n], hc[0usize..c])
    // shuffle(5a, 100a, FINAL_HEURISTICS)
    let times = 5i64 * i64(total)
    let maxtimes = 100i64 * i64(total)
    var t = f64(i64(total) / 10i64)
    var kf = 2.4f64
    let visited = gg.zb(a, n)
    let seen_all = gg.zb(a, n)
    let kbuff = gg.zi(a, n + 4usize)
    let dbuf = gg.zi(a, n + 2usize)
    var nb_swaps = 0i64
    var all_swaps = 0i64
    while times > nb_swaps && maxtimes > all_swaps {
        let save = backup(a, &h, total)
        var swaps = 0i64
        let k_int = usize(kf)
        var t_int = i64(math.floor[f64](t))
        if t_int < 1i64 { t_int = 1i64 }
        var s = t_int
        while s > 0i64 {
            swaps += random_edge_swap(r, &h, k_int, kbuff, visited)
            all_swaps += 1i64
            s -= 1i64
        }
        let conn = depth_search(a, &h, seen_all, dbuf) == n
        if conn {
            nb_swaps += swaps
        } else {
            restore(&h, dd[0usize..n], save)
        }
        if conn {
            if (kf + 10.0f64) * t > 5.0f64 * f64(total) {
                kf = kf / 1.03f64
            } else {
                t = t * 2.0f64
            }
        } else {
            kf = kf * 1.35f64
        }
    }
    i = 0usize
    while i < n {
        var k = 0usize
        let hs = hash_size(h.deg[i])
        while k < hs {
            let x = h.links[h.off[i] + k]
            if x != 0i64 - 1i64 && x > i64(i) { gg.push(a, &el, i64(i), x) }
            k += 1usize
        }
        i += 1usize
    }
    gg.canon(&el)
    ret el
}
