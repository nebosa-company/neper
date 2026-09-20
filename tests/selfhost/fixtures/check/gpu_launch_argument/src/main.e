use e.gpu

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = gpu.gid.x
}

fn run(q: *gpu.Queue, host: []u32) -> err {
    ret gpu.launch[fill](q, gpu.grid1(64usize), host)
}
