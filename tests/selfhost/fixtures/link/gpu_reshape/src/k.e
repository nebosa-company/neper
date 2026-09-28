use e.gpu

@gpu(4)
fn fill(buf: []u32) {
    buf[usize(gpu.wgid.x * 16u32 + gpu.lid.x)] = gpu.lid.x + 1u32
}

fn seed(buf: []u32) {
    buf[63] = 10u32
}
