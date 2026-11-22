// R sna on a directed adjacency matrix (n by n, row-major, zero diagonal): degree, Freeman betweenness, stress, closeness and graph centrality, density, Freeman centralization of degree, betweenness and closeness, and eigenvector centrality.
//
// Also: dyad and triad census, connectedness, hierarchy, prestige, infocent, sedist and blockmodel block contents (equiv.clust is sedist then e.algo.stat.hclust), netlm and netlogit (qap with Dekker semi-partialling, qapy, qapx, qapallx and classical nulls, t, z or beta statistics) and qaptest for gcor and hdist, all on R's rmperm draws.
// Not here: undirected modes, valued graphs, transitivity, the cug nulls, prestige by rowcolnorm or eigen, ERGM-style models.

use e.algo.linalg.matrix as mx
use e.math
use e.mem
use e.algo.rand.r as rrand
use e.algo.linalg.decomp as dcmp
use e.algo.stat.armglm as aglm
use e.math.nmath_beta as nb

// per node: out degree, in degree, total degree, betweenness, stress, closeness, graph centrality, eigenvector centrality (8 blocks of n in out); returns the density in the 9th slot of out (out has 8n + 1 values)
fn centrality(a: *mem.Arena, g: []const f64, n: usize, out: []f64) -> err {
    let (dist, e1) = mem.alloc[f64](a, n)
    let (sig, e2) = mem.alloc[f64](a, n)
    let (dep, e3) = mem.alloc[f64](a, n)
    let (st, e4) = mem.alloc[f64](a, n)
    let (queue, e5) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < 8usize * n + 1usize {
        out[i] = 0.0f64
        i += 1usize
    }
    var m = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if g[i * n + j] > 0.5f64 {
                out[i] += 1.0f64
                out[n + j] += 1.0f64
                m += 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[2usize * n + i] = out[i] + out[n + i]
        i += 1usize
    }
    out[8usize * n] = m / (f64(n) * f64(n - 1usize))
    var s = 0usize
    while s < n {
        i = 0usize
        while i < n {
            dist[i] = 0.0f64 - 1.0f64
            sig[i] = 0.0f64
            dep[i] = 0.0f64
            st[i] = 0.0f64
            i += 1usize
        }
        var head = 0usize
        var tail = 0usize
        queue[tail] = s
        tail += 1usize
        dist[s] = 0.0f64
        sig[s] = 1.0f64
        while head < tail {
            let v = queue[head]
            head += 1usize
            var w = 0usize
            while w < n {
                if g[v * n + w] > 0.5f64 {
                    if dist[w] < 0.0f64 {
                        dist[w] = dist[v] + 1.0f64
                        queue[tail] = w
                        tail += 1usize
                    }
                    if dist[w] == dist[v] + 1.0f64 { sig[w] += sig[v] }
                }
                w += 1usize
            }
        }
        var sumd = 0.0f64
        var maxd = 0.0f64
        i = 0usize
        while i < n {
            if i != s && dist[i] > 0.0f64 {
                sumd += dist[i]
                if dist[i] > maxd { maxd = dist[i] }
            }
            i += 1usize
        }
        if sumd > 0.0f64 && tail == n {
            out[5usize * n + s] = f64(n - 1usize) / sumd
            out[6usize * n + s] = 1.0f64 / maxd
        }
        // back-propagate in reverse BFS order
        var q = tail
        while q > 0usize {
            q -= 1usize
            let w = queue[q]
            var v = 0usize
            while v < n {
                if g[v * n + w] > 0.5f64 && dist[v] >= 0.0f64 && dist[w] == dist[v] + 1.0f64 {
                    dep[v] += sig[v] / sig[w] * (1.0f64 + dep[w])
                    st[v] += 1.0f64 + st[w]
                }
                v += 1usize
            }
        }
        i = 0usize
        while i < n {
            if i != s {
                out[3usize * n + i] += dep[i]
                out[4usize * n + i] += sig[i] * st[i]
            }
            i += 1usize
        }
        s += 1usize
    }
    // eigenvector centrality: the dominant right eigenvector of the adjacency matrix by power iteration on (g + I), unit length
    let (v, e6) = mem.alloc[f64](a, n)
    let (v2, e7) = mem.alloc[f64](a, n)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    i = 0usize
    while i < n {
        v[i] = 1.0f64 / math.sqrt[f64](f64(n))
        i += 1usize
    }
    var it = 0usize
    while it < 20000usize {
        var nv = 0.0f64
        i = 0usize
        while i < n {
            var sx = v[i]
            var j = 0usize
            while j < n {
                sx += g[i * n + j] * v[j]
                j += 1usize
            }
            v2[i] = sx
            nv += sx * sx
            i += 1usize
        }
        nv = math.sqrt[f64](nv)
        var diff = 0.0f64
        i = 0usize
        while i < n {
            let nw = v2[i] / nv
            diff += math.abs[f64](nw - v[i])
            v[i] = nw
            i += 1usize
        }
        if diff < 1.0e-15f64 { break }
        it += 1usize
    }
    i = 0usize
    while i < n {
        out[7usize * n + i] = v[i]
        i += 1usize
    }
    ret ok
}

