// A cold build's `--stats` counts of a module whose block went back (D1667) are a
// warm build's, which parses the kept module: this one carries a `@gpu` kernel and a
// `@test`, beside `e.os`'s externs and `@import`s. (`@nochecks` counts the attribute,
// which a `@nocheck { ... }` block is not, so no fixture here moves it off zero.)

use e.gpu
use e.io
use e.mem
use e.os

error Odd

@gpu(4)
fn copy(xs: []u32, ys: []u32) {
    let i = gpu.gid.x
    ys[usize(i)] = xs[usize(i)]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    var xs: [4]u32 = zero
    let (dx, dx_error) = gpu.upload[u32](q, xs[0..])
    if dx_error != ok { os.exit(3i32) }
    let (dy, dy_error) = gpu.alloc[u32](q, 4usize)
    if dy_error != ok { os.exit(4i32) }
    if gpu.launch[copy](q, gpu.grid1(4usize), dx, dy) != ok { os.exit(5i32) }
    if gpu.sync(q) != ok { os.exit(6i32) }
    if gpu.close(device) != ok { os.exit(7i32) }
    try io.print("front counts ok\n")
    ret ok
}

@test
fn counted(a: *mem.Arena) -> err {
    if 2i32 + 2i32 == 4i32 { ret ok }
    ret Odd
}
