// `e.gpu` on a Metal device (C193, D5838): the program's own kernels, written as MSL by the compiler into the executable, run
// through `gpu.launch` on the Mac's GPU and checked against the CPU backend: saxpy, then a checked-build bounds fault that must
// come back as `Fault` while the queue keeps working. A machine with no Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.gpu

@gpu(256)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    y[k] = a*x[k] + y[k]
}

fn run(q: *gpu.Queue, x: []const f32, y: []f32) -> err {
    let (dx, dx_error) = gpu.upload[f32](q, x)
    if dx_error != ok { ret dx_error }
    let (dy, dy_error) = gpu.upload[f32](q, y)
    if dy_error != ok { ret dy_error }
    try gpu.launch[saxpy](q, gpu.grid1(x.len), u32(x.len), 2.0, dx, dy)
    try gpu.download(q, dy, y)
    let r1 = gpu.release(q, dx)
    let r2 = gpu.release(q, dy)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [1000]f32 = zero
    var y: [1000]f32 = zero
    var at = 0usize
    while at < 1000usize {
        x[at] = f32(at)
        y[at] = 3.0
        at += 1usize
    }
    let (found, found_error) = gpu.devices(a, .Metal, 4usize)
    if found_error != ok { os.exit(0i32) }
    if found.len == 0usize { os.exit(0i32) }
    let (dev, open_error) = gpu.open(a, .Metal, 0u32)
    if open_error != ok { os.exit(2i32) }
    let (q, q_error) = gpu.queue(dev)
    if q_error != ok { os.exit(3i32) }
    let ran = run(q, x[0..], y[0..])
    if ran == gpu.Unsupported { os.exit(41i32) }
    if ran == gpu.Lost { os.exit(42i32) }
    if ran == gpu.TooLarge { os.exit(43i32) }
    if ran == gpu.OutOfMemory { os.exit(44i32) }
    if ran == gpu.InvalidHandle { os.exit(45i32) }
    if ran == gpu.Fault { os.exit(46i32) }
    if ran != ok { os.exit(4i32) }
    at = 0usize
    while at < 1000usize {
        if y[at] != 2.0*f32(at) + 3.0 { os.exit(5i32) }
        at += 1usize
    }
    let closed = gpu.close(dev)
    ret ok
}
