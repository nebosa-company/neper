// Section 4: a `Mask[T, N]` is register-only -- not a struct field.
use e.simd

type Lanes = struct { active: Mask[f32, 4] }

fn main() -> i64 {
    ret 0i64
}
