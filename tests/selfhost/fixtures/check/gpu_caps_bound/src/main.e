// Section 10 (D1589): `caps(...)` is an upper bound -- a helper two calls down that
// touches an `f64` needs `.Float64`, which the kernel did not list.
use e.gpu

fn widen(x: u32) -> f64 {
    ret f64(x) * 0.5f64
}

fn scaled(x: u32) -> u32 {
    ret u32(widen(x))
}

@gpu(64, caps(.Int8))
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = scaled(gpu.gid.x)
}
