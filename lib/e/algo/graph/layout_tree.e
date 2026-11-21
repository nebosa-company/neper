// R igraph layout_as_tree (Reingold-Tilford), ported from igraph 2.3.4 layout/reingold_tilford.c: root choice by degree
// (graphs under 500 vertices) or eccentricity (500 or more), with igraph's own BSD qsort so ties fall where igraph puts them, explicit roots
// with `rootlevel`, a virtual root over several roots, shortcut edges to unreachable vertices, `circular` and `flip.y`.
// Rows are (x, y), n rows. An edge list is flat pairs; `mode` is 1 out, 2 in, 3 all (forced to 3 for an undirected graph).
//

use e.algo.graph.games as gg
use e.math
use e.mem
use e.os

type Rt = struct { parent: []i64, level: []i64, offset: []f64, lc: []i64, rc: []i64, olc: []f64, orc: []f64, le: []i64, re: []i64, ole: []f64, ore: []f64, vcount: usize }

// neighbours without loops or repeats, sorted: nbr[v * nv + k], cnt[v]
fn adjacency(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize, nbr: []i64, cnt: []usize) {
    let seen = gg.zb(a, nv * nv)
    var k = 0usize
    while k + 1usize < ed.len {
        let x = usize(ed[k])
        let y = usize(ed[k + 1usize])
        if x != y {
            if mode == 1usize || mode == 3usize { seen[x * nv + y] = true }
            if mode == 2usize || mode == 3usize { seen[y * nv + x] = true }
        }
        k += 2usize
    }
    var v = 0usize
    while v < nv {
        cnt[v] = 0usize
        var w = 0usize
        while w < nv {
            if seen[v * nv + w] {
                nbr[v * nv + cnt[v]] = i64(w)
                cnt[v] += 1usize
            }
            w += 1usize
        }
        v += 1usize
    }
}

fn postorder(t: *Rt, node: usize) {
    let vc = t.vcount
    let minsep = 1.0f64
    var childcount = 0usize
    var i = 0usize
    while i < vc {
        if i != node && t.parent[i] == i64(node) {
            childcount += 1usize
            postorder(t, i)
        }
        i += 1usize
    }
    if childcount == 0usize { ret }
    var leftroot = 0i64 - 1i64
    var avg = 0.0f64
    var j = 0usize
    i = 0usize
    while i < vc {
        if i != node && t.parent[i] == i64(node) {
            if leftroot >= 0i64 {
                var lnode = leftroot
                var rnode = i64(i)
                var rootsep = t.offset[usize(leftroot)] + minsep
                var loffset = t.offset[usize(leftroot)]
                var roffset = loffset + minsep
                t.rc[node] = i64(i)
                t.orc[node] = rootsep
                while lnode >= 0i64 && rnode >= 0i64 {
                    if t.rc[usize(lnode)] >= 0i64 {
                        loffset += t.orc[usize(lnode)]
                        lnode = t.rc[usize(lnode)]
                    } else {
                        if t.lc[usize(rnode)] >= 0i64 {
                            let aux = usize(t.le[node])
                            let newoffset = (t.ore[node] - t.ole[node]) + minsep + t.olc[usize(rnode)]
                            t.lc[aux] = t.lc[usize(rnode)]
                            t.rc[aux] = t.lc[usize(rnode)]
                            t.olc[aux] = newoffset
                            t.orc[aux] = newoffset
                            t.le[node] = t.le[i]
                            t.re[node] = t.re[i]
                            t.ole[node] = t.ole[i] + rootsep
                            t.ore[node] = t.ore[i] + rootsep
                        } else {
                            t.re[node] = t.re[i]
                            t.ore[node] = t.ore[i] + rootsep
                        }
                        lnode = 0i64 - 1i64
                    }
                    if t.lc[usize(rnode)] >= 0i64 {
                        roffset += t.olc[usize(rnode)]
                        rnode = t.lc[usize(rnode)]
                    } else {
                        if lnode >= 0i64 {
                            let aux = usize(t.re[i])
                            let newoffset = loffset - rootsep - t.ore[i]
                            t.lc[aux] = lnode
                            t.rc[aux] = lnode
                            t.olc[aux] = newoffset
                            t.orc[aux] = newoffset
                        }
                        rnode = 0i64 - 1i64
                    }
                    if lnode >= 0i64 && rnode >= 0i64 && roffset - loffset < minsep {
                        rootsep += minsep - roffset + loffset
                        roffset = loffset + minsep
                        t.orc[node] = rootsep
                    }
                }
                t.offset[i] = rootsep
                t.orc[node] = rootsep
                avg = (avg * f64(j)) / f64(j + 1usize) + rootsep / f64(j + 1usize)
                leftroot = i64(i)
            } else {
                leftroot = i64(i)
                t.lc[node] = i64(i)
                t.rc[node] = i64(i)
                t.olc[node] = 0.0f64
                t.orc[node] = 0.0f64
                t.le[node] = t.le[i]
                t.re[node] = t.re[i]
                t.ole[node] = t.ole[i]
                t.ore[node] = t.ore[i]
                avg = t.offset[i]
            }
            j += 1usize
        }
        i += 1usize
    }
    t.olc[node] -= avg
    t.orc[node] -= avg
    t.ole[node] -= avg
    t.ore[node] -= avg
    i = 0usize
    while i < vc {
        if i != node && t.parent[i] == i64(node) { t.offset[i] -= avg }
        i += 1usize
    }
}

