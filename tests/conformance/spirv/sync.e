// Workgroup memory, memory barriers and 32/64-bit device atomics (D1615).
use e.gpu

// The smaller entry comes first: the module's Workgroup block must still be sized
// from `sync` below rather than from the first kernel encountered.
@gpu(1)
fn small(output: []u32) {
    shared var one: u32
    one = gpu.gid.x
    gpu.barrier()
    if gpu.gid.x == 0u32 { output[0usize] = one }
}

@gpu(64, caps(.Int64, .Atomic64))
fn sync(words: []Atomic[u32], wide: []Atomic[u64], output: []u32) {
    shared var count: Atomic[u32]
    shared var tile: [64]u32
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
    tile[usize(lane)] = lane + 1u32
    gpu.barrier()
    let shared_before = gpu.atomic_add(&count, 1u32, .AcqRel, .Workgroup)
    let device_before = gpu.atomic_add(&words[0usize], 1u32, .AcqRel, .Device)
    let wide_before = gpu.atomic_add(&wide[0usize], 1u64, .AcqRel, .Device)
    gpu.memory_barrier(.Workgroup)
    gpu.memory_barrier(.Device)
    gpu.barrier()
    if lane == 0u32 { output[0usize] = tile[63usize] + gpu.atomic_load(&count, .Acquire, .Workgroup) }
}
