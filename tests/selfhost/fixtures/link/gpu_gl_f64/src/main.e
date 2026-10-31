// f64 on e.gpu's `.Gl` backend (L181, D5903), built with `--gpu glsl`: GLSL's `double`, with every NaN result section 11's
// canonical 0x7FF8000000000000. 65,536 operand pairs from a fixed xorshift (random bit patterns over every exponent, and the
// special values in both places) through + - * / and the square root, and each first operand narrowed to f32; every result
// word must equal the CPU backend's. The kernel keeps denormals, so it runs only on a device that does (llvmpipe; Intel
// flushes, and an `ftz` kernel cannot hold f64). Otherwise, or without an OpenGL compute device, it says so and passes.
// `math.fma[f64]` (D5906) runs over 65,536 triples whose exponents stay within 300 of one's, where its emulation is
// exact; half the addends are the product's negation, whose answer is the product's rounding error.
use e.gpu
use e.io
use e.math
use e.mem
use e.os
use x.khronos.compute

@gpu(64)
fn arithmetic(n: u32, x: []const f64, y: []const f64, out: []f64, narrow: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    let base = k * 5usize
    out[base] = x[k] + y[k]
    out[base + 1usize] = x[k] - y[k]
    out[base + 2usize] = x[k] * y[k]
    out[base + 3usize] = x[k] / y[k]
    out[base + 4usize] = math.sqrt[f64](x[k])
    narrow[k] = f32(x[k])
}

@gpu(64)
fn fused(n: u32, a: []const f64, b: []const f64, c: []const f64, out: []f64) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    out[k] = math.fma[f64](a[k], b[k], c[k])
}

const N: usize = 65536usize

// A random double with its exponent within 300 of one's.
fn moderate(bits: u64) -> u64 {
    let exponent = 723u64 + (bits >> 52u32) % 600u64
    ret (bits & 9227875636482146303u64) | (exponent << 52u32)
}

fn fused_run(a: *mem.Arena, backend: gpu.Backend, xs: []const f64, ys: []const f64, zs: []const f64, out: []u64) -> err {
    let (device, open_error) = gpu.open(a, backend, 0u32)
    if open_error != ok { ret open_error }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (x, x_error) = gpu.upload[f64](queue, xs)
    let (y, y_error) = gpu.upload[f64](queue, ys)
    let (z, z_error) = gpu.upload[f64](queue, zs)
    let (o, o_error) = gpu.alloc[f64](queue, N)
    if x_error != ok || y_error != ok || z_error != ok || o_error != ok { os.exit(30i32) }
    try gpu.launch[fused](queue, gpu.grid1(N), u32(N), x, y, z, o)
    let (results, results_error) = mem.alloc[f64](a, N)
    if results_error != ok { os.exit(31i32) }
    if gpu.download(queue, o, results) != ok { os.exit(32i32) }
    var k = 0usize
    while k < N {
        out[k] = mem.bitcast[u64](results[k])
        k += 1usize
    }
    ret gpu.close(device)
}

fn special(k: u64) -> u64 {
    let table = k % 12u64
    if table == 0u64 { ret 0u64 }
    if table == 1u64 { ret 9223372036854775808u64 }
    if table == 2u64 { ret 9218868437227405312u64 }
    if table == 3u64 { ret 18442240474082181120u64 }
    if table == 4u64 { ret 9221120237041090560u64 }
    if table == 5u64 { ret 1u64 }
    if table == 6u64 { ret 4503599627370495u64 }
    if table == 7u64 { ret 4503599627370496u64 }
    if table == 8u64 { ret 9218868437227405311u64 }
    if table == 9u64 { ret 4607182418800017408u64 }
    if table == 10u64 { ret 4039728865751334912u64 }
    ret 5183643171103440896u64
}

