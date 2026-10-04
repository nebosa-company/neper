// `e.ml.gnn`: GCN, single-head GAT and message passing on a three-node
// chain against hand-computed projections, plus the storage and endpoint
// cases. Each check exits with its own code.

use e.mem
use e.ml.gnn as gnn
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [6]f64 = zero
    x[0usize] = 1.0f64
    x[1usize] = 0.0f64
    x[2usize] = 0.0f64
    x[3usize] = 1.0f64
    x[4usize] = 1.0f64
    x[5usize] = 1.0f64
    var src: [2]usize = zero
    src[0usize] = 0usize
    src[1usize] = 1usize
    var dst: [2]usize = zero
    dst[0usize] = 1usize
    dst[1usize] = 2usize
    var w: [4]f64 = zero
    w[0usize] = 0.5f64
    w[1usize] = 0.0f64 - 0.5f64
    w[2usize] = 1.0f64
    w[3usize] = 0.25f64
    var attention: [4]f64 = zero
    attention[0usize] = 0.5f64
    attention[1usize] = 0.0f64 - 0.5f64
    attention[2usize] = 0.25f64
    attention[3usize] = 0.1f64
    var message: [4]f64 = zero
    message[0usize] = 1.0f64
    message[1usize] = 0.0f64
    message[2usize] = 0.0f64
    message[3usize] = 1.0f64
    var update: [4]f64 = zero
    update[0usize] = 0.5f64
    update[1usize] = 0.5f64
    update[2usize] = 0.0f64 - 0.5f64
    update[3usize] = 0.5f64
    var out: [6]f64 = zero
    var scratch: [16]f64 = zero

    // 1: GCN with symmetric degree normalization and self-loops.
    if gnn.gcn_layer(x[..], 3usize, 2usize, 2usize, src[..], dst[..], 2usize, w[..], out[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(out[0usize], 0.5f64, 0.000000001f64) || !near(out[1usize], 0.0f64, 0.000000001f64) { os.exit(1i32) }
    if !near(out[2usize], 0.8535533905932737f64, 0.000000001f64) || !near(out[3usize], 0.0f64, 0.000000001f64) { os.exit(1i32) }
    if !near(out[4usize], 1.25f64, 0.000000001f64) || !near(out[5usize], 0.0f64, 0.000000001f64) { os.exit(1i32) }

    // 2: single-head GAT with max-subtracted softmax.
    if gnn.gat_layer(x[..], 3usize, 2usize, 2usize, src[..], dst[..], 2usize, w[..], attention[..], 0.2f64, out[..], scratch[..]) != ok { os.exit(2i32) }
    if !near(out[0usize], 0.5f64, 0.000000001f64) || !near(out[1usize], 0.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(out[2usize], 0.774916998656239f64, 0.000000001f64) || !near(out[3usize], 0.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(out[4usize], 1.2593706079392675f64, 0.000000001f64) || !near(out[5usize], 0.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(gnn.gat_score(x[..], 3usize, 2usize, 1usize, 0usize, attention[..], 0.2f64), 0.0f64 - 0.05f64, 0.000000001f64) { os.exit(2i32) }

    // 3: message passing with sum aggregation.
    if gnn.mpnn_step(x[..], 3usize, 2usize, 2usize, src[..], dst[..], 2usize, message[..], update[..], out[..], scratch[..]) != ok { os.exit(3i32) }
    if !near(out[0usize], 0.5f64, 0.000000001f64) || !near(out[1usize], 0.5f64, 0.000000001f64) { os.exit(3i32) }
    if !near(out[2usize], 0.5f64, 0.000000001f64) || !near(out[3usize], 0.5f64, 0.000000001f64) { os.exit(3i32) }
    if !near(out[4usize], 0.0f64, 0.000000001f64) || !near(out[5usize], 2.0f64, 0.000000001f64) { os.exit(3i32) }

    // 4: storage and endpoint cases.
    var bad: [2]usize = zero
    bad[0usize] = 0usize
    bad[1usize] = 9usize
    if gnn.gcn_layer(x[..], 3usize, 2usize, 2usize, bad[..], dst[..], 2usize, w[..], out[..], scratch[..]) != gnn.Invalid { os.exit(4i32) }
    if gnn.gat_layer(x[..], 3usize, 2usize, 2usize, src[..], dst[..], 2usize, w[..], attention[..], 0.2f64, out[..], scratch[..5usize]) != gnn.TooSmall { os.exit(4i32) }
    if gnn.mpnn_step(x[..], 3usize, 2usize, 2usize, src[..], bad[..], 2usize, message[..], update[..], out[..], scratch[..]) != gnn.Invalid { os.exit(4i32) }
    ret ok
}
