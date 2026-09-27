// Section 10's address spaces (D1590): a workgroup's `shared var` sliced into a
// `[]const shared u32`, addressed as a `*shared u32`, and handed to a generic helper
// that is instantiated once per space -- beside a device slice given to the same
// helper. The kernel's results are checked on the CPU backend.

use e.gpu
use e.io
use e.mem
use e.os

fn pair(xs: []const shared u32) -> u32 {
    ret xs[0usize] + xs[1usize]
}

fn head[S: type](xs: S) -> u32 {
    ret xs[0usize]
}

fn cell(p: *shared u32) -> u32 {
    ret *p
}

// out[gid] = tile[0] + tile[1] + tile[0] + src[gid] + tile[2], each invocation having
// written its id + 1 into the tile.
@gpu(4)
fn combine(src: []const u32, out: []u32) {
    shared var tile: [4]u32
    let i = gpu.lid.x
    tile[usize(i)] = i + 1u32
    gpu.barrier()
    let part = tile[0usize..3usize]
    let here = usize(gpu.gid.x)
    out[here] = pair(part) + head(part) + head(src[here..here + 1usize]) + cell(&tile[2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    var values: [8]u32 = [8]u32{ 10u32, 20u32, 30u32, 40u32, 50u32, 60u32, 70u32, 80u32 }
    let (source, source_error) = gpu.upload[u32](q, values[0..])
    if source_error != ok { os.exit(3i32) }
    let (results, results_error) = gpu.alloc[u32](q, 8usize)
    if results_error != ok { os.exit(4i32) }
    if gpu.launch[combine](q, gpu.grid1(8usize), source, results) != ok { os.exit(5i32) }
    var out: [8]u32 = zero
    if gpu.download[u32](q, results, out[0..]) != ok { os.exit(6i32) }
    // 1 + 2 from the pair, 1 from the head, 3 from the cell: 7, plus the source.
    if out[0] != 17u32 || out[3] != 47u32 || out[7] != 87u32 { os.exit(7i32) }
    try io.print("gpu spaces ok\n")
    ret ok
}
