use e.gpu

@gpu(4)
fn fill(v: []u32) {
    shared var tile: [4]u32 = zero
    tile[usize(gpu.lid.x)] = v[0]
}
