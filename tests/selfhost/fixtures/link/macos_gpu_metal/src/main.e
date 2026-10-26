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

@gpu(64)
fn outside(y: []u32) {
    let k = usize(gpu.gid.x) + 1000usize
    y[k] = 1u32
}

@gpu(64)
fn keep(x: []const f32, y: []f32) {
    let i = usize(gpu.gid.x)
    y[i] = x[i] + 0.0
}

fn run(q: *gpu.Queue, x: []const f32, y: []f32) -> err {
    let (dx, dx_error) = gpu.upload[f32](q, x)
    if dx_error != ok { os.exit(51i32) }
    let (dy, dy_error) = gpu.upload[f32](q, y)
    if dy_error != ok { os.exit(52i32) }
    let launched = gpu.launch[saxpy](q, gpu.grid1(x.len), u32(x.len), 2.0, dx, dy)
    if launched != ok { os.exit(53i32) }
    let downloaded = gpu.download(q, dy, y)
    if downloaded != ok { os.exit(54i32) }
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
    // A checked build's bounds fault comes back once, from the download, and the queue goes on working.
    var small: [64]u32 = zero
    let (bad, bad_error) = gpu.upload[u32](q, small[0..])
    if bad_error != ok { os.exit(6i32) }
    let faulted = gpu.launch[outside](q, gpu.grid1(64usize), bad)
    if faulted != ok { os.exit(7i32) }
    if gpu.download(q, bad, small[0..]) != gpu.Fault { os.exit(8i32) }
    let (record, had) = gpu.last_fault(q)
    if !had || record.kind != .Bounds { os.exit(9i32) }
    y[0] = 0.0
    let again = run(q, x[0..], y[0..])
    if again != ok { os.exit(10i32) }
    if y[1] != 7.0 { os.exit(11i32) }
    // A subnormal passes through an add of zero: the device preserves denormals, as the CPU does.
    var tiny: [64]f32 = zero
    var out: [64]f32 = zero
    tiny[3] = 0.00000000000000000000000000000000000001
    let (dt, dt_error) = gpu.upload[f32](q, tiny[0..])
    let (dout, dout_error) = gpu.upload[f32](q, out[0..])
    if dt_error != ok || dout_error != ok { os.exit(12i32) }
    let kept = gpu.launch[keep](q, gpu.grid1(64usize), dt, dout)
    if kept != ok { os.exit(13i32) }
    if gpu.download(q, dout, out[0..]) != ok { os.exit(14i32) }
    if out[3] != tiny[3] || out[3] == 0.0 { os.exit(15i32) }
    let closed = gpu.close(dev)
    ret ok
}
