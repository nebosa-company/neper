// Section 4: a `Mask[T, N]` is register-only -- `&m` has nothing to take.
use e.simd

fn main() -> i64 {
    var m: Mask[f32, 4] = zero
    let p = &m
    ret 0i64
}
