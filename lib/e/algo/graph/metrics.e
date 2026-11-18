// R igraph, the closed-form structure measures of a simple undirected graph given as a row-major 0/1 adjacency
// matrix: `transitivity` (global, local and average, isolates counted as zero), `coreness`,
// `assortativity_degree`, Jaccard and Dice `similarity`, `eccentricity`, `radius` and `diameter`.
//
// Not here: the directed variants, weights, cluster_walktrap, cluster_fast_greedy, cluster_infomap,
// cluster_optimal, motifs, triad_census, dominator_tree, bridges, gomory_hu_tree, connectivity, cohesive_blocks.

use e.math
use e.mem

fn degree(adj: []const f64, n: usize, v: usize) -> f64 {
    var d = 0.0f64
    var j = 0usize
    while j < n {
        if j != v { d += adj[v * n + j] }
        j += 1usize
    }
    ret d
}

// triangles through v
fn triangles(adj: []const f64, n: usize, v: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            if i != v && j != v && adj[v * n + i] != 0.0f64 && adj[v * n + j] != 0.0f64 && adj[i * n + j] != 0.0f64 { t += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

// global transitivity: 3 * triangles / connected triples
fn transitivity_global(adj: []const f64, n: usize) -> f64 {
    var tri = 0.0f64
    var trip = 0.0f64
    var v = 0usize
    while v < n {
        tri += triangles(adj, n, v)
        let d = degree(adj, n, v)
        trip += d * (d - 1.0f64) / 2.0f64
        v += 1usize
    }
    ret tri / trip
}

fn transitivity_local(adj: []const f64, n: usize, v: usize) -> f64 {
    let d = degree(adj, n, v)
    if d < 2.0f64 { ret 0.0f64 }
    ret triangles(adj, n, v) / (d * (d - 1.0f64) / 2.0f64)
}

fn transitivity_average(adj: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var v = 0usize
    while v < n {
        s += transitivity_local(adj, n, v)
        v += 1usize
    }
    ret s / f64(n)
}

// coreness of every vertex by repeated removal of the minimum-degree vertex; out has n slots
fn coreness(adj: []const f64, n: usize, out: []f64, deg: []f64, gone: []bool) {
    var v = 0usize
    while v < n {
        deg[v] = degree(adj, n, v)
        gone[v] = false
        v += 1usize
    }
    var k = 0.0f64
    var left = n
    while left > 0usize {
        var best = n
        v = 0usize
        while v < n {
            if !gone[v] && (best == n || deg[v] < deg[best]) { best = v }
            v += 1usize
        }
        if deg[best] > k { k = deg[best] }
        out[best] = k
        gone[best] = true
        var j = 0usize
        while j < n {
            if !gone[j] && j != best && adj[best * n + j] != 0.0f64 { deg[j] -= 1.0f64 }
            j += 1usize
        }
        left -= 1usize
    }
}

// degree assortativity: the Pearson correlation of the degrees at the two ends of every edge (both orientations)
fn assortativity_degree(adj: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var sx = 0.0f64
    var sxx = 0.0f64
    var sxy = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i != j && adj[i * n + j] != 0.0f64 {
                let a = degree(adj, n, i)
                let b = degree(adj, n, j)
                m += 1.0f64
                sx += a
                sxx += a * a
                sxy += a * b
            }
            j += 1usize
        }
        i += 1usize
    }
    let mean = sx / m
    ret (sxy / m - mean * mean) / (sxx / m - mean * mean)
}

