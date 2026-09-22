// Approximate nearest neighbours. `minhash` signatures estimate Jaccard
// similarity of `u64` sets and `lsh_match` bands them for candidate pairs;
// `graph_build`/`graph_search` are a navigable small-world graph (the base
// layer of HNSW: each point linked to its `m` nearest among the earlier
// ones plus back links, searched greedily with a beam of `ef`); `ivf_pq_*`
// is an inverted file over coarse k-means cells with product quantisation
// of the residuals and asymmetric distance search. Graph and index live in
// the caller's arena.

use e.algo.rand
use e.algo.sketch
use e.math
use e.mem
use e.ml.cluster

type Graph = struct { first: []u32, count: []u32, neighbours: []u32, m: usize, n: usize }
type IvfPq = struct { coarse: []f64, codebooks: []f64, codes: []u8, cell_start: []usize, cell_items: []u32, cells: usize, subspaces: usize, codebook_size: usize, d: usize, n: usize }
error TooSmall
error Invalid

// A MinHash signature of `set` with `signature.len` hash functions
// `(a (x mod p) + b) mod p`, `p = 2^32 - 5`, the coefficients drawn from `seed`.
fn minhash(set: []const u64, seed: u64, signature: []u64) -> err {
    if signature.len == 0usize { ret Invalid }
    let prime = 4294967291u64
    var r = rand.pcg64(seed, 1u64)
    var h = 0usize
    while h < signature.len {
        let a = 1u64 + rand.pcg64_next(&r) % (prime - 1u64)
        let b = rand.pcg64_next(&r) % prime
        var least = prime
        var i = 0usize
        while i < set.len {
            let v = (a * (set[i] % prime) + b) % prime
            if v < least { least = v }
            i += 1usize
        }
        signature[h] = least
        h += 1usize
    }
    ret ok
}

// The share of equal positions of two signatures.
fn jaccard_estimate(a: []const u64, b: []const u64) -> f64 {
    if a.len == 0usize || a.len != b.len { ret 0.0f64 }
    var same = 0usize
    var i = 0usize
    while i < a.len {
        if a[i] == b[i] { same += 1usize }
        i += 1usize
    }
    ret f64(same) / f64(a.len)
}

// Do two signatures agree on any of `bands` bands of `rows` positions?
fn lsh_match(a: []const u64, b: []const u64, bands: usize, rows: usize) -> bool {
    if a.len < bands * rows || b.len < bands * rows { ret false }
    var band = 0usize
    while band < bands {
        var equal = true
        var i = 0usize
        while i < rows && equal {
            if a[band * rows + i] != b[band * rows + i] { equal = false }
            i += 1usize
        }
        if equal { ret true }
        band += 1usize
    }
    ret false
}

fn distance_squared(x: []const f64, d: usize, i: usize, q: []const f64, j: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d {
        let t = x[i * d + k] - q[j * d + k]
        s += t * t
        k += 1usize
    }
    ret s
}

// Insert `candidate` (distance `dist`) into the beam `ids`/`dists` of
// capacity `cap`, kept sorted by distance; answers the new count.
fn beam_insert(ids: []u32, dists: []f64, count: usize, cap: usize, candidate: u32, dist: f64) -> usize {
    var at = count
    while at > 0usize && dists[at - 1usize] > dist { at -= 1usize }
    if at >= cap { ret count }
    var m = count
    if m == cap { m = cap - 1usize }
    while m > at {
        ids[m] = ids[m - 1usize]
        dists[m] = dists[m - 1usize]
        m -= 1usize
    }
    ids[at] = candidate
    dists[at] = dist
    if count < cap { ret count + 1usize }
    ret count
}

