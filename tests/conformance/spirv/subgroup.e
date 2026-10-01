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
