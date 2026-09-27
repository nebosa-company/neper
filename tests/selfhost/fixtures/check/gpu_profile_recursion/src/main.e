// Section 10 (D1588): a kernel reaches recursion through a helper that calls itself.
use e.gpu

fn depth(n: u32) -> u32 {
    if n == 0u32 { ret 0u32 }
    ret depth(n - 1u32) + 1u32
}

fn helper(n: u32) -> u32 {
    ret depth(n)
}

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = helper(gpu.gid.x)
}
