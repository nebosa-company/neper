// Spec section 11 on a kernel (C095, D4203): no implicit contraction, `math.fma` the only
// fused multiply-add, denormals preserved unless the kernel says `ftz`, and `f64`
// preserved even then. Each case runs on the CPU build and on every Vulkan device that
// is at the floor and compares bit for bit with what the host computes (the host is
// built under the same rules): `a * x + y` is two roundings, `math.fma` one; a
// denormal result or input survives a kernel without `ftz` and is flushed in one with
// it; a CPU `ftz` kernel does not leave FTZ set on the host afterwards.
//
// A kernel whose requirement a device does not have is refused at launch with
// `Unsupported`, never run: that refusal is part of what each case checks.

use e.gpu
use e.io
use e.math
use e.mem
use e.os

const N: usize = 16usize

@gpu(16)
fn mul_add(n: u32, a: []f32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = a[i] * x[i] + y[i]
}

@gpu(16)
fn fused(n: u32, a: []f32, x: []f32, y: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = math.fma[f32](a[i], x[i], y[i])
}

fn half_of(value: f32) -> f32 { ret value * 0.5 }

@gpu(16)
fn halve(n: u32, x: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = half_of(x[i])
}

@gpu(16, ftz)
fn halve_ftz(n: u32, x: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = half_of(x[i])
}

@gpu(16)
fn plus_zero(n: u32, x: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] + 0.0
}

@gpu(16, ftz)
fn plus_zero_ftz(n: u32, x: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] + 0.0
}

@gpu(16)
fn halve64(n: u32, x: []f64, out: []f64) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] * 0.5
}

@gpu(16, ftz)
fn halve64_ftz(n: u32, x: []f64, out: []f64) {
    let i = usize(gpu.gid.x)
    if gpu.gid.x >= n { ret }
    out[i] = x[i] * 0.5
}

fn bits(value: f32) -> u32 { ret mem.bitcast[u32](value) }
fn bits64(value: f64) -> u64 { ret mem.bitcast[u64](value) }
fn is_denormal(value: f32) -> bool {
    let magnitude = bits(value) & 2147483647u32
    ret magnitude != 0u32 && magnitude < 8388608u32
}
fn is_zero(value: f32) -> bool { ret (bits(value) & 2147483647u32) == 0u32 }

fn unfused(a: f32, x: f32, y: f32) -> f32 {
    let product = a * x
    ret product + y
}

// What the kernels see: pairs where one rounding and two differ, denormal operands and
// operands whose halves are denormal.
fn fill(a: []f32, x: []f32, y: []f32, d: []f32) {
    var at = 0usize
    while at < N {
        a[at] = mem.bitcast[f32](1065353216u32 + u32(at))
        x[at] = mem.bitcast[f32](1065353216u32 - u32(at * 3usize))
        y[at] = -1.0
        at += 1usize
    }
    // (1 + 2^-13)(1 - 2^-13) rounds to 1, and minus 1 is 0; the fused answer is -2^-26.
    a[0usize] = mem.bitcast[f32](1065354240u32)
    x[0usize] = mem.bitcast[f32](1065351168u32)
    let edge: [16]u32 = [16]u32{ 8388608, 8388611, 1065353216, 0, 2155872256, 8388613, 5, 2147483655, 8388607, 4194304, 8388609, 1, 2147483649, 8388610, 3212836864, 2139095039 }
    at = 0usize
    while at < N {
        d[at] = mem.bitcast[f32](edge[at])
        at += 1usize
    }
}

fn expect_equal_f32(label: i32, got: []const f32, want: []const f32) {
    var at = 0usize
    while at < want.len {
        if bits(got[at]) != bits(want[at]) { os.exit(label + i32(at)) }
        at += 1usize
    }
}

fn run_arith(q: *gpu.Queue, a: []f32, x: []f32, y: []f32, out: []f32, use_fma: bool) -> err {
    let (da, da_error) = gpu.upload[f32](q, a)
    if da_error != ok { ret da_error }
    defer let _ = gpu.release(q, da)
    let (dx, dx_error) = gpu.upload[f32](q, x)
    if dx_error != ok { ret dx_error }
    defer let _ = gpu.release(q, dx)
    let (dy, dy_error) = gpu.upload[f32](q, y)
    if dy_error != ok { ret dy_error }
    defer let _ = gpu.release(q, dy)
    let (dout, dout_error) = gpu.alloc[f32](q, N)
    if dout_error != ok { ret dout_error }
    defer let _ = gpu.release(q, dout)
    if use_fma {
        try gpu.launch[fused](q, gpu.grid1(N), u32(N), da, dx, dy, dout)
    } else {
        try gpu.launch[mul_add](q, gpu.grid1(N), u32(N), da, dx, dy, dout)
    }
    ret gpu.download(q, dout, out)
}

