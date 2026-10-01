// Subgroup identity and collectives over a full and a partial subgroup.
use e.gpu

@gpu(40, caps(.Subgroup, .Int64))
fn subgroup_collectives(identity: []u32, flags: []u32, ballots: []u64) {
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
}
