// Section 10 (D1589): a kernel within its `caps(...)`, with `ftz`.
use e.gpu

fn widen(x: u32) -> f64 {
    ret f64(x) * 0.5f64
}

@gpu(64, caps(.Float64, .Int8), ftz)
fn fill(v: []u32, bytes: []u8) {
    v[usize(gpu.gid.x)] = u32(widen(gpu.gid.x)) + u32(bytes[0usize])
}
