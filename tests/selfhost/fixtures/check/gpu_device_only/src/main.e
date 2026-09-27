// Section 10 (D1589): `lane` reads `gpu.lid`, so it is device-only, and plain CPU code
// cannot call it; the kernel can.
use e.gpu

fn lane() -> u32 {
    ret gpu.lid.x
}

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = lane()
}

fn host() -> u32 {
    ret lane()
}
