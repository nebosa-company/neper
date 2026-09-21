// `e.ml.knn` on three blobs of eight points: the three nearest of a query
// with their distances against scikit-learn, majority classification of
// three queries, mean regression of a linear target, and the storage and
// argument checks. Each check exits with its own code.

use e.io
use e.mem
use e.ml.knn
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [48]f64 = zero
    var base: [16]f64 = zero
    base[2usize] = 1.0f64
    base[5usize] = 1.0f64
    base[6usize] = 1.0f64
    base[7usize] = 1.0f64
    base[8usize] = 0.5f64
    base[9usize] = 0.5f64
    base[10usize] = 0.2f64
    base[11usize] = 0.8f64
    base[12usize] = 0.8f64
    base[13usize] = 0.2f64
    base[14usize] = 0.5f64
    base[15usize] = 0.1f64
    var i = 0usize
    while i < 8usize {
        x[2usize * i] = base[2usize * i]
        x[2usize * i + 1usize] = base[2usize * i + 1usize]
        x[16usize + 2usize * i] = base[2usize * i] + 10.0f64
        x[16usize + 2usize * i + 1usize] = base[2usize * i + 1usize]
        x[32usize + 2usize * i] = base[2usize * i]
        x[32usize + 2usize * i + 1usize] = base[2usize * i + 1usize] + 10.0f64
        i += 1usize
    }
    var labels: [24]usize = zero
    i = 0usize
    while i < 24usize {
        labels[i] = i / 8usize
        i += 1usize
    }

    var query: [2]f64 = zero
    query[0usize] = 0.4f64
    query[1usize] = 0.4f64
    var indices: [4]usize = zero
    var distances: [4]f64 = zero
    var scratch: [16]usize = zero

    // 1: neighbours.
    if knn.neighbors(x[..], 24usize, 2usize, query[..], 3usize, indices[..], distances[..]) != ok { os.exit(1i32) }
    if indices[0usize] != 4usize || indices[1usize] != 7usize || indices[2usize] != 5usize { os.exit(1i32) }
    if !near(distances[0usize], 0.14142136f64, 0.0000001f64) || !near(distances[1usize], 0.31622777f64, 0.0000001f64) || !near(distances[2usize], 0.4472136f64, 0.0000001f64) { os.exit(1i32) }
    if knn.neighbors(x[..], 24usize, 2usize, query[..], 0usize, indices[..], distances[..]) != knn.Invalid { os.exit(1i32) }
    if knn.neighbors(x[..], 24usize, 2usize, query[..], 25usize, indices[..], distances[..]) != knn.Invalid { os.exit(1i32) }
    if knn.neighbors(x[..], 24usize, 2usize, query[..], 3usize, indices[..2usize], distances[..]) != knn.TooSmall { os.exit(1i32) }

    // 2: classification.
    let (c1, c1_error) = knn.classify(x[..], labels[..], 24usize, 2usize, 3usize, query[..], 3usize, scratch[..], distances[..])
    if c1_error != ok || c1 != 0usize { os.exit(2i32) }
    query[0usize] = 9.0f64
    query[1usize] = 1.0f64
    let (c2, c2_error) = knn.classify(x[..], labels[..], 24usize, 2usize, 3usize, query[..], 3usize, scratch[..], distances[..])
    if c2_error != ok || c2 != 1usize { os.exit(2i32) }
    query[0usize] = 3.0f64
    query[1usize] = 7.0f64
    let (c3, c3_error) = knn.classify(x[..], labels[..], 24usize, 2usize, 3usize, query[..], 3usize, scratch[..], distances[..])
    if c3_error != ok || c3 != 2usize { os.exit(2i32) }
    let (_, c_room) = knn.classify(x[..], labels[..], 24usize, 2usize, 3usize, query[..], 3usize, scratch[..4usize], distances[..])
    if c_room != knn.TooSmall { os.exit(2i32) }

    // 3: regression of x + 2y.
    var goal: [24]f64 = zero
    i = 0usize
    while i < 24usize {
        goal[i] = x[2usize * i] + 2.0f64 * x[2usize * i + 1usize]
        i += 1usize
    }
    query[0usize] = 0.4f64
    query[1usize] = 0.4f64
    let (r1, r1_error) = knn.regress(x[..], goal[..], 24usize, 2usize, query[..], 3usize, indices[..], distances[..])
    if r1_error != ok || !near(r1, 1.33333333f64, 0.0000001f64) { os.exit(3i32) }
    query[0usize] = 9.0f64
    query[1usize] = 1.0f64
    let (r2, r2_error) = knn.regress(x[..], goal[..], 24usize, 2usize, query[..], 3usize, indices[..], distances[..])
    if r2_error != ok || !near(r2, 11.26666667f64, 0.0000001f64) { os.exit(3i32) }

    try io.print("ml knn ok\n")
    ret ok
}
