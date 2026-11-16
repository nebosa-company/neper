// R sna on a directed adjacency matrix (n by n, row-major, zero diagonal): degree, Freeman betweenness, stress, closeness and graph centrality, density, Freeman centralization of degree, betweenness and closeness, and eigenvector centrality.
//
// Not here: undirected modes, valued graphs, triad census, reciprocity, transitivity, structural equivalence, blockmodels, ERGM-style models.

use e.algo.linalg.matrix as mx
use e.math
use e.mem

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
