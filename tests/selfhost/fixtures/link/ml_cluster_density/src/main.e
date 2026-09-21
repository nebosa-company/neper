// `e.ml.cluster.density` on three blobs plus a stray point: DBSCAN finds
// the three clusters and marks the stray and the far corner of each blob
// as noise, as scikit-learn does at the same radius; OPTICS orders every
// blob as one run with the reachabilities scikit-learn reports and leaves
// the stray unreachable. Each check exits with its own code.

use e.io
use e.mem
use e.ml.cluster.density
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [50]f64 = zero
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
    var labels: [25]usize = zero
    i = 0usize
    while i < 24usize {
        labels[i] = i / 8usize
        i += 1usize
    }
    x[48usize] = 5.0f64
    x[49usize] = 5.0f64
    var queue: [25]usize = zero

    // 1: DBSCAN.
    let (clusters, dbscan_error) = density.dbscan(x[..], 25usize, 2usize, 0.6f64, 3usize, labels[..], queue[..])
    if dbscan_error != ok || clusters != 3usize { os.exit(1i32) }
    i = 0usize
    while i < 25usize {
        var want = i / 8usize
        if i == 3usize || i == 11usize || i == 19usize || i == 24usize { want = density.NOISE }
        if labels[i] != want { os.exit(1i32) }
        i += 1usize
    }
    let (one, one_error) = density.dbscan(x[..], 25usize, 2usize, 100.0f64, 3usize, labels[..], queue[..])
    if one_error != ok || one != 1usize || labels[24usize] != 0usize { os.exit(1i32) }
    let (none, none_error) = density.dbscan(x[..], 25usize, 2usize, 0.01f64, 3usize, labels[..], queue[..])
    if none_error != ok || none != 0usize || labels[0usize] != density.NOISE { os.exit(1i32) }
    let (_, dbscan_invalid) = density.dbscan(x[..], 25usize, 2usize, 0.6f64, 0usize, labels[..], queue[..])
    if dbscan_invalid != density.Invalid { os.exit(1i32) }
    let (_, dbscan_room) = density.dbscan(x[..], 25usize, 2usize, 0.6f64, 3usize, labels[..], queue[..10usize])
    if dbscan_room != density.TooSmall { os.exit(1i32) }

    // 2: OPTICS.
    var order: [25]usize = zero
    var reachability: [25]f64 = zero
    var core: [25]f64 = zero
    var work: [3]f64 = zero
    if density.optics(x[..], 25usize, 2usize, 2.0f64, 3usize, order[..], reachability[..], core[..], work[..], queue[..]) != ok { os.exit(2i32) }
    // Each blob is a run of eight in the ordering, blob A first.
    i = 0usize
    while i < 24usize {
        if order[i] / 8usize != i / 8usize { os.exit(2i32) }
        i += 1usize
    }
    if order[24usize] != 24usize || reachability[24usize] < 1.0e299f64 { os.exit(2i32) }
    // The first of each blob is where the run starts (unreached); the rest as scikit-learn.
    if reachability[0usize] < 1.0e299f64 || reachability[8usize] < 1.0e299f64 || reachability[16usize] < 1.0e299f64 { os.exit(2i32) }
    if !near(reachability[1usize], 0.3162f64, 0.0001f64) || !near(reachability[2usize], 0.4243f64, 0.0001f64) || !near(reachability[3usize], 0.7071f64, 0.0001f64) || !near(reachability[4usize], 0.7071f64, 0.0001f64) { os.exit(2i32) }
    if !near(reachability[5usize], 0.4243f64, 0.0001f64) || !near(reachability[6usize], 0.4243f64, 0.0001f64) || !near(reachability[7usize], 0.3162f64, 0.0001f64) || !near(reachability[23usize], 0.3162f64, 0.0001f64) { os.exit(2i32) }
    if density.optics(x[..], 25usize, 2usize, 2.0f64, 3usize, order[..], reachability[..], core[..], work[..2usize], queue[..]) != density.TooSmall { os.exit(2i32) }

    try io.print("ml cluster density ok\n")
    ret ok
}
