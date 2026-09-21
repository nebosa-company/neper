// `e.dist.collective`: a ring all-reduce over four nodes of ten values
// leaves every node the column sums (then the column maxima) in 2(n-1)
// steps and 2(n-1)n chunk moves; a binomial broadcast from root 2 of five
// nodes reaches all in ceil(log2 5) rounds and n-1 transfers; scatter
// and gather move chunk i between the root and node i. Expected sums,
// maxima and matrix hashes come from the Python/numpy reference. Each
// check exits with its own code.

use e.dist.collective
use e.io
use e.mem
use e.os

fn fill(vectors: []f64, seed: u64) {
    var s = seed
    var i = 0usize
    while i < vectors.len {
        s = s *% 6364136223846793005u64 +% 1442695040888963407u64
        vectors[i] = f64((s >> 33u32) % 100u64)
        i += 1usize
    }
}

fn fold_all(vectors: []const f64) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < vectors.len {
        h = h *% 31u64 +% u64(i64(vectors[i]))
        i += 1usize
    }
    ret h
}

fn rows_equal(vectors: []const f64, n: usize, d: usize, expected: []const f64) -> bool {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            if vectors[i * d + j] != expected[j] { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var v: [40]f64 = zero
    let sums = [10]f64{ 164.0, 183.0, 215.0, 174.0, 255.0, 214.0, 73.0, 224.0, 187.0, 121.0 }
    let maxes = [10]f64{ 91.0, 86.0, 83.0, 93.0, 95.0, 86.0, 32.0, 99.0, 94.0, 37.0 }

    // 1: ring all-reduce, Sum then Max.
    fill(v[..], 77u64)
    let (c, c_error) = collective.collective(v[..], 4usize, 10usize)
    if c_error != ok { os.exit(1i32) }
    var col = c
    let (transfers, steps) = collective.all_reduce_ring(&col, .Sum)
    if transfers != 24usize || steps != 6usize { os.exit(1i32) }
    if !rows_equal(v[..], 4usize, 10usize, sums[..]) { os.exit(1i32) }
    fill(v[..], 77u64)
    let (max_transfers, max_steps) = collective.all_reduce_ring(&col, .Max)
    if max_transfers != 24usize || max_steps != 6usize { os.exit(1i32) }
    if !rows_equal(v[..], 4usize, 10usize, maxes[..]) { os.exit(1i32) }
    let (_, too_small) = collective.collective(v[..], 5usize, 10usize)
    if too_small != collective.Invalid { os.exit(1i32) }

    // 2: binomial broadcast from root 2 of five nodes.
    var w: [50]f64 = zero
    fill(w[..], 78u64)
    let root_row = [10]f64{ 4.0, 11.0, 2.0, 65.0, 71.0, 74.0, 47.0, 69.0, 72.0, 64.0 }
    let (c5, c5_error) = collective.collective(w[..], 5usize, 10usize)
    if c5_error != ok { os.exit(2i32) }
    var col5 = c5
    let (b_transfers, b_rounds) = collective.broadcast(&col5, 2usize)
    if b_transfers != 4usize || b_rounds != 3usize { os.exit(2i32) }
    if !rows_equal(w[..], 5usize, 10usize, root_row[..]) { os.exit(2i32) }

    // 3: scatter from root 1, then gather to root 0.
    fill(w[..], 78u64)
    if collective.scatter(&col5, 1usize) != 4usize { os.exit(3i32) }
    if fold_all(w[..]) != 12694681803976670336u64 { os.exit(3i32) }
    if collective.gather(&col5, 0usize) != 4usize { os.exit(3i32) }
    if fold_all(w[..]) != 10970890812961472553u64 { os.exit(3i32) }
    let gathered = [10]f64{ 33.0, 26.0, 5.0, 2.0, 81.0, 99.0, 60.0, 64.0, 96.0, 19.0 }
    if !rows_equal(w[..10usize], 1usize, 10usize, gathered[..]) { os.exit(3i32) }

    try io.print("dist collective ok\n")
    ret ok
}
