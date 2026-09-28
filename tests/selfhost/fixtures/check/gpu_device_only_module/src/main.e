// Section 10 (D1589, D1677): only a module that imports `e.gpu` can name its builtins,
// so `stats.count`, whose field happens to be spelled `info.gpu.barrier_count`, is not
// device-only in a program that has kernels, and CPU code may call it.
use e.gpu
use stats

@gpu(64)
fn fill(v: []u32) {
    v[usize(gpu.gid.x)] = 1u32
}

fn host() -> u32 {
    ret stats.count()
}
