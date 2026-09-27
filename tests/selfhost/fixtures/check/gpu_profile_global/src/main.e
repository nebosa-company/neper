// Section 10 (D1588): a helper a kernel reaches reads a module-scope `var`.
use e.gpu

var counter: u32 = 0u32

fn bump(x: u32) -> u32 {
    ret x + counter
}

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = bump(gpu.gid.x)
}
