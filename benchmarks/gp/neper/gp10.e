// GP-10 measurement: one exact integer affine kernel on the CPU debugger and
// on the first Vulkan 1.2-floor device.
use e.gpu
use e.io
use e.mem
use e.os

const N: usize = 1048576usize
const ITERS: usize = 16usize

@gpu(256)
fn affine(n: u32, x: []const u32, y: []u32) {
    let lane = gpu.gid.x
    if lane < n {
        let at = usize(lane)
        y[at] = 3u32 * x[at] + y[at]
    }
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32) -> (u64, err) {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret (0u64, device_error) }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (0u64, queue_error) }
    let (x, x_error) = mem.alloc[u32](a, N)
    let (y, y_error) = mem.alloc[u32](a, N)
    if x_error != ok || y_error != ok { ret (0u64, mem.Exhausted) }
    var i = 0usize
    while i < N {
        x[i] = u32(i & 1023usize)
        y[i] = 1u32
        i += 1usize
    }
    let (dx, dx_error) = gpu.upload[u32](q, x)
    if dx_error != ok { ret (0u64, dx_error) }
    defer let _ = gpu.release(q, dx)
    let (dy, dy_error) = gpu.upload[u32](q, y)
    if dy_error != ok { ret (0u64, dy_error) }
    defer let _ = gpu.release(q, dy)
    var iteration = 0usize
    while iteration < ITERS {
        try gpu.launch[affine](q, gpu.grid1(N), u32(N), dx, dy)
        iteration += 1usize
    }
    try gpu.download(q, dy, y)
    var checksum = 0u64
    i = 0usize
    while i < N {
        checksum += u64(y[i])
        i += 1usize
    }
    ret (checksum, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len != 2usize { os.exit(1i32) }
    var backend = gpu.Backend.Cpu
    var index = 0u32
    if same(args[1usize], "vulkan") {
        backend = .Vulkan
        let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
        if found_error != ok { ret found_error }
        var at = 0usize
        while at < found.len {
            if found[at].supported {
                index = u32(at)
                break
            }
            at += 1usize
        }
        if at == found.len { ret gpu.NoDevice }
    } else if !same(args[1usize], "cpu") {
        os.exit(1i32)
    }
    let (checksum, run_error) = run(a, backend, index)
    if run_error != ok { ret run_error }
    try io.printf["gp10 {}\n"](checksum)
    ret ok
}
