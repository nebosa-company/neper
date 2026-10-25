use e.gpu

@gpu(8, ftz)
fn halve_ftz(x: []f32, out: []f32) {
    let i = usize(gpu.gid.x)
    out[i] = x[i] * 0.5
}

@gpu(8, ftz)
fn halve64_ftz(x: []f64, out: []f64) {
    let i = usize(gpu.gid.x)
    out[i] = x[i] * 0.5
}
