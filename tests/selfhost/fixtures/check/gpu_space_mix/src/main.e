// Section 10 (D1590): shared memory is its own address space, so a slice of a
// `shared var` is a `[]shared u32` and no `[]const u32` takes it.
use e.gpu

fn total(xs: []const u32) -> u32 {
    ret xs[0usize]
}

@gpu(64)
fn fill(v: []u32) {
    shared var tile: [64]u32
    tile[usize(gpu.lid.x)] = gpu.gid.x
    gpu.barrier()
    v[usize(gpu.gid.x)] = total(tile[0usize..4usize])
}