fn run(a: *mem.Arena, backend: gpu.Backend, xs: []const f64, ys: []const f64, out: []u64, narrow_out: []u32) -> err {
    let (device, open_error) = gpu.open(a, backend, 0u32)
    if open_error != ok { ret open_error }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (x, x_error) = gpu.upload[f64](queue, xs)
    let (y, y_error) = gpu.upload[f64](queue, ys)
    let (o, o_error) = gpu.alloc[f64](queue, 5usize * N)
    let (w, w_error) = gpu.alloc[f32](queue, N)
    if x_error != ok || y_error != ok || o_error != ok || w_error != ok { os.exit(2i32) }
    try gpu.launch[arithmetic](queue, gpu.grid1(N), u32(N), x, y, o, w)
    let (results, results_error) = mem.alloc[f64](a, 5usize * N)
    let (narrowed, narrowed_error) = mem.alloc[f32](a, N)
    if results_error != ok || narrowed_error != ok { os.exit(3i32) }
    if gpu.download(queue, o, results) != ok || gpu.download(queue, w, narrowed) != ok { os.exit(4i32) }
    var k = 0usize
    while k < 5usize * N {
        out[k] = mem.bitcast[u64](results[k])
        k += 1usize
    }
    k = 0usize
    while k < N {
        narrow_out[k] = mem.bitcast[u32](narrowed[k])
        k += 1usize
    }
    ret gpu.close(device)
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        try io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    if found_error != ok {
        try io.printf["OpenGL device enumeration failed: {}\n"](found_error)
        os.exit(1i32)
    }
    if found.len == 0usize {
        try io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    var usable = false
    var keeps = false
    for capability in found[0usize].capabilities {
        if capability == .Float64 { usable = true }
        if capability == .DenormPreserve { keeps = true }
    }
    if !usable || !keeps {
        try io.print("no f64 device that keeps denormals; nothing checked\n")
        ret ok
    }
    let (xs, xs_error) = mem.alloc[f64](a, N)
    let (ys, ys_error) = mem.alloc[f64](a, N)
    let (cpu_out, cpu_error) = mem.alloc[u64](a, 5usize * N)
    let (gl_out, gl_error) = mem.alloc[u64](a, 5usize * N)
    let (cpu_narrow, cpu_narrow_error) = mem.alloc[u32](a, N)
    let (gl_narrow, gl_narrow_error) = mem.alloc[u32](a, N)
    if xs_error != ok || ys_error != ok || cpu_error != ok || gl_error != ok || cpu_narrow_error != ok || gl_narrow_error != ok { os.exit(5i32) }
    var state = 88172645463325252u64
    var k = 0usize
    while k < N {
        state = state ^ (state << 13u32)
        state = state ^ (state >> 7u32)
        state = state ^ (state << 17u32)
        var xb = state
        state = state ^ (state << 13u32)
        state = state ^ (state >> 7u32)
        state = state ^ (state << 17u32)
        var yb = state
        if k % 8usize == 1usize { xb = special(u64(k / 8usize)) }
        if k % 8usize == 2usize { yb = special(u64(k / 8usize)) }
        if k % 8usize == 3usize {
            xb = special(u64(k / 8usize))
            yb = special(u64(k / 96usize))
        }
        // Every fourth pair shares an exponent, so sums cancel and quotients sit near one.
        if k % 4usize == 0usize { yb = (xb & 18442240474082181120u64) | (yb & 4503599627370495u64) }
        xs[k] = mem.bitcast[f64](xb)
        ys[k] = mem.bitcast[f64](yb)
        k += 1usize
    }
    if run(a, .Cpu, xs, ys, cpu_out, cpu_narrow) != ok { os.exit(6i32) }
    if run(a, .Gl, xs, ys, gl_out, gl_narrow) != ok { os.exit(7i32) }
    k = 0usize
    while k < 5usize * N {
        if cpu_out[k] != gl_out[k] {
            try io.printf["op {} pair {}: x {} y {} cpu {} gl {}\n"](k % 5usize, k / 5usize, mem.bitcast[u64](xs[k / 5usize]), mem.bitcast[u64](ys[k / 5usize]), cpu_out[k], gl_out[k])
            os.exit(10i32 + i32(k % 5usize))
        }
        k += 1usize
    }
    k = 0usize
    while k < N {
        if cpu_narrow[k] != gl_narrow[k] {
            try io.printf["narrowing {}: x {} cpu {} gl {}\n"](k, mem.bitcast[u64](xs[k]), cpu_narrow[k], gl_narrow[k])
            os.exit(20i32)
        }
        k += 1usize
    }
    let (fa, fa_error) = mem.alloc[f64](a, N)
    let (fb, fb_error) = mem.alloc[f64](a, N)
    let (fc, fc_error) = mem.alloc[f64](a, N)
    let (cpu_fused, cpu_fused_error) = mem.alloc[u64](a, N)
    let (gl_fused, gl_fused_error) = mem.alloc[u64](a, N)
    if fa_error != ok || fb_error != ok || fc_error != ok || cpu_fused_error != ok || gl_fused_error != ok { os.exit(33i32) }
    k = 0usize
    while k < N {
        state = state ^ (state << 13u32)
        state = state ^ (state >> 7u32)
        state = state ^ (state << 17u32)
        fa[k] = mem.bitcast[f64](moderate(state))
        state = state ^ (state << 13u32)
        state = state ^ (state >> 7u32)
        state = state ^ (state << 17u32)
        fb[k] = mem.bitcast[f64](moderate(state))
        state = state ^ (state << 13u32)
        state = state ^ (state >> 7u32)
        state = state ^ (state << 17u32)
        fc[k] = mem.bitcast[f64](moderate(state))
        if k % 2usize == 1usize { fc[k] = -(fa[k] * fb[k]) }
        k += 1usize
    }
    if fused_run(a, .Cpu, fa, fb, fc, cpu_fused) != ok { os.exit(34i32) }
    if fused_run(a, .Gl, fa, fb, fc, gl_fused) != ok { os.exit(35i32) }
    k = 0usize
    while k < N {
        if cpu_fused[k] != gl_fused[k] {
            try io.printf["fma {}: a {} b {} c {} cpu {} gl {}\n"](k, mem.bitcast[u64](fa[k]), mem.bitcast[u64](fb[k]), mem.bitcast[u64](fc[k]), cpu_fused[k], gl_fused[k])
            os.exit(36i32)
        }
        k += 1usize
    }
    try io.printf["65536 f64 sums, differences, products, quotients, roots, narrowings and fused multiply-adds equal to the CPU backend's on {}\n"](found[0usize].name)
    ret ok
}