fn calc_coords(t: *Rt, res: []f64, node: usize, xpos: f64) {
    res[node * 2usize] = xpos
    var i = 0usize
    while i < t.vcount {
        if i != node && t.parent[i] == i64(node) { calc_coords(t, res, i, xpos + t.offset[i]) }
        i += 1usize
    }
}

// layout_reingold_tilford on one rooted graph (every vertex reachable from the root)
fn rt_one(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize, root: usize) -> []f64 {
    let res = gg.zf(a, 2usize * nv)
    let nbr = gg.zi(a, nv * nv)
    let cnt = gg.alloc_u(a, nv)
    adjacency(a, nv, ed, mode, nbr, cnt)
    var t = Rt { parent: gg.zi(a, nv), level: gg.zi(a, nv), offset: gg.zf(a, nv), lc: gg.zi(a, nv), rc: gg.zi(a, nv), olc: gg.zf(a, nv), orc: gg.zf(a, nv), le: gg.zi(a, nv), re: gg.zi(a, nv), ole: gg.zf(a, nv), ore: gg.zf(a, nv), vcount: nv }
    var i = 0usize
    while i < nv {
        t.parent[i] = 0i64 - 1i64
        t.level[i] = 0i64 - 1i64
        t.lc[i] = 0i64 - 1i64
        t.rc[i] = 0i64 - 1i64
        t.le[i] = i64(i)
        t.re[i] = i64(i)
        i += 1usize
    }
    t.parent[root] = i64(root)
    t.level[root] = 0i64
    res[root * 2usize + 1usize] = 0.0f64
    let q = gg.zi(a, 2usize * nv + 2usize)
    var head = 0usize
    var tail = 0usize
    q[tail] = i64(root)
    q[tail + 1usize] = 0i64
    tail += 2usize
    while head < tail {
        let act = usize(q[head])
        let dist = q[head + 1usize]
        head += 2usize
        var j = 0usize
        while j < cnt[act] {
            let nb = usize(nbr[act * nv + j])
            if t.parent[nb] < 0i64 {
                res[nb * 2usize + 1usize] = f64(dist + 1i64)
                q[tail] = i64(nb)
                q[tail + 1usize] = dist + 1i64
                tail += 2usize
                t.parent[nb] = i64(act)
                t.level[nb] = dist + 1i64
            }
            j += 1usize
        }
    }
    postorder(&t, root)
    calc_coords(&t, res, root, t.offset[root])
    ret res
}

// ---- igraph's qsort (FreeBSD), sorting indices by a key, descending ----

fn qcmp(key: []const i64, ix: []const usize, x: usize, y: usize) -> i64 {
    let kx = key[ix[x]]
    let ky = key[ix[y]]
    if kx < ky { ret 1i64 }
    if kx > ky { ret 0i64 - 1i64 }
    ret 0i64
}

fn qswap(ix: []usize, x: usize, y: usize) {
    let t = ix[x]
    ix[x] = ix[y]
    ix[y] = t
}

fn qmed3(key: []const i64, ix: []const usize, a: usize, b: usize, c: usize) -> usize {
    if qcmp(key, ix, a, b) < 0i64 {
        if qcmp(key, ix, b, c) < 0i64 { ret b }
        if qcmp(key, ix, a, c) < 0i64 { ret c }
        ret a
    }
    if qcmp(key, ix, b, c) > 0i64 { ret b }
    if qcmp(key, ix, a, c) < 0i64 { ret a }
    ret c
}

fn qvecswap(ix: []usize, x: usize, y: usize, n: usize) {
    var k = 0usize
    while k < n {
        qswap(ix, x + k, y + k)
        k += 1usize
    }
}

