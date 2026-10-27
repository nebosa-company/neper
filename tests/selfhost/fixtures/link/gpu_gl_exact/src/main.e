// Exact f32 division and square root on e.gpu's `.Gl` backend (C217, D5891), built with `--gpu glsl`: GLSL rounds neither
// correctly, so the emitter writes both as integer sequences, and every result word must equal the CPU backend's. 65,536
// operand pairs from a fixed xorshift: random bit patterns over every exponent, the special values (zeros, infinities, NaNs,
// the largest and smallest normals, subnormals) in both positions, and quotients that land in the subnormal range and past
// the largest finite. A device that keeps denormals runs the plain kernels; one that flushes them (Intel) the `ftz` ones,
// which the CPU flushes too. A host without an OpenGL compute device exits 0 having printed why.

use e.gpu
use e.io
use e.math
use e.mem
use e.os
use x.khronos.compute

@gpu(64)
fn divide(n: u32, x: []const f32, y: []const f32, q: []f32, r: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    q[k] = x[k] / y[k]
    r[k] = math.sqrt[f32](x[k])
}

@gpu(64, ftz)
fn divide_ftz(n: u32, x: []const f32, y: []const f32, q: []f32, r: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    q[k] = x[k] / y[k]
    r[k] = math.sqrt[f32](x[k])
}

const N: usize = 65536usize

fn special(k: u32) -> u32 {
    let table = k % 16u32
    if table == 0u32 { ret 0u32 }
    if table == 1u32 { ret 2147483648u32 }
    if table == 2u32 { ret 2139095040u32 }
    if table == 3u32 { ret 4286578688u32 }
    if table == 4u32 { ret 2143289344u32 }
    if table == 5u32 { ret 2139095041u32 }
    if table == 6u32 { ret 2139095039u32 }
    if table == 7u32 { ret 8388608u32 }
    if table == 8u32 { ret 1u32 }
    if table == 9u32 { ret 8388607u32 }
    if table == 10u32 { ret 1065353216u32 }
    if table == 11u32 { ret 3212836864u32 }
    if table == 12u32 { ret 1073741824u32 }
    if table == 13u32 { ret 4194304u32 }
    if table == 14u32 { ret 1077936128u32 }
    ret 2155872256u32
}

fn bits_to(value: u32) -> f32 {
    var held = value
    ret *mem.cast[*f32](&held)
}

fn run(a: *mem.Arena, backend: gpu.Backend, flushing: bool, xs: []const f32, ys: []const f32, out: []u32) -> err {
    let (device, open_error) = gpu.open(a, backend, 0u32)
    if open_error != ok { ret open_error }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (x, x_error) = gpu.upload[f32](queue, xs)
    let (y, y_error) = gpu.upload[f32](queue, ys)
    let (q, q_error) = gpu.alloc[f32](queue, N)
    let (r, r_error) = gpu.alloc[f32](queue, N)
    if x_error != ok || y_error != ok || q_error != ok || r_error != ok { os.exit(2i32) }
    var launched = ok
    if flushing { launched = gpu.launch[divide_ftz](queue, gpu.grid1(N), u32(N), x, y, q, r) } else { launched = gpu.launch[divide](queue, gpu.grid1(N), u32(N), x, y, q, r) }
    if launched != ok { ret launched }
    let (quotients, quotients_error) = mem.alloc[f32](a, N)
    let (roots, roots_error) = mem.alloc[f32](a, N)
    if quotients_error != ok || roots_error != ok { os.exit(3i32) }
    if gpu.download(queue, q, quotients) != ok || gpu.download(queue, r, roots) != ok { os.exit(4i32) }
    var k = 0usize
    while k < N {
        out[k] = *mem.cast[*u32](&quotients[k])
        out[N + k] = *mem.cast[*u32](&roots[k])
        k += 1usize
    }
    ret gpu.close(device)
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error != ok || found.len == 0usize {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    var flushing = true
    for capability in found[0usize].capabilities {
        if capability == .DenormPreserve { flushing = false }
    }
    let (xs, xs_error) = mem.alloc[f32](a, N)
    let (ys, ys_error) = mem.alloc[f32](a, N)
    let (cpu_out, cpu_error) = mem.alloc[u32](a, 2usize * N)
    let (gl_out, gl_error) = mem.alloc[u32](a, 2usize * N)
    if xs_error != ok || ys_error != ok || cpu_error != ok || gl_error != ok { os.exit(5i32) }
    var state = 2463534242u32
    var k = 0usize
    while k < N {
        state = state ^ (state << 13u32)
        state = state ^ (state >> 17u32)
        state = state ^ (state << 5u32)
        var xb = state
        state = state ^ (state << 13u32)
        state = state ^ (state >> 17u32)
        state = state ^ (state << 5u32)
        var yb = state
        // Every eighth pair has a special value in one place or both; every fourth divisor is near the dividend's scale,
        // so the quotient is near one and the rounding is decided in the last bits.
        if k % 8usize == 1usize { xb = special(u32(k / 8usize)) }
        if k % 8usize == 2usize { yb = special(u32(k / 8usize)) }
        if k % 8usize == 3usize {
            xb = special(u32(k / 8usize))
            yb = special(u32(k / 128usize))
        }
        if k % 4usize == 0usize { yb = (xb & 4286578688u32) | (yb & 8388607u32) }
        xs[k] = bits_to(xb)
        ys[k] = bits_to(yb)
        k += 1usize
    }
    if run(a, .Cpu, flushing, xs, ys, cpu_out) != ok { os.exit(6i32) }
    let gl_run = run(a, .Gl, flushing, xs, ys, gl_out)
    if gl_run != ok { os.exit(7i32) }
    var wrong_quotients = 0usize
    var wrong_roots = 0usize
    k = 0usize
    while k < N {
        if cpu_out[k] != gl_out[k] { wrong_quotients += 1usize }
        if cpu_out[N + k] != gl_out[N + k] { wrong_roots += 1usize }
        k += 1usize
    }
    if wrong_quotients != 0usize { os.exit(8i32) }
    if wrong_roots != 0usize { os.exit(9i32) }
    if flushing { let mode = io.print("(ftz) ") }
    let named = io.print("65536 f32 quotients and square roots equal to the CPU backend's on ")
    let device_name = io.print(found[0usize].name)
    let ended = io.print("\n")
    ret ok
}
