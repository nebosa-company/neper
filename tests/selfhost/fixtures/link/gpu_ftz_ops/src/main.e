// An `ftz` kernel's CPU run flushes denormals on every float operation it does, and only while it runs (D4203, spec
// section 11; D5834 for WebAssembly, whose floats keep denormals and which the compiler makes flush). `gpu_float_modes`
// has a product and a sum; this has the rest of the operations a kernel can write: a difference, a quotient, a square
// root, an equality and a comparison. Each runs in a kernel without `ftz` (the denormals survive, bit for bit what the
// host computes) and in one with it (inputs that are denormal read as zero, results that are denormal are zero, and
// the sign of the zero is kept), and the host computes in between to show the mode was left behind.

use e.gpu
use e.io
use e.math
use e.mem
use e.os

const N: usize = 16usize

@gpu(16)
fn sub_plain(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] - y[i]
}

@gpu(16, ftz)
fn sub_ftz(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] - y[i]
}

@gpu(16)
fn div_plain(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] / y[i]
}

@gpu(16, ftz)
fn div_ftz(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] / y[i]
}

@gpu(16)
fn root_plain(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = math.sqrt[f32](x[i])
}

@gpu(16, ftz)
fn root_ftz(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = math.sqrt[f32](x[i])
}

// 1.0 where the two are equal, 2.0 where the first is less, 0.0 otherwise.
fn relation(x: f32, y: f32) -> f32 {
    if x == y { ret 1.0 }
    if x < y { ret 2.0 }
    ret 0.0
}

@gpu(16)
fn compare_plain(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = relation(x[i], y[i])
}

@gpu(16, ftz)
fn compare_ftz(n: u32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = relation(x[i], y[i])
}

fn bits(value: f32) -> u32 { ret mem.bitcast[u32](value) }

// What FTZ and DAZ do to one float: a zero exponent is a denormal or a zero, and keeps only its sign.
fn flushed(value: f32) -> f32 {
    let pattern = bits(value)
    if (pattern & 2139095040u32) == 0u32 { ret mem.bitcast[f32](pattern & 2147483648u32) }
    ret value
}

// Denormal, zero, normal and tiny-normal operands, in pairs that give denormal differences and quotients.
fn fill(x: []f32, y: []f32) {
    let first: [16]u32 = [16]u32{ 8388610, 8388608, 5, 2147483655, 8388613, 4194304, 1, 8388609, 1065353216, 0, 2155872256, 12582912, 16777216, 3, 1073741824, 8388607 }
    let second: [16]u32 = [16]u32{ 8388608, 8388610, 3, 2147483650, 8388608, 4194304, 1, 0, 1073741824, 4194304, 1, 16777216, 8388608, 8388607, 1090519040, 8388608 }
    var at = 0usize
    while at < N {
        x[at] = mem.bitcast[f32](first[at])
        y[at] = mem.bitcast[f32](second[at])
        at += 1usize
    }
}

// `which`: 0 difference, 1 quotient, 2 root, 3 relation; `flush` picks the kernel with `ftz`.
fn run(q: *gpu.Queue, which: u32, flush: bool, x: []f32, y: []f32, out: []f32) -> err {
    let (dx, dx_error) = gpu.upload[f32](q, x)
    if dx_error != ok { ret dx_error }
    defer let _ = gpu.release(q, dx)
    let (dy, dy_error) = gpu.upload[f32](q, y)
    if dy_error != ok { ret dy_error }
    defer let _ = gpu.release(q, dy)
    let (dout, dout_error) = gpu.alloc[f32](q, N)
    if dout_error != ok { ret dout_error }
    defer let _ = gpu.release(q, dout)
    if which == 0u32 && !flush { try gpu.launch[sub_plain](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 0u32 && flush { try gpu.launch[sub_ftz](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 1u32 && !flush { try gpu.launch[div_plain](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 1u32 && flush { try gpu.launch[div_ftz](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 2u32 && !flush { try gpu.launch[root_plain](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 2u32 && flush { try gpu.launch[root_ftz](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 3u32 && !flush { try gpu.launch[compare_plain](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    if which == 3u32 && flush { try gpu.launch[compare_ftz](q, gpu.grid1(N), u32(N), dx, dy, dout) }
    ret gpu.download(q, dout, out)
}

// The host's own answer for one element, with the flushing done by hand when `flush`.
fn expect(which: u32, flush: bool, x: f32, y: f32) -> f32 {
    var a = x
    var b = y
    if flush {
        a = flushed(x)
        b = flushed(y)
    }
    var r: f32 = 0.0
    if which == 0u32 { r = a - b }
    if which == 1u32 { r = a / b }
    if which == 2u32 { r = math.sqrt[f32](a) }
    if which == 3u32 { r = relation(a, b) }
    if flush && which < 3u32 { ret flushed(r) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (x, x_error) = mem.alloc[f32](a, N)
    if x_error != ok { os.exit(3i32) }
    let (y, y_error) = mem.alloc[f32](a, N)
    if y_error != ok { os.exit(3i32) }
    let (got, got_error) = mem.alloc[f32](a, N)
    if got_error != ok { os.exit(3i32) }
    fill(x, y)
    var which = 0u32
    while which < 4u32 {
        var mode = 0u32
        while mode < 2u32 {
            let flush = mode == 1u32
            if run(q, which, flush, x, y, got) != ok { os.exit(10i32 + i32(which)) }
            var seen_difference = false
            var at = 0usize
            while at < N {
                let want = expect(which, flush, x[at], y[at])
                // NaN has more than one pattern; both sides here give the one quiet NaN.
                if bits(got[at]) != bits(want) { os.exit(20i32 + i32(which) * 40i32 + i32(mode) * 20i32 + i32(at)) }
                if bits(want) != bits(expect(which, !flush, x[at], y[at])) { seen_difference = true }
                at += 1usize
            }
            // The data has to tell the two modes apart for each operation, or the check proves nothing.
            if mode == 1u32 && !seen_difference { os.exit(200i32 + i32(which)) }
            mode += 1u32
        }
        which += 1u32
    }
    // The host kept its denormals through all of the runs.
    if bits(mem.bitcast[f32](8388610u32) * 0.5) != 4194305u32 { os.exit(210i32) }
    try io.print("gpu ftz ops ok\n")
    ret ok
}