// Build the graph over `x` (`n × d`): point `i` links to its `m` nearest
// among points `0..i` (found through the graph itself with beam `ef`), and
// those link back while they have room. `scratch` needs `4 ef + n` floats
// and `visited.len >= n`.
fn graph_build(a: *mem.Arena, x: []const f64, n: usize, d: usize, m: usize, ef: usize, scratch: []f64, visited: []u32) -> (Graph, err) {
    if x.len < n * d || scratch.len < 4usize * ef + n || visited.len < n { ret (zero, TooSmall) }
    if n == 0usize || m == 0usize || ef == 0usize || n > 4000000000usize { ret (zero, Invalid) }
    let (first, first_error) = mem.alloc[u32](a, n)
    if first_error != ok { ret (zero, first_error) }
    let (count, count_error) = mem.alloc[u32](a, n)
    if count_error != ok { ret (zero, count_error) }
    let (neighbours, neighbours_error) = mem.alloc[u32](a, n * 2usize * m)
    if neighbours_error != ok { ret (zero, neighbours_error) }
    var g = Graph { first: first, count: count, neighbours: neighbours, m: m, n: 0usize }
    var i = 0usize
    while i < n {
        first[i] = u32(i * 2usize * m)
        count[i] = 0u32
        i += 1usize
    }
    var ids = scratch[..ef]
    var dists = scratch[ef..2usize * ef]
    i = 0usize
    while i < n {
        g.n = i
        if i > 0usize {
            let (found, search_error) = graph_search(&g, x, d, x[i * d..(i + 1usize) * d], m, ef, ids, dists, scratch[2usize * ef..], visited)
            if search_error != ok { ret (zero, search_error) }
            var k = 0usize
            while k < found {
                let j = usize(ids[k])
                neighbours[usize(first[i]) + usize(count[i])] = u32(j)
                count[i] += 1u32
                if usize(count[j]) < 2usize * m {
                    neighbours[usize(first[j]) + usize(count[j])] = u32(i)
                    count[j] += 1u32
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    g.n = n
    ret (g, ok)
}

// The `k` nearest of `query` by greedy beam search of width `ef` from
// point 0: `ids` (as floats holding the index) and `dists` receive them,
// nearest first. `scratch.len >= 2 ef + n`, `visited.len >= n`.
fn graph_search(g: *const Graph, x: []const f64, d: usize, query: []const f64, k: usize, ef: usize, ids: []f64, dists: []f64, scratch: []f64, visited: []u32) -> (usize, err) {
    if ids.len < ef || dists.len < ef || scratch.len < 2usize * ef || visited.len < g.n || k > ef { ret (0usize, TooSmall) }
    if g.n == 0usize { ret (0usize, ok) }
    var beam_ids = scratch[..ef]
    var beam_dists = scratch[ef..2usize * ef]
    var i = 0usize
    while i < g.n {
        visited[i] = 0u32
        i += 1usize
    }
    // Candidates and results share the same sorted beam; a candidate is
    // expanded once, in order of distance, while it can still improve the beam.
    var count = 0usize
    let d0 = distance_squared(x, d, 0usize, query, 0usize)
    count = float_beam_insert(beam_ids, beam_dists, count, ef, 0usize, d0)
    visited[0usize] = 1u32
    var expanding = true
    while expanding {
        // The nearest unexpanded entry (visited == 1: seen, 2: expanded).
        var pick = ef
        i = 0usize
        while i < count && pick == ef {
            if visited[usize(beam_ids[i])] == 1u32 { pick = i }
            i += 1usize
        }
        if pick == ef {
            expanding = false
        } else {
            let p = usize(beam_ids[pick])
            visited[p] = 2u32
            var e = 0usize
            while e < usize(g.count[p]) {
                let q = usize(g.neighbours[usize(g.first[p]) + e])
                if visited[q] == 0u32 {
                    visited[q] = 1u32
                    let dq = distance_squared(x, d, q, query, 0usize)
                    if count < ef || dq < beam_dists[count - 1usize] {
                        count = float_beam_insert(beam_ids, beam_dists, count, ef, q, dq)
                    } else {
                        visited[q] = 2u32
                    }
                }
                e += 1usize
            }
        }
    }
    var found = count
    if found > k { found = k }
    i = 0usize
    while i < found {
        ids[i] = beam_ids[i]
        dists[i] = beam_dists[i]
        i += 1usize
    }
    ret (found, ok)
}

fn float_beam_insert(ids: []f64, dists: []f64, count: usize, cap: usize, candidate: usize, dist: f64) -> usize {
    var at = count
    while at > 0usize && dists[at - 1usize] > dist { at -= 1usize }
    if at >= cap { ret count }
    var m = count
    if m == cap { m = cap - 1usize }
    while m > at {
        ids[m] = ids[m - 1usize]
        dists[m] = dists[m - 1usize]
        m -= 1usize
    }
    ids[at] = f64(candidate)
    dists[at] = dist
    if count < cap { ret count + 1usize }
    ret count
}

// Train an IVF-PQ index over `x` (`n × d`): `cells` coarse centroids by
// k-means (k-means++ seeded), residuals split into `subspaces` of `d /
// subspaces` each quantised by a `codebook_size`-word codebook, every
// vector encoded and listed under its cell. `scratch` needs
// `n * (d / subspaces) + n + cells + codebook_size` floats, `labels.len >= n`
// and `marks.len >= max(cells, codebook_size)` indices.
fn ivf_pq_train(a: *mem.Arena, x: []const f64, n: usize, d: usize, cells: usize, subspaces: usize, codebook_size: usize, r: *rand.Pcg64, scratch: []f64, labels: []usize, marks: []usize) -> (IvfPq, err) {
    if x.len < n * d || labels.len < n || marks.len < cells || marks.len < codebook_size { ret (zero, TooSmall) }
    if n == 0usize || cells == 0usize || subspaces == 0usize || d % subspaces != 0usize || codebook_size == 0usize || codebook_size > 256usize || n > 4000000000usize { ret (zero, Invalid) }
    let sub = d / subspaces
    if scratch.len < n * sub + n + cells + codebook_size { ret (zero, TooSmall) }
    let (coarse, coarse_error) = mem.alloc[f64](a, cells * d)
    if coarse_error != ok { ret (zero, coarse_error) }
    let (codebooks, codebooks_error) = mem.alloc[f64](a, subspaces * codebook_size * sub)
    if codebooks_error != ok { ret (zero, codebooks_error) }
    let (codes, codes_error) = mem.alloc[u8](a, n * subspaces)
    if codes_error != ok { ret (zero, codes_error) }
    let (residuals, residuals_error) = mem.alloc[f64](a, n * d)
    if residuals_error != ok { ret (zero, residuals_error) }
    let (cell_start, start_error) = mem.alloc[usize](a, cells + 1usize)
    if start_error != ok { ret (zero, start_error) }
    let (cell_items, items_error) = mem.alloc[u32](a, n)
    if items_error != ok { ret (zero, items_error) }
    let (cell_of, cell_of_error) = mem.alloc[usize](a, n)
    if cell_of_error != ok { ret (zero, cell_of_error) }
    var counts = scratch[..cells]
    var weights = scratch[cells..cells + n]
    var sub_scratch = scratch[cells + n..cells + n + n * sub]
    var code_counts = scratch[cells + n + n * sub..cells + n + n * sub + codebook_size]
    // Coarse quantiser.
    let seed_error = cluster.kmeans_pp_init(x, n, d, cells, r, coarse, weights)
    if seed_error != ok { ret (zero, seed_error) }
    let (_, coarse_run) = cluster.kmeans(x, n, d, cells, coarse, labels, 50u32, marks)
    if coarse_run != ok { ret (zero, coarse_run) }
    var i = 0usize
    while i < n {
        let (c, _) = cluster.nearest(x, d, i, coarse, cells)
        cell_of[i] = c
        var j = 0usize
        while j < d {
            residuals[i * d + j] = x[i * d + j] - coarse[c * d + j]
            j += 1usize
        }
        i += 1usize
    }
    // One codebook per subspace over the residual slices.
    var s = 0usize
    while s < subspaces {
        i = 0usize
        while i < n {
            var j = 0usize
            while j < sub {
                sub_scratch[i * sub + j] = residuals[i * d + s * sub + j]
                j += 1usize
            }
            i += 1usize
        }
        var book = codebooks[s * codebook_size * sub..(s + 1usize) * codebook_size * sub]
        let book_seed = cluster.kmeans_pp_init(sub_scratch, n, sub, codebook_size, r, book, weights)
        if book_seed != ok { ret (zero, book_seed) }
        let (_, book_run) = cluster.kmeans(sub_scratch, n, sub, codebook_size, book, labels, 50u32, marks)
        if book_run != ok { ret (zero, book_run) }
        i = 0usize
        while i < n {
            let (word, _) = cluster.nearest(sub_scratch, sub, i, book, codebook_size)
            codes[i * subspaces + s] = u8(word)
            i += 1usize
        }
        s += 1usize
    }
    // Inverted lists.
    var c = 0usize
    while c <= cells {
        cell_start[c] = 0usize
        c += 1usize
    }
    i = 0usize
    while i < n {
        cell_start[cell_of[i] + 1usize] += 1usize
        i += 1usize
    }
    c = 0usize
    while c < cells {
        cell_start[c + 1usize] += cell_start[c]
        c += 1usize
    }
    c = 0usize
    while c < cells {
        counts[c] = 0.0f64
        c += 1usize
    }
    i = 0usize
    while i < n {
        let cell = cell_of[i]
        cell_items[cell_start[cell] + usize(counts[cell])] = u32(i)
        counts[cell] += 1.0f64
        i += 1usize
    }
    ret (IvfPq { coarse: coarse, codebooks: codebooks, codes: codes, cell_start: cell_start, cell_items: cell_items, cells: cells, subspaces: subspaces, codebook_size: codebook_size, d: d, n: n }, ok)
}

// The `k` nearest of `query` by asymmetric distance over the `probes`
// nearest cells: `ids` and `dists` receive them nearest first.
// `scratch.len >= subspaces * codebook_size + cells` floats.
fn ivf_pq_search(index: *const IvfPq, query: []const f64, probes: usize, k: usize, ids: []u32, dists: []f64, scratch: []f64) -> (usize, err) {
    let d = index.d
    let sub = d / index.subspaces
    if query.len < d || ids.len < k || dists.len < k || scratch.len < index.subspaces * index.codebook_size + index.cells { ret (0usize, TooSmall) }
    if probes == 0usize || probes > index.cells || k == 0usize { ret (0usize, Invalid) }
    var table = scratch[..index.subspaces * index.codebook_size]
    var cell_dist = scratch[index.subspaces * index.codebook_size..index.subspaces * index.codebook_size + index.cells]
    var c = 0usize
    while c < index.cells {
        cell_dist[c] = distance_squared(index.coarse, d, c, query, 0usize)
        c += 1usize
    }
    var count = 0usize
    var probe = 0usize
    while probe < probes {
        // The next nearest cell not yet probed (marked by negating its distance).
        var cell = index.cells
        c = 0usize
        while c < index.cells {
            if cell_dist[c] >= 0.0f64 && (cell == index.cells || cell_dist[c] < cell_dist[cell]) { cell = c }
            c += 1usize
        }
        cell_dist[cell] = 0.0f64 - 1.0f64 - cell_dist[cell]
        // Distance table: residual of the query against every codeword per subspace.
        var s = 0usize
        while s < index.subspaces {
            var w = 0usize
            while w < index.codebook_size {
                var sum = 0.0f64
                var j = 0usize
                while j < sub {
                    let t = query[s * sub + j] - index.coarse[cell * d + s * sub + j] - index.codebooks[(s * index.codebook_size + w) * sub + j]
                    sum += t * t
                    j += 1usize
                }
                table[s * index.codebook_size + w] = sum
                w += 1usize
            }
            s += 1usize
        }
        var at = index.cell_start[cell]
        while at < index.cell_start[cell + 1usize] {
            let item = index.cell_items[at]
            var dist = 0.0f64
            s = 0usize
            while s < index.subspaces {
                dist += table[s * index.codebook_size + usize(index.codes[usize(item) * index.subspaces + s])]
                s += 1usize
            }
            count = beam_insert(ids, dists, count, k, item, dist)
            at += 1usize
        }
        probe += 1usize
    }
    ret (count, ok)
}

// --- HNSW ------------------------------------------------------------------

// A hierarchical navigable small world over points `0..n` of a row-major
// `x`: every node has links at layers `0..level`, `2 m` at layer 0 and `m`
// above, at `links[(node * levels + layer) * 2 m ..]`.
type Hnsw = struct { level: []u32, count: []u32, links: []u32, m: usize, levels: usize, d: usize, room: usize, entry: usize, n: usize }

// An empty index with room for `room` points of `d` values, `m` links per
// layer and layers `0..=max_level`, in the caller's arena.
fn hnsw(a: *mem.Arena, room: usize, d: usize, m: usize, max_level: usize) -> (Hnsw, err) {
    if room == 0usize || d == 0usize || m == 0usize || room > 4000000000usize { ret (zero, Invalid) }
    let levels = max_level + 1usize
    let (level, level_error) = mem.alloc[u32](a, room)
    if level_error != ok { ret (zero, level_error) }
    let (count, count_error) = mem.alloc[u32](a, room * levels)
    if count_error != ok { ret (zero, count_error) }
    let (links, links_error) = mem.alloc[u32](a, room * levels * 2usize * m)
    if links_error != ok { ret (zero, links_error) }
    ret (Hnsw { level: level, count: count, links: links, m: m, levels: levels, d: d, room: room, entry: 0usize, n: 0usize }, ok)
}

// Beam search of width `ef` at `layer` from `start`: the beam (nearest
// first) stays in `beam_ids`/`beam_dists` and its count is answered.
fn hnsw_layer(g: *const Hnsw, x: []const f64, query: []const f64, start: usize, layer: usize, ef: usize, beam_ids: []f64, beam_dists: []f64, visited: []u32) -> usize {
    var i = 0usize
    while i < g.n {
        visited[i] = 0u32
        i += 1usize
    }
    var count = float_beam_insert(beam_ids, beam_dists, 0usize, ef, start, distance_squared(x, g.d, start, query, 0usize))
    visited[start] = 1u32
    var expanding = true
    while expanding {
        var pick = ef
        i = 0usize
        while i < count && pick == ef {
            if visited[usize(beam_ids[i])] == 1u32 { pick = i }
            i += 1usize
        }
        if pick == ef {
            expanding = false
        } else {
            let p = usize(beam_ids[pick])
            visited[p] = 2u32
            let base = (p * g.levels + layer) * 2usize * g.m
            var e = 0usize
            while e < usize(g.count[p * g.levels + layer]) {
                let q = usize(g.links[base + e])
                if visited[q] == 0u32 {
                    visited[q] = 1u32
                    let dq = distance_squared(x, g.d, q, query, 0usize)
                    if count < ef || dq < beam_dists[count - 1usize] {
                        count = float_beam_insert(beam_ids, beam_dists, count, ef, q, dq)
                    } else {
                        visited[q] = 2u32
                    }
                }
                e += 1usize
            }
        }
    }
    ret count
}

// Link `j` to `node` at `layer`; a full list drops its farthest link when
// `node` is nearer (ties keep the list).
fn hnsw_connect(g: *Hnsw, x: []const f64, j: usize, layer: usize, node: usize) {
    var cap = g.m
    if layer == 0usize { cap = 2usize * g.m }
    let base = (j * g.levels + layer) * 2usize * g.m
    let c = usize(g.count[j * g.levels + layer])
    if c < cap {
        g.links[base + c] = u32(node)
        g.count[j * g.levels + layer] = u32(c + 1usize)
        ret
    }
    var worst = cap
    var worst_dist = distance_squared(x, g.d, j, x, node)
    var e = 0usize
    while e < c {
        let dist = distance_squared(x, g.d, j, x, usize(g.links[base + e]))
        if dist > worst_dist {
            worst = e
            worst_dist = dist
        }
        e += 1usize
    }
    if worst < cap { g.links[base + worst] = u32(node) }
}

// Insert point `g.n` of `x`: its level is `floor(-ln u / ln m)` for a
// uniform `u` from `r` (capped at the top layer), it descends greedily to
// that level, then at every layer down to 0 links to the `m` nearest of a
// beam of `ef`, which link back (`hnsw_connect`). `scratch.len >= 2 max(ef,
// 2 m)`, `visited.len >= room`.
fn hnsw_insert(g: *Hnsw, x: []const f64, r: *rand.Pcg64, ef: usize, scratch: []f64, visited: []u32) -> err {
    var width = ef
    if 2usize * g.m > width { width = 2usize * g.m }
    if g.n >= g.room || ef == 0usize { ret Invalid }
    if scratch.len < 2usize * width || visited.len < g.room || x.len < (g.n + 1usize) * g.d { ret TooSmall }
    let node = g.n
    let u = rand.pcg64_f64(r)
    var lvl = g.levels - 1usize
    if u > 0.0f64 && g.m > 1usize {
        let drawn = (0.0f64 - math.log[f64](u)) / math.log[f64](f64(g.m))
        if drawn < f64(lvl) { lvl = usize(drawn) }
    }
    g.level[node] = u32(lvl)
    var l = 0usize
    while l < g.levels {
        g.count[node * g.levels + l] = 0u32
        l += 1usize
    }
    if node == 0usize {
        g.entry = 0usize
        g.n = 1usize
        ret ok
    }
    let query = x[node * g.d..(node + 1usize) * g.d]
    var beam_ids = scratch[..width]
    var beam_dists = scratch[width..2usize * width]
    var ep = g.entry
    let top = usize(g.level[g.entry])
    l = top
    while l > lvl {
        let _ = hnsw_layer(g, x, query, ep, l, 1usize, beam_ids, beam_dists, visited)
        ep = usize(beam_ids[0usize])
        l -= 1usize
    }
    var layer = lvl
    if top < layer { layer = top }
    var descending = true
    while descending {
        let found = hnsw_layer(g, x, query, ep, layer, ef, beam_ids, beam_dists, visited)
        ep = usize(beam_ids[0usize])
        var take = found
        if take > g.m { take = g.m }
        let base = (node * g.levels + layer) * 2usize * g.m
        var k = 0usize
        while k < take {
            let j = usize(beam_ids[k])
            g.links[base + k] = u32(j)
            hnsw_connect(g, x, j, layer, node)
            k += 1usize
        }
        g.count[node * g.levels + layer] = u32(take)
        if layer == 0usize { descending = false } else { layer -= 1usize }
    }
    if lvl > top { g.entry = node }
    g.n = node + 1usize
    ret ok
}

// The `k` nearest of `query`: a greedy descent from the entry point to
// layer 1, then a beam of `ef >= k` at layer 0; `ids`/`dists` receive them
// nearest first. `scratch.len >= 2 ef`, `visited.len >= room`.
fn hnsw_search(g: *const Hnsw, x: []const f64, query: []const f64, k: usize, ef: usize, ids: []u32, dists: []f64, scratch: []f64, visited: []u32) -> (usize, err) {
    if scratch.len < 2usize * ef || visited.len < g.room || ids.len < k || dists.len < k || query.len < g.d { ret (0usize, TooSmall) }
    if k == 0usize || k > ef { ret (0usize, Invalid) }
    if g.n == 0usize { ret (0usize, ok) }
    var beam_ids = scratch[..ef]
    var beam_dists = scratch[ef..2usize * ef]
    var ep = g.entry
    var l = usize(g.level[g.entry])
    while l > 0usize {
        let _ = hnsw_layer(g, x, query, ep, l, 1usize, beam_ids, beam_dists, visited)
        ep = usize(beam_ids[0usize])
        l -= 1usize
    }
    var found = hnsw_layer(g, x, query, ep, 0usize, ef, beam_ids, beam_dists, visited)
    if found > k { found = k }
    var i = 0usize
    while i < found {
        ids[i] = u32(beam_ids[i])
        dists[i] = beam_dists[i]
        i += 1usize
    }
    ret (found, ok)
}

// The planned name of `ivf_pq_train`.
fn ivf_pq(a: *mem.Arena, x: []const f64, n: usize, d: usize, cells: usize, subspaces: usize, codebook_size: usize, r: *rand.Pcg64, scratch: []f64, labels: []usize, marks: []usize) -> (IvfPq, err) {
    let (index, train_error) = ivf_pq_train(a, x, n, d, cells, subspaces, codebook_size, r, scratch, labels, marks)
    ret (index, train_error)
}

// --- MinHash LSH index -----------------------------------------------------

// Signatures of `bands × rows` positions bucketed per band
// (`sketch.lsh_bucket`): `keys`/`ids` hold `bands * room` entries, band
// `b`'s at `b * room ..`.
type MinhashLsh = struct { keys: []u64, ids: []u32, bands: usize, rows: usize, room: usize, n: usize }

fn minhash_lsh(keys: []u64, ids: []u32, bands: usize, rows: usize, room: usize) -> (MinhashLsh, err) {
    if keys.len < bands * room || ids.len < bands * room { ret (zero, TooSmall) }
    if bands == 0usize || rows == 0usize || room == 0usize { ret (zero, Invalid) }
    ret (MinhashLsh { keys: keys, ids: ids, bands: bands, rows: rows, room: room, n: 0usize }, ok)
}

fn minhash_lsh_insert(index: *MinhashLsh, signature: []const u64, id: u32) -> err {
    if signature.len < index.bands * index.rows { ret TooSmall }
    if index.n >= index.room { ret Invalid }
    var b = 0usize
    while b < index.bands {
        index.keys[b * index.room + index.n] = sketch.lsh_bucket(signature, b, index.rows)
        index.ids[b * index.room + index.n] = id
        b += 1usize
    }
    index.n += 1usize
    ret ok
}

// The ids sharing a band bucket with `signature`, each once, in band then
// insertion order into `out`; answers the count (`TooSmall` once `out` is full).
// ponytail: a linear scan per band; sort each band's keys past a few thousand entries.
fn minhash_lsh_query(index: *const MinhashLsh, signature: []const u64, out: []u32) -> (usize, err) {
    if signature.len < index.bands * index.rows { ret (0usize, TooSmall) }
    var count = 0usize
    var b = 0usize
    while b < index.bands {
        let key = sketch.lsh_bucket(signature, b, index.rows)
        var i = 0usize
        while i < index.n {
            if index.keys[b * index.room + i] == key {
                let id = index.ids[b * index.room + i]
                var seen = false
                var k = 0usize
                while k < count {
                    if out[k] == id { seen = true }
                    k += 1usize
                }
                if !seen {
                    if count >= out.len { ret (count, TooSmall) }
                    out[count] = id
                    count += 1usize
                }
            }
            i += 1usize
        }
        b += 1usize
    }
    ret (count, ok)
}