// Freeman centralization of the vector c against the theoretical maximum tmax
fn centralization(c: []const f64, tmax: f64) -> f64 {
    var mx0 = c[0usize]
    var i = 1usize
    while i < c.len {
        if c[i] > mx0 { mx0 = c[i] }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < c.len {
        s += mx0 - c[i]
        i += 1usize
    }
    ret s / tmax
}

fn edge(g: []const f64, n: usize, i: usize, j: usize) -> bool {
    ret g[i * n + j] > 0.5f64
}

// dyad.census: out = mutual, asymmetric, null dyads
fn dyad_census(g: []const f64, n: usize, out: []f64) {
    out[0usize] = 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let x = edge(g, n, i, j)
            let y = edge(g, n, j, i)
            if x && y {
                out[0usize] += 1.0f64
            } else if x || y {
                out[1usize] += 1.0f64
            } else {
                out[2usize] += 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
}

// Davis-Leinhardt class in sna's order from the dyad census (m mutual, asym asymmetric), the out and in degrees of the three nodes over asymmetric ties, and whether the head of the single asymmetric tie of a 111 triad lies in the mutual dyad
fn tri_class(m: usize, asym: usize, od: []const usize, id: []const usize, mutual_in: bool) -> usize {
    let anyout = od[0usize] == 2usize || od[1usize] == 2usize || od[2usize] == 2usize
    let anyin = id[0usize] == 2usize || id[1usize] == 2usize || id[2usize] == 2usize
    if m == 0usize && asym == 0usize { ret 0usize }
    if m == 0usize && asym == 1usize { ret 1usize }
    if m == 1usize && asym == 0usize { ret 2usize }
    if m == 0usize && asym == 2usize {
        if anyout { ret 3usize }
        if anyin { ret 4usize }
        ret 5usize
    }
    if m == 1usize && asym == 1usize {
        if mutual_in { ret 6usize }
        ret 7usize
    }
    if m == 0usize && asym == 3usize {
        if od[0usize] == 1usize && od[1usize] == 1usize && od[2usize] == 1usize { ret 9usize }
        ret 8usize
    }
    if m == 2usize && asym == 0usize { ret 10usize }
    if m == 1usize && asym == 2usize {
        if anyout { ret 11usize }
        if anyin { ret 12usize }
        ret 13usize
    }
    if m == 2usize && asym == 1usize { ret 14usize }
    ret 15usize
}

// triad.census over the 16 digraph classes (003 012 102 021D 021U 021C 111D 111U 030T 030C 201 120D 120U 120C 210 300); out has 16 values
fn triad_census(a: *mem.Arena, g: []const f64, n: usize, out: []f64) -> err {
    let (od, e1) = mem.alloc[usize](a, 3usize)
    let (id, e2) = mem.alloc[usize](a, 3usize)
    let (mu, e3) = mem.alloc[bool](a, 3usize)
    let (nd, e4) = mem.alloc[usize](a, 3usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var k = 0usize
    while k < 16usize {
        out[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var l = j + 1usize
            while l < n {
                nd[0usize] = i
                nd[1usize] = j
                nd[2usize] = l
                k = 0usize
                while k < 3usize {
                    od[k] = 0usize
                    id[k] = 0usize
                    mu[k] = false
                    k += 1usize
                }
                var m = 0usize
                var asym = 0usize
                var head = 0usize
                var sx = 0usize
                while sx < 3usize {
                    var sy = sx + 1usize
                    while sy < 3usize {
                        let xy = edge(g, n, nd[sx], nd[sy])
                        let yx = edge(g, n, nd[sy], nd[sx])
                        if xy && yx {
                            m += 1usize
                            mu[sx] = true
                            mu[sy] = true
                        } else if xy || yx {
                            asym += 1usize
                            var from = sx
                            var to = sy
                            if yx {
                                from = sy
                                to = sx
                            }
                            od[from] += 1usize
                            id[to] += 1usize
                            head = to
                        }
                        sy += 1usize
                    }
                    sx += 1usize
                }
                let c = tri_class(m, asym, od, id, mu[head])
                out[c] += 1.0f64
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// reachability: r[i][j] = 1 when a path leads from i to j (diagonal 1), by Warshall closure
fn reach_all(g: []const f64, n: usize, r: []f64) {
    var i = 0usize
    while i < n * n {
        r[i] = 0.0f64
        if g[i] > 0.5f64 { r[i] = 1.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < n {
        r[i * n + i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < n {
        i = 0usize
        while i < n {
            if r[i * n + k] > 0.5f64 {
                var j = 0usize
                while j < n {
                    if r[k * n + j] > 0.5f64 { r[i * n + j] = 1.0f64 }
                    j += 1usize
                }
            }
            i += 1usize
        }
        k += 1usize
    }
}

// Krackhardt connectedness: the share of node pairs joined by a semipath
fn connectedness(a: *mem.Arena, g: []const f64, n: usize) -> (f64, err) {
    if n <= 1usize { ret (1.0f64, ok) }
    let (s, e1) = mem.alloc[f64](a, n * n)
    let (r, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            s[i * n + j] = 0.0f64
            if edge(g, n, i, j) || edge(g, n, j, i) { s[i * n + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    reach_all(s, n, r)
    var c = 0.0f64
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            c += r[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (c / (f64(n) * f64(n - 1usize) / 2.0f64), ok)
}

// hierarchy: measure 0 is one minus dyadic reciprocity; measure 1 is Krackhardt's, one minus the mutual share of connected dyads of the reachability graph
fn hierarchy(a: *mem.Arena, g: []const f64, n: usize, measure: usize) -> (f64, err) {
    let (r, e1) = mem.alloc[f64](a, n * n)
    let (dc, e2) = mem.alloc[f64](a, 3usize)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if measure == 0usize {
        dyad_census(g, n, dc)
        ret (1.0f64 - (dc[0usize] + dc[2usize]) / (dc[0usize] + dc[1usize] + dc[2usize]), ok)
    }
    reach_all(g, n, r)
    dyad_census(r, n, dc)
    ret (1.0f64 - dc[0usize] / (dc[0usize] + dc[1usize]), ok)
}

// prestige: cmode 0 indegree, 1 indegree.rownorm, 2 eigenvector, 3 domain, 4 domain.proximity; out has n values
fn prestige(a: *mem.Arena, g: []const f64, n: usize, cmode: usize, out: []f64) -> err {
    var j = 0usize
    var i = 0usize
    if cmode == 0usize || cmode == 1usize {
        while j < n {
            var s = 0.0f64
            i = 0usize
            while i < n {
                var rs = 1.0f64
                if cmode == 1usize {
                    rs = 0.0f64
                    var k = 0usize
                    while k < n {
                        rs += g[i * n + k]
                        k += 1usize
                    }
                }
                if g[i * n + j] != 0.0f64 && rs != 0.0f64 { s += g[i * n + j] / rs }
                i += 1usize
            }
            out[j] = s
            j += 1usize
        }
        ret ok
    }
    if cmode == 2usize {
        let (t, e1) = mem.alloc[f64](a, n * n)
        let (o, e2) = mem.alloc[f64](a, 8usize * n + 1usize)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                t[j * n + i] = g[i * n + j]
                j += 1usize
            }
            i += 1usize
        }
        let e3 = centrality(a, t, n, o)
        if e3 != ok { ret e3 }
        i = 0usize
        while i < n {
            out[i] = o[7usize * n + i]
            i += 1usize
        }
        ret ok
    }
    let (r, e4) = mem.alloc[f64](a, n * n)
    if e4 != ok { ret e4 }
    if cmode == 3usize {
        reach_all(g, n, r)
        j = 0usize
        while j < n {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += r[i * n + j]
                i += 1usize
            }
            out[j] = s - 1.0f64
            j += 1usize
        }
        ret ok
    }
    // domain.proximity: geodesic distances by Floyd-Warshall; a node some other node cannot reach scores 0 (R multiplies FALSE by Inf into NaN)
    let inf = 1.0e300f64
    i = 0usize
    while i < n * n {
        r[i] = inf
        if g[i] > 0.5f64 { r[i] = 1.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < n {
        r[i * n + i] = 0.0f64
        i += 1usize
    }
    var k = 0usize
    while k < n {
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                if r[i * n + k] + r[k * n + j] < r[i * n + j] { r[i * n + j] = r[i * n + k] + r[k * n + j] }
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    j = 0usize
    while j < n {
        var s = 0.0f64
        var every = true
        i = 0usize
        while i < n {
            if r[i * n + j] >= inf { every = false }
            s += r[i * n + j]
            i += 1usize
        }
        out[j] = 0.0f64
        if every { out[j] = f64(n - 1usize) * f64(n - 1usize) / (s * f64(n - 1usize)) }
        j += 1usize
    }
    ret ok
}

// infocent (Stephenson-Zelen) of the weakly symmetrized graph; isolates score 0
fn infocent(a: *mem.Arena, g: []const f64, n: usize, out: []f64) -> err {
    let (ix, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    var k = 0usize
    var i = 0usize
    while i < n {
        out[i] = 0.0f64
        var iso = true
        var j = 0usize
        while j < n {
            if i != j && (edge(g, n, i, j) || edge(g, n, j, i)) { iso = false }
            j += 1usize
        }
        if !iso {
            ix[k] = i
            k += 1usize
        }
        i += 1usize
    }
    if k == 0usize { ret ok }
    let (m, e2) = mem.alloc[f64](a, k * k)
    let (inv, e3) = mem.alloc[f64](a, k * k)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    i = 0usize
    while i < k {
        var deg = 0.0f64
        var j = 0usize
        while j < k {
            var s = 0.0f64
            if i != j && (edge(g, n, ix[i], ix[j]) || edge(g, n, ix[j], ix[i])) { s = 1.0f64 }
            deg += s
            m[i * k + j] = 1.0f64 - s
            inv[i * k + j] = 0.0f64
            j += 1usize
        }
        m[i * k + i] = 1.0f64 + deg
        inv[i * k + i] = 1.0f64
        i += 1usize
    }
    // Gauss-Jordan with partial pivoting
    var c = 0usize
    while c < k {
        var p = c
        var r = c + 1usize
        while r < k {
            if math.abs[f64](m[r * k + c]) > math.abs[f64](m[p * k + c]) { p = r }
            r += 1usize
        }
        var q = 0usize
        if p != c {
            while q < k {
                let t1 = m[c * k + q]
                m[c * k + q] = m[p * k + q]
                m[p * k + q] = t1
                let t2 = inv[c * k + q]
                inv[c * k + q] = inv[p * k + q]
                inv[p * k + q] = t2
                q += 1usize
            }
        }
        let pv = m[c * k + c]
        q = 0usize
        while q < k {
            m[c * k + q] = m[c * k + q] / pv
            inv[c * k + q] = inv[c * k + q] / pv
            q += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = m[r * k + c]
                if f != 0.0f64 {
                    q = 0usize
                    while q < k {
                        m[r * k + q] = m[r * k + q] - f * m[c * k + q]
                        inv[r * k + q] = inv[r * k + q] - f * inv[c * k + q]
                        q += 1usize
                    }
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    var tr = 0.0f64
    i = 0usize
    while i < k {
        tr += inv[i * k + i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        var rsum = 0.0f64
        var j = 0usize
        while j < k {
            rsum += inv[i * k + j]
            j += 1usize
        }
        out[ix[i]] = 1.0f64 / (inv[i * k + i] + (tr - 2.0f64 * rsum) / f64(n))
        i += 1usize
    }
    ret ok
}

// sedist with joint analysis over one graph (diagonal removed): method 0 correlation, 1 euclidean, 2 hamming, 3 gamma, 4 exact; code_diss negates correlation and gamma; out is n by n
fn sedist(a: *mem.Arena, g: []const f64, n: usize, method: usize, code_diss: bool, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    let (v, e1) = mem.alloc[f64](a, 2usize * n * n)
    if e1 != ok { ret e1 }
    // v[r * n + i] is entry r of column i: row i of g for r < n, column i for r >= n; the removed diagonal is NaN
    var i = 0usize
    while i < n {
        var r = 0usize
        while r < n {
            var x = g[i * n + r]
            var y = g[r * n + i]
            if r == i {
                x = nan
                y = nan
            }
            v[r * n + i] = x
            v[(n + r) * n + i] = y
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var cnt = 0.0f64
            var sx = 0.0f64
            var sy = 0.0f64
            var ham = 0.0f64
            var sq = 0.0f64
            var conc = 0.0f64
            var disc = 0.0f64
            var r = 0usize
            while r < 2usize * n {
                let x = v[r * n + i]
                let y = v[r * n + j]
                if x == x && y == y {
                    cnt += 1.0f64
                    sx += x
                    sy += y
                    ham += math.abs[f64](x - y)
                    sq += (x - y) * (x - y)
                    if x == y { conc += 1.0f64 }
                    if x != y { disc += 1.0f64 }
                }
                r += 1usize
            }
            var val = 0.0f64
            if method == 0usize {
                let mxx = sx / cnt
                let myy = sy / cnt
                var sxy = 0.0f64
                var sxx = 0.0f64
                var syy = 0.0f64
                r = 0usize
                while r < 2usize * n {
                    let x = v[r * n + i]
                    let y = v[r * n + j]
                    if x == x && y == y {
                        sxy += (x - mxx) * (y - myy)
                        sxx += (x - mxx) * (x - mxx)
                        syy += (y - myy) * (y - myy)
                    }
                    r += 1usize
                }
                val = sxy / (math.sqrt[f64](sxx) * math.sqrt[f64](syy))
                if code_diss { val = 0.0f64 - val }
            }
            if method == 1usize { val = math.sqrt[f64](sq) }
            if method == 2usize { val = ham }
            if method == 3usize {
                val = (conc - disc) / (conc + disc)
                if code_diss { val = 0.0f64 - val }
            }
            if method == 4usize {
                if disc > 0.0f64 { val = 1.0f64 }
            }
            out[i * n + j] = val
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// blockmodel block content over a partition memb (labels 1..k, one per node), the diagonal of g removed; content 0 density, 1 sum, 2 median, 3 min, 4 max, 5 meanrowsum, 6 meancolsum; out is k by k
fn blockmodel(a: *mem.Arena, g: []const f64, n: usize, memb: []const usize, k: usize, content: usize, out: []f64) -> err {
    let (vals, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    var bj = 1usize
    while bj <= k {
        var bk = 1usize
        while bk <= k {
            var cnt = 0usize
            var sum = 0.0f64
            var mn = 1.0e300f64
            var mxv = 0.0f64 - 1.0e300f64
            var rowsum_total = 0.0f64
            var colsum_total = 0.0f64
            var nr = 0.0f64
            var nc = 0.0f64
            var i = 0usize
            while i < n {
                if memb[i] == bj {
                    nr += 1.0f64
                    var rs = 0.0f64
                    var j = 0usize
                    while j < n {
                        if memb[j] == bk && i != j {
                            let x = g[i * n + j]
                            rs += x
                            sum += x
                            vals[cnt] = x
                            cnt += 1usize
                            if x < mn { mn = x }
                            if x > mxv { mxv = x }
                        }
                        j += 1usize
                    }
                    rowsum_total += rs
                }
                i += 1usize
            }
            var j2 = 0usize
            while j2 < n {
                if memb[j2] == bk {
                    nc += 1.0f64
                    var cs = 0.0f64
                    var i2 = 0usize
                    while i2 < n {
                        if memb[i2] == bj && i2 != j2 { cs += g[i2 * n + j2] }
                        i2 += 1usize
                    }
                    colsum_total += cs
                }
                j2 += 1usize
            }
            var res = 0.0f64 / 0.0f64
            if content == 0usize && cnt > 0usize { res = sum / f64(cnt) }
            if content == 1usize { res = sum }
            if content == 3usize && cnt > 0usize { res = mn }
            if content == 4usize && cnt > 0usize { res = mxv }
            if content == 5usize { res = rowsum_total / nr }
            if content == 6usize { res = colsum_total / nc }
            if content == 2usize && cnt > 0usize {
                var p = 1usize
                while p < cnt {
                    let key = vals[p]
                    var q = p
                    while q > 0usize && vals[q - 1usize] > key {
                        vals[q] = vals[q - 1usize]
                        q -= 1usize
                    }
                    vals[q] = key
                    p += 1usize
                }
                if cnt % 2usize == 1usize {
                    res = vals[cnt / 2usize]
                } else {
                    res = (vals[cnt / 2usize - 1usize] + vals[cnt / 2usize]) / 2.0f64
                }
            }
            out[(bj - 1usize) * k + (bk - 1usize)] = res
            bk += 1usize
        }
        bj += 1usize
    }
    ret ok
}

// column-major off-diagonal entries of the n by n row-major matrix g, as sna's gvectorize lays them out
fn gvec(g: []const f64, n: usize, out: []f64) {
    var k = 0usize
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            if i != j {
                out[k] = g[i * n + j]
                k += 1usize
            }
            i += 1usize
        }
        j += 1usize
    }
}

// rmperm: one sample(1:n) draw o, then p[i][j] = m[o[i]][o[j]]
fn rmperm(a: *mem.Arena, rg: *rrand.Rng, g: []const f64, n: usize, out: []f64) -> err {
    let (o, e) = rrand.sample_int(a, rg, i64(n), i64(n), false)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = g[(usize(o[i]) - 1usize) * n + (usize(o[j]) - 1usize)]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the statistic of one fit of graph ord[0] on graphs ord[1..nx+1] of the pool (n by n matrices, row-major): kind 0 lm t-values, 1 lm coefficients, 2 glm (binomial, logit) z-values, 3 glm coefficients.
// coefs gets the coefficients, stat the statistic, ext the residual sum of squares (deviance for glm), the null deviance (NaN for lm) and the residual degrees of freedom
fn stat_fit(a: *mem.Arena, pool: []const f64, n: usize, ord: []const usize, nx: usize, kind: usize, coefs: []f64, stat: []f64, ext: []f64) -> err {
    let nn = n * n
    let m = n * (n - 1usize)
    let (y, e1) = mem.alloc[f64](a, m)
    let (xc, e2) = mem.alloc[f64](a, m * nx)
    let (xr, e3) = mem.alloc[f64](a, m * nx)
    let (col, e4) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    gvec(pool[ord[0usize] * nn..(ord[0usize] + 1usize) * nn], n, y)
    var c = 0usize
    while c < nx {
        gvec(pool[ord[1usize + c] * nn..(ord[1usize + c] + 1usize) * nn], n, col)
        var r = 0usize
        while r < m {
            xc[c * m + r] = col[r]
            xr[r * nx + c] = col[r]
            r += 1usize
        }
        c += 1usize
    }
    if kind == 0usize || kind == 1usize {
        let (f, e5) = dcmp.lm_fit(a, xc, m, nx, y, 1.0e-7f64)
        if e5 != ok { ret e5 }
        let (q, e6) = dcmp.qr(a, xc, m, nx, 1.0e-7f64)
        if e6 != ok { ret e6 }
        var rss = 0.0f64
        var i = 0usize
        while i < m {
            rss += f.residuals[i] * f.residuals[i]
            i += 1usize
        }
        ext[0usize] = rss
        ext[1usize] = 0.0f64 / 0.0f64
        ext[2usize] = f64(m - f.rank)
        c = 0usize
        while c < nx {
            coefs[c] = f.coef[c]
            c += 1usize
        }
        if kind == 1usize {
            c = 0usize
            while c < nx {
                stat[c] = f.coef[c]
                c += 1usize
            }
            ret ok
        }
        // chol2inv(R): the diagonal of Rinv Rinv', Rinv by back substitution on the upper triangle of the pivoted qr
        let (rinv, e7) = mem.alloc[f64](a, nx * nx)
        if e7 != ok { ret e7 }
        var cc = 0usize
        while cc < nx {
            var rr = nx
            while rr > 0usize {
                rr -= 1usize
                var s = 0.0f64
                if rr == cc { s = 1.0f64 }
                var k = rr + 1usize
                while k < nx {
                    s = s - q.qr[k * m + rr] * rinv[k * nx + cc]
                    k += 1usize
                }
                rinv[rr * nx + cc] = s / q.qr[rr * m + rr]
            }
            cc += 1usize
        }
        c = 0usize
        while c < nx {
            var dg = 0.0f64
            var k = 0usize
            while k < nx {
                dg += rinv[c * nx + k] * rinv[c * nx + k]
                k += 1usize
            }
            stat[c] = f.coef[c] / math.sqrt[f64](dg * rss / f64(m - f.rank))
            c += 1usize
        }
        ret ok
    }
    let (wts, e8) = mem.alloc[f64](a, m)
    let (off, e9) = mem.alloc[f64](a, m)
    let (cv, e10) = mem.alloc[f64](a, nx * nx)
    let (info, e11) = mem.alloc[f64](a, 8usize)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    var i = 0usize
    while i < m {
        wts[i] = 1.0f64
        off[i] = 0.0f64
        i += 1usize
    }
    let it = aglm.glm_fit_gen(a, xr, y, m, nx, 1usize, 3usize, wts, off, false, coefs, cv, info)
    if it == 0usize { ret NoFit }
    ext[0usize] = info[1usize]
    ext[1usize] = info[2usize]
    ext[2usize] = info[4usize]
    c = 0usize
    while c < nx {
        stat[c] = coefs[c]
        if kind == 2usize { stat[c] = coefs[c] / math.sqrt[f64](cv[c * nx + c]) }
        c += 1usize
    }
    ret ok
}

error NoFit

// netlm (kind 0 t-value, 1 beta) and netlogit (kind 2 z-value, 3 beta) of the graph y on the nx0 graphs in xs (each n by n row-major, one after another), digraph without the diagonal.
// nullhyp 0 qap (Dekker semi-partialling; qapy when only one covariate), 1 qapy, 2 qapx, 3 qapallx, 4 classical.
// out (5 nx + 3 long, nx = nx0 plus the intercept) gets the coefficients, the statistic, pleeq, pgreq, pgreqabs, then ext (see stat_fit); dist (reps by nx, row-major) gets the null distribution
fn netfit(a: *mem.Arena, rg: *rrand.Rng, y: []const f64, xs: []const f64, nx0: usize, n: usize, intercept: bool, nullhyp: usize, reps: usize, kind: usize, out: []f64, dist: []f64) -> err {
    let nn = n * n
    var nx = nx0
    if intercept { nx += 1usize }
    let (pool, e1) = mem.alloc[f64](a, (nx + 1usize) * nn)
    let (work, e2) = mem.alloc[f64](a, (nx + 1usize) * nn)
    let (ord, e3) = mem.alloc[usize](a, nx + 1usize)
    let (coefs, e4) = mem.alloc[f64](a, nx)
    let (stat, e5) = mem.alloc[f64](a, nx)
    let (ext, e6) = mem.alloc[f64](a, 3usize)
    let (xcol, e7) = mem.alloc[f64](a, nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    while i < nn {
        pool[i] = y[i]
        i += 1usize
    }
    var slot = 1usize
    if intercept {
        i = 0usize
        while i < nn {
            pool[nn + i] = 1.0f64
            i += 1usize
        }
        slot = 2usize
    }
    i = 0usize
    while i < nx0 * nn {
        pool[slot * nn + i] = xs[i]
        i += 1usize
    }
    i = 0usize
    while i <= nx {
        ord[i] = i
        i += 1usize
    }
    var e = stat_fit(a, pool, n, ord, nx, kind, coefs, stat, ext)
    if e != ok { ret e }
    var hyp = nullhyp
    if hyp == 0usize && nx == 1usize { hyp = 1usize }
    let tot = (nx + 1usize) * nn
    var j = 0usize
    while j < nx {
        out[j] = coefs[j]
        out[nx + j] = stat[j]
        j += 1usize
    }
    out[5usize * nx] = ext[0usize]
    out[5usize * nx + 1usize] = ext[1usize]
    out[5usize * nx + 2usize] = ext[2usize]
    var rep = 0usize
    var cur = 0usize
    if hyp == 4usize {
        j = 0usize
        while j < nx {
            let tv = stat[j]
            out[2usize * nx + j] = nb.pt(tv, ext[2usize], true, false)
            out[3usize * nx + j] = nb.pt(tv, ext[2usize], false, false)
            var at = tv
            if at < 0.0f64 { at = 0.0f64 - at }
            out[4usize * nx + j] = 2.0f64 * nb.pt(at, ext[2usize], false, false)
            j += 1usize
        }
        ret ok
    }
    let nan = 0.0f64 / 0.0f64
    i = 0usize
    while i < reps * nx {
        dist[i] = nan
        i += 1usize
    }
    if hyp == 1usize {
        while rep < reps {
            let mk = mem.mark(a)
            i = 0usize
            while i < tot {
                work[i] = pool[i]
                i += 1usize
            }
            e = rmperm(a, rg, pool[0usize..nn], n, work[0usize..nn])
            if e != ok { ret e }
            if stat_fit(a, work, n, ord, nx, kind, coefs, stat, ext) == ok {
                j = 0usize
                while j < nx {
                    dist[rep * nx + j] = stat[j]
                    j += 1usize
                }
            }
            mem.reset(a, mk)
            rep += 1usize
        }
    }
    if hyp == 2usize {
        cur = 0usize
        while cur < nx {
            i = 0usize
            while i < tot {
                work[i] = pool[i]
                i += 1usize
            }
            rep = 0usize
            while rep < reps {
                let mk = mem.mark(a)
                e = rmperm(a, rg, work[(cur + 1usize) * nn..(cur + 2usize) * nn], n, xcol)
                if e != ok { ret e }
                i = 0usize
                while i < nn {
                    work[(cur + 1usize) * nn + i] = xcol[i]
                    i += 1usize
                }
                if stat_fit(a, work, n, ord, nx, kind, coefs, stat, ext) == ok { dist[rep * nx + cur] = stat[cur] }
                mem.reset(a, mk)
                rep += 1usize
            }
            cur += 1usize
        }
    }
    if hyp == 3usize {
        while rep < reps {
            let mk = mem.mark(a)
            i = 0usize
            while i < tot {
                work[i] = pool[i]
                i += 1usize
            }
            j = 0usize
            while j < nx {
                e = rmperm(a, rg, pool[(j + 1usize) * nn..(j + 2usize) * nn], n, work[(j + 1usize) * nn..(j + 2usize) * nn])
                if e != ok { ret e }
                j += 1usize
            }
            if stat_fit(a, work, n, ord, nx, kind, coefs, stat, ext) == ok {
                j = 0usize
                while j < nx {
                    dist[rep * nx + j] = stat[j]
                    j += 1usize
                }
            }
            mem.reset(a, mk)
            rep += 1usize
        }
    }
    if hyp == 0usize {
        let m = n * (n - 1usize)
        cur = 0usize
        while cur < nx {
            let mk0 = mem.mark(a)
            // x_cur on the others (lm), its residuals laid back into an n by n matrix
            let (yv, e8) = mem.alloc[f64](a, m)
            let (xo, e9) = mem.alloc[f64](a, m * (nx - 1usize))
            let (xres, e10) = mem.alloc[f64](a, nn)
            let (colv, e11) = mem.alloc[f64](a, m)
            if e8 != ok { ret e8 }
            if e9 != ok { ret e9 }
            if e10 != ok { ret e10 }
            if e11 != ok { ret e11 }
            gvec(pool[(cur + 1usize) * nn..(cur + 2usize) * nn], n, yv)
            var cc = 0usize
            var k = 0usize
            while k < nx {
                if k != cur {
                    gvec(pool[(k + 1usize) * nn..(k + 2usize) * nn], n, colv)
                    var r = 0usize
                    while r < m {
                        xo[cc * m + r] = colv[r]
                        r += 1usize
                    }
                    cc += 1usize
                }
                k += 1usize
            }
            let (f, e12) = dcmp.lm_fit(a, xo, m, nx - 1usize, yv, 1.0e-7f64)
            if e12 != ok { ret e12 }
            i = 0usize
            while i < nn {
                xres[i] = pool[(cur + 1usize) * nn + i]
                i += 1usize
            }
            var pos = 0usize
            var cj = 0usize
            while cj < n {
                var ri = 0usize
                while ri < n {
                    if ri != cj {
                        xres[ri * n + cj] = f.residuals[pos]
                        pos += 1usize
                    }
                    ri += 1usize
                }
                cj += 1usize
            }
            rep = 0usize
            while rep < reps {
                let mk = mem.mark(a)
                // slots: y, the other covariates in order, then the permuted residual matrix last
                i = 0usize
                while i < nn {
                    work[i] = pool[i]
                    i += 1usize
                }
                var wk = 1usize
                k = 0usize
                while k < nx {
                    if k != cur {
                        i = 0usize
                        while i < nn {
                            work[wk * nn + i] = pool[(k + 1usize) * nn + i]
                            i += 1usize
                        }
                        wk += 1usize
                    }
                    k += 1usize
                }
                e = rmperm(a, rg, xres, n, work[nx * nn..(nx + 1usize) * nn])
                if e != ok { ret e }
                if stat_fit(a, work, n, ord, nx, kind, coefs, stat, ext) == ok { dist[rep * nx + cur] = stat[nx - 1usize] }
                mem.reset(a, mk)
                rep += 1usize
            }
            mem.reset(a, mk0)
            cur += 1usize
        }
    }
    j = 0usize
    while j < nx {
        var le = 0.0f64
        var ge = 0.0f64
        var ga = 0.0f64
        var ta = stat_obs(out, nx, j)
        if ta < 0.0f64 { ta = 0.0f64 - ta }
        rep = 0usize
        while rep < reps {
            let dv = dist[rep * nx + j]
            var da = dv
            if da < 0.0f64 { da = 0.0f64 - da }
            if dv <= stat_obs(out, nx, j) { le += 1.0f64 }
            if dv >= stat_obs(out, nx, j) { ge += 1.0f64 }
            if da >= ta { ga += 1.0f64 }
            rep += 1usize
        }
        out[2usize * nx + j] = le / f64(reps)
        out[3usize * nx + j] = ge / f64(reps)
        out[4usize * nx + j] = ga / f64(reps)
        j += 1usize
    }
    ret ok
}

fn stat_obs(out: []const f64, nx: usize, j: usize) -> f64 {
    ret out[nx + j]
}

// qaptest(list(g1, g2), FUN, reps, g1 = 1, g2 = 2) for FUN = gcor (fun 0) or hdist (fun 1): each replicate permutes g1 then g2 with rmperm. out gets the test value, pgreq, pleeq, then the reps statistics
fn qaptest(a: *mem.Arena, rg: *rrand.Rng, g1: []const f64, g2: []const f64, n: usize, reps: usize, fun: usize, out: []f64) -> err {
    let nn = n * n
    let m = n * (n - 1usize)
    let (p1, e1) = mem.alloc[f64](a, nn)
    let (p2, e2) = mem.alloc[f64](a, nn)
    let (v1, e3) = mem.alloc[f64](a, m)
    let (v2, e4) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    gvec(g1, n, v1)
    gvec(g2, n, v2)
    let tv = vec_stat(v1, v2, fun)
    var ge = 0.0f64
    var le = 0.0f64
    var rep = 0usize
    while rep < reps {
        let mk = mem.mark(a)
        var e = rmperm(a, rg, g1, n, p1)
        if e != ok { ret e }
        e = rmperm(a, rg, g2, n, p2)
        if e != ok { ret e }
        gvec(p1, n, v1)
        gvec(p2, n, v2)
        let d = vec_stat(v1, v2, fun)
        out[3usize + rep] = d
        if d >= tv { ge += 1.0f64 }
        if d <= tv { le += 1.0f64 }
        mem.reset(a, mk)
        rep += 1usize
    }
    out[0usize] = tv
    out[1usize] = ge / f64(reps)
    out[2usize] = le / f64(reps)
    ret ok
}

fn vec_stat(u: []const f64, v: []const f64, fun: usize) -> f64 {
    let m = u.len
    var i = 0usize
    if fun == 1usize {
        var h = 0.0f64
        while i < m {
            h += math.abs[f64](u[i] - v[i])
            i += 1usize
        }
        ret h
    }
    var su = 0.0f64
    var sv = 0.0f64
    while i < m {
        su += u[i]
        sv += v[i]
        i += 1usize
    }
    let mu = su / f64(m)
    let mv = sv / f64(m)
    var suv = 0.0f64
    var suu = 0.0f64
    var svv = 0.0f64
    i = 0usize
    while i < m {
        suv += (u[i] - mu) * (v[i] - mv)
        suu += (u[i] - mu) * (u[i] - mu)
        svv += (v[i] - mv) * (v[i] - mv)
        i += 1usize
    }
    ret suv / (math.sqrt[f64](suu) * math.sqrt[f64](svv))
}