fn qsort_desc(key: []const i64, ix: []usize, a0: usize, n0: usize) {
    var a = a0
    var n = n0
    while true {
        if n < 2usize { ret }
        var swap_cnt = false
        if n < 7usize {
            var pm = a + 1usize
            while pm < a + n {
                var pl = pm
                while pl > a && qcmp(key, ix, pl - 1usize, pl) > 0i64 {
                    qswap(ix, pl, pl - 1usize)
                    pl -= 1usize
                }
                pm += 1usize
            }
            ret
        }
        var pm = a + n / 2usize
        if n > 7usize {
            var pl = a
            var pn = a + n - 1usize
            if n > 40usize {
                let d = n / 8usize
                pl = qmed3(key, ix, pl, pl + d, pl + 2usize * d)
                pm = qmed3(key, ix, pm - d, pm, pm + d)
                pn = qmed3(key, ix, pn - 2usize * d, pn - d, pn)
            }
            pm = qmed3(key, ix, pl, pm, pn)
        }
        qswap(ix, a, pm)
        var pa = a + 1usize
        var pb = pa
        var pc = a + n - 1usize
        var pd = pc
        while true {
            while pb <= pc && qcmp(key, ix, pb, a) <= 0i64 {
                if qcmp(key, ix, pb, a) == 0i64 {
                    swap_cnt = true
                    qswap(ix, pa, pb)
                    pa += 1usize
                }
                pb += 1usize
            }
            while pb <= pc && qcmp(key, ix, pc, a) >= 0i64 {
                if qcmp(key, ix, pc, a) == 0i64 {
                    swap_cnt = true
                    qswap(ix, pc, pd)
                    pd -= 1usize
                }
                pc -= 1usize
            }
            if pb > pc { break }
            qswap(ix, pb, pc)
            swap_cnt = true
            pb += 1usize
            pc -= 1usize
        }
        if !swap_cnt {
            var pm2 = a + 1usize
            while pm2 < a + n {
                var pl = pm2
                while pl > a && qcmp(key, ix, pl - 1usize, pl) > 0i64 {
                    qswap(ix, pl, pl - 1usize)
                    pl -= 1usize
                }
                pm2 += 1usize
            }
            ret
        }
        let pn = a + n
        var d1 = pa - a
        if pb - pa < d1 { d1 = pb - pa }
        qvecswap(ix, a, pb - d1, d1)
        d1 = pd - pc
        if pn - pd - 1usize < d1 { d1 = pn - pd - 1usize }
        qvecswap(ix, pb, pn - d1, d1)
        let l1 = pb - pa
        let l2 = pd - pc
        if l1 <= l2 {
            if l1 > 1usize { qsort_desc(key, ix, a, l1) }
            if l2 > 1usize {
                a = pn - l2
                n = l2
            } else {
                ret
            }
        } else {
            if l2 > 1usize { qsort_desc(key, ix, pn - l2, l2) }
            if l1 > 1usize {
                n = l1
            } else {
                ret
            }
        }
    }
}

// the vertices by degree, largest first, in the order igraph's sort_ind leaves them
fn by_degree(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize) -> []usize {
    let deg = gg.zi(a, nv)
    var k = 0usize
    while k + 1usize < ed.len {
        let x = usize(ed[k])
        let y = usize(ed[k + 1usize])
        if x != y {
            if mode == 1usize || mode == 3usize { deg[x] += 1i64 }
            if mode == 2usize || mode == 3usize { deg[y] += 1i64 }
        }
        k += 2usize
    }
    let ix = gg.alloc_u(a, nv)
    var i = 0usize
    while i < nv {
        ix[i] = i
        i += 1usize
    }
    qsort_desc(deg[0usize..nv], ix, 0usize, nv)
    ret ix[0usize..nv]
}

// the vertices by eccentricity along `mode`, smallest first, in the order igraph's sort_ind leaves them
fn by_ecc(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize) -> []usize {
    let nbr = gg.zi(a, nv * nv)
    let cnt = gg.alloc_u(a, nv)
    adjacency(a, nv, ed, mode, nbr, cnt)
    let key = gg.zi(a, nv)
    let dist = gg.zi(a, nv)
    let queue = gg.alloc_u(a, nv)
    var s = 0usize
    while s < nv {
        var i = 0usize
        while i < nv {
            dist[i] = 0i64 - 1i64
            i += 1usize
        }
        dist[s] = 0i64
        queue[0usize] = s
        var head = 0usize
        var tail = 1usize
        var far = 0i64
        while head < tail {
            let v = queue[head]
            head += 1usize
            if dist[v] > far { far = dist[v] }
            var k = 0usize
            while k < cnt[v] {
                let w = usize(nbr[v * nv + k])
                if dist[w] < 0i64 {
                    dist[w] = dist[v] + 1i64
                    queue[tail] = w
                    tail += 1usize
                }
                k += 1usize
            }
        }
        key[s] = 0i64 - far
        s += 1usize
    }
    let ix = gg.alloc_u(a, nv)
    var i = 0usize
    while i < nv {
        ix[i] = i
        i += 1usize
    }
    // ascending eccentricity is descending negated eccentricity
    qsort_desc(key[0usize..nv], ix, 0usize, nv)
    ret ix[0usize..nv]
}