// `which`: 0 halve, 1 halve_ftz, 2 plus_zero, 3 plus_zero_ftz.
fn run_unary(q: *gpu.Queue, which: u32, x: []f32, out: []f32) -> err {
    let (dx, dx_error) = gpu.upload[f32](q, x)
    if dx_error != ok { ret dx_error }
    defer let _ = gpu.release(q, dx)
    let (dout, dout_error) = gpu.alloc[f32](q, N)
    if dout_error != ok { ret dout_error }
    defer let _ = gpu.release(q, dout)
    if which == 0u32 { try gpu.launch[halve](q, gpu.grid1(N), u32(N), dx, dout) }
    if which == 1u32 { try gpu.launch[halve_ftz](q, gpu.grid1(N), u32(N), dx, dout) }
    if which == 2u32 { try gpu.launch[plus_zero](q, gpu.grid1(N), u32(N), dx, dout) }
    if which == 3u32 { try gpu.launch[plus_zero_ftz](q, gpu.grid1(N), u32(N), dx, dout) }
    ret gpu.download(q, dout, out)
}

fn run_double(q: *gpu.Queue, flush: bool, x: []f64, out: []f64) -> err {
    let (dx, dx_error) = gpu.upload[f64](q, x)
    if dx_error != ok { ret dx_error }
    defer let _ = gpu.release(q, dx)
    let (dout, dout_error) = gpu.alloc[f64](q, N)
    if dout_error != ok { ret dout_error }
    defer let _ = gpu.release(q, dout)
    if flush {
        try gpu.launch[halve64_ftz](q, gpu.grid1(N), u32(N), dx, dout)
    } else {
        try gpu.launch[halve64](q, gpu.grid1(N), u32(N), dx, dout)
    }
    ret gpu.download(q, dout, out)
}

