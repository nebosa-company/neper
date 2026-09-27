// Section 10 (D1588): a slice of an invocation's own array is a function-storage pointer.
use e.gpu

fn first(xs: []const u32) -> u32 {
    ret xs[0usize]
}

@gpu(64)
fn fill(v: []u32) {
    var local: [4]u32 = zero
    local[0usize] = gpu.gid.x
    v[usize(gpu.gid.x)] = first(local[0usize..2usize])
}
