// Matrix/scratch dimensions are validated by division, not overflowing usize
// products. 65536 squared is the wasm32 wrap boundary.
use e.algo.combopt
use e.os

fn main() {
    let edge = 65536usize
    if combopt.has_product(0usize, edge, edge) { os.exit(1) }
    if combopt.has_scaled(3usize, edge, 4usize, 4usize) { os.exit(2) }

    var empty: [0]f64 = zero
    var tour: [65536]usize = zero
    var visited: [65536]u8 = zero
    let (_, nearest_error) = combopt.tsp_nearest_neighbor(empty[0..], edge, 0usize, tour[0..], visited[0..])
    if nearest_error != combopt.TooSmall { os.exit(3) }
    let (_, _, two_opt_error) = combopt.tsp_two_opt(empty[0..], edge, tour[0..])
    if two_opt_error != combopt.TooSmall { os.exit(4) }
    os.exit(0)
}
