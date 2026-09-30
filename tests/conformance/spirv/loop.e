// A kernel with a loop (D1610): the SPIR-V emitter's first row writes straight-line
// kernels and `if`, and refuses a loop by name until its row lands.
use e.gpu

@gpu(64)
fn fill(n: u32, y: []u32) {
    var i = 0u32
    while i < n {
        y[usize(i)] = i
        i += 1u32
    }
}

fn main() {}