fn check_device(a: *mem.Arena, backend: gpu.Backend, index: u32, base: i32) -> err {
    let (device, open_error) = gpu.open(a, backend, index)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (va, va_error) = mem.alloc[f32](a, N)
    if va_error != ok { ret va_error }
    let (vx, vx_error) = mem.alloc[f32](a, N)
    if vx_error != ok { ret vx_error }
    let (vy, vy_error) = mem.alloc[f32](a, N)
    if vy_error != ok { ret vy_error }
    let (vd, vd_error) = mem.alloc[f32](a, N)
    if vd_error != ok { ret vd_error }
    let (got, got_error) = mem.alloc[f32](a, N)
    if got_error != ok { ret got_error }
    let (want, want_error) = mem.alloc[f32](a, N)
    if want_error != ok { ret want_error }
    fill(va, vx, vy, vd)

    // Contraction: two roundings on the device and on the CPU build alike, one rounding
    // only where the source says `math.fma`. Both need a device that preserves
    // denormals only because a kernel with floats is written with that mode.
    if gpu.has(device, .DenormPreserve) {
        var at = 0usize
        while at < N {
            want[at] = unfused(va[at], vx[at], vy[at])
            at += 1usize
        }
        try run_arith(q, va, vx, vy, got, false)
        expect_equal_f32(base + 0i32, got, want)
        at = 0usize
        while at < N {
            want[at] = math.fma[f32](va[at], vx[at], vy[at])
            at += 1usize
        }
        try run_arith(q, va, vx, vy, got, true)
        expect_equal_f32(base + 20i32, got, want)
    } else {
        if run_arith(q, va, vx, vy, got, false) != gpu.Unsupported { os.exit(base + 40i32) }
    }

    // Denormals preserved by a kernel without `ftz`.
    var at = 0usize
    while at < N {
        want[at] = half_of(vd[at])
        at += 1usize
    }
    if gpu.has(device, .DenormPreserve) {
        try run_unary(q, 0u32, vd, got)
        expect_equal_f32(base + 50i32, got, want)
        var seen = false
        at = 0usize
        while at < N {
            if is_denormal(got[at]) { seen = true }
            at += 1usize
        }
        if !seen { os.exit(base + 70i32) }
        at = 0usize
        while at < N {
            want[at] = vd[at] + 0.0
            at += 1usize
        }
        try run_unary(q, 2u32, vd, got)
        expect_equal_f32(base + 80i32, got, want)
    } else {
        if run_unary(q, 0u32, vd, got) != gpu.Unsupported { os.exit(base + 100i32) }
    }

    // `ftz`: results that would be denormal are zero, the rest unchanged; refused where
    // the device cannot flush.
    if gpu.has(device, .Ftz) {
        try run_unary(q, 1u32, vd, got)
        at = 0usize
        while at < N {
            let half = half_of(vd[at])
            var expected = half
            if is_denormal(half) { expected = 0.0 }
            if is_denormal(half) && !is_zero(got[at]) { os.exit(base + 110i32 + i32(at)) }
            if !is_denormal(half) && bits(got[at]) != bits(expected) { os.exit(base + 110i32 + i32(at)) }
            at += 1usize
        }
        try run_unary(q, 3u32, vd, got)
        at = 0usize
        while at < N {
            if is_denormal(vd[at]) && !is_zero(got[at]) { os.exit(base + 130i32 + i32(at)) }
            if !is_denormal(vd[at]) && bits(got[at]) != bits(vd[at]) { os.exit(base + 130i32 + i32(at)) }
            at += 1usize
        }
    } else {
        if run_unary(q, 1u32, vd, got) != gpu.Unsupported { os.exit(base + 150i32) }
    }

    // A CPU `ftz` run does not leave the host flushing.
    var host_half = half_of(vd[0usize])
    if !is_denormal(host_half) { os.exit(base + 151i32) }

    // `f64` keeps its denormals without `ftz`. With it the CPU build cannot keep them --
    // MXCSR's FTZ and DAZ are one bit for both widths -- so a CPU launch of a kernel that
    // is both `ftz` and `f64` is refused (`Unsupported`) rather than run flushed; a device
    // keeps them where the SPIR-V writer has `f64` at all (it does not yet: `Unsupported`).
    if gpu.has(device, .Float64) && gpu.has(device, .DenormPreserve) {
        let (vx64, vx64_error) = mem.alloc[f64](a, N)
        if vx64_error != ok { ret vx64_error }
        let (got64, got64_error) = mem.alloc[f64](a, N)
        if got64_error != ok { ret got64_error }
        var wide = 0usize
        while wide < N {
            vx64[wide] = mem.bitcast[f64](4503599627370496u64 + u64(wide))
            wide += 1usize
        }
        let preserved_error = run_double(q, false, vx64, got64)
        if backend == .Cpu && preserved_error != ok { os.exit(base + 154i32) }
        if preserved_error != ok && preserved_error != gpu.Unsupported { os.exit(base + 154i32) }
        if preserved_error == ok {
            wide = 0usize
            while wide < N {
                if bits64(got64[wide]) != bits64(vx64[wide] * 0.5) { os.exit(base + 152i32) }
                wide += 1usize
            }
        }
        let flushed_error = run_double(q, true, vx64, got64)
        if backend == .Cpu && flushed_error != gpu.Unsupported { os.exit(base + 155i32) }
        if flushed_error != ok && flushed_error != gpu.Unsupported { os.exit(base + 155i32) }
        if flushed_error == ok {
            wide = 0usize
            while wide < N {
                if bits64(got64[wide]) != bits64(vx64[wide] * 0.5) { os.exit(base + 153i32) }
                wide += 1usize
            }
        }
    }
    // The host is untouched by all of the above.
    var after = half_of(vd[0usize])
    if !is_denormal(after) { os.exit(base + 156i32) }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The inputs have to tell the two roundings apart, or the case proves nothing.
    let (ta, ta_error) = mem.alloc[f32](a, N)
    if ta_error != ok { ret ta_error }
    let (tx, tx_error) = mem.alloc[f32](a, N)
    if tx_error != ok { ret tx_error }
    let (ty, ty_error) = mem.alloc[f32](a, N)
    if ty_error != ok { ret ty_error }
    let (td, td_error) = mem.alloc[f32](a, N)
    if td_error != ok { ret td_error }
    fill(ta, tx, ty, td)
    if bits(unfused(ta[0usize], tx[0usize], ty[0usize])) == bits(math.fma[f32](ta[0usize], tx[0usize], ty[0usize])) { os.exit(1i32) }
    try check_device(a, .Cpu, 0u32, 10i32)
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == ok {
        var at = 0usize
        var ran = 0usize
        while at < found.len {
            if found[at].supported {
                try check_device(a, .Vulkan, u32(at), 10i32)
                ran += 1usize
            }
            at += 1usize
        }
        try io.printf["gpu float modes ok on cpu and {} devices\n"](ran)
        ret ok
    }
    try io.print("gpu float modes ok on cpu\n")
    ret ok
}
