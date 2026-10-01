// Subgroup identity and collectives over a full and a partial subgroup.
use e.gpu

@gpu(40, caps(.Subgroup, .Int64))
fn subgroup_collectives(identity: []u32, flags: []u32, ballots: []u64, broadcasts: []u32, shuffles: []u64) {
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    let at = usize(gpu.lid.x)
    let width = gpu.subgroup_size()
    identity[at] = width * 65536u32 + elected * 256u32 + gpu.sid
    flags[at] = 0u32
    let all = gpu.subgroup_all(gpu.sid < gpu.subgroup_size())
    if all { flags[usize(gpu.lid.x)] = 1u32 }
    let any = gpu.subgroup_any(gpu.sid + 1u32 == gpu.subgroup_size())
    if any { flags[usize(gpu.lid.x)] = flags[usize(gpu.lid.x)] | 2u32 }
    let ballot = gpu.subgroup_ballot(gpu.sid % 3u32 == 0u32)
    ballots[usize(gpu.lid.x)] = ballot
    let broadcast = gpu.subgroup_broadcast(gpu.lid.x + 100u32, 0u32)
    let shuffled = gpu.subgroup_shuffle(u64(gpu.lid.x) * 7u64, gpu.sid ^ 1u32)
    broadcasts[at] = broadcast
    shuffles[at] = shuffled
}

@gpu(40, caps(.Subgroup))
fn subgroup_scalar_exchange(signed_values: []i32, float_values: []f32, widths: []u32) {
    let at = usize(gpu.lid.x)
    let broadcast = gpu.subgroup_broadcast(i32(gpu.lid.x) - 20i32, 0u32)
    let shuffled = gpu.subgroup_shuffle(f32(gpu.lid.x) + 0.25f32, gpu.sid ^ 1u32)
    signed_values[at] = broadcast
    float_values[at] = shuffled
    widths[at] = gpu.subgroup_size()
}

@gpu(40, caps(.Subgroup, .Int64))
fn subgroup_integer_reduce(values: []u64) {
    let at = usize(gpu.lid.x) * 12usize
    let narrow = gpu.sid + 1u32
    let add32 = gpu.subgroup_add(narrow)
    let min32 = gpu.subgroup_min(narrow)
    let max32 = gpu.subgroup_max(narrow)
    let and32 = gpu.subgroup_and(narrow)
    let or32 = gpu.subgroup_or(narrow)
    let xor32 = gpu.subgroup_xor(narrow)
    let wide = u64(gpu.sid) + 4294967296u64
    let add64 = gpu.subgroup_add(wide)
    let min64 = gpu.subgroup_min(wide)
    let max64 = gpu.subgroup_max(wide)
    let and64 = gpu.subgroup_and(wide)
    let or64 = gpu.subgroup_or(wide)
    let xor64 = gpu.subgroup_xor(wide)
    values[at] = u64(add32)
    values[at + 1usize] = u64(min32)
    values[at + 2usize] = u64(max32)
    values[at + 3usize] = u64(and32)
    values[at + 4usize] = u64(or32)
    values[at + 5usize] = u64(xor32)
    values[at + 6usize] = add64
    values[at + 7usize] = min64
    values[at + 8usize] = max64
    values[at + 9usize] = and64
    values[at + 10usize] = or64
    values[at + 11usize] = xor64
}

@gpu(40, caps(.Subgroup))
fn subgroup_scalar_reduce(signed_values: []i32, float_values: []f32) {
    let signed_at = usize(gpu.lid.x) * 6usize
    let signed = i32(gpu.sid) - 16i32
    let signed_add = gpu.subgroup_add(signed)
    let signed_min = gpu.subgroup_min(signed)
    let signed_max = gpu.subgroup_max(signed)
    let signed_and = gpu.subgroup_and(signed)
    let signed_or = gpu.subgroup_or(signed)
    let signed_xor = gpu.subgroup_xor(signed)
    let float_at = usize(gpu.lid.x) * 3usize
    let floating = f32(gpu.sid) + 0.5f32
    let float_add = gpu.subgroup_add(floating)
    let float_min = gpu.subgroup_min(floating)
    let float_max = gpu.subgroup_max(floating)
    signed_values[signed_at] = signed_add
    signed_values[signed_at + 1usize] = signed_min
    signed_values[signed_at + 2usize] = signed_max
    signed_values[signed_at + 3usize] = signed_and
    signed_values[signed_at + 4usize] = signed_or
    signed_values[signed_at + 5usize] = signed_xor
    float_values[float_at] = float_add
    float_values[float_at + 1usize] = float_min
    float_values[float_at + 2usize] = float_max
}
