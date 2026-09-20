use e.gpu

fn helper(v: []u32) {
    gpu.barrier()
    v[0] = 1u32
}
