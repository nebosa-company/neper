// Section 4: a `Mask[T, N]` is register-only -- not an array element.
use e.simd

fn main() -> i64 {
    var rows: [2]Mask[f32, 4] = zero
    ret 0i64
}
