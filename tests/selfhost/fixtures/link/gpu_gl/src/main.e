// e.gpu's `.Gl` backend (L180, C215; D5888, D5889), built with `--gpu glsl`: x.khronos.compute installs the driver, the GL
// device opens, and each kernel's words equal the CPU backend's -- saxpy (f32 multiply and add, never fused), u8 and i16
// stores racing their neighbours in the same word, signed division and remainder by negative numbers, and a 2-D grid. Then a
// checked out-of-bounds index comes back as a Bounds fault with its invocation id. A host without OpenGL 4.3 and
// glBufferStorage exits 0 having printed why.

use e.gpu
use e.io
use e.mem
use e.os
use x.khronos.compute

@gpu(64)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    y[k] = a * x[k] + y[k]
}

// The same for a device that flushes f32 denormals (Intel's GL does): `ftz` lets it run, and the CPU flushes too.
@gpu(64, ftz)
fn saxpy_ftz(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    y[k] = a * x[k] + y[k]
}

@gpu(64)
fn narrow(n: u32, bytes: []u8, halves: []i16, quotients: []i32, remainders: []i32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    bytes[k] = u8((i * 37u32 + 11u32) & 255u32)
    halves[k] = i16(i32(i) * -151i32)
    let v = i32(i) - 100i32
    quotients[k] = v / -7i32
    remainders[k] = v % -7i32
}

@gpu(8, 8)
fn ids(width: u32, out: []u32) {
    let x = gpu.gid.x
    let y = gpu.gid.y
    if x >= width || y >= width { ret }
    let at = usize(y * width + x)
    out[at] = (gpu.wgid.y << 24u32) | (gpu.wgid.x << 16u32) | (gpu.lid.y << 8u32) | gpu.lid.x
}

// Helpers (C215): a scalar one, one that takes a slice, nested calls, and one that returns f32.
fn mix(x: u32, y: u32) -> u32 { ret (x *% 2654435761u32) ^ (y +% 7u32) }

fn pick(values: []const u32, k: usize) -> u32 {
    if k >= values.len { ret 0u32 }
    ret mix(values[k], u32(k))
}

fn halve(v: f32) -> f32 { ret v * 0.5f32 + 0.25f32 }

@gpu(64)
fn helped(n: u32, values: []const u32, out: []u32, floats: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    out[k] = pick(values, k) +% mix(i, 3u32)
    floats[k] = halve(f32(i))
}

@gpu(64, ftz)
fn helped_ftz(n: u32, values: []const u32, out: []u32, floats: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    out[k] = pick(values, k) +% mix(i, 3u32)
    floats[k] = halve(f32(i))
}

// 64-bit integers (GL_ARB_gpu_shader_int64): a wrapping multiply, shifts, division by a constant, signed division by a negative.
@gpu(64)
fn wide(n: u32, us: []u64, ss: []i64) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    let h = u64(i) *% 11400714819323198485u64
    us[2usize * k] = (h >> 7u64) ^ (u64(i) << 40u64)
    us[2usize * k + 1usize] = h / 1000003u64
    let v = i64(i) * -123456789012i64
    ss[2usize * k] = v / -97i64
    ss[2usize * k + 1usize] = v % -97i64
}

@gpu(64)
fn overrun(out: []u32) {
    let i = gpu.gid.x
    out[usize(i)] = i
}

const N: usize = 200usize