// roots_for_tree_layout: the degree heuristic under 500 vertices, the eccentricity one from 500
fn pick_roots(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize) -> []usize {
    var order = by_degree(a, nv, ed, mode)
    if nv >= 500usize { order = by_ecc(a, nv, ed, mode) }
    // reach[u*nv+v]: v reachable from u along `mode` (all of it for mode 3, in both directions)
    let reach = gg.zb(a, nv * nv)
    var k = 0usize
    while k + 1usize < ed.len {
        let x = usize(ed[k])
        let y = usize(ed[k + 1usize])
        if mode == 1usize || mode == 3usize { reach[x * nv + y] = true }
        if mode == 2usize || mode == 3usize { reach[y * nv + x] = true }
        k += 2usize
    }
    var v = 0usize
    while v < nv {
        reach[v * nv + v] = true
        v += 1usize
    }
    var m = 0usize
    while m < nv {
        var u = 0usize
        while u < nv {
            if reach[u * nv + m] {
                var w = 0usize
                while w < nv {
                    if reach[m * nv + w] { reach[u * nv + w] = true }
                    w += 1usize
                }
            }
            u += 1usize
        }
        m += 1usize
    }
    // membership: weak components for mode 3 (reach is symmetric there), strong otherwise
    let comp = gg.zi(a, nv)
    var nc = 0i64
    v = 0usize
    while v < nv {
        comp[v] = 0i64 - 1i64
        v += 1usize
    }
    v = 0usize
    while v < nv {
        if comp[v] < 0i64 {
            var w = v
            while w < nv {
                if reach[v * nv + w] && reach[w * nv + v] { comp[w] = nc }
                w += 1usize
            }
            nc += 1i64
        }
        v += 1usize
    }
    let roots = gg.zi(a, usize(nc))
    var c = 0usize
    while c < usize(nc) {
        roots[c] = 0i64 - 1i64
        c += 1usize
    }
    if mode != 3usize {
        // in-degree of each cluster from other clusters, in the direction opposite to mode
        let cd = gg.zi(a, usize(nc))
        k = 0usize
        while k + 1usize < ed.len {
            let x = usize(ed[k])
            let y = usize(ed[k + 1usize])
            if comp[x] != comp[y] {
                if mode == 1usize { cd[usize(comp[y])] += 1i64 } else { cd[usize(comp[x])] += 1i64 }
            }
            k += 2usize
        }
        var i = 0usize
        while i < nv {
            let vv = order[i]
            let cl = usize(comp[vv])
            if cd[cl] == 0i64 && roots[cl] == 0i64 - 1i64 { roots[cl] = i64(vv) }
            i += 1usize
        }
    } else {
        var i = 0usize
        while i < nv {
            let vv = order[i]
            let cl = usize(comp[vv])
            if roots[cl] == 0i64 - 1i64 { roots[cl] = i64(vv) }
            i += 1usize
        }
    }
    let out = gg.alloc_u(a, usize(nc))
    var j = 0usize
    c = 0usize
    while c < usize(nc) {
        if roots[c] != 0i64 - 1i64 {
            out[j] = usize(roots[c])
            j += 1usize
        }
        c += 1usize
    }
    ret out[0usize..j]
}

// the vertices of the graph the BFS from real_root (along mode) does not reach, as edges real_root -> v (v -> real_root for mode 2)
fn unreachable_edges(a: *mem.Arena, nv: usize, ed: []const i64, mode: usize, real_root: usize, extra: *gg.Edges) {
    let nbr = gg.zi(a, nv * nv)
    let cnt = gg.alloc_u(a, nv)
    adjacency(a, nv, ed, mode, nbr, cnt)
    let visited = gg.zb(a, nv)
    let q = gg.zi(a, nv * nv + 2usize)
    var head = 0usize
    var tail = 0usize
    q[tail] = i64(real_root)
    tail += 1usize
    while head < tail {
        let act = usize(q[head])
        head += 1usize
        visited[act] = true
        var j = 0usize
        while j < cnt[act] {
            let nb = usize(nbr[act * nv + j])
            if !visited[nb] {
                q[tail] = i64(nb)
                tail += 1usize
            }
            j += 1usize
        }
    }
    var i = 0usize
    while i < nv {
        if !visited[i] {
            if mode != 2usize {
                gg.push(a, extra, i64(real_root), i64(i))
            } else {
                gg.push(a, extra, i64(i), i64(real_root))
            }
        }
        i += 1usize
    }
}

