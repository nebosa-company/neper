use e.gpu

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = gpu.gid.x
}

fn run(q: *gpu.Queue, v: []u32) -> err {
    fill(v)
    ret ok
}
