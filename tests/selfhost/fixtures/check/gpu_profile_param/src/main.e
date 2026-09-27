// Section 10 (D1588): `usize` has another width on the device, so no kernel takes one.
use e.gpu

@gpu(64)
fn fill(v: []u32, n: usize) {
    if usize(gpu.gid.x) < n { v[usize(gpu.gid.x)] = 1u32 }
}
