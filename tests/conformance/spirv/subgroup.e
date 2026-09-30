// Subgroup identity inputs: the device width, lane id and one elected lane.
use e.gpu

@gpu(40, caps(.Subgroup))
fn subgroup_identity(output: []u32) {
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    output[usize(gpu.lid.x)] = gpu.subgroup_size() * 65536u32 + elected * 256u32 + gpu.sid
}
