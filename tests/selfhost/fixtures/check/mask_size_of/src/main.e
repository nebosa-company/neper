// Section 4: a `Mask[T, N]` is register-only -- it has no size to ask for.
use e.mem
use e.simd

fn main() -> i64 {
    let width = mem.size_of[Mask[f32, 4]]()
    ret 0i64
}
