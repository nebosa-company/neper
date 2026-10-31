// `e.gpu` on a Metal device (C193, D5838): the program's own kernels, written as MSL by the compiler into the executable, run
// through `gpu.launch` on the Mac's GPU and checked against the CPU backend: saxpy, then a checked-build bounds fault that must
// come back as `Fault` while the queue keeps working. A machine with no Metal device reports a distinct skip. macOS only.
use e.mem
use e.os
use e.gpu

@gpu(256, ftz)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    y[k] = a*x[k] + y[k]
}

@gpu(64, ftz)
fn outside(y: []u32) {
    let k = usize(gpu.gid.x) + 1000usize
    y[k] = 1u32
}

@gpu(64)
fn keep(x: []const f32, y: []f32) {
    let i = usize(gpu.gid.x)
    y[i] = x[i] + 0.0
}

@gpu(1, ftz)
fn poke3(a: []u32, b: []u32, c: []u32, small: []u32) {
    if gpu.gid.x == 0u32 {
        a[a.len - 1usize] = 11u32
        b[b.len - 1usize] = 22u32
        c[c.len - 1usize] = 33u32
        small[0usize] = a[a.len - 1usize]
        small[1usize] = b[b.len - 1usize]
        small[2usize] = c[c.len - 1usize]
    }
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

fn skip_no_metal() {
    let (written, write_error) = os.write(os.stderr(), "NEPER_SKIP_NO_METAL\n")
    os.exit(95i32)
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
    if found_error == gpu.Unsupported || found_error == gpu.NoDevice { skip_no_metal() }
    if found_error != ok { os.exit(1i32) }
    if found.len == 0usize { skip_no_metal() }
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
    // Metal flushes subnormals, so a kernel that does not say `ftz` is refused rather than run flushed (spec section 11).
    var tiny: [64]f32 = zero
    var out: [64]f32 = zero
    let (dt, dt_error) = gpu.upload[f32](q, tiny[0..])
    let (dout, dout_error) = gpu.upload[f32](q, out[0..])
    if dt_error != ok || dout_error != ok { os.exit(12i32) }
    if gpu.launch[keep](q, gpu.grid1(64usize), dt, dout) != gpu.Unsupported { os.exit(13i32) }
    // More than one heap's worth (256 MiB) of buffers: three of 200 MiB live in their own heaps and all are reachable (D5877).
    let (ba, ba_error) = gpu.alloc[u32](q, 50000000usize)
    let (bb, bb_error) = gpu.alloc[u32](q, 50000000usize)
    let (bc, bc_error) = gpu.alloc[u32](q, 50000000usize)
    if ba_error != ok || bb_error != ok || bc_error != ok { os.exit(20i32) }
    var three: [3]u32 = zero
    let (dthree, dthree_error) = gpu.upload[u32](q, three[0..])
    if dthree_error != ok { os.exit(21i32) }
    if gpu.launch[poke3](q, gpu.grid1(1usize), ba, bb, bc, dthree) != ok { os.exit(22i32) }
    if gpu.download(q, dthree, three[0..]) != ok { os.exit(23i32) }
    if three[0] != 11u32 || three[1] != 22u32 || three[2] != 33u32 { os.exit(24i32) }
    // Released, their room is taken again.
    let freed_a = gpu.release(q, ba)
    let freed_b = gpu.release(q, bb)
    let freed_c = gpu.release(q, bc)
    let (again_big, again_error) = gpu.alloc[u32](q, 50000000usize)
    if again_error != ok { os.exit(25i32) }
    // Launches in a row without a download between them stay in flight (D5879), more than the four the device keeps: each sees the
    // last one's writes, and the sum is exact.
    var run_x: [1000]f32 = zero
    var run_y: [1000]f32 = zero
    var j = 0usize
    while j < 1000usize {
        run_x[j] = f32(j)
        run_y[j] = 1.0
        j += 1usize
    }
    let (px, px_error) = gpu.upload[f32](q, run_x[0..])
    let (py, py_error) = gpu.upload[f32](q, run_y[0..])
    if px_error != ok || py_error != ok { os.exit(30i32) }
    var rounds = 0usize
    while rounds < 7usize {
        if gpu.launch[saxpy](q, gpu.grid1(1000usize), 1000u32, 2.0, px, py) != ok { os.exit(31i32) }
        rounds += 1usize
    }
    if gpu.download(q, py, run_y[0..]) != ok { os.exit(32i32) }
    j = 0usize
    while j < 1000usize {
        if run_y[j] != 1.0 + 14.0*f32(j) { os.exit(33i32) }
        j += 1usize
    }
    // A fault in the middle of a run is reported once, from the next call that waits, and the launches around it still ran.
    var flags: [64]u32 = zero
    let (pf, pf_error) = gpu.upload[u32](q, flags[0..])
    if pf_error != ok { os.exit(34i32) }
    run_y[0] = 1.0
    let (py2, py2_error) = gpu.upload[f32](q, run_y[0..])
    if py2_error != ok { os.exit(35i32) }
    if gpu.launch[saxpy](q, gpu.grid1(1000usize), 1000u32, 2.0, px, py2) != ok { os.exit(36i32) }
    if gpu.launch[outside](q, gpu.grid1(64usize), pf) != ok { os.exit(37i32) }
    if gpu.launch[saxpy](q, gpu.grid1(1000usize), 1000u32, 2.0, px, py2) != ok { os.exit(38i32) }
    if gpu.download(q, py2, run_y[0..]) != gpu.Fault { os.exit(39i32) }
    let (record_again, had_again) = gpu.last_fault(q)
    if !had_again || record_again.kind != .Bounds { os.exit(40i32) }
    if gpu.download(q, py2, run_y[0..]) != ok { os.exit(41i32) }
    if run_y[3] != 43.0 + 12.0 { os.exit(42i32) }
    let closed = gpu.close(dev)
    ret ok
}
