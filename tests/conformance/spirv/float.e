// Correctly rounded `f32` division and square root (D1613). Native Vulkan
// operations seed two FMA residual corrections; the runtime fixture supplies the
// finite boundaries, subnormals, infinities, signed zeros and NaNs.
use e.gpu
use e.math

@gpu(64)
fn exact(n: u32, numerators: []f32, denominators: []f32, answers: []f32) {
    let id = gpu.gid.x
    if id >= n { ret }
    answers[usize(id) * 2usize] = numerators[usize(id)] / denominators[usize(id)]
    answers[usize(id) * 2usize + 1usize] = math.sqrt[f32](numerators[usize(id)])
}

fn main() {}
