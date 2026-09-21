// Collective communication simulated in-process over one row-major
// `n x d` f64 buffer (row i is node i's vector): `all_reduce_ring`
// (reduce-scatter then all-gather, 2(n-1) steps, one chunk per node per
// step, 2(n-1)n chunk moves), `broadcast` (binomial tree from `root`,
// ceil(log2 n) rounds, n-1 transfers), `scatter` (chunk i of the root's
// row to node i) and `gather` (chunk i of node i to the root). Chunk c of
// a row is `[c*d/n, (c+1)*d/n)`, so d need not divide by n. Each answers
// the number of transfers it made.

type Op = enum u8 { Sum, Max }
type Collective = struct { vectors: []f64, n: usize, d: usize }

error Invalid

fn collective(vectors: []f64, n: usize, d: usize) -> (Collective, err) {
    if n == 0usize || vectors.len < n * d { ret (zero, Invalid) }
    ret (Collective { vectors: vectors, n: n, d: d }, ok)
}

fn chunk_lo(c: *const Collective, chunk: usize) -> usize { ret chunk * c.d / c.n }

// Copy chunk `chunk` of row `from` onto row `to`, reducing by `op` when given.
fn move_chunk(c: *Collective, from: usize, to: usize, chunk: usize, op: Op, reduce: bool) {
    var j = chunk_lo(c, chunk)
    let hi = chunk_lo(c, chunk + 1usize)
    while j < hi {
        let x = c.vectors[from * c.d + j]
        let at_to = to * c.d + j
        if !reduce {
            c.vectors[at_to] = x
        } else if op == .Sum {
            c.vectors[at_to] = c.vectors[at_to] + x
        } else if x > c.vectors[at_to] {
            c.vectors[at_to] = x
        }
        j += 1usize
    }
}

// Ring all-reduce: after it every row holds the `op` reduction of all rows.
// Answers (chunk transfers, steps).
fn all_reduce_ring(c: *Collective, op: Op) -> (usize, usize) {
    let n = c.n
    if n < 2usize { ret (0usize, 0usize) }
    var transfers = 0usize
    var step = 0usize
    // Reduce-scatter: node i sends chunk (i - step) to i + 1, which accumulates.
    while step + 1usize < n {
        var i = 0usize
        while i < n {
            let chunk = (i + n - step % n) % n
            move_chunk(c, i, (i + 1usize) % n, chunk, op, true)
            transfers += 1usize
            i += 1usize
        }
        step += 1usize
    }
    // All-gather: node i now owns chunk (i + 1) reduced; pass it round.
    step = 0usize
    while step + 1usize < n {
        var i = 0usize
        while i < n {
            let chunk = (i + 1usize + n - step % n) % n
            move_chunk(c, i, (i + 1usize) % n, chunk, op, false)
            transfers += 1usize
            i += 1usize
        }
        step += 1usize
    }
    ret (transfers, 2usize * (n - 1usize))
}

fn copy_row(c: *Collective, from: usize, to: usize) {
    var j = 0usize
    while j < c.d {
        c.vectors[to * c.d + j] = c.vectors[from * c.d + j]
        j += 1usize
    }
}

// Binomial-tree broadcast of the root's row. Answers (transfers, rounds).
fn broadcast(c: *Collective, root: usize) -> (usize, usize) {
    let n = c.n
    var transfers = 0usize
    var rounds = 0usize
    var span = 1usize
    while span < n {
        var r = 0usize
        while r < span && r + span < n {
            copy_row(c, (root + r) % n, (root + r + span) % n)
            transfers += 1usize
            r += 1usize
        }
        span *= 2usize
        rounds += 1usize
    }
    ret (transfers, rounds)
}

// Chunk i of the root's row goes to row i. Answers the transfers.
fn scatter(c: *Collective, root: usize) -> usize {
    var i = 0usize
    while i < c.n {
        if i != root { move_chunk(c, root, i, i, .Sum, false) }
        i += 1usize
    }
    ret c.n - 1usize
}

// Chunk i of row i goes to the root's row. Answers the transfers.
fn gather(c: *Collective, root: usize) -> usize {
    var i = 0usize
    while i < c.n {
        if i != root { move_chunk(c, i, root, i, .Sum, false) }
        i += 1usize
    }
    ret c.n - 1usize
}
