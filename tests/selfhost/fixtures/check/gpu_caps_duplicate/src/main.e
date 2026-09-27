// Section 10 (D1589): a `caps(...)` member may not repeat.
use e.gpu

@gpu(64, caps(.Int64, .Int64))
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = gpu.gid.x
}
