// Workgroup memory and barriers (D1615): CPU and Vulkan reduce the same two
// workgroups and agree word for word.
use e.gpu
use e.atomic
use e.io
use e.mem
use e.os

@gpu(64)
fn shared_sum(input: []const u32, output: []u32) {
    shared var tile: [64]u32
    let lane = gpu.lid.x
    tile[usize(lane)] = input[usize(gpu.gid.x)]
    gpu.barrier()
    var stride = 32u32
    while stride > 0u32 {
        if lane < stride { tile[usize(lane)] = tile[usize(lane)] + tile[usize(lane + stride)] }
        gpu.barrier()
        stride = stride / 2u32
    }
    if lane == 0u32 { output[usize(gpu.wgid.x)] = tile[0usize] }
}

@gpu(64)
fn atomic_counts(device_count: []Atomic[u32], shared_count: []u32) {
    shared var count: Atomic[u32]
    let lane = gpu.lid.x
    if lane == 0u32 {
        gpu.atomic_store(&count, 7u32, .Relaxed, .Workgroup)
        let old_xchg = gpu.atomic_xchg(&count, 9u32, .AcqRel, .Workgroup)
        let (won, old_cas) = gpu.atomic_cas(&count, 9u32, 12u32, .AcqRel, .Acquire, .Workgroup)
        let old_sub = gpu.atomic_sub(&count, 2u32, .AcqRel, .Workgroup)
        let old_and = gpu.atomic_and(&count, 14u32, .AcqRel, .Workgroup)
        let old_or = gpu.atomic_or(&count, 1u32, .AcqRel, .Workgroup)
        let old_xor = gpu.atomic_xor(&count, 3u32, .AcqRel, .Workgroup)
        let old_min = gpu.atomic_min(&count, 5u32, .AcqRel, .Workgroup)
        let old_max = gpu.atomic_max(&count, 7u32, .AcqRel, .Workgroup)
        gpu.atomic_store(&count, 0u32, .Release, .Workgroup)
    }
    gpu.barrier()
    let shared_before = gpu.atomic_add(&count, 1u32, .AcqRel, .Workgroup)
    let device_before = gpu.atomic_add(&device_count[0usize], 1u32, .AcqRel, .Device)
    gpu.memory_barrier(.Workgroup)
    gpu.memory_barrier(.Device)
    gpu.barrier()
    if lane == 0u32 { shared_count[0usize] = gpu.atomic_load(&count, .Acquire, .Workgroup) }
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, input: []u32, output: []u32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (source, source_error) = gpu.upload[u32](q, input)
    if source_error != ok { ret source_error }
    defer let _ = gpu.release(q, source)
    let (result, result_error) = gpu.upload[u32](q, output)
    if result_error != ok { ret result_error }
    defer let _ = gpu.release(q, result)
    try gpu.launch[shared_sum](q, gpu.grid1(input.len), source, result)
    ret gpu.download(q, result, output)
}

fn run_atomics(a: *mem.Arena, backend: gpu.Backend, index: u32, output: []u32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    var initial: [1]Atomic[u32] = zero
    initial[0usize] = atomic.init(0u32)
    let (count, count_error) = gpu.upload[Atomic[u32]](q, initial[0..])
    if count_error != ok { ret count_error }
    defer let _ = gpu.release(q, count)
    let (shared_result, shared_error) = gpu.upload[u32](q, output)
    if shared_error != ok { ret shared_error }
    defer let _ = gpu.release(q, shared_result)
    try gpu.launch[atomic_counts](q, gpu.grid1(64usize), count, shared_result)
    try gpu.download(q, shared_result, output)
    try gpu.download(q, count, initial[0..])
    output[1usize] = atomic.load(&initial[0usize], .Acquire)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var input: [128]u32 = zero
    var at = 0usize
    while at < input.len {
        input[at] = u32(at + 1usize)
        at += 1usize
    }
    var cpu: [2]u32 = zero
    try run(a, .Cpu, 0u32, input[0..], cpu[0..])
    var cpu_atomics: [2]u32 = zero
    try run_atomics(a, .Cpu, 0u32, cpu_atomics[0..])
    if cpu_atomics[0usize] != 64u32 || cpu_atomics[1usize] != 64u32 { os.exit(9i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu sync cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported {
            var answer: [2]u32 = zero
            try run(a, .Vulkan, u32(device_at), input[0..], answer[0..])
            if answer[0usize] != cpu[0usize] || answer[1usize] != cpu[1usize] { os.exit(10i32) }
            var atomic_answer: [2]u32 = zero
            try run_atomics(a, .Vulkan, u32(device_at), atomic_answer[0..])
            if atomic_answer[0usize] != cpu_atomics[0usize] || atomic_answer[1usize] != cpu_atomics[1usize] { os.exit(11i32) }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu sync cpu only\n")
        ret ok
    }
    try io.printf["gpu sync vulkan ok on {} devices\n"](ran)
    ret ok
}
