// Subgroup collectives through the MSL emitter (C193, D5852): ids, vote, ballot, broadcast, shuffle and the integer and float
// reductions over a full and a partial subgroup (a workgroup of 40), run on the CPU backend and on a Metal device, and the two
// answers must be equal word for word. A machine with no Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.gpu

const N: usize = 40usize

@gpu(40, ftz, caps(.Subgroup, .Int64))
fn collectives(a: []u32, b: []u64, c: []f32) {
    let at = usize(gpu.lid.x)
    let width = gpu.subgroup_size()
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    a[at] = width * 65536u32 + elected * 256u32 + gpu.sid
    var flags = 0u32
    if gpu.subgroup_all(gpu.sid < gpu.subgroup_size()) { flags = 1u32 }
    if gpu.subgroup_any(gpu.sid + 1u32 == gpu.subgroup_size()) { flags = flags | 2u32 }
    a[N + at] = flags
    b[at] = gpu.subgroup_ballot(gpu.sid % 3u32 == 0u32)
    a[2usize * N + at] = gpu.subgroup_broadcast(gpu.lid.x + 100u32, 0u32)
    c[at] = gpu.subgroup_shuffle(f32(gpu.lid.x) + 0.25f32, gpu.sid ^ 1u32)
    let narrow = gpu.lid.x * 3u32 + 5u32
    a[3usize * N + at] = gpu.subgroup_add(narrow)
    a[4usize * N + at] = gpu.subgroup_min(narrow)
    a[5usize * N + at] = gpu.subgroup_max(narrow)
    a[6usize * N + at] = gpu.subgroup_and(narrow | 1u32)
    a[7usize * N + at] = gpu.subgroup_or(narrow)
    a[8usize * N + at] = gpu.subgroup_xor(narrow)
    c[N + at] = gpu.subgroup_add(f32(gpu.lid.x))
}

fn run(q: *gpu.Queue, a: []u32, b: []u64, c: []f32) -> err {
    let (da, a_error) = gpu.upload[u32](q, a)
    if a_error != ok { ret a_error }
    let (db, b_error) = gpu.upload[u64](q, b)
    if b_error != ok { ret b_error }
    let (dc, c_error) = gpu.upload[f32](q, c)
    if c_error != ok { ret c_error }
    try gpu.launch[collectives](q, gpu.grid1(40usize), da, db, dc)
    try gpu.download(q, da, a)
    try gpu.download(q, db, b)
    try gpu.download(q, dc, c)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (found, found_error) = gpu.devices(a, .Metal, 4usize)
    if found_error != ok { os.exit(0i32) }
    if found.len == 0usize { os.exit(0i32) }
    var cpu_a: [360]u32 = zero
    var cpu_b: [40]u64 = zero
    var cpu_c: [80]f32 = zero
    var gpu_a: [360]u32 = zero
    var gpu_b: [40]u64 = zero
    var gpu_c: [80]f32 = zero
    let (cpu, cpu_error) = gpu.open(a, .Cpu, 0u32)
    if cpu_error != ok { os.exit(2i32) }
    let (cq, cq_error) = gpu.queue(cpu)
    if cq_error != ok { os.exit(3i32) }
    if run(cq, cpu_a[0..], cpu_b[0..], cpu_c[0..]) != ok { os.exit(4i32) }
    let (dev, open_error) = gpu.open(a, .Metal, 0u32)
    if open_error != ok { os.exit(5i32) }
    let (q, q_error) = gpu.queue(dev)
    if q_error != ok { os.exit(6i32) }
    let ran = run(q, gpu_a[0..], gpu_b[0..], gpu_c[0..])
    if ran == gpu.Unsupported { os.exit(7i32) }
    if ran != ok { os.exit(8i32) }
    var at = 0usize
    while at < 360usize {
        if cpu_a[at] != gpu_a[at] { os.exit(20i32 + i32(at / 40usize)) }
        at += 1usize
    }
    at = 0usize
    while at < 40usize {
        if cpu_b[at] != gpu_b[at] { os.exit(40i32) }
        at += 1usize
    }
    at = 0usize
    while at < 80usize {
        if cpu_c[at] != gpu_c[at] { os.exit(41i32) }
        at += 1usize
    }
    ret ok
}