// layout_as_tree(graph, root, circular, rootlevel, mode, flip.y); roots and rootlevel may be empty
fn tree(a: *mem.Arena, n: usize, ed0: []const i64, directed: bool, mode0: usize, roots0: []const usize, rootlevel: []const i64, circular: bool, flip: bool) -> []f64 {
    var mode = mode0
    if !directed { mode = 3usize }
    var nv = n
    var ed = gg.new_el(a)
    var k = 0usize
    while k < ed0.len {
        gg.push(a, &ed, ed0[k], ed0[k + 1usize])
        k += 2usize
    }
    var roots = gg.alloc_u(a, n + 2usize)
    var nroots = 0usize
    if roots0.len == 0usize {
        let pr = pick_roots(a, n, ed0, mode)
        nroots = pr.len
        var i = 0usize
        while i < nroots {
            roots[i] = pr[i]
            i += 1usize
        }
    } else {
        nroots = roots0.len
        var i = 0usize
        while i < nroots {
            roots[i] = roots0[i]
            i += 1usize
        }
        if rootlevel.len > 0usize && roots0.len > 1usize {
            var plus = 0i64
            i = 0usize
            while i < roots0.len {
                plus += rootlevel[i]
                i += 1usize
            }
            if plus != 0i64 {
                i = 0usize
                while i < roots0.len {
                    let rl = rootlevel[i]
                    let rn = i64(roots[i])
                    if rl != 0i64 {
                        if mode != 2usize {
                            gg.push(a, &ed, i64(nv), rn)
                            var j = 0i64
                            while j < rl - 1i64 {
                                gg.push(a, &ed, i64(nv) + 1i64, i64(nv))
                                nv += 1usize
                                j += 1i64
                            }
                        } else {
                            gg.push(a, &ed, rn, i64(nv))
                            var j = 0i64
                            while j < rl - 1i64 {
                                gg.push(a, &ed, i64(nv), i64(nv) + 1i64)
                                nv += 1usize
                                j += 1i64
                            }
                        }
                        roots[i] = nv
                        nv += 1usize
                    }
                    i += 1usize
                }
            }
        }
    }
    var real_root = 0usize
    if nroots == 1usize {
        real_root = roots[0usize]
    } else {
        real_root = nv
        nv += 1usize
        var i = 0usize
        while i < nroots {
            gg.push(a, &ed, i64(nv) - 1i64, i64(roots[i]))
            i += 1usize
        }
    }
    var extra = gg.new_el(a)
    unreachable_edges(a, nv, ed.b[0usize..ed.n], mode, real_root, &extra)
    k = 0usize
    while k < extra.n {
        gg.push(a, &ed, extra.b[k], extra.b[k + 1usize])
        k += 2usize
    }
    let full = rt_one(a, nv, ed.b[0usize..ed.n], mode, real_root)
    let res = gg.zf(a, 2usize * n)
    var i = 0usize
    while i < 2usize * n {
        res[i] = full[i]
        i += 1usize
    }
    if circular && n > 0usize {
        let nf = f64(n)
        var ratio = 2.0f64 * 3.141592653589793f64 * (nf - 1.0f64) / nf
        var minx = res[0usize]
        var maxx = res[0usize]
        i = 1usize
        while i < n {
            if res[i * 2usize] > maxx { maxx = res[i * 2usize] }
            if res[i * 2usize] < minx { minx = res[i * 2usize] }
            i += 1usize
        }
        if maxx > minx { ratio = ratio / (maxx - minx) }
        i = 0usize
        while i < n {
            let phi = (res[i * 2usize] - minx) * ratio
            let rr = res[i * 2usize + 1usize]
            res[i * 2usize] = rr * math.cos[f64](phi)
            res[i * 2usize + 1usize] = rr * math.sin[f64](phi)
            i += 1usize
        }
    }
    if flip && n > 0usize {
        var mx = res[1usize]
        i = 1usize
        while i < n {
            if res[i * 2usize + 1usize] > mx { mx = res[i * 2usize + 1usize] }
            i += 1usize
        }
        i = 0usize
        while i < n {
            res[i * 2usize + 1usize] = mx - res[i * 2usize + 1usize]
            i += 1usize
        }
    }
    ret res[0usize..2usize * n]
}
