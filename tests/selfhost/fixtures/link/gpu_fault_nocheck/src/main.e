// A `@nocheck` block in a kernel (D785, contract section 1.3) carries no bounds
// check and no fault: the read past the end is whatever follows the buffer, the
// launch syncs `ok` with no record, and the result is unspecified.

use e.gpu
use e.io
use e.mem
use e.os

@gpu(4)
fn poke(xs: []u32, ys: []u32) {
    let i = gpu.gid.x
    @nocheck {
        ys[usize(i)] = xs[usize(i) + 8usize]
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    var xs: [8]u32 = zero
    let (dx, dx_error) = gpu.upload[u32](q, xs[0..])
    if dx_error != ok { os.exit(3i32) }
    let (dy, dy_error) = gpu.alloc[u32](q, 4usize)
    if dy_error != ok { os.exit(4i32) }
    if gpu.launch[poke](q, gpu.grid1(4usize), dx, dy) != ok { os.exit(5i32) }
    if gpu.sync(q) != ok { os.exit(6i32) }
    let (_, found) = gpu.last_fault(q)
    if found { os.exit(7i32) }
    var seen: [4]u32 = zero
    if gpu.download(q, dy, seen[0..]) != ok { os.exit(8i32) }
    if gpu.close(device) != ok { os.exit(9i32) }
    try io.print("gpu nocheck ok\n")
    ret ok
}