// neighbour-set similarity of i and j: dice false is Jaccard
fn similarity(adj: []const f64, n: usize, i: usize, j: usize, dice: bool) -> f64 {
    var both = 0.0f64
    var either = 0.0f64
    var ni = 0.0f64
    var nj = 0.0f64
    var k = 0usize
    while k < n {
        let a = k != i && adj[i * n + k] != 0.0f64
        let b = k != j && adj[j * n + k] != 0.0f64
        if a { ni += 1.0f64 }
        if b { nj += 1.0f64 }
        if a && b { both += 1.0f64 }
        if a || b { either += 1.0f64 }
        k += 1usize
    }
    if dice {
        if ni + nj == 0.0f64 { ret 0.0f64 }
        ret 2.0f64 * both / (ni + nj)
    }
    if either == 0.0f64 { ret 0.0f64 }
    ret both / either
}

// breadth-first distances from s into dist (-1 for unreachable)
fn distances(adj: []const f64, n: usize, s: usize, dist: []i64, queue: []usize) {
    var i = 0usize
    while i < n {
        dist[i] = 0i64 - 1i64
        i += 1usize
    }
    dist[s] = 0i64
    queue[0usize] = s
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let u = queue[head]
        head += 1usize
        var j = 0usize
        while j < n {
            if j != u && adj[u * n + j] != 0.0f64 && dist[j] < 0i64 {
                dist[j] = dist[u] + 1i64
                queue[tail] = j
                tail += 1usize
            }
            j += 1usize
        }
    }
}

fn eccentricity(adj: []const f64, n: usize, v: usize, dist: []i64, queue: []usize) -> f64 {
    distances(adj, n, v, dist, queue)
    var best = 0i64
    var i = 0usize
    while i < n {
        if dist[i] > best { best = dist[i] }
        i += 1usize
    }
    ret f64(best)
}

// the Davis-Leinhardt triad census of a directed graph (adj[i * n + j] = 1 for an arc i -> j), class k in igraph's order: 003 012 102 021D 021U 021C 111D 111U 030T 030C 201 120D 120U 120C 210 300
fn triad_class(ab: bool, ba: bool, ac: bool, ca: bool, bc: bool, cb: bool) -> usize {
    var m = 0usize
    var asy = 0usize
    if ab && ba { m += 1usize } else if ab || ba { asy += 1usize }
    if ac && ca { m += 1usize } else if ac || ca { asy += 1usize }
    if bc && cb { m += 1usize } else if bc || cb { asy += 1usize }
    let nul = 3usize - m - asy
    if m == 0usize && asy == 0usize { ret 0usize }
    if m == 0usize && asy == 1usize { ret 1usize }
    if m == 1usize && asy == 0usize { ret 2usize }
    // out and in degrees inside the triad over the asymmetric arcs and the mutual ones
    var outd: [3]usize = zero
    var ind: [3]usize = zero
    if ab {
        outd[0usize] += 1usize
        ind[1usize] += 1usize
    }
    if ba {
        outd[1usize] += 1usize
        ind[0usize] += 1usize
    }
    if ac {
        outd[0usize] += 1usize
        ind[2usize] += 1usize
    }
    if ca {
        outd[2usize] += 1usize
        ind[0usize] += 1usize
    }
    if bc {
        outd[1usize] += 1usize
        ind[2usize] += 1usize
    }
    if cb {
        outd[2usize] += 1usize
        ind[1usize] += 1usize
    }
    if m == 0usize && asy == 2usize {
        // 021D: one vertex sends both arcs, 021U: one receives both, 021C: a path
        var k = 0usize
        while k < 3usize {
            if outd[k] == 2usize { ret 3usize }
            if ind[k] == 2usize { ret 4usize }
            k += 1usize
        }
        ret 5usize
    }
    if m == 1usize && asy == 1usize {
        // the vertex outside the mutual pair: 111D is "A<->B<-C" (the other arc points into the pair), 111U is "A<->B->C"
        var k = 0usize
        var outside = 0usize
        var kk = 0usize
        while kk < 3usize {
            let mutu = (kk == 0usize && ((ab && ba) || (ac && ca))) || (kk == 1usize && ((ab && ba) || (bc && cb))) || (kk == 2usize && ((ac && ca) || (bc && cb)))
            if !mutu { outside = kk }
            kk += 1usize
        }
        k = outside
        // the asymmetric arc touches the outside vertex: it points out of it (then B<-C: 111D) or into it (111U)
        if outd[k] == 1usize { ret 6usize }
        ret 7usize
    }
    if m == 0usize && asy == 3usize {
        var cyc = true
        var k = 0usize
        while k < 3usize {
            if outd[k] != 1usize { cyc = false }
            k += 1usize
        }
        if cyc { ret 9usize }
        ret 8usize
    }
    if m == 2usize && asy == 0usize { ret 10usize }
    if m == 1usize && asy == 2usize {
        // 120D: the asymmetric arcs leave a common vertex, 120U: they enter one, 120C: a path through the mutual pair's ends
        var k = 0usize
        while k < 3usize {
            let mut_deg = (k == 0usize && ((ab && ba) || (ac && ca))) || (k == 1usize && ((ab && ba) || (bc && cb))) || (k == 2usize && ((ac && ca) || (bc && cb)))
            if !mut_deg {
                if outd[k] == 2usize { ret 11usize }
                if ind[k] == 2usize { ret 12usize }
            }
            k += 1usize
        }
        ret 13usize
    }
    if m == 2usize && asy == 1usize { ret 14usize }
    ret 15usize
}

