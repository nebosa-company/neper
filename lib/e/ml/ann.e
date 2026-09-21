// Approximate nearest neighbours. `minhash` signatures estimate Jaccard
// similarity of `u64` sets and `lsh_match` bands them for candidate pairs;
// `graph_build`/`graph_search` are a navigable small-world graph (the base
// layer of HNSW: each point linked to its `m` nearest among the earlier
// ones plus back links, searched greedily with a beam of `ef`); `ivf_pq_*`
// is an inverted file over coarse k-means cells with product quantisation
// of the residuals and asymmetric distance search. Graph and index live in
// the caller's arena.

use e.algo.rand
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
