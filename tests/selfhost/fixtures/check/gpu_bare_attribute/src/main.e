use e.gpu

@gpu
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = gpu.gid.x
}
