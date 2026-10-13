// `f64` in a kernel (C095): add, subtract, multiply, negate, compare, `math.fma`, the
// conversions to and from `f32` and integers, `f64` in private memory (a local array) and
// in device buffers, on the CPU build and on every Vulkan device that has `Float64`. Each
// result is compared bit for bit with the host's answer to the same expressions. A device
// without `Float64`, or that preserves no denormals (a float kernel is written with that
// mode), refuses the launch with `Unsupported`; division and square root of
// `f64` are not written as SPIR-V yet and are not exercised here.
//
// On the machine this was written on no device runs it: one has no `Float64`, the other
// preserves no denormals. It passed on that second device (the RTX 3080) with the
// `.DenormPreserve` gate forced on for the experiment (D4701), every result bit for bit.

use e.gpu
use e.io
use e.math
use e.mem
use e.os

const N: usize = 16usize

fn expression(x: f64, y: f64) -> f64 {
    var t: [2]f64 = [2]f64{ 0.0, 0.0 }
    t[0usize] = x * y
    t[1usize] = t[0usize] + x
    let w = t[1usize] - y
    ret -w + math.fma[f64](x, y, 1.0)
}

fn narrowed(x: f64) -> f32 { ret f32(x) }
fn widened(i: i32) -> f64 { ret f64(i) }
fn truncated(x: f64) -> i32 { ret i32(x) }

@gpu(16, caps(.Float64))
fn arith(n: u32, x: []f64, y: []f64, out: []f64, small: []f32, back: []f64, whole: []i32, order: []u32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = expression(x[i], y[i])
    small[i] = narrowed(x[i])
    back[i] = widened(i32(i) - 8i32) + x[i]
    whole[i] = truncated(y[i])
    var flag = 0u32
    if x[i] < y[i] { flag = flag + 1u32 }
    if x[i] == y[i] { flag = flag + 2u32 }
    if x[i] >= y[i] { flag = flag + 4u32 }
    order[i] = flag
}

fn bits64(value: f64) -> u64 { ret mem.bitcast[u64](value) }
fn bits32(value: f32) -> u32 { ret mem.bitcast[u32](value) }

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, base: i32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (x, x_error) = mem.alloc[f64](a, N)
    if x_error != ok { ret x_error }
    let (y, y_error) = mem.alloc[f64](a, N)
    if y_error != ok { ret y_error }
    var at = 0usize
    while at < N {
        // Inputs a single-precision unit cannot hold: low bits below 2^-24, a tie, a
        // negative, a large and a tiny magnitude.
        x[at] = 1.0 + f64(at) * 1.1102230246251565e-16 + 3.0e-13 * f64(at)
        y[at] = 7.25 - f64(at) * 0.75
        at += 1usize
    }
    x[0usize] = 1.0 + 5.9604644775390625e-8 + 1.0e-12
    x[1usize] = 16777217.0
    x[2usize] = -3.5
    x[3usize] = 1.0e300
    x[4usize] = 1.0e-300
    y[4usize] = x[4usize]
    y[5usize] = x[5usize]
    let (got, got_error) = mem.alloc[f64](a, N)
    if got_error != ok { ret got_error }
    let (small, small_error) = mem.alloc[f32](a, N)
    if small_error != ok { ret small_error }
    let (back, back_error) = mem.alloc[f64](a, N)
    if back_error != ok { ret back_error }
    let (whole, whole_error) = mem.alloc[i32](a, N)
    if whole_error != ok { ret whole_error }
    let (order, order_error) = mem.alloc[u32](a, N)
    if order_error != ok { ret order_error }
    let (dx, dx_error) = gpu.upload[f64](q, x)
    if dx_error != ok { ret dx_error }
    defer let _ = gpu.release(q, dx)
    let (dy, dy_error) = gpu.upload[f64](q, y)
    if dy_error != ok { ret dy_error }
    defer let _ = gpu.release(q, dy)
    let (dout, dout_error) = gpu.alloc[f64](q, N)
    if dout_error != ok { ret dout_error }
    defer let _ = gpu.release(q, dout)
    let (dsmall, dsmall_error) = gpu.alloc[f32](q, N)
    if dsmall_error != ok { ret dsmall_error }
    defer let _ = gpu.release(q, dsmall)
    let (dback, dback_error) = gpu.alloc[f64](q, N)
    if dback_error != ok { ret dback_error }
    defer let _ = gpu.release(q, dback)
    let (dwhole, dwhole_error) = gpu.alloc[i32](q, N)
    if dwhole_error != ok { ret dwhole_error }
    defer let _ = gpu.release(q, dwhole)
    let (dorder, dorder_error) = gpu.alloc[u32](q, N)
    if dorder_error != ok { ret dorder_error }
    defer let _ = gpu.release(q, dorder)
    if !gpu.has(device, .Float64) || !gpu.has(device, .DenormPreserve) {
        let refused = gpu.launch[arith](q, gpu.grid1(N), u32(N), dx, dy, dout, dsmall, dback, dwhole, dorder)
        if refused != gpu.Unsupported { os.exit(base + 1i32) }
        ret ok
    }
    try gpu.launch[arith](q, gpu.grid1(N), u32(N), dx, dy, dout, dsmall, dback, dwhole, dorder)
    try gpu.download(q, dout, got)
    try gpu.download(q, dsmall, small)
    try gpu.download(q, dback, back)
    try gpu.download(q, dwhole, whole)
    try gpu.download(q, dorder, order)
    at = 0usize
    while at < N {
        let i = i32(at)
        if bits64(got[at]) != bits64(expression(x[at], y[at])) { os.exit(base + 10i32 + i) }
        if bits32(small[at]) != bits32(narrowed(x[at])) { os.exit(base + 30i32 + i) }
        if bits64(back[at]) != bits64(widened(i - 8i32) + x[at]) { os.exit(base + 50i32 + i) }
        if whole[at] != truncated(y[at]) { os.exit(base + 70i32 + i) }
        var flag = 0u32
        if x[at] < y[at] { flag = flag + 1u32 }
        if x[at] == y[at] { flag = flag + 2u32 }
        if x[at] >= y[at] { flag = flag + 4u32 }
        if order[at] != flag { os.exit(base + 90i32 + i) }
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try run(a, .Cpu, 0u32, 100i32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == ok {
        var at = 0usize
        var ran = 0usize
        var wide = 0usize
        while at < found.len {
            if found[at].supported {
                try run(a, .Vulkan, u32(at), 100i32 + 100i32 * i32(at + 1usize))
                ran += 1usize
                var cap_at = 0usize
                var has_float64 = false
                var has_denorm = false
                while cap_at < found[at].capabilities.len {
                    if found[at].capabilities[cap_at] == .Float64 { has_float64 = true }
                    if found[at].capabilities[cap_at] == .DenormPreserve { has_denorm = true }
                    cap_at += 1usize
                }
                if has_float64 && has_denorm { wide += 1usize }
            }
            at += 1usize
        }
        try io.printf["gpu f64 ok on cpu and {} devices ({} ran f64)\n"](ran, wide)
        ret ok
    }
    try io.print("gpu f64 ok on cpu\n")
    ret ok
}