// Every kernel on `backend`; the results land in `out`. `flushing` picks the `ftz` saxpy.
fn run(a: *mem.Arena, backend: gpu.Backend, out: []u32, flushing: bool, wide_check: bool) -> err {
    let (device, open_error) = gpu.open(a, backend, 0u32)
    if open_error != ok { ret open_error }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    var xs: [200]f32 = zero
    var ys: [200]f32 = zero
    var k = 0usize
    while k < N {
        xs[k] = f32(k) * 0.37f32 + 0.1f32
        ys[k] = 1.0f32 / (f32(k) + 3.0f32)
        k += 1usize
    }
    let (x, x_error) = gpu.upload[f32](q, xs[0usize..N])
    let (y, y_error) = gpu.upload[f32](q, ys[0usize..N])
    let (bytes, bytes_error) = gpu.alloc[u8](q, N)
    let (halves, halves_error) = gpu.alloc[i16](q, N)
    let (quotients, quotients_error) = gpu.alloc[i32](q, N)
    let (remainders, remainders_error) = gpu.alloc[i32](q, N)
    let (tile, tile_error) = gpu.alloc[u32](q, 256usize)
    if x_error != ok || y_error != ok || bytes_error != ok || halves_error != ok || quotients_error != ok || remainders_error != ok || tile_error != ok { os.exit(2i32) }
    var saxpy_error = ok
    if flushing { saxpy_error = gpu.launch[saxpy_ftz](q, gpu.grid1(N), u32(N), 2.5f32, x, y) } else { saxpy_error = gpu.launch[saxpy](q, gpu.grid1(N), u32(N), 2.5f32, x, y) }
    if saxpy_error != ok { ret saxpy_error }
    let narrow_error = gpu.launch[narrow](q, gpu.grid1(N), u32(N), bytes, halves, quotients, remainders)
    if narrow_error != ok { ret narrow_error }
    let ids_error = gpu.launch[ids](q, gpu.grid2(16usize, 16usize), 16u32, tile)
    if ids_error != ok { ret ids_error }
    var seeds: [200]u32 = zero
    k = 0usize
    while k < N {
        seeds[k] = u32(k) * 7919u32 + 13u32
        k += 1usize
    }
    let (seeded, seeded_error) = gpu.upload[u32](q, seeds[0usize..N])
    let (mixed, mixed_error) = gpu.alloc[u32](q, N)
    let (halves_f, halves_f_error) = gpu.alloc[f32](q, N)
    if seeded_error != ok || mixed_error != ok || halves_f_error != ok { os.exit(20i32) }
    var helped_error = ok
    if flushing { helped_error = gpu.launch[helped_ftz](q, gpu.grid1(N), u32(N), seeded, mixed, halves_f) } else { helped_error = gpu.launch[helped](q, gpu.grid1(N), u32(N), seeded, mixed, halves_f) }
    if helped_error != ok { ret helped_error }
    var got_mixed: [200]u32 = zero
    var got_halves_f: [200]f32 = zero
    if gpu.download(q, mixed, got_mixed[0usize..N]) != ok || gpu.download(q, halves_f, got_halves_f[0usize..N]) != ok { os.exit(21i32) }
    k = 0usize
    while k < N {
        out[5usize * N + 256usize + k] = got_mixed[k]
        out[6usize * N + 256usize + k] = *mem.cast[*u32](&got_halves_f[k])
        k += 1usize
    }
    // 64-bit words land after the helpers' results, as four u32 per pair; a device without Int64 leaves them zero on both sides.
    if gpu.has(device, .Int64) && wide_check {
        let (us, us_error) = gpu.alloc[u64](q, 2usize * N)
        let (ss, ss_error) = gpu.alloc[i64](q, 2usize * N)
        if us_error != ok || ss_error != ok { os.exit(22i32) }
        let wide_error = gpu.launch[wide](q, gpu.grid1(N), u32(N), us, ss)
        if wide_error != ok { ret wide_error }
        var got_us: [400]u64 = zero
        var got_ss: [400]i64 = zero
        if gpu.download(q, us, got_us[0usize..2usize * N]) != ok || gpu.download(q, ss, got_ss[0usize..2usize * N]) != ok { os.exit(23i32) }
        k = 0usize
        while k < 2usize * N {
            out[7usize * N + 256usize + 2usize * k] = u32(got_us[k] & 4294967295u64)
            out[7usize * N + 256usize + 2usize * k + 1usize] = u32(got_us[k] >> 32u64)
            let bits = *mem.cast[*u64](&got_ss[k])
            out[11usize * N + 256usize + 2usize * k] = u32(bits & 4294967295u64)
            out[11usize * N + 256usize + 2usize * k + 1usize] = u32(bits >> 32u64)
            k += 1usize
        }
    }
    var got_y: [200]f32 = zero
    var got_bytes: [200]u8 = zero
    var got_halves: [200]i16 = zero
    var got_quotients: [200]i32 = zero
    var got_remainders: [200]i32 = zero
    var got_tile: [256]u32 = zero
    if gpu.download(q, y, got_y[0usize..N]) != ok || gpu.download(q, bytes, got_bytes[0usize..N]) != ok || gpu.download(q, halves, got_halves[0usize..N]) != ok { os.exit(3i32) }
    if gpu.download(q, quotients, got_quotients[0usize..N]) != ok || gpu.download(q, remainders, got_remainders[0usize..N]) != ok || gpu.download(q, tile, got_tile[0usize..256usize]) != ok { os.exit(4i32) }
    k = 0usize
    while k < N {
        out[k] = *mem.cast[*u32](&got_y[k])
        out[N + k] = u32(got_bytes[k])
        out[2usize * N + k] = u32(*mem.cast[*u16](&got_halves[k]))
        out[3usize * N + k] = *mem.cast[*u32](&got_quotients[k])
        out[4usize * N + k] = *mem.cast[*u32](&got_remainders[k])
        k += 1usize
    }
    k = 0usize
    while k < 256usize {
        out[5usize * N + k] = got_tile[k]
        k += 1usize
    }
    // A checked index past the end: a Bounds fault with the first faulting invocation's id.
    let (short, short_error) = gpu.alloc[u32](q, 10usize)
    if short_error != ok { os.exit(5i32) }
    let overrun_error = gpu.launch[overrun](q, gpu.grid1(64usize), short)
    if overrun_error != ok { ret overrun_error }
    if gpu.sync(q) != gpu.Fault { os.exit(6i32) }
    let (record, faulted) = gpu.last_fault(q)
    if !faulted || record.kind != .Bounds || record.gid.x < 10u32 { os.exit(7i32) }
    ret gpu.close(device)
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (cpu_out, cpu_error) = mem.alloc[u32](a, 15usize * N + 256usize)
    let (gl_out, gl_error) = mem.alloc[u32](a, 15usize * N + 256usize)
    if cpu_error != ok || gl_error != ok { os.exit(8i32) }
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    if found_error != ok {
        try io.printf["OpenGL device enumeration failed: {}\n"](found_error)
        os.exit(1i32)
    }
    if found.len == 0usize {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    var flushing = true
    var wide_check = false
    for capability in found[0usize].capabilities {
        if capability == .DenormPreserve { flushing = false }
        if capability == .Int64 { wide_check = true }
    }
    if run(a, .Cpu, cpu_out, flushing, wide_check) != ok { os.exit(9i32) }
    let gl_run = run(a, .Gl, gl_out, flushing, wide_check)
    if gl_run == gpu.NoDevice || gl_run == gpu.Unsupported {
        let printed = io.print("the OpenGL device refused these kernels; nothing checked\n")
        os.exit(10i32)
    }
    if gl_run != ok { os.exit(11i32) }
    var k = 0usize
    while k < cpu_out.len {
        if cpu_out[k] != gl_out[k] { os.exit(12i32 + i32(k / N)) }
        k += 1usize
    }
    if flushing { let mode = io.print("(ftz) ") }
    if wide_check { let wide_mode = io.print("(int64) ") }
    let named = io.print("every word equal to the CPU backend's on ")
    let device_name = io.print(found[0usize].name)
    let ended = io.print("\n")
    var cleared = 0usize
    while cleared < cpu_out.len {
        cpu_out[cleared] = 0u32
        gl_out[cleared] = 0u32
        cleared += 1usize
    }
    ret check_es(a, cpu_out, gl_out)
}

// The same kernels through OpenGL ES 3.2, or 3.1 with GL_EXT_gpu_shader5 (C218, D5904): Mesa's GLES on Linux, ANGLE on
// Windows where it reaches either.
fn check_es(a: *mem.Arena, cpu_out: []u32, es_out: []u32) -> err {
    compute.install_es()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        let printed = io.print("no OpenGL ES 3.1 compute device with precise; ES not checked\n")
        ret ok
    }
    if found_error != ok {
        try io.printf["OpenGL ES device enumeration failed: {}\n"](found_error)
        os.exit(29i32)
    }
    if found.len == 0usize {
        let printed = io.print("no OpenGL ES 3.1 compute device with precise; ES not checked\n")
        ret ok
    }
    var flushing = true
    for capability in found[0usize].capabilities {
        if capability == .DenormPreserve { flushing = false }
    }
    if run(a, .Cpu, cpu_out, flushing, false) != ok { os.exit(30i32) }
    if run(a, .Gl, es_out, flushing, false) != ok { os.exit(31i32) }
    var k = 0usize
    while k < cpu_out.len {
        if cpu_out[k] != es_out[k] { os.exit(32i32 + i32(k / N)) }
        k += 1usize
    }
    if flushing { let mode = io.print("(ftz) ") }
    let named = io.print("every word equal to the CPU backend's on OpenGL ES: ")
    let device_name = io.print(found[0usize].name)
    let ended = io.print("\n")
    ret ok
}
