// SPIR-V `f32` division and square root (D1613): boundary and deterministic
// pseudo-random inputs agree bit for bit with the correctly rounded CPU backend.
use e.gpu
use e.io
use e.math
use e.mem
use e.os

const COUNT: usize = 8192usize

@gpu(256)
fn exact_float(n: u32, numerators: []f32, denominators: []f32, results: []f32) {
    let thread = gpu.gid.x
    if thread >= n { ret }
    results[usize(thread) * 2usize] = numerators[usize(thread)] / denominators[usize(thread)]
    results[usize(thread) * 2usize + 1usize] = math.sqrt[f32](numerators[usize(thread)])
}

fn next(state: *u32) -> u32 {
    *state = *state *% 1664525u32 +% 1013904223u32
    ret *state
}

fn inputs(numerators: []f32, denominators: []f32) {
    var state = 3237998081u32
    var at = 0usize
    while at < numerators.len {
        numerators[at] = mem.bitcast[f32](next(&state))
        denominators[at] = mem.bitcast[f32](next(&state))
        at += 1usize
    }
    let special_n: [16]u32 = [16]u32{ 0, 2147483648, 1065353216, 3212836864, 2139095040, 4286578688, 2143289345, 1, 8388607, 8388608, 2139095039, 1073741824, 3, 8388609, 1056964608, 1199570944 }
    let special_d: [16]u32 = [16]u32{ 1065353216, 3212836864, 0, 2147483648, 2139095040, 1065353216, 2143289346, 1073741824, 1077936128, 1077936128, 1065353217, 1077936128, 1073741824, 1073741824, 2139095039, 8388608 }
    at = 0usize
    while at < special_n.len {
        numerators[at] = mem.bitcast[f32](special_n[at])
        denominators[at] = mem.bitcast[f32](special_d[at])
        at += 1usize
    }
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, numerators: []f32, denominators: []f32, answers: []f32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { os.exit(30i32) }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(31i32) }
    let (dn, dn_error) = gpu.upload[f32](q, numerators)
    if dn_error != ok { os.exit(32i32) }
    defer let _ = gpu.release(q, dn)
    let (dd, dd_error) = gpu.upload[f32](q, denominators)
    if dd_error != ok { os.exit(33i32) }
    defer let _ = gpu.release(q, dd)
    let (da, da_error) = gpu.upload[f32](q, answers)
    if da_error != ok { os.exit(34i32) }
    defer let _ = gpu.release(q, da)
    let launch_error = gpu.launch[exact_float](q, gpu.grid1(numerators.len), u32(numerators.len), dn, dd, da)
    if launch_error != ok { os.exit(35i32) }
    let download_error = gpu.download(q, da, answers)
    if download_error != ok { os.exit(36i32) }
    ret ok
}

fn digest(values: []const f32) -> u64 {
    var hash = 14695981039346656037u64
    for value in values {
        hash = (hash ^ u64(mem.bitcast[u32](value))) *% 1099511628211u64
    }
    ret hash
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (numerators, numerators_error) = mem.alloc[f32](a, COUNT)
    if numerators_error != ok { ret numerators_error }
    let (denominators, denominators_error) = mem.alloc[f32](a, COUNT)
    if denominators_error != ok { ret denominators_error }
    let (cpu, cpu_error) = mem.alloc[f32](a, COUNT * 2usize)
    if cpu_error != ok { ret cpu_error }
    inputs(numerators, denominators)
    try run(a, .Cpu, 0u32, numerators, denominators, cpu)
    if digest(cpu) != 6270548297220908228u64 { os.exit(2i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu float cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported {
            let (answer, answer_error) = mem.alloc[f32](a, COUNT * 2usize)
            if answer_error != ok { ret answer_error }
            try run(a, .Vulkan, u32(device_at), numerators, denominators, answer)
            var at = 0usize
            while at < cpu.len {
                if mem.bitcast[u32](answer[at]) != mem.bitcast[u32](cpu[at]) {
                    try io.printf["gpu float mismatch {} numerator {} denominator {} cpu {} device {}\n"](at, mem.bitcast[u32](numerators[at / 2usize]), mem.bitcast[u32](denominators[at / 2usize]), mem.bitcast[u32](cpu[at]), mem.bitcast[u32](answer[at]))
                    os.exit(i32(10usize + at % 100usize))
                }
                at += 1usize
            }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu float cpu only\n")
        ret ok
    }
    try io.printf["gpu float vulkan ok on {} devices\n"](ran)
    ret ok
}
