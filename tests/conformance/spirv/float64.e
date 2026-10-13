// `f64` in a kernel (C095): the Float64 capability, 64-bit loads and stores through a
// device address, add, subtract, multiply, negate, compare, `math.fma`, and the
// conversions to and from `f32` and `i32`.
use e.gpu
use e.math

@gpu(16, caps(.Float64))
fn mixed(x: []f64, y: []f64, out: []f64, small: []f32, whole: []i32) {
    let i = usize(gpu.gid.x)
    var t: [2]f64 = [2]f64{ 0.0, 0.0 }
    t[0usize] = x[i] * y[i]
    t[1usize] = t[0usize] + x[i]
    var v = -(t[1usize] - y[i]) + math.fma[f64](x[i], y[i], 1.0)
    if x[i] < y[i] { v = v + 1.0 }
    out[i] = v
    small[i] = f32(x[i])
    whole[i] = i32(y[i]) + i32(f64(i32(i)))
}