fn triad_census(adj: []const f64, n: usize, k: usize) -> f64 {
    var cnt = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var l = j + 1usize
            while l < n {
                let c = triad_class(adj[i * n + j] != 0.0f64, adj[j * n + i] != 0.0f64, adj[i * n + l] != 0.0f64, adj[l * n + i] != 0.0f64, adj[j * n + l] != 0.0f64, adj[l * n + j] != 0.0f64)
                if c == k { cnt += 1.0f64 }
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret cnt
}

// the number of mutual arcs (which_mutual TRUE count, loops excluded)
fn mutual_count(adj: []const f64, n: usize) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i != j && adj[i * n + j] != 0.0f64 && adj[j * n + i] != 0.0f64 { c += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

// connected components of the undirected graph with edge (u, v) removed when skip_u < n
fn comp_count(adj: []const f64, n: usize, skip_u: usize, skip_v: usize, seen: []bool, stack: []usize) -> usize {
    var i = 0usize
    while i < n {
        seen[i] = false
        i += 1usize
    }
    var comps = 0usize
    var s = 0usize
    while s < n {
        if !seen[s] {
            comps += 1usize
            var top = 0usize
            stack[0usize] = s
            top = 1usize
            seen[s] = true
            while top > 0usize {
                top -= 1usize
                let u = stack[top]
                var v = 0usize
                while v < n {
                    var edge = adj[u * n + v] != 0.0f64 && u != v
                    if (u == skip_u && v == skip_v) || (u == skip_v && v == skip_u) { edge = false }
                    if edge && !seen[v] {
                        seen[v] = true
                        stack[top] = v
                        top += 1usize
                    }
                    v += 1usize
                }
            }
        }
        s += 1usize
    }
    ret comps
}

// the bridges of an undirected simple graph: the number, and the sum over bridges (u < v) of (u + 1) * n + v + 1 (a position-weighted digest)
fn bridges(a: *mem.Arena, adj: []const f64, n: usize, digest: bool) -> f64 {
    let (seen, e1) = mem.alloc[bool](a, n)
    let (stack, e2) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let base = comp_count(adj, n, n, n, seen, stack)
    var cnt = 0.0f64
    var w = 0.0f64
    var u = 0usize
    while u < n {
        var v = u + 1usize
        while v < n {
            if adj[u * n + v] != 0.0f64 {
                if comp_count(adj, n, u, v, seen, stack) > base {
                    cnt += 1.0f64
                    w += f64((u + 1usize) * n + v + 1usize)
                }
            }
            v += 1usize
        }
        u += 1usize
    }
    if digest { ret w }
    ret cnt
}

// the maximum flow from s to t on the capacity matrix cap (modified in place), by augmenting breadth-first paths
fn max_flow(a: *mem.Arena, cap: []f64, nn: usize, s: usize, t: usize) -> f64 {
    let (prev, e1) = mem.alloc[i64](a, nn)
    let (queue, e2) = mem.alloc[usize](a, nn)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var flow = 0.0f64
    while true {
        var i = 0usize
        while i < nn {
            prev[i] = 0i64 - 1i64
            i += 1usize
        }
        prev[s] = i64(s)
        var head = 0usize
        var tail = 1usize
        queue[0usize] = s
        while head < tail && prev[t] < 0i64 {
            let u = queue[head]
            head += 1usize
            var v = 0usize
            while v < nn {
                if prev[v] < 0i64 && cap[u * nn + v] > 0.0f64 {
                    prev[v] = i64(u)
                    queue[tail] = v
                    tail += 1usize
                }
                v += 1usize
            }
        }
        if prev[t] < 0i64 { break }
        var bott = 1.0e18f64
        var v = t
        while v != s {
            let u = usize(prev[v])
            if cap[u * nn + v] < bott { bott = cap[u * nn + v] }
            v = u
        }
        v = t
        while v != s {
            let u = usize(prev[v])
            cap[u * nn + v] = cap[u * nn + v] - bott
            cap[v * nn + u] = cap[v * nn + u] + bott
            v = u
        }
        flow += bott
    }
    ret flow
}

// edge_connectivity of an undirected simple graph: the smallest s-t maximum flow with unit capacities over t, s = 0
fn edge_connectivity(a: *mem.Arena, adj: []const f64, n: usize) -> f64 {
    let (cap, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var best = 1.0e18f64
    var t = 1usize
    while t < n {
        var i = 0usize
        while i < n * n {
            cap[i] = 0.0f64
            if adj[i] != 0.0f64 { cap[i] = 1.0f64 }
            i += 1usize
        }
        let f = max_flow(a, cap, n, 0usize, t)
        if f < best { best = f }
        t += 1usize
    }
    ret best
}

// vertex_connectivity of an undirected simple graph: n - 1 for a complete graph, else the smallest number of internally disjoint paths over non-adjacent pairs (vertex splitting)
fn vertex_connectivity(a: *mem.Arena, adj: []const f64, n: usize) -> f64 {
    let nn = 2usize * n
    let (cap, e1) = mem.alloc[f64](a, nn * nn)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var best = f64(n - 1usize)
    var s = 0usize
    while s < n {
        var t = s + 1usize
        while t < n {
            if adj[s * n + t] == 0.0f64 {
                var i = 0usize
                while i < nn * nn {
                    cap[i] = 0.0f64
                    i += 1usize
                }
                var v = 0usize
                while v < n {
                    // v_in = v, v_out = n + v
                    cap[v * nn + n + v] = 1.0f64
                    var w = 0usize
                    while w < n {
                        if adj[v * n + w] != 0.0f64 && v != w { cap[(n + v) * nn + w] = 1.0f64 }
                        w += 1usize
                    }
                    v += 1usize
                }
                cap[s * nn + n + s] = 1.0e9f64
                cap[t * nn + n + t] = 1.0e9f64
                let f = max_flow(a, cap, nn, s, n + t)
                if f < best { best = f }
            }
            t += 1usize
        }
        s += 1usize
    }
    ret best
}

// similarity(method = "invlogweighted") of the pair (i, j): common neighbours k weighted by 1 / ln(degree k)
fn similarity_invlog(adj: []const f64, n: usize, i: usize, j: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < n {
        if adj[i * n + k] != 0.0f64 && adj[j * n + k] != 0.0f64 {
            var d = 0.0f64
            var l = 0usize
            while l < n {
                if adj[k * n + l] != 0.0f64 { d += 1.0f64 }
                l += 1usize
            }
            s += 1.0f64 / math.log[f64](d)
        }
        k += 1usize
    }
    ret s
}

// motifs(g, 3) of an undirected simple graph: the induced subgraphs on three vertices with two edges (class 2, open triads) and with three (class 3, triangles)
fn motifs3(adj: []const f64, n: usize, class: usize) -> f64 {
    var cnt = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var l = j + 1usize
            while l < n {
                var e = 0usize
                if adj[i * n + j] != 0.0f64 { e += 1usize }
                if adj[i * n + l] != 0.0f64 { e += 1usize }
                if adj[j * n + l] != 0.0f64 { e += 1usize }
                if e == class { cnt += 1.0f64 }
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret cnt
}

// dominator_tree(g, root)$dom of a directed graph (arcs adj[i * n + j]): the immediate dominator of vertex v (0-based) by the iterative data-flow of Cooper, Harvey and Kennedy over a
// reverse post-order; the root and an unreachable vertex answer -1 (as the R package returns them), idom has n entries
fn dominator_idom(a: *mem.Arena, adj: []const f64, n: usize, root: usize, idom: []f64) {
    let (order, e1) = mem.alloc[usize](a, n)
    let (num, e2) = mem.alloc[i64](a, n)
    let (dom, e3) = mem.alloc[i64](a, n)
    let (stk, e4) = mem.alloc[usize](a, n * n + 1usize)
    let (it, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret }
    var i = 0usize
    while i < n {
        num[i] = 0i64 - 1i64
        dom[i] = 0i64 - 1i64
        it[i] = 0usize
        i += 1usize
    }
    // depth-first post-order from the root
    var cnt = 0usize
    var top = 1usize
    stk[0usize] = root
    num[root] = 0i64
    var seen_mark = 1usize
    var post = 0usize
    let (postv, e6) = mem.alloc[usize](a, n)
    if e6 != ok { ret }
    while top > 0usize {
        let u = stk[top - 1usize]
        if it[u] < n {
            let v = it[u]
            it[u] += 1usize
            if adj[u * n + v] != 0.0f64 && u != v && num[v] < 0i64 {
                num[v] = i64(seen_mark)
                seen_mark += 1usize
                stk[top] = v
                top += 1usize
            }
        } else {
            postv[post] = u
            post += 1usize
            top -= 1usize
        }
    }
    // post-order numbers: a larger number is closer to the root
    var pn: [64]i64 = zero
    var q = 0usize
    while q < post {
        pn[postv[q]] = i64(q)
        q += 1usize
    }
    dom[root] = i64(root)
    var changed = true
    while changed {
        changed = false
        var k = post
        while k > 0usize {
            k -= 1usize
            let b = postv[k]
            if b != root {
                var newd = 0i64 - 1i64
                var p2 = 0usize
                while p2 < n {
                    if adj[p2 * n + b] != 0.0f64 && p2 != b && num[p2] >= 0i64 && dom[p2] >= 0i64 {
                        if newd < 0i64 {
                            newd = i64(p2)
                        } else {
                            var f1 = usize(p2)
                            var f2 = usize(newd)
                            while f1 != f2 {
                                while pn[f1] < pn[f2] { f1 = usize(dom[f1]) }
                                while pn[f2] < pn[f1] { f2 = usize(dom[f2]) }
                            }
                            newd = i64(f1)
                        }
                    }
                    p2 += 1usize
                }
                if dom[b] != newd {
                    dom[b] = newd
                    changed = true
                }
            }
        }
    }
    cnt = 0usize
    while cnt < n {
        if num[cnt] < 0i64 {
            idom[cnt] = 0.0f64 - 1.0f64
        } else if cnt == root {
            idom[cnt] = 0.0f64 - 1.0f64
        } else {
            idom[cnt] = f64(dom[cnt])
        }
        cnt += 1usize
    }
}
